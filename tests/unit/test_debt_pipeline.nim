## Contract tests — AuditPipeline orchestration (S3: debt_pipeline.nim).
##
## v8 invariant-first contract (executable spec). RED until debt_pipeline.nim exists
## (and its S1/S2 dependencies). The signatures used here ARE the S3 contract —
## implement exactly these:
##
##   type AuditResult* = object
##     run*: AuditRun
##     commit*: Option[AuditCommit]     # none until commit succeeded
##     decisionDigest*: ContentDigest
##     eventRoot*: ContentDigest
##     projection*: UniverseProjection
##
##   proc runAudit*(path: string; run: AuditRun; decisions: seq[PolicyDecision];
##                  events: seq[ClassificationEvent];
##                  projectionVersion, inputRoot: string): Result[AuditResult, string]
##     -- PREPARE/EVALUATE 없이 이미 만들어진 decisions/events를 받아
##        TRANSACTION(memory) -> VALIDATE(projection) -> COMMIT(S1.writeAuditLog).
##        실패 시 journal에 아무것도 쓰지 않는다 (I15).
##   proc replayAuditRun*(path: string; runId: AuditRunId;
##                        projectionVersion, inputRoot: string): Result[ReplayReport, string]
##     -- committed execution 재구성 (evaluator 재실행 아님). replay #1/#2는 커밋
##        closure와 비교, #3(projection)은 지정된 version으로 재계산.
##   type ReplayReport* = object
##     decisionDigestMatch*, eventRootMatch*: bool
##     projectionDigest*: string      # version-param 재계산된 universeDigest
##     eventDigest*: ContentDigest    # 커밋에 기록된 eventRoot (replay #1 비교용)
##     allMatch*: bool
##
## 불변식: I15(실패 시 invisible), I16(커밋만 canonical), I17(commit closure),
## I18(resolveCommitAtTime은 pipeline/CLI — projection은 시간 무지), I13/D1, D4.

import std/[unittest, os, strutils, options]
import core/types/debt_types
import core/debt/debt_events
import core/debt/debt_projection
import core/debt/debt_pipeline

# ---------------------------------------------------------------------------
# Fixtures (via S1/S2 contract — demonstrate end-to-end)
# ---------------------------------------------------------------------------

func dig(s: string): ContentDigest =
  var h = s
  while h.len < 64: h.add('0')
  ContentDigest("sha256:" & h[0 .. 63])

var tmpSeq = 0

proc freshLog(name: string): string =
  ## Unique temp journal path per call — leftover files from previous runs of
  ## this suite must not trip the I17 "run already committed" guard.
  inc tmpSeq
  let dir = getTempDir() / "ax_test_debt_pipeline"
  createDir(dir)
  dir / (name & "-" & $tmpSeq & "-" & $getCurrentProcessId() & ".journal")

proc mkEvent(cand, run: string; seq: uint64; cls: DebtClass): ClassificationEvent =
  ClassificationEvent(
    eventId: "ev-" & run & "-" & $seq, candidateId: cand, auditRunId: run,
    auditSequence: seq, decisionId: dig("dec-" & cand).string,
    classifierVersion: "cv1", ruleSetHash: "rs1", taxonomyVersion: "t1",
    result: cls, evidenceIds: @["e1"], parentEventId: "",
    recordedAt: "2026-01-01T00:00:00Z", repositorySnapshot: "snap1")

proc mkRun(runId: string; recordedAt = "2026-01-01T00:00:00Z"): AuditRun =
  AuditRun(
    auditInputId: AuditInputId(dig("ai-" & runId).string),
    auditRunId: AuditRunId(runId),
    policyDigest: dig("policy-" & runId),
    evidenceRoot: dig("evd-" & runId),
    eventRoot: dig("e-" & runId),
    resultRoot: dig("res-" & runId),
    status: arPrepared, recordedAt: recordedAt)

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

suite "debt_pipeline: orchestration contract":

  test "runAudit writes TX + commit; canonical history has exactly one commit":
    let log = freshLog("pipeline")
    let run = mkRun("audit1")
    let evs = @[mkEvent("c1", "audit1", 0, dcOpenDebt)]
    # produce decisions from the same input (D1 — deterministic content)
    let res = runAudit(log, run, @[], evs, "v1", "in1")
    check res.isOk
    let report = readCommitHistory(log)
    check report.health == rhClean
    check report.valid.len == 1
    check report.valid[0].auditRunId == AuditRunId("audit1")
    check report.valid[0].eventCount == 1
    check res.get.commit.isSome

  test "failed validation never touches the journal (I15)":
    let log = freshLog("fail")
    let run = mkRun("bad-run")
    # empty events with eventCount==0 while run declares eventRoot — trigger digest mismatch
    let res = runAudit(log, run, @[], @[], "v1", "in1")
    check res.isErr                       # VALIDATE rejects empty/ mismatch
    check not fileExists(log)             # nothing was written (or file absent)
    if fileExists(log):
      let report = readCommitHistory(log)
      check report.valid.len == 0

  test "replay reconstructs committed execution with matching digests (D4/I13)":
    let log = freshLog("replay")
    let decs: seq[PolicyDecision] = @[]  # decisions supplied by caller in this contract
    let evs = @[mkEvent("c1", "audit1", 0, dcOpenDebt),
                mkEvent("c2", "audit1", 1, dcUnverified)]
    let res = runAudit(log, mkRun("audit1"), decs, evs, "v1", "in1")
    check res.isOk
    let rp = replayAuditRun(log, AuditRunId("audit1"), "v1", "in1")
    check rp.isOk
    check rp.get.allMatch
    # event digest must equal the canonical eventRoot recorded in the commit
    let report = readCommitHistory(log)
    check rp.get.eventDigest == report.valid[0].eventRoot

  test "commit closure: second audit on same run rejected (I17)"  :
    let log = freshLog("closure")
    let evs = @[mkEvent("c1", "same-run", 0, dcOpenDebt)]
    check runAudit(log, mkRun("same-run"), @[], evs, "v1", "in1").isOk
    let second = runAudit(log, mkRun("same-run"), @[],
                          @[mkEvent("c1", "same-run", 1, dcOpenDebt)], "v1", "in1")
    check second.isErr                    # commit closure: run already committed
    let report = readCommitHistory(log)
    check report.valid.len == 1