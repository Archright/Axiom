## tests/unit/test_completeness_binding.nim
## CompletenessBinding — strict admission wrapper unit tests.
##
## Covers (each named for the failure mode it pins):
##   - valid load: save → load round-trip with matching current source returns
##     the binding with every field intact (no defaults anywhere).
##   - stale source: a comment-only module edit changes subjectModuleSha256 →
##     none, even though the IR (flavor ② and ③) is unchanged.
##   - foreign module: different sourceIdentity → none.
##   - payload tamper: unaccompanied mutation of the stored payload → digest
##     recompute mismatch → none.
##   - missing payload: payload key absent → none (no default projection).
##   - profile mismatch: semanticProfileId ≠ current → none.
##   - toolchain mismatch: toolchainFingerprint ≠ current → none.
##   - key mismatch: artifact present under the requested anchor but stored
##     evidenceKey differs → none.
##   - unknown schema: schemaVersion not the constant → none (even with a
##     self-consistent recomputed digest).
##   - strict parse extras: wrong JSON types, unknown keys, missing keys → none.
##   - legacy isolation: a legacy 5-field artifact is never admitted through
##     the binding loader; the binding loader never feeds the legacy loader.
##   - save refusals: wrong schemaVersion / digest incoherence / empty anchor.
##   - determinism: identical bindings → byte-identical canonical artifacts.
##
## Run: nim c --hints:off --path:src -o:tmp/test_completeness_binding -r tests/unit/test_completeness_binding.nim
## Custom main() pattern per tests/unit/test_wpj4_ladder.nim precedent.

