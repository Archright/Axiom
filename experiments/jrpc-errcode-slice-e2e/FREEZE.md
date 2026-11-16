# FREEZE — jrpc-errcode Vertical Slice Soundness Contract (P0)

> **상태**: P0 동결 — 본 문서는 엔진 코드 작성 전에 동결된 제품 계약이다 (AGENTS.md §0.12).
> **변경 규칙**: 동결 후 개정은 재동결(re-freeze) 요구 — 수정 시 본 문서의 해시·채택 레코드 전부 재계산되어야 하며, 게이트 불일치는 fail-closed된다.
> **작성 근거**: JSON-RPC 2.0 Specification §5.1 (jsonrpc.org/specification, Updated 2013-01-04, 직접 fetch — 1차 소스 단일 인용으로 기록), status-im/nim-json-rpc 원문, Axiom bytesview/sidecar/d2 계약 3종.
> **관련 이슈**: Archright/Axiom #118 (fail-open 갭 bug), #119 (인증 subset 한계 공식화 — 본 슬라이스가 그 한계의 현실적 사례).

---

## 1. 정체·명명

본 슬라이스의 산출물은 **"Hash-bound 모델의 정형증명 + 핀된 원본 구현의 유한 입력 관찰 결속"**이며, 원본 구현 전체의 정형검증이 아니다. 이 명명은 강등이 아니라 구분이다: 무엇을 증명했고(채택 모델의 Lean 커널 증명), 무엇을 관찰했고(핀된 13개 입력에서의 원본 `new` 실행), 무엇을 증명하지 못했는지(§9 non-claims)가 기계적으로 구분된다.

## 2. 인증 형상 (bytesview 계약 정렬)

