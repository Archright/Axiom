import std/[unittest, strutils, hashes]
import gate/baseline_transition

suite "baseline_transition - classifyChange":

  test "same claim-set hash → tkImprovement":
    let t = BaselineTransitionInput(
      oldClaimPolicyVersion: "v1",
      newClaimPolicyVersion: "v1",
      oldClaimSetHash: "abc123",
      newClaimSetHash: "abc123",
      oldVkdNum: 5,
      newVkdNum: 5,
      policyDrift: false
    )
    check classifyChange(t) == tkImprovement

  test "policy version changed → tkMigration":
    let t = BaselineTransitionInput(
      oldClaimPolicyVersion: "v1",
      newClaimPolicyVersion: "v2",
      oldClaimSetHash: "abc123",
      newClaimSetHash: "def456",
      oldVkdNum: 5,
      newVkdNum: 4,
      policyDrift: false
    )
    check classifyChange(t) == tkMigration

  test "vkd down + same claims (relabel) → tkReclassification":
    let t = BaselineTransitionInput(
      oldClaimPolicyVersion: "v1",
      newClaimPolicyVersion: "v1",
      oldClaimSetHash: "abc123",
      newClaimSetHash: "abc123",
      oldVkdNum: 5,
      newVkdNum: 3,
      policyDrift: false
    )
    check classifyChange(t) == tkReclassification

  test "vkd down + hash changed + no policy drift → tkRegression":
    let t = BaselineTransitionInput(
      oldClaimPolicyVersion: "v1",
      newClaimPolicyVersion: "v1",
      oldClaimSetHash: "abc123",
      newClaimSetHash: "def456",
      oldVkdNum: 5,
      newVkdNum: 3,
      policyDrift: false
    )
    check classifyChange(t) == tkRegression

  test "empty/ambiguous input → tkInvalidState":
    let t = BaselineTransitionInput(
      oldClaimPolicyVersion: "",
      newClaimPolicyVersion: "",
      oldClaimSetHash: "",
      newClaimSetHash: "newhash",
      oldVkdNum: 0,
      newVkdNum: 0,
      policyDrift: false
    )
    check classifyChange(t) == tkInvalidState

suite "baseline_transition - isDetector":

  test "different hashes → true (change detected)":
    check isDetector("hashA", "hashB") == true

  test "same hashes → false (no change)":
    check isDetector("hashA", "hashA") == false

  test "empty old hash → true (detected)":
    check isDetector("", "hashB") == true