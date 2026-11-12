# DEFERRED — ledger of deliberately deferred items (NOT executed here)

**What this file is**: a tracking ledger for work items that exist but were
**deliberately not executed** during the 2026-10-11 evidence-replay
consolidation. Each item is a separate track. None of them has been run,
measured, or adjudicated; activating one requires its own task and its own
evidence base.

**Non-interference rule (binding)**: these items MUST NOT interfere with the
recorded verdicts in `bsec/verdicts_recorded.tsv` / `bsec/JUDGMENT.md` (the
P0 record). No verdict here, no severity assessment, no issue filed. A
deferred item is not an observation; activating one later starts from the
pinned bytes (`MANIFEST` + archives), never from this ledger.

**Status vocabulary**: `DEFERRED` = not started, no claim; `ACTIVATED` =
moved to its own workstream (update the row's evidence pointer when that
happens).

---

## D1 — typed-accessor SIGSEGV + `Table == nil` / `InlineTable == nil` crash

- **Status**: ACTIVATED (2026-10-12) — scope-bounded closure landed at
  `bsec/closure/D1_nileq.md` (72 per-consumer triples = 36 consumers × {D1, D-NIL},
  all N/A via R1 with call-site artifacts; rows in `bsec/verdicts_recorded.tsv` +
  `bsec/offline/consumers/triples_facts.tsv`; set-level summary is a report, not a
  rule-table row; reopen conditions R-O-1..8 in the closure record).
- **Item**: the B-SEC-02 mechanism class — absent-key typed `TomlValueRef`
  accessor nil-dereference (SIGSEGV 139, uncatchable, declared
  `raises: [KeyError]` not honored) — plus the adjacent `Table == nil` /
  `InlineTable == nil` equality-semantics crash.
- **Evidence base**: same zero-import evidence base as the recorded
  B-SEC-02 UNKNOWN (`followup/defects3/report.md`, probes + raw bytes;
  `followup/writer_table/report.md` eq-semantics rows). No new execution
  performed under this ledger.
- **Closure condition**: scope-bounded closure only — a (defect × consumer ×
  attacker-model) triple with its own call-site artifact and its own
  freshness terms. Reachability of `import toml_serialization/value_ops` in
  any consumer is currently unestablished (`bsec/JUDGMENT.md` §2.2).

## D2 — B-SEC-01 × stickyshell (untrusted-repo-checkout class)

- **Status**: ACTIVATED (2026-10-12) — own workstream + evidence recorded; see
  `followup/checkout_trio/report.md`, `followup/checkout_trio/raw/stickyshell/`
  (C-series s0-s8 + decode-state probe), `bsec/offline/callform/consumer_stickyshell.txt`,
  `bsec/offline/consumers/triples_facts.tsv` row `B-SEC-01|stickyshell|attacker-can-write-stickyshell.conf`,
  `bsec/verdicts_recorded.tsv` (NO-GO, scoped; NOT transferred from nph — the
  plain-overwrite precondition and the 3-way equivalence were re-established
  per this consumer). Consumer commit pinned `df552203e55a287264d513d82e964199810a9b6d`
  (master HEAD 2026-10-12); dep floating (no lockfile), experiment-pinned at
  the subject `4aa8e22`. Build scope: Nim 2.0.8 + repo `nim.cfg` `--deepCopy:on`
  (does not compile with 2.2.10 — recorded in the call-site artifact).
- **Item**: triple (B-SEC-01 × `xTrayambak/stickyshell` × attacker writes
  `stickyshell.conf` picked up from CWD — untrusted repo checkout class).
- **Evidence base** (was): classification only — `followup/exposure/consumers.tsv`
  row (decode form `Toml.decode(readFile("..."))`, CWD pickup; resolved dep
  `b5b387e6`, floating). The config data model is NOW verified
  (call-site artifact + contrast runs + capability-delta record).

## D3 — B-SEC-01 × click (untrusted-repo-checkout class)

- **Status**: ACTIVATED (2026-10-12) — own workstream + evidence recorded; see
  `followup/checkout_trio/report.md`, `followup/checkout_trio/raw/click/`
  (C-series k0-k13), `bsec/offline/callform/consumer_click.txt`,
  `bsec/offline/consumers/triples_facts.tsv` row `B-SEC-01|click|attacker-can-write-click.toml`,
  `bsec/verdicts_recorded.tsv` (NO-GO, scoped; NOT transferred from nph).
  Consumer commit pinned `305847074f4b377ccb3ca74eecab1e1c15c34a37`
  (master HEAD 2026-10-12); dep floating (no lockfile), experiment-pinned at
  the subject `4aa8e22`.
- **Item**: triple (B-SEC-01 × `ab9st8/click` × attacker writes
  `click.toml` inside a managed workspace/repo checkout).
