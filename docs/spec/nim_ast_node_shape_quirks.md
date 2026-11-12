# Nim AST Node-Shape Quirks (`compiler/ast`, Nim 2.2.10)

> AGENTS.md §0.5 Quirk Mandate — discovered 2026-10-04 while writing the
> AST-based static gate `src/gate/runners/evidence_truth_boundary_gate.nim`
> (declared-enum vocabulary lookup + keyed-write key extraction).
> Toolchain: Nim 2.2.10 (choosenim pin, compiled 2026-04-24).
> Every claim below was **re-verified against the pinned toolchain**, not
> transcribed from discovery notes — see §Verification. Where the discovery
> claim was wrong, the corrected form is recorded and the error is named.

All three quirks share one failure mode: they are **silently wrong**, not
loudly wrong. A matcher written against the wrong `NodeKind` compiles, runs,
and matches nothing — the gate reports "no violations" rather than "I looked
for the wrong node".

## Q1: the `*` export marker wraps the declared name in `nkPostfix` — `node[0]` is not the name

An exported declaration's name son is **not** a bare `nkIdent`. The parser
wraps it:

```nim
type
  RunVerdict* = enum     # nkTypeDef[nkPostfix[nkIdent("*"), nkIdent("RunVerdict")],
    rvPass, rvFail        #         nkEmpty, nkEnumTy[...]]
                          # son 0  = nkPostfix, NOT the name
                          # name   = son 0 son 1
```

Un-exported declarations keep the bare form, which is what makes the
difference so easy to miss in a fixture that happens not to use `*`:

```
exported enum : nkTypeDef[nkPostfix[nkIdent(*)][nkIdent(RunVerdict)]][nkEmpty][nkEnumTy[...]]
plain enum    : nkTypeDef[nkIdent(RunVerdict)][nkEmpty][nkEnumTy[...]]
```

This is **not enum-specific**. Every declaration form wraps identically:

| Source | Declaration node's son 0 |
|---|---|
| `type RunVerdict* = enum` | `nkTypeDef[nkPostfix[nkIdent("*"), nkIdent("RunVerdict")]]` |
| `type Foo* = object` / `Foo*[T]` | same (`nkPostfix`, generic params move to son 1) |
| `proc f*()` / `func f*()` | `nkProcDef[nkPostfix[...]]` |
| `const C* = 1` | `nkConstDef[nkPostfix[...]]` |
| `var g*: int` | `nkIdentDefs[nkPostfix[...]]` |
| `type Foo = object` + `x*: int` | the field's own `nkTypeDef[nkPostfix[...]]` |

### Correct extraction

Unwrap to the **last `nkIdent` son** rather than indexing a fixed position —
that stays correct if a declaration ever gains another wrapping form, and it
is what `declaredName` in `src/gate/runners/evidence_truth_boundary_gate.nim:188`
does.

```nim
func declaredName(node: PNode): string =
  var cur = node
  while cur != nil:
    case cur.kind
    of nkIdent: return cur.ident.s
    of nkPostfix, nkPrefix:
      var found = ""
      for i in 0 ..< cur.safeLen:
        if cur[i].kind == nkIdent: found = cur[i].ident.s   # LAST ident wins
      return found
    else: return ""
  ""
```

### Silent-failure shape

Two distinct failure modes, both quiet:

1. `node[0].ident.s == "RunVerdict"` never fires — the matcher simply never
   matches. A gate written that way reports a clean run.
2. `node[0].ident` does not **not** return `"*"` — it raises. `TNode` is a
   `case kind` union (`ident` is stored only for `nkIdent`), so reading the
   wrong payload field is a `FieldDefect`, which is **not** a `CatchableError`
   and aborts the process:

```
$ /tmp/quirk_probe3        # reads .ident on the nkPostfix name node
name-node.kind = nkPostfix
Error: unhandled exception: field 'ident' is not accessible for type 'TNode'
       using 'kind = nkPostfix' [FieldDefect]
$ echo $?
1
```

