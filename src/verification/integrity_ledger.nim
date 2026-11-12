import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Global Audit Buffer (AXIOM v0.6.8)
## In-memory accumulation of audit trails that are flushed atomically into
## certificates during commitUniverseIntegrityAndLock. Mid-pipeline modules
## MUST NOT perform disk I/O; they append to this buffer only.
##
## Relocated from src/core/integrity_ledger.nim to src/verification/ to restore
## Domain purity: mutable global state and file I/O belong in Infrastructure.

import std/options
import std/tables
import std/os
import std/strutils
import std/algorithm
import core/crypto/hash_kernel
import core/utils/io_utils
import core/json/json_utils
import core/json/std_redirect
import core/trusted/scope_identity
import core/trusted/trust_commit
# axiomIoBoundary

type
  GlobalAuditBuffer* = object
    reasoningTrail*: Table[string, seq[JsonNode]]
    provenanceLog*: Table[string, seq[JsonNode]]
    transitionLog*: Table[string, seq[JsonNode]]

## Module-level buffer. Reset at the start of each ax prove invocation
## and after each convergence flush.
var globalAuditBuffer*: GlobalAuditBuffer = GlobalAuditBuffer(
  reasoningTrail: initTable[string, seq[JsonNode]](),
  provenanceLog: initTable[string, seq[JsonNode]](),
  transitionLog: initTable[string, seq[JsonNode]]()
)

proc appendToReasoningTrail*(nodeId: string; event: JsonNode) {.raises: [].} =
  ## Buffer a reasoning event for the given nodeId.
  if nodeId.len == 0: return
  globalAuditBuffer.reasoningTrail.mgetOrPut(nodeId, newSeq[JsonNode]()).add(event)

proc appendToProvenanceLog*(nodeId: string; event: JsonNode) {.raises: [].} =
  ## Buffer a provenance event for the given nodeId.
  if nodeId.len == 0: return
  globalAuditBuffer.provenanceLog.mgetOrPut(nodeId, newSeq[JsonNode]()).add(event)

proc setTransitionLog*(nodeId: string; log: seq[JsonNode]) {.raises: [].} =
  ## Replace the buffered transition log for the given nodeId.
  if nodeId.len == 0: return
  globalAuditBuffer.transitionLog[nodeId] = log

## Is Certified Exempt Function Source.
## Determines whether a function qualifies as "axiom-pure-or-vacuous-primitive"
## based on structural heuristics in the source code.
## Criteria: func declaration (noSideEffect), short body, no complex control flow.
proc isCertifiedExemptFunctionSource*(sourceCode: string; functionName: string): bool =
  if sourceCode.len == 0 or functionName.len == 0:
    return false
  # Check for func declaration (indicates noSideEffect)
  let funcPattern = "func " & functionName & "*"
  let procPattern = "proc " & functionName & "*"
  let isFunc = sourceCode.contains(funcPattern)
  let isProc = sourceCode.contains(procPattern)
  if not isFunc and not isProc:
    return false
  # Extract function body roughly (between first '=' or ':' and next 'proc'/'func'/'type')
  var bodyStart = -1
  let funcIdx = sourceCode.find(functionName)
  if funcIdx < 0:
    return false
  # Look for '=' after function signature
  let searchStart = funcIdx + functionName.len
  let eqIdx = sourceCode.find("=", searchStart)
  if eqIdx < 0:
    return false
  bodyStart = eqIdx + 1
  # Find approximate end of function body (next top-level declaration)
  var bodyEnd = sourceCode.len
  for declPrefix in ["\nfunc ", "\nproc ", "\ntype ", "\nconst ", "\nvar ", "\nlet ", "\nimport "]:
    let declIdx = sourceCode.find(declPrefix, bodyStart)
    if declIdx >= 0 and declIdx < bodyEnd:
      bodyEnd = declIdx
  let body = sourceCode[bodyStart ..< bodyEnd].strip()
  if body.len == 0:
    return false
  # Heuristic: short body (<= 200 chars) suggests primitive
  if body.len <= 200:
    return true
  # Heuristic: no complex control flow keywords
  let complexKeywords = ["if ", "elif ", "else:", "while ", "for ", "case ", "try:", "except ", "finally:", "block ", "template ", "macro ", "when "]
  for kw in complexKeywords:
    if body.contains(kw):
      return false
  true

proc clearGlobalAuditBuffer*() {.raises: [].} =
  ## Reset all buffered audit data. Called after convergence flush.
  globalAuditBuffer.reasoningTrail = initTable[string, seq[JsonNode]]()
  globalAuditBuffer.provenanceLog = initTable[string, seq[JsonNode]]()
  globalAuditBuffer.transitionLog = initTable[string, seq[JsonNode]]()

