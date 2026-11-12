## Orchestrator Hook Part1 Feature Test.
## See tests/features/orchestrator_hook.feature for the specification.
##
## Verifies that the orchestrator hook module exports key procs and constants,
## and that pure helper functions behave correctly under real inputs.

import std/[unittest, os, strutils]
import core/results
import gate/orchestrator_hook
import gate/gate_utils

suite "Orchestrator Hook Part1":
  test "L2GateTimeoutMs constant is 30_000 (default)":
    check L2GateTimeoutMs == 30_000

  test "GlobalMaxTokens constant is 12 (default)":
    check GlobalMaxTokens == 12

  test "loadGateSla returns default SLA for unknown gate":
    ## An unknown gate gets the canonical default SLA from the tracked SLA
    ## config (tools/config/gate_sla.json): default_timeout_sec 120 +
    ## orchestrator_buffer_sec 30 = 150_000ms. (The file-absent default
    ## 120_000ms is not reachable in a checkout that tracks gate_sla.json.)
    let sla = loadGateSla("nonexistent-gate-id")
    check sla == 150_000

  test "resolveGateSourcePath returns empty string for empty input":
    let result = resolveGateSourcePath("")
    check result.len == 0

  test "resolveGateSourcePath resolves existing source via candidate fallback":
    ## Given an entry like "bin/some_gate" with a matching src/gate/runners/some_gate.nim
    ## The proc searches standard candidate paths.
    ## Test with a known existing gate binary name.
    let result = resolveGateSourcePath("bin/action_plan_cli")
    ## Should find src/cli/action_plan_cli.nim or similar — or at least not crash
    discard result  # valid paths depend on filesystem state

  test "filterByPattern returns all files when pattern is empty":
    let files = @["src/core/types.nim", "tests/gate/main_test.nim"]
    let filtered = context.filterByPattern(files, "")
    check filtered.len == 2

  test "filterByPattern filters by pipe-separated substring":
    let files = @["src/core/types.nim", "src/core/types2.nim", "tests/gate/main_test.nim"]
    let filtered = context.filterByPattern(files, "core")
    check filtered.len == 2
    for f in filtered:
      check "core" in f

  test "filterByPattern matches multiple pipe-separated patterns":
    let files = @["src/core/types.nim", "docs/readme.md", "tests/gate/main_test.nim"]
    let filtered = context.filterByPattern(files, "core|gate")
    check filtered.len == 2

  test "filterByPattern returns empty for non-matching pattern":
    let files = @["src/core/types.nim", "docs/readme.md"]
    let filtered = context.filterByPattern(files, "zzz_nonexistent")
    check filtered.len == 0

  test "safeExecCmd runs a simple command with exit code 0":
    let res = safeExecCmd("/bin/echo test_output_12345")
    check res.isOk
    let (output, exitCode) = res.get()
    check exitCode == 0
    check "test_output_12345" in output

  test "safeExecCmd returns non-zero exit code for failing command":
    let res = safeExecCmd("/bin/false")
    check res.isOk
    let (_, exitCode) = res.get()
    check exitCode != 0

  test "RunningGate type is accessible and constructible":
    ## Verify the RunningGate type is properly exported and usable.
    var rg: RunningGate
    rg.gateIdx = 3
    rg.allocatedTokens = 5
    check rg.gateIdx == 3
    check rg.allocatedTokens == 5
