import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/os
import std/sets
import std/strutils
import std/options
import std/tables
import std/json
import core/json/std_redirect

import core/symbolic/global_symbol_graph_types
import core/types/universe_types
import core/proof/proof_universe_lock
import core/results
import core/reasoning_recorder
import verification/integrity_ledger
import core/provenance_guard
import core/json/json_utils
import core/telemetry/metrics
import core/utils/io_utils
import core/utils/constants
import core/io/file_utils
import core/trusted/axiom_pragmas
import core/trusted/trust_commit
import core/trusted/scope_identity
import core/orchestrator/orchestrator_report_types
# axiomIoBoundary

proc writeGlobalSymbolGraphSnapshot*(
  repoRoot: string;
  graph: GlobalSymbolGraph
): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # WP2-a: snapshot writes route to stateRoot when set (subject immutability).
  let graphPath = block:
    let sr = getEnv("AXIOM_STATE_DIR", "").strip()
    if sr.len > 0: joinPath(sr, defaultGlobalSymbolGraphPath)
    else: repoRoot / defaultGlobalSymbolGraphPath
  try:
    let dir = parentDir(graphPath)
    if dir.len > 0 and not dirExists(dir):
      discard existsOrCreateDirOpt(dir)
    discard writeFileSafe(graphPath, pretty(graphSnapshotJson(graph), 2) & "\n")  # axiom:best-effort(write outcome verified via fileExists(graphPath) return check below)
    fileExists(graphPath)
  except CatchableError:
    false

