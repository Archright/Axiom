# @axiom-constraint: Doc-Code Sync Enforcement Specification

> **Status**: **Historical** — the `@axiom-constraint` feature and its
> `src/core/axiom_contract.nim` module were **removed** via governance-driven
> erasure (commit `e5b5b36fc`). Design-by-contract is now provided by the
> 3-Layer Contract Architecture in `src/core/contracts/` (`requires`/`ensures`
> macros + `{.spec.}` pragma via `src/core/contracts/spec_binding_macro.nim`).
> The code examples below illustrate the removed API and are preserved for
> historical reference only.

## Overview

`@axiom-constraint` is a source-level annotation pattern that binds **code-level conditions** to **documentation references**, enforcing doc-code synchronization at compile time. It extends the existing `@axiom-hint` pattern (which binds Lean/SMT propositions) with a documentation-verification dimension.

## Relationship to Existing Patterns

| Pattern | Purpose | Layer |
|---------|---------|-------|
| `@axiom-hint` | Bind Lean/SMT proof hints to functions | Verification (Infrastructure) |
| `@axiom-constraint` | Bind code conditions to documentation | Documentation-Code Sync (Domain) |
| `axiomFeature` | Bind test files to `.feature` specs | Spec-Test Binding (Gate) |

## Annotation Format

```nim
# @axiom-constraint: <condition> [<reference>]
```

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `<condition>` | Yes | A human-readable condition expressing a code-level invariant |
| `[<reference>]` | Yes | A documentation reference in square brackets |

### Examples

```nim
# @axiom-constraint: result.len >= 0 [AGENTS.md §0.6]
func getItems*(s: seq[string]): seq[string] {.raises: [].} =
  result = s
```

```nim
# @axiom-constraint: depth >= 0 [docs/spec/bmc_core.md §3.1]
# @axiom-constraint: depth <= maxDepth [docs/spec/proof_budget_spec.md §2]
func computeDepth*(n, maxDepth: int): int {.raises: [].} =
  result = min(n, maxDepth)
```

## Usage

### Module-level enforcement

Add at the top of a module to validate all `@axiom-constraint` annotations in that file:

```nim
import core/axiom_contract

axiomContractEnforce(staticRead("this_module.nim"))
```

### Runtime query API

```nim
import core/axiom_contract

# Count annotations in a source file
let n = countConstraints(sourceText)

# Get annotations for a specific function
let constraints = getConstraintsForProc(sourceText, "myFunction")

# Human-readable summary
for c in constraints:
  echo constraintSummary(c)
```

## Validation Rules

| Rule | Severity | Description |
|------|----------|-------------|
| Non-empty condition | Compile error | Condition text must not be empty |
| Reference present | Compile error | A `[reference]` bracket must be present |
| No placeholder refs | Compile error | References must not be `TODO` or `FIXME` |
| Annotation near proc | Informational | The macro records which proc/func follows the annotation |

## Data Types

### `AxiomConstraint`

```nim
type
  AxiomConstraint* = object
    line*: int           # 1-based source line number
    condition*: string   # The constraint condition text
    reference*: string   # Documentation reference
    procName*: string    # Name of associated function (empty if none)
```

### `ConstraintParseResult`

```nim
type
  ConstraintParseResult* = object
    constraints*: seq[AxiomConstraint]
    errors*: seq[string]
```

## nimtry Integration

`@axiom-constraint` is designed to integrate with the nimtry unified architecture enforcement engine (`src/gate/nimtry/`).

### Proposed integration points

1. **`nimtryCheck()` macro extension**: Add a nimtry plugin that calls `axiomContractEnforce(staticRead(...))` for each checked file.

2. **Incremental cache**: nimtry's SHA256 cache (`.nimcache/nimtry/`) already tracks file hashes. The constraint validation result can be cached alongside, so unchanged files skip re-validation.

3. **Pre-commit gate**: In the incremental principle (AGENTS.md §2.6), only changed files are validated. A `constraint-gate` runner can check changed `.nim` files for valid `@axiom-constraint` annotations.

4. **Integration sketch**:

```nim
# In a nimtry plugin or gate runner:
import core/axiom_contract

proc checkConstraintsInFile*(filePath: string) =
  let source = readFile(filePath)
  let parsed = parseAxiomConstraints(source)
  for err in parsed.errors:
    echo "CONSTRAINT ERROR: ", filePath, ": ", err
    quit(1)
  for c in parsed.constraints:
    if c.procName.len == 0:
      echo "CONSTRAINT WARNING: ", filePath, ":", c.line,
           " annotation not associated with a function"
```

## Design Principles

- **Ideal**: Compile-time prevention of doc-code desync (AGENTS.md §0.2)
- **Elegant**: Uses Nim's macro system natively, no external dependencies
- **Fundamental**: No hardcoded exceptions; all annotations are uniform
- **Deterministic**: Same source text → same parse result every time

## File Locations

| File | Role |
|------|------|
| [REMOVED] `src/core/axiom_contract.nim` | Core parsing and compile-time enforcement — removed via governance erasure (see banner); replaced by `src/core/contracts/spec_binding_macro.nim` |
| `tests/unit/axiom_contract_test.nim` | Unit tests (positive + negative + edge) — removed with the feature |
| `docs/spec/axiom_constraint_spec.md` | This specification document |
