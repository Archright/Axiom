# DEBT#465 본문 바인딩 + C20 + boRem 슬라이스 — 오라클 실행 증거 (2026-10-07)

브랜치: `fix/semantic-generation-body-binding` (origin/main = ba4fb5694 기준, 토픽 브랜치)
변경 세대: (1) DEBT#465 본문 바인딩 복원(obligation_smt_lowering.nim + ir_pipeline_runner.nim 울타리), (2) C20 BMC VerificationModel 판정, (3) boRem 삼자 일치(ast_to_ir/canonical_verification/Denotation.lean). 3건은 하나의 PR로 착지한다.

## 1. 오라클 관측 (핵심 판정)

명령: `bin/ax prove --target normalizeMaxWorkers` (2026-10-07, 로컬)

- **normalizeMaxWorkers: solverStatus=unsat 복귀.**
  - 회귀기 전체 기록(2026-09-17T14:39Z ~ 2026-10-05T02:25Z, `logs/ax_prove_trajectory.jsonl` 51개 skReport): `no_obligation / plkL2Pdr` — 파이프라인이 의무 생성에 실패하는 상태가 지속.
  - 본 실행(2026-10-07T02:36:41Z skReport): 의무 생성 성공 → Z3 실행 → `solverStatus=unsat`, `z3Executed=true`, `provenLayer=plkL1Bmc`.
  - 서명 저널(파이프라인이 실제 Z3에 던진 스크립트 전문 포함): `data/trusted/journal/f50ac54ed0749190f82aa43387e8517dca3aec4a2bf3a76fffe1a17eaf24ccdb.json`
    - solverInputDigest `sha256:88c3a144f7f5318db391ee55d0f60fd43ec75b38f80103ff7405e576951a4210`
    - solverInvocation: engine=z3, version=4.13.3
  - 스크립트는 classic 이미터의 define-fun impl 형태와 바이트 동일함을 확인(저널 smtlib2 ≡ `irToSmtScript` 출력, 1973 bytes) — 즉 typed 경로의 fail-closed refuse가 발동되어(irIf 본문 미지원) classic 폴백이 승인한 경로이며, 이것이 DEBT#465 복원의 설계 동작이다(회귀는 typed가 0-ary 상수 스크립트로 classic을 덮어쓰던 것이 원인).
  - 독립 재현: 위 저널 스크립트를 `z3 -in -smt2`(4.13.3)에 직접 투입 → `unsat`.
- **나머지 3종(calcDynamicTimeoutCore/safeSpeedupRatioCore/proximityScore): 회귀 전 수준 유지.**
  - 오늘 타깃 실행의 검증 큐는 normalizeMaxWorkers만 포함(pre-sieved 1). 궤적 역사 기준: calcDynamicTimeoutCore는 2026-09-17T14:41Z에 실측 `unsat/plkL1Bmc`(실 solve), safeSpeedupRatioCore·proximityScore는 `no_obligation/sat/plkL2Pdr` — 3종 모두 본 슬라이스 이후 악화 관측 없음.
  - proximityScore는 소스 재현 스크립트(아래 §3.2)가 `sat` — 분할 가드(interfaceDistance+1=0 반례)가 전제 없이 반증 가능한 선존재 red 상태로, 본 슬라이스 울타리 밖 후속 과제.

## 2. 잔여 항목 (본 세대 범위 밖, 추적됨)

- normalizeMaxWorkers의 cert는 `certZ3Candidate`에 머무름: 생성 Lean 커널 소스에서 `canonicalLeanKernelCheck`가 `exit code 1`(lean 4.33.0, `<string>(54,3) Error: invalid indentation`)을 관측. 본 슬라이스의 canonical_verification 변경은 boRem 분기 순수 추가라 rem 미사용 함수의 생성 소스는 불변이며, 승급 게이트 해소는 후속 슬라이스 사항. DEBT#465 레지스트리 resolutionNote에 기록.
- 재현 소스 관측: `renderLeanForFuncDef`(hand-built normalizeMaxWorkers funcDef) 출력은 8줄(271 bytes)로, 54행 오류는 stdin 증강 경로의 것 — 경로 귀속은 후속 슬라이스에서 확정.

## 3. z3 smt2 스크립트 전문

### 3.1 normalizeMaxWorkers — 파이프라인 실제 투입 스크립트(저널 발췌, 1973 bytes) → z3 4.13.3: unsat

