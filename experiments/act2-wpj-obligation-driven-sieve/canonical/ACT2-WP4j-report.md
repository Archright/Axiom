# ACT 2.2 / WP4-j — Obligation-Driven Sieve / Healing Decision
## §14 Canonicical Report (Pre-Sieve Admission Boundary)

---

## Question

구조적 sieve의 healing pattern 하나(has_loop/topology)가 후보 전체의 생사를
결정하는 기존 정책을, obligation-driven deterministic retry 모델로 재설계하면
loop-free + intrinsic-obligation 루틴(anchor=`stew/bitops2.nim::getBitsBE`)이
terminal hard-reject 없이 증명 파이프라인을 진행할 수 있는가?

구체적으로 이 WP가 검증한 것은 다음 두 주장이다.

1. **Pre-Sieve Admission Boundary** — pre-sieve는 obligation이 아직 존재하지 않는
   시점에서 obligation 기반 eligibility를 추론하지 않는다.
2. **Pattern mismatch ≠ semantic invalidity** — structural healing pattern
   불일치는 후보를 terminal reject하지 않는다.

---

## Context

| 항목 | 값 |
|------|-----|
| PROJECT_UNDER_TEST | `nim-stew-clean-c75502c` (immutable) |
| PROJECT_REVISION | `c75502c` |
| AXIOM_REVISION | baseline(캠페인 번들) + WP4-j 패치 5파일 |
| AXIOM_CONFIGURATION | `ax prove --target 'stew/bitops2.nim::getBitsBE' --limit 1` |
| TOOLCHAIN_IDENTITY | nim 2.2.10, z3 4.13.3, **lean 4.29.0** (gate pin은 4.33.0 — 환경 불일치, 아래 §Check/Toolchain) |
| VERIFICATION_SCOPE | 단일 anchor `getBitsBE`, repository coverage 아님 |
| EXPERIMENT_ID | `act2-wpj-obligation-driven-sieve` |

### 변경 세트 (WP4-j minimal fix)

| 파일 | 변경 |
|------|------|
| `src/core/diagnostics/pattern_guard.nim` | `FailureKind`, `PatternApplicability.failureKind`, `StructuralFactSignals`, `structuralFacts` func, `pgPatternToRefactoring/pgPatternFromRefactoring` func; `import core/trusted/axiom_pragmas_lite` |
| `src/core/diagnostics/strategy_plan.nim` | **신규** — 전부 func, deterministic strategy ordering (`intrinsic → structural → generic → unsupported`); `import core/trusted/axiom_pragmas_lite` |
| `src/core/diagnostics/refactoring_engine.nim` | `case guardResult.failureKind` 재작성: `paParseFailure`/`paEmptySource → erGuardHardReject`, `paPreconditionMiss → parseNimRes → computeStrategyPlan → fallback` |
| `src/verification/batch_uap/stages.nim:307` | `isPreSieveTerminalBlock` func (진짜 fatal만 terminal) |
| `src/verification/batch_uap/loop_driver.nim:195` | `isPreSieveTerminalBlock`로 fatal 분기, else carve-out |

**C4 재정의**: 사전 하드 게이트 `obligationCount > 0` 제거 →
**Pre-Sieve Admission Boundary**. 규칙:
`Admission ≠ Proof Eligibility` · `Admission ≠ Obligation Availability` · `Admission ≠ Proof Success`.
pre-sieve hard reject = source missing / malformed / explicitly unsupported 만 terminal.

---

## Scope

**포함**
- anchor `getBitsBE` 동일 재현 (baseline → WP4-j 패치 후 동일 명령).
- 5개 canonical regression suite + `refactoring_engine_test` (가장 많이 수정한 모듈).
- 보다 넓은 unit suite 32 (make test-fast 대체 병렬 실행) — zero-drift 확인.
- 결정론: Run1 vs Run2 동일 입력 동일 출력.

**제외**
- repository-wide proof, 다른 함수 proof (전부 시기상조 — AGENTS.md §7 scope discipline).
- Contract 삽입 variant (기본 전략 아님, 비교 실험으로만).
- Track B (evidence/historical debt) — 접촉 금지 (AGENTS.md §9).
- git mutation (금지).

---

## Procedure

### C — minimal fix
```
pragma 오류 해결: pattern_guard.nim:2, strategy_plan.nim에
  import core/trusted/axiom_pragmas_lite  추가

nim check  → pattern_guard/strategy_plan/refactoring_engine/loop_driver 모두 SuccessX
make build → exit 0
```

### D — regression + zero-drift
```
테스트 실행 패턴: nim c -r --hints:off <file>
  서브스트링 grep: "\[OK\]|\[FAIL\]|Passed:|Failed:|ALL PASSED"
```

### E — getBitsBE 동일 anchor replay
```sh
export AXIOM_STATE_DIR=/tmp/axanchor/wpj-replay-state
bin/ax prove --project <workspace>/nim-stew-clean-c75502c \
  --target 'stew/bitops2.nim::getBitsBE' --limit 1
```
- state dir seeding 필수: `mkdir -p <state>/data && cp data/verification_scope.lock <state>/data/`
  (안 하면 `loadKernelScope fail-closed: lock file missing` → exit 2).
