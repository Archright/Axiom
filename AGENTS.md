# Axiom 에이전트 지침

> **이 파일이 정의하는 것**: AGENTS.md는 **무엇이 참인가 · 무엇이 허용되는가 · 누가 권한을 가지는가 · 무엇이 완료인가**를 규정한 헌법이다. "어떻게 실행하는가"를 가르치는 문서가 아니다.
> **잔류 기준**: 이 파일에 남는 문장은 **Fact · Invariant · Authority · Acceptance/Failure**뿐이다. Procedure · Tool · Checklist · Rationale · Example은 이 파일에 존재하지 않으며, 그 전문은 `docs/agents/`가 담는다.
> **단방향 구조**: AGENTS.md가 정의하고 `docs/agents/`가 이를 참조한다 — 역방향 참조는 허용되지 않는다.
> 측정·감사·역사·생성 데이터는 §5 SSOT 위치를 따른다. 정본 계산이 존재할 때, AGENTS.md는 그 현재 값을 중복해서는 안 된다.

---

## §-1. 에이전트 수정 제한 (ABSOLUTE RULE)

다음 파일들은 **인간 아키텍트의 명시적 승인 없이 불변**이다:

- `src/gate/runners/import_encapsulation_gate.nim` + `config.nims` importEncapsulation 블록
- `AGENTS.md`

에이전트는 인간 아키텍트의 명시적 지시 없이 이 파일들을 **수정·우회·무효화해서는 안 된다**. 위반 = 즉시 작업 실패.

---

<!-- AGENTS.md는 1차 SSOT다. 이 파일과 docs/agents/ 아래의 모든 문서는
     하나의 논리적 SSOT를 이룬다. -->

---

## §0. 헌법 (CONSTITUTION)

### 0.1 프로젝트 목적

Axiom은 지원 대상 Nim 커널 범위에 대해 결정적 검증 결과·보증 등급·로컬 재현 검증 산출물을 제공하는 개발자 CLI다 (v1 제품 계약: [docs/spec/productization_contract.md]). Reasoning Ledger는 **[가설-시도-증거]**를 변조 방지 인증서로 정규화한다. **Zero-Footprint Integrity** + **CLI First**가 기본 원칙이다.

### 0.2 1차 원리 우아함 (First-Principles Elegance)

모든 변경은 **Ideal**(컴파일 시점 예방)·**Elegant**(언어 네이티브 도구)·**Fundamental**(하드코딩 예외 없음)·**Deterministic**(동일 입력 → 동일 출력)을 만족해야 한다. 에이전트는 설계 등급을 낮출 **권한이 없다**. 회피 불가능한 컴파일러 quirk는 §0.5에 따라 `docs/spec/`에 문서화한다.

### 0.2a 입법자 LLM 전용 의무 (HARD RULE)

Legislator 페르소나의 불변식은 **Leanstral API로만** 작성한다 — 로컬 LLM·기타 외부 LLM API·정적 휴리스틱은 금지된다. `docs/spec/legislator_llm_only_policy.md`.

### 0.3 신뢰 경계 (HARD RULE)

"차단 해제"를 위해 신뢰 경계·정본 계약 우회 금지; 문서화된 계약을 따른다. 전체: [constitution_details §0.3](docs/agents/constitution_details.md).

### 0.4c 메모리 정책 마커 (HARD RULE)

- **메모리에 기록하지 말 것**
- **프로젝트 정책/규칙/컨벤션은 모두 AGENTS.md에**

정책은 AGENTS.md + `docs/agents/`에만 존재한다. [docs/agents/memory_policy.md] 참조.

### 0.5 문서 우선 (Documentation-First) (HARD RULE)

모든 시스템 수준 변경은 공식 문서를 먼저 읽고, 문서 링크를 커밋/이슈에 기록한다. **Quirk Mandate**: 발견한 언어·컴파일러·툴체인 quirk는 반드시 `docs/spec/<topic>_quirks.md`에 문서화하고 여기에서 참조한다. 목록: [constitution_details §0.5b](docs/agents/constitution_details.md).

### 0.5c 부채 & QUIRK 마커 (HARD RULE)

무 ID의 순화 표현(`// quirk`, `// hack`)은 빌드를 차단한다 — `QUIRK(DEBT#xxx)` + `{.axiomDebt: "DEBT#xxx", kind: "quirk".}` 이중 결속만 허용된다. 추적된 마커를 제거·수정하지 않는다(`data/debt_registry.json`). 강제: `architecture_invariants.nim` + `debt_integrity_gate.nim`.

