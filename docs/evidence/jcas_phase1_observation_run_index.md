# Judgment CAS Phase 1 — 라이브 관측 런 인덱스 (cbb8c0db → bf6c72058 세대)

> 선행 문서: [jcas_phase1_cutover_observation.md](jcas_phase1_cutover_observation.md)
> (세대 컷오버 사실 + 관측 프로토콜). 본 문서는 재회전 세대
> (`cbb8c0db`, PR #630 수정 포함)에서의 실측 런 인덱스와 원시 계측값을
> 기록한다.

## 1. 관측 런

| # | run (Axiom repo) | event | base(B) | 결과 | 판정 근거 |
|---|---|---|---|---|---|
| A | 37879586769 | pull_request (synchronize) | `cbb8c0db` | **GREEN** — required check `admission-check` SUCCESS | attest 4/4 green + mint publish SUCCESS + verdict SUCCESS |
| A⁻ | 37878074796 | pull_request (reopen) | `6767884e7`(동결된 구 base) | RED — 13/14 | PR 이벤트 base.sha는 분기 시점 동결(reopen 미갱신) — synchronize로만 전진 |

## 2. Run A — 4종 GO-critical 스텝 원시 계측 (jobs API 로그 라인 타임스탬프)

attest job 113656732277, `[check] GO-critical admission tests` 스텝:

| subject | 결과 | 시작 | 종료 | 벽시간 |
|---|---|---|---|---|
| proof_integrity | `basis=EXECUTED` PASS | 03:34:44.02Z | 03:35:34.49Z | **50.5 s** |
| s1a | `basis=REUSED` SKIP — 커널 0회 | 03:35:34.49Z | 03:35:34.49Z | **0 s** (record 77d92e2c03ff 재검증) |
| d2_golden | `basis=EXECUTED` PASS | 03:35:34.49Z | 03:38:09.00Z | **154.5 s** |
| d2_persist | `basis=EXECUTED` PASS | 03:38:09.00Z | 03:38:42.34Z | **33.3 s** |

- d2_golden이 `basis=EXECUTED`로 **14회 전체 계측 + PASS** — #630 수정
  (카운티드 싱크 배선)이 라이브에서 13/14 fail-closed를 해소함을 실측.
- s1a REUSED: 동일 클로저 키 기록이 선행 사이클에서 발행되어 있어
  계획 단계가 재검증 후 승인 (`no kernel run this attempt`).
- mint publish: `MINT_EVAPPEND: OK — evidence record appended (key
  30ebb5923d92, append exactly-once: 1)` + judgment append는
  `idempotent no-op (judgment key 77d92e2c03ff already stored)`.

## 3. 절감 실측의 현재 경계

- 3종(per-subject)의 ledger append 배선(P7c-x)은 본 문서 작성 시점에
  main 미착지(#626 대기) — 3종은 매 사이클 EXECUTED가 정상 상태다.
- 따라서 현재 라이브에서 관측 가능한 REUSED 절감은 s1a 1종이며,
  3종 EXECUTED 합 **238.3 s** (50.5 + 154.5 + 33.3)가 #626 착지 후
  사이클당 회수될 절감액의 실측 상한이다. (사전 기준값 37+143+23 =
  203 s, 사전 실측 대비 러너 차등 포함)

## 4. 세대 전이 기록 (cbb8c0db → faae54125 → f68049cd9, 2026-10-09)

venue-split(#625, ADR-0032) 착지로 B가 `cbb8c0db` → `faae54125`로 전진하는
동안 관측된 fail-closed 사건과 복구:

| run | event | 주제 | 결과 |
|---|---|---|---|
| 37881146122 | pull_request | PR #629 재실행 (base 전진 후) | RED — `ADM_IDENTITY: FAIL — PR base.sha faae54125 != B cbb8c0db (base moved during admission? fail-closed)` |
| 37881090661 | pull_request | PR #633 | RED — mint-prepare preflight `trusted cert-artifact naming convention missing` ([gh_run_observation_quirks Q4](../../spec/gh_run_observation_quirks.md) grep 패턴 붕괴) |
| 37884232157 / 37884770529 | push(main) / pull_request | 49fdf 세대 전반 | startup_failure — jobs 0개 (Q4a: run 블록 주석 내 미종결 표현식 토큰) |
| 37880739976 | merge_group | PR #629 landing (B=faae) | SUCCESS — 4/4 EXECUTED (29.5 / 165.8 / 79.8 / 17.9 s) |

Q4 수정(#637)·Q4a 수정(#640) 후 org 핀 재로테이션(`f68049cd9`,
Archright/.github #97/#98, 04:57Z)으로 러너 정상화.

## 5. 정상화 후 런 인덱스 (f68049cd9 / bb7f2639e 세대)

| # | run | event | 기준 B | 결과 |
|---|---|---|---|---|
| B | 37886447411 | pull_request | `f68049cd9` | GREEN — preflight venue (attest / mint-prepare / mint-publish / verdict PASS, required `admission-check` SUCCESS) |
| C | 37887034303 | merge_group | `f29444027` (= f68049cd9 + #624, speculative stack) | SUCCESS — **PR #629 MERGED (`bb7f2639e`)** |
| D | 37888236604 | merge_group | `bf6c72058` (= bb7f2639e + #633 그룹) | SUCCESS — **PR #633 MERGED (`7769bb8db`)** (상세 §7) |

Run C — 4종 GO-critical 원시 계측 (attest job 113680350830,
`[admission-tests]` 라인 타임스탬프):

| subject | 결과 | 벽시간 |
|---|---|---|
| proof_integrity | `basis=EXECUTED` PASS | 29.5 s |
| s1a | `basis=EXECUTED` PASS | 154.7 s |
| d2_golden | `basis=EXECUTED` PASS | 76.3 s |
| d2_persist | `basis=EXECUTED` PASS | 16.7 s |

전 종목 EXECUTED가 정상 — 그룹 커밋에 #624(claim-cert-mint coupling)가
포함되어 클로저 입력이 전진한 세대다.

Run C — mint ledger (mint-publish job 113682060630):

- `MINT_PUB: OK — ledger append (first issuance, append 1)` …
  `B=f294440274f5 H=9f14b7099 run_id=37887034303 artifact=subject-certificate-1`
  `gateway_headSha=bb7f2639e gateway_conclusion=success field_binding=ok`
- `MINT_EVAPPEND: OK — evidence record appended (key 0b1edfde8fb2, append exactly-once: 1)`
- `MINT_JUDGAPPEND: OK — judgment record appended (key a20529d63ee5, append exactly-once: 1)`

## 6. 4조합 관측 매트릭스 (cutover 프로토콜 관측 대비)

| 조합 | 관측 런 | 결과 |
|---|---|---|
| (a) PR EXECUTED + append | 37879586769 (Run A, §2) | 3종 EXECUTED + s1a REUSED, `MINT_EVAPPEND … exactly-once: 1` |
| (b) 동일세대 MG REUSED (커널 0회) | 관측 창 내 미발화 — §7 참조 | 착지가 모두 세대 전진을 수반하는 동안 REUSED는 재현되지 않음 |
| (c) 세대 전진 MG EXECUTED | 37880739976 (B=`faae54125`), 37887034303 (B=`f29444027`), 37888236604 (B=`bf6c72058`) | 4/4 `basis=EXECUTED` PASS |
| (d) 교차 사이클 PR REUSED | Run A s1a (record `77d92e2c03ff`) | REUSED — 재검증 후 승인, 커널 0회 |

## 7. (b) 미발화의 기계적 사유 + PR #633 착지 런 (R1)

PR #633은 8f3964930 헤드로 merge queue에 진입해 착지되었다
(merge commit `7769bb8db`, 2026-10-09). 착지 MG 런 R1 = 37888236604
(B=`bf6c72058` = bb7f2639e + #633 그룹 커밋, gateway_headSha=`7769bb8db`,
`field_binding=ok`):

- 4종 전부 `basis=EXECUTED` PASS (proof 30.1 / s1a 164.4 / d2_golden 84.2 /
  d2_persist 18.2 s).
- `MINT_PUB: OK — ledger append (first issuance, append 1)` +
  `MINT_EVAPPEND (key 0e85748e45d9, exactly-once: 1)` +
  `MINT_JUDGAPPEND (key 18639ef53f62, exactly-once: 1)`.

(b)가 발화하지 않은 이유는 결함이 아니라 세대 역학이다: s1a 클로저 키는
커널 tree에 귀속되지만, 관측 창(04:22–05:34Z)의 모든 착지가 B를 전진시켰다
(`cbb8c0db` → `faae54125` → `f29444027` → `bf6c72058`). 직전 착지
(Run C, key `a20529d63ee5`)와 R1 (key `18639ef53f62`) 사이에도 세대가
달라 새 계측이 fail-closed 정상 경로다. Run A 시대(cbb8 세대 정체)에 s1a
REUSED가 관측된 것과 정확히 대칭이다 — **동일 세대가 2회 이상 착지하는
정적 구간에서 MG REUSED가 발화한다**는 예측을 남기며, 이는 다음 정적 구간의
관측 과제로 #626(3종 per-subject append)과 함께 후속 문서의 대상이다.
