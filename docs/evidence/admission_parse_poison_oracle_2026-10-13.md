# admission-check 파스 독 정본 오라클 실측 — 2026-10-13 (S1)

## 개요

0-job dispatch 교착(PR #780 도입, #794 미해소)의 잔여 독을 정본 오라클로 판별하고
후보 2(blob `09ff52b3596cbf116fa7e6c64b0763f91443f3b2`)의 파스 PASS를 실측했다.
본 문서는 Axiom PR #795(파스 독 제거 + A2 핀 원자 회전)의 착지 근거다.

## 오라클 구성

- 정본: `Archright/.github`의 기등록 워크플로 `parse-probe`(id `382154933`,
  path `.github/workflows/parse-probe.yml`) — workflow_dispatch, ref 지정
  디스패치로 브랜치별 판정군을 선택. 단일 변수 = callee 내용.
- 판정 기준: dispatch 수락 + job 생성 = 파스 PASS(런타임 결과 무관),
  HTTP 422 `error parsing called workflow` = FAIL.
- 브랜치: `probe/s1-mech-only`(기제 control), `probe/s1-fix-oracle`(후보),
  `probe/s1-fix-oracle-ctl`(대조군) — callee 파일을 org 저장소에 두는
  로컬 `./` callee 방식(probe/parse-h6 선례).

## 4군 실측 결과

| 군 | callee blob | dispatch | run ID / 에러 | 판정 |
|---|---|---|---|---|
| 기제 control (정상 세대 81bd6c608) | `22fe84bab7b4ea212820e9bba96dc3357f71f076` | 수락 | run `38272241691` job `s1-mech-good-22fe84 / admission-check` 생성 | **PASS** |
| 후보 1 (env 토큰만 제거, Axiom 5b918a894) | `d06399164e5e79b9b24577cb3ee683a994741213` | **422 거부** | `error parsing called workflow → ./.github/workflows/probe-s1-c1.yml (source branch sha:a7e12529): (Line: 1942, Col: 14): Exceeded max expression length 21000` | FAIL |
| **후보 2 (run 본문 토큰 0건, Axiom 53ccffeae)** | **`09ff52b3596cbf116fa7e6c64b0763f91443f3b2`** | 수락 | run `38273175092` job `s1-candidate-c1 / admission-check` 생성 | **PASS** |
| 대조군 (현 핀 18bb145e9 원문 = ec54a744) | `ec54a744e2bd617142eab277e38891abd75302a1` | **422 거부** | `→ ./.github/workflows/probe-s1-ctl.yml (sha:5dec9c5c): (Line: 1940, Col: 14): Exceeded max expression length 21000` | FAIL(재확인) |

## 새로 확정된 사실 (quirk Q4 확장 — 2026-10-13 실측)

1. **독 축은 토큰 자체가 아니라 "보간 토큰 보유 스칼라의 길이 한도"다.**
   GitHub 워크플로 파서는 보간 토큰을 포함한 `run:` 스칼라를 표현식으로 취급해
   **21,000자 상한**을 적용한다 — 초과 시 `Exceeded max expression length 21000`
   로 호출 그래프 계획 단계에서 거부(0-job, 체크런 미생성). 이 에러 원문은 본
   오라클이 처음 노출했다.
2. **토큰 없는 스칼라는 일반 문자열로 취급되어 상한을 받지 않는다.**
   26,282자 토큰 0건 스칼라 PASS(후보 2) vs 25,954자 토큰 보유 스칼라 FAIL(후보 1)
   — 길이가 아니라 토큰 보유 여부가 적용 조건이다.
3. 세대별 admission-predicate run 스칼라: 22fe84(정상)=19,340자+토큰 PASS /
   4acfc682(H6)=25,766자 FAIL / ec54a744(현 핀)=25,955자 FAIL /
   d06399164(후보 1)=25,954자 FAIL. #780이 후보-delta leg 주석·토큰으로 스칼라를
   21k를 넘게 확장한 시점부터 마비가 시작된 관측과 정합.
4. **승인 우회법 확정**: run 본문의 모든 이벤트 소득 값을 스텝 `env:` 매핑으로
   운반해 run 본문 토큰을 0건으로 유지한다(ADR-0033 §E no-new-tokens, quirk Q4의
   환경변수 경유 SL02_* 패턴 확장). env 매핑의 토큰은 run 스칼라 한도와 무관하다.
5. 0-job 실패 run은 **rerun 불가**(`This workflow run cannot be retried`,
   HTTP 403) — 재판정에는 새 이벤트(synchronize 등)가 필요하다.

## 착지 및 짝 행위

- Axiom PR #795: blob `09ff52b35` + TWS/epoch manifest 동일 커밋 회전(3자 일치),
  `make check-epoch-transaction` PASS, `make check-workflow-shell-syntax` PASS
  (158 블록 0 실패).
- 조직 핀 회전: Archright/.github PR #188(merge `bbd596a4`) — admission-gate
  callee 핀 18bb145e9 → 1ce590484. `pin-promotion-gate`(DEBT#473)는
  `vars.AXIOM_PIN_ALLOWLIST` break-glass에 `09ff52b35`를 추가해 통과(선례:
  #185의 4acfc682). Axiom main 승격 후 allowlist 정리 대상.
- 최종 관측 증거: #795의 병합 큐 경유 GitHub 네이티브 MERGE.
