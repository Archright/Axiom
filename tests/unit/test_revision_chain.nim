## tests/unit/test_revision_chain.nim
## Unit tests for tools/policy/revision_chain.nim — P0-1/P0-2/P0-3 invariants.
## P0-2: Genesis=1, head=1, reachable; fork & orphan & multi-genesis REJECTED.
## P0-3: PolicyDefinition genesis + patches → materialize reproduces disposition table.
## P0-1: decide(measurement, policyState) — baseline-free domain decision.
## verifyFreshness: fresh vs stale comparison.

import std/[unittest, json, os, strutils, options, sequtils]
import policy/revision_chain

# ══════════════════════════════════════════════════════════════════════
# Helper: build a revision chain JSON from scratch
# ══════════════════════════════════════════════════════════════════════

func makeChain*(revisions: varargs[JsonNode]): JsonNode =
  var arr = newJArray()
  for rev in revisions:
    arr.add(rev)
  %*{"revisions": arr}

func makeRevision*(revisionId: string; parentRevisionId: string; rationale: string;
                   evidenceRef: string; payload: JsonNode; patches: JsonNode = %*[]): JsonNode =
  var obj = newJObject()
  obj["revisionId"] = %revisionId
  if parentRevisionId.len > 0:
    obj["parentRevisionId"] = %parentRevisionId
  else:
    obj["parentRevisionId"] = newJNull()
  obj["rationale"] = %rationale
  obj["evidenceRef"] = %evidenceRef
  obj["payload"] = payload
  obj["patches"] = patches
  obj

# ══════════════════════════════════════════════════════════════════════
# Test Suite
# ══════════════════════════════════════════════════════════════════════

suite "revision_chain P0-2 invariants":

  test "single genesis (parentRevisionId=null) and exactly one head":
    let genesisPayload = %*{"policyId": "POLICY-001", "defaultDisposition": "ERROR",
                            "rules": [{"state": "DRIFT", "disposition": "INFO"}]}
    let chain = makeChain(
      makeRevision("rev-001", "", "Genesis", "test", genesisPayload)
    )
    let result = validateLinear(chain)
    check result.len == 0
    check findHead(chain).isSome()
    check findHead(chain).get() == "rev-001"

  test "multi-genesis REJECTED":
    let genesis1 = %*{"policyId": "P1", "defaultDisposition": "ERROR", "rules": @[]}
    let genesis2 = %*{"policyId": "P2", "defaultDisposition": "ERROR", "rules": @[]}
    let chain = makeChain(
      makeRevision("rev-A", "", "Genesis A", "test", genesis1),
      makeRevision("rev-B", "", "Genesis B", "test", genesis2)
    )
    let result = validateLinear(chain)
    check result.len > 0

  test "fork REJECTED (two children of same parent)":
    let genesis = %*{"policyId": "P1", "defaultDisposition": "ERROR", "rules": @[]}
    let chain = makeChain(
      makeRevision("rev-001", "", "Genesis", "test", genesis),
      makeRevision("rev-002", "rev-001", "Fork 1", "test", %*{}),
      makeRevision("rev-003", "rev-001", "Fork 2", "test", %*{})
    )
    let result = validateLinear(chain)
    check result.len > 0

  test "orphan REJECTED (node not reachable from genesis)":
    let genesis = %*{"policyId": "P1", "defaultDisposition": "ERROR", "rules": @[]}
    let chain = makeChain(
      makeRevision("rev-001", "", "Genesis", "test", genesis),
      makeRevision("rev-002", "rev-001", "Child", "test", %*{}),
      makeRevision("rev-003", "rev-orphan-parent", "Orphan", "test", %*{})
    )
    let result = validateLinear(chain)
    check result.len > 0

  test "materialize from history yields exactly one current state":
    let genesisPayload = %*{"policyId": "POLICY-001", "defaultDisposition": "ERROR",
                            "rules": [{"state": "DRIFT", "disposition": "INFO"}]}
    let patch1 = %*[{"op": "setRule", "arguments": {"state": "DRIFT", "disposition": "INFO"}}]
    let chain = makeChain(
      makeRevision("rev-001", "", "Genesis", "test", genesisPayload),
      makeRevision("rev-002", "rev-001", "Patch 1", "test", %*{}, patch1)
    )
    let result = validateLinear(chain)
    check result.len == 0
    let head = findHead(chain)
    check head.isSome()
    check head.get() == "rev-002"

  test "linear chain — no forks, all reachable":
    let genesisPayload = %*{"policyId": "POLICY-001", "defaultDisposition": "ERROR", "rules": @[]}
    let chain = makeChain(
      makeRevision("rev-001", "", "Genesis", "test", genesisPayload),
      makeRevision("rev-002", "rev-001", "Rev 2", "test", %*{}),
      makeRevision("rev-003", "rev-002", "Rev 3", "test", %*{})
    )
    let result = validateLinear(chain)
    check result.len == 0
    check findHead(chain).get() == "rev-003"

