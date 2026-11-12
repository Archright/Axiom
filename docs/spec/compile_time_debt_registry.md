# Compile-Time Debt Registry Self-Injection

> **Status**: Design spec — NOT implemented (as of 2026-08-02). The macro
> self-injection approach below was not adopted. The active debt pipeline remains
> `tools/debt_registry_gen.nim` (external `{.axiomDebt.}` pragma scanner, see
> Migration Path below) + `tools/debt_engine.nim --codegen` →
> `src/generated/debt_constants.nim`.
> **Date**: 2026-07-07

---

## Problem

The current debt registry relies on `tools/debt_registry_gen.nim`, an external
scanner that re-parses every `.nim` source file via a comment/string-aware state
machine (`gate/lib/debt_scanner`). This approach has three structural defects:

1. **Lost metadata**: The scanner extracts `file` and `line` from source text via
   heuristic line counting, but legacy entries migrated from markdown retain
   sentinel values (`"N/A (legacy import)"`, `line: 0`, empty `declName`). The
   scanner cannot retroactively recover the original author intent.

2. **False-positive surface**: `LIM-2026-07-06-006` documents that extremely
   unusual comment nesting may produce false-positive pragma matches because the
   scanner is not a full Nim parser.

3. **gorge() / external process coupling**: Any future scanner improvement that
   uses `gorge()` or subprocess calls violates the `gorge() = 0` compile-time
   purity constraint (AGENTS.md §4 GUARDIAN).

---

## Solution

A macro-based self-injection pattern using Nim's `instantiationInfo()` builtin
and `{.compileTime.}` mutable accumulator. Each `{.axiomDebt.}` pragma captures
its own file, line, and declaration name at compile time — zero external process
calls, zero heuristic parsing.

---

## Mechanism

### 1. Compile-Time Registry Accumulator

```nim
## Proposed module: debt_registry_inject.nim (design only — not implemented)

import std/macros
import std/[json, os, strutils]

type
  DebtRegistryEntry* = object
    id*: string
    category*: string
    impact*: string
    file*: string
    line*: int
    declName*: string

# Compile-time mutable accumulator — populated during macro expansion,
# consumed during final compilation pass.
var debtRegistry {.compileTime.}: seq[DebtRegistryEntry]
```

### 2. The `axiomDebt` Macro

```nim
macro axiomDebt*(id: static[string],
                 category: static[string] = "",
                 impact: static[string] = "Medium"): untyped =
  ## Attach a debt tracking entry to the enclosing declaration.
  ## Captures file + line via instantiationInfo() at compile time.
  ##
  ## Usage:
  ##   {.axiomDebt: ("DEBT#100", "Code Complexity", "High").}
  ##   func legacyHelper(x: int): int = x + 1

  let info = instantiationInfo()  # captures file + line at compile time

  # Accumulate into compile-time registry
  debtRegistry.add(DebtRegistryEntry(
    id: id,
    file: info.filename,
    line: info.line,
    category: category,
    impact: impact
  ))

  # Return empty statement — pragma is metadata-only, emits no runtime code
  result = newStmtList()
```

**Key properties**:
- `instantiationInfo()` returns the exact file path and line number where the
  pragma appears — no heuristic parsing needed.
- `{.compileTime.}` var is never emitted into the binary — zero runtime cost.
- The macro returns `newStmtList()` (empty AST node) — it is pure metadata,
  producing no runtime code.
- `gorge() = 0`: No external process calls whatsoever.

### 3. Declaration Name Extraction

Unlike the external scanner which must search nearby lines for `proc`/`func`
keywords, the macro operates inside the compiler's AST. The declaration name
can be extracted by inspecting the pragma's parent context:

```nim
macro axiomDebt*(id: static[string],
                 category: static[string] = "",
                 impact: static[string] = "Medium"): untyped =
  let info = instantiationInfo()

  # The pragma is placed before a declaration. The compiler resolves
  # the parent declaration's name. For now, we capture it from the
  # calling context — the pragma's placement site.
  # Future enhancement: walk `callsite()` parent node for declName.

  debtRegistry.add(DebtRegistryEntry(
    id: id,
    file: info.filename,
    line: info.line,
    category: category,
    impact: impact
  ))

  result = newStmtList()
```

> **Note**: Nim's macro system places `{.pragma.}` on the declaration that
> follows. The `declName` field may remain empty in Phase 1 and be populated
> in a future iteration using AST parent introspection.

### 4. Compile-Time Serialization

At final compilation, the accumulated registry is serialized to
`data/debt_registry.json` via a compile-time `static:` block. This replaces the
external `debt_registry_gen.nim` tool.

