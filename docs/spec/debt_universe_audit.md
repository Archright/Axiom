# Canonical Current Debt Universe — Deterministic Audit

**생성일**: 2026-08-15
**상태**: Active (deterministic evidence-first debt audit)
**소스**: `src/cli/debt_cli.nim`, `src/core/types/debt_types.nim`, `tests/unit/test_debt_universe_determinism.nim`
**근거**: `docs/history/reports/technical_debt_comprehensive_audit_2026_08_15.md` (baseline report)
**AGENTS.md 참조**: §0.9 Theater Prohibition, §0.9a Theater Debt Registry Schema, §0.5c Structured QUIRK/Spec

---

## 1. Purpose

Axiom의 기술부채 관리를 **registry-first에서 evidence-first로 전환**한다.

기존 모델은 `data/debt_registry.json`을 진실의 원천(SSOT)로 두고,
커서드 호면해 코드에 `DEBT#` 마커가 있어도 `fileExists`/`source` 여부에 따라
`OPEN_DEBT` / `STALE` / `RESOLVED` / `UNVERIFIED` 로 재판정한다.

핵심 설계 원칙 (사용자 주도, 2026-08-15):

1. **Fingerprint = canonical identity**, `DEBT#` = historical human-facing alias.
2. **탐지(이상 징후)와 판정(현재 부채 여부)을 분리** — 숫자 하나만으로 부채가 자동 생성되지 않는다.
3. **registry는 index/view일 뿐, evidence graph가 SSOT**.
4. **QUIRK은 3-way**: `UPSTREAM_CONFIRMED | PROJECT_LOCAL | UNVERIFIED/HISTORICAL`.
5. **PRODUCT_INTEGRITY_DEBT** (verification bypass / skip / exemption / fallback /
   noncanonical / manual override / uncertified path) 는 일반 TODO보다 높은 우선순위.
6. 모든 판정에 **규칙 버전(commit + detector + classifier + taxonomy)**을 박아
   `same repo + same detector + same rules = same universe` 결정론적 불변식을 보장.

## 2. CLI

`ax debt` 명령 11종 (`src/cli/debt_cli.nim`).
`runDebtCli` case: `sync|check|budget|ledger|audit|fingerprint|classify|universe|observe|evolve|drift`.

- `ax debt audit` → 분류 요약 + OPEN_DEBT/BUDGET_DRIFT 상세, 이상 시 exit 1.
- `ax debt universe` → `CanonicalCurrentDebtUniverse` JSON (`repository`, `commitSha`, versions,
  `openDebt`, `stale`, `resolved`, `unverified`, `quirks`, `budgetDrift`).
- `ax debt classify` → 항목별 분류.
- `ax debt fingerprint` → 항목별 `sha256:` fingerprint.
- `ax debt observe` → registry 항목을 `DebtObservation`으로 변환해 불변 evidence journal
  (`data/debt/observations.journal`, append-only)에 기록. 같은 내용은 내용 주소화로 중복 skip.
- `ax debt evolve [--explain <candidateId> | --json]` → observe→classify→provenance 전체 파이프라인.
  `--json` 출력에 `universeDigest` 필드 포함 (결정론적 SHA-256, 정렬된 classification events + ruleSetHash + taxonomyVersion).
- `ax debt drift` → budget metric 을 drift 로 분류. `driftIsAutoDebt`는 항상 false
  (metric 불일치 ≠ 자동 부채, 승격은 별도 정책 판정 필요).

## 2a. Evidence-first 파이프라인 & 분리 모듈

Registry-first를 폐기하고 evidence graph를 SSOT로 두는 순수 함수형 로직을
영향 없는(no-I/O) 모듈로 분리 (`src/core/debt/`):

| 모듈 | 책임 | 핵심 API |
|------|------|---------|
| `debt_observation.nim` | Observation substrate (immutable) | `canonicalizeObservation`, `observationDigest` |
| `debt_identity.nim` | canonical fingerprint (rule-independent) | `computeCandidateId` = `sha256("candidate:" ∥ observationIdentity(subject, semanticIdentity))` — snapshot/line 제외 |
| `debt_classifier.nim` | deterministic pure classification | `classifyDebt`(event-sourcing), `latestClassification`, `currentView` |
| `debt_budget.nim` | metric/drift 모델 (debt와 독립) | `classifyDrift`(MATCH…UNVERIFIED), `driftIsAutoDebt=false` |
| `debt_claim.nim` | 3-way quirk + claim | `assessQuirk`(`UPSTREAM_CONFIRMED|PROJECT_LOCAL|UNVERIFIED_HISTORICAL`) |
| `debt_provenance.nim` | append-only provenance DAG | `buildGraph`, `appendNode/Edge`, `findPath`(BFS), `nodeById`, `evidenceChainFor`(역추적 DFS) |

