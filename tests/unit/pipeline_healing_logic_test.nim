## pipeline_healing_logic_test.nim
## Comprehensive tests for pipeline_healing_logic.nim — the pipeline healing layer.
##
## Coverage:
##   - extractGoalLinesFromCompilerOutput: goal-line extraction + dedup
##   - mergeInvariantClauses: invariant clause merging + dedup
##   - strengthenInvariantFromLeanHints: Lean hint → invariant strengthening
##   - buildLeanHintAssertions: Lean hint → Nim assertion generation
##   - synthesizeLeanFallbackHints: fallback hint synthesis from compiler output
##   - injectNimAssertions: source code assertion injection

import std/[strutils, unittest]

import core/logic/pipeline_healing_logic
import core/logic/lean_diagnostic
import core/types/translation_types

# ─── Helpers ──────────────────────────────────────────────────────────────────

proc emptyTranslation(): UniversalTranslation =
  ## Minimal UniversalTranslation with no transition invariants.
  result = UniversalTranslation(
    transitionInvariants: @[]
  )

proc translationWith*(invariants: seq[string]): UniversalTranslation =
  ## Translation with specified transition invariants.
  result = UniversalTranslation(
    transitionInvariants: invariants
  )

# ─── extractGoalLinesFromCompilerOutput ───────────────────────────────────────

suite "extractGoalLinesFromCompilerOutput":

  test "empty input returns empty seq":
    let goals = extractGoalLinesFromCompilerOutput("")
    check goals.len == 0

  test "no goal-like lines returns empty seq":
    let goals = extractGoalLinesFromCompilerOutput("hello world\nnothing here")
    check goals.len == 0

  test "extracts lines containing turnstile character":
    let goals = extractGoalLinesFromCompilerOutput("⊢ x = 0")
    check goals.len == 1
    check goals[0] == "⊢ x = 0"

  test "extracts lines containing unicode less-than-or-equal":
    let goals = extractGoalLinesFromCompilerOutput("x ≤ y")
    check goals.len == 1
    check goals[0] == "x ≤ y"

  test "extracts lines containing <= token":
    let goals = extractGoalLinesFromCompilerOutput("amount <= balance")
    check goals.len == 1
    check goals[0] == "amount <= balance"

  test "extracts lines with unsolved goals tokens":
    let goals = extractGoalLinesFromCompilerOutput("error: unsolved goals")
    check goals.len == 1
    check goals.contains("error: unsolved goals")

  test "extracts lines with goal token":
    let goals = extractGoalLinesFromCompilerOutput("remaining goal: prove x > 0")
    check goals.len == 1

  test "extracts lines with goals token":
    let goals = extractGoalLinesFromCompilerOutput("2 goals remaining")
    check goals.len == 1

  test "deduplicates identical goal lines":
    let output = "⊢ x = 0\n⊢ x = 0\n⊢ x = 0"
    let goals = extractGoalLinesFromCompilerOutput(output)
    check goals.len == 1

  test "mixes multiple match criteria without duplication":
    let output = "⊢ x = 0\nerror: unsolved goals\n⊢ x = 0"
    let goals = extractGoalLinesFromCompilerOutput(output)
    check goals.len == 2
    check goals.contains("⊢ x = 0")
    check goals.contains("error: unsolved goals")

  test "handles lines with different match types correctly":
    let output = "x ≤ y\namount <= balance\n⊢ z = 0"
    let goals = extractGoalLinesFromCompilerOutput(output)
    check goals.len == 3

  test "filters out non-matching lines mixed with goal lines":
    let output = "normal line\n⊢ goal1\nnoise\namount <= balance\nmore noise"
    let goals = extractGoalLinesFromCompilerOutput(output)
    check goals.len == 2

  test "handles whitespace-only lines gracefully":
    let output = "  \t  \n⊢ x\n   "
    let goals = extractGoalLinesFromCompilerOutput(output)
    check goals.len == 1
    check goals[0] == "⊢ x"

  test "strips whitespace from lines before matching":
    let output = "  ⊢ x = 0  "
    let goals = extractGoalLinesFromCompilerOutput(output)
    check goals.len == 1

# ─── mergeInvariantClauses ────────────────────────────────────────────────────

