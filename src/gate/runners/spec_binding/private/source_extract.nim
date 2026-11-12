## Source CLI identifier extraction from cli_surface_generated.nim
## and action_plan_cli.nim.
##
## Moved from spec_binding_gate.nim as part of A1-A5 split.

import core/trusted/layer_declaration
axiomLayer "gate"
import std/strutils
import std/sets
import std/os
import core/utils/file_utils
import gate/runners/spec_binding/private/utils
import gate/runners/spec_binding/private/types
# axiomIoBoundary

# ---------------------------------------------------------------------------
# Source CLI Identifier Extraction
# ---------------------------------------------------------------------------

proc extractFlagsFromCliSurface*(): HashSet[string] =
  result = initHashSet[string]()
  if not fileExists(CliSurfacePath):
    return
  try:
    let content = readFileSafe(CliSurfacePath)
    for line in content.splitLines():
      var i = 0
      while i < line.len - 1:
        if line[i] == '-' and line[i + 1] == '-':
          var j = i + 2
          while j < line.len and line[j] notin {' ', '"', '\'', ',', ')', ']', '}'}:
            j.inc
          if j > i + MinFlagLen:
            let rawFlag = line[i ..< j]
            var cleanFlag = rawFlag.split("=")[0]
            cleanFlag = cleanFlag.strip(chars = {' ', ':', ',', ';', '\n', '\r', '\t'})
            var valid = true
            for ch in cleanFlag:
              if ch notin {'a'..'z', 'A'..'Z', '0'..'9', '-'}:
                valid = false
                break
            if valid and cleanFlag.len >= MinFlagLen:
              var allDashes = true
              for ch in cleanFlag:
                if ch != '-':
                  allDashes = false
                  break
              if not allDashes:
                result.incl(cleanFlag)
          i = j
        else:
          i.inc
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc extractCommandsAndUsageFlagsFromActionPlan*(): (HashSet[string], HashSet[string]) =
  var commands = initHashSet[string]()
  var flags = initHashSet[string]()
  if not fileExists(ActionPlanPath):
    return (commands, flags)
  try:
    let content = readFileSafe(ActionPlanPath)
    for line in content.splitLines():
      let trimmed = line.strip()
      if trimmed.startsWith("name: \"ax ") or trimmed.startsWith("name:\"ax "):
        let start = trimmed.find('"')
        let stop = trimmed.find('"', start + 1)
        if start >= 0 and stop > start:
          let cmd = trimmed[start + 1 ..< stop]
          commands.incl(cmd)
      if trimmed.startsWith("usage:"):
        var i = 0
        while i < trimmed.len - 1:
          if trimmed[i] == '-' and i + 1 < trimmed.len and trimmed[i + 1] == '-':
            var j = i + 2
            while j < trimmed.len and trimmed[j] notin {' ', '"', '|', ']', ')', ','}:
              j.inc
            if j > i + MinFlagLen:
              var cleanFlag = trimmed[i ..< j].strip(chars = {' ', ':'})
              var valid = true
              for ch in cleanFlag:
                if ch notin {'a'..'z', 'A'..'Z', '0'..'9', '-'}:
                  valid = false
                  break
              if valid and cleanFlag.len >= MinFlagLen:
                flags.incl(cleanFlag)
            i = j
          else:
            i.inc
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  result = (commands, flags)

proc extractErrorMessages*(): HashSet[string] =
  result = initHashSet[string]()
  if not fileExists(ActionPlanPath):
    return
  try:
    let content = readFileSafe(ActionPlanPath)
    for line in content.splitLines():
      let trimmed = line.strip()
      if "\"'ax " in trimmed or "'ax " in trimmed:
        var inQuote = false
        var current = ""
        for ch in trimmed:
          if ch == '"':
            if inQuote and current.len > 0:
              result.incl(current)
              current = ""
            inQuote = not inQuote
          elif inQuote:
            current.add(ch)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc extractAllSourceIdentifiers*(): HashSet[string] =
  result = initHashSet[string]()
  for flag in extractFlagsFromCliSurface():
    result.incl(flag)
  let (cmds, usageFlags) = extractCommandsAndUsageFlagsFromActionPlan()
  for cmd in cmds:
    result.incl(cmd)
  for flag in usageFlags:
    result.incl(flag)
  for msg in extractErrorMessages():
    result.incl(msg)
