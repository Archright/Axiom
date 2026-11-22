# ADR-0045: English-only canonical main -- single-language tracked text with a migration ratchet

## Status

**Proposed (2026-11-22)** -- architecture decision record for Phase 0 of the
English-only plan. This ADR declares the contract. It does not land a detector, it
does not add a gate dimension, and it does not translate any content. Activation is a
later phase and follows the same rules.

## Date

2026-11-22

## Context

The tracked tree carries Axiom-owned text in two languages. English is the language of
code, commit messages, and the contract documents; a large part of `docs/` (notably
`docs/evidence/`, `docs/spec/`, and `docs/adr/`) is Korean-heavy prose, and the product
ships a Korean locale catalog at `data/i18n/ko.json`. Measured for this plan with the
scope defined in `docs/spec/english_only_policy.md` (tracked tree, `.github` included,
`.git` excluded), the baseline inventory is 1,049 files, 67,440 lines, and 1,221,999
code points carrying text outside the Latin/Greek/Common/Inherited Script set. The
number is a measurement origin, not a target for deletion: every one of those code
points stays reachable in Git history.

Four facts constrain the design.

1. **ADR-0044 is not an English-only guarantee.** The `script-scan` dimension of
   `publication-integrity` enforces a Unicode Script allowlist over added diff lines.
   Its own declared limitations state that Latin-script non-English prose (French,
   Spanish, German), Greek prose, Common/Inherited punctuation, HTML numeric entities,
   Unicode escapes, binaries, and GitHub conversation text all pass. A tree that is
   green under `script-scan` can still be mostly non-English. Any wording that presents
   the Script allowlist as "English-only" is a contract violation (ADR-0044
   Consequences; `docs/spec/publication_integrity_gate.md` section 3.6).

2. **The Script allowlist cannot see the failure mode that matters.** The residual
   false confidence named by ADR-0044 is exactly the case an English-only policy must
   judge: prose written in a Latin script but not in English. Detecting that requires
   natural-language identification (NLID), not a Script table. NLID is a probabilistic
   classifier with a pinned model; it is not a property of Unicode.

3. **History is evidence and must not be rewritten.** Commit identities, blob SHAs,
   certificates, admission continuity, and the verification ledger are addressed by
   commit and blob. Rewriting history to erase Korean would invalidate those
   addresses and is irreversible. The goal is therefore a property of the current
   tree, achieved additively, with every original blob still reachable at its original
   commit.

4. **Landing authority is GitHub and is not ours to widen.** The `main` ruleset
   (`27097366`, `enforcement: active`, `bypass_actors: []`) requires seven contexts and
   a merge queue (`ALLGREEN`, native `MERGE`). `publication-integrity` is the only
   required context that judges repository content. Adding a required check, a GitHub
   App, or a ruleset rule would change the merge-authority surface; this plan is not
   authorized to do that and does not need to.

A fifth fact shapes the language rule itself: the repository can judge tracked text,
but it cannot judge conversation. PR titles, bodies, issues, reviews, and commit
messages never enter a landing diff, so no repository-side gate can read them. The
single-language rule therefore has two halves: a machine-judged tree property and a
contributor obligation for the untracked conversation surface.

## Decision

**(a) Axiom-owned tracked text is English single-source.** "Text" means prose,
documentation, comments, user-facing strings, identifiers as they appear in prose,
commit messages, and the repository-tracked artifacts of collaboration. Axiom-owned
means every path declared `ORIGINAL` in `compliance/provenance/source-origin.yml`.
The ownership declaration is the SSOT; this ADR does not carry a second path list.

**(b) Scope excludes third-party rights material and non-prose.** Paths declared
`THIRD_PARTY` in `compliance/provenance/source-origin.yml` are out of scope:
`LICENSES/**`, `vendor/**`, verbatim upstream code excerpts embedded in tests and
experiments, third-party fixtures, and the CC-BY-4.0 PDF
`docs/spec/SVF-SVC_Software_Verification_Using_SVF.pdf`. Axiom does not own the
wording of that material and cannot lawfully translate it. Binary files and declared
generated artifacts are non-prose and are judged by their own format contracts, not by
language.

**(c) Past Git objects are preserved and originals are traceable by blob SHA.**
Translation is additive: a new commit adds the English text, and the source blob
remains reachable at `sourceBaseCommit`. No history rewrite, no force-push of `main`,
no filter-repo. Every translation batch records the source and translated blob
digests in a translation lineage manifest
(`docs/spec/translation_lineage.md`). "English-only" is a claim about the current tree
and the current conversation surface, never about history.

**(d) Two modes, one ratchet.** Migration mode judges against a findings baseline:
an increase over the baseline is FAIL, a decrease is PASS, and the baseline moves only
through a reviewed policy change. Strict mode scans the full tree with no baseline and
requires zero findings. The baseline is a measurement origin, never an exemption list.
Mode definitions, metric definitions, and terminal criteria are normative in
`docs/spec/english_only_policy.md`.

**(e) The existing `publication-integrity` required check remains the sole landing
verdict.** The English-only judgment, when activated, arrives as an additional
dimension of that context, through the same aggregation seam every existing dimension
uses (job result, report artifact, policy file). The context name, the job id, and the
workflow path stay unchanged.

**(f) No new required check, no new GitHub App, no ruleset change.** The ruleset, its
seven required contexts, the producer identities, the merge queue parameters, and
`bypass_actors: []` are unchanged by this ADR and by every phase that implements it.
The judgment cannot ride the merge queue until it is inside the existing context,
which is the only reason to prefer the seam over a new check.

