# Writer Validity Tables — nim-toml-serialization (exhaustive, deterministic)

**Subject**: `<workspace>/nim-toml-serialization` @
`4aa8e2223649fc0837c490a4acfca7b8b1e756f9` (READ-ONLY; `git status
--porcelain` empty before and after this task; touched only via `--path`).
**Question**: for EVERY byte 0x00–0xFF, what does the WRITER emit (string
value and key), and is that output valid TOML per version — plus full
round-trip, preservation, and `==` semantics records.
**Method**: Nim 2.2.10 probes (`probes/*.nim`, each headed
`# nim-check: skip` + rationale) compiled from neutral cwd `/tmp`, binaries
in `/tmp/wt_build` only; `--mm:orc --skipUserCfg --skipParentCfg
--skipProjCfg`; `--path` subject + serialization-0.5.4 + faststreams-0.5.2 +
stew-0.5.0. Every emitted document written verbatim under `raw/`
(1054 `.toml` files + probe TSVs + logs). Inputs fully specified in
`inputs/probe_inputs.md`; the run bytes are pinned in `raw.tar.gz` (experiment-root `MANIFEST`; the `bash repro.sh` driver was removed 2026-10-11).

**Oracle discipline**: validity verdicts come from the pinned spec text
(`followup/SPEC_BASELINE.md`), version-scoped. Python 3.12 `tomllib` is
**TOML v1.0.0-only**: its verdict is authoritative ONLY for v1.0.0 columns
(`v100`-flavor emissions and any doc judged against v1.0.0); every RAISE it
produces on v1.1.0-only syntax (`\e`, `\xHH`) is expected and weightless
for v1.1.0. Cross-check result: **zero** spec-vs-tomllib mismatches on all
527 v1.0.0-flavor documents.

**Comparison discipline**: every round-trip / preservation verdict in this
report uses **exact byte comparison** of decoded Nim string bytes vs input
bytes (`string ==`, i.e. byte equality). `TomlValueRef.==` was **not** used
for any verdict — its semantics are recorded separately in Task 5 because
they would mask mismatches.

Flavors: `v100` = `Toml_v100` (`runtimeFlags = {}`, v1.0.0);
`v110` = default `Toml` (`Toml_v110_Flags`, v1.1.0) — `format.nim:26-41`,
`toml_serialization.nim:26-30`.

---

## Task 1 — exhaustive escaping table → `escapes.tsv` (512 rows = 256 bytes × 2 flavors)

**Writer mechanism** (`writer.nim:131-164`, identical logic both flavors
except the hex-escape flag): the string writer iterates `runes(s)`
(writer.nim:137) and, per rune ≤ 255: `lowEscape` = C0 minus
`{ \b \e \f \n \r \t }` and `highEscape` = 0x7F–0xFF → `\u00XX` (`v100`) or
`\xHH` (`v110`); six short escapes; `"` → `\"`, `\` → `\\`, **`'` → `\'`**;
everything else (0x20–0x7E remainder) raw. Runes > 255 → `\uXXXX` (< 0xFFFF)
or `\UXXXXXXXX`. Runes that Nim's `fastRuneAt` decodes from invalid UTF-8
are re-expressed (see Task 4).

**The writer emits only basic strings.** `writer.nim` has no literal-string
emission path, so `emitted_literal` is identical to `emitted_basic` for all
512 rows — recorded as a per-row fact in the table.

Verdict distribution (per row = one emitted document):

| verdict | rows | detail |
|---|---|---|
| valid v1.0.0 + valid v1.1.0 | 415 | short escapes, `\"`, `\\`, `\uXXXX`, `\UXXXXXXXX`, raw 0x20–0x7E |
| **invalid in BOTH versions** | **2** | byte 0x27 → `\'` (reserved escape in both) |
| invalid v1.0.0 only | 95 | 0x1B → `\e` (both flavors) + 93 `\xHH`-emitting bytes under `v110` flavor (00–07, 0B, 0E–1F, 7F–BF, FE, FF) |
| invalid v1.1.0 | — | none besides the two `\'` rows |

Representative rows (full detail in `escapes.tsv`; raw bytes in `raw/`):

