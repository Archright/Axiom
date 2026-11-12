## Certificate Hydration — Content-Addressed Proof Hydration (Phase 1)
##
## Scans certificate directories and determines which certificates are
## eligible for content-addressed hydration. The hydration check ensures:
##   1. Certificate status is certGreen or certVerifiedAxiom
##   2. A winning strategy is recorded
##   3. Lean compiler verification passed
##   4. Source hash matches the current source code fingerprint
##   5. Transitive fingerprint matches the current dependency closure
##
## Dependency logic (transitive deps, loop driving) lives in loop_driver;
## this module provides the per-node hydration decision only.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/json except parseJson
import std/os
import std/options
import std/tables
import std/algorithm
import std/strutils
import core/json/json_utils
import core/proof/source_fingerprint
import core/sorter/sorter_core
import core/orchestrator/orchestrator_request_types
import core/results
import core/utils/io_utils
# axiomIoBoundary
import core/axiom_pragmas

type
  CertificateHydrationRecord* = object
    ## Value type holding the minimal fields needed for hydration decisions.
    modulePath*: string
    functionName*: string
    sourceHash*: string
    transitiveFingerprint*: string
    fingerprint*: string
    status*: string
    winningStrategy*: string
    leanCompilerVerified*: bool
    certificatePath*: string
    trustCommitId*: string

