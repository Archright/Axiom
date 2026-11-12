import std/[os, json, strutils, unittest]
import core/types/results
import core/crypto/hash_kernel
import core/trusted/fingerprint_generator
import core/proof/source_fingerprint
import verification/cert_promotion
import verification/cert_reconcile
import verification/certificate_identity
import verification/canonical_certificate_payload

## Regression coverage for e144c5f5a / 625171581 — "fix(promotion): treat same
## evidence under a new subject ref as an idempotent cache refresh".
##
## The v3 canonical identity binds the subject git ref (via `evidenceId`),
## while the canonical cache file is keyed by `irHash` and the function-level
## evidence identity is `journalEvidenceKey` (the 13 identity fields minus
## `evidenceId`). The sealed behaviors:
##
##   1. re-verification of the SAME function-level evidence under a new
##      subject ref (new evidenceId → new v3 identity, same evidence key)
##      MUST succeed and the canonical file MUST become the new candidate's
##      projection (idempotent cache refresh);
##   2. a re-promotion of the already-current projection stays identity-
##      idempotent (C4 short-circuit);
##   3. a genuinely different evidence key (changed sourceHash → changed
##      subject bytes) under the same irHash MUST fail closed with the
##      "DIFFERENT canonical identity" conflict error and leave the canonical
##      file untouched.
##
## Real fixtures only: the candidates are full v3 certificates that pass the
## promotion aggregate gate; the canonical dir is a real
## `data/trusted/certificates` store under a temp CWD; the TrustCommit journal
## is redirected into the same temp sandbox via AXIOM_STATE_DIR.

const
  SubjectModule = "src/examples/promo_subject.nim"
  SubjectFn = "promoFn"
  LeanProp = "promoFn_staysTotal"
  Status = "certLeanVerified"
  WinningStrategy = "lean-replay"
  SolverStatus = ""
  InputHash = "sha256:fixture-input"
  SolverInDigest = "sha256:fixture-sinput"
  SolverOutDigest = "sha256:fixture-sresult"

var sandboxCounter = 0

proc makeSandbox(): string =
  ## Fresh temp CWD with the runtime canonical vault layout and a redirected
  ## journal root; the caller chdirs in and must restore CWD/env itself.
  inc sandboxCounter
  let dir = getTempDir() / "axiom_promo_refresh_test" /
    ($getCurrentProcessId() & "_" & $sandboxCounter)
  removeDir(dir)
  createDir(dir / "data" / "trusted" / "certificates")
  putEnv("AXIOM_STATE_DIR", dir / "state")
  dir

proc teardownSandbox(sandbox: string) =
  setCurrentDir(getTempDir())
  delEnv("AXIOM_STATE_DIR")
  removeDir(sandbox)

proc makeCandidateCert(irHash, evidenceId, sourceHash: string): JsonNode =
  ## A full v3 certificate over `promoFn` that passes the promotion aggregate
  ## gate (verifySemanticEvidence + verifyIdentityBinding +
  ## verifyCertificateCompleteness for certLeanVerified). `evidenceId` plays
  ## the subject-ref role: it is part of the v3 identity but NOT of
  ## journalEvidenceKey.
  let identityDigest = compV3Identity(V3IdentityState(
    schemaVersion: CanonicalCertificateSchemaVersion,
    modulePath: SubjectModule,
    functionName: SubjectFn,
    sourceHash: sourceHash,
    irHash: irHash,
    leanProposition: LeanProp,
    solverStatus: SolverStatus,
    status: Status,
    winningStrategy: WinningStrategy,
    inputHash: InputHash,
    solverInputDigest: SolverInDigest,
    solverResultDigest: SolverOutDigest,
    evidenceId: evidenceId))
  %*{
    "schemaVersion": CanonicalCertificateSchemaVersion,
    "modulePath": SubjectModule,
    "functionName": SubjectFn,
    "sourceHash": sourceHash,
    "irHash": irHash,
    "leanProposition": LeanProp,
    "solverStatus": SolverStatus,
    "status": Status,
    "winningStrategy": WinningStrategy,
    "inputHash": InputHash,
    "solverInputDigest": SolverInDigest,
    "solverResultDigest": SolverOutDigest,
    "evidenceId": evidenceId,
    "identityDigest": identityDigest,
    "fingerprint": computeVerificationFingerprint(irHash, LeanProp),
    "kernel": true,
    "solverMeta": %*{"leanCompilerVerified": true, "leanKernelVerified": true},
    "solverInvocation": %*{"engine": "lean", "mode": "replay", "strategy": "none", "version": "4.29.0"},
    "claim": %*{
      "modulePath": SubjectModule,
      "functionName": SubjectFn,
      "status": Status,
      "type": "verification"
    },
    "attestation": %*{
      "algorithm": "Ed25519",
      "authority": "axiom",
      "policyVersion": CanonicalCertificateSchemaVersion
    },
    "provenance": %*{
      "certificateDigest": identityDigest,
      "journalCommitId": evidenceId
    },
    "toolchainIdentity": %*{"nim": "2.2.10", "lean": "4.29.0"}
  }

proc stageCandidate(vault: string; name: string; cert: JsonNode): string =
  let path = vault / (name & ".json")
  writeFile(path, canonicalCertificateString(cert))
  path

