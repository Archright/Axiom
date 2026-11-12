# SPEC_CLAIMS.md — pinned spec clauses implicated by the valuemodel findings

Discipline: followup/SPEC_BASELINE.md §7 — (A) 명세 위반 and (B) 앱 정책 결함 are
never merged; the oracle is the pinned TOML spec, not a reference parser.
Oracle pinned at tag `1.0.0` (+ `main` = 1.1.0-draft where noted):
https://raw.githubusercontent.com/toml-lang/toml/1.0.0/toml.md
No severity, no CVSS, no issue — clause mapping only.

## Verdict per finding

### 1. accessor/type boundary (accessors.tsv) and innerValue coverage (innervalue.tsv)
**(B) 앱 정책 결함 — the pinned spec does not reach here.** TOML v1.0.0 governs
document syntax and value domain, not a host library's accessor API, its
exception contract, or its nil handling. No (A) clause applies. The
`raises: [KeyError]` declaration on `value_ops.nim:86` is a LIBRARY contract
(further contradicted by the compiler's own XCannotRaiseY hint), not a spec one.

### 2. `Table == InlineTable` → true; float 1E-7 tolerance; order-dependence; NaN/±0/subnormal class equality; `Table == nil` crash
**(B) 앱 정책 결함 — no (A) clause violated.** TOML v1.0.0 defines distinct value
TYPES but prescribes no equality relation between parsed values. The implicated
pinned clauses are recorded for the record:

- **TOML 1.0.0, Float section**: "A float consists of an integer part... may
  also be in exponential form" and, pinned verbatim: "Floats should be
  implemented as IEEE 754 binary64 values."
  Under IEEE 754 binary64 semantics, `x == x` for every non-NaN x, NaN != NaN,
  and +0.0 == -0.0. The library's value-model `==` (types.nim:193-198) instead
  yields `NaN == NaN = true`, `+0.0 == -0.0 = false`, non-transitive and
  order-dependent results near the band — i.e. the value model does not behave
  like the binary64 equality the spec's "should" clause describes for the
  values it represents. This is a "should" (advisory) clause touching the
  FORMAT's value domain; the deviation is observed on the LIBRARY's comparison
  operator, so the observation remains classified (B) with the clause recorded
  as implicated, not violated.
- **TOML 1.0.0, Integer section**: "Integers are 64 bits and may be negative"
  (range -2^63..2^63-1) — context for `uint64(-1)` wrapping in innerValue
  (innervalue.tsv): the library can hand out 18446744073709551615 for a
  spec-legal `-1`. Recorded under (B); the spec governs the document value,
  not the accessor's conversion.

### 3. `dateDimte` blast radius (dateDimte.md)
**(B) 앱 정책 결함 — no (A) clause applies.** Implicated context clauses only:

- **TOML 1.0.0, Offset Date-Time / Local Date-Time / Local Date / Local Time
  sections**: TOML defines FOUR distinct date-time value types. The library's
  value model collapses them into one `TomlKind.DateTime` with
  `Option[TomlDate]`/`Option[TomlTime]`/`Option[TomlTimeZone]` (types.nim:98-101,
  115-116) — a legitimate host-side representation choice; the typo then
  breaks extraction of the date-only/time-only projections. The spec neither
  requires nor forbids such accessors.

### 4. Explicitly NOT implicated
The SPEC_BASELINE clauses on escapes (§1), bare keys (§2), newline after `=`
(§3), UTF-8 (§4), duplicate keys (§5), and document validity (§6) are all
lexer/parser-surface rules; none of them is touched by the value-model or
accessor findings in this directory. The defects3 report (sibling directory)
covers the parser-surface (A) findings.

## Version scope
All observations above are runtime/compile-time behavior of the library at the
pinned commit and hold regardless of spec version; clause references are to
tag 1.0.0. No 1.1.0-draft clause changes any statement here (1.1.0's `cmd`
datetime draft is irrelevant to the value model as pinned).
