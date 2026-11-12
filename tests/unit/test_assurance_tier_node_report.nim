import std/[json, unittest]
import ../../src/core/orchestrator/orchestrator_report_types
import ../../src/core/orchestrator/orchestrator_parallel_types
import ../../src/core/types/verification_tier
import ../../src/cli/wf_render

suite "Phase 1 — Tier semantics: node-level exposure (B4/R2)":
  test "OrchestrationNodeReport carries assuranceTier + tierResolution fields":
    let r = OrchestrationNodeReport()
    check r.assuranceTier == ""
    check r.tierResolution == ""

  test "ParallelTaskResult carries assuranceTier + tierResolution fields":
    let p = ParallelTaskResult()
    check p.assuranceTier == ""
    check p.tierResolution == ""

  test "tierFromResults SSOT: z3-only -> z3-verified":
    check tierFromResults(true, false) == vtZ3Only
    check tierLabel(tierFromResults(true, false)) == "z3-verified"

  test "tierFromResults SSOT: dual -> dual-verified":
    check tierFromResults(true, true) == vtDual
    check tierLabel(tierFromResults(true, true)) == "dual-verified"

  test "tierFromResults SSOT: lean-only -> lean-verified":
    check tierFromResults(false, true) == vtLeanOnly
    check tierLabel(tierFromResults(false, true)) == "lean-verified"

  test "tierFromResults SSOT: neither -> none":
    check tierFromResults(false, false) == vtNone
    check tierLabel(tierFromResults(false, false)) == "none"

  test "determinism: tierFromResults is pure (2x identical)":
    let a = tierFromResults(true, false)
    let b = tierFromResults(true, false)
    check a == b
    check tierLabel(a) == tierLabel(b)

  test "determinism: tierFromResults(true,true) != tierFromResults(true,false)":
    check tierFromResults(true, true) != tierFromResults(true, false)
    check tierLabel(tierFromResults(true, true)) != tierLabel(tierFromResults(true, false))

  test "jsonFromOrchestrationReport projects assuranceTier + tierResolution on nodeReports":
    var report = OrchestrationReport()
    report.nodeReports.add(OrchestrationNodeReport(
      status: orchestrationVerified,
      assuranceTier: "z3-verified",
      tierResolution: "resolved"
    ))
    report.nodeReports.add(OrchestrationNodeReport(
      status: orchestrationVerified,
      assuranceTier: "dual-verified",
      tierResolution: "resolved"
    ))
    report.nodeReports.add(OrchestrationNodeReport(
      status: orchestrationProofFailed,
      assuranceTier: "unknown",
      tierResolution: "unavailable"
    ))
    let j = jsonFromOrchestrationReport(report)
    check j["nodeReports"].len == 3
    check j["nodeReports"][0]["assuranceTier"].getStr() == "z3-verified"
    check j["nodeReports"][0]["tierResolution"].getStr() == "resolved"
    check j["nodeReports"][1]["assuranceTier"].getStr() == "dual-verified"
    check j["nodeReports"][1]["tierResolution"].getStr() == "resolved"
    check j["nodeReports"][2]["assuranceTier"].getStr() == "unknown"
    check j["nodeReports"][2]["tierResolution"].getStr() == "unavailable"

  test "jsonFromOrchestrationReport summary carries tierCounts + statusCounts":
    var report = OrchestrationReport()
    report.nodeReports.add(OrchestrationNodeReport(
      status: orchestrationVerified,
      assuranceTier: "z3-verified",
      tierResolution: "resolved"
    ))
    report.nodeReports.add(OrchestrationNodeReport(
      status: orchestrationVerified,
      assuranceTier: "dual-verified",
      tierResolution: "resolved"
    ))
    report.nodeReports.add(OrchestrationNodeReport(
      status: orchestrationProofFailed,
      assuranceTier: "unknown",
      tierResolution: "unavailable"
    ))
    let j = jsonFromOrchestrationReport(report)
    let summary = j["summary"]
    check summary.hasKey("tierCounts")
    check summary.hasKey("statusCounts")
    check summary.hasKey("classifiedNodes")
    check summary["tierCounts"]["z3-verified"].getInt() == 1
    check summary["tierCounts"]["dual-verified"].getInt() == 1
    check summary["tierCounts"]["unknown"].getInt() == 1
    check summary["statusCounts"]["verified"].getInt() == 2
    check summary["statusCounts"]["failed"].getInt() == 1
    check summary["classifiedNodes"].getInt() == 3

  test "contract: sum(tierCounts.values) == classifiedNodes":
    var report = OrchestrationReport()
    report.nodeReports.add(OrchestrationNodeReport(
      status: orchestrationVerified,
      assuranceTier: "z3-verified",
      tierResolution: "resolved"
    ))
    report.nodeReports.add(OrchestrationNodeReport(
      status: orchestrationVerified,
      assuranceTier: "dual-verified",
      tierResolution: "resolved"
    ))
    report.nodeReports.add(OrchestrationNodeReport(
      status: orchestrationTimedOut,
      assuranceTier: "unknown",
      tierResolution: "unavailable"
    ))
    let j = jsonFromOrchestrationReport(report)
    let tc = j["summary"]["tierCounts"]
    var total = 0
    for key in ["z3-verified", "dual-verified", "lean-verified", "none", "k-induction", "uf-abstract", "unknown"]:
      total += tc[key].getInt()
    check total == j["summary"]["classifiedNodes"].getInt()
    check total == 3

  test "contract: unresolved node has assuranceTier=unknown, tierResolution=unavailable":
    let r = OrchestrationNodeReport(status: orchestrationProofFailed)
    check r.assuranceTier == ""
    let j = jsonFromOrchestrationReport(OrchestrationReport(nodeReports: @[r]))
    check j["nodeReports"][0]["assuranceTier"].getStr() == ""
    check j["nodeReports"][0]["tierResolution"].getStr() == ""
    check j["summary"]["classifiedNodes"].getInt() == 0
    check j["summary"]["tierCounts"]["unknown"].getInt() == 0
