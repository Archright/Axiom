# 🏛️ Axiom: 자가 진화형 무결성 수사 체계 (Architecture v2.0.0)


## 🏛️ Axiom: 자가 진화형 무결성 수사 체계 (Architecture v2.0.0)


> 🔬 핵심 철학: AI가 생성한 소프트웨어의 논리적 무결성을 수학적으로 증명하는 자가 진화형 수사 체계.


---


## §1. 프로젝트 개요


Axiom은 AI가 생성한 소프트웨어의 무결성을 수학적으로 검증하는 엔진입니다. Bounded Model Checking(BMC), Counter-Example Guided Abstraction Refinement(CEGAR), LLM 기반 자동 형식화(Auto-formalization), Lean 4 커널 검증을 결합하여 Race Condition, Memory Safety, Logic Correctness를 연역적으로 증명합니다. Reasoning Ledger는 [Hypothesis-Attempt-Evidence] 패턴을 기반으로 변조 방지 인증서를 생성하며, 자가 진화 루프를 통해 검증 정확도를 지속적으로 향상시킵니다.


핵심 원칙: CLI First (Unix 파이프 지원, 모든 출력은 표준 스트림으로), Effect-Free Core (핵심 도메인 로직은 func + {.raises: [].}), Deterministic (동일 입력 → 동일 출력, 가스 기반 예산 시스템), Static First (컴파일 타임에 런타임 예외를 제로로 드라이브). Nim 언어 전용 (Lean 4 증명, Markdown, 빌드 설정 제외).


---


## §2. 아키텍처 레이어 (5-Layer Verification Engine)


Axiom의 검증 엔진은 5개의 독립적인 레이어로 구성됩니다. 각 레이어는 고유한 검증 기법을 담당하며, 레이어 간의 인터페이스는 명확하게 정의된 데이터 타입(Artifact)으로 연결됩니다. 전체 파이프라인은 토폴로지 분석 → 노드별 UAP(Universal Analysis Pipeline) 실행 → 인증서 생성 순서로 진행됩니다.


```plain text
┌─────────────────────────────────────────────────────────────────────┐
│                    5-Layer Verification Engine                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Layer 1: Pre-Sieve ──→ Subjective Logic 위험도 평가               │
│     │  (AST 분석, 토폴로지, Unsat Core 상관변수)                    │
│     ▼                                                               │
│  Layer 2: SWAT ──→ BMC 엔진 (빠른 경로 검증)                       │
│     │  (stepBound=5, 루프 없는 함수의 얕은 검사)                    │
│     ▼                                                               │
│  Layer 3: Detective ──→ CEGAR 엔진 (정밀 분석)                     │
│     │  (추상화 → 후보 → Z3 검증 → 정제 → 수렴)                    │
│     ▼                                                               │
│  Layer 4: Scribe + Legislator ──→ LLM 자동 형식화                  │
│     │  (불변량 초안 + Lean 4 증명 합성)                             │
│     ▼                                                               │
│  Layer 5: Judge ──→ Lean 4 Kernel 연역적 검증                      │
│     (커널 통과 = 수학적 진리, 거부 = 피드백 루프)                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```


| **계층** | **페르소나** | **핵심 기술** | **역할** |
|---|---|---|---|
| Layer 1 | Pre-Sieve | Subjective Logic (Jøsang) | AST 기반 위험도 사전 평가, 블록/경고/통과 판정 |
| Layer 2 | SWAT | Bounded Model Checking | 루프 없는 함수의 빠른 BMC 검증, 버그 즉시 탐지 |
| Layer 3 | Detective | CEGAR + Z3 SMT Solver | 추상화-정제 루프, Unsat Core 추출, 정밀 분석 |
| Layer 4 | Legislator + Scribe | LLM Auto-formalization | 불변량 초안 생성 + Lean 4 증명 코드 합성 |
| Layer 5 | Judge | Lean 4 Kernel | 연역적 검증, 결정론적 수학적 진리 확립 |


---


## §3. Layer 1: Pre-Sieve (Subjective Logic)


