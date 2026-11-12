## Contract tests — Pure ProjectionEngine (S2: debt_projection.nim).
##
## v8 invariant-first contract (executable spec). RED until debt_projection.nim exists.
## The signatures used here ARE the S2 contract — implement exactly these:
##
##   type OrderedEvent* = object
##     commitSequence*, auditSequence*: uint64
##     eventId*: string
##     ev*: ClassificationEvent
##   func orderedEvents*(events: openArray[ClassificationEvent];
##                       commits: openArray[AuditCommit]): seq[OrderedEvent]
##     -- canonical order key = (commitSequence, auditSequence, eventId);
##        uncommitted runs EXCLUDED (I16); event timestamp is NOT an ordering key.
##   func projectAtCommit*(ordered: openArray[OrderedEvent];
##                         projectionVersion, inputRoot: string): UniverseProjection
##     -- fold reduce over ordered events; latest valid state per candidate wins (I19);
##        RESOLVED kept active=false, never deleted;
##        universeDigest = H(canonical(UniverseProjection minus digest)).
##   func universeDigestOf*(p: UniverseProjection): string   -- D3 helper
##
## 4대 불변식: InvProjection (pure deterministic fn of committed events + version),
## I12 (D3), I14 (reconstruct => same digest), I19 (state rule).
## Projection MUST NOT know about time: no times import, no clock, no I/O.

import std/[algorithm, sequtils, strutils, unittest]
import core/types/debt_types
import core/debt/debt_projection

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func dig(s: string): ContentDigest =
  var h = s
  while h.len < 64: h.add('0')
  ContentDigest("sha256:" & h[0 .. 63])

proc mkEvent(cand, run: string; auditSeq: uint64; cls: DebtClass;
             recordedAt = "2026-01-01T00:00:00Z"): ClassificationEvent =
  ClassificationEvent(
    eventId: "ev-" & run & "-" & $auditSeq,
    candidateId: cand, auditRunId: run, auditSequence: auditSeq,
    decisionId: dig("dec-" & cand & "-" & $auditSeq).string,
    classifierVersion: "cv1", ruleSetHash: "rs1", taxonomyVersion: "t1",
    result: cls, evidenceIds: @["e1"], parentEventId: "",
    recordedAt: recordedAt, repositorySnapshot: "snap1")

proc mkCommit(runId: string; seq: uint64): AuditCommit =
  AuditCommit(
    commitId: dig("commit-" & runId),
    commitSequence: seq,
    auditRunId: AuditRunId(runId),
    firstSequence: 0, lastSequence: 0, eventCount: 1,
    eventRoot: dig("eventRoot-" & runId),
    decisionDigest: dig("decisionDigest-" & runId),
    provenanceRoot: dig("prov-" & runId),
    parentCommitId: dig("parent-" & runId),
    recordedAt: "2026-01-01T00:00:00Z")

func runs(ids: openArray[string]): seq[AuditCommit] =
  var seqNo = 1'u64
  for id in ids:
    result.add(mkCommit(id, seqNo))
    inc seqNo

## Local helper: project a raw event set through the public contract.
proc projectEvents(evs: seq[ClassificationEvent]; commits: seq[AuditCommit];
                   projectionVersion, inputRoot: string): UniverseProjection =
  projectAtCommit(orderedEvents(evs, commits), projectionVersion, inputRoot)

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

