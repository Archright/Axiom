# Merge Authority Integrity (merge_authority_integrity)

**Status**: Normative contract (draft 2026-10-05 — 2026-10-05 main 동결 사고 계기).
merge-admission의 **권위는 여전히 GitHub 단독**이다(정본: AGENTS.md §2.3). 본 문서는 그 권위를
확장하지 않고, **권위가 있는 객체(ruleset · merge queue · merge state)를 그 권위의 진단자가
바꾸지 못하게** 한다는 불변식만 정의한다.

**Created**: 2026-10-05
**Related**: `AGENTS.md` §2.3 · §0.9(극장 금지) · `docs/agents/merge_admission_observation.md`
(L2-R 관측 층) · `docs/agents/rules_workflow.md` §2.8(Auto-Merge Default Policy) ·
`docs/spec/github_delegation_residuals.md` R2·R7(구성 평면 잔여 — **detector** 보유) ·
`docs/adr/0025-gateway-landing-authority.md`(M-B · Landing App standby 정정) ·
`config/trusted_writer_set.json`(강제된 권한 분리 선례)

## 1. Purpose / Scope

2026-10-05, merge queue가 entry를 가진 상태에서 main ruleset에 `update` 규칙이 추가되었다. 큐의
ref 갱신이 즉시 거절되었다(`rule_type:"update"` / `result:"fail"` /
`details:"Cannot update this protected ref."` — GitHub Rule Insights REST,
`rulesets/rule-suites/4360251067`, actor `github-merge-queue[bot]`, 1초 뒤
`removed_from_merge_queue`). main이 약 49분 동결되었다.

원인은 규칙의 정합성 문제가 아니다. **진단을 수행한 주체가 진단 대상을 직접 바꾸었다**
것이다. 기존 문서(`ci_epoch_cutover.md` · `authority_invariant_protocol.md` ·
`github_delegation_residuals.md` R7)를 모두 확인한 결과, 이 순서를 금지하는 문서는
**존재하지 않았다** — R7은 이를 구성 평면 외부 잔여로 분류하고 *detector*만 보유한다.

본 문서의 범위: main을 대상으로 하는 보호 구성(ruleset · branch protection)의 **변경**과
merge-admission의 **진단** 사이 권한 관계. 범위 밖: admission predicate의 판정 로직
(`docs/spec/merge_admission_controller.md` 정본), QUEUE 위임(`docs/adr/0027-queue-delegation.md`).

## 2. MUST 집합 (M1–M7)

| ID | MUST |
|---|---|
| **M1** | main-target 보호 구성의 **write 권한은 단일 identity·단일 절차에만** 존재한다. 두 개 이상의 쓰기 경로(CLI·UI·API·workflow)가 live 구성을 바꿀 수 있으면 그 구성에는 권위 주체가 없다. |
| **M2** | **큐에 entry가 있는 동안 main-target ruleset을 변경하지 않는다.** 불가피한 변경의 순서는 §5의 4단계를 따른다. |
| **M3** | 구성 변경 전·후에 **스냅샷을 남긴다**. 스냅샷 없는 변경은 회귀·_DRIFT의 근거를 소멸시키며, R2/R7 표면을 확대한다(스냅샷 = 드리프트 탐지의 유일 입력). |
| **M4** | required / non-required 판정의 **유일 해석자**는 GraphQL `CheckRun.isRequired(pullRequestNumber:)` 이다. 체크 이름·워크플로 존재·CLI 롤업은 근거가 아니다. |
| **M5** | `mergeStateStatus`는 **verdict** 이며 reason 필드가 없다. "어떤 규칙이·무엇 때문에 막혔나"의 유일 권위는 Rule Suites(`rulesets/rule-suites[/{id}]` → `rule_evaluations[].rule_type` / `.result` / **`.details`**)다. retention은 **약 1일** — 착지 직후 수집하지 않으면 소실된다. |
| **M6** | 판정 어휘는 **닫힌 집합**이다: `READY` / `NOT_READY` + `BLOCKED_BY_REQUIRED_CHECK` \| `BLOCKED_BY_REVIEW` \| `BLOCKED_BY_AUTHORITY` \| `BLOCKED_BY_QUEUE` / `UNKNOWN`. 사실이 부족하면 `UNKNOWN` — **원인을 모르면 UNKNOWN; 추측 금지.** 레이어: 원인 닫힌집합(`BLOCKED_BY_*` / `UNKNOWN`)은 **reason·evidence-kind 속성**으로 유지되며, 관측기의 **제어 계열**은 종단 상태기계(`docs/agents/merge_admission_observation.md` Liveness 절)로 판정한다 — MERGED→SUCCESS / 명시 blocker→FAIL / identity 변동 진행 증거→WAIT / 그 밖→UNKNOWN(**FAIL CLOSED, 즉시 정지**). `UNKNOWN`은 성공 가능 상태가 아니다. |
| **M7** | **진단 순수성**: 진단을 수행하는 identity는 진단 대상(ruleset · merge queue · merge state)을 **mutate하지 않는다**. 진단 = GET/GraphQL query만. |

