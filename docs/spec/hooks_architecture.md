# Git Hooks Architecture

> **Status**: Active specification (Phase 1 of Bash→Nim migration)
> **SSOT**: This file + `AGENTS.md` §0.3 (Gate Layer Boundary)
> **Created**: 2026-06-17

---

## §1. Target Architecture (Post-Migration)

```
┌─────────────────────────────────────────────────────────┐
│  Git Event (commit / push)                              │
└────────────┬────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────┐
│  .githooks/pre-commit  or  .githooks/pre-push           │
│  (Bash shim — pure dispatcher, NO validation logic)     │
│                                                         │
│  Responsibilities:                                      │
│    1. Read stdin (pre-push: ref/sha pairs)              │
│    2. Fast-fail: new-branch push detection              │
│    3. Binary-freshness guard → rebuild bin/gate_hook    │
│       only if src is newer than binary                  │
│    4. Bypass audit logging (.axiom/bypass_audit.jsonl) │
│    5. Invoke: exec bin/gate_hook <stage> [files...]     │
│                                                         │
│  MUST NOT contain: validation logic, phase checks,      │
│  gate invocations, or business rules.                   │
└────────────┬────────────────────────────────────────────┘
             │ exec
             ▼
┌─────────────────────────────────────────────────────────┐
│  bin/gate_hook  (compiled Nim binary)                   │
│  Source: src/gate/runners/gate_hook.nim                 │
│                                                         │
│  Responsibilities:                                      │
│    1. Parse stage (pre-commit / pre-push)               │
│    2. Load gate_list.nim (SSOT for gate registry)       │
│    3. Filter gates by stage                             │
│    4. Apply 4-layer resource defense (cgroups, nice,    │
│       CPU cap, memory limit)                            │
│    5. Execute gates in parallel (L2 concurrency)        │
│    6. Cache results via gate_memo (epoch-based)         │
│    7. Exit with gate failure code if any gate fails     │
└────────────┬────────────────────────────────────────────┘
             │ dispatch
             ▼
┌─────────────────────────────────────────────────────────┐
│  src/gate/manifest.d/_index.json  (SSOT)                         │
│                                                         │
│  GateConfig entries:                                    │
│    - id, name, layer (glMeta / glFunctional / glNimtry) │
│    - entry (binary path or source path)                 │
│    - stages: {gsPreCommit, gsPrePush, gsManual}        │
│    - passFilenames, filesPattern, weight                │
│                                                         │
│  Layer boundary:                                        │
│    L0: gate_hook.nim (orchestrator)                     │
│    L1: gate-self-check, sentinel, quality-gate-marker   │
│        → MUST NOT reference L0 entry points             │
│    L2: functional gates (nim_check, nimtry, ratchets)   │
│    L2d: nimtry architecture principle enforcement       │
└─────────────────────────────────────────────────────────┘
```

### 1.1 Design Principles

| Principle | Description |
|-----------|-------------|
| **Pure Dispatchers** | `.githooks/*` Bash scripts contain zero validation logic; they only read git context, apply freshness guards, and `exec bin/gate_hook`. |
| **SSOT gate_list.nim** | Every gate is declared in `gate_list.nim`. Adding/removing gates requires editing this single file. |
| **No Per-Push Compilation** | `bin/gate_hook` is compiled once and reused. The Bash shim rebuilds only when source timestamps indicate staleness. |
| **Binary Build Isolation** | The Bash shim verifies `bin/gate_hook` freshness via tree-based `find -newer` scan. If stale, it rebuilds with `nim c`. L1 meta gate (`gate_self_check`) provides a second layer via compile-time timestamp injection (`-d:AxiomCompileTime`). |
| **Transitive Dependency Awareness** | The freshness guard scans ALL `.nim` files under `src/gate/`, not just `gate_hook.nim`. This catches stale binaries caused by changes in transitive dependencies (`orchestrator_hook_part1.nim`, etc.). Cross-checked with `git diff` to avoid false positives from mtime distortion after `git checkout`. |
| **Performance Guarantee** | Pre-push shim overhead ≤ 1s. Pre-commit shim overhead ≤ 200ms. Zero Nim compilation on hot path. |

### 1.2 Hook Invocation Flow

**Pre-Push:**
```
git push → .githooks/pre-push
  → read stdin: local_ref local_sha remote_ref remote_sha
  → new-branch check (local_sha all zeros → skip)
  → compute CHANGED_FILES via git diff
  → binary-freshness guard
  → exec bin/gate_hook pre-push $CHANGED_FILES
  → proc→func conversion hint (informational, non-blocking)
```

