# Sync Protocol Gate Architecture

> **Status**: **Historical** — the standalone `sync_protocol_gate` runner was
> **removed on 2026-08-02** (rebase-only sync refactor, commit `e368d3054`,
> "remove branch merge infrastructure"). The pre-push stage now runs through the
> monolithic gateway via `bin/axiom-gate hook pre-push`
> (`src/gate/gateway.nim` + `src/gate/orchestrator_hook.nim`, stage `gsPrePush`).
> The `push_context` / `sync_signing` infrastructure modules survive;
> `tx_manifest` and `sync_metadata` were removed with the gate. The details below
> describe the removed standalone gate and are preserved for historical reference.
> **SSOT**: This file + `AGENTS.md` §0.3 (Gate Layer Boundary) + `docs/spec/nim_effect_system_quirks.md` §20
> **Created**: 2026-06-27

---

## §1. Overview

The sync-protocol-gate is a pre-push gate that statelessly verifies every commit in a push *before* it reaches the remote. It replaces the legacy `axiom_sync_runner` workflow with a three-check pipeline:

```
┌──────────────────────────────────────────────────────────────┐
│  Git pre-push hook (Bash shim)                              │
│  1. Capture stdin ref/sha pairs                              │
│  2. Serialize PushContext → AXIOM_PUSH_CONTEXT env var       │
│  3. Execute: bin/sync_protocol_gate                          │
└────────────┬─────────────────────────────────────────────────┘
             │ env var + commits
             ▼
┌──────────────────────────────────────────────────────────────┐
│  sync_protocol_gate (REMOVED 2026-08-02)                      │
│  Source: src/gate/runners/sync_protocol_gate.nim (removed)   │
│                                                              │
│  Statelessness: uses only env vars + commit SHAs.            │
│  No worktree reference, no disk state reads (except         │
│  HMAC key via tx_manifest).                                  │
│                                                              │
│  Check 1: HMAC signature authentication (per-commit)        │
│  Check 2: Fast-forward ancestry verification                 │
│  Check 3: Conflict marker residue scan                      │
└──────────────────────────────────────────────────────────────┘
```

---

## §2. PushContext Flow

### 2.1 Data Model

```
PushContext
 ├── refs: seq[PushRef]
 │    ├── localRef:   string   ## "refs/heads/main"
 │    ├── localSha:   string   ## 40-hex
 │    ├── remoteRef:  string   ## "refs/heads/main"
 │    └── remoteSha:  string   ## 40-hex (or 0000...0000 for new branch)
 └── commits: seq[string]     ## local SHAs being pushed
```

### 2.2 Serialization Path

```
pre-push stdin (4-column text)
        │
        ▼ parsePushStdin()
PushContext (in-memory, func — no I/O)
        │
        ▼ toJson()
JsonNode
        │
        ▼ $jsonNode (env var)
AXIOM_PUSH_CONTEXT="{"refs":[...],"commits":[...]}"
        │
        ▼ parseJson() → parsePushContext()
PushContext (deserialized in gate binary)
```

### 2.3 Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Env var transmission (not stdin re-parse) | Gate binary is separate process; stdin already consumed by hook shim |
| `parsePushContext` is `proc` not `func` | Calls `std/json.parseJson` which has side effects (§20b) |
| `commitShas()` returns `lent seq[string]` | Zero-copy accessor; callers treat as immutable (§20c) |
| Exception-safe parsing (silently skip malformed) | Pre-push hook must not fail on malformed lines — graceful degradation |

---

## §3. TxManifest Signing

### 3.1 Lifecycle

```
axiom-gate commit (pre-commit)
        │
        ▼ signAndSave()
TxManifest created
  ├── commitSha:  git rev-parse <sha>
  ├── treeOid:    git rev-parse <sha>^{tree}
  ├── timestamp:  epochTime().int64
  ├── resolvedVia: "axiom-gate commit"
  ├── pushContextRef: (empty for pre-commit)
  └── signature:  HMAC-SHA256(computePayload, signingKey)
        │
        ▼ saveManifest()  [atomic: write .tmp → fsync → rename]
.axiom/tx_manifest/{sha}.json  (+ .lock file for flock)
```

### 3.2 Verification Chain (sync_protocol_gate)

```
isCommitAuthorized(commitSha)
        │
        ├─ loadManifest(sha) → verifyManifest()
        │   ├── hmacVerify(payload, signature)  — constant-time comparison
        │   └── (epochTime - timestamp) < 86400  — 24-hour TTL
        │
        ├─ [legacy fallback] .axiom/sync_state/{sha}.json
        │   └── parseFile → hmacVerify → TTL check
        │
        └─ [legacy fallback 2] .axiom/commit_sigs/{sha}.sig
            └── readFile → git rev-parse tree → hmacVerify
```

### 3.3 POSIX File Locking

The `saveManifest` proc uses POSIX `flock()` for multi-process safety:

```nim
proc c_flock(fd: cint, operation: cint): cint
    {.importc: "flock", header: "<sys/file.h>", sideEffect.}

const
  LOCK_EX = cint(2)
  LOCK_UN = cint(8)
```

**Quirk**: `std/posix` does not re-export `flock` on Linux — local `importc` binding required (§20a).

