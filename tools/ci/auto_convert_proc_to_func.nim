## auto_convert_proc_to_func.nim — CI entry point for proc→func auto-conversion.
##
## Thin Nim wrapper that compiles and runs the full implementation at
## tools/auto_convert_proc_to_func.nim with pass-through CLI arguments.
## Replaces the former shell+Python wrapper pair.
##
## Usage:
##   nim c -r tools/ci/auto_convert_proc_to_func.nim --dry-run
##   nim c -r tools/ci/auto_convert_proc_to_func.nim --reset
##   nim c -r tools/ci/auto_convert_proc_to_func.nim
##
## Exit codes:
##   0 — success
##   1 — error (implementation failure or missing files)

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/[os, osproc, strutils]

# Minimal axiom pragma shim — mirrors core/axiom_pragmas for self-contained
# CI compilation.  In the full project context, import core/axiom_pragmas instead.
type
  AxiomEffectKind = enum
    Pure, IoEffect

template axiomEffect(effectType: AxiomEffectKind) {.pragma.}

const
  AnchorFile = ".axiom_root"
  ImplRel = "tools/auto_convert_proc_to_func.nim"
  MaxAncestors = 10

proc findRepoRoot(startDir: string): string {.raises: [].} =
  ## Walk up to MaxAncestors ancestors looking for .axiom_root anchor.
  result = startDir
  for _ in 0 .. MaxAncestors:
    try:
      if fileExists(result / AnchorFile):
        return result
    except CatchableError:
      discard  # axiom:best-effort(parentDir traversal — non-fatal, continues upward)
    let parent = parentDir(result)
    if parent == result:
      break
    result = parent

proc collectArgs(): seq[string] {.raises: [].} =
  ## Collect all command-line arguments, discarding on error.
  try:
    for i in 1 .. paramCount():
      result.add(paramStr(i))
  except CatchableError:
    discard  # axiom:best-effort(paramStr access failure — returns empty args)

proc main() {.axiomEffect: IoEffect, raises: [CatchableError].} =
  let repoRoot = findRepoRoot(getCurrentDir())
  let implPath = repoRoot / ImplRel
  if not fileExists(implPath):
    stderr.writeLine("auto_convert_proc_to_func: implementation not found: ", implPath)
    quit(1)

  let args = collectArgs()
  let nimExe = findExe("nim")
  if nimExe.len == 0:
    stderr.writeLine("auto_convert_proc_to_func: nim not found on PATH")
    quit(1)

  let cmd = nimExe & " c -r " & implPath & " " & args.join(" ")
  let (output, exitCode) = execCmdEx(cmd, workingDir = repoRoot)
  if output.len > 0:
    stdout.write(output)
  quit(exitCode)

when isMainModule:
  main()
