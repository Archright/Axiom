import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Config CLI — Show or validate project configuration from axiom.toml.
##
## Subcommands:
##   show              — print parsed configuration
##   validate          — validate axiom.toml structure
##
## Usage: ax config [show|validate]

import std/os
import std/tables
import cli/config_loader
import core/trusted/axiom_pragmas
import core/utils/repo_root
import infrastructure/logging_facade

proc configShow*(): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let tomlPath = axiomConfigPath()
  if tomlPath.len == 0:
    echo "[config] No axiom.toml found (config/axiom.toml or project root)."
    return 0
  let config = loadTomlConfig(tomlPath)
  if len(config) == 0:
    echo "[config] axiom.toml is empty or could not be parsed."
    return 0
  for section, entries in config:
    if section == "__root__":
      echo "[root]"
    else:
      echo "[" & section & "]"
    for key, value in entries:
      echo "  " & key & " = " & value
    echo ""
  return 0

proc configValidate*(): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let tomlPath = axiomConfigPath()
  if tomlPath.len == 0:
    echo "[config] No axiom.toml found — nothing to validate."
    return 0
  let config = loadTomlConfig(tomlPath)
  var errors = 0
  # Basic structural validation
  if len(config) == 0:
    echo "[config] Warning: axiom.toml parsed to empty configuration."
    inc(errors)
  # Check for known required sections
  let requiredSections = ["project", "engine"]
  for section in requiredSections:
    if section notin config:
      echo "[config] Warning: missing recommended section [" & section & "]"
  if errors == 0:
    echo "[config] Validation passed."
  return errors

proc runConfigCli*(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if args.len == 0:
    logInfo("config_cli", "Usage: ax config <command>")
    logInfo("config_cli", "Commands: show, validate")
    return 1

  let cmd = args[0]
  case cmd
  of "show":
    return configShow()
  of "validate":
    return configValidate()
  else:
    logInfo("config_cli", "Unknown config subcommand: " & cmd)
    logInfo("config_cli", "Commands: show, validate")
    return 1
{.pop.}
