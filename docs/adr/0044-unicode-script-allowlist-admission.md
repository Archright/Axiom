# ADR-0044: Unicode Script allowlist admission — the sixth landing dimension of publication-integrity

## Status

**Accepted (2026-11-21)** — architecture decision record; the implementation lands
with it. ADR-0043's venue split is unchanged (preflight `{secret-scan}`, landing = the
full dimension set, landing = the canonical verdict); its dimension enumeration gains
the sixth entry through this ADR.

## Date

2026-11-21

## Context

The `publication-integrity` context is the single required check for publication
readiness at the landing venue (`merge_group` · `schedule` · `workflow_dispatch`).
Its five dimensions each judge a different content property:

| dimension | judgment |
|---|---|
| secret-scan | audited secret fingerprints over the publication surface |
| license-scan | license atoms and copyright holders accounted against declarations or attribution |
| dependency-scan | OSV-indexed vulnerabilities (exit-code adjudication) |
| provenance | every tracked path declared in exactly one origin class |
| sbom | a non-empty SPDX-2.3 artifact with a recorded sha256 |

None of them inspects the Unicode Script property of the text a landing diff adds. A
diff can add prose in Korean, Chinese, Japanese, Cyrillic, Arabic, or Devanagari and
still produce five green dimensions. Review prose in GitHub (PR titles, bodies,
issues, reviews, commit messages) never reaches a repository diff, so no
repository-side gate can judge that text at all.

Two facts constrain the design:

1. The repository already contains non-Latin text (documentation and the product i18n
   catalog `data/i18n/ko.json`). A rule that scans the whole tree would fail on day
   one and force either an allowlist of thousands of paths or a silent weakening. The
   judgment must be scoped to **added lines of a landing diff**, with pre-existing
   text frozen at a measurement origin.
2. A "no non-ASCII characters" rule would be both too broad and too narrow: it would
   reject legitimate punctuation, mathematical notation, and emoji, while
   Latin-script non-English prose (French, Spanish, German) would pass untouched. The
   enforceable, testable claim is a Unicode **Script** allowlist — not an
   "English-only" policy.

## Exact claim and declared limitations

The exact claim, quoted from `compliance/policy/script-scan-policy.yml`:

> the landing diff introduces no Unicode code point whose Script property is outside
> {ASCII range, Latin, Greek, Common, Inherited}, except exact-path product i18n
> exemptions

The only exemption is the exact path `data/i18n/ko.json` (product i18n resource:
Korean locale catalog). Exemptions are exact paths with a reason; wildcards are
rejected by the policy parser.

This is **not** the claim "English-only". The following are outside this stage's
detection and are carried in every dimension report as `declaredLimitations`:

- Latin-script non-English prose (French, Spanish, German) is not detected.
- Greek prose is not detected (Greek is allowed for mathematical notation).
- Common/Inherited punctuation is allowed (U+3002, U+3001, U+30FC, emoji, symbols).
- HTML numeric entities and Unicode escapes are ASCII bytes and are not detected.
- Images and binaries outside the policy's document extensions are not inspected.
- PR titles, bodies, issues, reviews, and commit messages are not scanned.
- Code points are judged by Unicode Script using the default ripgrep engine
  (Unicode 15.0).
- Non-UTF-8 text is UNKNOWN (blocked), never silently passed.

Enforcement scope is `added-lines`: only added diff lines are scanned. Modifying an
existing non-English line emits a new added line and FAILS. Inside the non-exempt
zone a rename keeps existing debt in place because it adds no lines; a rename out of
an exempt path is fully rescanned at its destination; a rename into an exempt JSON
path must still parse as JSON.

## Decision

**(a) Add a sixth dimension `script-scan` to the landing venue.** The landing set
becomes `{secret-scan, license-scan, dependency-scan, provenance, sbom, script-scan}`.
The preflight set stays `{secret-scan}` (ADR-0043). The job shares the landing venue
condition: a `success` result for a dimension the venue does not require is a
BLOCKER (spec §2.1 invariant 4), so the job must not run at preflight.

**(b) Verdicts are the gate's closed set.** PASS / FAIL / UNKNOWN; exit 0 / 1 / 2.
UNKNOWN is blocking and never a pass.

**(c) Fail-closed inputs produce UNKNOWN.** Invalid UTF-8 (the evaluator validates
strictly because ripgrep silently drops invalid bytes), submodule/gitlink changes,
binary files with a document extension (`pdf`, `docx`, `xlsx`, `pptx`, `odt`, `ods`,
`odp`, `epub`), quoted or ambiguous paths, copy headers, an exempt path that is not
tracked, missing or version-mismatched tools, git below the policy floor, unreadable
base/head, a base that is not an ancestor of head, a merge-base that differs from the
declared base, upstream-read failures, and policy parse errors.

