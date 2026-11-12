# CI Finding: g7 verify-contract Cache-Order Fail-Closed Behavior

**Date:** 2026-09-05
**Status:** FINDING (documented, not fixed — pipeline/architect boundary)
**PR:** #40 (base=main f49ca3650, head=debt 1bf80235a)
**CI Run:** 33965731694 (rerun 33965731694 — identical result)

---

## Symptom

`verify-integration` fails at `verify-contract` group g7 (Makefile target `verify-contract-release-e2e`, line ~476). After `bin/ax prove --target normalizeMaxWorkers` succeeds, `bin/ax report --json` exits 1.

**Evidence:** CI run 33965731694 (and rerun 33965731694) — g7 RED.

---

## Root Cause Chain

1. **`src/verification/report_engine.nim:25` — `computeReportExitCode`** returns 0 only if `summary.verified > 0 AND summary.failed == 0`; else returns 1.
2. **Fresh verification state** on the runner (and locally) has `verified=0/40`, `failed=2` (safeSpeedupRatioCore + proximityScore — `IR pipeline FAIL status=psFail`).
3. The current kernel obligation profile yields `orchestrationNoObligation` for target `normalizeMaxWorkers`: `[Depth 1/1] Checking: orchestrator_api.nim::normalizeMaxWorkers... [NO_OBLIGATION]`. This means 2 units are inherently `psFail` with `verified=0` under fresh state.
4. **Main's CI (push run 33941865709 on f49ca3650) PASSED** verify-contract, but its log contains the **SAME** `IR pipeline FAIL: proximityScore` lines and its g7 shows `normalizeMaxWorkers ... [VERIFIED]` + `verified=1/40`. Main's run consumed a **cache-restored verified vault** (actions/cache + DEBT#457 frozen shared artifacts).

---

## Main-vs-PR Evidence

| Aspect | Main (f49ca3650) | PR (debt 1bf80235a) |
|---|---|---|
| Fresh-state `bin/ax prove --target normalizeMaxWorkers` | exits 1 | exits 0 (after `bin/hermetic_build` + `src/generated/build_env.nim` regeneration) |
| Fresh-state `bin/ax report --json` | exits 1 | exits 1 |
| CI g7 result | GREEN | RED |
| Reason for CI green | Cache-restored verified vault (actions/cache + DEBT#457 frozen artifacts) | No cache vault on fresh runner |

**Local A/B on main tree** (`/tmp/main-ab`, f49ca3650, fresh state): `bin/ax prove --target normalizeMaxWorkers` exits 1 and `bin/ax report --json` exits 1 — same failures as the PR.

---

## Determinism

CI rerun (`gh run rerun 33965731694`) failed identically — deterministic on the PR head without the cache vault.

---

## Boundary

This is a **pipeline/architect decision**, not a code bug in this branch.

- `src/gate/runners/import_encapsulation_gate.nim`, `.github/workflows/ci.yml`, `AGENTS.md`, and `config.nims` importEncapsulation block are **immutable** (§-1).
- `ci.yml` is untouched.
- Fix requires changing **verify-contract contract semantics** or the **obligation profile** — main pipeline/architect decision territory.

---

## Suggested Architect Options

| Option | Description | Tradeoffs |
|---|---|---|
| **A** | verify-contract g7 accept `no_obligation` target as pass-equivalent when `failed==0` | Widens pass criteria; may mask real failures; changes contract semantics |
| **B** | Seed the CI vault from a certified state so fresh runners inherit verified artifacts | Adds infrastructure dependency; stale-cert risk (DEBT#457); vault-order coupling remains |
| **C** | Make `computeReportExitCode` consider `no_obligation` as pass when `failed==0` | Changes exit-code contract; downstream consumers may rely on exit-1 for `verified==0`; requires spec change |

All options are pipeline-contract territory. No implementation is proposed here.
