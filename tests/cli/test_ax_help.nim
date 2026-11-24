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
# planAxActions — command-scoped help rows (issue #222)
#
# `ax prove --help` used to emit the 35-row top-level table, so the answer to
# "what does prove take?" was buried in every sibling's row. The help flag now
# carries that ONE command's row. `ax help` / `ax --help` keep the full table.
# ---------------------------------------------------------------------------

proc helpLinesOf(actions: seq[CliAction]): seq[string] {.raises: [CatchableError].} =
  ## Mirrors interpretCliActions' cliPrintUsage projection: a scoped seq when
  ## the planner carried one, otherwise the whole axUsageLines table. The test
  ## must resolve the fallback the same way the interpreter does, or it would
  ## assert on an empty seq that is never what the user sees.
  for a in actions:
    if a.kind == cliPrintUsage:
      return if a.helpUsageLines.len > 0: a.helpUsageLines else: axUsageLines()
  @[]

suite "planAxActions — command-scoped help rows":
  test "prove --help carries exactly the ax prove row":
    let lines = helpLinesOf(planAxActions(@["prove", "--help"]))
    check lines.len == 2                       # "usage:" + the one row
    check lines[0] == "usage:"
    check lines[1].startsWith("  ax prove ")
    check lines[1].contains("--project")
    check lines[1].contains("--target")
    check lines[1].contains("--smt-timeout")

  test "prove -h is the same scope as --help":
    check helpLinesOf(planAxActions(@["prove", "-h"])) ==
          helpLinesOf(planAxActions(@["prove", "--help"]))

  test "prove --help no longer advertises sibling commands":
    let lines = helpLinesOf(planAxActions(@["prove", "--help"]))
    for line in lines:
      check not line.contains("ax report")
      check not line.contains("ax topology")
      check not line.contains("ax capability")

  test "report --help carries exactly the ax report row":
    let lines = helpLinesOf(planAxActions(@["report", "--help"]))
    check lines.len == 2
    check lines[1].startsWith("  ax report ")
    check lines[1].contains("--upstream")

  test "ax help still carries the whole surface":
    let scoped = helpLinesOf(planAxActions(@["prove", "--help"]))
    let full = helpLinesOf(planAxActions(@["help"]))
    check full.len == 35                       # "usage:" + 34 commands
    check scoped.len < full.len

  test "top-level ax --help still carries the whole surface":
    let full = helpLinesOf(planAxActions(@["--help"]))
    check full.len == 35
    check helpLinesOf(planAxActions(@["-h"])) == full

  test "unknown subcommand falls back to the whole surface":
    # No subcommand matched, so there is no scoped row to scope to — the full
    # table is the only useful answer, and the exit class stays INVALID_INPUT.
    let lines = helpLinesOf(planAxActions(@["nonexistent"]))
    check lines.len == 35

  test "axCommandUsageLines is empty for an unknown help-table name":
    check axCommandUsageLines("ax no-such-command").len == 0

# ---------------------------------------------------------------------------
# planAxActions — top-level ax --help / -h (issue #222)
# ---------------------------------------------------------------------------

suite "planAxActions — top-level --help":
  test "top-level --help emits usage + quit(0)":
    let actions = planAxActions(@["--help"])
    var foundUsage = false
    var foundQuitZero = false
    var foundUnknown = false
    for a in actions:
      if a.kind == cliPrintUsage: foundUsage = true
      if a.kind == cliQuit and a.exitCode == 0: foundQuitZero = true
      if a.kind == cliWriteStderrLine and
         a.message.startsWith("unknown ax subcommand"):
        foundUnknown = true
    check foundUsage
    check foundQuitZero
    check not foundUnknown

  test "top-level -h emits usage + quit(0)":
    let actions = planAxActions(@["-h"])
    var foundUsage = false
    var foundQuitZero = false
    for a in actions:
      if a.kind == cliPrintUsage: foundUsage = true
      if a.kind == cliQuit and a.exitCode == 0: foundQuitZero = true
    check foundUsage
    check foundQuitZero

  test "genuinely unknown subcommand still exits 3 (rule not weakened)":
    let actions = planAxActions(@["definitely-not-a-subcommand"])
    var foundQuitThree = false
    var foundUsage = false
    for a in actions:
      if a.kind == cliQuit and a.exitCode == 3: foundQuitThree = true
      if a.kind == cliPrintUsage: foundUsage = true
    check foundQuitThree
    check foundUsage

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

  test "every accepted subcommand has a scoped help row that names itself":
    # The scoped row is the SSOT row for that command, so it must exist for
    # every command the parser accepts — a missing row would silently fall
    # back to the whole table.
    for key in helpTableKeys(ActionPlanSource):
      let lines = axCommandUsageLines("ax " & key)
      check lines.len == 2
      check lines[1].startsWith("  ax " & key)
