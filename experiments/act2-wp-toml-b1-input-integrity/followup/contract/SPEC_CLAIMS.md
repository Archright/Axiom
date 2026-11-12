# SPEC_CLAIMS — pinned-clause implication per observed behavior

**Scope rule (from followup/SPEC_BASELINE.md §7):** this file states ONLY which pinned spec clause is or is not implicated by each observed behavior in `contract.md`. No severity. No policy recommendation. No "should". The (A)/(B) discipline of SPEC_BASELINE §7 is applied: clause cited or explicitly none — nothing else.

Oracle clauses (pinned in `followup/SPEC_BASELINE.md`):
- **C1** — Escape sequences (v1.0.0: 9 escapes; `\e`/`\xHH` reserved → error) — *not touched by any observation in this record*
- **C2** — Bare key alphabet (`A-Za-z0-9_-` only)
- **C3** — No newline inside key-val: `keyval-sep = ws %x3D ws`, `ws = SP/HTAB` only → `key =\n5` is invalid TOML; *"수용되면 명세 위반"*
- **C4** — UTF-8 requirement
- **C5** — "Defining a key multiple times is invalid." (§ Keys, tag 1.0.0 line 178)
- **C6** — Whole-document validity: `toml = expression *( newline expression )`; trailing content matching no production makes the document invalid and it "거부해야 한다"

Each behavior below cites: observation (contract.md §) → clause implicated (yes/no, which). Where a behavior involves *valid* TOML being accepted or rejected, no pinned clause governs the acceptance direction (the pinned clauses regulate validity of documents, not decoder acceptance of unknown keys or typed coverage); those are marked **(B) — no clause implicated** per SPEC_BASELINE §7. Observations are grouped so that clause-implicating cells are not diluted by (B) cells.

---

## 1. Byte-identical duplicate key applied (last-wins, no error)

- Observed: `foo = 1` / `foo = 2` accepted, `foo=2` (contract.md §5b; JUDGMENT T2 Obs-1; C5 case).
- **C5 implicated.** The clause states defining a key multiple times is invalid; the typed decoder applies both and returns success.
- Also observed for the byte-identical trailing duplicate `a = "dup"` after completeness (contract.md §3, T3g) — the trailing copy is additionally never examined; C5 implicated for the acceptance, C6 not implicated (the trailing line is valid TOML).

## 2. Trailing content that matches no TOML production, accepted

- Observed: `!!!` after completeness accepted (contract.md §3, T3b); unterminated string `d = "unterminated` after completeness accepted (T3f); `!!!` on the same line as the last value on a later-than-start line accepted via the once-per-record `line` capture (§3a, SL1).
- **C6 implicated** for each: the resulting document matches no `expression` production; the decoder returns success. (T3b and SL1 are the mechanisms named in §3a: early break + start-line-only `checkEol`.)
- Converse observations (rejections, §3 controls): `!!!` / unterminated string while the record is incomplete ARE rejected (K1, K2on). Rejection is the conforming outcome on the C6 axis; no additional clause implicated. K2off rejects with `Unexpected field` before the value is parsed — the document would also be C6-invalid, but the rejection reason is the unknown-field policy, which is (B) (see §5).

## 3. Newline between `=` and the value, accepted

- Observed accepted (contract.md §4c/§4d): typed fields int, float, bool, date, time, datetime, string-enum, seq[int]; public helpers parseInt, parseFloat, parseNumber, parseBool, parseString, parseDate, parseTime, parseDateTime.
- **C3 implicated** for each accepting type/helper: `key =\n<value>` corresponds to no `keyval-sep` production (`ws` is SP/HTAB only), yet the decode succeeds.
- Observed rejected (same sections): typed string field, nested object field, parseAsString. These are consistent with C3 (no implication — the behavior does not violate the clause). Same-line controls (nlc_s, nlc_o) accepted are also consistent with C3.
- Note per SPEC_BASELINE §7 version discipline: C3 text is identical in scope for tag `1.0.0`; the ABNF cited is the `1.0.0` tag. The observations were recorded under the flavor `Toml_v100` and map to the `1.0.0` clause.

