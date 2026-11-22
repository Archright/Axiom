# English-only policy -- scope, modes, metrics, and terminal criteria

**Status**: Proposed (2026-11-22). Normative contract for the English-only plan
([ADR-0045](../adr/0045-english-only-canonical-main.md)). Phase 0 declares the
contract; no detector and no gate dimension is active yet.

This document is machine-relevant: the field names, the metric definitions, the
terminal criteria, and the UNKNOWN conditions are the vocabulary a conforming
evaluator and report MUST use.

## 1. Claim and non-claim

**The claim this policy defines**: Axiom-owned tracked text is English
single-source. The claim does not hold for the current tree: section 8 defines the
terminal criteria, and Phase 0 reaches none of them (see the pinned inventory and
section 8).

**Explicit non-equivalence**: the existing `script-scan` dimension of
`publication-integrity` is a **Unicode Script allowlist over added diff lines**. It is
**not** an English-only judgment, it does not scan the full tree, it does not detect
Latin-script non-English prose, and it does not read GitHub conversation text. A tree
that passes `script-scan` is "clean under the Script allowlist"; it is not
"English-only". See ADR-0044 and `docs/spec/publication_integrity_gate.md` section
3.6. Any report, PR body, or human summary that equates the two is non-conforming.

**NLID requirement**: the word "English-only" MUST NOT be used as a claim until a
pinned natural-language identification (NLID) detector has run over the in-scope set
and reported `nonEnglish = 0` with `unknown = 0`. Before that, the only supportable
statement is the narrower one the detector actually supports.

## 2. Scope

**In scope**: paths declared `ORIGINAL` in `compliance/provenance/source-origin.yml`.
The ownership declaration is the SSOT; this policy does not duplicate the path list.
At the time of writing this includes `docs/**`, `src/**`, `tests/**`, `tools/**`,
`config/**` text, `compliance/**` prose, `.github/**` prose, `experiments/**` prose,
and the declared root files.

**Out of scope -- third-party**: paths declared `THIRD_PARTY` in
`compliance/provenance/source-origin.yml`, including the license texts under
`LICENSES/`, `vendor/**` except the recorded `ORIGINAL` `.gitignore`,
verbatim upstream code excerpts embedded in tests and experiments, third-party
fixtures, and the third-party PDF
`docs/spec/SVF-SVC_Software_Verification_Using_SVF.pdf`. Axiom does not own the
wording and cannot lawfully translate it.

**Out of scope -- non-prose**: binary files, images, archives, and declared generated
artifacts whose value is their exact byte content (measurement logs, JSONL
trajectories, hash manifests, lock files, and similar machine-readable data). These
are judged by their own format contracts. Natural-language string data inside them is
counted separately as a non-prose finding (section 7) and is never silently passed.

**Out of scope -- conversation**: PR titles, PR bodies, issues, reviews, and commit
messages are governed by the contributor contract (issue #373; the root
`CONTRIBUTING.md` awaits the audited trust-surface lane). No current gate reads them.
A workflow could read PR fields from the event payload, commit messages from `git
log`, and issues or reviews through the API, so this is a gap in the gate, not a
platform impossibility. They are declared as a limitation, not as a pass.

## 3. Ownership classes

Every path belongs to exactly one class. The class is derived, never re-declared:

| class | derivation | language rule |
|---|---|---|
| `AXIOM_OWNED` | `origin: ORIGINAL` in `compliance/provenance/source-origin.yml` and not non-prose | English required |
| `THIRD_PARTY` | `origin: THIRD_PARTY` in `compliance/provenance/source-origin.yml` | not judged; notices stay verbatim |
| `NON_PROSE` | binary detection, declared generated artifact, or machine-data format under an `ORIGINAL` path | not judged as prose; string data counted separately |

A path that matches no declaration is a provenance failure in the existing
`provenance` dimension and is UNKNOWN here, never `AXIOM_OWNED` by default.

## 4. Exceptions

- An exception MUST name exactly one path and one reason. Exact paths only.
- Directory wildcards are forbidden, with one exception: a directory root that is
  itself a declared `THIRD_PARTY` root in `compliance/provenance/source-origin.yml` MAY be used with the
  same `**` form used there. No new wildcard form is introduced by this policy.
- An exception does not change the ownership class and does not relax the terminal
  criteria; it declares why a path is outside the judged set.
- Adding or removing an exception is a policy change. It cannot be done inside the
  change it enables.
