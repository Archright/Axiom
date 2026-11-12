# projection_golden_test.nim — S4 Gate 2: projection golden invariant
#
# Contract sentence 4 (canonical_execution_semantics.md §7.3):
#   Project(FullResult, Selected) == PrunedResult
# Full↔Pruned direct comparison is FORBIDDEN (universe size mismatch).
#
# Execution: nim c --hints:off -r --path:src tests/unit/projection_golden_test.nim

import std/[unittest, strutils, json, sequtils]

import core/crypto/hash_kernel
import core/types/result_identity
import engine/proof_certificate

# ==========================================================================
# Fixture: full universe of units A, B, C, D with distinct results
# ==========================================================================

func makeUnitResult*(unitId: string; status: ProofStatus;
                     failureClass, vacuityClass, certDigest: string): UnitResult =
  UnitResult(
    unitId: unitId,
    proofStatus: status,
    failureClassification: failureClass,
    vacuityClassification: vacuityClass,
    certificateIdentityDigest: certDigest,
    resultDigest: sha256Hex(unitId & $status & failureClass & vacuityClass & certDigest))

func makeFullResult*(): GlobalResult =
  ## Full universe: A, B, C, D with mix of statuses and one certificate identity.
  let units = @[
    makeUnitResult("A", psPass, "", "", "cert-A-digest"),
    makeUnitResult("B", psFail, "assertion-failure", "", "cert-B-digest"),
    makeUnitResult("C", psVacuousTrivial, "", "trivial-no-constraints", "cert-C-digest"),
    makeUnitResult("D", psPass, "", "", "cert-D-digest")
  ]
  GlobalResult(
    unitResults: units,
    selectedUniverseRatio: 0.0,
    selectionInvariantProjection: @[],
    selectionScopedReport: %*{})

func makePrunedResult*(): GlobalResult =
  ## PrunedResult: manually built from the same units A, D only.
  let units = @[
    makeUnitResult("A", psPass, "", "", "cert-A-digest"),
    makeUnitResult("D", psPass, "", "", "cert-D-digest")
  ]
  GlobalResult(
    unitResults: units,
    selectedUniverseRatio: 0.5,
    selectionInvariantProjection: @[],
    selectionScopedReport: %*{
      "totalUnits": 4,
      "selectedUnits": 2,
      "selectedUniverseRatio": 0.5,
      "passCount": 2,
      "failCount": 0,
      "timeoutCount": 0,
      "skipCount": 0,
      "errorCount": 0,
      "vacuousCount": 0})

# ==========================================================================
# Suite: Gate 2 — projection golden invariant
# ==========================================================================

