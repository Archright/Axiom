# ORACLE — duplicate keys & trailing-content (input-integrity judgment record)

- **Experiment**: `act2-wp-toml-b1-input-integrity`
- **Prepared**: 2026-10-11 (ORACLE side only). The subject library (`status-im/nim-toml-serialization`) was **NOT** executed in this record. No security-impact or severity assessment is made. No issue is filed anywhere.
- **Oracle scope**: **TOML 1.0.0** (the version our tests pin).

---

## 0. Authority statement — the SPEC is the oracle, not majority vote

**The oracle is the TOML 1.0.0 specification text itself.** Reference parsers (tomllib, tomlkit, Rust `toml`/`toml_edit`) are **cross-checks only**: their agreement is neither necessary nor sufficient for a conformance verdict. Where a parser's behavior differs from the spec text, the spec text governs. Implementation consensus must never be cited as the reason a document is invalid.

`tomllib` is admissible as an **auxiliary** oracle for the two observations under test because (a) its official documentation states it parses TOML 1.0.0 (quoted in §3.1) and (b) both observations are 1.0.0-level grammar/semantics questions where no implementation-specific latitude is in play.

**Source-version caveat.** The `main` branch of `toml-lang/toml` is the working draft (TOML 1.1.0-dev: adds `\e`, `\xHH` escapes, multi-line inline tables; its ABNF header also differs). All quotes below are taken from the **pinned tag `1.0.0`** (raw URLs) and the canonical published page `https://toml.io/en/v1.0.0`. The two duplicate-key sentences happen to be textually identical in the draft, but the draft text must not be cited as 1.0.0. Similarly, the Rust "latest" cross-check resolved to crates that target spec-1.1.0 (`toml 1.1.8+spec-1.1.0`, `toml_edit 0.25.17+spec-1.1.0`); a TOML-1.0.0-era pin (`toml 0.8.23`, `toml_edit 0.22.27`) was run in addition. For these two cases (duplicate key; trailing invalid bytes) both generations reject, so the cross-check stands under either spec generation.

---

## 1. Verbatim spec clauses

### 1.1 Duplicate keys

**Primary clause** — https://toml.io/en/v1.0.0 § Keys (canonical raw source: `https://raw.githubusercontent.com/toml-lang/toml/blob/1.0.0/toml.md`, tag `1.0.0`, line 178):

> Defining a key multiple times is invalid.

Immediate surrounding text (verbatim continuation):

> Indentation is treated as whitespace and ignored.
>
> Defining a key multiple times is invalid.
>
> ```
> # DO NOT DO THIS
> name = "Tom"
> name = "Pradyun"
> ```
>
> Note that bare keys and quoted keys are equivalent:

**Tables analogue** — https://toml.io/en/v1.0.0 § Table (tag `1.0.0`, line 709):

> Like keys, you cannot define a table more than once. Doing so is invalid.

**Wording characterization (important for the report).** The operative predicate is **"invalid"** — an absolute property of the document — not an imperative "must"/"should". The TOML spec carries **no RFC 2119 boilerplate**. Its normative vocabulary, observed in the 1.0.0 text:

| Vocabulary | Force | 1.0.0 examples |
|---|---|---|
| "invalid" | document-class rejection (absolute) | "Defining a key multiple times is invalid."; "Unspecified values are invalid."; "Like keys, you cannot define a table more than once. Doing so is invalid." |
| "must" | hard requirement | "There must be a newline (or EOF) after a key/value pair."; "A TOML file must be a valid UTF-8 encoded Unicode document."; "an error must be thrown" (unrepresentable integer) |
| "must produce an error at parse time" | strongest operative form (used only in § Array of Tables) | "Attempts to reverse that ordering **must produce an error at parse time**."; "Attempting to append to a statically defined array, even if that array is empty, **must produce an error at parse time**."; "Attempting to define a normal table with the same name as an already established array **must produce an error at parse time**. Attempting to redefine a normal table as an array must likewise produce a parse-time error." |
| "should" | advisory, non-normative | "All other escape sequences not listed above are reserved; if they are used, TOML **should** produce an error."; "TOML parsers should feel free to normalize newline..." |

