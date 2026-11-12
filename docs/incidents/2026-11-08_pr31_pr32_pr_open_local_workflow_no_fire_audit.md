# 인시던트 감사 기록 — PR #31/#32 PR open 시 repo-local pull_request 워크플로우 미발파 (2026-11-08)

- 문서: `docs/incidents/2026-11-08_pr31_pr32_pr_open_local_workflow_no_fire_audit.md`
- 사건 일자: 2026-11-08 / 기록 작성: 2026-11-10
- 성격: docs-only PR 2건(#31, #32)의 `pull_request` opened 이벤트에서 repo-local pull_request 워크플로우 9종이 발파되지 않은 현상의 원인 규명(η 에이전트 2026-11-09 보고의 follow-up)
- 분류: §2.3(merge-admission 관측 계약) — L1 관측층 성공 없이 required 체크가 미보고된 채 방치될 수 있음을 보인 사례. 회복은 close→reopen 재발행으로 관측됨
- 특기 사항: 본 문서의 착지 PR 자체가 docs 단일 파일 PR로서 동일 미발파 리스크에 노출된다 — §5 운영 대응 절차를 이 PR에 그대로 적용한다

모든 시각은 UTC. 근거 ID(EV-n)는 아래 관측에 대응하며, 원시 관측은 GitHub REST API GET(`actions/runs`, `commits/{sha}/check-runs`, `pulls/{n}`, `issues/{n}/timeline`, `pulls/{n}/files`, rulesets)과 `git log`로 2026-11-10 획득했다.

## 1. 확정 사실

### 1.1 현상 — open 이벤트에서 org 2종만 발파, repo-local 9종 run 레코드 부재

- [EV-1] PR #31(docs/evidence 1파일, head `4df814f3`, base `b9aba2a`) opened 2026-11-08T23:26:13Z. 직후 pull_request 이벤트 run은 org 필수 워크플로우 2종뿐: admission-gate run 42535167264·landing-integrity run 42535167130(각각 created 23:26:16Z, `run_started_at == created_at`, admission-gate는 23:31:44Z success 완주). repo-local pull_request 워크플로우 9종(axiom-operational-slice, bsec-integrity, debt-registry-gate, dependabot-auto-merge, generation-acceptance, observer-manifest-consistency, repository-surface, tests-ci-unit-diagnostic, trusted-writer-set)의 run은 **queued/failed/cancelled를 포함해 0건** — 지연이 아니라 run 레코드 자체가 없다.
- [EV-2] PR #32(docs/evidence 1파일, head `8465bd86`, 동일 base `b9aba2a`) opened 23:33:45Z — 동일 양상(run 42535768329/42535768023, 23:33:49Z, admission-gate 23:39:38Z success).
- [EV-3] 미발파가 docs-only 고유가 아님: #37(2파일)·#38(10파일)·#40(1파일)·#43(1파일)·#44(2파일)은 전부 docs-only인데 open 후 3~5초 내 전체 발파. #40은 1행성 docs PR로 η 보고 시점에 "재현 안 됨"으로 보고된 바로 그 PR이다.

### 1.2 open 시점 merge-admission 상태 — repo-local required 미보고

- [EV-4] #31 head의 check-run 전수: open 직후 org 체인(merge-admission-sanity, anchor-resolve, trust-surface-codeowners, trusted-writer-set-pairing, closure-deriver, attest/gateway/mint-prepare)이 23:26:19~23:30:04Z에 실행·성공했고 집계 required context `admission-check`는 23:31:40~23:31:43Z success 보고. 반면 repo-local required 4종(bsec-integrity, debt-registry-gate, generation-acceptance, axiom-operational-slice)의 check-run은 reopen 이전까지 부재 → 이 시점 PR은 repo-local required 미보고 상태(BLOCKED).
- [EV-5] #32 동일: `admission-check` 23:39:33Z success(이하 생략된 집계 시각 체인 동일 구조), repo-local required 4종 check-run은 23:48:43Z 이전 부재.
- [EV-6] main 분기 대상 ruleset은 repo ruleset **26702792 "main"**(enforcement active)이며, 그 `required_status_checks` 컨텍스트(2026-11-10 조회 스냅샷): `admission-check`, `bsec-integrity`, `debt-registry-gate`, `generation-acceptance`, `axiom-operational-slice`, `publication-integrity`. `publication-integrity`는 2026-11-09 PR #45/#46 이후 추가된 것으로, 사건 창(2026-11-08)의 필수 집합은 아니었다. GitHub는 ruleset 변경 이력 API를 제공하지 않아 당시 정확한 집합은 복구 불가(2026-10-13 감사 기록 EV-10과 동일한 관측 한계)다.

### 1.3 회복 — close→reopen 재발행 (head SHA 불변)

- [EV-7] #31: closed 23:44:47Z → reopened 23:44:54Z → 11개 run이 23:44:56Z에 생성(같은 head `4df814f3`, run 42536648697 외 10건). repo-local required 4종 check-run 23:44:59Z~23:51:03Z 모두 success → **00:02:00Z MERGED**(`be4e28a0`).
- [EV-8] #32: closed 23:48:35Z → reopened 23:48:37Z → 11개 run 23:48:40Z(`8465bd86`, run 42536949920 외 10건) → repo-local 4종 23:48:43Z~ success → **00:15:58Z MERGED**(`07de6801`).
- [EV-9] open(23:26:13Z)~close(23:44:47Z) 사이 head SHA 불변 — synchronize 이벤트(재발파 트리거)는 한 번도 없었다. 회복은 close→reopen의 `reopened` activity type이 유일한 경로였다.

### 1.4 전수 대조 — PR #28~#53 첫 발파 관측

- [EV-10] `actions/runs?event=pull_request` 전수 집계(2026-11-08T15:54Z~2026-11-10T01:54Z). "첫 발파" = PR open 직후 첫 run 버스트 시각:

| PR | open (UTC) | 첫 발파 | 내용 | 판정 |
|---|---|---|---|---|
| #28 | 11-08 16:55:23 | 16:55:27 (4s) 전체 | 혼합 | 정상 |
| #29 | 11-08 17:22:21 | 17:22:24 (3s) 전체 | docs+1 | 정상 |
| #30 | 11-08 17:24:37 | 17:24:41 (4s) 전체 | 혼합 | 정상 |
| **#31** | 11-08 23:26:13 | **org 2종만 23:26:16; 전체는 23:44:56 (reopen)** | docs 1파일 | **미발파** |
| **#32** | 11-08 23:33:45 | **org 2종만 23:33:49; 전체는 23:48:40 (reopen)** | docs 1파일 | **미발파** |
| #33 | 11-08 23:44:31 | 23:44:34 (3s) 전체 | 혼합 | 정상 |
| #34 | 11-08 23:53:42 | 23:53:47 (5s) 전체 | 혼합 | 정상 |
| #35 | 11-09 00:42:44 | 00:42:47 (3s) 전체 | 혼합 | 정상 |
| #36 | 11-09 00:46:27 | 00:46:31 (4s) 전체 | 혼합 | 정상 |
| #37 | 11-09 00:47:16 | 00:47:20 (4s) 전체 | docs-only | 정상 |
| #38 | 11-09 01:15:04 | 01:15:08 (4s) 전체 | docs-only | 정상 |
| #39 | 11-09 01:26:35 | 01:26:39 (4s) 전체 | 비-docs 1파일 | 정상 |
| #40 | 11-09 01:41:24 | 01:41:28 (4s) 전체 | docs 1파일 | 정상 |
| #41 | 11-09 02:04:26 | 02:04:29 (3s) 전체 | 비-docs 1파일 | 정상 |
| #42 | 11-09 02:46:22 | 02:46:26 (4s) 전체 | 비-docs 1파일 | 정상 |
| #43 | 11-09 05:56:50 | 05:56:54 (4s) 전체 | docs 1파일 | 정상 |
| #44 | 11-09 05:56:51 | 05:56:54 (3s) 전체 | docs 2파일 | 정상 |
| #45 | 11-09 09:24:28 | 09:24:32 (4s) 전체 | 혼합 | 정상 |
| #46 | 11-09 09:59:46 | 09:59:50 (4s) 전체 | 1파일 | 정상 |
| #47 | 11-09 12:15:12 | 12:15:16 (4s) 전체 | 1파일 | 정상 |
| #48 | 11-09 12:15:46 | 12:15:49 (3s) 전체 | 1파일 | 정상 |
| #49 | 11-09 12:15:49 | 12:15:53 (4s) 전체 | 1파일 | 정상 |
| #50 | 11-09 12:53:23 | 12:53:28 (5s) 전체 | 혼합 | 정상 |
| #52 | 11-09 17:09:17 | 17:09:25 (8s) 전체 | 혼합 | 정상 |
| #53 | 11-10 01:54:37 | 01:54:41 (4s) 전체 | 혼합 | 정상(OPEN) |

  (#51은 소진된 번호로 PR 부재 — `pulls/51` 404. #23~#27도 전부 open+3~4초 내 전체 발파로 정상이다.)

- 정상 24건의 open→첫 발파 지연은 3~8초로 일정하다. 미발파는 정확히 2건이고 둘 다 **2026-11-08T23:26:13Z(#31 open)~23:44:31Z(#33 open, 3초 후 정상 발파) 창** 안에서 open되었다. 창 내 open 2건 전부 미발파, 창 밖 open 전부 정상 — 내용(docs-only 여부)·브랜치·규모는 판별 인자가 아니다.

### 1.5 in-repo 원인 배제

- [EV-11] repo-local pull_request 워크플로우 9종 파일 blob이 #31/#32의 base `b9aba2a`와 현재 main tip(`5f3595a`)에서 전부 동일(`git rev-parse` blob 대조).
- [EV-12] 사건 창(2026-11-08T13:59Z~23:44Z)에 `.github/workflows/`를 건드린 main 커밋 0건.
- [EV-13] 12개 pull_request 트리거 워크플로우 중 어느 것도 `paths:`/`paths-ignore:` 필터를 갖지 않는다(`branches: [main]` 또는 무필터). docs-only 변경이 트리거에서 제외되는 구성 자체가 존재하지 않는다. probe-merge-queue의 `branches: [queue-probe]`는 본 사건과 무관한 대상 분기 필터다.
- [EV-14] 저장소 Actions 활성 상태(`actions/permissions`: enabled, allowed_actions=all). 창 중 비활성화 흔적 없음 — 비활성이었다면 org 필수 워크플로우도 실행될 수 없었다.
- [EV-15] concurrency 그룹 키는 전부 PR 번호 스코프(예: `repository-surface-${{ github.event.pull_request.number }}`)이며, concurrency로 취소된 run은 conclusion=cancelled 레코드로 남는다 — 관측된 것은 레코드 부재이므로 concurrency 취소와 양립하지 않는다.

### 1.6 절차적 원인 배제 (push 순서)

- [EV-16] PR open 이벤트 페이로드 자체가 head `4df814f3`/`8465bd86`을 담는다 — PR이 열린 시점에 브랜치 ref가 이미 존재했다(push가 open에 선행).
- [EV-17] org admission-gate가 open 10초 후 head tree를 정상 해석했다(closure-deriver가 H/B 양쪽 폐쇄를 23:26:26~23:27:57Z에 산출·성공). ref 전파 미완료 상태가 아니었다. "PR open이 push 전파를 앞질렀다"는 절차적 경쟁 가설은 관측과 모순된다.

### 1.7 org 필수 워크플로우와 repo-local 워크플로우의 트리거 경로 분리

- [EV-18] admission-gate/landing-integrity는 `Archright/.github` 저장소의 워크플로우다(`.github/workflows/admission-gate-v2.yml`, `landing-integrity.yml` — 이 저장소 역사 전체에서 두 파일은 존재한 적이 없음: `git log --all` 공백).
- [EV-19] org ruleset 25218071 "axiom-admission-gate"(active): rule type `workflows`로 `Archright/.github`(repository_id 1182157951)의 `.github/workflows/admission-gate-v2.yml@1eed0a482d370a77a6724b73ab7b484b6cddcff4`을 SHA 고정, 조건 ref `refs/heads/main` + 저장서 `Axiom`. ruleset 23943917 "landing-integrity" 동일 구조. org 필수 워크플로우 평가는 대상 저장소의 로컬 워크플로우 파일 목록 평가와 별개 경로다 — 같은 pull_request 이벤트에서 한쪽만 선택적으로 실패할 수 있는 구조적 이유다.
- [EV-20] repo `admission-check.yml`은 native pull_request 트리거가 없고 org admission-gate의 `workflow_call`이 유일 실행 경로다(파일 주석 명시). 따라서 required context `admission-check`는 org 경로가 살아있는 한 open에서도 보고되었고(EV-4/5), 막힌 것은 repo-local required 4종뿐이었다.

### 1.8 GitHub 서비스 상태 이력

- [EV-21] githubstatus.com incident 이력에 2026-11-08T23:26~23:44Z 창을 덮는 인시던트 없음. 근접 인시던트: 2026-11-09T10:00Z "Webhooks and Actions", 2026-11-09T18:12Z "Actions and Checks API"(둘 다 창 이후). 2026-11-04T17:53Z 인시던트 업데이트("issue with events that might trigger Actions... delayed status updates")는 '이벤트→Actions 트리거 평가' 실패가 플랫폼측에서 실재하는 장애 클래스임을 보여주는 사례다.

### 1.9 관측 타임라인 (2026-11-08~09, UTC)

| 시각 | 사건 | 근거 |
|---|---|---|
| 17:24:41Z | #30 open 전체 발파 — 창 직전 마지막 정상 open | EV-10 |
| 23:25:50Z | #31 head 커밋 작성(4df814f3, 부모 b9aba2a) | git 관측 |
| 23:26:13Z | **PR #31 opened** — repo-local 9종 미발파 | EV-1 |
| 23:26:16Z | org admission-gate·landing-integrity 즉시 실행(run_started=created) | EV-1 |
| 23:26:26Z | org 게이트 closure-deriver가 head tree 해석 성공 — ref 전파 완료 증명 | EV-17 |
| 23:31:43Z | required context `admission-check` success 보고(org 경로) | EV-4 |
| 23:33:45Z | **PR #32 opened** — 동일 미발파 | EV-2 |
| 23:39:33Z | #32 `admission-check` success(org 경로) | EV-5 |
| 23:44:31Z | PR #33 opened → 23:44:34Z 전체 발파(정상) — 창 종료 | EV-10 |
| 23:44:47Z / 23:44:54Z | #31 closed → reopened | EV-7 |
| 23:44:56Z | #31 전체 11 run 재발파(같은 head SHA) | EV-7 |
| 23:48:35Z / 23:48:37Z | #32 closed → reopened | EV-8 |
| 23:48:40Z | #32 전체 11 run 재발파 | EV-8 |
| 23:51:03Z | #31 repo-local required 4종 전부 success | EV-7 |
| 00:02:00Z | #31 MERGED(be4e28a0) | EV-7 |
| 00:15:58Z | #32 MERGED(07de6801) | EV-8 |

## 2. 근본 원인 판정

임무가 요구한 3분류에 대해:

- **(a) in-repo 원인 — 배제.** 트리거 구성은 문서화된 의미론 그대로다(무필터 `pull_request` = 기본 activity type 전체에 발파; paths 필터 부재). 9종 파일은 사건 전후로 byte-identical(EV-11/12/13), 창 이후 동일 구성으로 24연속 정상 발파(EV-10). in-repo 수정이 필요하다는 판정은 성립하지 않는다 — 수정할 in-repo 결함이 관측되지 않았다.
- **(c) 절차적 원인(push 순서 등) — 배제.** push는 open에 선행했고 ref 전파는 open 10초 내 완료 상태였다(EV-16/17). close→reopen "전에" 순서 문제가 있었다는 증거 없음.
- **(b) GitHub측 일시적 이상 — 판정.** 근거: (i) 공식 문서는 `on: pull_request`(types 미지정)가 activity type `opened`에서 실행됨을 규범으로 정하는데(§6 인용), opened에서 9종 전체가 run 레코드 없이 미실행되었다(EV-1/2) — 문서화된 의미론과 관측의 위배. (ii) 유일하게 문서화된 pull_request 미실행 조건(merge conflict, GITHUB_TOKEN 생성 PR 승인 게이팅, fork 승인)은 전부 해당하지 않는다(1커밋 무충돌 docs PR, author/triggering_actor=wintrover, same-repo 브랜치, 대기 run 레코드도 부재). (iii) 같은 이벤트에서 org 필수 워크플로우 경로는 즉시·완주 성공(EV-1/2/19) — 이벤트 전달 자체는 살아 있고 repo-local 트리거 평가만 선택적으로 실패했다. (iv) 18분 뒤 `reopened`에서 동일 구성이 2~3초 만에 전체 발파(EV-7/8) — 지속적 구성 결함이 아닌 일시적 상태. (v) 시간 상관이 완전하다: 창 내 open 2건 전부 미발파, 창 밖 24건 전부 정상(EV-10).
- **정확한 내부 메커니즘은 외부 관측으로 특정 불가**다(§3). 또한 githubstatus에 해당 창의 공개 인시던트가 없으므로(EV-21), "공개 장애"가 아니라 **공개 인시던트 임계 이하의 플랫폼측 일시 이상**으로 기록한다. 2026-11-04 "events that might trigger Actions" 인시던트가 보여주듯 이 실패 클래스 자체는 GitHub 플랫폼에서 실재한다.

## 3. 미확정 사항 (잔여)

- (a) GitHub 내부에서 어느 단계(로컬 워크플로우 목록 평가, 이벤트 라우팅 샤드 등)가 실패했는지 — 외부 관측 불가.
- (b) 미발파가 "opened 이벤트의 로컬 평가 스킵"인지 "평가 지연 후 reopen 이벤트 발파로 대체"인지 — run 레코드가 부재해 구분 불가. 어느 쪽이든 운영적 결론(§5)은 동일하다.
- (c) 사건 창의 정확한 시작 시각 — 마지막 정상 open은 17:24:37Z(#30), 첫 미발파 open은 23:26:13Z(#31). 그 사이 6시간 동안 PR open이 없어 창을 더 좁힐 관측이 없다.

## 4. 재현 조건 (관측 기반)

- 관측된 필요조건: **2026-11-08T23:26:13Z~23:44:31Z 사이 Archright/Axiom main 대상 PR open**. 해당 창에서 open된 2건(#31, #32) 전부 미발파.
- docs-only는 재현 인자가 아니다(창 밖 docs-only 5건 전부 정상, EV-3/10). 브랜치명·규모·단일/다중 파일·base SHA(#31/#32와 #33은 사실상 동일 시점의 main에서 분기)도 판별 인자가 아니다.
- 이후 재발 없음: 2026-11-09~10 PR #33~#53 전부 open+3~8초 내 정상 발파(EV-10). 유발·방지 조건은 관측되지 않았다 — 시간 상관만이 확인된 패턴이다.

## 5. 운영 대응 절차 (재발 시)

1. **required 0건 = UNKNOWN/NOT READY — merge 금지.** PR open 직후 어느 required context도 아직 보고되지 않은 상태는 성공이 아니라 미관측이다(AGENTS.md §2.3). org 경로만 살아 `admission-check`가 초록으로 돌아와도 repo-local required가 없으면 merge-admission은 완결 아니다(본 사건 그대로).
2. **감지**: PR open 후 수 분 내 repo-local run이 보이지 않으면 관측으로 판정한다(추측 금지):
   `gh api 'repos/Archright/Axiom/actions/runs?event=pull_request&head_sha=<HEAD_SHA>&per_page=100' --jq '.workflow_runs[].name'`
   — org 2종(admission-gate, landing-integrity)만 나열되면 본 사건 패턴이다.
3. **회복 — close→reopen 재발행** (head SHA 불변, 2~3초 내 전체 재발파, EV-7/8 검증):
   `gh pr close <N> && gh pr reopen <N>`
   빈 커밋 push는 synchronize 재발파를 유발하지만 head SHA를 바꾸므로 동등한 대안이 아니다. 재발파 후 required 체크의 실제 green을 기계 관측으로 확인한 뒤에만 merge 한다.
4. **증거 보존**: 재발 시 run 목록·check-run 스냅샷(`commits/{sha}/check-runs`)·githubstatus 이력을 본 문서 형식(EV-n)으로 `docs/incidents/`에 추가 기록한다. GitHub측 원인 재발이 누적되면 GitHub Support 제보 근거로 쓴다.

## 6. 공식 문서 인용

- [Events that trigger workflows — pull_request](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows): "By default, a workflow only runs when a `pull_request` event's activity type is `opened`, `synchronize`, or `reopened`." — §2 판정 (i)의 규범 근거. 같은 페이지의 Notes: merge conflict 시 미실행(유일하게 문서화된 조건부 스킵 — 본 건 비해당), GITHUB_TOKEN 생성 PR의 승인 게이팅(미해당 — 그 경우 run은 '승인 대기'로 존재한다), `GITHUB_REF=refs/pull/N/merge`·merge commit 실행 의미론.
- [Securely using pull_request_target](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target): "`pull_request` 이벤트는 PR의 merge commit에서 워크플로우 파일을 실행한다" — 로컬 평가가 merge ref 해석에 의존함(§3(a)의 후보 영역)의 문서적 근거.
- org 필수 워크플로우(= ruleset `workflows` 룰, SHA 고정)의 구성과 조건은 관측 데이터로 인용한다(EV-18/19).

## 7. 변경 필요 여부

- **in-repo 수정 불필요** — 트리거 구성은 문서화된 의미론에 합치하고 24연속 정상 발파를 유지한다(§2(a)). `.github/workflows/**`는 repository_surface v95 FROZEN이므로 어느 쪽이든 수정 착지는 Owner 2단계 사안이다.
- 대응은 §5의 운영 절차(관측→close→reopen→기계 검증)로 충분하다. 본 문서가 그 표준 절차의 근거 기록이다.