import std/[os, json, options, strutils, tempfiles]
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/semantic_fact_types
import core/trusted/completeness_binding
import core/trusted/semantic_profile
import core/deterministic_cas_key
import core/crypto/hash_kernel
import infrastructure/evidence_artifact_io

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
  let stateDir = createTempDir("axiom_oc_binding_test_", "")
  putEnv("AXIOM_STATE_DIR", stateDir)

  # ── Fixture: subject funcDef, source bytes, identity fields ───────
  let funcDef = IRFuncDef(
    name: "ocSubject", params: @[], retType: irTypeBitVec64(),
    body: irLet("n", irLit(32), irVar("n", irTypeBitVec64()),
                isCompileTime = true),
    isRecursive: false)

  # Flavor ③ — the materializer save key (external_ir_materializer:484).
  let casKey = computeDeterministicCasKey(serializeIRFuncDef(funcDef))
  # Flavor ② — the canonicalized IR digest.
  let canonicalDigest = computeIrDigest(funcDef)
  doAssert casKey != canonicalDigest, "fixture flavors must differ to be distinguishable"

  let fixtureSource = "proc ocSubject(): int =\n  let n = 32\n  result = n\n"
  let moduleSha = sha256Hex(fixtureSource)
  let sourceIdentity = "src/examples/oc_subject.nim"
  let toolchainFp = sha256Hex("nim-2.2.10|z3-4.13.3|lean-4.13.3")

  let evidence = CompletenessEvidence(
    translationLossFree: true,
    bindingUniverseComplete: true,
    opaqueExpansionStatus: "none",
    sourceBindingCount: 3,
    irBindingCount: 3)

  let binding = makeCompletenessBinding(
    evidenceKey = casKey,
    irDigest = casKey,
    irDigestCanonical = canonicalDigest,
    sourceIdentity = sourceIdentity,
    subjectModuleSha256 = moduleSha,
    semanticProfileId = SemanticProfileV1Hash,
    toolchainFingerprint = toolchainFp,
    payload = evidence)

  proc loadCurrent(key: string; srcIdentity, modSha, profileId, fp: string):
      Option[CompletenessBinding] =
    loadCompletenessBinding(key, srcIdentity, modSha, profileId, fp)

  proc loadMatchingCurrent(key: string): Option[CompletenessBinding] =
    loadCurrent(key, sourceIdentity, moduleSha, SemanticProfileV1Hash, toolchainFp)

  proc storedJson(key: string): JsonNode =
    parseJson(readFile(completenessBindingCachePath(key)))

  # ── Save: success, atomicity residue, canonical form ──────────────
  echo "=== saveCompletenessBinding ==="

  check "save returns true and lands the artifact at the anchor path":
    doAssert saveCompletenessBinding(binding)
    doAssert fileExists(completenessBindingCachePath(casKey))

  check "atomic save leaves no temp residue":
    var residue = false
    for f in walkDir(joinPath(stateDir, ".axiom", "cache", "evidence")):
      if f.path.contains(".tmp."):
        residue = true
    doAssert not residue

  check "canonical JSON: fixed key order, schemaVersion first":
    let raw = readFile(completenessBindingCachePath(casKey))
    doAssert raw.startsWith("{\"schemaVersion\":\"completeness-binding-v1\",\"evidenceKey\":\"" & casKey & "\"")

  check "determinism: same binding → byte-identical artifact":
    let before = readFile(completenessBindingCachePath(casKey))
    doAssert saveCompletenessBinding(binding)
    doAssert readFile(completenessBindingCachePath(casKey)) == before

  # ── Valid load (round-trip, every field intact) ───────────────────
  echo "=== valid load ==="

  check "valid load returns the binding with all fields intact":
    let loaded = loadMatchingCurrent(casKey)
    doAssert loaded.isSome
    let b = loaded.get
    doAssert b.schemaVersion == CompletenessBindingSchemaVersion
    doAssert b.evidenceKey == casKey
    doAssert b.irDigest == casKey
    doAssert b.irDigestCanonical == canonicalDigest
    doAssert b.sourceIdentity == sourceIdentity
    doAssert b.subjectModuleSha256 == moduleSha
    doAssert b.semanticProfileId == SemanticProfileV1Hash
    doAssert b.toolchainFingerprint == toolchainFp
    doAssert b.evidenceDigest == binding.evidenceDigest
    doAssert b.payload == evidence

  # ── Stale source: comment-only edit ───────────────────────────────
  echo "=== stale source (comment-only change) ==="

  check "comment-only source edit → none (module sha changed, IR unchanged)":
    let staleSha = sha256Hex(fixtureSource & "\n# a comment, IR untouched\n")
    doAssert staleSha != moduleSha
    doAssert not loadCurrent(casKey, sourceIdentity, staleSha,
      SemanticProfileV1Hash, toolchainFp).isSome

  # ── Foreign module ────────────────────────────────────────────────
  echo "=== foreign module ==="

  check "foreign sourceIdentity → none":
    doAssert not loadCurrent(casKey, "src/other/foreign.nim", moduleSha,
      SemanticProfileV1Hash, toolchainFp).isSome

  check "foreign module: same sha, different identity → none":
    doAssert not loadCurrent(casKey, "src/examples/impostor.nim", moduleSha,
      SemanticProfileV1Hash, toolchainFp).isSome

  # ── Payload tamper (unaccompanied mutation) ───────────────────────
  echo "=== payload tamper ==="

  check "tampered payload with stale digest → none":
    var j = storedJson(casKey)
    j["payload"]["sourceBindingCount"] = %99
    writeFile(completenessBindingCachePath(casKey), $j)
    doAssert not loadMatchingCurrent(casKey).isSome

  check "tampered evidenceDigest field → none":
    doAssert saveCompletenessBinding(binding)  # restore clean state
    var j = storedJson(casKey)
    j["evidenceDigest"] = %sha256Hex("forged")
    writeFile(completenessBindingCachePath(casKey), $j)
    doAssert not loadMatchingCurrent(casKey).isSome

  # ── Missing payload ───────────────────────────────────────────────
  echo "=== missing payload ==="

  check "payload key absent → none (no default projection)":
    var j = storedJson(casKey)
    j.delete("payload")
    writeFile(completenessBindingCachePath(casKey), $j)
    doAssert not loadMatchingCurrent(casKey).isSome

  # ── Profile / toolchain mismatch ──────────────────────────────────
  echo "=== profile & toolchain mismatch ==="

  doAssert saveCompletenessBinding(binding)  # restore clean state

  check "semanticProfileId mismatch → none":
    let otherProfile = sha256Hex("other-config-profile")
    doAssert otherProfile != SemanticProfileV1Hash
    doAssert not loadCurrent(casKey, sourceIdentity, moduleSha,
      otherProfile, toolchainFp).isSome

  check "toolchainFingerprint mismatch → none":
    let otherFp = sha256Hex("nim-9.9.9|z3-0.0.0|lean-0.0.0")
    doAssert otherFp != toolchainFp
    doAssert not loadCurrent(casKey, sourceIdentity, moduleSha,
      SemanticProfileV1Hash, otherFp).isSome

  # ── Key mismatch ──────────────────────────────────────────────────
  echo "=== key mismatch ==="

  check "artifact present at requested key but stored evidenceKey differs → none":
    let otherKey = computeDeterministicCasKey(serializeIRFuncDef(
      IRFuncDef(name: "another", params: @[], retType: irTypeBitVec64(),
                body: irLit(1), isRecursive: false)))
    doAssert otherKey != casKey
    writeFile(completenessBindingCachePath(otherKey),
              readFile(completenessBindingCachePath(casKey)))
    doAssert not loadMatchingCurrent(otherKey).isSome

  check "absent anchor → none":
    doAssert not loadMatchingCurrent(sha256Hex("no-such-anchor")).isSome

  # ── Unknown schema version ────────────────────────────────────────
  echo "=== unknown schema ==="

  check "unknown schemaVersion → none even with self-consistent digest":
    var j = storedJson(casKey)
    j["schemaVersion"] = %"completeness-binding-v2"
    var forged = CompletenessBinding(
      schemaVersion: "completeness-binding-v2",
      evidenceKey: j["evidenceKey"].getStr,
      irDigest: j["irDigest"].getStr,
      irDigestCanonical: j["irDigestCanonical"].getStr,
      sourceIdentity: j["sourceIdentity"].getStr,
      subjectModuleSha256: j["subjectModuleSha256"].getStr,
      semanticProfileId: j["semanticProfileId"].getStr,
      toolchainFingerprint: j["toolchainFingerprint"].getStr,
      payload: evidence,
      evidenceDigest: "")
    forged.evidenceDigest = computeCompletenessBindingDigest(forged)
    j["evidenceDigest"] = %forged.evidenceDigest
    writeFile(completenessBindingCachePath(casKey), $j)
    doAssert not loadMatchingCurrent(casKey).isSome

  # ── Strict parse: types and unknown keys ──────────────────────────
  echo "=== strict parse ==="

  proc restoreAndMutate(mutator: proc (j: JsonNode)) =
    doAssert saveCompletenessBinding(binding)
    var j = storedJson(casKey)
    mutator(j)
    writeFile(completenessBindingCachePath(casKey), $j)

  check "wrong scalar type (bool as string) → none":
    restoreAndMutate(proc (j: JsonNode) = j["toolchainFingerprint"] = %true)
    doAssert not loadMatchingCurrent(casKey).isSome

  check "wrong payload field type (count as float) → none":
    restoreAndMutate(proc (j: JsonNode) = j["payload"]["irBindingCount"] = %3.5)
    doAssert not loadMatchingCurrent(casKey).isSome

  check "unknown top-level key → none":
    restoreAndMutate(proc (j: JsonNode) = j["extra"] = %"smuggled")
    doAssert not loadMatchingCurrent(casKey).isSome

  check "unknown payload key → none":
    restoreAndMutate(proc (j: JsonNode) = j["payload"]["note"] = %"x")
    doAssert not loadMatchingCurrent(casKey).isSome

  check "missing top-level key → none":
    restoreAndMutate(proc (j: JsonNode) = j.delete("irDigestCanonical"))
    doAssert not loadMatchingCurrent(casKey).isSome

  check "non-JSON bytes → none":
    doAssert saveCompletenessBinding(binding)
    writeFile(completenessBindingCachePath(casKey), "{{{not json")
    doAssert not loadMatchingCurrent(casKey).isSome

  # ── Legacy artifact isolation ─────────────────────────────────────
  echo "=== legacy isolation ==="

  check "legacy 5-field artifact at the binding path → none":
    doAssert saveCompletenessBinding(binding)  # restore clean state
    let legacy = %* {
      "translationLossFree": true,
      "bindingUniverseComplete": true,
      "opaqueExpansionStatus": "none",
      "sourceBindingCount": 3,
      "irBindingCount": 3
    }
    writeFile(completenessBindingCachePath(casKey), $legacy)
    doAssert not loadMatchingCurrent(casKey).isSome

  check "legacy loader still serves the legacy artifact (compat preserved)":
    saveEvidenceArtifact(casKey, evidence)
    let legacyLoaded = loadEvidenceArtifact(casKey)
    doAssert legacyLoaded.isSome
    doAssert legacyLoaded.get == evidence

  check "namespace isolation: binding save does not disturb the legacy artifact":
    let legacyBefore = readFile(evidenceCacheDir(casKey))
    doAssert saveCompletenessBinding(binding)
    # The legacy loader reads <key>.json; the binding lives at <key>.binding.json.
    doAssert readFile(evidenceCacheDir(casKey)) == legacyBefore
    doAssert loadEvidenceArtifact(casKey).isSome
    doAssert loadEvidenceArtifact(casKey).get == evidence
    doAssert loadMatchingCurrent(casKey).isSome

  # ── Save refusals (fail-closed write boundary) ────────────────────
  echo "=== save refusals ==="

  check "save refuses wrong schemaVersion":
    var bad = binding
    bad.schemaVersion = "completeness-binding-v0"
    doAssert not saveCompletenessBinding(bad)

  check "save refuses digest-incoherent binding":
    var bad = binding
    bad.evidenceDigest = sha256Hex("incoherent")
    doAssert not saveCompletenessBinding(bad)

  check "save refuses empty anchor":
    var bad = makeCompletenessBinding("", casKey, canonicalDigest,
      sourceIdentity, moduleSha, SemanticProfileV1Hash, toolchainFp, evidence)
    doAssert not saveCompletenessBinding(bad)

  check "save refuses non-hex identity field":
    var bad = makeCompletenessBinding(casKey, casKey, canonicalDigest,
      sourceIdentity, "not-a-sha256", SemanticProfileV1Hash, toolchainFp, evidence)
    doAssert not saveCompletenessBinding(bad)

  # ── Restore clean state and summarize ─────────────────────────────
  doAssert saveCompletenessBinding(binding)
  try:
    removeDir(stateDir)
  except CatchableError:
    discard  # axiom:best-effort(temp state cleanup; assertions already recorded)

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

when isMainModule:
  main()