The three "must produce an error at parse time" sentences: https://toml.io/en/v1.0.0 § Array of Tables (tag `1.0.0` toml.md lines 938, 952, 962).

### 1.2 Document-level validity / trailing content

The spec establishes validity of the document **as a whole**:

1. **Preliminaries** — https://toml.io/en/v1.0.0:
   > A TOML file must be a valid UTF-8 encoded Unicode document.
2. **Overall structure** — ABNF, `https://raw.githubusercontent.com/toml-lang/toml/blob/1.0.0/toml.abnf` (tag `1.0.0`, line 18):
   > toml = expression *( newline expression )
3. **ABNF header note** — same file (tag `1.0.0`, lines 4–6):
   > ;; All valid TOML documents will match this description, however certain
   > ;; invalid documents would need to be rejected as per the semantics described
   > ;; in the supporting text description.
4. **Local supporting clause** — https://toml.io/en/v1.0.0 § Key/Value Pair:
   > There must be a newline (or EOF) after a key/value pair. (See Inline Table for exceptions.)

**Reading (for the judgment record).** The `toml` start rule spans the *entire* input; there is no provision for a parser to succeed on a proper prefix of the document. Trailing bytes that are not derivable as `*( newline expression )` (e.g. a line beginning `!`, which cannot start a `simple-key`, `table`, or `comment`) leave the document non-matching → the document is invalid → it must be rejected. The ABNF header note exists for the *converse* case: some semantic rules (duplicate keys, table redefinition, type conflicts) are not expressible in the ABNF, so documents that *do* match the grammar can still be invalid and "would need to be rejected as per the semantics described in the supporting text" — §1.1 is exactly such a rule. Both classes (grammar-invalid; grammar-valid-but-semantically-invalid) are invalid documents under TOML 1.0.0.

### 1.3 Unknown keys / typed decoding — the spec is SILENT

Full-text search of the pinned 1.0.0 sources (`toml.md` + `toml.abnf` at tag `1.0.0`) and the `main` draft finds **zero occurrences** of: `unknown`, `intermediate`, `final representation`, `schema`, `typed`, `deserial*`, `unmarshal`. `partial` occurs only as `partial-time` (date-time ABNF rule); `application` occurs only as the MIME type `application/toml`. The prior finding (zero matches for "intermediate"/"final representation"/"partial") is **confirmed and extended**.

The spec's entire scope statement — https://toml.io/en/v1.0.0 § Objectives:

> TOML aims to be a minimal configuration file format that's easy to read due to
> obvious semantics. TOML is designed to map unambiguously to a hash table. TOML
> should be easy to parse into data structures in a wide variety of languages.

**Consequence** — the spec defines document validity only; it says nothing about which keys an application's target structure accepts, nor about decoding into application types, nor about partial consumption. Therefore:

- Silently ignoring a trailing **valid** TOML unknown key is **application policy, not a conformance violation**.
- Ignoring a trailing **invalid** byte sequence **IS a conformance violation**, because that invalidity is defined by the spec (§1.2), independently of any application schema.

These two statements must be kept strictly separate (see §5).

---

## 2. Inputs under test (byte-exact, LF newlines, final newline present)

`oracle/inputs/dup.toml` (DUP — byte-identical duplicate bare key, last-wins candidate):

```toml
a = "first"
a = "second"
b = "third"
c = "fourth"
```

`oracle/inputs/trail.toml` (TRAIL — trailing bytes `!!!` that cannot start any TOML expression):

```toml
a = "first"
b = "second"
c = "third"
!!!
```

---

## 3. Live reference-parser results (recorded verbatim; cross-checks only)

### 3.1 Python stdlib `tomllib` — Python 3.12.3 (`/usr/lib/python3.12/tomllib`)

