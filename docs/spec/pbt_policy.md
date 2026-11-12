# Property-Based Testing (PBT) Policy

> **SSOT for AFL-based fuzzing and PBT conventions in the Axiom project.**
>
> Referenced by: `AGENTS.md`

---

## 1. Purpose

Axiom's integrity engine must be robust against arbitrary inputs. Property-Based Testing (PBT) via AFL fuzzing ensures that core parsing, hashing, and verification logic maintains its invariants under adversarial conditions — not just hand-crafted test cases.

---

## 2. Invariants Under Test

Every fuzz gate MUST verify these core invariants:

| # | Invariant | Target Function | Property |
|---|-----------|----------------|----------|
| 1 | Parse safety | `parseInt` | Always returns integer or raises `ValueError` — no other exception type |
| 2 | Result type safety | `safeParseInt` | Always returns `Option[int]`, never crashes |
| 3 | Hash determinism | `hash()` | Output is always `sizeof(int)` bytes; same input → same output |
| 4 | JSON robustness | `parseJson` | Always returns `JsonNode` or raises `JsonParsingError` — never corrupts state |

### Invariant Extension

When adding new invariants:

1. Define the checker function in `tests/fuzz/fuzz_gate.nim`
2. Update this document's invariant table

---

## 3. AFL Integration

### 3.1 Compilation

```bash
# Standard build (unit-test mode)
nim c -d:release tests/fuzz/fuzz_gate.nim

# AFL-instrumented build
nim c -d:afl --cc:/path/to/afl-clang-fast tests/fuzz/fuzz_gate.nim
```

The `-d:afl` flag activates the `aflAssert` template which triggers `SIGABRT` on invariant violation, allowing AFL to capture the crashing input.

### 3.2 Running AFL

```bash
# 1. Generate corpus
nim c -r tests/fuzz/generate_fuzz_input.nim tests/fuzz/corpus/

# 2. Run AFL
afl-fuzz \
  -i tests/fuzz/corpus/ \
  -o tests/fuzz/findings/ \
  -t 1000 \
  -- bin/fuzz_gate
```

### 3.3 Corpus Management

| Path | Purpose |
|------|---------|
| `tests/fuzz/corpus/` | Seed corpus (generated + curated) |
| `tests/fuzz/findings/` | AFL output (crashes, hangs, queue) |
| `tests/fuzz/findings/crashes/` | Crash-inducing inputs |
| `tests/fuzz/findings/hangs/` | Timeout-inducing inputs |

Crash inputs MUST be triaged immediately. Each crash becomes a regression test.

---

## 4. Fuzz Input Generator

`tests/fuzz/generate_fuzz_input.nim` generates edge-case seeds:

| Category | Examples |
|----------|---------|
| Empty | `""` |
| Whitespace | `" "`, `"\t"`, `"\n"` |
| Numeric | `"0"`, `"-1"`, `"2147483647"`, `"99999999999999999999"` |
| Special chars | `"!"`, `"@"`, `"{"`, `"}"`, `"\\"` |
| JSON edge | `"null"`, `"{"`, `"[1,2,3"`, `"undefined"` |
| Long strings | 256B, 1KB, 4KB, 10KB of repeated chars |
| Unicode | null byte, CJK, emoji, UTF-8 BOM |
| Boundary | embedded nulls, CRLF, bare CR |

To add new categories, add a generator function and call it from `generateCorpus()`.

---

## 5. nimtry Gate Integration (Inactive)

PBT nimtry queries were previously registered via a dedicated queries module that has since been removed. The four L2 gate queries (`pbt-infrastructure`, `pbt-invariant-coverage`, `pbt-afl-assertion`, `pbt-directory-convention`) are no longer active.

If PBT gate enforcement is needed again, implement a new query module in `src/gate/nimtry/` following the existing query registration pattern in `nimtry_query.nim`.

---

## 6. Adding New Invariants

### Checklist

1. **Define checker function** in `tests/fuzz/fuzz_gate.nim`
   - Function signature: `func myInvariant*(input: string): bool`
   - Returns `true` if invariant holds
2. **Add to `runFuzzGate`** with `aflAssert(myInvariant(input))`
3. **Update this document** invariant table (§2)
4. **Regenerate corpus** if new edge cases are needed

### Naming Convention

- Checker functions: `<concept>Invariant` (e.g., `parseIntInvariant`)
- Templates: `aflAssert(condition)` or `aflAssert(condition, message)`

---

## 7. CI Integration

```yaml
# In CI pipeline (pre-push gate):
- name: PBT gate
  run: |
    nim c -r tests/fuzz/generate_fuzz_input.nim
    src/gate/nimtry/nimtry_cli.nim tests/fuzz/fuzz_gate.nim
    # AFL fuzzing with timeout (CI-friendly short run)
    timeout 60 afl-fuzz -i tests/fuzz/corpus/ -o /tmp/afl_out -- tests/fuzz/fuzz_gate || true
    # Check for crashes
    test ! -d /tmp/afl_out/default/crashes || exit 1
```

---

## 8. Relationship to Other Gates

| Gate | Scope | Overlap |
|------|-------|---------|
| `nimtry` | Static architecture principles | PBT queries are a subset of nimtry L2 |
| `procedure-gate` | BDD/feature spec binding | PBT is orthogonal to spec binding |
| `nim check` | Type correctness | PBT validates runtime properties |
| AFL fuzzing | Adversarial input coverage | Supplements unit tests |

PBT does NOT replace unit tests or integration tests. It complements them by exploring the input space exhaustively.
