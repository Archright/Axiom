# Weekly Manual Gate Checklist

## Purpose

Quality-audit-gate and unified-sentry were originally `gsManual` gates. As of Phase E
(gate automation, 2026-06-16), both gates are promoted to `gsCI` stage. With the CI=0
cutover (2026-09-20) the remote CI pipeline is gone; both gates remain excluded from
local hooks (pre-commit/pre-push) and are run on demand via `ax gate run`.

## Current Schedule

| Gate | Stage | Scheduled Runs | Local Hook Runs | Manual Override |
|------|-------|----------------|-----------------|-----------------|
| `quality-audit-gate` | `gsCI, gsManual` | On demand (`ax gate run`) | ❌ No | `ax gate run quality-audit-gate` |
| `unified-sentry` | `gsCI, gsManual` | On demand (`ax gate run`) | ❌ No | `ax gate run unified-sentry` |

## Local/CI Separation Design (Phase E)

- **LOCAL hooks** (pre-commit, pre-push): Lightweight gates only — `nim check` on changed
  files, nimtry cache hit check, import encapsulation, procedure gate, etc.
- **Heavy gates**: Full nimtry scan, `quality-audit-gate`, `unified-sentry` — previously
  `gsCI` jobs in `.github/workflows/ci.yml` (retired with the CI=0 cutover, 2026-09-20).
  Run manually on the local machine; the cache/resources/environment requirement remains,
  so schedule them deliberately (`ax gate run …`).

## Manual Override

If you need to run these gates locally for debugging:

```bash
ax gate run quality-audit-gate
ax gate run unified-sentry
```

## Maintenance Rules

1. **SSOT**: `gate_list.nim` is the SSOT for gate stage scheduling. This file documents
   the local/CI separation rationale.
2. **Escalation**: Two consecutive gate FAILs → escalate to architect.
3. **Reversion**: To move gates back to `gsManual` only, remove `gsCI` from their stages
   in `gate_list.nim`.