| byte | v100 token | v110 token | v1.0.0 | v1.1.0 |
|---|---|---|---|---|
| 00 | `"\u0000"` | `"\x00"` | VALID | INVALID (reserved `\x`) for the v110 token; VALID v1.1.0 |
| 08 | `"\b"` | `"\b"` | VALID | VALID |
| 09 | `"\t"` | `"\t"` | VALID | VALID |
| 1B | `"\e"` | `"\e"` | **INVALID** (reserved) | VALID |
| 22 | `"\""` | `"\""` | VALID | VALID |
| 27 | `"\'"` | `"\'"` | **INVALID** | **INVALID** |
| 5C | `"\\\\"` (`\\`) | `"\\\\"` (`\\`) | VALID | VALID |
| 7F | `"\u007F"` | `"\x7F"` | VALID | VALID (the v110 token is INVALID v1.0.0) |
| C0 | `"\uFFFD"` | `"\uFFFD"` | VALID | VALID (value destroyed — Task 4) |
| E9 | `"\uFFFD"` | `"\uFFFD"` | VALID | VALID (value destroyed — Task 4) |
| FF | `"\u00FF"` | `"\xFF"` | VALID | VALID |

Confirmed and extended from the earlier pass: `\e` (0x1B) and `\'` (0x27)
behave exactly as `followup/writer/report.md` recorded; new here is the
exhaustive per-byte record including the `v110` `\xHH` emissions (95
v1.0.0-invalid rows that the earlier partial sweep did not enumerate).

## Task 2 — key-escaping table → `keys.tsv` (542 rows: 512 = 256 bytes × 2 flavors + 30 multi-char)

**Writer mechanism** (`writer.nim:166-181`): `shouldEscape =
{'\0'..'\32', '.', '\"', '\'', '#', '\127'..'\255'}`; a key containing any
of these (or any rune ≥ 255, or empty) is quoted **via the string writer**
(basic string); otherwise appended **bare**. Bare vs quoted per byte is
byte-for-byte identical under both flavors except the escape spelling
inside quoted keys (`\u` vs `\x`).

