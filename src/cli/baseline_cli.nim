import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Baseline CLI — atomic SSOT baseline pipeline (Phase 2 WS-4).
##
##   ax baseline update  — rebuild data/baseline.json from the stable vault
##   ax baseline check   — verify baseline integrity per Zero-Theater Exit Contract:
##                         exit 2 = empty vault, 1 = VKD degraded, 0 = maintained
##
## The single SSOT output is `data/baseline.json`, produced by the same logic
## (baseline_snapshot_core.nim) used by tools/baseline_snapshot.nim.

import std/os
import core/axiom_pragmas
import core/types/results
import core/proof/proof_integrity
import core/parsers/safe_parsers
import infrastructure/logging_facade
import cli/shared/baseline_snapshot_core

proc kernelScopeFromCwd*(): KernelScopeInfo {.raises: [CatchableError].} =
  ## Loads verification_scope.lock from the project data dir.
  ## failClosed=true: missing/corrupt lock raises instead of degrading to empty scope.
  loadKernelScope(getCurrentDir() / BaselineDataDir / "verification_scope.lock", failClosed = true)

proc cmdBaselineUpdate*(): int {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Rebuild data/baseline.json from the stable certificate vault.
  echo "=== Axiom Baseline Update ==="
  echo "Scanning stable vault: " & ProofVaultDir
  try:
    let scope = kernelScopeFromCwd()
    let snap = computeBaselineSnapshot(ProofVaultDir, scope)
    let outPath = getCurrentDir() / BaselineDataDir / BaselineFileName
    # Monotonic ratchet guard, with a P0 certificate-reclassification carve-out:
    # a VKD drop is only permitted when it is a RECLASSIFICATION (previously
    # overstated certGreen certs correctly demoted to their evidence-derived
    # tier), never when it is an ACTUAL_REGRESSION of genuinely dual-verified
    # proofs. This lets the migration finalize its new evidence-derived baseline
    # (VKD 5→0) while still failing on real proof loss. See
    # baseline_snapshot_core.baselineCheckOutcome / changeKind.
    let storedVkd = readBaselineVkdFixed4(outPath)
    if storedVkd.len > 0:
      let outcome = baselineCheckOutcome(outPath, ProofVaultDir, scope)
      if outcome.code == ErrBaselineDegradedExit and
          outcome.changeKind != "RECLASSIFICATION":
        logError("baseline_cli",
          "[baseline] VKD regression (not a reclassification) — baseline NOT updated (" &
          snap.vkdFixed4 & " < " & storedVkd &
          ", changeKind=" & outcome.changeKind &
          "). Only reclassification or monotonic ratchet allowed.")
        return 1
      elif outcome.code == ErrBaselineDegradedExit:
        logError("baseline_cli",
          "[baseline] VKD drop accepted as certificate reclassification (" &
          snap.vkdFixed4 & " < " & storedVkd &
          ", changeKind=" & outcome.changeKind & ") — finalizing migration baseline.")
    let writeRes = writeBaseline(outPath, snap)
    if writeRes.isErr:
      logError("baseline_cli", "[baseline] update failed: " & writeRes.error)
      return 1
    echo "  VKD Fixed4:         " & snap.vkdFixed4
    echo "  Total Functions:    " & $snap.totalFunctions
    echo "  Verified Functions: " & $snap.verifiedFunctions
    echo "  VKD Score:          " & $snap.vkdScore
    echo "Written to: " & outPath
    result = 0
  except CatchableError as e:
    logError("baseline_cli", "[baseline] update failed: " & e.msg)
    result = 1

proc cmdBaselineCheck*(): int {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Verify baseline integrity per the Zero-Theater Exit Contract (ADR-0010):
  ##   Exit 2 — empty vault (kernel scope unhydrated)
  ##   Exit 1 — VKD_current < VKD_baseline (degraded) or no baseline found
  ##   Exit 0 — VKD_current >= VKD_baseline (maintained)
  echo "=== Axiom Baseline Check ==="
  let baselinePath = getCurrentDir() / BaselineDataDir / BaselineFileName
  try:
    let scope = kernelScopeFromCwd()
    let outcome = baselineCheckOutcome(baselinePath, ProofVaultDir, scope)
    case outcome.code
    of ErrEmptyVaultExit:
      echo "[ERROR] Vault unhydrated (kernel scope empty)"
      result = ErrEmptyVaultExit
    of ErrBaselineDegradedExit:
      if outcome.storedVkd.len == 0:
        echo "[WARN] No baseline found at " & baselinePath & ". Run 'ax baseline update' first."
      else:
        echo "[FAIL] VKD degraded: current " & outcome.currentVkd &
          " < baseline " & outcome.storedVkd
      result = ErrBaselineDegradedExit
    of OkBaselineExit:
      echo "[OK] Baseline maintained: " & outcome.currentVkd &
        " >= " & outcome.storedVkd
      result = OkBaselineExit
    else:
      logError("baseline_cli", "[baseline] check returned unknown exit code: " & $outcome.code)
      result = ErrBaselineDegradedExit
  except CatchableError as e:
    logError("baseline_cli", "[baseline] check failed: " & e.msg)
    result = 1

proc runBaselineCli*(args: seq[string]): int {.axiomDecision.} =
  let cmd = if args.len > 0: args[0] else: ""
  case cmd
  of "update":
    result = cmdBaselineUpdate()
  of "check":
    result = cmdBaselineCheck()
  else:
    echo "Usage: ax baseline <update|check>"
    echo "  update  Rebuild data/baseline.json from the stable vault"
    echo "  check   Verify baseline integrity (exit 0 on match)"
    result = 1

{.pop.}
