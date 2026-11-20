# nim-json-rpc error-code classification binding — Product Contract

> **레인**: `jrpc-errclass` (신규 capability lane, capConstructedGate 계열 — 구성 캐리어, v0.7.0 첫 출하)
> **채택 문서**: `config/spec/json_rpc_errcode_class.json` (SPEC-JRPC-ERRCLASS, soExplicit, hash-bound)
> **동결 계약**: `experiments/jrpc-errcode-slice-e2e/FREEZE.md` (P0) + `P1-GATE.md` (게이트 판정 기록)
> **피검험체**: status-im/nim-json-rpc @ `debf33cabf7be009a2e905d4c7921b85eb7ca6dd`, `json_rpc/errors.nim` blob sha256 `9c060ed7…7b0762`, 심볼 `new`
> **정체·명명**: 본 슬라이스의 산출물은 "Hash-bound 모델의 정형증명 + 핀된 원본 구현의 유한 입력 관찰 결속"이며 원본 구현 전체의 정형검증이 아니다 (FREEZE §1).
> **계약 버전**: **Axiom v5.1** (2026-11-18) — 정밀화 개정 A~E (A §1.1 · B §2.1 · C `obligation_semantics.md` §2.1b · D §5.1 · E §10). 이 개정은 새 판정 생산자·enum·게이트를 만들지 않으며, §1.1·§2.1·§5.1·§10이 §1~§9의 주장 범위를 명시적으로 분해한다.
> **General shape**: [adopted_model_observation_contract.md](./adopted_model_observation_contract.md) — the lane-neutral two-claim + stamped-observation contract this lane specializes.

## 1. Scope and spec identity

- **주장 범위**: `json_rpc/errors.nim::new`의 오류코드 → 클래스 분류가, 채택 매핑 테이블(8영역)과 채택된 13개 경계 인스턴스에서 일치한다.
- **스펙 근거**: JSON-RPC 2.0 Specification §5.1 — 5개 명시 코드, 서버 대역 `[-32099, -32000]`, 예약 폐구간 `[-32768, -32000]`, 잔여 공간의 application 사용. `-32000`의 이중 소속은 표의 명시 정의(Server error)가 "reserved for future use"보다 우선한다는 동결 해석으로 확정 (FREEZE §4).
- **spec identity**: `SpecID = H(sorted canonicalSpecIR | origin | ruleVersion)` — `specification_artifact.specIdentity`가 로드 시점에 재계산하며 `adoption.adoptedSpecHash`와 byte-exact 대조한다 (§2). 현재 세대: `c6ddc32e…82df`.

### 1.1 Source–model correspondence — two claims, one canonical manifest (v5.1)

본 계약의 주장은 단일 명제가 아니라 **서로 다른 두 명제**다. 두 명제는 같은 subject·claim·input set에 결속되며, 하나의 canonical manifest가 그 결속을 소유한다.

- **(i) `Model ⊨ Specification_subset`** — 채택 모델이 §4의 8영역 분류 테이블과 §1의 스펙 부분집합을 만족한다는 **모델 정합성 주장**이다. Lean 커널이 증명하는 대상은 이 명제이며, 원본 구현의 실행 의미가 아니다.
- **(ii) `∀x ∈ I13, Observe(Source, x) = Expected(Model, x)`** — 핀된 원본 `new`를 13개 입력 `I13`에서 실행한 관찰이 모델의 기대 분류와 일치한다는 **관찰 결속 주장**이다. 이는 유한 13-인스턴스 관찰이지 입력 공간 전체의 전칭 정리가 아니다.

두 주장은 동일한 `subject`(repository/commit/module/blobSha256), 동일한 `claim`(`C = P1 ∧ … ∧ P13`), 동일한 `inputSet`(`I13`의 ordinal·code)을 참조해야 하며, 하나의 canonical manifest가 이 세 결속을 원자적으로 기록한다. 어느 한 주장만으로 다른 주장을 함의하지 않는다 — `Model ⊨ Specification_subset`은 (ii)를 함의하지 않고, (ii)의 13/13 일치는 (i)를 함의하지 않는다.