suite "mergeInvariantClauses":

  test "both empty returns empty string":
    check mergeInvariantClauses("", "") == ""

  test "empty base returns stripped extra":
    check mergeInvariantClauses("", "b") == "b"

  test "empty extra returns stripped base":
    check mergeInvariantClauses("a", "") == "a"

  test "merges two unique conjuncts":
    check mergeInvariantClauses("a", "b") == "a ∧ b"

  test "deduplicates existing conjunct":
    check mergeInvariantClauses("a ∧ b", "b") == "a ∧ b"

  test "appends multiple missing conjuncts":
    check mergeInvariantClauses("a", "b ∧ c") == "a ∧ b ∧ c"

  test "deduplicates when extra is subset of base":
    check mergeInvariantClauses("a ∧ b ∧ c", "a ∧ b") == "a ∧ b ∧ c"

  test "handles whitespace in conjuncts":
    check mergeInvariantClauses("  a  ", "  b  ") == "a ∧ b"

  test "single character conjuncts":
    check mergeInvariantClauses("x", "y") == "x ∧ y"

  test "handles special characters in conjuncts":
    check mergeInvariantClauses("x >= 0", "y <= 10") == "x >= 0 ∧ y <= 10"

# ─── strengthenInvariantFromLeanHints ─────────────────────────────────────────

suite "strengthenInvariantFromLeanHints":

  test "empty hints returns base invariant unchanged":
    let strengthened = strengthenInvariantFromLeanHints(
      "base_inv", emptyTranslation(), @[]
    )
    check strengthened == "base_inv"

  test "hint with amount+balance+<= adds amount balance guard":
    let strengthened = strengthenInvariantFromLeanHints(
      "", emptyTranslation(),
      @["Pre-condition suggestion: amount <= balance"]
    )
    check strengthened.contains("amount <= state.balance")

  test "hint with >= symbol adds lower bound invariant":
    let strengthened = strengthenInvariantFromLeanHints(
      "", emptyTranslation(),
      @["some invariant with >= 0"]
    )
    check strengthened.contains("0 <= state.balance")

  test "hint with unicode >= adds lower bound invariant":
    let strengthened = strengthenInvariantFromLeanHints(
      "", emptyTranslation(),
      @["value ≥ 0"]
    )
    check strengthened.contains("0 <= state.balance")

  test "hint with always/ge/zero tokens adds lower bound invariant":
    let strengthened = strengthenInvariantFromLeanHints(
      "", emptyTranslation(),
      @["always ge zero"]
    )
    check strengthened.contains("0 <= state.balance")

  test "hint with zero_le token adds lower bound invariant":
    let strengthened = strengthenInvariantFromLeanHints(
      "", emptyTranslation(),
      @["zero_le check"]
    )
    check strengthened.contains("0 <= state.balance")

  test "hint with transition/invariant tokens triggers transition check":
    let translation = translationWith(@["next.balance <= state.balance"])
    let strengthened = strengthenInvariantFromLeanHints(
      "", translation,
      @["transition invariant"]
    )
    check strengthened.contains("next.balance <= state.balance")

  test "no matching transition invariant in translation does not add transition clause":
    let translation = translationWith(@["next.x <= state.x"])
    let strengthened = strengthenInvariantFromLeanHints(
      "", translation,
      @["transition invariant"]
    )
    check not strengthened.contains("next.balance <= state.balance")

  test "empty transition invariants list does not add transition clause":
    let translation = translationWith(@[])
    let strengthened = strengthenInvariantFromLeanHints(
      "", translation,
      @["transition invariant"]
    )
    check not strengthened.contains("next.balance")

  test "multiple hints combine all matching invariant clauses":
    let translation = translationWith(@["next.balance <= state.balance"])
    let strengthened = strengthenInvariantFromLeanHints(
      "", translation,
      @[
        "amount <= balance",
        "value >= 0",
        "transition invariant"
      ]
    )
    check strengthened.contains("amount <= state.balance")
    check strengthened.contains("0 <= state.balance")
    check strengthened.contains("next.balance <= state.balance")

  test "preserves base invariant when adding new clauses":
    let strengthened = strengthenInvariantFromLeanHints(
      "x > 0", emptyTranslation(),
      @["amount <= balance"]
    )
    check strengthened.contains("x > 0")
    check strengthened.contains("amount <= state.balance")

  test "hint that matches nothing produces no additional clauses":
    let strengthened = strengthenInvariantFromLeanHints(
      "base", emptyTranslation(),
      @["unrelated hint text"]
    )
    check strengthened == "base"

  test "dedup does not add same clause twice":
    let strengthened = strengthenInvariantFromLeanHints(
      "amount <= state.balance", emptyTranslation(),
      @["amount <= balance"]
    )
    # Should not have duplicate "amount <= state.balance"
    let count = strengthened.count("amount <= state.balance")
    check count == 1

