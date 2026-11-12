import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import api/tools_facade
import shared_types/gate_bridge
import shared_types/shared_types
import std/[os, strformat, tables, parseopt, strutils]
proc printUsage() =
  stderr.writeLine """pipeline_runner — Unified Axiom Pipeline

Usage: pipeline_runner [options]

Options:
  --stage STAGE    Gate stage: pre-commit, pre-push, manual (default: manual)
  --max-jobs N     Max parallel gate jobs (default: 4)
  --scan-dirs DIRS Comma-separated scan directories (default: src)
  --with-ast       Build AST cache for quality gates
  --show-cache     Print cached .axiom_state.json and exit
  --clear-cache    Delete .axiom_state.json and force full re-run
  --help           Show this help"""
proc parseStage(s: string): GateStage =
  case s
  of "pre-commit": gsPreCommit
  of "pre-push": gsPrePush
  of "manual": gsManual
  else: gsManual
proc main() =
  var stage = gsManual
  var maxJobs = 4
  var scanDirs: seq[string] = @["src"]
  var withAst = false
  var showCache = false
  var clearCache = false

  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      case p.key
      of "stage": stage = parseStage(p.val)
      of "max-jobs": maxJobs = parseInt(p.val)
      of "scan-dirs": scanDirs = p.val.split(",")
      of "with-ast": withAst = true
      of "show-cache": showCache = true
      of "clear-cache": clearCache = true
      of "help":
        printUsage()
        quit(0)
      else:
        stderr.writeLine &"Unknown option: --{p.key}"
        printUsage()
        quit(1)
    of cmdArgument:
      discard

  let repoRoot = findRepoRoot()
  if repoRoot.len == 0:
    stderr.writeLine "[PIPELINE] Error: Not inside Axiom project (no .axiom_root found)"
    quit(1)

  let cachePath = repoRoot / ".axiom" / "cache" / ".axiom_state.json"

  # --show-cache: Print and exit
  if showCache:
    if fileExists(cachePath):
      echo readFile(cachePath)
    else:
      echo "{}"
    quit(0)

  # --clear-cache: Delete and continue
  if clearCache:
    if fileExists(cachePath):
      removeFile(cachePath)
      stderr.writeLine "[PIPELINE] Cache cleared."
    quit(0)

  # runPipeline internally calls registerDefaultInProcessGates()
  let ok = runPipeline(stage, repoRoot, maxJobs, epoch = 0, scanDirs = scanDirs)

  if ok:
    stderr.writeLine "[PIPELINE] All gates PASSED."
    quit(0)
  else:
    stderr.writeLine "[PIPELINE] FAILED — see gate output above."
    quit(1)

main()
{.pop.}