**Hash identity ≠ model correctness ≠ theorem truth.** `adoptedSpecHash`·`blobSha256`·`SpecID`의 byte-exact 일치는 **콘텐츠 동일성**만 말한다. 그것은 (a) 그 콘텐츠가 스펙 부분집합을 만족한다는 것도, (b) 모델이 핀된 원본과 대응한다는 것도, (c) Lean 정리가 참이라는 것도 아니다. (a)는 (i)의 증명 대상이고, (b)는 (ii)의 관찰 대상이며, (c)는 theorem identity·Lean source hash·toolchain·transitive axiom set의 커널 수용으로만 성립한다. 해시가 일치해도 세 명제는 각각 거짓일 수 있다.

canonical manifest의 최소 필드: `subject{repository, commit, module, blobSha256}`, `claim{specId, adoptedSpecHash, conjunction = P1 ∧ … ∧ P13}`, `inputSet{I13: ordinal → code}`, `model{modelDigest, theoremIdentity}`, `observations{ordinal → (expected, observed, replayVerdict)}`. **스키마 식별자·저장 경로(확정)**: `schemaId = "axiom.jrpc_errcode.manifest.v1"`, path = `$AXIOM_STATE_DIR/evidence/jrpc_errcode_manifest.json`. 직렬화는 canonical JSON(정렬된 키, 고정 구분자)이며 `manifestDigest = sha256(canonical bytes)`를 proof state와 campaign evidence에 기록한다. 이 계약은 필드 결속을 규정하며, 스키마 이름을 발명하지 않는다.

## 2. Hash-bound adoption (2단 로더)

`validateJrpcErrclassOverlayNode` — sidecar 계약 §2와 동일 형상:

- **Stage (i)**: `explicitSpecFromOverlay` 권위 핀(soExplicit) + description/semanticCaveats/nonClaims 형상 + 채택 레코드 전 필드(64-hex 해시·40-hex commit·문법 버전 핀) + 매핑 형상(정확히 8항, 태그 0..7 전부·유일, 클래스 == 폐쇄 codomain 집합, remainder 정확히 1, base 클래스 정확히 1) + 인스턴스 형상(≥1, 코드 중복 없음, expectedClass ∈ codomain) + 파생 pre/post 문구의 폐쇄 문법 파싱 + `canonicalSpecIR` == 재계산 절 목록.
- **Stage (ii)**: 로드된 명제 내용에서 재계산한 SpecID와 `adoption.adoptedSpecHash`의 byte-exact 대조. 채택 이후 어떤 절·ruleId·ruleVersion 변경도 기계적으로 채택을 무효화한다.
- **모델↔인스턴스 일치성은 deliberately NOT 검증** — 변이 문서가 로드되어야 재생 반증이 성립한다 (FREEZE §10). 관찰이, 로더가 아니다.

### 2.1 Adoption authority — approval is not hash identity (v5.1)

- **승인 권한**: 모델·명제 채택의 승인자는 **Axiom 인간 아키텍트(저장소 소유자)**다. 에이전트·CI·PR head·해시 일치는 채택 권한이 아니다. 모델 채택 레코드의 `adopter` 필드(현재 `axiom (workstream/jrpc-errcode-map P2 slice, user-approved mission)`)는 이 승인 행위의 기록이며, 승인자의 지위를 해시나 자동화가 대체할 수 없다.
- **Hash pinning ≠ adoption legitimacy**: `adoptedSpecHash`/`SpecID`의 byte-exact 일치는 채택된 콘텐츠와 현재 콘텐츠가 같다는 것만 증명한다. 채택의 정당성은 (i) 인간 승인자, (ii) 승인 근거(`basis`), (iii) 승인 시점(`adoptedAt`)이 기록된 **채택 행위**에서 나온다. 해시가 맞아도 승인 기록이 없으면 채택은 없고, 승인 기록이 있어도 해시가 어긋나면 그 채택은 현재 콘텐츠를 결속하지 못한다.
- **PR head 금지**: PR head가 adoption 레코드나 해시를 바꾸는 경로는 채택이 아니다 — 채택은 보호된 ref에 커밋된 레코드로만 성립한다.