## 4. Case-variant duplicate keys applied under non-default case modes

- Observed: `foo = 1` / `FOO = 2` accepted under `TomlCaseInsensitive` → `foo=2` (contract.md §5b); mis-target/split behaviors §5d.
- **C5 not implicated** on its own terms: the clause speaks of defining *a key* multiple times; whether `FOO` and `foo` are "the same key" is not defined by any pinned clause (the pinned key clauses define the allowed alphabet, not case-folding for duplicate detection).
- **(B) — no clause implicated** for the mis-target and split observations themselves (typed-decode key→field mapping is not regulated by the pinned clauses). Mis-targets involve distinct TOML keys, each individually valid; the documents are valid (C6 not implicated).

## 5. Unknown-key policy dichotomy (raise vs skip vs never-examined)

- Observed: flag OFF → `Unexpected field 'd'` raised for a valid TOML key (contract.md §1a); flag ON → skipped; both flags → silently ignored after completeness (§1b); inline-table unknown keys §1c.
- **(B) — no clause implicated.** The pinned clauses do not regulate unknown keys, typed decode, or partial consumption (SPEC_BASELINE §4.2 of JUDGMENT agrees). Valid documents both accepted (flag ON / post-break) and rejected (flag OFF) — no pinned clause requires either outcome.

## 6. Missing-field completeness and never-reached fields

- Observed: 0–2 of 3 fields supplied → accepted, defaults (contract.md §2); field present in input but never examined due to the early break (C5 case; breaksteal case) (§2).
- **(B) — no clause implicated.** Typed coverage is not regulated by the pinned clauses; the documents involved are valid TOML (C6 not implicated). The C5-case document additionally contains a byte-identical duplicate — C5 implicated for that input independently (see §1); the *never-reached* aspect of the observation adds no clause implication.

## 7. Table-header handling while incomplete

- Observed: `[x]` mid-record treated as a candidate field name → rejected flag-OFF, rejected (different message) flag-ON (contract.md §1d, K3/K3on); `[[x]]` on array-less type → rejected both flags (K4/U12); `[x]`/`[[x]]` after completeness → ignored (T3c/T3c2).
- **(B) — no clause implicated.** The documents are valid TOML; no pinned clause requires their acceptance. The ignore-after-completeness cells additionally never examine the header bytes; C6 not implicated (headers are valid productions).

## 8. Bare-key alphabet

- Observed: `!!!` reaching the key path raises `illegal character "!"` (contract.md §3 control K1; §1a U9 skip-path value parse).
- **C2 consistent** (no implication of violation): `!` is outside the bare-key alphabet, and the decoder rejects it wherever it reaches key position. C6 consistent (rejection of invalid content).

## 9. Clauses not touched by this record

- **C1 (escape sequences)**: no observation involves string escape parsing.
- **C4 (UTF-8)**: no observation involves non-UTF-8 or non-ASCII bytes.

---

## Summary counts

| observed behavior group | clause implicated |
|---|---|
| Byte-identical duplicate key applied (typed path) | **C5** |
| Trailing no-production content accepted (T3b, T3f, SL1) | **C6** |
| `key =\n<value>` accepted (9 typed types + 8 helpers) | **C3** |
| Case-variant duplicate application / mis-target / split | none (B) |
| Unknown-key raise/skip/ignore dichotomy | none (B) |
| Missing fields defaulted; present-but-unreached field ignored | none (B) |
| Header-as-field-name while incomplete; `[[x]]` rejection; post-break header ignore | none (B) |
| `!!!` at key position rejected (K1, U9) | C2/C6 consistent (no violation) |
| String-field / object-field newline rejection; same-line controls | C3 consistent (no violation) |
