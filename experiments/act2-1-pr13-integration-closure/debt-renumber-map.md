# DEBT Renumber Map — Act 2.1 Integration Closure

Scope: `feat/act2-external-verification` rebased onto `origin/main` (`f217b225c`).
Purpose: document the DEBT namespace canonicalization performed in Phase 3 of the
integration closure, so that every renumbered branch entry records its original
identity, title, registration commit, and the deviation rationale.

## 1. Why renumbering was necessary

After rebasing the Act 2 branch onto `origin/main`, the union `debt_registry.json`
contained collisions:

- `main` introduced `DEBT#436 … #439` (four new entries, all from Track B / debt-governance work).
- the Act 2 branch independently introduced `DEBT#436 … #439` (four entries from WP4-g.2),
  colliding with the main set at the same numeric IDs.

Both sets had distinct titles, distinct semantics, and distinct registration commits.
The union could not assign both to the same numeric ID — that would violate the
hard invariant **"each DEBT#NNN has exactly one meaning"** and the no-duplicate-ID rule.

## 2. Decision

- **`main` #436–#439 remain immutable** (Track B provenance, main-owned).
- **branch-only #440–#444 remain unchanged** (WP-4g / external-proof-path debt, no collision).
- **the four colliding branch entries (#436–#439) were renumbered to #445–#448.**

Final namespace: continuous `DEBT#436 … #448`, `nextDebtNum = 449`, duplicate IDs = 0.

This preserves every entry's semantics and provenance (nothing was merged, dropped, or
deduplicated); only the four colliding branch entries changed their numeric identity.

## 3. Division of ownership

- `main` #436–#439: immutable main-owned Track B entries. Do NOT remap; they are the
  conflict base that was already on `origin/main`.
- branch #440–#444: Act 2 branch-owned, unchanged.
- branch #436–#439 → #445–#448: Act 2 branch-owned, renumbered to resolve the collision.

## 4. Mapping table

| Original (branch) | New        | Status    | Title                                                             | Registered by (pre-rebase / rebased commit) |
|-------------------|------------|-----------|-------------------------------------------------------------------|---------------------------------------------|
| DEBT#436          | **DEBT#445** | open      | Historical tcVerifiedProof records are provenance-unqualified      | `ec0bc0549` / `d690f285f` (WP3-wp4f)         |
| DEBT#437          | **DEBT#446** | open      | stale_cert_gate sourceHash-only limitation                        | `cfdc76cab` / `a603014cc` (WP4-g.2)          |
| DEBT#438          | **DEBT#447** | open      | certificate producer/consumer contract divergence                 | `cfdc76cab` / `a603014cc` (WP4-g.2)          |
| DEBT#439          | **DEBT#448** | open      | journal write-time reverse index for buildClaimBuckets            | `cfdc76cab` / `a603014cc` (WP4-g.2)          |

`DEBT#445..#448` titles above are the current registry titles. Registration origins were
established with `git log -S "<title fragment>" -- data/debt_registry.json`:
`#445` first appeared in the WP3-wp4f commit (`ec0bc0549`, rebased as `d690f285f`);
`#446..#448` first appeared in the WP4-g.2 commit (`cfdc76cab`, rebased as `a603014cc`).
The pre-rebase commits are the original authors; the rebased successors carry identical
content under new hashes.

## 5. References updated

Branch-origin references to the renumbered entries (their numeric ID changed) were
updated **only where the reference unambiguously points at a branch entry**, where
ownership was established by commit ancestry (`git merge-base --is-ancestor`):

- `docs/adr/0017-trust-claim-authority.md` — created in branch commit `d690f285f`;
  its `DEBT#436` is `Trust / Evidence` (the Historical tcVerifiedProof debt)
  → remapped to `DEBT#445`.
- `docs/spec/trust_revalidation_protocol.md` — created in branch commit `d690f285f`;
  its "DEBT#436 … debt_registry_open 17→18" references describe the WP3-c
  historical-trust debt → remapped to `DEBT#445`.
- `experiments/act2-wp3c-historical-trust-debt/` (branch experiment) — every `DEBT#436`
  reference describes the `Trust / Evidence` tcVerifiedProof population → remapped to `DEBT#445`.

**Deliberately NOT remapped** (main-origin references to the now-different main `#436..#439`,
verified by ancestry + semantics):

- `docs/spec/debt_projection_contract.md` — committed on `main` (`7431f9cf5`); its
  `DEBT#436` = "Dependency File Drift / CI Test-Swallow Fail-Open" = main `#436`, and
  `DEBT#437` = "Dedicated Mutation Path" = main `#437`. Both must keep their IDs.
- `docs/spec/cert_lifecycle_contracts.md` — contains **no** `DEBT#436..#439` reference.
- `docs/DEBT_REGISTRY.md` — derived by `debt_engine --codegen`; already reflects the
  cutover (main #436–#439 + branch #445–#448). No manual edit.
- `docs/spec/debt_projection_contract.md` references are excluded from this change set.

`main`-origin references to `DEBT#436..#439` were left **untouched** (they are
immutable main entries and must keep their IDs).

## 6. Invariants preserved

- Single meaning per `DEBT#NNN`: ✅ (main #436–#439 and branch #445–#448 are distinct).
- No duplicate IDs: ✅ (178 entries, dup NONE, `sorted=True`).
- `main` entries immutable: ✅.
- Every entry preserved (nothing dropped): ✅.
- Continuous namespace, no gap in the Act 2 band: ✅ `#436..#448`.
- Mapping documented (this file): ✅.

## 7. Deviation from plan text

The integration plan stated the literal mapping "branch #436→440, #437→441, #438→442,
#439→443" while also instructing "#440~444 keep". That was internally contradictory,
because the destination IDs `#440..#443` were already occupied by existing branch entries.
The plan's hard invariants (single meaning / no dup / main immutable / preserve all /
mapping document) are fully satisfied; only the literal numeric destinations were
adjusted to `#445..#448`. This file records that deviation.
