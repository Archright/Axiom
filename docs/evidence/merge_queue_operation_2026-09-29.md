# Merge Queue 운영 실증 — E1–E12 판정 (2026-09-29)

**결정 권위**: `docs/adr/0027-queue-delegation.md` (PROPOSED) · §2.5 CI Epoch Cutover ·
freeze tag `ci-epoch-pre-mq-freeze`(기록: 구 callee 핀 `9021a9a0`, ruleset strict=true, merge_queue 부재, 롤백 참조).
본 문서는 계획의 Completion Evidence를 **관측값으로만** 판정한다 — 선언 없음.

## Terminal Outcome 실측

2-PR 동시 시나리오(X+A, X+B)가 큐를 통해 **X+A+B 조합으로 검증·인증된 뒤 착지**, 착지 커밋이
C1 continuity로 기계 검증됨 — 전부 실측:

| 착지 | merge 커밋 | 시각 | 경로 |
|---|---|---|---|
| #367 (X+A 마커) | `595c1de27eb1` | 10:46:52Z | 큐 (position 1) |
| #368 (X+B 마커) | `54aca0d7f073` | 10:46:53Z | 큐 (position 2, 그룹2 = 검증 시점에 이미 X+A+B) |
| #369 (mint·runner 수정) | `d0d0f39c4` | 11:31:16Z | 큐 |
| #370 (admission·TWS·pin 수정) | `f52e93e8d908` | 12:08:54Z | 큐 |
| #372 (surface v33 정책) | — | 12:29:26Z | 큐 (auto-enqueue 자동 인계 실증) |

## E 판정표

| # | 증거 | 판정 | 실측 (명령/관측) |
|---|---|---|---|
| E1 | merge_queue 규칙셋 | **PASS** | `gh api repos/Archright/Axiom/rulesets/20303214`: `merge_queue` rule = MERGE / ALLGREEN / min-max merge 1:1 / max_build 2 / timeout 120분. 활성화 PUT body diff = 정확히 3항목(strict 전환·룰 추가·그 외 불변) |
| E2 | required check/bypass | **PASS** | 동 ruleset: contexts=`["admission-check"]` (integration 15368), `strict=false`, `bypass_actors=[]` |
| E3 | Phase 0 probe α | **PASS** | `docs/evidence/merge_queue_probe_2026-09-29.md` — 2회 연속 `parents(L)=[B, H_PR]`, head_ref·tree_id 실측, γ 없음 |
| E4 | merge_group 발화 | **PASS** | round-1: fail-closed 6런(결함 감지) → round-2: run 36556838509/36556838573 등 **admission-gate×2·landing-integrity×2·probe×2 전부 success** |
| E5 | X+A+B 트리 | **PASS** | 그룹2(`54aca0d7`)는 #367 착지 **이전**(10:38)에 검증 — `tree=783b5d6b82ec` == 최종 main tree; `git ls-tree origin/main data/mq-probe/`에 마커 A·B 동시 존재; `git diff 3a0d56db8 origin/main` = 2파일 8행 |
| E6 | canary (PR 경로) | **PASS** | #366: callee 핀 상승 후 `admission-check` + `trusted-writer-set-pairing` GREEN, 병합 `3a0d56db8` |
| E7 | continuity | **PASS ×2** | `ax cert continuity --main 595c1de2 --cert cert_g1.json` → **ccPassed**; `--main 54aca0d7 --cert cert_g2.json` → **ccPassed**. cert_g1 subject=(B `3a0d56db8`, H `9159aca9`, certTree `556c1401`=착지 tree); cert_g2 subject=(B **`595c1de2` = 앞 그룹 착지**, H `0231db4d`, certTree `783b5d6b`=최종 main tree) — 스펙큘러티브 체이닝에서도 base 결속 정확 일치 |
| E8 | parents/L==G | **PASS** | `parents(595c1de2)=[3a0d56db8, 9159aca9]`, `parents(54aca0d7)=[595c1de2, 0231db4d]` — [B, H_PR] α 형태; 착지 SHA == 10:38 merge_group 검증 SHA (**L==G**, 양쪽) |
| E9 | artifact candidate-key | **PASS** | run 36556838509 artifacts: `admission-check-595c1de27eb131c6b0f9707ba814e0e5b21e556c` (G 기반, PR 번호 없음) + `subject-certificate-1` (E7의 cert 원본) |
| E10 | 우회 거부 | **PASS** | `gh pr merge 369 --admin --merge` → exit 1: `Repository rule violations found / Required workflow 'admission-gate' is not satisfied / Changes must be made through the merge queue` — bypass_actors=[]가 연산 수준에서 작동 |
| E11 | 문서 계약 정합 | **PASS** | ADR-0027 main 존재; `merge_admission_controller`의 "pole은 폐기" 3건 전부 **supersession 문맥**으로 개정(`2026-09-29 ADR-0027 supersede`); Owner #11 amendment·#13 확장·C1의 `[ADR-0027 Phase 0 측정 확정 — α]`·canonical_run_graph candidate-key 갱신 모두 main 확인. 잔존 `admission-check-<PR>` 인용은 ADR-0027 본문의 개정 대상 서술뿐 |
| E12 | ledger cert | **PARTIAL (사전 존재 소굴)** | 원장 append는 `scope_sl0713=NO-FIRE`로 N+6 epoch부터 **의도적 휴면**(`slice_catalog`: "SL-0713 미정착 — D6/[B2] 별도 승격 slice 대기") — merge_group 변경과 무관(09-29 전 PR 런에도 미발화). cert는 런 아티팩트로 발급·[X]3 결속 성공(P4 `c_head == SUBJECT_HEAD (α subject identity)` 로그 실측), E7은 그 아티팩트로 검증 완료. 별도 후속(슬 승격)으로 분리 |

