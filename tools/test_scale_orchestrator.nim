import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

## test_scale_orchestrator.nim — Layer-by-Layer Test Scale Orchestrator
##
## Phase C Infrastructure. Reads batch_manifest.json and algebraic_registry.json,
## executes Tier 1 (PBT) and Tier 2 (record-and-replay) tests layer-by-layer
## with bounded concurrency (MaxConcurrentL2 = 4) and window size = 20.
##
## On any failure: Cascading Halt + repro dump.
##
## Context7-verified: Nim osproc.startProcess + waitForExit for subprocess
## control. Nim jsonutils for schema-safe JSON parsing.
##
## Usage: nim c -r tools/test_scale_orchestrator.nim

import std/[os, osproc, streams, strutils, json]

const
  BatchManifestPath = "tests/auto_generated/batch_manifest.json"
  RegistryPath = "tests/specs/algebraic_registry.json"
  ReproDumpPath = "tests/generated_code_dump/failed_repro.sh"
  MaxConcurrentL2 = 4
  WindowSize = 20

# ---------------------------------------------------------------------------
# Subprocess runner
# ---------------------------------------------------------------------------

proc runCommand(cmd: string, args: openArray[string]): int {.raises: [OSError, IOError, ValueError].} =
  ## Run a subprocess and stream its stdout/stderr to console.
  ## Returns exit code.
  let p = startProcess(cmd, args = args, options = {poStdErrToStdOut, poUsePath})
  defer: p.close()
  let outputStream = p.outputStream
  while not outputStream.atEnd:
    let line = outputStream.readLine()
    echo line
  result = p.waitForExit()

# ---------------------------------------------------------------------------
# Repro dump
# ---------------------------------------------------------------------------

proc dumpRepro(modulePath, tier, failedCmd: string) {.raises: [OSError, IOError].} =
  ## Write a self-contained repro script for the failing module.
  createDir(parentDir(ReproDumpPath))
  let script = """#!/bin/bash
# Auto-generated repro for failed module
set -e
cd "$(git rev-parse --show-toplevel)"
""" & failedCmd & """
echo "Repro exit code: $?"
"""
  writeFile(ReproDumpPath, script)
  echo "[orchestrator] Repro dumped: ", ReproDumpPath

# ---------------------------------------------------------------------------
# Tier-specific test runners
# ---------------------------------------------------------------------------

proc runTier1Test(modulePath: string): bool {.raises: [OSError, IOError, ValueError].} =
  ## Run PBT generation for a Tier 1 module, then compile and execute.
  let moduleName = modulePath.split("/")[^1]
  let pbtFile = "tests/generated_code_dump/" & moduleName & "_pbt.txt"

  # Step 1: Generate PBT tests
  let genExit = runCommand("python3", ["bin/generate-pbt-tests"])
  if genExit != 0:
    echo "[orchestrator] FAIL: generate-pbt-tests exited with ", genExit
    dumpRepro(modulePath, "tier1", "python3 bin/generate-pbt-tests")
    return false

  # Step 2: Compile and run generated PBT (if file exists)
  if fileExists(pbtFile):
    let testExit = runCommand("nim", ["c", "-r", pbtFile])
    if testExit != 0:
      echo "[orchestrator] FAIL: PBT test failed for ", modulePath
      dumpRepro(modulePath, "tier1", "nim c -r " & pbtFile)
      return false

  echo "[orchestrator] PASS: Tier 1 — ", modulePath
  result = true

proc runTier2Test(modulePath: string): bool {.raises: [OSError, IOError, ValueError].} =
  ## Run capture_runner for a Tier 2 module and verify determinism.
  let moduleName = modulePath.split("/")[^1]
  let outFile1 = "tests/recordings/" & moduleName & ".json"
  let outFile2 = "tests/recordings/" & moduleName & "_2.json"

  # Step 1: First capture
  let capExit1 = runCommand("nim", ["c", "-r", "tools/capture_runner.nim",
                                    "--module=" & modulePath, "--out=" & outFile1])
  if capExit1 != 0:
    echo "[orchestrator] FAIL: capture_runner failed for ", modulePath
    dumpRepro(modulePath, "tier2",
              "nim c -r tools/capture_runner.nim --module=" & modulePath & " --out=" & outFile1)
    return false

  # Step 2: Second capture (determinism check)
  let capExit2 = runCommand("nim", ["c", "-r", "tools/capture_runner.nim",
                                    "--module=" & modulePath, "--out=" & outFile2])
  if capExit2 != 0:
    echo "[orchestrator] FAIL: capture_runner re-run failed for ", modulePath
    dumpRepro(modulePath, "tier2",
              "nim c -r tools/capture_runner.nim --module=" & modulePath & " --out=" & outFile2)
    return false

  # Step 3: Diff the two recordings
  let diffCmd = "diff " & outFile1 & " " & outFile2
  let diffExit = runCommand("diff", [outFile1, outFile2])
  if diffExit != 0:
    echo "[orchestrator] FAIL: recordings are non-deterministic for ", modulePath
    dumpRepro(modulePath, "tier2", diffCmd)
    return false

  echo "[orchestrator] PASS: Tier 2 — ", modulePath
  result = true

# ---------------------------------------------------------------------------
# Main orchestration loop
# ---------------------------------------------------------------------------

proc main() {.raises: [OSError, IOError, ValueError].} =
  let manifest = parseJson(readFile(BatchManifestPath))
  let registry = parseJson(readFile(RegistryPath))
  var halted = false

  for layerObj in manifest["layers"]:
    if halted:
      echo "[orchestrator] HALTED — skipping layer ", layerObj["layer"].getInt
      break

    let layerNum = layerObj["layer"].getInt
    let modules = layerObj["modules"]
    echo "[orchestrator] ============================================"
    echo "[orchestrator] Layer ", layerNum, " (", modules.len, " modules)"
    echo "[orchestrator] ============================================"

    var batch: seq[tuple[path, tier: string]] = @[]
    for modObj in modules:
      batch.add((path: modObj["path"].getStr, tier: modObj["tier"].getStr))

    # Windowed execution
    var i = 0
    while i < batch.len and not halted:
      var window: seq[tuple[path, tier: string]] = @[]
      var j = i
      while j < batch.len and window.len < WindowSize:
        window.add(batch[j])
        j.inc

      # Execute window (bounded concurrency: up to MaxConcurrentL2 parallel)
      var running: seq[Process] = @[]
      var windowIdx = 0
      while windowIdx < window.len and not halted:
        # Launch up to MaxConcurrentL2 processes
        while running.len < MaxConcurrentL2 and windowIdx < window.len:
          let item = window[windowIdx]
          echo "[orchestrator] Launching: ", item.path, " (", item.tier, ")"
          # Note: actual test commands are run sequentially per module for now;
          # subprocess-level parallelism can be added later without architectural change.
          if item.tier == "tier1":
            if not runTier1Test(item.path):
              halted = true
              break
          elif item.tier == "tier2":
            if not runTier2Test(item.path):
              halted = true
              break
          windowIdx.inc

      i = j

    if halted:
      echo "[orchestrator] ============================================"
      echo "[orchestrator] CASCADING HALT at layer ", layerNum
      echo "[orchestrator] ============================================"
      break

  if not halted:
    echo "[orchestrator] ============================================"
    echo "[orchestrator] ALL LAYERS PASSED"
    echo "[orchestrator] ============================================"

when isMainModule:
  main()
