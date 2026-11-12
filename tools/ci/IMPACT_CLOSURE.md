# Impact Closure Selector (Shadow Mode)

> Phase P3 of the Deterministic Incremental Verification Engine work stream.
> Initial draft by the impact-closure selector; the governing contract is
> `docs/spec/incremental_ci_contract.md` (normative), the observed DAG is
> `docs/reports/ci_observed_dag_p1_2026-08-28.md`, and the avoidable-work
> analysis is `docs/reports/ci_avoidable_work_matrix_p1_2026-08-28.md`.

## What this tool does

`impact-closure` deterministically computes **which CI work units are affected**
by a git diff — and, by the contract's Reuse invariant, which units are
**provably reusable**. It runs in **shadow mode**: it never touches `.github/
workflows/ci.yml` (immutable, §-1) and never executes any gate. It only
writes a machine-readable shadow report describing what the closure would be.

The intent of the underlying work stream is to move CI from *recompute
everything on every change* to *recompute only the affected dependency
closure*. This tool is the deterministic *selector* half of that design; the
fingerprint/CAS and scheduled-execution halves are P4–P7.

## Build

Nim is pinned to 2.2.x (compile-time guard in the source).

```bash
nim c --hints:off --path:src -o:bin/impact-closure tools/ci/impact_closure_selector.nim
```

## Usage

```bash
bin/impact-closure --base <ref> --head <ref> [--output <path>] [--decision-out <path>]
```

- `--base <ref>` — base ref for `git diff <base>..<head>` (required).
- `--head <ref>` — head ref (default `HEAD`).
- `--output <path>` — JSON report path
  (default `docs/reports/impact_closure_shadow_<date>.json`).
- `--decision-out <path>` — A2 select-job decision envelope (JSON): deterministic
  projection of the verdict onto the `runner-pool-acceptance` 9-job surface
  (`mode`, `executableWorkUnits`, `shards`, `ciBootstrap`, `gatewayTestScope` —
  W2↔ci-bootstrap, W8↔gateway-shard, ADR-0017 A1.3). Consumed by the `select`
  job + `proof_reconcile_gate` (A3 skip-자체 검증). No timestamps — byte-identical
  output for identical (base, head, repo state) inputs, so
  `decisionHash = sha256(decision.json)` is reproducible.

Examples:

```bash
bin/impact-closure --base main --head HEAD
bin/impact-closure --base HEAD~1 --head HEAD
bin/impact-closure --base somecommit --head somecommit --output docs/reports/impact.json
bin/impact-closure --base main --head HEAD --decision-out decision.json --require-certain
```

## Core invariants (from `incremental_ci_contract.md` §4)

1. `affected(U, Δ) ≡ closure(Δ) ∩ inputClosure(U) ≠ ∅`
2. **Skip** is allowed only when `affected(U, Δ)` is provably false.
3. **Reuse**: `reusable(U) ≡ Fingerprint(U.inputs, contract, toolchain) ==
   CachedFingerprint`.
4. **Conservative over-approximation**: an unknown edge widens the affected
   set; under-approximation (missing a genuinely affected unit) is forbidden.

## Work unit catalog (W1–W11)

The work-unit catalog (ids, names, input path patterns, durations, tiers) is
defined **once** in `src/gate/proof_unit_catalog.nim` — the single editing
authority for the W-axis (cutover 2026-09-23). This document intentionally does
not duplicate the table. Durations/provenance mirror the sources described in
`docs/reports/ci_observed_dag_p1_2026-08-28.md` (§0 recap); the selector's
selector-side decoration (provenance, container flag, semantic-rule labels)
lives in `tools/ci/impact_closure_selector.nim` §2.

## Selection rules

1. **Direct path-pattern match** — a changed file matching a unit's
   `pathPatterns` selects that unit.
2. **Semantic dependency rules** — e.g. W3 depends on W2 output (`bin/ax`);
   `src/core/` changes exercise W4 invariants; `src/` changes propagate to W5,
   W8, W10 (coverage instrumentation).
3. **Core import-graph closure** — changed `src/core/` modules plus their
   transitive dependents (BFS over the reverse import graph) select any unit
   whose patterns match an affected module. This is the "semantic dependency
   unit, not file unit" core of the design.
4. **Conservative over-approximation** — `Makefile` (pervasive invocation)
   affects W1–W9; `src/generated/` affects all compilation-dependent units.
5. **Normative docs** — `docs/spec/` changes conservatively affect W4 and W7
   (contract gap G4: cache-key invalidation not yet wired).

## Document-role classification

Per the P1 avoidable-work matrix (§5), non-normative documentation is a
**known non-affected** edge and must select **0 units** — enforced by *not*
including a bare `docs/` catch-all in any unit's patterns; docs handling routes
solely through the explicit edges below (docs classification fix 2026-09-23):

- Non-normative (`docs/reports/`, `docs/audit/`, `docs/history/`) → **no**
  unit selected, 100% reusable.
- Normative (`docs/spec/`) → conservatively affects W4, W7 (G4).
- `docs/DEBT_REGISTRY.md` → affects **W1** (explicit edge; `make check-debt` →
  `bin/debt_engine --validate` reads it, `tools/debt_engine.nim` MarkdownPath).
- `docs/agents/**` → **conservative UNCERTAIN** (build input:
  `src/policy/embedded_agents_docs.nim` staticReads these at compile time).

## Output

Human-readable stdout summary plus a JSON report with:

- `base`, `head`, `changeFingerprint`
- `changedFiles` (path, status, blob hash)
- `selectedWorkUnits` (id, name, reason, duration, provenance, isContainer)
- `estimatedCostMinutes`, `fullPipelineCostMinutes`, `costSavingsMinutes`,
  `savingsPercent`
- `limitations`

`changeFingerprint` = `sha256` over the canonical `path + blobHash` lines of
the changed set, so identical semantic inputs yield identical fingerprints
(determinism: no timestamps in the body).

## Documented limitations (also printed in the report)

- `import_graph.nim` cannot be imported (checksums/sha2 dependency gap in this
  Nim 2.2.10 environment); the core transitive-dependency resolution is a
  direct reimplementation (build → reverse → BFS), core-only.
- Gate-target closure beyond `src/core/` is a known gap.
- `ci-lake-build` (W9) duration is UNKNOWN; excluded from cost sums.
- Normative-doc → cache-key invalidation (G4) is not yet wired; handled as a
  conservative over-approximation.
- `Makefile` pervasive-invocation over-approximation may over-claim W1–W9 for
  recipe-level changes.

## Verified behavior (shadow runs)

| Change set | Selected units | Affected cost | Notes |
|------------|----------------|---------------|-------|
| `docs/DEBT_REGISTRY.md` only | W1 | 16.0 m | explicit edge (debt engine reads it) |
| single `tests/gateway/*` test file | W1, W4, W7, W8 | 47.9 m | narrow closure |
| `src/core/*` (+clients, generated) | W1–W6, W8, W10, W11 | 73.7 m (≈full) | ~98% impact, matches P1 |
