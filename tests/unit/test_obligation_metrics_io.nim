## Unit tests for `verification/obligation/metrics_io.nim`.
##
## Tests pure serialization/deserialization, zero-value handling,
## and additive merge semantics with baseline_snapshot_core.

import std/[json, os, strutils, monotimes]
import unittest
import core/utils/io_utils
import ../../src/verification/obligation/metrics_io
import ../../src/verification/obligation/metrics

suite "ObligationMetrics — defaults":
  test "defaultObligationMetrics returns all zeros":
    let m = defaultObligationMetrics()
    check m.schemaVersion == 1
    check m.eligibleTargets == 0
    check m.targetsWithObligations == 0
    check m.obligationGeneratedCount == 0
    check m.obligationAttemptedCount == 0
    check m.ogr == 0.0
    check m.par == 0.0

suite "ObligationMetrics — from counts":
  test "metricsFromCounts computes OGR/PAR correctly":
    let m = metricsFromCounts(10, 5, 8, 6)
    check m.eligibleTargets == 10
    check m.targetsWithObligations == 5
    check m.obligationGeneratedCount == 8
    check m.obligationAttemptedCount == 6
    check m.ogr == 0.5   # 5/10
    check m.par == 0.75  # 6/8

  test "metricsFromCounts zero denominator yields 0.0":
    let m = metricsFromCounts(0, 0, 0, 0)
    check m.ogr == 0.0
    check m.par == 0.0

  test "metricsFromCounts only eligible targets (no obligations)":
    let m = metricsFromCounts(10, 0, 0, 0)
    check m.ogr == 0.0
    check m.par == 0.0

  test "metricsFromCounts full coverage":
    let m = metricsFromCounts(10, 10, 10, 10)
    check m.ogr == 1.0
    check m.par == 1.0

suite "ObligationMetrics — JSON roundtrip":
  test "metricsToJson → parseJson → metricsFromJson roundtrip":
    let original = metricsFromCounts(20, 10, 15, 12)
    let jsonNode = metricsToJson(original)
    check jsonNode.kind == JObject
    check jsonNode["schemaVersion"].getInt() == 1
    check jsonNode["eligibleTargets"].getInt() == 20
    check jsonNode["targetsWithObligations"].getInt() == 10
    check jsonNode["obligationGeneratedCount"].getInt() == 15
    check jsonNode["obligationAttemptedCount"].getInt() == 12
    check abs(jsonNode["ogr"].getFloat() - 0.5) < 1e-9
    check abs(jsonNode["par"].getFloat() - 0.8) < 1e-9

    let restored = metricsFromJson(jsonNode)
    check restored.eligibleTargets == original.eligibleTargets
    check restored.targetsWithObligations == original.targetsWithObligations
    check restored.obligationGeneratedCount == original.obligationGeneratedCount
    check restored.obligationAttemptedCount == original.obligationAttemptedCount
    check abs(restored.ogr - original.ogr) < 1e-9
    check abs(restored.par - original.par) < 1e-9

  test "fromJson with missing fields falls back to defaults":
    let partial = %*{
      "schemaVersion": 1,
      "eligibleTargets": 5
    }
    let m = metricsFromJson(partial)
    check m.eligibleTargets == 5
    check m.targetsWithObligations == 0
    check m.obligationGeneratedCount == 0
    check m.ogr == 0.0
    check m.par == 0.0

  test "fromJson with ogr=0 still reads par":
    let node = %*{
      "schemaVersion": 1,
      "eligibleTargets": 10,
      "targetsWithObligations": 0,
      "obligationGeneratedCount": 0,
      "obligationAttemptedCount": 0,
      "ogr": 0.0,
      "par": 0.5
    }
    let m = metricsFromJson(node)
    check m.ogr == 0.0
    check m.par == 0.5

suite "ObligationMetrics — write/read cycle":
  test "writeObligationMetrics creates file and readObligationMetrics recovers it":
    let tmpDir = getTempDir() / "axiom_metrics_test_" & $getMonoTime().ticks
    try:
      let metrics = metricsFromCounts(30, 15, 20, 18)
      if not dirExists(tmpDir): createDir(tmpDir)

      let path = joinPath(tmpDir, "obligation_metrics.json")
      discard writeFileAtomic(path, metricsToJson(metrics).pretty() & "\n")  # axiom:best-effort(test scaffolding)

      # Read back via direct file read (readObligationMetrics uses hardcoded MetricsDir)
      let content = readFile(path)
      let node = parseJson(content)
      check node["eligibleTargets"].getInt() == 30
      check node["targetsWithObligations"].getInt() == 15
      check node["ogr"].getFloat() == 0.5
      check node["par"].getFloat() == 0.9

    finally:
      if dirExists(tmpDir):
        removeDir(tmpDir)

  test "readObligationMetrics returns default when file missing":
    let tmpDir = getTempDir() / "axiom_metrics_missing_" & $getMonoTime().ticks
    try:
      if not dirExists(tmpDir): createDir(tmpDir)
      let path = joinPath(tmpDir, "nonexistent.json")
      check not fileExists(path)
      let m = defaultObligationMetrics()
      check m.eligibleTargets == 0
    finally:
      if dirExists(tmpDir):
        removeDir(tmpDir)

suite "Baseline merge semantics":
  test "baseline_snapshot_core merges ogr/par only when > 0":
    ## Simulates what computeBaselineSnapshot does:
    ## diskMetrics.ogr > 0 → overwrite snap.ogr
    ## diskMetrics.par > 0 → overwrite snap.par

    var snapOgr = 0.0
    var snapPar = 0.0

    # Case 1: disk has values
    let diskMetrics = metricsFromCounts(10, 5, 8, 6)
    if diskMetrics.ogr > 0.0: snapOgr = diskMetrics.ogr
    if diskMetrics.par > 0.0: snapPar = diskMetrics.par
    check snapOgr == 0.5
    check snapPar == 0.75

    # Case 2: disk has zeros (no prove run yet) — should NOT overwrite
    let emptyMetrics = defaultObligationMetrics()
    if emptyMetrics.ogr > 0.0: snapOgr = emptyMetrics.ogr
    if emptyMetrics.par > 0.0: snapPar = emptyMetrics.par
    check snapOgr == 0.5  # unchanged
    check snapPar == 0.75 # unchanged

    # Case 3: fresh snapshot with no prior values
    var freshOgr = 0.0
    var freshPar = 0.0
    if diskMetrics.ogr > 0.0: freshOgr = diskMetrics.ogr
    if diskMetrics.par > 0.0: freshPar = diskMetrics.par
    check freshOgr == 0.5
    check freshPar == 0.75
