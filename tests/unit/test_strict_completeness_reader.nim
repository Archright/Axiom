## tests/unit/test_strict_completeness_reader.nim
## Phase 1A — strict-first CompletenessBinding reader + authenticated strict
## evidence identity negative controls.
##
## Covers (each named for the failure mode it pins):
##   - strict round-trip: dual-write → measureCompletenessRecordDigest returns
##     the ref (evidenceKey/evidenceDigest/payloadDigest) and NEVER consults
##     the legacy artifact (payload digest equals the legacy serialization of
##     the SAME payload — the bound-obligation representation is compatible).
##   - generation marker: a strict-generation anchor (marker present) with a
##     missing/corrupt/stale binding is UNKNOWN in BOTH env modes — the legacy
##     artifact is never a fallback. A pre-generation legacy-only anchor (no
##     marker) still serves the legacy ref when AXIOM_EVIDENCE_STRICT is unset.
##   - fail-closed: strict artifact absent + AXIOM_EVIDENCE_STRICT set → none,
##     even though the legacy artifact exists.
##   - tamper EXTRA fields (sourceIdentity / subjectModuleSha256 /
##     semanticProfileId / irDigestCanonical / toolchainFingerprint) → strict
##     load refused; a marked anchor returns none in both env modes.
##   - two-anchor search: pre-synthesis anchor threaded → strict binding found
##     at the pre-synthesis key.
##
## Run: nim c --hints:off --path:src -o:tmp/test_strict_completeness_reader -r tests/unit/test_strict_completeness_reader.nim