Pre-Sieve는 선언적 파이프라인(Chain of Responsibility)으로 구현됩니다. AST 파싱은 I/O 경계(SieveContext 생성 시점)에서 한 번만 수행되며, 이후의 모든 규칙은 순수 함수(func)로 동작합니다. 각 규칙은 SieveContext → Option[RuleResult] 타입의 결정론적 함수이며, 결과는 Jøsang의 Subjective Logic Binomial Opinion (b, d, u, a)으로 표현됩니다. 규칙 간 충돌(위험 vs 안전)은 ConflictIntensity로 감지됩니다.


### Subjective Logic 규칙 체인


| **규칙** | **조건** | **b** | **d** | **u** | **a** | **근거** |
|---|---|---|---|---|---|---|
| evaluateTopology | 의존성 깊이 ≥ 3 | 0.7 | 0.1 | 0.2 | 0.5 | 깊은 의존성 → 복잡도 상승 |
| evaluateAst | 루프 존재 | 0.6 | 0.2 | 0.2 | 0.5 | while/for → BMC 필요 |
| evaluateAst | 재귀 호출 | 0.8 | 0.1 | 0.1 | 0.5 | 재귀 → 종료 증명 필요 |
| evaluateAst | 비선형 연산 | 0.5 | 0.3 | 0.2 | 0.5 | *, / → Z3 비선형 제약 |
| evaluateUnsatCore | 상관변수 > 5 | 0.6 | 0.2 | 0.2 | 0.5 | 높은 결합도 → 분리 필요 |
| evaluateUnsatCore | 상관변수 ≤ 2 | 0.1 | 0.7 | 0.2 | 0.5 | 낮은 결합도 → 안전 신호 |
| Cumulative Fusion | 모든 의견 결합 | — | — | — | — | Jøsang eq. 4.96 누적 융합 |


### Cumulative Fusion 공식


```python
# Jøsang eq. 4.96 — Cumulative Fusion (same proposition, independent observers)
# x, y: BinomialOpinion(b, d, u, a)
# wa = padOpinion(x), wb = padOpinion(y)

denom = wa.u + wb.u - wa.u * wb.u

b_fused = (wa.b * wb.u + wb.b * wa.u) / denom
d_fused = (wa.d * wb.u + wb.d * wa.u) / denom
u_fused = (wa.u * wb.u) / denom
a_fused = (wa.a * wb.u + wb.a * wa.u) / (wa.u + wb.u)

# Expected probability (E): E = b + a·u
# ε-padding: u < ε → scale (b, d) to (1-ε), preserve ratio
```


### 차단 판정 임계값


```python
const blockThreshold   = 0.50  # E >= 0.50 → BLOCKED (파이프라인 중단)
const warningThreshold = 0.30  # E >= 0.30 → WARNING (로그 출력, 계속 진행)

score = probabilityProjection(combined)  # E = b + a·u

if score >= blockThreshold:
    → blocked = True, reason = "E={score} >= 0.50"
elif score >= warningThreshold:
    → blocked = False, warning = "E={score} approaching 0.50"
else:
    → blocked = False, safe to proceed
```


---


## §4. Layer 2: SWAT — BMC 엔진


Bounded Model Checking(BMC)은 유한 상태 공간을 탐색하여 안전 속성 위반을 찾는 기법입니다. SWAT 페르소나는 이 BMC의 '빠른 경로(fast-path)'를 담당합니다. 루프가 없는 함수는 상태 공간이 유한하므로 stepBound=5의 얕은 검사만으로도 완전한 검증이 가능합니다. 이를 통해 복잡한 CEGAR 엔진 없이도 상당수의 버그를 즉시 탐지할 수 있습니다.


### SWAT → BMC 실행 흐름


swat.nim의 executeRaid() → layer1_bmc.nim의 runLayer1Bmc() → bmc_generic.nim의 BMC 엔진 순서로 호출됩니다. BMC 결과가 lbvBugFound이면 즉시 SwatArtifact(버그 증거 포함)를 반환하고, lbvProven이면 안전 증거를 반환합니다. lbvInconclusive이면 다음 레이어(Detective)로 전달됩니다.


