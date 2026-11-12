# OBSERVATION — ①' width-64 arithmetic slice (u64 plain + admission, v1.2)

실험 사전등록: `experiments/u64-add-2026-11-02/FREEZE.md` (7-field identity + 예상 판정표)
착지: Axiom @ MERGE_SHA `ed9cab36d5ad6bea9f43c859f9d87033162647e6` (PR #1206, GitHub 네이티브 MERGE, parents=2, mergedAt 2026-11-02T04:17:22Z, admission-gate run 41386286028 success)
작업 브랜치: `work/u64-add-2026-11-02` (impl `9c081ed95` → pin `3187ca31a` → arch-debt `ab342eee4`)
작성: 2026-11-02, 주 에이전트 독립 관측 (구현 agent-66, 전량 주 에이전트 재검증)

## 1. FREEZE 예상 vs 실측 (5/5 일치)

| target | FREEZE 예상 | premerge (9c081ed95, detached clean) | cold (MERGE_SHA ed9cab36d) |
|---|---|---|---|
| u64_add | verified + certPath + irHash, exit 0 | verified, cert `8fd2dae5…87`, exit 0 | verified, cert `8fd2dae5…87`, exit 0 |
| u64_add_mutant | failed + CONFIRMED + exit 1 | failed, CONFIRMED, exit 1 | failed, CONFIRMED, exit 1 |
| u64_echo | verified + cert (회귀) | verified, cert `5e7fb809…a9`, exit 0 | verified, cert `5e7fb809…a9`, exit 0 |
| u64_seven_mutant | failed + CONFIRMED, exit 1 (회귀) | failed, CONFIRMED, exit 1 | failed, CONFIRMED, exit 1 |
| u64_seven | unknown "no derivable guard obligation" | unknown — reason ③ D2와 바이트 동일 | unknown — reason 바이트 동일 |

인증서: status=certLeanVerified, kernel=true, axiomsUsed=[Quot.sound, propext] (허용목록 내, sorryAx/native 부재).
cold exits: A=0, B=1, C=0, D=1, E=0 (정확히 FREEZE 예상 exit 패턴).
B cold replay: input.a=594475149730709119, input.b=14852871580170916868 (premerge와 동일 반례),
replay.verdict=rvAgree, replay.subjectGitRef=ed9cab36d…, replay.moduleSha256=5352659d… (fixture lib.rs sha256 일치),
replay.porcelainClean=true, treeMerkle=48e50bfe….
D cold replay: input._x=0 (③ B2와 동일 반례 형태), subjectGitRef=ed9cab36d….
서브젝트 불변: lib.rs=5352659d…, llbc=0d5bb37e…, specs=0e5c5fae… — pre/post 동일 (SUBJECT_IMMUTABLE=yes).
엔진 정체성: BuildSourceHash 6162460016916914928 — premerge와 cold에서 동일 (src는 9c081ed95 이후 불변, pin/debt 커밋은 config/data만).

## 2. 관측된 편차 (FREEZE 표기 → 기계 실측 정정)

1. **replay 극성 표기**: FREEZE "replay rvDisagree" → 실측 CONFIRMED = `replay.verdict=rvAgree` +
   `replay.outcome=rroAgree` (rust_replay_adapter 판정 게이트). `rvDisagree`는 양성 관측(속성이
   실제 실행에서 만족)에 쓰이는 값 — 코드가 정본.
2. **main worktree에서 B·D가 unknown(cvUnresolved)**: replay의 Zero-Footprint post-run 체크가
   `git status --porcelain` 전체(미추적 포함)를 검사 — 선존 미추적 `gh_env.txt`가 porcelain을
   비운 채 유지 불가. ③ premerge `u64_mutant_kernel_decline_dirtyworktree.err`와 동일한 honest
   선례. CONFIRMED는 detached clean worktree에서 관측됨.
3. **detached worktree 첫 실행 cvUnresolved**: `make build`가 빌드 스탬프
   (`src/generated/build_metadata.json`)를 오염 (③ cold run1 퀴크 동일). HEAD 복원 후 CONFIRMED
   관측 (③ run2 패턴) — 이번 cold 러너는 복원을 legs 전에 선제 적용.

## 3. 착지 게이트가 잡은 정당한 drift (문서화된 경로로 해소)

1. **rotation pin drift** (DRIFT changed=21): `bin/reanchor_pin --ref 9c081ed95 --write` →
   게이트 커밋 `3187ca31a`.
2. **architecture_debt canonical hash drift** (Part A ❌ 4건): 이번 슬라이스가 수정한
   ir_to_lean·ir_to_smt_chunk3·ast_to_ir·counterexample_replay가 등록 파일.
   `bin/debt_engine --regen-arch`로 8엔트리 갱신 — 4개는 이번 슬라이스(canonical+raw 모두),
   4개는 main 선존 스테일 canonical 해시(report_cli·wf_render·ir_pipeline_runner·layer1_bmc —
   브랜치 diff 밖, raw 불변). 게이트 커밋 `ab342eee4`.

## 4. 구현 중 발견·수정된 결함 (INV-4 차등 시험)

`rust_extraction_agreement.operandExpr`가 `valueU64`(≥2^63) 상수를 `irLit(op.value)`(부호
캐리어)로 변환해 `irLit(0)`으로 붕괴시키는 결함 — 2^63/2^64−1 차등 벡터가 Nim 레그에서 동일
digest로 떨어지는 것을 포착(Lean 레그는 정확히 구별 → eaMismatch fail-closed가 작동).
수정: `valueU64 != 0`이면 `irLitU64` 2부 리터럴 라우팅. 이것이 계획된 INV-4 폐쇄의 실증이다.

## 5. 범위 밖 발견 (Follow-up — 이 슬라이스 불개입)

`tests/trusted/test_trivial_lean_router.nim` 3건 실패가 **HEAD(ad8f67238)에서 동일 재현** —
이전 슬라이스 2daf2ac65(GAP-8 misc)가 boLt를 `leanBvSlt`(BitVec.slt)로 전환했으나 시험 기대값
(`(x < 100)`) 미갱신. 이 시험은 workflows·tools/ci·Makefile 어디에도 수집되지 않는 비관측
시험이라 방치됨. 이번 슬라이스의 실패 집합은 HEAD와 동일(추가 실패 0건).
→ Follow-up 권고: 시험 기대값 갱신 또는 관측 경로 연결.

## 6. 독립 재현 매트릭스 (동일 판정 4환경)

| 환경 | 상태 | A | B | C | D | E |
|---|---|---|---|---|---|---|
| round1 (main worktree, dirty) | vstate_* 신규 | verified | unknown | verified | unknown | unknown |
| round3 (main worktree, committed clean) | r3state_* 신규 | verified | unknown | verified | unknown | unknown |
| premerge detached (9c081ed95) | pm_state* 신규 | — | **failed CONFIRMED** | — | **failed CONFIRMED** | — |
| cold detached (MERGE_SHA) | cold_* 신규 | verified | **failed CONFIRMED** | verified | **failed CONFIRMED** | unknown |

인증서 해시 `8fd2dae5…87`/`5e7fb809…a9`는 ③ cold acceptance(u64_echo) 및 round1/round3/cold 전
환경에서 동일 (irHash-키 콘텐츠 어드레싱). B·D의 cvUnresolved↔CONFIRMED 전이는 오직 replay의
Zero-Footprint porcelain 조건이며, 판정 본체(spec 기각 + 반례 존재)는 환경 무관 동일.

## 7. 산출물

- `artifacts/premerge/` — round3 5 legs(커밋된 트리) + B·D CONFIRMED legs @ 9c081ed95
- `artifacts/acceptance/` — cold 5 legs + 엔진 정체성 + provenance + 서브젝트 불변 + porcelain + 인증서 2건
- `SHA256SUMS` — 산출물 무결성

## 8. 폐쇄 PR #1208 착지 궤적 (관측 기록 — 이 커밋의 사유)

- `6a248f2ff` 게이트 커밋 → PR #1208 개설(04:36Z) → arm(04:36:34Z) → 큐 진입(04:43:17Z).
- merge_group 8종 전부 success 완료(04:53~04:55Z, admission-gate 41390038028).
- **정체**: 04:49:37/38Z에 org ruleset `axiom-admission-gate`(25218071)·`landing-integrity`
  (23943917)의 required-workflow 핀이 회전됨 — 큐 체크 진행 중. 회전 이전 정의로 green
  판정된 엔트리(#1207·#1208, 빌드 04:42~04:43Z)의 평가가 무효화되어 AWAITING_CHECKS로
  68분+ 정체(#1206 기준선: 체크 완료 24초 후 착지). 회전 이후 빌드된 #1210·#1211은
  정상 착지(06:20:05/45Z).
- **탈크**: 06:11:49Z RemovedFromMergeQueue(타 workstream의 queue_jump 06:04:05Z·
  06:11:51Z·06:20:05Z 체인, actor=wintrover — 감사로그). rearm 판정
  `"green MG + manual dequeue = intentional removal"` → no-arm.
- **재진입 불가의 기계 판정**: 재 arm(06:20:15Z) 후에도 AddedToMergeQueueEvent 없음.
  `enqueuePullRequest` mutation이 사유 반환:
  `Required workflow 'admission-gate' is not satisfied / Required workflow 'landing-integrity' is not satisfied`
  — PR head의 required-workflow 실행(04:36:17Z, run 41389395796)이 핀 회전 **이전** 정의로
  실행되어 만족 불가. mergeable=MERGEABLE, PR-head 5개 required context green 임에도.
- **회복**: 이 커밋(head 갱신)으로 required workflow가 현재 핀 정의로 PR head에서
  재실행되고, arm 재설정 후 큐 재진입·착지를 관측한다. 병합 권한은 계속 GitHub
  merge queue가 행사한다(AGENTS.md §2.3). 타 workstream의 큐 조작(점프/수동 탈크)은
  관측 사실로만 기록한다.
