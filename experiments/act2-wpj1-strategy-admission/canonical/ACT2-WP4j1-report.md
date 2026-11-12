# ACT 2 WP4-j.1 — Structural Strategy Admission Localization: 실측 보고서

- **실험 ID**: ACT2-WP4j1-strategy-admission
- **날짜**: 2026-08-30
- **상위 계약**: 사용자 지시 — "WP4-j를 다시 구현하지 말고, vtStructural → srNoTransformApplied
  경계가 왜 getBitsBE를 탈락시키는지 read-only로 국소화한 뒤, 원인이 확인되는 경우에만
  최소 일반화 수정을 한다"

---

## Question

obligation 13개가 생성된 getBitsBE가 E2E에서 `vtStructural → srNoTransformApplied →
psFail(solverMethod=smNone)`로 끝나는 정확한 원인은 무엇인가? 특히:

- 사용자가 보고한 모순 — "WP4-j가 pattern mismatch를 soft skip으로 바꿨는데 왜 여전히
  terminal 실패인가" — 의 실체는 무엇인가?
- 사용자 Q1~Q6 중 핵심 Q4 — "strategy failure가 ProofFailure로 승격되는가?" — 는
  사실인가?
- Z3는 getBitsBE에 대해 실제로 호출되었는가? 호출되었다면 그 결과는 무엇을 의미하는가?

---

## Context

- **Subject**: nim-stew `stew/bitops2.nim::getBitsBE`
- **Subject revision**: `c75502ceedb5ed2a37b7b5e4744fc71313682859`
- **Axiom revision**: `44fefd470fc6ad9c24ba40350d5721d4d6a9605c` (working tree — WP4-k
  Phase C/D 변경 포함, 본 WP에서 `src/` 무변경)
- **AXIOM_CONFIGURATION**: `make build` (hermetic), `AXIOM_STATE_DIR=/tmp/axanchor/wpk-state`
- **TOOLCHAIN_IDENTITY**: Nim (config.nims), Z3 (persistent pool, rlimit 30M 결정론)
- **Experiment identifier**: ACT2-WP4j1 (Phase A~D)

---

## Scope

### 포함
- getBitsBE의 E2E 결정 경계 전체의 코드/런타임 국소화
- WP4-j 구현물의 실재성 확인 (사용자 보고 모순 해소)
- Z3 실행 여부와 raw status의 실증 (차등 telemetry + digest 재구성)
- sat 결과의 공허성(vacuity) 분석

### 배제
- 제품 코드 수정 (Phase C 판정 결과 **수정 불필요**로 귀결 — 아래 참조)
- obligation encoding fidelity 개선 (다음 WP 경계 — 아래)
- Lean/KAA/TrustCommit, Track B debt, repository-wide proof, contract 주입

---

## Procedure

1. **Phase A (코드 국소화, read-only)**: `vtStructural`(ax_classify.nim) / `srNoTransformApplied`
   (refactor_task_types.nim:46, refactoring_engine.nim:384) / `psFail` 승격
   (ir_pipeline_runner.nim:1408-1411)의 정의·생성·승격 지점 전수 확인. WP4-j 구현물
   (pattern_guard.nim, strategy_plan.nim, stages.nim:307, loop_driver.nim:195) 존재 확인.
2. **Phase B (런타임 계측)**: getBitsBE Run A/B 재실행 (exit 2, 결정론 확인), JSON decision
   ledger 작성, Q1~Q6 초안 판정.
3. **Phase C (분기 확정)**: 파이프라인 표준 경로 정밀 독해 — `:945` irToSmtScript → `:965-978`
   P3 golden lowering → `:986` TheaterGuard(미발화) → `:1044` runZ3CheckViaIR → `:1048`
   `makeInconclusive(rkEvidenceRejected)`(C20 fail-closed, **무조건**) → `:1098`
   `success = cv.consistent && unsat` → `:1408-1411` else → psFail.
4. **Phase D (실증)**:
   - 차등 telemetry: target=getBitsBE(+11 lines) vs target=normalizeMaxWorkers(+9, exit 0)
     digest 집합 비교 → getBitsBE 전용 호출 2건, 둘 다 **sat**.
   - golden script 재구성 (`tests/unit/wpj1_golden_script_repro.nim`): extractor와 동일
     proposition(`uoNot(boEq(irVar("resultBits",BitVec64),irLit(0)))`)을 동일 lowering으로
     처리 → QF_AUFBV+zmRaw digest가 관측값 `d9f9af27...`와 **정확 일치**.
   - zero-drift: `make build` ✅ + `make check-imports` PASS.

---

## Result (canonical machine-observed)

### 모순 해소 — WP4-j는 구현되어 있었고 성공했다

- WP4-j 5개 패치 파일이 제품에 존재한다 (pattern_guard/strategy_plan/refactoring_engine/
  stages.nim `isPreSieveTerminalBlock`/loop_driver carve-out).
- `seRetry`/`CandidateSieveDecision` 심볼은 없다 — 구현은 C4 재정의(carve-out) + failureKind
  분기로 대체됐다. WP4-j 보고서는 erGuardHardReject → soft skip 전환 **성공**을 기록했고,
  "UAP 0 results"를 다음 경계로 명시했다.