**채택 레코드 — `PR_ADMISSION_CONTRACT.md` v1.1.0 (Axiom v5.1)**

| 항목 | 값 |
|---|---|
| 문서 (SSOT) | `Archright/.github` `.github/axiom-admission/PR_ADMISSION_CONTRACT.md` |
| 대상 | `Archright/nim-libp2p` PR admission (캠페인 계약 아님) |
| 버전·일자 | v1.1.0 (2026-11-14) |
| commit | `a6fd6cbe8e8328160cac961a59cc37af828c2c92` |
| 문서 sha256 | `a3ad1b342d69c81bc5b40beadfb15e455264ce5f658c2fc403a232d346f5efbd` |
| 승인자 | Axiom 인간 아키텍트(저장소 소유자); 커밋 기록 `wintrover` (2026-11-14) |
| 채택 범위 | **PR admission 전용** — `external_verification_campaign_contract.md`와 별개 |
| 구분 | PR admission은 PR 단위 7 불변식+판정 매핑이고, 캠페인 계약은 캠페인 5가드+11클래스다. 두 문서는 서로를 대체·개정하지 않으며, 인용 시 혼용하지 않는다. |

## 3. The closed grammar — `nim-jrpc-errclass-v1`

sidecar의 `nim-sidecar-expr-v1` 계열 복제 + **음수 리터럴** (오류코드가 전부 음수 — v1과의 유일한 확장, FREEZE §7):

```
expr     := equality
equality := additive ( "==" additive )?
additive := primary ( "+" primary )*
primary  := ident | INT | "(" additive ")"
ident    := "result" | "code"
INT      := [0-9]+ | "-" [0-9]+
```

폐쇄: 다른 연산자·호출·타입 토큰·문자열 전부 명시적 거부. INT는 2^63 크기 상한으로 오버플로 검사 (음수 arm은 int64.low까지, 양수 arm은 int64.high까지 — 감싸기 없음). 기존 `nim-sidecar-expr-v1` 파서는 바이트 불변.

## 4. Classification-function contract (FREEZE §5)

채택 매핑 `classify: int → ClassTag`는 **우선순위 테이블**이다 — 태그 순 first-match (소스의 `case`→`else` 체인, errors.nim:105-122):

1. **전함수 (total)** — remainder가 잔여 전부를 포착 (irIf 사슬의 최종 else).
2. **결정적 (deterministic)** — 동일 code → 동일 태그.
3. **유효 배타 (effectively exclusive)** — 태그 우선순위를 적용한 *유효* 입력 영역은 서로 겹치지 않는다. 원시 영역의 집합론적 중복(5개 싱글턴이 예약 대역 [-32768,-32100] 안에 있음)은 case-우선순위의 정직한 인코딩이며 로드 게이트에서 기각 대상이 아니다(FREEZE §7은 형상+codomain만 핀). 우선순위 오배치는 검증 기계 자체가 잡는다(SAT + 재생).
4. **완전 분할 (exhaustive)** — 유효 영역 8개의 합집합이 입력 공간 전체.
5. **태그 인코딩은 구별적** — 태그값 0..7 상호 distinct. 함수 전체는 단사가 아니다 (-32099..-32000 전부 태그 5) — 본 계약의 대상은 분류로서의 완전성·배타성이지 단사성이 아니다.

| 태그 | 클래스 | 입력 영역 (원시) |
|---|---|---|
| 0..4 | RpcParseError / RpcInvalidRequestError / RpcMethodNotFoundError / RpcInvalidParamsError / RpcInternalError | {-32700} / {-32600} / {-32601} / {-32602} / {-32603} |
| 5 | RpcServerError | [-32099, -32000] |
| 6 | RpcResponseError (제네릭 베이스) | [-32768, -32100] — 싱글턴 5개를 포함하나 태그 우선순위로 양보 |
| 7 | RpcApplicationError | remainder (int ＼ 위 전부) |