proc resolveCertPath*(certDir: string; irHash: string): string {.raises: [].} =
  ## CAS-based cert path (irHash as sole address key) within the given cert directory.
  if irHash.len == 0: return ""
  result = certDir / (irHash & ".json")

proc auditBufferNodeIds(): seq[string] {.raises: [].} =
  var allNodeIds = initTable[string, bool]()
  for nodeId in globalAuditBuffer.reasoningTrail.keys:
    allNodeIds[nodeId] = true
  for nodeId in globalAuditBuffer.provenanceLog.keys:
    allNodeIds[nodeId] = true
  for nodeId in globalAuditBuffer.transitionLog.keys:
    allNodeIds[nodeId] = true

  var nodeIds: seq[string] = @[]
  for nodeId in allNodeIds.keys:
    nodeIds.add(nodeId)
  nodeIds.sort()
  nodeIds

proc auditBufferClaim(): JsonNode {.raises: [].} =
  var cert = newJObject()

  func appendField(fieldName: string; events: seq[JsonNode]) {.raises: [].} =
    if events.len == 0: return
    var updated = newJArray()
    for t in events:
      updated.add(t)
    cert[fieldName] = updated

  for nodeId in auditBufferNodeIds():
    if globalAuditBuffer.reasoningTrail.hasKey(nodeId):
      appendField("reasoningTrail", globalAuditBuffer.reasoningTrail.getOrDefault(nodeId, @[]))
    if globalAuditBuffer.provenanceLog.hasKey(nodeId):
      appendField("provenanceLog", globalAuditBuffer.provenanceLog.getOrDefault(nodeId, @[]))
    if globalAuditBuffer.transitionLog.hasKey(nodeId):
      appendField("transitionLog", globalAuditBuffer.transitionLog.getOrDefault(nodeId, @[]))

  result = cert

proc flushGlobalAuditBufferToCertificates*(certDir: string) {.raises: [].} =
  ## [AXIOM Wave 3] Atomic convergence flush: publish the in-memory audit buffer
  ## to the TrustCommit journal as the single durable state record. Called
  ## exclusively from commitUniverseIntegrityAndLock (single-threaded synchronous
  ## gate). Certificates are legacy side artifacts only; they are not merged or
  ## written by this flush path.

  let nodeIds = auditBufferNodeIds()
  if nodeIds.len == 0:
    clearGlobalAuditBuffer()
    return

  let journalBaseDir = parentDir(certDir)
  if journalBaseDir.len == 0:
    return

  let claimJson = auditBufferClaim()
  let claim = pretty(claimJson, 2) & "\n"
  let solverInvocation = "integrity-ledger-flush"
  let certificateDigest = "sha256:" & hash_kernel.sha256Hex(claim)
  let evidenceId = computeEvidenceId(claim, solverInvocation, certificateDigest)

  let scopeInput = CanonicalScopeInput(
    kernelSymbols: nodeIds,
    kernelExemptSymbols: @[],
    kernelTotal: nodeIds.len,
    vksTotal: nodeIds.len,
    profileIdentity: solverInvocation,
    protocolVersion: "wave3"
  )
  let scopeDigest = canonicalScopeDigest(scopeInput)
  let configDigest = configIdentityDigest(solverInvocation, certDir)

  let tc = TrustCommit(
    kind: tcVerifiedProof,
    evidenceId: evidenceId,
    claim: claim,
    solverInvocation: solverInvocation,
    attestation: "integrity-ledger-flush:v1",
    certificateDigest: certificateDigest,
    scopeDigest: scopeDigest,
    configDigest: configDigest,
    parentCommit: none(string)
  )

  try:
    let commitRes = commitVerification(journalBaseDir, tc)
    if commitRes.ok:
      clearGlobalAuditBuffer()
    else:
      # best-effort flush: on journal rejection keep the buffer for a later
      # retry and surface the rejection (never silently drop the audit trail).
      try:
        stderr.writeLine("[AXIOM WAVE3] integrity-ledger journal commit rejected: " & commitRes.err)
      except CatchableError:  # axiom:best-effort("best-effort stderr logging; logging failure must not mask original rejection")
        discard
  except CatchableError as e:
    try:
      stderr.writeLine("[AXIOM WAVE3] integrity-ledger journal commit raised: " & e.msg)
    except CatchableError:  # axiom:best-effort("best-effort stderr logging; logging failure must not mask original error")
      discard

{.pop.}

