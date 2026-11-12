## src/core/debt/debt_projection.nim — Pure Projection Engine (v8, S2).
##
## Canonical Commit Stream — S2: committed ClassificationEvent 스트림을 순수
## 함수로 canonical UniverseProjection에 접는다 (projection materialization).
##
## v8 확정 계약 (executable spec: tests/unit/test_debt_projection.nim):
##
##   type OrderedEvent* = object
##     commitSequence*: uint64   ## global history order (AuditCommit.commitSequence)
##     auditSequence*: uint64    ## audit-local order (ClassificationEvent.auditSequence)
##     eventId*: string
##     ev*: ClassificationEvent
##
##   func orderedEvents*(events; commits): seq[OrderedEvent]
##     -- canonical order key = (commitSequence, auditSequence, eventId);
##        uncommitted run 제외 (I15/I16); timestamp 논키.
##   func projectAtCommit*(ordered; projectionVersion, inputRoot): UniverseProjection
##     -- fold reduce; 후보당 최신 committed event 상태 지배 (I19);
##        RESOLVED 는 active=false 로 유지, 삭제 금지;
##        universeDigest = H(canonical(UniverseProjection minus digest)).
##   func universeDigestOf*(p): string   -- D3: digest 재사용 헬퍼
##
## 본 모듈은 순수 함수만을 포함한다 — 시간 읽기, I/O, 전역 상태 금지
## (InvProjectionPure: projection = committed events ⊗ explicit version 의
## 순수 결정 함수). 시계나 프로세스 상태에 기반하는 분기 없음, 정렬을 통해
## map/seq 반복 순서 의존 제거.
##
## v8 D 계열 연결: D3 (동일 history + 동일 version → 동일 digest)는
## orderedEvents → projectAtCommit 이 완전 결정성 합성 함수임으로써 충족된다.
## I14: 함수의 도메인/코도메인이 immutable facts + version 이므로 materialized
## view 삭제 후 재구성은 digest-identical 하다.

import core/trusted/layer_declaration
axiomLayer "domain"

import std/[algorithm, strutils]
import core/axiom_pragmas
import core/types/debt_types

# ---------------------------------------------------------------------------
# OrderedEvent — canonical ordering 계약 타입.
#
# key 를 명시적으로 부여한 뒤 순수 비교자로 정렬한다. event.recordedAt 은
# key 가 아니다 (I18: 시간은 커밋 resolve 용 메타데이터이며 canonical
# projection order 에 개입하지 않는다).
# ---------------------------------------------------------------------------

type OrderedEvent* = object
  commitSequence*: uint64   ## global cross-audit commit order (v4#1)
  auditSequence*: uint64    ## audit-LOCAL sequence (전역 아님)
  eventId*: string
  ev*: ClassificationEvent

proc cmpOrderedEventKey(a, b: OrderedEvent): int {.raises: [].} =
  ## Canonical key comparator: (commitSequence, auditSequence, eventId).
  result = cmp(a.commitSequence, b.commitSequence)
  if result == 0:
    result = cmp(a.auditSequence, b.auditSequence)
  if result == 0:
    result = cmp(a.eventId, b.eventId)

# ---------------------------------------------------------------------------
# orderedEvents — event set → canonical total order.
#
# 유효성(inclusion) 규칙 (I16/InvCanonicality): auditRunId 가 최소 하나의
# 커밋 AuditCommit과 일치하는 이벤트만 canonical history 에 편입된다.
# 커밋되지 않은 run 의 이벤트는 절대로 projection 에 나타나지 않는다.
#
# 동일 key (commitSequence, auditSequence, eventId) 로 중복 존재하는 이벤트는
# 집합 의미로 중복 제거된다 — "permutation invariance": 동일 event SET 을
# 어떤 입력 순서로 넣든 동일한 ordered sequence 를 산출한다 (first keep).
# ---------------------------------------------------------------------------

