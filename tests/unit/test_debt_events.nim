## Contract tests — Canonical Audit Log / Commit Stream (S1: debt_events.nim).
##
## v8 invariant-first contract (executable spec). RED until debt_events.nim exists.
## The signatures used here ARE the S1 contract — implement exactly these:
##
##   proc writeAuditLog*(path: string; run: AuditRun;
##                       decisions: seq[PolicyDecision];
##                       events: seq[ClassificationEvent]): Result[AuditCommit, string]
##       -- TX-BEGIN + DECISION* + EVENT* + TX-COMMIT(closure) 를 단일 writer로 기록;
##          commitSequence = last canonical commit + 1, parentCommitId 연결.
##   proc readCommitHistory*(path: string): JournalReadReport[AuditCommit]
##       -- canonical reader: 완전 valid prefix만 승격; 중간 손상 -> rhIntegrityFailure
##          (fail-close); EOF 불완전 frame만 rhRecoverableTail.
##   proc readCommitHistoryForensic*(path: string): JournalReadReport[AuditCommit]
##       -- forensic reader: skipped 수집 (문법 오류를 조용히 버리지 않음).
##   proc latestValidCommitAtOrBefore*(commits: openArray[AuditCommit]; ts: string): Option[AuditCommit]
##       -- I18: 시간 -> 커밋 선택. commit.recordedAt(ISO-8601) 사용.
##   func isRunCommitted*(commits: openArray[AuditCommit]; runId: AuditRunId): bool  -- I16
##
## 4대 불변식 (debt_types.nim const):
##   InvCanonicality / InvCommitValidity / InvRecovery / InvProjection.
## Writer semantics: single-writer. Decision: payload first, closure(commit) last, fsync.

import std/[unittest, os, strutils, options]
import core/types/debt_types
import core/debt/debt_events

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func dig(s: string): ContentDigest =
  ## Deterministic 64-char hex-ish digest ref for fixtures (not real sha256).
  var h = s
  while h.len < 64: h.add('0')
  ContentDigest("sha256:" & h[0 .. 63])

var tmpSeq = 0

proc freshLog(name: string): string =
  ## Unique temp journal path per call, so tests never collide — even across
  ## repeated runs of the suite (leftover files from earlier executions would
  ## otherwise trip the I17 "already committed" guard).
  inc tmpSeq
  let dir = getTempDir() / "ax_test_debt_events"
  createDir(dir)
  dir / (name & "-" & $tmpSeq & "-" & $getCurrentProcessId() & ".journal")

proc tmpLog(name: string): string =
  ## Alias kept for readability in mid-test corruption helpers.
  freshLog(name)

proc mkEvent(cand, run: string; seq: uint64; cls: DebtClass;
             recordedAt = "2026-01-01T00:00:00Z"): ClassificationEvent =
  ClassificationEvent(
    eventId: "ev-" & run & "-" & $seq,
    candidateId: cand,
    auditRunId: run,
    auditSequence: seq,
    decisionId: dig("dec-" & cand & "-" & $seq).string,
    classifierVersion: "cv1",
    ruleSetHash: "rs1",
    taxonomyVersion: "t1",
    result: cls,
    evidenceIds: @["e1"],
    parentEventId: "",
    recordedAt: recordedAt,
    repositorySnapshot: "snap1")

proc mkDecision(cand: string; verdict = ipvAcceptable): PolicyDecision =
  PolicyDecision(
    decisionId: dig("d-" & cand),
    candidateId: cand,
    evidenceRoot: dig("er-" & cand),
    policyDigest: dig("pd-" & cand),
    verdict: verdict,
    rationale: "rationale-" & cand)

proc mkRun(runId: string; recordedAt = "2026-01-01T00:00:00Z"): AuditRun =
  AuditRun(
    auditInputId: AuditInputId(dig("ai-" & runId).string),
    auditRunId: AuditRunId(runId),
    policyDigest: dig("policy-" & runId),
    evidenceRoot: dig("evd-" & runId),
    eventRoot: dig("e-" & runId),
    resultRoot: dig("res-" & runId),
    status: arPrepared,
    recordedAt: recordedAt)

# ---------------------------------------------------------------------------
# Tests — canonical write/read contract
# ---------------------------------------------------------------------------