**Pre-Commit:**
```
git commit → .githooks/pre-commit
  → bypass audit (.axiom/bypass_audit.jsonl)
  → exec bin/gate_hook pre-commit
```

### 1.3 Binary Freshness Guard

The Bash shim implements a **2-layer defense** against stale binaries:

**Layer 1 — Bash Shim (tree-based scan + git cross-check):**

```bash
# 1. Scan ALL .nim files under src/gate/ — catches transitive dependency changes
STALE=$(find src/gate -name "*.nim" -newer bin/gate_hook -print -quit 2>/dev/null)
if [ -n "$STALE" ]; then
  # 2. Cross-check with git: real change vs mtime distortion from git checkout
  STAGED=$(git diff --cached --name-only -- src/gate/ | head -1)
  DIRTY=$(git diff --name-only -- src/gate/ | head -1)
  if [ -n "$STAGED" ] || [ -n "$DIRTY" ]; then
    # 3. Rebuild with compile-time timestamp injection
    nim c --hints:off -d:release \
      -d:AxiomCompileTime=$(date +%s) \
      -o:bin/gate_hook src/gate/runners/gate_hook.nim
  fi
fi
```

**Layer 2 — Nim L1 Meta Gate (compile-time timestamp embedding):**

```nim
# gate_hook.nim: compile-time define, always injected by Bash Shim
const AxiomCompileTime* {.intdefine.}: int = 0

# gate_self_check.nim: runtime verification
proc checkBinaryFreshness(repoRoot: string) =
  for path in walkDirRec(repoRoot / "src" / "gate", yieldFilter = {pcFile}):
    if path.endsWith(".nim"):
      if getLastModificationTime(path).toUnix() > AxiomCompileTime:
        quit(1)  # FATAL: source modified after compilation
```

This ensures:
- **Transitive dependency coverage**: Changes in ANY `src/gate/*.nim` file trigger rebuild.
- **No false positives from mtime distortion**: `git diff` cross-check prevents unnecessary rebuilds after `git checkout`/`git pull`.
- **Incremental cache safety**: `-d:AxiomCompileTime=$(date +%s)` forces nimcache SHA1 change → recompilation bypasses module-level caching.
- **Two-layer defense**: Layer 1 (Bash) auto-rebuilds; Layer 2 (Nim) panics if stale binary somehow runs.

### 1.4 Bypass Audit Trail

Emergency bypass requires a valid **Ed25519 signature over a TOTP-based time window** (`src/core/trusted/bypass_verify.nim`), not a static token. A plain `AXIOM_EMERGENCY_NO_VERIFY=1` alone is insufficient — it must be accompanied by a valid signature.

Bypass credentials are supplied via env vars (see `src/core/trusted/env_types.nim`):
- `AXIOM_BYPASS_SIGNATURE` — hex Ed25519 signature
- `AXIOM_BYPASS_PUBKEY` — hex Ed25519 public key
- `AXIOM_BYPASS_REASON` — bypass reason (defaults to `agent-emergency`)

`verifyBypassSignature` checks the signature against the current AND previous TOTP window (boundary-condition replay guard). The canonical payload is `"{window}|{tree_hash}|{reason}"`. On success, the bypass is logged to `.axiom/bypass_audit.jsonl` (deduplicated by timestamp):

```json
{"ts": 1750000000, "reason": "agent-emergency", "pubkey": "abcd1234...", "window": 2916666, "type": "ephemeral"}
```