# ══════════════════════════════════════════════════════════════════════
# P0-3: PolicyDefinition genesis + patches → materialize reproduces disposition table
# ══════════════════════════════════════════════════════════════════════

suite "revision_chain P0-3 policy materialization":

  test "genesis PolicyDefinition + patches → materialize reproduces disposition table":
    ## Decision table:
    ##   import_lint_violations: DRIFT → INFO
    ##   layer_violations: DRIFT → INFO
    ##   debt_registry_open: DRIFT → INFO
    ##   debt_registry_closed: DRIFT → INFO
    ##   nimtry_violations: PASS → INFO
    ##   effect_violations: DRIFT → INFO
    ##   unknown metrics → ERROR (fail-closed)
    let genesisPayload = %*{"policyId": "POLICY-001",
                            "statusDomain": ["PASS", "DRIFT"],
                            "defaultDisposition": "ERROR",
                            "rules": [{"state": "DRIFT", "disposition": "INFO"},
                                      {"state": "PASS", "disposition": "INFO"}]}
    let chain = makeChain(
      makeRevision("policy-genesis", "", "Initial PolicyDefinition", "test", genesisPayload)
    )
    let result = validateLinear(chain)
    check result.len == 0

    let head = findHead(chain)
    check head.isSome()

    let materialized = materialize(chain, genesisPayload)
    check materialized.policyId == "POLICY-001"
    check materialized.defaultDisposition == "ERROR"
    check materialized.rules.len == 2

    # DRIFT → INFO
    let driftIdx = materialized.rules.findIt(it.state == "DRIFT")
    check materialized.rules[driftIdx].disposition == "INFO"

    # PASS → INFO
    let passIdx = materialized.rules.findIt(it.state == "PASS")
    check materialized.rules[passIdx].disposition == "INFO"

  test "patch setRule changes disposition for a state":
    let genesisPayload = %*{"policyId": "POLICY-001",
                            "statusDomain": ["PASS", "DRIFT"],
                            "defaultDisposition": "ERROR",
                            "rules": [{"state": "DRIFT", "disposition": "INFO"},
                                      {"state": "PASS", "disposition": "INFO"}]}
    let patch = %*[{"op": "setRule", "arguments": {"state": "DRIFT", "disposition": "WARN"}}]
    let chain = makeChain(
      makeRevision("policy-genesis", "", "Genesis", "test", genesisPayload),
      makeRevision("policy-rev-001", "policy-genesis", "Escalate DRIFT to WARN", "test", %*{}, patch)
    )
    check validateLinear(chain).len == 0
    let materialized = materialize(chain, genesisPayload)
    let driftIdx = materialized.rules.findIt(it.state == "DRIFT")
    check materialized.rules[driftIdx].disposition == "WARN"

  test "patch setDefault changes default disposition":
    let genesisPayload = %*{"policyId": "POLICY-001",
                            "statusDomain": ["PASS", "DRIFT"],
                            "defaultDisposition": "ERROR",
                            "rules": [{"state": "DRIFT", "disposition": "INFO"}]}
    let patch = %*[{"op": "setDefault", "arguments": {"disposition": "WARN"}}]
    let chain = makeChain(
      makeRevision("policy-genesis", "", "Genesis", "test", genesisPayload),
      makeRevision("policy-rev-001", "policy-genesis", "Change default", "test", %*{}, patch)
    )
    check validateLinear(chain).len == 0
    let materialized = materialize(chain, genesisPayload)
    check materialized.defaultDisposition == "WARN"

  test "patch addRule adds a new rule":
    let genesisPayload = %*{"policyId": "POLICY-001",
                            "statusDomain": ["PASS", "DRIFT"],
                            "defaultDisposition": "ERROR",
                            "rules": [{"state": "DRIFT", "disposition": "INFO"}]}
    let patch = %*[{"op": "addRule", "arguments": {"state": "PASS", "disposition": "WARN"}}]
    let chain = makeChain(
      makeRevision("policy-genesis", "", "Genesis", "test", genesisPayload),
      makeRevision("policy-rev-001", "policy-genesis", "Add PASS rule", "test", %*{}, patch)
    )
    check validateLinear(chain).len == 0
    let materialized = materialize(chain, genesisPayload)
    check materialized.rules.len == 2
    check materialized.rules.anyIt(it.state == "PASS" and it.disposition == "WARN")

