# GitHub Actions·merge-admission 관측 프로토콜 (절차)

AGENTS.md + docs/agents/는 하나의 논리적 SSOT이다. 헌법 surface(사실·불변식·canonical location)는 AGENTS.md가 정의하고, docs/agents는 operational protocol만 담는다 — 규칙의 정본은 AGENTS.md, 실행 방법의 정본은 각 프로토콜 문서다.

> **정본: AGENTS.md §2.3.** 제어 대상 상태/산출물당 선언된 authority 하나(adapter·reporter는 authority가 아님), merge-admission의 authority 원천, required checks 0건의 판정, 단일 관측층만으로 완료를 주장할 수 없다는 불변식은 모두 **AGENTS.md §2.3**이 정의한다. 이 문서는 그 판정을 수행하는 절차·adapter 명령·관측 사실만 담으며, 불변식을 재정의하거나 변경하지 않는다.

## §2.3 관측 프로토콜

에이전트는 권위 상태를 사람이 추측하지 않고 아래 절차에 따라 결정론적으로 관측·기록한다.

#### 관측 규칙 (mechanism)

1. **수동 판단 금지**: 권위 판정은 명시된 명령의 기계 판독 출력(JSON·exit code)으로만 내린다.
2. **관측 간격 ≥ 30s**: gh `--interval` 기본값 10s — API 트래픽을 가볍게 하기 위해 `--interval 30`을 항상 명시한다.
3. **hand-rolled polling 금지(프로젝트 정책)**: 손으로 만든 폴링 루프(`for`/`until` + `gh api`/`gh run list` + `sleep`), 추측한 시간 동안의 sleep, 완료를 기다리기 위한 job status 반복 조회는 금지다. 공식 근거: GitHub는 webhook 기반 구독을 권장하고 반복 폴링을 rate-limit best practice 위반으로 본다. 관측 재호출은 아래 "승인된 예외" 형태로만 한다.

#### 0 checks의 adapter 관측 사실

`gh pr checks --required`는 required checks 0건 시 "no required checks reported" 오류로 비0 종료한다(gh 2.45.0 실측·v2.45.0 소스) — adapter 수준에서도 SUCCESS 신호가 없다. 이 사실이 관측되는 **판정 의미(0건 = UNKNOWN / NOT READY)는 정본: AGENTS.md §2.3**.

#### 관측 3층 (Phase A → B → C)

merge-admission 관측은 L1 → L2 → L3 순서로 수행한다. 단일 관측층(L1)의 성공만으로 완료를 주장하지 않는다는 불변식의 정본은 **AGENTS.md §2.3**이다.

- **L1 — 선행조건·checks 층 (PR-head 투영)**

  **바인딩 기준의 정본**: run↔identity 바인딩과 validation identity의 정본은 `docs/spec/merge_admission_controller.md` §2b / §3이다("A check-run **name** alone is not identity"). 아래는 그것을 기계 판독하는 절차이며 기준을 재정의하거나 완화하지 않는다. 후보 head 선택은 이벤트 분기 폴백(`pull_request.head.sha || merge_group.head_sha || github.sha`, ADR-0027 P2)이고, 귀속 context(`pr-head | merge_group`)는 아래 증거 귀속 블록에 명시한다.

  **바인딩 어서션 5종 — 전부 통과해야 통과로 판정한다.** `name == "admission-check" ∧ conclusion == "success"` 한 쌍만 확인하는 것은 §3이 금지한 "check name is not identity"의 재발이다 — PR이 동명 워크플로를 스스로 정의할 수 있다. 관측 대상 질문은 하나다: **올바른 워크플로가, 올바른 커밋에 대해, 올바른 바인딩 아래 성공을 보고했는가.**

  | # | 어서션 | 관측 | 불합격 판정 |
  |---|---|---|---|
  | 1 | `workflow_id` 일치 | run 객체의 `workflow_id` ↔ `config/policy/merge_admission.json` `requiredValidations[].workflowId` | 불일치 = NOT READY (워크플로 삭제·재생성은 id를 바꾼다) |
  | 2 | `workflow_path` 일치 | run 객체의 `path` ↔ `requiredValidations[].workflowPath` (workflow_id + path **이중 바인딩**) | 불일치 = NOT READY |
  | 3 | `run.head_sha == <H>` (후보 커밋 SHA) | run 객체의 `head_sha` | 불일치 = NOT READY (다른 커밋의 성공을 이 PR의 성공으로 읽음) |
  | 4 | 트리 **독립 재도출** — `GET /commits/<H>` → `commit.tree.sha == candidateTreeDigest` | §2b "Logical ≠ Materialized": **같은 API 재호출은 독립 재도출이 아니다** — 코드 경로와 데이터 소스가 둘 다 달라야 한다 | 불일치 = NOT READY. `head_sha`만으로는 **커밋**을 증명할 뿐 **의도한 트리**를 증명하지 않는다(§2b) |
  | 5 | `conclusion == "success"` **정확히** — `skipped`/`neutral`/`cancelled`/`failure`/`timed_out`, 그리고 미완료(`status != "completed"`)는 불합격 | attempt-pinned 잡 결론 (`/runs/{id}/attempts/{attempt}/jobs`); 적용 가능 잡 0개 또는 2개 이상 = 모호 | 불합격 = NOT READY; 모호한 잡은 `AMBIGUOUS_VALIDATION`으로 deny |

  - **값의 정본은 정책이다**: 위 1·2의 `workflowId`/`workflowPath`/허용 결론은 `config/policy/merge_admission.json`에서 읽어 대조한다 — 본 문서는 이 값의 정본이 아니다(§0.2 Fundamental: 하드코딩 예외 없음).
  - **상태 판정(기계)**: 위 5종을 JSON으로 판정하고, `gh api repos/<owner>/<repo>/rulesets/<id>`의 required_status_checks 컨텍스트와 교차 확인한다. (gh 2.45.0 실측: `gh pr checks`는 `--json` 미지원 — JSON 기계 판정은 REST 층이 담당한다, 각주 ④)
  - **적용 가능 run·attempt 선정(2단계)**: `ApplicableRun(H, workflow)` = `(workflow_id, H, event)`에 대한 **최신** run(전체 페이지 순회, `created_at` max + `id` 동률 타임브레이크 — 목록 기본 정렬은 신뢰하지 않는다) → `ApplicableAttempt` = 그 run의 `run_attempt`. 이전 attempt의 성공은 더 최신 attempt가 있으면 유효하지 않다(§4).
  - **adapter 보조 관측**: `gh pr checks <PR> --required`의 텍스트 행에 admission-check가 나타나고 bucket이 `pass`인지 확인한다 — 행 부재·버킷 비pass = NOT READY. 보조이므로 위 5종 판정을 대체하지 않는다.
  - **완료 대기**: `gh pr checks <PR> --required --watch --interval 30` → exit 0(0=성공은 관측 실측 확정; 비0 = 실패·pending). 특정 run 객체 관측의 정식 어댑터는 `gh run watch`다(아래 adapter 층 — `--exit-status --interval 30`).