The legacy "any non-empty value, no persistent audit" token mechanism (a theater/Dead Gate, DEBT#289) has been **removed** and replaced by the Ed25519+TOTP signature path above.

---

## §2. Migration Boundary (During Transition)

During the Bash→Nim migration (Phases 1-3), hooks operate in a **hybrid mode**:

```
┌─────────────────────────────────────┐
│  .githooks/pre-commit (Bash)        │
│  ┌─────────────────────────────┐    │
│  │ Phase N: Fast-fail checks   │ ←── Still in Bash during Phase 2
│  └─────────────────────────────┘    │
│  ┌─────────────────────────────┐    │
│  │ Phase N+1: bin/gate_hook    │ ←── Nim gates, verified equivalent
│  └─────────────────────────────┘    │
└─────────────────────────────────────┘
```

**Rules during migration:**
1. Bash phases are deleted only after the corresponding Nim gate is registered in `gate_list.nim` AND the parity harness confirms equivalence.
2. The parity harness (`tests/hooks/parity_harness.nim`) runs both paths and compares exit codes + stderr signatures.
3. Double-execution is tolerated in Phase 2 but must not exceed baseline + 20% latency.

### 2.1 Gate Inventory (Current Bash Phases → Nim Targets)

| # | Bash Phase (`.githooks/pre-commit`) | Nim Target Gate | Phase |
|---|--------------------------------------|-----------------|-------|
| 0.5 | Purge guard (`tests/generated/`) | `purge-guard-gate` | Phase 2 |
| 0.7 | Language ban (extension allowlist) | `language-ban-gate` | Phase 2 |
| 1.0 | Binary artifact (ELF/PE/Mach-O) | `binary-artifact-gate` | Phase 2 |
| 1.5 | Magic number sniffer | (external Python) | Retained in shim |
| 1.6 | Monotonic whitelist ratchet | `monotonic-whitelist-gate` | Phase 2 |
| 1.7 | Hermetic test ratchet | `hermetic-test-gate` | Phase 2 |
| 1.8 | Debt reduction ratchet | `debt-reduction-gate` | Phase 2 |
| 1.9 | Asset hygiene ratchet | `asset-hygiene-gate` | Phase 2 |
| 1.10 | Forbidden pattern gate | (external Python) | Retained in shim |
| 2.0 | Ratchet ceiling check | (external Bash) | Retained in shim |
| 2.1 | Gate exception schema validation | (external Python) | Retained in shim |
| 2.2 | Zero-byte detection | `binary-artifact-gate` | Phase 2 |
| 3.0 | LFS pointer validation | `lfs-pointer-gate` | Phase 2 |
| 4.0 | Domain placement check | `domain-placement-gate` | Phase 2 |
| 5.0 | Forwarding stub cycle detection | `forwarding-stub-cycle-gate` | Phase 2 |
| 6.0 | `nim check` on changed files | `nim-check-gate` | Already in gate_list |
| 7.0 | nimtry architecture check | `nimtry-gate` | Already in gate_list |
| 7.5 | Annotation hygiene | `annotation-hygiene-gate` | Phase 2 |
| 8.0 | Core I/O invariant enforcement | `core-invariant-gate` | Phase 2 |
| 8.1 | `cast(noSideEffect)` doc check | `cast-nosideeffect-doc-gate` | Phase 2 |

---

## §3. File Responsibilities (Post-Migration)

| File | Role | Validation Logic? |
|------|------|-------------------|
| `.githooks/pre-commit` | Bash dispatcher | **No** — pure `exec bin/gate_hook pre-commit` |
| `.githooks/pre-push` | Bash dispatcher | **No** — pure `exec bin/gate_hook pre-push $FILES` |
| `bin/gate_hook` | Compiled Nim orchestrator | **Yes** — delegates to registered gates |
| `src/gate/runners/gate_hook.nim` | Source for `bin/gate_hook` | **Yes** — gate scheduling, resource limits |
| `src/gate/manifest.d/_index.json` | Gate registry (SSOT) | **No** — declarative config only |
| `src/gate/runners/*_gate.nim` | Individual gate implementations | **Yes** — one per validation phase |
| `bin/setup-hooks` | Git hooks path configurator (sole writer of `core.hooksPath` — ADR-0028) | **No** — sets `core.hooksPath` to `.githooks` |
| `tests/hooks/parity_harness.nim` | Migration scaffold (Phase 1-3) | **Yes** — parity verification |

---

## §4. Constraints

1. **Language Ban**: All hooks and gate code must be Nim (or Bash shim for dispatcher only). No Python validation in the gate path (Python scripts in `tools/ci/` may be invoked as external processes but are not part of the core gate chain).
2. **No Per-Push Compilation**: The Bash shim must never invoke `nim c -r`. It must use the pre-compiled `bin/gate_hook`.
3. **Worktree Safety**: `core.hooksPath=.githooks` at repository scope. `tools/setup_hooks.nim:15` writes it with the bare form `git config core.hooksPath .githooks`, which targets the repository-local config — it does NOT pass `--global` and does NOT spell out `--local`. All paths relative to repo root via `git rev-parse --show-toplevel`. `nimble hooks` is RETIRED (ADR-0028) — it wrote `hooks`, a gitignored directory, and silently disarmed the tracked hooks above; `make -f ci/checker.mk setup-hooks` is the install command.
4. **Emergency Bypass**: `AXIOM_EMERGENCY_NO_VERIFY=1` skips all gates (pre-commit only). `git push --no-verify` skips pre-push. Both are audit-logged.
5. **L1/L0 Boundary**: L1 meta gates MUST NOT reference `gate_hook` entry points (compile-time `static` assertion).
