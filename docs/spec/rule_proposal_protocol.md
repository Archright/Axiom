# RuleProposal Protocol Specification

## 1. 개요

AGENTS.md의 불변성(§-1)을 보장하면서도 에이전트가 규칙 변경을 제안할 수 있는 정형화된 프로토콜.
Human-in-the-loop 승인 게이트를 통해 안전한 규칙 변경 파이프라인을 제공한다.

## 2. 상태 머신

```
pending → signed → approved → applied
                  ↘ rejected
                  ↘ expired
```

| 상태 | 전이 조건 | 담당자 |
|------|----------|--------|
| `pending` | `propose` 명령 실행 시 자동 생성 | 에이전트 |
| `signed` | `sign` 명령 실행 (HMAC-SHA256 서명) | 인간 건축가 |
| `approved` | 서명 검증 통과 후 | 시스템 |
| `applied` | `apply` 명령 성공 (빌드 검증 포함) | 시스템 |
| `rejected` | 인간 건축가가 거부 | 인간 건축가 |
| `expired` | TTL 만료 (7일) | 시스템 |

## 3. RuleProposal.json 스키마

### 필수 필드

| 필드 | 타입 | 설명 |
|------|------|------|
| `proposalId` | string (16 hex) | SHA-256 해시의 앞 16자 |
| `version` | string | 스키마 버전 ("1.0.0") |
| `timestamp` | string (ISO 8601) | 생성 시각 |
| `status` | enum | pending/approved/applied/rejected/expired |
| `title` | string | 규칙 제목 |
| `section` | enum | 대상 섹션 (constitution/architecture/rules_workflow/environment/guardian/new_section) |
| `subsection` | string | 삽입 지시자 |
| `content` | string (Markdown) | 추가/수정할 내용 |
| `rationale` | string | 변경 이유 |
| `proposedBy` | string | 제안자 식별자 |

### 선택 필드

| 필드 | 타입 | 설명 |
|------|------|------|
| `impact` | string | 영향 분석 |
| `evidence` | string[] | 근거 파일/링크 |
| `checksum` | string (64 hex) | content의 SHA-256 |
| `approval` | object | 승인 정보 (psApproved 시 필수) |

### ApprovalInfo 객체

| 필드 | 타입 | 설명 |
|------|------|------|
| `approvedBy` | string | 승인자 식별자 |
| `approvedAt` | string (ISO 8601) | 승인 시각 |
| `signature` | string (64 hex) | HMAC-SHA256 서명 |

서명 대상: `proposalId + checksum + approvedAt`

### Subsection 지시자

| 형식 | 설명 | 예시 |
|------|------|------|
| `after:2.XX` | 특정 서브섹션 뒤에 삽입 | `after:2.XY` |
| `new:2.XZ` | 새 서브섹션 생성 (§2와 §3 사이) | `new:2.XZ` |
| `replace:2.XY` | 기존 서브섹션 내용 교체 | `replace:2.XY` |
| (비어있음) | 대상 섹션 끝에 추가 | — |

## 4. apply 파이프라인 (6단계)

### Stage 0: CONCURRENCY GUARD
- `.axiom/proposal.lock`에 POSIX flock(2) 배타적 락 획득
- 다른 apply 프로세스가 진행 중이면 블로킹
- `src/engine/atomic_ops.nim`의 `c_flock` 패턴 사용

### Stage 1: LOAD + VERIFY SIGNATURE
- Proposal JSON 로드 + 상태 확인 (`psApproved`만 허용)
- `hmacVerify(payload, approval.signature)`로 서명 검증
- payload = `proposalId & checksum & approval.approvedAt`
- 실패 시 exit 1

### Stage 2: MUTATE (in-memory only)
- AGENTS.md 내용을 메모리에 로드
- 섹션 경계 감지 (`## §N.` 패턴)
- `subsection` 필드에 따라 삽입/교체 위치 결정
- 수정된 내용을 `modifiedContent` 변수에 보관 (디스크 미쓰기)

### Stage 3: STAGING — 심링크 스왑
- 원본 백업: `copyFile("AGENTS.md", "AGENTS.md.bak")`
- 스테이징 디렉토리 생성: `.axiom/staging_apply/`
- 수정본 쓰기: `writeFile(staging/AGENTS.md, modifiedContent)` + fsync
- 심링크 스왑: `removeFile("AGENTS.md")` → `createSymlink(staging/AGENTS.md, "AGENTS.md")`
- nimble build가 `staticRead`로 수정본을 읽음

