## Hermetic Policy Verification Feature Test
##
## Verifies the decoupled build/policy workflow:
##   - host builds a binary
##   - bin/hermetic_build verifies the hermetic build orchestration contract
##   - old build-style invocations are rejected with the current subcommand contract

import std/[os, osproc, streams, strtabs, strutils, unittest]

const
  FixtureSource = "build/hello_hermetic.nim"
  FixtureBinary = "build/hello_hermetic"

proc repoRoot(): string =
  ## tests/gateway/<file> -> project root
  result = absolutePath("../..", currentSourcePath().parentDir)

proc runHermetic(args: openArray[string]): tuple[output: string, exitCode: int] =
  let cmd = repoRoot() / "bin" / "hermetic_build"
  var env = newStringTable(modeCaseSensitive)
  for (k, v) in envPairs():
    if k != "AXIOM_HERMETIC_BUILDING":
      env[k] = v
  var process = startProcess(
    command = cmd,
    args = @args,
    env = env,
    options = {poUsePath, poStdErrToStdOut}
  )
  result.output = streams.readAll(process.outputStream)
  result.exitCode = process.waitForExit()
  process.close()

proc dockerAvailable(): bool =
  let (_, code) = execCmdEx("docker info")
  result = code == 0

suite "Hermetic policy verification":
  setup:
    let fixtureSrc = repoRoot() / FixtureSource
    let fixtureBin = repoRoot() / FixtureBinary
    writeFile(fixtureSrc, "echo \"hello from hermetic\"\n")
    let nim = findExe("nim")
    if nim.len == 0:
      raise newException(OSError, "nim not found on PATH")
    var compileProcess = startProcess(
      command = nim,
      # -d:AXIOM_GATE_BOND=1 skips config/integrity.nims manifestBootstrap so the
      # fixture compile doesn't re-run feature_manifest_generator (nested nim c).
      args = @["c", "-d:AXIOM_GATE_BOND=1", "-o:" & fixtureBin, fixtureSrc],
      workingDir = repoRoot(),
      options = {poUsePath, poStdErrToStdOut}
    )
    let compileOut = streams.readAll(compileProcess.outputStream)
    let compileCode = compileProcess.waitForExit()
    compileProcess.close()
    if compileCode != 0:
      echo compileOut
      raise newException(OSError, "failed to compile fixture binary")

  teardown:
    let fixtureSrc = repoRoot() / FixtureSource
    let fixtureBin = repoRoot() / FixtureBinary
    try:
      removeFile(fixtureSrc)
      removeFile(fixtureBin)
    except CatchableError:
      discard

  test "supplied binary is not an executable subcommand":
    if not dockerAvailable():
      echo "Docker not available; skipping hermetic policy verification test"
      skip()
    let (output, code) = runHermetic([FixtureBinary])
    check code != 0
    check "Unknown subcommand: " & FixtureBinary in output

  test "old build-style invocation is rejected":
    if not dockerAvailable():
      echo "Docker not available; skipping hermetic policy verification test"
      skip()
    let (output, code) = runHermetic(["nimble", "build"])
    check code != 0
    check "Unknown subcommand: nimble" in output

  test "forbidden interpreter invocation is rejected":
    if not dockerAvailable():
      echo "Docker not available; skipping hermetic policy verification test"
      skip()
    let (output, code) = runHermetic(["bash", "-c", "echo 1"])
    check code != 0
    check "Unknown subcommand: bash" in output
