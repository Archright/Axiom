# Writer Round-Trip Integrity — nim-toml-serialization

**Subject**: `nim-toml-serialization` @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9` (READ-ONLY; `git status --porcelain` = empty before and after this task).
**Question**: does the library's WRITER produce output that is (a) valid TOML and (b) re-parseable by the library itself?
**Method**: spec text fetched from toml.io first (verdict authority); deterministic Nim probes (`probes/probe1_esc.nim`, `probe2_keys.nim`, `probe3_roundtrip.nim`) compiled with Nim 2.2.10 (`--mm:orc --skipUserCfg --skipParentCfg --skipProjCfg`, `--path` to the pinned clone + serialization-0.5.4 + faststreams-0.5.2 + stew-0.5.0), **built and run only in `/tmp`** from a neutral cwd; emitted bytes recorded verbatim; re-parse with the same flavor; cross-check with Python 3.12.3 `tomllib`.
**Scope note**: determinate facts only — no severity assessment, no issue filed.

**Reference-parser limitation (explicit)**: Python 3.12 `tomllib` implements **TOML v1.0.0 only**. It is a valid auxiliary oracle **only for v1.0.0 verdicts** (`Toml_v100`-flavor emissions). It MUST NOT be used to judge v1.1.0-only syntax (`\e`, `\xHH`, multi-line inline tables, inline-table trailing commas, omitted seconds). Every v1.1.0-flavor `RAISE` below is expected and carries **no** v1.1.0 verdict weight; for v1.1.0 the spec text itself is the only authority applied.

Flavors under test: `Toml_v100` = `createTomlFlavor(..., runtimeFlags = {}, version = TomlVersion_v100)`; default `Toml` = `flavorRuntimeFlags = {TomlInlineTableNewline, TomlInlineTableTrailingComma, TomlHexEscape, TomlHourMinute, TomlStrictComma}`, `flavorTomlVersion = (1,1,0)` (`toml_serialization/format.nim:26-41`, `toml_serialization.nim:26-30`).

---

## Task 1 — the `\e` escape (writer.nim:148)

**Code claim check — CONFIRMED**: `writer.nim:133` excludes `\e` from `lowEscape` and `writer.nim:148` is `of '\e': append "\\e"`. The writer emits the two bytes `\` `e` (hex `5C 65`) for input byte `0x1B`, under **both** flavors.

### Spec (verbatim)

TOML v1.0.0, [toml.io/en/v1.0.0](https://toml.io/en/v1.0.0), § String:

> For convenience, some popular characters have a compact escape sequence.
>
> ```text
> \b         - backspace       (U+0008)
> \t         - tab             (U+0009)
> \n         - linefeed        (U+000A)
> \f         - form feed       (U+000C)
> \r         - carriage return (U+000D)
> \"         - quote           (U+0022)
> \\         - backslash       (U+005C)
> \uXXXX     - unicode         (U+XXXX)
> \UXXXXXXXX - unicode         (U+XXXXXXXX)
> ```
>
> Any Unicode character may be escaped with the \uXXXX or \UXXXXXXXX forms. The escape codes must be valid Unicode scalar values.
> **All other escape sequences not listed above are reserved; if they are used, TOML should produce an error.**

TOML v1.1.0, [toml.io/en/v1.1.0](https://toml.io/en/v1.1.0), § String:

> ```text
> \b         - backspace       (U+0008)
> \t         - tab             (U+0009)
> \n         - linefeed        (U+000A)
> \f         - form feed       (U+000C)
> \r         - carriage return (U+000D)
> \e         - escape          (U+001B)
> \"         - quote           (U+0022)
> \\         - backslash       (U+005C)
> \xHH       - unicode         (U+00HH)
> \uHHHH     - unicode         (U+HHHH)
> \UHHHHHHHH - unicode         (U+HHHHHHHH)
> ```
>
> Any Unicode character may be escaped with the \xHH, \uHHHH, or \UHHHHHHHH forms.
> All other escape sequences not listed above are reserved; if they are used, TOML should produce an error.

`\e` is **absent** from the v1.0.0 list and **explicitly present** in the v1.1.0 list. **Prior research "`\e` was ADDED in 1.1.0" — CONFIRMED** by the verbatim text of both versions.

### Observed behavior (exact bytes)

| case | flavor | emitted document (hex / as text) |
|---|---|---|
| `TomlValueRef` `{"esc": "\x1BABC"}` | `Toml_v100` | `20 20 65 73 63 3D 22 5C 65 41 42 43 22 0A` = `  esc="\eABC"\n` |
| same | `Toml` (v1.1.0 flags) | identical bytes: `  esc="\eABC"\n` |
| `Obj(s = "\x1BABC")` | `Toml_v100` | `73 20 3D 20 22 5C 65 41 42 43 22 0A` = `s = "\eABC"\n` |
| same | `Toml` | identical bytes |
| C0+DEL+0x80+0xFF sweep | `Toml_v100` | `"\u0000…\u0007\b\t\n\u000B\f\r\u000E…\u001A\e\u001B→\e \u001C…\u001F\u007F\u0080\u00FF"` — ESC emitted as `\e`; everything else `\u00XX` |
| C0+DEL+0x80+0xFF sweep | `Toml` | same shape but `\x00…\xFF` (TomlHexEscape active); ESC still emitted as `\e` |

### Re-parse (same flavor)

- `Toml_v100.decode` of `  esc="\eABC"\n` → **OK**, `stringVal` = `1B 41 42 43`, byte-exact. Round-trip: **YES**.
- `Toml.decode` (v1.1.0 flags) of the same bytes → **OK**, byte-exact. Round-trip: **YES**.
- Reader-side cause: `lexer.nim:438` accepts `\e` **unconditionally** (no flag gate — unlike `\x`, which raises "not supported by standard" unless `TomlHexEscape` is set, `lexer.nim:420-421`).
- Full C0 sweep under `Toml_v100`: re-decodes byte-exact for 0x00–0x1F and 0x7F, but input bytes `80 FF` (invalid UTF-8) return as `C2 80 C3 BF` — the v1.0.0-flavor emission is spec-valid; the loss is a Nim-bytes vs Unicode-scalars gap (see Task 3).

### Reference parser (tomllib, v1.0.0 oracle)

- `esc_v100_value/object/ctrl.toml` → `TOMLDecodeError: Unescaped '\' in a string` (the `\e`). Confirms the spec verdict for v1.0.0.
- `esc_v110_*.toml` → also raise, **expected and weightless** (tomllib is 1.0.0-only; `\e` is v1.1.0 syntax).

