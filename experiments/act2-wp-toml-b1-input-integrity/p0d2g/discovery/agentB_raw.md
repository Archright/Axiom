All evidence is gathered. Here is my final report.

---

# Contradiction candidates — nim-toml-serialization

Ranked, most likely genuine first. Every claim is grounded in repository bytes; no builds/tests were run.

## 1. Built-in enum writer: README says "ordinal (integer)", code and tests say string — high confidence (three-way disagreement; tests side with the code)

**(a) PROPOSITION.** README.md claims "the writer/encoder only has an `ordinal` built-in writer" (ordinal = TOML integer), but the built-in writer emits the enum's *string* form, and the repo's own encoder tests assert the string form as built-in behavior.

**(b) FORMALIZABLE PROPERTY.** For enum `E = enum x0, x1, x2` and `W = object v: E`, with no user `writeValue` overload: documented postcondition — `encode(W(v: x0))` contains `v = 0`; actual postcondition — `encode(W(v: x0)) == "v = \"x0\"\n"`.

**(c) GROUNDING.**
- Doc: `README.md:322-327` — "the reader/decoder can parse both the `ordinal` or `string` representation of an enum. While on the other hand, the writer/encoder only has an `ordinal` built-in writer. … The `ordinal` representation of an enum is TOML integer." README.md:356-357 even shows a *custom* overload being needed "to write enum output as a string".
- Code: `toml_serialization/writer.nim:482-484` — `elif value is enum: checkAutoSerialization(...): w.writeValue $value` (dispatches to the string writer at writer.nim:131).
- Test: `tests/test_encoder.nim:205-208` — `Toml.encode(Wrapper(v: x0)) == "v = \"x0\"\n"` with **no** custom overload defined for `EnumTest`.

**(d) COUNTEREXAMPLE APPROACH.** `Toml.encode(Wrapper(v: x0))` → code produces `v = "x0"`; README's claim requires `v = 0`. Trivially checkable by compiling the README's ownEnums section minus the optional overload.

## 2. README's worked enum example decodes an ordinal with default config; the reader rejects ordinals by default — high confidence

**(a) PROPOSITION.** README's fruits example decodes `fruit2 = 1` into an enum field with no configuration and asserts success; `parseEnum` raises unless `allowNumericRepr` is enabled, and `tests/test_decoder.nim` asserts that numeric enum input **fails** by default.

**(b) FORMALIZABLE PROPERTY.** Precondition: input `fruit2 = 1` (or `v = 1`), target type an enum without `configureTomlDeserialization`. Documented postcondition: decodes to `Banana`/`x1`. Actual postcondition: raises `TomlError` ("illegal character").

**(c) GROUNDING.**
- Doc: `README.md:321-323` ("can parse both the `ordinal` or `string` representation"), `README.md:332-336` (`fruit2 = 1   # ordinal value` in fruits.toml), `README.md:350-353` (`var x = Toml.loadFile("fruits.toml", FruitBasket); assert x.fruit2 == Banana` — no configuration call).
- Code: `toml_serialization/reader.nim:134-136` (`allowNumericRepr: static[bool] = false`), reader.nim:152-154 (`else: raiseIllegalChar(r.lex, next)`).
- Tests: `tests/test_decoder.nim:338-345` — `expect TomlError: discard Toml.decode("v = 0\n", EnumTestX, "v")` (same for `1`, `2`); `tests/test_features.nim:347-348` — the repo's own fruits.toml test only passes through a *custom* `readValue` with `allowNumericRepr = true`; `tests/test_compile_time.nim:16-20` sidesteps by typing `fruit2: int`.

**(d) COUNTEREXAMPLE APPROACH.** Run README.md:350-353 verbatim against `tests/tomls/fruits.toml` (fixture contains `fruit2 = 1`): code raises; README requires `x.fruit2 == Banana`. Verified grep: no library-internal default enables numeric repr anywhere.

## 3. Blanket "implements v1.1.0 spec / passes both test suites" claim vs incomplete control-character rejection and ~25 skipped spec tests — high confidence on the code fact

**(a) PROPOSITION.** README claims full v1.1.0 spec conformance and passing the iarna/burntsushi suites, but the lexer accepts raw control characters (e.g. 0x01, 0x0B) inside basic, literal and multi-line strings — it rejects only {8,16,31,127} single-line / {16,31,127} multi-line — and the repo's own spec harness runs with extensive skip lists (including many *valid* tests).

**(b) FORMALIZABLE PROPERTY.** Precondition: document containing a raw byte 0x01 inside a string, e.g. `k = "<0x01>"` or `k = """<0x0B>"""`. Postcondition per the spec the README invokes (forbidden: U+0000–U+0008, U+000A–U+001F, U+007F in strings): decode raises. Actual postcondition: decode succeeds and yields the control byte as string content.

