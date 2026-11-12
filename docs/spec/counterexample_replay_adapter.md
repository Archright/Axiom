# Counterexample Replay Execution Adapter — S4-S5 계약

> **Status**: Implemented contract — S4-S5 of the nim-stew `PROPOSITION_DISPROVED`/`NO_BUG_PROVED` 운영 판정 milestone
> **Created**: 2026-10-08
> **AGENTS.md 참조**: §0.5 (문서 우선), §0.9 (극장 금지), §0.12 (제품 계약 선행)
> **Related**: [bug_verdict_glossary.md](./bug_verdict_glossary.md) §2.2 (PROPOSITION_DISPROVED와 공용 4요소), [authority_contract.md](./authority_contract.md) §2 (Authority ≠ Adapter)
> **Module**: `src/verification/counterexample_replay.nim` (adapter) · `src/verification/solver_adapter.nim` + `src/verification/batch_uap/ir_pipeline_runner.nim` (capture/transport)
> **I/O 경계 선언**: 본 모듈은 실제 서브프로세스(`nim c -r`, read-only git)·파일 I/O를 수행한다. 파일 헤더의 `axiomIoBoundary` 선언 마커(§0.6 I/O 경계 선례 — `counterexample_validator.nim`)가 nimtry purity 쿼리의 모듈 스킵 근거이고, 모든 I/O proc은 `{.axiomEffect: IOEffect.}`를 명시한다. `src/gate/**`는 FROZEN 표면이라 레지스트리 수정 없이 선언적 마커로 해소한다.

---

## 1. Authority = 0 (HARD RULE)

이 어댑터는 **관측 전용**(Authority ≠ Adapter)이다. 승격 권위는 기존대로 P4 `finalizeVerdict`(cvConfirmed → vsDisproved, `counterexample_validator.nim` DECISION-0312)에 그대로 있다.

- 파이프라인은 **cvConfirmed 승격 결과(vsDisproved)에 한해서만** 어댑터를 발동한다.
- **replay 동의(rvAgree)** → vsDisproved 유지 + PROPOSITION_DISPROVED payload 완성.
- **그 외 전부(rvDisagree, rvUnavailable)** → 호출부가 fail-closed로 cvUnresolved(=rkCandidateCounterexample Inconclusive)로 강등한다. 승격 권위 자체는 변경되지 않는다.
- 어댑터는 판정 값을 생산하지 않는다. `ReplayVerdict`는 관측 분류이지 verdict 어휘(vr*/vd*/cl*)가 아니다.

## 2. S4 — 반례 payload 캡처·운반

1. **모델 캡처**: assert 기반 스크립트(= `(check-sat)` 포함)에 `(get-model)`을 발행한다. SAT 답변은 구체 변수 배정(`(define-fun …)`)을 운반하고, UNSAT 시 Z3의 `(error …)` 응답은 `classifyOutput`(괄호 행 무시)과 `extractCertificate`(`(error …)` 스킵) 모두가 무시하므로 **UNSAT 경로는 바이트 동일하게 유지**된다. 캡처 비용은 SAT일 때만 발생한다.
2. **구조화**: SAT 출력은 `parseModelBindings`(`core/types/obligation_evidence.nim`)으로 파싱되어 `SolverOutcome.modelBindings`에 적재되고, `modelToTestInputs`(`verification/symbolic_test_synth.nim`)으로 주체 파라미터 순서의 exact Nim 입력 리터럴로 사상된다.
3. **운반**: cvConfirmed 승격 시 1차 모델의 원시 출력이 `VerificationResult.model`에 적재된다 — `evidenceVerdict`의 승격 분기(`ir_pipeline_runner.nim`)가 `finalizeVerdict` 결과에 `ce.model`(= `certificate.solverMetadata`, `(get-model)` 응답 포함 원시 출력)을 명시 적재한다. 이 적재는 메타데이터 운반이지 판정 변경이 아니다.
4. **인증서 반영**: `IrPipelineResult.counterExample`(신규 필드, 기본 @[])이 `toProofCertificate`의 기존 슬롯 `ProofCertificate.counterExample`(`src/engine/proof_certificate.nim:65` — 새 표면 아님)로 투영된다. 슬롯은 **replay 동의 생존 시에만** 비어 있지 않다. cert JSON 서명은 Ed25519가 전체 payload를 커버하므로 별도 서명이 없다.
5. **CAS 배제**: 실패·미확정 replay는 reusable CAS에 들어가지 않는다(`evidence_cas.nim` `isReusableOutcome` 원칙 — ALL-PASS만 저장).
6. **호출 규모 보존**: BMC 레인의 Z3 호출은 `runZ3CheckViaIR(smtScript & '\n' & "(get-model)", …)` — 앵커된 `runIrPipeline`의 effective-SLOC span을 변위시키지 않는 1:1 치환이다(`'\n'` char 리터럴 분해 이유는 [effective_sloc.md](./effective_sloc.md) Policy Matrix의 escape-`\n` 확장 quirk 참조).

## 3. S5 — replay Execution Adapter 동작