| **BMC 속성** | **값** |
|---|---|
| 검출 대상 1 | Race Condition — 동시 접근, 교착 상태 패턴 |
| 검출 대상 2 | Integer Overflow/Underflow — 산술 연산 범위 초과 |
| 검출 대상 3 | Index Out of Bounds — 배열/시퀀스 접근 범위 위반 |
| 검출 대상 4 | Null Dereference — nil 참조 가능성 |
| stepBound (fast-path) | 5 — 루프 없는 함수의 얕은 검사 |
| 판정 | lbvBugFound / lbvProven / lbvInconclusive |


루프 없는 함수의 얕은 검사 (stepBound=5) fast-path: SWAT는 먼저 Nim compiler parser로 AST를 파싱하여 루프/재귀 유무를 판단합니다. 루프가 없는 경우 stepBound=5로 BMC를 실행하고, 결과가 확정적이면 즉시 반환합니다. 이 fast-path는 전체 검증 시간을 크게 단축시키는 핵심 최적화입니다.


---


## §5. Layer 3: Detective — CEGAR 엔진


Counter-Example Guided Abstraction Refinement(CEGAR)은 추상 모델 검증 기법입니다. 1단계: 프로그램을 추상화하여 후보 불변량을 생성합니다. 2단계: Z3 SMT Solver로 후보를 검증합니다. 3단계: 검증 실패 시 반례(Counter-Example)를 추출하고 추상화를 정제합니다. 4단계: 수렴 조건(지문 중복 또는 최대 반복)에 도달할 때까지 반복합니다.


### CEGAR 실행 흐름


detective.nim의 investigate() → cegar_engine.nim의 CEGAR 루프 → fixedpoint_engine.nim의 고정점 분석 순서로 진행됩니다. 추상화된 프로그램에서 후보 불변량을 생성하고, Z3로 검증하여 반례가 있으면 Unsat Core를 추출하여 정제합니다.


```plain text
┌──────────────────────────────────────────────────────────────┐
│                    CEGAR Refinement Loop                     │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ① Abstract ──→ 추상 모델 생성 (CFG + 추상 상태)            │
│     │                                                        │
│     ▼                                                        │
│  ② Candidate ──→ 후보 불변량 생성 (fixedpoint engine)       │
│     │                                                        │
│     ▼                                                        │
│  ③ Z3-check ──→ SMT-LIB2 인코딩 후 Z3 실행                  │
│     │                                                        │
│     ├── SAT (반례 발견) ──→ Unsat Core 추출                  │
│     │     │                                                  │
│     │     ▼                                                  │
│     │  ④ Refine ──→ 추상화 정제 (핵심 변수 확장)             │
│     │     │                                                  │
│     │     └──→ ①으로 복귀 (fingerprint로 중복 감지)          │
│     │                                                        │
│     └── UNSAT (안전 증명) ──→ cegarProven 반환               │
│                                                              │
│  종료 조건: 수렴 (동일 fingerprint) 또는 max iterations      │
└──────────────────────────────────────────────────────────────┘
```


Unsat Core 추출: Z3가 UNSAT을 반환하면, 추적 변수(track_N)를 사용하여 어떤 불변량들이 증명에 기여했는지 추출합니다. 이 Unsat Core는 이후 CEGAR→BMC Bridge에서 구체적인 반례 추적(witness trace)을 생성하는 데 사용됩니다.


| **CEGAR 결과** | **설명** |
|---|---|
| cegarProven | 모든 추상 상태에서 안전성이 증명됨. 수학적 안전 보장. |
| cegarCounterexample | 구체적인 반례가 발견됨. CEGAR→BMC Bridge로 witness trace 생성. |
| cegarMaxIterations | 최대 반복 횟수(20회)에 도달. 수렴 실패. |
| cegarBudgetExceeded | 가스 예산(gas limit) 초과. 더 이상의 solver 호출 불가. |


---


## §6. Layer 4: Scribe + Legislator — LLM 자동 형식화


Layer 4는 두 개의 독립적인 페르소나로 분리됩니다: 입법자(Legislator)는 LLM을 사용하여 불변량(Loop Invariant)을 초안하고, 서기(Scribe)는 Lean 4 증명 코드를 합성합니다. 이 분리는 관심사 분리(SoC) 원칙에 따라 설계되었습니다.


