import core/trusted/layer_declaration


axiomLayer "gate"
import infrastructure/logger
{.push raises: [CatchableError].}

## External CLI Smoke Test Gate
##
## Compile-time source-binary hash verification gate.
## Prevents stale AOT binaries from being used by checking
## source file checksums against cached binary hashes.
import std/os
import std/osproc
import core/crypto/hash_kernel
import core/utils/io_utils
import core/axiom_pragmas
# axiomIoBoundary

# Compile-time embedded source hash: self-validating without external .sha256 file.
const
  repoRoot = currentSourcePath().parentDir().parentDir().parentDir().parentDir()
  embeddedHash = hash_kernel.sha256Hex(staticRead(repoRoot / "tools/ci/smoke_test.nim"))

const
  SmokeBinary = "bin/smoke_test"
  SmokeCacheDir = "build/nimcache/smoke_test"
  SmokeSource = "tools/ci/smoke_test.nim"

# Runtime freshness check: verify smoke_test.nim hasn't changed since gate compilation.
proc verifySmokeSourceFreshness() {.axiomEffect: IOEffect.} =
  let sourcePath = SmokeSource
  if not fileExists(sourcePath):
    logger.info("🚨 " & sourcePath & " not found. Cannot verify freshness.")
    quit(1)
  let currentHash = hash_kernel.sha256Hex(readFile(sourcePath))
  if currentHash != embeddedHash:
    logger.info("🚨 tools/ci/smoke_test.nim has changed since gate was compiled.")
    logger.info("   Recompile: nim c -o:bin/external_cli_smoke src/gate/runners/external_cli_smoke.nim")
    quit(1)

proc compileSmokeTest(): int {.axiomEffect: IOEffect.} =
  discard existsOrCreateDirOpt(SmokeCacheDir)
  let cmd = "nim c --hints:off --nimcache:" & quoteShell(SmokeCacheDir) &
            " -o:" & quoteShell(SmokeBinary) & " " & quoteShell(SmokeSource)
  let (output, exitCode) = execCmdEx(cmd)
  stdout.write(output)
  exitCode

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if "--skip-heavy" in commandLineParams():
    logger.info("Skipping external CLI smoke (--skip-heavy)")
    return
  verifySmokeSourceFreshness()

  var exitCode: int
  if fileExists(SmokeBinary):
    let (output, code) = execCmdEx(SmokeBinary)
    stdout.write(output)
    exitCode = code
  else:
    exitCode = compileSmokeTest()
    if exitCode == 0:
      let (output, code) = execCmdEx(SmokeBinary)
      stdout.write(output)
      exitCode = code

  quit(exitCode)

when isMainModule:
  main()

{.pop.}