# ─── buildLeanHintAssertions ──────────────────────────────────────────────────

suite "buildLeanHintAssertions":

  test "empty hints returns empty seq":
    let assertions = buildLeanHintAssertions("proc f() = discard", @[])
    check assertions.len == 0

  test "hint with amount balance adds doAssert amount <= balance":
    let assertions = buildLeanHintAssertions(
      "proc f() = discard",
      @["amount <= balance"]
    )
    check assertions.contains("doAssert amount <= balance")

  test "hint with ge zero adds doAssert balance >= 0":
    let assertions = buildLeanHintAssertions(
      "proc f() = discard",
      @["value >= 0"]
    )
    check assertions.contains("doAssert balance >= 0")

  test "hint with unicode >= adds balance >= 0 assertion":
    let assertions = buildLeanHintAssertions(
      "proc f() = discard",
      @["value ≥ 0"]
    )
    check assertions.contains("doAssert balance >= 0")

  test "hint with zero_le adds balance >= 0 assertion":
    let assertions = buildLeanHintAssertions(
      "proc f() = discard",
      @["zero_le invariant"]
    )
    check assertions.contains("doAssert balance >= 0")

  test "source already has amount guard skips amount assertion":
    let assertions = buildLeanHintAssertions(
      "proc f() =\n  doassert amount <= balance\n  discard",
      @["amount <= balance"]
    )
    check not assertions.contains("doAssert amount <= balance")

  test "source already has balance guard skips balance assertion":
    let assertions = buildLeanHintAssertions(
      "proc f() =\n  doassert balance >= 0\n  discard",
      @["value >= 0"]
    )
    check not assertions.contains("doAssert balance >= 0")

  test "source has both guards skips both assertions":
    let assertions = buildLeanHintAssertions(
      "proc f() =\n  doassert amount <= balance\n  doassert balance >= 0\n  discard",
      @["amount <= balance", "value >= 0"]
    )
    check assertions.len == 0

  test "unrelated hint produces no assertions":
    let assertions = buildLeanHintAssertions(
      "proc f() = discard",
      @["something unrelated"]
    )
    check assertions.len == 0

  test "multiple hints produce multiple assertions when applicable":
    let assertions = buildLeanHintAssertions(
      "proc f() = discard",
      @["amount <= balance", "value >= 0"]
    )
    check assertions.len == 2
    check assertions.contains("doAssert amount <= balance")
    check assertions.contains("doAssert balance >= 0")

# ─── synthesizeLeanFallbackHints ──────────────────────────────────────────────

suite "synthesizeLeanFallbackHints":

  test "no unsolved goals returns empty":
    let hints = synthesizeLeanFallbackHints("src", "inv", "all good")
    check hints.len == 0

  test "empty compiler output returns empty":
    let hints = synthesizeLeanFallbackHints("src", "inv", "")
    check hints.len == 0

  test "unsolved goals alone with no matching patterns returns empty":
    let hints = synthesizeLeanFallbackHints(
      "proc f() = discard",
      "",
      "error: unsolved goals"
    )
    check hints.len == 0

  test "amount balance in invariant adds precondition guard hint":
    let hints = synthesizeLeanFallbackHints(
      "proc f() = discard",
      "amount <= balance",
      "error: unsolved goals"
    )
    check hints.contains(hintPreConditionGuard)

  test "amount balance in output adds precondition guard hint":
    let hints = synthesizeLeanFallbackHints(
      "proc f() = discard",
      "",
      "unsolved goals\namount <= balance"
    )
    check hints.contains(hintPreConditionGuard)

  test "balance >= in invariant adds lower bound hint":
    let hints = synthesizeLeanFallbackHints(
      "proc f() = discard",
      "balance >= 0",
      "error: unsolved goals"
    )
    check hints.contains(hintLowerBoundInvariant)

  test "unicode >= in output adds lower bound hint":
    let hints = synthesizeLeanFallbackHints(
      "proc f() = discard",
      "",
      "unsolved goals\nbalance ≥ 0"
    )
    check hints.contains(hintLowerBoundInvariant)

  test "transition in invariant adds strengthening hint":
    let hints = synthesizeLeanFallbackHints(
      "proc f() = discard",
      "next balance <= state",
      "error: unsolved goals"
    )
    check hints.contains(hintInvariantStrengthening)

  test "transition amount balance in output adds strengthening hint":
    let hints = synthesizeLeanFallbackHints(
      "proc f() = discard",
      "",
      "unsolved goals\ntransition amount balance"
    )
    check hints.contains(hintInvariantStrengthening)

  test "turnstile invariant transition in output triggers strengthening hint":
    let hints = synthesizeLeanFallbackHints(
      "proc f() = discard",
      "",
      "unsolved goals\n⊢ invariant (transition amount balance)"
    )
    check hints.contains(hintInvariantStrengthening)

  test "source with existing amount guard skips precondition hint":
    let hints = synthesizeLeanFallbackHints(
      "proc f() =\n  doassert amount <= balance\n  discard",
      "amount <= balance",
      "error: unsolved goals"
    )
    check not hints.contains(hintPreConditionGuard)

  test "source with existing balance guard skips lower bound hint":
    let hints = synthesizeLeanFallbackHints(
      "proc f() =\n  doassert balance >= 0\n  discard",
      "balance >= 0",
      "error: unsolved goals"
    )
    check not hints.contains(hintLowerBoundInvariant)

  test "all three hint categories appear when all conditions met":
    let hints = synthesizeLeanFallbackHints(
      "proc f() = discard",
      "next balance <= amount <= balance",
      "error: unsolved goals\namount balance <=\nbalance >= 0\ntransition amount balance"
    )
    check hints.len == 3
    check hints.contains(hintPreConditionGuard)
    check hints.contains(hintLowerBoundInvariant)
    check hints.contains(hintInvariantStrengthening)

  test "zero_le in invariant adds lower bound hint":
    let hints = synthesizeLeanFallbackHints(
      "proc f() = discard",
      "balance zero_le",
      "error: unsolved goals"
    )
    check hints.contains(hintLowerBoundInvariant)

