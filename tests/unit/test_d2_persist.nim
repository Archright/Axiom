import std/[os, strutils, json, times, options]
import ../../src/core/results
import ../../src/core/trusted/claim_authority
import ../../src/verification/obligation/obligation_ir
import ../../src/core/crypto/hash_kernel
import ../../src/core/types/certificate_types
import ../../src/core/types/verification_tier
import ../../src/verification/obligation/lean_kernel_boundary
import ../../src/verification/obligation/kernel_acceptance_authority
import ../../src/verification/obligation/verification_decision_authority
import ../../src/verification/obligation/identity
import ../../src/verification/cert_writer
import ../../src/verification/cert_promotion
import ../../src/verification/cert_vault_role
import ../../src/verification/judgment_cas

## Judgment CAS test-boundary capture (d2_persist subject): the persistence
## LOOP judgment — the single kernel receipt + the writer→reader round-trip
## checkpoint observations. Unarmed (no
## AXIOM_JUDGMENT_CAS_EVIDENCE_PATH_D2_PERSIST) the flush is a no-op pass.
var judgmentKernelRunCount = 0
var judgmentLoop: D2PersistJudgmentEvidence
var judgmentLoopCaptured = false

proc jcapLoop(e: D2PersistJudgmentEvidence) =
  judgmentLoop = e
  judgmentLoopCaptured = true

## D2 Persistence — persist a genuine Lean-verified certificate
## through the real product persistence boundary (cert_writer.nim).
##
## This script demonstrates that a genuine kernel-backed verified
## certificate CAN flow through the real product writer.
##
## Usage: nim c -d:release --hints:off --warnings:off --path:src --path:. -o:bin/d2_persist tools/d2_persist.nim && bin/d2_persist

const
  D2GoldenSource = "theorem d2Golden : True := trivial\n"
  D2GoldenTheoremName = "d2Golden"

