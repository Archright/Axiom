import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

import std/strutils
import core/axiom_pragmas
import core/gate/state_ledger
import core/gate/state_ledger_types
import core/crypto/hash_kernel
import core/utils/repo_root
import cli/commands/command_registry

type ObservabilityCliResult* = object
  lines*: seq[string]
  exitCode*: int

proc runObservability*(repoRoot: string): ObservabilityCliResult {.
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect],
  raises: [CatchableError].} =
  var res = ObservabilityCliResult(exitCode: 0)

  if not ledgerFileExists(repoRoot):
    res.lines.add("No state ledger found at: " & getLedgerPath(repoRoot))
    res.lines.add("Run a pipeline first (ax prove or git commit).")
    res.exitCode = 1
    return res

  let ledger = openLedger(repoRoot)
  if ledger == nil:
    res.lines.add("State ledger found but corrupt or invalid (CRC/format mismatch).")
    res.lines.add("Expected path: " & getLedgerPath(repoRoot))
    res.exitCode = 1
    return res

  let crcHex = ledger.checksum.toHex
  let epoch = ledger.header.epoch
  let gateCount = ledger.header.gateCount
  let stage = ledger.workspace.stage
  let mode = ledger.workspace.mode

  var passCount, failCount, skipCount, deferredCount, unknownCount: int
  var totalExecTimeMs: int64

  for i in 0 ..< int(gateCount):
    let gResult = ledger.gates[i].result
    let gExecTime = ledger.gates[i].execTimeMs
    case gResult
    of uint8(lgrPass):
      inc passCount
    of uint8(lgrFail):
      inc failCount
    of uint8(lgrSkip):
      inc skipCount
    of uint8(lgrDeferred):
      inc deferredCount
    else:
      inc unknownCount
    totalExecTimeMs += int64(gExecTime)

  res.lines.add("=== Axiom Pipeline Observability ===")
  res.lines.add("")
  res.lines.add("State Ledger CRC32:  0x" & crcHex)
  res.lines.add("Epoch:               " & $epoch)
  res.lines.add("Stage:               " & $stage)
  res.lines.add("Mode:                " & $mode)
  res.lines.add("Gate Count:          " & $gateCount)
  res.lines.add("")
  res.lines.add("--- Per-Result Breakdown ---")
  res.lines.add("Pass:                " & $passCount)
  res.lines.add("Fail:                " & $failCount)
  res.lines.add("Skip:                " & $skipCount)
  res.lines.add("Deferred:            " & $deferredCount)
  res.lines.add("Unknown:             " & $unknownCount)
  res.lines.add("")
  res.lines.add("Total Exec Time (ms):" & $totalExecTimeMs)
  res.lines.add("")
  res.lines.add("--- Workspace Hashes ---")
  res.lines.add("Dirty Hash:          " & hashValueToHex(ledger.workspace.dirtyHash))
  res.lines.add("Rule Hash:           " & hashValueToHex(ledger.workspace.ruleHash))
  res.lines.add("Build Env Hash:      " & hashValueToHex(ledger.workspace.buildEnvHash))
  res.lines.add("Staging Tree Hash:   " & hashValueToHex(ledger.workspace.stagingTreeHash))

  closeLedger(ledger)

proc runObservabilityCmd*(args: seq[string]): int {.nimcall, raises: [].} =
  ## CommandHandler wrapper for ax observability.
  ## Handles --help flag and calls runObservability().
  if args.len > 0 and args[0] in ["--help", "-h"]:
    echo "Usage: ax observability"
    echo ""
    echo "Read pipeline state ledger and display observability dashboard."
    return 0
  try:
    let repoRoot = findRepoRoot()
    let cliResult = runObservability(repoRoot)
    for line in cliResult.lines:
      echo line
    cliResult.exitCode
  except CatchableError:
    echo "Error: " & getCurrentExceptionMsg()
    1

func registerObservabilityCommands*(): CommandRegistry {.raises: [].} =
  result = @[]
  result.register("observability", runObservabilityCmd,
    "Read pipeline state ledger and display observability dashboard")

{.pop.}
