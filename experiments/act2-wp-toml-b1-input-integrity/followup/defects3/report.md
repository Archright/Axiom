# defects3 — confirmation report: nim-toml-serialization @ 4aa8e22

Subject: `<workspace>/nim-toml-serialization` @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9` (READ-ONLY; `git status --porcelain` empty before and after all work — verified in `raw/env.txt` and in the final check).
Compiler: Nim 2.2.10 (`~/.choosenim/toolchains/nim-2.2.10/bin/nim`), flags `--mm:orc --skipUserCfg --skipParentCfg --skipProjCfg`, `--path` to the subject clone and to nimble `serialization-0.5.4` / `faststreams-0.5.2` / `stew-0.5.0`. All compiles ran from `/tmp/defects3_build` (neutral cwd). Binaries stayed in `/tmp`; only sources are committed under `probes/`.

Probe convention: every source under `probes/` carries `# nim-check: skip` as line 1 plus the rationale comment, per `experiments/bug-verdict-e2e/cout_probe.nim` (they import out-of-tree packages via explicit `--path` and cannot resolve in repo context).

---

## Defect 1 — `dateDimte` typo in `value_ops.nim` — verdict: CONFIRMED

### Source (subject `toml_serialization/value_ops.nim:29-36`)

```nim
  elif T is TomlDate:
    if n.kind == TomlKind.DateTime:
      if n.dateTime.date.isSome:
        result = n.dateDimte.date.get            # line 32
  elif T is TomlTime:
    if n.kind == TomlKind.DateTime:
      if n.dateTime.time.isSome:
        result = n.dateDimte.time.get            # line 36
```

`innerValue` (line 14) is a plain proc instantiated per `T`; `proc `[]`*(node: TomlValueRef, name: string, T: type): T` at lines 86-87 calls it inline, so the branches compile only when someone actually calls the typed accessor.

### Probe

`probes/p1a_accessor_tomldate.nim` (and `p1b_accessor_tomltime.nim`): decode a document into `TomlValueRef` and call `doc["d", TomlDate]` / `doc["t", TomlTime]`. Note: the accessors live in `toml_serialization/value_ops.nim`, which `toml_serialization.nim` does **not** re-export (it exports only `desc, reader, writer, types, format, decoder`), so probes need `import toml_serialization/value_ops`.

### Observed (verbatim, `raw/p1a_accessor_tomldate.compile.out`; COMPILE_EXIT=1)

```
<workspace>/nim-toml-serialization/toml_serialization/value_ops.nim(32, 19) Error: undeclared field: 'dateDimte' for type types.TomlValueRef [type declared in <workspace>/nim-toml-serialization/toml_serialization/types.nim(106, 3)]
```

`raw/p1b_accessor_tomltime.compile.out` (COMPILE_EXIT=1) is identical except `(36, 19)`.

### Controls

- `raw/p1c_control_non_date_accessors.compile.out` + `p1c.run.*` — same library, accessors for int/string/bool only: compiles (COMPILE_EXIT=0) and runs (`stdout: 5 hi true`, RUN_EXIT=0). The failure is attributable solely to the TomlDate/TomlTime branches.
- `raw/p1d_direct_typed_decode.compile.out` + `p1d.run.*` — direct typed decode `Toml.decode("d = 1979-05-27", TomlDate, "d")` / `Toml.decode("t = 07:32:00", TomlTime, "t")` (reader path, never instantiates `innerValue`): compiles and runs (`stdout: date: 1979-5-27` / `time: 7:32:0`, RUN_EXIT=0).
- `raw/p1e_accessor_patched_copy.compile.out` — same accessor one-liners compiled against a `/tmp`-only patched copy of the repo where lines 32/36 read `n.dateTime...` (patch diff verified to touch only those two tokens; the read-only clone untouched). **Surprise: it still fails to compile, with a second, independent error** (COMPILE_EXIT=1):

```
/tmp/defects3_build/p1e_accessor_patched_copy.nim(18, 12) template/generic instantiation of `[]` from here
/tmp/defects3_patched/nim-toml-serialization/toml_serialization/value_ops.nim(87, 13) template/generic instantiation of `innerValue` from here
/tmp/defects3_patched/nim-toml-serialization/toml_serialization/value_ops.nim(32, 33) Error: type mismatch
Expression: get(n.dateTime.date)
  [1] n.dateTime.date: Option[types.TomlDate]

Expected one of (first mismatch at [position]):
[1] template get(T: typedesc[tuple]; i: static int): untyped
```

i.e. `Option.get` is not in scope in `value_ops.nim` (it imports only `std/[tables, typetraits, strutils], ./types, ./private/utils`; `types.nim` imports `std/options` but exports only `errors`). This compilation emitted exactly one error (grep count 1); line 31's `isSome` produced no diagnostic.

### Verdict

**CONFIRMED** — `node["d", TomlDate]` and `node["t", TomlTime]` fail to compile, with the exact `undeclared field: 'dateDimte'` errors at value_ops.nim:32/:36. Additional observed fact (not part of the verdict): repairing only the typo is insufficient — the accessor then fails on `Option.get` scope, so the path is currently unreachable at compile time either way.