suite "Gate 2 — Projection Golden Invariant":

  # -----------------------------------------------------------------------
  # Contract sentence 4: Project(FullResult, Selected) == PrunedResult
  # -----------------------------------------------------------------------
  test "projectToSelected(FullResult, Selected) == PrunedResult for {A,D}":
    let full = makeFullResult()
    let pruned = makePrunedResult()
    let projected = projectToSelected(full, @["A", "D"])

    # Unit count must match
    check projected.unitResults.len == pruned.unitResults.len
    check projected.unitResults.len == 2

    # Per-unit fields must match exactly (selection-invariant)
    for i in 0 ..< projected.unitResults.len:
      let p = projected.unitResults[i]
      let r = pruned.unitResults[i]
      check p.unitId == r.unitId
      check p.proofStatus == r.proofStatus
      check p.failureClassification == r.failureClassification
      check p.vacuityClassification == r.vacuityClassification
      check p.certificateIdentityDigest == r.certificateIdentityDigest
      check p.resultDigest == r.resultDigest

  # -----------------------------------------------------------------------
  # Per-unit field preservation (explicit field-by-field)
  # -----------------------------------------------------------------------
  test "selectionInvariantProjection preserves per-unit fields exactly":
    let full = makeFullResult()
    let projected = projectToSelected(full, @["A", "D"])

    for i in 0 ..< projected.unitResults.len:
      let p = projected.unitResults[i]
      # Find the same unit in the full result by filtering
      let matching = full.unitResults.filterIt(it.unitId == p.unitId)
      check matching.len == 1
      let original = matching[0]
      check original.proofStatus == p.proofStatus
      check original.failureClassification == p.failureClassification
      check original.vacuityClassification == p.vacuityClassification
      check original.certificateIdentityDigest == p.certificateIdentityDigest
      check original.resultDigest == p.resultDigest

  # -----------------------------------------------------------------------
  # Selection-scoped aggregates are NOT invariant: they differ full vs pruned
  # -----------------------------------------------------------------------
  test "selection-scoped aggregates differ between full and pruned":
    let full = makeFullResult()
    let projected = projectToSelected(full, @["A", "D"])

    # Full result's selectedUniverseRatio is 0.0 (uninitialized for full run)
    # or reflects full universe context — it is NOT the same as the pruned ratio.
    # The projected result carries the selection-scoped ratio.
    check projected.selectedUniverseRatio == 0.5
    check projected.selectedUniverseRatio != full.selectedUniverseRatio or
          full.selectedUniverseRatio == 0.0  # full run has no selection context yet

    # The selectionScopedReport carries the S/U ratio and aggregate counts
    check projected.selectionScopedReport.hasKey("selectedUniverseRatio")
    check projected.selectionScopedReport["selectedUniverseRatio"].getFloat == 0.5

    # Aggregate counts reflect the selection scope (2 selected, not 4)
    check projected.selectionScopedReport["selectedUnits"].getInt == 2
    check projected.selectionScopedReport["totalUnits"].getInt == 4

  # -----------------------------------------------------------------------
  # Negative: injecting a non-selected unit (C) into PrunedResult != projection
  # -----------------------------------------------------------------------
  test "PrunedResult with C injected does NOT equal the projection":
    let full = makeFullResult()
    let projected = projectToSelected(full, @["A", "D"])

    # Build a tampered PrunedResult that includes C (not in Selected)
    let tamperedUnits = @[
      makeUnitResult("A", psPass, "", "", "cert-A-digest"),
      makeUnitResult("D", psPass, "", "", "cert-D-digest"),
      makeUnitResult("C", psVacuousTrivial, "", "trivial-no-constraints", "cert-C-digest")
    ]
    let tamperedPruned = GlobalResult(
      unitResults: tamperedUnits,
      selectedUniverseRatio: 0.75,
      selectionInvariantProjection: @[],
      selectionScopedReport: %*{
        "totalUnits": 4, "selectedUnits": 3,
        "selectedUniverseRatio": 0.75,
        "passCount": 2, "failCount": 0, "timeoutCount": 0,
        "skipCount": 0, "errorCount": 0, "vacuousCount": 1})

    # The projection must NOT equal the tampered pruned result
    check projected.unitResults.len != tamperedPruned.unitResults.len

    # Also verify that the projection does not contain C
    check projected.unitResults.filterIt(it.unitId == "C").len == 0

  # -----------------------------------------------------------------------
  # Edge case: empty Selected → empty projection, ratio 0
  # -----------------------------------------------------------------------
  test "projectToSelected with empty Selected yields empty projection, ratio 0":
    let full = makeFullResult()
    let projected = projectToSelected(full, @[])

    check projected.unitResults.len == 0
    check projected.selectedUniverseRatio == 0.0
    check projected.selectionScopedReport["selectedUnits"].getInt == 0
    check projected.selectionScopedReport["totalUnits"].getInt == 4

  # -----------------------------------------------------------------------
  # Edge case: all units selected → projection == full result (unit-wise)
  # -----------------------------------------------------------------------
  test "projectToSelected with all units selected preserves all units":
    let full = makeFullResult()
    let projected = projectToSelected(full, @["A", "B", "C", "D"])

    check projected.unitResults.len == 4
    check projected.selectedUniverseRatio == 1.0
    check projected.selectionScopedReport["selectedUnits"].getInt == 4
