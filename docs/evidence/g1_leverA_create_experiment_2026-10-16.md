# G1 Lever-A — ruleset DELETE+CREATE 실험 기록 (2026-10-16)

> G1 PUT 실험(실패 확정: 양단 무발화, 3× post-2단 게이트 완결 0건)의 후속 — 조사 권고: "모든 ruleset-workflow 생성 시점이 출생 즉시 발화" = CREATE가 유일하게 검증된 발화 경로.

## 수술 (04:50-04:52Z 창, 직접 수행)

| 단계 | 관측 |
|---|---|
| 창 | 04:50:24Z queue=0 ∧ admission-gate in-flight=0 (재확인 후 진입) |
| 동결 | 20303214 mq 2→0 PUT·readback 0 |
| DELETE | `/orgs/Archright/rulesets/24233738` — rc=0 |
| CREATE | POST 기준 본문 verbatim → **신규 id 25218071** |
| readback | sha `ade11572052d9bce01242df452d05ab38ed78eb0`·enforcement active·path 정확·**본문 diff = 공란**(id/node/created/updated/링크만 상이) |
| 해제 | mq 0→2 readback 2 |
| 최종 | {25218071 axiom-admission-gate active, 23943917 landing-integrity active(무훼손 대조군)} |

독립 병합 차단(2단과 동일 입증): 20303214 required_status_checks(admission-check·bsec-integrity 미보고 시 차단) + pull_request 규칙 + mq 동결. 잔여: 초 단위 창의 관리자 UI bypass — 기록됨.

## 관측 (본 착지 후 기입)

(관측차량: 본 PR의 큐 착지 — 게이트 MG 완결 후 90초 창 publisher 바인딩 판정)

## 관측 결과 (판정, 2026-10-16 05:28-05:30Z)

- 관측차량 PR #875의 admission-gate MG **완결 05:28:02Z, 무인 착지 05:29:01Z**.
- 완결 후 publisher 실행 4건(38855963553·38855970608·38856036556·38856040055) — 바인딩 전부 **merge-queue-rearm / trusted-writer-set**(착지 후 이벤트). **admission-gate 바인딩 0건.**

## 판정: 레버A 실패 (사전 고정 표)

- PUT 경로(멱등·룰재생성)에 이어 **CREATE 경로(신규 ruleset id 25218071·완전 동일 명세)까지 무발화** — ruleset 엔트리 재생성으로는 이벤트 구독이 재부착되지 않음.
- 함의: 결함의 소재는 ruleset 바인딩이 아니라 **대상 리포지터리의 워크플로 객체 정체성**(workflow id 367727531) 쪽일 가능성이 지배적으로 됨 — 조사의 H-B(레지스트리 부재 대칭)가 재평가됨: 양 워크플로 모두 레지스트리 부재인데 landing-integrity만 발화하므로, 객체 정체성의 *발화 측* 상태가 비대칭.
- 잔여 레버(별도 승인): **B — 워크플로 파일 경로 변경**(Archright/.github에서 admission-gate.yml → 신규 이름 + ruleset path 갱신 = 신규 워크플로 등록 강제, 고착 정체성과 충돌 불가능한 유일한 경로) + **지원 티켓**(PR #874 패키지).