- 즉 **현재 blocker는 WP4-j가 고친 계층이 아니다** — 모순이 아니라 서로 다른 두 계층이다.

### 결정 경계의 실체

- `vtStructural`은 capability 분류일 뿐이고 실행을 막지 않았다 (ax_classify.nim:189,
  body 복잡도만 보고 obligation은 안 봄).
- `srNoTransformApplied`는 refactor 트랙의 `SkippedReason`이며 proof status로 승격되지
  않는다 (refactor 결과는 IR 파이프라인에 피드백 없음).
- 파이프라인은 표준 경로를 끝까지 통과했고 **Z3를 실제 호출했다**.
- `smNone`은 `:1048` C20 fail-closed 고정값("Raw solver unsat must NOT set Proved")이다 —
  Z3 미호출을 의미하지 않는다. psFail은 `:1408-1411` else 분기의 정상 매핑이다.

### Z3 실행의 실증과 공허성

- getBitsBE 전용 Z3 호출 2건, 둘 다 **sat** (차등 telemetry).
- golden 스크립트 digest 정확 일치 (`d9f9af27...`, QF_AUFBV+zmRaw):

```
(set-logic QF_AUFBV)
(set-option :rlimit 30000000)
(declare-fun resultBits () (_ BitVec 64))
(assert (not (not (= resultBits #x0000000000000000))))
(check-sat)
```

- 이 스크립트는 `resultBits`를 **무제약 자유변수**로 선언한다 — 상수 전포/가정 바인딩 없음.
  이중 부정이 상쇄되어 실질 `(assert (= resultBits 0))`이며 자유변수 모델이 항상 존재 →
  **sat는 구조적으로 자명**.
- subject에서 `resultBits`는 `const resultBits = sizeof(result) * 8` (bitops2.nim:576) —
  컴파일 타임 상수, 항상 ≥ 8. **subject의 나눗셈은 안전하다.**
- 따라서 sat는 진짜 counterexample이 아니라 **인코딩 아티팩트**이고, psFail은 그
  underconstrained 인코딩에 대한 정직한 fail-closed다.

### Q1~Q6 최종 판정

| 질문 | 판정 | 핵심 근거 |
|---|---|---|
| Q1 obligation 존재? | **YES** | ogrGenerated(13), golden lowering → Z3 digest 일치 |
| Q2 strategy 미적용이 rejection 원인? | **NO** | refactor 트랙 출력일 뿐; proof 결과는 파이프라인 자체의 Z3 실행(sat)에서 나옴 |
| Q3 다른 strategy 존재? | **N/A** | 파이프라인이 이미 실행함 — 질문 소멸 |
| Q4 strategy failure → ProofFailure 승격? | **NO** | psFail 원인은 실제 solver 결과 sat; smNone은 C20 고정값 |
| Q5 srNoTransformApplied = not-attempted? | **YES** | refactor 트랙 전용, 파이프라인에 피드백 없음 |
| Q6 obligation 실행 목록 제거? | **PARTIAL** | 1/13 실행(golden), 12/13 명시적 drop(osrDroppedOutsideScope) — 무음 제거 아님, O11 계약 준수 |

### 결정론

Run A=B (timestamp 제거 후 출력 동일, CAS key `cf4013de...` 동일), telemetry digest
시퀀스 3그룹 fingerprint 동일. exit 2는 무관한 자체 커널 2개의 cert promotion 실패
(인프라 귀속)로 Run E(target=커널)에서는 exit 0.

---

## Evidence

| 항목 | 위치/값 |
|---|---|
| golden digest 일치 | `probe/golden-script-digest-match.md` — QF_AUFBV+zmRaw = `d9f9af27c1dfa8b3...` |
| 재구성 하네스 | `Axiom/tests/unit/wpj1_golden_script_repro.nim` (읽기 전용 probe, solver 미실행) |
| 정정된 decision ledger | `probe/getBitsBE-decision-ledger-v2.json` (Phase B v1을 대체 — Q4 정정) |
| 차등 실행 | `runs/runA-stdout.txt`, `runs/runB-stdout.txt`, `/tmp/wpj1_runC/D/E_stdout.txt` |
| 저널 | `$STATE/build/certificates/.../journal/*.json` — getBitsBE certRed, smNone, irHash `4936704f...`(5개 실행 동일) |
| 핵심 코드 | ax_classify.nim:151,189 / refactoring_engine.nim:384 / ir_pipeline_runner.nim:945,965-978,1044,1048,1098,1408-1411 / semantic_target_extractor.nim:156 / obligation_smt_lowering.nim(assembly) / bitops2.nim:576 |
| zero-drift | make build ✅, check-imports PASS(33 files) |

---

## Classification

- **getBitsBE 개별 결과**: `Vacuous` — Z3 sat는 무제약 자유변수 모델에 기반한 자명한
  반박으로, subject 상태를 가리키지 않는다 (AGENTS.md §6). psFail은 이 인코딩에 대한
  정직한 fail-closed로, `Verified`도 `Counterexample`도 아니다.
