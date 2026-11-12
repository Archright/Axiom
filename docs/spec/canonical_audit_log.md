# Canonical Audit Log — Strict Commit Stream (v8)

**상태**: 적용 (v8, 2026-08)
**소스**: `src/core/types/debt_types.nim` (§617-655 const), `src/core/debt/debt_events.nim`, `src/core/debt/debt_projection.nim`, `src/core/debt/debt_pipeline.nim`, `src/cli/debt_cli.nim`
**테스트**: `tests/unit/test_debt_events.nim` (8), `test_debt_projection.nim` (6), `test_debt_pipeline.nim` (4)
**AGENTS.md 참조**: §0.9 Theater Prohibition, §0.9a Theater Debt Registry Schema, §0.5c Structured QUIRK/Spec

---

## 1. 요약

Canonical audit log는 append-only 감사 저널에 엄격한 commit manifest를 결합한 구조이다. 단일 writer가 `TX-BEGIN / DECISION* / EVENT* / TX-COMMIT` 프레임을 순서대로 기록하며, 각 물리적 줄에는 JSON 객체 하나만 포함된다. `AuditCommit`은 execution closure로서 "무엇이 실행·영속되었는가"를 canonical history에 편입시키는 유일한 승격 증거이며, interpretation(universeDigest/projectionVersion)은 `ProjectionRequest(commitId, projectionVersion)` 쪽 소관으로 분리된다. 이 설계는 marker-based 포맷을 폐기하고 D4(Canonical History Determinism) + fail-closed recovery + replay auditability를 보장한다.

---

## 2. 불변식 (Invariants)

### 2.1 최종 4대 불변식 (v8 — 피드백 §11 확정)

```nim
InvCanonicality =
  "Canonical history is the maximal valid committed prefix of the audit log"

InvCommitValidity =
  "A commit is valid iff its transaction is complete, its closure validates, and its parent/sequence relation matches the preceding canonical commit"

InvRecovery =
  "Only an incomplete frame at physical EOF is recoverable; any corruption after a valid committed prefix is fail-closed"

InvProjectionPure =
  "Projection is a pure deterministic function of committed canonical events and an explicit projection version"
```

출처: `src/core/types/debt_types.nim` lines 638-645 (`const` 섹션).

### 2.2 결정성 4종 (v8 — 피드백 7)

```nim
D1ExecutionDeterminism =
  "same AuditInputManifest + same PolicyArtifact + same evaluatorVersion -> same PolicyDecision set"

D2EventDeterminism =
  "same decision set -> same canonical ClassificationEvent set -> same eventRoot"

D3ProjectionDeterminism =
  "same committed history + same ProjectionRequest.projectionVersion -> same universeDigest"

D4CanonicalHistoryDeterminism =
  "same logical history -> same canonical commit chain (digest/sequence/parent)"
```

출처: `src/core/types/debt_types.nim` lines 648-655.

### 2.3 추가 코드 참조 불변식

아래 불변식들은 `debt_types.nim` const §(lines 618-635)에서 정의되며, v8 commit stream 설계와 직접 연관된다:

```nim
I15CommittedVisibility =
  "uncommitted ClassificationEvent (no valid AuditCommit) -> never visible in canonical current universe"

I16CommitAuthority =
  "only a valid AuditCommit (eventRef==expected, committed stream) can produce canonical projection; AuditRun.status is metadata only"

I17CommitClosure =
  "a committed AuditRun has an immutable ClassificationEvent set; appending any later event to that run is invalid"

I18TimeProjectionClosure =
  "projectUpToTime(t) = projectUpToCommit(latestValidCommitAtOrBefore(t))"

I19ProjectionStateRule =
  "current classification(candidate) = latest valid committed ClassificationEvent under order (commitRun,didSeq,eventId); RESOLVED kept as active=false history, never deleted"

I20ReplayTargetIdentity =
  "exact replay -> AuditRunId; re-evaluate -> AuditInputId; reconstruct -> CommitId|time; explain -> CandidateId"
```

---

## 3. 설계 결정

### 3.1 Closure vs Interpretation Split

`AuditCommit`은 **execution closure**이다. 다음 필드를 포함한다:

| 필드 | 의미 |
|------|------|
| `commitSequence` | 전역 cross-audit history order (single-writer ordinal) |
| `auditRunId` | owning audit run (content-addressed) |
| `firstSequence` / `lastSequence` | audit-local event range |
| `eventCount` | committed event 수 |
| `eventRoot` | H(canonical(committed event set)) — content-address 증명 (D2) |
| `decisionDigest` | evaluator(PolicyDecision[]) output의 canonical root |
| `provenanceRoot` | provenance DAG root |
| `parentCommitId` | 이전 canonical commit 체인 링크 |
| `recordedAt` | execution metadata (ISO-8601) |