**codomain 폐쇄 (엔진 상수)**: 8개 구체 클래스명. codomain 밖(조상 `JsonRpcError`/`CatchableError`, deprecated alias, `new`가 생성 불가한 타입)은 로드 즉시 거부. base 클래스 = `RpcResponseError` (§6의 of-매트릭스 베이스 판별자이자 하니스 콜 폼 `RpcResponseError.new(<lit>, "m")`의 생성 타입).

## 5. Synthesis contract (D1–D4) — 13캐리어, 인스턴스별 obligation

- **D1 로드**: `loadJrpcErrclassOverlayDomain` (runtimeSpecOverlayPath 경유) / 레지스트리 디스패치는 어댑터 validate leg가 entry.raw에서 순수 검증.
- **D2 캐리어**: 인스턴스별 13개 (`new_errclass_defect` — 문서 순서 1번, wave-facing, entry.name=검사 심볼로 rename / `new_errclass_control_02`…`_13` — 자기 이름). 각 캐리어: body = 채택 매핑의 **irIf 사슬(구성 IR)**, params = `code: BitVec64` 단일, pre = `code == <c>` (파싱된 인스턴스 pre), post = `result == <tag>`를 모델에 β-splice (정확히 1회, fail-closed). `expectedObligation = true` — 파생 obligation 0개는 scope mismatch로 기각된다.
- **D3 측정**: `measureClaimCarrierParseBoundComponents(moduleBytes, "new", "jrpc-errclass-model-v1|rule=<ruleId>|inst=<n>)")` + `replayHarnessTemplate` = 스탬프된 하니스. 완전성 비트는 전부 true/lossOutside=false (근거: 구성된 IR — 추출이 아니므로 번역 손실이 없다).
- **D4 멤버십**: `modulePath == adoption.subject.module ∧ (fnName == "new" ∨ fnName ∈ 캐리어명 집합)`. 라우팅: canonical `module::fn` (d2 형상).

왜 13캐리어인가: `extractObligationCandidates`는 post마다 별도 obligation을 생성하고, 재생 post 도출(`d2AgentReplayPostcondition`)은 post 1개·`<body> == <리터럴>` 형상만 수용한다 — 인스턴스별 캐리어만이 기존 기계 무수정으로 변이 시나리오(§8)를 성립시킨다.

### 5.1 D3 — governed claim conjunction and verdict semantics (v5.1)

> 명명 주의: 이 절의 "D3"는 v5.1 개정 항목 이름이며, §5의 D3 측정 단계와 구분한다.

**Governed claim**: `C = P1 ∧ … ∧ P13`. 각 `Pi`는 `I13`의 ordinal `i`에 대응하는 INSTANCE obligation이며, 모든 `Pi`는 동일한 핀된 subject와 동일한 입력 `xi`를 참조한다. `C`는 입력 공간 전체의 전칭 정리가 아니라 13개 핀 인스턴스 주장의 논리곱이다.

**Verdict rule (전사·상호배타)**:

| 조건 | `claimOutcome` |
|---|---|
| 13개 `Pi` 전부 증명됨 (각 `Pi`의 solver proof status = `psUnsat` → `clProved`) | `clProved` |
| 적어도 하나의 `Pi`에 **유효한 반례**가 존재함 — 동일 subject·동일 입력 `xi`·quartet 완비·재생 동의 `rvAgree`·구체적 property 위반 | `clDisproved` |
| 위 어느 것도 성립하지 않음 | `UNKNOWN` |

`clProved`는 **all-13** 요건이고, `clDisproved`는 **at-least-one** 요건이며, `UNKNOWN`은 나머지 전부의 fail-closed 귀결이다. 12개 증명 + 1개 미결은 `clProved`가 아니며, 반례 1개는 나머지 12개가 증명되었더라도 `clDisproved`다. 여기서 `clProved`는 governed claim `C`의 claim-level 판정이다 — 각 `Pi`의 solver proof status가 `psUnsat`(→ `clProved`)인 13개가 전부 모여야 한다. `clProved` 자체는 theorem truth가 아니며, 긍정 `NO_BUG_PROVED`에는 별도로 VDA receipt 9-field 확인(`vdVerified`)이 필요하다 (C; `obligation_semantics.md` §2.1b).