공용 타입 계약: `src/core/types/debt_types.nim` (모든 모듈이 import).

각 `ClassificationEvent` 는 `eventId = H(candidateId‖classifierVersion‖ruleSetHash‖parentEventId)` 로
event-sourcing (append-only, overwrite 없음). `currentView` 는 candidate line별 최신 이벤트만 view.

결정론 불변식: 같은 repo snapshot + 같은 detector/classifier/taxonomy rule = 같은 universe.
`evolve --explain <candidateId>` 는 provenance DAG를 따라 `Classification → Observation` 체인을
완전히 재생한다 (예: 후보 `012b6b…` → 체인 길이 2).

## 3. Classification (`classifyEntry`)

입력: `debt_registry.json` 항목 + cwd. 파일 존재/소스 마커(`source`)/resolution/category 기준.

```
category contains "quirk"          -> QUIRK
status open  + file/source 존재     -> OPEN_DEBT
status open  + 파일 전무            -> UNVERIFIED
status closed/accepted + resolution -> RESOLVED   (lifecycle settled)
status closed/accepted (무내용)     -> STALE or RESOLVED
fallback                           -> STALE
```

(2026-08-15 변경: `closed` 분기를 resolution 우선으로 재구성 —
이전엔 resolution이 있더라도 파일 전무 시 STALE로 잘못 귀속. 이제 해결된 부채는 항상 RESOLVED.)

## 3. Fingerprint (`computeFingerprint`)

```
sha256:sha256(category | normalizeFilePath(files) | normalizeDescription(description))
```

- 정규화: 경로 백슬래시→슬래시, `./` 제거 — 동일 부채는 동일 fingerprint (같은 lineage).
- 서로 다른 파일/설명 → 서로 다른 fingerprint.

## 4. Determinism Invariant

검증 (`tests/unit/test_debt_universe_determinism.nim`):
- 같은 입력 → 같은 fingerprint / 다른 입력 → 다른 fingerprint / 경로 정규화.
- `open`+존재 파일 → `OPEN_DEBT`, `open`+불존재 → `UNVERIFIED`, `closed`+resolution → `RESOLVED`,
  `quirk` category → `QUIRK`.
- `ax debt universe` 결정론: 연속 2회 실행 `sha256sum` 동일 (`322e863fe4...`).

## 5. Budget Drift 는 Debt 이 아님

`debt_registry_open`/`closed` 등 지표가 예산(`data/debt_budgets.json`)과 다르면
즉시 부채가 아니라 **BUDGET_DRIFT 후보**로 분리 — `measurement-drift | baseline-drift |
definition-drift | intentional-regression | stale-budget | unverified` 중 하나를 판정 후 연결.

## 6. Verified results (2026-08-15, commit 79da0df)

**registry-view 분류기** (`ax debt audit`, 기존 경로):
```
OPEN_DEBT      2   DEBT#416 (Kernel), DEBT#417 (Architecture, WONT_FIX)
UNVERIFIED     0
STALE          0
RESOLVED      143
QUIRK         2
BUDGET_DRIFT   2   effect_violations 2090/80 (2512.5%), debt_registry_closed 107/0
```

**evidence-first 분류기** (`ax debt evolve`, 신규 파이프라인 — 147개 registry 항목 → 147개
`ClassificationEvent`, observation journal `data/debt/observations.journal` 395KB):
```
OPEN_DEBT    105   okSourceMarker default → dcOpenDebt (raw rule; lineage별 OPEN_DEBT 정책 판정은 별도)
RESOLVED      34   payload "RESOLVED"/"FIXED" → dcResolved
STALE          6   payload "STALE" → dcStale
QUIRK          2   payload "QUIRK" → dcQuirk
BUDGET_DRIFT   0
Total events: 147   Classifier/Rule/Taxonomy: classifier-dev
```

