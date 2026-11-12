{.push raises: [CatchableError].}

## FSM Invariant Prover Tests — Unit tests for fsm_invariant_prover.nim
## Tests the BMC encoding (pure) and Z3 execution (I/O boundary).
## Z3 integration tests are gated by -d:axiomTestZ3 compile-time flag.

import std/[unittest, strutils, os]
import core/bmc/fsm_invariant_prover

# ---------------------------------------------------------------------------
# BMC Encoding Tests (Pure — no Z3 required)
# ---------------------------------------------------------------------------

suite "FSM BMC Encoding":
  test "legal transitions count is 14":
    check LegalTransitions.len == 14

  test "all transition states are in range 0..8":
    for (src, dst) in LegalTransitions:
      check src >= 0 and src <= 8
      check dst >= 0 and dst <= 8

  test "initial state 0 has exactly one outgoing transition (to 1)":
    var outgoing: seq[int] = @[]
    for (src, dst) in LegalTransitions:
      if src == 0:
        outgoing.add(dst)
    check outgoing.len == 1
    check outgoing[0] == 1

  test "state 1 (InProgress) has 6 outgoing transitions":
    var outgoing: seq[int] = @[]
    for (src, dst) in LegalTransitions:
      if src == 1:
        outgoing.add(dst)
    check outgoing.len == 6
    check 2 in outgoing
    check 3 in outgoing
    check 4 in outgoing
    check 5 in outgoing
    check 6 in outgoing
    check 7 in outgoing

  test "all terminal states have exactly one outgoing transition (to 0 or 8)":
    for terminalState in [2, 3, 4, 5, 6, 7, 8]:
      var outgoing: seq[int] = @[]
      for (src, dst) in LegalTransitions:
        if src == terminalState:
          outgoing.add(dst)
      check outgoing.len == 1
      if terminalState == 2:
        check outgoing[0] == 8
      else:
        check outgoing[0] == 0

  test "buildBmcQuery produces valid SMT-LIB2 preamble":
    let query = buildBmcQuery(fikDeadlockFreedom, 5000)
    check "(set-logic QF_LIA)" in query
    check "(set-option :timeout 5000)" in query
    check "(set-option :rlimit 1000000)" in query
    check "(define-fun T" in query
    check "(check-sat)" in query

  test "deadlock freedom query contains non-terminal predicate":
    let query = buildBmcQuery(fikDeadlockFreedom, 5000)
    check "(NT dl_s)" in query
    check "(T dl_s" in query

  test "transition validity query enumerates all 14 transitions":
    let query = buildBmcQuery(fikTransitionValidity, 5000)
    var inValiditySection = false
    var transitionCount = 0
    for line in query.splitLines():
      if "Transition validity:" in line:
        inValiditySection = true
      if inValiditySection and "(= tv_s " in line and "(= tv_sp " in line:
        inc transitionCount
      if inValiditySection and "(check-sat)" in line:
        break
    check transitionCount == 14

  test "forward progress query checks terminal states are NOT on path":
    let query = buildBmcQuery(fikForwardProgress, 5000)
    check "(not (Term s0))" in query
    check "(not (Term s8))" in query

  test "different invariant kinds produce different queries":
    let q1 = buildBmcQuery(fikDeadlockFreedom, 5000)
    let q2 = buildBmcQuery(fikTransitionValidity, 5000)
    let q3 = buildBmcQuery(fikForwardProgress, 5000)
    check q1 != q2
    check q2 != q3
    check q1 != q3

# ---------------------------------------------------------------------------
# Summary and Result Tests
# ---------------------------------------------------------------------------

suite "FsmProverResult":
  test "isFullyProved returns true for all proved":
    let results = @[
      FsmProverResult(kind: fikDeadlockFreedom, proved: true),
      FsmProverResult(kind: fikTransitionValidity, proved: true),
      FsmProverResult(kind: fikForwardProgress, proved: true),
    ]
    check isFullyProved(results) == true

  test "isFullyProved returns false if any failed":
    let results = @[
      FsmProverResult(kind: fikDeadlockFreedom, proved: true),
      FsmProverResult(kind: fikTransitionValidity, proved: false, timedOut: true),
      FsmProverResult(kind: fikForwardProgress, proved: true),
    ]
    check isFullyProved(results) == false

  test "summarizeResults contains PROVED/FAILED/TIMEOUT":
    let results = @[
      FsmProverResult(kind: fikDeadlockFreedom, proved: true, elapsedMs: 42),
      FsmProverResult(kind: fikTransitionValidity, proved: false, timedOut: true, elapsedMs: 10000),
    ]
    let summary = summarizeResults(results)
    check "PROVED" in summary
    check "TIMEOUT" in summary
    check "42ms" in summary

# ---------------------------------------------------------------------------
# Z3 Integration Tests (compile-time gated by -d:axiomTestZ3)
# ---------------------------------------------------------------------------

when defined(axiomTestZ3):
  suite "Z3 BMC Integration":
    test "proveAllInvariants returns 3 results":
      let results = proveAllInvariants(timeoutMs = 5000)
      check results.len == 3

    test "deadlock freedom is provable":
      let r = proveInvariant(fikDeadlockFreedom, timeoutMs = 5000)
      check r.proved
      check not r.timedOut

    test "transition validity is provable":
      let r = proveInvariant(fikTransitionValidity, timeoutMs = 5000)
      check r.proved
      check not r.timedOut

    test "forward progress is provable":
      let r = proveInvariant(fikForwardProgress, timeoutMs = 5000)
      check r.proved
      check not r.timedOut

{.pop.}
