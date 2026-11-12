# B-SEC verdicts — (defect, consumer, attacker model) rows actually tested in this record

Verdict vocabulary (exactly one of): `GO` | `NO-GO` | `N/A` | `UNKNOWN`.

Canonical verdict-generation ledger: `bsec/verdict_generations.tsv` (APPEND-ONLY, created
2026-10-12). This document is a PROJECTION: it shows the current generation of each verdict
lineage plus its supersession chain — it is not the record of how verdicts changed. Where a
bundle-local row below predates the canonical record, the canonical record governs
(2026-10-12 D2 record correction).

Semantics (corrected 2026-10-11; aligned with `rules/rule_table.tsv` — the
binding encoding — and the campaign record `../JUDGMENT.md`):

- `GO` = security impact reproduced under the stated attacker model and real
  consumer path.
- `NO-GO` = the stated scope of paths and impact hypotheses was TESTED and
  the observed result does not support a security-impact claim. **This is a
  scoped verdict, NOT "no impact exists" and NOT ecosystem safety.** It never
  transfers to other consumers, attacker models, or revisions.
- `N/A` = evidence confirms the path is unreachable in this exact consumer
  AND version (call-site investigation artifact REQUIRED).
- `UNKNOWN` = reachability, attacker control, or impact is insufficiently
  established — fail-closed. Observing one valid contrast input + fail-closed
  behavior does NOT exclude all possible security impact; anything beyond the
  tested scope stays UNKNOWN.

**Defect ids — campaign numbering** (`../JUDGMENT.md` §1 is authoritative):

- **B-SEC-01** = the B-1 defect pair: (i) byte-identical duplicate keys
  accepted, applied last-wins **and** (ii) early break after all fields
  filled; trailing input never validated (`../../JUDGMENT.md`).
- **B-SEC-02** = absent-key typed `TomlValueRef` accessor nil-dereference
  (`../../followup/defects3/report.md`). **Not exercised in this record.**
- **B-SEC-03** = `\xHH` escape inserts the raw byte into the decoded string
  (`TomlHexEscape`; `../../followup/utf8/report.md` §5).

## Tested rows

| Defect | Consumer | Attacker model | Verdict | Evidence |
|---|---|---|---|---|
| B-SEC-01 | nph `2cacf6cc28116e4046e0b67a13545af5c4e756bd` (consumes toml_serialization 0.2.18-76ae1c2a) | attacker-can-write-`.nph.toml` | **NO-GO** | `capdelta/capdelta.md` §2–§3; `link_b_consumer/raw/{c0_baseline_check,c1_dup_exclude_check,c2_valid_exclude_check,c3_dup_color_true_false_diff,c4_valid_color_false_diff,c5_dup_color_false_true_diff,c6_valid_color_true_diff,c7_trailing_garbage_diff,c8_valid_4fields_diff,c10_dup_and_garbage_inplace,c10b_boundary_3fields_garbage,c11_valid_inplace,c12_baseline_inplace}` |

This single NO-GO row covers both facets of B-SEC-01 observed on nph:

1. **Facet (i) duplicate keys last-wins reaches nph** — accepted without
   warning; on the one live field (`color`) both directions observed:
   C3 (true→false) ≡ C4 (`color=false`), C5 (false→true) ≡ C6
   (`color=true`), stdout byte-identical; on the dead pattern fields C1 ≡ C2
   ≡ C0 (identical listing; `exclude = [".*"]` would exclude everything if
   the filter were evaluated — it is never evaluated, `src/nph.nim:428-429`).
2. **Facet (ii) trailing-skip reaches nph** — C7 (4 distinct fields +
   `!!!`/`[[attacker_table]]`/garbage) accepted silently, byte-identical to
   valid C8; boundary C10b (3 distinct fields + `!!!`) is **rejected**
   (`(4, 1) illegal character "!"`) — proving the early break is the
   mechanism. In-place C10 ≡ C11 ≡ C12 (identical rewritten-file manifests).