**(g) NLID is required before claiming "English-only".** The claim requires a pinned
natural-language identification detector to report `nonEnglish = 0` over the in-scope
set. Until that detector exists, is pinned by name, version, and artifact sha256, and
runs, the only supportable claim is "clean under the Unicode Script allowlist". The
distinction is mandatory in every report and every human summary. This is the
anti-theater clause of the ADR (AGENTS.md section 0.9): a Script table is not a
language detector, and reporting it as one would be a false guarantee.

**(h) UNKNOWN is blocking and never a pass.** Unreadable input, invalid UTF-8, an
unpinned or version-mismatched detector, a missing model digest, and an ambiguous
classification all produce UNKNOWN. UNKNOWN blocks the claim and, once the dimension is
wired, blocks the landing verdict for that dimension.

**(i) Exceptions are exact paths only.** An exception names one path and one reason.
Directory wildcards are forbidden except where the directory root is itself a declared
third-party root in `compliance/provenance/source-origin.yml`. No new wildcard is
invented by this policy.

**(j) ADR-0044 is retained unchanged.** The Unicode Script allowlist remains a
separate, weaker judgment with its own declared limitations. The English-only
dimension does not replace it, does not weaken it, and does not inherit its
exemptions. `data/i18n/ko.json` stays an exact-path exemption for `script-scan` and is
counted, not exempted, under the English-only terminal criteria.

## Consequences

- **One language for tracked text.** Reviewers read one language, and a translated
  document has one source of truth instead of a drifting pair.
- **The debt is visible and monotone.** Migration mode forbids growth and allows
  shrinkage, so the corpus converges without a single unreviewable mass rewrite.
- **Translation becomes an auditable event.** A batch manifest binds source blobs,
  translated blobs, engine, glossary, and review into one record
  (`docs/spec/translation_lineage.md`). Legal provenance stays separate and unchanged.
- **History remains bilingual forever.** The repository will always contain Korean in
  past objects. That is a deliberate consequence of not rewriting history, not an
  incomplete migration.
- **Evidence files need care.** A measurement log whose value is its byte content is
  non-prose; translating it produces a new artifact, not an edit. The lineage record
  says which blob the translated text came from.
- **Contributor cost moves to the front.** A contributor reads the CLA and writes in
  English; the landing path gains no new check and no new approval step.
- **The residual is NLID quality.** A pinned detector can be wrong in both directions.
  UNKNOWN and the review gate are the mitigations; neither makes the detector
  infallible, and the declared limitations say so.

## Alternatives rejected

1. **Rewrite history to purge Korean.** Rejected: it invalidates blob-addressed
   evidence, certificates, and admission continuity; it is irreversible; and the goal
   is a tree property, not an erasure. Originals must stay traceable by blob SHA.
2. **A whole-tree "no non-ASCII" rule.** Rejected for the same reasons ADR-0044
   rejected it: it fails on legitimate punctuation and notation, and it still passes
   Latin-script non-English prose. It is the wrong claim in both directions.
3. **A new required check or a new GitHub App.** Rejected: it changes the
   merge-authority surface, needs a ruleset change and a new producer identity, and
   splits the single-verdict contract. The existing context already has the seam.
4. **Translate third-party material.** Rejected: Axiom does not own the rights, and
   license notices must remain verbatim for compliance.
5. **Per-file lineage records.** Rejected: the same facts are recorded once per batch
   at a fraction of the overhead, and per-file records would be generated noise that
   no reviewer reads.
6. **Claim "English-only" on the Script allowlist alone.** Rejected as theater: the
   allowlist cannot see Latin-script non-English prose, so the claim would guarantee
   nothing it appears to guarantee.
7. **One mass-translation PR.** Rejected: unreviewable at the required depth, prone to
   silently changing meaning, and it would break evidence files whose value is their
   exact bytes.

## Declared limitations

- Detection depends on a pinned NLID detector. False negatives and false positives are
  possible; UNKNOWN covers ambiguity but not misclassification.
- GitHub conversation text (PR titles, bodies, issues, reviews) is a contributor
  obligation. No repository-side gate can judge it at landing.
- Binary files and document formats outside the declared extension set are not
  inspected.
- Historical Git objects remain bilingual by design.
- Non-prose evidence may contain natural-language string data (quoted log lines,
  captured messages). It is excluded by ownership class and counted separately, not
  silently passed.
- The metrics are a snapshot of a tree at a commit. They are not a proof of authorial
  intent and they do not survive as a claim about any other ref.

## References

- `docs/spec/english_only_policy.md` -- scope, ownership classes, modes, metrics,
  terminal criteria, detector pinning, UNKNOWN semantics.
- `docs/spec/translation_lineage.md` -- batch manifest schema and translation rules.
- `CONTRIBUTING.md` -- contributor-facing language rule, CLA path, landing path.
- `docs/adr/0044-unicode-script-allowlist-admission.md` -- the Unicode Script
  allowlist dimension; explicitly not an English-only guarantee.
- `docs/spec/publication_integrity_gate.md` section 3.6 -- `script-scan` semantics and
  declared limitations.
- `compliance/provenance/source-origin.yml` -- ownership classes (ORIGINAL /
  THIRD_PARTY) used as the scope SSOT.
- `config/policy/trust_surface_manifest.json` -- the 18 paths whose blob equality
  gates `admission-check`.
- `config/policy/merge_admission.json` -- required contexts and the merge queue
  contract.
- AGENTS.md section 0.9 (theater prohibition), section 0.12 (product contract first),
  section 2.6 (authority invariants).