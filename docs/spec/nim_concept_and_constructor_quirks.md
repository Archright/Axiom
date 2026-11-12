# Nim Concept & Constructor Syntax Quirks

## §1: `concept` keyword unavailable in Nim 2.2.10

**Symptom**: `Error: expression expected, but found 'keyword concept'`

**Root cause**: The `concept` keyword is not implemented in Nim 2.2.10 (compiled 2026-04-24).
It is not available as an experimental feature either (`--experimental:concept` gives
`unknown experimental feature`).

**Workaround**: Document the interface as a comment contract and enforce field existence
at compile time via `static:` blocks with `when not compiles(...)` checks.

**Example**:
```nim
# Instead of:
#   concept CstNode =
#     self.kind is CstNodeKind
#     ...

# Use compile-time field validation:
static:
  when not compiles(default(MyType).kind is CstNodeKind):
    {.error: "MyType must have field 'kind: CstNodeKind'".}
```

**Status**: Awaiting Nim language support. Track: `concept` keyword in Nim roadmap.

---

## §2: Function parameters named as ref object fields trigger constructor syntax

**Symptom**: `Error: type expected` when calling a function with named parameters
that match field names of its return type.

**Example that fails**:
```nim
type Foo = ref object
  name*: string

func initFoo*(name: string = ""): Foo {.raises: [].} =
  Foo(name: name)

# This fails with "type expected":
let x = initFoo(name: "hello")
```

**Root cause**: Nim's parser interprets `initFoo(name: "hello")` as an object constructor
for type `initFoo` with field initializer `name: "hello"`, rather than as a function call
with a named argument. This happens when:
1. The function name could be a type name
2. The named parameter matches a field of the return type

**Workaround**: Either:
- Use `ConcreteCstNode(name: "hello")` directly (type constructor works correctly)
- Use positional arguments: `initFoo("hello")`
- Prefix parameter names to avoid collision: `func newFoo(fooName: string)`

**Status**: Inherent to Nim's object-constructor syntax. Workaround is stable.

---

## §3: ok()/err() Result templates require a `result` context — not usable on local vars

**Symptom**: `Error: object constructor needs an object type` pointing INTO
`core/types/results.nim` when calling `err("...")` from a context without a
`result` variable (e.g. assigning into a local `var r: Result[T, E]` inside a
`try/except` in a CLI proc).

**Example that fails**:
```nim
var recordRes: Result[EvidenceCasRecord, string]
try:
  recordRes = buildEvidenceCasRecord(cas, payload)
except Exception as e:
  recordRes = err("record build raised: " & e.msg)  # ← object constructor error
```

**Root cause**: `ok`/`err` are `untyped` templates that delegate the Result type
to `typeof(result)` (the caller's implicit `result`). They only synthesize
inside a proc whose return type is the target `Result[T, E]` — a local
destination variable is not a `result` context, so `typeof(result)` resolves to
something unusable and the `R(ok: false, err: e)` object constructor fails.

**Workaround**: construct the Result object directly at the assignment site
(the generic params are then fixed by the declared local type):
```nim
recordRes = Result[EvidenceCasRecord, string](ok: false,
  err: "record build raised: " & e.msg)
```

**Status**: Inherent to the template-based Result factory design
(core/types/results.nim). Workaround is stable.

---

## §4: `$` + slice on a distinct string — slice binds before the conversion

**Symptom**: `Error: type mismatch` for `$casKey[0 ..< 12]` where
`EvidenceKey* = distinct string`.

**Root cause**: the argument index expression binds to the distinct-typed
operand before `$` is considered, and slicing is not defined for the distinct
type (`$` is not distributed into the index op).

**Workaround**: parenthesize the conversion: `($casKey)[0 ..< 12]`.

**Status**: Inherent to Nim's `$`/index precedence. Workaround is stable.

---

## §5: Template parameters can replace constructor field identifiers

Nim substitutes template parameters in identifier positions, including object
constructor field names. If a parameter has the same name as a constructor
field, instantiating the template can replace the field name with the argument
and produce invalid constructor syntax. Give the template parameter a distinct
name from the field, as in `persistAndRecord` in
`src/cli/upstream_report_cli.nim`.

This is template substitution, not a claim of a compiler defect. The Nim manual
describes parameter substitution even in field-access expressions and separately
explains hygiene for constructor field names:
https://nim-lang.org/docs/manual.html#templates-lookup-rules-for-template-parameters
https://nim-lang.org/docs/manual.html#templates-hygiene-in-templates