- **L2 — 결정 층·큐 상태 머신**: `gh api graphql -f query='query{repository(owner:"Archright",name:"Axiom"){mergeQueue{entries(first:5){nodes{state position pullRequest{number}}}}}}'` → entry state(`AWAITING_CHECKS`/`QUEUED`/`IMMUTABLE`/…)를 관측한다.
- **L3 — 종결**: `gh pr view <PR> --json state,mergedAt,mergeCommit` → `state=="MERGED"` ∧ `mergeCommit.oid` 존재(REST의 merged/merge_commit_sha 대응).
- **L2-R — readiness·원인 판독 층 (L2와 L3 사이)**

  **정체**: L2가 "큐에 어디까지 들어와 있나"를, L3가 "착지했나"를 보는 것과 별개로 **"착지가 왜 안 되나"를 사실로 말하는 층**이다. L2-R은 L1의 어서션 5종과 L2의 큐 관측을 **대체하지 않으며**, 단일 관측층만으로 완료를 주장할 수 없다는 불변식의 정본은 여전히 **AGENTS.md §2.3**이다.

  **authority-per-fact — 사실마다 권위 하나**:

  | 사실 | 권위 신호 | 성격 |
  |---|---|---|
  | required / non-required | GraphQL `CheckRun.isRequired(pullRequestNumber:)` | 판정 근거의 **유일** 해석자 — 체크 이름 유사성·워크플로 존재·`gh pr checks` 롤업은 근거가 아니다 |
  | required check 결론 | L1의 attempt-pinned job conclusion(위 5종 표 #5) | 실행 결과 |
  | merge 가능/불가 | PR `mergeStateStatus` | **verdict** — reason 필드가 없다 |
  | 큐 진입 여부 | PR `isInMergeQueue` · `mergeQueueEntry` | 상태 |
  | 큐 항목 상태 | GraphQL `mergeQueue{entries}` (L2) | 상태 |
  | **왜 ref 갱신이 거절됐나** | REST `GET /repos/<o>/<r>/rulesets/rule-suites[/{rule_suite_id}]` → `rule_evaluations[]`의 `rule_type`·`result`·**`details`** | **사유의 유일 권위** |
  | 규칙 구성 | `GET /rulesets` · `GET /rulesets/{id}` · `GET /rules/branches/{b}` | 현재 구성(드리프트 감지 대상) |

  - **결과와 사유를 같은 말로 쓰지 않는다**: `mergeStateStatus`는 `BLOCKED` 같은 **판정(verdict)** 만 준다 — 어떤 규칙이·무엇 때문에 막혔는지 담지 않는다. 2026-10-05 사고의 `{rule_type:"update", result:"fail", details:"Cannot update this protected ref."}` 는 rule suite 판독으로만 진술 가능하다. 따라서 **사유 필드를 못 읽으면 blocker 이름을 정할 수 없다 → `UNKNOWN`**(아래 어휘).
  - **보존 기간 짧음**: rule suites retention은 약 1일 — 착지 직후 수집하지 않으면 "왜였나"는 소실된다. 소실 후의 사유 재구성은 금지(재구성한 서사는 관측이 아니다).
  - **`isRequired`는 이름이 아니라 정본이다**: L1의 어서션 #1-#2가 증명한 `workflow_id`/`workflow_path` 이중 바인딩과 짝을 이룬다 — 어떤 체크가 required인지의 해석자는 오직 이 필드다. CLI 텍스트 행은 보조 관측이며 판정을 대체하지 않는다.

  **판정 어휘 (닫힌 집합)**:

  **제어 계열(control)** — watcher 제어 출력은 아래 6 상태만 사용한다. 각 상태의 기계 조건·행동의 유일 권위는 아래 **Liveness state machine** 표이며, 이 표는 어휘 요약일 뿐 조건을 재정의하지 않는다:

  | 제어 상태 | 성격 |
  |---|---|
  | `SUCCESS` | 착지 확정 — 관측 종료 |
  | `FAIL` | 관측된 blocker — 정지, evidence-kind = `OBSERVED_BLOCKER` |
  | `RECOMPUTING` | GitHub 재계산 — 동일 head SHA 재관측 1회만 허용 |
  | `LANDING_PENDING_ENQUEUE` | arm 완료·큐 미편입 — 지연 재관측 1회만 허용 |
  | `WAIT` | 진행 증거 + identity 변동이 있을 때만 성립하는 **조건부 권한** |
  | `UNKNOWN` | FAIL CLOSED — 재관측 라운드로 연장하지 않는다 |

  **사유 계열(reason · evidence-kind 속성)** — `BLOCKED_BY_*`는 제어 판정에서 제외되며 `FAIL`/`UNKNOWN` 관측에 붙는 속성으로 유지된다:

  | 사유 속성 | 조건 |
  |---|---|
  | `BLOCKED_BY_REQUIRED_CHECK` | `isRequired == true`인 check 중 미충족(미완료·실패)이 있음 |
  | `BLOCKED_BY_REVIEW` | 리뷰·승인 요구가 충족되지 않음 |
  | `BLOCKED_BY_AUTHORITY` | 주체 권한 부족 — `rule_evaluations`에서 권한·권위 규칙이 fail |
  | `BLOCKED_BY_QUEUE` | 큐 상태·큐 정책이 착지를 막음(entry 상태 또는 큐 규칙) |

  - **원인을 모르면 UNKNOWN; 추측 금지.** 그럴듯한 서사를 골라 blocker 이름으로 채우지 않는다. `BLOCKED_BY_*` 네 값 중 하나는 **관측 사실이 뒷받침할 때만** 붙인다 — 근거 없는 blocker 이름은 `UNKNOWN`과 같고, 기록상 `UNKNOWN`이 정직하다(AGENTS.md §4 검증 불가 = fail closed).
  - **0 signals의 판정 의미는 정본: AGENTS.md §2.3** — required checks 0건은 SUCCESS로 해석하지 않는다.

  **진단은 GET만**: L2-R의 모든 호출은 REST GET / GraphQL **query**다. 진단 identity는 진단 대상(GitHub ruleset · merge queue · merge state)을 **mutate하지 않는다**. 정본: [docs/spec/merge_authority_integrity.md](../spec/merge_authority_integrity.md) §4(M7 · 진단 순수성).

#### Liveness state machine (fail-closed — WAIT는 조건부 권한)

L1·L2·L3·L2-R의 관측값을 한 라운드마다 아래 표 **위에서부터 순서대로 평가**해 첫 일치 판정을 취한다. 두 실측 사고(2026-10-05: ~49분 `queue=[empty] pr=[OPEN - -]` 정체 루프, PR #482 armed·전체 SUCCESS·큐 EMPTY BLOCKED 지속)가 증명한 것은 **불확실을 대기로 위장하면 안 된다**는 것이다 — 대기도 판정이며, 근거 없는 대기는 무한 후퇴다. 실측 근거: [docs/evidence/pr_liveness_fail_closed_2026-10-05.md](../evidence/pr_liveness_fail_closed_2026-10-05.md).

| 우선순위 | 판정 | 기계 조건 | 행동 |
|---|---|---|---|
| 1 | `SUCCESS` | GraphQL `state==MERGED` (또는 REST `closed`∧`merged`) ∧ `mergedAt` ∧ `mergeCommit.oid`; MERGE 방법이면 merge commit parent 수 2 부가 검증. **`merge_commit_sha` 단독 금지** — 병합 전 test merge commit으로 non-null이 될 수 있다(GitHub 공식 문서) | 정지 — 관측 종료 |
| 2 | `FAIL` | 필수 context conclusion ∈ {failure, timed_out, cancelled, action_required} ∪ DIRTY ∪ 필수 리뷰 CHANGES_REQUESTED ∪ strict 정책 하의 BEHIND — 이 저장소는 `strict_required_status_checks_policy: true`(`config/policy/merge_admission.json` v1.8.0)다 *(원안 — superseded 2026-10-11: 라이브 ruleset 20303214 실측은 `strict_required_status_checks_policy: false` + 활성 `merge_queue` 규칙이다 — 아래 갱신 노트)* | 정지, evidence-kind = `OBSERVED_BLOCKER` |
| 3 | `RECOMPUTING` | `mergeable==null` ∨ `mergeStateStatus==UNKNOWN` — GitHub-UNKNOWN ≠ monitor-UNKNOWN | 같은 head SHA로 재관측 1회만 허용; 그 뒤에도 동일하면 `UNKNOWN` |
| 4 | `LANDING_PENDING_ENQUEUE` | `autoMergeRequest` 존재 ∧ 필수 전부 충족 ∧ 큐 entry 없음 — **armed 단독은 진행 증거가 아니다**(PR #482 실측: arm 이후 BLOCKED 지속, 사유는 읽기 API 어디에도 없었다) | 지연 재관측 1회만; 그 뒤에도 entry 없으면 `UNKNOWN` |
| 5 | `WAIT` | **진행 증거 존재 ∧ 그 identity가 직전 관측 대비 변동** — check run status ∈ {queued, in_progress, waiting, requested, pending} / workflow run status ∈ {queued, in_progress, requested, waiting, pending} / combined status pending("Waiting for status to be reported") / 큐 entry state·position 변동 / (suite queued ∧ run conclusion=failure → 재시행 중). identity 무변동이면 WAIT 권한 없다 | 대기 재개 가능; 증거별 age 상한(GitHub 작성 타임스탬프 기준) 초과 → `STALE_EVIDENCE` → `UNKNOWN`. wall-clock timeout은 보조 수단일 뿐 판정 근거가 아니다 |
| 6 | `UNKNOWN` | 위 어느 판정의 근거도 없음 (권한 부족 미관측, retention 소실, API 실패, 신호 부재) | **FAIL CLOSED — 정지**, 마지막 raw facts를 출력하고 제어권을 반환한다. 라운드 1회로 끝내며 재관측 루프로 정지를 연장하지 않는다. evidence-kind = `NO_SIGNAL_YET` / `REASON_UNAVAILABLE` / `STALE_EVIDENCE` |

**갱신 (2026-10-11 — 위 행 2의 `strict: true` 단언은 superseded)**: 라이브 main ruleset(20303214) 재실측(`gh api repos/Archright/Axiom/rulesets/20303214` — `enforcement: active`) 결과 `strict_required_status_checks_policy: false` + 활성 `merge_queue` 규칙(grouping ALLGREEN · merge_method MERGE · max_entries_to_build 2)이다 — ADR-0027 P5(operator 승인 2026-10-05)의 `strict=false` 라이브 전환이 착지한 것이며, 원안의 `true`(v1.8.0 시점)는 전환 이전의 역사 기록이다. 현행에서 main 착지 경로의 freshness는 큐 무효화 의미론으로 집행되므로 "strict 정책 하의 BEHIND" 차단 사유는 이 저장소의 현재 구성에서 발화하지 않는다. 정본: [docs/spec/github_delegation_residuals.md](../spec/github_delegation_residuals.md) R2(2026-10-11 실측 기록) · [docs/adr/0027-queue-delegation.md](../adr/0027-queue-delegation.md) §P5.

**`evidence-kind` 속성 (닫힌 집합)** — 관측 기록에 근거의 성격을 명시한다: `OBSERVED_BLOCKER` · `LANDING_IN_FLIGHT` · `RECOMPUTING` · `NO_SIGNAL_YET` · `REASON_UNAVAILABLE` · `STALE_EVIDENCE`. 사유 필드를 못 읽으면(Case B — `mergeStateStatus`는 reason 없는 verdict, rule-suite는 ref-update **시도**만 기록, 사유 노출의 유일 경로는 write-path 에러 — 큐 진입 변이 mutation의 거부 응답 "Pull request Cannot update this protected ref."([증거 E1-b](../evidence/merge_authority_integrity_2026-10-05.md))) `REASON_UNAVAILABLE`이며 blocker 이름은 정하지 않는다 — 위 L2-R의 "결과와 사유를 같은 말로 쓰지 않는다" 불변식(M5)과 동일하다.

**Legacy 매핑** — 레거시 `READY`/`NOT_READY`는 watcher **제어 출력에서 폐기**된다: `READY` → 진행 증거 존재(WAIT 가능), `NOT_READY` → `FAIL`(`OBSERVED_BLOCKER`) 또는 `UNKNOWN`(evidence-kind로 구분), `UNKNOWN` → `UNKNOWN`(FAIL CLOSED). AGENTS.md §2.3의 레거시 문구는 §-1(에이전트 수정 제한)에 따라 **frozen으로 유지**되며, 본 매핑은 그 해석 계층일 뿐 정본을 개정하지 않는다.

**불변식 — monitor의 GitHub write 호출 = 0**: 관측 명령 인벤토리는 REST GET / GraphQL **query**만 포함하며, `tools/ci/monitor_purity_scan.sh`(`make check-monitor-purity`)가 이 표면을 정적으로 검증한다(2026-10-05 실측: `files=3 violations=0` exit 0 + negative FAIL 확인). 정직 기록(§0.9): 이 스캔은 명령 **표면의 정적 검증**일 뿐 호출 토큰의 write 권한을 강제하지 않는다(Tier 0 — [docs/spec/merge_authority_integrity.md](../spec/merge_authority_integrity.md) §6). auto-merge arm은 **operator 행위**(명령의 정본: [rules_workflow.md](rules_workflow.md) §Auto-Merge Default Policy · [operations.md](operations.md))로 본 문서의 관측 명령 인벤토리에 포함하지 않는다.

**Evidence-identity liveness** — WAIT는 상태가 아니라 **조건부 권한**이다. "기다려도 된다"는 사실 자체를 GitHub authority가 증명해야 하며, 동일 증거의 반복은 새 권한을 발급하지 않는다 — ~49분 동안 같은 `queue=[empty] pr=[OPEN - -]`를 반복 관측한 루프는 진행을 증명한 것이 아니라 권한 없이 대기를 연장한 것이다.

#### adapter 층 — 특정 run의 직접 관측

GitHub Actions 런을 완료까지 관측해야 할 때 — push 후, `gh run rerun`, `gh workflow run`, CI 상태 확인, 완료된 런의 로그/타이밍이 필요한 모든 측정 — 에이전트는 `gh run watch`를 사용한다:

```bash
gh run watch <RUN_ID> --exit-status --interval 30
```

- `gh run watch`는 PR required check 관측의 하위 어댑터가 아니라 **특정 run·merge_group run 등 별도 관심 객체의 관측 도구**다(공식 문서에 강등 분류가 없다). 같은 워크플로 실행도 PR-head 컨텍스트와 merge_group 컨텍스트를 구분 귀속한다.
- `--exit-status`는 런 결론을 종료 코드로 전파한다; 0이 아니면 실패한 런으로 취급한다(로그를 읽고, 맹목적으로 재관측하지 않는다).
- `--interval`은 ≥ 30s여야 한다(기본값 3s — `--interval 30` 명시 필수).
- 긴 런은 예상 벽시계 시간을 커버하는 타임아웃으로 백그라운드 작업으로 실행한다.

**금지**: 손으로 만든 폴링 루프(`for`/`until` + `gh api`/`gh run list` + `sleep`), 추측한 시간 동안의 sleep, 완료를 기다리기 위한 job status 반복 조회.

**승인된 예외만**:

1. 런 객체가 아직 생성되지 않음(jobs 목록 비어 있음): 런이 나타나거나 `in_progress`가 될 때까지 `.status`를 ≥30s 간격으로 재관측하고, 즉시 `gh run watch`로 전환한다. 이 부트스트랩을 전체 완료 루프로 확장하지 않는다.
2. `gh`를 사용할 수 없음.

로그/아티팩트 취득은 완료 후 `gh run view --log` / `gh run download` 사용 — 아직 진행 중인 런을 절대 tail하지 않는다.

#### REST 교차검증 층 (판정 보조)

adapter 출력과 플랫폼 상태가 어긋날 의심이 있을 때(#14253 클래스 — CLI check-rollup이 실패 체크를 누락하고 SUCCESS를 오보고한 선례) REST로 교차 검증한다: `gh api .../actions/runs/<id>` + `commits/<head_sha>/check-runs` + `jobs`/`logs` 1세트(read-only). 판정 루프를 대체하지 않는다.

#### 증거 귀속 블록 (모든 관측 기록 필수)

모든 관측 기록에 다음을 붙인다: `PR number / head SHA / timestamp(UTC) / 관측 원문(JSON) / REST check-runs 관측 / L1 바인딩 5종 관측값(workflow_id · path · head_sha · commit.tree.sha · attempt-pinned job conclusion) / context = pr-head | merge_group 명시` — merge queue의 merge_group 컨텍스트와 PR-head 컨텍스트의 **구분 귀속**을 위함이며, 동시에 L1의 어느 어서션이 관측되었는지 **감사 가능하게** 하기 위한 최소 기록이다.

#### adapter 한계 각주 (정직 기록)

- **① cli/cli #9228(OPEN)**: 조직 ruleset으로 정의된 workflow의 run은 `gh run list`·`gh run view`/watch가 404 — 조직 규칙 기반 실행은 PR 체크 롤업·REST로 관측한다.
- **② cli/cli #7401(CLOSED)**: "no checks" race(checks 등장 전 `gh pr checks --watch` 동작 이슈) — 위 0 checks adapter 관측 사실이 대응하며, 판정 의미는 **정본: AGENTS.md §2.3**.
- **③ cli/cli #14253(CLOSED)**: REST↔CLI check-rollup 불일치(실패 체크 누락·statusCheckRollup SUCCESS 오보고) — REST 교차검증 층이 대응한다.
- **④ gh 2.45.0 실측**: `gh pr checks`는 `--json` 미지원(`unknown flag`) — JSON 기계 판정은 REST 층이 담당한다.

새 정본이 이 문제들을 "모두 해결"한다고 주장하지 않는다 — adapter 한계는 GitHub 플랫폼 상태의 투영이라는 구조적 사실에 근거해 정직하게 기록한다.

#### 부록 — merge_group 관측 어댑터 · CLEAN 마스킹 실패 모드 · failure→recovery 절차 (2026-10-06 사고)

2026-10-06 PR #498 착지 대기 사고가 드러낸 계약 gap 4건 — ① merge_group run discovery 명령 미커밋 ② "CLEAN이 merge_group 실패를 가림" 미기록 ③ merge_group context FAIL semantics 미정의 ④ failure→recovery 절차 부재 — 를 닫는 부록이다. 기존 절을 개정하지 않으며, 불변식의 정본은 여전히 **AGENTS.md §2.3**이다.

**(a) merge_group 관측 어댑터 (discovery — 본문에 없던 표면)**

merge_group run은 PR head sha가 아니라 **queue merge commit**(`gh-readonly-queue/main/pr-<N>-<baseSha>` 브랜치)에서 실행된다. `gh pr checks`와 GraphQL `statusCheckRollup`는 **PR head sha에만 결속**하므로 큐 phase를 절대 관측하지 못한다(아래 (d)). 큐 entry 상태와 admission run 발견:

```bash
# 큐 entry 상태 — dequeue 후 mergeQueueEntry == null ("큐에 없음"의 authority 신호)
gh api graphql -f query='query{repository(owner:"Archright",name:"Axiom"){pullRequest(number:<N>){state mergedAt mergeCommit{oid} isInMergeQueue mergeQueueEntry{state position headCommit{oid}}}}}'

# merge_group admission run 발견 — head_branch 정규식 또는 group-commit head_sha로
gh api "/repos/Archright/Axiom/actions/runs?event=merge_group&per_page=30" \
  --jq '.workflow_runs[] | select(.head_branch | test("^gh-readonly-queue/main/pr-<N>-"))'
gh api "/repos/Archright/Axiom/actions/runs?event=merge_group&head_sha=<group-commit-sha>"
```

- `head_branch` 형식 `gh-readonly-queue/main/pr-<N>-<baseSha>`는 **2026-10-06 실측 상수**다(GitHub 공식 문서에 문서화되지 않은 값 — 관측 어댑터 전용으로 사용한다).
- 한 entry에 복수 워크플로가 실행된다(2026-10-06 실측: `admission-gate` · `landing-integrity` · `probe-merge-queue`). admission 판정 귀속은 **admission-gate** run이며, 워크플로별 **최신 run**만 유효하다(§4 — 최신 attempt만 유효; run number는 truth identity가 아니다).
- 1-pass 관측기: `tools/ci/landing_observe.sh <N>` — 위 어댑터 + L3 종결(merge commit parents=2 포함) + `gh pr view` 교차검증을 GET-only 단일 패스로 수행하고 닫힌 4-verdict(`TERMINAL_SUCCESS`/`TERMINAL_FAIL`/`PROGRESSING`/`UNKNOWN`, exit 0/1/2/3)을 출력한다. 어휘 매핑: `TERMINAL_SUCCESS→SUCCESS`, `TERMINAL_FAIL→FAIL(OBSERVED_BLOCKER)`, `PROGRESSING→WAIT`(identity 변동 증거 충족 시만), `UNKNOWN→UNKNOWN`(FAIL CLOSED). 출력은 **advisory evidence**다 — authority는 바인딩된 admission run + MERGE commit이다.

**(b) 기록된 실패 모드 — CLEAN이 merge_group 실패를 마스킹한다 + merge_group context FAIL semantics**

2026-10-06 PR #498 실측 타임라인:

| 시각(UTC) | 관측 |
|---|---|
| 07:19:27 | merge_group entry 실행 개시(`gh-readonly-queue/main/pr-498-b2a979b…`): admission-gate run `37428943334` · landing-integrity `37428942844` · probe-merge-queue `37428942860` |
| 07:32:59 | admission-gate run `37428943334` → **failure** |
| 07:33:24 | `github-merge-queue[bot]` **auto-dequeue** — `mergeQueueEntry` → null |
| 07:31–08:05 | 대기 루프의 `mergeStateStatus` 관측은 **OPEN/CLEAN 동일 값 68회** — 종료 조건 불성립, 46분 무진행 순회 후 종료 |

기계적 원인: `mergeStateStatus`는 merge-ability **verdict** 전용(위 authority-per-fact 표)이며, merge_group 실패는 이 필드에 **전혀 투영되지 않는다** — dequeue는 merge-ability를 바꾸지 않으므로 PR은 CLEAN을 유지한다. 마스킹 서명: **`mergeStateStatus=CLEAN` + `mergeQueueEntry=null` + 최근 merge_group admission-gate failure run**. 같은 날 관측기 검증(#498, GET-only)에서 `statusCheckRollup.state=SUCCESS`·`mergeStateStatus=CLEAN`이 실패한 admission run과 **공존**함을 확인했다 — PR 요약 표면 전체가 merge_group 실패를 가릴 수 있다.

**merge_group context FAIL semantics(③의 정의)**:

- **merge_group context FAIL** = 해당 entry(`head_branch` 정규식 또는 group-commit `head_sha`로 바인딩)의 **admission-gate run conclusion ∈ {failure, cancelled, timed_out}**. 미완료(`status != "completed"`)는 FAIL이 아니라 진행 신호 또는 UNKNOWN이다.
- **pr-head context FAIL** = 위 L1 바인딩 어서션 5종의 conclusion 불합격(기존 FAIL 행의 필수 context conclusion과 동일).
- 어느 context든 FAIL이면 **정지 · `OBSERVED_BLOCKER`**다. **`mergeStateStatus=CLEAN`은 이 FAIL을 무효화하지 않으며, 성공·진행의 증거도 아니다** — verdict에는 reason이 없고 큐 phase를 보지 못한다(위 (a)).
- 어휘 확장 없음: 6-state 제어 어휘와 evidence-kind 닫힌 집합은 위 표 그대로다. 이 절은 FAIL의 **관측 귀속 규칙**을 정의할 뿐이다.

**(c) failure→recovery 유한 절차 (bounded)**

1. **진단(GET만)**: `gh api /repos/Archright/Axiom/actions/runs/<run_id>/jobs` → 실패 job 식별 → **완료된** run의 로그 취득. 원인은 사실로 기록한다(추측 서사 금지 — 위 "결과와 사유를 같은 말로 쓰지 않는다").
2. **수정**: 결함을 고치는 새 커밋을 PR에 반영한다(head identity 변화 = 재판정 대상).
3. **재-enqueue — operator 행위**:

<!-- monitor-purity:begin -->
   `gh pr merge <N> --auto` — 큐 편입 권위는 GitHub에 있다(auto-merge arm과 동일한 operator act로, 본 문서의 관측 명령 인벤토리 밖이다).
   **`gh run rerun <run_id>`는 재-enqueue가 아니다**: 죽은 큐 브랜치(`gh-readonly-queue/…`) 위 job의 재실행일 뿐 PR을 큐에 다시 세우지 않는다 — dequeue된 entry의 유일한 복귀 경로는 위 재-enqueue다.
<!-- monitor-purity:end -->

4. **회차 관측**: (a) 어댑터 + 위 Liveness state machine으로 단일 패스씩 수행한다. UNKNOWN → 정지·보고 — 무한 대기 금지 불변은 회차 관측에서도 변함없다.

**(d) 어댑터 한계 추가 기록 (정직 기록 — 각주 ①의 근원 클래스)**

- **`gh run watch`와 `gh run view`는 조직 호스팅 재사용 워크플로(org reusable workflow) run에서 HTTP 404**(2026-10-06 실측 — admission-gate merge_group run `37428943334`). 근원: cli/cli `shared.GetRun`이 run 객체의 workflow id를 현재 저장소의 워크플로로 **재해석(re-resolution)** 하므로 org 소유 워크플로 id가 매칭되지 않는다(위 각주 ① cli/cli #9228이 바로 이 클래스다). **동작하는 어댑터는 raw REST다**: `gh api /repos/<o>/<r>/actions/runs/<id>`(+`/jobs`; 로그 취득은 완료 후). 위 "adapter 층"의 `gh run watch` 처방은 **저장소 로컬 워크플로 run에 한정**된다 — 한계 기록이지 처방 폐기가 아니다.
- **`gh pr checks`(`--watch` 포함)와 GraphQL `statusCheckRollup`는 merge_group phase를 관측할 수 없다** — PR head sha 결속(위 (a)). 큐 phase의 유일한 관측 경로는 (a)의 merge_group run discovery다.

<!-- Extracted from AGENTS.md §2.3 to keep AGENTS.md under the context-size threshold. -->

#### 부록 — 2026-10-12/13 사고: stale-B 치유 표준 사이클 · dequeue→auto-merge 소멸 실측 · 고아 루프 점검 (2026-10-13)

기존 절을 개정하지 않으며, 불변식의 정본은 여전히 AGENTS.md §2.3이다. 본 부록은 2026-10-12/13 PR #787 착지 사고(4단계 수동 개입)에서 실측된 사실과 그로부터 도출된 운영 절차를 기록한다.

**(a) stale-B 치유 표준 사이클 (유한 절차)** — 2026-10-12 #787에서 PR venue preflight가 낡은 이벤트 페이로드 base(payload lazy refresh — 플랫폼 미문서)로 CANDIDATE_TREE_MISMATCH를 발화한 사건의 표준 치유 절차:
1. 진단(GET만): `tools/ci/landing_observe.sh <N>` + `gh api graphql -f query='…pullRequest(number:N){isInMergeQueue mergeQueueEntry{state position headCommit{oid}}…}'` — 실패 run의 job/step과 저널 코드를 사실로 기록(추측 금지).
2. baseRefOid 갱신 대기 관측: `gh api repos/Archright/Axiom/pulls/<N> --jq .base.sha` 와 `gh api repos/Archright/Axiom/git/ref/heads/main --jq .object.sha` 가 일치할 때까지 관측(간격 ≥30s, sleep ≤300s).
3. 빈 커밋 synchronize retrigger — 승인된 유일한 base 스냅샷 리프레시 수단(gh_run_observation_quirks Q5/Q6). raw rebase 금지(HARD RULE — 2026-10-12 외부 행위자 rebase가 이 절차를 위반했음); 브랜치 동기화가 필요하면 `ax git sync` 만.
4. 재arm — operator 행위:
<!-- monitor-purity:begin -->
   `gh pr merge <N> --auto --match-head-commit <headSha>` (monitor-purity 인벤토리 밖; 본 문서의 관측 명령이 아님).
<!-- monitor-purity:end -->
5. 종결 관측: `landing_observe.sh <N>` 닫힌 4-verdict(TERMINAL_SUCCESS/…)로 종결. 각 단계 실패 시 정지·보고.
#787 실측: CANDIDATE_TREE_MISMATCH(job 115057032653) → (위반 rebase 경유 — 3절) preflight PASS(run 38324149322) → merge_group ROT_ALLOWLIST(run 38324839465) → diff 수정(c0c1cec5) → 재큐 → MERGED(31fb3e50, 2026-10-13 00:44:50Z, 정상 merge queue 경로).

**(b) dequeue→auto-merge 소멸 실측** — #787에서 merge_group 실패(ROT_ALLOWLIST) 직후 github-merge-queue[bot]의 자동 dequeue가 관측되었고, 이후 auto-merge가 소멸하여 수동 재arm이 필요했다. GitHub 공식 문서의 auto-merge 취소 조건은 3종뿐(무권한 push, base 브랜치 전환, 수동 disable) — dequeue로 인한 소멸은 미문서 플랫폼 동작이며 본 실측이 계약 근거다. 플랫폼 자동 재enqueue 기능도 부재(큐는 남은 entry의 그룹 재구성만 수행) — dequeue된 PR의 재진입은 operator 재arm이 유일 경로(기존 (c) 절과 정합).

**(c) 고아 루프 금지 + 세션 재개 점검 프로토콜** — 세션(agent·백그라운드 태스크)은 executor일 뿐 owner가 아니다(AGENTS.md §2.7 — 소유권 프로토콜 부재가 정책). 세션 재개 시: (i) 잔여 백그라운드 태스크 점검, (ii) 원격 브랜치 head가 마지막 관측과 불일치하거나 미지원 커밋이 발견되면 정지·보고 — 절대 자동 rebase/force 경로 금지. 동기: 2026-10-12 외부 행위자(재부팅 후 이전 세션 권한 승계 추정)가 대상 브랜치를 rebase+push하여 raw rebase 금지(HARD RULE)를 위반했다. 기계적 backstop은 GitHub ruleset뿐(로컬 deny는 kimi -p 모드에서 작동하지 않음 — operations.md 실측)이므로, 이 점검은 운영 계약으로서 시행한다.

**(d) org-ruleset 런 관측 경로 재확인** — org required workflow 런은 run-id 폴링 불가(cli/cli#9228: gh run view 404). 정식 경로는 기존 (a) 어댑터와 동일(`landing_observe.sh` + REST `actions/runs?event=merge_group` 필터) — 본 사건 조사에서도 재확인되었다.

**(e) 실전 재arm 사이클 (2026-10-13 #805)** — 위 (a)의 문서화된 치유 사이클이 전투(combat) 실행에서 발동된 실측 기록. Stage 2 cutover의 첫 수용 merge_group 런이 조직 게이트 측 회귀(PR 내용 아님 — `docs/spec/gh_run_observation_quirks.md` Q10: gateway transitive-skip → mint-publish MINT_PUB_TREE, run 38359095521)로 실패하자 github-merge-queue[bot]이 자동 dequeue했고 auto-merge는 소멸했다(위 (b)의 미문서 동작 재실측). org 수정 착지(Archright/.github #197, `4a81d18a`, 07:16:42Z) 후 operator가 단계 ④만 수행했다:

<!-- monitor-purity:begin -->
   `gh pr merge 805 --auto --match-head-commit c872e28ac…` (관측 명령 인벤토리 밖 operator 행위 — 본 문서가 실행하지 않는다).
<!-- monitor-purity:end -->

   큐 재진입 07:17:05Z(`auto_merge_enabled` 이벤트) → MERGED 07:58:53Z (`12ab65d4`, parents=2, admission-verdict 아티팩트 존재, error 애노테이션 0건, `landing_observe` TERMINAL_SUCCESS).

- **단계 ②·③ 불요(원인 클래스에 따른 선택 적용)**: baseRefOid 갱신 대기와 빈 커밋 synchronize retrigger는 수행되지 않았다 — 실패 원인이 base staleness가 아니라 venue-gate 측 회귀였기 때문이다. (a) 사이클의 ②·③은 base 이동이 원인인 경우에만 적용한다.
- **autoMergeRequest 필드 불신뢰 정정**: 재arm된 live 큐 entry의 전 수명에서 GraphQL `autoMergeRequest`/REST `auto_merge`는 null 판독(07:18Z 이후 매 관측, 병합 후까지 — `docs/spec/gh_run_observation_quirks.md` Q9). 위 (b)의 "dequeue→auto-merge 소멸" 실측은 유효하되, 소멸·생존의 관측 신호는 autoMergeRequest 필드가 아니라 GraphQL `mergeQueueEntry`/`isInMergeQueue`다.
