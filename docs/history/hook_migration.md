# Hook Migration Log: Bash → Nim

> **Migration Plan**: `docs/spec/hooks_architecture.md`
> **Plan Source**: [dove-raven-wolverine.md](../../.kimi-code/plans/dove-raven-wolverine.md)
> **Started**: 2026-06-17

---

## §1. Strategic Summary

Migrate all validation logic from Bash (`.githooks/pre-commit`, `.githooks/pre-push`) to compiled Nim gates (`src/gate/runners/*_gate.nim`), orchestrated by `bin/gate_hook` via `gate_list.nim` (SSOT).

**Approach**: B-via-A — incremental migration with parity verification at each phase. Bash hooks are thinned incrementally; each Bash phase is deleted only after the Nim equivalent is proven equivalent via the parity harness.

**Final State**: `.githooks/pre-commit` and `.githooks/pre-push` are pure dispatchers containing zero validation logic.

---

## §2. Phase Checklist

### Phase 1 — Foundation & Safety (no Bash deletion yet)

| # | Task | Owner | Status |
|---|------|-------|--------|
| 1.1 | Rewrite `.githooks/pre-push` to invoke `bin/gate_hook pre-push` instead of `nim c -r` | Subagent A | ✅ Done (alternative path; hooks dispatch directly to compiled gate binaries via bin/gate_hook, not via wrapper) |
| 1.2 | Add binary-freshness guard in Bash shim (rebuild only if source newer) | Subagent A | ✅ Done (partial; build-if-missing guard present, timestamp freshness delegated to Nim binary_freshness_gate) |
| 1.3 | Add bypass audit logging to `logs/bypass_audit.jsonl` for pre-push | Subagent A | ✅ Done |
| 1.4 | Extend `binary_freshness_gate.nim` to verify `bin/gate_hook` | Subagent A | ✅ Done |
| 1.5 | Update stale `.git/hooks/` comments in `orchestrator_hook.nim` → `.githooks/` | Subagent A | ✅ Done |
| 1.6 | Create `tests/hooks/parity_harness.nim` (ephemeral scaffold) | Subagent C | ⬜ Deferred |
| 1.7 | Delete `src/gate/runners/unified_sentry.nim` + clean references | Subagent C | ✅ Done |
| 1.8 | Mark/delete `@legacy` feature files (unified_sentry, gate_memoization, gate_runner) | Subagent C | ✅ Done |
| 1.9 | Create `docs/spec/hooks_architecture.md` | Subagent D | ✅ Done |
| 1.10 | Create `docs/history/hook_migration.md` (this file) | Subagent D | ✅ Done |
| 1.11 | Verify `bin/setup-hooks --verify` passes with new layout | Subagent D | ✅ Done (ported to Pure Nim; no --verify flag — config verified via git config core.hooksPath) |

**Phase 1 → Phase 2 Gate Criteria:**
- [x] `nim c --hints:off src/gate/runners/gate_hook.nim` compiles successfully
- [x] `bin/gate_hook pre-push` dry-run exits 0
- [ ] Pre-push shim overhead ≤ 1s / Pre-commit shim overhead ≤ 200ms (paired — not measured, TBD)
- [x] `binary-freshness-gate` passes for `bin/gate_hook`
- [x] `unified_sentry.nim` deleted; no references remain in `src/`, `bin/`, `tests/`, `docs/`
- [ ] Parity harness compiles and runs baseline scenarios
<!-- ~~- [ ] `bin/setup-hooks --verify` passes~~ (flag does not exist; setup-hooks is Pure Nim — config verified via git config core.hooksPath) -->

---

### Phase 2 — Port Low-Risk Gates (Bash still present as backup)

| # | Task | Owner | Status |
|---|------|-------|--------|
| 2.1 | Implement `language-ban-gate` (staged file extension allowlist) | Subagent B | ⬜ Not Started |
| 2.2 | Implement `binary-artifact-gate` (ELF/PE/Mach-O magic bytes + zero-byte + LFS pointer) | Subagent B | ⬜ Not Started |
| 2.3 | Implement `core-invariant-gate` (I/O primitive scan for `src/core/`) | Subagent B | ⬜ Not Started |
| 2.4 | Implement `forwarding-stub-cycle-gate` (circular dependency detection) | Subagent B | ⬜ Not Started |
| 2.5 | Implement `cast-nosideeffect-doc-gate` (annotation enforcement) | Subagent B | ⬜ Not Started |
| 2.6 | Reconfigure existing ratchet gates for `gsPreCommit`/`gsPrePush` | Subagent B | ⬜ Not Started |
| 2.7 | Extend parity harness for each new gate scenario | Subagent C | ⬜ Not Started |
| 2.8 | Update docs per gate | Subagent D | ⬜ Not Started |

