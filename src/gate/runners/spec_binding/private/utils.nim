import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}
# axiomIoBoundary

## Shared token parser for feature-file CLI surface scanning.

import std/sets
import std/strutils

const
  MinFlagLen* = 3
  ExcludedTokens* = [
    "assert", "assert-not", "and", "not", "true", "false",
    "given", "when", "then", "and", "but", "scenario",
    "feature", "rule", "background", "examples",
  ].toHashSet()

func isKnownAxSubcommand*(word: string): bool {.raises: [].} =
  const knownCommands = [
    "prove", "report", "verify", "gate", "mcp", "submit",
    "init", "dashboard", "uap", "integrity-loop", "help",
    "heal", "scan", "view", "trace", "diff", "check",
    "monitor", "status", "inspect", "submit-proof",
    "vault-sync", "cert", "procedure", "run",
    "induction", "workflow", "topology",
  ]
  word in knownCommands

type
  CliTokenScan* = object
    flags*: HashSet[string]
    commands*: HashSet[string]

func parseCliTokensFromLine*(line: string): CliTokenScan {.raises: [].} =
  result.flags = initHashSet[string]()
  result.commands = initHashSet[string]()
  let stripped = line.strip()
  if stripped.len == 0 or stripped.startsWith("#") or stripped.startsWith("@"):
    return
  var i = 0
  while i < stripped.len - 1:
    if stripped[i] == '-' and i + 1 < stripped.len and stripped[i + 1] == '-':
      var j = i + 2
      while j < stripped.len and stripped[j] notin {' ', '"', '\'', ',', ')', ']', '}', '?', '.', ':', '|'}:
        j.inc
      if j > i + MinFlagLen:
        let flag = stripped[i ..< j]
        var valid = true
        for ch in flag:
          if ch notin {'a'..'z', 'A'..'Z', '0'..'9', '-', '='}:
            valid = false
            break
        if valid:
          let cleanFlag = flag.split("=")[0]
          if cleanFlag.len >= MinFlagLen and cleanFlag notin ExcludedTokens:
            result.flags.incl(cleanFlag)
        i = j
      else:
        i.inc
    elif i + 2 < stripped.len and stripped[i] == 'a' and stripped[i + 1] == 'x' and stripped[i + 2] == ' ':
      var j = i + 3
      while j < stripped.len and stripped[j] != ' ':
        j.inc
      let subcmd = stripped[i + 3 ..< j]
      if subcmd.len > 0 and isKnownAxSubcommand(subcmd):
        result.commands.incl("ax " & subcmd)
      i = j
    else:
      i.inc

{.pop.}
