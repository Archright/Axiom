## Wave2 UAP loop cutover: certificate persistence now lands in TrustCommit journal.

import std/json
import std/os
import std/options
import std/strutils

import core/crypto/hash_kernel
import core/trusted/trust_commit
import core/utils/io_utils
import verification/cert_writer

proc main() =
  echo "=== Wave2 UAP loop TrustCommit cutover ==="
  let tmp = getTempDir() / "ax_wave2_loop_cutover" & $getCurrentProcessId()
  try:
    removeDir(tmp)
  except CatchableError:
    # axiom:best-effort(temp dir pre-cleanup is non-fatal; test asserts on TrustCommit journal output)
    discard
  discard existsOrCreateDirOpt(tmp)

  var logLines: seq[string] = @[]
  let modulePath = "src/wave2/mod.nim"
  let functionName = "loopCandidate"
  let sourceCode = """proc loopCandidate(i: int): int =
  result = 0
  for x in 0..<i:
    inc result
"""
  let irHash = "wave2-ir"
  let ok = writeCertificateFromUapResult(
    certDir = tmp,
    modulePath = modulePath,
    functionName = functionName,
    sourceCode = sourceCode,
    leanKernelVerified = false,
    smtlib2 = "",
    solverStatus = "unknown",
    logLines = logLines,
    irHash = irHash)
  doAssert ok, "UAP loop certificate must commit to TrustCommit: " & logLines.join("; ")

  let idsRes = listCommitIds(tmp)
  doAssert idsRes.ok, "TrustCommit journal enumeration must succeed"
  var solverInvocations: seq[string] = @[]
  var foundUapCommit = false
  for id in idsRes.value:
    let commit = readCommit(tmp, id)
    doAssert commit.ok, "read persisted UAP commit must succeed"
    doAssert validateCommit(commit.value).ok, "persisted UAP commit must re-validate"
    solverInvocations.add(commit.value.solverInvocation)
    if commit.value.solverInvocation == "batch-uap-loop":
      let commitNode = parseJson(commitToJson(commit.value))
      let claimNode = parseJson(commit.value.claim)
      doAssert commitNode["kind"].getStr == "tcVerifiedProof"
      doAssert claimNode["status"].getStr == "certRed"
      doAssert claimNode["reason"].getStr == "unverified"
      doAssert claimNode["modulePath"].getStr == modulePath
      doAssert claimNode["functionName"].getStr == functionName
      doAssert claimNode["solverStatus"].getStr == "unknown"
      doAssert claimNode["irHash"].getStr == irHash
      doAssert not claimNode.hasKey("claimId")
      foundUapCommit = true

  doAssert idsRes.value.len >= 2, "UAP loop cutover must produce batch-uap-loop + z3out TrustCommit journals"
  doAssert "batch-uap-loop" in solverInvocations, "journal includes batch-uap-loop solverInvocation"
  doAssert "z3out" in solverInvocations, "journal includes z3out solverInvocation"

  let commit = readCommit(tmp, idsRes.value[0])
  doAssert commit.ok, "read persisted UAP commit must succeed"
  doAssert validateCommit(commit.value).ok, "persisted UAP commit must re-validate"
  doAssert commit.value.claim.len > 0
  doAssert commit.value.attestation.len > 0
  doAssert commit.value.certificateDigest == hash_kernel.sha256Hex(commit.value.claim)
  doAssert commit.value.evidenceId == computeEvidenceId(commit.value.claim, commit.value.solverInvocation, commit.value.certificateDigest)
  doAssert commit.value.scopeDigest == hash_kernel.sha256Hex(modulePath & "|" & functionName & "|" & sourceCode & "|" & irHash)
  doAssert commit.value.configDigest.len > 0
  doAssert commit.value.parentCommit == none(string)

  doAssert not fileExists(tmp / (irHash & ".json")), "legacy raw cert file must not be written"

  try:
    removeDir(tmp)
  except CatchableError:
    # axiom:best-effort(temp dir teardown is cleanup; test outcome already asserted above)
    discard
  echo "  OK: UAP loop cert persistence is TrustCommit-only"
  echo "=== Wave2 UAP loop TrustCommit cutover OK ==="

main()