- **Bare single-char keys (90 bytes = 0x21–0x7E minus `. " ' #`)**:
  64 are valid bare keys (`A-Za-z0-9_-`) → VALID both versions.
  **26 are INVALID in BOTH versions**: `! $ % & ( ) * + / : ; < = > ? @ [ \ ] ^ { | } ~`
  — the established `[ ] = { } ,` subset plus 20 more (notably backslash
  `\` 0x5C and comma `,` 0x2C, both absent from `shouldEscape`).
- **Quoted single-char keys (34 bytes + all ≥ 0x7F)**: valid per the
  basic-string rules of each version → the only quoted invalids are 0x27
  (`\'`, both versions) and, under `v110`, the `\xHH`-emitting bytes
  (invalid v1.0.0 only, weightless for v1.1.0).
- **Multi-char keys** (both flavors): `a.b` → `"a.b"` (quoted — cannot be
  re-read as dotted) VALID; `a b` → `"a b"` VALID; `a"b` → `"a\"b"` VALID;
  `a#b` → `"a#b"` VALID; `a<LF>b` → `"a\nb"` VALID; `é` → `"\u00E9"`
  (v100) / `"\xE9"` (v110); `ʎǝʞ` → `"\u024E\u029E"` both flavors;
  lone `E9` → `"\uFFFD"` both flavors.
  **INVALID both versions (6)**: `a[b`, `a]b`, `a=b`, `a{b`, `a}b`, `a,b`
  — written bare. **INVALID both versions (1)**: `a'b` → `"a\'b"` (`\'`).

Verdict distribution: 542 rows → **68 invalid-in-both** (34 per flavor =
26 + 7 mc + 1 quoted-apos… precisely: 26 bare single + 7 bare/`\'` multi +
1 quoted-apos single per flavor), invalid-v1.0.0-only 96 (v110 `\x` quoted
keys + v100-flavor `\e` key), none invalid-v1.1.0 beyond the both-set.

## Task 3 — round-trip matrix → `roundtrip.tsv` (1054 rows)

Every emitted document from Tasks 1–2 re-parsed by (a) the library's own
reader, same flavor, and (b) tomllib (v1.0.0-only oracle — its column is
authoritative exclusively for v1.0.0; RAISE on v110-flavor docs is expected
and carries no v1.1.0 weight).

- **Library re-parse FAILS on exactly 64 documents** — all and only the
  bare-key emissions that violate the bare-key charset (26 single-char +
  6 multi-char, × 2 flavors; e.g. `  k[=7` → `(1, 5) expected "="`). The
  writer produces documents its own reader cannot parse.
- **Library accepts, spec+tomllib reject (5 rows)**: `\e` and `\'`
  emissions (`lexer.nim:438,443` accept both unconditionally, even under
  the v1.0.0 flavor). These are the writer-invalid-but-self-consistent
  cases: `b1B` (string), `b27`/`27` (string/key), `mc:squote`.
- **Zero spec-vs-tomllib mismatches** across all 527 v1.0.0-flavor docs;
  the two oracles agree on every v1.0.0 verdict in the table.
- Decoded-key byte preservation column (`key_bytes_preserved`): 193
  OK-read key rows where the decoded key bytes ≠ input key bytes
  (mechanism in Task 4; e.g. `mc:eacute` under v110: `"\xE9"` → decoded
  key = lone `E9`, not `C3 A9`).

## Task 4 — value- vs byte-preservation → `preservation.tsv` (512 rows)

Single-byte inputs, encode→decode same flavor, exact byte comparison:

| flavor | byte_preserving | value_preserving_only | lossy |
|---|---|---|---|
| v100 | 128 (0x00–0x7F) | 66 (0x80–0xBF, 0xFE, 0xFF → `\u00XX` → 2-byte UTF-8) | 62 |
| v110 | 194 (0x00–0xBF, 0xFE, 0xFF — `\xHH` decodes to a RAW byte, `lexer.nim:429`) | 0 | 62 |

- **Lossy set is identical under both flavors: 0xC0–0xFD (62 bytes)** —
  each round-trips to `EF BF BD` (U+FFFD). This **extends** the earlier
  `E9`/`FF` finding: the cause is Nim's `fastRuneAt`
  (toolchain `lib/pure/unicode.nim:84-152`), under which a LONE lead byte
  of any valid UTF-8 sequence length — 2-byte (C0–DF), 3-byte (E0–EF),
  4-byte (F0–F7), **5-byte (F8–FB), 6-byte (FC–FD)** — yields `replRune`
  (U+FFFD), while 0x80–0xBF and 0xFE–0xFF fall through to the final
  `else` and pass through as raw code points. The earlier report's
  asymmetry (`E9` → FFFD vs `FF` → 00FF) is exactly this boundary.
- **Flavor asymmetry (new)**: under `v110`, 0x80–0xBF and 0xFE–0xFF are
  **byte-preserving** (`\xHH` → raw byte on decode), while the same bytes
  under `v100` are only value-preserving (`\u00XX` → UTF-8 re-encoding).
- **Corollary observed directly** (`keys.tsv`/`roundtrip.tsv`,
  `mc:eacute`): multi-byte UTF-8 input under the `v110` flavor loses
  bytes — `é` (`C3 A9`) is emitted as `"\xE9"` and decodes to the single
  byte `E9`. Under `v100` the same input is byte-preserving
  (`"\u00E9"` → `C3 A9`).
- All losses are idempotent (a second encode/decode cycle is stable);
  every emitted document remains valid UTF-8 of valid scalars, so these
  are value-loss facts, not output-validity violations (see
  `SPEC_CLAIMS.md`, non-violations).

## Task 5 — `==` semantics (exact bytes used everywhere else)

`TomlValueRef.==` (`types.nim:190-215`), measured by `probe_eq_semantics`
(full log `raw/probe_eq_semantics.log`):

- **Float tolerance**: `result = abs(a - b) < 1E-7` (types.nim:198) —
  STRICT. Measured: `1.0 == 1.00000001` → true (diff 9.999999939e-09);
  `1.0 == 1.00000005` → true; `1.0 == 1.0000001` → **false** (diff
  1.0000000006e-07, not < 1E-7); `1.0 == 1.000001` → false.
- **Non-transitivity triple** (concrete): `x = 1.0`, `y = 0.99999994`,
  `z = 0.99999988` → `x == y` true (diff 6.0e-08), `y == z` true (diff
  6.0e-08), `x == z` **false** (diff 1.2e-07). Transitivity violated.
- **Non-normal floats compare by `classify()` category only**:
  `NaN == NaN` → **true**; `Inf == Inf` → true; `Inf == -Inf` → false;
  `0.0 == -0.0` → **false** (`fcZero` vs `fcNegZero`); `0.0 == 1e-30` →
  false (`fcZero` vs `fcSubnormal`).
- **Table == InlineTable → true** (both in `tableKind`, types.nim:180-188;
  then compared as tables): `Table{k:1} == InlineTable{k:1}` → true;
  nested `Table{k:{x:1.0}} == InlineTable{k:{x:1.0}}` → true; differing
  content → false. A kind change (Table ↔ InlineTable) is invisible to `==`.
- Kind mismatches elsewhere are false: `Int(1) == Float(1.0)` → false.
- **Round-trip relevance**: decode(encode(`{v: 1.00000001}`)) `==`
  `Float(1.0)` → **true** while the decoded value is bit-exactly
  1.00000001 — `==` cannot certify float round-trips.
- **All other verdicts in this report use exact byte comparison**, never
  `==` (stated per the task; enforced in the probes and assembler).

## Surprising facts (index)

1. The invalid-in-both string set is exactly one byte: 0x27 (`\'`).
2. 26 distinct single-char bare keys are emitted bare and are invalid in
   BOTH versions — the established `[ ] = { } ,` six plus 20 more,
   including `\`, `,`, `~`, `@`, `/`, `:`.
3. `\'` is emitted for `'` inside quoted KEYS too (`"a\'b"`, `"\'"`),
   invalid in both versions, yet the library's own reader accepts it.
4. Lossy bytes are 0xC0–0xFD (62), not 0xC0–0xF7: Nim `fastRuneAt` has
   working 5-byte (F8–FB) and 6-byte (FC–FD) lead branches that map lone
   bytes to U+FFFD, while 0xFE–0xFF pass through as raw code points.
5. Preservation is flavor-asymmetric: `\xHH` decodes to a raw byte
   (`lexer.nim:429`), so v110 preserves 0x80–0xBF/0xFE–0xFF byte-exactly
   while v100 re-encodes them; conversely v110 destroys multi-byte UTF-8
   input (`é` → lone `E9`).
6. The writer has no literal-string emission path at all — `emitted_literal`
   equals `emitted_basic` for all 512 escape rows by construction.
7. `==` equates NaN with itself and distinguishes `0.0` from `-0.0`
   (classify-category comparison), in addition to the known tolerance and
   Table/InlineTable equivalence.

## Files

| file | rows/contents |
|---|---|
| `escapes.tsv` | 512 rows (byte, hex, flavor, emitted_basic, emitted_literal, valid_v100, valid_v110, note) |
| `keys.tsv` | 542 rows (same shape; 256 single-char × 2 flavors + 15 multi-char × 2) |
| `roundtrip.tsv` | 1054 rows (lib_read + tomllib_v100_oracle per emitted document) |
| `preservation.tsv` | 512 rows (category per byte × flavor) |
| `SPEC_CLAIMS.md` | violating emission → pinned clause (C1–C4 + non-violations), no severity |
| `inputs/probe_inputs.md` | deterministic input definitions |
| `probes/` | 3 Nim probes + oracle_tomllib.py + assemble_tables.py, all `# nim-check: skip`-headed |
| `raw/` | 1054 emitted `.toml`, probe TSVs, logs, tomllib oracle TSV |
| `raw.tar.gz` | pinned run bytes (every member hash in the experiment-root `MANIFEST`) |

## Reproduce

2026-10-11 consolidation: the `bash repro.sh` driver was removed — regenerating in place
would overwrite the record. The pinned bytes (`raw.tar.gz`, member hashes in the
experiment-root `MANIFEST`, checked by `bash bsec/replay.sh verify`) plus the method above
(neutral cwd `/tmp`, binaries in `/tmp/wt_build`, sweeps into a scratch dir, tomllib
oracle + assembler) are the reproduction contract; the subject clone stays byte-clean.