M4·M5·M6의 관측 절차(adapter 명령·증거 귀속)는 `docs/agents/merge_admission_observation.md`
의 **L2-R** 가 정본이며, 본 표는 불변식만 담는다(단방향: agents → spec 역방향 참조 금지).

## 3. authority-per-fact

| 사실 | 권위 신호 | 읽기 데 필요한 권한 | 성격 |
|---|---|---|---|
| required / non-required | GraphQL `CheckRun.isRequired(pullRequestNumber:)` | `Metadata: Read` | 판정 근거의 유일 해석자 |
| merge 가능/불가 (verdict) | PR `mergeStateStatus` | `Metadata: Read` | **reason 없음** |
| 큐 진입·항목 상태 | PR `isInMergeQueue` · `mergeQueueEntry` · GraphQL `mergeQueue{entries}` | `Metadata: Read` | 상태 |
| **ref 갱신 거절 사유** | REST `rulesets/rule-suites[/{id}]` → `rule_evaluations[]` | `Metadata: Read` | **사유의 유일 권위** (retention ≈1일) |
| ruleset 구성 | `GET /rulesets` · `GET /rulesets/{id}` | `Metadata: Read` | 현재 구성 |
| branch protection | `GET /rules/branches/{b}` | `Metadata: Read` | 현재 구성 |
| **bypass_actors** | `GET /rulesets/{id}` 응답 필드 | **ruleset에 write 접근 권한이 있는 호출자에게만 반환** | §4 참조 |
| **ruleset history** | `GET /rulesets/{id}/history[/{version_id}]` | **`Administration: repository permissions (WRITE)`** | write 게이트가 걸린 GET |

## 4. 진단 순수성 (M7) — 그리고 `Administration` write 게이팅

M7의 실질은 **권한 분리**다. 규칙(ruleset)을 바꾸려면 `Administration: write`가 필요하고,
그 token은 `PUT`을 issued *할 수 있다*. 진단 도구가 그 token을 들면 진단자는 자기 대상을
바꿀 수 있다 — 2026-10-05 사고가 정확히 그 경로였다.

- **플랫폼 제약(측정된 사실)**: 규칙 history 읽기와 규칙 쓰기는 **같은 권한**이다
  (`Administration: repository permissions (WRITE)`) — **분리 불가**. `bypass_actors` 역시
  ruleset에 write 접근 권한이 있는 호출자에게만 반환된다.
- **따라서**: `bypass_actors`와 `ruleset history`는 **진단 사실 집합에 포함될 수 없다**.
  이 두 사실은 **선언된 Mutator 창**(§5의 drain 이후·변경 직전과 직후)에 수집·기록된다.
  진단 identity가 그 창에서 write 권한을 보유하면 M7이 깨지므로, Tier 1 분리(§6)가
  전제 조건이다.
- **honesty 조건**: Mutator 창을 쓰기 위해 진단 identity에 write 권한을 부여했다면,
  M7은 **절차 계약이지 구조 강제가 아니다** — 이 상태를 §6 Tier 0으로 정직하게 기록한다.

## 5. mid-queue mutation ban (M2)

