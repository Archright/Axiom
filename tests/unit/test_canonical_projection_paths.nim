# test_canonical_projection_paths.nim — path & cache-key stripping invariants
#
# productization_contract.md §6/R3: the canonical projection must exclude
# path/location identity and cache-state observation so the same logical input
# re-verified at a different physical root (different AXIOM_STATE_DIR) projects
# to the same hash (R3 pathIndependentProjectionEqual, measured by
# tools/ci/wp5_relocation_measure.nim).
#
# Execution: nim c --hints:off -r --path:src tests/unit/test_canonical_projection_paths.nim

import std/[unittest, json]

import core/utils/canonical_projection

func stateWithNode(node: JsonNode): JsonNode =
  ## Minimal proof-state shape carrying one node report (wf_render.nim fields).
  %*{
    "schemaVersion": "axiom.report.v1",
    "summary": {"verified": 1, "plannedNodeCount": 1},
    "nodeReports": [node]
  }

func absValNode(vaultPath: string, cacheHit: bool): JsonNode =
  %*{
    "nodeId": "absval.nim::absVal",
    "label": "absval.nim::absVal",
    "status": "verified",
    "vaultPath": vaultPath,
    "cacheHit": cacheHit,
    "evidenceLogJson": "{\"solverStatus\":\"unsat\",\"method\":\"uap-pipeline\"}"
  }

suite "canonical projection — path & cache key stripping":

  test "absolute vaultPath variation does not change the digest":
    let atRootA = stateWithNode(absValNode(
      "/tmp/wp5_rootA/state/.axiom/vault/absval.absVal.axiom.json", false))
    let atRootB = stateWithNode(absValNode(
      "/tmp/wp5_rootB_elsewhere/state/.axiom/vault/absval.absVal.axiom.json", false))
    check canonicalProjectionHash(atRootA) == canonicalProjectionHash(atRootB)

  test "state with an absolute vaultPath equals the digest without the key":
    let withPath = stateWithNode(absValNode(
      "/tmp/wp5_rootA/state/.axiom/vault/absval.absVal.axiom.json", false))
    let withoutPath = parseJson($withPath)
    withoutPath["nodeReports"][0].delete("vaultPath")
    check canonicalProjectionHash(withPath) == canonicalProjectionHash(withoutPath)

  test "cacheHit variation does not change the digest":
    # cacheHit flips at a cold/warm boundary for identical logical input; it is
    # cache-state observation, not logical identity (§6 exclusion table).
    let cold = stateWithNode(absValNode("/vault/absval.json", false))
    let warm = stateWithNode(absValNode("/vault/absval.json", true))
    check canonicalProjectionHash(cold) == canonicalProjectionHash(warm)

  test "cacheHitCount and evidenceLogJson variation does not change the digest":
    let run1 = stateWithNode(absValNode("/vault/absval.json", false))
    run1["executionStats"] = %*{"cacheHitCount": 0, "totalWallTimeMs": 12}
    let run2 = stateWithNode(absValNode("/vault/absval.json", false))
    run2["executionStats"] = %*{"cacheHitCount": 1, "totalWallTimeMs": 3}
    run2["nodeReports"][0]["evidenceLogJson"] =
      %"{\"solverStatus\":\"unsat\",\"vaultPath\":\"/tmp/other/state/.axiom/vault/x.json\"}"
    check canonicalProjectionHash(run1) == canonicalProjectionHash(run2)

  test "path and root identity keys are stripped wherever they appear":
    let located = %*{
      "subjectRoot": "/checkouts/alpha",
      "stateRoot": "/checkouts/alpha/.axiom",
      "repoRoot": "/checkouts/alpha",
      "config": {
        "sourcePath": "/checkouts/alpha/src/absval.nim",
        "tmpPath": "/tmp/axiom-build-123/tmp",
        "absolutePath": "/checkouts/alpha/src/absval.nim",
        "path": "/checkouts/alpha/src/absval.nim"
      }
    }
    let relocated = %*{
      "subjectRoot": "/checkouts/beta",
      "stateRoot": "/checkouts/beta/.axiom",
      "repoRoot": "/checkouts/beta",
      "config": {
        "sourcePath": "/checkouts/beta/src/absval.nim",
        "tmpPath": "/tmp/axiom-build-999/tmp",
        "absolutePath": "/checkouts/beta/src/absval.nim",
        "path": "/checkouts/beta/src/absval.nim"
      }
    }
    check canonicalProjectionHash(located) == canonicalProjectionHash(relocated)

  test "a semantic change DOES change the digest":
    let verified = stateWithNode(absValNode("/vault/absval.json", false))
    let failed = stateWithNode(absValNode("/vault/absval.json", false))
    failed["nodeReports"][0]["status"] = %"failed"
    failed["summary"]["verified"] = %0
    check canonicalProjectionHash(verified) != canonicalProjectionHash(failed)

  test "isVolatileKey covers the path and cache-state keys":
    for k in ["vaultPath", "tmpPath", "absolutePath", "path", "sourcePath",
              "subjectRoot", "stateRoot", "repoRoot", "cacheHit",
              "cacheHitCount", "evidenceLogJson"]:
      check isVolatileKey(k)