발동 조건: cvConfirmed 승격(vsDisproved) — `runIrPipelineWithCas`의 후처리 블록(`result = runIrPipeline(…)` 직후, 캐시 적재 전)에서 진입점 **`replayConfirmedDisproof(subjectRepoRoot, sourcePath, funcDef, modelRaw)`**을 호출한다. `runIrPipeline` 본문은 변경하지 않는다(앵커된 소스 메트릭 보존). 레인 게이트: `verification.status == vsDisproved ∧ provenance ≠ vpInductiveLoop ∧ model 비어있지 않음` — CHC/Spacer 인덕티브 레인의 모델은 전이 관계 증인이지 함수 진입 exact input이 아니므로(루프 replay는 범위 밖) 제외한다. 절차:

0. **exact-input 게이트**: `replayConfirmedDisproof`는 모델이 **모든** 주체 파라미터를 바인딩했을 때만 replay한다. `modelToTestInputs`는 미바인딩 파라미터에 타입 기본 리터럴(예: bv64 → "0")을 채우므로, 부분 모델을 replay하면 기본값 입력이 솔버의 반례인 것처럼 제시되는 극장이 된다 — 부분 바인딩은 rvUnavailable(fail-closed)이다.

1. **주체 바인딩 측정**: `moduleSha256`(실행 전), `subjectGitRef`(`rev-parse HEAD`), `subjectTreeMerkle`(`rev-parse HEAD^{tree}`). git 바인딩 실패 = rvUnavailable(fail-closed — exact commit 없이 PROPOSITION_DISPROVED 불가, glossary §2.2 요소 1). **주체 저장소 루트는 주체 모듈의 git toplevel에서 발견된다**(Q5 — 외부 `--project` 런이 Axiom 저장소 소재 셀프커널 콜래트럴을 증명할 때 신원·워크트리 안정성·컴파일 루트가 모두 모듈의 저장소를 기술해야 한다; `subjectRepoRoot` 인자는 발견 실패 시 폴백).
2. **하니스 합성**: `$AXIOM_STATE_DIR/.axiom/tmp/replay/<digest16>/` 아래 wrapper 하나. 주체 모듈은 **컴파일 플래그 `--path:`로만 resolve되는 `include` 스플라이스**로 관찰된다(Q6 — 커널 콜래트럴 심볼은 대부분 비공개라 `import`로는 원리적으로 도달 불가; 주체 트리 무변경 — Zero-Footprint Integrity). plain 하니스 컴파일은 주체 저장소의 nimble `requires` 루트와 툴체인 루트를 추가 `--path:`로 부착한다(Q5 — skip 플래그가 config 주입을 평가하지 않으므로). d2-agent 스탬프 템플릿 경로는 Q4 dep 해석 그대로 — 명령 바이트 동일.
3. **실행 (언어 분할 어댑터)**: 어댑터 표면은 **언어 분할(language-partitioned)**이다. **Nim 어댑터는 기존 그대로**(변경 없음): repo 고정 nim(2.2.10)으로 `nim c -r` 실행, GateEnvLock 측정 방식과 동일한 트리플(nimVersion/nimHash/stdlibHash — `precompile_gates.buildCurrentFingerprint` 동일 측정)을 fold에 기록. 선례: `gate_hook.nim` nim c 실행. 그 옆에 **Rust 어댑터**(`src/verification/rust_replay_adapter.nim` + 리터럴 투영 `src/verification/rust_symbolic_test_synth.nim`)가 병존한다 — 새 게이트·새 권위·새 verdict 없이, 동일한 `AXIOM_REPLAY_BEGIN/END` 마커 프로토콜과 동일한 `rv*` 관측 어휘(`rvAgree`/`rvDisagree`/`rvUnavailable`)와 콘크리트 평가(`evalConcreteIr`)를 재사용한다. Rust 어댑터는 주체 `.rs`를 `include!`로 컴파일 시점 스플라이스하는 하니스(주체 트리 무변경)를 `rustc --edition 2021`로 컴파일한 뒤 실행하며, 도구 신원은 **선언 pin이 아니라 실측값**을 기록한다: rustc 버전, `<sysroot>/bin/rustc` 바이너리 해시, `lib/rustlib/components` 해시 + 실측 컴포넌트 셋, active channel, rustup profile (`docs/spec/rust_toolchain_quirks.md` Q1 — pin 파일 단독은 설치 환경을 결정하지 않는다). declared pin이 제시되면 실측 채널이 이를 만족하지 못하거나 검증 불가능한 경우 fail-closed다. (측정 quirk: Nim `findExe`는 rustup shim 심링크를 다중 호출 대상으로 resolve하므로 resolve된 경로를 exec하면 rustup CLI가 dispatch된다 — rustc 실행은 항상 PATH 이름으로 수행하며 자세한 것은 어댑터 모듈 헤더 참조.)
4. **관측**: stdout + exit code 기록. 마커(`AXIOM_REPLAY_BEGIN/END`) 사이의 관측값이 함수의 실제 반환값이다.
5. **사후 무결성**: 모듈 재해시 + 실행 전/후 **상대 비교**(predicate v2
   `worktreeStable`, 2026-11-03 복구 — subject inputs digest·
   `git status --porcelain --untracked-files=all` 출력·`git diff HEAD` 출력의
   pre/post 해시 동일성; repo 전체 porcelain **공백은 요구하지 않는다** —
   사전 노이즈는 비교 양변에 존재하므로 봉인을 깰 수 없다). 드리프트 = rvUnavailable.