### 0.6 정적 우선 & 코드 정책

- **Static-Analysis-First (판정·검증)**: 정적으로 결정 가능한 판정·검증을 우선한다; 런타임(CI·태그 push·실행 증거)은 정적 불가 항목만 담당한다. 불일치 시 관측을 부정하지 않고 정적 모델을 관측에 보정한다.
- 코어: `func` + `{.raises: [].}` 기본; `proc`는 I/O 경계만 + `{.axiomEffect: IoEffect.}`.
- 동시성: malebolgia(CPU·value만), asyncdispatch/startProcess(I/O)만 허용; `spawn` + `ref object` 금지.
- 바이너리: Git LFS 필수(≤10KB 아이콘/로고 면제). 전체: [constitution_details §0.6–0.6b](docs/agents/constitution_details.md).

### 0.7 비즈니스 한정 테스트 범위

`tests/gateway/*.feature`의 비즈니스 시나리오만 — 컴파일러 보장 동작 제외. [§0.7](docs/agents/constitution_details.md)

### 0.8 스텁 파일 금지

스텁(`check true` 밀도 >50%) → 게이트 FAIL + 작업 거절; 에이전트는 자신의 스텁을 삭제한다. [§0.8](docs/agents/constitution_details.md)

### 0.9 극장 금지 (Theater Prohibition) (HARD RULE)

**Theater(극장)** = 보장하는 척/보이는 척 하면서 아무것도 보장하지 않는 것(항상 통과·실패 삼킴·위장 스텁·공허한 증명·죽은 게이트·강제 안 된 주장). 도입 = 작업 실패. 발견된 극장은 **반드시** `data/debt_registry.json`에 등록한다(접두사 `Theater/`, source `theater_audit`) — 절대 조용히 패치하지 않는다. Fail-open 경로는 `docs/spec/`에 문서화 + 런타임 로깅된 경우에만 극장이 아니다.

### 0.9a 극장 레지스트리 스키마

극장/마스킹 행동 추가 금지. `data/debt_registry.json` 기존 스키마 준수(문서 참조) — file+symbol+contentHash 일치 → 0-token skip.

### 0.9b 무한 후퇴 종료 (HARD RULE)

"검증자를 누가 검증하는가?" → **Triple-Closure**: 외부 뮤테이션 하니스 → `static_gate_scanner.nim`의 인간 감사(작고 순수한 TCB) → 직교 언어(Nim→Nim, Lean 4→Lean). 한 단계라도 건너뛰면 = 작업 실패. 전체: [constitution_details §0.9b](docs/agents/constitution_details.md).

### 0.10 결정 바인딩 (Decision Binding) (HARD RULE)

변경은 커밋된 결정/정책에 구속; waiver(`config/decision_binding.waiver.toml`) 없이 우회 금지. 전체: [docs/spec/decision_binding_framework.md].

### 0.11 어휘 (Lexicon) (HARD RULE)

도메인 용어는 인터넷 검색으로 찾을 수 없다; `src/`/`docs/spec/` SSOT에서 출처 증거와 함께 답한다; 숫자는 `data/baseline.json` 원 계산 경로.

- **VKD** — 심층 검증받는 VKS 심볼 비율; 정본 밀도 투영 ONLY(역사적/캐시 값 무권위). [docs/spec/verification_density.md]
- **VKS** — 면제 적용 후 검증 가능한 커널 범위 (정본·숫자: 위 문서 + `data/baseline.json`).
- **ASI** — 정보 가중 안정성 지수(`src/core/types/asi_types.nim`); `coverageRatio`/`rigorScore`는 보조, VKD와 분리.

### 0.12 제품 계약 및 수직 슬라이스 우선 (HARD RULE)

**제품 계약과 acceptance criteria가 구현보다 선행한다** — 범위와 terminal outcome이 정의되지 않은 작업은 구현을 시작하지 않는다. 서브시스템 완결성이 아니라 커밋된 계약과 고객 대면 수직 슬라이스가 주도한다.

불변식: 우아함·재사용·이론·미래 필요만으로 서브시스템을 만들지 않는다; 최소 변경 우선; 고객 무관하면 유보; 슬라이스 선행은 correctness·integrity·reproducibility·determinism의 검증된 전제조건일 때만. 단위 테스트·아키텍처 품질·커버리지는 제품 준비성을 **입증하지 않는다** — 종단간 계약이 필요하다.

