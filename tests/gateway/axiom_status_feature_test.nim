## Axiom Status Feature Test.
## Verifies the CLI entry point for the gate pipeline observability dashboard.
##
## Tests:
##   - CLI flag parsing (help, unknown, missing args)
##   - Exit code behavior for valid and invalid inputs

import std/[unittest, os]
import cli/axiom_status

suite "Axiom Status — CLI Flag Parsing":

  test "runStatusCli --help returns exit code 0":
    ## Given the user requests help
    ## When runStatusCli is called with --help
    ## Then it returns exit code 0
    let code = runStatusCli(@["--help"])
    check code == 0

  test "runStatusCli -h also returns exit code 0":
    ## Given the user requests help via -h
    ## When runStatusCli is called with -h
    ## Then it returns exit code 0
    let code = runStatusCli(@["-h"])
    check code == 0

  test "runStatusCli with unknown flag returns exit code 1":
    ## Given the user passes an unrecognized flag
    ## When runStatusCli is called
    ## Then it returns exit code 1
    let code = runStatusCli(@["--nonexistent-flag"])
    check code == 1

  test "runStatusCli --gate without argument returns exit code 1":
    ## Given the user passes --gate but no gate ID
    ## When runStatusCli is called
    ## Then it returns exit code 1 (missing required argument)
    let code = runStatusCli(@["--gate"])
    check code == 1

  test "runStatusCli with no history file returns 0 gracefully":
    ## Given no gate_history.jsonl exists in the current directory
    ## When runStatusCli is called with no flags
    ## Then it returns 0 and prints a "no history" message
    let code = runStatusCli(@[])
    check code == 0