suite "debt_projection: pure projection contract":

  test "canonical ordering excludes uncommitted events (I16 / InvCanonicality)":
    let commits = runs(["r1"])
    let evCommitted = mkEvent("c1", "r1", 0, dcOpenDebt)
    let evOrphan    = mkEvent("c2", "noRun", 0, dcOpenDebt)
    let ord = orderedEvents(@[evCommitted, evOrphan], commits)
    check ord.len == 1
    check ord[0].eventId == evCommitted.eventId
    check ord[0].commitSequence == 1

  test "permutation invariance after canonical ordering (피드백 §9)":
    ## 같은 committed event SET을 어떤 순서로 입력해도, canonical ordering을 거친
    ## fold 결과는 동일해야 한다. (다른 순서가 다른 의미를 만드는 구조(e.g. OPEN,
    ## RESOLVE 순서)는 set이 아니라 sequence 의미이므로 canonical order key에 반영됨)
    let commits = runs(["r1"])
    let e0 = mkEvent("c1", "r1", 0, dcOpenDebt)
    let e1 = mkEvent("c2", "r1", 1, dcUnverified)
    let e2 = mkEvent("c1", "r1", 2, dcResolved)
    let base = @[e0, e1, e2]
    let shuffled = @[e2, e0, e1]             # 순서만 다르게
    let dupExtra = @[e0, e1, e1, e2]         # 중복 포함 — canonical set으로는 동일
    let pBase = projectEvents(base, commits, "v1", "in1")
    let pShuf = projectEvents(shuffled, commits, "v1", "in1")
    let pDup  = projectEvents(dupExtra, commits, "v1", "in1")
    check pBase.universeDigest == pShuf.universeDigest
    check pBase.universeDigest == pDup.universeDigest

  test "I19 state rule: RESOLVED -> active=false, kept; later OPEN revives":
    ## same candidate: OPEN (r1) -> RESOLVED (r2) -> OPEN (r3)
    let commits = runs(["r1", "r2", "r3"])
    let evOpen  = mkEvent("X", "r1", 0, dcOpenDebt)
    let evRes   = mkEvent("X", "r2", 0, dcResolved)
    let evOpen2 = mkEvent("X", "r3", 0, dcOpenDebt)
    # up to commit seq=2: RESOLVED, inactive, kept (evOpen2 is beyond pB's prefix)
    let pB = projectEvents(@[evOpen, evRes], commits, "v1", "in1")
    let cands = pB.candidates
    check cands.len == 1
    check cands[0].candidateId == "X"
    check cands[0].classification == dcResolved
    check cands[0].active == false
    check cands[0].firstSeen == "2026-01-01T00:00:00Z"
    check cands[0].lastSeen == "2026-01-01T00:00:00Z"
    # full history (up to r3): later OPEN wins, active=true
    let pC = projectEvents(@[evOpen, evRes, evOpen2], commits, "v1", "in1")
    check pC.candidates[0].classification == dcOpenDebt
    check pC.candidates[0].active == true

  test "I12/D3 determinism: same input -> same universeDigest; version change -> different":
    let commits = runs(["r1"])
    let evs = @[mkEvent("c1", "r1", 0, dcOpenDebt)]
    let a = projectEvents(evs, commits, "v1", "in1")
    let b = projectEvents(evs, commits, "v1", "in1")
    check a.universeDigest == b.universeDigest
    check universeDigestOf(a) == a.universeDigest
    let v2 = projectEvents(evs, commits, "v2", "in1")
    check v2.universeDigest != a.universeDigest   # interpretation varies by version

  test "digest sensitivity: event set / classification change alters digest":
    let commits = runs(["r1"])
    let evOpen = mkEvent("c1", "r1", 0, dcOpenDebt)
    let evRes  = mkEvent("c2", "r1", 1, dcResolved)
    let base = projectEvents(@[evOpen, evRes], commits, "v1", "in1")
    let changedClass = projectEvents(
      @[mkEvent("c1", "r1", 0, dcUnverified), evRes], commits, "v1", "in1")
    check changedClass.universeDigest != base.universeDigest
    let dropped = projectEvents(@[evOpen], commits, "v1", "in1")
    check dropped.universeDigest != base.universeDigest

  test "universeDigest = canonical serialization (stable fields)":
    let evs = @[mkEvent("c1", "r1", 0, dcOpenDebt), mkEvent("c2", "r1", 1, dcUnverified)]
    let p1 = projectEvents(evs, runs(["r1"]), "v1", "in1")
    let p2 = projectEvents(evs, runs(["r1"]), "v1", "in1")
    # identical inputs -> identical canonical form and orderedCommitRoot
    check $p1.candidates == $p2.candidates
    check p1.orderedCommitRoot == p2.orderedCommitRoot