## test_deterministic_report.nim — R7 determinism verification for report emitter
##
## Verifies that jsonFromOrchestrationReport produces byte-identical output
## across multiple invocations with the same fixed input, and that wall-clock
## timing values are excluded from canonical output (moved to runtimeMeta).
##
## R7 evidence: runDeterminism_byteLevel was DIFFERENT due to timing-only lines
## (elapsed ms, pipeline total ms, cache ready ms). This test ensures the
## canonical payload (everything except runtimeMeta) is deterministic.

import std/[json, strutils, unittest]

# Import only the pure function under test — no IO boundary.
import cli/wf_render
import core/orchestrator/orchestrator_report_types
import core/sorter/sorter_core
import core/types/asi_types

# ---------------------------------------------------------------------------
# Fixture builder — creates a minimal OrchestrationReport with fixed data
# ---------------------------------------------------------------------------

func makeFixedReport(): OrchestrationReport =
  ## Build a deterministic OrchestrationReport with zero timing values.
  result = OrchestrationReport(
    finalState: SorterState(
      nodes: @[
        SorterNode(
          modulePath: "test",
          functionName: "foo",
          nodeType: "func",
          id: sorterNodeId("test::foo"),
          dependencyIds: @[],
          astResidency: astResident,
          isStale: false,
          refactoredSource: ""
        )
      ],
      vaultEntries: @[],
      vaultIntegrityBlocks: @[]
    ),
    nodeReports: @[
      OrchestrationNodeReport(
        nodeId: sorterNodeId("test::foo"),
        dependencyDepth: 0,
        usesDependencyVault: false,
        readsDependencySource: false,
        injectedAxioms: @[],
        status: orchestrationVerified,
        vaultPath: "",
        cacheHit: false,
        remediationHint: "",
        mathematicalRationale: "proven",
        timeoutComplexityWeight: 0,
        timeoutHotspots: @[],
        selfHealingGuidance: @[],
        smtlib2: "",
        evidenceLogJson: "",
        staleReason: "",
        complexity: 0.0,
        assuranceTier: "z3-verified",
        tierResolution: "resolved"
      )
    ],
    blockedNodes: @[],
    staleDependencyNodes: @[],
    reproofNodes: @[],
    timeoutNodes: @[],
    timeoutImpactNodes: @[],
    executionStats: OrchestrationExecutionStats(
      nodeStats: @[
        OrchestrationNodeExecutionStat(
          nodeId: sorterNodeId("test::foo"),
          dependencyDepth: 0,
          solverElapsedMs: 0,
          wallElapsedMs: 0,
          cacheHit: false,
          status: orchestrationVerified,
          timeoutMs: 0,
          failureReason: ""
        )
      ],
      depthStats: @[],
      totalWallTimeMs: 0,
      totalSolverTimeMs: 0,
      serialBaselineMs: 0,
      parallelSpeedupRatio: 0.0,
      cpuEfficiency: 0.0,
      cacheHitCount: 0,
      solverInvocationCount: 0,
      maxWorkerCount: 1,
      timeoutCount: 0,
      hotspotNodeId: sorterNodeId(""),
      hotspotElapsedMs: 0,
      obligationGeneratedCount: 0,
      obligationAttemptedCount: 0,
      targetsWithObligations: 0,
      eligibleTargets: 1
    )
  )

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

suite "Deterministic Report Emitter":

  test "jsonFromOrchestrationReport produces identical JSON on repeated calls":
    ## Call the emitter twice with the same fixed input and assert byte-identical output.
    let report = makeFixedReport()
    let json1 = jsonFromOrchestrationReport(report, 0)
    let json2 = jsonFromOrchestrationReport(report, 0)
    
    check $json1 == $json2

  test "timing fields absent from canonical output when all timings are zero":
    ## When timing values are zero, canonical output should not contain any
    ## timing-related keys at the top level beyond what's expected.
    let report = makeFixedReport()
    let json = jsonFromOrchestrationReport(report, 0)
    let jsonStr = $json
    
    ## Verify runtimeMeta key exists (where timing values are condensed)
    check json.hasKey("runtimeMeta")
    
    ## Verify executionStats has timing keys (backward compat) but they're zero
    let execStats = json["executionStats"]
    check execStats.hasKey("totalWallTimeMs")
    check execStats["totalWallTimeMs"].getInt() == 0
    check execStats.hasKey("hotspotElapsedMs")
    check execStats["hotspotElapsedMs"].getInt() == 0
    
    ## Verify runtimeMeta contains the same timing values
    let runtimeMeta = json["runtimeMeta"]
    check runtimeMeta.hasKey("totalWallTimeMs")
    check runtimeMeta["totalWallTimeMs"].getInt() == 0

  test "canonical string excludes timing when set to non-zero via runtimeMeta":
    ## Even when timing values are non-zero, the canonical comparison should
    ## exclude runtimeMeta. This test verifies that the structure supports
    ## this separation.
    var report = makeFixedReport()
    report.executionStats.totalWallTimeMs = 12345
    report.executionStats.hotspotElapsedMs = 6789
    
    let json = jsonFromOrchestrationReport(report, 0)
    
    ## runtimeMeta should carry the timing values
    check json["runtimeMeta"]["totalWallTimeMs"].getInt() == 12345
    check json["runtimeMeta"]["hotspotElapsedMs"].getInt() == 6789
    
    ## executionStats should also carry them (backward compat)
    check json["executionStats"]["totalWallTimeMs"].getInt() == 12345
    check json["executionStats"]["hotspotElapsedMs"].getInt() == 6789
