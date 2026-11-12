{.push raises: [].}
## src/core/debt/debt_events.nim — Canonical Commit Stream (v8, S1).
##
## Append-only audit journal with a strict manifest: TX-BEGIN / DECISION* /
## EVENT* / TX-COMMIT frames, one JSON object per physical line.  The
## TX-COMMIT frame carries the canonical closure (AuditCommit) — the single
## promotion authority for the canonical history.
##
## Writers:
##   writeAuditLog — single-writer append; commitSequence = last canonical
##                   commit's sequence + 1; parentCommitId links the chain.
## Readers:
##   readCommitHistory          — canonical reader: maximal valid committed
##                                prefix; mid-file corruption after a valid
##                                prefix => rhIntegrityFailure (fail-closed);
##                                a torn frame at physical EOF =>
##                                rhRecoverableTail (prefix promoted, tail
##                                dropped).
##   readCommitHistoryForensic — same walk, but syntax errors are recorded
##                                into `skipped` (lineNo + reason) instead of
##                                failing closed.
##   readTransactions           — valid transaction payloads (for S3 replay).
## Queries:
##   latestValidCommitAtOrBefore — I18: time -> commit selection.
##   isRunCommitted               — I16: run-level committed visibility.
##
## Invariants (debt_types.nim): InvCanonicality, InvCommitValidity,
## InvRecovery, D4 (same logical history -> same commit chain).

import std/[json, os, strutils, options, sequtils, algorithm]
import core/results
export results
import core/trusted/layer_declaration
axiomLayer "domain"
import core/axiom_pragmas
import core/types/debt_types

# ---------------------------------------------------------------------------
# Journal frame grammar
# ---------------------------------------------------------------------------

type
  FrameTag* = enum
    fgBegin    ## "B"
    fgDecision ## "D"
    fgEvent    ## "E"
    fgCommit   ## "C"

  JournalTx* = object
    ## One complete committed transaction with its payload (S3 replay input).
    commit*: AuditCommit
    decisions*: seq[PolicyDecision]
    events*: seq[ClassificationEvent]

proc frameTagToStr(t: FrameTag): string {.raises: [].} =
  case t
  of fgBegin:    "B"
  of fgDecision: "D"
  of fgEvent:    "E"
  of fgCommit:   "C"

