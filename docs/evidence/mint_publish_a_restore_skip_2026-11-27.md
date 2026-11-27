# mint-publish A-layer restore skip — change record (2026-11-27)

> **Status**: change record for a measure-and-narrow change, written before landing.
> **Created**: 2026-11-27
> **Branch**: `perf/mint-publish-skip-a-restore-2026-11-27`
> **Baseline observed**: merge_group run 45940366569 at `a6805fc4`
> **Writer != approver**: the author is an agent; landing is approved on GitHub by the
> native MERGE commit. Nothing here claims a post-landing measurement it does not have.

## §0. Scope of this record

This document records one change to the merge_group admission chain: the `mint-publish`
job restores the full A-layer (native toolchain) cache although it never executes that
toolchain. It records the baseline observation, the rejected alternatives, the adopted
mechanism, and the expected cost. The saving is a **projection** from the baseline's own
per-step timings, not a measurement of the landed change; §5 states the procedure that
turns it into a measurement.

## §1. Baseline (run 45940366569, `a6805fc4`)

| Stage | Wall | Note |
|---|---|---|
| `attest/admission-check` | 65 s | `setup-axiom-toolchain` 31 s |
| `mint-prepare` | 20 s | toolchain at `runtime` scope, 6 s |
| `mint-publish` | 69 s | B-supply restore at `full` scope 42 s; ledger appends 15 s |
| `admission-check` | 5 s | |

Provisioning is 79 s of the 159 s merge_group wall. Inside `mint-publish`, the A-layer
restore is the largest single item at 34.4 s of 69 s (payload ~1084 MB, exact-hit rate
~1/20).

## §2. Rejected alternatives

| Candidate | Rejected because |
|---|---|
| (a) reuse `provision-scope: runtime` for `mint-publish` | `a_prefix` is split by scope (`action.yml:258-263`), `a_fp = sha256(a_key)[:32]` (`:372`), `b_key = axiom-b-{identity}-{recipe}{a_fp}` (`:373`). A scope change rotates `a_fp`, so `b_key` changes and every B restore becomes a structural MISS -> (P3) cold build -> no nim -> failure. Already documented at `certificate-mint.yml:1334-1339`. |
| (b) unserialize `mint-prepare` | It downloads a witness artifact produced by attest (`admission-gate-v2.yml:531` `needs: [attest, anchor-resolve]`). A real data dependency, not a scheduling artifact. |
| (c) poll/sleep on the happy path | Adds wall without removing work, and turns a graph dependency into a timing assumption. |

## §3. Adopted mechanism

A new caller input `skip-a-restore` (default `'false'`) on
`.github/actions/setup-axiom-toolchain/action.yml`, set to `'true'` at the single
`mint-publish` call site (`certificate-mint.yml:1343`). `provision-scope` stays `'full'`
so the B key namespace is unchanged (candidate (a)).

The input gates **the whole A-layer reaction chain**, not only the restore:

- `A-layer restore`, `A-layer restore observation`, `A-layer non-exact discard`;
- `Toolchain functional probes` (`a-probe`);
- `Install Nim`, `Install project Nim dependencies`, `Install Lean`;
- `A-layer save authority`, `A-layer save`.

Gating the restore alone would be a regression, not an optimization: a skipped restore
leaves `a-restore.cache-hit` empty, and the fail-closed chain reads `'' != 'true'` as
"no exact hit", so every installer and probe would run and `Verify toolchain pins` would
then fail on the absent toolchain. The restoration was chosen over the literal
"gate the restore step only" because the latter turns 69 s into minutes and reddens the
job.

The native installers are suppressed only behind a **verified B supply**: exact B hit
plus `b-verify-ok` plus a new `b-probe-ok` output that the semantic provenance probe sets
to `true` only when the payload survived (`false` on discard, `false` when the probe tree
is not a 40-hex OID and the probe therefore SKIPs - unprobed is not verified). Anything
less keeps the installers running, because the (P3) cold-build fallback
(`certificate-mint.yml:1787`, `make -f ci/checker.mk ci-compile-ax`) needs nim.

Deliberately **not** gated (the always-provisioned supply, ~1-2 s): `Install Z3 4.13.3`,
`Install jq 1.7.1`, `Export toolchain PATH`. `Verify toolchain pins` therefore still
asserts z3 4.13.3 and jq 1.7.1 on the skip path, and relaxes only the nim/lean assertions,
under exactly the conjunct that suppresses the installers.

`AXIOM_CACHE_B_RESTORE: exact-hit=true` and the B restore/verify conditions are
unchanged. The keygen step is untouched.

## §4. Cost: one expected cold cycle

`script_hash` (`action.yml:253`) hashes `action.yml` itself, so landing this change
rotates every A-layer and B-layer key exactly once. `a-key`, `a_fp` and therefore `b-key`
change bytes at landing; the key **formula** does not change, and `skip-a-restore` never
enters a key. The first merge_group after landing is cold on both layers until
`ci-cache-publisher` reseeds. This is expected, bounded, and already documented in the
action header.

Projected effect (from the baseline's per-step timings, not measured):

| Item | Before | After (projected) |
|---|---|---|
| `mint-publish` | 69.52 s | ~41 s |
| A-layer exact-hit rate | 1/22 | 1/20 |

## §5. How to verify after landing

1. First `mint-publish` log after the cold cycle: `AXIOM_CACHE_B_RESTORE: exact-hit=true`
   and `AXIOM_CACHE_A_PINS: skip-a-restore` present, with no `Install Nim` /
   `Install Lean 4.33.0` step in the run.
2. `mint-publish` wall in the admission budget observation: expect ~41 s against the
   69.52 s baseline.
3. On any run where the B supply is absent or discarded, the log must show the native
   installers running and `(P3)` cold build succeeding - that is the fail-closed branch,
   and it is the one that must not be traded away for the saving.
4. 3-way trust equality unchanged (this change does not touch `admission-check.yml`):
   `config/policy/epoch_manifest.json:28 productionExecutionPin` =
   `config/trusted_writer_set.json:41 trustedAdmissionWorkflowSha` =
   `git hash-object .github/workflows/admission-check.yml` = `433be3c3`.

## §6. G2b declaration

- Engine change: `certificate-mint.yml` (non-pinned engine; path 2 implemented-scope
  repair) plus the shared action `setup-axiom-toolchain/action.yml`.
- Epoch definition untouched: no change to `epoch_manifest.json`.
- TWS / `productionExecutionPin` unchanged: `433be3c3` (see §5.4).
- Scope-gate surface non-decreasing: no `scope_*` condition and no `[slice-engine]` step
  is removed or weakened. The A-layer gates this change adds are cache-provisioning
  conditions, not slice-scope gates.
- Pin rotation: `admission-gate-v2.yml` `workflow_call` refs for `certificate-mint.yml`
  (lines 558 and 615) move to the commit that carries the `certificate-mint.yml` change.