**Quartet — 네 필드의 정확한 정의** (`bug_verdict_glossary.md` §2.2 공용 4요소와 동일 정의):

1. **subject** — 정확한 subject commit + 대상 모듈 blob sha256 (+ 해당되는 경우 tree merkle root).
2. **input** — 반례를 재현하는 정확한 입력 `xi`(instance ordinal + code). 클래스·범위·대표값은 입력이 아니다.
3. **violation** — 위반된 conjunct `Pi`와 그 predicate/domain.
4. **replay** — 관측 출력 + 재생 명령 + toolchain/host 폴드 + `replayVerdict`.

네 필드는 **동일 subject·동일 input**을 참조해야 하며, replay는 `rvAgree`여야 한다. 서로 다른 subject/input에서 조립된 quartet, `rvDisagree`/`rvUnavailable` quartet, 필드 결측 quartet은 유효한 반례가 아니다.

**Manifest binding**: 모든 `Pi`와 모든 quartet 레코드는 §1.1의 동일 canonical manifest에 `adoptedSpecHash`, `instanceOrdinal`(1..13), `derivationRule`(`jrpc-errclass-model-v1|rule=<ruleId>|inst=<n>`), `carrierIdentity`(`new_errclass_defect` 또는 `new_errclass_control_NN`)를 결속해야 한다. 결속이 결측된 `Pi`는 `clProved`에도 `clDisproved`에도 기여할 수 없다.

**단일 신호 승격 금지**: `psFail` 단독은 승격하지 않는다 — 그것은 solver-level proof 실패 표시이며, replay-agreed quartet 없이는 claim-level 반례로 승격되지 않는다. `rvDisagree` 단독도 승격하지 않는다 — 재생이 모델과 모순된다는 뜻이므로 fail-closed로 `UNKNOWN`/inconclusive로 강등된다. solver SAT 단독, exit code 단독, 관찰 불일치 단독도 승격하지 않는다. `clDisproved`는 오직 replay-agreed 반례 quartet으로만, `clProved`는 오직 13개 전부의 claim-level proof로만 성립하며, `vdVerified`는 오직 VDA receipt 9-field 확인으로만 성립한다.

**DEBT#529/#530 closure ordering**: 두 부채의 폐쇄는 **Phase 4 증거 이후**로 이동한다. 본 개정은 어느 쪽도 폐쇄하지 않으며, P4 증거가 존재하기 전에 폐쇄를 기록하는 PR·문서·주장은 이 계약 위반이다.

## 6. of-observation — method A (FREEZE §8, 동결)

하니스(폐쇄 템플릿 레지스트리 `errors-class-v1`, 엔진 소유):

```nim
import json_rpc/errors
let r = RpcResponseError.new(<lit>, "m")
var leafCount = 0
var observed = -1
<tags>            # 채택 매핑에서 스탬프 (단일근원)
echo "AXIOM_REPLAY_BEGIN"
echo $observed
echo "AXIOM_REPLAY_END"
```

`<tags>` 블록: 리프 7개(태그 순, base 제외)의 `if r of <Class>: inc leafCount; observed = <tag>` + 베이스 판별 + fail-closed 검사. 관찰 불변식: **베이스 참 = 1 ∧ 리프 참 ≤ 1** — "8개 중 정확히 1개 참"은 잘못된 불변식(베이스가 조상이라 리프 분기에서 2개 참). 관찰 클래스 = 유일 참 리프, 또는 리프 0 ∧ 베이스 참 → 베이스 태그. 관찰값은 **int 태그**(0..7)를 마커 사이에 echo — 기존 `parseConcreteLiteral`·`decideReplayAgreement`의 int 채널을 그대로 재사용한다. expected는 post로 주입된다(템플릿 하드코딩 금지).

**fail-closed 5조건**:

| # | 조건 | 처리 |
|---|---|---|
| ① | 베이스 판별 거짓 (nil 포함) | 정적 폴딩 CondTrue(`new`의 반환 정적 타입 = `ref RpcResponseError`) — 도메인 사전조건 (P1-GATE 기록; "기대 단일 판별" 설계는 기각된 선례) |
| ② | 리프 참 ≥ 2 (외부 서브클래싱·하니스 결함) | `quit 1` → 비정상 exit → rvUnavailable |
| ③ | 리프 0 ∧ 베이스 거짓 | ①과 동일 경로 (폴딩); 리프 0 ∧ 베이스 참은 정상 — observed = 베이스 태그 |
| ④ | observed ≠ expected | post 위반 → **rvAgree → PROPOSITION_DISPROVED** (UNKNOWN 아님) |
| ⑤ | expected가 codomain 밖 | 로드 단계 즉시 거부 |

**합성 후 스탬프 검증 (fail-closed)**: `<tags>`·`<module>` 잔존 없음 + `<lit>` 정확히 1회.

## 7. Replay expectations

- SAT(모델 위반) → P4 → 재생: 모델 바인딩 code → `<lit>`에 십진 int64 리터럴 렌더 (BV64 hex는 int64로 bit-exact 변환) → 하니스 관찰 → post `result == <expected tag>`의 콘크리트 평가. 일치 → rvAgree (PROPOSITION_DISPROVED), 불일치 → cvUnresolved.
- 의존성 고정: 하니스의 `import json_rpc/errors` closure는 `AXIOM_REPLAY_DEP_PATHS`(콜론 구분 — nim-serialization 5종 핀) env override 우선 해석 (FREEZE §12.1).
- 정직 문서(현재 세대)에서 13 obligation은 전부 UNSAT — 재생이 발화하지 않는 것이 정상 (bytesview v1.1.0 law-conformance 전례).

## 8. Negative control — mutation test (FREEZE §10)

**거짓 채택 파일**(독립 adoption 해시): 인스턴스 4번(-32600)의 기대를 태그 0으로 왜곡. 기대 거동: 매핑(모델)은 정직하므로 obligation `code == -32600 → 모델 == 0`이 SAT(모델은 1을 산출) → 재생 관찰 1 ≠ expected 0 → 조건 ④ → `vrFail ∧ clDisproved ∧ icCounterexample` 반증 경로 + 원본 코드 재생. 단위 스위트가 이 시나리오를 재현한다. 이 대조는 검출 경로의 가동 증명이지 일반 검출 증명이 아니다.

## 9. Non-claims

- 필드 값·msg·data 내용 무주장 (obj-constr·필드 의미론이 인증 subset 밖 — Axiom #119).
- 13 핀 인스턴스 밖의 입력 공간 무주장 (INSTANCE obligations).
- 피검험체 바디 추출·번역·검증 무주장 (구성 IR; 원본 연결은 재생 관찰이 유일).
- Zero-Footprint — nim-json-rpc 무수정.
- JSON-RPC 2.0 본문의 재유도가 아님 — 스펙 근거는 §5.1 원문 인용, 채택은 명시적 hash-bound 행위.
- 내부 클래스명 선택·미정의 예약 코드→제네릭 매핑은 구현 선택 (스펙 규범으로 귀속시키지 않는다).
- 긍정 판정은 Lean 커널 수용만; 새 판정 생산자 없음 (기존 VDA·판정 구조 불변).

## 10. Release order and re-freeze scope (v5.1)

허용되는 출하 순서는 하나뿐이다:

```
PR → MERGE → P4 re-verification on canonical main → P6 → P7 acceptance → v0.7.0 publish
```

- **P4 re-verification은 MERGE 이후 canonical main에서 수행한다.** PR head의 green은 출하 게이트가 아니며, PR head에서 생성된 증거를 publish 근거로 재사용하지 않는다.
- P6(워크플로/어드미션)과 P7(acceptance 재생)은 post-merge 증거를 소비한다. **v0.7.0 publish는 P7 acceptance 이후에만** 수행한다.
- **재동결(re-freeze) 범위**: FREEZE는 변경된 입력의 **의존성 폐포(dependency-reachable set)에 도달하는 항목만** 재생성한다. 폐포 밖의 기존 항목은 재계산·재기록하지 않는다. 반대로, 변경된 입력에 도달 가능한 항목의 재생성은 생략할 수 없다 — 이는 면제가 아니다.