활성 merge queue가 entry를 가진 동안 main-target ruleset을 변경하지 않는다. 큐는 **진행 중인
착지에 현재 규칙을 재평가**해 적용하므로, 변경 시점의 규칙이 큐의 모든
진행 항목에 소급된다. 2026-10-05에는 이것이 착지를 **영구 거부**(복구 없이)했다.

불가피한 변경의 **필수 순서** (4단계의 상대 순서는 고정):

```text
drain queue  →  change ruleset  →  take snapshot  →  resume
```

- **생략·재배열·병합 금지.** 병합(예: "queue 비우고 바로 수정")은 4단계 위반이다.
- **pre-snapshot**(변경 전 구성)은 M3 수집이며 drain 과 change **사이에** 놓인다 —
  drain 이후이므로 살아있는 큐가 관측을 방해하지 않고, 4단계의 상대 순서는 그대로다:
  `drain → (pre-snapshot) → change → snapshot → resume`.
- **authority 불일치는 pre-snapshot에서 잡는다** — 변경 전에 "누가 main을 바꾸는가"를
  확정하지 않은 채 변경하면 M1 위반이 먼저 발생한다(§9 V4).
- 이 금지는 `docs/spec/github_delegation_residuals.md` R7을 **대체하지 않는다** — R7은
  arm-완료 사이 큐 규칙 제거라는 별개 잔여이며, 그 분류와 detector를 유지한다.

## 6. Tier 0 / Tier 1 — 강제 vs 절차

| Tier | 성격 | 내용 | 강제 여부 |
|---|---|---|---|
| **Tier 0** | **절차적(procedural)** | "진단 token으로 write를 쓰지 않는다"를 문서·절차로 규율. 같은 token은 여전히 `PUT`을 issued *할 수 있다* | **구조적 강제가 아님 (explicitly NOT structural)** |
| **Tier 1** | **구조적(structural)** | `Metadata: Read` 만 가진 fine-grained PAT로 분리된 진단 identity — `Administration: write`가 없으므로 진단 중 규칙 변경이 **불가능** | 구조적으로 강제되나 **인간 액션 선행 필요** |

- **Tier 1의 인간 의존**: GitHub은 **PAT 생성 API를 제공하지 않는다** — 토큰 발급은 UI/조직
  설정에서만 가능하다. 따라서 Tier 1은 에이전트가 완성할 수 없고 **인간이 먼저 만든다**.
  Tier 1이 없으면 M7은 Tier 0 = 절차 계약으로만 존재한다. 이 상태를 M7이 구조적으로
  보장한다고 서술하지 않는다(AGENTS.md §0.9 극장 금지).
- **선례**: `config/trusted_writer_set.json` — "admission-check.yml: UNPRIVILEGED B-pinned
  check producer (top-level contents: read; NEVER a ledger writer)". 그 워크플로는
  **구조적으로** `contents: write`를 거부되며 "unprivileged"는 의도(grace) 가 아니라
  **집행되는 속성(enforced property)** 이다. Tier 1은 merge-authority 축에 같은 선례를
  적용한다.

## 7. Executor inventory — 누가 main을 실제로 바꾸는가

| 경로 | 실행 주체 (actor) | 식별 |
|---|---|---|
| auto-merge 발화 착지 | GitHub merge infrastructure가 ref 갱신을 실행, 행위자는 merge queue bot | `github-merge-queue[bot]`, actor id `118344674` |
| 수동 병합 | 요청한 인간이 병합을 요청 | actor id `53123826` |

- 2026-10-05 규칙 평가 행위자는 **`github-merge-queue[bot]`** 였다 — 진단을 수행한 주체와
  ref 갱신을 시도한 주체는 서로 다른 주체이며, 전자가 후자의 **대상**(ruleset)을 바꾸면서
  막았다. 이 부재(mismatch)가 M1·M7의 근거다.
- inventory에 **Landing App은 없다** — §8.

## 8. `config/app_landing_binding.json` staleness (Landing App)