**(c) GROUNDING.**
- Doc: `README.md:64-69` — "nim-toml-serialization implements v1.1.0 TOML spec and pass these test suites: iarna… burntsushi…".
- Code: `toml_serialization/lexer.nim:588` — `if ord(next) in {8, 16, 31, 127}: raiseInvalidChar(lex, next)` (single-line); `lexer.nim:554` — `if ord(next) in {16, 31, 127}: raiseInvalidChar(lex, next)` (multi-line). Contrast the repo's own complete sets: `lexer.nim:75` `invalidCommentChar = {'\x00'..'\x08', '\x0A'..'\x1F', '\x7F'}` and `writer.nim:133` `lowEscape = {'\0'..'\31'} - {...}` — the encoder always escapes these bytes, so the decoder accepts documents the encoder itself could never emit unescaped.
- Tests/harness: `spec_test/run_test.sh:49-64` and `73-108` — 15 skips for v1.0.0 and 26 for v1.1.0, including valid cases (`valid/float/inf-and-nan`, `valid/datetime/datetime|edge|local|local-time|no-seconds`, `valid/spec-1.1.0/common-12…34`, `valid/spec-example-1`). Git commit `096659b` shows 8 was added to the single-line set only when the suite was run against toml-test v2.2.0 — reactive patching of an incomplete set. `tests/test_lexer.nim:721-725` exercises control chars only in *comments*, never inside strings.

**(d) COUNTEREXAMPLE APPROACH.** Decode `key = "<raw 0x01>"` into `TomlValueRef`: code returns a String containing 0x01; the README's conformance claim requires a `TomlError`. (Also note run_test.sh's own skips contradict the unqualified "pass these test suites".)

## 4. `loadFile` drops `tomlCase` before reader init; `decode` keeps it — the two documented sibling APIs disagree on field matching — medium-high confidence

**(a) PROPOSITION.** `Toml.loadFile(filename, T, key, tomlCase)` passes `tomlCase` only to key navigation, not to `TomlReader.init`, so field matching inside the record stays case-sensitive — while the parallel `Toml.decode(input, T, key, tomlCase)` passes it to init and matches case-insensitively.

**(b) FORMALIZABLE PROPERTY.** Precondition: doc `owner = { NAME = "Tom" }`; `Owner = object name: string`; calls `loadFile(f, Owner, "owner", TomlCaseInsensitive)` and `decode(doc, Owner, "owner", TomlCaseInsensitive)`. Expected (API parity): both succeed with `name == "Tom"`. Actual: `decode` succeeds; `loadFile` raises "Unexpected field 'NAME'" because `r.tomlCase` is `TomlCaseSensitive`.

**(c) GROUNDING.**
- Code: `toml_serialization/decoder.nim:73` — `var reader = unpackArgs(init, [TomlReaderType, stream, params])` (loadFile path: no tomlCase) vs `decoder.nim:48` — `unpackArgs(init, [TomlReaderType, stream, tomlCase, params])` (decode path); `decoder.nim:77` — `reader.moveToKey(key, tomlCase)` (loadFile uses it only here); `reader.nim:62-67` — init stores `tomlCase` (defaults `TomlCaseSensitive` via reader.nim:69-72); field lookup uses `r.tomlCase` at reader.nim:324-325 and reader.nim:372-373.
- Doc: `README.md:187-194` presents `loadFile`/`decode` as symmetric (`Toml.loadFile("filename.toml", ip, "server.ip")`).
- Test gap: `tests/test_features.nim:276` exercises `loadFile` + case only for keyed *string* extraction (which bypasses `findFieldReader`); no test covers loadFile + case + object fields.

**(d) COUNTEREXAMPLE APPROACH.** As in (b): write `owner = { NAME = "Tom" }` to a file, call `Toml.loadFile(file, Owner, "owner", TomlCaseInsensitive)` → raises, while the equivalent `Toml.decode` succeeds.

## 5. Unknown-field rejection is order-dependent, and the test codifies the weakening — medium confidence

**(a) PROPOSITION.** README presents unknown-field skipping as gated by `TomlUnknownFields`, but `decodeRecord` stops reading once all declared fields are seen, so without the flag an unknown key raises only if it appears *before* the last known field — and the test explicitly asserts both behaviors under the title "TomlUnknownField not enabled".

**(b) FORMALIZABLE PROPERTY.** Precondition: `UnknownField = object apple: int`; input `apple = 1\nbanana = 2`, no flags. Flag-gated semantics predict `TomlError` for `banana`. Actual: success (`apple == 1`, `banana` silently dropped). Reverse order raises.

