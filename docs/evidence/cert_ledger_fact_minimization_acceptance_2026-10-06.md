# Cert-Ledger Fact Minimization Production Acceptance — ledger connection reuse + artifact cert fact (2026-10-06)

## Scope

Production observations for the two workstream slices landed this day, closing the cert-ledger scan bottleneck mechanically attributed in [v1_v2_acceptance_2026-10-06.md](v1_v2_acceptance_2026-10-06.md):

- **#511** — PR #511 (mergeCommit `6d4e7b8df`, merged 2026-10-06T14:34:53Z): cert-ledger HTTP connection reuse.
- **#512** — PR #512 (mergeCommit `a6524975d1`, merged 2026-10-06T15:29:31Z): cert fact minimization Slices A+B — `--cert` artifact fact replaces the full ledger scan; pinned recursive-tree index shrinks bootstrap 3+4N → 3+N.

## Background — the problem

The production merge_group verdict unconditionally performed the full cert-ledger scan (3+4N requests) even when the run already received a certificate via the `--cert` artifact — the artifact was bound, then the ledger was re-walked anyway.

#506 baseline (verdict job 112236610580, production verbatim):

```
[INFO] merge_cli: phase=cert-ledger-scan certs=273 elapsed_ms=306676
[INFO] merge_cli: attribution: collect_ms=308861 bind_ms=0 predicate_ms=0 total_ms=308861
```

cert-ledger scan = 306,676ms of collect 308,861ms (99.3%).

## Slice C adjudication (design rationale)

Exact O(1) cert lookup was discarded. Of the subjectId 6-tuple, `evidenceDigest` is the full kernel-input hash of the attest stage and is NOT_DERIVABLE at admission time — an admission-side exact lookup cannot reconstruct the key without re-running attest, which would be a second transport of the same work (circularity). Therefore the deterministic terminal point is: **`--cert` path = 0 ledger requests; bootstrap path = 3+N**. Avoiding the circular second transport is the correct boundary.

## PR #511 — ledger connection reuse (merged 6d4e7b8df, 2026-10-06T14:34:53Z)

- Local A/B: per-request 419ms → 353ms; scan 470.8s → 396.9s (−15.7%); request count unchanged (1,115 = 3+4×278).
- Production: landing group run 37478432734, verdict job 112323309057 (production log, verbatim):

```
[INFO] merge_cli: phase=cert-ledger-scan certs=279 elapsed_ms=258057
[INFO] merge_cli: attribution: collect_ms=259902 bind_ms=0 predicate_ms=0 total_ms=259903
```

collect 259.9s vs the #506 baseline 308.9s = **−15.8%**; verdict GO.

- Honest finding: the dominant remaining cost is GitHub API server latency (~300ms/req), not the client transport — the fundamental improvement is reducing the request count, which is what #512 does.

## PR #512 — cert fact minimization Slices A+B (merged a6524975d1, 2026-10-06T15:29:31Z)

- **Slice A** (`merge_cli.nim`): when the `--cert` artifact fact is pre-bound, the full ledger scan is skipped; the `--apply` double-scan is removed.
- **Slice B** (`ledger_side_ref.nim`): pinned recursive-tree index shrinks bootstrap from 3+4N to 3+N requests.
- **Fail-closed addition**: `truncated=true` from any ledger walk is a new fail-closed path.

Local evidence:

- `--cert` path: 0 ledger requests, collect 2.6s, verdict bytes identical (GO) versus the scan path.
- Bootstrap path: 282 = 3+279 requests (1,119 → 282, −73%), collect 117.3s.
- `test_merge_cli` 65/65 (6 new), `test_attestation` 224 checks; all fail-closed paths regressed green (NO_CERT / SUBJECT_MISMATCH / POLICY·SCOPE / CERT_INVALID / STALE_BASE / truncated).

### Production acceptance (core)

Landing group run 37487107918 (merge_group, conclusion success), verdict job 112354374179, wall clock 1m31s (15:32:44Z → 15:34:15Z). Production log, verbatim:

```
[INFO] merge_cli: phase=fact-certledger skipped (artifact --cert fact replaces ledger scan)
[INFO] merge_cli: attribution: collect_ms=2095 bind_ms=0 predicate_ms=0 total_ms=2096
[check] certificate source = ARTIFACT subject-certificate-1 (--cert /home/runner/work/Axiom/Axiom/.subject-certificate/certificate.json)
{"prNumber":514,"headSha":"2970a1c7ac5afe0dd12c94b2a14143c0f7c12ff1","baseSha":"a6524975d16bcce2be57377db4d176d5c256cf13","verdict":{"result":"mergeGo","reasonCode":"GO", ...}}
```

- verdict GO; ledger requests = **0** on the `--cert` path (no `cert-ledger-scan` phase fired anywhere in the verdict job log).

## Terminal outcome comparison

| Metric | baseline (#506) | after #511 | after #512 |
|---|---|---|---|
| production collect | 308.9s | 259.9s (−15.8%) | **2.1s (−99.3%)** |
| verdict job wall clock | ~5m38s | 4m40s | **1m31s** |
| `--cert` path ledger requests | ~1,119 | ~1,119 | **0** |
| bootstrap requests | 3+4N | 3+4N | **3+N (282, N=279)** |
| verdict | GO | GO | GO (identical) |

## Invariants verified unchanged

- NO_CERT vocabulary; duplicate-cert warn + newest-wins adoption; `certRequired`; subject wire format (`axiom.subject.v2`); required check names; all fail-closed semantics — unchanged.
- Certification reuse, not caching: the artifact fact *is* the certificate bound at admission; the cache≠certificate distinction is preserved.

## Follow-up candidates (out of scope, recorded only)

- Bootstrap path 117s at 3+N: per-request ~300ms server latency dominates — parallelization is a separate workstream.
- Live verdict byte-comparison of the old binary was not performed (API budget); substituted by fixture tests + byte-identical two-path comparison + production baseline citation.