- 선언된 Landing App = app id **`4879411`** (`installation_id` `160192931`), slug
  `axiom-ci-elastic`(`docs/evidence/ghec_ruleset_p1c_bypass_2026-09-24.md:13`).
- **이 App은 main을 한 번도 업데이트한 적이 없다.** Landing App CAS E2E 착지 **0건**은
  이미 실측·기록되어 있다(ADR-0025 §1 M-B 실측 ③, `docs/adr/0025-gateway-landing-authority.md`).
- ADR-0025는 이를 **비authoritative standby**로 정정했고, 불변식 1의 실행으로 CAS 경로
  (`updateRefs`/`beforeOid`/temp-ref)도 제거했다.
- 그러므로 `config/app_landing_binding.json:5`의 "The Landing App is the **ONLY authority**
  that mutates refs/heads/main" 서술은 **현재 사실과 불일치한다**. 본 문서는 그 서술을
  사실로 재확정하지 않으며, 정정은 ADR-0025의 후속 개정 경로에 속한다.
- **§7 executor inventory는 Landing App을 집행 주체로 열거하지 않는다.** 선언과 실행의
  불일치는 M3 pre-snapshot에서 탐지 대상이다(§9 V4).

## 9. Verification

아래는 **계약**이다. 각 행의 관측값은 **실측 전까지 공란**이며, 관측되지 않은 숫자·PASS를
채워 넣지 않는다(AGENTS.md §2.2 — 완료는 기계 검증이다). 기입은 명령·타임스탬프(UTC)·관측
원문 JSON을 동반할 때만 유효하다.

| # | 관측 항목 | 관측 방법 | 관측값 | 판정 |
|---|---|---|---|---|
| **V1** | direct push 거부 | main 대상 보호 구성에서 push 거부 규칙 활성 확인 + 거부 시도 결과 | T1 probe(2026-10-05 15:49:11 KST / 06:49:11 UTC): `git push origin HEAD:main` 거부 + `GET /repos/Archright/Axiom/rulesets/rule-suites/4361198253` — actor `wintrover`(53123826), `refs/heads/main`, result **fail**; update · pull_request · required_status_checks · merge_queue · workflows fail, creation · non_fast_forward · deletion · file_path_restriction×2 pass | **PASS** — bypass가 `pull_request` 모드여도 직접 push는 차단됨 |
| **V2** | 큐 착지 시 `update: fail` 0건 | 착지 직후 `GET /repos/{o}/{r}/rulesets/rule-suites` 수집 → `rule_evaluations[]` 중 `{rule_type:"update", result:"fail"}` 건수 (retention ≈1일 — **착지 직후 수집 필수**) | PR #482 MERGED(mergeCommit `888575faa031ff54ece3cea5513675618002e415`, mergedAt `2026-10-05T08:10:53Z`, mergedBy `wintrover`) 착지 전후 rule-suites 캡처(2026-10-05 17:01 · 17:14 KST / 08:01 · 08:14 UTC): suite IDs `4362123444` · `4362123586` · `4362123754` · `4362298950` · `4362299064` · `4362299205` — 전부 result pass, 평가는 `file_path_restriction`뿐. `{rule_type:"update", result:"fail"}` **0건**. 관측 공백: 성공적 큐 착지는 `refs/heads/main` rule-suite를 발행하지 않았다(사고 시 fail suite `4360251067`과 대조) — "정상 착지의 rule-suite 부재" 자체가 관측 사실 | **PASS** — update: fail 0건 (suite 미발행은 성공의 증거로 읽지 않고 관측 공백으로 병기) |
| **V3** | 진단의 mutation 0건 | 진단 identity(M7 §4)가 write 권한 없이 수행되었음을 identity 스코프로 확인 — GitHub은 요청 메서드를 감사 노출하지 않으므로 **token scope로 판정**한다 | token scope 기준 세션 전체 구성 쓰기는 **선언된 Mutator 창 2회**뿐 — Phase C `PUT /rulesets/20303214` 1회(2026-10-05 15:41 KST 큐 EMPTY 확인 → pre-snapshot → PUT) + 롤백 `PUT` 1회(16:57:39 KST / 07:57:39 UTC, `updated_at:"2026-10-05T16:57:39.440+09:00"`, 큐 EMPTY 확인 후 control 5규칙). 진단 구간(Phase A 스냅샷 · T1 probe · rule-suite 판독)은 GET/GraphQL query만 | 절차 계약(**Tier 0**) 준수 — 구조 강제 아님(§6) |
| **V4** | authority 불일치 탐지 (pre-snapshot) | §5 pre-snapshot의 실행 주체 선언(§7 inventory·§8 Landing App standby)과 실제 착지 행위자 대조 — 불일치가 **변경 전에** 탐지되었는지 | pre-snapshot의 executor 선언(§7): `github-merge-queue[bot]`(118344674) 자동 경로 · `wintrover`(53123826) 수동, Landing App 제외. 실제 착지 행위자: PR #482 mergedBy=`wintrover`, 큐 경로(auto-merge, mergedAt `2026-10-05T08:10:53Z`) — inventory에 열거된 경로이며 상충 없음 | **상충 없음** — actor attribution은 관측 사실 그대로 기술(mergedBy `wintrover`, 큐 경로) |

