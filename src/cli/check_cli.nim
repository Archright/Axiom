import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
import core/axiom_pragmas
import infrastructure/hermetic_sandbox
import std/[algorithm, os, sequtils, strutils]
# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc listSourceFiles(dir: string): seq[string]  =
  ## Walk dir for .nim files, sorted alphabetically.
  result = @[]
  for path in walkDirRec(dir, relative = true):
    if path.endsWith(".nim"):
      result.add(dir / path)
  result.sort()

# ---------------------------------------------------------------------------
# nim check runner
# ---------------------------------------------------------------------------
proc runNimCheck*(files: seq[string], dryRun: bool): int {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run `nim check --hints:off --warnings:off` on each file.
  ## Returns 0 on all-pass, 1 if any file failed.
  var failed = 0
  let total = files.len
  for f in files:
    if dryRun:
      echo "would check: " & f
      continue
    let (output, exitCode) = hermeticExec(
      "nim", @["check", "--hints:off", "--warnings:off", f])
    if exitCode != 0:
      echo "FAIL: " & f
      if output.len > 0:
        echo output
      inc failed
    else:
      echo "OK: " & f

  if failed > 0:
    # Integer-only percentage: (count * 100) div total
    let pct = if total > 0: (failed * 100) div total else: 0
    echo "\n" & $failed & "/" & $total &
      " file(s) failed check (" & $pct & "%)"
    return 1
  return 0

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
proc run*(args: seq[string])  =
  try:
    var checkAll = false
    var dryRun = false
    for a in args:
      if a == "--all":
        checkAll = true
      elif a == "--dry-run":
        dryRun = true

    let root = getCurrentDir()
    let srcDir = root / "src"
    if not dirExists(srcDir):
      echo "ax check: src/ not found"
      quit(1)

    var files: seq[string]
    if checkAll:
      files = listSourceFiles(srcDir)
    else:
      # Default: only changed files via git diff HEAD~1
      let (gitOut, gitCode) = hermeticExec(
        "git", @["diff", "--name-only", "HEAD~1", "--", "src/"])
      if gitCode == 0 and gitOut.strip().len > 0:
        files = gitOut.strip().splitLines()
          .filterIt(it.endsWith(".nim") and fileExists(root / it))
      else:
        # Fallback: check all source files when git diff is unavailable
        files = listSourceFiles(srcDir)

    if files.len == 0:
      echo "ax check: no files to check"
      return

    echo "ax check: checking " & $files.len & " file(s)" &
      (if dryRun: " (dry-run)" else: "")
    let exitCode = runNimCheck(files, dryRun)
    quit(exitCode)
  except CatchableError:
    echo "ax check: error: " & getCurrentExceptionMsg()
    quit(1)
{.pop.}
