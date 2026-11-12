## tools/verify_clean_build.nim — CP4: Clean build verification before commit
##
## Forces a clean build with isolated nimcache to catch delayed regressions
## caused by stale incremental compilation cache.
##
## Usage:
##   nim c -r tools/verify_clean_build.nim
##
## Returns 0 on success, 1 on failure.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, strutils, times]

const
  CleanCacheDir = "build/nimcache_clean"
  MainTarget = "src/axiom.nim"

proc cleanBuild(): bool =
  ## Perform a clean build with isolated nimcache.
  echo "[verify_clean_build] Starting clean build verification..."
  echo "[verify_clean_build] Clean cache: " & CleanCacheDir

  # Remove old clean cache
  if dirExists(CleanCacheDir):
    removeDir(CleanCacheDir)

  # Create fresh cache directory
  createDir(CleanCacheDir)

  # Run clean build
  let cmd = "nim c -f --nimcache:" & CleanCacheDir &
            " -d:axiomStrict -d:release --hints:off " & MainTarget
  echo "[verify_clean_build] Running: " & cmd

  let (output, exitCode) = execCmdEx(cmd)

  if exitCode == 0:
    echo "[verify_clean_build] PASS — Clean build succeeded"
    result = true
  else:
    echo "[verify_clean_build] FAIL — Clean build failed with exit code: " & $exitCode
    echo "[verify_clean_build] Output:"
    echo output
    result = false

  # Cleanup
  removeDir(CleanCacheDir)

proc main() =
  let startTime = epochTime()
  let success = cleanBuild()
  let duration = epochTime() - startTime

  echo "[verify_clean_build] Duration: " & formatFloat(duration, ffDecimal, 2) & "s"

  if not success:
    quit(1)

when isMainModule:
  main()
