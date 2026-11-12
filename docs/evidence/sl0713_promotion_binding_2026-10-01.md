# SL-0713 승격 결정 바인딩 — D6/[B2] 준비성 판정 + 영구 append 폭발반경 (2026-10-01)

**결정 권위**: AGENTS.md §0.10 (Decision Binding Framework) · `docs/spec/decision_binding_framework.md`
· ADR-0025 §C.5 (mint [B2](c) mode=none 재조정 메모 확정) · `tools/ci/epoch_transaction_gate.nim`
(S0-c — 카탈로그+매니페스트+엔진+pin 4-way) · freeze tag `ci-frozen-2026-09-30` (롤백 기준).
본 문서는 `docs/evidence/merge_queue_operation_2026-09-29.md:50`의 후속 항목
("계획 필요 — G1/G2b 승격 트랜잭션 + D6/[B2] 준비성 판정(결정 바인딩) + 영구 append
폭발반경 설계")을 **결정 바인딩으로 해소**한다.

---

## 1. D6/[B2] 준비성 판정 — READY (승격 실시)

판정 대상: SL-0713 승격 후 certificate-mint publish stage가 매 candidate에서
시행할 (P0)/(P5)/(P6)/(P7) — [B2] (b)/(c) + D6 exactly-once ledger append.

| 구성요소 | 위치 | 상태 (실측) |
|---|---|---|
| (P0) Publish activation guard | `certificate-mint.yml:1014` (scope_sl0713) | 실존 ✓ |
| (P5) [B2] (b) canonical tree identity | `certificate-mint.yml:1284` (scope_sl0713) | 실존 ✓ — tested-tree-digest 소비 (SL-10 산출, mode 무관) |
| (P6) [B2] (c) gateway lane conclusion | `certificate-mint.yml:1337` (scope_sl0713) | 실존 ✓ — §C.5 mode=none 대응으로 갱신 (본 승격 PR 동봉, G2b path 1) |
| (P7) D6 + FF-CAS 3분기 reconciliation + exactly-once | `certificate-mint.yml:1387` (scope_sl0713) | 실존 ✓ — `ax cert ledger-append` + 재실행 멱등(append 0) + 첫 발행 1 |
| ledger append CLI | `src/cli/cert_cli.nim` (`ax cert ledger-append/list/verify`) | 실존 ✓ |
| ledger side-ref (append-only) | `src/verification/ledger_side_ref.nim:401-402` (PATCH `refs/heads/axiom/certificates` `force:false` CAS — 422 원자 거부) | 실존 ✓ |
| 원장 테스트 | `tests/verification/test_attestation.nim` P11 (fake-transport append→tip→list·verify), P13 (dup-subject 재발행 거부) | 실존 ✓ |

선행 확정: ADR-0025 §C.5 (mode=none candidate의 [B2](c) 대응 — scheduler 없는
lane 결론 semantics) · 본 승격 epoch_transaction_gate L1(G1 원자 페어)/L2(3-way
등식)/L3(pin 3-way) 통과 · `productionExecutionPin` 무변경 (admission blob 불변).
판정: **승격 착수는 준비성 충족 — READY.** (모두 실존/기계 검증 대상이며
신규 authority·신규 워크플로 추가 없음 — §2.6 AUTHORITY/ARTIFACT 불변.)

## 2. 영구 append 폭발반경 — 결정 바인딩 (HARD)

**바인딩 대상**: 승격 후 mint-publish (P7)이 발화하는 모든 candidate — NORMAL
(mode=full/selected) 및 mode=none(docs-only, derivedEmpty) candidate 포함.
(P0)/(P5)/(P6)/(P7) 동시 발화 — 인지된 부수 효과.

1. **append-only 영구 기록**: candidate마다 `refs/heads/axiom/certificates`
   side-ref에 **영구·불변** ledger record 1건이 append된다 (first issuance
   append=1; 멱등 재실행은 append=0 — exactly-once). 기록은 재작성·삭제·prune
   되지 않는다.
2. **FF-CAS 강제**: append는 fast-forward-only CAS (`force:false`) — 동시 경합
   422 원자 거부로 lost update·중복 엔트리 차단. **force-push 금지** (레거시
   publisher publishM 경로는 CI=0에서 삭제 완료 — 재도입 금지).
3. **실패 = 착지 차단 (fail-closed)**: append 실패 → (P7) CAS 3분기
   reconciliation (재조회 → (A) record 존재∧일치 → PASS(0) / 불성립 → FAIL) —
   불성립 시 publish FAIL → cert 미발행 → `certRequired`(merge_admission.json
   v1.6.0) NO_CERT → verdict K `admission ∧ mint-prepare ∧ mint-publish ∧
   gateway` 실패 → **merge 불가**. 완화·재시도·cooldown 없음 (권한 재분석 후
   결정 — AGENTS.md §2.2-8).
4. **폭발반경 합의**: 발화 면적 = queue를 통과하는 모든 candidate (candidate
   수만큼 영구 기록). 이 부담은 예상·승인된 것이며, ledger가 성장하는 것은
   정상 상태(append-only 인증 로그)이다.
5. **변경 금지 (HARD)**: 이 바인딩(영구·append-only·candidate당 1건·실패=차단)을
   무효화·축소·재기록·prune 하려면 **별도 결정 바인딩/ADR 개정**이 선행되어야
   한다 — 본 문서가 권한이며, silent rewrite·force-push·prune은 §0.9
   (Theater) 위반으로 간주한다.
6. **관측 계약**: append 발생은 (P7) 로그 `MINT_PUB: OK — ledger append (first
   issuance, append 1)` / 재실행 `append exactly-once: 0`으로 기계 기록되며,
   `bin/ax cert ledger-list` / `ledger-verify`로 검증 가능 (C8·C11 판정 기준).

## 3. 기록·연결

- 해소 항목: `docs/evidence/merge_queue_operation_2026-09-29.md:50` — SL-0713 승격
  ("계획 필요") → 본 문서 + SL-0713 epoch N+7 승격 PR (2026-10-01).
- 검증 게이트: `tools/ci/epoch_transaction_gate` (L1/L2/L3) — 본 승격 PR에서
  통과 필수.
- acceptance: `docs/evidence/sl0713_promotion_acceptance_2026-10-01.md` (C11 —
  승격 이후 별도 PR에서 실측 기록).