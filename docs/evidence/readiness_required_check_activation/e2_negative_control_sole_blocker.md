# E2 — 음성 대조(sole-blocker): NO-GO가 실제로 병합을 차단한다 (PR #124)

> DEBT#537 청산 증거 체인의 E2. ADR-0037 §4 선례에 따른 activation 계약의 음성 대조.
> 원본 관측: `raw/pr2_observations_pr2a.json`, `raw/pr2_checks_pr2a.txt`.

## §1. 프로브 설계 (PR-2a)

- **돌연변이**: `config/readiness_policy.json` `r1.contractCommands`에 존재 불가능한 명령
  `"definitely-nonexistent-cmd-probe2a"` 추가 → 수집기 `commandExists=false` 관측 유도.
- **PR #124** `probe/pr2a-sole-blocker` (head `7d7000f60c834d13b96578b2d0727465d48203e9`),
  병합 금지 프로브(큐 미진입 — trustSurface v1.23.0 수정 포함 PR의 admission-check
  오염 방지, 관측 스크립트 계약 §규칙).

## §2. 관측 (2026-11-16 UTC, run 43914508144)

| 항목 | 관측값 |
|---|---|
| readiness-verdict check-run | **FAILURE** (잡 133468585538, 17:10:51Z→17:14:29Z) |
| 게이트 판정 원문 | `verdict: NO-GO`, `R1 = FAIL`, `R5 = FAIL`, `failureCategory: CONTRACT_FAIL` |
| 인과사슬 | commandExists=false → R1·R5(critical) FAIL → NO-GO → 게이트 exit 1 → check FAILURE |
| 나머지 보고 required 체크 | axiom-operational-slice·bsec-integrity·debt-registry-gate·generation-acceptance·publication-integrity **전부 pass** (admission-check는 PR venue에서 구조적 미보고 — PR #121과 동일) |
| ruleset 등록 | 7 contexts에 `readiness-verdict` 포함, required=true |
| PR 상태 | `mergeable_state: blocked`, **0 병합**, 관측 후 미병합 close |
| sole-blocker 교차표 | nonGreenRequiredContexts = `[admission-check(미보고), readiness-verdict]` — **보고된 체크 중 유일 실패** |

## §3. 증명하는 것

**기존 required check들이 모두 성공하더라도 readiness가 NO-GO이면 GitHub가 병합을
막는다** — DEBT#537이 기술한 "모든 required check가 green인 상태에서 NO-GO가 조용히
병합되는" 갭의 폐쇄를 실운영에서 실증한다. 스킵=Success 함정 방어(스펙 §4 잡 헤더
`needs`+`!cancelled()`)는 E3(선행 실패 후에도 판정 잡 실행)·E4(취소≠성공)에서
관측된다.
