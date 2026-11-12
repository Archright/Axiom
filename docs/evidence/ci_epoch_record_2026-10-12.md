# CI Epoch Record — bsec-integrity required check 도입 (2026-10-12)

> §2.5 CI Epoch Cutover, 단계 1–2 (Freeze · Record) — **DRAFT**. 정본 규칙: `AGENTS.md` §2.5 / `docs/agents/ci_epoch_cutover.md`. 형식 선행 기록: `docs/evidence/ci_epoch_record_2026-10-04.md`.
>
> **이것은 초안이다.** freeze 태그는 이 기록의 작성 시점에 **생성되지 않았다**(생성은 본 기록을 소유한 메인 에이전트의 몫이며, 이름은 §1 표에 고정). ruleset 전이(Sf·S1)도 아직 실행되지 않았다 — 본 기록은 전이의 **롤백 기준선과 결속 대상**을 고정할 뿐이다. 본 기록이 소유한 구현 물건: `.github/workflows/bsec-integrity.yml`(신규) + `config/repository_surface.json` v77 등록.

## 1. Freeze (단계 1)

| 항목 | 값 |
|---|---|
| freeze tag (의도) | `ci-epoch-pre-bsec-integrity-2026-10-12` (annotated) — **미생성** |
| HEAD at drafting | `c3f1d9825e7b771843e0f392565484cbf5937a19` (`main`, 2026-10-12) |
| workstream branch | (이 기록을 소유하는 워크스트림 브랜치 — §2.1, `main` 아님) |
| 선행 freeze 태그 (참고) | `ci-epoch-pre-authority-structure-2026-10-04` 등 |

## 2. Record — required-check binding 상태 전이 (S0 → Sf → S1)

### 2.1 S0 — 현재 (cutover 이전; 2026-10-12 관측, 기계 검증)

```
gh api repos/Archright/Axiom/rulesets/20303214
```

| 항목 | 값 |
|---|---|
| ruleset | `20303214` (이름 `main`), enforcement `active` |
| `required_status_checks` | **단일: `admission-check`** (integration_id `15368` — 조직 필수 워크플로 admission-gate) |
| 병행 규칙 | `deletion` · `non_fast_forward` · `pull_request` · `merge_queue` (MERGE, ALLGREEN) |

### 2.2 Sf — 과도기 (temporary, 본 epoch 전용)

| 항목 | 값 |
|---|---|
| required checks | `admission-check` + **`merge-freeze-<unguessable-hex>`** (임시 — 생성 시 무작위 hex를 결합해 컨텍스트 문자열을 예측 불가로 한다. 모든 read-access 사용자가 ruleset을 열람할 수 있으므로 이름 자체가 비밀은 아니며, 목적은 캐주얼 스푸핑의 표면 축소다) |
| 목적 | bsec-integrity가 첫 실제 런에서 check-context를 보고하고 바인딩 준비를 마칠 때까지 큐 진입을 동결 |
| 예외 | **사전 승인된 전이 PR 1건** — freeze ruleset의 narrow `bypass_actors`로만 통과. 실측된 단일 유저 레시피: `{actor_id: 53123826, actor_type: "User", bypass_mode: "pull_request"}` (직접 push는 여전히 차단되는 실측 모드 — `docs/spec/merge_authority_integrity.md:148` V1). **후보 PR이 자기 자신에게 성공을 부여할 수 없다** — bypass_actors는 ruleset 플랫폼 상태이며 PR이 변경할 수 없다 |
| 큐 처리 | **drain 금지 → dequeue/cancel** (drain은 구 규칙으로 병합을 완료시킨다 — 공식 확인). M2 순서: 큐 취소 → pre-snapshot → 변경 → post-snapshot → 재개 |
| 롤백 | **freeze ruleset 제거** (S0로 복귀 — 부분 상태 혼합 없이 일관 세대 전환, §2.5) |

#### 2.2.1 스푸핑 잔여 리스크와 수습 (R1 실측, 2026-10-12)

