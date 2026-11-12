# v5 증거 세대 운영 acceptance — 프로토콜 (2026-10-21)

> **분류**: 실행 증거 · **차량**: 이 문서의 착지 자체가 acceptance A다 — 본 PR은 N-제외 `.md`만 변경하므로 판정 closure는 main 현재 트리와 동일한 v5 closure이고, v5 키로는 아직 어떤 기록도 존재하지 않는다.

## 세대 전환 체인 (실측)
| 단계 | 값 |
|---|---|
| v5 코드 착지 | Axiom PR #1012, merge `7120e42f18dae3a730cd548339b2008dc0f83580` (2026-10-21T11:54:21Z) |
| workflow blob (A2 triple) | `db869c65af06c42e48fcb657a2d6b21b5089d293` == TWS `trustedAdmissionWorkflowSha` == epoch `productionExecutionPin` |
| scheme | `JudgmentKeyScheme* = "axiom.judgment.cas.key.v5"` (wire "schema" 멤버 — v4 기록 자연 고아화) |
| org 회전 | org PR #246 (pin-promotion-gate PASS 7s) → org main `2bcbcb8c58a9f36453dc3f2e09751e1eefd60b2b` |
| ruleset 재핀 | 25218071·23943917 모두 `workflows[].sha = 2bcbcb8c…` (readback byte-consistent) |
| controller 핀 | `admission-check.yml@7120e42f…` (attest/verdict 두 곳) |

## A/B/C/D 프로토콜
- **A (신규 v5 증거)**: 본 PR — landing run에서 `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)` + `exec-record[s1a] verdict=PASS basis=EXECUTED` + MERGED. 동시에 **D의 운영 증명**: 이 closure의 논리적 동일 대상에 v4 기록이 존재했으나 v5 키가 일치하지 않아 재사용되지 않았다(신규 실행 선택 = v4 미승격).
- **B (동일 closure REUSED)**: A 착지 후 또 하나의 N-제외 `.md` PR — A가 발화한 v5 기록이 5조건(per-read re-hash 포함)을 통과해 `basis=REUSED`·`decision=REUSED`·`verdict=UNKNOWN`으로 승인, s1a 테스트 skip, MERGED. 착지 소요가 EXECUTED 대비 단축됨을 관측.
- **C (변경 closure의 재사용 거부)**: B 이후 ①의 tree closure 멤버(예: `src/core/results.nim`)에 주석 1행 추가 — ①·⑤가 전진해 기존 v5 기록과 키가 달라지고 신규 실행(EXECUTED+PASS)으로 전환됨을 관측 + MERGED.
- **D (v4 스킴 거부)**: 기계(단위 테스트 — v4 wire ≠ v5 키) + 운영(A의 실행 = 동일 논리 대상의 v4 기록 미재사용).

## 판정 어휘 원칙
`verdict=UNKNOWN basis=REUSED`는 기존 증거의 유효성 재인증이지 실행 결과가 아니다 — EXECUTED/PASS와 동일하게 기록·표현하지 않는다.