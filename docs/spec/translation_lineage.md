# Translation lineage -- batch manifest and rules

**Status**: Proposed (2026-11-22). Normative contract referenced by
[ADR-0045](../adr/0045-english-only-canonical-main.md) and
[`english_only_policy.md`](english_only_policy.md).

Translation lineage answers one question: **which source blob became which translated
blob, with which engine, under which glossary, and who reviewed it.** It is not a
license record and it is not a history rewrite.

## 1. Batch-level, not per-file

One manifest covers one translation batch, however many files the batch touches.
Per-file manifests are forbidden: they repeat the same engine, glossary, and review
facts once per file, which increases review overhead and produces records nobody
reads.

- Location: `data/translation_lineage/<batchId>.yml`.
- Format: the restricted YAML subset consumed by `tools/ci/publication_yaml.nim`
  (flat mappings, quoted strings, `- ` lists, 2-space indent). No anchors, no
  multi-line scalars, no flow style.
- One manifest per `batchId`. A `batchId` that already exists MUST NOT be reused for a
  different batch; a corrected batch gets a new id.

## 2. Schema

```yaml
schemaVersion: "axiom.translation-lineage.v1"
batchId: "2026-11-docs-evidence-phase1"
sourceBaseCommit: "<40-hex commit>"
sourcePaths:
  - path: "<source path>"
    blobSha256: "<64-hex>"
translatedCommit: "<40-hex commit>"
translatedPaths:
  - path: "<translated path>"
    blobSha256: "<64-hex>"
engine:
  name: "<engine>"
  version: "<version>"
  modelId: "<provider>/<model>"
  modelSha256: "<64-hex | declared-unavailable>"
glossarySha256: "<64-hex>"
review:
  status: "approved"
  reviewers:
    - "<handle | role>"
  date: "YYYY-MM-DD"
referenceUpdates: []   # omit only when the batch updated no reference
exceptions: []         # omit only when the batch declares no exception
```

Field semantics:

| field | meaning |
|---|---|
| `schemaVersion` | literal `axiom.translation-lineage.v1` |
| `batchId` | stable identifier of the batch; also the file name stem |
| `sourceBaseCommit` | the commit at which every `sourcePaths` entry is addressed |
| `sourcePaths[].path` | repo-relative path of the source file at `sourceBaseCommit` |
| `sourcePaths[].blobSha256` | sha256 of the exact blob bytes of that path at that commit |
| `translatedCommit` | commit that carries the translated text |
| `translatedPaths[].path` | repo-relative path of the translated file |
| `translatedPaths[].blobSha256` | sha256 of the exact blob bytes at `translatedCommit` |
| `engine.name` | engine identity (deterministic translator, LLM, or human-assisted tool) |
| `engine.version` | engine version string |
| `engine.modelId` | provider-qualified model identifier; required when the engine is a hosted model |
| `engine.modelSha256` | sha256 of the model weights when they are locally available; the literal `declared-unavailable` when the engine is hosted and the weights are not distributable |
| `glossarySha256` | sha256 of the glossary revision that pinned terminology when the batch was reviewed; see section 3 |
| `review.status` | closed set: `pending` / `approved` / `rejected` |
| `review.reviewers` | human reviewers; a GitHub handle, or a governance role when the approval is role-bound; the engine is never a reviewer |
| `review.date` | review date, `YYYY-MM-DD`; a date-only value does not prove review-before-landing, so a conforming batch SHOULD also record the review commit |
| `referenceUpdates[]` | references (links, anchors, path mentions) updated because of the translation; the key MAY be omitted only when the list is empty |
| `exceptions[]` | exact paths in the batch that stay verbatim, with a reason; the key MAY be omitted only when the list is empty |

`sourcePaths` and `translatedPaths` are paired positionally; the entries at index `i`
describe one translation relation. A batch that also renames a path records the old
path in `sourcePaths` and the new path in `translatedPaths` at the same index. A batch
that adds a new file with no source, or removes a file, declares that in `exceptions`
with the reason.

## 3. Rules

1. **Source identity is a Git blob.** The source is addressed by
   `sourceBaseCommit:path`, and the recorded `blobSha256` is the content digest of that
   blob. The Git blob object id at that commit MUST resolve to the same bytes. The
   digest is what makes the record verifiable independently of the hash algorithm a
   future Git object format uses.
2. **History is preserved. No history rewrite.** A translation is a new commit. The
   source blob stays reachable at `sourceBaseCommit` forever. Force-pushing `main`,
   filter-repo, and any operation that makes a recorded source blob unreachable are
   forbidden.
