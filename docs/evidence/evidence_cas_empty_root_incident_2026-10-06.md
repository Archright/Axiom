# Evidence CAS incident 2 — empty-root ledger tree read (2026-10-06)

## What this record is

The production record of the second fail-closed defect found by the
identity-keyed evidence reuse slice's first real produce+append cycle, its
root cause, fix, and the pin choreography that landed it. Companion to
`evidence_cas_baseline_2026-10-06.md` (incident 1: attest GITHUB_TOKEN
wiring) and `evidence_cas_rollout_timeline_2026-10-06.md` (generation
boundaries).

## Incident

After the wiring fix (`5af2afd6e`) re-armed SL-15, the first PR through the
re-armed generation (Axiom #495, run `37417742964`) passed the attest chain
— the evidence record was produced, keyed, and byte-verified — and then
failed at the mint's exactly-once append:

```
evidence_cli: ledger-append: evidence_ledger.appendEvidence:
evidence_ledger.existingEvidenceAtTip: ledger tree read for tip
0a13b825f556…: GitHub API error …/git/trees/0a13b825…?recursive=1: 404
```

The append had just rooted the side ref (`refs/heads/axiom/evidence-cas`,
root commit "axiom: evidence-cas ledger root", parents=[], tree =
`4b825dc642cb…` — the well-known empty tree) and then tried to list the
tip's tree.

## Root cause (confirmed against the live API)

The Git Data API `/git/trees/<sha>?recursive=1` resolves a **commit** sha
to its tree only when that tree is non-empty:

- `/git/trees/7ddaeb02…` (certificates tip, 255 entries) → 200
- `/git/trees/0a13b825…` (evidence root, empty tree) → **404**
- `/git/trees/4b825dc642cb…` (EmptyTreeSha itself) → **404**

The empty tree is not a materialized fetchable object. So the very first
append to any fresh ledger — and every consult against a root-only ledger
— read a 404 and failed closed. The fail-closed direction is correct (an
unreadable ledger is never treated as "not stored"); the read path simply
could not express "root commit, zero entries".

## Fix (Axiom #495, merge commit `a77a944a`)

`fetchTipTree` in `src/verification/ledger_side_ref.nim`: resolve the tip
**commit** to its tree sha first (`/git/commits/<tip>`); a tip resolving to
`EmptyTreeSha` is normalized to a synthetic empty listing (no entries by
definition); any other tree-read failure — including 404 on a non-empty
tree — still fails closed. All six tip-tree read sites across the
certificate and evidence ledgers now share it
(`listLedgerCertIds`, `listRefEntryNames`, `downloadLedgerCertificate`,
`ledgerHasCertAtTip`, `fetchEvidenceRecord`, `existingEvidenceAtTip`).

Regression E9 (`test_evidence_ledger.nim`): a root-only ledger lists as
empty, reports MISS, accepts its first append exactly-once, and round-trips
the stored record. Full verification: ledger E1–E9, attestation × CAS
T1–T5, identity matrix, wave3 integrity, `check-determinism`,
`check-debt` (1387/1387) — all green.

Known follow-up (out of scope here, not on any failure path):
`src/verification/admission_artifact.nim` lines 245/304/391 retain the
same latent tip-as-tree-sha URL pattern.

## Pin choreography (same documented shape as incident 1)

`.github` #53 (`076c7b5c`) rolled the 4 callee pins back to the pre-SL15
generation so #495 could land through green legacy-callee checks; `.github`
#54 (`e33cd795`) re-rotated them to `a77a944a`. No required check was
bypassed at any point.

## Observation status at record time

This PR is the first landing under the fully-fixed generation. Expected on
its own runs: `pull_request` — the ledger's first successful append
(`AXIOM_EVIDENCE_CAS: MISS — produced + stored record` followed by
`MINT_EVAPPEND: OK`); `merge_group` — same tree, kernel chain skipped,
`AXIOM_EVIDENCE_CAS: HIT — reused + rebound record`. Walls recorded in the
follow-up acceptance record.
