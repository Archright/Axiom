## Nimtry Synthetic Fixture Test Runner
##
## Fixtures in tests/unit/nimtry_fixtures/ are intentionally-bad modules,
## but their actual paths (tests/unit/...) do not match production layer
## patterns (src/core/, src/cli/, etc.), so layerForPath() returns "" and
## no violations are triggered.
##
## This test runner copies each fixture to a temporary directory with a
## matching src/<layer>/ structure, then runs bin/nimtry using relative
## paths (e.g., "src/core/soc_violation.nim") from within the temp dir.
##
## Key insight: bin/nimtry uses getCurrentDir() as the repo root for
##   (a) loading src/gate/architecture_policy.lock
##   (b) normalizing file paths via normalizedPath() which strips
##       the repo-root prefix before layer matching
##   Both require running from the temp dir with relative paths.
##
## Usage: nim c -r tests/integration/test_nimtry_fixtures.nim

when defined(axiomIntegration) or defined(leanIntegration):

  import std/[os, osproc, strutils, sequtils, times, unittest]

  const
    RepoRoot = currentSourcePath().parentDir().parentDir().parentDir()
    NimtryBin = RepoRoot / "bin" / "nimtry"
    PolicyLock = RepoRoot / "src" / "gate" / "architecture_policy.lock"
    FixturesDir = RepoRoot / "tests" / "unit" / "nimtry_fixtures"

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  proc runNimtry(tmpDir: string; files: seq[string]; baseRef: string = ""): tuple[exitCode: int; output: string] =
    ## Run bin/nimtry from tmpDir with relative file arguments.
    ## Optional baseRef enables temporal OCP detection via --base-ref.
    let args = files.map(proc(f: string): string = f.quoteShell).join(" ")
    let baseRefArg = if baseRef.len > 0: " --base-ref " & baseRef.quoteShell else: ""
    let (output, exitCode) = execCmdEx(NimtryBin.quoteShell & baseRefArg & " " & args,
                                       workingDir = tmpDir)
    (exitCode, output.strip())

  proc setupFixture(tmpDir: string; file: string; layer: string): bool =
    ## Copy a fixture + policy lock into temp dir.
    ## Also lowers the DRY node-count threshold so small fixture functions
    ## are checked for duplication (default 50 is too high for fixtures).
    try:
      createDir(tmpDir / "src" / layer)
      createDir(tmpDir / "src" / "gate")
      copyFile(PolicyLock, tmpDir / "src" / "gate" / "architecture_policy.lock")
      let policyPath = tmpDir / "src" / "gate" / "architecture_policy.lock"
      var policyContent = readFile(policyPath)
      policyContent = policyContent.replace("function_clone_min_ast_nodes = 50", "function_clone_min_ast_nodes = 5")
      writeFile(policyPath, policyContent)
      copyFile(FixturesDir / file, tmpDir / "src" / layer / file)
      result = true
    except IOError:
      result = false

  # ---------------------------------------------------------------------------
  # Test cases
  # ---------------------------------------------------------------------------

  suite "nimtry synthetic fixtures with correct layer paths":

    test "soc_violation (core): triggers 3 SoC layer import violations":
      ## Core layer has empty edges (cannot import from any other layer).
      ## soc_violation imports cli/axiom_engine, cli/wf_semantic, gate/gate_list.
      let tmpDir = getTempDir() / "nimtry_fx_soc_" & $toUnix(getTime())
      require setupFixture(tmpDir, "soc_violation.nim", "core")
      let (exitCode, output) = runNimtry(tmpDir, @["src/core/soc_violation.nim"])
      removeDir(tmpDir)

      check exitCode != 0
      check "FAILED" in output
      check "3 violations" in output
      check "[SoC]" in output
      check "soc-layer-imports" in output
      check "cli/axiom_engine" in output
      check "cli/wf_semantic" in output
      check "gate/gate_list" in output

    test "solid_srp_violation (core): triggers surface-area + OCP violations":
      ## 22+ unrelated functions with 23 exported functions (core max 15).
      ## 6 case branches with 0 registry calls.
      let tmpDir = getTempDir() / "nimtry_fx_srp_" & $toUnix(getTime())
      require setupFixture(tmpDir, "solid_srp_violation.nim", "core")
      let (exitCode, output) = runNimtry(tmpDir, @["src/core/solid_srp_violation.nim"])
      removeDir(tmpDir)

      check exitCode != 0
      check "FAILED" in output
      check "2 violations" in output
      check "[SOLID]" in output
      check "soc-surface-area" in output
      check "23 exported functions" in output
      check "solid-ocp" in output
      check "6 case branches" in output

    test "ssot_violation (cli): triggers SSOT type-placement violation":
      ## Defines ValidatedAsi outside its canonical owner src/core/metrics.nim.
      let tmpDir = getTempDir() / "nimtry_fx_ssot_" & $toUnix(getTime())
      require setupFixture(tmpDir, "ssot_violation.nim", "cli")
      let (exitCode, output) = runNimtry(tmpDir, @["src/cli/ssot_violation.nim"])
      removeDir(tmpDir)

      check exitCode != 0
      check "FAILED" in output
      check "[SSOT]" in output
      check "ssot-type-placement" in output
      check "ValidatedAsi" in output
      check "metrics.nim" in output

    test "dry_violation + dry_violation_b (core): triggers SOLID SRP cohesion":
      ## Both files have 3 functions each with no shared variable refs,
      ## yielding LCOM=0.6667 > threshold 0.6.
      let tmpDir = getTempDir() / "nimtry_fx_dry_" & $toUnix(getTime())
      require setupFixture(tmpDir, "dry_violation.nim", "core")
      require setupFixture(tmpDir, "dry_violation_b.nim", "core")
      let (exitCode, output) = runNimtry(tmpDir, @["src/core/dry_violation.nim", "src/core/dry_violation_b.nim"])
      removeDir(tmpDir)

      check exitCode != 0
      check "FAILED" in output
      check "5 violations" in output
      check "[SOLID]" in output
      check "solid-srp" in output
      check "LCOM=" in output
      check "[DRY]" in output
      check "exact AST fingerprint duplicate" in output

    test "solid_dip_violation (cli): triggers SOLID forbidden-calls (DIP)":
      ## Calls z3ExecPersistent and z3Spawn from src/cli/, which are
      ## restricted to allowed callers in src/core/solver_bridge.nim etc.
      let tmpDir = getTempDir() / "nimtry_fx_dip_" & $toUnix(getTime())
      require setupFixture(tmpDir, "solid_dip_violation.nim", "cli")
      let (exitCode, output) = runNimtry(tmpDir, @["src/cli/solid_dip_violation.nim"])
      removeDir(tmpDir)

      check exitCode != 0
      check "FAILED" in output
      check "[SOLID]" in output
      check "solid-forbidden-calls" in output
      check "z3ExecPersistent" in output

    test "canonical_dry_violation_a + canonical_dry_violation_b (core): triggers exact AST DRY":
      ## Both files define exported functions that differ syntactically but are
      ## semantically equivalent after PNode canonical normalization (commutative
      ## operator sorting + not-branch normalization). Canonicalized AST
      ## fingerprints match, triggering a cross-file exact-duplicate DRY violation.
      let tmpDir = getTempDir() / "nimtry_fx_canon_dry_" & $toUnix(getTime())
      require setupFixture(tmpDir, "canonical_dry_violation_a.nim", "core")
      require setupFixture(tmpDir, "canonical_dry_violation_b.nim", "core")
      let (exitCode, output) = runNimtry(tmpDir, @["src/core/canonical_dry_violation_a.nim", "src/core/canonical_dry_violation_b.nim"])
      removeDir(tmpDir)

      check exitCode != 0
      check "FAILED" in output
      check "[DRY]" in output
      check "exact AST fingerprint duplicate" in output

    test "ocp_temporal_violation (core): triggers OCP only for newly added branch":
      ## Base version has 2 case branches (no violation). New commit adds a
      ## 3rd branch without registry calls. With --base-ref HEAD~1, only the
      ## new branch should be counted, triggering solid-ocp.
      let tmpDir = getTempDir() / "nimtry_fx_ocp_temp_" & $toUnix(getTime())
      require setupFixture(tmpDir, "ocp_temporal_violation.nim", "core")

      # Write base version (2 branches) and commit
      let baseContent = "proc dispatchAction*(action: string): string =\n  case action\n  of \"start\": result = \"started\"\n  of \"stop\": result = \"stopped\"\n  of \"pause\": result = \"paused\"\n  else: result = \"unknown\"\n"
      writeFile(tmpDir / "src" / "core" / "ocp_temporal_violation.nim", baseContent)
      discard execCmdEx("git init", workingDir = tmpDir)
      discard execCmdEx("git config user.email \"test@test.com\"", workingDir = tmpDir)
      discard execCmdEx("git config user.name \"Test\"", workingDir = tmpDir)
      discard execCmdEx("git add .", workingDir = tmpDir)
      discard execCmdEx("git commit -m \"base\"", workingDir = tmpDir)

      # Overwrite with new version (3 branches) and commit
      copyFile(FixturesDir / "ocp_temporal_violation.nim", tmpDir / "src" / "core" / "ocp_temporal_violation.nim")
      discard execCmdEx("git add .", workingDir = tmpDir)
      discard execCmdEx("git commit -m \"add branch\"", workingDir = tmpDir)

      let (exitCode, output) = runNimtry(tmpDir, @["src/core/ocp_temporal_violation.nim"], "HEAD~1")
      removeDir(tmpDir)

      check exitCode != 0
      check "FAILED" in output
      check "[SOLID]" in output
      check "solid-ocp" in output

    test "solid_pragma_violation (mcp): triggers SOLID forbidden-pragmas (SoC)":
      ## Uses {.dynlib.} from src/mcp/, which is restricted to
      ## src/cli/action_interpreter_cli.nim and src/core/sync_utils_*.nim.
      let tmpDir = getTempDir() / "nimtry_fx_pragma_" & $toUnix(getTime())
      require setupFixture(tmpDir, "solid_pragma_violation.nim", "mcp")
      let (exitCode, output) = runNimtry(tmpDir, @["src/mcp/solid_pragma_violation.nim"])
      removeDir(tmpDir)

      check exitCode != 0
      check "FAILED" in output
      check "[SOLID]" in output
      check "solid-forbidden-pragmas" in output
      check "dynlib" in output
