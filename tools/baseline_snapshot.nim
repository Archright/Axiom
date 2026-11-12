## tools/baseline_snapshot.nim
## Baseline Snapshot Tool — Captures the stable certificate vault state as an
## audit baseline (Phase 2 WS-4).
##
## The stable vault is `src/verification/certificates/*.json` (the real, committed
## certificate store). The output is the single SSOT file `data/baseline.json`.
##
## Build & Run:
##   export PATH="$HOME/.choosenim/toolchains/nim-2.2.10/bin:$HOME/.nimble/bin:$PATH"
##   nim c tools/baseline_snapshot.nim
##   ./tools/baseline_snapshot

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[strutils, os, tables]
import core/types/results
import core/proof/proof_integrity
import cli/shared/baseline_snapshot_core

proc runSnapshot() =
  echo "=== Axiom Baseline Snapshot ==="
  echo "Scanning stable vault: " & ProofVaultDir

  let lockPath = getCurrentDir() / BaselineDataDir / "verification_scope.lock"
  let scope = loadKernelScope(lockPath)
  let snap = computeBaselineSnapshot(ProofVaultDir, scope)

  let outPath = getCurrentDir() / BaselineDataDir / BaselineFileName
  let writeRes = writeBaseline(outPath, snap)
  if writeRes.isErr:
    echo "[ERROR] " & writeRes.error
    quit(1)

  echo "  Timestamp:         " & snap.timestamp
  echo "  Total Functions:   " & $snap.totalFunctions
  echo "  Verified Functions:" & $snap.verifiedFunctions
  echo "  VKD Fixed4:        " & snap.vkdFixed4
  echo "  VKD Score:         " & $snap.vkdScore
  echo "  Coverage Ratio:    " & $snap.coverageRatio
  echo "  Rigor Score:       " & formatFloat(snap.rigorScore, ffDecimal, 2)
  echo "  Soundness Mode:    " & snap.soundnessMode
  echo ""
  echo "  Tier Distribution:"
  for k, v in snap.tierDistribution.pairs:
    echo "    " & k & ": " & $v
  echo ""
  echo "  Top Modules:"
  for i, (name, count) in snap.topSourceModules:
    if i >= 5: break
    echo "    " & name & " (" & $count & " certs)"
  echo ""
  echo "Snapshot written to: " & outPath

when isMainModule:
  runSnapshot()
