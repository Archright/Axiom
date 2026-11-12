# Canonical AST Identity Contract

## Purpose

`src/core/ast_kernel.nim` provides a deterministic, content-based identity primitive for Nim compiler ASTs (`PNode`). It enables structural equality checking and semantic deduplication without relying on source positions, parser transient metadata, or lexical form variations.

## Identity Hierarchy

- **PNode = Syntax Domain SSOT.** The parsed AST is the single source of truth for syntactic structure.
- **AST hash = Syntax Identity SSOT.** The canonical hash (`sha256:v2:nim-pnode-canonical-v2:<hex>`) is the content identity of the syntax domain. It is **not** business identity (which includes semantic types, symbol resolution, etc.).

## Ignored (Excluded from Identity)

| Element | Reason |
|---------|--------|
| Comments | Lexer-level; never appear as PNode children |
| Irrelevant whitespace | Lexer-level; never appear as PNode children |
| Source position (`n.info`, line, column) | Not semantically meaningful for content identity |
| Parser transient metadata | Not exposed in PNode fields |
| Literal lexical form (`0x1` vs `1`, `1'u8` vs `1`) | Semantic-value canonicalization collapses lexical variants |

## Preserved

| Element | How Captured |
|---------|-------------|
| Identifiers | `n.ident.s` for `nkIdent`; `n.sym.name.s` for `nkSym` (string only, no pointer/hash) |
| Literal semantic values | `intVal`, `floatVal`, `strVal`, `intVal` (char) — decoded/semantic values |
| Declarations | AST structure via node kind + children |
| Operators | Node kind (`nkInfix`, `nkPrefix`, etc.) |
| AST structure/ordering | Default child order preserved for all nodes |
| Imports | AST structure preserved |
| Pragmas | AST structure preserved |

## Ordering Rules

- **Default-ordered**: Statement lists, parameters, branches, declarations, imports preserve their original order.
- **Unordered allowlist**: Only `nkTableConstr` (table constructors) and `nkCurly` (set constructors) are order-independent. Their children are sorted by canonical serialized representation (string comparison) before hashing. **No hash/pointer/address is used for sorting.**
- **Ordered (not in allowlist)**: `nkTupleConstr`, `nkObjConstr`, and all other container nodes preserve child order.

## Literal Canonicalization Policy (Semantic-Value)

| Node Kind | Canonical Value |
|-----------|----------------|
| `nkIntLit..nkUInt64Lit` | `$n.intVal` — `0x1`, `0o1`, `1`, `1'u8` all become `"1"` |
| `nkFloatLit..nkFloat128Lit` | `$n.floatVal` |
| `nkStrLit..nkTripleStrLit`, `nkRStrLit` | `n.strVal` — decoded value (escape sequences resolved) |
| `nkCharLit` | `$n.intVal` — character code as decimal string |

## Parser Compatibility

- **Nim 2.2.10 fixed.** The AST structure and PNode field layout are tied to this compiler version.
- **Compiler upgrade → hash contract change.** If the Nim compiler version changes, the `CanonicalHashAlgorithm` constant and hash prefix version must be updated (e.g., `v2` → `v3`). This signals a migration boundary.

## Algorithm Identifier

`"nim-pnode-canonical-v2"` — the `v2` suffix indicates this is the second version of the canonicalization algorithm. Version increments signal contract changes (new node kinds handled, ordering rules changed, literal policy updated).

## Fail-Closed Behavior

- `canonicalizePNode(n: PNode): string` — the core canonical projection: recursively emits `$n.kind` + semantic leaf values (`n.ident.s`, literal values) joined by `|`, omitting `n.info`, `nkEmpty`, `nkCommentStmt`, `nkHiddenKinds`. Default-ordered with unordered allowlist `{nkTableConstr, nkCurly}` (stable-sorted on canonical repr).
- `parseSourceToPNode` returns `err` if parsing fails.
- `computeCanonicalAstHash` propagates the error — **no raw-text fallback**.
- This ensures that unparseable source never produces a spurious hash.
- (`serializeCanonicalPNode` is intentionally NOT a separate public primitive — `canonicalizePNode` already is the stable serialization contract; split it only if multiple consumers require raw canonical bytes.)

## Determinism Guarantees

- Same PNode → byte-for-byte identical canonical string → identical hash.
- No `HashMap`, `HashSet`, or non-deterministic iteration is used.
- All iterations follow either tree-child order (deterministic) or stable sort by canonical repr (deterministic).
- `NimVersion` is included in `buildEnvHash` (see `state_ledger.nim`) — compiler version changes are externally detectable.

## Related Specs

- `docs/spec/pnode_nimnode_type_separation_quirk.md` — PNode vs NimNode type separation
- `docs/spec/nim_effect_system_quirks.md` — Nim effect system quirks
- `docs/spec/state_ledger_architecture.md` — buildEnvHash and compiler version binding