## 사고·교훈 기록 (fail-closed가 잡아낸 것)

1. **E2E 라운드 1 결함 2종**: full-ref 비교(`merge_group.base_ref` = `refs/heads/main` ≠ `main`, 5곳) + symbolic OID(`B="HEAD~1"` 미해석, 2곳) — merge_group 첫 실전에서 fail-closed 2건 실패로 감지 → #369/#370 수정. **probe 없이는 운영에서 터졌을 결함**.
2. **callee 핀 고아화**: 통합 SHA `01a977ff6`를 임시 브랜치 tip에 핀 후 force-push → 원격 ref 도달 불가 → 게이트 `uses` 해석 zero-job failure → org PR #32 교정. **원칙: 핀은 안정 ref**(현재 `0dc883949` = main 조상 = 영구 도달 가능).
3. **핀 SHA 수기 생성**: 교정 시 12자 prefix만 보고 나머지 28자를 직접 작성 → **미존재 커밋**을 핀에 부착 → 전 런 실패 → org PR #33에서 `git ls-remote` 실측값으로 교정. 워크플로의 40-hex fail-closed 원칙이 핀 입력에도 필요함을 스스로 실증 — **SHA는 소스에서 파싱만**.
4. **required-workflow 핀 무효화 메커니즘**: callee 핀 변경 = 열린 전 PR의 `Required workflow 'admission-gate'` 요건 무효 → 큐 진입 거부(`enqueuePullRequest` 명시 에러). 해소 = close/reopen으로 재발화. 새 callee 없이는 어떤 PR도 큐에 못 들어가는 fail-closed 속성.

4. **빈 커밋 병합(사고 5호)**: evidence 본문을 `git add` 없이 L2 커밋 → 신규 untracked 파일 미포함 **빈 커밋**으로 PR이 files:[]로 병합됨. 커밋 exit 0은 무효 판단 불가 — **커밋 후 `git show --stat`의 산출물 포함을 기계 검증**. 본 문서는 복구 커밋으로 재착지(본 PR).

5.5 **규칙셋 이름 필드 셸 문자열 + 동시성 레이스(close-out)**: 형제 세션이 `queue-probe` 스코프로 이중 규칙셋을 생성(16:27 같은 초 last-writer-wins 레이스, `24162466` 파라미터 임시 변이 → 16:48 원상복구), `24164452`의 name에 셸 조건문 문자열이 저장됨. agent-12의 identity 게이트가 fail-closed 중지 → 원인은 PR #365 부록으로 규명 → ref 폭발반경 실측 후 id 승인 삭제. **교훈: API 필드는 셸 평가 금지(리터럴 취급), 이름≠식별자 — id+ref+rules로 식별.**

## 잔여·후속 (Out of scope 분리)

- **SL-0713 승격**: ledger append(D6 exactly-once + [B2]) 복원은 별도 epoch 승격 slice (사전 존재 상태, 카탈로그에 명시된 대기 항목). **계획 필요 — G1/G2b 승격 트랜잭션 + D6/[B2] 준비성 판정(결정 바인딩) + 영구 append 폭발반경 설계.**
- **scratch ruleset 정리 — 완료 (2026-09-29 close-out)**: `24162466` 삭제(204→404, identity 3중 게이트 통과) · `24164452`는 이름 필드가 셸 조건문 문자열(`$( [ $id = 24164452 ] && … )`)로 identity 게이트가 fail-closed 중지 → 원인 규명(동시성 사고 부록 = 병행 세션 생성, PR #365 부록) 후 **ref=`queue-probe` 한정 폭발반경 실측으로 오케스트레이터 id 승인 삭제**(204→404). 최종 인벤토리 = 프로덕션 6건만 무손실.
- **핀 canonical화 — 완료**: callee 핀 = Axiom main tip `3156f9246…` (org PR #34, callee 3파일 바이트 동등성 게이트 + ruleset 24041674 1필드 diff 증명 + callee 라인 역검증). 불변식: **pin == main tip** (content-equality 추론 불필요).

## §2.5 시퀀스 매핑

freeze(`ci-epoch-pre-mq-freeze`) → record(태그 메시지에 핀·ruleset 상태) → 측정(probe α×2) →
new epoch(callee 핀 3회 상승, 각각 atomic: 코멘트/파일·SHA 결속) → short validation(canary #366) →
canonical cutover(merge_queue 활성화 PUT) → **production acceptance(본 문서 E1–E12)** →
rollback(freeze 태그로 핀·ruleset 복귀).