### Legislator — LLM-Only 불변량 초안


Legislator는 LLM-only 정책(§0.2a HARD RULE)을 따릅니다. 정적 휴리스틱 기반 불변량 생성은 금지되어 있으며, callLeanstral()을 통해서만 불변량을 초안합니다. 입력으로 함수 소스 코드, 이전 불변량, ASI 메트릭을 받아 더 정교한 불변량을 제안합니다. legislator.nim의 legislate() → callLeanstral(prompt) 흐름으로 동작합니다.


### Scribe — Lean 4 증명 합성


Scribe는 Leanstral 모델을 사용하여 Lean 4 증명 코드를 합성합니다. scribe.nim의 synthesizeLeanTheorem() → callLeanstral(leanPrompt) → lean_replay.nim의 runLeanReplay() 순서로 동작합니다. 합성된 증명은 즉시 Lean 4 컴파일러로 검증(replay)되며, 검증 실패 시 재시도합니다. 제한된 Lean 4 전용 전술만 사용 가능: rfl, simp, intro, apply, exact, rw, induction, cases, assumption, constructor, calc, have, refine, omega.


### Legislator → Scribe 연결


legislator.nim → callLeanstral() → scribe.nim → synthesizeLeanTheorem() 흐름: Legislator가 생성한 불변량이 Scribe의 Lean 4 증명 합성에 시드(seed)로 전달됩니다. 불변량이 비어 있으면 이전 promotion의 불변량을 fallback으로 사용합니다. mergeInvariantClauses()로 새 불변량과 기존 불변량을 병합합니다.


| **LLM 컴포넌트** | **모델** | **역할** |
|---|---|---|
| Legislator | Leanstral (callLeanstral) | 함수 불변량 초안 생성, 정적 휴리스틱 금지 |
| Scribe | Leanstral (callLeanstral) | Lean 4 증명 코드 합성, 즉시 replay 검증 |
| Feedback | Legislator Feedback | Judge 거부 시 CounterExamplePayload 전달, 재시도 유도 |


---


## §7. Layer 5: Judge — Lean 4 Kernel 검증


Judge는 Axiom 검증 체계의 최종 관문입니다. Lean 4의 커널은 독립적으로 검증 가능한 연역적 추론 엔진으로, 커널이 증명을 수락하면 그 결과는 수학적 진리로 확립됩니다. judge.nim → lean_replay.nim → verification_unit.nim 흐름으로 동작합니다.


### Leanstral Shortcut


사전 합성된 증명(Leanstral이 생성한 Lean 4 코드)이 Lean 커널을 통과하면 즉시 수락됩니다. 이는 LLM의 합성 능력과 커널의 검증 능력을 결합한 효율적인 검증 경로입니다. runLeanReplay()가 Lean 4 컴파일러를 서브프로세스로 실행하여 검증합니다.


### Closed-loop Feedback


Judge가 증명을 거부하면, CounterExamplePayload가 Legislator에 전달됩니다. 이 피드백에는 Lean 컴파일러의 오류 메시지, 위치 정보, 진단 불연속성이 포함됩니다. Legislator는 이 정보를 사용하여 더 나은 불변량을 재생성합니다. 3회 연속 Z3 거부 시 refactoringEscalated → 인간 아키텍트에게 핸드오프합니다.


| **Judge 경로** | **조건** | **동작** |
|---|---|---|
| Leanstral Shortcut | Leanstral 증명이 커널 통과 | 즉시 수락, 검증 완료 |
| VerificationUnit | 표준 검증 파이프라인 | verification_unit.nim을 통한 체계적 검증 |
| Closed-loop Retry | 커널 거부 시 | CounterExamplePayload를 Legislator에 전달, 재시도 (최대 5회) |


---


## §8. 자가 진화 루프 (The Closed-Loop)


Axiom의 핵심 차별화 요소는 5단계 폐루프(closed-loop) 자가 진화 메커니즘입니다. 검증 실패가 단순한 에러가 아닌 학습 기회로 전환되어, 시스템이 반복 실행마다 정확도를 향상시킵니다.