Version claim, quoted from https://docs.python.org/3.12/library/tomllib.html:
> This module provides an interface for parsing TOML 1.0.0 (Tom's Obvious Minimal Language, https://toml.io). This module does not support writing TOML.

and:
> A TOMLDecodeError will be raised on an invalid TOML document.

| Input | Result (verbatim) |
|---|---|
| DUP | `tomllib.TOMLDecodeError` — `Cannot overwrite a value (at line 2, column 13)` |
| TRAIL | `tomllib.TOMLDecodeError` — `Invalid statement (at line 4, column 1)` |

Prior-check expectations **verified**: `Cannot overwrite a value` ✓ and `Invalid statement` ✓, with line/col as recorded above.

### 3.2 `tomlkit` 0.15.1 (Python; installed into throwaway venv `/tmp/tomlkit_venv` for this run — not a project dependency)

| Input | Result (verbatim) |
|---|---|
| DUP | `tomlkit.exceptions.ParseError` — `Key "a" already exists. at line 3 col 0` |
| TRAIL | `tomlkit.exceptions.EmptyKeyError` — `Empty key at line 4 col 0` |

**Note**: the prior check expected `KeyAlreadyPresent` / `UnexpectedCharError`. Those exception classes exist in `tomlkit.exceptions`, but the `loads()` parse path actually raises `ParseError` / `EmptyKeyError` (both subclass `ParseError`-family parse failures). Actual live behavior is recorded above and supersedes the prior expectation.

### 3.3 Rust `toml` / `toml_edit` (toolchain already present; crates fetched, no toolchain installed)

**Run 1 — latest, TOML-1.1.0-draft-targeted**: `toml 1.1.8+spec-1.1.0`, `toml_edit 0.25.17+spec-1.1.0`

| Input | API | Result (verbatim) |
|---|---|---|
| DUP | `toml::from_str::<toml::Value>` | `TOML parse error at line 2, column 1` / `2 \| a = "second"` / `^` / `duplicate key` |
| DUP | `toml::from_str::<Cfg>` (typed) | identical parse error: `duplicate key` |
| DUP | `str::parse::<toml_edit::DocumentMut>` | identical parse error: `duplicate key` |
| TRAIL | all three APIs | `TOML parse error at line 4, column 4` / `4 \| !!!` / `^` / `key with no value, expected '='` |

**Run 2 — pinned TOML-1.0.0-era**: `toml 0.8.23`, `toml_edit 0.22.27`

| Input | API | Result (verbatim) |
|---|---|---|
| DUP | `toml::from_str::<toml::Value>` | `TOML parse error at line 2, column 1` / `duplicate key \`a\` in document root` |
| DUP | `toml::from_str::<Cfg>` (typed) | identical parse error: `duplicate key \`a\` in document root` |
| DUP | `str::parse::<toml_edit::DocumentMut>` | identical parse error |
| TRAIL | all three APIs | `TOML parse error at line 4, column 1` / `4 \| !!!` / `^` / `invalid key` |

**Key observation**: the *typed* entry point `toml::from_str::<Cfg>` fails with the **parse-level** error in both generations — the Rust `toml` crate parses the whole document before typed deserialization; typed decoding cannot succeed on an invalid document. This **confirms live** the prior static finding ("rust toml reports `duplicate key`; `toml::from_str` parses the whole document before typed deserialization").

### 3.4 Go `BurntSushi/toml` — **not available in this environment**

No `go` toolchain present (`which go` → not found). Per task instruction no toolchain was installed. No live result; the prior static finding stands unverified in this environment.

---

## 4. Summary table — observation under test → oracle

| Observation under test | Governing spec clause (verbatim + URL) | Expected conforming behavior | Auxiliary reference-parser behavior (exact errors) |
|---|---|---|---|
| **DUP**: document with byte-identical duplicate key (`a` twice), library applies last-wins and reports success | § Keys: "Defining a key multiple times is invalid." (https://toml.io/en/v1.0.0); ABNF header: "certain invalid documents would need to be rejected as per the semantics described in the supporting text description." (`…/toml/1.0.0/toml.abnf` lines 4–6) | **Reject the document** (parse-time error). Last-wins acceptance is non-conforming regardless of whether values differ. | tomllib: `Cannot overwrite a value (at line 2, column 13)` · tomlkit 0.15.1: `Key "a" already exists. at line 3 col 0` (ParseError) · Rust toml 0.8.23 & 1.1.8: `duplicate key` / `duplicate key \`a\` in document root` (also from typed `from_str`) · Go BurntSushi: not available in this environment |
| **TRAIL**: valid prefix `a/b/c`, then trailing `!!!` that cannot start any expression; library stops consuming after last needed field and reports success | § Key/Value Pair: "There must be a newline (or EOF) after a key/value pair."; ABNF overall structure: `toml = expression *( newline expression )` + header note "invalid documents would need to be rejected…" (`…/toml/1.0.0/toml.abnf` line 18, lines 4–6); Preliminaries: "A TOML file must be a valid UTF-8 encoded Unicode document." (whole-document validity) | **Reject the document**: a conforming parser validates the entire input against the `toml` start rule; a non-derivable trailing sequence makes the whole document invalid. | tomllib: `Invalid statement (at line 4, column 1)` · tomlkit 0.15.1: `Empty key at line 4 col 0` (EmptyKeyError) · Rust toml 0.8.23: `invalid key` at line 4 col 1; toml 1.1.8: `key with no value, expected '='` at line 4 col 4 (also from typed `from_str`) · Go BurntSushi: not available in this environment |
| *(related, NOT under test as spec violation)* trailing **valid** TOML unknown key silently ignored by typed decoding | **No clause exists.** Spec contains zero unknown-key / typed-decoding / partial-consumption vocabulary (§1.3); scope statement: "TOML is designed to map unambiguously to a hash table…" | No spec-mandated behavior. Rejecting, erroring, or ignoring are all conforming; the choice is application policy. | Not applicable (no parser behavior is probative for an application-policy question) |

---

## 5. Verdict criteria — two strictly separated categories

### (A) SPEC VIOLATION (conformance)

- **A1 — duplicate key**: the library accepts a TOML 1.0.0 document containing a byte-identical duplicate key and applies last-wins. This violates the governing clause "Defining a key multiple times is invalid." (§1.1) together with the ABNF header's rejection rule for semantically invalid documents (§1.2). Cross-checks: every available parser rejects (§3).
- **A2 — trailing invalid content**: the library accepts a document whose trailing bytes (`!!!`) are not derivable from the overall structure `toml = expression *( newline expression )`, i.e. it stops consuming input once all target fields are populated and never validates the remainder. Document validity is whole-document (§1.2); acceptance is non-conforming. Cross-checks: every available parser rejects (§3).

### (B) APPLICATION-POLICY DEFECT (NOT a spec violation)

- **B1 — silent unknown-key ignore**: silently ignoring a trailing **valid** TOML key that the application's target structure does not declare. The TOML 1.0.0 spec is silent on unknown keys, typed decoding, intermediate/final representations, and partial consumption (§1.3); therefore no conformance claim attaches. This is a library API/robustness concern of the *application contract*, not of TOML conformance.

**B1 must never be merged into (A) in the judgment record.** Citing a spec clause for B1 would be a false conformance claim; conversely, downgrading A1/A2 to "policy" would understate a documented spec violation. The discriminating question is: *is the trailing content valid TOML?* Valid → B1 territory. Invalid → A2 territory.

---

## 6. Reproduction

- Inputs: `oracle/inputs/dup.toml`, `oracle/inputs/trail.toml` (byte-exact above).
- tomllib: `python3 -c "import tomllib; tomllib.loads(open('inputs/dup.toml').read())"` (same for `trail.toml`); Python 3.12.3.
- tomlkit 0.15.1: venv at `/tmp/tomlkit_venv` (ephemeral) — `pip install tomlkit` then `tomlkit.loads(...)`.
- Rust: harnesses kept in `oracle/harness/rust-spec-1.1.0/` (toml 1.1.8+spec-1.1.0, toml_edit 0.25.17+spec-1.1.0) and `oracle/harness/rust-spec-1.0.0/` (toml 0.8.23, toml_edit 0.22.27); `cargo run` in either directory executes all three API forms (`toml::from_str::<Value>`, typed `toml::from_str::<Cfg>`, `str::parse::<DocumentMut>`) against `../../inputs/`.
- Spec sources fetched 2026-10-11: `https://toml.io/en/v1.0.0`, `https://raw.githubusercontent.com/toml-lang/toml/1.0.0/toml.md`, `https://raw.githubusercontent.com/toml-lang/toml/1.0.0/toml.abnf`, draft `…/main/toml.md` + `…/main/toml.abnf`, `https://docs.python.org/3.12/library/tomllib.html`.
