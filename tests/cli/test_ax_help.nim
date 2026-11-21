{.push raises: [].}

## Unit tests for ax CLI help handling and the help-table/parser SSOT alignment.
##
## Verifies that planAxActions intercepts --help/-h before flag parsing,
## emits cliPrintUsage + cliQuit(0), and that normal args pass through unchanged.
## Also asserts that axCommandHelpEntries advertises exactly the subcommands
## accepted by parseAxSubcommandKind.

import std/[os, sets, strutils, unittest]

import cli/action_plan_cli
import cli/cli_types

# ---------------------------------------------------------------------------
# hasHelpFlag
# ---------------------------------------------------------------------------

suite "hasHelpFlag":
  test "--help detected":
    check hasHelpFlag(@["--limit", "10", "--help"]) == true

  test "-h detected":
    check hasHelpFlag(@["-h"]) == true

  test "no help flags returns false":
    check hasHelpFlag(@["--limit", "10"]) == false

  test "empty args returns false":
    check hasHelpFlag(@[]) == false

  test "--help at start of args":
    check hasHelpFlag(@["--help", "--limit", "5"]) == true

  test "partial match like --helptext does not trigger":
    check hasHelpFlag(@["--helptext"]) == false

# ---------------------------------------------------------------------------
# planAxActions — ax prove --help / -h
# ---------------------------------------------------------------------------

suite "planAxActions — ax prove --help":
  test "prove --help emits usage + quit(0)":
    let actions = planAxActions(@["prove", "--help"])
    var foundUsage = false
    var foundQuitZero = false
    for a in actions:
      if a.kind == cliPrintUsage: foundUsage = true
      if a.kind == cliQuit and a.exitCode == 0: foundQuitZero = true
    check foundUsage
    check foundQuitZero

  test "prove -h emits usage + quit(0)":
    let actions = planAxActions(@["prove", "-h"])
    var foundUsage = false
    var foundQuitZero = false
    for a in actions:
      if a.kind == cliPrintUsage: foundUsage = true
      if a.kind == cliQuit and a.exitCode == 0: foundQuitZero = true
    check foundUsage
    check foundQuitZero

  test "prove --help with other flags still emits usage + quit(0)":
    let actions = planAxActions(@["prove", "--limit", "5", "--help"])
    var foundUsage = false
    var foundQuitZero = false
    for a in actions:
      if a.kind == cliPrintUsage: foundUsage = true
      if a.kind == cliQuit and a.exitCode == 0: foundQuitZero = true
    check foundUsage
    check foundQuitZero

  test "prove without help runs engine (normal path preserved)":
    let actions = planAxActions(@["prove", "--limit", "10"])
    var foundEngine = false
    for a in actions:
      if a.kind == cliRunAxiomEngine: foundEngine = true
    check foundEngine

# ---------------------------------------------------------------------------
# planAxActions — ax report --help / -h
# ---------------------------------------------------------------------------

suite "planAxActions — ax report --help":
  test "report --help emits usage + quit(0)":
    let actions = planAxActions(@["report", "--help"])
    var foundUsage = false
    var foundQuitZero = false
    for a in actions:
      if a.kind == cliPrintUsage: foundUsage = true
      if a.kind == cliQuit and a.exitCode == 0: foundQuitZero = true
    check foundUsage
    check foundQuitZero

  test "report -h emits usage + quit(0)":
    let actions = planAxActions(@["report", "-h"])
    var foundUsage = false
    var foundQuitZero = false
    for a in actions:
      if a.kind == cliPrintUsage: foundUsage = true
      if a.kind == cliQuit and a.exitCode == 0: foundQuitZero = true
    check foundUsage
    check foundQuitZero

  test "report --help with other flags still emits usage + quit(0)":
    let actions = planAxActions(@["report", "--json", "--help"])
    var foundUsage = false
    var foundQuitZero = false
    for a in actions:
      if a.kind == cliPrintUsage: foundUsage = true
      if a.kind == cliQuit and a.exitCode == 0: foundQuitZero = true
    check foundUsage
    check foundQuitZero

  test "report without help dispatches normally":
    let actions = planAxActions(@["report", "--json"])
    var foundDispatch = false
    for a in actions:
      if a.kind == cliDispatchCommand: foundDispatch = true
    check foundDispatch

