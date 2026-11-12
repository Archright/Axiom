# WP2 Ingress Root-Cause Analysis: decodedLength Dropped from Global Symbol Graph

## Question

Why does the Axiom engine's global symbol graph builder drop the exported proc `decodedLength` from `stew/base36.nim` while the probe path correctly finds it, and what is the precise AST-level mechanism of the drop?

## Context

- **EXPERIMENT_ID**: `act2-wp2-subject-scoped-execution`
- **Subject**: `nim-stew@c75502c`
- **Axiom**: `@f7dd583ca`
- **Run args**: `--project . --limit 1 --target decodedLength`
- **AXIOM_STATE_DIR**: `/tmp/wp0c_state`
- **Subject under test**: `nim-stew` (Nim stew library), specifically `stew/base36.nim`

## Scope

Localization only — no code changed in the subject, Axiom, or any protected file. The scope is restricted to identifying the root cause of the name-extraction drop in the engine's symbol-graph builder.

## Canonical Builder Proof

### Call Chain

1. `axiom_engine.nim:1052` — `loadOrBuildGlobalSymbolGraph(cwd)` where `cwd` = subject dir when `--project` is set.
2. `global_symbol_graph.nim:44/83` — `buildGlobalSymbolGraph(repoRoot, freezeGraphCache)`
3. `src/core/symbol_graph/global_symbol_graph_builder_part2.nim:142` — `buildGlobalSymbolGraph` (canonical builder entry).

### Artifact Writer

- `saveGlobalSymbolGraphCache` at `part2.nim:350`
- Output path: `AXIOM_STATE_DIR/logs/global_symbol_graph.json`
- Confirmed on disk at `/tmp/wp0c_state/logs/global_symbol_graph.json`
- Schema: `axiom.global-symbol-graph.v1`
- `symbolCount=333`, `edgeCount=0`

### Executed Branch

The incremental cache branch ran (not a full rebuild). The module contribution for `stew/base36.nim` in the cache contains only `base36.*` and `base36.newAlphabet36` — `decodedLength` is absent. The `topology_merkle` has the real names (`decodedLength`, etc.), proving the drop occurs in the builder (`part2`), not downstream.

## decodedLength vs newAlphabet36 Evidence Table

| file:line | AST node[0] kind | export marker presence | normalized name | qualified name | graph insertion | reason |
|---|---|---|---|---|---|---|
| part2.nim:212 (engine) | `nkPostfix` | yes (`*`) | `"*"` (wrong) | `stew/base36.nim::*` → dedups to `base36.*` | `base36.*` (skProc) | `findFirstNodeP(node[0], {nkIdent})` returns the first nkIdent descendant, which is `"*"` in the nkPostfix node |
| part2.nim:212 (engine) | `nkIdent` | no | `"newAlphabet36"` (correct) | `stew/base36.nim::newAlphabet36` | `base36.newAlphabet36` | node[0] is nkIdent directly; findFirstNodeP returns `"newAlphabet36"` correctly |
| wp1_ingress_probe.nim:72-85 (probe) | `nkPostfix` | yes (`*`) | `"decodedLength"` (correct) | `stew/base36.nim::decodedLength` | obligation generated | explicit nkPostfix handling: `if nameNode.len>1: pNodeText(nameNode[1])` |
| wp1_ingress_probe.nim:72-85 (probe) | `nkIdent` | no | `"newAlphabet36"` (correct) | `stew/base36.nim::newAlphabet36` | obligation generated | nkIdent handled directly |

## H1..H7 Disposition Table

| H | Disposition | Evidence |
|---|---|---|
| H1 typedesc param handling | REJECTED | typedesc is ordinary param; bug is export-marker name extraction |
| H2 generic/type-bound symbol handling | REJECTED | neither proc has generic params; node[1] is nkEmpty |
| H3 overload/name normalization | REJECTED | issue is name extraction, not dedup normalization |
| H4 AST preprocessing node loss | REJECTED | findNodesP finds all procs; decodedLength IS found but name mis-extracted |
| H5 graph builder path != probe path | ACCEPTED | probe getProcName handles nkPostfix; engine findFirstNodeP does not |
| H6 eligibility/filtering drop | REJECTED | base36.* present proves base36.nim parsed+indexed; drop is in name extraction |
| H7 config/execution-context | REJECTED | incremental cache shows wrong builder output; fresh build same result |

