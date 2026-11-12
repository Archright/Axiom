import std/unittest
import std/os
import std/json
import src/engine/profiler

suite "Profiler Tests":
  test "profileBlock with expression":
    let result = profileBlock("test expr"):
      42 + 1
    check result == 43

  test "profileBlock with statement":
    var x = 0
    profileBlock("test stmt"):
      x = 42
    check x == 42

  test "profileBlock emit writes a schema-v2 execution artifact to the CWD":
    # perf_latest.json is an untracked execution artifact (gitignored): the
    # emit lands under $CWD/data/benchmarks/, so this assertion runs in a
    # throwaway CWD — it exercises the fresh-checkout path (no prior latest)
    # and never reads or dirties the shared data/benchmarks/ tree.
    when defined(axiomProfile):
      let origDir = getCurrentDir()
      let tmpDir = getTempDir() / ("axiom_test_profiler_" & $getCurrentProcessId())
      try:
        removeDir(tmpDir)
      except OSError:
        discard
      createDir(tmpDir)
      defer:
        setCurrentDir(origDir)
        removeDir(tmpDir)
      setCurrentDir(tmpDir)
      profileBlock("slow test", 1):
        sleep(10)  # 10ms > 1ms threshold
      let perfData = readFile(tmpDir / "data" / "benchmarks" /
        "perf_latest.json").parseJson
      check perfData["schemaVersion"].getInt() == 2
      check perfData["measurements"]["slowtest"]["duration_us"].getInt() > 1_000
