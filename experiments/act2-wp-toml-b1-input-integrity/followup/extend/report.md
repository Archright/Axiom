# B1 Extension — two adjacent code paths, same methodology

**Subject**: `status-im/nim-toml-serialization` @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9` (READ-ONLY; `git status --porcelain` verified empty before and after every run — recorded in `raw/env.txt`)
**Base study**: `../../JUDGMENT.md` (top-level typed record path, defects (i) duplicate-key last-wins and (ii) `fieldsDone` early-break + no trailing validation)
**This study**: extends the SAME methodology to (1) the inline-table path, (2) the case-matching modes, (3) the fragment-composition recipe `N = totalFields − k`. Determinate facts only; no severity assessment, no upstream filing.

**Pinned configuration** (identical to base study): Nim 2.2.10 (`--mm:orc --skipUserCfg --skipParentCfg --skipProjCfg`), serialization 0.5.4 (`b5473564e80a4908cf6c5a038e4c4a6ca7de2223`), faststreams 0.5.2, stew 0.5.0, `Toml_v100` flavor (`toml_serialization.nim:26` `createTomlFlavor Toml_v100`; runtime flags `= {}` because v100 < v1.1.0, `format.nim:51-53`), no `TomlUnknownFields`. Builds run from a neutral cwd (`/tmp/toml_b1_extend`) — a `nimble.lock` in a cwd ancestor disables nimble discovery (JUDGMENT.md §1.6).

**Pinned call forms**:

- Typed records: `Toml_v100.decode(input, T)` — un-keyed; `moveToKey` is a no-op for empty keys (`reader.nim:74-76`), reader starts in `state = TopLevel` (`reader.nim:66`) → `decodeRecord` (`reader.nim:248`, dispatch `reader.nim:385-389`).
- Case-mode variants: `Toml_v100.decode(input, T, "", <TomlCase>)` — the only decode overloads accepting a case mode are keyed (`decoder.nim:118-122`); all un-keyed forms hardcode `TomlCaseSensitive` (`decoder.nim:127,133,144,150`). With key `""`, `moveToKey` is a no-op, so this reproduces the un-keyed path exactly, with `r.tomlCase` selectable.
- Spec-conforming control: `Toml_v100.decode(input, TomlValueRef)` (`reader.nim:442-444` → `parseValue(r)` → at `TopLevel` the full-document `parseToml` (`reader.nim:158-163`, `lexer.nim:1948`), else value `parseValue`).

---

## Task 1 — inline-table path

### Structure (static trace)

Two structurally different consumers exist for an inline table:

| Path | Driver | Duplicate guard | Early-break |
|---|---|---|---|
| **Value** (`T = TomlTableRef`), used by `TomlValueRef` decode | `parseValue` → `parseInlineTable` (`lexer.nim:1827-1832`) | `curTable.hasKey(keys[^1])` → `raiseDuplicateTableKey` (`lexer.nim:1784-1785`) | none — consumes to `}` |
| **Typed object field** (`decodeInlineTable`, `reader.nim:348-383`) | `parseInlineTableImpl` (`lexer.nim:1670-1729`) with `findFieldReader` in the value action (`reader.nim:372-373`) | **none** — `findFieldReader` wrap-around re-match (`utils.nim:75-87`) | **none** — `parseInlineTableImpl` has no `fieldsDone`; it loops to `}` (`lexer.nim:1682-1688`) |

`decodeInlineTable` is reached when the object is in VALUE position: `decodeRecord` sets `r.state = ExpectValue` on key presence (`reader.nim:303`), the field reader re-enters `readValue`, and `readRecordValue` dispatches `decodeInlineTable` (`reader.nim:385-389`).

### Question A — does the typed field path accept `t = {a = "1", a = "2"}` last-wins while `TomlValueRef` raises?

**Verdict: CONFIRMED** (divergence reproduced on the inline-table path).

- Input `inputs/t1_inline_dup_keyed.toml` (sha256 `aef35d29…`):
  ```
  t = {a = "1", a = "2"}
  ```
- Typed: `Toml_v100.decode(input, Outer)`, `Outer = object of RootObj; t: Inner`, `Inner = object of RootObj; a: string`.
- Observed (`raw/p1_inline_table__dup_keyed__typed.out`, exit 0):
  ```
  decode_call=Toml_v100.decode(input, Outer)
  DECODE_RESULT=OK
  t_a=[2]
  a_is_2=true
  ```
- Control `Toml_v100.decode(input, TomlValueRef)` on the same input (`raw/p1_inline_table__dup_keyed__value_v100.out`):
  ```
  DECODE_RESULT=RAISE
  EXCEPTION_TYPE=TomlError
  EXCEPTION_MSG=[(1, 22) duplicate table key not allowed: 'a']
  ```
  (`Toml.decode` default flavor: identical message — `raw/p1_inline_table__dup_keyed__value_default.out`.)
- Baseline `t = {a = "1"}` decodes to `t_a=[1]` (`raw/p1_inline_table__baseline__typed.out`).

**Step-by-step trace of the observed acceptance**:

1. `decodeRecord(Outer)`: sees key `t`, state → `ExpectValue` (`reader.nim:303`); `findFieldReader` matches `t` (`reader.nim:324-325`), its reader calls `readValue(Inner)`; `readRecordValue` sees `ExpectValue` → `decodeInlineTable(Inner)` (`reader.nim:386-387`).
2. `decodeInlineTable` (totalFields=1) runs `parseInlineTableImpl` (`reader.nim:351-353`); the impl loop reads `{` via the initial action (`reader.nim:359`), then per entry: key action `scanKey` (`reader.nim:364-365`, `lexer.nim:1722`), `=`, value action (`lexer.nim:1729`).
3. Entry `a = "1"`: `findFieldReader(fields, "a", expectedFieldPos=0, …)` — first loop matches index 0 and advances `expectedFieldPos = 1` (`utils.nim:78-81`); reader applies `"1"`.
4. Entry `a = "2"`: first loop scans `1 ..< 1` — empty; **wrap-around loop** re-matches index 0 and returns its reader **without updating `expectedFieldPos`** (`utils.nim:83-85`); reader applies `"2"` (last-wins). No seen-set exists anywhere on this path (also `serialization-0.5.4/object_serialization.nim:217,249-250,268` — JUDGMENT.md §1.3).
5. `}` closes via the closing action (`lexer.nim:1685-1688`); `Outer.fieldsDone` = 1 ≥ totalFields(Outer) = 1 → outer loop breaks (`reader.nim:345-346`).

**Boundary fact (whole-document form)**: the literal input `{a = "1", a = "2"}` as the entire document raises on BOTH paths — `(1, 1) illegal character "{"` (`raw/p1_inline_table__dup_whole__whole_typed.out`, `…dup_whole__value_v100.out`). Reason: un-keyed decode starts `decodeRecord` at `TopLevel` (`reader.nim:66,385-389`), whose key branch feeds `{` to `scanKey`→`scanName`, which rejects it (`reader.nim:299-305`, `lexer.nim:714-715`); the `TomlValueRef` path at `TopLevel` runs the full-document `parseToml` (`reader.nim:158-163`), whose `parseKeyValue` also feeds `{` to `scanKey` (`lexer.nim:1930`, `1977`). So `decodeInlineTable` is **unreachable** for whole documents; it only drives inline tables in value position.

### Question B — does the `fieldsDone` early-break / trailing-ignoring defect also exist for inline tables?

**Verdict: CONFIRMED for the no-early-break half, REFUTED for the "inline-table decoding skips trailing content" half — the trailing suppression exists, but it is the OUTER record's `fieldsDone` break, not the inline-table consumer.**

1. **No early break inside the inline table** — every entry is visited:
   - `t = {a = "1", a = "2", a = "3"}` → `DECODE_RESULT=OK`, `t_a=[3]` (`raw/p1_inline_table__multi_dup__typed.out`): three re-matches, all applied. A `fieldsDone`-style break after the first match would have yielded `t_a=[1]`.
   - `t = {a = "1", b = "2"}` into `Inner{a}` → **raises**: `EXCEPTION_TYPE=TomlFieldReadingError`, `EXCEPTION_DETAIL=field=[t] inner_type=TomlError inner_msg=[(1, 18) Unexpected field 'b' while deserializing 'Inner'] line=0 col=0` (`raw/p1_inline_table__unknown_inside__typed.out`; wrapper built at `reader.nim:330-331`, note the wrapper's own line/col stay 0). An early-break path would have silently dropped `b`.
2. **Trailing content after `}` is skipped only when the OUTER object's fields are all matched** — discriminated with a 1-field vs 2-field outer type:
   - Input `inputs/t1_inline_trailing_valid_nextline.toml`: `t = {a = "1"}` + newline + `zzz = "x"`.
     - `Outer` (1 field, all matched): `DECODE_RESULT=OK`, `t_a=[1]` — `zzz` never examined (`raw/p1_inline_table__trail_valid__typed.out`).
     - `Outer2 = object; t: Inner; u: string` (1 of 2 matched): **raises** `(2, 6) Unexpected field 'zzz' while deserializing 'Outer2'` (`raw/p1_inline_table__trail_valid__typed2.out`).
     - Discriminator: the inner inline-table step returned after `}` in both cases; only the outer `fieldsDone >= totalFields` break (`reader.nim:345-346`, counter incremented at `reader.nim:334`) explains the 1-field swallow. Same result for invalid trailing `!!!`: swallowed by `Outer` (`raw/p1_inline_table__trail_invalid__typed.out`), raised by `Outer2` — `(2, 1) illegal character "!"` (`raw/p1_inline_table__trail_invalid__typed2.out`).
   - Same-line trailing content after `}` IS caught by the outer `checkEol` (`reader.nim:332` → `lexer.nim:1918-1923`): `t = {a = "1"} zzz` → `(1, 15) illegal character "z"` (`raw/p1_inline_table__trail_sameline__typed.out`).

So: the inline-table consumer itself always consumes exactly to `}`; trailing suppression is defect (ii) re-asserting one level out, whenever the containing record is already fully matched — including when the record consists solely of the inline-table field.

---

## Task 2 — case-matching modes

### Declarability precondition (static, compiler-verified)

- Two fields differing only by **case** ARE declarable in one Nim 2.2.10 object: `Foo`+`foo`, `ABC`+`abc` compile.
- Two fields differing only by **underscores** are NOT: `fooBar`+`foo_bar` → `Error: attempt to redefine: 'foo_bar'` (`raw/build__p2a_case_compile_attempt.log`, probe `probes/p2a_case_compile_attempt.nim`, T1/T3 as accepted controls, T2 rejected at line 22).

So the prior claim's Nim-ident two-field variant (`fooBar`/`foo_bar` as two declared fields) is **undeclarable** — untestable by construction. The case-only variant (`Foo`/`foo`) IS declarable and was tested exactly as proposed. (Because Nim member lookup is itself style-insensitive, the two slots are read positionally through a layout-identical view type in the probe.)

### Observed behavior — type `CasePair = object; Foo: string; foo: string`, input `FOO = "x"` / `FOO = "y"` (`inputs/t2_case_upper_dup.toml`, sha256 `9c150cac…`)

| Mode | Result | slot0 `Foo` | slot1 `foo` | Raw |
|---|---|---|---|---|
| `TomlCaseSensitive` | **RAISE** `(1, 6) Unexpected field 'FOO' while deserializing 'CasePair'` | — | — | `raw/p2_case_modes__upper_dup__pair__sensitive.out` |
| `TomlCaseInsensitive` | **OK — no error** | `x` | `y` | `raw/p2_case_modes__upper_dup__pair__insensitive.out` |
| `TomlCaseNim` | **OK — no error** | `y` (last-wins) | *(empty)* | `raw/p2_case_modes__upper_dup__pair__nim.out` |

Verbatim insensitive output:
```
DECODE_RESULT=OK
slot0_Foo=[x]
slot1_foo=[y]
slot0_is_x=true
slot1_is_y=true
```
Verbatim nim output:
```
DECODE_RESULT=OK
slot0_Foo=[y]
slot1_foo=[]
slot0_is_x=false
slot1_is_y=false
```

**Which field gets which value**: insensitive — first `FOO` → `Foo`, second `FOO` → `foo` (the two byte-identical keys land on DIFFERENT declared fields). nim — both `FOO` → `Foo`, last-wins.

**Trace (insensitive, mis-targeting)**: entry 1: `findFieldReader(fields, "FOO", expectedFieldPos=0, Insensitive)` — first loop index 0: `compare("Foo","FOO", Insensitive)` = `cmpIgnoreCase("Foo","FOO") == 0` (`utils.nim:56-61`) → match, `expectedFieldPos=1` (`utils.nim:78-81`); `"x"` → `Foo`; `fieldsDone=1` (`reader.nim:334`); 1 < 2 → continue. Entry 2: first loop index 1: `compare("foo","FOO", Insensitive)` → match → `"y"` → `foo`; `fieldsDone=2` → break (`reader.nim:345-346`). No duplicate detection exists; the forward first-loop plus case-insensitive equality makes the second occurrence a **new-field match**, not a duplicate.

**Trace (nim, no mis-targeting)**: `compare("foo","FOO", Nim)` → `cmpNimIdent` requires the FIRST character to be byte-equal (`utils.nim:29` `if a[0] != b[0]: return false`): `'f' != 'F'` → no forward match. Wrap-around re-matches `Foo` (`utils.nim:83-85`) → `"y"` applied to the SAME field, last-wins — the case-sensitive analogue of defect (i).

**Auxiliary mode determinations** (type `Lower{foo,bar}` / `Camel{fooBar,other}`, raw under `raw/p2_case_modes__*.out`):

- `FOO`/`FOO` on `Lower`: sensitive → raise `(1, 6) Unexpected field 'FOO' … 'Lower'`; insensitive → OK `foo=[y]` `bar=[]` (same-field last-wins); nim → raise (first char `'f' != 'F'`).
- `fooBar`/`foo_bar` on `Camel`: sensitive → raise `(2, 10) Unexpected field 'foo_bar'`; insensitive → raise `(2, 10) Unexpected field 'foo_bar'` (length-guard `a.len != b.len` `utils.nim:57`, 7 ≠ 6); nim → OK `fooBar=[y]` `other=[]` (two byte-DIFFERENT input keys both match one field: `cmpNimIdent` skips underscores, `utils.nim:34-36`).
- `foobar`/`FOOBAR` on `Camel`: sensitive → raise `(1, 9) Unexpected field 'foobar'`; insensitive → OK `fooBar=[y]` `other=[]` (same-field last-wins); nim → raise `(2, 9) Unexpected field 'FOOBAR'`.

### Verdict on the prior claim

**CONFIRMED for `TomlCaseInsensitive`, REFUTED for `TomlCaseNim` and `TomlCaseSensitive`** — precisely: "a repeated key can land on a DIFFERENT declared field with no error" is TRUE in insensitive mode with a declarable case-only-differing field pair; in Nim mode a repeated key never changes field (same-field last-wins, no error); in sensitive mode the first non-matching occurrence raises. The `fooBar`/`foo_bar` two-field variant of the claim is undeclarable (compiler rejects), hence UNDECIDABLE at the type level — but `cmpNimIdent`'s first-char case sensitivity makes a cross-field jump impossible even hypothetically for `FOO`-style inputs, since forward matching fails and only the already-matched field can wrap-around match.

---

## Task 3 — fragment-composition recipe `N = totalFields − k`

Setup: `type Obj = object of RootObj; a, b, c: string` — `totalSerializedFields(Obj) == 3` (count source: `serialization-0.5.4/object_serialization.nim:249-250` via `totalSerializedFieldsImpl:178`; verified by JUDGMENT.md §1.4 probe technique). Pinned path: `Toml_v100.decode(input, Obj)`.

Mechanism recap: each matched entry does `inc fieldsDone` (`reader.nim:334`); duplicates of an already-matched key re-match through the wrap-around loop without advancing `expectedFieldPos` (`utils.nim:83-85`); `fieldsDone >= totalFields` breaks the loop (`reader.nim:345-346`); after the break no input is read, not even invalid input (no EOF/charset validation after the loop — JUDGMENT.md defect (ii)).

| Input (file, sha256 prefix) | k | N given | Observed (`raw/p3_fragment_recipe__*.out`) | Recipe |
|---|---|---|---|---|
| `t3_frag_k2_n1.toml` (`fac68c0a`): `a`,`b`, then `a = "dupe"`, then `c = "later"` | 2 | 1 | OK — `a=[dupe] b=[second] c=[]`, `c_is_later=false` | **works** — `c` never applied |
| `t3_frag_k1_n2.toml` (`2ebf1611`): `a`, then `a="d1"`, `a="d2"`, then `b = "b"`, `c = "later"` | 1 | 2 | OK — `a=[d2] b=[] c=[]` | **works** — `b`,`c` never applied |
| `t3_frag_k2_n2.toml` (`d89e6bdd`): `a`,`b`, `a="d1"`, `a="d2"`, `c="later"` | 2 | 2 | OK — `a=[d1] b=[second] c=[]` | **over-supply still works** — break fires at the N-th (first) duplicate; `d2` and `c` never read |
| `t3_frag_k2_n0.toml` (`2f545e73`): `a`,`b`,`c` — no duplicates | 2 | 0 | OK — `a=[first] b=[second] c=[later]` | **fails as expected** — without the N duplicates the later content IS applied |
| `t3_frag_k2_n1_dup_after_later.toml` (`acedffe9`): `a`,`b`,`c="later"`, then `a="dupe"` | 2 | 1 (placed after) | OK — `a=[first] b=[second] c=[later]` | **fails if placed after** — `c` is the 3rd match, so the break fires at the `c` line and the trailing duplicate is the content that gets suppressed; ORDER IS REQUIRED: the N duplicates must precede the content to be suppressed |
| `t3_frag_k2_n1_invalid_later.toml` (`90550cfa`): `a`,`b`,`a="dupe"`, then `!!!` | 2 | 1 | OK — `a=[dupe] b=[second] c=[]` | **break skips even syntax validation** — invalid trailing input never scanned, extending base defect (ii) |

**Value-path controls** (`Toml_v100.decode(input, TomlValueRef)`): the k2_n1 fragment raises `(3, 3) duplicate table key not allowed: 'a'`; the k2_n0 fragment parses fully (`Table len=3`, a/b/c all present); the invalid-later fragment raises `(3, 3) duplicate table key not allowed: 'a'` — the spec-conforming path validates the whole document and rejects every fragment the typed path silently truncates (`raw/p3_fragment_recipe__*__value_v100.out`).

**Exactness statement**: the recipe is exact for the top-level typed record path in the pinned configuration — with `k` matched entries, appending exactly `N = totalFields − k` duplicates of any already-matched key fires the `fieldsDone` break and makes all later content (valid or invalid) unread. It is minimal (N−1 duplicates do not fire the break — k2_n0) and order-sensitive (duplicates must precede the content to suppress — dup_after_later). N > N works and is not minimal (k2_n2). All runs exit 0; every run's stdout/stderr/exit code is under `raw/`.

---

## Determinism & integrity

- The (2026-10-11 removed) regeneration driver was executed twice back-to-back: every run output (`*.out`, `*.err`, `*.exit`) is byte-identical across the two runs; the per-probe build logs differ only in the compiler's self-reported wall-time line (`… lines; N.NNNs; … [SuccessX]`), which is compiler-internal timing, not probe behavior. The deliberate-failure build log (`build__p2a_case_compile_attempt.log`) is byte-identical. This matches the base study's determinism practice (JUDGMENT.md §5).
- Subject repo: `git status --porcelain` empty before and after each run (recorded in `raw/env.txt`).
- All builds in `/tmp/toml_b1_extend`; binaries never written into either repository.

## Deliverable map

```
followup/extend/
├── report.md                  ← this file
├── raw.tar.gz                 ← pinned run bytes (member hashes in root MANIFEST; driver removed 2026-10-11)
├── inputs/                    ← 17 pinned inputs (LF, trailing newline) + sha256sums.txt
├── probes/
│   ├── p1_inline_table.nim            (Task 1; modes: typed, typed2, whole_typed, value_v100, value_default)
│   ├── p2_case_modes.nim              (Task 2; args: <case> <lower|camel|pair> <input>)
│   ├── p2a_case_compile_attempt.nim   (Task 2; deliberate compile-failure evidence)
│   └── p3_fragment_recipe.nim         (Task 3; modes: record, value_v100)
└── raw/                       ← build__*.log, p*__*.out/.err/.exit per run, env.txt, sha256_inputs_at_run.txt
```