### Verdict (version-scoped)

- **TOML v1.0.0 (`Toml_v100` flavor)**: the emitted `"\e…"` is **INVALID TOML v1.0.0**. In-library round-trip: **YES** (reader accepts `\e` despite the v1.0.0 flavor). So the v1.0.0-flavor writer emits a document that is spec-invalid but self-consistent.
- **TOML v1.1.0 (default `Toml` flavor)**: the emitted `"\e…"` is **VALID TOML v1.1.0**. In-library round-trip: **YES**.

---

## Task 2 — key escaping (writer.nim:166-181)

**Code claim check — CONFIRMED**: `writer.nim:168` `shouldEscape = {'\0'..'\32', '.', '\"', '\'', '#', '\127'..'\255'}`; a key containing none of these (and length > 0) is appended **bare** (`writer.nim:177-180`). Therefore `[`, `]`, `=`, `{`, `}`, `,` are written bare. When a key IS quoted, it is emitted via the string writer (`writeValue(w, s)`), i.e. as a basic string with escapes.

### Spec (verbatim)

TOML v1.0.0, [toml.io/en/v1.0.0](https://toml.io/en/v1.0.0), § Keys (the v1.1.0 text at [toml.io/en/v1.1.0](https://toml.io/en/v1.1.0) is word-for-word identical on both rules):

> A key may be either bare, quoted, or dotted.
> **Bare keys may only contain ASCII letters, ASCII digits, underscores, and dashes (A-Za-z0-9_-).** Note that bare keys are allowed to be composed of only ASCII digits, e.g. 1234, but are always interpreted as strings.
>
> **Quoted keys follow the exact same rules as either basic strings or literal strings** and allow you to use a much broader set of key names. Best practice is to use bare keys except when absolutely necessary.

So `[`, `]`, `=`, `{`, `}`, `,` and space in a key are only expressible as **quoted** keys; a bare occurrence is invalid TOML in **both** v1.0.0 and v1.1.0.

### Observed behavior — per character (identical under BOTH flavors)

Writer output and same-flavor re-parse; tomllib (v1.0.0 oracle) on the `Toml_v100` emissions:

| key char | path | emitted (repr, `\x0A`=LF) | library re-parse | tomllib (v1.0.0) | round-trips in-library |
|---|---|---|---|---|---|
| `[` | kv | `  k[=7\x0A` | **FAIL** `(1,5) expected "="` | RAISE `Expected '=' after a key` | **NO** |
| `]` | kv | `  k]=7\x0A` | **FAIL** `(1,5) expected "="` | RAISE | **NO** |
| `=` | kv | `  k==7\x0A` | **FAIL** `(1,5) illegal character "="` | RAISE `Invalid value` | **NO** |
| `{` | kv | `  k{=7\x0A` | **FAIL** `(1,4) illegal character "{"` | RAISE | **NO** |
| `}` | kv | `  k}=7\x0A` | **FAIL** `(1,4) illegal character "}"` | RAISE | **NO** |
| `,` | kv | `  k,=7\x0A` | **FAIL** `(1,4) illegal character ","` | RAISE | **NO** |
| space | kv | `  "k "=7\x0A` (quoted) | OK, key `6B 20` preserved | OK | **YES** |
| `[` | nested table | `  t[.inner=1\x0A` (dotted form) | **FAIL** | RAISE | **NO** |
| `]` | nested table | `  t].inner=1\x0A` | **FAIL** | RAISE | **NO** |
| `=` | nested table | `  t=.inner=1\x0A` | **FAIL** `(1,5) illegal character "."` | RAISE | **NO** |
| `{` | nested table | `  t{.inner=1\x0A` | **FAIL** | RAISE | **NO** |
| `}` | nested table | `  t}.inner=1\x0A` | **FAIL** | RAISE | **NO** |
| `,` | nested table | `  t,.inner=1\x0A` | **FAIL** | RAISE | **NO** |
| space | nested table | `  "t ".inner=1\x0A` | OK | OK | **YES** |
| `[` | inline member | `t={i[ = 7}\x0A` | **FAIL** | RAISE | **NO** |
| `]` | inline member | `t={i] = 7}\x0A` | **FAIL** | RAISE | **NO** |
| `=` | inline member | `t={i= = 7}\x0A` | **FAIL** `(1,7) illegal character "="` | RAISE | **NO** |
| `{` | inline member | `t={i{ = 7}\x0A` | **FAIL** | RAISE | **NO** |
| `}` | inline member | `t={i} = 7}\x0A` | **FAIL** | RAISE | **NO** |
| `,` | inline member | `t={i, = 7}\x0A` | **FAIL** | RAISE | **NO** |
| space | inline member | `t={"i " = 7}\x0A` | OK | OK | **YES** |

Reference cases (kv path, both flavors): `k.` → `"k."=7` (OK, correctly quoted so it cannot re-parse as a dotted key); `k"` → `"k\""` (OK); `k#` → `"k#"` (OK, quoted so `#` cannot start a comment); `k'` → `"k\'"` (**in-library OK, but spec-invalid — see below**); `ka`/`k` → bare, OK.

**Additional determinate fact — `\'`**: when a key (or string value) contains `'`, the writer emits `\'` (`writer.nim:153`). `\'` is **not in the v1.0.0 escape list** and **not in the v1.1.0 escape list** — both end with "All other escape sequences not listed above are reserved; if they are used, TOML should produce an error." The library's reader accepts it (`lexer.nim:443`), so it round-trips in-library, and tomllib raises `Unescaped '\' in a string` (`key_v100_kv_6B27.toml`, `rt_v100_str_apos.toml`, `rt_v100_str_ctrl_mix.toml`, `rt_v100_key_apos.toml`). Spec verdict: invalid in **both** v1.0.0 and v1.1.0 (the tomllib raise is confirmatory for v1.0.0; for v1.1.0 the spec text alone decides).

### Verdict per character (version-scoped; bare-key rules are identical in v1.0.0 and v1.1.0)

- `[`, `]`, `=`, `{`, `}`, `,` → written **bare** → **INVALID v1.0.0 AND INVALID v1.1.0**; library re-parse **FAILS for every one** on all three write paths; tomllib (v1.0.0) **raises for every one**. Prior analysis **CONFIRMED in full**.
- space → written **quoted** (`"k "`) → **VALID v1.0.0 and v1.1.0** (quoted keys follow basic-string rules; space allowed); round-trips; tomllib OK.
- `'` → written as quoted key containing `\'` → the `\'` escape is **invalid in both v1.0.0 and v1.1.0** even though the key itself round-trips in-library.

---

## Task 3 — general round-trip under `Toml_v100` (encode → decode → encode)

Method: each case is a single-key root table `{"v": value}` (unordered-table iteration cannot hide differences); verdicts use **exact byte comparison** of E1 vs E2 and of decoded string/key bytes — `TomlValueRef.==` was **not** used for any verdict (see tolerance findings below).

### Round-trip table (flavor `Toml_v100`, runtimeFlags `{}`)

| case | emitted (repr) | E1==E2 byte-exact | value bytes preserved | tomllib (v1.0.0) |
|---|---|---|---|---|
| str_plain `abc` | `  v="abc"` | YES | YES | OK |
| str_tab | `  v="a\tb"` | YES | YES | OK |
| str_nl | `  v="a\nb"` | YES | YES | OK |
| str_cr | `  v="a\rb"` | YES | YES | OK |
| str_esc `0x1B` | `  v="\e"` | YES | YES | **RAISE** (`\e` invalid v1.0.0; valid v1.1.0) |
| str_quote `say "hi"` | `  v="say \"hi\""` | YES | YES | OK |
| str_bs | `  v="a\\b"` | YES | YES | OK |
| str_apos `it's` | `  v="it\'s"` | YES | YES | **RAISE** (`\'` invalid v1.0.0 **and** v1.1.0) |
| str_eacute_utf8 `C3 A9` | `  v="\u00E9"` | YES | YES | OK |
| str_cjk 日本語 | `  v="\u65E5\u672C\u8A9E"` | YES | YES | OK |
| str_emoji U+1F600 | `  v="\U0001F600"` | YES | YES | OK |
| str_del `7F` | `  v="\u007F"` | YES | YES | OK |
| **str_lone_e9** (byte `E9`, invalid UTF-8) | `  v="\uFFFD"` | YES | **NO** — `E9` → `EF BF BD` | OK |
| **str_lone_ff** (byte `FF`) | `  v="\u00FF"` | YES | **NO** — `FF` → `C3 BF` | OK |
| str_empty | `  v=""` | YES | YES | OK |
| str_ctrl_mix `a 00 b 1B c " d \ e` | `  v="a\u0000b\ec\"d\\e"` | YES | YES | **RAISE** (at the `\e`; the `\u0000` passed) |
| int 42 / -17 | `  v=42` / `  v=-17` | YES | — | OK |
| float 3.141592653589793 | `  v=3.141592653589793` | YES | — | OK |
| float 1.00000001 | `  v=1.00000001` | YES | — | OK |
| bool true | `  v=true` | YES | — | OK |
| datetime 1979-05-27T07:32:00Z | `  v=1979-05-27T07:32:00Z` | YES | — | OK |
| arr_mixed `[1,"a",true]` | `  v=[1,"a",true]` | YES | — | OK |
| arr_nested | `  v=[[1,2],[3,4]]` | YES | — | OK |
| tbl_nested `{a:{b:1}}` | `  v.a.b=1` (dotted-key form, not `[v.a]` header) | YES | keys preserved | OK |
| inline `{x:1}` | `v={x = 1}` | YES | keys preserved | OK |
| aot (2 tables under `aot`) | `[[aot]]\x0A  name="a"\x0A[[aot]]\x0A  name="b"` | YES | keys preserved | OK |
| key_empty `""` | `  ""=1` | YES | YES | OK |
| key_dot `a.b` | `  "a.b"=1` (quoted — no dotted-key reinterpretation) | YES | YES | OK |
| **key_bracket `k[`** | `  k[=1` | — | — | RAISE — **library re-parse FAILS** `(1,5) expected "="` (Task 2 case, identical here) |
| key_space `k␠` | `  "k "=1` | YES | YES | OK |
| key_apos `k'` | `  "k\'"=1` | YES | YES | **RAISE** (`\'`) |
| key_uni ʎǝʞ `C9 8E CA 9E` | `  "\u024E\u029E"=1` | YES | YES | OK |

(All emitted lines carry the writer's two-space indent and unspaced `=`; both are legal TOML whitespace.)

### Non-round-trip summary (determinate)

1. **Value-level loss, spec-valid output**: lone bytes `E9` / `FF` (invalid UTF-8) are re-encoded as `\uFFFD` / `\u00FF` and come back as UTF-8 of U+FFFD / U+00FF (`E9→EF BF BD`, `FF→C3 BF`). The writer treats Nim strings as Unicode scalars (`writer.nim:137` iterates `runes`); byte content that is not valid UTF-8 is not preserved. E1==E2 remains stable (the loss is idempotent).
2. **No round-trip at all**: keys containing `[` `]` `=` `{` `}` `,` (Task 2).
3. **In-library round-trip YES but spec-invalid emission**: `\e` (invalid v1.0.0 only) and `\'` (invalid v1.0.0 **and** v1.1.0) — from `writer.nim:148` and `writer.nim:153` respectively.

### Where `TomlValueRef.==` would hide a mismatch (demonstrated, `types.nim:198`)

- `decoded(1.00000001) == 1.0` → **true** (a 1e-8 encoding difference is absorbed; `==` cannot certify byte-exact float round-trips).
- Non-transitivity demonstrated: `x=1.0`, `y=0.99999994`, `z=0.99999988` → `x==y` **true**, `y==z` **true**, `x==z` **false**.
- `Table{...} == InlineTable{...}` (same content) → **true** (the two kinds are equated by `==`; a kind change would be invisible).
- Strings and table keys compare exactly inside `==` (`types.nim:203-204`), but this probe did not rely on `==` for any verdict.

---

## Reproduce

2026-10-11 consolidation: the `repro.sh` driver was removed; the run's bytes are pinned in
`raw.tar.gz` (every member hash-enforced by the experiment-root `MANIFEST`; check with
`bash bsec/replay.sh verify`). The method — compile the three probes from a neutral cwd
(`/tmp`) with binaries in `/tmp/toml_wr_build`, run them into a scratch dir, run the
tomllib oracle — is fully specified above and in `probes/`; the checked-in `raw/` directory
holds this run's full logs and emitted documents (97 files).

## Verdict index

| # | claim | verdict |
|---|---|---|
| 1 | writer emits `\e` for 0x1B (writer.nim:148) | **CONFIRMED** (both flavors, identical bytes) |
| 2 | `\e` invalid TOML v1.0.0 | **CONFIRMED** (spec text + tomllib) |
| 3 | `\e` added in TOML v1.1.0 | **CONFIRMED** (verbatim v1.1.0 escape list) |
| 4 | `\e` round-trips through the library | **YES, both flavors** (reader accepts unconditionally, lexer.nim:438) |
| 5 | keys with `[` `]` `=` `{` `}` `,` written bare (writer.nim:168-180) | **CONFIRMED** (all three write paths, both flavors) |
| 6 | those bare keys are invalid TOML | **CONFIRMED for v1.0.0 and v1.1.0** (bare keys = `A-Za-z0-9_-` in both) |
| 7 | those keys fail the library's own re-parse | **CONFIRMED — none round-trip** |
| 8 | space keys | quoted, valid, round-trip (both flavors, both spec versions) |
| 9 | extra finding: `\'` emitted for `'` in strings/quoted keys | **spec-invalid in BOTH v1.0.0 and v1.1.0**; in-library round-trip YES; tomllib raises (v1.0.0 confirmatory) |
| 10 | extra finding: non-UTF-8 Nim string bytes not preserved | `E9→EF BF BD`, `FF→C3 BF` via `\uFFFD`/`\u00FF`; spec-valid output, lossy value |
| 11 | extra finding: `TomlValueRef.==` | 1E-7 float tolerance (hides 1.00000001 vs 1.0), non-transitive (demonstrated), Table==InlineTable |
