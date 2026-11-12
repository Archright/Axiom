# Differential verification: `toml_serialization/private/utf8_validate.nim` DFA table

- **Subject** (READ-ONLY): `nim-toml-serialization` @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9`
- **Date**: 2026-10-11 · **Toolchain**: Nim 2.2.10 (pinned), Python 3.12.3, 16 cores, Linux amd64
- **Headline**: **ZERO disagreements.** The compiled DFA agrees with CPython's UTF-8 decoder
  on **every one of 100,923,864 byte sequences** differentially compared, the table is a
  cell-for-cell match of Höhrmann's canonical DFA (0/400 differences), and the incremental
  `push`/`valid`/`clear` API is verdict-identical to the batch entry point across
  386,786,400 split-point checks and 739,887,040 full chunk-composition executions.
- The escape interaction (`\xHH`) is a **real, reproduced divergence** — but it is in the
  lexer's escape decoding, **not** in the DFA table. Details in §5.

---

## 1. Table transcription (Task 1)

Source: `toml_serialization/private/utf8_validate.nim` (53 lines). Parsed programmatically
from the source text (`probes/parse_table.py`) — no hand retyping. Machine-readable form:
`table.json` (this directory).

| Property | Value |
|---|---|
| Table length | **400** entries (not ~416) |
| Layout | 256 byte-class entries + 144 transition entries |
| DFA states | **9** (values 0..8), transition rows of 16 classes |
| Index formula | `class = table[byte]`; `state' = table[256 + state*16 + class]` |
| Accept / reject encoding | `UTF8_ACCEPT = 0`, `UTF8_REJECT = 1` |
| Max class produced | 11 (0xb) |
| Dead transition cells | 36 (classes 12..15 are never produced by the class table) |
| Entry points | `validateUTF8` (batch), `UTF8Validator` object with `push`/`valid`/`clear` |