func orderedEvents*(events: openArray[ClassificationEvent];
                    commits: openArray[AuditCommit]): seq[OrderedEvent] {.raises: [].} =
  ## 유효하게 커밋된 이벤트만 canonical order 로 정렬해 돌려준다.
  ## - auditRunId → commitSequence 결정: run에 커밋이 여럿이어도 가장 작은
  ##   commitSequence (최초 커밋)를 그 run 의 global 위치로 취한다.
  ## - dedupe: 완전 동일 key 는 입력 순서의 첫 번째 발생만 유지.
  ## - 정렬: (commitSequence, auditSequence, eventId) — timestamp 미사용.
  for ev in events:
    var commitSeq = 0'u64
    var runFound = false
    for c in commits:
      if raw(c.auditRunId) == ev.auditRunId:
        if not runFound or c.commitSequence < commitSeq:
          commitSeq = c.commitSequence
          runFound = true
    if not runFound:
      continue                       # uncommitted run — I16 제외
    var dup = false
    for existing in result:
      if existing.commitSequence == commitSeq and
         existing.auditSequence == ev.auditSequence and
         existing.eventId == ev.eventId:
        dup = true
        break
    if dup:
      continue                       # 동일 키 — 첫 발생만 유지
    result.add OrderedEvent(
      commitSequence: commitSeq,
      auditSequence: ev.auditSequence,
      eventId: ev.eventId,
      ev: ev)
  sort(result, cmpOrderedEventKey)

# ---------------------------------------------------------------------------
# projectAtCommit — fold over canonical ordered stream → UniverseProjection.
#
# 순수 fold (I19): 후보당 canonical order 상 마지막 이벤트가 최신 상태를
# 결정한다. RESOLVED → active=false (history 는 삭제하지 않고 후보 유지).
# universeDigest 는 전체 canonical 서술의 결정적 해시.
# ---------------------------------------------------------------------------

proc severityLabel(dc: DebtClass): string {.raises: [].} =
  ## 결정론적 severity 라벨 — 결과에서 파생되는 작은 로컬 매핑.
  ## 분류·세기·순서에 의존하지 않고 외부 계약이 없는 보조 필드.
  case dc
  of dcOpenDebt:    "high"
  of dcUnverified:  "medium"
  of dcStale:       "low"
  of dcResolved:    "none"
  of dcQuirk:       "low"
  of dcBudgetDrift: "medium"

proc canonicalCandidate(c: CandidateProjection): string {.raises: [].} =
  ## CandidateProjection 원자적 canonical 텍스트 — digest 입력 전용.
  c.candidateId & "\x1e" &
    debtClassToStr(c.classification) & "\x1e" &
    c.category & "\x1e" &
    c.severity & "\x1e" &
    (if c.active: "1" else: "0") & "\x1e" &
    c.firstSeen & "\x1e" &
    c.lastSeen & "\x1e" &
    c.lineageId & "\x1e" &
    c.decisionId

proc cmpCandidateId(a, b: CandidateProjection): int {.raises: [].} =
  ## candidateId 오름차순 — 결정적 candidates 순서 보장.
  cmp(a.candidateId, b.candidateId)

proc containsSeq(s: seq[uint64]; v: uint64): bool {.raises: [].} =
  for x in s:
    if x == v:
      return true
  false

proc containsStr(s: seq[string]; v: string): bool {.raises: [].} =
  for x in s:
    if x == v:
      return true
  false