- **사용자 Q4 가설(승격 버그)**: **기각** — 근거 있게 기각된 것으로, 이것도 유효한 실험
  결과다. 수정은 수행하지 않았다 (수정 근거 부재).
- **실험 자체**: 완결 (read-only 국소화 + 실증 + zero-drift). 인프라 exit 2는 `Unknown`/
  인프라 귀속으로 별도 기록.

---

## Interpretation

1. **사용자가 예측한 대로 겉과 속이 달랐다** — 단, 방향이 정반대였다. "vtStructural 자체가
   원인이 아니라 분류 결과가 proof status로 승격되는 경계가 진짜 문제"라는 의심에 대해:
   승격 경계(`:1408-1411`)는 존재하지만 그것이 승격한 것은 strategy-unavailable이 아니라
   **실제 solver 실행 결과**였다. 진짜 문제는 한 계층 더 깊은 **obligation encoding
   fidelity**다: proposition lowering이 상수 전파/가정 바인딩 없이 기호를 자유변수로
   lower하기 때문에, 컴파일 타임 상수 divisor에 대한 안전 사실(`resultBits ≠ 0`)이
   자명하게 반박 가능한 형태로 인코딩된다.
2. 사용자가 WP4-j 논의에서 경고했던 함정이 정확히 재현됐다 — "상수 divisor가 아니라
   symbolic obligation을 우선하라"는 전략 자체는 옳았지만, **기호가 실제로는 상수일 때
   그 상수성을 보존하지 못하면** 강한 symbolic check가 자명한 반박으로 반전된다.
3. WP4-k가 만든 O9/O10/O11 substrate와 ledger는 이번 국소화의 결정적 도구였다 —
   ledger 계약(1 plan + 12 accounted drops) 덕분에 "무음 제거"가 없음을 기계적으로
   확인할 수 있었다.
4. 제품 수정 0건으로 경계가 확정됐다 — 최소 개입 원칙이 정확히 지켜졌다.

---

## Non-Conclusions

- getBitsBE(또는 nim-stew)에 나눗셈 결함이 있다 → **아니다** (resultBits는 상수, 안전).
- Axiom의 status semantics에 승격 버그가 있다 → **아니다** (Q4 기각). 단,
  `smNone` provenance 라벨이 실제 solver 실행을 가리지 못하는 **표시 충실도 문제**는
  관찰됐다 (기능 결함 아님, 다음 WP에서 정리 가능).
- WP4-j가 실패했거나 허위였다 → **아니다** (구현 확인, 목표 달성 확인).
- Z3가 getBitsBE를 검증했다/반증했다 → **둘 다 아니다** — 인코딩이 underconstrained라
  어느 쪽 증거로도 쓸 수 없다 (공허성).
- structural sieve가 obligation을 죽였다 → **아니다** (파이프라인은 끝까지 실행됐다).
- repository 수준의 어떤 주장도 하지 않는다 — 본 보고서는 getBitsBE 단일 anchor의
  실측이다.

---

## Next Experiment

**WP4-j.2 — Obligation Encoding Fidelity (가정 바인딩 / 상수 전파)** — 가장 작은 다음 실험:

1. read-only 측정: golden proposition의 자유변수가 IR에서 상수로 알려진 경우
   (`const resultBits = sizeof(result)*8`처럼) 그 상수 정보가 proposition/lowering의
   어느 지점에서 소실되는지 추적 (semantic_target_extractor → obligation_ir → lowering).
2. 최소 설계: lowering에 가정 바인딩 추가 — `lowerObligationToSmt`가 proposition과 함께
   상수/전제 바인딩(`(assert (= resultBits #x0000...0040))`)을 받아 스크립트에 포함.
   이 경우 golden 스크립트는 `(assert (not (not (= #x40 0))))` → **unsat** → 정당한
   fail-closed 성공 경로로 진화 (C20 evidence gate는 그대로 — Verified는 여전히
   model 요구).
3. 검증: 동일 anchor(getBitsBE) replay에서 golden attempt가 unsat로 바뀌는지,
   O9/O10/O11 테스트와 theaterguard 회귀가 유지되는지, 결정론(digest 안정성)이
   유지되는지.
4. 병행(별도 소규모 WP 후보): `smNone` provenance 라벨에 실제 solver status
   (`bmcOutcome.status`)을 반영해 "실행됨/미실행" 오표시를 제거.

성공 시 다음 경계는 Z3 unsat → C20 evidence gate(model 요구) → Lean/KAA이고,
실패 시 소실 지점이 상위(ingress/IR)임이 확정되어 별도 WP로 분리된다.

---

## Non-goals (의도적으로 하지 않은 것)

- 제품 코드 수정 (판정 결과 불필요 — 수정 근거 부재)
- status semantics 재설계 / seRetry 도입 (Q4 기각으로 근거 소멸)
- obligation encoding 변경 (다음 WP — 단일 변수 원칙)
- `if getBitsBE` 특수화, TheaterGuard 약화, subject 수정
- Track B debt, repository-wide proof, Lean/KAA 변경