### Stage 4: BUILD VERIFICATION
- `execCmdEx("nimble build 2&1")` 실행
- **빌드 실패 시 롤백**:
  - `removeFile("AGENTS.md")` (심링크 제거)
  - `moveFile("AGENTS.md.bak", "AGENTS.md")` (원본 복원)
  - `removeDir(".axiom/staging_apply/")` (스테이징 정리)
  - 감사 로그에 `apply_failed` 기록
- 빌드 성공 시 Stage 5 진행

### Stage 5: FINALIZE
- 원자적 최종 스왑: 심링크 제거 → 실제 파일로 교체
- 정리: 백업 삭제, 스테이징 디렉토리 삭제
- 상태 업데이트: `proposal.status = psApplied`
- 감사 로그 기록 (`.axiom/rule_proposals.jsonl`)
- stdout에 성공 메시지 출력

## 5. 보안 모델

### 5.1 동시성 제어
- POSIX flock(2) 기반 `.axiom/proposal.lock`
- `src/engine/atomic_ops.nim`의 `c_flock(fd, LOCK_EX)` 패턴
- apply 프로세스 간 mutual exclusion 보장

### 5.2 승인 무결성 (HMAC-SHA256)
- `src/infrastructure/sync_signing.nim`의 `hmacSign`/`hmacVerify` 사용
- 키: `.axiom/signing_key` (64-char hex, 32 random bytes, perms 600)
- 상수 시간 비교 (XOR accumulation) — 타이밍 사이드 채널 방지
- 서명 대상: `proposalId + checksum + approvedAt`
- 부인 방지: 서명 키는 인간 건축가만 보유

### 5.3 원자적 스테이징
- 심링크 스왑 패턴 (`src/core/gate/atomic_deploy.nim` 참조)
- 빌드 실패 시 원본 AGENTS.md 1비트도 변경 없음
- `.bak` 백업 + 스테이징 디렉토리 이중 안전장치

### 5.4 Proposal 변조 방지
- `checksum` 필드: content의 SHA-256 해시
- `approval.signature`: HMAC-SHA256으로 proposalId+checksum+approvedAt 서명
- 이중 검증: checksum 변경 → 서명 검증 자동 실패

## 6. CLI 사용법

```bash
# 1. 에이전트가 제안서 생성
bin/rule_proposal propose --file=proposal.json

# 2. 인간 건축가가 제안서 검토 후 서명
bin/rule_proposal sign --id=<proposalId> --by=human:suhyok

# 3. 시스템이 승인된 제안서 적용 (서명 검증 + 스테이징 + 빌드 + 원자적 스왑)
bin/rule_proposal apply --id=<proposalId>

# 4. 제안서 목록 조회
bin/rule_proposal list [--status=pending|approved|applied|rejected|expired]
```

## 7. 감사 추적

모든 이벤트는 `.axiom/rule_proposals.jsonl`에 append-only로 기록된다.

### 감사 이벤트 구조
```json
{
  "timestamp": "2026-06-28T03:00:00Z",
  "proposalId": "a1b2c3d4e5f67890",
  "action": "proposed|approved|applied|apply_failed|rejected|expired",
  "actor": "agent|human:suhyok|system",
  "details": "title=... section=...",
  "signature": "HMAC-SHA256(timestamp + proposalId + action + actor)"
}
```

## 8. 에이전트 워크플로우 예시

### 시나리오: 새 게이트 규칙 추가

1. 에이전트가 병합 프로세스 중 새 규칙이 필요하다고 판단
2. `RuleProposal.json` 생성:
```json
{
  "title": "2.XY Deterministic AST-Native Merge Protocol",
  "section": "rules_workflow",
  "subsection": "new:2.XY",
  "content": "### 2.XY Deterministic AST-Native Merge Protocol (HARD RULE)\n\n...",
  "rationale": "병합 충돌 해결의 결정론성 보장",
  "proposedBy": "agent:kimi-code",
  "evidence": ["docs/spec/sync_protocol_gate_architecture.md"]
}
```
3. `bin/rule_proposal propose --file=RuleProposal.json` 실행
4. 인간 건축가에게 알림 (stdout 메시지)
5. 인간 건축가가 검토 후 `bin/rule_proposal sign --id=<id> --by=human:suhyok`
6. `bin/rule_proposal apply --id=<id>` — 서명 검증 → 스테이징 → 빌드 → 원자적 스왑
7. 감사 로그에 기록 완료
