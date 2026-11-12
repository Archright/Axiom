# ACT 2 WP4-k — Obligation Execution Closure: 실측 보고서

- **실험 ID**: ACT2-WP4k-obligation-execution
- **날짜**: 2026-08-30
- **작성자**: Axiom evaluation agent (WP4-k 핸드오프 기준 Phase C→E 실행)

---

## Question

UAP에서 `obligation → request → dispatch → SMT → Z3 → result`의 소유권 체인이 단절되는 문제
(`requests=1 → results=0`)를, ProofObligation을 1급 객체로 승격해 결정론적 실행 substrate로
닫을 수 있는가? 특히 WP4-k가 추가로 부과한 세 불변식을 기계적으로 검증할 수 있는가:

- **O9** — `canonicalEnvelopeDigest`는 sentinel을 제외한 pre-sentinel envelope의 결정론적 해시인가?
- **O10** — 동일 obligation이 재실행에서 동일 transport identity(digest/provenance)를 재현하는가?
- **O11** — 생성된 모든 obligation이 정확히 하나의 terminal attribution(계획 실행 또는 명시적 drop)을 갖는가?

---

## Context

- **Subject (PROJECT_UNDER_TEST)**: nim-stew
- **Subject revision (PROJECT_REVISION)**: `c75502ceedb5ed2a37b7b5e4744fc71313682859` (c75502c)
- **Axiom revision (AXIOM_REVISION)**: `44fefd470fc6ad9c24ba40350d5721d4d6a9605c`
- **AXIOM_CONFIGURATION**: local `make build` (hermetic, `bin/ax`), state dir `AXIOM_STATE_DIR=/tmp/axanchor/wpk-state`
- **TOOLCHAIN_IDENTITY**: Nim (repo `config.nims`), z3 via `-d:allowMissingZ3` (unit) / runtime Z3 (E2E), Lean 미도달
- **VERIFICATION_SCOPE**: `stew/bitops2.nim::getBitsBE` 단일 target (`--limit 1`), 전역 seed 상태
- **Anchors**:
  - SMT lowering: `src/verification/solver/z3_pool.nim` (`buildZ3QueryEnvelope*`, `:611`)
  - 실행 ledger: `src/verification/obligation/verification_result_interpreter.nim` (canonical ledger 타입 단일 source of truth)
  - runner: `src/verification/batch_uap/ir_pipeline_runner.nim`
  - telemetry: `src/core/solver/z3_telemetry.nim` (`logs/z3_telemetry.jsonl`)
- **Experiment identifier**: `ACT2-WP4k` (Phase A–E)

---

## Scope

### 분석 대상 (included)
- getBitsBE의 intrinsic safety obligation이 존재하는지, 그리고 WP4-k가 이전 WP에서 닫은
  `Typed ProofIR → SMT` 파이프라인이 O9/O10/O11 불변식으로 확증되는지.
- Phase C에서 제거한 gap 2 (`runZ3CheckViaIR(string)`의 기존 문자열 재해석 우회 — `:778` transport 해시
  버그, `solverInvocationId`의 envelope digest 포함)의 회귀.
- 결정론: 동일 입력 → 동일 CAS identity / envelope digest / transport digest.

### 배제 (excluded)
- **Lean/KAA/TrustCommit 도달** — Lean 백엔드 및 evidence binding은 이번 WP 범위 밖 (다음 WP 경계).
- **Structural sieve/healing policy**(getBitsBE가 `vtStructural`로 misclassify되는 문제) — 사용자가 명시적으로
  WP4-j로 분리한 작업. WP4-k에서 수정하지 않음(단일 변수 실험 원칙).
- **Contract 주입**(getBitsBE에 precondition/postcondition 삽입) — 비교 실험으로만, 기본 경로 아님.
- **Track B debt**(historical 6,806, CurrentEvidence, reverse index, effect inference, stale full provenance).
- **Repository-wide proof / multiproof generalization**.
- core `proc` budget 증설과 무관한 비핵심 리팩터.

---

## Procedure

