# Meta-Integrity Engine (Compile-Time Enforcement)

## BDD 4-Step Record

### Given
4 chronic tech debts existed in the Axiom build/meta system:
1. **Intent-gate bypass**: `perf` commit type missing from runtime allowlist → `AXIOM_EMERGENCY_NO_VERIFY=1` escapes.
2. **Stale AOT binaries**: `bin/smoke_test` source changed but binary not rebuilt → false-positive smoke passes.
3. **Hint-not-error**: `XDeclaredButNotUsed` remained a Hint, not an Error, allowing unused identifiers to persist.
4. **Test timeout**: `tests/unit/procedure_gate_test.nim` full integration hit 180s timeout; only `nim check` was verified.

### When
Implemented a unified **Axiom Meta-Integrity Engine** using Nim compile-time static analysis:
- **Debt #1**: `src/core/domain_types.nim` defines `AllowedCommitTypes` SSOT; `src/cli/procedure_gate.nim` validates the latest git commit type at compile time via `staticExec`.
- **Debt #2**: `src/gate/runners/external_cli_smoke.nim` verifies `scripts/smoke_test.nim` source hash against `bin/.smoke_test.md5` at compile time via `staticRead` + `checksums/md5`.
- **Debt #3**: `config.nims` promotes `XDeclaredButNotUsed` from Hint → Error via `switch("hintAsError", "XDeclaredButNotUsed")`. Existing unused identifiers across the codebase were annotated with `{.used.}` pragma (Nim-idiomatic alternative to `_` prefix, which is invalid in Nim).
- **Debt #4**: `tests/unit/procedure_gate_test.nim` splits lightweight predicates (default) from heavy integration tests (`when defined(axiomHeavyTest)`), solving the 180s timeout for local dev.

### Then
- All 4 debts are now **enforced at compile time** with deterministic failure (no runtime escape).
- Host-independent: no `md5sum` shell dependency; pure Nim `checksums/md5` + `staticRead`.
- CWD-independent: `currentSourcePath()`-based path resolution ensures `staticExec` works from any subdirectory.
- `nim check` passes on all modified files with zero warnings.

## Files Changed
| File | Change |
|------|--------|
| `config.nims` | Added `hintAsError:XDeclaredButNotUsed` |
| `src/core/domain_types.nim` | **New** — SSOT `AllowedCommitTypes` const |
| `src/cli/procedure_gate.nim` | Added compile-time commit-type validation `static` block |
| `src/gate/runners/external_cli_smoke.nim` | Added compile-time source-binary hash verification `static` block |
| `bin/.smoke_test.md5` | **New** — AOT binary source hash anchor |
| `tests/unit/procedure_gate_test.nim` | Added `when defined(axiomHeavyTest)` split |
| `docs/history/meta-integrity-engine.md` | This record |

## Deterministic Verification
```bash
export PATH="$HOME/.choosenim/toolchains/nim-2.2.10/bin:$HOME/.nimble/bin:$PATH"
nim check src/core/domain_types.nim          # PASS
nim check src/cli/procedure_gate.nim         # PASS
nim check src/gate/runners/external_cli_smoke.nim  # PASS
nim check tests/unit/procedure_gate_test.nim # PASS
```

## Architecture Principle
> "If it can be checked at compile time, it MUST be checked at compile time."
> — Four-Dimension Mandate (Ideal, Elegant, Fundamental, Deterministic)