⚠️ **두 수치(2 vs 105 OPEN)는 오류가 아닌 서로 다른 view다.** registry-view는 lifecycle +
resolution 위주로, evidence-first raw classifier는 payload 문자열 규칙만으로 분류한다.
둘의 차이는 의도된 것이며, 최종 `OPEN_DEBT` 정책 판정(§5의 dissension 기준:
actionable ∧ currently-true ∧ evidence-sufficient ∧ not-intentionally-accepted)은
아직 명시 결정 정책 평가 단계에 있다. 결정론 재생은 `ax debt evolve --explain <candidateId>`로
검증된다 (예: `012b6b…` → Chain length 2: Classification → Observation).

## 7. Restriction

- `AGENTS.md`, `config.nims`, `import_encapsulation_gate.nim` 는 immutable (원 목록의 `.github/workflows/ci.yml`은 CI=0 cutover, 2026-09-20로 삭제됨) — 이 문서는 소스/레지스트리/레지스트리 미변경.
- 명령은 워크트리 검증만, 커밋/푸시 없음.

---

## (v8) Canonical Commit Stream

v8 기술부채 universe는 결정론적 audit log 위에 구축된다. 기존 marker-based evidence journal(`data/debt/observations.journal`) 대신, **strict commit manifest**를 채택하여 단일 writer가 `TX-BEGIN / DECISION / EVENT / TX-COMMIT` 프레임을 append-only로 기록한다. 각 물리적 줄에는 JSON 객체 하나만 포함된다.

### Closure / Interpretation Split

`AuditCommit`은 execution closure이다 — "무엇이 실행·영속되었는가"를 담은 객체로, `eventRoot`, `decisionDigest`, `provenanceRoot`, `commitSequence`, `parentCommitId`를 포함한다. `universeDigest`와 `projectionVersion`은 포함하지 않는다. interpretation은 `ProjectionRequest(commitId, projectionVersion)` 쪽 소관이며, 동일 commit + projectionVersion v1 → universeDigest A, v2 → universeDigest B로 분리된다.

### 새 불변식 (I15–I20 + 4대 최종 불변식)

기존 v7 불변식(I12–I14)에 더해 v8에서 6개가 추가된다:

- **I15** `CommittedVisibility`: uncommitted ClassificationEvent는 canonical current universe에 보이지 않음
- **I16** `CommitAuthority`: 유효한 `AuditCommit`만 canonical projection을 생성; `AuditRun.status`는 metadata만 담당
- **I17** `CommitClosure`: 커밋된 `AuditRun`은 immutable `ClassificationEvent` set을 가짐; 이후 이벤트 append는 무효
- **I18** `TimeProjectionClosure`: `projectUpToTime(t) = projectUpToCommit(latestValidCommitAtOrBefore(t))`
- **I19** `ProjectionStateRule`: 최신 유효 커밋 이벤트가 상태를 지배; RESOLVED는 `active=false`로 유지, 삭제 불가
- **I20** `ReplayTargetIdentity`: exact replay → AuditRunId, re-evaluate → AuditInputId, reconstruct → CommitId|time, explain → CandidateId

최종 4대 불변식:

- **InvCanonicality**: Canonical history는 audit log의 maximal valid committed prefix
- **InvCommitValidity**: commit이 유효하려면 transaction이 완전하고, closure가 validate되며, parent/sequence relation이 직전 canonical commit과 일치해야 함
- **InvRecovery**: 물리적 EOF의 불완전 frame만 recoverable; 유효 prefix 이후 중간 손상은 fail-closed
- **InvProjectionPure**: Projection은 committed canonical events와 명시적 projection version의 순수 결정 함수

### Health/Recovery 모델

`ReadHealth` 4분류: `rhClean`(모두 유효), `rhRecoverableTail`(EOF 불완전 frame — 유효 prefix 승격, tail 폐기), `rhMalformedRecord`(문법 오류 — forensic reader용 telemetry), `rhIntegrityFailure`(유효 prefix 이후 중간 손상 — fail-close). canonical reader는 maximal valid committed prefix만 승격한다.

자세한 내용은 `docs/spec/canonical_audit_log.md`를 참조한다.