### Phase D — 회귀 + O9/O10/O11 테스트 (제품 코드는 Phase C 이후 미변경)

신규 unit 테스트 `tests/unit/test_obligation_execution_ledger.nim` 작성, 직접 검증:

```
nim c --hints:off -d:allowMissingZ3 --out:/tmp/wp4k_ob_ledger_test \
  tests/unit/test_obligation_execution_ledger.nim && /tmp/wp4k_ob_ledger_test
```

기존 회귀 테스트 재컴파일 + 실행:

```
nim c --hints:off -d:allowMissingZ3 --out:/tmp/wp4k_tg_test  tests/unit/test_ir_pipeline_theaterguard.nim
nim c --hints:off -d:allowMissingZ3 --out:/tmp/wp4k_psm_test tests/unit/proof_state_machine_test.nim
```

zero-drift:

```
make build
make check-imports
```

### Phase E — getBitsBE 재실행 (Run A / Run B)

```
export AXIOM_STATE_DIR=/tmp/axanchor/wpk-state
bin/ax prove --project <workspace>/nim-stew-clean-c75502c \
  --target 'stew/bitops2.nim::getBitsBE' --limit 1
```

Run A와 Run B 두 번 실행, stdout 전체 + `$AXIOM_STATE_DIR/logs/z3_telemetry.jsonl` 비교.

---

## Result (canonical machine-observed)

### Phase D — unit/회귀 통과

- `test_obligation_execution_ledger.nim`: **11 passed, 0 failed**
  - O9 ×3 (pre-sentinel 해시 일치, 결정론, payload 의존성) — 전부 PASS
  - O10 ×2 (동일 obligation → 동일 digest 재현, provenance 기록) — 전부 PASS
  - O11 ×6 (accept 1 + reject 5: 0-terminal / 2-terminal / drop-no-reason /
    drop-unknown / duplicate-drop) — 전부 PASS
- `test_ir_pipeline_theaterguard.nim`: (a)–(f) 전부 OK (TheaterGuard 무발화 포함)
- `proof_state_machine_test.nim`: **52 passed, 0 failed**
- `make build`: ✅ Build successful
- `make check-imports`: PASSED (33 files, no import boundary violations)

### Phase E — getBitsBE Run A/B (exit code 2, both runs)

- `--target filter: 1 node(s) match 'stew/bitops2.nim::getBitsBE'`
- classify: `getBitsBE → vtStructural (complex body operations)`
- `[ir-cas] MISS func=getBitsBE key=cf4013de578c923dc566aa3817b01b76927bfeac1b4f4fed1a41a1b07dd8c556`
  (A/B 동일 — 16진수 64자)
- IR pipeline: `getBitsBE status=psFail provenance=solverMethod=smNone,provenance=pkNone`
- `loop_driver: [1/1] getBitsBE — pre-sieved`
- `Verification-Gate: UAP produced 0 results (requests=1)`
- structural verification: `✓ getBitsBE — structural verification`, `⚠ skipped: srNoTransformApplied`
- `verifiedRatio=0.0000, verified=0/40`
- `PERSIST FAIL: 2 promotable certificate(s) failed canonical promotion`
  (`safeSpeedupRatioCore`, `proximityScore` — getBitsBE 아님)

### 결정론 (Run A = Run B)

- getBitsBE CAS identity key: `cf4013de…c8c556` — A/B **byte-identical**
- getBitsBE 관련 결과 라인(classification/psFail/verifiedRatio/requests) — timestamp 제거 후 diff **IDENTICAL**
- Z3 telemetry `canonical_envelope_digest` 시퀀스 — Run A(2그룹)·Run B(1그룹) 3그룹 **fingerprint 동일**
  (`aba44ebe626a70591be46f03a1950204`)
- Z3 telemetry `transport_payload_digest` 시퀀스 — 3그룹 **fingerprint 동일**
  (`ba18857ad937eb49a014cdb040c5c662`)

---

## Evidence

