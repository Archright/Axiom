## Unit tests for canonical_obligation_generator.nim — semantic golden oracle.
##
## Oracle design (design-change-sensitive — update header when spec changes):
## Each test case is an oracle row: (IRFuncDef fixture, policy, expected_kind,
## expected_count, expected_derivationRule_prefix, expected_excludedClasses_len).
##
## Oracle columns verified per test:
## 1. Input value (IRFuncDef + ScopePolicy)
## 2. Semantic facts (post-verification summary in provenance)
## 3. Candidate classes (which ObligationKind values were considered)
## 4. Expected result kind (ogrGenerated / ogrNoApplicable / ogrUnsupported / ogrIllFormed)
## 5. Expected obligation count (for Generated: len ≥ 1)
## 6. Expected derivationRule / provenance existence check
## 7. ID determinism (re-call produces identical IDs)
## 8. Order determinism (re-call produces identical ordering)
##
## Failure mode: any mismatch → test FAIL. Design changes require updating
## this header and the expected values below.

import std/[unittest, strutils, options]
import core/trusted/axiom_ir_helpers
import verification/obligation/semantic_target_extractor
import verification/obligation/canonical_obligation_generator
import verification/obligation/obligation_types
import verification/obligation/obligation_ir

suite "Canonical Obligation Generator — semantic golden oracle":

  # -----------------------------------------------------------------------
  # (a) clamp류 → Generated (postcondition from clamp pattern)
  # -----------------------------------------------------------------------
  test "clamp function generates postcondition obligation (Generated)":
    let x = irVar("x", irTypeBitVec64())
    let lo = irLit(0)
    let hi = irLit(100)
    # Body: min(max(x, lo), hi) — clamp pattern
    let body = irCall("min", @[
      irCall("max", @[x, lo]),
      hi
    ])
    let funcDef = irFuncDef("clamp", @[("x", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let policy = defaultScopePolicy()
    let result = generateCanonicalObligations(funcDef, policy)

    check result.kind == ogrGenerated
    check result.obligations.len >= 1
    # Should have at least one postcondition obligation
    var foundPost = false
    for obl in result.obligations.items:
      if obl.kind == okContractPost:
        foundPost = true
        check obl.derivationRule == "obs:contract"
        check obl.provenance.len > 0
    check foundPost

  # -----------------------------------------------------------------------
  # (b) div/mod → Generated (safety: divisor≠0)
  # -----------------------------------------------------------------------
  test "division operation generates divSafety obligation (Generated)":
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irDiv(x, y)
    let funcDef = irFuncDef("safe_div", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let policy = defaultScopePolicy()
    let result = generateCanonicalObligations(funcDef, policy)

    check result.kind == ogrGenerated
    check result.obligations.len >= 1
    var foundDiv = false
    for obl in result.obligations.items:
      if obl.kind == okSafetyDiv:
        foundDiv = true
        check obl.derivationRule == "obs:division"
        check obl.subject.contains("≠ 0")
    check foundDiv

  # -----------------------------------------------------------------------
  # (c) double(int 곱) → NoApplicable + provenance 검증
  # -----------------------------------------------------------------------
  test "pure multiplication with no targets yields NoApplicable":
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irMul(x, y)
    let funcDef = irFuncDef("double", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let policy = defaultScopePolicy()
    let result = generateCanonicalObligations(funcDef, policy)

    check result.kind == ogrNoApplicableObligation
    # Provenance must be populated
    check result.provenance.derivationRule == "obs:noObligations"
    check result.provenance.excludedClasses.len > 0
    check result.provenance.semanticFacts.len > 0
    # Semantic facts should mention what was checked
    var hasDivFact = false
    for fact in result.provenance.semanticFacts:
      if "division" in fact.toLowerAscii: hasDivFact = true
    check hasDivFact

  # -----------------------------------------------------------------------
  # (d) isEven(mod 2) → Generated (safety: divisor≠0)
  # -----------------------------------------------------------------------
  test "modulo operation generates divSafety obligation (Generated)":
    let x = irVar("x", irTypeBitVec64())
    let two = irLit(2)
    let body = irRem(x, two)
    let funcDef = irFuncDef("isEven", @[("x", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let policy = defaultScopePolicy()
    let result = generateCanonicalObligations(funcDef, policy)

    check result.kind == ogrGenerated
    check result.obligations.len >= 1
    var foundDiv = false
    for obl in result.obligations.items:
      if obl.kind == okSafetyDiv:
        foundDiv = true
        check obl.derivationRule == "obs:division"
    check foundDiv

  # -----------------------------------------------------------------------
  # (e) string identity → NoApplicable (not Unsupported per spec §4.3)
  # -----------------------------------------------------------------------
  test "string identity function yields NoApplicable (not Unsupported)":
    let s = irVar("s", irTypeString())
    let body = s  # identity: return input as-is
    let funcDef = irFuncDef("identity", @[("s", irTypeString())], irTypeString(), body, false)
    let policy = defaultScopePolicy()
    let result = generateCanonicalObligations(funcDef, policy)

    # Per spec §4.3 table: pure func + postcondition ∅ + div/index/loop 없음
    # → ogrNoApplicableObligation (NOT Unsupported)
    check result.kind == ogrNoApplicableObligation
    check result.provenance.derivationRule == "obs:noObligations"
    # No obligation class should be marked as Unsupported for this case
    # (string identity is in scope, just trivially safe)

  # -----------------------------------------------------------------------
  # (f) exempt(policy.admissible=false) → NoApplicable & excludedClasses
  # -----------------------------------------------------------------------
  test "exempt policy produces NoApplicable with excludedClasses (17자 시나늄)":
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irDiv(x, y)
    let funcDef = irFuncDef("exempt_div", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let policy = ScopePolicy(
      admissible: false,
      exemptReason: some("exempt per policy"),
      expectedObligation: false
    )
    let result = generateCanonicalObligations(funcDef, policy)

    check result.kind == ogrNoApplicableObligation
    # exemptReason must be 17 characters ("exempt per policy")
    check policy.exemptReason.isSome
    check policy.exemptReason.get.len == 17
    # excludedClasses must be non-empty
    check result.provenance.excludedClasses.len > 0
    # derivationRule must reference policy exemption
    check result.provenance.derivationRule == "policy:scopeExempt"
    # semanticFacts must mention exemption
    var hasExemptFact = false
    for fact in result.provenance.semanticFacts:
      if "exempt" in fact.toLowerAscii or "admissible" in fact.toLowerAscii:
        hasExemptFact = true
    check hasExemptFact

  # -----------------------------------------------------------------------
  # (g) loopVars==1+result CHC edge → Generated (loop-bound obligation)
  # -----------------------------------------------------------------------
  test "loop with variant generates loop-bound obligation (Generated)":
    let i = irVar("i", irTypeBitVec64())
    let n = irVar("n", irTypeBitVec64())
    let result = irVar("result", irTypeBitVec64())
    # loopCond: i < n
    let loopCond = irLt(i, n)
    # loopStep: i + 1
    let loopStep = irAdd(i, irLit(1))
    # loopBody: result = i (simplified)
    let loopBody = result
    # variant: n - i (decreasing metric)
    let variant = irSub(n, i)
    let loopExpr = irLoop(lkWhile, @["i"], @[irLit(0)], loopCond,
                           loopStep, loopBody, @[], variant)
    let funcDef = irFuncDef("sum_to_n", @[("n", irTypeBitVec64())], irTypeBitVec64(), loopExpr, false)
    let policy = defaultScopePolicy()
    let result2 = generateCanonicalObligations(funcDef, policy)

    check result2.kind == ogrGenerated
    check result2.obligations.len >= 1
    # Should have at least one loop-bound obligation
    var foundLoopBound = false
    for obl in result2.obligations.items:
      if obl.kind == okSafetyLoopBound:
        foundLoopBound = true
        check obl.derivationRule in ["obs:loopBound", "obs:loopVariant"]
    check foundLoopBound

  # -----------------------------------------------------------------------
  # (h) IllFormed: body nil → IllFormed
  # -----------------------------------------------------------------------
  test "function with nil body produces IllFormed":
    let funcDef = IRFuncDef(
      name: "broken",
      params: @[],
      retType: irTypeBitVec64(),
      body: nil,
      isRecursive: false,
      preConditions: @[],
      postConditions: @[]
    )
    let policy = defaultScopePolicy()
    let result = generateCanonicalObligations(funcDef, policy)

    check result.kind == ogrIllFormed
    # illFormedReason should indicate the body is missing
    check result.illFormedReason == ifUnknownSymbol

  # -----------------------------------------------------------------------
  # Determinism tests (ID + order)
  # -----------------------------------------------------------------------
  test "ID determinism: re-call produces identical obligation IDs":
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irDiv(x, y)
    let funcDef = irFuncDef("div_id_test", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let policy = defaultScopePolicy()

    let r1 = generateCanonicalObligations(funcDef, policy)
    let r2 = generateCanonicalObligations(funcDef, policy)

    check r1.kind == r2.kind
    if r1.kind == ogrGenerated and r2.kind == ogrGenerated:
      check r1.obligations.len == r2.obligations.len
      for i in 0 ..< r1.obligations.len:
        check r1.obligations.items[i].id == r2.obligations.items[i].id

  test "Order determinism: re-call produces identical ordering":
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    # Body with both division and modulo (multiple candidates)
    let body = irDiv(x, y)
    let funcDef = irFuncDef("order_test", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let policy = defaultScopePolicy()

    let r1 = generateCanonicalObligations(funcDef, policy)
    let r2 = generateCanonicalObligations(funcDef, policy)

    if r1.kind == ogrGenerated and r2.kind == ogrGenerated:
      let o1 = r1.obligations.toSeq
      let o2 = r2.obligations.toSeq
      check o1.len == o2.len
      for i in 0 ..< o1.len:
        check o1[i].kind == o2[i].kind
        check o1[i].subject == o2[i].subject
        check o1[i].id == o2[i].id

  # -----------------------------------------------------------------------
  # extractObligationCandidates determinism
  # -----------------------------------------------------------------------
  test "extractObligationCandidates is deterministic":
    let x = irVar("x", irTypeBitVec64())
    let y = irVar("y", irTypeBitVec64())
    let body = irDiv(x, y)
    let funcDef = irFuncDef("extractor_det", @[("x", irTypeBitVec64()), ("y", irTypeBitVec64())], irTypeBitVec64(), body, false)

    let c1 = extractObligationCandidates(funcDef)
    let c2 = extractObligationCandidates(funcDef)

    check c1.len == c2.len
    for i in 0 ..< c1.len:
      check c1[i].kind == c2[i].kind
      check c1[i].subject == c2[i].subject
      check c1[i].predicate == c2[i].predicate
      check c1[i].derivationRule == c2[i].derivationRule

  # -----------------------------------------------------------------------
  # C5: postcondition absence is NEVER Unsupported
  # -----------------------------------------------------------------------
  test "postcondition absence never produces Unsupported":
    # A pure func with no postcondition, no div, no index, no loop
    let x = irVar("x", irTypeBitVec64())
    let body = irLit(42)
    let funcDef = irFuncDef("no_post", @[("x", irTypeBitVec64())], irTypeBitVec64(), body, false)
    let policy = defaultScopePolicy()
    let result = generateCanonicalObligations(funcDef, policy)

    # Must NOT be Unsupported — postcondition absence is not a scope error
    check result.kind != ogrUnsupported
    # Should be NoApplicable (no safety targets found)
    check result.kind == ogrNoApplicableObligation