```plain text
┌──────────────────────────────────────────────────────────────┐
│               5-Step Closed-Loop Evolution                   │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ① [의도 입법] Legislator: LLM이 불변량 초안 생성           │
│     │                                                        │
│     ▼                                                        │
│  ② [헌법 심판] Judge: Lean 4 커널이 연역적 검증              │
│     │                                                        │
│     ▼                                                        │
│  ③ [취약점 추리] Detective: CEGAR로 반례 분석                │
│     │                                                        │
│     ▼                                                        │
│  ④ [특공대 급습] SWAT: BMC로 구체적 증거 확보               │
│     │                                                        │
│     ▼                                                        │
│  ⑤ [반례 학습] Feedback → Legislator에 전달 → ①으로 복귀   │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```


### 3중 피드백 메커니즘

1. Inner Loop — CEGAR: 추상화 → Z3 검증 → 정제. 최대 20회 반복. fingerprint로 수렴 감지.
1. Middle Loop — Judge Retry: 거부 → Legislator에 CounterExamplePayload 전달 → 재합성. 최대 5회.
1. Outer Loop — f×g×h Refactoring: 3회 연속 Z3 거부 → refactoringEscalated → 인간 핸드오프.

### 정체 감지 (Stagnation Detection)


RefactoringStagnation 객체가 연속 실패 횟수를 추적합니다. 기본 최대 실패 횟수는 3회(maxFailures=3)이며, 이 한계에 도달하면 escalated 플래그가 설정되고 인간 아키텍트에게 핸드오프합니다. metricsHistory에 ProgressMetric(unsatCoreSize, invariantCount, leanKernelVerified, proofDepth, roundIndex)을 기록하여 진행 상황을 추적합니다. 지문(fingerprint) 중복 감지를 통해 동일한 상태를 반복하는 무한 루프를 방지합니다.


---


## §9. 3대 최종 관문 (Sieve / Diagnosis / Guidance)


```plain text
┌──────────────────────────────────────────────────────────────┐
│                   3 Final Gates Architecture                 │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Sieve (판별) ──→ Pre-Sieve + Post-UAP 인증서 볼트          │
│     │                                                        │
│     ▼                                                        │
│  Diagnosis (진단) ──→ 6종 수학적 불연속성 분석               │
│     │     Unsat Core 상관변수 추출                            │
│     ▼                                                        │
│  Guidance (교정) ──→ f×g×h 리팩토링 엔진                    │
│        6종 패턴 → 자동 코드 변환 → Z3 등가성 검증           │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```


### 판별 (Sieve)


Pre-Sieve(Subjective Logic)의 위험도 평가와 Post-UAP의 인증서 볼트(certificate vault)를 결합하여 함수의 검증 상태를 판별합니다. 인증서 지문(fingerprint)이 이미 존재하면 증분 검증을 수행하고, 없으면 전체 검증 파이프라인을 실행합니다.


### 진단 (Diagnosis)


6종 수학적 불연속성을 탐지합니다: Quantifier Excess, Non-linear Arithmetic, Deep Dependency, High Coupling, Missing Loop Invariant, Missing Decrease Measure. Unsat Core 상관변수 분석을 통해 검증 실패의 근본 원인을 정확히 식별합니다. diagnostics_engine.nim이 진단을 수행하고, 결과를 RefactoringSignalKind로 변환합니다.


### 교정 (Guidance)


f×g×h 리팩토링 엔진(refactoring_engine.nim)이 진단 결과를 기반으로 자동 코드 변환을 수행합니다. f(g(h(code))) 패턴에서 f=구조 복잡도, g=제약 복잡도, h=의존 복잡도를 나타냅니다. 변환 후 Z3 등가성 검증으로 안전성을 보장합니다.


| **관문** | **구현** | **출력** |
|---|---|---|
| 판별 (Sieve) | sieve_engine.nim + certificate_manager.nim | SieveVerdict (blocked/warning/pass) + 인증서 상태 |
| 진단 (Diagnosis) | diagnostics_engine.nim | RefactoringSignalKind[] + UnsatCore 상관변수 |
| 교정 (Guidance) | refactoring_engine.nim | RefactoringTemplate[] + Z3 등가성 검증 결과 |


