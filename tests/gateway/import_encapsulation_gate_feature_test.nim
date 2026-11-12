## Import Encapsulation Gate Feature Test.
## See tests/features/import_encapsulation_gate.feature for the specification.
##
## Verifies the import encapsulation gate via subprocess invocation:
##   - Gate binary compiles and executes correctly
##   - Intra-core imports (within src/core/) are allowed
##   - Exempted hub-module imports pass
##   - Direct internal imports from non-exempted paths are violations

import std/[unittest, os, osproc, strutils, times]

## Find or compile the import encapsulation gate binary.
proc getGateBinary(): string {.raises: [IOError, OSError, ValueError].} =
  ## Try to find pre-compiled binary in bin/
  let precompiled = "bin/import_encapsulation_gate"
  if fileExists(precompiled):
    return absolutePath(precompiled)

  ## Compile from source if pre-compiled binary not found
  let source = "src/gate/runners/import_encapsulation_gate.nim"
  if not fileExists(source):
    raise newException(OSError, "import encapsulation gate source not found: " & source)

  let tmpBin = getTempDir() / "axiom_import_encap_gate_" & $epochTime().int
  # -d:AXIOM_GATE_BOND=1 skips config/integrity.nims manifestBootstrap so the
  # nested nim c doesn't re-run feature_manifest_generator (parallel race).
  # Isolated repo-internal nimcache (all_gateway_runner convention) — the
  # default build/nimcache/debug is job-shared and cache-restored in CI, where
  # a stale cross-job state made this nested compile fail deterministically
  # (see docs/spec/loop_bmc_soundness.md sibling CI fix context).
  let isolatedNimcache = "build/gateway-tests/nimcache/import_encapsulation_gate"
  let compileCmd = "nim c --nimcache:" & isolatedNimcache &
                   " -d:AXIOM_GATE_BOND=1 -o:" & quoteShell(tmpBin) & " " & quoteShell(source)
  let compileResult = execCmdEx(compileCmd)
  if compileResult.exitCode != 0:
    raise newException(OSError, "Failed to compile import encapsulation gate:\n" & compileResult.output)

  return tmpBin

## Run an already-resolved gate binary as a subprocess and return the result.
proc runGateBinary(gateBin, repoRoot: string): tuple[ok: bool; stdout: string; stderr: string] {.raises: [IOError, OSError, ValueError].} =
  ## Gate binary expects: <repoRoot> <mode> <maxJobs> [files...]
  ## workingDir MUST be repoRoot — the gate resolves scanned paths relative to
  ## the process working directory, so any other cwd yields zero violations.
  let cmd = quoteShell(gateBin) & " " & quoteShell(absolutePath(repoRoot)) & " test 1"
  let procResult = execCmdEx(cmd, workingDir = repoRoot)
  result.ok = procResult.exitCode == 0
  result.stdout = procResult.output.strip()
  result.stderr = ""

## Run the import encapsulation gate as a subprocess and return the result.
proc runGateScan(repoRoot: string): tuple[ok: bool; stdout: string; stderr: string] {.raises: [IOError, OSError, ValueError].} =
  runGateBinary(getGateBinary(), repoRoot)

## Read the violation count out of the gate's "[GUARD] N ... violations:" line.
## The runner emits it through `logger.info`, so the line carries an
## "[INFO] logger: " prefix — the marker is located, not anchored.
## Returns -1 when no such line is present (i.e. the gate reported no violation
## block at all), so a vacuous "all clean" run cannot satisfy a count assertion.
proc guardViolationCount(outp: string): int =
  const marker = "[GUARD] "
  for line in outp.splitLines():
    let idx = line.find(marker)
    if idx < 0:
      continue
    let rest = line[idx + marker.len .. ^1]
    try:
      return parseInt(rest.split(' ')[0])
    except ValueError:
      discard
  return -1