피검험체 바디는 IR로 번역하지 않는다 (구조적으로 불가능 — template `err` :95, obj-constr+`move` :96, `case` :105, `in`-범위 :117/:119 가 전부 인증 subset 밖; 근거는 Axiom #118·#119). 대신:

- **채택 모델**(constructed IR — 채택 파일의 매핑에서 구성, 피검험체 심볼을 materialize하지 않음)의 denotation을 핀된 Lean 커널이 증명
- **원본 연결**은 스탬프 재생 하니스의 관찰이 유일 (bytesview 계약 §3: "the solver verifies the ADOPTED MODEL, not the subject")
- 피검험체 바디의 materialize 시도는 `moUnsupportedDeclKind`/loss로 **정직 보고** — 숨기지 않음

인증 체인의 정확한 주장 범위는 certification_continuity_contract.md §2와 동렬이다: 핀된 Nim 프론트엔드(Qualified TCB)·선언된 subset·hash-bound 채택·핀된 Lean 커널. **Nim 프론트엔드 정확성·채택 의도 충실성·subset 외 의미론·필드 값·입력 공간 전체·바디 의미 추출을 주장하지 않는다.**

## 3. 피검험체 핀 (전체 해시)

| 항목 | 값 |
|---|---|
| 저장소 | status-im/nim-json-rpc |
| commit (40-hex) | `debf33cabf7be009a2e905d4c7921b85eb7ca6dd` |
| commit tree (40-hex) | `d6d3209ede4d1d1ecce90005ff8d5b2eb9b46da4` |
| 대상 모듈 | `json_rpc/errors.nim` |
| blob (git sha1) | `b37707fd85810625303a0d0e896c4d1524d792ff` |
| blob sha256 (파일 내용) | `9c060ed7df574956dc0c8f05cf0e1c33db418b659a3a6e75aade7cbb557b0762` |
| 검증 심볼 | `new` (`proc new*(T: type RpcResponseError, …)` — errors.nim:88) |
| 툴체인 | Nim 2.2.10 (재생 하니스와 동일 버전 — Axiom 핀과 동일) |

Zero-Footprint: 원본 tree는 무수정. 무결성 검증은 **원본 subject blob·tree 불변 + 허용 파일(본 채택 파일)만 존재**로 정의한다 (전체 저장소 tree 일치는 요구하지 않는다 — 채택 파일 추가로 전체 tree가 달라지는 것은 정상).

## 4. 스펙 근거 — JSON-RPC 2.0 §5.1 (원문 인용)

> "The error codes **from and including -32768 to -32000** are reserved for pre-defined errors. Any code within this range, but not defined explicitly below is reserved for future use."

| code | message | meaning (원문) |
|---|---|---|
| -32700 | Parse error | Invalid JSON was received by the server… |
| -32600 | Invalid Request | The JSON sent is not a valid Request object. |
| -32601 | Method not found | The method does not exist / is not available. |
| -32602 | Invalid params | Invalid method parameter(s). |
| -32603 | Internal error | Internal JSON-RPC error. |
| -32000 to -32099 | Server error | Reserved for implementation-defined server-errors. |

> "The remainder of the space is available for application defined errors."

**경계 해석 (동결)**: 예약 폐구간 [-32768, -32000]. **-32000은 양쪽에 언급되나 표의 명시 정의(Server error)가 "reserved for future use"보다 우선하므로 Server로 확정**. 서버 대역 [-32099, -32000] 양단 포함. 이 해석이 구현 분기와 일치함은 §5·§6 대조로 확증된다.

**규정의 구분**: §5.1이 규정하는 것 — 5개 코드의 이름·의미, 서버 대역의 존재·용도, 예약 폐구간, 잔여 공간의 application 사용. §5.1이 규정하지 않는 것 — 내부 클래스명 8종, 클래스 계층, origin/data/msg 필드. 따라서 채택 명제는 "§5.1이 정의한 오류코드 의미·예약 범위와 nim-json-rpc의 **내부 클래스 분류**가 일치한다"이며, 내부 클래스명 자체는 라이브러리·채택자의 구현 선택이다.

## 5. 분류 함수 계약 (채택 대상)

errors.nim:105-122의 실제 분기 (라인 인용):

```nim
105  case code
106  of JSON_PARSE_ERROR:      err(RpcParseError)          # -32700
108  of INVALID_REQUEST:       err(RpcInvalidRequestError) # -32600
110  of METHOD_NOT_FOUND:      err(RpcMethodNotFoundError) # -32601
112  of INVALID_PARAMS:        err(RpcInvalidParamsError)  # -32602
114  of INTERNAL_ERROR:        err(RpcInternalError)       # -32603
116  else:
117    if code in -32768 ..< -32099:  err(RpcResponseError)  # [-32768, -32100] 제네릭 베이스
119    elif code in -32099 .. -32000: err(RpcServerError)    # [-32099, -32000]
121    else:                        err(RpcApplicationError) # 잔여 전부
```

**계약 (동결)**: 채택 매핑 `classify: int → ClassTag`는

1. **전함수 (total)** — 모든 int가 정확히 하나의 태그로 분류된다 (사상이 전사; 소스의 else-체인이 이를 구조적으로 보장).
2. **결정적 (deterministic)** — 동일 code → 동일 태그.
3. **상호배타 (mutually exclusive)** — 각 클래스의 입력 영역은 서로 겹치지 않는다 (분기 조건이 겹침 없음: 117행은 -32099 배타, 119행은 -32099 포함 → 중복·공백 없음).
4. **완전 분할 (exhaustive)** — 입력 공간을 8개 영역의 합집합으로 빈틈없이 나눈다.
5. **태그 인코딩은 구별적 (distinct)** — 태그값 0..7은 서로 다르다. **함수 전체는 단사가 아니다** (-32000..-32099가 전부 Server) — 본 계약이 다루는 것은 분류로서의 완전성·배타성이지 단사성이 아니다.

**태그 배정 (동결)**:

| 태그 | 클래스 (구체 생성 타입) | 입력 영역 |
|---|---|---|
| 0 | RpcParseError | {-32700} |
| 1 | RpcInvalidRequestError | {-32600} |
| 2 | RpcMethodNotFoundError | {-32601} |
| 3 | RpcInvalidParamsError | {-32602} |
| 4 | RpcInternalError | {-32603} |
| 5 | RpcServerError | [-32099, -32000] |
| 6 | RpcResponseError (제네릭) | [-32768, -32100] |
| 7 | RpcApplicationError | int ＼ (위 전부) |

영역의 스펙 대응: 태그 0-4 = §5.1 표의 5 코드; 태그 5 = 서버 대역; 태그 6 = "reserved for future use" (미정의 예약 코드를 제네릭 베이스에 매핑하는 것은 **구현 선택**이며 스펙 규범이 아님 — 스펙은 해당 코드의 future-use 상태만 규정); 태그 7 = "remainder of the space".

## 6. 인스턴스 obligation 목록 (경계값 13개 — 동결)

| # | code | 기대 태그 | 스펙 근거 | 소스 분기 (§5 대조) |
|---|---|---|---|---|
| 1 | -32769 | 7 | 예약 밖 하방 → application | 121 ✅ |
| 2 | -32768 | 6 | 예약 폐구간 하단 (미정의) | 117 ✅ |
| 3 | -32700 | 0 | Parse error | 106 ✅ |
| 4 | -32600 | 1 | Invalid Request | 108 ✅ |
| 5 | -32601 | 2 | Method not found | 110 ✅ |
| 6 | -32602 | 3 | Invalid params | 112 ✅ |
| 7 | -32603 | 4 | Internal error | 114 ✅ |
| 8 | -32100 | 6 | 예약 내·미정의 (Server **아님** — 서버 대역 경계 밖) | 117 ✅ |
| 9 | -32099 | 5 | 서버 대역 하단 (경계 쌍의 일부) | 119 ✅ |
| 10 | -32000 | 5 | 서버 대역 상단 (표 명시 정의 — 이중 경계) | 119 ✅ |
| 11 | -31999 | 7 | 예약 밖 상방 → application | 121 ✅ |
| 12 | 0 | 7 | application 공간 | 121 ✅ |
| 13 | 1 | 7 | application 공간 (양수 경계) | 121 ✅ |

핵심 증거값: **-32100/-32099 쌍** (제네릭↔서버 경계 전환), **-32000** (스펙 이중 경계 — 표 우선 해석의 구현 확증), **-32768/-32769** (예약 하단·밖), **-31999** (상단 밖). 13개 인스턴스 전부 스펙 기대와 소스 분기가 일치함을 에이전트 대조로 확증했다 (불일치 발견: 없음).

각 인스턴스는 **INSTANCE obligation**이다 (sidecar 계약 §7 전례): "이 핀된 입력에서 classify(code) == 기대 태그" — universal theorem이 아니다.

## 7. 단일 근원 채택 파일 (동결)

**하나의 hash-bound 채택 파일이 모델·obligation·하니스 expected 관찰의 공통 근원**이다. 하니스에 기대값을 하드코딩하는 것·모델과 관찰이 별도 명세를 쓰는 것은 금지한다 — 우연 일치 후 편향 검출 불능(사용자 지적 #4)이 되기 때문이다.

- **형식**: sidecar 계약 §2의 hash-bound 채택 구조 (2단 로더: Stage (i) 형상+문법, Stage (ii) SpecID byte-exact 재계산 대조) + subject 핀 {source, module, symbol, commit(40-hex), blobSha256} + adoption 레코드 {adoptedSpecHash, adopter, adoptedAt, basis, grammarVersion, provenance}.
- **폐쇄 문법 `nim-jrpc-errclass-v1` (신규 버전 핀)**: sidecar의 `nim-sidecar-expr-v1` 계열이나 **음수 리터럴 포함** (오류코드가 전부 음수이기 때문 — 기존 문법의 NON_NEG_INT만으로는 인스턴스 지정이 불가능하다):
  ```
  expr     := equality
  equality := additive ( "==" additive )?
  additive := primary ( "+" primary )*
  primary  := ident | INT | "(" additive ")"
  ident    := "result" | "code"
  INT      := [0-9]+ | "-" [0-9]+        # 음수 허용 — v1과의 유일한 확장
  ```
  폐쇄: 다른 연산자·호출·타입 토큰·문자열 전부 거부. **새 문법은 새 엔진 버전** — 본 슬라이스의 v0.7.0 출하와 정합.
- **문서 내용**: 매핑 테이블(§5의 8영역), 인스턴스 목록(§6의 13쌍 (code, expected_class)), pre/post 문구 — pre: `code == <인스턴스 code>`, post: `result == <태그>`.
- **문법 밖 입력은 반드시 거부** — 별도 문자열 해석·추측 복구 금지 (fail-closed).
- **expected_class 스키마 검증**: 8개 구체 codomain {RpcParseError, RpcInvalidRequestError, RpcMethodNotFoundError, RpcInvalidParamsError, RpcInternalError, RpcServerError, RpcResponseError, RpcApplicationError} 밖이면 로드 단계 즉시 실패 (조상 `JsonRpcError`/`CatchableError`, deprecated `ApplicationError`/`InvalidRequest`, `new`가 생성 불가한 타입 전부 거부).

## 8. 관찰 채널 (of-매트릭스 — 방식 A, 동결)

**Nim `of` 의미 (Nim 2.2.10 공식 문서 확증)**: `x of T`는 x의 동적 타입이 T **또는 T의 하위타입**이면 참 (system.nim:850, manual §Objects: "similar to `instanceof` in Java"). 실패 시 false (무예외·noSideEffect). nil ref는 안전하게 false. 무관 타입과의 `of`는 컴파일 거부.

**타입 계층 (errors.nim 라인 인용)**: `CatchableError → JsonRpcError(:15) → RpcResponseError(:57, new의 반환 타입·분류의 조상) →` 리프 7종 (RpcParseError :63, RpcInvalidRequestError :65, RpcMethodNotFoundError :67, RpcInvalidParamsError :69, RpcInternalError :71, RpcServerError :73, RpcApplicationError :75).

**판별 매트릭스 (동결)**: 판별자는 **8종 = 리프 7 + 베이스 1(RpcResponseError)**. 하니스는 채택 파일이 지정한 각 인스턴스 code에 대해:

1. `r = new(RpcResponseError, code, …)` 실행 (원본 모듈 심볼 — 스탬프 재생, 하니스는 분류 기대를 갖지 않는다)
2. 8개 판별 전부 실행: `r of <판별자>` × 8
3. **수정 불변식** (관찰의 완전성·배타성): `베이스 참 = 1 ∧ 리프 참 ≤ 1` — 관찰 클래스 = 유일 참 리프; 또는 (리프 참 0 ∧ 베이스 참) = RpcResponseError
   - 주의: "8개 중 정확히 1개 참"은 **잘못된 불변식**이다 — 8개 중 1개(베이스)가 나머지 7개의 조상이라 리프 분기에서 항상 2개가 참한다.
4. observed_class ↔ 채택 파일의 expected_class 비교

**fail-closed 조건 (5종 — 어느 하나 위반 시 해당 인스턴스 관찰 = UNKNOWN/실패)**: ① 베이스 판별 거짓 (nil ref 포함), ② 리프 참 2개 이상 (모호 — 이 계층에선 불가능, 관찰되면 하니스 결함·외부 서브클래싱), ③ 리프 참 0 ∧ 베이스 거짓, ④ observed ≠ expected, ⑤ expected가 codomain 밖.

**기각한 설계 (동결 기록)**: "기대 단일 판별" 방식은 기각 — 기대가 조상이면 하위타입 매칭으로 무조건 참(거짓 양성)이고, 특히 베이스 기대는 `new`의 반환 정적 타입이 이미 `ref RpcResponseError`이므로 **컴파일러가 CondTrue로 폴딩 — 런타임 관찰이 성립하지 않는다**. 베이스 판별의 유효 역할은 도메인 사전조건 + "정확히 베이스" 식별의 보조뿐이다.

## 9. Non-claims (동결)

- 태그 투영이 클래스 외 속성 (필드 값·msg·data 내용) 에 대해 아무것도 주장하지 않는다 — obj-constr·필드 의미론이 인증 subset에 없어 (Axiom #119) 필드 보존은 증명 대상이 아니다.
- 관찰 결속은 **핀된 13개 인스턴스에서만** — 입력 공간 전체의 정리가 아니다 (INSTANCE obligations).
- 피검험체 바디·템플릿의 추출·검증을 주장하지 않는다 (bytesview §7 :153 철자).
- 미정의 예약 코드 → 제네릭 매핑(태그 6)은 구현 선택이며 스펙 규범으로 귀속시키지 않는다.
- 채택 명제의 스펙-의도 충실성·내부 클래스명 선택은 채택자(사람)의 책임이다 (adoption = authority, content ≠ authority).
- Nim 2.2.10 프론트엔드는 Qualified TCB (미검증). Z3는 최대 후보 보조 — 긍정 판정은 Lean 커널 수용만.
- 음성 대조(§10)는 **특정 mutation test**다 — "모든 잘못된 채택을 검출한다"는 일반 증명이 아니다.
- 리프 서브클래싱 부재는 이 저장소 수준의 사실이다 — fail-closed 조건 ②가 그 위반을 런타임에 잡는 안전망이다.

## 10. 음성 대조 (mutation test — 동결)

**거짓 채택 파일** (독립 파일·독립 adoption 해시): 인스턴스 4번의 매핑을 **-32600 → 태그 0 (RpcParseError)**로 왜곡. 기대 거동: 모델은 채택 매핑을 따르므로 Lean 증명은 그 자체로 성립할 수 있으나(모델은 자기 일관적), **재생 관찰이 원본 `new(-32600)` = RpcInvalidRequestError(태그 1)를 산출** → observed(1) ≠ expected(0) → fail-closed 조건 ④ → 반증 경로 `vrFail ∧ clDisproved ∧ icCounterexample` (quartet 관찰) + 원본 코드 재생.

**이 대조가 증명하는 것**: 이 특정 거짓 매핑이 이 입력에서 관찰 불일치를 일으키고, 시스템이 그 불일치를 검출·반증 경로로 전환한다는 것. **검출 경로의 가동 증명(mutation test)이지 일반 검출 증명이 아니다.**

## 11. 판정 논리·권한 (동결 — 기존 권한 불변)

- **긍정**: `vrPass ∧ vdVerified ∧ clProved` = `NO_BUG_PROVED(P,D)` (bug_verdict_glossary §2.1). vdVerified는 VDA(`verification_decision_authority`)에서만 생성 — 본 슬라이스는 **새 판정 생산자를 만들지 않는다**. `propositionVerdict = NOT_DISPROVED`는 디스플레이 층의 순수 투영이다 (DEBT#531 폐쇄).
- **부정**: `vrFail ∧ clDisproved ∧ icCounterexample` (quartet) = DISPROVED. quartetComplete는 부정 전용 요건이다 — 긍정 요건이 아니다.
- **그 밖의 전부**: UNKNOWN (fail-closed). Z3-만 통과는 긍정으로 승격하지 않는다.

## 12. 결정론 통제 (6항 — 동결)

1. Nim 2.2.10·Lean(elan 핀)·Axiom bundle·의존성(nim-serialization 등 5종)의 정확한 버전·해시 고정 (replay-dep-pins 40-hex).
2. 타깃 아키텍처·컴파일 설정 고정 (하니스·모델·커널 동일 조건).
3. 하니스에 전달되는 입력·typedesc 값의 정확한 고정 (채택 파일의 13쌍 — 하니스는 다른 소스를 읽지 않는다).
4. 시간·임의성·파일 탐색 순서·환경값 영향 제거·통제.
5. A/B 콜드 잡 간 캐시·상태 저장소 분리 (`AXIOM_STATE_DIR`·vault 디렉토리 분리).
6. canonical digest의 경로·시간 등 비결정적 메타데이터 정규화 — A==B 바이트 동일 재생의 판정 기준.

A/B 2회 일치는 필요조건이지 전체 시스템 결정론의 증명이 아니다 — 위 6항의 통제 기록과 함께 증거화한다.

---

## 13. 게이트 (P1 — 구현 착수 조건)

P1 실증이 다음을 관측하지 못하면 **구현을 중단하고 본 계약을 개정·재동결한다** (자동 백업 전환 금지 — 사용자 조건 5):

1. of-매트릭스 관찰: 13 인스턴스 × 8 판별 실행에서 수정 불변식 위반 없음·observed == expected 전부 (probe 확장).
2. sidecar 2단 로더의 외부 피검험체(@debf33c) 적용 가능성 — 불가 시 **중단·재동결** (프라그마 자동 전환 없음).
3. 엔진 추가점 실존: closed registry(external_subject_registry.nim:225-235)·d2 형상 post 생성기(counterexample_replay.nim:1407-1422)·stamped 브랜치(:1475-1496)·typedesc 캐리어 토큰.

*본 문서의 채택 레코드(adoptedSpecHash 등)는 구현 시 신뢰 경로(specIdentity)로 재계산되며 수동 해싱되지 않는다.*
