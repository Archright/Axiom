# Conformance claim ceiling — POL-6 decision inputs (recorded, NOT decided)

**What this file is**: the binding record of the two mandatory named inputs to
the conformance-claim-ceiling decision (`../DEFERRED.md` POL-6) and the shape
that decision must take. **It does not decide the policy** — no conformance
claim is made, widened, or narrowed here; this file changes no verdict in
`bsec/verdicts_recorded.tsv` and asserts no severity.

**Ledger status**: POL-6 remains DEFERRED. Nothing below is an adjudication.

---

## The two mandatory named inputs

1. **The destruction input is the TOML spec's OWN v1.1.0 example.**
   `"Jos\xE9"` — the spec's own v1.1.0 escape example — decodes, under the
   library's default `Toml` flavor, to `4A 6F 73 E9` instead of the required
   `4A 6F 73 C3 A9`: a decoded value that is not well-formed UTF-8, invalid
   by the subject's own DFA validator and by CPython
   (`utf8/report.md` §5 probe table + version-scoped verdict; spec basis
   `SPEC_BASELINE.md` §1/§4). Any argument of the form "only exotic inputs
   trigger this" is closed by the record: the failing input is verbatim spec
   text.

2. **The corrupting round-trip is entirely inside the library's own default
   configuration.** The writer emits `\xHH` for a multi-byte character
   (`é`, input bytes `C3 A9` → emitted token `"\xE9"`;
   `writer_table/report.md` Task 4 corollary + surprising fact #5), and the
   reader inserts the raw byte for `\xHH` (`lexer.nim:429`;
   `utf8/report.md` §5). Under the default `Toml` flavor
   (`Toml_v110_Flags`, `TomlHexEscape` included, no user flags) a single
   encode→decode cycle loses bytes (`C3 A9` → lone `E9`). No unusual input,
   no unusual flag, no third party, no adversarial document required. This
   is the single most upstream-actionable fact in the record.

Supporting recorded rows: `writer_table/preservation.tsv` (v110 lossy set
0xC0–0xFD), `writer_table/escapes.tsv` (95 v110 `\xHH`-emitting bytes),
`bsec/evidence/callsite.md`.

## The decision's shape

- **The default conformance claim must be limited to the spec versions and
  input sets actually tested** — v1.0.0 behavior over the byte strings and
  documents enumerated in `writer_table/` (escapes/keys/roundtrip/
  preservation), v1.1.0 behavior over the probe cases in `utf8/report.md`
  §5, all at subject revision `4aa8e222`. A claim outside those axes is not
  supported by this record.
- **Expanding the claim requires coverage evidence at the expanded scope** —
  a new measured input set, version-scoped per `SPEC_BASELINE.md` §7, not a
  re-reading of the existing tables. The two named inputs above are the
  bound floor: no expansion argument may treat them as edge cases (input 1)
  or as non-default configuration (input 2).
- The decision itself — which claim to state, where, and with what wording —
  is a separate, human-owned policy act. When it is taken, it starts from
  the pinned bytes (`MANIFEST` + archives), per the ledger's non-interference
  rule.

---

*Written 2026-10-12 as the evidence binding for DEFERRED.md POL-6. Not a
verdict, not a severity claim, not an upstream communication.*
