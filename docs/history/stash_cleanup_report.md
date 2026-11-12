# Stash Cleanup Report

**Date**: 2026-06-17
**Agent**: Subagent — Stash Cleanup
**Worktrees**: `Axiom` (main) and `Axiom-core` (core) — shared stash pool

---

## Summary

| Metric | Value |
|--------|-------|
| Initial count | 18 |
| Dropped | 9 |
| Kept | 9 |
| Blockers | 0 |

---

## Drops (9 stashes)

All drops were verified by inspecting `git stash show -p` output and confirming changes are superseded by HEAD.

### Phase 1 — Superseded nimtry ratchet stashes

| Original Index | New Index (after renames) | Message | Reason |
|--------|---------|---------|--------|
| `{9}` | dropped | WIP on core: 72679723 chore(nimtry): ratchet 713 | Only adds bypass_audit.jsonl entry; superseded by later ratchets |
| `{8}` | dropped | WIP on core: e06de202 chore(nimtry): ratchet 57 | Only adds bypass_audit.jsonl entries; superseded by v2 baseline |
| `{7}` | dropped | WIP on core: dca6cf94 chore(nimtry): ratchet 705 | Only adds bypass_audit.jsonl entries; superseded by v2 baseline |
| `{5}` | dropped | WIP on core: 84097e60 fix(nimtry): deduplicate file paths | `src/core/persona_interface.nim` deletion + import path changes — HEAD already uses `core/domains/persona_interface`; file already deleted |

**Commands used**:
```
git stash drop stash@{9}
git stash drop stash@{8}
git stash drop stash@{7}
git stash drop stash@{5}
```

### Phase 2 — Duplicate

| Original Index | Message | Reason |
|--------|---------|--------|
| `{16}` | On core: LFS PDF fix | Identical to stash@{15}; duplicate of PDF→LFS-pointer conversion |

**Command used**: `git stash drop stash@{16}`

### Phase 3 — Verified superseded by HEAD

| Original Index | New Index (after renames) | Message | Reason |
|--------|---------|---------|--------|
| `{17}` | dropped | On core: pre-cleanup | Import path normalization (`core/json_utils` → `core/json/json_utils`) — verified HEAD already has `core/json/json_utils` in all affected files |
| `{10}` | dropped | On core: dirty-report | `proc_to_func_report` update — HEAD has newer version committed in `d4707bb0` |
| `{11}` | dropped | WIP on main: 0a1cd270 fix | `proc_to_func_report` + small test fix — HEAD already has newer report; test imports at `core/domains/persona_interface` |
| `{13}` | dropped | On core: pre-sync stash | `proc_to_func_report` update + test import fixes (`core/types/persona_interface` → `core/persona_interface`) — HEAD already uses `core/domains/persona_interface` |

**Commands used**:
```
git stash drop stash@{17}
git stash drop stash@{16}
git stash drop stash@{13}
git stash drop stash@{11}
git stash drop stash@{10}
```

---

## Kept (9 stashes)

| New Index | Original Index | Message | Reason to Keep |
|-----------|----------------|---------|----------------|
| `{0}` | `{0}` | On main: pre-sync-cleanup-main | CLI rename `bin/ax` → `bin/axiom` across 64 files — significant unapplied work; may conflict but valuable |
| `{1}` | `{1}` | On core: pre-rebase stash | `axiom_api_session_helpers.nim` refactor — `??` chains to explicit `isErr`/`get` pattern |
| `{2}` | `{2}` | WIP on main: d674a27b feat(gate) | Gate enforcement work — `topology_cli.nim`, `wf_semantic.nim`, `legislator.nim` |
| `{3}` | `{3}` | WIP on main: 6c65980d feat: OCP macro | OCP macro registry + CEGAR combinator decomposition — 11 files |
| `{4}` | `{4}` | On main: sync-branch auto-stash | Contains `payload_bridge.nim` string→JsonNode refactor (needed for integration daemon plan) + `topology.lock` + `symbolic_types_*` rewrites |
| `{5}` | `{6}` | WIP on main: 70a4a202 feat(tools) | `persona_interface.nim` move to `domains/`, `domain_layout.json`, `gate_list.nim` |
| `{6}` | `{12}` | WIP on main: 2046d8c5 refactor(contract) | `pipeline_dispatch.nim` major refactor + `proc_to_func_report` |
| `{7}` | `{14}` | WIP on main: 9497894c fix(hygiene) | Massive PBT regeneration — 194 files + new `all_pbt_manifest.nim` |
| `{8}` | `{15}` | On core: PDF LFS workaround | PDF→LFS-pointer conversion — needs LFS migration first |

---

## Verification

```bash
$ git stash list  # 9 stashes remain
stash@{0}: On main: pre-sync-cleanup-main
stash@{1}: On core: pre-rebase stash
stash@{2}: WIP on main: d674a27b feat(gate): enforce Language Ban via .gitignore allowlist + pre-commit Phase 0.7
stash@{3}: WIP on main: 6c65980d feat: OCP macro registry, Result parse guard, CEGAR combinator decomposition
stash@{4}: On main: sync-branch auto-stash
stash@{5}: WIP on main: 70a4a202 feat(tools): upgrade feature_runner_compiler with observable assertion generator
stash@{6}: WIP on main: 2046d8c5 refactor(contract): SSOT forwarding stub, quirk docs for false positives
stash@{7}: WIP on main: 9497894c fix(hygiene): BareExcept 경고 억제 + Scenario 파싱 수정
stash@{8}: On core: PDF LFS workaround
```

---

## Notes

1. **No `git stash clear` was used** — all drops were targeted.
2. **Renumbering**: Indices shifted after each drop. Final list is clean 0–8.
3. **stash@{4}** (sync-branch auto-stash) contains the `payload_bridge.nim` `string→JsonNode` type change that the integration daemon plan depends on. Consider extracting this change separately if needed.
4. **stash@{7}** (PBT regeneration, 194 files) may need re-execution with the current synthesizer rather than applying directly — it will likely conflict with HEAD.
5. **stash@{8}** (PDF LFS) requires Git LFS tracking setup (`git lfs track "*.pdf"`) before the pointer conversion can be applied.