# ─── injectNimAssertions ──────────────────────────────────────────────────────

suite "injectNimAssertions":

  test "empty assertions returns source unchanged":
    let result = injectNimAssertions("proc f() =\n  discard", @[])
    check not result.changed
    check result.updated == "proc f() =\n  discard"

  test "empty source with assertions appends at end":
    let result = injectNimAssertions("", @["doAssert x > 0"])
    check result.changed
    check result.updated.endsWith("doAssert x > 0")

  test "inserts assertion after function header ending with =":
    let result = injectNimAssertions(
      "proc f() =\n  discard",
      @["doAssert x > 0"]
    )
    check result.changed
    check result.updated.contains("proc f() =")
    check result.updated.contains("doAssert x > 0")
    check result.updated.contains("discard")

  test "preserves indentation of the = line":
    let result = injectNimAssertions(
      "  proc f() =\n    discard",
      @["doAssert x > 0"]
    )
    check result.changed
    check result.updated.contains("    doAssert x > 0")

  test "inserts only at the first = line":
    let result = injectNimAssertions(
      "proc f() =\n  let x = 1\n  discard",
      @["doAssert x > 0"]
    )
    check result.changed
    # The assertion should be inserted after the first line ending with =
    let lines = result.updated.split("\n")
    check lines[0] == "proc f() ="
    check lines[1] == "  doAssert x > 0"

  test "multiple assertions are all inserted":
    let result = injectNimAssertions(
      "proc f() =\n  discard",
      @["doAssert x > 0", "doAssert y >= 0"]
    )
    check result.changed
    check result.updated.contains("doAssert x > 0")
    check result.updated.contains("doAssert y >= 0")

  test "no = line appends assertions at end":
    let result = injectNimAssertions(
      "let x = 1",
      @["doAssert x > 0"]
    )
    check result.changed
    check result.updated.endsWith("doAssert x > 0")

  test "handles lines ending with = and spaces":
    let result = injectNimAssertions(
      "proc f() =  \n  discard",
      @["doAssert x > 0"]
    )
    check result.changed
    check result.updated.contains("doAssert x > 0")

  test "multi-line source inserts after first matching = line":
    let source = "import std/unittest\n\nproc transfer() =\n  let x = 1\n  discard"
    let result = injectNimAssertions(
      source,
      @["doAssert balance >= 0"]
    )
    check result.changed
    # Should be inserted after "proc transfer() =" line
    let lines = result.updated.split("\n")
    var foundInsertion = false
    for i in 0 ..< lines.len:
      if lines[i].strip().endsWith("=") and lines[i].contains("transfer"):
        check lines[i + 1].contains("doAssert balance >= 0")
        foundInsertion = true
        break
    check foundInsertion

  test "assertions added at end have no extra indentation":
    let result = injectNimAssertions(
      "let x = 1",
      @["doAssert y"]
    )
    check result.changed
    check result.updated.endsWith("doAssert y")
