# E1 — PR #121 rotation 착지 + 첫 production 실행 녹색 + 스테디 상태

> DEBT#537 청산 증거 체인의 E1. 활성화 후보가 실제로 main에 착지했고, 착지 커밋에서
> required check가 녹색으로 실행되었으며, 정책 미러와 live ruleset이 일치하는 스테디
> 상태에 진입했음을 관측한다. 원본 명령→응답 기록: `raw/rotation_execution_record.md`.

## §1. 착지 (2026-11-16 UTC)

- **후보**: PR #121 `feat/readiness-verdict-wiring`, head `8170dacccffee8fd8394cae529c9f5581c049415`.
- **착지 경로**: MUST-T2a rotation 3단계(위임 기록 `must_t2a_rotation_landing.md` §2):
  1. 큐 0건 확인(mergeStateStatus queued 0; 잔존 `gh-readonly-queue/main/pr-76-…`는 MERGED PR #76의 유물).
  2. bypass 등록 PUT 2026-11-16T16:50:13Z (ruleset version 58030608) — 본문 = live 7-context·5규칙 원문 보존 + `bypass_actors:[OrganizationAdmin, pull_request]`.
  3. REST 병합 16:50:37Z: `gh api -X PUT /repos/Archright/Axiom/pulls/121/merge -f merge_method=merge -f sha=8170dac…` → `{"sha":"e3ec8ae1f475b7cb47cc175fb3694a7babc269f5","merged":true}` — **2-parent native MERGE**(main head 일치, PR MERGED 16:50:39Z, mergedBy wintrover).
  4. 복원 PUT 16:50:55Z (version 58030755) — readback `bypass_actors:[]`, 7 contexts, `RESTORE_IDENTICAL` 실증(`/rules/branches/main` projection 7 contexts·5규칙 동일).
- **우회창 42초**, 드리프트창 14:19:58Z(사전 PUT 58006001) → 16:50:55Z(복원) = **같은 UTC 일(2026-11-16) 폐쇄** — 스펙 §7.3 실충족(E6 §3 정정 참조).

## §2. 첫 production 실행 녹색 (Identity: 착지 커밋)

- **Run 43911956696**: event `push`, head_sha `e3ec8ae…`(**== mergeCommit**), conclusion `success` (16:50:41Z → 17:01:24Z, workflow 415675102).
- **readiness-verdict 잡 133458781756**: success.
  - 판정: **CONDITIONAL GO**, conditions `[R7=FAIL]` (R1–R6, R8 = PASS).
  - **decisionDigest `0bcb25bd79286b356ee382278acf55a60f9eac9f381883a6e61a0ec318f1377b`** — PR #121 자기 실행(pull_request run 43909803169)과 **동일 digest**(venue 간 결정론적 투영 실증).

## §3. 스테디 상태 (정책 미러 == live ruleset)

- main 착지 후 `config/policy/merge_admission.json` = **v1.23.0, 7 contexts**(PR #121이 정책 미러·`src/cli/merge_cli.nim` 이중 결속 동반 — ADR-0037 §6 패턴).
- live ruleset 27097366 readback(2026-11-16T17:27:18Z, operator-promotion-adapter): 7 contexts, 전부 integration_id 15368, enforcement `active`, `bypass_actors:[]`.
- **7 == 7 일치** — 이후 모든 PR의 GPA(generation-acceptance) 이름 해석 정상. PR #121 관측된 GPA 일시 red(run 43882659122 `REJECTED:RULESET_UNAVAILABLE`)은 위임 기록 §2.1에 **예측·기록된** 순서 역전 창의 관측이며, 착지로 해소됨(일탈 정직 기록은 E6).

## §4. 이후 모든 main 커밋에 대한 지속 집행

ruleset이 `readiness-verdict`를 요구하는 한, main으로 향하는 모든 큐 항목은 이 판정의
exit 코드를 병합 조건으로 소비한다. 양성(큐 통과)·음성(#124/#125/#126)·취소(#126)의
실측은 E2–E4, 제3자 재현은 E5, 기계 관계 검증은 E6에 기록한다.