**(c) GROUNDING.**
- Doc: `README.md:46-49` — "Allow skipping unknown fields using the `TomlUnknownFields` flag."
- Code: `toml_serialization/reader.nim:345-346` — `if fieldsDone >= totalFields: break`.
- Test: `tests/test_toml_v110.nim:61-68` — `expect TomlError` for `unknownFields1` (`banana` first), then "no exception if the unknown fields come after known fields due to internal optimization" for `unknownFields2`.

**(d) COUNTEREXAMPLE APPROACH.** `Toml.decode("apple = 1\nbanana = 2", UnknownField)` returns normally; the flag-gated reading of README predicts an error. Behavior is certain; the "contradiction" hinges on README not promising an exception — but the test's own title shows the repo once claimed rejection.

## 6. `TomlHourMinute` — documented as parse-side leniency — silently abbreviates *encoder* output on the default flavor — medium-low confidence

**(a) PROPOSITION.** README frames `TomlHourMinute` as allowing `HH:MM` when *parsing*, but because the default `Toml` flavor force-adds the v1.1 flags, the *writer* omits `:00` for zero-second times — producing output that a TOML 1.0 consumer (e.g. `Toml_v100`) cannot re-read — and no test asserts default-flavor time encoding.

**(b) FORMALIZABLE PROPERTY.** `Toml.encode(TopTime(time: TomlTime(hour:13, minute:5, second:0, subsecond:0)))` → actual `time = 13:05`; expected per README's framing (flag = parsing allowance; standard requires HH:MM:SS): `time = 13:05:00`.

**(c) GROUNDING.**
- Code: `toml_serialization/writer.nim:88-89` — `if TomlHourMinute in w.flags and time.second == 0 and time.subsecond == 0: return`; writer init adds flavor flags (writer.nim:38-39); `format.nim:36` — `template flavorRuntimeFlags*(_: type Toml) = Toml_v110_Flags` (includes `TomlHourMinute`, format.nim:28-34).
- Doc: `README.md:82-83` — "TOML standard requires time in HH:MM:SS format, `TomlHourMinute` flags will allow HH:MM format."
- Tests/harness: `tests/test_features.nim:401` asserts full `two = 13:05:00` only for `Toml_v100.encode` (flags off); `spec_test/run_test.sh:77-81` skips *all* `valid/datetime/*` for the v1.1 decoder — consistent with the writer's abbreviation breaking the harness's canonical JSON comparison.

**(d) COUNTEREXAMPLE APPROACH.** Encode a zero-second `TomlTime` with the default flavor and feed the result to `Toml_v100.decode` → error; with the default flavor round-trip the seconds information (`13:05:00` vs `13:05`) is not preserved verbatim.

## 7. README attributes features to "v0.3.0"; manifest and tags say 0.2.18 — medium-low confidence (doc/metadata drift)

**(a) PROPOSITION.** README documents tokKind, flavors, and v1.1.0-by-default as "Since v0.3.0", but the nimble manifest is still `0.2.18` and no v0.3.0 tag exists — the README references a release the repository itself never made.

**(b) FORMALIZABLE PROPERTY.** Not behavioral; metadata invariant: manifest version ≥ any version the README cites as shipping features, or the citation is false. Not cleanly formalizable over program inputs/outputs.

**(c) GROUNDING.** `README.md:54-58` ("Since v0.3.0: `tokKind` parser… Flavors… TOML v1.1.0 features enabled by default") vs `toml_serialization.nimble:4` (`version = "0.2.18"`); `git tag` maxes at `v0.2.18` (verified).

**(d) COUNTEREXAMPLE APPROACH.** `nimble install toml_serialization` yields 0.2.18, which per the README's own versioning should lack all three feature groups — yet they are in the tree. One side is stale; likely the manifest.

---

**Dimensions that yielded nothing significant / supplementary notes:**
- **Version-gated flags (dimension c):** otherwise clean — `Toml_v100` vs `Toml` flag gating (format.nim:26-58) behaves exactly as README.md:71-88 describes per flag; `tests/test_toml_v110.nim` pins it.
- **Silently skipped/weakened tests (dimension d), not counted above:** `tests/test_spec.nim:70-79` compiles out *all* round-trip suites under the README-documented `-d:tomlOrderedTable` switch ("TODO: the encoder/writer still cannot produce ordered result correctly"), and test_spec.nim:91-94 excludes `spec.toml` per-platform; `tests/test_decoder.nim:592-598` is an unconditional `skip()` for `Option[requiresInit]` ("worked only due to bugs"). These are explicit and commented, so they read as acknowledged debt rather than contradictions — but they mean the README's `-d:tomlOrderedTable` feature ships with an untested (and self-admittedly broken) writer path.
- **Lexer/history note:** the narrow control-char sets of candidate 3 date to the initial commits and were last touched reactively (commit `096659b` added only `8`), reinforcing that the sets are incomplete rather than principled.