All evidence is in. Compiling the final ranked report.

# Contradiction Candidates — nim-toml-serialization

Ranked, most likely genuine first. All citations verified against repository bytes.

---

## 1. "Pass these test suites" — the conformance runner skips ~40 cases, including the advertised v1.1.0 features and several *invalid* fixtures

**Confidence: high** — the claim and the runner are both in-repo, and CI (`.github/workflows/ci.yml`, `test-command: ... spec_test/run_test.sh`) runs exactly this script.

**(a) PROPOSITION:** README claims the library "implements v1.1.0 TOML spec and pass these test suites" (iarna + burntsushi), but the repo's own conformance runner excludes ~40 test cases via `-skip`, including every datetime case, the hex-escape case, and invalid-input cases (meaning the parser accepts documents the suite marks invalid).

**(b) FORMALIZABLE PROPERTY:** For each fixture F in the suite with expected outcome O ∈ {valid, invalid}: `parse(F) succeeds ⟺ O == valid`. The skip list removes dozens of (F, O) pairs from verification, so the universal claim is not established by the repo's own machinery; for skipped invalid fixtures the repo's own tooling would show `parse(F) succeeds` while O = invalid.

**(c) GROUNDING:**
- Claim — `README.md:64-69`: "nim-toml-serialization implements [v1.1.0](…) TOML spec and pass these test suites: - [iarna toml test suite](…) - [burntsushi toml test suite](…)"
- Runner — `spec_test/run_test.sh:47-64` (v1.0.0): `-skip="invalid/table/super-twice"`, `-skip="invalid/table/duplicate-key-07"`, `-skip="invalid/control/bare-cr"`, `-skip="valid/float/inf-and-nan"`, `-skip="valid/comment/tricky"` …
- `spec_test/run_test.sh:73-108` (v1.1.0): `-skip="valid/datetime/datetime"`, `-skip="valid/datetime/no-seconds"` (line 81 — the HH:MM feature the README advertises!), `-skip="valid/string/hex-escape"` (line 98 — the TomlHexEscape feature!), `-skip="valid/spec-1.1.0/common-12"` … `-skip="invalid/control/multi-cr"`, `-skip="invalid/table/append-with-dotted-keys-01"`.

