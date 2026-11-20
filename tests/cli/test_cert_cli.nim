{.push raises: [CatchableError].}

## Unit tests for cli/cert_cli — `ax cert show` absence semantics (issue #225).
##
## §0.7 business scenario: listing a proof vault that does not exist (or is
## empty) must not exit 0 as if certificates had been shown. The explicit
## `--allow-missing` opt-in is the only success path for absence.

import std/os
import std/times
import std/unittest

import cli/cert_cli

proc makeTempWorkspace(): string =
  let base = getTempDir() / "axiom_cert_cli_test_" & $getCurrentProcessId() &
             "_" & $epochTime().int
  createDir(base)
  result = base

proc removeWorkspace(dir: string) =
  if dirExists(dir):
    removeDir(dir)

template withWorkspace(body: untyped) =
  let ws = makeTempWorkspace()
  let savedDir = getCurrentDir()
  try:
    setCurrentDir(ws)
    body
  finally:
    setCurrentDir(savedDir)
    removeWorkspace(ws)

suite "cert_cli — show absence (§0.7: proof vault missing)":
  test "missing vault exits 1":
    withWorkspace():
      check runCertCli(@["show"]) == 1

  test "missing vault with --allow-missing exits 0":
    withWorkspace():
      check runCertCli(@["show", "--allow-missing"]) == 0

  test "empty vault exits 1":
    withWorkspace():
      createDir(".axiom/vault")
      check runCertCli(@["show"]) == 1

  test "empty vault with --allow-missing exits 0":
    withWorkspace():
      createDir(".axiom/vault")
      check runCertCli(@["show", "--allow-missing"]) == 0

  test "vault with a certificate exits 0":
    withWorkspace():
      createDir(".axiom/vault")
      writeFile(".axiom/vault/abc123.json", "{}")
      check runCertCli(@["show"]) == 0

suite "cert_cli — show argument surface":
  test "show with a certificate id is rejected as invalid input":
    ## `show` lists the vault and has no id lookup — the id must not be
    ## silently ignored.
    withWorkspace():
      check runCertCli(@["show", "abc123"]) == 3

  test "show with an unknown flag is rejected as invalid input":
    withWorkspace():
      check runCertCli(@["show", "--bogus"]) == 3

  test "no subcommand exits 1":
    check runCertCli(@[]) == 1

{.pop.}