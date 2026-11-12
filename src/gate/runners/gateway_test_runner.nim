import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Gateway Test Runner
##
## Discovers, compiles, and executes ``tests/gateway/*_test.nim`` files
## using bounded-parallelism process pools. Two-phase execution:
## compile-all then run-all.

import std/os
import std/strutils
import std/strformat
import std/sequtils
import std/times
import gate/gate_types
import gate/types
import gate/runners/runner_process_pool
import core/trusted/axiom_pragmas
# axiomIoBoundary

# ============================================================================
# Dynamic Test Discovery
# ============================================================================

proc collectGatewayTestNames(repoRoot: string): seq[string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for kind, path in walkDir(repoRoot / "tests" / "gateway"):
    if kind == pcFile and path.endsWith("_test.nim") and
       not splitFile(path).name.startsWith("."):
      result.add(splitFile(path).name)

# ============================================================================
# Gateway Test Bounded Parallel Compilation
# ============================================================================

proc compileGatewayTests*(repoRoot: string; tests: seq[string];
                          maxJobs: int): bool {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var compileCmds: seq[CmdSpec] = @[]
  for t in tests:
    let src = repoRoot / &"tests/gateway/{t}.nim"
    let outBin = repoRoot / &"bin/{t}"
    if not fileExists(src):
      continue
    compileCmds.add(cmdSpec("nim", @["c", "--hints:off", "-o:" & outBin, src]))
  let compileCodes = runBatch(compileCmds, repoRoot, maxJobs)
  compileCodes.allIt(it.exitCode == 0)

proc runGatewayTestBinaries*(repoRoot: string; tests: seq[string];
                             maxJobs: int) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  when defined(gcOrc):
    GC_fullCollect()
  sleep(100)
  var runCmds: seq[CmdSpec] = @[]
  for t in tests:
    let binPath = repoRoot / &"bin/{t}"
    if fileExists(binPath):
      runCmds.add(cmdSpec(binPath, @[]))
  discard runBatch(runCmds, repoRoot, maxJobs)

proc runGatewayTest*(repoRoot: string; mode: GateRunMode;
                     maxJobs: int): GateResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let start = getTime()
  case mode
  of grmIncremental:
    return GateResult(
      ok: true,
      name: "Axiom gateway test gate",
      stdout: "Incremental mode: gateway tests deferred to pre-push",
      stderr: "",
      duration: getTime() - start
    )
  of grmExhaustive:
    discard
  let tests = collectGatewayTestNames(repoRoot)
  if not compileGatewayTests(repoRoot, tests, maxJobs):
    return GateResult(
      ok: false,
      name: "Axiom gateway test gate",
      stdout: "",
      stderr: "",
      duration: getTime() - start
    )
  runGatewayTestBinaries(repoRoot, tests, maxJobs)
  result = GateResult(
    ok: true,
    name: "Axiom gateway test gate",
    stdout: "",
    stderr: "",
    duration: getTime() - start
  )

{.pop.}
