import std/[json, unittest, os]
import ../../src/core/types/certificate_types
import ../../src/core/trusted/axiom_pragmas
import ../../src/core/trusted/fingerprint_generator
import ../../src/core/proof/proof_integrity
import ../../src/verification/certificate_verifier
import ../../src/core/proof/source_fingerprint
import ../../src/core/utils/repo_root
import ../../src/core/io/file_utils
import ../../src/core/results
import ../../src/verification/judgment_cas

# Unit tests for proof_integrity unified deep-verification predicate
# with the Phase 2 WS-A Set Membership stage.

## Judgment CAS test-boundary capture (proof_integrity subject): every
## checkpoint's OBSERVED predicate verdict is recorded in capture order.
## The set is run-invariant — the suite is a pure predicate battery (kernel
## 0 runs) — so the capture is the judgment, not a sample of it. Unarmed
## (no AXIOM_JUDGMENT_CAS_EVIDENCE_PATH_PROOF_INTEGRITY) the flush is a
## no-op pass; recording is opt-in by env, never ambient.
var judgmentCheckpoints: seq[tuple[name, verdict: string]]

proc jcap(name, verdict: string) =
  judgmentCheckpoints.add((name: name, verdict: verdict))

proc makeKernelEntry(name: string, modulePath: string): RuntimeAxiomEntry =
  RuntimeAxiomEntry(
    name: name,
    irSerialized: "ir",
    smtSource: "",
    leanSource: "",
    sourcePath: modulePath,
    isKernel: true,
    irHash: "abc123"
  )

proc makeEmpiricalEntry(name: string): RuntimeAxiomEntry =
  RuntimeAxiomEntry(
    name: name,
    irSerialized: "ir",
    smtSource: "",
    leanSource: "",
    sourcePath: "",
    isKernel: false,
    irHash: "abc123"
  )

proc readSource(modulePath: string): string =
  let repo = resolveRepoRoot()
  let fullPath = repo / modulePath
  if not fileExists(fullPath):
    return ""
  readFileSafe(fullPath)

proc makeKernelCert(modulePath, functionName: string; source: string): JsonNode =
  let irHash = "abc123"
  let leanProp = "p"
  let fp = computeVerificationFingerprint(irHash, leanProp)
  result = %*{
    "modulePath": modulePath,
    "functionName": functionName,
    "fingerprint": fp,
    "irHash": irHash,
    "leanProposition": leanProp,
    "solverMeta": {"leanCompilerVerified": true, "smtlib2": ""},
    "smtlib2": "",
    "passed": true,
    "status": "certLeanVerified",
    "axiomsUsed": ["propext", "Quot.sound"],
    # certLeanVerified claims the Lean kernel accepted this proof, so the cert
    # must carry the `kernel` assertion that certificateEvidenceFromJson
    # conjuncts with solverMeta.leanCompilerVerified (verification_tier.nim:110).
    # Production writers emit it (cert_writer.nim:332, cert_reconcile.nim:277).
    "kernel": true,
    "sourceHash": computeStableSourceFingerprint(source)
  }

proc makeKernelCert(modulePath, functionName: string): JsonNode =
  makeKernelCert(modulePath, functionName, readSource(modulePath))

proc testKernelSymbolInDenominator() =
  ## kernel cert `axiomSpecToJsonNode` is in the denominator -> Set Membership
  ## passes when scope contains it.
  let scope = KernelScopeInfo(
    kernelSymbols: @["src/core/vault/vault_manager_spec.nim::axiomSpecToJsonNode"],
    kernelTotal: 1
  )
  let cert = makeKernelCert("src/core/vault/vault_manager_spec.nim", "axiomSpecToJsonNode")
  let entry = makeKernelEntry("axiomSpecToJsonNode", "src/core/vault/vault_manager_spec.nim")
  let observed = isDeepVerified(cert, "", entry, "", scope, certificate_verifier.isDeepVerified)
  check observed == dvcSuccess
  jcap("kernelSymbolInDenominator", $observed)

proc testKernelSymbolNotInDenominator() =
  ## kernel cert `sanitizeVaultToken` is NOT in the denominator -> dvcNotInKernelScope.
  let scope = KernelScopeInfo(
    kernelSymbols: @["src/core/vault/vault_manager_spec.nim::axiomSpecToJsonNode"],
    kernelTotal: 1
  )
  let cert = makeKernelCert("src/core/vault/vault_manager_spec.nim", "sanitizeVaultToken")
  let entry = makeKernelEntry("sanitizeVaultToken", "src/core/vault/vault_manager_spec.nim")
  let observed = isDeepVerified(cert, "", entry, "", scope, certificate_verifier.isDeepVerified)
  check observed == dvcNotInKernelScope
  jcap("kernelSymbolNotInDenominator", $observed)