suite "DEBT#459 — parallel cache-hit row serialization":

  test "cache-hit row (status=failed, cacheHit=true) is REUSED, not failed, in summary":
    # The parallel scheduler emits cache-hit rows with the fail-closed runtime
    # status orchestrationProofFailed + cacheHit=true. jsonFromOrchestrationReport
    # (the exit-code path — axProofShortcutExitCode reads summary.failedCount)
    # must classify the pair as REUSED, not a failure.
    var report = OrchestrationReport()
    report.nodeReports.add(OrchestrationNodeReport(
      status: orchestrationProofFailed,
      cacheHit: true,
      evidenceLogJson: "CACHE-HIT: no kernel acceptance evidence"
    ))
    report.nodeReports.add(OrchestrationNodeReport(status: orchestrationVerified))
    let j = jsonFromOrchestrationReport(report)
    let summary = j["summary"]
    check summary["failedCount"].getInt() == 0
    check summary["reusedCount"].getInt() == 1
    check summary["statusCounts"]["failed"].getInt() == 0
    check summary["statusCounts"]["reused"].getInt() == 1
    check summary["statusCounts"]["verified"].getInt() == 1
    # The row itself serializes cacheHit=true (the DEBT#459 omission).
    check j["nodeReports"][0]["cacheHit"].getBool() == true
    check j["nodeReports"][0]["status"].getStr() == "failed"

  test "genuine failure (cacheHit=false) still counts as failed":
    var report = OrchestrationReport()
    report.nodeReports.add(OrchestrationNodeReport(status: orchestrationProofFailed))
    let j = jsonFromOrchestrationReport(report)
    check j["summary"]["failedCount"].getInt() == 1
    check j["summary"]["reusedCount"].getInt() == 0
    check j["summary"]["statusCounts"]["failed"].getInt() == 1
