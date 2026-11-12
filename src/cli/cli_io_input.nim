import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

import core/results
import core/parsers/safe_parsers
import cli/cli_io_error
import ../core/trusted/axiom_pragmas

## Read All Stdin.
proc readAllStdin*(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    result = stdin.readAll()
  except CatchableError:
    result = ""

## Parse Required Int Arg.
func parseRequiredIntArg*(name: string; value: string): Result[int, string] {.raises: [], axiom: ["(assert (and (>= (str.len name) 0) (>= (str.len value) 0)))", "name.length ≥ 0 ∧ value.length ≥ 0"].} =
  let r = safeParseInt(value)
  if r.isOk():
    ok(r.get())
  else:
    err("invalid integer for " & name & ": " & value)

## Parse Required Int Arg Or Die.
  ## axiom-smt: (assert (and (>= (str.len name) 0) (>= (str.len value) 0)))
  ## axiom-lean: name.length ≥ 0 ∧ value.length ≥ 0
proc parseRequiredIntArgOrDie*(name: string; value: string): int {.axiomTryImpl.} =
  let parsed = parseRequiredIntArg(name, value)
  if parsed.isErr():
    die(parsed.error)
  result = parsed.get()

## Parse Required Int Cli Arg.
func parseRequiredIntCliArg*(name: string; value: string): Result[int, string] {.raises: [], axiom: ["(assert (and (= (str.len value) 0)))", "value.length = 0"].} =
  if value.len == 0:
    return err("missing value: " & name)
  parseRequiredIntArg(name, value)

## Require Next Arg — extracts the next positional argument after a flag.
## Advances `i` past the consumed value. Dies with a clear message if missing.
  ## axiom-smt: (assert (and (>= (seq.len args) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len args))) (>= (str.len (seq.nth args i)) 0))) (and (>= i -9223372036854775808) (<= i 9223372036854775807)) (>= (str.len flagName) 0) (>= (seq.len args) 0) (forall ((argsIdx Int)) (=> (and (>= argsIdx 0) (< argsIdx (seq.len args))) (>= (str.len (seq.nth args argsIdx)) 0))) (and (>= i -9223372036854775808) (<= i 9223372036854775807)) (>= (str.len flagName) 0) (>= result 0) (forall ((argsIdx Int)) (=> (and (>= argsIdx 0) (< argsIdx (seq.len args))) (>= (str.len (seq.nth args argsIdx)) 0)))))
  ## axiom-lean: args.size ≥ 0 ∧ ∀ (i : Fin args.size), (args.get i).length ≥ 0 ∧ i ≥ -9223372036854775808 ∧ i ≤ 9223372036854775807 ∧ flagName.length ≥ 0 ∧ args.size ≥ 0 ∧ (∀ (argsIdx : Fin args.size), (args.get argsIdx).length ≥ 0) ∧ i ≥ -9223372036854775808 ∧ i ≤ 9223372036854775807 ∧ flagName.length ≥ 0 ∧ (result ≥ 0) ∧ (∀ (argsIdx : Fin args.size), (args.get argsIdx).length ≥ 0)
proc requireArg*(args: seq[string]; i: var int; flagName: string): string {.axiomTryImpl.} =
  if i + 1 >= args.len:
    die("missing value: " & flagName)
  result = args[i + 1]
  i += 2

## Require Next Int Arg — as requireArg but parses to int.
  ## axiom-smt: (assert (and (>= (seq.len args) 0) (forall ((argsIdx Int)) (=> (and (>= argsIdx 0) (< argsIdx (seq.len args))) (>= (str.len (seq.nth args argsIdx)) 0))) (and (>= i -9223372036854775808) (<= i 9223372036854775807)) (>= (str.len flagName) 0) (forall ((argsIdx Int)) (=> (and (>= argsIdx 0) (< argsIdx (seq.len args))) (>= (str.len (seq.nth args argsIdx)) 0)))))
  ## axiom-lean: args.size ≥ 0 ∧ (∀ (argsIdx : Fin args.size), (args.get argsIdx).length ≥ 0) ∧ i ≥ -9223372036854775808 ∧ i ≤ 9223372036854775807 ∧ flagName.length ≥ 0 ∧ (∀ (argsIdx : Fin args.size), (args.get argsIdx).length ≥ 0)
proc requireIntArg*(args: seq[string]; i: var int; flagName: string): int {.axiomTryImpl.} =
  let raw = requireArg(args, i, flagName)
  parseRequiredIntArgOrDie(flagName, raw)
{.pop.}
