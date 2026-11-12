# Quality Gates & Post-Change Verification

> Extracted from AGENTS.md §3. Refer back to AGENTS.md §3 for the condensed version.

## 3.1 Pre-commit Pipeline

1. `intent_gate`, `spec_presence_gate`, `test_coverage_gate` — BDD Contract Gates (Tier 0)
2. `nim check` on all staged `.nim` files (warningAsError:UnusedImport)
3. `procedure_gate` — 4-step integrity per `src/` change (checks for BDD feature evidence)
4. `nimtry --full-tree` — unified architecture analysis (Tier 2d)
5. `memory_policy_gate` — AGENTS.md SSOT boundary enforcement

## 3.1b Gate Memoization Cache

The gate hook employs a **Merkle-based memoization layer** (`src/core/gate/gate_memo.nim`) to skip redundant gate executions when neither input files nor the gate validator source have changed.

### Cache Key Design
- **Input hash**: Merkle root SHA1 over all staged files matched by the gate's `filesPattern`.
- **Validator hash**: SHA1 of the gate's Nim source file (resolved via `resolveGateSourcePath`).
- **Composite lock**: `SHA1(Merkle(input) + SHA1(source))`.

### Cache Behavior
- **Hit**: If `compositeLockHash` matches the cached entry, the gate result is replayed from `logs/.gate_memo/<gateId>.json` with `(cached)` annotated in stderr output.
- **Miss**: Any change to staged files OR the gate source invalidates the cache and triggers a fresh execution.
- **Storage**: JSON files under `logs/.gate_memo/` (gitignored, auto-created).

### Coverage
- L1 Meta gates: checked/saved in sequential loop.
- L2 Functional gates: checked before spawn, saved on completion.
- Single-gate mode (child processes): checked/saved directly.

## 3.1c Unified Nimcache (cli-build Optimization)

The cli-build process compiles 6 CLI binaries (`main`, `ax`, `server`, `gate_hook`, `unified_sentry`, `all_gateway_runner`). Historically, each target used an **isolated nimcache directory**, causing ~99.5% redundant compilation: `build/nimcache/main/` and `build/nimcache/ax/` share 616 of 617 artifacts, yet Nim recompiled all shared modules twice.

### Design
- **Shared cache**: All targets now use `build/nimcache/shared_<flagDigest>`
- **Flag-aware isolation**: Cache path incorporates a digest of codegen-relevant compile flags (e.g., `-d:ThreadPoolSize=14`). If future targets use different flags, artifacts are automatically isolated into separate directories.
- **Deterministic**: Same source hash + same flagset → identical artifact reuse

### Impact
| Scenario | Before (isolated nimcache) | After (unified nimcache) |
|----------|---------------------------|-------------------------|
| 2 targets stale (main + ax) | ~180s | ~95s |
| 4 targets stale | ~360s | ~120s |
| 6 targets stale | ~540s | ~150s |

## 3.2 Pre-push Pipeline

Merkle verification of `data/universe_merkle.lock`. If stale, `ax prove` must regenerate.

## 3.3 Post-Change Verification

After any `src/core/`, `src/cli/`, or `src/verification/` modification:
1. `ax prove` — confirm certificate validity
2. `ax prove --limit N` — confirm self-healing loop

Resolve all regressions until ASI = 1.0000 before commit.

## 3.4 Report & Stale State Guardrails

- `ax report` → TUI (ASCII table). `ax report --json` → JSON only.
- `logs/ax_proof_state.json` is transient; auto-purged after 24h.
- ASI SSOT = certificate vault (`src/verification/certificates/`).
- `data/universe_merkle.lock` is Git-tracked; only `ax prove` may update it.

## 3.5 Emergency Override

`AXIOM_EMERGENCY_NO_VERIFY=1 git commit --no-verify` / `git push --no-verify`. Post-action documentation mandatory.

---

## Pre-commit / Pre-push Pipeline (Skill Reference)

The `prek-quality-gate` skill was migrated to the gate pipeline documented above (enforced by `src/gate/runners/` gates); its SKILL.md is removed. See `docs/agents/plugin-migration.md` for the migration registry.

## Post-Change Verification Pipeline Test (Mandatory)

After any code modification to `src/core/`, `src/cli/`, or `src/verification/`, the agent **MUST** run the following verification pipeline tests before committing:

1. **`ax prove`** — confirms that existing certificates remain valid and no new fingerprint mismatches or structural mismatches are introduced.
2. **`ax prove --limit N`** (integrated healing mode) — confirms that the self-healing loop can still generate and validate hints, and that no new `unverifiable` nodes appear due to the change.

These tests are **not optional**. If either command reveals regressions (ASI drop, new `unverifiable` nodes, Lean compiler errors, or certificate invalidation), the agent **MUST** resolve all regressions and re-run the pipeline until ASI returns to `1.0000` before proceeding to `git commit`.

## Emergency Override (Detailed)

`AXIOM_EMERGENCY_NO_VERIFY=1 git commit --no-verify` — requires post-commit documentation.

---

## Related

- [AGENTS.md §3](../../AGENTS.md) — Condensed quality gates overview
- [AGENTS.md §2.5](../../AGENTS.md) — Evidence-Based Deterministic Convergence (EDC) protocol: verify_success, post_condition, evidence receipts
- [docs/agents/mcp-parallelism.md](mcp-parallelism.md) — Parallelism policy for sub-agents
