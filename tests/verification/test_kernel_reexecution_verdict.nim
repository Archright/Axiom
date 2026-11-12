import core/trusted/layer_declaration

## Kernel re-execution — the Z3 verdict is a solver ANSWER, not a substring.
##
## `ax cert verify --kernel` turns a fresh Z3 re-execution into a
## verified-proof claim. A stdout that merely mentions "unsat" somewhere —
## inside `unknown`, inside an error message, inside an unsat-core entry, or
## as part of a file name — is not an answer, and reading it as one is the
## claim this test exists to prevent (AGENTS.md §0.9; INV-10).

import verification/kernel_reexecution

proc expect(cond: bool; msg: string) =
  if not cond:
    doAssert false, msg
  echo "  OK: " & msg

block:
  echo "=== 1. a real ⟨check_sat_response⟩ passes ==="
  expect(z3ResultVerdict(0, false, "unsat") == krPassed,
    "exit 0 + bare `unsat` line is the only shape that re-executes to krPassed")
  expect(z3ResultVerdict(0, false, "unsat\n") == krPassed,
    "trailing newline does not change the verdict")
  expect(z3ResultVerdict(0, false, "  unsat  \n") == krPassed,
    "surrounding whitespace on the response line is stripped")

block:
  echo "=== 2. `unsat` inside another token never passes ==="
  expect(z3ResultVerdict(0, false, "unknown") == krZ3Mismatch,
    "`unknown` is not `unsat`")
  expect(z3ResultVerdict(0, false, "not unsat") == krZ3Mismatch,
    "`not unsat` is not a solver response")
  expect(z3ResultVerdict(0, false, "unsatisfiable") == krZ3Mismatch,
    "`unsatisfiable` is not `unsat`")
  expect(z3ResultVerdict(0, false, "definitely_unsat.smt2") == krZ3Mismatch,
    "a file name containing `unsat` is not a solver response")

block:
  echo "=== 3. an error line quoting `unsat` never passes ==="
  expect(z3ResultVerdict(0, false, "(error \"line 5: unexpected token unsat\")") == krZ3Mismatch,
    "an error message quoting `unsat` is not a decision")
  expect(z3ResultVerdict(0, false, "(error \"unsat\")\n(:reason-unknown aborted)\n") == krZ3Mismatch,
    "an error plus an unknown reason is not a decision, however many times `unsat` is quoted")
  expect(z3ResultVerdict(0, false, "(unsat-core u1 u2)\n") == krZ3Mismatch,
    "an unsat-core s-expression is not a response line")

block:
  echo "=== 4. solver elaboration around the answer is not the answer ==="
  expect(z3ResultVerdict(0, false, "(:reason-unknown incomplete)\nunknown\n") == krZ3Mismatch,
    "`:reason-unknown` free text does not create a proof")
  expect(z3ResultVerdict(0, false, "sat\n") == krZ3Mismatch,
    "`sat` is a mismatch, not a pass")
  expect(z3ResultVerdict(0, false, "(error \"unsupported\")\n") == krZ3Mismatch,
    "an error-only stdout is a mismatch")
  expect(z3ResultVerdict(0, false, "") == krZ3Mismatch,
    "an empty stdout is a mismatch")
  expect(z3ResultVerdict(0, false, "(error \"unsat\")\n\"AXIOM_KERNEL_REEXEC_FIN\"\n") == krZ3Mismatch,
    "the envelope sentinel echo never satisfies the verdict")

block:
  echo "=== 5. exit code and timeout dominate the output ==="
  expect(z3ResultVerdict(1, false, "unsat") == krZ3Mismatch,
    "non-zero exit with an unsat token is still a mismatch")
  expect(z3ResultVerdict(0, true, "unsat") == krTimeout,
    "a timeout is krTimeout even when the killed process had printed unsat")
  expect(z3ResultVerdict(-1, true, "") == krTimeout,
    "an unrunnable kernel is krTimeout, never a pass")

block:
  echo "=== 6. composition stays fail-closed ==="
  expect(composeKernelVerdict(krPassed, krPassed, true, true) == krPassed,
    "both classes re-executing to krPassed composes to krPassed")
  expect(composeKernelVerdict(krPassed, krZ3Mismatch, true, true) == krZ3Mismatch,
    "one mismatching class decides the overall verdict")
  expect(composeKernelVerdict(krPassed, krPassed, false, false) == krMissingInput,
    "no embedded evidence at all is krMissingInput, never a pass")

echo "=== ALL kernel re-execution verdict tests PASSED ==="