proc frameTagFromStr(s: string): Option[FrameTag] {.axiomDecision(id = "DECISION-0645", reason = "Parse FrameTag enum from its single-character wire representation for journal frame dispatch", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  case s
  of "B": some(fgBegin)
  of "D": some(fgDecision)
  of "E": some(fgEvent)
  of "C": some(fgCommit)
  else: none(FrameTag)

# ---------------------------------------------------------------------------
# PolicyDecision / DebtClass round-trip (canonical string forms)
# ---------------------------------------------------------------------------

func debtClassFromStr(s: string): Option[DebtClass] {.raises: [], axiomDecision(id = "DECISION-0646", reason = "Parse DebtClass enum from its canonical string form for frame deserialization", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  case s
  of "OPEN_DEBT":    some(dcOpenDebt)
  of "UNVERIFIED":   some(dcUnverified)
  of "STALE":        some(dcStale)
  of "RESOLVED":     some(dcResolved)
  of "QUIRK":        some(dcQuirk)
  of "BUDGET_DRIFT": some(dcBudgetDrift)
  else: none(DebtClass)

proc verdictFromStr(s: string): Option[IntegrityPolicyVerdict] {.raises: [], axiomDecision(id = "DECISION-0647", reason = "Parse IntegrityPolicyVerdict enum from its canonical string form for frame deserialization", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  case s
  of "ACCEPT":      some(ipvAcceptable)
  of "WARN":        some(ipvWarning)
  of "VIOLATION":   some(ipvViolation)
  of "UNVERIFIED":  some(ipvUnverified)
  else: none(IntegrityPolicyVerdict)

func eventCanonical(e: ClassificationEvent): string {.raises: [].} =
  ## Fixed-order canonical predicate for one event (digest input, not wire).
  e.eventId & "\x1e" & e.candidateId & "\x1e" & $e.auditSequence & "\x1e" &
    e.decisionId & "\x1e" & e.classifierVersion & "\x1e" & e.ruleSetHash & "\x1e" &
    e.taxonomyVersion & "\x1e" & debtClassToStr(e.result) & "\x1e" &
    join(e.evidenceIds, ",") & "\x1e" & e.parentEventId & "\x1e" &
    e.recordedAt & "\x1e" & e.repositorySnapshot

func decisionCanonical(d: PolicyDecision): string {.raises: [].} =
  d.candidateId & "\x1e" & raw(d.evidenceRoot) & "\x1e" & raw(d.policyDigest) & "\x1e" &
    integrityPolicyVerdictToStr(d.verdict) & "\x1e" & d.rationale

func sortedEvents(events: openArray[ClassificationEvent]): seq[ClassificationEvent] {.raises: [].} =
  ## Canonical event order: (auditSequence, eventId).  Timestamps are NOT an
  ## ordering key (classification order is a history property, not wall time).
  result = @events
  result.sort(proc(a, b: ClassificationEvent): int =
    if a.auditSequence < b.auditSequence: -1
    elif a.auditSequence > b.auditSequence: 1
    else: cmp(a.eventId, b.eventId))

func sortedDecisions(decisions: openArray[PolicyDecision]): seq[PolicyDecision] {.raises: [].} =
  result = @decisions
  result.sort(proc(a, b: PolicyDecision): int =
    let c = cmp(a.candidateId, b.candidateId)
    if c != 0: c else: cmp(raw(a.decisionId), raw(b.decisionId)))

func eventRootOf*(events: openArray[ClassificationEvent]): ContentDigest {.raises: [].} =
  ## D2: H(canonical(committed event set)) — content-address of the events.
  ContentDigest(sha256Ref("EventRoot:", join(mapIt(sortedEvents(events),
    eventCanonical(it)), "\n")))

func decisionDigestOf*(decisions: openArray[PolicyDecision]): ContentDigest {.raises: [].} =
  ## evaluator(PolicyDecision[]) output root — deterministic (D1).
  ContentDigest(sha256Ref("DecisionDigest:", join(mapIt(sortedDecisions(decisions),
    decisionCanonical(it)), "\n")))# ---------------------------------------------------------------------------
# Frame serialization (wire form, one JSON object per line)
# ---------------------------------------------------------------------------

proc beginFrameToJson(run: AuditRun): JsonNode {.raises: [].} =
  %*{
    "t": frameTagToStr(fgBegin),
    "run": raw(run.auditRunId),
    "input": raw(run.auditInputId),
    "pd": raw(run.policyDigest),
    "er": raw(run.evidenceRoot),
    "rr": raw(run.resultRoot),
    "ts": run.recordedAt
  }

proc decisionToJson(d: PolicyDecision): JsonNode {.raises: [].} =
  %*{
    "t": frameTagToStr(fgDecision),
    "di": raw(d.decisionId),
    "c": d.candidateId,
    "e": raw(d.evidenceRoot),
    "pd": raw(d.policyDigest),
    "v": integrityPolicyVerdictToStr(d.verdict),
    "r": d.rationale
  }

proc eventToJson(e: ClassificationEvent): JsonNode {.raises: [].} =
  %*{
    "t": frameTagToStr(fgEvent),
    "id": e.eventId,
    "c": e.candidateId,
    "run": e.auditRunId,
    "seq": $e.auditSequence,
    "di": e.decisionId,
    "cv": e.classifierVersion,
    "rs": e.ruleSetHash,
    "tv": e.taxonomyVersion,
    "res": debtClassToStr(e.result),
    "ev": e.evidenceIds,
    "pe": e.parentEventId,
    "ts": e.recordedAt,
    "snap": e.repositorySnapshot
  }

proc provenanceRootOf(run: AuditRun): ContentDigest {.raises: [].} =
  ## Deterministic provenance digest over the run's input identity.  The run
  ## identity itself is content-addressed (AuditInputId), so this binds the
  ## closure to the immutable input manifest (I9/I10).
  ContentDigest(sha256Ref("ProvenanceRoot:",
    raw(run.auditInputId) & "\x1e" & raw(run.policyDigest) & "\x1e" &
      raw(run.evidenceRoot) & "\x1e" & raw(run.resultRoot) & "\x1e" &
      raw(run.auditRunId)))

proc commitClosureCanonical(seqNo: uint64; runId: AuditRunId; firstSeq, lastSeq,
                            count: uint64; eventRoot, decisionDigest,
                            provenanceRoot: ContentDigest): string =
  ## Canonical closure predicate — EXCLUDES commitId and recordedAt
  ## (recordedAt is execution metadata; inclusion would break D4).
  $seqNo & "\x1e" & raw(runId) & "\x1e" & $firstSeq & "\x1e" & $lastSeq & "\x1e" &
    $count & "\x1e" & raw(eventRoot) & "\x1e" & raw(decisionDigest) & "\x1e" &
    raw(provenanceRoot)

proc commitToJson(c: AuditCommit; parentId: string): JsonNode {.raises: [].} =
  %*{
    "t": frameTagToStr(fgCommit),
    "seq": $c.commitSequence,
    "run": raw(c.auditRunId),
    "f": $c.firstSequence,
    "l": $c.lastSequence,
    "n": $c.eventCount,
    "er": raw(c.eventRoot),
    "dd": raw(c.decisionDigest),
    "pr": raw(c.provenanceRoot),
    "pid": parentId,
    "ts": c.recordedAt,
    "id": raw(c.commitId)
  }# ---------------------------------------------------------------------------
# Frame parsing (wire -> types)
# ---------------------------------------------------------------------------

type TxAccum = object
  ## In-flight transaction accumulator (single-writer means at most one open
  ## transaction at a time; a second BEGIN while active is a manifest error).
  active: bool
  runId: AuditRunId
  beginLine: int
  decisions: seq[PolicyDecision]
  events: seq[ClassificationEvent]

proc parseFrameLine(line: string): Result[(FrameTag, JsonNode), string] {.axiomDecision(id = "DECISION-0648", reason = "Parse a single journal frame line into its tag and JSON payload; fail-closed on malformed JSON", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  try:
    let node = parseJson(line)
    let tag = frameTagFromStr(node["t"].getStr())
    if tag.isNone:
      return err("unknown frame tag")
    ok((tag.get, node))
  except CatchableError as e:
    err("frame parse error: " & e.msg)

proc parseDecisionFrame(node: JsonNode): Result[PolicyDecision, string] {.axiomDecision(id = "DECISION-0649", reason = "Parse a DECISION frame JSON node into a PolicyDecision; fail-closed on unknown verdict", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  try:
    let verdict = verdictFromStr(node["v"].getStr())
    if verdict.isNone:
      return err("decision frame: unknown verdict")
    ok(PolicyDecision(
      decisionId: ContentDigest(node["di"].getStr()),
      candidateId: node["c"].getStr(),
      evidenceRoot: ContentDigest(node["e"].getStr()),
      policyDigest: ContentDigest(node["pd"].getStr()),
      verdict: verdict.get,
      rationale: node["r"].getStr()))
  except CatchableError as e:
    err("decision frame: " & e.msg)

proc parseEventFrame(node: JsonNode): Result[ClassificationEvent, string] {.axiomDecision(id = "DECISION-0650", reason = "Parse an EVENT frame JSON node into a ClassificationEvent; fail-closed on unknown class", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  try:
    let cls = debtClassFromStr(node["res"].getStr())
    if cls.isNone:
      return err("event frame: unknown class")
    ok(ClassificationEvent(
      eventId: node["id"].getStr(),
      candidateId: node["c"].getStr(),
      auditRunId: node["run"].getStr(),
      auditSequence: node["seq"].getStr().parseUInt,
      decisionId: node["di"].getStr(),
      classifierVersion: node["cv"].getStr(),
      ruleSetHash: node["rs"].getStr(),
      taxonomyVersion: node["tv"].getStr(),
      result: cls.get,
      evidenceIds: node["ev"].getElems.mapIt(it.getStr()),
      parentEventId: node["pe"].getStr(),
      recordedAt: node["ts"].getStr(),
      repositorySnapshot: node["snap"].getStr()))
  except CatchableError as e:
    err("event frame: " & e.msg)

proc parseCommitFrame(node: JsonNode): Result[tuple[seqNo, firstSeq, lastSeq, count: uint64; runId: AuditRunId; eventRoot, decisionDigest, provenanceRoot, parentId: string; recordedAt, id: string], string] {.axiomDecision(id = "DECISION-0651", reason = "Parse a COMMIT frame JSON node into its closure tuple; fail-closed on missing fields", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  try:
    ok((node["seq"].getStr().parseUInt,
        node["f"].getStr().parseUInt,
        node["l"].getStr().parseUInt,
        node["n"].getStr().parseUInt,
        AuditRunId(node["run"].getStr()),
        node["er"].getStr(),
        node["dd"].getStr(),
        node["pr"].getStr(),
        node["pid"].getStr(),
        node["ts"].getStr(),
        node["id"].getStr()))
  except CatchableError as e:
    err("commit frame: " & e.msg)

# ---------------------------------------------------------------------------
# Journal walker (shared by canonical reader, forensic reader and replay)
# ---------------------------------------------------------------------------

type
  JournalHealth = enum   # internal; maps 1:1 onto ReadHealth
    jhClean, jhRecoverableTail, jhMalformedRecord, jhIntegrityFailure

proc healthToReadHealth(h: JournalHealth): ReadHealth =
  case h
  of jhClean:               rhClean
  of jhRecoverableTail:     rhRecoverableTail
  of jhMalformedRecord:     rhMalformedRecord
  of jhIntegrityFailure:    rhIntegrityFailure

proc validateClosure(cf: tuple[seqNo, firstSeq, lastSeq, count: uint64;
                               runId: AuditRunId; eventRoot, decisionDigest,
                               provenanceRoot, parentId: string;
                               recordedAt, id: string];
                     tx: TxAccum;
                     commits: openArray[AuditCommit];
                     lineNo: int): Result[(AuditCommit, string), string] =
  ## InvCommitValidity: transaction complete + closure validates +
  ## parent/sequence relation matches the preceding canonical commit.
  let prevSeq = if commits.len == 0: 0'u64 else: commits[^1].commitSequence
  let prevId = if commits.len == 0: "" else: raw(commits[^1].commitId)
  if cf.seqNo != prevSeq + 1:
    return err("closure: sequence " & $cf.seqNo & " != last+1 (" & $prevSeq & ")")
  if cf.parentId != prevId:
    return err("closure: parentCommitId mismatch on line " & $lineNo)
  if cf.runId != tx.runId:
    return err("closure: runId mismatch on line " & $lineNo)
  if cf.count != uint64(tx.events.len):
    return err("closure: eventCount " & $cf.count & " != payload " & $tx.events.len)
  if tx.events.len == 0:
    return err("closure: empty event payload on line " & $lineNo)
  # canonical eventRoot / decisionDigest must match the payload (D2/D1)
  if cf.eventRoot != raw(eventRootOf(tx.events)):
    return err("closure: eventRoot mismatch on line " & $lineNo)
  if cf.decisionDigest != raw(decisionDigestOf(tx.decisions)):
    return err("closure: decisionDigest mismatch on line " & $lineNo)
  var firstSeq = high(uint64)
  var lastSeq = 0'u64
  for e in tx.events:
    if e.auditSequence < firstSeq: firstSeq = e.auditSequence
    if e.auditSequence > lastSeq:  lastSeq = e.auditSequence
  if cf.firstSeq != firstSeq:
    return err("closure: firstSequence mismatch on line " & $lineNo)
  if cf.lastSeq != lastSeq:
    return err("closure: lastSequence mismatch on line " & $lineNo)
  let c = AuditCommit(
    commitSequence: cf.seqNo,
    auditRunId: cf.runId,
    firstSequence: firstSeq,
    lastSequence: lastSeq,
    eventCount: uint64(tx.events.len),
    eventRoot: ContentDigest(cf.eventRoot),
    decisionDigest: ContentDigest(cf.decisionDigest),
    provenanceRoot: ContentDigest(cf.provenanceRoot),
    parentCommitId: (if prevId == "": ContentDigest("") else: ContentDigest(prevId)),
    recordedAt: cf.recordedAt)
  let expectedId = sha256Ref("AuditCommit:",
    commitClosureCanonical(cf.seqNo, cf.runId, firstSeq, lastSeq,
      uint64(tx.events.len), ContentDigest(cf.eventRoot),
      ContentDigest(cf.decisionDigest), ContentDigest(cf.provenanceRoot)))
  if cf.id != expectedId:
    return err("closure: commitId mismatch on line " & $lineNo)
  var c2 = c
  c2.commitId = ContentDigest(expectedId)
  ok((c2, cf.parentId))

proc walkLines(text: string; forensic: bool): tuple[
    commits: seq[AuditCommit], txs: seq[JournalTx],
    skips: seq[JournalSkip], health: JournalHealth] {.raises: [].} =
  ## Core scan over journal text.  canonical (forensic=false): fail-closed on
  ## the FIRST anomaly (valid = maximal committed prefix).  forensic: anomalies
  ## land in `skipped` with line numbers and walking continues.
  var health = jhClean
  var tx: TxAccum
  if text.len == 0:
    return (@[], @[], @[], health)
  let raw = text.split('\n')
  let endsWithNewline = text.endsWith("\n")
  let lines = if endsWithNewline and raw.len > 0: raw[0 .. ^2] else: raw
  for idx, line in lines:
    let lineNo = idx + 1
    if idx == lines.high and not endsWithNewline:
      # an unterminated physical frame at EOF — recoverable tail (InvRecovery)
      if forensic:
        result.skips.add(JournalSkip(lineNo: lineNo,
          reason: "torn frame at physical EOF (incomplete transaction)",
          kind: rhRecoverableTail))
      if health == jhClean: health = jhRecoverableTail
      break
    if line.len == 0:
      if forensic:
        result.skips.add(JournalSkip(lineNo: lineNo, reason: "empty line",
          kind: rhMalformedRecord))
        health = jhMalformedRecord
        continue
      else:
        health = jhIntegrityFailure
        break
    let fr = parseFrameLine(line)
    if fr.isErr:
      if not forensic:
        health = jhIntegrityFailure
        break
      result.skips.add(JournalSkip(lineNo: lineNo, reason: fr.error,
        kind: rhMalformedRecord))
      health = jhMalformedRecord
      continue
    let (tag, node) = fr.get
    try:
      case tag
      of fgBegin:
        if tx.active:
          if not forensic:
            health = jhIntegrityFailure
            break
          result.skips.add(JournalSkip(lineNo: lineNo,
            reason: "nested TX-BEGIN while transaction open", kind: rhMalformedRecord))
          health = jhMalformedRecord
          continue
        tx = TxAccum(active: true, runId: AuditRunId(node["run"].getStr()),
                     beginLine: lineNo, decisions: @[], events: @[])
      of fgDecision:
        if not tx.active:
          if not forensic:
            health = jhIntegrityFailure
            break
          result.skips.add(JournalSkip(lineNo: lineNo,
            reason: "DECISION outside TX", kind: rhMalformedRecord))
          health = jhMalformedRecord
          continue
        let d = parseDecisionFrame(node)
        if d.isErr:
          if not forensic:
            health = jhIntegrityFailure
            break
          result.skips.add(JournalSkip(lineNo: lineNo, reason: d.error,
            kind: rhMalformedRecord))
          health = jhMalformedRecord
          continue
        tx.decisions.add(d.get)
      of fgEvent:
        if not tx.active:
          if not forensic:
            health = jhIntegrityFailure
            break
          result.skips.add(JournalSkip(lineNo: lineNo,
            reason: "EVENT outside TX", kind: rhMalformedRecord))
          health = jhMalformedRecord
          continue
        let e = parseEventFrame(node)
        if e.isErr:
          if not forensic:
            health = jhIntegrityFailure
            break
          result.skips.add(JournalSkip(lineNo: lineNo, reason: e.error,
            kind: rhMalformedRecord))
          health = jhMalformedRecord
          continue
        tx.events.add(e.get)
      of fgCommit:
        if not tx.active:
          if not forensic:
            health = jhIntegrityFailure
            break
          result.skips.add(JournalSkip(lineNo: lineNo,
            reason: "COMMIT outside TX", kind: rhMalformedRecord))
          health = jhMalformedRecord
          continue
        let cf = parseCommitFrame(node)
        if cf.isErr:
          if not forensic:
            health = jhIntegrityFailure
            break
          result.skips.add(JournalSkip(lineNo: lineNo, reason: cf.error,
            kind: rhMalformedRecord))
          health = jhMalformedRecord
          continue
        let v = validateClosure(cf.get, tx, result.commits, lineNo)
        if v.isErr:
          if not forensic:
            health = jhIntegrityFailure
            break
          result.skips.add(JournalSkip(lineNo: lineNo, reason: v.error,
            kind: rhIntegrityFailure))
          health = jhMalformedRecord
          continue
        result.commits.add(v.get[0])
        result.txs.add(JournalTx(commit: v.get[0], decisions: tx.decisions,
                                 events: tx.events))
        tx = TxAccum()   # close
    except CatchableError:
      if not forensic:
        health = jhIntegrityFailure
        break
      result.skips.add(JournalSkip(lineNo: lineNo, reason: "internal parse error",
        kind: rhMalformedRecord))
      health = jhMalformedRecord
      continue
  result.health = health

proc readCommitHistory*(path: string): JournalReadReport[AuditCommit] {.raises: [].} =
  ## Canonical reader: maximal valid committed prefix only.  Mid-file anomaly
  ## after a valid prefix => rhIntegrityFailure (fail-closed); a torn frame at
  ## physical EOF => rhRecoverableTail (prefix promoted).
  result = JournalReadReport[AuditCommit](valid: @[], skipped: @[], health: rhClean)
  var text: string
  try:
    if not fileExists(path):
      return
    text = readFile(path)
  except CatchableError as e:
    result.skipped.add(JournalSkip(lineNo: 0, reason: "unreadable journal: " & e.msg,
      kind: rhIntegrityFailure))
    result.health = rhIntegrityFailure
    return
  let w = walkLines(text, forensic = false)
  result.valid = w.commits
  result.skipped = @[]
  result.health = healthToReadHealth(w.health)

proc readCommitHistoryForensic*(path: string): JournalReadReport[AuditCommit] {.raises: [].} =
  ## Forensic reader: same walk, but anomalies are reported in `skipped`
  ## (lineNo + reason) instead of failing closed.  Nothing is silently dropped.
  result = JournalReadReport[AuditCommit](valid: @[], skipped: @[], health: rhClean)
  var text: string
  try:
    if not fileExists(path):
      return
    text = readFile(path)
  except CatchableError as e:
    result.skipped = @[JournalSkip(lineNo: 0, reason: "unreadable journal: " & e.msg,
      kind: rhIntegrityFailure)]
    result.health = rhIntegrityFailure
    return
  let w = walkLines(text, forensic = true)
  result.valid = w.commits
  result.skipped = w.skips
  result.health = healthToReadHealth(w.health)

proc readTransactions*(path: string): Result[seq[JournalTx], string] {.raises: [], axiomDecision(id = "DECISION-0652", reason = "Read committed transaction payloads from the audit journal for S3 replay", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  ## Valid committed transaction payloads (events + decisions + commit), for
  ## S3 replay/reconstruct.  Invalid transactions are skipped and reported
  ## through the same walker (nothing is silently dropped).
  try:
    if not fileExists(path):
      return ok(newSeq[JournalTx]())
    let w = walkLines(readFile(path), forensic = true)
    ok(w.txs)
  except CatchableError as e:
    err("readTransactions: " & e.msg)# ---------------------------------------------------------------------------
# Writer — single-writer append with canonical closure
# ---------------------------------------------------------------------------

proc lastValidCommitFrom(path: string): Option[AuditCommit] {.raises: [], axiomDecision(id = "DECISION-0653", reason = "Find the last canonical commit on disk for parent/sequence linkage in append mode", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  ## Last canonical commit currently on disk (for parent/sequence linkage).
  if not fileExists(path):
    return none(AuditCommit)
  let report = readCommitHistory(path)
  if report.valid.len == 0:
    return none(AuditCommit)
  some(report.valid[^1])

func isRunCommitted*(commits: openArray[AuditCommit];
                     runId: AuditRunId): bool {.raises: [].} =
  ## I16: a run is committed iff its canonical commit exists in the history.
  for c in commits:
    if c.auditRunId == runId and raw(c.commitId) != "":
      return true
  false

proc flushFsync(path: string): void {.raises: [IOError, OSError].} =
  ## Best-effort durability: reopen and flush the journal file so the frames
  ## are observable by immediate readers (same-process tests).
  var f: File
  if f.open(path, fmReadWrite):
    try:
      f.flushFile()
    finally:
      f.close()

proc writeAuditLog*(path: string; run: AuditRun; decisions: seq[PolicyDecision];
                    events: seq[ClassificationEvent]): Result[AuditCommit, string] {.raises: [].} =
  ## Single-writer append: payload frames first, closure (TX-COMMIT) last,
  ## one write syscall, fsync.  commitSequence = last canonical commit + 1;
  ## parentCommitId links the chain.  If a run already has a canonical commit
  ## the append is rejected (I16/I17 — AuditRun.status is metadata only).
  if events.len == 0:
    return err("writeAuditLog: empty event payload")
  var last: Option[AuditCommit]
  var prevId = ""
  try:
    last = lastValidCommitFrom(path)
    if last.isSome and isRunCommitted(@[last.get], run.auditRunId):
      return err("writeAuditLog: run already committed (I17): " & raw(run.auditRunId))
    let seqNo = (if last.isNone: 1'u64 else: last.get.commitSequence + 1)
    if last.isSome:
      prevId = raw(last.get.commitId)
    let sorted = sortedEvents(events)
    var firstSeq = high(uint64)
    var lastSeq = 0'u64
    for e in sorted:
      if e.auditSequence < firstSeq: firstSeq = e.auditSequence
      if e.auditSequence > lastSeq:  lastSeq = e.auditSequence
    let eventRoot = eventRootOf(events)
    let decisionDigest = decisionDigestOf(decisions)
    let provRoot = provenanceRootOf(run)
    let commitId = sha256Ref("AuditCommit:",
      commitClosureCanonical(seqNo, run.auditRunId, firstSeq, lastSeq,
        uint64(events.len), eventRoot, decisionDigest, provRoot))
    let c = AuditCommit(
      commitSequence: seqNo,
      auditRunId: run.auditRunId,
      firstSequence: firstSeq,
      lastSequence: lastSeq,
      eventCount: uint64(events.len),
      eventRoot: eventRoot,
      decisionDigest: decisionDigest,
      provenanceRoot: provRoot,
      parentCommitId: (if prevId == "": ContentDigest("") else: ContentDigest(prevId)),
      recordedAt: run.recordedAt)
    var c2 = c
    c2.commitId = ContentDigest(commitId)
    # Frame payload first, closure last — one atomic append + fsync.
    var lines: seq[string]
    lines.add($beginFrameToJson(run))
    for d in decisions:
      lines.add($decisionToJson(d))
    for e in events:
      lines.add($eventToJson(e))
    lines.add($commitToJson(c2, prevId))
    let payload = join(lines, "\n") & "\n"
    var f: File
    if f.open(path, fmAppend):
      try:
        f.write(payload)
        f.flushFile()
      finally:
        f.close()
    ok(c2)
  except CatchableError as e:
    err("writeAuditLog: " & e.msg)

# ---------------------------------------------------------------------------
# Queries (pure)
# ---------------------------------------------------------------------------

func latestValidCommitAtOrBefore*(commits: openArray[AuditCommit];
                                  ts: string): Option[AuditCommit] {.raises: [].} =
  ## I18: latest valid commit whose recordedAt <= ts.  recordedAt is fixed-
  ## width ISO-8601 UTC in our writers, so lexicographic comparison is the
  ## temporal order (deterministic, depends only on the commit headers).
  result = none(AuditCommit)
  for c in commits:
    if c.recordedAt <= ts:
      result = some(c)