V2의 retention 제약은 이 절 자체가 "사후 관측에 의존한다"는 구조적 사실을 반영한다 — 사유를
남기지 않으면 M5는 사후에 검증 불가능하다.

## 10. Residuals (정직 기록)

- **Tier 1 미확립 시 M7은 절차다.** PAT 생성은 인간 전용이며 자동화 불가 → 구조적 강제는
  인간 액션에 의존한다. Tier 0 상태에서 M7을 "강제된다"고 서술하지 않는다.
- **Mutator 창의 존재 자체가 §4의 예외다.** `bypass_actors`·history는 write 권한 없이는
  읽히지 않으므로, 그 두 사실의 수집은 진단 밖에 선언된다.
- **`tools/merge_ruleset_drift_monitor.nim`은 관측 순수하지만 identity 분리는 아니다.** GET
  만 issuing 하므로 구성상 관측 순수이나, 호출 토큰이 `PUT`을 issued *할 수 있다* — M7의
  Tier 1 분리가 이 도구에 적용되기 전까지 관측 전용 계층이다(그리고 **여전히 보안 경계가
  아니다** — `docs/agents/rules_workflow.md` §2.8 Authority layering 정본).
- **`tools/setup_branch_protection.nim` — 분해(decommission)됨 (2026-10-12, M7 위임 실행
  슬라이스)**. §10 구 기록("live `PUT`을 수행하며 어떤 trust surface에도 등록되어 있지
  않다")의 후속 처리: 저장소 전수 검색에서 호출자·빌드 배선·debt 레지스트리 참조 0건을
  실측했고, 페이로드는 ruleset 권위 이전 이전의 구식 branch protection(all-gates-passed
  required check)을 겨냥한 것이므로 trust surface **등록이 아니라 제거**를 택했다 — 등록은
  operator identity의 제2 write 경로를 합법화할 뿐 M1("write 경로의 단일 권위 주체")을
  회복하지 못한다. 도구 파일은 M7 본문 PR에서 삭제되었으며 main-target 보호 구성의 쓰기
  경로는 ruleset 권위(GitHub UI/API의 선언된 mutator)로 단일화된다. 본 항목은 폐기 기록
  (tombstone)이지 권한·면제를 부여하지 않는다(AGENTS.md §2.5).

## References

- GitHub REST — Rule suites: `GET /repos/{owner}/{repo}/rulesets/rule-suites[/{rule_suite_id}]`
- GitHub REST — Rulesets history: `GET /repos/{owner}/{repo}/rulesets/{ruleset_id}/history` (
  **`Administration: repository permissions (WRITE)`** — write 게이트가 걸린 GET)
- `docs/agents/merge_admission_observation.md` L2-R · `docs/agents/rules_workflow.md` §2.8
- `docs/spec/github_delegation_residuals.md` R2·R7 · `docs/adr/0025-gateway-landing-authority.md`
  M-B / Amendment A 불변식 1 · `config/trusted_writer_set.json` · `config/app_landing_binding.json`
