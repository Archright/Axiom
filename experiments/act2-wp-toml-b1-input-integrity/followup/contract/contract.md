# Typed Decoder Input Contract — Observation Record

**Subject (READ-ONLY):** `status-im/nim-toml-serialization` @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9`
**Working tree at recording time:** `git status --porcelain` = 0 entries (byte-clean, verified before and after all runs).
**Nature of this document:** OBSERVATION ONLY. Every cell records what the decoder did. This document contains **no** statement about whether any observed behavior is correct, desirable, or defective; clause mapping lives in `SPEC_CLAIMS.md` (clause-implication only). No severity, no policy, no issue filed.

---

## 0. Environment and method (pinned)

| item | value |
|---|---|
| Nim | `<user-home>/.choosenim/toolchains/nim-2.2.10/bin/nim` — nim 2.2.10, Linux amd64 |
| flags | `--mm:orc --skipUserCfg --skipParentCfg --skipProjCfg -d:release` |
| `--path` | subject clone + `~/.nimble/pkgs2/serialization-0.5.4-6a75be38…` + `faststreams-0.5.2-589a9cf0…` + `stew-0.5.0-db229429…` |
| cwd at compile | `/tmp/ax_toml_contract_build` (neutral; a `nimble.lock` in a cwd ancestor disables nimble discovery — JUDGMENT §1.6) |
| decode entry | un-keyed `Toml.decode(input, T)` (3-arg) or `Toml.decode(input, T, "", tomlCase)`; flavor `Toml_v100` (automatic object + primitives serialization) |
| inputs | `inputs/*.toml` (LF, trailing newline; `c_empty.toml` is 0 bytes), fixed by `inputs/sha256sums.txt` (63 entries) |
| raw evidence | `raw/<case>.stdout|.stderr|.exit` per case; build logs `raw/build_*.std*` (the compiler's closing timing/peak-mem hint line is filtered as non-contract noise; nothing else is altered) |
| reproduction | the (now removed) regeneration driver ran 3 consecutive runs: `FIRST RUN`, then `IDENTICAL (294 files)` ×2; raw bytes are pinned in `raw.tar.gz` (experiment-root `MANIFEST`) |
| probes | `probes/probe_record.nim`, `probe_newline.nim`, `probe_helpers.nim`, `probe_collide.nim`, `probe_collide_compile.nim` (each starts with `# nim-check: skip` + rationale) |

Types used by probes:

```nim
Three = object  a, b, c: string          # Tasks 1, 2, 3
One   = object  only: string             # Task 3 (SL3)
Inner = object  x, y: int                # Task 1 (inline table)
Wrap  = object  inner: Inner             # Task 1 (inline table)
CP3   = object  foo, bar, baz: int       # Task 5 (no intra-type collision)
Named = object  myfield: int             # Task 5 (underscore/case variants)
AllTypes = object i,f,b,s,d,t,dt,e,sq,o  # Task 4 (int,float,bool,string,date,time,datetime,enum,seq[int],object)
Bad  = object  foo: int; Foo: int        # Task 5b (byte-distinct colliding names; Nim 2.2.10 ACCEPTS this declaration — collide-decl)
```

Error rendering: `TomlFieldReadingError` (lexer.nim:26) carries `field` + `error` (the wrapped `TomlError`); probes print both (`ERRFIELD` / `ERRINNERMSG`), because the wrapper's own `.msg` is empty.

---

## 1. Task 1 — unknown-key handling matrix

Decision points in code: `reader.nim:312-316` (array-of-tables path), `reader.nim:335-343` (record path), `reader.nim:377-383` (inline-table path), early break `reader.nim:345-346`. `TomlUnknownFields` is declared `types.nim:49-57`.

### 1a. Record top level, unknown key examined (record NOT yet complete)

| flag | unknown key position | result | code path | cases |
|---|---|---|---|---|
| OFF (default) | first line / alone / between knowns / last line | **REJECT** — `(line, 4) Unexpected field 'd' while deserializing 'Three'` | `findFieldReader` returns nil → `raiseUnexpectedField` at reader.nim:341-343 (field lookup happens BEFORE the value is parsed) | U1, U5, U7, U10, U13off |
| ON | same inputs | **ACCEPT** — unknown key silently skipped; known keys before and after it are applied (`a=[1] b=[2] c=[3]`) | nil reader + flag → `parseValue(r.lex, skipValue: TomlVoid)` at reader.nim:335-340; loop continues | U2, U6, U8, U13on |

Sub-observations on the skip path (flag ON):
- Unknown key whose **value is invalid TOML** (`d = !!!`): **REJECT** — `(1, 5) illegal character "!"` (U9). The skip still parses the value (`parseValue`, lexer.nim:1788); only the KEY is exempted by the flag.
- Unknown key whose **value is an inline table** (`d = { e = 1, f = 2 }`): **ACCEPT** — parsed as `TomlVoid`; the nested keys are never field-looked-up (U13on). Flag OFF: REJECT `Unexpected field 'd'…` before any value parsing (U13off).

### 1b. Record top level, unknown key AFTER the record is complete (past the early break)

| flag | result | code path | cases |
|---|---|---|---|
| OFF | **ACCEPT — silently ignored** | after `fieldsDone >= totalFields` the loop breaks (reader.nim:345-346); `decodeRecord` returns; the caller (`decoder.nim:46-55` `tomlDecodeImpl`) performs no EOF/trailing check; the line is never tokenized | U3 |
| ON | **ACCEPT — silently ignored** (same path; flag never consulted) | same | U4 |

### 1c. Unknown key inside an inline table (value of a KNOWN object-typed field: `inner = { x = 1, d = 2 }`)

| flag | result | code path | cases |
|---|---|---|---|
| OFF | **REJECT** — surfaces as `TomlFieldReadingError(field=inner)`, inner msg `(1, 21) Unexpected field 'd' while deserializing 'Inner'` | `decodeInlineTable` value action, reader.nim:381-383; wrapped per-field at reader.nim:330-331 | U11off |
| ON | **ACCEPT** — `inner=[x=1 y=0]`, `d` skipped | reader.nim:377-380 (`parseValue(TomlVoid)`) | U11on |

Note: `decodeInlineTable` (reader.nim:348-389) has **no** `fieldsDone`/early-break — every pair in the inline table is examined whenever the inline table is examined (contrast 1b).

### 1d. Table headers while the record is incomplete (fall-through behavior)

| input fragment | flag | result | code path | case |
|---|---|---|---|---|
| `[x]` (unknown name) after `a`,`b` | OFF | **REJECT** — `(4, 1) Unexpected field 'x' while deserializing 'Three'` | after `scanTableName` fills `fieldName` with the header name (reader.nim:285) control FALLS THROUGH to `findFieldReader` (reader.nim:324) — the header name is treated as a candidate field | K3 |
| `[x]` same position | ON | **REJECT** — `(4, 1) illegal character "c"` | header name `x` is nil-reader + flag → skip attempts to parse the NEXT line (`c = "3"`) as a VALUE → lexer `parseValue` sees `c` → `raiseIllegalChar` | K3on |
| `[[x]]` on an array-less type | OFF and ON | **REJECT** both — `(4, 1) / (2, 1) double bracket not allowed` | reader.nim:291-292: `when arrayFields > 0 … else: raiseTomlErr(errDoubleBracket)` — flag-independent | K4, U12off, U12on |

### 1e. Unknown array-of-tables when the type HAS array fields
Not exercised: probe types have `arrayFields == 0`. Static path for reference: reader.nim:307-318 — unknown `[[name]]` + flag ON → `skipTableBody`; OFF → `raiseUnexpectedField`.

---

## 2. Task 2 — field-completeness contract

Type `Three{a,b,c}` (3 string fields).

| supplied | result | case |
|---|---|---|
| none (empty document) | **ACCEPT**, `a=[] b=[] c=[]` | C1 |
| 1 of 3 (`a`) | **ACCEPT**, `b`, `c` remain zero-defaults | C2 |
| 2 of 3 (`a`,`b`) | **ACCEPT**, `c` remains zero-default | C3 |
| 3 of 3 | **ACCEPT**, all set | C4 |

- `decodeRecord` never requires all fields: `totalFields` (reader.nim:252) is used only as the early-break threshold (reader.nim:345-346); there is no "fields seen == fields required" comparison anywhere in `reader.nim`/`decoder.nim`. Observed: missing fields keep their default-init values, silently.

Field present in input but never reached because of the early break:

| input | result | case |
|---|---|---|
| `a = "first"` / `a = "second"` / `b = "third"` / `c = "fourth"` | **ACCEPT**, `a=[second] b=[third] c=[]` — `c = "fourth"` is present in the input but `fieldsDone` reached 3 after `b` (2 applications to `a` + `b`), the loop breaks (reader.nim:345-346), and the `c` line is never examined | C5 (JUDGMENT T2/Obs-2 confirmed) |
| `foo = 1` / `FOO = 2` / `baz = 3` / `bar = 7` under `TomlCaseInsensitive` (type CP3) | **ACCEPT**, `foo=[2] bar=[0] baz=[3]` — the case-variant duplicate `FOO` consumed the 2nd completion slot and `bar = 7` (present, later in input) is never examined | M-insens-breaksteal |

---

## 3. Task 3 — trailing-input contract (all typed fields already filled)

Base document: `a = "1"` / `b = "2"` / `c = "3"` (record complete after line 3), then the trailing form on line 4+.

| form | trailing bytes | result | case |
|---|---|---|---|
| (a) valid key-value the type lacks | `d = "extra"` | **ACCEPT** (ignored) | T3a |
| (b) garbage | `!!!` | **ACCEPT** (ignored) | T3b |
| (c) second table header | `[x]` | **ACCEPT** (ignored) | T3c |
| (c2) array-of-tables header | `[[x]]` | **ACCEPT** (ignored) | T3c2 |
| (d) comment | `# hi` | **ACCEPT** (ignored) | T3d |
| (e) blank lines only | three empty lines | **ACCEPT** | T3e |
| (f) unterminated string | `d = "unterminated` | **ACCEPT** (ignored; the string is never scanned) | T3f |
| (g) duplicate of an existing key | `a = "dup"` | **ACCEPT** (ignored; `a` stays `[1]`) | T3g |

Controls — the SAME forms while the record is still incomplete (loop actually reaches them):

| control | result | catching site | case |
|---|---|---|---|
| `!!!` after 2 of 3 fields | **REJECT** `(3, 1) illegal character "!"` | loop `else` branch → `scanKey`/`scanName` (reader.nim:304 → lexer.nim:691-717, `!` not in the name alphabet) — proves the early break is what silences T3b | K1 |
| `d = "unterminated` after 2 fields, flag OFF | **REJECT** `(3, 4) Unexpected field 'd'…` — value never parsed | reader.nim:341-343 | K2off |
| same, flag ON | **REJECT** `(4, 1) unterminated string` | skip path parses the value → `scanString` → `errUnterminatedString` | K2on |
| `[x]` after 2 fields | **REJECT** — see 1d | reader.nim:285 fall-through | K3 / K3on |
| `[[x]]` after 2 fields | **REJECT** `double bracket not allowed` | reader.nim:291-292 | K4 |

### 3a. `checkEol` — what it does and does not catch

`lexer.nim:1918-1923`:

```nim
proc checkEol*(lex: var TomlLexer, line: int) =
  let next = lex.nonws(skipLf)
  if next != EOF:
    if lex.line == line:
      raiseIllegalChar(lex, next)
```

- It skips ALL whitespace including newlines (`nonws(skipLf)`, lexer.nim:201-208 — comment there explicitly says newline is not "whitespace" but `skipLf` skips it anyway) and then raises `illegal character` **only if** the next char is not EOF **and** the current lexer line EQUALS the `line` argument.
- `decodeRecord` captures `line = r.lex.line` **once, before the loop** (reader.nim:269) and passes that captured value at every `checkEol` call (reader.nim:332, 339). The check therefore enforces: "after a completed field, no non-whitespace may remain **on the record's START line**" — NOT "on the value's line".

Observed consequences (record types Three / One):

| scenario | result | case |
|---|---|---|
| garbage `!!!` on the same line as the FIRST value (line 1 = record start line) | **REJECT** `(1, 9) illegal character "!"` — checkEol fires | SL2 |
| garbage `!!!` on the same line as the only value of a single-field record (value line == start line) | **REJECT** `(1, 12) illegal character "!"` — checkEol fires | SL3 |
| garbage `!!!` on the same line as the LAST value, but on line 3 while the record started on line 1 | **ACCEPT** — `lex.line`(3) ≠ captured line(1) → checkEol passes → loop breaks → `!!!` never examined. Identical byte shape to SL3; outcome differs only because of the once-per-record capture | SL1 |
| garbage `!!!` on line 2, mid-record (not yet complete) | checkEol passes (2 ≠ 1), then the loop's key path catches it: **REJECT** `(2, 9) illegal character "!"` via `scanName` | SL4 |

Net: `checkEol` catches same-line trailing content **only on the record's start line**. On later lines, same-line garbage survives `checkEol` and is caught only if the loop is still running (by `scanName` in the key path); past the early break nothing catches anything.

---

## 4. Task 4 — `expectChars` `skip` parameter

### 4a. Source facts (reader.nim:84-96)

| template | body skip usage | parameter honored? |
|---|---|---|
| `expectChar(c: char, skip = skipLf)` (84-87) | `nonws(r.lex, skip)` | **YES** — singular form uses its parameter |
| `expectChars(c: set[char], err: untyped, skip = skipLf)` (89-91) | `nonws(r.lex, skipLf)` | **NO** — hardcodes `skipLf`, parameter dead |
| `expectChars(c: set[char], skip = skipLf)` (93-96) | `nonws(r.lex, skipLf)` | **NO** — hardcodes `skipLf`, parameter dead |

### 4b. Every plural `expectChars` call site (all in reader.nim; none passes an explicit `skip`, so all behave as `skipLf`; the dead parameter has no behavioral effect at any current site)

| line | enclosing proc / context | type read | overload used |
|---|---|---|---|
| 457 | `readValue` — `value is TomlTime` | TomlTime | `(c, err)` |
| 462 | `readValue` — `value is TomlDate` | TomlDate | `(c, err)` |
| 467 | `readValue` — `value is TomlDateTime` | TomlDateTime | `(c, err)` |
| 472 | `readValue` — `value is SomeInteger` | integer | plain |
| 477 | `readValue` — `value is SomeFloat` | float | plain |
| 570 | `parseNumber` (public helper) | number-as-string | plain |
| 574 | `parseInt` (public helper) | integer | plain |
| 578 | `parseDateTime` (public helper) | TomlDateTime | `(c, err)` |
| 582 | `parseTime` (public helper) | TomlTime | `(c, err)` |
| 586 | `parseDate` (public helper) | TomlDate | `(c, err)` |
| 606 | `parseFloat` (public helper) | float-as-string | plain |

### 4c. Intervening-newline matrix — typed object fields, input `<field> =\n<value>` (probe `probe_newline`, type AllTypes)

| field type | input | result | value obtained | entry skip behavior | case |
|---|---|---|---|---|---|
| int | `i =\n5` | **ACCEPT** | `5` | `expectChars(signedDigits)` → hardcoded skipLf (reader.nim:472) | nl_i |
| float | `f =\n5.5` | **ACCEPT** | `5.5` | reader.nim:477, same | nl_f |
| bool | `b =\ntrue` | **ACCEPT** | `true` | `scanBool` uses `nonws(…, skipLf)` directly (lexer.nim:791) | nl_b |
| string | `s =\n"hi"` | **REJECT** — `TomlFieldReadingError(field=s)`, inner `(1, 4) illegal character "\x0A"` | — | `readValue(string)` → `parseValue` → `nonws(skipNoLf)` (reader.nim:449 → lexer.nim:1789) | nl_s |
| date | `d =\n1979-05-27` | **ACCEPT** | `1979-05-27` | reader.nim:462 | nl_d |
| time | `t =\n07:32:00` | **ACCEPT** | `07:32:00.0` | reader.nim:457 | nl_t |
| datetime | `dt =\n1979-05-27T07:32:00Z` | **ACCEPT** | `1979-05-27T07:32:00.0+00:00` | reader.nim:467 | nl_dt |
| enum (string) | `e =\n"cRed"` | **ACCEPT** | `cRed` | `parseEnum` uses `nonws(…, skipLf)` (reader.nim:137) | nl_e |
| seq[int] | `sq =\n[1, 2]` | **ACCEPT** | `[1,2]` | `parseList` → **singular** `expectChar('[')` with default `skipLf` (reader.nim:212, 84-87) | nl_sq |
| nested object | `o =\n{ q = 1 }` | **REJECT** — `TomlFieldReadingError(field=o)`, inner `(1, 4) expected '"{"'` | — | `decodeInlineTable` → **singular** `expectChar('{', skipNoLf)` (reader.nim:359) — explicitly no-LF-skip | nl_o |

Same-line controls (newline-specificity): `s = "hi"` **ACCEPT** `hi` (nlc_s); `o = { q = 1 }` **ACCEPT** `q=1` (nlc_o). Both rejections above are exclusively about the LF between `=` and the value.

Both rejecting paths surface wrapped in `TomlFieldReadingError` (wrap point reader.nim:330-331); the accepting paths are not wrapped.

**Completed matrix vs earlier finding:** accept = int, float, date, time, datetime, bool, enum, seq; reject = string, **nested object (inline table)**. The earlier note "object accepts" did not reproduce: the nested-object field REJECTS because `decodeInlineTable` pins `expectChar('{', skipNoLf)` (reader.nim:359) — observation recorded, not adjudicated.

### 4d. Public helper procs with a leading LF before the value (probe `probe_helpers`; input files start with `\n`)

| helper (reader.nim line) | result | value | case |
|---|---|---|---|
| `parseInt` (574) | **ACCEPT** | `5` | hv_int |
| `parseFloat` (606) | **ACCEPT** | `5.5` | hv_float |
| `parseNumber` (570) | **ACCEPT** | `5`, base10 | hv_number |
| `parseBool` (609, no expectChars — `scanBool` skipLf) | **ACCEPT** | `true` | hv_bool |
| `parseString` (589) | **ACCEPT** | `hi` — its own first statement is `nonws(r.lex, skipLf)` (reader.nim:590) | hv_string |
| `parseAsString` (602 → `parseValue`) | **REJECT** `(1, 1) illegal character "\x0A"` | — | hv_asstring |
| `parseDate` (586) | **ACCEPT** | `1979-5-27` | hv_date |
| `parseTime` (582) | **ACCEPT** | `7:32:0.0` | hv_time |
| `parseDateTime` (578) | **ACCEPT** | `1979T7` | hv_datetime |

Notable internal inconsistency (observation only): the `parseString` HELPER accepts an LF before the string (its own `nonws(skipLf)`, reader.nim:590) while the typed string FIELD path rejects (its `parseValue` uses `skipNoLf`, lexer.nim:1789).

Incidental build-time observation (not a decode behavior): the 2-arg convenience `TomlReader.init(stream)` (reader.nim:69-72) fails to instantiate on Nim 2.2.10 — the default `Flavor = Toml` is not applied through the typedesc chain (`Error: type mismatch: got 'typedesc[TomlReader]' for 'T' but expected 'Flavor = Forward'`); probes instantiate `TomlReader[Toml]` explicitly.

---

## 5. Task 5 — case-mode matrix

`compare` (utils.nim:52-73): `TomlCaseSensitive` → byte `==`. `TomlCaseInsensitive` → equal length + `cmpIgnoreCase` per segment. `TomlCaseNim` → `cmpNimIdent` (utils.nim:24-50): **the FIRST character is compared byte-sensitively** (utils.nim:29 `if a[0] != b[0]: return false`); remaining characters are case-insensitive and `_` is skipped.

`findFieldReader` (utils.nim:75-87): first scans `expectedFieldPos ..< len` (advancing `expectedFieldPos` past each match), then **wrap-around** `0 ..< expectedFieldPos`. No seen-set anywhere; no duplicate detection anywhere.

### 5a. Declaration support (probe_collide_compile / collide-decl)

Nim 2.2.10 **accepts** `type Bad = object foo: int; Foo: int` — the compiled program prints `(foo: 1, Foo: 0)`. Byte-distinct colliding field names are therefore constructible, and the decoder's field table contains both names (`Bad` cases below prove both are reachable).

### 5b. No-collision type CP3{foo, bar, baz} — repeated/case-variant keys

| mode | input | result | case |
|---|---|---|---|
| CS | `foo = 1` / `foo = 2` | **ACCEPT** `foo=2 bar=0 baz=0` — identical repeat last-wins, NO raise (wrap-around re-match) | M-sens-dup |
| CI | `foo = 1` / `FOO = 2` | **ACCEPT** `foo=2` — case-variant repeat last-wins onto the SAME field, NO raise | M-insens-dup |
| CN | `foo = 1` / `foo = 2` | **ACCEPT** `foo=2` | M-nim-dup |
| CS | `FOO = 1` / `foo = 2` | **REJECT** `(1, 6) Unexpected field 'FOO'` | M-sens-dup-rev |
| CI | `FOO = 1` / `foo = 2` | **ACCEPT** `foo=2` | M-insens-dup-rev |
| CN | `FOO = 1` / `foo = 2` | **REJECT** `(1, 6) Unexpected field 'FOO'` — first char `F` ≠ `f` | M-nim-dup-rev |
| CS | `foo=1` / `FOO=2` / `baz=3` / `bar=7` | **REJECT** at `(2, 6) Unexpected field 'FOO'` | M-sens-breaksteal |
| CI | same | **ACCEPT** `foo=2 bar=0 baz=3` — duplicate consumed a slot; `bar = 7` never examined (early break after `baz`) | M-insens-breaksteal |
| CN | same | **REJECT** at `(2, 6) Unexpected field 'FOO'` | M-nim-breaksteal |

### 5c. Name-shape matrix on Named{myfield}

| input | CS | CI | CN | cases |
|---|---|---|---|---|
| `my_field = 5` | REJECT `Unexpected field 'my_field'` | REJECT (length differs) | **ACCEPT** `myfield=5` | M-{sens,insens,nim}-underscore |
| `MYFIELD = 5` | REJECT | **ACCEPT** `myfield=5` | REJECT — first char `M` ≠ `m` | M-{sens,insens,nim}-caseonly |

### 5d. Byte-distinct colliding fields Bad{foo, Foo} (declaration order: foo, Foo)

| mode | input | result | classification of the key landing | case |
|---|---|---|---|---|
| CS | `foo = 1` | `foo=1 Foo=0` | exact field | X-CS-foo |
| CS | `Foo = 1` | `foo=0 Foo=1` | exact field | X-CS-Foo |
| CS | `FOO = 5` | **REJECT** `Unexpected field 'FOO'` | — | X-CS-FOO |
| CS | `foo=1` / `foo=2` | `foo=2 Foo=0` | repeat overwrote SAME field, no raise | X-CS-rep-foo |
| CS | `Foo=1` / `Foo=2` | `foo=0 Foo=2` | repeat overwrote SAME field, no raise | X-CS-rep-Foo |
| CS | `foo=1` / `Foo=2` | `foo=1 Foo=2` | both exact | X-CS-mixed |
| CS | `Foo=1` / `foo=2` | `foo=2 Foo=1` | both exact | X-CS-mixed-rev |
| CI | `FOO = 5` | `foo=5 Foo=0` | **MIS-TARGET**: `FOO` landed on `foo` (first table entry), no error | X-CI-FOO |
| CI | `Foo = 1` | `foo=1 Foo=0` | **MIS-TARGET**: the byte-exact name `Foo` landed on `foo` (cmpIgnoreCase matches the earlier entry first) | X-CI-Foo |
| CI | `FOO=1` / `FOO=2` | `foo=1 Foo=2` | **SPLIT**: two byte-identical keys landed on DIFFERENT fields (2nd occurrence matched `Foo` in the first scan loop from `expectedFieldPos=1` before any wrap-around) | X-CI-rep-FOO |
| CI | `Foo=1` / `Foo=2` | `foo=1 Foo=2` | **SPLIT**, same mechanism | X-CI-rep-Foo |
| CI | `foo=1` / `Foo=2` | `foo=1 Foo=2` | first key → foo; second matched `Foo` in the forward scan | X-CI-mixed |
| CI | `Foo=1` / `foo=2` | `foo=1 Foo=2` | **SWAPPED pairing**: `Foo`→foo, then `foo`→Foo | X-CI-mixed-rev |
| CN | `Foo = 1` | `foo=0 Foo=1` | correct (first char `F` byte-equal) | X-CN-Foo |
| CN | `FOO = 5` | `foo=0 Foo=5` | **MIS-TARGET**: `FOO` landed on `Foo` (first char byte-equal `F`==`F`, rest Nim-ident), NOT on `foo`; no error | X-CN-FOO |
| CN | `foo=1` / `Foo=2` | `foo=1 Foo=2` | both correctly targeted | X-CN-mixed |
| CN | `Foo=1` / `foo=2` | `foo=2 Foo=1` | both correctly targeted | X-CN-mixed-rev |

Answer to the Task-5 question, per mode (observation only):
- Does a repeated key raise? **Never** in any mode/case recorded (92 decode cases, zero duplicate-key errors from the typed path).
- Overwrite the same field? Yes when every occurrence matches the same table entry (CS repeats; CI/CN when the wrap-around lands on the same entry — M-* dup cases).
- Mis-target a different field? **Yes, reproducibly, under CI and CN only** (X-CI-FOO, X-CI-Foo, X-CI-rep-FOO, X-CI-rep-Foo, X-CI-mixed-rev, X-CN-FOO). CS never mis-targets. Under CI the winner is the FIRST matching table entry (declaration order); under CN the first char must be byte-equal, so `FOO` can only ever hit `Foo`, never `foo`.

---

## 6. Case → raw file index

Every case id below has `raw/<id>.stdout`, `.stderr`, `.exit`:

- Task 1: `U1 U2 U3 U4 U5 U6 U7 U8 U9 U10 U11off U11on U12off U12on U13off U13on`
- Task 2: `C1 C2 C3 C4 C5`
- Task 3: `T3a T3b T3c T3c2 T3d T3e T3f T3g`, controls `K1 K2off K2on K3 K3on K4`, line-capture `SL1 SL2 SL3 SL4`
- Task 4: `nl_i nl_f nl_b nl_s nl_d nl_t nl_dt nl_e nl_sq nl_o nlc_s nlc_o`, `hv_int hv_float hv_number hv_bool hv_string hv_asstring hv_date hv_time hv_datetime`
- Task 5: `M-sens-dup M-insens-dup M-nim-dup M-sens-dup-rev M-insens-dup-rev M-nim-dup-rev M-sens-breaksteal M-insens-breaksteal M-nim-breaksteal M-sens-underscore M-insens-underscore M-nim-underscore M-sens-caseonly M-insens-caseonly M-nim-caseonly`, `collide-decl`, `X-CS-foo X-CS-Foo X-CS-FOO X-CS-rep-foo X-CS-rep-Foo X-CS-mixed X-CS-mixed-rev X-CI-FOO X-CI-Foo X-CI-rep-FOO X-CI-rep-Foo X-CI-mixed X-CI-mixed-rev X-CN-Foo X-CN-FOO X-CN-mixed X-CN-mixed-rev`

Exit-code convention: probe binaries exit 0 on decode acceptance, 3 on decode rejection (recorded per case; the removed regeneration driver never asserted against them).

## 7. Reproduction

2026-10-11 consolidation: the `repro.sh` regeneration driver was removed — regenerating in
place would overwrite the record, so the record's invariant is the pinned bytes, not
re-execution. `raw.tar.gz` (every member hash-enforced by the experiment-root `MANIFEST`;
`bash bsec/replay.sh verify`) carries the exact bytes of the three runs recorded below.
The build command and method above are sufficient to re-derive them out-of-tree.

```text
# run 1: REPRO VERDICT: FIRST RUN (294 files recorded)
# run 2: REPRO VERDICT: IDENTICAL (294 files byte-identical to previous run)
# run 3: REPRO VERDICT: IDENTICAL (294 files byte-identical to previous run)
```

Subject working tree verified byte-clean before and after (`git status --porcelain` empty at `4aa8e22`); binaries existed only under `/tmp/ax_toml_contract_build`.