- **공식 문서는 중복 check-run 이름의 해석(ANY/ALL/latest)을 정하지 않는다(UNCLEAR).** 확정된 것은 check-run과 commit-status 동명 시 "둘 다 pass"뿐이며, 중복 job 이름은 공식적으로 "ambiguous". `integration_id: 15368` 앱 핀은 **같은 앱(Actions) 내부의 스푸핑 워크플로를 걸러내지 못한다** (핀은 앱 단위, 워크플로 단위가 아님).
- **수습(근본)**: 저장소에는 이미 `docs/spec/merge_admission_controller.md:102`의 **workflow identity binding**이 있다 — *"check-run 이름만은 정체가 아니다 … workflow identity binding이 새 워크플로의 동명 스푸핑을 차단한다"* (`config/policy/merge_admission.json:5-12`의 `requiredValidations` = context + workflowId). `bsec-integrity`의 workflowId를 첫 실제 런에서 확보해 `requiredValidations`에 등록하면, ruleset 이름 매칭이 뚫려도 **admission-check 판정이 스푸프를 차단**한다. 이 등록은 trustSurface 정책 변경(= decision revision)이며 PR #318 선례대로 착지한다.
- **수습(운영)**: 창 최소화, `integration_id: 15368` 핀 유지, 종료 후 Rule Suites 사후 관측(`docs/spec/merge_authority_integrity.md:40` M5, 보존 ≈1일).
- **잔여 리스크(정직 기록)**: freeze 컨텍스트의 동명 스푸핑이 창 동안 성공할 가능성은 기계적으로 제로가 아니다. 위 수습 3층 + 사전 승인된 전이 PR 1건이라는 예외 범위 한정으로 잔여 리스크를 수용한다. 스푸핑 실측 프로브(`cas-probe-scratch` ruleset 선례, `refs/heads/probe/*` 전용)는 Phase 4에서 별도 프로브로 수행한다 — main에서 실험하지 않는다.

### 2.3 S1 — 최종

| 항목 | 값 |
|---|---|
| required checks | `admission-check` + **`bsec-integrity`** |
| 실행 정의 | `.github/workflows/bsec-integrity.yml` — 2-tree 실행 경계: trusted BASE verifier(`pull_request.base.sha \|\| merge_group.base.sha`에서 체크아웃한 트리가 유일하게 실행되는 프로그램; GATE A doctrine, `admission-check.yml:5-6`) + candidate-as-data(`github.sha`, 절대 실행 금지) + pinned subject `status-im/nim-toml-serialization@4aa8e2223649fc0837c490a4acfca7b8b1e756f9` |
| 실행 동사 | `replay.sh verify` → `replay.sh judge` 만. `run`은 트리 코드를 컴파일하므로 금지, `freshness`는 체크 계약 밖 |
| 권한 | workflow-level `permissions: contents: read` 단일; 전 actions full-commit-SHA pin(`actions/checkout@11d5960a…62 # v4` — 저장소 규약); 전 checkout `persist-credentials: false` |
| 런타임 | hosted `ubuntu-24.04` (jq 사전 설치). self-hosted axiom-ci 러너 금지 — jq 부재 실측(2026-09-08, axiom-ci runner-3; `admission-check.yml:492-493`) |
| check context | job id `bsec-integrity` (bare — job-level `name:` 없음. `name:`은 context 문자열을 바꿔 ruleset 결합을 무음으로 끊는다) |

### 2.4 Tombstone 노트

**아무것도 폐기되지 않았다 — 이것은 추가다.** tombstone 기록은 구현의 END를 기록한다(`docs/agents/ci_epoch_cutover.md`). 본 epoch는 기존 required check·워크플로·게이트를 은퇴시키지 않으며, tombstone 레코드는 존재하지 않는다. 유일하게 "끝나는" 것은 선행 상태 **S0**이며, 그 종료 시점은 본 cutover다. `admission-check`는 S1에서도 변함없이 required로 유지된다.

## 3. Open items — 미폐쇄 등록 (open register)

`AGENTS.md` §0.9: 기록되지 않은 지연은 아무도 찾지 않은 공백과 구별되지 않는다. 다음 두 항목은 본 epoch의 **열린** 작업이며, 닫히지 않았다.

1. **ruleset GraphQL Relay-ID PUT with pre/post snapshots.** ruleset 20303214의 `required_status_checks` 갱신은 REST PATCH가 아니라 GraphQL Relay-ID(`node id`) PUT 경로로 수행하고, 그 직전·직후 ruleset 스냅샷(§2.1 관측 명령 출력 전문)을 본 기록 부속 증거로 남긴다.
2. **정확한 check-context 문자열 확인.** ruleset 바인딩 전에 첫 실제 런(PR 또는 merge_group)에서 GitHub이 보고하는 check-run context 문자열을 관측해 고정한다. job id `bsec-integrity`를 기대하지만, 보고된 문자열이 규칙(ruleset 바인딩 값)과 일치하는지는 관측으로만 확정된다 — 기대 ≠ 결합.
3. **`requiredValidations` workflowId 등록 (스푸핑 수습, §2.2.1).** 첫 실제 런에서 `bsec-integrity` check-run의 **workflowId**를 확보해 `config/policy/merge_admission.json`의 `requiredValidations`에 context+workflowId 쌍으로 등록한다 — admission-check 판정이 새 워크플로의 동명 스푸핑을 차단하는 workflow identity binding 실현. 이 편집은 trustSurface 정책 변경이므로 PR #318 선례대로 일반 PR로 착지하되 Axiom auto-merge는 보류(MUST-T2 human manual merge).

### 3.1 인터페이스 의존 (병행 workstream)