suite "Import Encapsulation Gate":
  setup:
    let tmpDir = getTempDir() / "axiom_import_encap_test_" & $epochTime().int
    # Create directory structure matching what the scanner expects
    createDir(tmpDir / "src" / "gate")
    createDir(tmpDir / "src" / "core")

  teardown:
    removeDir(tmpDir)

  test "runImportEncapsulationScan passes on clean file":
    ## Given a .nim file with no internal path imports
    ## When runImportEncapsulationScan is called
    ## Then it returns ok=true
    writeFile(tmpDir / "src" / "gate" / "clean.nim",
      "import std/os\necho \"hello\"\n")
    let res = runGateScan(tmpDir)
    check res.ok == true

  test "intra-core import is allowed":
    ## Given a file inside src/core/ importing another core module
    ## When runImportEncapsulationScan is called
    ## Then it returns ok=true (intra-core imports are exempted)
    writeFile(tmpDir / "src" / "core" / "inner.nim",
      "import core/types/results\nproc foo() = discard\n")
    let res = runGateScan(tmpDir)
    check res.ok == true

  test "exempted hub import from src/gate/ is allowed":
    ## Given a file in src/gate/ importing core/parsers/ (exempted for gate/)
    ## When runImportEncapsulationScan is called
    ## Then it returns ok=true (hub exemption applies)
    writeFile(tmpDir / "src" / "gate" / "uses_parsers.nim",
      "import core/parsers/safe_parsers\nproc bar() = discard\n")
    let res = runGateScan(tmpDir)
    check res.ok == true

  test "non-exempted internal import is a violation":
    ## Given a file in src/gate/ importing core/bmc/ (NOT exempted for gate/)
    ## When runImportEncapsulationScan is called
    ## Then it returns ok=false with a violation reported
    writeFile(tmpDir / "src" / "gate" / "bad_import.nim",
      "import core/bmc/bmc_runner\nproc baz() = discard\n")
    let res = runGateScan(tmpDir)
    check res.ok == false
    check "violation" in res.stdout.toLowerAscii()

  test "non-exempted import from src/frontend/ is a violation":
    ## Given a file in src/frontend/ importing core/solver/ (NOT exempted for frontend/)
    ## When runImportEncapsulationScan is called
    ## Then it returns ok=false
    createDir(tmpDir / "src" / "frontend")
    writeFile(tmpDir / "src" / "frontend" / "bad.nim",
      "import core/solver/z3_backend\nproc render() = discard\n")
    let res = runGateScan(tmpDir)
    check res.ok == false

  test "empty file list with empty src/ returns ok":
    ## Given an empty src/ directory with no .nim files
    ## When runImportEncapsulationScan is called with no files
    ## Then it returns ok=true (nothing to scan)
    let emptyDir = tmpDir / "empty"
    createDir(emptyDir / "src")
    let res = runGateScan(emptyDir)
    check res.ok == true

  test "ambient verdict-shaping env cannot change the verdict":
    ## DEBT#478 closure — invariance property at the only unit that CAN express
    ## a verdict: the gate runner binary (exit code + [GUARD] line). For one
    ## fixed fixture the verdict and violation count are identical whether an
    ## uninvolved caller injects AXIOM_GATE_SEVERITY=warn, leaves it unset, or
    ## names it explicitly. Injection is direct — no bootstrap scrub in between,
    ## because the closure removed the parent-side scrub (DEBT#478 phase 1):
    ## the runner itself must be immune, on every path an orchestrator or a
    ## hostile caller can reach.
    writeFile(tmpDir / "src" / "gate" / "bad_import.nim",
      "import core/bmc/bmc_runner\nproc baz() = discard\n")
    writeFile(tmpDir / "src" / "gate" / "clean_control.nim",
      "import std/os\nproc control() = discard\n")

    let gateBin = getGateBinary()

    let ambientCases = [
      ("AXIOM_GATE_SEVERITY", "warn"),
      ("AXIOM_GATE_SEVERITY", ""),
      ("AXIOM_GATE_SEVERITY", "error")
    ]

    var runs: seq[tuple[ok: bool; stdout: string]] = @[]
    for (key, value) in ambientCases:
      # An uninvolved caller injects verdict-shaping env into the gate process.
      if value.len == 0:
        delEnv(key)
      else:
        putEnv(key, value)

      let res = runGateBinary(gateBin, tmpDir)
      runs.add((res.ok, res.stdout))

    delEnv("AXIOM_GATE_SEVERITY")

    # Non-vacuous: the fixture holds exactly one violation, and it is the same
    # single violation under every ambient setting — never a warn-only PASS.
    for r in runs:
      check r.ok == false
      check "[GUARD:WARN]" notin r.stdout
    check guardViolationCount(runs[0].stdout) == 1
    check guardViolationCount(runs[1].stdout) == 1
    check guardViolationCount(runs[2].stdout) == 1