**(d) COUNTEREXAMPLE APPROACH:** Run `spec_test/run_test.sh` (as CI does) with the skips removed. Expected failures include `invalid/table/duplicate-key-07` (parser accepts a duplicate key; cf. `lexer.nim:1894-1916` `createTable` only rejecting some redefinitions) and `invalid/control/bare-cr` (`lexer.nim:207-210` treats `CR` as ordinary whitespace in `nonws`, so a bare CR is accepted; `lexer.nym:184` doesn't even count CR as a line break). Documented expectation: every suite case passes.

---

## 2. Built-in enum writer emits strings, contradicting the README's "ordinal built-in writer" claim

**Confidence: high** — code, tests, and README directly disagree; the test suite is even *named* OrdinalEnum while asserting string output.

**(a) PROPOSITION:** README states "the writer/encoder only has an `ordinal` built-in writer" (ordinal = TOML integer), but the built-in writer emits the enum's *string* representation (`$value`), and the repo's own tests assert string output.

**(b) FORMALIZABLE PROPERTY:** Pre: `v` is any Nim enum value; Post: `Toml.encode(Wrapper(v: v))` contains the quoted case name (e.g. `"v = \"x0\"\n"`), never the bare ordinal (`v = 0`). The code and tests satisfy this — the README asserts the opposite.

**(c) GROUNDING:**
- Code — `toml_serialization/writer.nim:482-484`:
  ```nim
  elif value is enum:
    checkAutoSerialization(Flavor, typeof(value), value):
      w.writeValue $value
  ```
- Claim — `README.md:321-327`: "While on the other hand, the writer/encoder only has an `ordinal` built-in writer. … The `ordinal` representation of an enum is TOML integer."
- Test — `tests/test_encoder.nim:196-208`: suite/test named `OrdinalEnum` checks `Toml.encode(Wrapper(v: x0)) == "v = \"x0\"\n"` (string, not `v = 0`).

**(d) COUNTEREXAMPLE APPROACH:** Encode `Wrapper(v: x0)` with no user overload: code produces `v = "x0"`; the README's claim requires `v = 0`. The README's follow-up example ("write enum output as a string" via `proc writeValue*(w: var TomlWriter, val: Fruits) = w.writeValue $val`, `README.md:356-361`) is redundant — the built-in already does exactly that (see identical overload in `tests/test_features.nim:350-351`).

---

## 3. Control characters (0x01–0x07, 0x0B, 0x0C, 0x0E–0x1E except 16/31; 0x08 in multi-line) are accepted inside strings, violating the claimed spec conformance

**Confidence: high** — the same lexer file uses the *correct* full range for comments, proving the string sets are not a stylistic choice.

**(a) PROPOSITION:** The lexer only rejects bytes {8, 16, 31, 127} in single-line strings and {16, 31, 127} in multi-line strings, while TOML v1.0.0/v1.1.0 (which the README claims to implement) forbids U+0000–0008, U+000A–001F, U+007F in all strings.

**(b) FORMALIZABLE PROPERTY:** Pre: input document contains a raw control byte c ∈ {0x01..0x07, 0x0B, 0x0C, 0x0E..0x15, 0x17..0x1E} inside a basic or literal string (or c = 0x08 in a multi-line string). Post (spec): parse raises; Post (actual): parse succeeds and yields the control char in the value. (NUL only raises accidentally: `EOF* = '\0'` at `lexer.nim:72` makes a mid-stream NUL hit the `errUnterminatedString` check at `lexer.nim:551`.)

**(c) GROUNDING:**
- Code — `toml_serialization/lexer.nim:554` (multi-line): `if ord(next) in {16, 31, 127}:` and `lexer.nim:588` (single-line): `if ord(next) in {8, 16, 31, 127}:`
- Same file, correct range for comments — `lexer.nim:75`: `invalidCommentChar = {'\x00'..'\x08', '\x0A'..'\x1F', '\x7F'}`
- Claim — `README.md:64-65` ("implements v1.1.0 … spec"); tests only cover comments: `tests/test_decoder.nim:618-632` ("invalid chars in comment" — nothing for strings except `\b` at `test_lexer.nim:265`).
- Fixture side: the vendored iarna control fixtures contain exactly 0x00/0x10/0x1F/0x7F (hexdumped: `string-basic-control-2.toml` = `a = "ctrl-P\x10"`), i.e. precisely the members of the ad-hoc sets — the suite cannot catch the gap.

**(d) COUNTEREXAMPLE APPROACH:** Input `a = "bell\x07x"` (raw 0x07 byte). Code: parses successfully to `"bell\x07x"` (0x07 ∉ {8,16,31,127}; UTF-8 validator accepts it per `private/utf8_validate.nim:17-21` where table[0x07]=0). Spec expectation (both v1.0.0 and the v1.1.0 draft): parse error. Likewise `a = """\x08"""` (raw 0x08 in multi-line) is accepted since the multi-line set omits 8.

---

## 4. `innerValue`'s TomlDate/TomlTime branches cannot compile (`n.dateDimte`) — the exported typed accessor contract is broken and untested

**Confidence: medium-high** — the defect is certain (two occurrences, no other definition of `dateDimte`); it's a doc/API-contract contradiction rather than a README contradiction, and no test exercises these branches.

**(a) PROPOSITION:** The exported accessor `node[name, T]` is provided for typed extraction from `TomlValueRef`, and `innerValue` has dedicated branches for `TomlDate`/`TomlTime`, but those branches reference the non-existent field `dateDimte` (typo for `dateTime`), so any instantiation with `TomlDate` or `TomlTime` fails to compile.

**(b) FORMALIZABLE PROPERTY:** Pre: `v` is a `TomlValueRef` with `kind == TomlKind.DateTime` and `dateTime.date.isSome`. Post (contract): `v["k", TomlDate]` compiles and equals `v.dateTime.date.get`. Actual: does not compile (`undeclared identifier: 'dateDimte'`). Compile-time checkable, hence cleanly formalizable.

**(c) GROUNDING:**
- Code — `toml_serialization/value_ops.nim:31-32`: `elif T is TomlDate: if n.kind == TomlKind.DateTime: if n.dateTime.date.isSome: result = n.dateDimte.date.get` and `value_ops.nim:35-36`: `... result = n.dateDimte.time.get`
- Contract — `value_ops.nim:86-87`: `proc `[]`*(node: TomlValueRef, name: string, T: type): T … node[name].innerValue(T)`; README promotes mixed decode: `README.md:39-41` ("Decode into Nim data types mixed with `TomlValueRef` …").
- Test side — the only typed accessor use in tests is string-typed (`tests/test_decoder.nim:654`: `x["fruit"]["color", string]`); `tests/test_value_ops.nim` never touches `TomlDate`/`TomlTime` extraction — conspicuously unasserted.

**(d) COUNTEREXAMPLE APPROACH:** `Toml.decode("d = 1979-05-27", TomlValueRef)["d", TomlDate]` — Nim compile error "undeclared identifier: 'dateDimte'" (`value_ops.nim:32`). Documented expectation: the date is returned.

---

## 5. Manifest version 0.2.18 vs README's "Since v0.3.0" feature claims (v1.1.0 by default)

**Confidence: medium** — a version-hygiene contradiction, fully grounded in bytes + git tags; behavior itself is not in dispute.

**(a) PROPOSITION:** The README's changelog assigns v1.1.0-by-default and related features to "v0.3.0", and the default flavor indeed ships v1.1.0 flags, but the package version is still 0.2.18 — a 0.2.x release carrying 0.3.0-documented behavior.

**(b) FORMALIZABLE PROPERTY:** Not a behavioral property; formalizable only as manifest invariant "documented feature version ≤ package version". Clean formalization not meaningful beyond that.

**(c) GROUNDING:**
- `toml_serialization.nimble:4`: `version       = "0.2.18"`
- `README.md:54-57`: "Since v0.3.0: - `tokKind` parser … - Flavors … - TOML v1.1.0 features enabled by default"
- Behavior confirms the 0.3.0-level state — `toml_serialization/format.nim:36`: `template flavorRuntimeFlags*(_: type Toml): set[TomlFlag] = Toml_v110_Flags`
- Git: latest tag `v0.2.18`; `62dcb2c Enable TOML v1.1.0 (#115)` (and `096659b`, `7352976`) landed after it with no version bump.

**(d) COUNTEREXAMPLE APPROACH:** A consumer pinning `toml_serialization >= 0.2.18 < 0.3.0` per the README's own version history expects v1.0.0 semantics (e.g. `a = { x = 1, }` rejected); the delivered 0.2.18 accepts it (trailing-comma flag on). The README's changelog requires the version bump that never happened.

---

## 6. Suite "toml v1.0.0 spec" test "trailing commas not allowed in inline table" passes for the wrong reason, under a flavor where trailing commas are allowed

**Confidence: medium** — indisputable that the assertion is vacuous; whether a test-internal suite name counts as a "claim" is a judgment call.

**(a) PROPOSITION:** The test named "trailing commas not allowed in inline table" (in a suite named "toml v1.0.0 spec") uses `Toml.decode` (default flavor, `TomlInlineTableTrailingComma` on) with input containing a colon (`{subkey: "val", }`), so it fails on the missing `=` — never exercising the trailing comma — while the same flavor accepts `{a=1, b=2, c=3, }`.

**(b) FORMALIZABLE PROPERTY:** Pre: `Toml.decode("key = {subkey = \"val\", }", TomlValueRef)` (correct v1.0.0 probe, default flavor). Expected by test's name/suite: error. Actual: succeeds (flag on at `lexer.nim:1701-1705`). The test's actual input raises only because `lexer.nim:1724-1726` demands `=`.

**(c) GROUNDING:**
- Test — `tests/test_decoder.nim:634-636`: `test "trailing commas not allowed in inline table": expect TomlError: discard Toml.decode("key = {subkey: \"val\", } ", TomlValueRef)`
- Flag default-on — `toml_serialization/format.nim:28-34` (`Toml_v110_Flags` includes `TomlInlineTableTrailingComma`) + `lexer.nim:1702`: `if TomlInlineTableTrailingComma in lex.flags: … return` (accept)
- Acceptance proof in the same file — `tests/test_decoder.nim:303-304`: `Toml.decode("x = {a=1, b=2, c=3, }", TomlValueRef, "x", {TomlInlineTableTrailingComma})` succeeds.

**(d) COUNTEREXAMPLE APPROACH:** Replace the probe with `key = {subkey = "val", }` under the same default flavor: v1.0.0 semantics (per the suite's name) require an error; the code accepts it. The existing test cannot detect this because its input dies on `:` first.

---

## 7. `writeKey` doesn't quote keys containing `=`, `[`, `]`, `{`, `}`, `,` — encoder output is not "full spec TOML"

**Confidence: medium-low** — certain from code, but the claim it contradicts ("full spec TOML", `README.md:44`) is a terse marketing line, and no in-repo test constructs such keys.

**(a) PROPOSITION:** The README claims `TomlValueRef` encoding produces "full spec TOML", but `writeKey` only quotes keys containing chars in `{'\0'..'\32', '.', '"', '\'', '#', '\127'..'\255'}` — a key like `a=b` is emitted bare, producing a document that violates the TOML grammar (bare keys are limited to `A-Za-z0-9_-`) and cannot be re-parsed by the library's own lexer.

**(b) FORMALIZABLE PROPERTY:** Pre: table with key k containing a char ∉ `[A-Za-z0-9_-]` and ∉ the escape set (e.g. `=`). Post (claim): `encode` output is a valid TOML document that parses back to the same value. Post (actual): output `a=b = 1`, which the library's own `scanName` rejects (`lexer.nim:714-715` raises `errIllegalChar` on `=`).

**(c) GROUNDING:**
- Code — `toml_serialization/writer.nim:166-180`: `shouldEscape = {'\0'..'\32', '.', '\"', '\'', '#', '\127'..'\255'}`; bare output otherwise (`append s`).
- Claim — `README.md:44`: "- Encode `TomlValueRef` into full spec TOML."
- Supporting evidence of a disabled guard — `writer.nim:466`: `#doAssert(value.kind in {TomlKind.Table, TomlKind.InlineTable})` (root-kind restriction commented out).

**(d) COUNTEREXAMPLE APPROACH:** `Toml.encode(TomlValueRef(kind: Table, tableVal: {"a=b": int-ref}))` → output `a=b = 1\n`; feeding it back to `Toml.decode(…, TomlValueRef)` raises `illegal character '='`. Claim requires valid, round-trippable output. (Adjacent, same claim: an `Array`-kinded root `TomlValueRef` encodes as `=[1, 2]` since `writeKeyValue` unconditionally appends `=` for non-`noKey` writes, `writer.nim:225-234`.)

---

## Dimensions that yielded nothing reportable

- **(b) Paired producer/consumer consistency:** reader/writer round-trips for `TomlTime`/`TomlDateTime`/inline tables are consistent when both sides use the same flags (`tests/test_encoder.nim:53-57, 113-124`); the `TomlHourMinute` writer omission of `:00` (`writer.nim:88-89`) matches the reader's flag-gated acceptance (`lexer.nim:1056-1060`). The float `==` epsilon (`types.nim:193-198`, `abs(a-b) < 1E-7`, NaN==NaN true) is suspicious but no in-repo claim or test is contradicted by it.
- **(c) Version-gated flags vs gated behavior:** `Toml_v100` correctly resolves to empty flags (`format.nim:51-53`, `toml_serialization.nim:26-30`), and the flag-gated lexer branches match the README's feature descriptions — modulo candidates 1, 3, and 6 above.
- **(d) Silently weakened tests:** beyond candidates 1/6, one honest `skip()` exists (`tests/test_decoder.nim:592-598`, `requiresInit` support disabled with an explanatory comment), and the `tomlOrderedTable` roundtrip suite is disabled with an in-file TODO (`test_spec.nim:70-73`: "the encoder/writer still cannot produce ordered result correctly") despite the README advertising the switch (`README.md:50-51`) — noted here since it straddles (d), but the limitation is self-declared rather than hidden, so it is not ranked as a candidate.