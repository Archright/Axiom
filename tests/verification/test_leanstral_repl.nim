{.push raises: [CatchableError].}

## Leanstral REPL Tests — Unit tests for verification/leanstral_repl.nim
## Tests exported types, buildReplPromptFromFeedback, and buildHealingPrompt.
## REPL-dependent procs (tryLeanstralReplSynthesis) are skipped — they need a live REPL.

import std/[unittest, strutils]
import verification/leanstral_repl

# ---------------------------------------------------------------------------
# TacticModeEntry type
# ---------------------------------------------------------------------------

suite "TacticModeEntry type":
  test "construction with values":
    let entry = TacticModeEntry(
      proofState: 42,
      env: 1,
      goals: @["⊢ Invariant (Run steps amount initialBalance)"]
    )
    check entry.proofState == 42
    check entry.env == 1
    check entry.goals.len == 1
    check "Invariant" in entry.goals[0]

  test "construction with empty goals":
    let entry = TacticModeEntry(proofState: 0, env: -1, goals: @[])
    check entry.goals.len == 0

# ---------------------------------------------------------------------------
# ReplFeedback type
# ---------------------------------------------------------------------------

suite "ReplFeedback type":
  test "construction with full fields":
    let fb = ReplFeedback(
      proofState: 5,
      goals: @["⊢ Nat"],
      proofStatus: "Goals accomplished",
      error: "",
      diagnostics: @["warning: unused variable"]
    )
    check fb.proofState == 5
    check fb.proofStatus == "Goals accomplished"
    check fb.error.len == 0
    check fb.diagnostics.len == 1

  test "construction with error":
    let fb = ReplFeedback(
      proofState: -1,
      goals: @[],
      proofStatus: "",
      error: "unknown tactic 'bad'",
      diagnostics: @[]
    )
    check fb.error == "unknown tactic 'bad'"
    check fb.proofStatus.len == 0

  test "empty construction":
    let fb = ReplFeedback()
    check fb.proofState == 0
    check fb.goals.len == 0
    check fb.error.len == 0

# ---------------------------------------------------------------------------
# LeanstralReplResult type
# ---------------------------------------------------------------------------

suite "LeanstralReplResult type":
  test "default construction (failure)":
    let r = LeanstralReplResult()
    check r.success == false
    check r.rounds == 0
    check r.tacticTrace.len == 0

  test "successful construction":
    let r = LeanstralReplResult(
      success: true,
      theoremSource: "theorem foo : True := by trivial",
      tacticTrace: @["trivial"],
      rounds: 1,
      diagnostics: "done",
      rawOutput: ""
    )
    check r.success == true
    check "theorem" in r.theoremSource
    check r.tacticTrace.len == 1
    check r.rounds == 1

# ---------------------------------------------------------------------------
# buildReplPromptFromFeedback
# ---------------------------------------------------------------------------

suite "buildReplPromptFromFeedback":
  test "includes base prompt":
    let result = buildReplPromptFromFeedback("solve this", @[], "", 1)
    check "solve this" in result
    check "Round 1" in result

  test "includes goals when present":
    let goals = @["⊢ Invariant (Run steps amount initialBalance)"]
    let result = buildReplPromptFromFeedback("base", goals, "", 1)
    check "Current goals:" in result
    check "Invariant" in result

  test "includes previous error when present":
    let result = buildReplPromptFromFeedback("base", @[], "tactic failed", 2)
    check "Previous error:" in result
    check "tactic failed" in result

  test "round number is correct":
    let result = buildReplPromptFromFeedback("base", @[], "", 5)
    check "Round 5" in result

  test "empty goals and no error":
    let result = buildReplPromptFromFeedback("prompt", @[], "", 1)
    check "Current goals:" notin result
    check "Previous error:" notin result
    check "prompt" in result

  test "multiple goals":
    let goals = @["⊢ goal1", "⊢ goal2", "⊢ goal3"]
    let result = buildReplPromptFromFeedback("base", goals, "", 1)
    check "goal1" in result
    check "goal2" in result
    check "goal3" in result

  test "instruction to output only tactic":
    let result = buildReplPromptFromFeedback("base", @[], "", 1)
    check "ONLY the tactic" in result

# ---------------------------------------------------------------------------
# buildHealingPrompt
# ---------------------------------------------------------------------------

suite "buildHealingPrompt":
  test "includes base prompt":
    let result = buildHealingPrompt("base prompt", @[], "error msg", 1)
    check "base prompt" in result
    check "Attempt 1/3" in result

  test "includes compiler error":
    let result = buildHealingPrompt("base", @[], "type mismatch", 2)
    check "compiler error" in result
    check "type mismatch" in result

  test "includes goals when present":
    let goals = @["⊢ Invariant x"]
    let result = buildHealingPrompt("base", goals, "err", 1)
    check "Current goals:" in result
    check "Invariant x" in result

  test "attempt number is correct":
    let result = buildHealingPrompt("base", @[], "err", 3)
    check "Attempt 3/3" in result

  test "instruction to output corrected single tactic":
    let result = buildHealingPrompt("base", @[], "err", 1)
    check "corrected single tactic" in result
    check "ONLY the tactic" in result

{.pop.}