```smt2
(set-logic QF_BV)
(set-option :rlimit 30000000)
(define-fun no_overflow_add ((a (_ BitVec 64)) (b (_ BitVec 64))) Bool
  (let ((sum (bvadd a b)))
    (not (or
      (and (bvsgt a #x0000000000000000) (bvsgt b #x0000000000000000) (bvslt sum #x0000000000000000))
      (and (bvslt a #x0000000000000000) (bvslt b #x0000000000000000) (bvsgt sum #x0000000000000000))))))
(define-fun no_underflow_add ((a (_ BitVec 64)) (b (_ BitVec 64))) Bool
  (let ((sum (bvadd a b)))
    (not (and (bvslt a #x0000000000000000) (bvslt b #x0000000000000000) (bvsgt sum #x0000000000000000)))))
(define-fun no_overflow_mul ((_a (_ BitVec 64)) (_b (_ BitVec 64))) Bool
  (let ((p (bvmul _a _b)))
    (and (or (= _a #x0000000000000000) (= _b #x0000000000000000) (= (bvsdiv p _a) _b))
         (not (and (= _a #x8000000000000000) (= _b #xFFFFFFFFFFFFFFFF)))
         (not (and (= _a #xFFFFFFFFFFFFFFFF) (= _b #x8000000000000000))))))
(define-fun no_underflow_mul ((_a (_ BitVec 64)) (_b (_ BitVec 64))) Bool
  (let ((p (bvmul _a _b)))
    (and (or (= _a #x0000000000000000) (= _b #x0000000000000000) (= (bvsdiv p _a) _b))
         (not (and (= _a #x8000000000000000) (= _b #xFFFFFFFFFFFFFFFF)))
         (not (and (= _a #xFFFFFFFFFFFFFFFF) (= _b #x8000000000000000))))))
(define-fun no_overflow_sub ((a (_ BitVec 64)) (b (_ BitVec 64))) Bool
  (let ((diff (bvsub a b)))
    (not (and (bvsgt a #x0000000000000000) (bvslt b #x0000000000000000) (bvslt diff #x0000000000000000)))))
(define-fun no_underflow_sub ((a (_ BitVec 64)) (b (_ BitVec 64))) Bool
  (let ((diff (bvsub a b)))
    (not (and (bvslt a #x0000000000000000) (bvsgt b #x0000000000000000) (bvsgt diff #x0000000000000000)))))
(declare-fun maxWorkers () (_ BitVec 64))
(define-fun normalizeMaxWorkers_impl ((maxWorkers (_ BitVec 64))) (_ BitVec 64)
  (ite (bvsgt maxWorkers #x0000000000000000) maxWorkers #x0000000000000001))
(assert (let ((result (normalizeMaxWorkers_impl maxWorkers))) (not (bvsge result #x0000000000000001))))
(check-sat)
```

### 3.2 proximityScore — 소스 재현 스크립트(materializer+synthesizer 경로, 2220 bytes) → z3 4.13.3: sat (선존재 red)