| 항목 | 값 |
|---|---|
| Subject rev | `c75502ceedb5ed2a37b7b5e4744fc71313682859` |
| Axiom rev | `44fefd470fc6ad9c24ba40350d5721d4d6a9605c` |
| getBitsBE CAS key (A=B) | `cf4013de578c923dc566aa3817b01b76927bfeac1b4f4fed1a41a1b07dd8c556` |
| O9 pre-sentinel digest 규칙 | `canonicalEnvelopeDigest = sha256Hex(pre-sentinel bytes)` (z3_pool.nim `:655`) |
| RunA stdout | `/tmp/wp4k_runA_stdout.txt` |
| RunB stdout | `/tmp/wp4k_runB_stdout.txt` |
| telemetry | `$AXIOM_STATE_DIR/logs/z3_telemetry.jsonl` (33 lines, 3 deterministic groups) |
| O9/O10/O11 테스트 | `tests/unit/test_obligation_execution_ledger.nim` — 11/11 PASS |
| theaterguard 회귀 | `tests/unit/test_ir_pipeline_theaterguard.nim` — (a)–(f) OK |
| state machine 회귀 | `tests/unit/proof_state_machine_test.nim` — 52/52 PASS |
| build/import | `make build` ✅ / `make check-imports` PASS (33 files) |
| Phase C 수정 | z3_pool.nim `:778` `sha256Hex(payload)` (transport), ir_pipeline_runner.nim `:1084` solverInvocationId digest 포함, interpreter ledger 단일화, `buildZ3QueryEnvelope*` export |

---

## Classification

**`Incomplete`** (getBitsBE 정성 기준) + **`InfrastructureFailure`**(PERSIST FAIL, exit 2 귀속).

구체적으로:
- WP4-k가 닫아야 할 obligation→SMT lowering + identity 불변식(Phase C/D): **성공으로 닫힘** — O9/O10/O11
  unit 통과, E2E Z3 digest 결정론 확인.
- getBitsBE가 **Z3/obligation ledger까지 실측 도달하지 못함**: `vtStructural` misclassify로 중단.
  이는 WP4-k 결함이 아니라 사용자가 WP4-j로 확정한 **structural sieve policy** 경계.
- exit code 2는 getBitsBE와 무관한 두 repo 커널(`safeSpeedupRatioCore`, `proximityScore`)의
  canonical certificate promotion 실패 → **Infrastructure/attribution**으로 귀속.

---

## Interpretation

증거가 실제로 확립하는 것:

1. **WP4-k lowering substrate는 결정론적으로 닫혔다** — 동일 SMT payload는 항상 동일 pre-sentinel
   digest와 동일 transport digest를 산출(unit O9/O10 + E2E telemetry 3그룹 fingerprint 동일).
2. **O11 terminal attribution 불변식이 기계 검증 가능한 형태로 구현·검증됨** —
   `checkTerminalAttribution(ledger)`가 0/2-terminal, 무이유 drop, 미지 obligation drop, 중복 drop을
   구조적으로 거부.
3. **getBitsBE의 결정론 자체는 확립됨** — 똑같은 입력이 똑같은 CAS key와 똑같은 실패 outcome을
   만든다. 즉 "어떻게 실패하는지"도 결정론적이다.
4. **getBitsBE는 여전히 structural sieve에서 중단** — 생성된 intrinsic obligation이
   `vtStructural`/`srNoTransformApplied` healing policy에 의해 SMT로 라우팅되지 못하고
   `psFail(smNone)`으로 종결됨. 이것은 정확히 사용자가 WP4-j로 고정한
   "structural healing pattern이 obligation의 생사를 결정하는 정책" 문제다.

---

## Non-Conclusions

증거가 확립하지 **않는** 것:

- getBitsBE가 SMT/Z3 obligation ledger에 도달했다 → **아니다** (vtStructural에서 중단).
- getBitsBE가 kernel-accepted proof를 얻었다 → **아니다** (Lean 미도달; 애초에 SMT 자체 미도달).
- "requests=1 → results=0"이 WP4-k에서 해소됐다 → **부분만**. 테스트 수준 lowering은 닫혔지만,
  E2E에서 getBitsBE의 request가 sieve에 의해 생성조차 안 되는 경로는 WP4-j 필요.
