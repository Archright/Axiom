## Summary

Request a compile-time mechanism to register "canonical" constant values and detect duplicates across modules, enforcing Single Source of Truth (SSOT) for literals.

## Motivation

In large projects, magic numbers and string literals are often duplicated across modules:

```nim
# src/core/config.nim
const defaultTimeoutMs = 5000

# src/cli/commands/heal.nim
let timeout = 5000   # Should have imported config.defaultTimeoutMs
```

Current Nim provides `distinct` types to prevent accidental mixing of values (e.g., `Dollar` vs `Euro`), but there is no mechanism to enforce that a specific literal value is defined in exactly one place.

## Proposed Solutions

### Option A: `{.canonical.}` Pragma

Mark a constant as the canonical definition of a value. The compiler warns if the same literal appears elsewhere without referencing the canonical const:

```nim
const defaultTimeoutMs {.canonical: "timeout"} = 5000

# Elsewhere:
let timeout = 5000
# Warning: literal 5000 (tagged "timeout") should use config.defaultTimeoutMs
```

### Option B: Compile-Time Registry Macro

A macro that scans all modules at compile time and reports duplicates:

```nim
import std/macros

static:
  registerCanonical("timeout", 5000, "src/core/config.nim")
  registerCanonical("maxRetries", 3, "src/core/config.nim")
  # At end of compilation: report any 5000 or 3 found outside registered modules
```

### Option C: `distinct` with Literal Tag

Extend `distinct` to tag literal values, preventing silent duplication:

```nim
type TimeoutMs = distinct int
  ## Only assignable from canonical source or explicit cast

const defaultTimeoutMs: TimeoutMs = 5000.TimeoutMs
let timeout = 5000      # Error: cannot assign int to TimeoutMs
let timeout2 = 5000.TimeoutMs  # Error: 5000 is not the canonical TimeoutMs value
```

## Why Not Just External Tools?

We maintain an AST-based gate that extracts literal values from `PNode` trees. It works, but:
- It cannot distinguish legitimate local literals (e.g., `for i in 0..<10`) from SSOT violations.
- Any threshold or heuristic produces false positives.
- A language-native mechanism would be precise and zero-cost.

## Related

- `distinct` types (doc/manual.md) — prevent type-level mixing but not value-level duplication.
- `std/hashes` — could be used for literal fingerprinting, but not for cross-module registry.

No existing RFC or issue covers compile-time literal deduplication across modules.
