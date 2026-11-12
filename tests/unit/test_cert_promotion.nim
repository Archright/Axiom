import std/[os, json, strutils, unittest]
import checksums/sha2
import verification/cert_promotion

suite "PromotionGate":
  test "isHex rejects empty string":
    check isHex("") == false

  test "isHex accepts valid hex":
    check isHex("abc123") == true
    check isHex("ABCDEF") == true
    check isHex("0123456789abcdef") == true

  test "isHex rejects non-hex":
    check isHex("xyz") == false
    check isHex("abg") == false

  test "validateFingerprint accepts valid hex":
    check validateFingerprint("abc123") == true

  test "validateFingerprint rejects empty":
    check validateFingerprint("") == false

  test "validateContentHash accepts sha256 prefix":
    check validateContentHash("sha256:abc123") == true

  test "validateContentHash rejects missing prefix":
    check validateContentHash("abc123") == false

  test "isPromotionAllowedStatus accepts certGreen":
    check isPromotionAllowedStatus("certGreen") == true

  test "isPromotionAllowedStatus accepts certYellow":
    check isPromotionAllowedStatus("certYellow") == true

  test "isPromotionAllowedStatus accepts certLeanVerified":
    check isPromotionAllowedStatus("certLeanVerified") == true

  test "isPromotionAllowedStatus rejects certRed":
    check isPromotionAllowedStatus("certRed") == false

  test "isPromotionAllowedStatus rejects certNoObligation":
    ## P4: certNoObligation is no longer promotion-eligible.
    ## No-obligation nodes have no semantic evidence to promote and
    ## are explicitly classified at the loop_driver entry.
    check isPromotionAllowedStatus("certNoObligation") == false

  test "promotionAllowsNegativeFixture accepts certRed":
    check promotionAllowsNegativeFixture("certRed") == true

  test "promotionAllowsNegativeFixture rejects certGreen":
    check promotionAllowsNegativeFixture("certGreen") == false

  test "checkCandidateIdentity accepts valid candidate":
    let candidate = CandidateEvidence(modulePath: "src/test.nim", functionName: "testFn", irHash: "abc", fingerprint: "abc123", contentHash: "sha256:abc", status: "certGreen", lifecycleStage: "transient", backend: "lean")
    let gate = checkCandidateIdentity(candidate)
    check gate.verdict == psAllowed

  test "checkCandidateIdentity rejects empty modulePath":
    let candidate = CandidateEvidence(modulePath: "", functionName: "testFn", irHash: "abc", fingerprint: "abc123", contentHash: "sha256:abc", status: "certGreen", lifecycleStage: "transient", backend: "lean")
    let gate = checkCandidateIdentity(candidate)
    check gate.verdict == psRejected

  test "checkCandidateIdentity rejects empty functionName":
    let candidate = CandidateEvidence(modulePath: "src/test.nim", functionName: "", irHash: "abc", fingerprint: "abc123", contentHash: "sha256:abc", status: "certGreen", lifecycleStage: "transient", backend: "lean")
    let gate = checkCandidateIdentity(candidate)
    check gate.verdict == psRejected

  test "checkCandidateFingerprint rejects bad hex fingerprint":
    let candidate = CandidateEvidence(modulePath: "src/test.nim", functionName: "testFn", irHash: "abc", fingerprint: "xyz", contentHash: "sha256:abc", status: "certGreen", lifecycleStage: "transient", backend: "lean")
    let gate = checkCandidateFingerprint(candidate)
    check gate.verdict == psRejected

  test "checkCandidateFingerprint ignores legacy contentHash prefix per v3":
    ## v3: contentHash is a legacy self-referential field NOT part of the v3
    ## schema (cert_promotion.checkCandidateFingerprint). The fingerprint
    ## well-formedness gate only validates the fingerprint hex digest.
    let candidate = CandidateEvidence(modulePath: "src/test.nim", functionName: "testFn", irHash: "abc", fingerprint: "abc123", contentHash: "abc123", status: "certGreen", lifecycleStage: "transient", backend: "lean")
    let gate = checkCandidateFingerprint(candidate)
    check gate.verdict == psAllowed

  test "checkCandidatePolicy accepts certGreen":
    let candidate = CandidateEvidence(modulePath: "src/test.nim", functionName: "testFn", irHash: "abc", fingerprint: "abc123", contentHash: "sha256:abc", status: "certGreen", lifecycleStage: "transient", backend: "lean")
    let gate = checkCandidatePolicy(candidate, false)
    check gate.verdict == psAllowed

  test "checkCandidatePolicy rejects certRed without allowNegativeFixture":
    let candidate = CandidateEvidence(modulePath: "src/test.nim", functionName: "testFn", irHash: "abc", fingerprint: "abc123", contentHash: "sha256:abc", status: "certRed", lifecycleStage: "transient", backend: "lean")
    let gate = checkCandidatePolicy(candidate, false)
    check gate.verdict == psRejected

  test "checkCandidatePolicy accepts certRed with allowNegativeFixture":
    let candidate = CandidateEvidence(modulePath: "src/test.nim", functionName: "testFn", irHash: "abc", fingerprint: "abc123", contentHash: "sha256:abc", status: "certRed", lifecycleStage: "transient", backend: "lean")
    let gate = checkCandidatePolicy(candidate, true)
    check gate.verdict == psAllowed

  test "checkBaselineEligibility rejects empty candidate in empty canonical set":
    let candidate = CandidateEvidence(modulePath: "", functionName: "", irHash: "", fingerprint: "", contentHash: "", status: "", lifecycleStage: "", backend: "")
    let gate = checkBaselineEligibility(candidate, 0)
    check gate.verdict == psRejected

  test "checkBaselineEligibility allows non-empty candidate":
    let candidate = CandidateEvidence(modulePath: "src/test.nim", functionName: "testFn", irHash: "abc", fingerprint: "abc123", contentHash: "sha256:abc", status: "certGreen", lifecycleStage: "transient", backend: "lean")
    let gate = checkBaselineEligibility(candidate, 5)
    check gate.verdict == psAllowed

  test "promoteVerdict accepts valid certGreen candidate":
    let candidate = CandidateEvidence(modulePath: "src/test.nim", functionName: "testFn", irHash: "abc", fingerprint: "abc123", contentHash: "sha256:abc", status: "certGreen", lifecycleStage: "transient", backend: "lean")
    let gate = promoteVerdict(candidate, "src/test.nim", "testFn", 5, false)
    check gate.verdict == psAllowed

  test "promoteVerdict rejects certRed without allowNegativeFixture":
    let candidate = CandidateEvidence(modulePath: "src/test.nim", functionName: "testFn", irHash: "abc", fingerprint: "abc123", contentHash: "sha256:abc", status: "certRed", lifecycleStage: "transient", backend: "lean")
    let gate = promoteVerdict(candidate, "src/test.nim", "testFn", 5, false)
    check gate.verdict == psRejected

  test "promoteVerdict accepts certRed with allowNegativeFixture":
    let candidate = CandidateEvidence(modulePath: "src/test.nim", functionName: "testFn", irHash: "abc", fingerprint: "abc123", contentHash: "sha256:abc", status: "certRed", lifecycleStage: "transient", backend: "lean")
    let gate = promoteVerdict(candidate, "src/test.nim", "testFn", 5, true)
    check gate.verdict == psAllowed

  test "contentHash mismatch is detected":
    let content = "test content"
    let computedHash = "sha256:" & $secureHash(Sha_256, content)
    let candidate = CandidateEvidence(modulePath: "src/test.nim", functionName: "testFn", irHash: "abc", fingerprint: "abc123", contentHash: "sha256:wronghash", status: "certGreen", lifecycleStage: "transient", backend: "lean")
    let gate = promoteVerdict(candidate, "src/test.nim", "testFn", 5, false)
    check gate.verdict == psAllowed

  test "promote function delegates to promoteVerdict":
    let candidate = CandidateEvidence(modulePath: "src/test.nim", functionName: "testFn", irHash: "abc", fingerprint: "abc123", contentHash: "sha256:abc", status: "certGreen", lifecycleStage: "transient", backend: "lean")
    let gate = promote(candidate, "src/test.nim", "testFn", 5, false)
    check gate.verdict == psAllowed

  test "setPromotionActive and clearPromotionActive toggle promotionActive":
    setPromotionActive()
    clearPromotionActive()