- `data/i18n/ko.json` remains an exact-path exemption for `script-scan` only. Under
  this policy it is counted by `koreanLocaleAssets` (section 8) and is not exempt.

## 5. Modes

### 5.1 Migration

- Judgment is against a findings baseline. The baseline records per-path counts at a
  measured commit.
- **Increase is FAIL.** A path whose current count exceeds its baseline entry fails.
  A new path with a non-zero count and no baseline entry fails.
- **Decrease is PASS.** A count below its baseline entry passes and may be written
  back as the new baseline only through the reviewed baseline update in section 5.3.
- A baseline file that is absent in Migration mode is **UNKNOWN**, not zero. The mode
  cannot start without a measurement origin.

### 5.2 Strict

- Full-tree scan over the in-scope set. No baseline is consulted.
- Every finding is FAIL. The terminal criteria in section 8 are the pass condition.
- A baseline file that is still present in Strict mode is **UNKNOWN**: the mode is
  defined by the absence of a baseline, and a leftover baseline is a contradiction,
  not a silent override.

### 5.3 Baseline updates

- The baseline is a measurement origin, never an exemption list.
- Moving the baseline forward, or adding an entry, is a reviewed policy change under
  the same authority as any other policy change. It cannot land in the change it
  admits.
- Removing the baseline is the Strict-mode transition and requires all terminal
  criteria to hold at that commit.

## 6. Metrics

A conforming report carries these four numbers **separately**. They MUST NOT be
summed, averaged, or converted into one another. A single "non-English count" is a
non-conforming report.

| field | definition | unit |
|---|---|---|
| `scannedFiles` | number of in-scope files the run attempted to classify; includes files that ended UNKNOWN | files |
| `matchedFiles` | number of files with at least one finding of any criterion; a file with findings in two criteria counts once | files |
| `findings` | number of finding records emitted by the detectors; one file may emit many | records |
| `codePoints` | number of code points judged disallowed by the Script criterion | code points |

`findings` is not a line count and not a code point count. `codePoints` is not a
finding count. A file can be one `matchedFile`, carry twelve `findings`, and contain
nine hundred `codePoints`; all three facts are true and none is derivable from the
others.

## 7. Criteria

The report carries four criterion counters:

| criterion | meaning | source |
|---|---|---|
| `disallowedScript` | code points outside the Unicode Script allowlist in `AXIOM_OWNED` prose | pinned Script detector |
| `nonEnglish` | text classified as not English by the pinned NLID detector | pinned NLID detector |
| `unknown` | in-scope files or detector steps the run could not classify | evaluator |
| `koreanLocaleAssets` | tracked Korean-locale product assets | declared locale path inventory |

`nonEnglish` is a criterion count of classification records, not a code point count.
`disallowedScript` is a criterion count of Script violations; the `codePoints` metric
is the separate code point total behind it.

## 8. Terminal criteria

The English-only terminal state holds only when **all four** are zero at the judged
commit:

```
disallowedScript  = 0
nonEnglish        = 0
unknown           = 0
koreanLocaleAssets = 0
```

- `disallowedScript = 0` -- no in-scope prose carries a code point outside the Script
  allowlist.
- `nonEnglish = 0` -- no in-scope prose is classified as non-English.
- `unknown = 0` -- every in-scope file and every detector step produced a
  classification. One UNKNOWN is enough to block the terminal state.
- `koreanLocaleAssets = 0` -- no tracked Korean-locale product asset exists. At the
  time of writing the only such asset is `data/i18n/ko.json`. Phase 0 does not remove
  it; the metric exists so the remaining delta is visible and is a separate product
  decision. Until it reaches zero the terminal state is not reached, regardless of the
  other three counters.

Strict mode passes when the terminal criteria hold. Migration mode can pass per-change
while the terminal criteria are still non-zero; that is the ratchet, not the terminal
state.

## 9. Detector pinning

Every detector MUST be pinned and the pin MUST be bound into the report. A version
string alone is not a pin.

| detector | pin fields | requirement |
|---|---|---|
| `script` | `name`, `version`, `sha256` | the artifact that runs; the version string is checked against the policy |
| `nlid` | `name`, `version`, `sha256`, `modelSha256` | the artifact plus the model weights digest; an unpinned or model-less classifier is not conforming |