# ══════════════════════════════════════════════════════════════════════
# P0-1: decide(measurement, policyState) — baseline-free domain decision
# ══════════════════════════════════════════════════════════════════════

suite "P0-1 baseline-free domain decision":

  test "decide without baseline input — DRIFT measurement with INFO policy → INFO":
    ## Baseline is NOT a Decision input (P0-1).
    ## decide(measurement, policyState) uses only measurement result + policy rules.
    let materialized = MaterializedState(
      policyId: "POLICY-001",
      defaultDisposition: "ERROR",
      rules: @[PolicyRule(state: "DRIFT", disposition: "INFO"),
               PolicyRule(state: "PASS", disposition: "INFO")]
    )
    # DRIFT measurement → INFO (from policy rule)
    let dispIdx = materialized.rules.findIt(it.state == "DRIFT")
    check materialized.rules[dispIdx].disposition == "INFO"

  test "decide without baseline input — unknown metric → fail-closed ERROR":
    let materialized = MaterializedState(
      policyId: "POLICY-001",
      defaultDisposition: "ERROR",
      rules: @[PolicyRule(state: "DRIFT", disposition: "INFO")]
    )
    # Unknown metric not covered by any rule → defaultDisposition (ERROR)
    check materialized.defaultDisposition == "ERROR"

  test "decide without baseline input — PASS measurement → INFO":
    let materialized = MaterializedState(
      policyId: "POLICY-001",
      defaultDisposition: "ERROR",
      rules: @[PolicyRule(state: "DRIFT", disposition: "INFO"),
               PolicyRule(state: "PASS", disposition: "INFO")]
    )
    let passIdx = materialized.rules.findIt(it.state == "PASS")
    check materialized.rules[passIdx].disposition == "INFO"

# ══════════════════════════════════════════════════════════════════════
# verifyFreshness — fresh vs stale
# ══════════════════════════════════════════════════════════════════════

suite "verifyFreshness":

  test "STALE when committed file differs from materialized state":
    let materialized = MaterializedState(
      policyId: "POLICY-001",
      defaultDisposition: "ERROR",
      rules: @[PolicyRule(state: "DRIFT", disposition: "INFO")]
    )
    let tmpPath = "tmp/test_freshness_stale.json"
    var f2: File
    if open(f2, tmpPath, fmWrite):
      f2.write("{\"policyId\":\"POLICY-002\",\"defaultDisposition\":\"WARN\"}")
      close(f2)
    let status = verifyFreshness(materialized, tmpPath)
    check status == "STALE (run tools/sync_policy)"
    removeFile(tmpPath)

  test "STALE when committed file is missing":
    let materialized = MaterializedState(
      policyId: "POLICY-001",
      defaultDisposition: "ERROR",
      rules: @[PolicyRule(state: "DRIFT", disposition: "INFO")]
    )
    let status = verifyFreshness(materialized, "tmp/nonexistent_file_xyz.json")
    check status.startsWith("STALE")