### 리팩토링 패턴 매핑


| **Signal** | **Pattern** | **설명** |
|---|---|---|
| Quantifier Excess | ExtractPureFunction | 정수자 범위를 순수 함수로 추출 |
| Non-linear Arithmetic | LinearizeVariables | 비선형 제약을 선형 보조 변수로 대체 |
| Deep Dependency | InsertCompositionNode | 중간 조합 노드 삽입으로 깊이 감소 |
| High Coupling | IsolateInterface | 경계 계약 분리 |
| Missing Loop Invariant | AddLoopInvariant | 루프 불변량 주석 추가 |
| Missing Decrease Measure | AddDecreaseMeasure | 종료 측정치 추가 |


---


## §10. 5대 페르소나 (Core Quintet)


Axiom의 검증 체계는 5개의 독립적인 페르소나(persona)로 구성됩니다. 각 페르소나는 고유한 기술 스택과 역할을 가지며, persona_interface.nim을 통해 공통 인터페이스를 구현합니다. 페르소나 간 통신은 명확히 정의된 Artifact 타입을 통해서만 이루어집니다.


| **페르소나** | **기술 스택** | **핵심 역할** |
|---|---|---|
| Pre-Sieve | Subjective Logic (Jøsang) | AST 분석 기반 위험도 사전 평가, 블록/경고/통과 판정 |
| Legislator | LLM (Leanstral), callLeanstral() | 불변량 초안 생성, LLM-only 정책 준수 |
| Judge | Lean 4 Kernel, lean_replay.nim | 연역적 검증, 수학적 진리 확립, 피드백 루프 |
| Detective | CEGAR, Z3 SMT Solver | 추상화-정제 루프, Unsat Core 추출, 반례 분석 |
| SWAT | BMC (bmc_generic.nim), Nim compiler parser | 빠른 경로 BMC 검증, 버그 즉시 탐지, 증거 확보 |


---


## §11. CLI 아키텍참


진입점: **3개 실행 표면** 이 존재합니다 — **bin/ax** (통합 CLI), **bin/run_gate** (게이트 러너), **bin/axiom-gate** (커밋 게이트). 모두 `src/cli/` 소스에서 빌드되며, `bin/ax`가 주요 진입점입니다.


### 디스치 체인


**runMain() → stripGlobalFlags() → mainLoop() → planAxActions() → interpretCliActions()**


3단계 디스치: **planAxActions()** (action_plan_cli.nim:78) → **seq[CliAction]** 생성. **interpretCliActions()** (action_interpreter_cli.nim:38) → 각 action 실행. **cliRunAxiomEngine** 액션은 **runAxiomEngineCli()** (axiom_engine.nim:179)로 디스치.


### ax prove 흐름


```plain text
ax prove --limit 50
  │
  ├─ parseAxProveFlags(args) → AxProveFlags(limit: 50)
  ├─ loadTomlConfig("axiom.toml") → [prove] 기본값
  ├─ buildProofTask(flags, ...) → ProofTask
  ├─ initAxiomEngine(mono, gasLimit) → ProofBudget
  ├─ runProofPipeline(engine, task, ...)
  │    ├─ analyzeTopologySourceRoot("src/", queueLimit=50)
  │    │    ├─ 701 파일 스캔, 3412 심볼 추출
  │    │    └─ 상위 50개 노드 → verificationQueue
  │    ├─ topologyToWorkflowPayload(topology)
  │    └─ runBatchUapOrchestration(state, requests)
  │         ├─ Pre-Sieve Interceptor (Subjective Logic)
  │         ├─ UAP: SWAT → Detective → Scribe → Judge
  │         └─ BatchUapReport
  └─ ProofReport (JSON + exitCode)
```


### 구현된 CLI 명령어 (3개)


| **명령어** | **플래그** | **역할** | **구현 파일** |
|---|---|---|---|
| ax prove | [--limit N] | 소스 스캔, 타겟 증명, 자동 치유. ASI 1.0000 도달까지 반복. | axiom_engine.nim |
| ax report | [--json] | 검증 보고서, ASI 메트릭, 인증서 상태 생성. TTY 감지 시 자동 JSON. | report_cli.nim |
| ax help | (없음) | 도움말 출력 후 종료. | action_plan_cli.nim |