**Phase 2 → Phase 3 Gate Criteria:**
- [ ] All new gates registered in `gate_list.nim`
- [ ] Parity harness passes for every migrated phase across test matrix
- [ ] Double-execution latency ≤ baseline + 20%
- [ ] At least one real pre-commit/pre-push with Bash phase disabled succeeds

---

### Phase 3 — Deprecate Bash Phases

| # | Task | Owner | Status |
|---|------|-------|--------|
| 3.1 | Delete migrated Bash phases from `.githooks/pre-commit` one-by-one | Subagent A | ⬜ Not Started |
| 3.2 | Finalize all gate registrations in `gate_list.nim` | Subagent B | ⬜ Not Started |
| 3.3 | Parity sign-off for all phases | Subagent C | ⬜ Not Started |
| 3.4 | Update `.githooks/pre-commit` to minimal fast-fail shim | Subagent A | ⬜ Not Started |

**Phase 3 → Phase 4 Gate Criteria:**
- [ ] `.githooks/pre-commit` contains ≤ 30 lines (bypass + freshness + exec only)
- [ ] All gates pass in Nim-only mode for 5+ consecutive pushes
- [ ] No validation logic remains in any `.githooks/*.sh`

---

### Phase 4 — Full Nim Port & Cleanup

| # | Task | Owner | Status |
|---|------|-------|--------|
| 4.1 | Replace `.githooks/pre-commit` and `.githooks/pre-push` with symlinks or minimal wrappers | Subagent A+D | ⬜ Not Started |
| 4.2 | Update `bin/setup-hooks` for direct binary installation | Subagent D | ✅ Done (binary port complete; setup-hooks is now Pure Nim — no --verify flag) |
| 4.3 | Add compile-time assertion: no `.githooks/*.sh` contains validation logic | Subagent B | ⬜ Not Started |
| 4.4 | **Delete `tests/hooks/parity_harness.nim`** | Subagent C | ⬜ Not Started |
| 4.5 | Final architecture documentation update | Subagent D | ⬜ Not Started |
| 4.6 | All pre-push/pre-commit gates pass in final state | All | ⬜ Not Started |

**Final Acceptance Criteria:**
- [ ] `.githooks/pre-commit` and `.githooks/pre-push` contain zero validation logic
- [ ] `gate_list.nim` is the sole SSOT for gate configuration
- [ ] `tests/hooks/parity_harness.nim` deleted
<!-- ~~- [ ] `bin/setup-hooks --verify` passes~~ (flag does not exist; setup-hooks is Pure Nim — config verified via git config core.hooksPath) -->
- [ ] All gates pass on a clean workspace

---

## §3. Ephemeral Parity Harness

`tests/hooks/parity_harness.nim` is a **temporary safety scaffold** created in Phase 1 and deleted in Phase 4.

**Purpose**: Run synthetic commits through both the Bash hook path and the Nim gate path, comparing exit codes and stderr signatures to prove behavioral equivalence before deleting any Bash phase.

**Lifecycle**:
- **Created**: Phase 1 (Subagent C)
- **Expanded**: Phase 2 (one scenario per migrated gate)
- **Destroyed**: Phase 4 — tracked by this checklist item

> ⚠️ **DESTRUCTION TRIGGER**: When Phase 4 begins, `tests/hooks/parity_harness.nim` MUST be deleted. It is not product code; it is migration scaffolding.

---

## §4. Performance Baseline (To Be Recorded in Phase 1)

| Metric | Target | Actual | Date |
|--------|--------|--------|------|
| Pre-push shim overhead | ≤ 1s | TBD | — |
| Pre-commit shim overhead | ≤ 200ms | TBD | — |
| `bin/gate_hook` cold compile time | N/A | TBD | — |
| `bin/gate_hook` pre-push total wall time | baseline | TBD | — |
| Parity harness baseline run time | N/A | TBD | — |

---

## §5. Risk Register

| Risk | Mitigation | Status |
|------|------------|--------|
| Double-execution slows pre-commit in Phase 2 | Limit Phase 2 duration; port highest-overlap gates first | Open |
| New Nim gate misses edge case | Parity harness covers binary, zero-byte, invalid extension, circular stub | Open |
| `bin/gate_hook` stale | Freshness guard in shim + `binary-freshness-gate` at pre-push | Open |
| Legacy tests break | `@legacy` tests marked `@skip` or deleted | In Progress |
| Hook path confusion | Keep `core.hooksPath=.githooks` until Phase 4 | Open |

---

## §6. Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-06-17 | B-via-A strategy adopted | Incremental migration with parity verification preserves commit/push safety |
| 2026-06-17 | Ephemeral parity harness approach | Temporary scaffolding is idiomatic in Git workflows; defined destruction trigger prevents stale code |
| 2026-06-17 | Bash shim retained as dispatcher | Minimal overhead; allows binary-freshness check without Nim dependency on hot path |
| 2026-06-17 | `unified_sentry.nim` deletion approved | Dead code not part of migration path; removing reduces confusion |
