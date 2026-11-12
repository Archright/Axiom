# Canonical AST Boundary

## Purpose

`tools/shared/canonical_ast.nim` provides a **version-independent AST adapter** that wraps `std/macros.NimNode` behind a stable canonical model (`CanonNode` / `CanonKind`). This document defines the boundary contract between the raw Nim compiler AST domain and downstream consumers (tools, `src/core/`, tests).

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Nim Compiler (Nim 2.2.10)                                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  std/macros.NimNode / PNode                           │  │
│  │  - Version-specific node kinds (nnkProcDef, nnkCall…) │  │
│  │  - Direct index-based child access                    │  │
│  │  - Magic procs (strVal, intVal, floatVal, repr)       │  │
│  └───────────────────┬───────────────────────────────────┘  │
│                      │ toCanon()                             │
│                      │ nimKindToCanon()                      │
│                      │ formatSourceSpan()                    │
├──────────────────────┼───────────────────────────────────────┤
│  tools/shared/canonical_ast.nim (Adapter Layer)             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  CanonKind* = enum                                    │  │
│  │    ckNone, ckEmpty, ckIdent, ckSym, … ckUnknown       │  │
│  │    (~57-63 kinds, version-independent surface)        │  │
│  │                                                       │  │
│  │  CanonNode* = object                                  │  │
│  │    kind*, name*, strVal*, intVal*, floatVal*,         │  │
│  │    sourceSpanRef*: string,                            │  │
│  │    children*: seq[CanonNode]                          │  │
│  │                                                       │  │
│  │  Public API (~15 functions):                          │  │
│  │    getNodeKind*, getNodeName*, getStringValue*,       │  │
│  │    getIntValue*, getFloatValue*, getChildCount*,      │  │
│  │    getChild*, getChildren*, extractProcName*,         │  │
│  │    extractParams*, extractBody*, walkDescendants*,    │  │
│  │    isOfType*, isIdentOrSym*, newNode*, newProc*,      │  │
│  │    extractCondition*, getRepr*                        │  │
│  └───────────────────┬───────────────────────────────────┘  │
│                      │                                      │
├──────────────────────┼───────────────────────────────────────┤
│  Consumers                                              │
│  ┌───────────────────┴───────────────────────────────────┐  │
│  │  tools/discover_test_debt.nim                         │  │
│  │  src/core/macros/enforce_linear.nim                   │  │
│  │  src/core/macros/best_effort.nim                      │  │
│  │  src/core/ir/ir_generator.nim                         │  │
│  │  tests/unit/test_canonical_ast_location.nim           │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Import Path Rules

### Nim Search Path Configuration

`config.nims` (line 7-8) adds both `src` and `tools` to the Nim search path:

```nim
switch("path", "src")
switch("path", "tools")
```

This means any `.nim` file in the project can import via either prefix:

```nim
import shared/canonical_ast   # resolves to tools/shared/canonical_ast.nim
import core/gate/gate_context # resolves to src/core/gate/gate_context.nim
```

### Import Encapsulation Gate

The `import_encapsulation_gate.nim` gate (`src/gate/runners/import_encapsulation_gate.nim`) enforces internal import boundaries. Key rules:

- `src/core/` files are **exempt** from encapsulation checks (line 35: `if filepath.startsWith("src/core/"): return true`)
- `tools/` is listed in `hubMapping` with exemptions for specific `core/` subpaths (gate_consts.nim line 56)
- `tools/shared/canonical_ast` is **not** in `InternalPaths` — it is an approved public utility

**Result**: `src/core/` files may freely `import shared/canonical_ast`. No import encapsulation violation will occur.

## Source Mapping Equivalence Contract

### What IS Guaranteed

| Aspect | Guarantee |
|--------|-----------|
| **Kind mapping** | Every `NimNodeKind` maps deterministically to exactly one `CanonKind` via `nimKindToCanon()` |
| **Semantic values** | `strVal`, `intVal`, `floatVal` are extracted faithfully from the source NimNode |
| **Tree structure** | Child count and order are preserved through `toCanon()` recursion |
| **Provenance** | `sourceSpanRef` carries `"file:line:col:kind"` when location info is available |
| **Determinism** | Same input NimNode → byte-for-byte identical CanonNode tree |

### What IS NOT Required

| Aspect | Not Required |
|--------|-------------|
| **Physical position identity** | `sourceSpanRef` is provenance-only; semantic comparison MUST NOT read this field (see `canonical_ast_identity.md`) |
| **NimNode API parity** | Consumers use CanonNode accessor functions, not direct NimNode indexing |
| **Version lock** | `CanonKind` enum absorbs future NimNode additions as `ckUnknown`; consumers never switch on raw `nnk*` |

### Provenance Field Semantics

`CanonNode.sourceSpanRef`:

- Format: `"filename:line:column:NimNodeKind"` (e.g., `"main.nim:42:8:nnkProcDef"`)
- Empty string when no location info: `li.line == 0 OR li.filename.len == 0`
- **Never part of identity or semantic equality** — purely for diagnostics/debugging
- Populated by `formatSourceSpan()` which reads `n.lineInfoObj` at conversion time