**포함하지 않는 필드**: `universeDigest`, `projectionVersion` — 이들은 interpretation 소관이며 `ProjectionRequest` 쪽에서 관리된다.

```nim
ProjectionRequest* = object
  commitId*: ContentDigest
  projectionVersion*: string
```

동일 commit + projectionVersion v1 → universeDigest A, v2 → universeDigest B.

### 3.2 commitId 계산

```
commitId = H(canonical(AuditCommit excluding commitId, excluding recordedAt))
```

`recordedAt`은 execution metadata로 I18(`TimeProjectionClosure`)에서 시간→커밋 resolve용으로 쓰이지만, canonical closure hashing에서는 제외된다(D4). 이는 동일한 논리 역사가 다른 시간에 기록되어도 동일한 commit chain을 산출함을 보장한다.

### 3.3 Single-Writer Model

- `commitSequence` = 마지막 canonical commit의 sequence + 1
- `parentCommitId` = 직전 canonical commit의 `commitId`; 첫 commit의 parent = empty digest
- 단일 writer가 순차적으로 append — 동시성 제어 없음 (append-only journal의 단순성)

### 3.4 Health 모델 (ReadHealth)

```nim
ReadHealth* = enum
  rhClean            ## 유효한 레코드만 존재
  rhRecoverableTail  ## EOF의 불완전 frame만 있음 — 유효 prefix 승격, tail 폐기
  rhMalformedRecord  ## 문법 오류 record 발견 — forensic reader용 기록(telemetry)
  rhIntegrityFailure ## 유효 prefix 이후 중간 손상/체크섬 불일치 — fail-close
```

canonical reader는 **maximal valid committed prefix만을 승격**한다:

- `rhClean`: 모든 레코드가 유효 — 전체 history 사용
- `rhRecoverableTail`: 물리적 EOF에서 불완전한 frame (마지막 줄에 newline 없음) — 유효 prefix를 승격하고 torn tail을 폐기
- `rhIntegrityFailure`: 유효 prefix 이후 mid-file 손상 — fail-closed (손상 지점 이후 폐기)
- `rhMalformedRecord`: syntax error — forensic reader가 `JournalSkip(lineNo, reason, kind)`로 수집

### 3.5 Module Map

| 모듈 | 책임 | 핵심 API |
|------|------|---------|
| **S1** `src/core/debt/debt_events.nim` | Writer/Reader/Query | `writeAuditLog`, `readCommitHistory`, `readCommitHistoryForensic`, `readTransactions`, `latestValidCommitAtOrBefore`, `isRunCommitted` |
| **S2** `src/core/debt/debt_projection.nim` | Pure orderedEvents/projectAtCommit/universeDigestOf — I/O 없음, clock 없음 | `orderedEvents`, `projectAtCommit`, `universeDigestOf` |
| **S3** `src/core/debt/debt_pipeline.nim` | Orchestration: TRANSACTION → VALIDATE → COMMIT | `runAudit`, `replayAuditRun` |

### 3.6 Wire Format

프레임 태그 (4종):

| 태그 | 의미 | JSON 키 |
|------|------|---------|
| `B` | TX-BEGIN | `"txBegin"` |
| `D` | DECISION | `"decision"` |
| `E` | EVENT | `"event"` |
| `C` | TX-COMMIT | `"commit"` |

각 프레임은 물리적 줄 하나에 JSON 객체로 직렬화된다. 태그는 `"t"` 필드에 `B`/`D`/`E`/`C` 값으로 식별한다. 예:

```json
{"t":"B","run":"run-1","input":"sha256:...","pd":"sha256:...","er":"sha256:...","rr":"sha256:...","ts":"2026-01-01T00:00:00Z"}
{"t":"D","di":"sha256:...","c":"cand-1","e":"sha256:...","pd":"sha256:...","v":"ACCEPT","r":"rationale"}
{"t":"E","id":"ev-1","c":"cand-1","run":"run-1","seq":"0","di":"sha256:...","cv":"cv1","rs":"rs1","tv":"t1","res":"OPEN_DEBT","ev":["e1"],"pe":"","ts":"2026-01-01T00:00:00Z","snap":"snap1"}
{"t":"C","seq":"1","run":"run-1","f":"0","l":"0","n":"1","er":"sha256:...","dd":"sha256:...","pr":"sha256:...","pid":"","ts":"2026-01-01T00:00:00Z","id":"sha256:..."}
```

필드명은 `src/core/debt/debt_events.nim`의 직렬화기(`beginFrameToJson`/`decisionToJson`/`eventToJson`/`commitToJson`)가 정의한다.

### 3.7 결정성 보장

- `eventRoot` / `decisionDigest`는 payload로부터 결정론적으로 계산됨 — `run.eventRoot` 같은 runtime 값 사용 금지
- canonical event ordering key: `(commitSequence, auditSequence, eventId)` — timestamp(**recordedAt**)는 ordering key가 아님 (I18)
- 동일 입력 → 동일 출력 합성 함수: `orderedEvents → projectAtCommit` (D3)

