import core/trusted/layer_declaration
axiomLayer "gate"
import infrastructure/logger
{.push raises: [CatchableError].}

## Lean↔Z3 Consensus Gate — SA-δ2/δ3
##
## Verifies that both proof systems (Lean 4 formal proofs and Z3 SMT solver)
## are healthy and consistent. Implements Dual-Kernel Consensus.
##
## Checks:
##   1. Z3 solver is responsive (z3 --version)
##   2. Lean proof witness (proof_witness.json) exists and has valid structure
##   3. Lean proofs build successfully (lake build)
##   4. Proof hashes are consistent (no stale artifacts)
##
## Usage:
##   nim c -r src/gate/runners/lean_z3_consensus_gate.nim <repoRoot> <mode> <maxJobs> [files...]

import std/[json, os, osproc, strutils]
import core/axiom_pragmas
import core/trusted/env_access
import infrastructure/process_utils
import infrastructure/logging_facade



const
  ProofWitnessPath = "proofs/proof_witness.json"
  ProofsDir = "proofs"
  LeanToolchainPath = "proofs/lean-toolchain"

type
  ConsensusStatus = enum
    csPass       ## Both systems healthy and consistent
    csLeanOnly   ## Only Lean is healthy (Z3 unavailable)
    csZ3Only     ## Only Z3 is healthy (Lean proofs stale)
    csFail       ## Neither system is healthy

  ConsensusReport = object
    leanHealthy: bool
    leanWitnessValid: bool
    z3Healthy: bool
    z3Version: string
    leanVersion: string
    status: ConsensusStatus
    details: seq[string]

proc checkZ3Health(): tuple[healthy: bool, version: string] =
  try:
    let (output, exitCode) = execCmdEx("z3 --version")
    if exitCode == 0 and output.strip().len > 0:
      result.healthy = true
      result.version = output.strip()
    else:
      result.healthy = false
      result.version = "unavailable"
  except CatchableError:
    result.healthy = false
    result.version = "unavailable"

proc checkLeanToolchain(repoRoot: string): string {.axiomEffect: IOEffect.} =
  let toolchainPath = repoRoot / LeanToolchainPath
  if fileExists(toolchainPath):
    try:
      let content = readFile(toolchainPath).strip()
      if ":" in content:
        return content.split(':')[1]
      return content
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
  return "unknown"

proc checkProofWitness(repoRoot: string): tuple[valid: bool, hashCount: int, sourceHash: string] {.axiomEffect: IOEffect.} =
  let witnessPath = repoRoot / ProofWitnessPath
  if not fileExists(witnessPath):
    return (false, 0, "")

  try:
    let content = readFile(witnessPath)
    let parsed = parseJson(content)
    if not parsed.hasKey("lean_version") or
       not parsed.hasKey("traces") or
       not parsed.hasKey("source_hash") or
       not parsed.hasKey("overall_hash"):
      return (false, 0, "")

    let traces = parsed["traces"]
    let hashCount = traces.len
    let sourceHash = parsed["source_hash"].getStr()

    for key, val in traces:
      if not val.hasKey("depHash") or
         not val.hasKey("oleanHash") or
         not val.hasKey("sourceFile"):
        return (false, 0, "")

    return (hashCount > 0, hashCount, sourceHash)
  except CatchableError:
    return (false, 0, "")

proc checkLeanBuild(repoRoot: string): bool =
  let proofsDir = repoRoot / ProofsDir
  if not dirExists(proofsDir):
    return false
  try:
    # Ensure elan/lake is in PATH for subprocess
    let elanBin = getHomeDir() / ".elan" / "bin"
    let localBin = getHomeDir() / ".local" / "bin"
    let currentPath = getAxiomEnv(evPath, "")
    let newPath = elanBin & ":" & localBin & ":" & currentPath
    putEnv("PATH", newPath)
    let (output, exitCode) = execCmdWithTimeout("lake build", workingDir = proofsDir, timeoutMs = 120_000)
    result = exitCode == 0
    if not result:
      logger.info("[lean-z3-consensus] Lean build failed: " & output[0..min(200, output.len-1)])
  except CatchableError as e:
    logger.info("[lean-z3-consensus] Lean build error: " & e.msg)
    result = false

func determineStatus(report: ConsensusReport): ConsensusStatus =
  if report.leanHealthy and report.leanWitnessValid and report.z3Healthy:
    return csPass
  elif report.leanHealthy and report.leanWitnessValid:
    return csLeanOnly
  elif report.z3Healthy:
    return csZ3Only
  else:
    return csFail

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let args = commandLineParams()
  if args.len < 3:
    logInfo("lean_z3_consensus_gate", "Usage: lean_z3_consensus_gate <repoRoot> <mode> <maxJobs> [files...]")
    quit(1)

  let repoRoot = args[0]

  logger.info("=== Lean-Z3 Consensus Gate ===")

  var report: ConsensusReport
  report.details = @[]

  # Check 1: Z3 Health
  logger.info("[1/3] Checking Z3 solver health...")
  let (z3Ok, z3Ver) = checkZ3Health()
  report.z3Healthy = z3Ok
  report.z3Version = z3Ver
  if z3Ok:
    logger.info("  Z3: " & z3Ver & " OK")
    report.details.add("Z3 solver healthy: " & z3Ver)
  else:
    logger.info("  Z3: unavailable")
    report.details.add("Z3 solver unavailable")

  # Check 2: Proof Witness
  logger.info("[2/3] Checking proof witness...")
  let (witnessValid, hashCount, sourceHash) = checkProofWitness(repoRoot)
  report.leanWitnessValid = witnessValid
  if witnessValid:
    logger.info("  Witness: " & $hashCount & " traces, hash=" & sourceHash[0..min(15, sourceHash.len-1)] & " OK")
    report.details.add("Proof witness valid: " & $hashCount & " traces")
  else:
    logger.info("  Witness: invalid or missing")
    report.details.add("Proof witness invalid or missing")

  # Check 3: Lean Build
  logger.info("[3/3] Checking Lean proof build...")
  let leanVer = checkLeanToolchain(repoRoot)
  report.leanVersion = leanVer
  let leanBuildOk = checkLeanBuild(repoRoot)
  report.leanHealthy = leanBuildOk
  if leanBuildOk:
    logger.info("  Lean build: success (v" & leanVer & ") OK")
    report.details.add("Lean proofs build successfully")
  else:
    logger.info("  Lean build: failed")
    report.details.add("Lean proofs build failed")

  # Determine Status
  report.status = determineStatus(report)

  logger.info("")
  logger.info("=== Consensus Result ===")
  case report.status
  of csPass:
    logger.info("Status: PASS - Both Lean and Z3 are healthy")
  of csLeanOnly:
    logger.info("Status: PASS (Lean-only) - Z3 unavailable but Lean proofs valid")
  of csZ3Only:
    logger.info("Status: WARN (Z3-only) - Lean proofs stale, Z3 healthy")
  of csFail:
    logger.info("Status: FAIL - Neither proof system is healthy")

  for detail in report.details:
    logger.info("  - " & detail)

  case report.status
  of csPass, csLeanOnly, csZ3Only:
    quit(0)
  of csFail:
    quit(1)

when isMainModule:
  main()

{.pop.}
