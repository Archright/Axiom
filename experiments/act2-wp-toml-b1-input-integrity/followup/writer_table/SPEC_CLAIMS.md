# SPEC_CLAIMS — pinned spec clause implicated by each violating emission

Authority: `followup/SPEC_BASELINE.md` (pinned: `toml-lang/toml` tag `1.0.0`
+ `main` = 1.1.0 draft). Fact-finding only — no severity, no CVSS, no issue
filed. Version scope is attached to every claim. Verdicts below are the
spec-text verdicts; tomllib (v1.0.0-only) cross-checked with ZERO
mismatches on all 527 v1.0.0-flavor documents (roundtrip.tsv).

## C1 — `\e` emitted for byte 0x1B (writer.nim:148; both flavors)

- **TOML v1.0.0: INVALID.** Clause: SPEC_BASELINE §1 — v1.0.0 escape list
  (tag `1.0.0`, `toml.md:272-291`) contains exactly 9 escapes; `\e` is
  absent → "All other escape sequences not listed above are reserved; if
  they are used, TOML should produce an error."
- **TOML v1.1.0: valid.** Clause: SPEC_BASELINE §1 — v1.1.0 list
  (`main`, `toml.md:285-302`) explicitly includes `\e` (U+001B); ABNF
  `escape-seq-char =/ %x65`.
- Affected emissions: `escapes.tsv` rows (1B, v100) and (1B, v110);
  `esc_v100/b1B.toml`, `esc_v110/b1B.toml`.

## C2 — `\'` emitted for byte 0x27 (writer.nim:153; both flavors)

- **TOML v1.0.0: INVALID.** Clause: SPEC_BASELINE §1 reserved-escape rule
  (`\'` not in the 9-escape list).
- **TOML v1.1.0: INVALID.** Same clause — the v1.1.0 list
  (`\b \t \n \f \r \e \" \\ \xHH \uHHHH \UHHHHHHHH`) does not contain `\'`.
- Affected emissions: byte 0x27 rows in `escapes.tsv` (both flavors — the
  only two string emissions invalid under BOTH versions); quoted-key
  emissions containing `\'`: `keys.tsv` rows (27, v100), (27, v110),
  (mc:squote, v100), (mc:squote, v110); `roundtrip.tsv` cases b27/27/
  mc:squote.

## C3 — `\xHH` emitted for lowEscape/highEscape bytes (v110 flavor only; writer.nim:141-143)

- **TOML v1.0.0: INVALID.** Clause: SPEC_BASELINE §1 — `\xHH` absent from
  the v1.0.0 list → reserved escape.
- **TOML v1.1.0: valid.** Clause: SPEC_BASELINE §1 — `\xHH` listed;
  ABNF `escape-seq-char =/ %x78 2HEXDIG`.
- Affected emissions: 95 `escapes.tsv` rows with flavor=v110 whose token
  contains `\x` (26 lowEscape bytes 00-07/0B/0E-1F, DEL 7F, 80-BF, FE-FF);
  93 `keys.tsv` rows (quoted keys follow basic-string rules, SPEC_BASELINE
  §2). Note the emitted bytes are always valid `\u`-expressible scalars, so
  only the escape FORM is version-divisive.

## C4 — bare keys outside `A-Za-z0-9_-` (writer.nim:166-181 `shouldEscape`)

- **TOML v1.0.0: INVALID.** Clause: SPEC_BASELINE §2 —
  `unquoted-key = 1*( ALPHA / DIGIT / %x2D / %x5F )` (tag `1.0.0`,
  `toml.abnf:50`); §Keys text: "Bare keys may only contain ASCII letters,
  ASCII digits, underscores, and dashes."
- **TOML v1.1.0: INVALID.** Same rule (§Keys text word-for-word identical
  in `main`).
- Affected emissions (both flavors each — 68 `keys.tsv` rows):
  - 26 single-char bare keys: `! $ % & ( ) * + / : ; < = > ? @ [ \ ] ^ { | } ~` —
    `shouldEscape` (writer.nim:168) omits them all; `[ ] = { } ,` are the
    established subset.
  - 6 multi-char bare keys: `a[b`, `a]b`, `a=b`, `a{b`, `a}b`, `a,b`
    (lbrack/rbrack/eq/lbrace/rbrace/comma).
  - Also implicated for these 64 documents: the library's own reader
    REJECTS every one (roundtrip.tsv `lib_read` FAIL, 64 rows) — the
    writer emits documents its own reader cannot parse.

## Explicit non-violations (recorded to keep (A) vs (B) separated)

- **Invalid-UTF-8 input bytes (0x80-0xBF, 0xC0-0xFD, 0xFE-0xFF) re-emitted
  as `\u00XX`/`\xHH`/`\uFFFD`:** every emitted document is valid UTF-8
  encoding valid scalars → no clause of SPEC_BASELINE §4 (UTF-8
  requirement) is violated by the OUTPUT. The byte/value loss is a
  library-vs-Nim-bytes semantic (category (B) in SPEC_BASELINE §7), not a
  spec violation. Recorded in `preservation.tsv`.
- **Two-space indent and unspaced `key=`:** `ws = *(%x20 / %x09)` — legal
  (SPEC_BASELINE §3).
- **`\uXXXX` for C0 bytes (incl. `\u0000`):** valid in both versions
  (SPEC_BASELINE §1); tomllib accepts (roundtrip.tsv).
- **NaN == NaN / 0.0 == -0.0 / 1E-7 float tolerance in `TomlValueRef.==`:**
  in-library comparison semantics; TOML does not discipline host `==` —
  no clause implicated (report.md Task 5 for the record).
