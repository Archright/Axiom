{.push raises: [].}

## Unit tests for ax prove/report --help / -h handling.
##
## Verifies that planAxActions intercepts --help/-h before flag parsing,
## emits cliPrintUsage + cliQuit(0), and that normal args pass through unchanged.

import std/sets
import std/unittest

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
  # action_plan_cli.nim:252). Docs/spec/productization_contract.md:270,281 and
  # docs/design/r7_cli_outcome_contract.md ratify INVALID_INPUT -> 3. This is a
  # contract alignment, not merely a red-test fix. (It does NOT claim "all invalid
  # input -> 3 is ratified"; the broader partition stays pending.)
  test "unknown subcommand exits INVALID_INPUT (3) per ratified R7 contract":
    let actions = planAxActions(@["nonexistent"])
    var foundQuitThree = false
    for a in actions:
      if a.kind == cliQuit and a.exitCode == 3: foundQuitThree = true
    check foundQuitThree