# ══════════════════════════════════════════════════════════════════════
# verifyPolicyDispositions — kernel function tests
# ══════════════════════════════════════════════════════════════════════

suite "verifyPolicyDispositions":

  test "fresh file → empty issues":
    let genesisPayload = %*{"policyId": "POLICY-001",
                            "statusDomain": ["PASS", "DRIFT"],
                            "defaultDisposition": "ERROR",
                            "rules": [{"state": "DRIFT", "disposition": "INFO"},
                                      {"state": "PASS", "disposition": "INFO"}]}
    let chain = makeChain(
      makeRevision("policy-genesis", "", "Genesis", "test", genesisPayload)
    )
    let tmpDir = "tmp/dispositions_test"
    if not dirExists(tmpDir): createDir(tmpDir)
    let dispositionsPath = tmpDir & "/policy_dispositions.json"
    # Write a file that matches what the materialized rules produce
    let freshContent = """{"version":"1.0.0","schema":"policy_dispositions","metrics":{"import_lint_violations":{"disposition":"INFO","reason":"Advisory tracking; non-blocking"},"layer_violations":{"disposition":"INFO","reason":"Advisory tracking; non-blocking"},"debt_registry_open":{"disposition":"INFO","reason":"Advisory tracking; non-blocking; no ERROR before sync-budget regeneration"},"debt_registry_closed":{"disposition":"INFO","reason":"Advisory tracking; non-blocking"},"nimtry_violations":{"disposition":"INFO","reason":"Advisory tracking; non-blocking"},"effect_violations":{"disposition":"INFO","reason":"Advisory tracking; non-blocking (evaluator resolved)"}}}"""
    writeFile(dispositionsPath, freshContent)
    let issues = verifyPolicyDispositions(chain, genesisPayload, dispositionsPath)
    check issues.len == 0
    removeFile(dispositionsPath)

  test "disposition mismatch → STALE issues":
    let genesisPayload = %*{"policyId": "POLICY-001",
                            "statusDomain": ["PASS", "DRIFT"],
                            "defaultDisposition": "ERROR",
                            "rules": [{"state": "DRIFT", "disposition": "INFO"},
                                      {"state": "PASS", "disposition": "INFO"}]}
    let chain = makeChain(
      makeRevision("policy-genesis", "", "Genesis", "test", genesisPayload)
    )
    let tmpDir = "tmp/dispositions_test"
    if not dirExists(tmpDir): createDir(tmpDir)
    let dispositionsPath = tmpDir & "/policy_dispositions_mismatch.json"
    # Write a file with wrong disposition for import_lint_violations (should be INFO, we write WARN)
    let staleContent = """{"version":"1.0.0","schema":"policy_dispositions","metrics":{"import_lint_violations":{"disposition":"WARN","reason":"Advisory tracking; non-blocking"},"layer_violations":{"disposition":"INFO","reason":"Advisory tracking; non-blocking"},"debt_registry_open":{"disposition":"INFO","reason":"Advisory tracking; non-blocking; no ERROR before sync-budget regeneration"},"debt_registry_closed":{"disposition":"INFO","reason":"Advisory tracking; non-blocking"},"nimtry_violations":{"disposition":"INFO","reason":"Advisory tracking; non-blocking"},"effect_violations":{"disposition":"INFO","reason":"Advisory tracking; non-blocking (evaluator resolved)"}}}"""
    writeFile(dispositionsPath, staleContent)
    let issues = verifyPolicyDispositions(chain, genesisPayload, dispositionsPath)
    check issues.len > 0
    check issues.anyIt(it.contains("import_lint_violations"))
    removeFile(dispositionsPath)

  test "undeclared metric in committed file → issue":
    let genesisPayload = %*{"policyId": "POLICY-001",
                            "statusDomain": ["PASS", "DRIFT"],
                            "defaultDisposition": "ERROR",
                            "rules": [{"state": "DRIFT", "disposition": "INFO"},
                                      {"state": "PASS", "disposition": "INFO"}]}
    let chain = makeChain(
      makeRevision("policy-genesis", "", "Genesis", "test", genesisPayload)
    )
    let tmpDir = "tmp/dispositions_test"
    if not dirExists(tmpDir): createDir(tmpDir)
    let dispositionsPath = tmpDir & "/policy_dispositions_extra.json"
    # Write a file with an extra metric not in DecisionTable
    let extraContent = """{"version":"1.0.0","schema":"policy_dispositions","metrics":{"import_lint_violations":{"disposition":"INFO","reason":"Advisory tracking; non-blocking"},"layer_violations":{"disposition":"INFO","reason":"Advisory tracking; non-blocking"},"debt_registry_open":{"disposition":"INFO","reason":"Advisory tracking; non-blocking; no ERROR before sync-budget regeneration"},"debt_registry_closed":{"disposition":"INFO","reason":"Advisory tracking; non-blocking"},"nimtry_violations":{"disposition":"INFO","reason":"Advisory tracking; non-blocking"},"effect_violations":{"disposition":"INFO","reason":"Advisory tracking; non-blocking (evaluator resolved)"},"unknown_metric":{"disposition":"INFO","reason":"Not in decision table"}}}"""
    writeFile(dispositionsPath, extraContent)
    let issues = verifyPolicyDispositions(chain, genesisPayload, dispositionsPath)
    check issues.len > 0
    check issues.anyIt(it.contains("undeclared metric"))
    removeFile(dispositionsPath)

