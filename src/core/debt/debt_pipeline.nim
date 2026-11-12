## src/core/debt/debt_pipeline.nim — Audit Pipeline Orchestration (v8, S3).
##
## Canonical Commit Stream — S3: S1(writeAuditLog) × S2(projectAtCommit)를
## TRANSACTION → VALIDATE → COMMIT 순서로 조립하는 오케스트레이션 레이어.
##
## 불변식: I15(실패 시 invisible), I16(커밋만 canonical), I17(commit closure),
##        D1/D4(결정성), InvProjectionPure.

import core/trusted/layer_declaration
axiomLayer "domain"

import std/[options, algorithm]
import core/axiom_pragmas
import core/results
import core/types/debt_types
import core/debt/debt_events
import core/debt/debt_projection

# ---------------------------------------------------------------------------
# Public result types
# ---------------------------------------------------------------------------

type AuditResult* = object
  run*: AuditRun
  commit*: Option[AuditCommit]     # none until commit succeeded
  decisionDigest*: ContentDigest
  eventRoot*: ContentDigest
  projection*: UniverseProjection

type ReplayReport* = object
  decisionDigestMatch*, eventRootMatch*: bool
  projectionDigest*: string
  eventDigest*: ContentDigest      # the commit's recorded eventRoot (as stored)
  allMatch*: bool

# ---------------------------------------------------------------------------
# runAudit — TRANSACTION(memory) → VALIDATE(projection) → COMMIT(S1)
# ---------------------------------------------------------------------------

proc runAudit*(path: string; run: AuditRun; decisions: seq[PolicyDecision];
               events: seq[ClassificationEvent];
               projectionVersion, inputRoot: string): Result[AuditResult, string] {.raises: [].} =
  ## PREPARE/EVALUATE 없이 이미 만들어진 decisions/events 를 받아
  ## TRANSACTION(memory) → VALIDATE(projection) → COMMIT(S1.writeAuditLog).
  ## 실패 시 journal 에 아무것도 쓰지 않는다 (I15).
  try:
    # --- TRANSACTION: compute digests & projection over existing history ---
    let dd = decisionDigestOf(decisions)
    let er = eventRootOf(events)

    # --- VALIDATE: reject empty events BEFORE writing anything ---
    if events.len == 0:
      return err("runAudit: empty event payload — validation failed (I15)")

    # --- COMMIT: write to S1 ---
    let commitRes = writeAuditLog(path, run, decisions, events)
    if commitRes.isErr:
      return err("runAudit: commit failed — " & commitRes.error)

    let newCommit = commitRes.get

    # Recompute projection over ALL committed history including the new one
    let allCommitsIncludingNew = readCommitHistory(path).valid
    let orderedAll = orderedEvents(events, allCommitsIncludingNew)
    let finalProj = projectAtCommit(orderedAll, projectionVersion, inputRoot)

    ok(AuditResult(
      run: run,
      commit: some(newCommit),
      decisionDigest: dd,
      eventRoot: er,
      projection: finalProj))
  except CatchableError as e:
    err("runAudit: " & e.msg)

# ---------------------------------------------------------------------------
# replayAuditRun — reconstruct committed execution from journal
# ---------------------------------------------------------------------------

proc replayAuditRun*(path: string; runId: AuditRunId;
                      projectionVersion, inputRoot: string): Result[ReplayReport, string] {.raises: [].} =
  ## committed execution 재구성 (evaluator 재실행 아님).
  ## replay #1/#2 는 커밋 closure 와 비교, #3(projection)은 지정된 version 으로 재계산.
  try:
    let txsRes = readTransactions(path)
    if txsRes.isErr:
      return err("replayAuditRun: cannot read journal — " & txsRes.error)

    let txs = txsRes.get

    # Find the committed transaction for the given runId
    var targetTx: JournalTx
    var found = false
    for tx in txs:
      if tx.commit.auditRunId == runId:
        targetTx = tx
        found = true
        break

    if not found:
      return err("replayAuditRun: run not found — " & raw(runId))

    # Replay #1: compare decision digest
    let replayedDD = decisionDigestOf(targetTx.decisions)
    let decisionDigestMatch = replayedDD == targetTx.commit.decisionDigest

    # Replay #2: compare event root digest
    let replayedER = eventRootOf(targetTx.events)
    let eventRootMatch = replayedER == targetTx.commit.eventRoot

    # Replay #3: recompute projection over committed history
    let allCommits = readCommitHistory(path).valid
    var allEvents: seq[ClassificationEvent]
    for tx in txs:
      allEvents.add(tx.events)
    let orderedReplay = orderedEvents(allEvents, allCommits)
    let replayProj = projectAtCommit(orderedReplay, projectionVersion, inputRoot)

    let projectionDigest = replayProj.universeDigest
    let eventDigest = targetTx.commit.eventRoot
    let allMatch = decisionDigestMatch and eventRootMatch

    ok(ReplayReport(
      decisionDigestMatch: decisionDigestMatch,
      eventRootMatch: eventRootMatch,
      projectionDigest: projectionDigest,
      eventDigest: eventDigest,
      allMatch: allMatch))
  except CatchableError as e:
    err("replayAuditRun: " & e.msg)