Lock protocol:
1. Open `.lock` file with `posix.open()` (local `O_CREAT`/`O_RDWR` constants, §20d)
2. `flock(LOCK_EX)` — exclusive lock, blocks concurrent writers
3. Write `.tmp` file → `moveFile` (atomic rename)
4. `flock(LOCK_UN)` + `posix.close()` in `finally` block

---

## §4. sync_metadata Deprecated Wrapper

### 4.1 Purpose

`sync_metadata.nim` is a **backward-compatibility shim** that maps the legacy `SyncMetadata` type and its procs to the new `tx_manifest` module. It exists solely to avoid breaking existing callers (e.g., `axiom_sync_runner`) during migration.

### 4.2 Migration Table

| Legacy (`sync_metadata`) | Replacement (`tx_manifest`) |
|--------------------------|---------------------------|
| `SyncMetadata` type | `TxManifest` type |
| `syncStatePath(sha)` | `txManifestPath(sha)` |
| `computePayload(m)` | `computePayload(m)` (same name, different type) |
| `saveSyncMetadata(m)` | `saveManifest(m)` or `signAndSave(sha, via)` |
| `loadSyncMetadata(sha)` | `loadManifest(sha)` |
| `verifySignature(m)` | `verifyManifest(m)` |
| `isWithinTtl(m)` | `verifyManifest(m)` (includes TTL check) |
| `isCommitAuthorized(sha)` | `isCommitAuthorized(sha)` (same name, direct forward) |
| `reSign(sha)` | `signAndSave(sha, resolvedVia)` |
| `signCommit(sha)` | `signAndSave(sha, resolvedVia)` |

### 4.3 Field Mapping

```
SyncMetadata                    TxManifest
─────────────────────           ──────────────────────
mergeCommit        ──→          commitSha
treeOid            ──→          treeOid
timestamp          ──→          timestamp
resolvedVia        ──→          resolvedVia
signature          ──→          signature
baseBranch         ──→          (dropped — no equivalent)
secondaryBranch    ──→          (dropped — no equivalent)
                   ──←          pushContextRef   (new field)
```

### 4.4 Deprecation Policy

- All forwarding procs carry `{.deprecated: "Use tx_manifest.XXX instead".}` pragmas.
- `sync_protocol_gate.nim` imports `tx_manifest` directly — does NOT use the wrapper.
- The wrapper will be removed once all callers have migrated (tracked in debt registry).

---

## §5. sync_protocol_gate Validation Fixes

### 5.1 Stateless Design

The gate reads **only**:
1. `AXIOM_PUSH_CONTEXT` env var (serialized `PushContext`)
2. Git object database (via `git rev-parse`, `git merge-base`, `git diff-tree`, `git show`)
3. `tx_manifest` HMAC key + manifest files (via `tx_manifest.isCommitAuthorized`)

It does **not** read:
- Any worktree file content
- Any `.axiom/` state except manifests
- Any config files

This ensures the gate can run in any working directory state.

### 5.2 Three-Check Pipeline

| Check | Failure Class | What It Catches |
|-------|--------------|-----------------|
| HMAC authentication | `fcPermanent` | Unsigned commits, tampered metadata, expired TTL |
| Fast-forward ancestry | `fcPermanent` | Non-fast-forward pushes, rewritten history |
| Conflict marker scan | `fcTransient` | Leftover `<<<<<<<` / `>>>>>>>` / `=======` markers |

**Failure classes**:
- `fcPermanent` — the push is fundamentally invalid; retrying without fixing will always fail
- `fcTransient` — may succeed on retry (e.g., conflict markers resolved in a subsequent commit)

### 5.3 Conflict Marker Detection

- Uses `git diff-tree --no-commit-id --name-only -r` to list changed files
- For each changed file, reads content via `git show <commit>:<path>`
- Scans first 50 files (bounded to prevent DoS on massive pushes)
- Checks for `<<<<<<< `, `>>>>>>> `, and `=======` prefixes

### 5.4 Edge Cases Handled

| Edge Case | Behavior |
|-----------|----------|
| Branch deletion push (empty ref list) | PASS — nothing to verify |
| New branch push (`remoteSha = 0000...0000`) | PASS — no ancestry check possible |
| Empty commit list | PASS — no commits to verify |
| Malformed PushContext JSON | Returns empty context → empty commits → PASS |
| Legacy sync_state fallback | `isCommitAuthorized` tries `.axiom/sync_state/` then `.axiom/commit_sigs/` |
| More than 50 changed files | Conflict check truncated at 50 files |

---

## §6. Module Dependency Graph

```
sync_protocol_gate.nim
 ├── infrastructure/sync_metadata      (deprecated, NOT used by gate directly)
 ├── infrastructure/push_context       (PushContext types + parse)
 ├── infrastructure/tx_manifest        (HMAC verify + manifest load)
 │    ├── infrastructure/sync_signing  (HMAC-SHA256 primitives)
 │    └── infrastructure/push_context  (PushContext for serialize)
 ├── gate/utils/real_git              (findRealGit)
 ├── core/trusted/env_access           (getEnv wrapper)
 └── infrastructure/logger             (structured logging)
```

---

*Last updated: 2026-06-27*
