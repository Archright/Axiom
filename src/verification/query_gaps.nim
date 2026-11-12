## query_gaps.nim — Known Gaps / Fail-Closed Register
##
## Documents gaps and self-feeds in the verification-auditor query
## path. These are documented as gap-watch items; none is a verdict-
## path input today (the gate is fail-closed on missing evidence).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## ── GAP-1 ────────────────────────────────────────────────────────
## data/verification_auditor_snapshot.json — orphan artifact.
##
## grep confirms 0 consumers today. It is NOT an input to the
## verification-auditor gate (the gate reads the live working tree
## via walkDirRec + readFile, not this snapshot file). Documented
## here as a gap-watch item. Do not wire it into the query model
## until a consumer is added and approved.

## ── GAP-2 ────────────────────────────────────────────────────────
## baseline.updated_at timestamp — self-feed.
##
## verification_auditor_gate.nim loadBaseline (line 144) writes
## updated_at = `$now().utc` via writeFile during auto-calibration.
## tools/verification_auditor.nim writeBaseline also writes it.
## The verdict logic ignores updated_at (it is zeroed before
## comparison), so baseline CONTENT is the query input, not the
## timestamp. However, the gate's auto-calibration mutates its own
## future input (baseline.json). This is a documented self-feed:
## the gate can change the baseline it will later compare against.
## Mitigation: the baseline domain_count is the semantic input;
## updated_at is metadata and excluded from comparison (see
## verification_auditor.nim writeBaseline: the comparison
## strips updated_at before diffing).

## ── GAP-3 ────────────────────────────────────────────────────────
## walkDirRec existence changes → captured via RepoSnapshotDigest
## recomputation. The snapshot digest recomputes from the live tree
## on each gate invocation, so filesystem changes are reflected
## in the next query identity. No stale cache between invocations.

## ── GAP-4 ────────────────────────────────────────────────────────
## Empty directories are invisible to the digest.
##
## walkDirRec iterates files only; directories produce no entries
## and therefore do not affect RepoSnapshotDigest. Two different
## empty-directory trees produce the same digest. This is a
## documented limitation, not a bug: directory structure is not a
## semantic input for the snapshot-audit gate. If directory-structure
## sensitivity is required, a directory manifest must be added to
## the SelectionRule (future work).

## ── GAP-5 ────────────────────────────────────────────────────────
## data/verification_auditor_snapshot.json vs. live tree.
##
## The snapshot JSON is a static artifact; the live tree (walkDirRec)
## is the authoritative source. If they diverge, the live tree wins.
## The snapshot file should be regenerated or retired.
