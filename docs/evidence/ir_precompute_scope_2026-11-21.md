# VS-IR-PRECOMPUTE-SCOPE — fetch widening is not an execution budget (2026-11-21)

> Scope: equivalence and performance measurement of the change that limited the
> phase-10 IR precompute from handing the whole VKD ratchet pool to the executor
> down to the intersection with the requested keys (plus JRPC carriers), together
> with the re-observation after landing on canonical main.
> Recorder is not approver: the author is an agent, the approver is the user (wintrover).
> This document records measurements and observations only. The verdict contract
> itself is owned by `docs/spec/productization_contract.md`.
> **These numbers were measured on a local 16 CPU host; they are not CI Merge Queue SLO measurements.**

## Section 0. Landing history — measured ROT_ALLOWLIST abort and landing decomposition

The first single PR (#306, head `75769ad`) failed closed in its merge_group verdict
(run `44883641559`) with `mergeAborted / ROT_ALLOWLIST`. When the candidate delta
changes the trusted checker closure (ROTATION), **every** changed path must be inside
the allowlist (ADR-0025 A2), but `tests/unit/ir_precompute_scope_test.nim` (new) and
`data/debt_reduction_baseline.json` were outside it. To resolve this without touching
the trust surface (`src/cli/merge_cli.nim`), the change was decomposed as follows.

| Step | PR | Change | Path class |
|---|---|---|---|
| A | #316 | `data/debt_reduction_baseline.json` 4374 to 4381 (count-only) | outside closure, NORMAL |
| B | #306 (rebuilt) | 2 source files, generated metadata, baseline/arch hash, closure pin re-anchor | all inside allowlist, ROTATION |
| C | #320 | regression test and `TESTS_FAST_UNIT` registration (merge `48ea64f`) | outside closure, NORMAL |
| D | this document | evidence | outside closure, NORMAL |

## Section 1. Baseline and environment

| Item | Measured value | Command |
|---|---|---|
| main before the change | `f68ca0f` | `git log -1` |
| PR-A merge commit | `974f4af` (PR #316) | `gh pr view 316 --json mergeCommit` |
| PR-B merge commit | `4ea334d` (PR #306) | `gh pr view 306 --json mergeCommit` |
| PR-C merge commit | `48ea64f` (PR #320) | `gh pr view 320 --json mergeCommit` |
| Host | 16 CPU / 30 GiB / Linux 6.17.0-42-generic x86_64 | `nproc`, `free -g`, `uname -srm` |
| Nim | 2.2.10 | `nim --version` |
| Execution mode | release (default `make build`) | `bin/ax --version` |

## Section 2. Change inventory

| File | Change |
|---|---|
| `src/cli/axiom_engine.nim` | phase-10: leave the `selectProofCandidates` pool untouched and pass only the deterministic intersection with the requested node `(modulePath, functionName)` plus JRPC `errclassResultKey` (P1..P13) key set into `irCtx.entries`. The log records `pool/requests/required/executed` |
| `src/verification/batch_uap/loop_driver.nim` | pure `func scopeIrEntriesToRequiredKeys(entries, requiredKeys, cwd)` preserving pool order and accepting both raw and normalized key rules. The normalization rule is extracted into the pure `normalizeScopeModulePathAt(rawPath, cwd)` while the existing `normalizeScopeModulePath` remains an IO wrapper. `preComputedIrProvided` distinguishes "not provided (None)" from "provided and empty (Some(@[]))" |
| `tests/unit/ir_precompute_scope_test.nim` | 7 tests (order preservation, empty set, identity, absolute to normalized, external path fail-closed, raw matching, provided-empty wiring guard), landed in a follow-up PR |
| `data/nimtry_baseline.json` / `data/debt_reduction_baseline.json` | ratchet re-anchor at 4381 (main live equals main declaration equals 4381; net increase of this slice is zero) |
| `data/architecture_debt.json` | `bin/debt_engine --regen-arch` (2 entries) |
| `config/trusted_checker_closure.json` | `bin/reanchor_pin` (fourth new anchor) |

## Section 3. Equivalence (same tree, two binaries A/B)

Across 5 interleaved pairs (`normalizeMaxWorkers`, `safeSpeedupRatioCore`) the
following were **exactly identical**.

| Surface | Result |
|---|---|
| `nodeReports` (including verdict) | identical: normalize=verified and safe=failed on both sides |
| `metrics` | identical |
| `certificates` | identical |
| exit code | identical (0 / 1) |

`report --canonical-digest` was identical across 5 runs within each binary
(deterministic). Between the two binaries it differs, and the cause is limited to
`executionIdentity.verifierBuildId` (build identity rotation), timing fields, and
run-scoped execution accounting (`executionStats.eligibleTargets` 4 to 1, three
`unitEvidenceRefs` keys). This is because the volatile list in `canonical_projection.nim`
does not exclude execution accounting, and whether "a change of execution scope moves
the digest" is a separate decision matter (this slice does not decide it).

JRPC path: `tests/unit/test_jrpc_errclass_binding.nim` passes 55/55, confirming that
the P1..P13 carriers are not dropped by the intersection.

## Section 4. Performance

### 4.1 Pre-landing A/B (same working tree, 5 interleaved pairs, warm)

Command: `AXIOM_CI=1 <bin> prove --target <T>` (base is the release build of main
f68ca0f, new is the release build of the change branch). Raw data:
`build/tmp/vs-ir-scope/summary.txt` and each run's `.traj.jsonl`
(`ir-thread window completed`).

| Target | wall median (base to new) | IR window median (base to new) | exit |
|---|---|---|---|
| normalizeMaxWorkers | 5,153 to **2,802 ms** | 3,196 to **872 ms** | 0 / 0 |
| safeSpeedupRatioCore | 4,856 to **2,382 ms** | 3,028 to **524 ms** | 1 / 1 |

`topology scan` and `graph hydration` are unchanged (medians 478-526 and 170-174 ms).
The base log shows `IR extraction — 4/231 entries (limit=1)` while the new log shows
`pool=4/231 requests=1 required=1 executed=1 (limit=1)`.

### 4.2 Re-observation on main after landing (`4ea334d`)

Command: `make build` then `AXIOM_CI=1 bin/ax prove --target <T>`. Raw data:
`build/tmp/vs-ir-scope-accept/`.

| Item | Measured value |
|---|---|
| `make build` | exit 0, `Build successful` |
| `bin/ax --check-provenance` | `OK — embedded BuildSourceHash == live src tree (vs1-tree-hash/1:-6394464270943497635)` |
| normalizeMaxWorkers x4 | exit 0/0/0/0, wall 3,919 / 2,932 / 2,831 / 3,436 ms (first run cold) |
| normalize IR window x3 | 825 / 848 / 835 ms |
| safeSpeedupRatioCore x1 | exit 1 (unchanged), wall 2,526 ms, IR window 539 ms |
| phase-10 log | `pool=4/231 requests=1 required=1 executed=1 (limit=1)` |
| `report --canonical-digest` x2 | identical: `2656f65571a627aeb8523994d4e278447a46d7f15e7e3b07a47b7d6beba46330` |
| `report --json` | `nodeReports: 1` — `src/core/orchestrator/orchestrator_api.nim::normalizeMaxWorkers` gives `verified` |

The post-landing IR window on main is in the same band as the pre-landing A/B new
value (872/524 ms), a reduction of about 3.8x/5.6x against the base (3,196/3,028 ms).
Absolute wall values vary with host load (R8: performance is not a verdict input).

### 4.3 Re-observation after the full landing (`48ea64f`, PR-A/B/C all merged)

Command: `git switch main && make build` then
`AXIOM_CI=1 bin/ax prove --target normalizeMaxWorkers`. Raw data:
`build/tmp/vs-ir-scope-final/`.

| Item | Measured value |
|---|---|
| `make build` | exit 0, `Build successful`, wall 55,161 ms |
| `bin/ax --check-provenance` | `OK — embedded BuildSourceHash == live src tree (vs1-tree-hash/1:-6394464270943497635)` |
| regression test (main) | `nim c -r tests/unit/ir_precompute_scope_test.nim` gives 7/7 OK |
| normalizeMaxWorkers x4 | exit 0/0/0/0, wall 3,708 / 2,954 / 2,773 / 2,714 ms (first run cold) |
| IR window x4 | 1,145 / 902 / 833 / 840 ms |
| phase-10 log | `pool=4/231 requests=1 required=1 executed=1 (limit=1)` |
| `report --canonical-digest` x2 | identical: `fcf7a60ea07b6da6b8ca58f46619d14246545884973ca903d78e0e5fd0517e34` |
| `report --json` | `nodeReports: 1` — `src/core/orchestrator/orchestrator_api.nim::normalizeMaxWorkers` gives `verified`, `assuranceTier: dual-verified` |
| verifierBuildId | `95a4245fce46...` (a different generation from the `4ea334d` observation in 4.2) |

The digest differs from 4.2 (`2656f655...`) because #320 changed `Makefile`, which
rotated RecipeDigest into VerifierBuildId. **Within one identity the result is
deterministic** (2 of 2 identical) while the verdict surface (verdict/tier) is
unchanged: a measured example of "build identity rotation is not a change of verdict
meaning".

## Section 5. Limitations

- These measurements cover two workloads on a single local host; the VKD numerator
  and denominator are unchanged before and after.
- Because `executionStats`/`unitEvidenceRefs` are part of the canonical projection,
  an optimization that changes the execution scope moves `report --canonical-digest`.
  The verdict surface (verdict/tier/VKD) is unchanged.
- Ratchet cap 4381 is a **re-anchor of declaration onto measurement**, not a
  resolution of a violation (reduction is separate work).
- The JRPC carrier path is closed at the unit level (55/55); a real JRPC lane `prove`
  execution record is not part of this slice.

## Section 6. Meaning of the release switch (compiler and contract cross-check)

Whether the switch of the default build to release means "removal of checks" was
cross-checked against the pinned toolchain and the contract documents.

| Question | Evidence | Result |
|---|---|---|
| Does `-d:release` disable bounds/range/overflow/assert? | `compiler/commands.nim:525-537` (nim 2.2.10), `config/nim.cfg:86-94` | **No.** release only excludes `optStackTrace`/`optLineTrace`/`optLineDir` and enables `optOptimizeSpeed`. `optBoundsCheck`/`optRangeCheck`/`optOverflowCheck`/`optAssert` are **retained**. Their removal is exclusive to `-d:danger` (or `-d:quick`). |
| Which contract checks disappear in Axiom? | `src/core/contracts/spec_binding_macro.nim:107,115,180,188` | `requires`/`ensures` DbC is compiled out under `when not defined(release)`. The module docstring (:8) states "non-release builds only, production zero cost", so this is an intended **development diagnostic**. Verdicts come from the proof pipeline, not from this runtime DbC. |
| Is `except Defect` handling (8 sites) effective in release? | `config.nims:47-49` `switch("panics","on")` plus `lib/system/excpt.nim:487-491` | **No.** Under panics:on a Defect goes through `reportUnhandledError` and then `rawQuit(1)`, so `try/except` cannot catch it (all 8 sites, including `src/cli/main.nim:112`). |
| What is the exit code then? | probe: `nim c --panics:on` plus out-of-bounds gives `unhandled exception ... [IndexDefect]`, **exit 1**; `--panics:off` gives catch, exit 2 | Compared with the contract (`docs/spec/productization_contract.md`, v1 CLI Exit-State) where `1`=VERIFICATION_FAILURE and `2`=INTERNAL_ERROR, the crash is **misclassified as `1` (a fail-closed state)**. A false PASS cannot be produced, but the identification of the `internal-error` state is lost. The corresponding row in the contract document reads "139 (SIGSEGV), no CLI boundary handler", which is **inconsistent with the current code** (OPEN-ITEM). |

These items were not changed in this slice: `config.nims` and `main.nim` are trust
surface, and any modification rotates VerifierBuildId and RecipeDigest (authority and
invariant protocol, section 2.6).
