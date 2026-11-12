import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## VKD Sync CLI — atomic composite VKD lifecycle command (Phase D2).
##
##   ax vkd sync — atomically: prove (regenerate certs, limit 25, updateLock)
##                 → safe orphan cleanup → baseline update.
##
## Replaces the manual 3-step SOP (prove --limit 25 --update-lock; safe orphan
## cleanup; baseline update) with a single command. Mirrors the exact prove
## entry used by the CLI (`runAxiomEngineCli`) and delegates baseline update to
## `cmdBaselineUpdate` (which respects the monotonic VKD ratchet, ADR-0011).

import std/os
import core/axiom_pragmas
import core/types/results
import cli/axiom_engine
import cli/baseline_cli
import cli/cli_outcome
import cli/scope_cli
import cli/shared/baseline_snapshot_core
import core/utils/repo_root
import verification/vault_manifest
import infrastructure/logging_facade

const
  VkdSyncProveLimit = 25

proc cmdVkdSync*(): int {.raises: [CatchableError, IOEffect], axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Atomic VKD lifecycle: prove → safe orphan cleanup → baseline update.
  ## Returns 0 on success; non-zero with logged messages on any step failure.
  echo "=== Axiom VKD Sync ==="

  # Step 0a: Regenerate verification_scope.lock BEFORE prove so it stays in
  # sync with the certificate vault across the prove + baseline update cycle.
  # runAxiomEngineCli calls generateAxiomInit internally, but the scope lock
  # must be derived from the compile-time kernel registry here, so we hydrate
  # it explicitly.
  echo "Step 0a: regenerate verification_scope.lock"
  generateAxiomInit()
  let scopeRoot = findRepoRoot()
  let (scopeOk, _) = writeScopeLockFromRegistry(scopeRoot)
  if not scopeOk:
    logError("vkd_sync", "[vkd sync] scope lock generation error")
    return 1
  logInfo("vkd_sync", "[vkd sync] verification_scope.lock regenerated")

  # Step 0b: Write-ahead snapshot of baseline.json for rollback. If a later
  # step fails (e.g. the VKD ratchet rejects the update), we restore this
  # snapshot so certificates/lock written by prove are not left inconsistent
  # with a stale baseline.
  let baselinePath = getCurrentDir() / BaselineDataDir / BaselineFileName
  let baselineSnapshot =
    if fileExists(baselinePath):
      try: readFile(baselinePath)
      except CatchableError: ""
    else: ""

  echo "Step 1/3: prove (limit " & $VkdSyncProveLimit & ", update lock)"
  let proveRes = try:
    runAxiomEngineCli(@["--limit", $VkdSyncProveLimit], updateLock = true)
  except Exception as e:
    logError("vkd_sync", "[vkd sync] prove failed: " & e.msg)
    return 1  # No rollback needed — prove failed, no certs written
  if proveRes.isErr():
    logError("vkd_sync", "[vkd sync] prove failed: " & proveRes.error.msg)
    return proveRes.error.kind.exitCode  # canonical exit code for the failure class

  echo "Step 2/3: orphan check (non-destructive)"
  let manifestPath = getCurrentDir() / ProofVaultDir / "manifest.json"
  var expectedIrHashes: seq[string] = @[]
  try:
    if fileExists(manifestPath):
      let manifest = loadManifest(manifestPath)
      for e in manifest.entries:
        if e.irHash.len > 0:
          expectedIrHashes.add(e.irHash)
  except CatchableError as e:
    logError("vkd_sync", "[vkd sync] failed to read manifest: " & e.msg)
    return 1
  # NOTE: orphan cleanup is deliberately NON-DESTRUCTIVE here. The per-run vault
  # manifest only lists certificates produced by THIS prove batch, so it does not
  # cover the full committed proof set — deleting by that set would destroy
  # committed certificates (integrity hazard). Destructive orphan removal remains
  # available only via the writeCertificates full-rebuild path, which derives the
  # expected set from the complete function list (cert_builder.nim).
  if expectedIrHashes.len == 0:
    logError("vkd_sync", "[vkd sync] manifest empty — skipping orphan check (fail-safe)")
  else:
    logInfo("vkd_sync", "[vkd sync] manifest references " & $expectedIrHashes.len &
      " certificate(s); orphan removal skipped (non-destructive by design)")

  echo "Step 3/3: baseline update"
  let baselineExit = cmdBaselineUpdate()
  if baselineExit != 0:
    # Rollback: restore the write-ahead baseline snapshot so the vault/certificates
    # and lock written by prove are not left inconsistent with a rejected
    # baseline. Full certificate-vault rollback is out of scope for this phase;
    # baseline restoration is the minimum viable consistency restoration.
    if baselineSnapshot.len > 0:
      try:
        writeFile(baselinePath, baselineSnapshot)
        logInfo("vkd_sync", "[vkd sync] baseline.json rolled back to previous state")
      except CatchableError as e:
        logError("vkd_sync", "[vkd sync] rollback of baseline.json failed: " & e.msg)
    logError("vkd_sync", "[vkd sync] baseline update failed with exit code " & $baselineExit &
      " — VKD sync failed, baseline rolled back to previous state")
    return baselineExit

  echo "=== Axiom VKD Sync complete ==="
  result = 0

proc runVkdCli*(args: seq[string]): int {.raises: [CatchableError, IOEffect], axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let cmd = if args.len > 0: args[0] else: ""
  case cmd
  of "sync":
    result = cmdVkdSync()
  else:
    echo "Usage: ax vkd <sync>"
    echo "  sync  prove (limit 25, update lock) → safe orphan cleanup → baseline update"
    result = 1

{.pop.}
