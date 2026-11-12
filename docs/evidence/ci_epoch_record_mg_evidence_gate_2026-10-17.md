# CI Epoch Record — mg-evidence-gate 세대 전환 (2026-10-17)

> §2.5 CI Epoch Cutover — Freeze · Record · Cutover. 정본 규칙: `AGENTS.md` §2.5 / `docs/agents/ci_epoch_cutover.md`. 형식 선행 기록: `docs/evidence/ci_epoch_record_2026-10-12.md`. 사전등록: [mg_evidence_gate_prereg_2026-10-17.md](mg_evidence_gate_prereg_2026-10-17.md).
> **전환 물건(단일 cutover 커밋에 결속)**: `.github/workflows/admission-check.yml` (blob `f2ad3b03…` → `1c9848a74b4767faa696138c2985d267d73f65ac`) + `config/trusted_writer_set.json::trustedAdmissionWorkflowSha` + `config/policy/epoch_manifest.json::productionExecutionPin` (ADR-0025 Amendment F 원자 회전 — "두 값 외 변경 없음"). Nim 계층 선행 커밋 48a33ede4 (`src/verification/judgment_cas.nim` 강제 실행 단락회로 + SSOT 서브젝트 투영 CLI).

## 1. Freeze

| 항목 | 값 |
|---|---|
| freeze tag | `ci-freeze-mg-evidence-gate-20261017` (annotated, 태그 객체 51408987a…) — **변경 이전 세대**(pre-change generation)를 가리킨다 |
| tag → commit | `c9cca2655` (main 병합 지점; 워크플로 blob f2ad3b03 == 양 핀 — 롤백 기준선) |
| Nim 커밋 | `48a33ede4` (freeze 이후, cutover 이전 — 브랜치 `ci/mg-evidence-gate`) |
| preflight | `nim c -r src/gate/runners/agent_preflight.nim` PASS (편집 전 HARD RULE 이행) |

## 2. Record — 세대 상태 전이

### 2.1 구세대 (f2ad3b03, ~2026-10-17)

- 착지(merge_group) venue의 Judgment CAS가 **원장 재사용(REUSED)을 허용** — GO-critical 테스트가 착지 런에서 재사용 판정으로 건너뛸 수 있었다.
- armed-attest는 레코드 **존재**만 검사(FAIL-CLOSED) — 서브젝트 집합의 완결성(누락/잔존 decision 파일)은 검사 대상이 아니었다.

### 2.2 신세대 (1c9848a74b…)

- **REUSED-on-MG 차단**: 레인 plan env `AXIOM_JUDGMENT_CAS_FORCE_EXECUTED: ${{ github.event_name == 'merge_group' && '1' || '' }}` — callee는 호출자 event_name을 상속(실측: MG 38983713057 → venue=landing, PR 38990620435/38983249224 → venue=preflight)하므로 착지 런의 계획 단락이 원장 consult 전에 jExecuted로 단락된다(48a33ede4). PR preflight는 빈 값 — 재사용 유지.
- **SSOT 서브젝트 집합 동등성**: armed-attest가 B-built `ax cert judgment-subjects`(1줄/서브젝트)와 실제 decision 파일 투영(`jq -r '.subject // "s1a"'`, sort -u)을 개수+문자열(comm) 동등 검사 — 누락·잔존 모두 fail-closed. 기존 레코드 존재 검사는 약화 없이 유지.
- **착지 basis 증명**: merge_group venue에서 전 decision 파일 `"basis":"EXECUTED"` 강제(grep -q 방식, 비-EXECUTED 서브젝트 목록과 함께 fail) — 강제 술어가 callee에 닿지 않은 세대 왜곡을 착지 런 자체가 증명한다.
- **활성화 순간**: (i) MG 런 `referenced_workflows`의 admission-check sha == 1c9848a74b… **그리고** (ii) 동일 런 집계 `admission-check` SUCCESS — 두 조건의 최초 동시 성립 런. org 캘리는 신세대 브랜치에서도 구핀(64f78ab7d…)을 참조하므로, main 병합 직후 첫 MG 런은 "구핀 캘리 × 신세대 H 트리 yml" 조합이며 신세대 배선의 첫 라이브 검증이다(구핀 자기 검증 — 사전등록 §4).

### 2.3 검증 상태 (기계 관측)

| 검증 | 결과 |
|---|---|
| 단위 G11 (48a33ede4) | green — 술어 5 분기 + SSOT 투영 정준 바이트 + 클로저 유도 케이스 |
| `make test-workflow-poison-lint` | PASS — files=16, tokenized-max-overall=14049 (한도 21k) |
| pyyaml `safe_load` | PASS |
| 편집 run 블록 `bash -n` | PASS (attest step, lane env 표현식 확인) |
| 라이브 MG 집합 동등성 · PR 재사용 유지 | **관측 대기** — merge_queue 진입 후 판정 (사전등록 §3.2 계약) |

## 3. Tombstone

**"REUSED-on-merge_group 허용"의 종료 선언.** 구세대 blob f2ad3b03의 착지 venue 재사용 포즈는 본 전환으로 끝난다. 이것은 **우회·면제·required-check 제거가 아니다**: required check `admission-check`(ruleset 20303214)는 변함없이 단일 required로 유지되며, 신세대는 착지의 증거 기준을 **강화**한다(실행 강제 + 집합 동등성 + basis 증명). 폐기되는 실행 경계는 없다 — 행동 포즈의 세대 교체만이 기록된다. rollback: freeze 태그에서의 원자 revert + 필요 시 org 핀 f2ad3b03 재회전(사전등록 §5).

## 4. Open items (§0.9 open register)

1. org 핀 회전(Archright/.github) — 별도 후속 단계(본 세대 커밋 밖; 사용자 승인 하 별도 작업).
2. 적색 런 append 뉘앙스 / G10(e) changed-tree 드릴 환경 의존 / 셸 fixture 하네스 deferred — 사전등록 §6과 동일한 open register다(중복 기록하지 않는다).