proc testNonKernelMemberNotChecked() =
  ## non-kernel cert -> Set Membership skipped, 3-stage result preserved.
  let scope = KernelScopeInfo(
    kernelSymbols: @["src/core/vault/vault_manager_spec.nim::axiomSpecToJsonNode"],
    kernelTotal: 1
  )
  let cert = makeKernelCert("src/core/vault/vault_manager_spec.nim", "nonKernelFunc")
  let entry = makeEmpiricalEntry("nonKernelFunc")
  let observed = isDeepVerified(cert, "", entry, "", scope, certificate_verifier.isDeepVerified)
  check observed == dvcSuccess
  jcap("nonKernelMemberNotChecked", $observed)

proc testEmptyScopeDegradedMode() =
  ## empty scope (lock missing / schema v1) -> Set Membership skipped, 3-stage result.
  let scope = KernelScopeInfo(kernelSymbols: @[], kernelTotal: 0)
  let cert = makeKernelCert("src/core/vault/vault_manager_spec.nim", "sanitizeVaultToken")
  let entry = makeKernelEntry("sanitizeVaultToken", "src/core/vault/vault_manager_spec.nim")
  let observed = isDeepVerified(cert, "", entry, "", scope, certificate_verifier.isDeepVerified)
  check observed == dvcSuccess
  jcap("emptyScopeDegradedMode", $observed)

proc testLoadKernelScopeValid() =
  let scope = KernelScopeInfo(
    kernelSymbols: @["src/core/vault/vault_manager_spec.nim::axiomSpecToJsonNode"],
    kernelTotal: 1
  )
  let symbol = makeKernelCert("src/core/vault/vault_manager_spec.nim", "axiomSpecToJsonNode")
  let inScope = symbolInKernelScope(symbol, scope)
  check inScope == true
  jcap("kernelScopeSymbolInDenominator", $inScope)
  let other = makeKernelCert("src/core/vault/vault_manager_spec.nim", "sanitizeVaultToken")
  let outOfScope = symbolInKernelScope(other, scope)
  check outOfScope == false
  jcap("kernelScopeSymbolOutOfDenominator", $outOfScope)

proc testAdmissionAdmit() =
  ## certGreen + kernel + non-exempt + in-scope → varAdmit.
  ## P0: certGreen is admitted ONLY with dual (Z3 ∧ Lean) evidence.
  let scope = KernelScopeInfo(
    kernelSymbols: @["src/core/vault/vault_manager_spec.nim::axiomSpecToJsonNode"],
    kernelTotal: 1,
    kernelExemptSymbols: @[]
  )
  let cert = makeKernelCert("src/core/vault/vault_manager_spec.nim", "axiomSpecToJsonNode")
  cert["status"] = %"certGreen"
  cert["solverStatus"] = %"unsat"   # P0: dual evidence (Z3 unsat) + leanCompilerVerified=true
  let entry = makeKernelEntry("axiomSpecToJsonNode", "src/core/vault/vault_manager_spec.nim")
  let observed = isVkdAdmissible(cert, entry, scope, certificate_verifier.isDeepVerified)
  check observed == varAdmit
  jcap("admissionAdmit", $observed)

proc testAdmissionExemptIsScopeInconsistency() =
  ## An exempt symbol (defense-in-depth) → varScopeInconsistency, never admit.
  let scope = KernelScopeInfo(
    kernelSymbols: @["src/core/vault/vault_manager_spec.nim::axiomSpecToJsonNode"],
    kernelTotal: 1,
    vksTotal: 0,
    kernelExemptSymbols: @["src/core/vault/vault_manager_spec.nim::axiomSpecToJsonNode"]
  )
  let cert = makeKernelCert("src/core/vault/vault_manager_spec.nim", "axiomSpecToJsonNode")
  let entry = makeKernelEntry("axiomSpecToJsonNode", "src/core/vault/vault_manager_spec.nim")
  let observed = isVkdAdmissible(cert, entry, scope, certificate_verifier.isDeepVerified)
  check observed == varScopeInconsistency
  jcap("admissionExemptIsScopeInconsistency", $observed)

proc testAdmissionNoObligationRejects() =
  ## certNoObligation vocabulary — a failure/incomplete state must NOT admit.
  let scope = KernelScopeInfo(
    kernelSymbols: @["src/core/vault/vault_manager_spec.nim::axiomSpecToJsonNode"],
    kernelTotal: 1
  )
  let cert = makeKernelCert("src/core/vault/vault_manager_spec.nim", "axiomSpecToJsonNode")
  cert["status"] = %"certNoObligation"
  let entry = makeKernelEntry("axiomSpecToJsonNode", "src/core/vault/vault_manager_spec.nim")
  let observed = isVkdAdmissible(cert, entry, scope, certificate_verifier.isDeepVerified)
  check observed == varReject
  jcap("admissionNoObligationRejects", $observed)