6. **합의 판정(순수)**: 관측값 + 모델 입력으로 위반된 postcondition 집합을 콘크리트 평가(`evalConcreteIr` — 인증 서브셋 외 연산은 none = fail-closed)한다. **propertyHolds == false 가 replay 동의**다. propertyHolds == true는 솔버 모델과 모순(rvDisagree), 평가 불가는 rvUnavailable이다.
7. **기록**: `replayRecordPayload` — verdict/exitCode/subjectGitRef/treeMerkle/moduleSha256(±afterRun)/worktreeStable(+subjectInputsPre/Post·repoFootprintPre/Post)/nimVersion/nimHash/stdlibHash/hostPlatformId folds가 `input.*`(exact input, 요소 2)·`propertyViolated=`(위반 서술, 요소 3)과 함께 counterExample 슬롯에 적재된다(요소 4). Rust 어댑터는 동일 롤에 실측 Rust 도구 신원(rustVersion/rustcHash/componentsHash/rustChannel/rustProfile/rustComponents/declaredPin)을 추가한 `rustReplayRecordPayload`를 사용한다.

**승격 규칙 불변 (fail-closed promotion — 변경 없음)**: 두 어댑터 모두 Authority = 0 관측자다. 솔버 sat 단독으로는 PROPOSITION_DISPROVED가 발행되지 않으며(`batch_uap/ir_pipeline_runner.nim` 1450-1458 기존 fail-closed 게이트), Rust 주체의 PROPOSITION_DISPROVED에도 **Rust 실행 관측(rvAgree)**이 요구된다 — Rust 어댑터가 그 관측을 생산한다. replay 불일치(rvDisagree)·불가용(rvUnavailable)은 기존대로 호출부가 `vsDisproved` → `makeInconclusive(rkCandidateCounterexample)`로 강등한다.

## 4. 수용 기준 (Acceptance)

- 유닛(`tests/unit/test_counterexample_replay.nim`, `TESTS_FAST_UNIT` 등록):
  - 실제 z3 SAT 시나리오에서 `(get-model)` 구체 배정 캡처 → exact Nim 입력 사상.
  - UNSAT 회귀: `(error …)` 응답이 인증서·상태를 오염시키지 않음.
  - 실제 `nim c -r` 하니스가 합성 fixture의 위반을 재현(rvAgree) / 모순을 감지(rvDisagree) / 바인딩 부재를 fail-closed(rvUnavailable).
  - `replayConfirmedDisproof` 파이프라인 진입점: 동의 시 PROPOSITION_DISPROVED payload 조립 / 모순 시 fail-closed / 부분 모델 exact-input 게이트.
  - `ProofCertificate.counterExample` 슬롯 투영(비었을 때 기존 경로 zero-diff).
  - 셀프커널 콜래트럴 해석(Q5/Q6): `include` 스플라이스 렌더, nimble `requires` 이름 파서, `ceReplayModulePath` 저장소 루트 후보, 중첩 모듈 디렉터리 + 비공개 심볼 + 모듈 저장소 신원 바인딩의 실 `nim c -r` 종단.
- 루프 CHC 강등 갭(`ir_pipeline_runner.nim` 723-747 대역)은 범위 밖 — 손대지 않았다.

### 상류 결함 관찰 (어댑터 범위 밖 — 2026-10-19 defect-leg 기록)

어댑터가 정직한 관찰자로서 노출한 파이프라인 결함 2건 — 어댑터는 fail-closed로
정확히 기각하며, 해소는 obligation-lowering/IR-encoding 하류에서 후속 작업:

1. **calcDynamicTimeoutCore** — 파이프라인 BMC 스크립트가 `minDynamicTimeoutMs`/`maxDynamicTimeoutMs` 상수를 SMT 심볼로 미해결 방출(`(error "unknown constant minDynamicTimeoutMs")`)하고, Z3는 오류 응답 뒤 처리 가능 조각에 `sat`을 답해 (0,0,0,0) 모델을 운반했다. 실제 실행은 result=5000으로 사후조건이 **성립** — 정직한 재생은 이 가짜 반증을 rvDisagree로 반박한다(fail-closed cvUnresolved 유지).
2. **proximityScore** — typed-obligation lowering이 classic 스크립트를 첫 생성 의무(div overflow — `interfaceDistance`만 참조)로 대체(`ir_pipeline_runner.nim:1180`)해 모델이 애초에 `nodeCount`를 선언하지 않는다. 정직한 BMC 스크립트는 in-domain **UNSAT**(위반 없음)다. exact-input 게이트의 부분 모델 기각(§3.0)은 설계대로 — 기본값 채움 재생은 극장이다.
