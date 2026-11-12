# nimtry Policy — Unified Tier 2d Architecture Gate

> **Status**: Active  
> **Enforced by**: `src/gate/nimtry/nimtry_cli.nim` (standalone CLI)  
> **Baseline**: `src/gate/architecture_policy.lock` (whitelist) + `data/impure_procedures_whitelist_baseline.json` (monotonic count)  
> **AGENTS.md**: §0.6 (Static First Enforcement), §0.4 (Architecture Governance)

---

## 1. Overview

nimtry is Axiom's unified architecture gate that validates code against project
policy at compile time and via AST analysis. It replaces the legacy
`architecture_gate` and integrates Nim compiler queries with project-specific
rules.

```
nimtry check [file1.nim file2.nim ...]   # Incremental (changed files only)
nimtry check                              # Full tree scan
nimtry --full-tree                        # Force full tree even with file args
```

**Exit codes**: 0 = PASS, 1 = FAIL (violations found), 2 = ERROR (internal)

---

## 2. Rule Categories

### 2.1 SOC Transitive (`soc-transitive`)
Detects layer import violations. Each module belongs to a layer (core, gate,
cli, infrastructure, etc.) and must only import from allowed layers.

### 2.2 SOLID LSP (`solid-lsp`)
Liskov Substitution Principle: detects override methods that narrow the
exception set or widen the parameter types beyond the base contract.

### 2.3 SOLID SRP (`solid-srp`)
Single Responsibility Principle: detects modules that mix concerns from
different domains (e.g., CLI parsing + business logic in the same file).

### 2.4 Architecture Rules
- **Layer import violations**: cross-layer imports not in the allowlist
- **SSOT type placement**: domain types must be in their canonical module
- **SOLID forbidden calls**: e.g., `execCmdEx` in core layer
- **SSOT forbidden assignments**: e.g., writing to a domain type's field outside its SSOT module
- **Surface area limits**: max exported symbols per module (default: 50)
- **DRY duplicate detection**: identical function bodies across modules

### 2.5 Proc Purity (`safety-proc-purity`)
Validates that `proc` declarations in core layer have I/O justification.
Procs without transitive I/O calls MUST be `func` per AGENTS.md §0.6.

---

## 3. Baseline Management

### 3.1 Monotonic Decrease Policy

Violation count MUST NEVER increase across commits. This is enforced by
`tools/ci/monotonic_whitelist_gate.py`.

| Metric | Location | Rule |
|--------|----------|------|
| Total violation baseline | nimtry output | Must decrease or stay same |
| Impure whitelist count | `data/impure_procedures_whitelist_baseline.json` | Must match lock file |
| Architecture policy lock | `src/gate/architecture_policy.lock` | SSOT for all rules + whitelist |

### 3.2 Whitelist Management

The `impure_procedures_whitelist` in `architecture_policy.lock` lists procs
that are inherently impure (I/O boundary) and cannot be converted to `func`.

```toml
[impure_procedures_whitelist]
whitelist = ["src/core/smt.nim:bar", ...]
```

**Adding entries**: Use `nimtry --update-lock` after verifying the proc is
genuinely impure (has transitive I/O calls that cannot be refactored away).

**Removing entries**: Only when the proc has been converted to `func` or deleted.

### 3.3 Baseline Update Workflow

```
1. nimtry check                    # Verify current state
2. nimtry --update-lock            # Update architecture_policy.lock
3. Update baseline JSON            # Match new whitelist count
4. Commit both files atomically
```

---

## 4. Agent Workflow

### 4.1 Pre-Commit Check

```bash
# Changed files only (incremental — fast)
nimtry check src/changed_file.nim

# Full tree (CI — slow but comprehensive)
nimtry check
```

### 4.2 Interpreting Results

```
[nimtry] PASS — 2 violations (errors: 0, warnings: 2, baseline: 1129 ↓1127 improving)
```

- **PASS**: No new errors (warnings allowed)
- **FAIL**: New errors introduced — MUST fix before commit
- **baseline: N ↓M**: Current count M, baseline N. ↓ means improving.

### 4.3 Adding New Impure Procs

When a genuinely impure proc is discovered:

1. Verify it has transitive I/O (read `docs/spec/nim_effect_system_quirks.md`)
2. Add to `impure_procedures_whitelist` in `architecture_policy.lock`
3. Run `nimtry check` to verify no new errors
4. Update `data/impure_procedures_whitelist_baseline.json` count
5. Commit with message: `fix(gate): whitelist <module>:<proc> — <reason>`

### 4.4 Stale Binary Prevention

nimtry binary MUST be rebuilt after modifying:
- `src/gate/nimtry/` (any file)
- `src/gate/architecture_policy.lock` (rule changes)
- `src/gate/architecture_ast_facts.nim` (AST analysis)

```bash
# Delete stale binary + entry trap
rm -f src/gate/nimtry/nimtry_cli.nim src/gate/runners/nimtry
# Rebuild
nim c -o:src/gate/nimtry/nimtry_cli.nim src/gate/nimtry/nimtry_cli.nim
```

---

## 5. Known Limitations

### 5.1 `parseJson` False Positive
Nim stdlib's `parseJson` is classified as impure by the effect system despite
being logically pure. This is documented in `docs/spec/nim_effect_system_quirks.md`.
Procs calling `parseJson` MUST remain in the whitelist.

### 5.2 Transitive Purity Depth
nimtry checks transitive I/O to a default depth of 3 call levels. Deep call
chains (4+ levels) may produce false negatives. See
`docs/spec/nimtry_transitive_proc_purity.md` for the detection algorithm.

### 5.3 `wf_semantic.nim` Pragma Indentation
The `{.pop.}` pragma at line 608 of `src/cli/wf_semantic.nim` MUST be indented
2 spaces (not column 0). Column 0 causes a compilation error in downstream
binaries that import this module. This is a known Nim parser quirk.

---

## 6. Related Documents

| Document | Topic |
|----------|-------|
| `docs/spec/nim_effect_system_quirks.md` | stdlib side effect registry |
| `docs/spec/nimtry_transitive_proc_purity.md` | Transitive purity detection algorithm |
| `docs/spec/nimtry_concurrency_rules_proposal.md` | Proposed concurrency rules |
| `docs/spec/proc_to_func_completed.md` | Migration completion status |
| `docs/spec/concurrency_policy.md` | Concurrency rules (AGENTS.md §0.6a) |
| `docs/agents/architecture.md` | Layer definitions and gate architecture |
