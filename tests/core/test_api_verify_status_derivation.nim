import core/trusted/layer_declaration

## axiom_api_verify k-induction — the status a run reports is derived from the
## evidence it produced.
##
## `finalStatus = "proved"` as a default means every path the author did not
## think about inherits the strongest claim the system can make. AGENTS.md
## §0.9 and docs/adr/0017 forbid a trust artifact asserting more than its
## evidence; docs/spec/evidence_calculus.md I6 records that a bare solver
## `unsat` is not a proof-checked proof. These cases pin both halves: the
## weakest status is the default, and `inductionProved` is never raised by a
## status string.

import std/strutils
import core/api/axiom_api_verify
import core/types/results

proc expect(cond: bool; msg: string) =
  if not cond:
    doAssert false, msg
  echo "  OK: " & msg

const ruleText = "x = x - 1"
const invariantText = "balance >= 0"

proc verifyBoth(baseStdout, stepStdout: string) =
  ## Both k-induction entry points must derive their status from the same
  ## evidence; running each stdout pair through both is what keeps the two
  ## copies from drifting apart again.
  let viaSolver = verifyKInductionBySolverOutput(2, 10, 1, baseStdout, stepStdout)
  let viaRule = verifyKInductionByInjectedRuleOutput(
    2, 10, ruleText, invariantText, baseStdout, stepStdout)
  doAssert viaSolver.isOk == viaRule.isOk,
    "both entry points accept or refuse the same stdouts"
  if viaSolver.isOk:
    expect(viaSolver.get().status == viaRule.get().status,
      "both entry points report the same status for " & stepStdout.strip)
    expect(viaSolver.get().inductionProved == viaRule.get().inductionProved,
      "both entry points raise the induction flag on the same evidence")
  else:
    expect(viaRule.isErr, "both entry points refuse the same stdouts")

block:
  echo "=== 1. both obligations discharged ==="
  verifyBoth("unsat\n", "unsat\n")
  let discharged = verifyKInductionBySolverOutput(2, 10, 1, "unsat\n", "unsat\n")
  doAssert discharged.isOk
  expect(discharged.get().status == "proved",
    "base AND step unsat is the only path to `proved`")
  expect(discharged.get().inductionProved, "the conjunction raises the induction flag")
  expect(not discharged.get().hasCounterExample,
    "a discharged argument has no counter-example")

block:
  echo "=== 2. `unsat` quoted inside another token never proves ==="
  verifyBoth("unsat\n", "(error \"unexpected token unsat\")")
  let quoted = verifyKInductionBySolverOutput(
    2, 10, 1, "unsat\n", "(error \"unexpected token unsat\")")
  doAssert quoted.isOk
  expect(quoted.get().status == "unknown",
    "a step stdout that merely quotes `unsat` reports the solver's own answer")
  expect(not quoted.get().inductionProved,
    "a quoted `unsat` does not raise the induction flag")

block:
  echo "=== 3. a non-unsat step reports what the solver said ==="
  for (stepStdout, expected) in [
      ("sat\n", "sat"),
      ("unknown\n", "unknown"),
      ("(error \"unsat\")\n", "unknown"),
      ("not unsat\n", "unknown")]:
    verifyBoth("unsat\n", stepStdout)
    let r = verifyKInductionBySolverOutput(2, 10, 1, "unsat\n", stepStdout)
    doAssert r.isOk
    expect(r.get().status == expected,
      "step stdout " & stepStdout.strip & " reports " & expected)
    expect(not r.get().inductionProved,
      "step stdout " & stepStdout.strip & " does not raise the induction flag")
  let satCase = verifyKInductionBySolverOutput(2, 10, 1, "unsat\n", "sat\n")
  doAssert satCase.isOk
  expect(satCase.get().hasCounterExample, "a `sat` step is a counter-example")
  expect(satCase.get().counterExampleProperty == "k_induction_base_or_step",
    "a counter-example names the failing obligation")

block:
  echo "=== 4. a failed base obligation never becomes a proof ==="
  for baseStdout in ["sat\n", "unknown\n", "(error \"unsat\")\n", ""]:
    let res = verifyKInductionBySolverOutput(2, 10, 1, baseStdout, "unsat\n")
    expect(res.isErr,
      "base stdout " & (if baseStdout.len == 0: "<empty>" else: baseStdout.strip) &
      " is refused rather than answered")
  let emptyStep = verifyKInductionBySolverOutput(2, 10, 1, "unsat\n", "")
  expect(emptyStep.isErr, "an unparseable step is refused rather than defaulted")

block:
  echo "=== 5. the default status is the weakest one, not the strongest ==="
  ## Exhaustively: over every stdout shape the parser can turn into a step
  ## result, `proved` may appear only when BOTH obligations came back unsat.
  var sawProved = false
  for stepStdout in ["unsat\n", "sat\n", "unknown\n", "", "(error \"unsat\")\n",
                     "not unsat\n", "  UNSAT  \n", "unsat extra tokens\n",
                     "(unsat-core u1 u2)\n"]:
    let res = verifyKInductionBySolverOutput(2, 10, 1, "unsat\n", stepStdout)
    if res.isErr:
      continue
    let r = res.get()
    if r.status == "proved":
      sawProved = true
      expect(r.inductionProved, "a reported proof always carries the induction flag")
    else:
      expect(not r.inductionProved,
        "status " & r.status & " never carries the induction flag")
  expect(sawProved,
    "the discharged case is still reachable — this is not a blanket refusal")

echo "=== ALL api_verify status derivation tests PASSED ==="