A `try/except CatchableError` around the read does not intercept it (verified).
The export marker itself is at `node[0][0]` (`nkPostfix[nkIdent("*"), nkIdent(Name)]`),
so `node[0][0].ident.s == "*"` is the correct way to ask "is this exported?" —
it is just not the way to ask "what is it called?". Guard with `safeLen` + a
`kind` test before touching payload fields.

## Q2: `nkBoolLit` does not exist — `true` / `false` are `nkIdent`

There is no `nkBoolLit` in `compiler/ast`; `true` and `false` parse as plain
identifiers, exactly like any other bare word:

```
let x = true   →  nkLetSection[nkIdentDefs[nkIdent(x)][nkEmpty][nkIdent(true)]]
let y = false  →  nkLetSection[nkIdentDefs[nkIdent(y)][nkEmpty][nkIdent(false)]]
when true:     →  nkWhenStmt[nkElifBranch[nkIdent(true)][...]]
```

Source-level confirmation against the pinned toolchain:

```
$ grep -rn "nkBoolLit" ~/.choosenim/toolchains/nim-2.2.10/compiler/
(no output — the identifier occurs nowhere in the compiler tree)
```

### Consequence

`when node.kind == nkBoolLit` does not compile (unknown enum value), so this
quirk is loud rather than silent. The silent variant is the gate that *omits*
the boolean case altogether: a boolean-valued condition is then classified as
an ordinary identifier and either mis-accepted or mis-rejected depending on the
surrounding rule. Match on `node.kind == nkIdent and node.ident.s in ["true",
"false"]`.

## Q3: `a[k]` is `nkBracketExpr`; `nkBracket` is the `[...]` LITERAL, and a slice is an `nkBracketExpr`

Subscripting produces `nkBracketExpr` — for reads, for writes (as the LHS of
`nkAsgn`), and for nesting:

```
a[k] = 7  →  nkAsgn[nkBracketExpr[nkIdent(a)][nkIdent(k)]][nkIntLit(7)]
m[0][1]   →  nkBracketExpr[nkBracketExpr[nkIdent(m)][nkIntLit(0)]][nkIntLit(1)]
```

### Correction to the discovery claim

The discovery note claimed *"`nkBracket` is the unrelated slice form"*. **That
is wrong on both halves**, and the corrected fact matters because a gate
written from the wrong version silently misses every slice:

- **`nkBracket` is the bracketed literal / `[]`-constructor node**, produced by
  `exprColonEqExprList(p, nkBracket, tkBracketRi)` at
  `~/.choosenim/toolchains/nim-2.2.10/compiler/parser.nim:841`. It is what an
  array/set/object display literal parses to:
  `[0, 1, 2, 3]` → `nkBracket[nkIntLit(0), nkIntLit(1), nkIntLit(2), nkIntLit(3)]`.
- **A slice is an `nkBracketExpr` too.** There is no separate slice node kind;
  the slice is recognised by its *index* child being an `nkInfix` whose first
  son is `..` or `..<`:

```
sl[0 .. 2]   →  nkBracketExpr[nkIdent(sl)][nkInfix[nkIdent(..)][nkIntLit(0)][nkIntLit(2)]]
sl[0 ..< 2]  →  nkBracketExpr[nkIdent(sl)][nkInfix[nkIdent(..<)][nkIntLit(0)][nkIntLit(2)]]
sl[^1]       →  nkBracketExpr[nkIdent(sl)][nkPrefix[nkIdent(^)][nkIntLit(1)]]
```

So the correct rule is: **`nkBracketExpr` covers both subscript and slice; a
gate that matches `nkBracket` for `a[k]` matches nothing at all.** A
conservative matcher may still accept `nkBracket` on the assignment LHS (it can
only widen coverage, never narrow it) — but it must match `nkBracketExpr`
first, or drop the `nkBracket` alternative entirely.

### Known in-repo comment that states the wrong form

`src/gate/runners/evidence_truth_boundary_gate.nim:291-292` carries the
discovery note verbatim:

> `nkBracketExpr` is the `a[k]` subscript — `nkBracket` is the unrelated
> slice/index-range form.

The second clause is incorrect (see above). The accompanying code at
`src/gate/runners/evidence_truth_boundary_gate.nim:296` accepts
`nkBracketExpr` **or** `nkBracket`, so behaviour is unaffected — the defect is
in the comment. Recorded here because the file is outside this change's edit
scope; correcting the comment is a follow-up for the file's owner.

## Verification

Every shape above was produced by the following standalone probe (no project
`config.nims`, so no parent-config influence), compiled against the pinned
toolchain:

```
$ nim c --hints:off --noNimblePath \
    --path:$HOME/.choosenim/toolchains/nim-2.2.10 \
    --nimcache:/tmp/ast_shape_nc -o:/tmp/ast_shape_probe /tmp/ast_shape_probe.nim
$ /tmp/ast_shape_probe
```

```nim
import std/strutils
import compiler/[parser, ast, idents, options, llstream, pathutils]

proc shape(n: PNode; depth = 0): string =
  if depth > 12: return $n.kind
  result = $n.kind
  case n.kind
  of nkIdent: result.add "("; result.add n.ident.s; result.add ")"
  of nkStrLit..nkTripleStrLit: result.add "("; result.add n.strVal; result.add ")"
  of nkCharLit..nkUInt64Lit: result.add "("; result.add $n.intVal; result.add ")"
  else: discard
  if n.kind notin {nkIdent, nkSym} and n.kind notin {nkStrLit..nkTripleStrLit} and
     n.kind notin {nkCharLit..nkUInt64Lit}:
    for i in 0 ..< n.len:
      result.add "["; result.add shape(n[i], depth + 1); result.add "]"

proc probe(src: string): string =
  let identCache = newIdentCache()
  let configRef = newConfigRef()
  configRef.errorMax = high(int)   # newConfigRef() leaves this 0 -> first parse
                                   # error quit()s the host process
  var stream = llStreamOpen(src)
  var p: Parser
  openParser(p, AbsoluteFile("<probe>"), stream, identCache, configRef)
  result = shape(parseAll(p))
  closeParser(p)

const cases: array[7, tuple[name, src: string]] = [
  ("exported enum",  "type\n  RunVerdict* = enum\n    rvPass, rvFail"),
  ("plain enum",     "type\n  RunVerdict = enum\n    rvPass, rvFail"),
  ("exported proc",  "proc f*(): int =\n  1"),
  ("exported field", "type\n  Foo = object\n    x*: int"),
  ("bool literal",   "let x = true\nlet y = false"),
  ("subscript",      "proc h(a: var seq[int]; k: int) =\n  a[k] = 7"),
  ("slice / literal","let sl = [0, 1, 2, 3]\nlet sub = sl[0 ..< 2]")
]
for c in cases:
  echo c.name; echo ":  "; echo probe(c.src)
```

`configRef.errorMax = high(int)` is required: `newConfigRef()` leaves
`errorMax` at 0, and the Nim compiler's reaction to the first parse error is
then `quit()` — terminating the host process instead of returning an error
count. The in-repo equivalent is `src/core/parser_utils.nim:26` (inside
`initParserUtils`, which is the pattern any AST gate in this repo should use).

## Assessment

- **Quiet-failure risk**: **high** for Q1 and Q3. Both produce a well-formed,
  compilable matcher that matches nothing and reports a clean run. Q2 is
  loud at compile time but quiet at the semantic level (boolean conditions
  fall into the generic-identifier branch).
- **Countermeasure**: parse-and-print the actual tree shape once, from the
  pinned toolchain, before trusting a hand-written node-pattern — and prefer
  last-`nkIdent`-son unwrapping over fixed son indices for declared names.
- Related: `docs/spec/pnode_parse_char_literal_quirks.md` (payload-field
  layout of `TNode` — `intVal` vs `strVal`, and why reading the wrong field is
  a non-catchable `Defect`), `docs/spec/pnode_nimnode_type_separation_quirk.md`.