**axCommandHelpEntries()** (action_plan_cli.nim:16) 가 SSOT를 제공합니다. **AxSubcommandKind** 열거형에는 **axSubcommandProve**, **axSubcommandReport**, **axSubcommandHelp** 만 존재합니다.


| **명렉어** | **플래그** | **역할** | **구현 파일** |
|---|---|---|---|
| ax prove | [--limit N] | 소스 스캔, 타겟 증명, 자동 치유. ASI 1.0000 도달까지 반복. | axiom_engine.nim |
| ax report | [--json] | 검증 보고서, ASI 메트릭, 인증서 상태 생성. | report_cli.nim |
| ax help | (없음) | 도움말 출력 후 종료. | action_plan_cli.nim |


### 명렉어 SSOT


| **SSOT** | **파일** | **역할** |
|---|---|---|
| 플래그 SSOT | cli_surface_generated.nim | cli_surface_generator.nim에 의해 자동 생성. --limit, --json 등. |
| 명렉어 SSOT | axCommandHelpEntries() | action_plan_cli.nim:16. 모든 ax 명렉어 이름/usage/description. |
| 서브컴맨드 열거형 | AxSubcommandKind | cli_types.nim:50. prove, report, help 3개만 존재. |


---


## §12. 게이트 시스템


게이트 시스템은 3계층 구조로 아키텍처 원칙과 코드 품질을 enforcement합니다. L0 Orchestrator(gate_hook.nim)가 전체 게이트를 스케줄링하고, L1 Meta 게이트가 인프라 무결성을 검증하며, L2 Functional 게이트가 코드/로직 검증을 수행합니다. L1 게이트는 L0 진입점을 참조할 수 없다는 계층 경계 규칙이 컴파일 타임 static assertion으로 enforce됩니다.


### nimtry 통합 아키텍처 원칙 Enforcement


nimtry(src/gate/nimtry/)는 SOLID, SSOT, DRY, SoC 아키텍처 원칙을 통합적으로 검증하는 단일 엔진입니다. SHA256 증분 캐시(.nimcache/nimtry/)를 사용하여 모듈 수에 무관한 warm-scan 성능을 보장합니다. Pre-commit: 변경된 파일만 캐시 해시와 비교. Pre-push: 캐시 미스 또는 --full-tree 플래그 시 전체 트리 스캔.


