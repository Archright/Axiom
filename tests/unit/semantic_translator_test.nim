## Unit tests for verification/semantics/translator.nim
## Phase 1 of feature/k-induction-soundness refactor.

import std/unittest
import std/options
import std/strutils
import core/types/domain_types
import core/bmc/bmc_types
import verification/semantics/translator

suite "SemanticRuleBundle extraction":

  test "empty translation returns none/none with diagnosis":
    let t = UniversalTranslation(
      language: "nim",
      functionName: "pureAdd",
      logic: slQfLia,
      transitionRelation: @[],
      stateInvariants: @[]
    )
    let bundle = extractRuleBundle(t, "pureAdd", "func pureAdd(a, b: int): int = a + b")
    check bundle.transition.isNone
    check bundle.invariant.isNone
    check bundle.diagnosis.startsWith("empty_translation")

  test "pure function with no state returns none/none":
    # A pure function has no transition relation or invariants
    let t = UniversalTranslation(
      language: "nim",
      functionName: "double",
      logic: slQfLia,
      transitionRelation: @[],
      stateInvariants: @[]
    )
    let bundle = extractRuleBundle(t, "double", "func double(x: int): int = x * 2")
    check bundle.transition.isNone
    check bundle.invariant.isNone
    check "empty_translation" in bundle.diagnosis

  test "SMT-LIB invariant >= 0 extracts min-value rule":
    let t = UniversalTranslation(
      language: "nim",
      functionName: "withdraw",
      logic: slQfLia,
      transitionRelation: @[],
      stateInvariants: @["(>= balance 0)"]
    )
    let bundle = extractRuleBundle(t, "withdraw", "withdraw(bal, amt)")
    check bundle.invariant.isSome
    let inv = bundle.invariant.get()
    check inv.kind == invariantMinValue
    check inv.minValue == 0
    check bundle.diagnosis.len == 0  # no error

  test "SMT-LIB invariant <= 100 extracts max-value rule":
    let t = UniversalTranslation(
      language: "nim",
      functionName: "clamp",
      logic: slQfLia,
      transitionRelation: @[],
      stateInvariants: @["(<= x 100)"]
    )
    let bundle = extractRuleBundle(t, "clamp", "clamp(x)")
    check bundle.invariant.isSome
    let inv = bundle.invariant.get()
    check inv.kind == invariantMaxValue
    check inv.maxValue == 100

  test "transition with subtraction extracts subtract rule":
    let t = UniversalTranslation(
      language: "nim",
      functionName: "withdraw",
      logic: slQfLia,
      transitionRelation: @["(= bal' (- bal 5))"],
      stateInvariants: @[]
    )
    let bundle = extractRuleBundle(t, "withdraw", "bal -= 5")
    check bundle.transition.isSome
    let tr = bundle.transition.get()
    check tr.op == transitionSub
    check tr.delta == 5

  test "transition with addition extracts add rule":
    let t = UniversalTranslation(
      language: "nim",
      functionName: "deposit",
      logic: slQfLia,
      transitionRelation: @["(= bal' (+ bal 10))"],
      stateInvariants: @[]
    )
    let bundle = extractRuleBundle(t, "deposit", "bal += 10")
    check bundle.transition.isSome
    let tr = bundle.transition.get()
    check tr.op == transitionAdd
    check tr.delta == 10

  test "both transition and invariant extracted":
    let t = UniversalTranslation(
      language: "nim",
      functionName: "boundedWithdraw",
      logic: slQfLia,
      transitionRelation: @["(= bal' (- bal 1))"],
      stateInvariants: @["(>= bal 0)"]
    )
    let bundle = extractRuleBundle(t, "boundedWithdraw", "boundedWithdraw(bal)")
    check bundle.transition.isSome
    check bundle.invariant.isSome
    check bundle.transition.get().op == transitionSub
    check bundle.transition.get().delta == 1
    check bundle.invariant.get().kind == invariantMinValue

  test "unparseable entries return none with parse_failure diagnosis":
    let t = UniversalTranslation(
      language: "nim",
      functionName: "complexFn",
      logic: slQfLia,
      transitionRelation: @["some symbolic expression without numbers"],
      stateInvariants: @["(and (complex constraint))"]
    )
    let bundle = extractRuleBundle(t, "complexFn", "complexFn()")
    check bundle.transition.isNone
    check bundle.invariant.isNone
    check bundle.diagnosis.startsWith("parse_failure")

  test "bare >= N pattern parses correctly":
    let t = UniversalTranslation(
      language: "nim",
      functionName: "guard",
      logic: slQfLia,
      transitionRelation: @[],
      stateInvariants: @["count >= 42"]
    )
    let bundle = extractRuleBundle(t, "guard", "guard(count)")
    check bundle.invariant.isSome
    check bundle.invariant.get().minValue == 42

  test "bare <= N pattern parses correctly":
    let t = UniversalTranslation(
      language: "nim",
      functionName: "cap",
      logic: slQfLia,
      transitionRelation: @[],
      stateInvariants: @["count <= 999"]
    )
    let bundle = extractRuleBundle(t, "cap", "cap(count)")
    check bundle.invariant.isSome
    check bundle.invariant.get().maxValue == 999
