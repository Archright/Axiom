## check_lean_vacuity_v2.nim — Nim wrapper around the Lean 4 vacuity scanner.
##
## Uses `lake run check-vacuity` to invoke check_vacuity.lean via the Lake build
## system. This ensures all dependencies are built before the scan runs.
##
## Usage:
##   nim c -o:bin/check_lean_vacuity_v2 tools/ci/check_lean_vacuity_v2.nim
##   bin/check_lean_vacuity_v2 [file1.lean ...]
##
## When no files are given, scans all .lean files under proofs/ (except lakefile).
## Exit code:
##   0 = no vacuity detected
##   1 = vacuity or tool error

import core/trusted/layer_declaration
axiomLayer "tools"
import api/tools_facade
import std/[os, osproc, streams, strutils]

type
  VacuityResult* = object
    file*: string
    pass*: bool
    detail*: string

const proofsDir = "proofs"

proc findRepoRoot*(): string {.axiomEffect: IoEffect.} =
  var dir = getAppDir()
  while dir.len > 0:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = parentDir(dir)
    if parent == dir:
      break
    dir = parent
  result = getAppDir() / ".." / ".."
  normalizePath(result)

proc collectLeanFiles*(root: string): seq[string] =
  result = @[]
  for path in walkDirRec(root):
    if path.endsWith(".lean") and not path.endsWith("lakefile.lean"):
      result.add path

proc runVacuityCheck*(files: seq[string]): seq[VacuityResult] {.axiomEffect: IoEffect.} =
  result = @[]
  let repoRoot = findRepoRoot()
  let lakeExe = findExe("lake")
  if lakeExe.len == 0:
    result.add VacuityResult(
      file: "<tool>", pass: false,
      detail: "lake executable not found in PATH"
    )
    return

  let proofsAbs = repoRoot / proofsDir
  if not dirExists(proofsAbs):
    result.add VacuityResult(
      file: proofsAbs, pass: false,
      detail: "proofs directory not found"
    )
    return

  try:
    let args = @["script", "run", "check_vacuity"] & files
    var p = startProcess(lakeExe, args = args, workingDir = proofsAbs,
                         options = {poStdErrToStdOut, poUsePath})
    let outStream = p.outputStream()
    let output = outStream.readAll()
    let exitCode = p.waitForExit()
    result.add VacuityResult(
      file: if files.len > 0: files.join(", ") else: "all",
      pass: exitCode == 0,
      detail: output.strip()
    )
  except OSError as e:
    result.add VacuityResult(file: "lake", pass: false, detail: e.msg)

proc main*() {.axiomEffect: IoEffect.} =
  let params = commandLineParams()
  let files = if params.len > 0: params else: collectLeanFiles(findRepoRoot() / proofsDir)

  let results = runVacuityCheck(files)
  var passed = 0
  var failed = 0
  for r in results:
    if r.pass:
      echo "PASS: ", r.file
      inc passed
    else:
      echo "FAIL: ", r.file
      if r.detail.len > 0:
        echo r.detail
      inc failed

  echo "\n", passed, " passed, ", failed, " failed"
  if failed > 0:
    quit(1)
  else:
    quit(0)

when isMainModule:
  main()