### Scope conditions of the NO-GO

- Consumer revision `2cacf6cc…`, dependency `toml_serialization`
  0.2.18-76ae1c2a (defect code re-verified in the consumed copy:
  `reader.nim:326-327`, `private/utils.nim:73-87`); Linux; non-TTY stdout;
  `--check`/`--diff`/in-place modes.
- Attacker model limited to writing `.nph.toml` where nph runs. A model
  where the attacker controls only the config and the formatted tree belongs
  to a victim is **not** exercised here.
- Every case's exit code is 3 (fixture `b.nims` unparseable) — uniform
  across arms, carries no signal.
- Byte-identity claims are scoped to per-case outputs (see `README.md`);
  run metadata excluded.
- Protected boundary (`capdelta/capdelta.md` §4): `arnetheduck/nph-action@v1`
  runs `./nph .` on the PR checkout then `git diff --exit-code` (never
  `--diff`, so `color` inert); the judged tree IS the attacker's own PR
  content; no adopter has CODEOWNERS.
- Re-evaluate if a future consumer revision makes the include/exclude
  filters live, reads `color` outside `--diff`, or binds a config type with
  non-overwrite semantics (the equivalence is structural: all four
  `NphConfig` fields are plain overwrites — `capdelta/capdelta.md` §3).

## B-SEC-02 rows (not exercised in this record)

| Defect | Consumer | Attacker model | Verdict | Reason |
|---|---|---|---|---|
| B-SEC-02 | nph `2cacf6cc…` | attacker-can-write-`.nph.toml` | **UNKNOWN** | The defective path (typed `TomlValueRef` accessor) was not exercised in this record. Static fact recorded: nph's source contains **no** `TomlValueRef` usage (grep of `/tmp/bsec_consumer/nph/src` → 0 matches); nph binds only the record type `NphConfig`. The campaign record (`../JUDGMENT.md`, `../verdicts_recorded.tsv`) holds UNKNOWN for this triple ("no reachable consumer found; SIGSEGV shape introduced 71ed139 after both known consumer pins"); that committed judgment is not contradicted here. |
| B-SEC-02 | nph-action@v1 pipeline | same | **UNKNOWN** | Inherits the row above. |

## B-SEC-03 rows

Campaign-record verdicts (canonical generation ledger: `bsec/verdict_generations.tsv`;
reason cells in `verdicts_recorded.tsv` equal the current generation's `payload.reason`
byte-for-byte):