### Synthetic Node Handling

```
newNimNode(nnkEmpty) in macro context → gets VM creation-site line info (NOT empty)
parseStmt("")                       → filename=='' → formatSourceSpan returns ""
```

Test S1 (`test_canonical_ast_location.nim`) verifies this distinction explicitly.

## Conversion Pipeline

### `toCanon(n: NimNode): CanonNode`

```
Input:  NimNode (raw compiler AST)
Steps:
  1. kind   ← nimKindToCanon(n.kind)          # version-independent enum
  2. name   ← n.strVal if nnkIdent/nnkSym else ""
  3. strVal ← n.strVal for string literals
  4. intVal ← n.intVal for integer/char literals
  5. floatVal ← n.floatVal for float literals
  6. sourceSpanRef ← formatSourceSpan(n)       # provenance only
  7. children ← [toCanon(n[i]) for i in 0..n.len-1]
Output: CanonNode (stable value type)
```

### `formatSourceSpan(n: NimNode): string`

```
li ← n.lineInfoObj
if li.line == 0 OR li.filename.len == 0:
  return ""  # synthetic node
return li.filename & ":" & $li.line & ":" & $li.column & ":" & $n.kind
```

**Nim 2.2.10 quirk**: `newNimNode()` inside a macro assigns creation-site line info, so "no location" must be detected via zero line OR empty filename, not via constructor identity.

## Consumer Migration Pattern

When migrating a `src/core/` file from raw NimNode to canonical adapter:

1. **Add import**: `import shared/canonical_ast`
2. **Preserve NimNode for construction**: Macros that modify AST still need `newNimNode()`, `newTree()`, etc.
3. **Use CanonNode for analysis**: Kind checks, value extraction, tree traversal via accessor functions
4. **Bridge helpers**: Define local `canonKind(n: NimNode)` / `wrapNimNode(n: NimNode)` for compile-time conversion
5. **No behavioral change**: This is pure refactoring — IR output, diagnostics, and runtime behavior must remain identical

### Example: enforce_linear.nim migration

Before (raw NimNode):
```nim
proc hasConsumeCall(node: NimNode, tokenName: string): bool {.raises: [].} =
  case node.kind
  of nnkCall, nnkCommand:
    if node.len > 1:
      let callee = node[0]
      if callee.kind == nnkIdent and callee.strVal == "consume": ...
```

After (canonical adapter):
```nim
import shared/canonical_ast

proc hasConsumeCall(node: CanonNode, tokenName: string): bool {.noSideEffect.} =
  case getNodeKind(node)
  of ckCommand, ckCall:
    if getChildCount(node) > 1:
      let callee = getChild(node, 0)
      if getNodeKind(callee) == ckIdent and getStringValue(callee) == "consume": ...
```

## Testing Strategy

### S1: sourceSpanRef Dimension Verification

File: `tests/unit/test_canonical_ast_location.nim`

Four compile-time macro assertions:
1. Real proc node → non-empty `sourceSpanRef` ending with `"nnkProcDef"`
2. Synthetic node (`parseStmt("")`) → empty `sourceSpanRef`
3. Semantic fields deterministic regardless of `sourceSpanRef`
4. Children of real nodes carry non-empty `sourceSpanRef`

Build command:
```bash
nim c --hints:off --nimcache:/tmp/nimv2 --panics:on -r -o:/tmp/ws2_loc \
  tests/unit/test_canonical_ast_location.nim
```

Expected output: `S1 sourceSpanRef tests passed.`

### S2: Import Encapsulation Gate

Verify `src/core/` can import `shared/canonical_ast` without violation:

```bash
nim c --hints:off --nimcache:/tmp/nimv2_s2 -o:/tmp/ws2_s2_core \
```

Expected: exit code 0, no import encapsulation violations.

### S3/S4: Compilation Integrity

Each migrated file compiles independently:
```bash
nim c --hints:off --nimcache:/tmp/nimv2_s3 -o:/tmp/check_enforce_linear \
  src/core/macros/enforce_linear.nim

nim c --hints:off --nimcache:/tmp/nimv2_s4 -o:/tmp/check_best_effort \
  src/core/macros/best_effort.nim

nim c --hints:off --nimcache:/tmp/nimv2_s4b -o:/tmp/check_ir_generator \
  src/core/ir/ir_generator.nim
```

Expected: all exit code 0, no errors, no warnings.

## Related Specs

- `docs/spec/canonical_ast_identity.md` — PNode canonical hash contract (syntax domain)
- `docs/spec/pnode_nimnode_type_separation_quirk.md` — PNode vs NimNode type separation
- `docs/spec/nim_effect_system_quirks.md` — Nim effect system quirks relevant to adapter
- `tools/shared/canonical_ast.nim` — Implementation (SSOT)
- `tests/unit/test_canonical_ast_location.nim` — S1 verification test