| **게이트 계층** | **진입점** | **역할** |
|---|---|---|
| L0 Orchestrator | bin/gate_hook | 게이트 스케줄링, cgroups, 리소스 제한. 모든 계층 제어. |
| L1 Meta | src/gate/runners/gate_self_check, sentinel, quality-gate-marker | 인프라 검증, 마커 유효성 검사. L0 참조 금지. |
| L2 Functional | bin/*_gate, src/gate/runners/* | 코드/로직 검증 (nim check, tests 등). cgroups 하위 프로세스. |
| L2d nimtry | src/gate/nimtry/nimtry_cli.nim, src/gate/nimtry/ | 통합 아키텍처 원칙 enforcement (SOLID, SSOT, DRY, SoC) |


### 4-Layer Resource Defense Stack


L1 CPU: countProcessors() / 2 (동시성 제한). L2 Priority: nice -n 10 (우선순위 낮춤). L3 OS Guard: cgroups v2 (CPUQuota=50%, IOWeight=10, MemoryMax=8G). L4 Memory: setrlimit(RLIMIT_AS, 1536MB) per-process.


---


## §13. 구현 파일 맵


### Pre-Sieve (Subjective Logic) 모듈


| **파일** | **역할** |
|---|---|
| src/sieve/sieve_engine.nim | Pre-Sieve 메인 엔진. applyPreSieve() — 규칙 체인 실행, 융합, 판정. |
| src/sieve/sieve_rules.nim | 순수 규칙 체인. evaluateTopology, evaluateAst, evaluateUnsatCore. |
| src/sieve/subjective_logic.nim | Jøsang Subjective Logic 구현. BinomialOpinion, Cumulative Fusion. |
| src/sieve/sieve_types.nim | Pre-Sieve 타입 정의. SieveContext, RuleResult, SieveVerdict. |
| src/sieve/sieve_bridge.nim | I/O 경계. AST 파싱, SieveContext 생성. |


### 핵심 검증 모듈


| **파일** | **역할** |
|---|---|
| src/personas/swat.nim | SWAT 페르소나. executeRaid() — BMC 빠른 경로 실행. |
| src/personas/detective.nim | Detective 페르소나. investigate() — CEGAR 분석. |
| src/personas/legislator.nim | Legislator 페르소나. legislate() — LLM 불변량 초안. |
| src/personas/scribe.nim | Scribe 페르소나. synthesizeLeanTheorem() — Lean 4 증명 합성. |
| src/personas/judge.nim | Judge 페르소나. adjudicate() — Lean 4 커널 검증. |
| src/verification/cegar_engine.nim | CEGAR 엔진. 추상화-정제 루프, fingerprint 수렴. |
| src/verification/cegar_bmc_bridge.nim | CEGAR→BMC 브릿지. 반례에서 구체적 witness trace 생성. |
| src/core/bmc/bmc_generic.nim | 범용 BMC 엔진. overflow/bounds/null/race 검출. |
| src/core/proof/proof_budget.nim | 이중 예산 시스템. 가스 제한(deterministic) + 월클록 안전망. |
| src/core/diagnostics/refactoring_engine.nim | f×g×h 리팩토링 엔진. 6종 패턴 → Z3 등가성 검증. |
| src/core/judge/lean_replay.nim | Lean 4 컴파일러 replay. 증명 검증 via subprocess. |
| [DEPRECATED] src/verification/batch_uap_orchestrator.nim | 배치 UAP 오케스트레이터. 토폴로지 → 노드별 UAP. |


### 아키텍처 변경 이력


| **변경** | **이전** | **이후** |
|---|---|---|
| Sieve 엔진 | 단순 필터 | Subjective Logic 기반 확률적 평가 |
| CEGAR | 가짜 적응 추상화 (timeout fallback) | 실제 고정점 수렴 루프 |
| Legislator | 정적 휴리스틱 + LLM 혼합 | LLM-Only (§0.2a HARD RULE) |
| 리팩토링 | 수동 | f×g×h 자동 + Z3 등가성 검증 |


---


## §14. 결정론적 안전성 보장


Axiom은 동일한 입력에 대해 항상 동일한 출력을 보장하는 결정론적 시스템입니다. 이는 검증 결과의 신뢰성과 재현성의 핵심 전제입니다.


| **속성** | **보장 방식** |
|---|---|
| 동일 입력 → 동일 출력 | 가스 기반 예산 시스템(proof_budget.nim). iteration count = deterministic. |
| 순수 함수 핵심 | 핵심 도메인 로직은 func + {.raises: [].}. I/O 경계에서만 proc. |
| AST 파싱 I/O 경계 | Nim compiler parser 파싱은 SieveContext 생성 시 1회. 이후 순수 함수. |
| CEGAR 지문 수렴 | FNV-1a 64-bit fingerprint로 동일 상태 재탐색 방지. |
| Z3 결정론 | SMT-LIB2 인코딩이 결정론적. 동일 제약 → 동일 결과. |
| Lean 4 커널 | 커널은 결정론적 연역 추론 엔진. 검증 결과 수학적 진리. |
| 가스 한계 | maxTotalSolverInvocations=8. 예산 소진 = deterministic failure. |
| 월클록 안전망 | orchestrationWallClockTimeoutMs=600,000 (10분). 비결정론적이나 2nd-class. |
| 증분 캐시 | SHA256 캐시(.nimcache/nimtry/). 변경된 파일만 재검증. |


---


> 📋 문서 버전: Architecture v2.0.0
🔧 구현 언어: Nim 2.2.10 + Lean 4.33.0
📅 갱신: 2026-06-05
🔒 보안: 모든 핵심 로직은 {.raises: [].} + func로 컴파일 타임에 안전성 보장