| Defect | Consumer | Attacker model | Verdict | Reason |
|---|---|---|---|---|
| B-SEC-03 | nph `2cacf6cc…` (resolved dep `b5b387e6`, nimblemeta vcsRevision) | attacker-supplies-theme-or-config-input | **N/A** | Call-site artifact `evidence/callsite.md`: at the RESOLVED dep commit `b5b387e6` the `TomlHexEscape` gate (`lexer.nim:391-392`) raises BEFORE the defective raw-byte insert (`lexer.nim:431`) — defect path never executed; static (no `format.nim`, `TomlReader.init flags={}`) + dynamic (probe `probe_nph_profile` rejects `\x45`/`\x80` at nph's exact call form). Rule R1. SCOPE: bound to the resolved commit; nph has no lockfile — a new in-range tag triggers freshness RE-EVALUATE (counterfactual `probe_head_profile` @ `4aa8e22`, same "0.2.18" string: accepts). This corrects this bundle's earlier UNKNOWN rows (2026-10-11), which predate the call-site artifact. |
| B-SEC-03 | ImThemes `d67592d…` (lock-pinned dep `b5b387e6`, nimble.lock vcsRevision) | attacker-supplies-theme-or-config-input | **N/A** | Same gate, lock-pinned: probe `probe_imthemes_profile` rejects `\x45`/`\x80` at `browseview.nim:193` (value-tree path via niprefs `30f522ac`). Rule R1. SCOPE: bound to the locked commit; lock re-resolution triggers freshness RE-EVALUATE. |
| B-SEC-03 | nph-action@v1 pipeline | same | **N/A** (inherited, resolution-bound) | Inherits the nph row: at the recorded resolution the defect path is not executed (R1); no separate canonical triple exists in `verdicts_recorded.tsv`. If the resolution moves into activation (e.g. `4aa8e22` — counterfactual probe accepts), freshness RE-EVALUATE reopens the question; `color`/`--diff` inertness is irrelevant until activation is established. |
| B-SEC-03 | nimbus-eth1 `0c023085…` (vendor submodule `73529768`) | attacker-can-write-`.config-file` | **UNKNOWN** | Umbrella lineage, current generation **VG-0003** (R11, fail-closed): wire egress delta OBSERVED (devp2p Hello clientId lone `0x80`, unreachable by any valid TOML input); CORS and process-state surfaces atomized (H1a-CORS / H1a-PROC below, NO-GO surface-scoped, VG-0004/VG-0005); boundary UNDETERMINED — peer-side runtime handling NOT tested (H1b-runtime open gap); the peer source survey (`p0d2/peer_survey.md`, H1b-source) is a bounded report claim, NOT a protection_boundary observation (R10 design intent is a live-observed boundary; widening what a rule may conclude is a decision, not an observation — `DEFERRED.md` CAND-A). Supersession chain: VG-0001 UNKNOWN (R11) ← VG-0002 NO-GO (R10 on `protection_boundary=neutralizes` — out-of-design, triple value reverted to unknown) ← **VG-0003 UNKNOWN (current, supersedes VG-0002)**. |
| H1a-CORS | nimbus-eth1 `0c023085…` | same, surface-scoped: CORS `sameOrigin` decision surface ONLY | **NO-GO** (surface-scoped) | VG-0004 (R2): defect ≡ defect-free contrast — identical Http403 on the observed CORS surface (appended byte lands in the parsed Uri port in both cases). Scope selector names exactly this one surface — no wildcard over consumers/environments; does NOT transfer to the clientId egress surface. |
| H1a-PROC | nimbus-eth1 `0c023085…` | same, surface-scoped: process-state surface ONLY | **NO-GO** (surface-scoped) | VG-0005 (R2): decode SUCCESS + exit 0 identical across baseline/defect/contrast — zero process-state capability delta. Scope selector names exactly this one surface — no wildcard over consumers/environments; does NOT transfer to the clientId egress surface. |

Report-only claims (NOT verdict rows, per the claim-atomization design): **H1b-source** —
bounded source-survey claim (`p0d2/peer_survey.md`: what the pinned-ref survey covered and
did not cover); **H1b-runtime** — UNKNOWN, NOT tested (open gap, no verdict row asserts it);
**H2** — open-set existence claim over the consumer ecosystem, recorded in the report only;
NO-GO is forbidden for an open-set existence claim (one demonstrated impact would make it
GO; absence in surveyed repos cannot close the set).

## Non-exercised (defect, consumer) pairs beyond the above

| Defect | Consumer | Attacker model | Verdict | Reason |
|---|---|---|---|---|
| B-SEC-01/02/03 | any consumer WITHOUT a canonical verdict row (2026-10-12: the sole verdict authority is the ledger `bsec/verdict_generations.tsv`; `verdicts_recorded.tsv` is its cross-check projection of ledger heads and prose docs are derived report views; `judge` enforces the facts↔recorded↔ledger-head set bijection as a consistency check, not an authority grant — nph, ImThemes, nimbus-eth1, stickyshell, click, and the 36 D1/D-NIL closure consumers) | — | **UNKNOWN** | No call-site investigation artifact exists for any consumer outside the canonical record; per the campaign rule, `N/A` requires recording such an artifact reference. UNKNOWN here means "no triple generated", not "safe" (bsec/JUDGMENT.md §3: 미생성 3원조). |

## Explicit non-goals of this record

No severity or CVSS assessment; no upstream issue filed; no GO forced where
evidence shows none. `UNKNOWN` means "undetermined", not "safe".