- **Evidence base** (was): classification only — `followup/exposure/consumers.tsv`
  row (typed `Toml.decode` of workspace `click.toml`; dep `b5b387e6`,
  floating). Config data model NOW verified. Recorded (not adjudicated):
  `config.compiler` feeds `execShellCmd` verbatim — arbitrary command
  execution is already a property of any valid `click.toml`; the defects
  confer no additional channel.

## CAND-A — Candidate A: stack exhaustion (deep nesting)

- **Status**: DEFERRED
- **Item**: recursion-depth/stack-exhaustion behavior on deeply nested TOML
  (inline tables / arrays-of-tables). Out of scope of the B-1 slice
  (`JUDGMENT.md` §5, §6) and never measured here.
- **Rule-vocabulary ceiling (recorded now, so nobody re-derives it the hard
  way)**: deep nesting is VALID TOML. Any defect-vs-valid contrast is
  therefore `valid_contrast=equivalent`, which caps the current rule table
  at NO-GO (R2). Under the present vocabulary **measurement cannot produce
  GO** for this candidate, no matter what the crash depth is. Activation
  requires either a new rule row (new impact axis, e.g. availability under a
  stated attacker model) or an explicit vocabulary revision — a decision,
  not an observation.
- **Environment note**: crash depth is environment-dependent (stack limit);
  no universal threshold may be recorded (`JUDGMENT.md` §5).

## POL-1..POL-6 — the six policy items

**Activation rule**: activate only what the current judgment needs. These
are the app-policy dichotomies the campaign records observed but explicitly
did **not** adjudicate (`followup/contract/SPEC_CLAIMS.md` (B) class; no
pinned spec clause governs them). None is executed or decided here.

- **POL-1 — Status: DEFERRED** — unknown-key policy dichotomy:
  `TomlUnknownFields` OFF raises `Unexpected field`, ON silently skips,
  and past the early break BOTH silently ignore (`contract.md` §1; SPEC_CLAIMS §5).
- **POL-2 — Status: DEFERRED** — missing-field completeness: 0–2 of 3
  fields accepted with silent zero-defaults; no required-fields notion
  anywhere (`contract.md` §2; SPEC_CLAIMS §6).
- **POL-3 — Status: DEFERRED** — case-mode selection: CI/CN mis-target and
  split pairings for byte-distinct colliding keys; CN first-char
  byte-sensitivity (`contract.md` §5b–5d; SPEC_CLAIMS §4).
- **POL-4 — Status: DEFERRED** — duplicate-key acceptance on the typed path
  vs document-first validation (C5 implicated; the reference implementations
  validate the whole document before typed decode, this library does not)
  (`JUDGMENT.md` §4.1 A-1; SPEC_CLAIMS §1).
- **POL-5 — Status: DEFERRED** — writer `\e` unconditional emission
  (invalid in v1.0.0 output; no literal-string emission path exists)
  (`followup/writer_table/report.md` surprising facts #6; `bsec/JUDGMENT.md` B-SEC-03 row).
- **POL-6 — Status: DEFERRED — MANDATORY INPUT** — `\xHH` raw-byte
  semantics + v110 multi-byte UTF-8 destruction. The decision carries **two
  mandatory named inputs**, bound here so the decision cannot be taken
  without them:
  - **Named input 1 — the destruction input is the TOML spec's OWN v1.1.0
    example, not an exotic input.** `"Jos\xE9"` — the v1.1.0 spec's own
    escape example — decodes to `4A 6F 73 E9` instead of the required
    `4A 6F 73 C3 A9` (invalid UTF-8 in the decoded value; subject's own
    validator and CPython both call it invalid)
    (`followup/utf8/report.md` §5 probe table + version-scoped verdict).
    This kills the "exotic input" objection: the failing input is verbatim
    spec text.
  - **Named input 2 — the corrupting round-trip is entirely inside the
    library's own default configuration.** The writer emits `\xHH` for a
    multi-byte character (`é`, `C3 A9` → `"\xE9"`;
    `followup/writer_table/report.md` Task 4 corollary + surprising fact
    #5), and the reader inserts the raw byte for `\xHH` (`lexer.nim:429`;
    `followup/utf8/report.md` §5). Encode→decode under the default `Toml`
    flavor (`Toml_v110_Flags` incl. `TomlHexEscape`, no user flags) loses
    bytes (`C3 A9` → lone `E9`) with no unusual input, no unusual flag, and
    no third party involved — the single most upstream-actionable fact in
    the record.
  - Decision's shape (recorded, NOT decided): `followup/conformance_ceiling.md`.
  **This item is a mandatory input to the conformance-claim-ceiling
  decision**: any claim about which spec versions this library conforms to
  is bounded by the byte-destruction rows in `preservation.tsv` /
  `escapes.tsv`. It cannot be skipped when that decision is taken.

---

*Ledger written 2026-10-11 during the evidence-replay consolidation. Nothing
in this file is a verdict, a severity claim, or an upstream communication.*