---

## 4. CLI 표면

현재 `src/cli/debt_cli.nim`에 wiring 중인 명령어:

| 명령어 | 설명 |
|--------|------|
| `ax debt audit-run <journal-path> <projection-version> [input-root]` | v8 `runAudit`: 결정·이벤트를 canonical TX로 커밋하고 commitId/eventRoot/decisionDigest/universeDigest 출력 |
| `ax debt replay <journal-path> <run-id> <projection-version>` | `replayAuditRun`: 커밋된 execution을 재구성해 closure digest 비교(allMatch) 및 projection 재계산 |
| `ax debt reconstruct <journal-path> [--at <commit-id|time>]` | `readTransactions`+projection 재계산: 동일 history → 동일 universeDigest (D3/I14) |
| `ax debt explain <journal-path> <candidate-id>` | candidate의 최종 상태(classification/active/firstSeen/lastSeen)와 lineage 이벤트 출력 (I20) |

journal 경로는 CLI 인자로 명시하며, 기본 evidence journal(`data/debt/observations.journal`)은 그대로 유지된다.

---

## 5. Rationale

### 5.1 Marker-Based 포맷 대체 이유

기존 `data/debt/observations.journal`은 observation entry를 plain JSON append 방식으로 기록하지만, commit manifest가 없으면:

1. **D4 위반**: 동일한 논리 역사가 다른 시점에 기록되면 다른 commit chain을 산출할 수 있음
2. **Recovery 비결정적**: mid-file 손상 시 maximal valid prefix를 어떻게 정의할지 명확하지 않음
3. **Replay Auditable 하지 않음**: commit closure가 없으면 "무엇이 영속되었는가"를 독립적으로 검증 불가

strict manifest는 이를 해결한다:

- `commitId = H(closure)` — content-addressed commit이 SSOT
- `parentCommitId` chain — linear history traversal 가능
- `eventRoot` / `decisionDigest` — payload integrity 검증

### 5.2 피드백 반영 (v8)

- **피드백 5·6**: closure에 `universeDigest`/`projectionVersion` 포함 금지 — interpretation split 확립
- **피드백 7**: D4 명칭을 `Canonical History Determinism`으로 확정
- **피드백 11**: 4대 불변식(InvCanonicality, InvCommitValidity, InvRecovery, InvProjectionPure) 확정 원문

---

## 6. 테스트 커버리지 매핑

### 6.1 `tests/unit/test_debt_events.nim` (8 tests)

| 테스트 | pinned invariant |
|--------|-----------------|
| `complete transaction promotes exactly one canonical commit (rhClean)` | InvCanonicality, InvCommitValidity |
| `commit sequence = last valid + 1, parent chain (D4)` | D4 |
| `rewriting identical logical history yields identical chain (D4 determinism)` | D4 |
| `incomplete frame at physical EOF -> recoverableTail (InvRecovery)` | InvRecovery |
| `middle corruption after valid prefix -> integrityFailure (fail-closed)` | InvRecovery |
| `latestValidCommitAtOrBefore resolves time -> commit (I18)` | I18 |
| `isRunCommitted (I16)` | I16 |
| `forensic reader reports skipped lines instead of silently dropping` | InvRecovery (forensic path) |

### 6.2 `tests/unit/test_debt_projection.nim` (6 tests)

| 테스트 | pinned invariant |
|--------|-----------------|
| `canonical ordering excludes uncommitted events (I16 / InvCanonicality)` | I16, InvCanonicality |
| `permutation invariance after canonical ordering` | D2, InvProjectionPure |
| `I19 state rule: RESOLVED -> active=false, kept; later OPEN revives` | I19 |
| `I12/D3 determinism: same input -> same universeDigest; version change -> different` | I12, D3 |
| `digest sensitivity: event set / classification change alters digest` | D3 |
| `universeDigest = canonical serialization (stable fields)` | D3 |

### 6.3 `tests/unit/test_debt_pipeline.nim` (4 tests)

| 테스트 | pinned invariant |
|--------|-----------------|
| `runAudit writes TX + commit; canonical history has exactly one commit` | InvCanonicality, InvCommitValidity |
| `failed validation never touches the journal (I15)` | I15 |
| `replay reconstructs committed execution with matching digests (D4/I13)` | D4, I13 |
| `commit closure: second audit on same run rejected (I17)` | I17 |

---

## 7. 참고

- `docs/spec/debt_universe_audit.md` — v8 canonical commit stream 섹션에서 본 문서로 연결
- `src/core/types/debt_types.nim` lines 451-481 — `AuditCommit`, `ProjectionRequest`, `ReadHealth`, `JournalSkip`, `JournalReadReport` 타입 정의
- `src/core/types/debt_types.nim` lines 617-655 — 모든 invariant const 정의
