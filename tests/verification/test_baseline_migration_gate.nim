import std/[unittest, os]
import gate/baseline_transition
import gate/runners/baseline_migration_gate

suite "baseline_migration_gate - runBaselineMigrationGate":

  test "regression → exit 1":
    let old = BaselineTransitionInput(
      oldClaimPolicyVersion: "v1",
      newClaimPolicyVersion: "v1",
      oldClaimSetHash: "abc123",
      newClaimSetHash: "abc123",
      oldVkdNum: 5,
      newVkdNum: 5,
      policyDrift: false
    )
    let new = BaselineTransitionInput(
      oldClaimPolicyVersion: "v1",
      newClaimPolicyVersion: "v1",
      oldClaimSetHash: "abc123",
      newClaimSetHash: "def456",
      oldVkdNum: 5,
      newVkdNum: 3,
      policyDrift: false
    )
    check runBaselineMigrationGate(old, new) == 1

  test "migration → exit 0":
    let old = BaselineTransitionInput(
      oldClaimPolicyVersion: "v1",
      newClaimPolicyVersion: "v1",
      oldClaimSetHash: "abc123",
      newClaimSetHash: "abc123",
      oldVkdNum: 5,
      newVkdNum: 5,
      policyDrift: false
    )
    let new = BaselineTransitionInput(
      oldClaimPolicyVersion: "v1",
      newClaimPolicyVersion: "v2",
      oldClaimSetHash: "abc123",
      newClaimSetHash: "def456",
      oldVkdNum: 5,
      newVkdNum: 3,
      policyDrift: false
    )
    check runBaselineMigrationGate(old, new) == 0

  test "reclassification → exit 0":
    let old = BaselineTransitionInput(
      oldClaimPolicyVersion: "v1",
      newClaimPolicyVersion: "v1",
      oldClaimSetHash: "abc123",
      newClaimSetHash: "abc123",
      oldVkdNum: 5,
      newVkdNum: 5,
      policyDrift: false
    )
    let new = BaselineTransitionInput(
      oldClaimPolicyVersion: "v1",
      newClaimPolicyVersion: "v1",
      oldClaimSetHash: "abc123",
      newClaimSetHash: "abc123",
      oldVkdNum: 5,
      newVkdNum: 3,
      policyDrift: false
    )
    check runBaselineMigrationGate(old, new) == 0

  test "invalid → exit 1":
    let old = BaselineTransitionInput(
      oldClaimPolicyVersion: "",
      newClaimPolicyVersion: "",
      oldClaimSetHash: "",
      newClaimSetHash: "oldhash",
      oldVkdNum: 0,
      newVkdNum: 0,
      policyDrift: false
    )
    let new = BaselineTransitionInput(
      oldClaimPolicyVersion: "",
      newClaimPolicyVersion: "",
      oldClaimSetHash: "oldhash",
      newClaimSetHash: "newhash",
      oldVkdNum: 0,
      newVkdNum: 0,
      policyDrift: false
    )
    check runBaselineMigrationGate(old, new) == 1

  test "improvement (same claim set, stable VKD) → exit 0":
    let old = BaselineTransitionInput(
      oldClaimPolicyVersion: "v1",
      newClaimPolicyVersion: "v1",
      oldClaimSetHash: "abc123",
      newClaimSetHash: "abc123",
      oldVkdNum: 5,
      newVkdNum: 5,
      policyDrift: false
    )
    let new = BaselineTransitionInput(
      oldClaimPolicyVersion: "v1",
      newClaimPolicyVersion: "v1",
      oldClaimSetHash: "abc123",
      newClaimSetHash: "abc123",
      oldVkdNum: 5,
      newVkdNum: 5,
      policyDrift: false
    )
    check runBaselineMigrationGate(old, new) == 0

  test "policy drift → exit 0":
    let old = BaselineTransitionInput(
      oldClaimPolicyVersion: "v1",
      newClaimPolicyVersion: "v1",
      oldClaimSetHash: "abc123",
      newClaimSetHash: "abc123",
      oldVkdNum: 5,
      newVkdNum: 5,
      policyDrift: false
    )
    let new = BaselineTransitionInput(
      oldClaimPolicyVersion: "v1",
      newClaimPolicyVersion: "v1",
      oldClaimSetHash: "abc123",
      newClaimSetHash: "def456",
      oldVkdNum: 5,
      newVkdNum: 3,
      policyDrift: true
    )
    check runBaselineMigrationGate(old, new) == 0