3. **Legal provenance is separate.** `compliance/provenance/source-origin.yml` answers
   who owns a path and under which license. Translation lineage answers what text
   became what text. A translation does not change the `origin` class, the copyright
   holder, or the license. Neither record may be used to answer the other's question.
4. **Reproducibility requires identical input, tool, and contract.** The same source
   blobs, the same engine pin (including `modelSha256`), the same glossary digest, and
   the same translation contract MUST produce the same output. A batch that cannot
   demonstrate this MUST NOT claim reproducibility.
5. **Review precedes landing.** `review.status` MUST be `approved` before the batch
   lands. Reviewers are humans. `pending` and `rejected` are blocking.
6. **Engine pinning mirrors detector pinning.** `engine.name` and `engine.version`
   alone are not a pin. A locally run model additionally requires `modelSha256`. A
   hosted model requires `engine.modelId` and MUST record `modelSha256` as
   `declared-unavailable` when the weights are not distributable; such a batch MUST
   NOT claim bit reproducibility, because the provider controls the weights. Same
   model id, prompt contract, and glossary reproduce the procedure, not necessarily
   the bytes. An unpinned engine produces no lineage record that can support the
   English-only claim.
7. **References travel with the translation.** Renaming or translating a document can
   break links, anchors, and path mentions. Every such update is listed in
   `referenceUpdates` so a reviewer can check the batch's blast radius without
   diffing the whole tree.
8. **Exceptions are exact paths with a reason.** A quoted upstream excerpt, a code
   block that must remain byte-identical, or a legal notice stays verbatim and is
   declared. A wildcard is not an exception.
9. **One batch, one commit boundary.** `translatedCommit` is a single commit. A batch
   spread over several commits is several batches, each with its own id.
10. **The manifest is tracked.** It is a tracked record under `data/`, covered by the
    `data/**` origin declaration, and it is reviewed like any other change.

**Glossary revision semantics.** A glossary may be introduced after a batch's
`sourceBaseCommit`. `glossarySha256` therefore binds the glossary revision that the
review actually used, not a file that must exist at `sourceBaseCommit`; the glossary's
introducing commit is the audit anchor. A later edit to the glossary is a new revision
(for example `en-v2`) and never an in-place edit, so a recorded digest never changes
meaning retroactively.

## 4. What lineage does not do

- It does not authorize a translation. Authorization comes from the contribution and
  review process (issue #373; the root `CONTRIBUTING.md` awaits the audited
  trust-surface lane).
- It does not replace the CLA. A contributor grants rights under the CLA; lineage
  records the transformation.
- It does not make a translated third-party text lawful. Third-party material stays
  verbatim and outside scope.
- It does not prove the translation is correct. Review does that; lineage makes the
  review auditable.

## 5. Example batch

```yaml
schemaVersion: "axiom.translation-lineage.v1"
batchId: "2026-11-docs-evidence-phase1"
sourceBaseCommit: "db0e977f6219d33dcfc91be1f9e238a72f2dd53b"
sourcePaths:
  - path: "docs/spec/publication_integrity_gate.md"
    blobSha256: "0000000000000000000000000000000000000000000000000000000000000000"
translatedCommit: "1111111111111111111111111111111111111111"
translatedPaths:
  - path: "docs/spec/publication_integrity_gate.md"
    blobSha256: "2222222222222222222222222222222222222222222222222222222222222222"
engine:
  name: "example-engine"
  version: "1.0.0"
  modelId: "example-provider/example-model"
  modelSha256: "3333333333333333333333333333333333333333333333333333333333333333"
glossarySha256: "4444444444444444444444444444444444444444444444444444444444444444"
review:
  status: "approved"
  reviewers:
    - "reviewer-handle"
  date: "2026-11-22"
referenceUpdates:
  - path: "docs/adr/0044-unicode-script-allowlist-admission.md"
    note: "link target kept after the source file was retitled"
exceptions:
  - path: "docs/spec/SVF-SVC_Software_Verification_Using_SVF.pdf"
    reason: "third-party PDF stays verbatim; its wording is not Axiom-owned"
```

The digests above are illustrative placeholders, not recorded values.

## 6. References

- [ADR-0045](../adr/0045-english-only-canonical-main.md) -- decision and declared
  limitations.
- [`english_only_policy.md`](english_only_policy.md) -- scope, modes, metrics,
  terminal criteria, detector pinning.
- `compliance/provenance/source-origin.yml` -- legal provenance (separate record).
- `tools/ci/publication_yaml.nim` -- the YAML subset parser.
- Issue #373 -- contributor obligations for translated changes (the root
  `CONTRIBUTING.md` awaits the audited trust-surface lane).