# ---------------------------------------------------------------------------
# planAxActions — other subcommands unaffected
# ---------------------------------------------------------------------------

suite "planAxActions — other subcommands unaffected by --help":
  test "ax help still works":
    let actions = planAxActions(@["help"])
    var foundUsage = false
    var foundQuitZero = false
    for a in actions:
      if a.kind == cliPrintUsage: foundUsage = true
      if a.kind == cliQuit and a.exitCode == 0: foundQuitZero = true
    check foundUsage
    check foundQuitZero

  # Test-expectation alignment with the ratified R7 contract: the planner emits
  # CliOutcome.INVALID_INPUT.exitCode() = 3 for an unknown subcommand (see
  # parseAxSubcommandKind / planAxActions). Docs/spec/productization_contract.md:270,281
  # and docs/design/r7_cli_outcome_contract.md ratify INVALID_INPUT -> 3. This is a
  # contract alignment, not merely a red-test fix. (It does NOT claim "all invalid
  # input -> 3 is ratified"; the broader partition stays pending.)
  test "unknown subcommand exits INVALID_INPUT (3) per ratified R7 contract":
    let actions = planAxActions(@["nonexistent"])
    var foundQuitThree = false
    for a in actions:
      if a.kind == cliQuit and a.exitCode == 3: foundQuitThree = true
    check foundQuitThree

# ---------------------------------------------------------------------------
# Help table / parser SSOT alignment
# ---------------------------------------------------------------------------

const
  RepoRoot = currentSourcePath().parentDir().parentDir().parentDir()
  ActionPlanSource = staticRead(RepoRoot / "src" / "cli" / "action_plan_cli.nim")

func helpTableKeys(source: string): HashSet[string] =
  ## Keys advertised by axCommandHelpEntries (`name: "ax <key>"`).
  const Marker = "name: \"ax "
  for line in source.splitLines():
    let at = line.find(Marker)
    if at < 0:
      continue
    let rest = line[at + Marker.len .. ^1]
    let close = rest.find('"')
    if close >= 0:
      result.incl(rest[0 ..< close])

func parserKeys(source: string): HashSet[string] =
  ## Tokens accepted by parseAxSubcommandKind (`of "<token>":`).
  const StartMark = "func parseAxSubcommandKind"
  const EndMark = "func dispatchCommandAction"
  const Marker = "of \""
  let start = source.find(StartMark)
  let stop = source.find(EndMark)
  if start < 0 or stop <= start:
    return
  for line in source[start ..< stop].splitLines():
    let at = line.find(Marker)
    if at < 0:
      continue
    let rest = line[at + Marker.len .. ^1]
    let close = rest.find("\":")
    if close >= 0:
      result.incl(rest[0 ..< close])

suite "help table matches parser-accepted subcommands":
  test "help table advertises exactly one entry per accepted subcommand":
    let helpKeys = helpTableKeys(ActionPlanSource)
    let accepted = parserKeys(ActionPlanSource)
    check helpKeys.len == 34
    check accepted.len == 34
    check helpKeys == accepted

  test "seed-registry is neither advertised nor accepted":
    let helpKeys = helpTableKeys(ActionPlanSource)
    let accepted = parserKeys(ActionPlanSource)
    check "seed-registry" notin helpKeys
    check "seed-registry" notin accepted

  test "every help entry routes to a known subcommand":
    for key in helpTableKeys(ActionPlanSource):
      let actions = planAxActions(@[key])
      var unknown = false
      for a in actions:
        if a.kind == cliWriteStderrLine and
           a.message.startsWith("unknown ax subcommand"):
          unknown = true
      check not unknown