**(d) Tool binding.** ripgrep 14.1.0. The workflow pins the release tarball by sha256
(`f84757b07f425fe5cf11d87df6644691c644a5cd2348a2c670894272999d3ba7`) and verifies it
before extraction; the evaluator checks the reported version against the policy and
records the observed binary sha256 (the musl release artifact is
`c2feed7a376d3754958fa6235a6ef88a74bcabc9b0cfccacbd48939b5f87860d`; a local distro
build is recorded, not pinned, because the report binds the run's actual binary).
Git floor 2.40.0 (reference environment 2.43.0). The report binds the policy sha256,
tool and git versions, base/head/merge-base SHAs, and a sha256 of the diff text.

**(e) The baseline is a measurement origin, not an exemption.**
`baselineCommit db0e977f6219d33dcfc91be1f9e238a72f2dd53b` is the evaluator's default
base and freezes the pre-existing corpus so the gate can be activated without a mass
rewrite. It never exempts an added line. The workflow passes an explicit base per
venue (the merge-queue base on `merge_group`; `HEAD~1` on
`schedule`/`workflow_dispatch`), so a landing run judges that landing's change set.
The aggregator accepts a `script-scan` report only when its bound head equals the gate
head: a missing binding is UNKNOWN, a different commit is a BLOCKER.

**(f) No new required check, App, workflow file, or permanent ruleset structure.**
GitHub ruleset `27097366` remains the merge authority. The only affected required
context is `publication-integrity`, whose aggregation gains a sixth dimension through
the same four points every dimension uses: the job's `needs` result, `--job
script-scan=<result>`, `--report script-scan=<report.json>`, and `--policy-file
compliance/policy/script-scan-policy.yml`.

**(g) The judgment input is a trust surface.** The evaluator
(`tools/ci/publication_script_eval.nim`) and the policy
(`compliance/policy/script-scan-policy.yml`) join `config/policy/merge_admission.json`
`trustSurface`, so weakening the allowlist or the detector cannot ride the auto-merge
queue.

**(h) Operational risk — the bypass window is declared.** This change touches the
trust surface, so it cannot ride the auto-merge queue. It lands through a temporary
`OrganizationAdmin` bypass. Two repository rulesets require the `admission-check`
context — `27097366` (`main`, seven contexts) and `27525972` (`main-admission`,
`admission-check` alone) — and each is PUT twice (add the actor, restore
`bypass_actors: []`), four PUTs in total; bypassing only one was measured to fail
with HTTP 405 (2026-11-19 break-glass record). During that window the merge authority
is wider than `[]`. Controls: the pre-change readback is recorded (7 contexts, 5
rules, `bypass_actors: []`, merge queue `MERGE`/`ALLGREEN`, `max_entries_to_build:
100`, `max_entries_to_merge: 1`, `check_response_timeout_minutes: 120`); every PUT is
audited and recorded with timestamps; the window closes on the same UTC day; the
queue is drained before the first PUT; and a final readback must show the contexts,
rules, and `bypass_actors` restored to the pre-change values. This record must never
be described as "no ruleset change".

## Consequences

- **The PR venue is unchanged.** No new context, no new App, no new workflow file;
  `publication-integrity` remains the only required context, and preflight still runs
  `{secret-scan}`. The PR-venue runner cost does not grow.
- **Landing wall time grows by one evaluator run** over the diff; the scan is a single
  ripgrep pass over the collected added lines.
- **Pre-existing debt is frozen, not laundered.** Only added lines are judged, and
  modifying a frozen non-English line fails — the debt stops growing without a
  one-shot mass rewrite.
- **The main residual is false confidence.** A Script allowlist is not an English-only
  policy; the limitations are therefore declared in the policy, copied into every
  report, and repeated in the spec (§3.6). Any wording that presents this gate as
  "English-only" is a contract violation.
- **Reversal is a contract amendment.** Removing the dimension means removing it from
  the aggregator's required set and the workflow step; the required context and
  ruleset stay intact, so rollback of the gate does not move merge authority.
- **Baseline rotation is an explicitly reviewed change.** Moving `baselineCommit`
  forward, or adding an exemption path, is a policy change under the trust surface —
  it cannot be done quietly to admit a diff.

## Alternatives considered

1. **A new required check `script-scan` in the ruleset.** Rejected: it changes the
   ruleset structure and the merge-authority surface, needs a producer identity, and
   splits the single-verdict contract into two contexts. The existing
   `publication-integrity` context already has the aggregation seam.
2. **Reviving the dormant `language_ban_gate.nim`.** Rejected: it judges file
   extensions of staged files (the Python/Shell ban) at the `manual` stage; it has no
   diff, diff-base, or Script semantics. Extending it would conflate two different
   judgments and place a Unicode table outside the publication verdict.
3. **An inline regex in the aggregator (`publication_report.nim`).** Rejected: the
   aggregator would have to invoke tools and produce a dimension verdict, losing the
   single report artifact, the policy sha256 binding, the tool-pin verification, and
   `declaredLimitations`. A shell-level regex would also be un-pinned and
   quoting-fragile.
4. **A pre-commit hook only.** Rejected as the enforcement mechanism: hooks are local,
   bypassable (`--no-verify`), and invisible to the landing verdict. A hook is
   advisory defense, not evidence.
5. **A "no non-ASCII characters" rule.** Rejected: it fails on legitimate punctuation,
   mathematical notation, and emoji, and it still passes Latin-script non-English
   prose — the wrong claim in both directions. The Script allowlist states exactly what
   is enforced.

## References

- `docs/spec/publication_integrity_gate.md` §1 (claim), §2 (structure), §2.1 (venue),
  §3.6 (`script-scan` semantics), §5 (tool capabilities and declared limitations).
- `compliance/policy/script-scan-policy.yml` — allowlist, exemptions, tool contract,
  claim, declared limitations.
- `tools/ci/publication_script_eval.nim` — the evaluator.
- `tools/ci/publication_report.nim` — the aggregator.
- `docs/adr/0043-publication-venue-split.md` — landing venue as the canonical verdict.
- `docs/evidence/epoch_record_script_scan_2026-11-21.md` — freeze/record for this
  cutover.
- AGENTS.md §0.9 (theater prohibition) · §0.12 (product contract first) · §2.5 (CI
  epoch cutover) · §2.6 (authority invariants).
