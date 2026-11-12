import std/json
import std/options
import std/strutils
import std/os
import core/crypto/hash_kernel
import core/trusted/assurance_profile
import core/trusted/claim_authority
import core/trusted/solver_invocation
import core/trusted/append_store
import core/trusted/claim_store_append

proc makeClaim(claimId: string; subjectId: string; outcome: VerificationOutcomeRef): VerifiedClaim =
  VerifiedClaim(
    subjectId: subjectId,
    outcome: outcome,
    assurance: AssuranceProfile(
      specificationAuthority: true,
      translationTrust: true,
      solverEvidence: true,
      replayability: false,
      kernelChecking: false
    ),
    specificationId: "spec-1",
    semanticProfileId: "sem-1",
    obligationId: "obl-1",
    evidenceId: "ev-1",
    dependencySnapshotId: "dep-1",
    policyId: "pol-1",
    claimId: claimId
  )

proc main() =
  echo "=== append_store tests ==="
  let tmpDir = getAppDir() & "/.tmp_append_store_test"
  if dirExists(tmpDir):
    removeDir(tmpDir)
  createDir(tmpDir)

  # --- Test 1: append 2 claims → readRecords returns 2 lines; claimIdUniqueness true ---
  let storePath = tmpDir & "/claims.store"
  let claim1 = makeClaim("claim-id-1", "subject-A", clProved)
  let claim2 = makeClaim("claim-id-2", "subject-B", clDisproved)
  doAssert appendClaim(storePath, claim1), "appendClaim should succeed for claim1"
  doAssert appendClaim(storePath, claim2), "appendClaim should succeed for claim2"
  let records1 = readRecords(storePath)
  doAssert records1.len == 2, "readRecords should return 2 lines, got " & $records1.len
  doAssert records1[0].contains("claim-id-1"), "first record should contain claim-id-1"
  doAssert records1[1].contains("claim-id-2"), "second record should contain claim-id-2"
  doAssert claimIdUniqueness(records1), "claimIdUniqueness should be true for 2 unique claims"
  echo "Test 1 PASSED: append 2 claims, readRecords returns 2 lines, uniqueness true"

  # --- Test 2: append same claim again → claimIdUniqueness false ---
  let claim1Duplicate = makeClaim("claim-id-1", "subject-A", clProved)
  doAssert appendClaim(storePath, claim1Duplicate), "appendClaim should succeed for duplicate claim"
  let records2 = readRecords(storePath)
  doAssert records2.len == 3, "readRecords should return 3 lines after duplicate append"
  doAssert not claimIdUniqueness(records2), "claimIdUniqueness should be false when same claimId appears twice"
  echo "Test 2 PASSED: duplicate claimId detected, uniqueness false"

  # --- Test 3: corruption recovery ---
  let corruptPath = tmpDir & "/corrupt.store"
  writeFile(corruptPath, "line1\nline2\npartial")
  let corruptRecords = readRecords(corruptPath)
  doAssert corruptRecords.len == 2, "corrupt last line should be dropped, got " & $corruptRecords.len
  doAssert corruptRecords[0] == "line1", "first record should be line1"
  doAssert corruptRecords[1] == "line2", "second record should be line2"
  echo "Test 3 PASSED: corruption recovery drops partial last line"

  # --- Test 4: solver invocation ---
  let solverPath = tmpDir & "/solver.store"
  let smtText4 = "(assert (<= x 100))\n(check-sat)\n"
  let si = makeSolverInvocation(
    scriptDigest = "digest1",
    solverVersion = "v1",
    solverOptionsDigest = "opts1",
    semanticProfileId = "sem-1",
    encodingIdentity = "enc-1",
    solverIdentity = "z3",
    env = "",
    canonicalSourceIdentity = "",
    specificationIdentity = "",
    translationIdentityHash = "",
    smtScriptDigest = sha256Hex(smtText4),
    smtScript = smtText4
  )
  doAssert appendSolverInvocation(solverPath, si), "appendSolverInvocation should succeed"
  let solverRecords = readRecords(solverPath)
  doAssert solverRecords.len == 1, "should have 1 solver record"
  doAssert solverRecords[0].contains(si.replayKey), "record should contain replayKey"
  let siParsed = parseJson(solverRecords[0])
  doAssert siParsed.hasKey("smtScript"), "record must have smtScript key"
  doAssert siParsed["smtScript"].getStr() == smtText4,
    "record must preserve smtScript text"
  echo "Test 4 PASSED: solver invocation appended with smtScript, replayKey found in records"

  # --- Test 4b: appendSolverInvocation round-trip preserves smtScript text ---
  let roundTripPath = tmpDir & "/solver_roundtrip.store"
  let smtText4b = "(set-logic QF_BV)\n(assert (bvult x (bv #x0000000000000064)))\n(check-sat)\n"
  let si4b = makeSolverInvocation(
    scriptDigest = "digest-rt-1",
    solverVersion = "z3-4.8.8",
    solverOptionsDigest = "opts-rt-1",
    semanticProfileId = "semprof-rt-1",
    encodingIdentity = "axiom-ir-smt-v1",
    smtScriptDigest = sha256Hex(smtText4b),
    smtScript = smtText4b
  )
  doAssert appendSolverInvocation(roundTripPath, si4b), "round-trip append should succeed"
  let rtRecords = readRecords(roundTripPath)
  doAssert rtRecords.len == 1, "should have 1 round-trip record"
  let rtParsed = parseJson(rtRecords[0])
  doAssert rtParsed.hasKey("smtScript"), "round-trip record must have smtScript key"
  doAssert rtParsed["smtScript"].getStr() == smtText4b,
    "round-trip must preserve smtScript text byte-for-byte"
  doAssert rtParsed["smtScriptDigest"].getStr() == sha256Hex(smtText4b),
    "round-trip must preserve smtScriptDigest"
  echo "Test 4b PASSED: appendSolverInvocation round-trip preserves smtScript text"

  # --- Test 4c: solverBinaryDigest survives the ledger ---
  # A record that names its option set but not its executable is a
  # self-describing claim about a solver nobody can identify; the identity is
  # lost the moment the record reaches the append-only store.
  let binaryDigestPath = tmpDir & "/solver_binary.store"
  let binaryDigest = sha256Hex("pretend-z3-elf-bytes")
  let si4c = makeSolverInvocation(
    scriptDigest = "digest-rt-2",
    solverVersion = "z3-4.8.8",
    solverOptionsDigest = deterministicSolverOptionsDigest(),
    semanticProfileId = "semprof-rt-2",
    encodingIdentity = "axiom-ir-smt-v1",
    solverBinaryDigest = binaryDigest,
    smtScriptDigest = sha256Hex(smtText4b),
    smtScript = smtText4b
  )
  doAssert appendSolverInvocation(binaryDigestPath, si4c),
    "round-trip append should succeed"
  let binRecords = readRecords(binaryDigestPath)
  doAssert binRecords.len == 1, "should have 1 record"
  let binParsed = parseJson(binRecords[0])
  doAssert binParsed.hasKey("solverBinaryDigest"),
    "the record must carry the solver binary digest"
  doAssert binParsed["solverBinaryDigest"].getStr() == binaryDigest,
    "the digest must survive byte-for-byte"
  let decoded = solverInvocationFromJson(binParsed)
  doAssert decoded.isSome, "the record must decode back to a SolverInvocation"
  doAssert decoded.get().solverBinaryDigest == binaryDigest,
    "the read path must recover the solver binary digest"
  doAssert decoded.get().solverOptionsDigest == deterministicSolverOptionsDigest(),
    "the read path must recover the recorded option digest unchanged"
  doAssert decoded.get().replayKey == si4c.replayKey,
    "the read path must not perturb the replay key"
  doAssert solverInvocationFromJson(newJString("not an object")).isNone,
    "a line that does not decode is refused rather than defaulted"
  echo "Test 4c PASSED: solverBinaryDigest survives append -> read intact"

  # --- Test 5: determinism ---
  let storePath2 = tmpDir & "/claims2.store"
  let claimA = makeClaim("claim-det-1", "subject-X", clProved)
  doAssert appendClaim(storePath2, claimA), "first append should succeed"
  let recordsBefore = readRecords(storePath2)
  doAssert recordsBefore.len == 1, "should have 1 record"
  let line1 = recordsBefore[0]
  doAssert appendClaim(storePath2, claimA), "second append of same claim should succeed"
  let recordsAfter = readRecords(storePath2)
  doAssert recordsAfter.len == 2, "should have 2 records"
  let line2 = recordsAfter[1]
  doAssert line1 == line2, "determinism: same claim should produce same serialized line"
  echo "Test 5 PASSED: determinism verified, same inputs produce same serialized line"

  # --- Cleanup ---
  removeDir(tmpDir)

  echo "=== All append_store tests PASSED ==="

main()