---

## Defect 2 — nil dereference on missing-key typed access — verdict: CONFIRMED

### Source (subject `toml_serialization/value_ops.nim:79-87`)

```nim
proc `[]`*(node: TomlValueRef, name: string): TomlValueRef {.inline.} =
  ## Gets a field from a `TomlKind.Table`, which must not be nil.
  ## If the value at `name` does not exist, raises KeyError.
  assert(not isNil(node))
  assert(node.kind == TomlKind.Table)
  node.tableVal.getOrDefault(name)                # line 84 — returns nil, no KeyError

proc `[]`*(node: TomlValueRef, name: string, T: type): T {.inline, raises: [KeyError].} =
  node[name].innerValue(T)                        # line 87 — nil.innerValue dereferences n.kind (line 16)
```

Array variant at lines 89-98 (`node.arrayVal[index]`, bounds-checked).

### Probes and observed behavior

(a) **Missing key on a decoded table, raw run** (`probes/p2a_missing_key_typed_raw.nim`; debug defaults). `raw/p2a.run.stderr` verbatim:

```
Traceback (most recent call last)
/tmp/defects3_build/p2a_missing_key_typed_raw.nim(19) p2a_missing_key_typed_raw
<workspace>/nim-toml-serialization/toml_serialization/value_ops.nim(87) []
<workspace>/nim-toml-serialization/toml_serialization/value_ops.nim(16) innerValue
SIGSEGV: Illegal storage access. (Attempt to read from nil?)
```

`raw/p2a.run.exit`: `RUN_EXIT=139` (killed by SIGSEGV). stdout got as far as `hasKey(a)=true hasKey(absent)=false` / `about to evaluate doc["absent", int] ...` and never printed a value. The traceback pins the crash to `value_ops.nim:87` → `innerValue` line 16 (`case n.kind`) — exactly the claimed mechanism.