proc purgeStaleEvidenceFiles*(evidenceDir: string; certDir: string) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    if not dirExists(evidenceDir) or not dirExists(certDir):
      return
    var validNodeIds = initHashSet[string]()
    for kind, path in walkDir(certDir):
      if kind != pcFile or not path.endsWith(".json"):
        continue
      let nodeOpt = readJsonFile(path)
      if nodeOpt.isNone:
        continue
      let node = nodeOpt.get()
      if node.kind != JObject:
        continue
      let mp = node.getOrDefault("modulePath").getStr("")
      let fn = node.getOrDefault("functionName").getStr("")
      if mp.len > 0 and fn.len > 0:
        validNodeIds.incl(mp & "::" & fn)
    for kind, path in walkDir(evidenceDir):
      if kind != pcFile:
        continue
      let filename = extractFilename(path)
      var nodeId = filename
      if filename.endsWith(".z3out"):
        nodeId = filename[0 ..< (filename.len - 6)]
      elif filename.find("_leanstral_") >= 0:
        let idx = filename.find("_leanstral_")
        nodeId = filename[0 ..< idx]
      if nodeId notin validNodeIds:
        discard removeFileOpt(path)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc rebuildUniverseMerkleLockFile*(
  repoRoot: string = getCurrentDir();
  vkdFixed4: ValidatedAsi;
  updateLock: bool = false
): Result[void, string] {.raises: [], axiomDecision(id = "DECISION-0013",
    reason = "Merkle lock computed+validated on every run but only persisted on canonical runs (ax vkd sync / --update-lock); updateLock=false skips the atomic write",
    adr = "docs/adr/0012-ax-vkd-sync.md",
    introduced = "v32"), axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let lockOpt = computeProofUniverseLock(repoRoot, proof_universe_lock.defaultCertDir, vkdFixed4, source = asiComputed)
  if lockOpt.isErr():
    return err("[AXIOM DEFECT] proof_universe.lock compute failed: " & lockOpt.error)
  let lock = lockOpt.get
  let lockPath = block:
    let sr = getEnv("AXIOM_STATE_DIR", "").strip()
    if sr.len > 0: joinPath(sr, defaultProofUniverseLockPath)
    else: repoRoot / defaultProofUniverseLockPath
  let lockJson = %*{
    "merkleRoot": lock.merkleRoot,
    "timestamp": lock.timestamp,
    "fileCount": lock.fileCount,
    vkdFixed4Key: lock.vkdFixed4
  }
  let lockContent = pretty(lockJson) & "\n"
  # The proof universe merkle lock is computed/validated on every run, but only
  # canonical runs (`ax vkd sync` / `--update-lock`) persist it to disk. All
  # other integrity side effects remain unconditional (see
  # commitUniverseIntegrityAndLock). Skip the atomic write when updateLock=false.
  if updateLock:
    let dir = parentDir(lockPath)
    if dir.len > 0 and not dirExists(dir):
      let dirRes = existsOrCreateDirOpt(dir)
      if dirRes.isErr():
        return err("[AXIOM DEFECT] proof_universe.lock: cannot create directory: " & dirRes.error)
    let writeRes = writeFileAtomic(lockPath, lockContent)
    if writeRes.isErr():
      return err("[AXIOM DEFECT] proof_universe.lock: write failed: " & writeRes.error)
  result = Result[void, string](ok: true)

# ─────────────────────────────────────────────────────────────────────────────
# WP3-b Change 3 — tcVerifiedProof positive gate.
#
# Structurally forbid `tcVerifiedProof` from being committed for outcomes that
# are NOT kernel-tier verified proof. A trust journal entry must never claim
# stronger semantics than the upstream verification result supports.
#
# Gate design (positive gate only — NO `!= Vacuous` negative gate):
#   A kernel-tier VerifiedProof entry is written ONLY when a node report:
#     (a) is orchestrationVerified AND its assuranceTier signals real kernel
#         acceptance ("lean-verified" | "dual-verified"). `orchestrationVerified`
#         alone is insufficient — it is also granted for Z3-only UNSAT
#         (src/verification/batch_uap/stages.nim:466-469).
#     (b) is claim-associated: the node's module identity exists in the current
#         graph snapshot universe (modulePath::functionName association).
#     (c) belongs to the current run (the nodeReports are the current run's
#         proof reports — never global/cached state).
#   If the resulting set is empty, the TrustCommit block is skipped entirely
#   (return ok — not an error).
#
# The `verifiedNodes` claim payload is built from a SET input via
# `buildVerifiedTrustCommit`; the canonical projectors enforce subject-relative
# module identity (D3), byte-lex sorting, fixed key order, and forbid
# timestamp/float nondeterminism.
# ─────────────────────────────────────────────────────────────────────────────

type
  VerifiedCommitNode* = object
    nodeId*: string              ## canonical modulePath::functionName (subject-relative, D3)
    modulePath*: string          ## subject-relative module path
    functionName*: string
    assuranceTier*: string       ## "lean-verified" | "dual-verified"

## Helper 1a — kernel-tier predicate. `orchestrationVerified` alone is not
## enough: it is also granted for Z3-only UNSAT. Real kernel acceptance requires
## the assurance tier to signal Lean acceptance.
func isKernelVerifiedEvidence*(node: OrchestrationNodeReport): bool =
  node.status == orchestrationVerified and
    (node.assuranceTier == "lean-verified" or node.assuranceTier == "dual-verified")

## Helper 1b — claim association. Returns the canonical (modulePath, functionName)
## when the node's module identity exists in the current graph snapshot universe.
## The nodeId format is `modulePath::functionName` (canonical across the repo, cf.
## state_persistence.nim:66, universal_pipeline.nim:78). The module is considered
## present when at least one indexed symbol in the graph carries the same
## subject-relative modulePath.
func claimAssociatedNodeId*(
  node: OrchestrationNodeReport;
  graph: GlobalSymbolGraph
): (string, string) =
  let raw = string(node.nodeId)
  let sep = raw.find("::")
  if sep <= 0:
    return ("", "")
  let modulePath = raw[0 ..< sep]
  let functionName = raw[(sep + 2) .. ^1]
  if modulePath.len == 0 or functionName.len == 0:
    return ("", "")
  # The module must exist in the current graph universe.
  for s in graph.symbols.values:
    if s.modulePath == modulePath:
      return (modulePath, functionName)
  ("", "")

## Helper 1 — select kernel-tier, claim-associated nodes from the CURRENT run.
func verifiedCommitEvidence*(
  nodeReports: seq[OrchestrationNodeReport];
  graph: GlobalSymbolGraph
): seq[VerifiedCommitNode] =
  result = @[]
  for node in nodeReports:
    if not isKernelVerifiedEvidence(node):
      continue
    let (mp, fn) = claimAssociatedNodeId(node, graph)
    if mp.len == 0 or fn.len == 0:
      continue
    result.add(VerifiedCommitNode(
      nodeId: mp & "::" & fn,
      modulePath: mp,
      functionName: fn,
      assuranceTier: node.assuranceTier
    ))

## Helper 2 — canonical projection: dedupe, byte-lex sort deterministically.
## No timestamp/float fields; fixed key order (finalizeSourceFingerprint contract,
## run_context.nim:56-67). A SET is produced so the downstream constructor cannot
## admit a strict subset accidentally.
func verifyingNodeCmp*(a, b: VerifiedCommitNode): int =
  cmp(a.nodeId, b.nodeId)

func canonicalVerifiedNodes*(ev: seq[VerifiedCommitNode]): seq[VerifiedCommitNode] =
  var seen = initHashSet[string]()
  result = @[]
  # Insert in byte-lex order (no `sort` dependency — avoids calling-convention
  # ambiguity between system.sort / std.algorithm). Inputs are tiny.
  for n in ev:
    if n.nodeId in seen:
      continue
    seen.incl(n.nodeId)
    var pos = 0
    while pos < result.len and verifyingNodeCmp(result[pos], n) <= 0:
      inc pos
    result.insert(n, pos)

## Helper 3 — build the canonical verifiedNode claim payload. Takes a SET
## (seq treated as set) so `{A,B}` cannot structurally yield a `{A}` claim.
func buildVerifiedCommitPayload(verified: seq[VerifiedCommitNode]): JsonNode =
  var arr = newJArray()
  for n in verified:
    arr.add(%*{
      "nodeId": n.nodeId,
      "modulePath": n.modulePath,
      "functionName": n.functionName,
      "assuranceTier": n.assuranceTier
    })
  arr

proc commitUniverseIntegrityAndLock*(
  currentDir: string;
  currentGraph: GlobalSymbolGraph;
  vkdFixed4: ValidatedAsi;
  caller: string = "unknown";
  updateLock: bool = true;
  graphReused: bool = false;
  nodeReports: seq[OrchestrationNodeReport] = @[]
): Result[void, string] {.raises: [], axiomDecision(id = "DECISION-0014",
    reason = "Canonical lock authority: authorizes lock persistence AND enforces the caller whitelist; all non-lock integrity side effects remain unconditional per run",
    adr = "docs/adr/0012-ax-vkd-sync.md",
    introduced = "v32"), axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if caller != AuthorizedLockCaller:
    return err("[CONSTITUTIONAL VIOLATION] proof_universe.lock update rejected: " &
      "unauthorized caller '" & caller & "'. " &
      "Only '" & AuthorizedLockCaller & "' may commit the universe lock.")
  if currentGraph.symbols.len == 0:
    # WP2-a: stateRoot routing (subject immutability).
    let cachePath = block:
      let sr = getEnv("AXIOM_STATE_DIR", "").strip()
      if sr.len > 0: joinPath(sr, defaultGlobalSymbolGraphPath)
      else: currentDir / defaultGlobalSymbolGraphPath
    if fileExists(cachePath):
      try:
        discard removeFileOpt(cachePath)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    return err("[AXIOM DEFECT] proof_universe.lock: global symbol graph is empty. Cache cleared. Please re-run 'ax prove'.")
  # WP2-a: stateRoot routing.
  let graphPath = block:
    let sr = getEnv("AXIOM_STATE_DIR", "").strip()
    if sr.len > 0: joinPath(sr, defaultGlobalSymbolGraphPath)
    else: currentDir / defaultGlobalSymbolGraphPath
  # P0 reuse boundary: when the caller reused the graph from a validated snapshot
  # (GraphInputFingerprint == same, I1/I2) AND we are not committing the canonical
  # lock, the on-disk snapshot + merkle + lock are already current and
  # deterministically unchanged, so the redundant re-materialization
  # (snapshot write + graph merkle hash + lock validation) can be skipped.
  # NEVER skipped for updateLock=true (canonical lock authority), and NEVER when
  # the canonical snapshot file is missing (fail-closed rebuild). The I3
  # audit/provenance/evidence side effects below remain unconditional regardless.
  let canSkipRematerialization =
    graphReused and not updateLock and fileExists(graphPath)
  if not canSkipRematerialization:
    let graphOk = writeGlobalSymbolGraphSnapshot(currentDir, currentGraph)
    if not graphOk:
      return err("[AXIOM DEFECT] proof_universe.lock: failed to write global symbol graph snapshot")
    block:
      let h = computeGraphMerkleHash(graphPath)
      if h.isErr:
        return err("[AXIOM DEFECT] proof_universe.lock: global symbol graph Merkle hash rejected")
  # --- I3 unconditional side effects (never skipped when materialization is reused) ---
  for ev in drainThreadReasoningTrail():
    appendToReasoningTrail(ev{"nodeId"}.getStr(""), ev)
  for ev in drainThreadProvenanceLog():
    appendToProvenanceLog(ev{"nodeId"}.getStr(""), ev)
  let certDirPath = block:
    let sr = getEnv("AXIOM_STATE_DIR", "").strip()
    if sr.len > 0: joinPath(sr, proof_universe_lock.defaultCertDir)
    else: currentDir / proof_universe_lock.defaultCertDir
  flushGlobalAuditBufferToCertificates(certDirPath)
  if not canSkipRematerialization:
    block:
      let lr = rebuildUniverseMerkleLockFile(currentDir, vkdFixed4, updateLock = updateLock)
      if lr.isErr:
        return err(lr.error)
  # --- Trust Commit journal hook (Wave E) ---
  # After the lock is persisted, build an immutable TrustCommit record and call
  # commitVerification so the replay layer can reconstruct durable state.
  let lockReadPath = block:
    let sr = getEnv("AXIOM_STATE_DIR", "").strip()
    if sr.len > 0: joinPath(sr, defaultProofUniverseLockPath)
    else: currentDir / defaultProofUniverseLockPath
  let lockReadRes = readProofUniverseLock(lockReadPath)
  if lockReadRes.isOk:
    # WP3-b Change 3: positive gate — a tcVerifiedProof journal entry is
    # structurally permitted ONLY when this run produced kernel-tier, claim-
    # associated verified nodes. Any other outcome (Vacuous, Unsupported,
    # Unknown, NoObligation, or Z3-only candidates) yields an empty set and the
    # VerifiedProof commit is skipped entirely (return ok, never a stronger claim).
    let verifiedNodes = canonicalVerifiedNodes(verifiedCommitEvidence(nodeReports, currentGraph))
    if verifiedNodes.len > 0:
      let lockJsonSummary = %*{
        "merkleRoot": lockReadRes.get.merkleRoot,
        "fileCount": lockReadRes.get.fileCount,
        "vkdFixed4": lockReadRes.get.vkdFixed4
      }
      let claim = %*{
        "graphSnapshot": %*{
          "symbolCount": currentGraph.symbols.len,
          "edgeCount": currentGraph.edges.len,
          "symbols": sortedSymbolKeys(currentGraph.symbols)
        },
        "lockSnapshot": lockJsonSummary,
        "verifiedNodes": buildVerifiedCommitPayload(verifiedNodes)
      }
      let claimStr = $claim
      let solverInvocation = "proof-universe-lock:v33"  # deterministic non-empty solver identifier
      let lockMerkleRoot = lockReadRes.get.merkleRoot
      let certificateDigest = lockMerkleRoot
      let evidenceId = computeEvidenceId(claimStr, solverInvocation, certificateDigest)
      var ks = sortedSymbolKeys(currentGraph.symbols)
      let scopeInput = CanonicalScopeInput(
        kernelSymbols: ks,
        kernelExemptSymbols: @[],
        kernelTotal: ks.len,
        vksTotal: 0,
        profileIdentity: asString(vkdFixed4),
        protocolVersion: "axiom-v33"
      )
      let scopeDigest = canonicalScopeDigest(scopeInput)
      let scopeLockHash = if lockReadRes.isOk: lockReadRes.get.merkleRoot else: ""
      let configDigest = configIdentityDigest(asString(vkdFixed4), scopeLockHash)
      let tc = TrustCommit(
        kind: tcVerifiedProof,
        evidenceId: evidenceId,
        claim: claimStr,
        solverInvocation: solverInvocation,
        attestation: "",
        certificateDigest: certificateDigest,
        scopeDigest: scopeDigest,
        configDigest: configDigest,
        parentCommit: none(string)
      )
      try:
        # WP3-b Change 1: route journal base to AXIOM_STATE_DIR when set,
        # else repo root (via repoRootForPath), else legacy currentDir.
        let journalBase = block:
          let sr = getEnv("AXIOM_STATE_DIR", "").strip()
          if sr.len > 0: sr
          else:
            let rr = repoRootForPath(currentDir)
            if rr.len > 0: rr
            else: currentDir
        let commitRes = commitVerification(journalBase, tc)
        if commitRes.isOk:
          echo "[AXIOM TRUST] proof_universe commit recorded: " & commitRes.get
        else:
          echo "[AXIOM TRUST] proof_universe commit failed: " & commitRes.error
      except CatchableError as e:
        # Best-effort journal hook: a journal write failure must not fail the
        # universe lock commit itself (lock is the primary gate; journal is the
        # durable replay record). Surface, never silently drop.
        echo "[AXIOM TRUST] proof_universe journal hook raised: " & e.msg
    else:
      # No kernel-tier verified nodes this run → skip the VerifiedProof commit.
      # The universe lock / integrity side effects above are unaffected.
      echo "[AXIOM TRUST] proof_universe VerifiedProof commit skipped: " &
        "no kernel-tier verified nodes in this run (verifiedNodes=" & $verifiedNodes.len & ")"
  result = Result[void, string](ok: true)

{.pop.}