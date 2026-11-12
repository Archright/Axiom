## Unit tests for obligation IR types (obligation_types.nim + obligation_ir.nim).
## Uses custom main() pattern to avoid unittest framework cleanup crashes.

import std/[options, strutils, sequtils]
import verification/obligation/obligation_types
import verification/obligation/obligation_ir
import verification/obligation/no_obligation_provenance

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  template assertEq(a, b: untyped) =
    assert a == b, "Expected " & $b & " but got " & $a

  template assertNeq(a, b: untyped) =
    assert a != b, "Expected different values but both are " & $a

  # -----------------------------------------------------------------------
  # 1. LightNonEmptySeq — makeLightNonEmpty(@[]) 거부 (doAssert)
  # -----------------------------------------------------------------------
  echo "=== LightNonEmptySeq ==="

  check "makeLightNonEmpty(@[1]) succeeds":
    let seq = makeLightNonEmpty(@[1])
    assert seq.len == 1
    assert seq.items == @[1]
    assert seq.toSeq == @[1]

  check "makeLightNonEmpty(@[1,2,3]) len == 3":
    let seq = makeLightNonEmpty(@[1, 2, 3])
    assert seq.len == 3

  # -----------------------------------------------------------------------
  # 2. computeObligationId — same input → same value, different → different
  # -----------------------------------------------------------------------
  echo "=== computeObligationId determinism ==="

  check "same inputs produce same ID":
    let id1 = computeObligationId("foo", okSafetyDiv, "", "x > 0", "div-check")
    let id2 = computeObligationId("foo", okSafetyDiv, "", "x > 0", "div-check")
    assertEq(id1, id2)

  check "different subject produces different ID":
    let id1 = computeObligationId("foo", okSafetyDiv, "", "x > 0", "div-check")
    let id2 = computeObligationId("bar", okSafetyDiv, "", "x > 0", "div-check")
    assertNeq(id1, id2)

  check "different kind produces different ID":
    let id1 = computeObligationId("foo", okSafetyDiv, "", "x > 0", "div-check")
    let id2 = computeObligationId("foo", okSafetyIndex, "", "x > 0", "div-check")
    assertNeq(id1, id2)

  check "different predicate produces different ID":
    let id1 = computeObligationId("foo", okSafetyDiv, "", "x > 0", "div-check")
    let id2 = computeObligationId("foo", okSafetyDiv, "", "x >= 0", "div-check")
    assertNeq(id1, id2)

  check "different derivationRule produces different ID":
    let id1 = computeObligationId("foo", okSafetyDiv, "", "x > 0", "div-check")
    let id2 = computeObligationId("foo", okSafetyDiv, "", "x > 0", "index-check")
    assertNeq(id1, id2)

  # -----------------------------------------------------------------------
  # 3. 4-way variant — each state 생성/패턴 매칭 유효
  # -----------------------------------------------------------------------
  echo "=== ObligationGenerationResult 4-way variant ==="

  let testObl = VerificationObligation(
    id: "test-id",
    kind: okSafetyDiv,
    subject: "foo",
    assumptions: "",
    predicate: "",
    proposition: nil,
    derivationRule: "test-rule",
    provenance: "test"
  )
  let leq = makeLightNonEmpty(@[testObl])

  check "ogrGenerated pattern match works":
    let r = makeGenerated(leq)
    case r.kind
    of ogrGenerated:
      assert r.obligations.len == 1
    else:
      assert false, "Expected ogrGenerated"

  check "ogrNoApplicableObligation pattern match works":
    let prov = makeNoApplicableProvenance(@[okSafetyDiv], "rule-1", @["fact-1"])
    let r = makeNoApplicable(prov)
    case r.kind
    of ogrNoApplicableObligation:
      assert r.provenance.excludedClasses.len == 1
    else:
      assert false, "Expected ogrNoApplicableObligation"

  check "ogrUnsupported pattern match works":
    let r = makeUnsupported(usScopedRecursiveHeapNotModeled)
    case r.kind
    of ogrUnsupported:
      assert r.unsupportedReason == usScopedRecursiveHeapNotModeled
    else:
      assert false, "Expected ogrUnsupported"

  check "ogrIllFormed pattern match works":
    let r = makeIllFormed(ifUnknownSymbol)
    case r.kind
    of ogrIllFormed:
      assert r.illFormedReason == ifUnknownSymbol
    else:
      assert false, "Expected ogrIllFormed"

  # -----------------------------------------------------------------------
  # 4. UnsupportedReason — 폐쇄 목록 3개만 존재 (enum으로 보장)
  # -----------------------------------------------------------------------
  echo "=== UnsupportedReason closed list ==="

  check "UnsupportedReason has exactly 3 values":
    ## The enum definition has exactly 3 members.
    ## Any addition requires updating this count.
    assert UnsupportedReason.high.ord == 2, "UnsupportedReason must have exactly 3 values (0,1,2)"
    assert UnsupportedReason.low.ord == 0

  check "all 3 UnsupportedReason values are distinct":
    assert usScopedRecursiveHeapNotModeled != usScopedHigherOrderEffectNotModeled
    assert usScopedRecursiveHeapNotModeled != usScopedLanguageConstructNotModeled
    assert usScopedHigherOrderEffectNotModeled != usScopedLanguageConstructNotModeled

  # -----------------------------------------------------------------------
  # 5. phase/terminal 분리 — ProofPhase.terminal 시 terminal이 Some인지
  # -----------------------------------------------------------------------
  echo "=== phase/terminal separation ==="

  check "ppTerminal phase has Some terminal value":
    let outcome = ObligationOutcome(
      phase: ppTerminal,
      terminal: some(ptProved),
      detail: "proved"
    )
    assert outcome.terminal.isSome, "ppTerminal must have terminal = some"
    assert outcome.terminal.get == ptProved

  check "ppCandidate phase has none terminal":
    let outcome = ObligationOutcome(
      phase: ppCandidate,
      terminal: none(ProofTerminal),
      detail: "not yet decided"
    )
    assert outcome.terminal.isNone, "ppCandidate must have terminal = none"

  check "ppProofAttempted with ptInconclusive terminal":
    let outcome = ObligationOutcome(
      phase: ppProofAttempted,
      terminal: some(ptInconclusive),
      detail: "backend timeout"
    )
    assert outcome.terminal.isSome
    assert outcome.terminal.get == ptInconclusive

  check "ObligationOutcome detail field is independent of phase/terminal":
    let outcome = ObligationOutcome(
      phase: ppAnalyzed,
      terminal: none(ProofTerminal),
      detail: "analysis complete, awaiting decision"
    )
    assert outcome.detail == "analysis complete, awaiting decision"
    assert outcome.phase == ppAnalyzed
    assert outcome.terminal.isNone

  # -----------------------------------------------------------------------
  # 6. NoObligationProvenance — applicableClasses always empty
  # -----------------------------------------------------------------------
  echo "=== NoObligationProvenance ==="

  check "NoObligationProvenance applicableClasses is always empty":
    let prov = makeNoApplicableProvenance(@[okSafetyDiv], "rule-1", @["fact-1"])
    assert prov.applicableClasses.len == 0, "applicableClasses must always be empty"

  check "NoObligationProvenance excludedClasses preserved":
    let prov = makeNoApplicableProvenance(@[okSafetyDiv, okSafetyIndex], "rule-2", @[])
    assert prov.excludedClasses.len == 2

  check "NoObligationProvenance derivationRule preserved":
    let prov = makeNoApplicableProvenance(@[okSafetyDiv], "my-rule", @[])
    assert prov.derivationRule == "my-rule"

  check "NoObligationProvenance semanticFacts preserved":
    let prov = makeNoApplicableProvenance(@[okSafetyDiv], "rule-1", @["fact-a", "fact-b"])
    assert prov.semanticFacts.len == 2

  # -----------------------------------------------------------------------
  # 7. VerificationObligation — full construction and C4 identity
  # -----------------------------------------------------------------------
  echo "=== VerificationObligation ==="

  check "VerificationObligation computeId is deterministic":
    let obl = VerificationObligation(
      id: "",
      kind: okSafetyDiv,
      subject: "div_check",
      assumptions: "",
      predicate: "",
      proposition: nil,
      derivationRule: "div-zero-rule",
      provenance: "test-source"
    )
    let id1 = obl.computeId()
    let id2 = obl.computeId()
    assertEq(id1, id2)

  check "VerificationObligation computeId differs for different subjects":
    let obl1 = VerificationObligation(
      id: "", kind: okSafetyDiv, subject: "foo",
      assumptions: "", predicate: "",
      proposition: nil,
      derivationRule: "rule", provenance: "src"
    )
    let obl2 = VerificationObligation(
      id: "", kind: okSafetyDiv, subject: "bar",
      assumptions: "", predicate: "",
      proposition: nil,
      derivationRule: "rule", provenance: "src"
    )
    assertNeq(obl1.computeId(), obl2.computeId())

  # -----------------------------------------------------------------------
  # Summary
  # -----------------------------------------------------------------------
  echo ""
  echo "=== Results ==="
  echo "  Passed: " & $passed
  echo "  Failed: " & $failed
  if failed > 0:
    echo "  FAILED"
    quit(1)
  else:
    echo "  ALL PASSED"

when isMainModule:
  main()