구현 전 질문 체크리스트와 각 판단 절차: [constitution_details §0.12](docs/agents/constitution_details.md).

#### 제품 계약 SSOT

`docs/spec/productization_contract.md` + `config/readiness_policy.json` + `tools/readiness_evaluator.nim`이 범위 정의. 충돌 시: 계약 보존 → 최소 변경 → 무관 유보 → 확장 전 계약 명시 개정. 모든 새 공개 표면/지표/산출물/주장은 계약 또는 승인 개정으로 정당화.

---

## §1. 아키텍처 (ARCHITECTURE)

- CLI 우선; MCP/IDE 인터페이스는 확장이지 핵심이 아니다.
- 계층 경계와 정본 진실 원천을 보존한다; 중복 의미 상태 금지.
- 핵심 검증 로직은 결정적이고 부수효과 제한 상태를 유지한다.
- Hermetic 빌드/게이트 무결성 규칙은 필수다(§-1).
- 커밋된 제품 계약 없이 새 아키텍처 계층 추가 금지(§0.12).
- 상세 아키텍처와 결정: [docs/agents/architecture.md](docs/agents/architecture.md) + `docs/spec/`.

---

## §2. 규칙 & 워크플로

- 편집 전 관련 저장소 지침을 로드하고, 변경 전 GUARDIAN을 적용한다([docs/agents/core_rules.md](docs/agents/core_rules.md)).
- 커밋은 프로젝트 필수 게이트를 통과해야만 수용된다 — 게이트 우회·감사 추적 없는 통과는 금지된다.
- merge(랜딩) authority는 GitHub다 — PR 랜딩의 정본은 GitHub 네이티브 MERGE 커밋이다.

### 2.1 피처 작업 브랜치 정책 (HARD RULE)

비사소 구현은 전용 workstream 브랜치에서만 수행한다. `main`에서의 source mutation은 금지된다. `main`의 미커밋 변경은 절대 reset·discard·stash·overwrite 금지(보존 후 전환). 완료는 기계 검증을 수반한다 — "완료됨" 주장은 증거가 아니다. 절차: [docs/agents/task-process.md](docs/agents/task-process.md).

### 2.2 작업 범위 & 완료 정책

**최종 결과가 권위**다 — 증거로 입증된 때만 완료다. **범위는 닫힌다** — 범위 밖 발견은 Follow-up이며 확장을 정당화하지 않는다. **발견 ≠ 권한**(관찰은 작업도 인가도 아니다). **기회적 리팩터링 금지.** **완료는 기계 검증**이다 — 명령→관측→pass/fail 없이 완료를 주장할 수 없다. 전문: [docs/agents/task-process.md](docs/agents/task-process.md).

### 2.3 GitHub Actions·merge-admission 관측 계약 (HARD RULE)

- **Per-output authority**: 각 제어 대상 상태·산출물에는 정확히 하나의 선언된 authority가 있고, adapter·reporter는 authority가 아니다(`Authority ≠ Adapter`).
- **merge-admission의 authority는 GitHub다**(ruleset·required checks·queue·병합); 다른 층의 성공은 GitHub의 판정을 대체하지 않는다.
- required checks가 0건이면 **UNKNOWN / NOT READY**다 — SUCCESS로 해석하지 않는다.
- 단일 관측층(L1)의 성공만으로 merge-admission 완료를 주장하지 않는다.

전문: [docs/agents/merge_admission_observation.md](docs/agents/merge_admission_observation.md).

### 2.4 자격 증명 권한 (Credential Authority) (HARD RULE)

외부 자격 증명은 네이티브 클라이언트로만(GitHub = `gh auth`). 파일시스템·dotfiles·환경변수·키링·셸 히스토리·비밀 경로 스캔하여 발견·읽기·복사·내보내기 **금지**. 네이티브 인증 실패 = 보고 후 STOP(발견은 절대 대체 수단 아님). 명시 프로비저닝 시크릿은 발견 대상 아님.

### 2.5 CI Self-Bootstrap Bottleneck (HARD RULE)

**활성(live) 실행 경계를 in-place로 부분 수정하여 상태를 혼합하지 않는다** — 변경은 일관된 세대(coherent generation) 전환으로 착지해야 한다. 모든 CI 변경은 규모를 불문하고 이 불변식을 따른다.

