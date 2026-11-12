# WP0-b/c 완료 보고서 — Canonical External Execution Context 구현·검증

> Status: COMPLETE (2026-08-27). 근거는 전부 file:line 또는 커맨드 재현분.
> 상위 계획: 계획 v5(승인) / 규범: D1-D4-spec.md / 계약: productization_contract.md §10

## 1. Question
외부 프로젝트(nim-stew@c75502c)가 명시적 ExecutionContext(`--project` + `AXIOM_STATE_DIR`)
으로 수용되어, **subject 트리 무오염(P4)** 하에 `ax prove` 파이프라인이 end-to-end로
실행되는가?

## 2. Context
- PROJECT_UNDER_TEST: nim-stew@c75502c (submodule-free, lockfile-absent)
- AXIOM_REVISION: Axiom@f7dd583ca + WP0 작업분 14파일 (커밋 전, L2 게이트 대기)
- TOOLCHAIN_IDENTITY: nim-2.2.10 | lean-v4.33.0(lake-toolchain 파일) | z3-4.13.3 (빌드타임 고정치 주입)

## 3. Scope
구현: 신규 core/context 모듈, --project 플래그, state 라우팅 11사이트, D2/D3 교정.
미포함(B군): import-graph 범용화, report --project, Execution API daemon, binary/image identity.

## 4. Procedure & Result (핵심 산출)
### WP0-a (문서·정책)
- §10 삽입: docs/spec/productization_contract.md:345-382 (append-only, 기존 344행 무변경)
- 정책키 4개: config/readiness_policy.json R3/R4/R8 (+15/-0), json.tool VALID
- 정합성: CONSISTENT(wp0a-consistency-report.md) / 감사: COMPLETE(wp0a-completion-verdict.md)
- Open Items 확정: §10 번호, prove-only 플래그, zero-diff AXIOM_STATE_DIR + `--project`
  페어링 fail-closed(§10.3 문언 추가)

### WP0-b/c (코드) — 최종 diff 요약(git numstat)
- 신규: src/core/context/run_context.nim(249행, proc 1개 — 나머지 func/template),
  tests/unit/wp0_context_identity_test.nim
- 배선: cli_types.nim(+2 project 필드), axiom_engine.nim(+87/-8: --project 파싱,
  fail-closed 페어링 :904-913, precedence :974-975, runtimeMeta.subject :999-1020,
  toml 경로 해소 :948-957, scope/baseline stateRoot 우선 :296-309,:620-627),
  cli_surface_generated.nim(+10)
- 라우팅(writers→stateJoin): wf_runners.nim(2), selection_state.nim(helper),
  cert_vault_role.nim(:42 default 분기만), metrics_io.nim(2), lean_build_sandbox.nim(4+
  proofs 소스 앵커 :144-151)
- 교정: canonical_verification.nim(+64/-9): D2 captureToolchainIdentity = 컴파일타임
  provenance(NimVersion/BuildEnvZ3Version/staticRead lean-toolchain; gcsafe 복원),
  D3 workdir="<execution>" fsBoundary="<subject>"(:592,598)

## 5. Evidence (명령·결과)
- nim check: run_context/cli_types/canonical_verification/main 전부 SuccessX
  (`nim check src/cli/main.nim` exit=0 — gcsafe 회귀 복원 포함)
- 유닛테스트: wp0_context_identity_test 5/5 [OK]
  (골든벡터 40ce2087…d9, LE 프리픽스, NFC≠NFD, absent 리터럴, tmpdir 통합)
- 회귀: wf_runners_exit_code_test 17 OK, test_s1a_lean_golden 11 PASS(pin 갱신 반영)
- 실측(E2E): `cd nim-stew && AXIOM_STATE_DIR=... ax_wp0c_smoke prove --project .`
  → exit=0, logs/ax_proof_state.json summary.verified=1 failedCount=0
- P4: 성공 런 후 `git -C nim-stew status --porcelain` == EMPTY
- fail-closed: AXIOM_STATE_DIR 미설정 `--project` → stderr 진단 + exit 1, 생성물 0(ls -A = 0)

## 6. Classification
WP0-a/b/c: **Verified** (제품 수직 슬라이스의 기계 판정 불변식 준수 + E2E 성공)
단, M1 사중 술어는 WP5(clean-room 3런) 미실시로 **Incomplete** — 다음 Act 과제.

## 7. Interpretation
Axiom은 이제 외부 프로젝트를 명시적 VerificationSubject로 수용하며 subject 트리를
오염시키지 않는다(쓰기는 state/execution workspace로 라우팅). CWD는 여전히 convenience이며,
identity에는 물리경로가 들어가지 않는다(D3 역할치환 검증: 동일 subject@다른경로 런은
WP5에서 확인 예정).

## 8. Non-Conclusions
- "verified=1"은 Axiom이 자기 커널 스코프의 1심볼을 검증했다는 것일 뿐, nim-stew 코드
  자체의 Verified 아님(R7 비과장 준수). 외부 심볼 대상 검증은 IR 추출 범용화(WP1+) 필요.
- byte-level 재현성(M1/P1-P3)은 아직 측정되지 않았다.

## 9. Incidents & Resolutions (작업 중 실제 발생)
- gcsafe 회귀: execCmdEx 프로브 → 컴파일타임 상수 전환으로 해소(§10 위 코멘트).
- proc-budget(≤950, HEAD==950): 신규 모듈을 func/template화해 정확히 950 유지.
- template 인자명 ≡ 객체 필드명 충돌(`subjectRoot`) → 매개변수명 변경(tmpDir 오류 소멸).
- loadTomlConfig/scope/baseline/sandbox-proofs의 암묵적 CWD 의존 4건 → §10 규칙 적용.
  특히 proofs/는 stateStaged(/tmp/wp0c_state/proofs)로 해소.

## 10. Next Experiment
WP1-M1: import-graph 부분 범용화(core/ 프리픽스 비의존 모드) → nim-stew stew/endian2·bitops2
대상 첫 외부 검증 → clean-room RunA/B/C 3런으로 M1 사중 술어 판정.

## 11. 남은 작업트리 상태 (아키텍트 검토 대기)
14 modified + 2 untracked. 커밋 금지 — L2 `axiom-gate commit` 경로로만.
untracked: src/core/context/, tests/unit/wp0_context_identity_test.nim
