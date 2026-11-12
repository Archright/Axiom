# Git Semantics Verification Report

**Date**: 2026-06-17
**Test environment**: Linux, Git (Korean locale), isolated bare repo at `/tmp/axiom-sync-test-*`
**Purpose**: Verify Git behaviors required by the Integration Daemon architecture (shadow worktree sync, lock contention, dirty detection, merge semantics).

---

## 1. Shadow Worktree Ref Update

### Setup
- Bare repo with one worktree (`main-worktree`) on `main` branch
- Shadow worktree (`shadow-sync`) in detached HEAD

### Finding: `git branch -f` is BLOCKED

```bash
git -C <shadow> branch -f main <new-sha>
# fatal: cannot force update the branch 'main' used by worktree at '/path/to/main-worktree'
```

Git **protects branches checked out in any worktree** from force-update. Exit code 128.

### Finding: `git update-ref` SUCCEEDS

```bash
git -C <shadow> update-ref refs/heads/main <new-sha>
# EXIT_CODE=0
```

- Works even when agent worktree has the branch checked out
- Works even when agent worktree is **dirty** (uncommitted changes)
- Agent working tree files are **NOT modified** by the ref update
- Agent HEAD follows the branch pointer (expected — HEAD is on `main`)
- Dirty changes in the agent worktree are **preserved**

### Verdict

**`bin/sync-branch` MUST use `git update-ref refs/heads/main <sha>` instead of `git branch -f main <sha>`** from the shadow worktree. The `branch -f` approach is a non-starter.

---

## 2. `GIT_OPTIONAL_LOCKS=0 git status --porcelain`

### Finding: Works correctly

```bash
GIT_OPTIONAL_LOCKS=0 git status --porcelain
# EXIT_CODE=0, empty output when clean
```

- Exits 0 with or without `GIT_OPTIONAL_LOCKS=0`
- `GIT_OPTIONAL_LOCKS=0` prevents index refresh side-effect (no lock acquisition)

### Finding: Ignored files are NOT shown by default

```bash
# With .gitignore containing nimcache/ and build/
git status --porcelain          # → empty (PASS)
git status --porcelain --ignored  # → "!! nimcache/" "!! build/" (shows them)
```

**Build artifacts in `.gitignore` do NOT appear in `--porcelain` output.** The daemon's dirty check via `git status --porcelain` will not be polluted by `nimcache/`, `build/`, etc.

### Verdict

`GIT_OPTIONAL_LOCKS=0 git status --porcelain` is safe for background daemon use. The daemon MUST set this env var for all read-only Git calls.

---

## 3. Index.lock Contention

### Finding: Read-only operations are UNAFFECTED by index.lock

| Operation | Exit code | Notes |
|-----------|-----------|-------|
| `git status --porcelain` | 0 | Succeeds even with lock held |
| `git diff` | 0 | Succeeds |
| `git rev-parse HEAD` | 0 | Succeeds |
| `git log --oneline -3` | 0 | Succeeds |
| `GIT_OPTIONAL_LOCKS=0 git status --porcelain` | 0 | Succeeds |

### Finding: Write operations FAIL with exit code 128

| Operation | Exit code | Error pattern |
|-----------|-----------|---------------|
| `git add <file>` | 128 | `fatal: '<path>/.git/index.lock': File exists.` |
| `git commit -m "..."` | 128 | Same pattern |

**Error string (Korean locale)**:
```
fatal: '/path/.git/index.lock' 파일을 만들 수 없습니다: 파일이 있습니다.
```

**Error string (English equivalent)**:
```
fatal: '<path>/.git/index.lock': File exists.
```

### Finding: Lock location for linked worktrees

Each worktree has its **own** `index.lock` in its `git-dir`:
- Agent worktree: `<common-dir>/index.lock`
- Shadow worktree: `<common-dir>/worktrees/shadow-sync/index.lock`

### Daemon Implication

Since the daemon only performs **read-only** operations (`git status`, `git rev-parse`), index.lock contention from concurrent agent commits will **not block the daemon's dirty check**. The retry logic is still valuable as a defensive measure for edge cases (e.g., simultaneous `git checkout` by the agent).

**Lock detection pattern**: Check exit code 128 + stderr contains `index.lock`.

---

## 4. `git merge --ff-only` Behavior

### Finding: merge --ff-only does NOT refuse when dirty (non-conflicting)

```bash
# Agent is behind main, README.md is dirty (modified)
git merge --ff-only main
# Fast-forward (adds new files, doesn't touch README.md)
# EXIT_CODE=0 ← SUCCEEDS despite dirty worktree!
```

**CRITICAL**: `git merge --ff-only` only fails when:
1. The merge cannot be fast-forwarded (diverged branches), OR
2. The fast-forward would **overwrite** the dirty file

