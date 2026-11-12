# VFS Hasher Quirks

## 1. Malebolgia SIGSEGV in parallelHash (2026-06-20)

**Symptom**: `gate_hook pre-commit` crashes with SIGSEGV (signal 11) during VFS hash stage.

**Root Cause**: Malebolgia's thread pool has a known bug in `alloc.nim addToSharedFreeList()` that causes SIGSEGV in heavily threaded code. The `try/except CatchableError, Defect` in the caller CANNOT catch OS-level signals — the process is killed before the handler runs.

**Fix**: Removed malebolgia dependency. `parallelHash` now delegates to sequential `hashFiles`. Pre-commit hook hashes ~100-500 changed files, completing in <2s sequentially.

**Decision**: Sequential-only hashing. The marginal speedup of parallel hashing does not justify the SIGSEGV risk and complexity. See AGENTS.md §0.2 (First-Principles Elegance).
