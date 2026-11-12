import core/trusted/layer_declaration

## The Spacer CHC script projects the ONE pinned option set.
##
## `buildSpacerScript` used to write `(set-option :random-seed 0)` and its two
## siblings as string literals. SMT-LIB 2.7 §4.1.7 defines `:random-seed 0` as
## the solver MAY use a different seed on every run — 0 is the opt-OUT — so the
## script contradicted the reproducibility the recorded option digest claims.
## The literals were also a second emitter: the digest could not describe them.

import core/bmc/bmc_types
import core/trusted/solver_invocation
import core/types/z3_solver_config
import core/trusted/axiom_pragmas
import std/[algorithm, os, osproc, strutils, streams]
import verification/spacer_chc_router

proc expect(cond: bool; msg: string) =
  if not cond:
    doAssert false, msg
  echo "  OK: " & msg

const optOutDirectives = [
  "(set-option :random-seed 0)",
  "(set-option :sat.random_seed 0)",
  "(set-option :fp.spacer.random_seed 0)"
]

let transitions = @[
  BmcTransition(preState: @[("x", "Int")], guard: "(> x 0)",
                postState: @[("x", "(+ x 1)")])
]
let initialState = @[("x", "Int")]

proc emittedScript(): string =
  buildSpacerScript(transitions, initialState, "(< x 0)", withGetModel = true)

proc runZ3(script: string; tag: string): string {.axiomEffect: IOEffect.} =
  let path = getTempDir() / ("axiom_spacer_seed_" & tag & ".smt2")
  defer: removeFile(path)
  writeFile(path, script)
  let (output, code) = execCmdEx(resolveZ3Path() & " -smt2 " & "\"" & path & "\"")
  doAssert code == 0, "z3 rejected the emitted Spacer script (" & tag & "): " & output
  output

## The pinned script and its opt-out-seed twin, run once each up front so the
## behavioural comparison below is between two real solver invocations.
let pinnedRun = runZ3(emittedScript(), "pinned")
let optOutScript = emittedScript().replace(
  solverOptionDirective(SolverOptionSpec(name: "random-seed", value: $Z3PinnedRandomSeed)),
  "(set-option :random-seed 0)")
let optOutRun = runZ3(optOutScript, "optout")

block:
  echo "=== 1. the emitted script carries the pinned projection ==="
  let script = emittedScript()
  for spec in pinnedDeterminismOptions():
    let directive = solverOptionDirective(spec)
    expect(script.contains(directive), "the Spacer script emits " & directive)
  for optOut in optOutDirectives:
    expect(not script.contains(optOut),
      "the Spacer script no longer emits the opt-out " & optOut)
  expect(Z3PinnedRandomSeed != 0, "the pinned seed is non-zero")

block:
  echo "=== 2. no directive escapes the projection ==="
  ## Every `(set-option …)` line in the script must BE one of the pinned ones.
  ## A hand-added option here would be invisible to solverOptionsDigest, which
  ## is exactly the drift the pinned projection exists to prevent.
  let script = emittedScript()
  var emitted: seq[string] = @[]
  for line in script.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("(set-option "):
      emitted.add trimmed
  emitted.sort()
  var expected: seq[string] = @[]
  for spec in pinnedDeterminismOptions():
    expected.add solverOptionDirective(spec)
  expected.sort()
  expect(emitted == expected,
    "the script's option set is exactly the pinned projection: " & emitted.join(" | "))

block:
  echo "=== 3. the CHC configuration survives the option-set change ==="
  let script = emittedScript()
  expect(script.startsWith("(set-logic HORN)"), "the HORN logic header survives")
  expect(script.contains("(declare-fun state (Int) Bool)"), "the CHC predicate survives")
  expect(script.contains("(check-sat)"), "the query survives")
  expect(script.contains("(get-model)"), "the model query survives")

block:
  echo "=== 4. the real solver accepts it and answers identically ==="
  let pinnedLines = pinnedRun.splitLines()
  var responses: seq[string] = @[]
  for line in pinnedLines:
    let trimmed = line.strip()
    if trimmed == "sat" or trimmed == "unsat" or trimmed == "unknown":
      responses.add trimmed
  expect(responses == @["sat"],
    "z3 answers the CHC script with exactly one response, `sat`: " & $responses)
  expect(not pinnedRun.contains("(error"),
    "z3 parses every command in the emitted script: " &
    pinnedRun.replace("\n", " | "))
  expect(pinnedRun.contains("define-fun state"),
    "Spacer still synthesises an invariant: " & pinnedRun.replace("\n", " | "))

block:
  echo "=== 5. pinning the seed changed nothing the solver answered ==="
  ## The same script with the opt-out seed is the behavioural control: identical
  ## bytes out means the option-set change is a determinism claim, not a
  ## semantic one.
  expect(optOutScript.contains("(set-option :random-seed 0)"),
    "the control script really does carry the opt-out seed")
  expect(optOutRun == pinnedRun,
    "seed 0 and seed " & $Z3PinnedRandomSeed &
    " produce byte-identical solver output on this problem")

block:
  echo "=== 6. the seed is stable across repeated runs of the pinned script ==="
  let script = emittedScript()
  expect(runZ3(script, "r1") == runZ3(script, "r2"),
    "two runs of the pinned script are byte-identical")

block:
  echo "=== 7. the production entry point still synthesises through the pool ==="
  let viaPool = trySpacerInvariantSynthesis(transitions, initialState, "(< x 0)")
  expect(viaPool.status == "sat",
    "trySpacerInvariantSynthesis still reports the solver's own answer: " &
    $viaPool.status)
  expect(viaPool.invariantSource.len > 0,
    "and still returns the synthesised invariant body")

echo "=== ALL spacer CHC seed pinning tests PASSED ==="