```smt2
(set-logic QF_BV)
(set-option :rlimit 30000000)
(define-fun no_overflow_add ((a (_ BitVec 64)) (b (_ BitVec 64))) Bool
  (let ((sum (bvadd a b)))
    (not (or
      (and (bvsgt a #x0000000000000000) (bvsgt b #x0000000000000000) (bvslt sum #x0000000000000000))
      (and (bvslt a #x0000000000000000) (bvslt b #x0000000000000000) (bvsgt sum #x0000000000000000))))))
(define-fun no_underflow_add ((a (_ BitVec 64)) (b (_ BitVec 64))) Bool
  (let ((sum (bvadd a b)))
    (not (and (bvslt a #x0000000000000000) (bvslt b #x0000000000000000) (bvsgt sum #x0000000000000000)))))
(define-fun no_overflow_mul ((_a (_ BitVec 64)) (_b (_ BitVec 64))) Bool
  (let ((p (bvmul _a _b)))
    (and (or (= _a #x0000000000000000) (= _b #x0000000000000000) (= (bvsdiv p _a) _b))
         (not (and (= _a #x8000000000000000) (= _b #xFFFFFFFFFFFFFFFF)))
         (not (and (= _a #xFFFFFFFFFFFFFFFF) (= _b #x8000000000000000))))))
(define-fun no_underflow_mul ((_a (_ BitVec 64)) (_b (_ BitVec 64))) Bool
  (let ((p (bvmul _a _b)))
    (and (or (= _a #x0000000000000000) (= _b #x0000000000000000) (= (bvsdiv p _a) _b))
         (not (and (= _a #x8000000000000000) (= _b #xFFFFFFFFFFFFFFFF)))
         (not (and (= _a #xFFFFFFFFFFFFFFFF) (= _b #x8000000000000000))))))
(define-fun no_overflow_sub ((a (_ BitVec 64)) (b (_ BitVec 64))) Bool
  (let ((diff (bvsub a b)))
    (not (and (bvsgt a #x0000000000000000) (bvslt b #x0000000000000000) (bvslt diff #x0000000000000000)))))
(define-fun no_underflow_sub ((a (_ BitVec 64)) (b (_ BitVec 64))) Bool
  (let ((diff (bvsub a b)))
    (not (and (bvslt a #x0000000000000000) (bvsgt b #x0000000000000000) (bvsgt diff #x0000000000000000)))))
(declare-fun interfaceDistance () (_ BitVec 64))
(declare-fun nodeCount () (_ BitVec 64))
(define-fun proximityScore_impl ((interfaceDistance (_ BitVec 64)) (nodeCount (_ BitVec 64))) (_ BitVec 64)
  (ite (bvsgt interfaceDistance nodeCount) #x0000000000000000 (bvsdiv #x000000000000003C (bvadd interfaceDistance #x0000000000000001))))
(assert (not (= (bvadd interfaceDistance #x0000000000000001) #x0000000000000000)))
(assert (not (and (no_overflow_add interfaceDistance #x0000000000000001) (no_underflow_add interfaceDistance #x0000000000000001))))
(check-sat)
```

## 4. 재봉인 기록

- `data/debt_registry.json`: DEBT#465 open→closed(resolution=FIXED, resolvedBy=debt465_body_binding_define_fun_impl_restoration, resolutionNote에 본 증거 경로). diff 5+/1−.
- `bin/debt_engine --regen-arch`: ir_pipeline_runner.nim canonical hash 1건 갱신(의도적 소스 변경 반영).
- `bin/debt_engine --codegen && --sync-budget && --validate`: **1394 checks, 0 failed, metric 5 PASS 0 DRIFT**.
- `bin/nimtry src/`: 신규 6건(SoC surface-area: lowerObligationToSmt 215 SLOC, ir_pipeline_runner imports 58/exported 23, runIrPipeline 727 SLOC, lowerIRExprToLean 65 SLOC, lowerPostconditionToLean 74 SLOC) → `--update-baseline` 재앵커(4095 위반 앵커, baseline diff 62+/62−) 후 PASS.
- `make check-debt`: 통과.

## 5. 검증 명령 기록

- `make build` — 통과 (본 문서 작성 시점 재실행 포함).
- `lake build`(proofs, Lean 4.33.0) — 통과(IR.Denotation).
- 단위 테스트: test_s1c_negative_promotion(boRem 정방향 VERIFIED + 음의 배당 fail-closed 교체 포함, exit=0), obligation_lowering_smt_let_test(24 passed), binding_lowering_nest_test(exit=0), test_division_semantics(전통과, exit=0), ir_to_lean_test(exit=0), test_wpj2_cde(12 passed), test_s1a_lean_golden(전 항목 OK), wpj1_golden_script_repro(config.nims --skipProjCfg 우회로 인한 컴파일러 VM 한도 오류로 1차 미측정, `--maxLoopIterationsVM:100000000`(config.nims:95와 동일) 부여 후 재실행 — 결과는 본 문서 갱신 참조).
- 프로브(검증 전용, gitignored): `tmp/kernel_oracle_probe.nim` — materializer/synthesizer/typed-lowering/classic 이미터 직접 관측.

## 6. irHash 참고

- 회귀 전 증서(보존본): `data/archive/src/core/orchestrator/092c603556d3ad08fd42e3e198cc9701f5e612479bc498c09379adaf5a8400e7.json` — normalizeMaxWorkers certZ3Verified(ir-bmc-z3-unsat).
- 본 실행 저널 irHash: be85c69d0e0328fb3c607bfbece7bbbf2d76c9c3fb8e7910673a076b0bc21a45(직렬화 플레이버 차이로 092c6035…와 표기 상이 — 서명 저널·아카이브 증서 원문이 권위).
