# WP2 Ingress Path Comparison: Probe vs Engine

## Question

How do the probe path and the engine path differ in their handling of exported Nim proc names, and why does this divergence cause `decodedLength` to be dropped from the global symbol graph?

## Probe Path

**Entry**: `experiments/act2-wp2-subject-scoped-execution/wp1_ingress_probe.nim`

1. **Parse**: `parseStringAST` produces the AST for the subject source file.
2. **Name extraction** (`getProcName`, `wp1_ingress_probe.nim:72-85`):
   - Iterates over proc-defining nodes.
   - For `nkPostfix` nodes (exported procs with `*`): explicitly checks `if nameNode.len>1: pNodeText(nameNode[1])` — extracts the **second child** of the postfix node, which is the real proc name.
   - For `nkIdent` nodes (non-exported procs): extracts the identifier text directly.
3. **Canonicalization**: `pnodeToCanon` converts the extracted name to a canonical form.
4. **Obligation generation**: `convertFuncDefCanon` produces the verification obligation.

The nkPostfix handling at `wp1_ingress_probe.nim:72-85` ensures that exported procs like `decodedLength*` yield the name `"decodedLength"`, not `"*"`.

## Engine Path

**Entry**: `src/core/symbol_graph/global_symbol_graph_builder_part2.nim`

1. **Build**: `buildGlobalSymbolGraph` at `part2.nim:142` (called from `axiom_engine.nim:1052` via `global_symbol_graph.nim:44/83`).
2. **Find procs**: `findNodesP(ProcDefKinds)` locates all proc-definition nodes in the subject AST.
3. **Name extraction** (`part2.nim:212`):
   - `let nameNodeOpt = findFirstNodeP(node[0], {nkIdent})`
   - `findFirstNodeP` returns the **first** `nkIdent` descendant in document order.
   - For an exported proc, `node[0]` is `nkPostfix` with children `[nkIdent("*"), nkIdent("decodedLength")]`. The first `nkIdent` is `"*"`, so the extracted name is `"*"`.
   - For a non-exported proc, `node[0]` is `nkIdent` directly, so the name is extracted correctly.
4. **Qualified name**: `qualifiedName` combines module path + extracted name.
5. **Module symbols**: `moduleSymbols` inserts the symbol into the per-module contribution.
6. **Graph**: Symbols are assembled into the global symbol graph and written by `saveGlobalSymbolGraphCache` (part2.nim:350).

## Divergence Point

| Aspect | Probe (`wp1_ingress_probe.nim`) | Engine (`part2.nim`) |
|---|---|---|
| File | `experiments/act2-wp2-subject-scoped-execution/wp1_ingress_probe.nim` | `src/core/symbol_graph/global_symbol_graph_builder_part2.nim` |
| Line | 72-85 (`getProcName`) | 212 (`findFirstNodeP`) |
| nkPostfix handling | Explicit: `if nameNode.len>1: pNodeText(nameNode[1])` | None — falls through to `findFirstNodeP` which finds `"*"` first |
| nkIdent handling | Direct identifier text extraction | Direct via `findFirstNodeP` (works correctly) |
| Result for `decodedLength*` | `"decodedLength"` (correct) | `"*"` (wrong) |
| Result for `newAlphabet36` | `"newAlphabet36"` (correct) | `"newAlphabet36"` (correct) |

## AST Shape Difference for an Exported Proc

For `func decodedLength*(...)`:

- **AST node `node[0]`**: `nkPostfix`
  - Child 0: `nkIdent("*")` — the export marker
  - Child 1: `nkIdent("decodedLength")` — the real proc name

- **Probe** (`wp1_ingress_probe.nim:72-85`): sees `nkPostfix`, takes `nameNode[1]` → `"decodedLength"`
- **Engine** (`part2.nim:212`): calls `findFirstNodeP(node[0], {nkIdent})` → finds `nkIdent("*")` first → `"*"`

## Why newAlphabet36 Survives

`newAlphabet36` is **not exported** (no `*` marker). Its `node[0]` is `nkIdent` directly, not `nkPostfix`. Both the probe and the engine extract the name correctly because there is no export marker node in the way. `findFirstNodeP(node[0], {nkIdent})` on an `nkIdent` node returns that node itself, yielding `"newAlphabet36"`.

## Evidence Artifacts

1. **Incremental cache**: The module contribution for `stew/base36.nim` contains only `base36.*` and `base36.newAlphabet36` — `decodedLength` is absent. This proves the drop is in the builder, not downstream.
2. **Topology merkle**: Contains the real proc names (`decodedLength`, `encodedLength`, etc.), confirming the AST was parsed correctly and the names exist in the subject.
3. **Graph JSON** (`/tmp/wp0c_state/logs/global_symbol_graph.json`): Schema `axiom.global-symbol-graph.v1`, `symbolCount=333`, `edgeCount=0`. The `base36.*` entry is present; `base36.decodedLength` is absent.

## Conclusion

The probe path and the engine path diverge at the name-extraction step for exported procs. The probe's `getProcName` explicitly handles `nkPostfix` by extracting the second child, while the engine's `findFirstNodeP` does not account for the export marker and returns `"*"` instead of the real proc name. This causes all exported procs in a module to collapse to a single `module.*` graph entry, dropping the individual proc names from the symbol graph. The bug is general — it affects ALL exported procs in ANY subject, not just nim-stew or `decodedLength`.