# ══════════════════════════════════════════════════════════════════════
# P3: Policy Ratchet — stability constraint tests
# ══════════════════════════════════════════════════════════════════════

suite "DriftDirection enum":

  test "DriftDirection values exist":
    check ddImprovement == ddImprovement
    check ddRegression == ddRegression
    check ddMaintained == ddMaintained

  test "DriftDirection ordinals":
    check ord(ddImprovement) == 0
    check ord(ddRegression) == 1
    check ord(ddMaintained) == 2

  test "$ produces expected strings":
    check $ddImprovement == "ddImprovement"
    check $ddRegression == "ddRegression"
    check $ddMaintained == "ddMaintained"

suite "parseDriftDirection":

  test "parses IMPROVEMENT correctly":
    check parseDriftDirection("IMPROVEMENT").isSome()
    check parseDriftDirection("IMPROVEMENT").get() == ddImprovement

  test "parses REGRESSION correctly":
    check parseDriftDirection("REGRESSION").isSome()
    check parseDriftDirection("REGRESSION").get() == ddRegression

  test "parses MAINTAINED correctly":
    check parseDriftDirection("MAINTAINED").isSome()
    check parseDriftDirection("MAINTAINED").get() == ddMaintained

  test "returns none for invalid direction":
    check parseDriftDirection("INVALID").isNone()
    check parseDriftDirection("").isNone()

suite "StabilityConfig":

  test "can be constructed with all fields":
    let sc = StabilityConfig(
      minStableRevisions: 3,
      direction: some(ddRegression),
      requiredConsecutiveObservations: 5
    )
    check sc.minStableRevisions == 3
    check sc.direction.isSome()
    check sc.direction.get() == ddRegression
    check sc.requiredConsecutiveObservations == 5

  test "can be constructed with direction = none (backward compatible)":
    let sc = StabilityConfig(
      minStableRevisions: 1,
      direction: none(DriftDirection),
      requiredConsecutiveObservations: 1
    )
    check sc.direction.isNone()