## Exact Drop-Site

**File**: `src/core/symbol_graph/global_symbol_graph_builder_part2.nim`
**Line**: 212

```nim
let nameNodeOpt = findFirstNodeP(node[0], {nkIdent})
```

`findFirstNodeP` returns the **first** `nkIdent` descendant. For an **exported** Nim proc like `func decodedLength*(...)`, the AST node `node[0]` is `nkPostfix` with children `[nkIdent("*"), nkIdent("decodedLength")]`. `findFirstNodeP` traverses the tree in document order and encounters `nkIdent("*")` first, so it returns `"*"`. The extracted name is `"*"`, and the qualified name becomes `stew/base36.nim::*`. All exported procs in `base36.nim` (`encodedLength`, `decodedLength`, `encode`, `decode`) collapse to the same qualified name `stew/base36.nim::*` and dedup into the single graph entry `base36.*` (skProc). The real proc names are lost.

For non-exported `newAlphabet36` (no `*` marker), `node[0]` is `nkIdent` directly, so `findFirstNodeP` returns `"newAlphabet36"` correctly.

## Probe vs Engine Divergence

- **Probe path** (`experiments/act2-wp2-subject-scoped-execution/wp1_ingress_probe.nim:72-85`, function `getProcName`): explicitly handles `nkPostfix` — `of nkPostfix: if nameNode.len>1: pNodeText(nameNode[1])`. This extracts the real proc name (`decodedLength`) from the second child of the postfix node.
- **Engine path** (`part2.nim:212`): uses `findFirstNodeP(node[0], {nkIdent})` which does **NOT** handle `nkPostfix`. It finds the first `nkIdent` descendant, which is the `"*"` export marker, not the proc name.

**Divergence point**: `part2.nim:212` (engine) vs `wp1_ingress_probe.nim:72-85` (probe). This is why the probe found `decodedLength` but the engine graph dropped it.

## Classification

**Incomplete** — This is a general symbol-ingress name-extraction bug, not a typedesc issue. The bug affects ALL exported procs in ANY external subject (and any Axiom-internal exported proc too). It is not specific to nim-stew or to `decodedLength`.

## Minimal-Change Proposal

**NOT APPLIED** — code changes are explicitly forbidden in this localization pass.

At `part2.nim:212`, handle `nkPostfix` by extracting the real name (`node[0][1]` or `nameNode[1].ident.s`) before falling back to `findFirstNodeP`, mirroring `wp1_ingress_probe.nim:72-85` `getProcName`. This is generic external-subject support, not a nim-stew-specific workaround.

## No-Code-Change Confirmation

No source file, protected file, or subject file was modified during this analysis. All findings are based on read-only inspection of existing artifacts (graph JSON, incremental cache, topology merkle, source code at the identified lines).

## Non-Conclusions

- The probe's `getProcName` is not itself verified as correct for all AST shapes — only that it handles `nkPostfix` where the engine does not.
- The fix proposal has NOT been implemented or tested.
- Whether `edgeCount=0` in the graph artifact is a separate issue or a consequence of the name-collision is not determined here.

## Next Experiment

1. Apply the minimal change at `part2.nim:212` to handle `nkPostfix` (extract `node[0][1]` before `findFirstNodeP` fallback).
2. Re-run the engine with `--project . --limit 1 --target decodedLength`.
3. Verify that `decodedLength` appears in the global symbol graph with the correct qualified name `stew/base36.nim::decodedLength`.
4. Confirm that `encodedLength`, `encode`, and `decode` also appear correctly (all exported procs in base36.nim).
5. Re-run the full verification scope to confirm no regressions.