proc main() =
  echo "=== D2 Persistence ==="
  echo ""

  # Stage 1: Get the real Lean kernel receipt
  echo "[Stage 1] Real Lean Kernel Check"
  let receiptRes = canonicalLeanKernelCheck(D2GoldenSource)
  if receiptRes.isErr():
    echo "FATAL: canonicalLeanKernelCheck failed: " & receiptRes.error()
    quit(1)
  let receipt = receiptRes.get()
  inc judgmentKernelRunCount
  echo "  receipt.theoremIdentity = " & receipt.receiptTheoremIdentity
  echo "  Stage 1: PASS"
  echo ""

  # Stage 2: Bind receipt → KAA
  echo "[Stage 2] Receipt → KAA"
  let kaaRes = bindReceipt(receipt)
  if kaaRes.isErr():
    echo "FATAL: bindReceipt failed: " & kaaRes.error()
    quit(1)
  let kaa = kaaRes.get()
  echo "  Stage 2: PASS"
  echo ""

  # Stage 3: Evaluate → vdVerified
  echo "[Stage 3] Evaluate → vdVerified"
  let policy = VerificationPolicy(
    allowedAxioms: @["propext", "Classical.choice"],
    sorryPolicy: spForbid
  )
  let verdict = evaluate(kaa, policy)
  if verdict != vdVerified:
    echo "FATAL: evaluate did not return vdVerified"
    quit(1)
  echo "  verdict = " & $verdict
  echo "  Stage 3: PASS"
  echo ""

  # Stage 4: Persist a genuine kernel-backed certificate through the real
  # product persistence boundary (writeCertificateFromUapResult).
  # The KAA from Stages 1-2 is the ONLY forge-proof route to kernel=true:
  # KernelAcceptanceAttestation can only be produced by bindReceipt(LeanKernelCheckReceipt)
  # where the receipt came from canonicalLeanKernelCheck (real Lean execution).
  echo "[Stage 4] Persist Certificate via cert_writer"
  let certDir = getTempDir() / ("d2_persist_" & $epochTime().int64)
  var certLogLines: seq[string] = @[]
  let irHash = sha256Hex("test_d2_persist" & D2GoldenTheoremName & D2GoldenSource)
  let wroteOk = writeCertificateFromUapResult(
    certDir,
    modulePath = "test_d2_persist",
    functionName = D2GoldenTheoremName,
    sourceCode = D2GoldenSource,
    leanKernelVerified = true,
    smtlib2 = "",
    solverStatus = "",
    logLines = certLogLines,
    vacuityProven = true,
    irHash = irHash,
    leanProposition = D2GoldenSource,
    negativeTestResult = false,
    kaa = some(kaa)
  )
  if not wroteOk:
    echo "FATAL: writeCertificateFromUapResult failed"
    quit(1)
  echo "  Certificate written to: " & certDir
  echo "  Stage 4: PASS"
  echo ""

  # Stage 5: Verify the persisted certificate is honest and internally consistent
  echo "[Stage 5] Verify Persisted Certificate"
  let certFileName = irHash & ".json"
  let certPath = certDir / certFileName
  if not fileExists(certPath):
    echo "FATAL: certificate file not found at " & certPath
    quit(1)
  let certNode = parseJson(readFile(certPath))
  doAssert certNode.kind == JObject, "certificate must be a JSON object"

  # kernel must be true — derived from the genuine KAA, not a static lookup
  let kernelVal = certNode.getOrDefault("kernel").getBool(false)
  doAssert kernelVal == true, "kernel must be true from genuine KAA, got: " & $kernelVal

  # status must be certLeanVerified — honest evidence tier from real kernel acceptance
  let statusVal = certNode.getOrDefault("status").getStr("")
  doAssert statusVal == "certLeanVerified", "status must be certLeanVerified, got: " & statusVal

  # solverMeta.leanCompilerVerified must be true (from genuine KAA)
  let solverMeta = certNode.getOrDefault("solverMeta")
  doAssert solverMeta != nil and solverMeta.kind == JObject, "solverMeta must be an object"
  let leanCompilerVerified = solverMeta.getOrDefault("leanCompilerVerified").getBool(false)
  doAssert leanCompilerVerified == true, "leanCompilerVerified must be true from genuine KAA"

  # certificateEvidenceFromJson must yield leanVerified==true (proves genuine kernel evidence)
  let evidence = certificateEvidenceFromJson(certNode)
  doAssert evidence.leanVerified == true, "leanVerified must be true from genuine kernel evidence"

  # statusConsistentWithEvidence must pass (cert claims no more than its evidence supports)
  let statusConsistent = statusConsistentWithEvidence(certNode)
  doAssert statusConsistent, "status must be consistent with stored evidence"

  # verificationTier must be vtLeanOnly (Lean-only, no Z3 evidence)
  let tierVal = certNode.getOrDefault("verificationTier").getStr("")
  doAssert tierVal == "lean-verified", "verificationTier must be lean-verified, got: " & tierVal

  # Judgment CAS loop capture: every checkpoint's OBSERVED result.
  var loop: D2PersistJudgmentEvidence
  loop.irHash = irHash
  for i, name in CanonicalD2PersistLoopCheckpoints:
    loop.loopCheckpoints[i] = case name
      of "evidenceLeanVerified": evidence.leanVerified
      of "kernelFlagFromKaa": kernelVal
      of "leanCompilerVerified": leanCompilerVerified
      of "statusCertLeanVerified": statusVal == "certLeanVerified"
      of "statusConsistentWithEvidence": statusConsistent
      of "tierLeanVerified": tierVal == "lean-verified"
      of "writerPersisted": wroteOk
      else: false
  jcapLoop(loop)

  # Clean up temp certificate directory
  try:
    removeDir(certDir)
  except CatchableError:
    discard  # axiom:best-effort(temp cleanup)

  echo "  Certificate honesty verified: kernel=true, status=certLeanVerified, leanVerified=true"
  echo "  Stage 5: PASS"
  echo ""

  # Judgment CAS flush (d2_persist subject) — armed: emit; unarmed: pass.
  # Fail-closed: an armed run whose loop evidence cannot be staged fails HERE.
  if getEnv(subjectEvidencePathEnv(jsD2Persist), "").len > 0:
    if not judgmentLoopCaptured:
      echo "FATAL: judgment CAS armed but the loop judgment was never captured"
      quit(1)
    let written = writeD2PersistJudgmentEvidenceFile(judgmentLoop, judgmentKernelRunCount)
    if written.isErr:
      echo "FATAL: judgment CAS flush failed: " & written.error
      quit(1)
    let reparsed = parseJudgmentEvidenceFile(getEnv(subjectEvidencePathEnv(jsD2Persist), ""))
    if reparsed.isErr or reparsed.get != written.get:
      echo "FATAL: judgment CAS evidence re-parse mismatch"
      quit(1)
    echo "  Judgment CAS: evidence staged (" & subjectName(jsD2Persist) & ")"
  echo "=== D2 Persistence Complete (GENUINE KERNEL CERTIFICATE) ==="

when isMainModule:
  main()