```nim
## Proposed module: debt_registry_emit.nim (design only — not implemented)
##
## Import this module in the root compilation unit to trigger registry emission.

import std/[json, os, strutils]

proc emitDebtRegistry*(entries: seq[DebtRegistryEntry]) =
  ## Serialize accumulated debt entries to JSON.
  ## Called at compile time from the root module.
  var root = newJObject()
  root["version"] = newJInt(3)  # v3: compile-time injected
  root["scanner"] = newJString("compile-time macro (axiomDebt)")
  root["entryCount"] = newJInt(entries.len)

  var entriesArr = newJArray()
  for entry in entries:
    var obj = newJObject()
    obj["id"] = newJString(entry.id)
    obj["category"] = newJString(entry.category)
    obj["impact"] = newJString(entry.impact)
    obj["file"] = newJString(entry.file)
    obj["line"] = newJInt(entry.line)
    obj["declName"] = newJString(entry.declName)
    obj["status"] = newJString("open")
    obj["source"] = newJString("compile-time")
    entriesArr.add(obj)

  root["entries"] = entriesArr

  let outputPath = "data/debt_registry.json"
  let content = pretty(root) & "\n"

  # Idempotent write — skip if content unchanged
  if fileExists(outputPath):
    try:
      let existing = readFile(outputPath)
      if existing == content:
        return
    except IOError: discard

  createDir(outputPath.parentDir())
  writeFile(outputPath, content)
```

**Integration point**: The root compilation unit (e.g., `src/api.nim` or the
CLI main) imports this module and calls `emitDebtRegistry` in a `static:` block:

```nim
static:
  emitDebtRegistry(debtRegistry)
```

This runs exactly once at final compilation, after all `{.axiomDebt.}` pragmas
have been expanded.

---

## Reference Pattern: `src/core/registry_macro.nim`

The existing `injectRegistry` macro in `src/core/registry_macro.nim` demonstrates
the compile-time registry bake pattern:

1. `walkDirRec(srcDir)` — discover all `.nim` files at compile time
2. `staticRead(filePath)` — read source content without I/O
3. String scanning for pragma patterns — extract metadata
4. Build `nnkConstSection` AST — emit a baked const table
5. Zero runtime disk I/O — everything in-memory

The new debt registry inverts this: instead of scanning files at compile time,
each declaration self-registers via the macro. This is strictly more accurate
because `instantiationInfo()` provides the compiler's own file/line resolution,
eliminating the need for heuristic line counting.

---

## Migration Path

### Phase 0: Parallel Operation (current)

- `tools/debt_registry_gen.nim` remains the active scanner.
- `data/debt_registry.json` v2 format is produced by the scanner.
- No source files use `{.axiomDebt.}` pragma yet.

### Phase 1: First Pragma Adoption

- The first `{.axiomDebt.}` pragma is added to an actual declaration in `src/`.
  **Activation trigger**.
- The macro accumulates the entry at compile time.
- The compile-time emitter writes `data/debt_registry.json` v3.
- Legacy entries (DEBT#001–DEBT#261) are preserved as `source: "compile-time"`
  historical records.

### Phase 2: Scanner Decommission

- Once all active debt entries have `{.axiomDebt.}` pragmas, `debt_registry_gen.nim`
  is deleted.
- `docs/DEBT_REGISTRY.md` is regenerated from the compile-time JSON.
- `gate/lib/debt_scanner` is removed.

---

## Backward Compatibility

| Concern | Resolution |
|---------|-----------|
| Legacy DEBT#001–#261 entries | Preserved in v3 JSON with `source: "compile-time"` |
| `docs/DEBT_REGISTRY.md` | Regenerated from v3 JSON by the emitter |
| `debt_registry_gen.nim` | Kept during Phase 0–1; deleted in Phase 2 |
| `gate/lib/debt_scanner` | Kept during Phase 0–1; deleted in Phase 2 |

---

## Constraints

1. **gorge() = 0**: The entire mechanism uses only `instantiationInfo()`,
   `{.compileTime.}` vars, and `static:` blocks. No external process calls.
2. **Zero runtime cost**: The macro emits `newStmtList()` (empty AST). The
   `{.compileTime.}` var is erased during code generation.
3. **Deterministic output**: Same source → same registry JSON (sorted by ID).
4. **Idempotent write**: Compile-time emitter compares content before writing.
5. **AGENTS.md §4 GUARDIAN compliance**: Pure Nim macro, no side effects,
   no external tools, no hardcoded exceptions.

---

## Open Questions

1. **Declaration name resolution**: Can Nim macros reliably extract the
   parent declaration's name from the pragma attachment site? Requires
   prototyping with `callsite()` or AST parent walking.
2. **Incremental compilation**: Will Nim's incremental compilation correctly
   update the `{.compileTime.}` accumulator when only one file changes?
   May require a full recompilation to regenerate the registry.
3. **File path normalization**: `instantiationInfo()` returns absolute paths.
   Should the emitter normalize to project-relative paths (e.g., strip the
   project root prefix)?