proc testStaleCertSourceHashMismatch() =
  ## Stage 2: source modified + old cert → dvcNotCurrent (artifact is valid
  ## but not current product truth — source staleness is a compatibility axis,
  ## not an integrity violation).
  let scope = KernelScopeInfo(
    kernelSymbols: @["src/core/vault/vault_manager_spec.nim::axiomSpecToJsonNode"],
    kernelTotal: 1
  )
  let entry = makeKernelEntry("axiomSpecToJsonNode", "src/core/vault/vault_manager_spec.nim")
  let oldSource = "different source content that produces a different fingerprint"
  let cert = makeKernelCert("src/core/vault/vault_manager_spec.nim", "axiomSpecToJsonNode", oldSource)
  let observed = isDeepVerified(cert, "", entry, "", scope, certificate_verifier.isDeepVerified)
  check observed == dvcNotCurrent
  jcap("staleCertSourceHashMismatch", $observed)

proc testRenewedCertAccepts() =
  ## Stage 3: renewed cert (new sourceHash matching current file) → dvcSuccess.
  let scope = KernelScopeInfo(
    kernelSymbols: @["src/core/vault/vault_manager_spec.nim::axiomSpecToJsonNode"],
    kernelTotal: 1
  )
  let cert = makeKernelCert("src/core/vault/vault_manager_spec.nim", "axiomSpecToJsonNode")
  let entry = makeKernelEntry("axiomSpecToJsonNode", "src/core/vault/vault_manager_spec.nim")
  let observed = isDeepVerified(cert, "", entry, "", scope, certificate_verifier.isDeepVerified)
  check observed == dvcSuccess
  jcap("renewedCertAccepts", $observed)

proc testFreshCertAccepts() =
  ## Stage 1: fresh cert (sourceHash == current file) → dvcSuccess.
  let scope = KernelScopeInfo(
    kernelSymbols: @["src/core/vault/vault_manager_spec.nim::axiomSpecToJsonNode"],
    kernelTotal: 1
  )
  let cert = makeKernelCert("src/core/vault/vault_manager_spec.nim", "axiomSpecToJsonNode")
  let entry = makeKernelEntry("axiomSpecToJsonNode", "src/core/vault/vault_manager_spec.nim")
  let observed = isDeepVerified(cert, "", entry, "", scope, certificate_verifier.isDeepVerified)
  check observed == dvcSuccess
  jcap("freshCertAccepts", $observed)

suite "Proof Integrity":
  test "Proof Integrity tests":
    testKernelSymbolInDenominator()
    testKernelSymbolNotInDenominator()
    testNonKernelMemberNotChecked()
    testEmptyScopeDegradedMode()
    testLoadKernelScopeValid()

  test "VKD admission: admit / reject / scopeInconsistency separation":
    testAdmissionAdmit()
    testAdmissionExemptIsScopeInconsistency()
    testAdmissionNoObligationRejects()

  test "3-stage source-staleness pipeline (production certSourceHashMatchesSource path)":
    testFreshCertAccepts()
    testStaleCertSourceHashMismatch()
    testRenewedCertAccepts()

suite "Judgment CAS flush (proof_integrity subject)":
  test "judgment CAS flush — the canonical predicate set (armed: emit; unarmed: pass)":
    ## AXIOM_JUDGMENT_CAS: when AXIOM_JUDGMENT_CAS_EVIDENCE_PATH_PROOF_INTEGRITY
    ## is armed, THIS test is the single flush point for the subject's
    ## judgment evidence — the observed predicate verdicts of the whole
    ## battery (kernel 0 runs, pure predicates). Unarmed (every other
    ## invocation: unit CI, local dev, other gates) it trivially passes.
    if getEnv(subjectEvidencePathEnv(jsProofIntegrity), "").len == 0:
      skip()
    else:
      check judgmentCheckpoints.len == ProofIntegrityCheckpointCount
      var e = ProofIntegrityJudgmentEvidence()
      for i, name in CanonicalProofIntegrityCheckpoints:
        var found = false
        for cp in judgmentCheckpoints:
          if cp.name == name:
            e.checkpointVerdicts[i] = cp.verdict
            found = true
            break
        check found
      let written = writeProofIntegrityJudgmentEvidenceFile(e)
      check written.isOk
      ## The flushed bytes must re-parse and re-validate — the attest stage
      ## will build the record from exactly these bytes.
      let reparsed = parseJudgmentEvidenceFile(
        getEnv(subjectEvidencePathEnv(jsProofIntegrity), ""))
      check reparsed.isOk
      check reparsed.get == written.get