proc scanCertificateDir*(certDir: string): Table[string, CertificateHydrationRecord] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Scan ``certDir/*.json`` exactly once and build a table keyed by
  ## canonical node ID (``modulePath & "::" & functionName``).
  ## Best-effort: files that fail to parse are silently skipped.
  result = initTable[string, CertificateHydrationRecord]()
  let pattern = joinPath(certDir, "*.json")
  # First pass: count files for pre-sizing the table
  var fileCount = 0
  try:
    for path in walkPattern(pattern):
      inc fileCount
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  if fileCount > 0:
    result = initTable[string, CertificateHydrationRecord](fileCount)
  # Second pass: parse and populate
  try:
    for path in walkPattern(pattern):
      let nodeOpt = readJsonFile(path)
      if nodeOpt.isNone: continue
      let node = nodeOpt.get()
      if node.kind != JObject: continue
      let modulePath = node.getOrDefault("modulePath").getStr("")
      let functionName = node.getOrDefault("functionName").getStr("")
      if modulePath.len == 0 or functionName.len == 0: continue
      let solverMeta = node.getOrDefault("solverMeta")
      let leanVerified = if not solverMeta.isNil and solverMeta.kind == JObject:
        solverMeta.getOrDefault("leanCompilerVerified").getBool(false)
      else:
        false
      let nodeId = modulePath & "::" & functionName
      result[nodeId] = CertificateHydrationRecord(
        modulePath: modulePath,
        functionName: functionName,
        sourceHash: node.getOrDefault("sourceHash").getStr(""),
        transitiveFingerprint: node.getOrDefault("transitiveFingerprint").getStr(""),
        fingerprint: node.getOrDefault("fingerprint").getStr(""),
        status: node.getOrDefault("status").getStr(""),
        winningStrategy: node.getOrDefault("winningStrategy").getStr(""),
        leanCompilerVerified: leanVerified,
        certificatePath: path,
        trustCommitId: node.getOrDefault("trustCommitId").getStr("")
      )
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

func findNodeByIdString*(state: SorterState; nodeIdStr: string): Option[SorterNode] {.raises: [].} =
  for node in state.nodes:
    if sorterNodeIdString(node.id) == nodeIdStr:
      return some(node)
  none(SorterNode)

proc collectTransitiveSourceHashes(
  state: SorterState;
  nodeIdStr: string;
  sourceCache: var Table[string, string];
  memo: var Table[string, string]
): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute a stable transitive source fingerprint for ``nodeIdStr`` by
  ## combining its own source hash with the sorted source hashes of all
  ## transitive dependencies. Iterative post-order traversal eliminates
  ## stack overflow on deep dependency chains.
  if memo.hasKey(nodeIdStr):
    return memo.getOrDefault(nodeIdStr, "")

  type
    FrameKind = enum fkUnvisited, fkVisited
    StackFrame = object
      nodeId: string
      kind: FrameKind

  var stack: seq[StackFrame] = @[StackFrame(nodeId: nodeIdStr, kind: fkUnvisited)]
  var onStack: Table[string, bool]  # cycle guard

  while stack.len > 0:
    let frame = stack.pop()

    if frame.kind == fkVisited:
      # All dependencies processed — compute result for this node
      var hashes: seq[string] = @[]

      # Single lookup for this node
      let nodeOpt = findNodeByIdString(state, frame.nodeId)

      # Compute own source hash (populate sourceCache)
      var ownHash = ""
      if sourceCache.hasKey(frame.nodeId):
        ownHash = sourceCache.getOrDefault(frame.nodeId, "")
      elif nodeOpt.isSome:
        let srcRes = readFileOpt(nodeOpt.get().modulePath)
        if srcRes.isOk:
          ownHash = computeStableSourceFingerprint(srcRes.get())
        sourceCache[frame.nodeId] = ownHash
      hashes.add(ownHash)

      # Collect dependency hashes already written to memo
      if nodeOpt.isSome:
        for dep in nodeOpt.get().dependencyIds:
          let depStr = sorterNodeIdString(dep)
          if memo.hasKey(depStr):
            hashes.add(memo.getOrDefault(depStr, ""))

      sort(hashes)
      let combined = hashes.join("|")
      memo[frame.nodeId] = computeStableSourceFingerprint(combined)
    else:
      # First visit — check memo, then push VISITED marker + dependencies
      if memo.hasKey(frame.nodeId):
        continue

      # Mark as in-progress (cycle guard: prevents re-pushing)
      onStack[frame.nodeId] = true
      stack.add(StackFrame(nodeId: frame.nodeId, kind: fkVisited))
      let nodeOpt = findNodeByIdString(state, frame.nodeId)
      if nodeOpt.isSome:
        for dep in nodeOpt.get().dependencyIds:
          let depStr = sorterNodeIdString(dep)
          if not memo.hasKey(depStr) and not onStack.hasKey(depStr):
            stack.add(StackFrame(nodeId: depStr, kind: fkUnvisited))

  memo.getOrDefault(nodeIdStr, "")

proc computeNodeTransitiveFingerprint*(
  state: SorterState;
  nodeIdStr: string;
  requests: seq[OrchestrationProofRequest]
): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute the transitive source fingerprint for a node, seeding the
  ## source cache with the source code from the request table.
  var sourceCache = initTable[string, string]()
  for r in requests:
    sourceCache[sorterNodeIdString(r.nodeId)] = computeStableSourceFingerprint(r.sourceCode)
  var memo = initTable[string, string]()
  collectTransitiveSourceHashes(state, nodeIdStr, sourceCache, memo)

func isCertificateHydratable*(
  cert: CertificateHydrationRecord;
  request: OrchestrationProofRequest;
  currentTransitiveFingerprint: string = ""
): bool {.raises: [].} =
  ## A certificate is hydratable only if ALL conditions hold:
  ##   1. Status is ``certGreen`` or ``certVerifiedAxiom``
  ##   2. Winning strategy is non-empty
  ##   3. Lean compiler verified
  ##   4. Transitive fingerprint (if present in cert and supplied by caller)
  ##      matches the current dependency closure
  ##   5. Source hash (legacy) matches the request source fingerprint
  if cert.status != "certGreen" and cert.status != "certVerifiedAxiom":
    return false
  if cert.winningStrategy.len == 0:
    return false
  if not cert.leanCompilerVerified:
    return false
  # P0 invariant (statusConsistentWithEvidence) is enforced at the
  # shared helper / certificate_verifier read-path level; this typed-record
  # path already requires leanCompilerVerified explicitly for certGreen.

  if cert.transitiveFingerprint.len > 0 and currentTransitiveFingerprint.len > 0:
    if cert.transitiveFingerprint != currentTransitiveFingerprint:
      return false
  elif cert.sourceHash.len > 0:
    let currentFingerprint = computeStableSourceFingerprint(request.sourceCode)
    if cert.sourceHash != currentFingerprint:
      return false
  else:
    # Neither transitive nor source hash available: not hydratable.
    return false

  true

func findHydratableCertificate*(
  certs: Table[string, CertificateHydrationRecord];
  nodeIdStr: string;
  request: OrchestrationProofRequest;
  currentTransitiveFingerprint: string = ""
): Option[CertificateHydrationRecord] {.raises: [].} =
  ## Look up ``nodeIdStr`` in the certificate table. Return ``some(cert)``
  ## if the certificate is hydratable, ``none`` otherwise.
  if not certs.hasKey(nodeIdStr):
    return none(CertificateHydrationRecord)
  let cert = certs.getOrDefault(nodeIdStr, CertificateHydrationRecord())
  if isCertificateHydratable(cert, request, currentTransitiveFingerprint):
    some(cert)
  else:
    none(CertificateHydrationRecord)

func allDependenciesInVerifiedSet*(
  dependencyIds: seq[SorterNodeId];
  verifiedSet: Table[string, bool]
): bool {.raises: [].} =
  ## Dependency gate: return true only if every ID in ``dependencyIds``
  ## is present as a key in ``verifiedSet``.  An empty dependency list
  ## trivially passes (leaf nodes are always eligible).
  for depId in dependencyIds:
    if not verifiedSet.hasKey(sorterNodeIdString(depId)):
      return false
  true

proc computeTransitiveFingerprintWithCaches*(
  state: SorterState;
  nodeIdStr: string;
  sourceCache, memo: var Table[string, string];
 engineSalt: string = ""
): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute a transitive source fingerprint reusing caller-owned caches.
  ## The caller should seed ``sourceCache`` with known source codes (e.g.
  ## from ``OrchestrationProofRequest``) before calling this for a batch.
  ## engineSalt: when non-empty, appended to the result for cache isolation.
  let base = collectTransitiveSourceHashes(state, nodeIdStr, sourceCache, memo)
  if engineSalt.len > 0:
    base & "||SALT:" & engineSalt
  else:
    base

{.pop.}