**Fidelity vs the reference DFA** (`raw/canonical_table_diff.txt`): the canonical Höhrmann
table was fetched from the author's page
([bjoern.hoehrmann.de/utf-8/decoder/dfa](http://bjoern.hoehrmann.de/utf-8/decoder/dfa/)).
The class table was rebuilt from that page's prose byte→class mapping and the transition
rows transcribed from its primary table, then **independently cross-checked** against the
page's pre-multiplied variation (`UTF8_REJECT=12`, states ×12), reduced to 16-class form:
cross-form mismatches over all live cells (s0..s8 × classes 0..11): **0**.
Subject-vs-canonical: **0 / 400 cell differences**.

## 2. Differential coverage (Task 2) — exactly what was enumerated

Verdict sources per sequence: **V1** = subject `validateUTF8` (compiled, bitmap), **V2** =
subject `UTF8Validator` `clear/push`/`valid` (compiled, bitmap), **V3** = Python mirror of
the parsed table (exact statement-level mirror of `validateUTF8`), **V4** =
CPython `bytes.decode('utf-8')` strict (the oracle). Compared four-way per sequence.

| Range | Contents | Sequences | Accepted (all sources agree) |
|---|---|---|---|
| R1-R3 | **exhaustive** all byte strings of length 1, 2, 3 (256 + 256² + 256³ = 16,843,008) | 16,843,008 | 2,668,544 |
| R4 | **complete** all 4-byte sequences with lead F0..F4 × all b2,b3,b4 ∈ 0..255² | 83,886,080 | 1,048,576 |
| R5 | all 251 non-F0-F4 leads × [full b2 sweep + full b3 sweep + full b4 sweep + 8 corners] | 194,776 | 4,740 |
| R6 | full legal codepoint space U+0000..U+10FFFF minus surrogates (canonical encodings) | 1,112,064 | all (confirmatory) |
| R7 | explicit invalid boundary sets (see below) | 267,072 | 0 (confirmatory) |

Accepted-count cross-checks against closed-form models:
- R1-R3: 2,668,544 = 128 + (128² + 1,920) + (128³ + 2·128·1,920 + 61,440) — i.e. every
  valid UTF-8 string of length ≤ 3 including multi-character ASCII/mixed strings.
- R4: 1,048,576 = |U+10000..U+10FFFF| exactly.
- R5: 4,740 = 1,920 (ASCII byte + one 3-byte char: 128 × 15) + 1,920 (one 3-byte char
  E0-EF\{ED} + BF + 80, then ASCII byte: 15 × 128) + 900 (two 2-byte chars C2-DF+80,
  C2-DF+BF: 30 × 30) — each verified valid by CPython.
- R7 counts: surrogate forms (ED A0-BF × 80-BF: 2,048), 2-byte overlongs (C0/C1: 128),
  3-byte overlongs (E0 80-9F: 2,048), 4-byte overlongs (F0 80-8F: 65,536), >U+10FFFF
  (F4 90-BF: 196,608), impossible leads (F5-FF: 704).

**Total: 100,923,864 sequences compared four-way (V1=V2=V3=V4), plus 1,112,064 + 267,072
confirmatory.** Nim ran both entry points over all of R1-R5; Python ran V3/V4 over all of
R1-R7.

Coverage-completeness argument (why this is decisive for the table):
- Exhaustive R1-R3 exercises every (state, class) cell reachable within 3 bytes, with
  end-of-input verdicts.
- The only cells whose full semantic effect requires a 4th byte are the "expect-2-more-
  continuations" cells of rows s6/s7/s8 (entered only after F0/F1-F3/F4 + 1 byte). R4 is
  **complete over exactly those leads**, so every one of those cells is witnessed by all
  4-byte continuations.
- For non-F0-F4 leads in R5: the table-level property "state 1 (REJECT) is absorbing"
  (`s1` row is all 1s — verified directly from the parsed table) means any continuation
  after a rejected lead is verdict-equivalent; the per-lead sweeps verify this empirically
  against CPython for every lead.

## 3. Disagreements (Task 2, the key answer)

**None.** All pairwise comparisons are 0 for every sequence in every range:
`nim_batch vs py_mirror`, `nim_obj vs py_mirror`, `py_mirror vs codecs`,
`nim_batch vs codecs`, `nim_obj vs codecs`.
The per-range disagreement CSVs in `raw/disagreements_*.csv` contain headers only.
Summary: `raw/differential_summary.json`; known-vector results: `raw/known_vector_results.txt`;
compressed Nim verdict bitmaps: `raw/r*_batch.bin.gz`, `raw/r*_obj.bin.gz`.

This is a clean result, and given the coverage above it is a strong one: any single wrong
live cell in the 400-entry table would necessarily have produced visible verdict
differences in R1-R3 + R4.

## 4. Incremental / streaming property (Task 2b)

`dfa_probe.nim` (compiled against the pinned clone, run in /tmp) over all 100,923,864
sequences of R1-R5:

- 386,786,400 **prefix split-point checks**: after every `push`, `valid()` must equal the
  standalone `validateUTF8` verdict of the prefix consumed so far — 0 mismatches.
- 739,887,040 **chunk-composition executions**: every way to split each sequence into
  consecutive chunks (all 2^(n-1) compositions) run through one validator — 0 mismatches.
  (Note honestly: `push` is per-byte, so compositions are mechanically identical push
  streams by construction; the test verifies that empirically, and the split-point checks
  above are the informative boundary tests.)
- Object-API final verdicts are also emitted as bitmaps (V2) and match the batch bitmaps
  bit-for-bit on all 100,923,864 sequences.
- Sanity semantics: fresh validator `valid()` = true; partial sequence `valid()` = false;
  `clear()` restores ACCEPT.

A table transposition would break R1-R3/R4 verdicts long before chunking; chunking is
nonetheless clean.

## 5. Escape interaction (Task 3)

### Source facts (quoted)

State is cleared before every escape; escape-produced bytes are never pushed through the
validator — `toml_serialization/lexer.nim:592-598` (single-line strings):

```nim
    when kind == StringType.Basic:
      if next == '\\':
        next = lex.next
        if not utf8.valid():
          raiseTomlErr(lex, errInvalidUTF8)
        utf8.clear()
        lex.scanEscapeChar(next, res)
        continue
```

Same pattern in multi-line strings — `lexer.nim:543-549`:

```nim
        else:
          if not utf8.valid():
            raiseTomlErr(lex, errInvalidUTF8)
          utf8.clear()
          # This is just an escape sequence (like "\t")
          lex.scanEscapeChar(lex.next, res)
          continue
```

`\xHH` inserts the raw byte — `lexer.nim:416-429`:

```nim
proc scanHexEscape[T](lex: var TomlLexer, res: var T) {.raises: [IOError, TomlError].} =
  ...
  if TomlHexEscape notin lex.flags:
    raiseInvalidHex(lex, "not supported by standard, please use `TomlHexEscape`")

  var code: int
  let col = scanDigits(lex, code, base16)
  if col != 2:
    raiseInvalidHex(lex, "'\\x' must have 2 character value")

  when T is string:
    res.add char(code)
```

By contrast `\uXXXX` re-encodes properly — `lexer.nim:413-414`:

```nim
  when T is string:
    res.add unicode.toUTF8(Rune(code))
```

Flag plumbing: the reader always merges the flavor's runtime flags —
`reader.nim:62-64`: `T(lex: TomlLexer.init(..., flags + flavorRuntimeFlags(Flavor)))`,
and the default `Toml` flavor is v1.1.0 with `TomlHexEscape` in
`Toml_v110_Flags` (`format.nim:28-36`). So `\xHH` is **enabled by default**; passing empty
user flags does not disable it (probe case `x45_default_emptyflags`).

### Probe results (`probes/escape_probe.nim`, output `raw/escape_probe_stdout.txt`, codecs check `raw/escape_bins_codecs_check.csv`)

| TOML document (bytes) | Flavor / flags | Decoded string (hex) | Subject `validateUTF8` | CPython codecs |
|---|---|---|---|---|
| `val = "\x80"` | default `Toml` (v1.1.0 flags) | `80` | invalid | **invalid** |
| `val = "\x80"` | `{TomlHexEscape}` | `80` | invalid | **invalid** |
| `val = "\xFF"` | `{TomlHexEscape}` | `ff` | invalid | **invalid** |
| `val = "Jos\xE9"` (v1.1.0 spec example) | `{TomlHexEscape}` | `4a6f73e9` | invalid | **invalid** |
| `val = "\u0080"` (control) | `{TomlHexEscape}` | `c280` | valid | valid |
| `val = """\x80"""` (multi-line path) | `{TomlHexEscape}` | `80` | invalid | **invalid** |
| `val = "\x80"` + raw `C3 A9` | `{TomlHexEscape}` | `80c3a9` | invalid | **invalid** |
| raw `C3` then `\x80` | `{TomlHexEscape}` | raises `invalid UTF-8 sequence` | — | — |
| `val = "\uD800"` | `{TomlHexEscape}` | raises `must be a unicode scalar value` | — | — |
| `val = "H\x45X"`, v1.0.0 flavor, no flag | `Toml_v100` `{}` | raises `not supported by standard, please use \`TomlHexEscape\`` | — | — |
| `val = "H\x45X"`, v1.0.0 flavor + flag | `Toml_v100` `{TomlHexEscape}` | `484558` (valid) | valid | valid |

What is in the resulting Nim string: **the single raw byte** (e.g. `0x80`) — a lone UTF-8
continuation byte. It is not valid UTF-8 by the subject's own validator, nor by CPython.
The before-escape `utf8.valid()` guard does fire for raw invalid bytes preceding an escape
(case `rawC3_then_x80`), but after each escape the validator is `clear()`ed, so escape-
produced bytes are never checked and cannot poison the check of following raw bytes
(case `x80_then_rawC3A9` is accepted while its decoded value is invalid).

### Version-scoped verdict

- **v1.0.0** (`https://toml.io/en/v1.0.0`): `\xHH` does not exist; "All other escape
  sequences not listed above are reserved; if they are used, TOML should produce an
  error." The subject's v1.0.0 flavor behaves accordingly (raises without the flag) — the
  v1.0.0-scoped behavior is conforming.
- **v1.1.0** (`https://toml.io/en/v1.1.0`, published 2025-12-18): `\xHH` is defined as
  `unicode (U+00HH)`, "The escape codes must be Unicode scalar values", and "all TOML
  strings are sequences of Unicode characters, not byte sequences". Judged against
  v1.1.0, the observed behavior diverges from the spec for HH ≥ 0x80: the decoder inserts
  the raw byte `HH` into the string value instead of the UTF-8 encoding of U+00HH
  (e.g. `Jos\xE9` yields `4A 6F 73 E9` instead of `4A 6F 73 C3 A9`), producing a decoded
  string value that is not well-formed UTF-8. This is enabled by default on the `Toml`
  flavor. (The document bytes themselves remain valid UTF-8; the invalidity is in the
  decoded value.) No severity assessment is made here and no issue is filed.

Adjacent observations recorded by the same probe (not judged further here):
- Greedy hex-digit absorption: `scanHexEscape` calls `scanDigits` with
  `maxDigits = high(int)` (lexer.nim:337-340) and then requires exactly 2, so
  `val = "a\x80b"` raises `'\x' must have 2 character value` — the trailing `b` is
  absorbed into the escape. The v1.1.0 ABNF (`%x78 2HEXDIG`) specifies exactly two hex
  digits, under which `\x80b` would be U+0080 followed by literal `b`.
- `raw/toml.abnf` is archived byte-exact from
  `https://raw.githubusercontent.com/toml-lang/toml/main/toml.abnf`
  (sha256 `2038f64825dd9a2bbb22807bcb46900c6d6c30eb728d577e948db8eda87555c5`).

## 6. Spec basis (Task 4) — the oracle

Full quotes with sources: `raw/spec_quotes.md`. Key lines:

- v1.0.0: "A TOML file must be a valid UTF-8 encoded Unicode document." / "All strings
  must contain only valid UTF-8 characters." / "The escape codes must be valid Unicode
  scalar values."
- v1.1.0: "A TOML file must be a valid UTF-8 encoded Unicode document. Specifically this
  means that a file as a whole must form a well-formed code-unit sequence. Otherwise, it
  must be rejected (preferably) or have ill-formed byte sequences replaced with U+FFFD,
  as per the Unicode specification." / "All strings must contain only Unicode
  characters." / `\xHH - unicode (U+00HH)` / "The escape codes must be Unicode scalar
  values." / "all TOML strings are sequences of Unicode characters, not byte sequences."
- ABNF (main = v1.1.0 edition): "Although a TOML document must be valid UTF-8, this
  grammar refers to the Unicode Code Points you get after you decode the UTF-8 input." /
  `non-ascii = %x80-D7FF / %xE000-10FFFF` (surrogates excluded) /
  `escape-seq-char =/ %x78 2HEXDIG ; xHH  U+00HH`.

CPython's strict `utf-8` codec (rejects surrogates, overlongs, >U+10FFFF, ill-formed
sequences) is the operational oracle and matches the spec requirements above.

## 7. Artifacts & reproduction

```
followup/utf8/
├── report.md            ← this file
├── table.json           ← parsed 400-entry table + metadata (Task 1)
├── raw.tar.gz           ← pinned run bytes (member hashes in root MANIFEST; rerun driver removed 2026-10-11)
├── probes/
│   ├── parse_table.py       (table extraction, structural invariants)
│   ├── dfa_probe.nim        (exhaustive ranges + bitmaps + chunking; uses subject public API)
│   ├── escape_probe.nim     (12 escape-interaction cases through the public decoder)
│   └── diff_harness.py      (4-way differential vs CPython codecs, 16-way parallel)
└── raw/
    ├── differential_summary.json      (per-range counts + 0 diffs)
    ├── disagreements_r*.csv           (headers only — zero disagreements)
    ├── canonical_table_diff.txt       (0/400 vs Höhrmann, cross-form check)
    ├── known_vector_results.txt, boundary_sets_summary.txt
    ├── escape_probe_stdout.txt, escape_bins_codecs_check.csv
    ├── spec_quotes.md, toml.abnf (byte-exact, sha256 2038f648…)
    ├── nim_summary.txt
    └── r*_batch.bin.gz, r*_obj.bin.gz (Nim verdict bitmaps, MSB-first)
```

The `./repro.sh` rerun driver was removed in the 2026-10-11 consolidation — the recorded
bytes live in `raw.tar.gz` (member hashes in the experiment-root `MANIFEST`; check with
`bash bsec/replay.sh verify`), and the pipeline above (`parse_table.py` → `dfa_probe.nim`
→ `escape_probe.nim` → `diff_harness.py`; Nim 2.2.10, Python ≥3.12; nimble deps
`faststreams`, `serialization`, `stew` needed only by the escape probe) re-derives them
out-of-tree. Binaries are produced under `/tmp` only; the subject clone is opened
read-only and remains byte-clean (`git status --porcelain` empty before and after).