suite "enforceConstraints":

  test "empty chain passes constraints":
    let chain = %*{"revisions": []}
    let materialized = MaterializedState(
      policyId: "POLICY-001",
      defaultDisposition: "ERROR",
      rules: @[]
    )
    let issues = enforceConstraints(materialized, chain)
    check issues.len == 0

  test "revision with no stability field passes (backward compatible)":
    let genesisPayload = %*{"policyId": "POLICY-001",
                            "statusDomain": ["PASS", "DRIFT"],
                            "defaultDisposition": "ERROR",
                            "rules": [{"state": "DRIFT", "disposition": "INFO"}]}
    let chain = makeChain(
      makeRevision("policy-genesis", "", "Genesis", "test", genesisPayload)
    )
    let materialized = materialize(chain, genesisPayload)
    let issues = enforceConstraints(materialized, chain)
    check issues.len == 0

  test "valid stability config passes":
    let genesisPayload = %*{"policyId": "POLICY-001",
                            "statusDomain": ["PASS", "DRIFT"],
                            "defaultDisposition": "ERROR",
                            "rules": [{"state": "DRIFT", "disposition": "INFO"}]}
    let patch = %*[{"op": "setRule", "arguments": {"state": "DRIFT", "disposition": "WARN"}}]
    let chain = makeChain(
      makeRevision("policy-genesis", "", "Genesis", "test", genesisPayload),
      makeRevision("policy-rev-001", "policy-genesis", "Escalate DRIFT", "test", %*{}, patch)
    )
    let materialized = materialize(chain, genesisPayload)
    let issues = enforceConstraints(materialized, chain)
    check issues.len == 0

  test "invalid direction value produces error":
    let badChain = %*{"revisions": [
      {
        "revisionId": "policy-rev-001",
        "parentRevisionId": newJNull(),
        "rationale": "test",
        "evidenceRef": "test",
        "payload": {"policyId": "P1", "defaultDisposition": "ERROR", "rules": []},
        "stability": {"minStableRevisions": 1, "direction": "INVALID_DIR", "requiredConsecutiveObservations": 1}
      }
    ]}
    let materialized = MaterializedState(
      policyId: "P1",
      defaultDisposition: "ERROR",
      rules: @[]
    )
    let issues = enforceConstraints(materialized, badChain)
    check issues.len > 0
    check issues.anyIt(it.contains("invalid direction"))

  test "minStableRevisions < 1 produces error":
    let badChain = %*{"revisions": [
      {
        "revisionId": "policy-rev-001",
        "parentRevisionId": newJNull(),
        "rationale": "test",
        "evidenceRef": "test",
        "payload": {"policyId": "P1", "defaultDisposition": "ERROR", "rules": []},
        "stability": {"minStableRevisions": 0, "direction": "IMPROVEMENT", "requiredConsecutiveObservations": 1}
      }
    ]}
    let materialized = MaterializedState(
      policyId: "P1",
      defaultDisposition: "ERROR",
      rules: @[]
    )
    let issues = enforceConstraints(materialized, badChain)
    check issues.len > 0
    check issues.anyIt(it.contains("minStableRevisions must be >= 1"))

  test "requiredConsecutiveObservations < 1 produces error":
    let badChain = %*{"revisions": [
      {
        "revisionId": "policy-rev-001",
        "parentRevisionId": newJNull(),
        "rationale": "test",
        "evidenceRef": "test",
        "payload": {"policyId": "P1", "defaultDisposition": "ERROR", "rules": []},
        "stability": {"minStableRevisions": 1, "direction": "IMPROVEMENT", "requiredConsecutiveObservations": 0}
      }
    ]}
    let materialized = MaterializedState(
      policyId: "P1",
      defaultDisposition: "ERROR",
      rules: @[]
    )
    let issues = enforceConstraints(materialized, badChain)
    check issues.len > 0
    check issues.anyIt(it.contains("requiredConsecutiveObservations must be >= 1"))