(a') **Same probe with `-d:release`** (`raw/p2a_release.run.stderr`): `SIGSEGV: Illegal storage access. (Attempt to read from nil?)`, `RUN_EXIT=139` (no traceback, same signal death). Observable is build-mode independent.

(a'') **Instrumented variant** (`probes/p2b_missing_key_typed_instrumented.nim`, try/except Defect then CatchableError): process died by SIGSEGV before any handler ran (`raw/p2b.run.stdout` empty, `p2b.run.stderr` = same SIGSEGV traceback, `RUN_EXIT=139`). **KeyError never fires** — neither as a raised exception nor catchable.

(b) **Out-of-range index on an array** (`probes/p2c_missing_index_typed_raw.nim`, `arr[9, int]` on a 3-element array): clean bounds-checked failure — `raw/p2c.run.stderr` ends with `Error: unhandled exception: index 9 not in 0 .. 2 [IndexDefect]`, `RUN_EXIT=1`. So the nil-dereference is specific to the table/key path; the array path raises IndexDefect as its doc comment (value_ops.nim:90-92) promises.

(c) **Control** (`probes/p2d_untyped_accessor_control.nim`): the untyped `doc["absent"]` and `doc.getOrDefault("absent")` silently return nil (`stdout: ... isNil: true ... isNil: true`, RUN_EXIT=0) — the mechanism feeding nil into the typed accessor, with no exception at all.

### Verdict

**CONFIRMED** — absent-key typed access is a hard nil dereference: the process dies with SIGSEGV (shell exit code 139) in debug and release; it is not a `NilAccessDefect` that can be caught, and the declared `raises: [KeyError]` can never fire. The array case behaves differently and cleanly (IndexDefect, exit 1).

---

## Defect 3 — `expectChars` ignores its `skip` parameter — verdict: CONFIRMED (behavior) / spec violation (normative)

### Source (subject `toml_serialization/reader.nim:84-96`)

```nim
template expectChar(c: char, skip = skipLf) =
  if nonws(r.lex, skip) != c:                     # uses its parameter
    raiseExpectChar(r.lex, c)
  eatChar

template expectChars(c: set[char], err: untyped, skip = skipLf) =
  if nonws(r.lex, skipLf) notin c:                # line 90 — hardcodes skipLf, ignores `skip`
    raiseTomlErr(r.lex, err)

template expectChars(c: set[char], skip = skipLf) =
  let next = nonws(r.lex, skipLf)                 # line 94 — hardcodes skipLf, ignores `skip`
  if next notin c:
    raiseIllegalChar(r.lex, next)
```

The body references the module-level `skipLf` constant (lexer.nim), not the `skip` parameter, so the parameter is dead. `nonws(lex, skipLf)` treats LF as skippable whitespace (lexer.nim:201-210). Call sites: `expectChars` precedes the typed TomlTime/TomlDate/TomlDateTime reads (reader.nim:457,462,467), SomeInteger/SomeFloat reads (472,477), and parseNumber/parseInt/parseDateTime/parseTime/parseDate/parseFloat (570,574,578,582,586,606).

### OBSERVED behavior (`raw/p3.run.stdout`, verbatim, RUN_EXIT=0)

```
keyed int "key =\x0A5" -> ACCEPTED value=5
keyed int "key = 5" -> ACCEPTED value=5
keyed int "key =\x0A\"s\"" -> REJECTED TomlError: (2, 1) illegal character "\""
keyed float "f =\x0A1.5" -> ACCEPTED value=1.5
keyed TomlDate "d =\x0A1979-05-27" -> ACCEPTED value=1979-5-27
keyed TomlTime "t =\x0A07:32:00" -> ACCEPTED value=7:32:0
keyed TomlDateTime "dt =\x0A1979-05-27T07:32:00Z" -> ACCEPTED value=1979-5-27 7:32:0
keyed string "s =\x0A\"x\"" -> REJECTED TomlError: (1, 4) illegal character "\x0A"
keyed bool "b =\x0Atrue" -> ACCEPTED value=true
unkeyed TomlValueRef-int "5" -> REJECTED TomlError: (1, 2) expected '"="'
unkeyed TomlValueRef-int-lf "\x0A5" -> REJECTED TomlError: (2, 2) expected '"="'
unkeyed object "x =\x0A5" -> ACCEPTED value=Conf(x=5)
```

Reading of the record:

- The question case `Toml.decode("key =\n5", int, "key")` is **ACCEPTED** (value 5). Same for float, TomlDate, TomlTime, TomlDateTime, bool, and object fields (`x =\n5` → `Conf(x=5)`).
- The wrong-type control `key =\n"s"` is rejected with `(2, 1)` — the scanner's position is start of line 2, proving the intervening LF was consumed before the digit-set check; the rejection is about the `"` char, not the newline.
- String values after a newline are REJECTED (`(1, 4) illegal character "\x0A"`) — the string branch (reader.nim:446-449, lexer `parseValue`) does not go through `expectChars`; strictness is type-dependent. Bool goes through `scanBool` (no `expectChars`) and is accepted.
- Un-keyed form: a keyed-API fact first — `Toml.decode(input, int)` without a key does not exist as a runtime behavior at all: it is a compile-time fatal by design (`raw/p3.unkeyed_scalar_fatal.compile.out`: `decoder.nim(25, 10) Error: fatal error: Toml.decode: 'int' not allowed at top level Toml`, per the `TomlNotTopLevel` guard, decoder.nim:19-27). Of the legal unkeyed forms, the object form accepts `x =\n5`; top-level `TomlValueRef` rejects bare `"5"`/`"\n5"` with `expected "="` (it parses key/value document structure, and its `(2, 2)` position for `"\n5"` shows the leading LF was skipped there too).

### SPEC position (separate from the observation)

From https://toml.io/en/v1.0.0 (fetched 2026-10-11; HTML kept at `/tmp/defects3_build/toml_spec_v100.html`):

- Spec preamble: "Whitespace means tab (0x09) or space (0x20). Newline means LF (0x0A) or CRLF (0x0D 0x0A)."
- Key/Value Pair section: "Keys are on the left of the equals sign and values are on the right. Whitespace is ignored around key names and values. **The key, equals sign, and value must be on the same line** (though some values can be broken over multiple lines)."
- Key/Value Pair section: "Unspecified values are invalid. `key = # INVALID`" and "There must be a newline (or EOF) after a key/value pair. (See Inline Table for exceptions.)" — this rule governs what may follow a pair, not what may sit between `=` and the value.

The task brief's recalled wording ("There must be a newline (or EOF) after a key/value pair") is real but is the *after-the-pair* rule; the rule that disallows `key =\n5` is the same-line requirement quoted above. (The parenthetical about values broken over multiple lines refers to multi-line value tokens such as multi-line strings/arrays — the break happens inside the value token, not between `=` and the value's first character; an integer has no multi-line form.)

### Verdict

**CONFIRMED** — the library accepts `key =\n5` (and the same shape for float/date/time/datetime/bool/object fields), which **violates** TOML v1.0.0's "The key, equals sign, and value must be on the same line". Observed behavior and spec position are stated separately above per instructions.

---

## Surprises (observations only)

1. Defect 1 is doubly broken: after fixing the typo in a `/tmp` copy, instantiation still fails on `Option.get` scope in `value_ops.nim` (no `std/options` import; only a tuple-indexing `get` template is a candidate).
2. `toml_serialization.nim` does not re-export `value_ops.nim`; the `TomlValueRef` accessors are reachable only via `import toml_serialization/value_ops`.
3. Defect 2 kills the process by SIGSEGV in both debug (`--mm:orc` defaults, with Nim traceback) and `-d:release`; an `except Defect` handler does not run. Exit code as seen by the shell is 139.
4. Defect 3 strictness is inconsistent across types: newline-before-value is accepted for int/float/date/time/datetime/bool/object but rejected for string.
5. Unkeyed scalar decode (`Toml.decode(s, int)`) is a compile-time fatal by design (`TomlNotTopLevel` guard, decoder.nim:19-27), so it has no runtime behavior to test.

No issue was filed anywhere; the subject repo was never modified (`git status --porcelain` empty at start and finish).
