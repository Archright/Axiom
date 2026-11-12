import std/[unittest, strutils]
import core/types/results
import core/judge/the_judge_eval
import core/judge/lean_replay
import core/judge/smart_search
import core/types/hubs/judge_hub

suite "parseUnsatCore":
  test "extracts hypothesis IDs from parenthesized list":
    let output = "unsat\n(h0 h1 h2)"
    let core = parseUnsatCore(output)
    check core.len == 3
    check core[0] == "h0"
    check core[1] == "h1"
    check core[2] == "h2"

  test "handles empty core":
    let core = parseUnsatCore("unsat\n()")
    check core.len == 0

  test "handles single hypothesis":
    let core = parseUnsatCore("unsat\n(h0)")
    check core.len == 1
    check core[0] == "h0"

  test "ignores non-parenthesized lines":
    let output = "unsat\n(h0)\nsat"
    let core = parseUnsatCore(output)
    check core.len == 1
    check core[0] == "h0"

  test "deduplicates repeated IDs":
    let output = "unsat\n(h0 h0 h1)"
    let core = parseUnsatCore(output)
    check core.len == 2
    check core[0] == "h0"
    check core[1] == "h1"

suite "verifySmtLeanConsistency":
  test "empty unsat core returns err":
    let smt = Z3QueryResult(isUnsat: true, unsatCore: @[])
    let lean = LeanReplayResult(isValid: true, theoremName: "thm", hypotheses: @["h0"])
    let res = verifySmtLeanConsistency(smt, lean)
    check res.isErr
    check "no-smt-witness" in res.error

  test "empty theorem name returns err":
    let smt = Z3QueryResult(isUnsat: true, unsatCore: @["h0"])
    let lean = LeanReplayResult(isValid: true, theoremName: "", hypotheses: @["h0"])
    let res = verifySmtLeanConsistency(smt, lean)
    check res.isErr
    check "no-lean-witness" in res.error

  test "empty lean hypotheses returns err":
    let smt = Z3QueryResult(isUnsat: true, unsatCore: @["h0"])
    let lean = LeanReplayResult(isValid: true, theoremName: "thm", hypotheses: @[])
    let res = verifySmtLeanConsistency(smt, lean)
    check res.isErr
    check "no-lean-witness" in res.error

  test "hypothesis mismatch returns err":
    let smt = Z3QueryResult(isUnsat: true, unsatCore: @["h0", "h1"])
    let lean = LeanReplayResult(isValid: true, theoremName: "thm", hypotheses: @["h0", "h2"])
    let res = verifySmtLeanConsistency(smt, lean)
    check res.isErr
    check "hypothesis-mismatch" in res.error

  test "one-or-both-provers-failed returns err":
    let smt = Z3QueryResult(isUnsat: false, unsatCore: @["h0"])
    let lean = LeanReplayResult(isValid: true, theoremName: "thm", hypotheses: @["h0"])
    let res = verifySmtLeanConsistency(smt, lean)
    check res.isErr
    check "one-or-both-provers-failed" in res.error

  test "matching hypotheses returns ok with JointProofWitness":
    let smt = Z3QueryResult(isUnsat: true, unsatCore: @["h0", "h1"])
    let lean = LeanReplayResult(isValid: true, theoremName: "judge_proof", hypotheses: @["h0", "h1"])
    let res = verifySmtLeanConsistency(smt, lean)
    check res.isOk
    let witness = res.get
    check witness.smtUnsatCore == @["h0", "h1"]
    check witness.leanTheoremName == "judge_proof"
    check witness.leanHypotheses == @["h0", "h1"]

  test "subset matching ok (SMT core ⊆ Lean hyps)":
    let smt = Z3QueryResult(isUnsat: true, unsatCore: @["h0"])
    let lean = LeanReplayResult(isValid: true, theoremName: "thm", hypotheses: @["h0", "h1", "h2"])
    let res = verifySmtLeanConsistency(smt, lean)
    check res.isOk
    check res.get().smtUnsatCore == @["h0"]

suite "extractHypotheses (via lean_replay)":
  test "extracts from theorem with paren binders":
    let src = "theorem judge_proof (h0 : True) (h1 : True) : (A \\/ ~A) := by\n  aesop"
    let hyps = extractHypotheses(src)
    check hyps == @["h0", "h1"]

  test "extracts from lemma with curly binders":
    let src = "lemma test_lemma {h0 : True} (h_sys : True) : True := by\n  trivial"
    let hyps = extractHypotheses(src)
    check hyps == @["h0", "h_sys"]

  test "no binders returns empty":
    let src = "theorem simple : True := by\n  trivial"
    let hyps = extractHypotheses(src)
    check hyps.len == 0

suite "buildJudgeLeanTheorem":
  test "generates theorem with hypothesis binders":
    let result = buildJudgeLeanTheorem("(A \\/ ~A)", @["h0", "h1"])
    check result.contains("theorem judge_proof")
    check result.contains("(h0 : True)")
    check result.contains("(h1 : True)")
    check result.contains("(A \\/ ~A)")
    check result.contains("aesop")