"작은 변경"이라는 독자 판단으로 절차·검증을 축약·생략하지 않는다 — 권한은 사용자 명시에만 있다. 단순함을 이유로 correctness를 가정하지 않으며, 불변식 무효화는 명시 판정해야 한다. 폐기 기록(tombstone)은 권한·면제를 갖지 않는다(역사 기록일 뿐). 되돌릴 수 없는 상태에서 기존 실행 경계를 영구 제거하지 않는다.

전문: [docs/agents/ci_epoch_cutover.md](docs/agents/ci_epoch_cutover.md).

### 2.6 변경 불변조건 프로토콜 (HARD RULE)

**authority · state transition · failure semantics · proof가 정의되지 않은 상태에서 실행 경계를 변경하지 않는다.**

- 산출물당 생성 authority는 하나다 — 기존 authority가 있으면 추가하지 말고 소비한다. 실행은 산출물·상태가 아니며, 재실행은 identity를 불필요하게 변동시키지 않는다.
- 계약 파괴를 구현으로 우회하지 않는다 — 최소 구조 변경으로 불변식을 유지한다. 코드·테스트 성공만으로 완료를 주장하지 않는다; **기계적 관측 증거**가 필수다.

전문: [docs/agents/authority_invariant_protocol.md](docs/agents/authority_invariant_protocol.md).

### 2.7 작업 공간 & 브랜치 정책 (HARD RULE)

목적 불변식은 **I1 workstream 격리**(다른 workstream의 작업 공간 침범 금지)와 **I2 결정론적 수렴**(GitHub merge authority → main)뿐이다. 아래 장치는 목적을 대체하지 않는다.

- **보호 대상은 `main` branch이지 main clone 디렉터리가 아니다.** `main`에서의 source mutation은 금지하되, clone 내에서 토픽 브랜치로 전환해 작업하는 것은 정상 경로다(clone-first). 새 workspace를 만들지 않고 현재 clone에서 작업한다.
- **session은 executor일 뿐 owner가 아니다** — claim·lease·heartbeat·SessionEnd 소유권 프로토콜은 없다.
- 상세: [docs/agents/rules_workflow.md](docs/agents/rules_workflow.md), [docs/agents/operations.md](docs/agents/operations.md).

## §3. 환경 (빌드 & 툴체인)

- 저장소 고정(pinned) Nim/Lean/툴체인 버전을 사용한다(Nim 2.2.10; Lean은 elan 경유).
- 문서화된 빌드/테스트 명령을 사용한다; 제출 전 필수 로컬 검증이 통과해야 한다.
- CI/배포 상세는 [docs/agents/operations.md](docs/agents/operations.md)에 정의된다.

---

## §4. GUARDIAN

- 변경을 커밋된 제품 계약·불변식에 검증; 정본 SSOT 보존, 중복 의미 상태 금지.
- 제품 주장을 넓히지 말고 범위를 좁힌다(§0.12). 명시적 타입·명시적 상태 전이·순수 투영·정본 직렬화.
- 검증 불가/오래된 증거 = fail closed. 수직 슬라이스 범위 보존, 미래 지향 추상화 유보.
- 감사 추적 없는 게이트 우회 금지. 극장 의심 시: 뮤테이션 하니스 → 스캐너 감사 → 독립 빌드(§0.9b).

전체: [docs/agents/core_rules.md](docs/agents/core_rules.md) — AGENTS.md + core_rules.md = 단일 논리적 SSOT.

## §5. SSOT 위치

| 계층 | 내용 |
|---|---|
| AGENTS.md + docs/agents/ | 지속적 규칙, 불변식, 금지 사항 |
| docs/spec/ | 계약, Claim/Attestation/Certificate 의미, VKD 정의, CLI/exit 의미 |
| config/ | 정책, 임계값, waiver |
| data/ | 측정, baseline, 증거, 궤적 |
| docs/audit/ | 생성된 투영; 시점별 감사, 판정 |
| docs/history/ | 역사적 근거(개정 이력 = git) |
| docs/evidence/ | 실행 증거(관측·검증 기록) |

**규칙**: 측정, 역사적 결론, 생성 데이터를 AGENTS.md에 절대 배치하지 않는다. 정본 계산이 존재할 때, AGENTS.md는 그 현재 값을 중복해서는 안 된다.