`bsec/replay.sh`는 병행 workstream에서 `AXIOM_TARGET_TREE` 매개변수화가 진행 중이다(데이터 경로를 target tree로 해석; 스크립트는 자기 trusted 위치에서 실행). 워크플로는 그 인터페이스 기준으로 작성됐다. 2026-10-12 기준 `replay.sh`는 `SUBJECT_REPO`(`:113`)와 `AXIOM_LEDGER_BASE`(`:466`)는 이미 소비하지만 `AXIOM_TARGET_TREE`는 아직 보이지 않는다 — 매개변수화 착지 전까지 `REPO_ROOT`는 `BASH_SOURCE`(trusted 트리)에서 유도된다(`:102-104`). **워크플로 본문 PR은 이 의존이 착지한 뒤 착지해야 한다**(§2.5 단계 순서 유지).

## 4. 다음 단계

단계 1 Freeze(**태그 생성 미수행** — 메인 에이전트) · 단계 2 Record(본 문서) · 워크플로 본문 PR(§3.1 의존 후) · 첫 실제 런 → check-context 관측(§3 open item 2) · ruleset PUT + 스냅샷(§3 open item 1) → S1. 롤백 = §2.2 (freeze ruleset 제거).

## 5. 전환 실행 기록 (S0 → Sf → S1, 2026-10-12)

### 5.1 2단계 착지 (surface v78 choreography, 선례 v55–v77 준수)

| 단계 | PR | 판정 |
|---|---|---|
| 1단계 정책 선등록 | #777 `policy/surface-v78-bsec-integrity` (재번호: drafted v77 → v78, v77은 PR #771에 선착지 소진 — v64 선례) | surface FAIL/SURFACE_FORBIDDEN **위반 1건뿐**(의도된 자기승인 차단, v51) — JSON 공개 + advisory bypass 경로 push. 병합: admission-check green |
| 2단계 소비 본문 | #778 `followup/bsec-integrity-body` | v78 소비 후 surface **PASS**, 정상 push(bypass 불필요) — 워크플로·파라미터화·ADR·drift monitor·epoch 기록 착지 |
| 부속 | #776 `followup/debt-hygiene-504` | DEBT#504 + 기록 위생 (main 동기화 후 랜딩) |

첫 run 관측: check context = **`bsec-integrity`** (bare job id — epoch open item 2 해소). 첫 run은 BASE(main)의 파라미터화 이전 스크립트가 자기 트리를 검증해 FAIL(예정된 부트스트랩 상태, PR #778 코멘트로 기록). 본문 랜딩 후 PR #776에서 **첫 SUCCESS** — 부트스트랩 해소 실증.

### 5.2 Sf freeze (창: 바인딩 직전~직후)

- 생성: ruleset `bsec-cutover-freeze-Sf` (id **24912717**, active) — required_status_checks에 미보고 컨텍스트 `merge-freeze-8dbf8e9851d424920f11`(unguessable). **bypass 없음** — 전이 PR(본문)이 창 전에 이미 랜딩되어 예외가 불필요해짐(설계보다 엄격한 형태). 롤백 = ruleset 제거.
- 해제: 바인딩 직후 `DELETE /rulesets/24912717` — 창은 수 분. (dequeue 시도: GraphQL 스키마에 해당 뮤테이션 없음 — freeze가 큐 진입을 기계적으로 차단하는 것으로 충분했음.)

### 5.3 S1 바인딩 (단일 API — REST PUT, 혼용 없음)

- `PUT /repos/Archright/Axiom/rulesets/20303214` (숫자 ID, 전체 규칙 객체 치환 — Phase C 선례 `docs/evidence/merge_authority_integrity_2026-10-05.md`).
- required_status_checks: `admission-check` → `admission-check + bsec-integrity` (둘 다 integration_id 15368).
- **전후 스냅샷 대조(기계적 diff)**: 변경 = `rules[3].parameters.required_status_checks` (길이 1→2) + `updated_at` **뿐**. `bypass_actors=[]`, `conditions`, `pull_request` 전 파라미터, `merge_queue` 전 파라미터, `deletion`, `non_fast_forward` 전부 바이트 동일 보존.

### 5.4 스푸핑 수습 (워크플로 정체 바인딩)

`config/policy/merge_admission.json` v1.12.0: `requiredValidations`에 `bsec-integrity` (workflowId **381835906**, 최초 실제 run에서 관측) 등록 — 새 워크플로의 동명 스푸프를 admission-check 판정이 차단(`merge_admission_controller.md:102` workflow identity binding). trustSurface에 `bsec-integrity.yml` + `bsec/replay.sh` 추가 — 무단 수정은 auto-merge 거부 + base-sourced 2-tree 실행이 변조를 무효화.

### 5.5 잔여 리스크 (정직 기록)

freeze 창의 동명 스푸핑 가능성은 기계적 제로가 아니었다(공식 문서의 중복 context 해석 UNCLEAR). 수습 3층(unguessable context / 짧은 창 / workflow identity binding)으로 수용. 창 동안 미검사 병합 0건 — freeze가 전 병합을 기계적으로 차단.
