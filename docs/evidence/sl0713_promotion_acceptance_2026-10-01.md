# SL-0713 승격 production acceptance — C11 실측 기록 (2026-10-01)

**결정 권위**: Plan 2-A1 (`blue-marvel-jessica-cruz-black-widow.md` C6~C8·C11) · ADR-0025 §C.5 ·
`docs/evidence/sl0713_promotion_binding_2026-10-01.md` · `merge_queue_operation_2026-09-29.md:50` 해소.
본 문서는 Completion Evidence를 **관측값으로만** 판정한다 — 선언 없음.

## 1. 승격 사실 (2026-10-01)

- 승격 PR: **#425** (`feature/sl0713-promotion`) — native MERGE `9c4164bb0f32f7b6ba683ad0681e0e0813e3958c` (parents `1be4e4654` + `beedff6ec`, 2-parent, 12:41:05Z)
- epoch: **N+7** — `config/policy/epoch_manifest.json`: `implementedSlices` ∋ `SL-0713` · `notYetImplementedSlices` ∌ SL-0713 · `productionExecutionPin` = `7539c1638f9e4c3023867f608b9b64c1f2714c06` (무변경 — admission blob 불변)
- catalog: `src/gate/slice_catalog.nim` SL-0713 `implemented: true` (P1/P2/P4 → SL-04 귀속 정정, 증거 라인 :1014/:1284/:1337/:1387 실측)
- 선행 확정: ADR-0025 §C.5 (mode=none [B2](c) 대응) · 결정 바인딩(영구 append 폭발반경) · epoch_transaction_gate L1/L2/L3 PASS (static + --diff)
- 표면 선등록: #424 (surface v43 — 본 문서 경로 CONTROLLED)

## 2. 사전 검증 (승격 PR, 로컬 실측)

- `bin/epoch_transaction_gate` static + `--diff 1be4e465 HEAD`: catalog↔manifest↔engine 3-way 등식 PASS · pin base+head 3-way PASS — EXIT 0
- (P6) mode=none 대응 pre-flight — 실측 런 재현: 36770241367(mode=none): `n_gw=6 sel=success n_bad=0 n_skip=5` · 36771219320(normal): `n_gw=6 sel=success n_bad=0 n_skip=4` — 구 검사식이 두 집단 모두 오차 차단하는 것을 확인하고 갱신
- workflow-shell-syntax 110 블록 0 실패 · check-repository-surface PASS · doc_path_validator PASS

## 3. 본 PR 실측 (acceptance — C11)

본 PR(`#426`)의 admission 런(36864277201, 12:56Z) = 승격 후 **base(B)에 SL-0713이
반영된 최초 candidate** — docs-only 변경이므로 mode=none(derivedEmpty) 경로.
**결과: FAIL-CLOSED 차단 (원문 기록 — 논픽션).**

| # | 실측 항목 | 관측 (원문) | 결과 |
|---|---|---|---|
| (a) | scope_sl0713 발화 | publish job 로그 (12:56:12Z): `[slice-engine] epoch=N+7 implemented=["SL-08","SL-01","SL-03","SL-04","SL-12","SL-10","SL-0713"] sl04=fire sl0713=fire` — (P0)/(P5)/(P6)/(P7) 실행 | **발화 확인** |
| (a-2) | (P5) [B2](b) mode=none 3-way identity | `MINT_PUB_TREE: OK — canonical tree identity (b): testedTreeDigest == tree(github.sha) == certTree == 78ee196eebd4be117d33d61e013f32d83a4e4f09` | **PASS** (§C.5 ③ identity legs 실증) |
| (b) | (P6) [B2](c) — **실패** | `MINT_PUB_JOBS: FAIL — 5 gateway-lane job(s) without conclusion=success — [B2] (c) (fail-closed) (fail-closed)` (12:56:16Z) — **실행된 엔진 = org callee pin `certificate-mint.yml@4b7719e15`(N+5 era, 구 semantics)** — 승격 (P6) 미배포 | **FAIL (엔진 pin 갭)** |
| (b-2) | (P7) ledger append | 미도달 (P6 실패로 스텝 중단) — append 0 | 미발화 |
| (d) | org verdict K | `ADMISSION_GATE: FAIL — needed job 'mint-publish' result='failure' (expected 'success' — skipped/cancelled/failed must block, never green) (fail-closed)` — env 실측: RESULT_ADMISSION=success RESULT_MINT_PREPARE=success RESULT_MINT_PUBLISH=failure RESULT_GATEWAY=success | **FAIL (fail-closed 정상 작동)** |
| (c) | ledger record | side-ref 실존: `refs/heads/axiom/certificates` = `2abbbed537…` (tip tree = subjectId-명명 .json 140건, 역사적 기록) — **N+7 subject append 미발화** (P6 실패로 (P7) 미도달) | 미실현 (본 subject) |
| (e) | native merge | 미해당 — PR BLOCKED | — |
| (f) | 조직 파일 | `Archright/.github` HEAD `d6c6c9a6c…` (07:48Z) — 세션 동안 무변경 | 무변경 ✓ |

## 3b. 차단 원인·해소 (원문 기록)

**원인**: org admission-gate가 callee `certificate-mint.yml@4b7719e153…`(N+5 era —
N+5 이후 certificate-mint는 핀 회전 없음)을 실행하는 동안, B-tree epoch manifest는
N+7(SL-0713 implemented) — slice-engine이 scope_sl0713=fire를 내리고 **핀된 구 엔진의
구 (P6)**(skipped lane job = 실패)이 mode=none·SL-09-notYet candidate(5 skipped lane
job)를 차단. §2.5 Atomic Binding (workflow+pin 결합 = 1 논리 변경) 요구 — 승격 엔진
변경이 org callee pin에 미반영된 상태.

**해소 (별도 작업 — org 측)**: `Archright/.github` admission-gate.yml의
certificate-mint.yml callee pin을 N+7 main sha(`9c4164bb0f32f7b6ba683ad0681e0e0813e3958c`)
로 회전 (선례: org PR #34/#37/#39 — callee 3파일 바이트 동등성 게이트 + SHA 파싱 원칙).
회전 후 본 PR #426을 close/reopen으로 재발화(선례: merge_queue_operation 사고 4)하여
아래 표 갱신 — 그때 (b)는 새 (P6) mode=none 경로, (b-2)는 P7 append 최초 발생, (c) ledger
record 존재, (d) verdict K OK, (e) native merge + push@main 0이 실측된다.

## 4. 판정

**BLOCKED (승격 본체는 main 착지 완료 — N+7)**: C11 acceptance는 org callee pin 회전
(별도 작업) 이후 재발화로 완결. 실패는 전부 fail-closed 표면화(fail-open 0, theater 0) —
P5 mode=none identity 경로는 실전에서 PASS(§C.5 ③ 실증), P6 구엔진 차단은 의도된
epoch-pin 갭. C8(ledger append·NO_CERT 해소)는 pin 회전 후 실측 예정.