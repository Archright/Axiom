import std/[json, os, unittest]
import ../../src/cli/shared/proof_hydration
import ../../src/cli/report_cli
import ../../src/cli/cli_types
import core/types/results

# Phase 3 — Canonical VKD determinism test.
#
# Single-canonical-wire contract:
#   1. getCanonicalVkdMetrics is deterministic — two calls on the same repo
#      state MUST return identical (verified, total, ratio).
#   2. The ONLY user-facing "vkd" field is `ax report --json` →
#      `metrics.vkd`, and it MUST equal the direct getCanonicalVkdMetrics
#      projection. No other output may carry a field named "vkd" that is
#      actually a different metric (summary.verifiedRatio is the renamed
#      legacy full-function success rate; summary.density_pct is DEBT#409 raw).
#
# The value is MEASURED, never asserted: this test compares two measured
# projections against each other, not against a hardcoded number.
#
# Report input: since #936 the canonical reader is journal-driven and never
# reads the L1 cache (logs/ax_proof_state.json), and the write-back that used
# to recreate a summary-only cache is gone. `ax report` is fail-closed on a
# missing proof-state document, so this test supplies one through the
# supported `--state-file` argument as a temp fixture — the repository's
# logs/ directory is never written to or deleted.

proc repoRoot(): string =
  ## Resolves the repository root at runtime (tests execute from the project root).
  getCurrentDir()

proc writeTempReportState(): string =
  ## Minimal proof-state document loadReportProofState accepts: any parseable
  ## JSON object loads (identity re-validation demotes, never rejects). The
  ## fixture carries "summary" so the projected report document contains the
  ## summary section the label-invariant assertion inspects.
  let dir = getTempDir() / ("axiom_vkd_determinism_" & $getCurrentProcessId())
  createDir(dir)
  result = dir / "ax_report_state.json"
  writeFile(result, "{\"summary\": {}}\n")

proc cleanupTempReportState(statePath: string) =
  try:
    removeFile(statePath)
    removeDir(parentDir(statePath))
  except CatchableError:
    discard  # axiom:best-effort(temp fixture cleanup)

suite "Canonical VKD determinism (Phase 3 single-wire)":
  test "getCanonicalVkdMetrics is deterministic across two calls":
    let a = getCanonicalVkdMetrics(repoRoot())
    let b = getCanonicalVkdMetrics(repoRoot())
    check a.verifiedCount == b.verifiedCount
    check a.totalCount == b.totalCount
    check a.failed == b.failed
    # Ratio is derived from the same counts, so it too must be identical.
    let ra = if a.totalCount > 0: a.verifiedCount.float / a.totalCount.float else: 0.0
    let rb = if b.totalCount > 0: b.verifiedCount.float / b.totalCount.float else: 0.0
    check ra == rb

  test "ax report --json metrics.vkd equals direct getCanonicalVkdMetrics projection":
    # The L1 cache is NOT VKD authority: the canonical reader is journal-driven
    # (TrustCommit journal + verification_scope.lock) and never reads
    # logs/ax_proof_state.json, so there is no cache path to clear — the old
    # "delete the cache to force the vault-scan path" premise died with the
    # #936 write-back. What the report does require is its proof-state
    # document as a separate input (loadReportProofState is fail-closed on a
    # missing file); it is supplied via the supported --state-file argument.
    let statePath = writeTempReportState()
    defer: cleanupTempReportState(statePath)

    let direct = getCanonicalVkdMetrics(repoRoot(), forceHydration = true)
    let directRatio = if direct.totalCount > 0:
        direct.verifiedCount.float / direct.totalCount.float else: 0.0

    let reportRes = runReportCli(@["--json", "--state-file", statePath])
    check reportRes.isOk()
    let result = reportRes.get()
    let reportJson = parseJson(result.outputJson)

    # The single canonical VKD exposure lives under metrics.vkd.
    check reportJson.hasKey("metrics")
    check reportJson{"metrics"}.kind == JObject
    check reportJson{"metrics"}.hasKey("vkd")
    let metricsVkd = reportJson{"metrics"}{"vkd"}
    check metricsVkd.kind == JObject
    check metricsVkd.hasKey("verified")
    check metricsVkd.hasKey("total")
    check metricsVkd.hasKey("ratio")

    check metricsVkd{"verified"}.getInt() == direct.verifiedCount
    check metricsVkd{"total"}.getInt() == direct.totalCount
    check metricsVkd{"ratio"}.getFloat() == directRatio

  test "ax report --json does NOT expose a different metric under the name vkd":
    # Label-cleanup invariant: summary.vkd was renamed to verifiedRatio.
    # The summary object must not carry a "vkd" key (that name is reserved
    # for the canonical metrics.vkd projection only).
    let statePath = writeTempReportState()
    defer: cleanupTempReportState(statePath)

    let reportRes = runReportCli(@["--json", "--state-file", statePath])
    check reportRes.isOk()
    let reportJson = parseJson(reportRes.get().outputJson)
    let summary = reportJson{"summary"}
    # The fixture guarantees a summary section and the report projects the
    # state document verbatim (injecting schemaVersion/metrics only), so the
    # invariant holds unconditionally.
    check summary.kind == JObject
    check not summary.hasKey("vkd")