- 실제 저장 위치: `act2-wp4h3-proofir/runs/` (동일 워크스페이스 실행), canonical 사본은
  `act2-wpj-obligation-driven-sieve/{runs,canonical/evidence}/`로 보존했다.

---

## Result

### getBitsBE anchor — baseline vs WP4-j (canonical trajectory)

| 지표 | WP4-h3 baseline | WP4-j |
|------|----------------|-------|
| sieve 결과 | `escalated: erGuardHardReject` (terminal) | `srNoTransformApplied` (soft skip) |
| StructuralAST layer | `rejected (counterexample)` | `leFailedSat` (실패 but non-terminal) |
| UAP requests | 0 | **1** |
| UAP results | 0 | 0 |
| status | (hard-reject) | `pre_sieved` |
| assuranceTier | — | `unknown` |
| solverInvocationCount | 0 | 0 |
| obligationGeneratedCount | — | **13** |
| obligationAttemptedCount | — | 0 |

- trajectory `skReport` 확정: `Sieve-Gate passed=false`, `Diagnosis-Gate passed=false`,
  `layerTrace=[{layerName:"StructuralAST","outcome":"leFailedSat"}]`,
  `refactorSummary: strategy=structural_ast, dominantRule=topology`.
- **결정론 확인**: Run1(03:33:46)과 Run2(03:34:35)의 `skReport`가 timestamp 제외
  byte-identical (`records identical (modulo timestamps): True`).

### Stage 결과 요약
```
Discovery        PASS
Admission        PASS
Obligation       PASS (obligationGeneratedCount=13)
Sieve            SOFT-SKIP (재설계 전: HARD REJECT)
Healing          PASS(non-terminal 전환)
ProofIR/Plan     통과
UAP → Z3         도달하려 했으나 UAP 0 results로 obligation execution에서 정지
```

---

## Evidence

| 산출물 | 경로 |
|--------|------|
| WP4-j replay 로그 | `.../runs/prove_getBitsBE_wpj_replay.log` |
| trajectory (Run1+Run2) | `.../runs/prove_trajectory_wpj.jsonl`, `.../canonical/evidence/trajectory_run12.jsonl` |
| A1 5-link 상관 | `.../A1-five_link_correlation.md` |
| A1 5-state 분류 | `.../A1-five_state_classification.md` |
| A3 taxonomy | `.../A3-taxonomy.md` |
| A3 solver 부하 추정 | `.../A3-solver_load_estimate.md` |
| B 구현 사양 | `.../B-implementation_spec.md`, `.../B-strategy_semantics_freeze.md` |
| probe 스크립트 | `.../probe/` (extract_corpus.py, replay_identity_probe.sh, B_pattern_applicability_shape.py) |

### Check / Gates

| gate | 결과 |
|------|------|
| `make check-imports` | **PASSED** (17 files, no import boundary violations) |
| `make check-determinism` | **환경상 실패** — lean 4.29.0 vs gate pin 4.33.0 (WP4-j 무관, toolchain 환경 불일치) |
| proc→func invariant | `src/core` 총 **950** (=cap, 초과 없음), strategy_plan func 작성 |
| `make build` audit | exit 0, `[decision-binding] Found 2 violation(s)` — **touched 파일 0건** (남은 2건 pre-existing: `identity.nim:52`, `canonical_cache.nim:149`) |

### Regression (D)

| suite | 결과 |
|-------|------|
| `test_ir_pipeline_theaterguard.nim` | 2 OK, exit 0 |
| `candidate_eligibility_test.nim` | 19 OK, exit 0 |
| `proof_state_machine_test.nim` | **52 passed, 0 failed** |
| `test_obligation_ir.nim` | Passed 23, ALL PASSED |
| `test_obligation_adapters.nim` | Passed 13, ALL PASSED |
| `refactoring_engine_test.nim` | 8 OK, exit 0 |
| broader unit 32 | **29 green**; 3 pre-existing env/data 실패 (`test_theater_allowlist_structure`, `test_vkd_determinism` SIGSEGV, `test_certificate_trust_closure`) — **변경 모듈 import 안 함**: zero-drift 확정 |

---

## Classification

- **getBitsBE** → **Incomplete**
  (structural hard-reject는 제거됐고 Stage 1c UAP request 빌드까지 도달, requests=1,
  그러나 UAP가 0 results 반환 → obligation execution 경계에서 정지, `pre_sieved`).
- `Verified` 아님. 주장 금지.

---

## Interpretation

이 WP가 확립한 것은 정확히 다음 경계 이동이다.

**기존**: structural sieve의 dominant healing pattern(has_loop/topology) 불일치가
후보를 terminal kill → `getBitsBE`의 이미 생성된 13개 intrinsic obligation은 dead.

**WP4-j**: `erGuardHardReject` → `srNoTransformApplied`(soft) 로 전환.
sieve는 더 이상 증명 가능성을 판정하지 않고 "어떤 실행 경로를 시도할지"만 선택한다.
`PaPreconditionMiss → parseNimRes → computeStrategyPlan → fallback`로 retry 경로가 열렸다.

