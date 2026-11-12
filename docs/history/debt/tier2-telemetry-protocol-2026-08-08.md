# Tier-2 CI Telemetry Decision Protocol (2026-08-08)

**Status**: DEPLOY-VERIFICATION — active once the next CI run uploads `gate-telemetry`.

## Background

Tier-2 gates that had no alternate CI coverage are executed directly in
`verify-integration` (architect-approved decision ③, 2026-08-08):

- `proof-universe-lock-gate` (`nim c -r src/gate/runners/proof_universe_lock_gate.nim`)
- `verification-auditor-gate` (`nim c -r src/gate/runners/verification_auditor_gate.nim "$PWD" full 2`)
- `external-cli-smoke` (`nim c -r src/gate/runners/external_cli_smoke.nim`, added 2026-08-08)

Both heavy gates append canonical `gate_history.jsonl` records (`durationNs`)
via best-effort `appendGateHistory`. CI uploads `.axiom/gate_history.jsonl` as
the `gate-telemetry` artifact after the tier-2 step.

## Decision Rule (measured, data-driven — no arbitrary thresholds)

After a CI run, read the uploaded `gate_history.jsonl` records for
`proof-universe-lock` and `verification-auditor` and compute their **sum** of
`durationNs`:

```
Sum < 240s   → keep current single-step structure (300s hard cap retained).
Sum ≥ 240s   → split the two gates into independent CI steps for parallelism.
```

- The 300s `timeout-minutes: 5` hard cap remains the physical safety bound in
  both branches; GitHub Actions kills any step at 300s.
- Rationale for 240s (vs the earlier 180/270): it is the midpoint of the
  internal worst-case bound — proof-universe-lock is internally capped at
  `MaxTotalGateSec = 115`, verification-auditor at SLA 120s → worst sequential
  sum ≈ 235s. 240s sits just above the worst-case so no partitioning is needed
  unless measured time actually exceeds the internal bound (a signal worth
  surfacing).

## Evidence Needed

- `gate-telemetry` artifact from the next CI run (upload step:
  `.github/workflows/ci.yml` — "Upload gate telemetry").
- Parse: `gateId` in {"proof-universe-lock", "verification-auditor"}, sum
  `durationNs` → apply the rule above.
- If either gate has no record (e.g., empty main path), treat as an
  observability gap and report (do not fabricate a number).

## Follow-ups

- If Sum ≥ 240s: split `Run tier-2 gates` into per-gate steps in
  `.github/workflows/ci.yml` (architect-approved ci.yml edits are already
  sanctioned).
- Re-run CI after any change; thresholds are re-calibrated from fresh data only.
