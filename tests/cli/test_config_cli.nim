{.push raises: [CatchableError].}

## Unit tests for cli/config_cli — `ax config validate` absence semantics
## (issue #225).
##
## Default mode preserves the historical warning-only contract for missing
## required sections. `--strict` promotes absent config and absent required
## sections to failure; a non-zero exit is the only signal a script can use.

import std/os
import std/times
import std/unittest

import cli/config_cli

proc makeTempWorkspace(): string =
  let base = getTempDir() / "axiom_config_cli_test_" & $getCurrentProcessId() &
             "_" & $epochTime().int
  createDir(base)
  writeFile(base / ".axiom_root", "")
  result = base

proc removeWorkspace(dir: string) =
  if dirExists(dir):
    removeDir(dir)

template withWorkspace(configBody: string, withConfig: bool, body: untyped) =
  let ws = makeTempWorkspace()
  if withConfig:
    writeFile(ws / "axiom.toml", configBody)
  let savedDir = getCurrentDir()
  try:
    setCurrentDir(ws)
    body
  finally:
    setCurrentDir(savedDir)
    removeWorkspace(ws)

const fullConfig = """
[project]
name = "test"

[engine]
version = "1"
"""

const onlyProject = """
[project]
name = "test"
"""

suite "config_cli — validate missing config file":
  test "default mode tolerates a missing axiom.toml (backward compatible)":
    withWorkspace("", false):
      check runConfigCli(@["validate"]) == 0

  test "--strict fails on a missing axiom.toml":
    withWorkspace("", false):
      check runConfigCli(@["validate", "--strict"]) == 1

suite "config_cli — validate required sections":
  test "full config passes in default mode":
    withWorkspace(fullConfig, true):
      check runConfigCli(@["validate"]) == 0

  test "full config passes in strict mode":
    withWorkspace(fullConfig, true):
      check runConfigCli(@["validate", "--strict"]) == 0

  test "missing [engine] is a warning in default mode":
    withWorkspace(onlyProject, true):
      check runConfigCli(@["validate"]) == 0

  test "missing [engine] fails in strict mode":
    withWorkspace(onlyProject, true):
      check runConfigCli(@["validate", "--strict"]) == 1

  test "config with no required sections fails in strict mode":
    withWorkspace("[prove]\nbudget_gas = 0\n", true):
      check runConfigCli(@["validate", "--strict"]) == 1

  test "empty config fails in both modes":
    withWorkspace("", true):
      check runConfigCli(@["validate"]) == 1
      check runConfigCli(@["validate", "--strict"]) == 1

suite "config_cli — validate flag parsing":
  test "unknown validate option exits 1":
    withWorkspace(fullConfig, true):
      check runConfigCli(@["validate", "--bogus"]) == 1

  test "unknown subcommand exits 1":
    check runConfigCli(@["bogus"]) == 1

{.pop.}