import std/[os, json, options, strutils, tempfiles]
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/semantic_fact_types
import core/trusted/completeness_binding
import core/trusted/semantic_profile
import core/deterministic_cas_key
import core/crypto/hash_kernel
import infrastructure/evidence_artifact_io
import infrastructure/external_ir_materializer
import verification/obligation/canonical_verification

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()
      except Defect:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  # ── Isolated state dir (AXIOM_STATE_DIR is read per call) ─────────
  let stateDir = createTempDir("axiom_strict_reader_test_", "")
  putEnv("AXIOM_STATE_DIR", stateDir)
  putEnv("AXIOM_EVIDENCE_STRICT", "")

  # ── Fixture: subject funcDef + a real path-resolved subject module ─
  # tests/golden/identity_postcondition.nim is the repo fixture whose bytes
  # the capture and the reader both digest; the funcDef is its IR mirror.
  let sourcePath = "tests/golden/identity_postcondition.nim"
  let moduleBytes = readFile(sourcePath)
  let fd = IRFuncDef(
    name: "identityPostcondition",
    params: @[IRFuncParam(name: "x", ty: irTypeBitVec64())],
    retType: irTypeBitVec64(),
    body: irVar("x", irTypeBitVec64()),
    isRecursive: false)

  let key = computeDeterministicCasKey(serializeIRFuncDef(fd))
  let canonicalDigest = computeIrDigest(fd)
  let evidence = CompletenessEvidence(
    translationLossFree: true,
    bindingUniverseComplete: true,
    opaqueExpansionStatus: "none",
    sourceBindingCount: 1,
    irBindingCount: 1)
  let legacyDigest = sha256Hex($evidenceToJson(evidence))

  # The producer dual-write (same entry point the materializer uses).
  let capture = measureCompletenessSourceCapture("", sourcePath, moduleBytes,
    contentCarried = false)
  check "capture identity is measurable for the repo fixture":
    doAssert capture.sourceIdentity.len == 64
    doAssert capture.moduleSha256 == sha256Hex(moduleBytes)

  check "dual-write lands the strict sibling and the generation marker":
    doAssert saveCompletenessEvidenceDual(key, fd, capture, evidence)
    doAssert fileExists(completenessBindingCachePath(key))
    doAssert fileExists(strictGenerationMarkerPath(key))

  proc storedJson(): JsonNode =
    parseJson(readFile(completenessBindingCachePath(key)))

  proc restore() =
    doAssert saveCompletenessEvidenceDual(key, fd, capture, evidence)

  # ── Strict round-trip ─────────────────────────────────────────────
  echo "=== strict round-trip ==="

  check "strict hit returns the authenticated ref":
    let refOpt = measureCompletenessRecordDigest(fd, "",
      capture.sourceIdentity, capture.moduleSha256)
    doAssert refOpt.isSome
    let r = refOpt.get
    doAssert r.evidenceKey == key
    doAssert r.evidenceDigest == storedJson()["evidenceDigest"].getStr
    doAssert r.evidenceDigest.len == 64

  check "payload digest compatibility: strict ref payloadDigest == legacy 5-field digest":
    let refOpt = measureCompletenessRecordDigest(fd, "",
      capture.sourceIdentity, capture.moduleSha256)
    doAssert refOpt.get.payloadDigest == legacyDigest

  check "strict hit does NOT consult the legacy artifact (remove it, strict still hits)":
    removeFile(evidenceCacheDir(key))
    let refOpt = measureCompletenessRecordDigest(fd, "",
      capture.sourceIdentity, capture.moduleSha256)
    doAssert refOpt.isSome
    doAssert refOpt.get.evidenceKey == key
    restore()  # binding back
    saveEvidenceArtifact(key, evidence)  # legacy artifact back for later checks

  # ── Strict-generation marker: no legacy fallback ─────────────────
  echo "=== strict-generation marker (legacy fallback refused) ==="

  check "marked anchor + binding removed + env unset → none (no legacy fallback)":
    removeFile(completenessBindingCachePath(key))
    let refOpt = measureCompletenessRecordDigest(fd, "",
      capture.sourceIdentity, capture.moduleSha256)
    doAssert refOpt.isNone
    restore()

  check "pre-generation legacy-only anchor (no marker) + env unset → legacy ref":
    # Simulate a record produced before the strict generation: no binding and
    # no generation tag, only the legacy 5-field artifact.
    removeFile(completenessBindingCachePath(key))
    removeFile(strictGenerationMarkerPath(key))
    let refOpt = measureCompletenessRecordDigest(fd, "",
      capture.sourceIdentity, capture.moduleSha256)
    doAssert refOpt.isSome
    let r = refOpt.get
    doAssert r.evidenceKey == ""
    doAssert r.evidenceDigest == ""
    doAssert r.payloadDigest == legacyDigest
    restore()

  # ── Fail-closed under AXIOM_EVIDENCE_STRICT ───────────────────────
  echo "=== fail-closed (AXIOM_EVIDENCE_STRICT=1) ==="

  check "strict artifact absent + env set → none, legacy exists notwithstanding":
    removeFile(completenessBindingCachePath(key))
    putEnv("AXIOM_EVIDENCE_STRICT", "1")
    let refOpt = measureCompletenessRecordDigest(fd, "",
      capture.sourceIdentity, capture.moduleSha256)
    doAssert refOpt.isNone
    putEnv("AXIOM_EVIDENCE_STRICT", "")
    restore()

  check "tampered strict artifact + env set → none (never the legacy behind it)":
    var j = storedJson()
    j["payload"]["translationLossFree"] = %false
    writeFile(completenessBindingCachePath(key), $j)
    putEnv("AXIOM_EVIDENCE_STRICT", "1")
    let refOpt = measureCompletenessRecordDigest(fd, "",
      capture.sourceIdentity, capture.moduleSha256)
    doAssert refOpt.isNone
    putEnv("AXIOM_EVIDENCE_STRICT", "")
    restore()

  # ── Tamper each EXTRA field ───────────────────────────────────────
  echo "=== extra-field tamper (never counted as strict) ==="

  proc restoreAndMutate(mutator: proc (j: JsonNode)) =
    restore()
    var j = storedJson()
    mutator(j)
    writeFile(completenessBindingCachePath(key), $j)

  template tamperExtraField(name: string; mutator: proc (j: JsonNode)) =
    check name & " → strict refused; marked anchor never degrades to legacy":
      restoreAndMutate(mutator)
      # The generation marker stays: the tampered binding is refused and the
      # legacy artifact behind it is NOT servable — in either env mode.
      for strictEnv in ["1", ""]:
        putEnv("AXIOM_EVIDENCE_STRICT", strictEnv)
        doAssert measureCompletenessRecordDigest(fd, "",
          capture.sourceIdentity, capture.moduleSha256).isNone
      putEnv("AXIOM_EVIDENCE_STRICT", "")

  tamperExtraField "tampered sourceIdentity",
    proc (j: JsonNode) = j["sourceIdentity"] = %sha256Hex("forged-source-identity")
  tamperExtraField "tampered subjectModuleSha256",
    proc (j: JsonNode) = j["subjectModuleSha256"] = %sha256Hex("forged-module-bytes")
  tamperExtraField "tampered semanticProfileId",
    proc (j: JsonNode) = j["semanticProfileId"] = %sha256Hex("forged-profile")
  tamperExtraField "tampered irDigestCanonical",
    proc (j: JsonNode) = j["irDigestCanonical"] = %sha256Hex("forged-canonical-ir")
  tamperExtraField "tampered toolchainFingerprint",
    proc (j: JsonNode) = j["toolchainFingerprint"] = %sha256Hex("forged-toolchain")

  # ── Two-anchor search (pre-synthesis anchor threaded) ─────────────
  echo "=== two-anchor search ==="

  check "strict binding found at the threaded pre-synthesis anchor":
    restore()
    # Binding lives at `key`; the reader searches preSynthesis first.
    let refOpt = measureCompletenessRecordDigest(fd, key,
      capture.sourceIdentity, capture.moduleSha256)
    doAssert refOpt.isSome
    doAssert refOpt.get.evidenceKey == key

  check "wrong source identity → none in either env mode (marked anchor)":
    restore()
    saveEvidenceArtifact(key, evidence)
    for strictEnv in ["1", ""]:
      putEnv("AXIOM_EVIDENCE_STRICT", strictEnv)
      doAssert measureCompletenessRecordDigest(fd, "",
        "foreign-source-identity", capture.moduleSha256).isNone
    putEnv("AXIOM_EVIDENCE_STRICT", "")

  # ── Cleanup ───────────────────────────────────────────────────────
  try:
    removeDir(stateDir)
  except CatchableError:
    discard  # axiom:best-effort(temp state cleanup; assertions already recorded)

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()
