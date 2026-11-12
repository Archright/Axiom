# Phase-4 general-path evidence cross-check (C2 closure):
# writeCertificateFromUapResult WITHOUT a VerifiedClaim must derive status purely
# from evidence (z3Passed, leanVerified) — and the P0 guard
# (statusConsistentWithEvidence, DECISION-0630) must run AFTER the evidence
# fields are populated, so legitimate certs are never downgraded while a
# drifted/overclaiming status would be corrected. No verified boolean collapse:
# every cert carries verificationTier + solverMeta so Z3-only vs dual is
# distinguishable downstream (B4 tier-collapse closure).

import std/json
import std/options
import std/os
import std/strutils
import core/crypto/hash_kernel
import core/trusted/layer_declaration
import core/trusted/trust_commit
import core/types/certificate_types
import core/types/verification_tier
import core/utils/io_utils
import verification/cert_writer

proc lastBatchCommit(certDir: string): JsonNode =
  ## Returns the claim JSON of the batch-uap-loop journal commit (general path).
  let idsRes = listCommitIds(certDir)
  doAssert idsRes.ok, "journal ids available"
  for id in idsRes.value:
    let c = readCommit(certDir, id)
    doAssert c.ok, "journal commit reads: " & id
    if c.value.solverInvocation == "batch-uap-loop" and c.value.claim.len > 0:
      return parseJson(c.value.claim)
  doAssert false, "batch-uap-loop commit missing in journal"

proc runGeneral(solverStatus: string; leanKernelVerified: bool;
                expectedStatus, expectedReason: string) =
  let tmp = getTempDir() / "ax_writer_general" & "_" & solverStatus & "_" &
            $leanKernelVerified & "_" & $getCurrentProcessId()
  try:
    removeDir(tmp)
  except CatchableError:
    discard # axiom:best-effort(temp dir pre-cleanup is non-fatal)
  discard existsOrCreateDirOpt(tmp)
  var logLines: seq[string] = @[]
  let ok = writeCertificateFromUapResult(
    certDir = tmp,
    modulePath = "src/mod.nim",
    functionName = "f",
    sourceCode = "func f(x:int):int = x",
    leanKernelVerified = leanKernelVerified,
    smtlib2 = "(set-logic QF_BV)",
    solverStatus = solverStatus,
    logLines = logLines,
    irHash = "irhash" & solverStatus & $leanKernelVerified,
    semanticProfileId = "SPV1")
  doAssert ok, "general path write must succeed, logs: " & logLines.join("; ")

  let cert = lastBatchCommit(tmp)
  doAssert cert["status"].getStr == expectedStatus,
    "status must be evidence-derived (" & expectedStatus & "), got: " & cert["status"].getStr
  doAssert cert["reason"].getStr == expectedReason,
    "reason mismatch: " & cert["reason"].getStr
  # P0: the written status must never be stronger than stored evidence
  doAssert statusConsistentWithEvidence(cert),
    "writer emitted evidence-inconsistent status: " & $cert
  # B4 closure: tier must be present and match evidence, not a collapsed boolean
  doAssert cert["verificationTier"].getStr.len > 0
  let tier = cert["verificationTier"].getStr
  doAssert tierToStatusString(tierFromEvidence(certificateEvidenceFromJson(cert))) == expectedStatus
  # evidence fields present so report/audit can reconstruct the tier
  doAssert cert["solverStatus"].getStr == solverStatus
  doAssert cert["solverMeta"]["leanCompilerVerified"].getBool == leanKernelVerified
  # C2 regression: the guard may NOT fire on legitimate evidence (anti-theater)
  doAssert cert["reason"].getStr != "evidence-corrected",
    "legitimate evidence must not be corrected: " & $cert
  try:
    removeDir(tmp)
  except CatchableError:
    discard # axiom:best-effort(temp dir teardown; assertions already ran)
  echo "  OK: solverStatus=" & solverStatus & " lean=" & $leanKernelVerified &
       " -> " & expectedStatus

proc main() =
  echo "=== Phase-4 general-path evidence cross-check ==="
  # 1. Z3-only evidence must yield certZ3Candidate (never certGreen) — B2
  #    mapping (core/types/certificate_types: Z3-only/K-induction are
  #    candidate-only, never verified).
  runGeneral("unsat", false, "certZ3Candidate", "z3-verified")
  # 2. A naked leanKernelVerified flag is lean-evidence-unbound (A2 binding:
  #    cert_writer promotes lean evidence only with a bound leanProposition),
  #    so it cannot promote the Z3-only tier on its own.
  runGeneral("unsat", true, "certZ3Candidate", "z3-verified")
  # 3. Lean-only flag without a bound leanProposition: tier vtNone renders as
  #    certNoObligation with the lean-evidence-unbound reason.
  runGeneral("unknown", true, "certNoObligation", "lean-evidence-unbound")
  # 4. No evidence at all: B2 maps vtNone to certNoObligation (never certRed).
  runGeneral("sat", false, "certNoObligation", "unverified")

  # 5. C2 guard teeth: a drifted status (certGreen on Z3-only evidence) is
  #    rejected by statusConsistentWithEvidence and demoted by the same
  #    decision logic the writer embeds.
  let drifted = %*{
    "status": "certGreen",
    "solverStatus": "unsat",
    "solverMeta": {"leanCompilerVerified": false, "z3Executed": true}
  }
  doAssert not statusConsistentWithEvidence(drifted),
    "P0 gate must reject certGreen without dual evidence"
  let demotedTier = tierFromEvidence(certificateEvidenceFromJson(drifted))
  doAssert demotedTier == vtZ3Only
  doAssert tierToStatusString(demotedTier) == "certZ3Candidate",
    "drifted certGreen must demote to certZ3Candidate"
  echo "     OK: drifted certGreen rejected -> certZ3Candidate (guard teeth)"
  echo "=== Phase-4 general-path evidence cross-check OK ==="
main()