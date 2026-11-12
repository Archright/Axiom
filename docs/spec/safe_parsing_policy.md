# Axiom Safe Parsing Policy

> SSOT for compile-time debt prevention in parsing operations.

## Overview

Axiom enforces safe parsing practices at compile time using custom pragmas defined in `src/core/axiom_pragmas.nim`. This prevents common technical debt patterns from entering the codebase.

## Enforcement Rules

### 1. Safe Parse Enforcement (`axiomSafeParse`)

**Rule**: Use `safeParseInt`/`safeParseFloat` instead of `parseInt`/`parseFloat`.

**Rationale**: 
- `parseInt`/`parseFloat` raise `ValueError` on invalid input
- Nim official: "exceptions should be raised in exceptional cases" at I/O boundaries
- `safeParseInt`/`safeParseFloat` return `Result[T, string]` for explicit error handling

**Example**:
```nim
import core/safe_parsers

# ❌ Bad: raw parseInt (raises ValueError)
let value = parseInt("123")

# ✅ Good: safeParseInt (returns Result)
let result = safeParseInt("123")
if result.isOk:
  let value = result.get
else:
  echo "Parse error: ", result.error
```

**Enforcement**: `axiomSafeParse` macro detects raw `parseInt`/`parseFloat` calls and raises compile-time error.

#### 1a. Consumption contracts: `safeParseInt` (prefix) vs `strictParseInt` (whole-string)

`safeParseInt` wraps `parseutils.parseInt`, whose official contract is a
**consumed-length return value** ("Result is the number of processed chars
or 0") — so a prefix parse succeeds: `"1abc" -> ok(1)`. This prefix
semantics is the broad-consumer contract of `safeParseInt` and must not be
tightened in place.

Callers that need the `strutils.parseInt` whole-string contract (success
only when the entire string is consumed — trailing garbage rejected) must
use `strictParseInt`:

```nim
import core/parsers/safe_parsers

let prefix = safeParseInt("1abc")   # ok(1)
let whole = strictParseInt("1abc")  # err("invalid integer: 1abc")
```

Rule: substituting `strutils.parseInt` with `safeParseInt` at a call site
is a silent semantics change whenever the input may carry trailing
characters (constants parsed out of overlay/RHS strings, binding values,
URL fragments). Those sites require `strictParseInt` (regression:
commit f9305a902, `evalLinearRhs("e - 1abc", "e", 4)` -> `some(3)`).

### 2. Strong Hash Enforcement (`axiomStrongHash`)

**Rule**: Use `checksums/sha2` instead of `checksums/md5` or `std/sha1`.

**Rationale**:
- MD5 is cryptographically broken since 2005
- SHA-1 is broken for signatures
- SHA-256 provides adequate security for content-addressed storage

**Example**:
```nim
import checksums/sha2

# ❌ Bad: weak hash
import checksums/md5
let hash = getMD5(data)

# ✅ Good: strong hash
var hasher = initSha_256()
hasher.update(data)
let hash = $hasher.digest()
```

**Enforcement**: `axiomStrongHash` macro detects weak hash imports and raises compile-time error.

### 3. Acyclic Enforcement (`axiomAcyclic`)

**Rule**: Add `{.acyclic.}` to non-cyclic `ref object` types.

**Rationale**:
- ORC cycle collector runs on all `ref object` types by default
- `{.acyclic.}` optimizes away cycle detection for types without self-references
- AGENTS.md §0.6a: "ALL non-cyclic `ref object` MUST have `{.acyclic.}`"

**Example**:
```nim
# ❌ Bad: missing {.acyclic.}
type
  MyObj = ref object
    data: string

# ✅ Good: {.acyclic.} present
type
  MyObj {.acyclic.} = ref object
    data: string
```

**Enforcement**: `axiomAcyclic` macro warns on `ref object` without `{.acyclic.}` pragma.

## Integration with nimtry

The `nimtry` architecture gate (implemented in `src/gate/nimtry/nimtry_cli.nim`,
dispatched from `src/gate/in_process_gates.nim`) validates architecture rules at
compile time. An earlier `nimtry_plugin.nim` template (removed) used to call
`axiomEnforceAll()` to validate all rules.

## References

- Context7: Nim Official Manual - compile-time assertions, custom pragmas
- AGENTS.md §0.6a - Static First Enforcement
- AGENTS.md §0.2 - First-Principles Elegance
- `src/core/parsers/safe_parsers.nim` - Safe parse wrappers
- `docs/DEBT_REGISTRY.md` - DEBT#089, DEBT#090, DEBT#091