suite "debt_events: canonical write/read contract":

  test "complete transaction promotes exactly one canonical commit (rhClean)":
    let path = freshLog("audit")
    let run = mkRun("run1")
    let evs = @[mkEvent("c1", "run1", 0, dcOpenDebt),
                mkEvent("c2", "run1", 1, dcUnverified)]
    let decs = @[mkDecision("c1"), mkDecision("c2")]
    let res = writeAuditLog(path, run, decs, evs)
    check res.isOk
    let report = readCommitHistory(path)
    check report.health == rhClean
    check report.valid.len == 1
    let c = report.valid[0]
    check c.auditRunId == AuditRunId("run1")
    check c.commitSequence == 1
    check c.firstSequence == 0
    check c.lastSequence == 1
    check c.eventCount == 2
    check c.parentCommitId == ContentDigest("")
    check c.recordedAt == "2026-01-01T00:00:00Z"
    # closure: deterministic, non-empty digests
    check c.eventRoot != ContentDigest("")
    check c.decisionDigest != ContentDigest("")
    check c.commitId != ContentDigest("")

  test "commit sequence = last valid + 1, parent chain (D4)":
    let log = tmpLog("seq.journal")
    let decs = @[mkDecision("c1")]
    let ev1 = @[mkEvent("c1", "a", 0, dcOpenDebt)]
    let ev2 = @[mkEvent("c1", "b", 0, dcResolved)]
    discard writeAuditLog(log, mkRun("a"), decs, ev1)
    discard writeAuditLog(log, mkRun("b"), decs, ev2)
    let report = readCommitHistory(log)
    check report.health == rhClean
    check report.valid.len == 2
    check report.valid[0].commitSequence == 1
    check report.valid[1].commitSequence == 2
    check report.valid[1].parentCommitId == report.valid[0].commitId
    check report.valid[1].firstSequence == 0
    check report.valid[1].lastSequence == 0

  test "rewriting identical logical history yields identical chain (D4 determinism)":
    let log1 = tmpLog("d4a.journal")
    let log2 = tmpLog("d4b.journal")
    let decs = @[mkDecision("c1")]
    let evs = @[mkEvent("c1", "a", 0, dcOpenDebt)]
    discard writeAuditLog(log1, mkRun("a"), decs, evs)
    discard writeAuditLog(log2, mkRun("a"), decs, evs)
    let r1 = readCommitHistory(log1)
    let r2 = readCommitHistory(log2)
    check r1.valid[0].commitId == r2.valid[0].commitId
    check r1.valid[0].eventRoot == r2.valid[0].eventRoot
    check r1.valid[0].decisionDigest == r2.valid[0].decisionDigest

  test "incomplete frame at physical EOF -> recoverableTail (InvRecovery)":
    let log = tmpLog("tail.journal")
    discard writeAuditLog(log, mkRun("a"), @[mkDecision("c1")],
                          @[mkEvent("c1", "a", 0, dcOpenDebt)])
    # manually append a torn half-frame (no newline) — simulates crash mid-append
    log.writeFile(log.readFile & "TXPARTIAL:1:2:3")
    let report = readCommitHistory(log)
    check report.health == rhRecoverableTail
    check report.valid.len == 1          # only the valid prefix promoted
    check report.valid[0].auditRunId == AuditRunId("a")

  test "middle corruption after valid prefix -> integrityFailure (fail-closed)":
    let log = tmpLog("corrupt.journal")
    discard writeAuditLog(log, mkRun("a"), @[mkDecision("c1")],
                  @[mkEvent("c1", "a", 0, dcOpenDebt)])
    log.writeFile(log.readFile & "GARBAGE-NOT-A-FRAME\n")
    discard writeAuditLog(log, mkRun("b"), @[mkDecision("c2")],
                  @[mkEvent("c2", "b", 0, dcOpenDebt)])
    let report = readCommitHistory(log)
    check report.health == rhIntegrityFailure   # middle corruption: fail-closed
    check report.valid.len == 1                 # only prefix promoted

  test "latestValidCommitAtOrBefore resolves time -> commit (I18)":
    let log = tmpLog("time.journal")
    discard writeAuditLog(log, mkRun("a", "2026-01-01T00:00:00Z"),
                          @[mkDecision("c1")],
                          @[mkEvent("c1", "a", 0, dcOpenDebt, "2026-01-01T00:00:00Z")])
    discard writeAuditLog(log, mkRun("b", "2026-02-01T00:00:00Z"),
                          @[mkDecision("c1")],
                          @[mkEvent("c1", "b", 0, dcResolved, "2026-02-01T00:00:00Z")])
    let report = readCommitHistory(log)
    check report.valid.len == 2
    check latestValidCommitAtOrBefore(report.valid, "2026-01-15T00:00:00Z").isSome
    check latestValidCommitAtOrBefore(report.valid, "2026-01-15T00:00:00Z").get.auditRunId == AuditRunId("a")
    check latestValidCommitAtOrBefore(report.valid, "2026-03-01T00:00:00Z").get.auditRunId == AuditRunId("b")
    check latestValidCommitAtOrBefore(report.valid, "2025-12-01T00:00:00Z").isNone

  test "isRunCommitted (I16)":
    let log = tmpLog("committed.journal")
    discard writeAuditLog(log, mkRun("a"), @[mkDecision("c1")],
                          @[mkEvent("c1", "a", 0, dcOpenDebt)])
    let report = readCommitHistory(log)
    check isRunCommitted(report.valid, AuditRunId("a"))
    check not isRunCommitted(report.valid, AuditRunId("zzz"))

  test "forensic reader reports skipped lines instead of silently dropping":
    let log = tmpLog("forensic.journal")
    discard writeAuditLog(log, mkRun("a"), @[mkDecision("c1")],
                          @[mkEvent("c1", "a", 0, dcOpenDebt)])
    log.writeFile(log.readFile & "BADLINE\n")
    let report = readCommitHistoryForensic(log)
    check report.valid.len >= 1
    check report.skipped.len >= 1
    check report.skipped[0].reason.len > 0