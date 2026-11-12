# Proof Cache Architecture

> **Status**: Skeleton (Phase D) | **Full integration**: Next sprint

## Overview

The proof cache eliminates redundant Z3/Lean verification by storing proof results
keyed on a salted hash of: source content + compiler version + Z3 binary hash + active flags.

## Cache Key Derivation

```nim
cacheKey = sha256Hex(
  sourceFileContent &
  compiler.Version &        # Nim 2.2.10
  expectedZ3Hash &          # sha256 of vendor/z3/bin/z3
  definedFlagsString        # -d:axiomStrict -d:ffiEnabled etc.
)
```

This prevents false-positive cache hits when:
- Nim compiler is upgraded (different codegen)
- Z3 binary is updated (different solver behavior)
- Build flags change (different verification scope)

## Directory Structure

```
.axiom/proof_cache/
├── <source_sha>_<target_sha>/
│   ├── manifest.json     # Per-file hashes + proof results
│   ├── z3_results.json   # UNSAT core cache (per goal)
│   └── lean_results.json # ProofCertificate cache (per goal)
```

## Integration Points

| Location | Action |
|----------|--------|
| `tools/safe_merge.nim` (pre-gate) — **removed** (rebase-only sync, see AGENTS.md §2.8) | ~~Check cache; skip gates on hit~~ |
| `src/infrastructure/gate_signing/safe_merge.nim` (pre-daemon) — **removed** | ~~Check cache; skip daemon on hit~~ |
| `src/core/proof/proof_cache.nim` | Core cache logic |

## Anti-Poisoning Measures

- Cache key includes compiler version, Z3 hash, and flags (salted)
- Per-file content hash for granular invalidation
- Atomic write (temp + rename) for crash safety
- Cache clear via `bin/merge-lockout --clear-cache`

## Future Work

- [ ] Integrate with Z3 FFI layer for goal-level caching
- [ ] Integrate with Lean 4 kernel for tactic-level caching
- [ ] Cache eviction policy (LRU, max size)
- [ ] Cache warmup on CI for known-good merges
