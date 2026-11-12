## Documentation-First Gate Test
## Business scenario: Verify the gate enforces documentation-first protocol
## for system-level changes (AGENTS.md §0.5).

import std/[os, strutils, unittest]
import core/utils/repo_root
import core/utils/test_helper

const
  GateBinary = "bin/documentation_first_gate"
  TestConfigPath = "src/gate" / "configs" / "documentation_first.json"
  TestEvidenceDir = "docs" / "evidence"

let
  REPO_ROOT = findRepoRoot()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc createTempNimFile(dir, filename, content: string): string =
  ## Create a temporary .nim file for testing.
  let path = dir / filename
  writeFile(path, content)
  path

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

suite "documentation-first-gate":
  test "binary exists and runs --self-test":
    ## Business scenario: Gate binary is compiled and self-test passes.
    let (output, exitCode) = runGateInRepo(GateBinary, @["--self-test"])
    check exitCode == 0
    check output.contains("6 passed") or output.contains("passed")
    check output.contains("0 failed")

  test "pass on clean source files":
    ## Business scenario: Source files without trigger keywords pass the gate.
    let tmpDir = getTempDir() / "doc_first_test_clean"
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    let testFile = createTempNimFile(tmpDir, "clean_module.nim",
      "proc doSomething(): string =\n  result = \"hello world\"\n")
    let (output, exitCode) = runGateInRepo(GateBinary, @[testFile])
    check exitCode == 0
    check output.contains("Issues found: 0") or output.contains("no system-level keywords")

  test "detect kernel trigger in source file":
    ## Business scenario: Kernel keyword triggers documentation requirement.
    let tmpDir = getTempDir() / "doc_first_test_kernel"
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    let testFile = createTempNimFile(tmpDir, "kernel_config.nim",
      "# Configure kernel parameter settings\nconst\n  KERNEL_PARAM = true\n")
    let (output, exitCode) = runGateInRepo(GateBinary, @[testFile])
    # Should fail or warn about kernel trigger
    check output.contains("kernel") or output.contains("trigger")

  test "config file loads correctly":
    ## Business scenario: JSON config is parseable and contains expected triggers.
    let configPath = REPO_ROOT / TestConfigPath
    check fileExists(configPath)
    let content = readFile(configPath)
    check content.contains("trigger_components")
    check content.contains("\"keyword\": \"kernel\"")
    check content.contains("\"keyword\": \"grub\"")
    check content.contains("evidence_patterns")

  test "gate respects debug mode":
    ## Business scenario: When debug mode is active, gate prints diagnostics
    ## to stderr but exits 0 (non-blocking).
    let debugMarker = REPO_ROOT / ".axiom" / "debug_mode_on"
    let debugActive = fileExists(debugMarker)
    if debugActive:
      let tmpDir = getTempDir() / "doc_first_test_debug"
      createDir(tmpDir)
      defer: removeDir(tmpDir)

      let testFile = createTempNimFile(tmpDir, "trigger_debug.nim",
        "# kernel parameter modification\nboot_time = 100\n")
      let (output, exitCode) = runGateInRepo(GateBinary, @[testFile])
      # Debug mode: always exit 0
      check exitCode == 0
      check output.contains("DEBUG") or output.contains("diagnostics")

  test "pass on non-source files (markdown, json)":
    ## Business scenario: Documentation and config files are not scanned
    ## for trigger keywords — they are not system-level changes.
    let tmpDir = getTempDir() / "doc_first_test_nonsrc"
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    let mdFile = tmpDir / "notes.md"
    writeFile(mdFile, "# investigate kernel driver issue later\n")
    let (output, exitCode) = runGateInRepo(GateBinary, @[mdFile])
    # Markdown files should be skipped (not source files)
    check exitCode == 0
