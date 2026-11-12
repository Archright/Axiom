# PNode char-literal & parseStringAST quirks

Status: documented 2026-08-04 (discovered while unblocking `ax prove`; fixes in `pnode_nav.nim`, `fixedpoint_engine.nim`).

## 1. `nkCharLit` stores its codepoint in `intVal`, not `strVal`

Nim's compiler AST stores character literals as integers. Per the official `doc/astspec.txt`:

```
' '   →  nnkCharLit(intVal = 32)
42    →  nnkIntLit(intVal = 42)
"a"   →  nnkStrLit(strVal = "a")
```

`TNode` uses a `case kind` layout: `nkCharLit..nkUInt64Lit` live in `intVal`; only `nkStrLit..nkTripleStrLit` live in `strVal`. Reading `.strVal` on an `nkCharLit` node raises `FieldDefect: field 'strVal' is not accessible for type 'TNode' using 'kind = nkCharLit'` — a non-catchable `Defect`, so a `try/except CatchableError` guard does not help and the process aborts.

### Correct extraction

```nim
of nkCharLit:
  result = $chr(int(node.intVal))
```

### Affected sites (fixed)

- `src/core/parsers/pnode_nav.nim:62` — `pNodeText` incorrectly grouped `nkCharLit` with `nkStrLit, nkTripleStrLit` and read `.strVal`. Fixed to read `intVal`.
- `src/verification/solver/fixedpoint_engine.nim:188` — `stmtText` read `.strVal` on `nkCharLit`. Fixed.

### Sites that already handled it correctly (reference)

- `src/core/ast_hash.nim:26` — `of nkCharLit..nkUInt64Lit: ... intVal`.
- `src/gate/nimtry/nimtry_extract_part1.nim:74` — `"'" & $(n.intVal.chr) & "'"`.

## 2. `parseStringAST` reports parse errors as `<string>(line, col)`

`src/core/parser_utils.nim:52` opens the compiler parser with `fakePath = AbsoluteFile("<string>")`. Any parse failure inside `parseStringAST` therefore prints `<string>(line, col) Error: ...` to stderr — the error message gives no filename, which made root-causing `bin/ax prove`'s `expected: ')', but got: ']'` failure (see §3) harder.

The topology scan parses the full file *content* (via `readFile` + `parseStringAST(content)`), so `line`/`col` refer to the file's lines even though the label says `<string>`.

## 3. Topology scan parses ALL git-tracked `.nim` files — orphan files can block `ax prove`

`enrichAxiomImplFlags` → `parseNimRes` parses every git-tracked `.nim` file (from `git ls-files`, ~1805). Files that are **never compiled by any build/test target** (orphan tests, e.g. `tests/test_tactic_solver.nim`, `tests/test_ir_generator.nim`) still participate in this scan. A latent syntax error in such a file — invisible to `nim c bin/ax` because the file is not in the import graph — aborts `ax prove` with Exit 1.

### Countermeasure

Any new `.nim` file (especially under `tests/` or `tools/`) must parse cleanly even if it is not wired into a build target. A cheap check: `nim c --hints:off --compileOnly <file>` or rely on `ax prove`'s topology scan (it will surface the error deterministically).