If the dirty files don't conflict with incoming changes, **merge succeeds with dirty worktree**.

### Finding: merge --ff-only FAILS when diverged

```bash
# Diverged branches (can't fast-forward)
git merge --ff-only main
# fatal: Diverging branches can't be fast-forwarded
# EXIT_CODE=128
```

### Finding: Untracked files don't block merge

```bash
# Only untracked files present
git merge --ff-only main
# EXIT_CODE=0 (succeeds)
```

### Verdict

**The daemon MUST NOT rely on `git merge --ff-only` to detect dirty state.** It MUST explicitly check `git status --porcelain` BEFORE attempting the merge:

```
1. GIT_OPTIONAL_LOCKS=0 git status --porcelain
2. If non-empty → DIRTY_DEFERRED
3. If empty → proceed with merge --ff-only
```

---

## 5. `fswatch` Signal Detection

### Finding: `fswatch` is NOT installed on this system

```bash
which fswatch  # → not found
```

### Finding: Polling fallback works

```bash
SIGNAL_FILE="<bare-repo.git>/AXIOM_SYNC_STATE.json"
[ -f "$SIGNAL_FILE" ] && echo "Signal detected"
# PASS: Signal detected by polling
```

- File existence check: reliable
- `stat -c%Y` for mtime: works for change detection
- Atomic write (temp + rename): works

### Verdict

Daemon MUST detect `fswatch` at startup. If unavailable, fall back to polling `AXIOM_SYNC_STATE.json` every `pollIntervalSeconds` (default 5).

---

## 6. Robust Path Resolution (Linked Worktrees)

### Finding: Two reliable methods

**Method A (preferred)**:
```bash
git -C <worktree-path> rev-parse --git-common-dir
# Returns: /path/to/main-worktree/.git  (or bare repo .git)
```

**Method B (manual, no git invocation)**:
```bash
# Read .git file: "gitdir: /path/to/main-worktree/.git/worktrees/<name>"
# Common dir = dirname(dirname(gitdir_path))
```

### Finding: `.git` file structure

```
Shadow worktree .git file content:
  gitdir: /tmp/.../main-worktree/.git/worktrees/shadow-sync

Resolution chain:
  .git file → gitdir path → worktree-specific dir → parent's parent = common dir
```

### Finding: Worktree directory layout

```
<main-worktree>/.git/              ← common dir (shared refs/, objects/, config)
  ├── worktrees/
  │   └── shadow-sync/             ← git-dir for shadow (own HEAD, index, index.lock)
  │       ├── HEAD
  │       ├── index
  │       ├── index.lock           ← shadow's lock (independent from agent's)
  │       └── ...
  ├── HEAD
  ├── index
  ├── refs/
  ├── objects/
  └── config
```

Each worktree has its **own** `HEAD` and `index`. The `refs/` and `objects/` are shared via the common dir.

---

## Summary: Verified Command Sequence for Daemon

### Sync (from shadow worktree)
```bash
# 1. Create commit in shadow worktree
git -C "$SHADOW_DIR" add -A
git -C "$SHADOW_DIR" commit -m "sync: ..."

# 2. Advance main ref (NOT branch -f)
NEW_SHA=$(git -C "$SHADOW_DIR" rev-parse HEAD)
git -C "$SHADOW_DIR" update-ref refs/heads/main "$NEW_SHA"

# 3. Write atomic signal file
echo "{\"newMain\":\"$NEW_SHA\",...}" > "$SIGNAL_FILE.tmp"
mv "$SIGNAL_FILE.tmp" "$SIGNAL_FILE"
```

### Integration (in agent worktree)
```bash
# 1. Read signal file (polling or fswatch)

# 2. Dirty check (MUST be first)
DIRTY=$(GIT_OPTIONAL_LOCKS=0 git -C "$AGENT_DIR" status --porcelain)
[ -n "$DIRTY" ] && { log DIRTY_DEFERRED; exit 0; }

# 3. Idempotency check
CURRENT=$(git -C "$AGENT_DIR" rev-parse HEAD)
[ "$CURRENT" = "$NEW_MAIN" ] && { log ALREADY_INTEGRATED; exit 0; }

# 4. Merge
git -C "$AGENT_DIR" merge --ff-only main
# If exit 0 → log MERGE_OK
# If exit 128 → log MERGE_FAILED, enter PANIC mode
```

### Path resolution (from any worktree)
```bash
COMMON_DIR=$(git -C "$WORKTREE" rev-parse --git-common-dir)
```

---

## Test Environment Cleanup

All temporary files removed: `/tmp/axiom-sync-test-1781684190`