결과적으로:
- `Admission ≠ Proof Eligibility` invariant가 코드로 확립됨.
- `pattern mismatch ≠ semantic invalidity`이 확립됨.
- **결정론 유지** — Run1==Run2 identical.
- **zero-drift** — WP4-j 코드는 어떤 실패 단위에도 기여 안 함 (5 canonical suite +
  refactoring_engine + 29 broader unit green, 3 pre-existing env/data failure는 변경
  모듈 무관).

즉 단일 구조 패턴이 obligation 전체의 생사를 결정하던 정책은 obligation-driven,
deterministic retry 모델로 교체되었다. 이것은 getBitsBE 한 함수만이 아니라
division/index/slice/shift/overflow 등 서로 다른 intrinsic obligation을 가진 함수가
각각 올바른 경로를 선택할 일반 실행 선택기를 위한 기반이다.

---

## Non-Conclusions

이 WP의 결과는 다음을 **증명하지 않는다**:

- getBitsBE의 `resultBits != 0` intrinsic obligation이 **참**임. (Verified 주장 없음)
- UAP/obligation 실행이 loop-free intrinsic 함수에 결과를 줄 수 있다는 capability.
  (오히려 이 정확한 지점이 다음 blocker로 드러났다 — `UAP produced 0 results,
  requests=1`.)
- solver 부하 +15~18% 추정치의 실제 흡수 가능성. (A3는 read-only 측정/추정일 뿐,
  실행 입증 아님 — `obligationAttemptedCount=0`이므로 실제 부하 생성 자체가 이번에
  관측되지 않았다.)
- repository-wide / 다른 함수에 대한 검증 성공.
- exit code 변화의 정확한 원인 귀속.

---

## 주의: exit code 귀속은 Unverified

- WP4-j replay는 실행 종료 시 `PERSIST FAIL: 2 promotable certificate(s)`
  (`safeSpeedupRatioCore`, `proximityScore` — **getBitsBE 아님**, pre-existing
  후보들) 로 exit 2.
- baseline replay 로그에는 동일 PERSIST FAIL 블록이 없어, carve-out가 getBitsBE를
  IR-pipeline FAIL 세트에서 빼면서 persist 경로가 바뀐 **것으로 추정**된다.
- 이 귀속은 정확히 검증되지 않았다. git mutation 금지로 baseline binary 재검증이
  불가능해, 이 항목은 `Unknown`/`Incomplete` 경계로 honest하게 기록한다. exit code
  자체는 본 WP의 관측 대상이 아니며, getBitsBE 분류 변화(erGuardHardReject →
  srNoTransformApplied)는 trajectory에서 독립적으로 확정된다.

---

## Next Experiment

다음 경계는 **"loop-free intrinsic-obligation 루틴(getBitsBE)에서 UAP가 결과를
산출하게 하는 것"** 이다.

구체적으로 WP4-j 이후 실제 blocker:

```
getBitsBE
  → obligation 생성 (13개)
  → UAP request 빌드 (requests=1)
  → UAP results = 0          ← 다음 capability boundary
  → status pre_sieved
```

즉 `strategy_plan`의 obligation-driven 선택이 단순 관찰(soft skip)에 그치지 않고,
실제로 `okSafetyDiv(resultBits != 0)` intrinsic obligation을 executable SMT goal로
이어주어야 한다. 이것은 WP4-h3의 Typed ProofIR + SMT lowering 위에서,
WP4-i/4-j의 structural ingress 통과 이후, obligation execution(UAP)이 그 obligation을
실제로 소비하도록 배선하는 작업이다.

- 대상: `getBitsBE` 고정 anchor 유지 (갈아타기 금지).
- acceptance: `UAP results ≥ 1`(또는 명시적 SAT/UNSAT)에 도달.
- 여전히 VRepo coverage 목표 아님. `Verified` 주장 금지 — result가
  SAT/UNSAT/UNKNOWN 중 무엇이 됐든 canonical evidence로 기록.

---

## Invariants (이 WP가 유지·확립한 것)

1. **Proc→func**: `src/core` proc 선언 총 950 (=cap). strategy_plan을 func로 작성.
   향후 `src/core`에 proc 선언 절대 추가 금지.
2. **Import boundary**: `check-imports` PASSED. `core/trusted/axiom_pragmas_lite`는
   명시적 import 필요(레이어 선언만으론 안 됨).
3. **Fail-closed**: TheaterGuard 유지. lowering 실패 → empty → TheaterGuard.
   Guard를 제거하는 것이 아니라 Guard에 걸리지 않는 올바른 artifact를 만든다.
4. **결정론**: 동일 입력 → 동일 선택 → 동일 결과. Run1==Run2 확인.
5. **Admission ≠ Proof Eligibility**: pre-sieve는 transport만, 증명 가능성 판정 안 함.
6. **pattern mismatch ≠ semantic invalidity**: soft retry, terminal reject 아님.
7. **Verified 금지**: 이번 anchor는 Incomplete로 분류.
