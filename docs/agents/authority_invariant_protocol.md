# 변경 불변조건 프로토콜 (AGENTS.md §2.6 실행 프로토콜)

이 문서는 Authority Graph Discipline의 실행 프로토콜이다.

AGENTS.md + docs/agents/는 하나의 논리적 SSOT이다. 헌법 surface(사실·불변식·canonical location)는 AGENTS.md가 정의하고, docs/agents는 operational protocol만 담는다 — 규칙의 정본은 AGENTS.md, 실행 방법의 정본은 각 프로토콜 문서다.

> **정본: AGENTS.md §2.6.** authority·state transition·failure semantics·proof가 정의되기 전에 실행 경계를 변경하지 않는다는 헌법 불변식과, 완료를 코드·테스트 성공이 아니라 **기계적으로 관측 가능한 증거**로 확인해야 한다는 의무는 **AGENTS.md §2.6**이 정의한다.

#### 실행 프로토콜 — 8항목 체크리스트

새로운 **authority(권한 주체)**, 실행 경계, 산출물 생성자, 의존성, 캐시 경계 또는 상태 변경 경로를 추가·변경할 때는 코드 수정 전에 다음을 검토한다. (아래는 점검 절차이며 위 불변식을 재정의하지 않는다)

#### 1. AUTHORITY — 실행·변경 권한

- 누가 이 산출물 또는 상태를 생성·변경할 권한을 가지는가?
- 하나의 산출물에 생성 authority가 둘 이상 생기지 않는가?
- 기존 authority가 이미 존재한다면 새 authority를 추가하지 말고 기존 것을 소비한다.

#### 2. IDENTITY — 동일성

- 무엇이 같은 논리적 객체이고 무엇이 다른 객체인가?
- execution identity와 artifact/state identity를 혼동하지 않는다.
- 재실행·재시도에서도 논리적으로 같은 대상의 identity가 불필요하게 변하지 않는지 확인한다.

#### 3. ARTIFACT — 산출물 소유권

- 무엇을 생성하는가?
- 그 산출물의 유일한 생성자는 누구인가?
- 소비자는 기존 산출물을 소비해야 하며, producer-owned 산출물을 다시 생성하지 않는다.
- 산출물은 가능한 경우 immutable artifact로 전달하고, 필요한 경우 digest/identity를 함께 결속한다.

#### 4. DEPENDENCY — 실제 의존성

- 이 작업은 무엇에 실제로 의존하는가?
- 의미적 의존성이 없는 작업 사이에 DAG edge를 추가하지 않는다.
- 병렬 실행 가능한 작업을 편의상 직렬화하지 않는다.
- 새로운 dependency edge는 반드시 그 필요성을 설명할 수 있어야 한다.

#### 5. INVARIANTS — 기존 불변조건

변경으로 다음 불변조건 중 무엇이 영향을 받는지 확인한다.

- correctness / evidence
- authority / single-writer
- identity / binding
- idempotency / retry
- concurrency / ordering
- latency / wall-clock
- compute / infrastructure cost
- failure / fail-closed semantics
- observability / auditability

**성능 최적화도 장기적으로 시스템이 의존하는 경우 architecture invariant로 취급한다.**

예:

- 한 번 생성하고 여러 consumer가 소비
- 핵심 경로의 latency budget
- 동일 logical object의 재실행은 idempotent
- 특정 상태 변경은 단일 writer만 수행

#### 6. IMPACT — 변경 영향

새로운 authority 또는 execution boundary는 단순한 로컬 구현 변경으로 취급하지 않는다.

다음을 함께 검토한다.

`authority → identity → artifact → cache → dependency → retry → latency → cost → failure`

하나를 변경하면 나머지에 미치는 영향을 확인한다.

#### 7. MINIMAL CHANGE — 최소 변경

기존 불변조건과 동작을 유지하면서 가장 작은 구조적 변경을 선택한다.

기존 최적화나 아키텍처 계약을 깨뜨려야 한다면 단순 구현 변경으로 우회하지 않는다.

#### 8. PROOF — 기계적 증명

코드와 테스트가 성공했다는 사실만으로 변경 완료를 주장하지 않는다.

변경으로 영향을 받은 불변조건이 실제 운영 또는 테스트에서 여전히 성립함을 **기계적으로 관측 가능한 증거**로 확인한다.

---

#### 신규 Job / Component / Authority 추가 시 필수 6문항

1. 왜 이 실행이 필요한가?
2. 이 실행이 유일하게 소유하는 산출물·상태·증거는 무엇인가?
3. 다른 authority가 이미 생성하는 것을 다시 생성하는 것은 아닌가?
4. 이 실행은 병렬화할 수 있는가?
5. 기존 artifact를 소비하지 않고 다시 계산해야 하는 이유가 있는가?
6. 이 실행이 발화시키는 권위 행위는 무엇이며, 시간적·데이터적 선행조건이 모두 충족된 뒤에만 발화하는가?

---

#### 불변조건 위반 규칙

변경이 기존 불변조건을 깨뜨릴 경우 다음 둘 중 하나만 허용한다.

**A.** 변경을 다시 설계하여 기존 불변조건을 유지한다.

**B.** 해당 불변조건의 폐기·변경을 ADR 등 정식 아키텍처 경로로 명시하고, 영향을 받은 속성을 다시 검증한다.

불변조건의 암묵적 회귀를 허용하지 않는다.

##### 핵심 원칙

> **새로운 authority 또는 execution boundary의 도입은 항상 기존 architecture invariant를 변경할 가능성이 있는 설계 변경으로 취급한다.**
> 운영에서만 발견되는 문제를 앞단의 invariant/contract 검증으로 최대한 끌어올리는 것이 시간을 줄이는 핵심이다.

> **"이것이 Axiom이 믿어야 하는 사실인가?"**

와

> **"이것은 그 사실을 실행하기 위한 방법인가?"**

를 반드시 분리한다.

**첫 번째 면**: Trust Layer.

**두 번째 면**: Execution Adapter.

그리고 두 번째를 첫 번째로 승격하려면 **정당한 이유가 있어야 한다.**

---


<!-- Extracted from AGENTS.md §2.6 to keep AGENTS.md under the context-size threshold. -->