suite "promoteToCanonical — same-evidence new-subject-ref cache refresh (e144c5f5a)":

  test "identity axes: same evidence key with different evidenceId, different key with changed sourceHash":
    ## The exact identity axis the fix rides on: evidenceId changes the v3
    ## identity without changing journalEvidenceKey; a changed sourceHash
    ## changes both.
    let subjectV1 = "proc promoFn(x: int): int = x + 1"
    let subjectV2 = "proc promoFn(x: int): int = x + 2"
    let irHash = "irhash-promo-axis-0001"
    let certA = makeCandidateCert(irHash, "evid-subject-ref-a",
                                  computeStableSourceFingerprint(subjectV1))
    let certB = makeCandidateCert(irHash, "evid-subject-ref-b",
                                  computeStableSourceFingerprint(subjectV1))
    let certC = makeCandidateCert(irHash, "evid-subject-ref-c",
                                  computeStableSourceFingerprint(subjectV2))
    check v3IdentityFromJson(certA) != v3IdentityFromJson(certB)
    check journalEvidenceKey(certA) == journalEvidenceKey(certB)
    check journalEvidenceKey(certA) != journalEvidenceKey(certC)

  test "same evidence under a new subject ref refreshes the canonical cache":
    let sandbox = makeSandbox()
    setCurrentDir(sandbox)
    try:
      let vault = sandbox / "build" / "certificates"
      createDir(vault)
      let irHash = "irhash-promo-refresh-0001"
      let sourceHash = computeStableSourceFingerprint(
        "proc promoFn(x: int): int = x + 1")
      let certOld = makeCandidateCert(irHash, "evid-ref-old", sourceHash)
      let certNew = makeCandidateCert(irHash, "evid-ref-new", sourceHash)

      # First promotion under subject ref OLD: fresh canonical write.
      let candOld = stageCandidate(vault, irHash, certOld)
      let resOld = promoteToCanonical(candOld, candidateRoot = vault)
      check resOld.isOk()
      let canonicalPath = sandbox / "data" / "trusted" / "certificates" / (irHash & ".json")
      check fileExists(canonicalPath)
      check parseJson(readFile(canonicalPath)){"evidenceId"}.getStr("") == "evid-ref-old"

      # Re-verification after a merge: SAME function-level evidence, NEW
      # subject ref (new evidenceId → new v3 identity). Must be an idempotent
      # cache refresh, not a conflict.
      let candNew = stageCandidate(vault, irHash, certNew)
      let resNew = promoteToCanonical(candNew, candidateRoot = vault)
      check resNew.isOk()
      if resNew.isErr:
        echo "    refresh error: " & resNew.error

      # The canonical file is now the NEW candidate's projection.
      let projected = parseJson(readFile(canonicalPath))
      check projected{"evidenceId"}.getStr("") == "evid-ref-new"
      check projected{"identityDigest"}.getStr("") ==
        certNew{"identityDigest"}.getStr("")
      check readFile(canonicalPath) == canonicalCertificateString(certNew)

      # The manifest catalog was refreshed with the new projection's content hash.
      let manifest = parseJson(readFile(sandbox / "data" / "trusted" / "certificates" / "manifest.json"))
      var entry: JsonNode = nil
      for e in manifest{"entries"}.items():
        if e{"irHash"}.getStr("") == irHash:
          entry = e
      check entry != nil
      check entry{"contentHash"}.getStr("") ==
        "sha256:" & sha256Hex(canonicalCertificateString(certNew))
    finally:
      teardownSandbox(sandbox)

  test "re-promoting the already-current projection stays identity-idempotent":
    let sandbox = makeSandbox()
    setCurrentDir(sandbox)
    try:
      let vault = sandbox / "build" / "certificates"
      createDir(vault)
      let irHash = "irhash-promo-idem-0002"
      let cert = makeCandidateCert(irHash, "evid-ref-cur",
        computeStableSourceFingerprint("proc promoFn(x: int): int = x + 1"))
      let cand = stageCandidate(vault, irHash, cert)
      check promoteToCanonical(cand, candidateRoot = vault).isOk()
      let res = promoteToCanonical(cand, candidateRoot = vault)
      check res.isOk()
      check "already present" in res.value
    finally:
      teardownSandbox(sandbox)

  test "different evidence key under the same irHash is a hard conflict (fail-closed)":
    let sandbox = makeSandbox()
    setCurrentDir(sandbox)
    try:
      let vault = sandbox / "build" / "certificates"
      createDir(vault)
      let irHash = "irhash-promo-conflict-0003"
      let sourceV1 = computeStableSourceFingerprint(
        "proc promoFn(x: int): int = x + 1")
      let sourceMutated = computeStableSourceFingerprint(
        "proc promoFn(x: int): int = x * 2")
      let certOld = makeCandidateCert(irHash, "evid-ref-old", sourceV1)
      # Subject bytes changed (sourceHash) → a genuinely different evidence
      # key behind the SAME cache key (irHash).
      let certMutated = makeCandidateCert(irHash, "evid-ref-mutated", sourceMutated)
      check journalEvidenceKey(certOld) != journalEvidenceKey(certMutated)

      let candOld = stageCandidate(vault, irHash, certOld)
      check promoteToCanonical(candOld, candidateRoot = vault).isOk()
      let canonicalPath = sandbox / "data" / "trusted" / "certificates" / (irHash & ".json")
      let bytesBefore = readFile(canonicalPath)

      let candMutated = stageCandidate(vault, irHash, certMutated)
      let res = promoteToCanonical(candMutated, candidateRoot = vault)
      check res.isErr()
      if res.isErr:
        check "DIFFERENT canonical identity" in res.error
        echo "    conflict error: " & res.error

      # Fail-closed: the canonical projection is untouched.
      check readFile(canonicalPath) == bytesBefore
    finally:
      teardownSandbox(sandbox)