func projectAtCommit*(ordered: openArray[OrderedEvent];
                      projectionVersion, inputRoot: string): UniverseProjection {.raises: [].} =
  ## Canonical(이미 orderedEvents 를 통과한) 이벤트 스트림을 fold → 최종
  ## projection 을 산출한다. 순수 함수: I/O·시간·전역 상태 없음.
  ##
  ## - 후보 상태: canonical order 상 최신 이벤트 (I19).
  ## - RESOLVED 는 active=false 로 유지, 삭제 금지.
  ## - 결정성: 하위 digest 전부 정렬된 입력 인자로만 계산.
  ##
  ## universeDigest = H(projectionVersion ∥ cutoff ∥ orderedCommitRoot ∥
  ##                    policyContextDigest ∥ inputRoot ∥ canonical(candidates)).

  # 1) 후보별 최신 이벤트 — canonical order 는 정렬 상태이므로
  #    마지막 등장(=key 최대) 이 이벤트가 해당 후보의 latest 이다.
  var latestSeqByCand: seq[tuple[cand: string, oe: OrderedEvent]]
  for oe in ordered:
    var idx = -1
    for i in 0 ..< latestSeqByCand.len:
      if latestSeqByCand[i].cand == oe.ev.candidateId:
        idx = i
        break
    if idx < 0:
      latestSeqByCand.add (oe.ev.candidateId, oe)
    else:
      latestSeqByCand[idx] = (oe.ev.candidateId, oe)

  # 2) 후보별 firstSeen / lastSeen — canonical order 순순회 (결정적).
  var candidates: seq[CandidateProjection]
  for (cand, latest) in latestSeqByCand:
    var firstSeen = ""
    var lastSeen = ""
    var seenFirst = false
    for oe in ordered:
      if oe.ev.candidateId == cand:
        if not seenFirst:
          firstSeen = oe.ev.recordedAt
          seenFirst = true
        lastSeen = oe.ev.recordedAt
    let cls = latest.ev.result
    candidates.add CandidateProjection(
      candidateId: cand,
      classification: cls,
      category: debtClassToStr(cls),
      severity: severityLabel(cls),
      active: cls != dcResolved,
      firstSeen: firstSeen,
      lastSeen: lastSeen,
      lineageId: latest.ev.parentEventId,
      decisionId: latest.ev.decisionId)

  sort(candidates, cmpCandidateId)   # 결정적 순서 (digest 입력·반환 모두)

  # 3) orderedCommitRoot — 본 함수는 commits 배열에 접근할 수 없으므로
  #    canonical "ordered [{commitSequence}]" 셋(유일 커밋 시퀀스, 정렬)을
  #    봉합한다. 동일 committed history → 동일 root (D4 하위 호환).
  var commitSeqs: seq[uint64]
  for oe in ordered:
    if not containsSeq(commitSeqs, oe.commitSequence):
      commitSeqs.add oe.commitSequence
  sort(commitSeqs)
  var lines = ""
  for s in commitSeqs:
    if lines.len > 0:
      lines.add '\x1e'
    lines.add $s
  let orderedCommitRoot = sha256Ref("OrderedCommitRoot:", lines)

  # 4) cutoff — 마지막 커밋 시퀀스 (빈 history = HEAD).
  let cutoff =
    if commitSeqs.len > 0: "cutoff:" & $commitSeqs[commitSeqs.high]
    else: "HEAD"

  # 5) policyContextDigest — active 후보의 정렬+중복제거 decisionId 해시 (v3#6).
  var activeDecisions: seq[string]
  for c in candidates:
    if c.active and c.decisionId.len > 0 and not containsStr(activeDecisions, c.decisionId):
      activeDecisions.add c.decisionId
  sort(activeDecisions)
  var decisionPayload = ""
  for d in activeDecisions:
    if decisionPayload.len > 0:
      decisionPayload.add '\x1e'
    decisionPayload.add d
  let policyContextDigest = sha256Ref("PolicyContext:", decisionPayload)

  # 6) universeDigest — canonical(모든 필드 minus digest).
  var canonCandidates = ""
  for c in candidates:
    if canonCandidates.len > 0:
      canonCandidates.add '\x1e'
    canonCandidates.add canonicalCandidate(c)
  let universeDigest = sha256Ref("UniverseProjection:",
    projectionVersion & "\x1e" &
    cutoff & "\x1e" &
    orderedCommitRoot & "\x1e" &
    policyContextDigest & "\x1e" &
    inputRoot & "\x1e" &
    canonCandidates)

  result = UniverseProjection(
    projectionVersion: projectionVersion,
    cutoff: cutoff,
    orderedCommitRoot: orderedCommitRoot,
    policyContextDigest: policyContextDigest,
    inputRoot: inputRoot,
    candidates: candidates,
    universeDigest: universeDigest)

func universeDigestOf*(p: UniverseProjection): string {.raises: [].} =
  ## D3 헬퍼 — 이미 materialize 된 universeDigest 재사용.
  p.universeDigest