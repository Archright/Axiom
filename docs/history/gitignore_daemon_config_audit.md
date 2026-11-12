# Gitignore & Daemon Config Audit

**Date**: 2026-06-17
**Scope**: `.gitignore` (root + `bin/`), `.axiom/daemon.json.template`

---

## 1. Worktree Status

| Worktree | Non-ignored dirty files | Ignored entries |
|----------|------------------------|-----------------|
| Axiom (main) | 0 | 416 |
| Axiom-core | 0 | 262 |

Both worktrees are **clean** — no non-ignored files would block the daemon.

## 2. Build Artifact Coverage

All key artifact directories are properly gitignored:

| Directory/Pattern | Gitignore Rule | Daemon Impact |
|-------------------|----------------|---------------|
| `nimcache/`, `nimcache_*`, `.nimcache/` | Lines 57-61, 188 | ✅ Safe |
| `build/`, `build/nim.so` | Lines 21, 257 | ✅ Safe |
| `bin/*` (compiled binaries) | `bin/.gitignore:1:*` | ✅ Safe (whitelisted scripts only) |
| `.axiom/` (staging) | Line 248 | ✅ Safe (runtime config ignored) |
| `data/proof_cache/` | Line 252 | ✅ Safe |
| `logs/*`, `*.log` | Lines 65, 72 | ✅ Safe (`integration.log` covered) |
| `cache/`, `*.cache` | Lines 64, 71 | ✅ Safe |
| `nimblecache/` | Line 58 | ✅ Safe |
| `.lake/` | Line 76 | ✅ Safe |
| `vendor/` | Line 79 | ✅ Safe |

## 3. Daemon Signal File

- **Signal file**: `.git/AXIOM_SYNC_STATE.json` (inside `.git/`, never shows in `git status`)
- **Runtime config**: `.axiom/daemon.json` (gitignored by `.axiom/` rule)
- **Daemon log**: `logs/integration.log` (gitignored by `*.log` rule)
- **Template**: `.axiom/daemon.json.template` (gitignored by `.axiom/` rule — runtime use only)

## 4. Changes Made

### 4a. `bin/.gitignore` — Added whitelist entries

```diff
 !sync-branch
+!integration-daemon
+!sync-main-worktree
 !.gitignore
 !.smoke_test.sha256
```

**Rationale**: `bin/.gitignore` has `*` catch-all. New daemon scripts must be whitelisted here or they'll be invisible to `git add`.

### 4b. Root `.gitignore` — Added whitelist entries

```diff
 !bin/sync-branch
+!bin/integration-daemon
+!bin/sync-main-worktree
```

**Rationale**: Redundant with `bin/.gitignore` for untracked files, but ensures consistency if `bin/.gitignore` is ever removed. Root-level whitelist is the defense-in-depth layer.

### 4c. `.axiom/daemon.json.template` — Created

Template with documented fields:

| Field | Default | Description |
|-------|---------|-------------|
| `pollIntervalSeconds` | 5 | Fallback polling interval when fswatch unavailable |
| `maxLockRetries` | 5 | Max retries on `.git/index.lock` contention |
| `lockRetryBaseMs` | 200 | Base ms for exponential backoff (200, 500, 1000, 2000, 4000) |
| `signalTtlSeconds` | 86400 | Signal file TTL before stale cleanup |
| `untrackedExcludes` | `[]` | Pathspecs to exclude from dirty check (logged as `CUSTOM_IGNORE_APPLIED`) |
| `pathspecs` | `[]` | Restrict dirty check to subset of paths |
| `notifyOnPanic` | `true` | Desktop notification on panic/safe mode |

## 5. Known Issues

### 5a. Dead root `.gitignore` whitelist entries

The root `.gitignore` has `!src/gate/nimtry/nimtry_cli.nim` (line 226) but `src/gate/nimtry/nimtry_cli.nim` is not tracked and `bin/.gitignore:1:*` overrides it. This is a pre-existing issue (not caused by this change). Similar dead entries may exist for other bin/ scripts.

**Impact**: None for daemon operation. These are cosmetic gitignore inconsistencies.

### 5b. `.axiom/` is fully gitignored

The daemon config template at `.axiom/daemon.json.template` is gitignored. This is intentional — `.axiom/` is the P4 topology staging directory. The template is a runtime reference, not a version-controlled artifact. If version control is desired, place it at `docs/spec/daemon_config_template.json` instead.

## 6. Verdict

**No .gitignore additions are needed for daemon operation.** All build artifacts are properly covered. The only changes are:
1. Whitelisting new `bin/` scripts (required for `git add` to work)
2. Creating the daemon config template