- **Script detector**: `ripgrep` 14.1.0 over the pattern
  `[^\x00-\x7F\p{Latin}\p{Greek}\p{Common}\p{Inherited}]`, default engine, Unicode
  15.0. This policy consumes the detector that `script-scan` already runs; it does not
  redefine it. The pin is split across two files today:
  `compliance/policy/script-scan-policy.yml` carries `ripgrepVersion` and
  `gitMinVersion`, and `.github/workflows/publication-integrity.yml` pins the ripgrep
  release tarball by sha256 before extraction. The evaluator reports the observed
  binary digest but does not compare it to a policy-pinned value. The English-only
  detector MUST close that gap by binding `sha256` into the policy itself.
- **NLID detector**: deterministic, offline, no network call, no per-run model
  download. The model digest MUST be recorded even when the model ships inside the
  artifact, because the artifact digest and the model digest answer different
  questions.
- A pin mismatch between policy and observed tool is **UNKNOWN**. A missing pin is
  **UNKNOWN**. Neither is a pass.
- The detector set is recorded as an array so a later detector can be added without
  redefining the schema.

## 10. UNKNOWN semantics

UNKNOWN is blocking. It is never a pass and never converted to zero. At minimum the
following are UNKNOWN:

- invalid UTF-8 in an in-scope file;
- a submodule or gitlink in the in-scope set;
- a detector that is missing, version-mismatched, unpinned, or lacking a model digest;
- a baseline that is absent in Migration mode or present in Strict mode;
- a language classification below the detector's declared confidence floor;
- an in-scope path that is declared but not readable at the judged commit;
- a policy file that fails to parse, or a policy digest that does not match the
  report binding;
- an exception that does not resolve to exactly one tracked path.

The evaluator MUST report the UNKNOWN count and MUST fail the verdict while it is
non-zero.

## 11. Translation lineage

A translation batch MUST carry a translation lineage record
(`docs/spec/translation_lineage.md`). The record binds source blobs, translated
blobs, engine pin, glossary digest, and review state. Legal provenance
(`compliance/provenance/source-origin.yml`) answers ownership and license; translation
lineage answers what text became what text, and the two MUST NOT be merged.

A change that translates text and carries no lineage record is non-conforming at
review. It is not counted as a translated finding because no finding exists; the
missing record is a review failure, not a metric.

## 12. Report shape

```yaml
schemaVersion: "axiom.english-only-report.v1"
mode: "migration"            # migration | strict
verdict: "PASS"              # PASS | FAIL | UNKNOWN
policySha256: "<64-hex>"
head:
  commit: "<40-hex>"
base:
  commit: "<40-hex>"         # migration baseline origin; empty in strict
detectors:
  - id: "script"
    name: "ripgrep"
    version: "14.1.0"
    sha256: "<64-hex>"
  - id: "nlid"
    name: "<tool>"
    version: "<version>"
    sha256: "<64-hex>"
    modelSha256: "<64-hex>"
metrics:
  scannedFiles: 0
  matchedFiles: 0
  findings: 0
  codePoints: 0
criteria:
  disallowedScript: 0
  nonEnglish: 0
  unknown: 0
  koreanLocaleAssets: 0
```

`verdict` is the closed set PASS / FAIL / UNKNOWN. Exit codes follow the existing
gate convention: 0 PASS, 1 FAIL, 2 UNKNOWN.

## 13. Declared limitations

- NLID is a classifier, not an oracle. False negatives and false positives are
  possible; the confidence floor converts ambiguity into UNKNOWN rather than a guess.
- Conversation text in GitHub is outside every repository scan and remains a
  contributor obligation.
- Binary formats and undeclared document formats are not inspected.
- Historical Git objects are bilingual by design; the policy judges a commit, not
  history.
- Non-prose string data is counted separately and is not translated in place.
- The metrics are a snapshot; they are not a claim about any other ref or any future
  commit.

## 14. References

- [ADR-0045](../adr/0045-english-only-canonical-main.md) -- the decision and its
  declared limitations.
- [ADR-0044](../adr/0044-unicode-script-allowlist-admission.md) -- the Unicode Script
  allowlist dimension; explicitly not an English-only guarantee.
- `docs/spec/publication_integrity_gate.md` section 3.6 -- `script-scan` semantics.
- `docs/spec/translation_lineage.md` -- batch manifest schema.
- `compliance/provenance/source-origin.yml` -- ownership classes.
- `compliance/policy/script-scan-policy.yml` -- the Script detector contract this
  policy consumes.
- Issue #373 -- the contributor-facing language rule (the root `CONTRIBUTING.md`
  awaits the audited trust-surface lane).