- `Verified` → 아니다. 어떤 kernel-tier 증명도 없음.
- PERSIST exit 2가 getBitsBE 책임이다 → **아니다** (다른 커널 cert promotion 실패).
- WP4-k가 structural sieve / healing policy를 바꿨다 → 아니다(수정 안 함, 의도적).

---

## Next Experiment

가장 작고 유용한 후속 실험 (WP4-j — Obligation-Driven Sieve/Healing Decision):

1. read-only corpus: getBitsBE를 포함한 loop-free + intrinsic obligation > 0 함수들의
   `obligationKinds/obligationCount/hasLoop/selectedHealingPattern/patternCompatibility/finalSieveDecision` 측정.
2. 현재 dominant-rule(`has_loop`) 선택이 obligation 정보보다 우선하는지 사례 분류.
3. `pattern mismatch ≠ semantic invalidity`를 만족하도록 sieve를 hard-reject → `seRetry` 3상태로 확장
   (단, deterministic strategy ordering 보장).
4. 이후 getBitsBE를 동일 anchor로 재실행해
   `Obligation → ProofIR → SMT → Z3` 도달 여부를 WP4-k ledger로 재확인.

성공/실패에 따라 다음 경계:
- Z3 SAT/UNSAT/UNKNOWN → Lean lowering boundary (WP4-l)
- Lean accept → KAA/Trust boundary
- 여전히 planning fail → planning/semantics WP

---

## Non-goals (이번 실행에서 의도적으로 하지 않은 것)

- getBitsBE용 특수 parser / `if getBitsBE` 이름 특수화
- structural sieve/healing policy 수정 (→ WP4-j)
- Contract 주입 기본화 (비교 실험으로만)
- generic type 전체 재설계, postcondition 합성 대폭 확장
- Track B debt
- Lean/KAA 변경
- repository-wide proof

---

## Erratum (2026-08-30, WP4-j.1 Phase D에서 추가)

본 보고서의 Interpretation 4번 항목 — "getBitsBE는 여전히 structural sieve에서 중단" 및
Result의 "getBitsBE가 Z3/obligation ledger에 도달하지 못함" — 은 **정정된다**.

정정 근거 (ACT2-WP4j1 Phase D, `experiments/act2-wpj1-strategy-admission/probe/golden-script-digest-match.md`):

- 본 보고서가 "getBitsBE 관련 Z3 telemetry 없음"의 근거로 삼은 것은 telemetry 레코드에
  함수 귀속 필드가 없다는 점에 대한 **과잉 추론**이었다. 차등 telemetry 실험(target 교체)과
  golden script digest 재구성(`d9f9af27...` 정확 일치, QF_AUFBV + zmRaw)으로
  **getBitsBE의 golden obligation이 실제로 Z3에서 실행되었음(result=sat)이 실증됐다**.
- 파이프라인은 표준 경로(`ir_pipeline_runner.nim:1044` runZ3CheckViaIR)를 통과했고,
  `solverMethod=smNone`은 C20 fail-closed(`makeInconclusive(rkEvidenceRejected)`,
  `:1048`)의 고정 필드값일 뿐 Z3 미호출을 의미하지 않는다.
- psFail은 strategy-unavailable의 승격이 아니라, 무제약 자유변수 `resultBits`에 대한
  자명한 sat(공허한 인코딩 아티팩트 — subject에서 `resultBits`는 컴파일 타임 상수
  `sizeof(result)*8`이므로 나눗셈은 안전)에 대한 정직한 fail-closed 결과다.
- 분류는 `Incomplete`에서 **`Vacuous`(sat 방향) + 파이프라인 도달 확인**으로 정정되며,
  다음 경계는 structural sieve가 아니라 **obligation encoding fidelity
  (상수 전파/가정 바인딩)** 이다.

본 보고서의 나머지 결론(O9/O10/O11 테스트 통과, transport identity 결정론, exit 2의
인프라 귀속)은 변경되지 않는다.
