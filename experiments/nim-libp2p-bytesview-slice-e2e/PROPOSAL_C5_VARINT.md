# PROPOSAL — nim-libp2p C5(varint) 형식 명제 3건 (NOT_ADOPTED)

> **Status**: **NOT_ADOPTED** — 채택 메커니즘만 존재하는 상태. 어떤 명제도 채택되지 않았고, 어떤 검증 권한도 만들어지지 않았다. 명제 채택권은 사용자(인간 아키텍트)에게 있다; Axiom은 채택된 명제를 검증하는 도구일 뿐이다.
> **Date**: 2026-10-30 · **Experiment ID**: `nim-libp2p-bytesview-slice-e2e`
> **Subject pin (READ-ONLY, Zero-Footprint)**: status-im/nim-libp2p — 로컬 READ-ONLY 클론 `<workspace>/nim-libp2p` @ `a130a7f32219909bdcda14b7f1e64d0804fc832c` (기존 bytesview 오버레이 `config/spec/nim_libp2p_bytesview_slice.json:16`이 핀하는 동일 커밋).
> - `libp2p/varint.nim` content sha256 = `cb534bcd3af603f46b319e8f60df6539a9714dad80ed4512d24a87260ee22845`
> - `libp2p/vbuffer.nim` content sha256 = `847ee42b9218b78d8911a062c8780545e642a9f71bad10eee46e6f3833720d1f`
> (subject pin 해시 종류는 bytesview 오버레이의 관례와 동일: 모듈 파일 내용 sha256 — `nim_libp2p_bytesview_slice.json:53` caveat.)
> **선행 발견 기록**: `experiments/nim-libp2p-bytesview-slice-e2e/discovery/01_nim_libp2p_full_survey.md:122-124` (C5 정식 기록, 본 제안서의 ①~③ 사실과 일치).
> **본 PR 범위**: 제안서 + 표현력 실행 증거 + NOT_ADOPTED 기록 **뿐**. `src/` 기능 구현(uint64 리터럴·문법 확장 등) 전혀 없음. nim-libp2p 트리 무변경.

---

## §0. 요약 — 3개 명제와 판정

| # | 명제 | 진리값(주장) | canonical 표현 가능? | 해시 | 증거 등급 |
|---|---|---|---|---|---|
| (a) | 정준성: `putUVarint(getUVarint(b)) == b` (b = 디코더가 소비한 정확한 바이트 구간) | 미판정(코드 관측상 참으로 보임) | **불가** — roundtrip 절 형태만 파싱되고, 필수 정수 도메인 절이 b를 정수로 강제 코어싱(RUN7) → 의미 변질 | 제안서 레코드 해시 `c03ffe17…` (SpecID 아님) | 코드 관측 + 테스트 근거 — **보편 명제의 증명 아님** |
| (b) | 값 왕복: `getUVarint(putUVarint(v)) == v`, 도메인 `0 ≤ v ≤ 9223372036854775807` | 미판정(채택 시 검증 대상) | **가능** — 실제 로더가 로드 성공(RUN1) | **SpecID** `ddf7eca1151d672f963b04716c4772940e5e59b69045428b5385151d764f0607` (후보 신원; NOT adopted) | 코드 관측 + 테스트 근거 — **보편 명제의 증명 아님** |
| (c) | C5 결함 명제: `∀v ∈ [2^63, 2^64)` writeLPVarint가 절단 없이 인코딩한다 | **거짓** (반례 증인: `vbuffer.nim:63` 조용한 절단) | **불가** — 도메인 리터럴 2^63·2^64−1이 int64 초과로 fail-closed 거부(RUN2/3/4) + 단일 호출 사후조건 절 종류 부재(RUN5) | 제안서 레코드 해시 `c42e064e…` (SpecID 아님) | 코드 순서 기반 정적 반례 추론 + survey 합치; **replay 반증 실행은 아님** |

---

## §1. varint 사실 재검증 (nim-libp2p @ a130a7f32, file:line 근거)

① **overlong(비정준) 인코딩 읽기 거부** — `libp2p/varint.nim:142-143`:
```nim
if vsizeof(parsed.val) != parsed.len:
  return err(VarintError.Overlong)
```
디코딩된 값의 재인코딩 길이가 실제 소비 바이트 수와 다르면 `Overlong` 에러 — 비정준(varint를 늘려 쓰는) 인코딩은 거부된다.

② **63비트 상한 (LP 방언)** — 모듈 문서 `libp2p/varint.nim:9-11` ("LibP2P varint, which is able to encode only 63bits … maximum size … 9 octets").
- 디코드 측: `libp2p/varint.nim:138-140` — `parsed.val >= 0x8000_0000_0000_0000'u64` → `err(VarintError.Overflow)`.
- 인코딩 측: `libp2p/varint.nim:171-173` — `LP.putUVarint`에서 `(uint64(outval) and 0x8000_0000_0000_0000'u64) != 0` → `err(VarintError.Overflow)`.

③ **C5 결함의 실체** — `libp2p/vbuffer.nim:59-67` (`writeLPVarint`):
```nim
proc writeLPVarint*(vb: var VBuffer, value: LPSomeUVarint) =
  var length = 0
  # LibP2P varint supports only 63 bits.
  var v = value and cast[type(value)](0x7FFF_FFFF_FFFF_FFFF)   # ← :63 마스킹
  vb.buffer.setLen(len(vb.buffer) + vsizeof(v))
  let res = LP.putUVarint(toOpenArray(vb.buffer, vb.offset, vb.buffer.high), length, v)  # ← :65
```
:63의 마스킹이 :65의 `LP.putUVarint`가 수행하는 Overflow 검사(`varint.nim:171-173`)보다 **먼저** 실행된다. 따라서 v ≥ 2^63은 **조용히 절단**된다: `2^63 → 0x7FFF_FFFF_FFFF_FFFF & 0x8000_0000_0000_0000 = 0`, `2^64−1 → 2^63−1`. `writeVarint`도 이에 위임된다(`vbuffer.nim:69-70`). 결과: `varint.nim:171-173`의 Overflow 분기는 VBuffer 경로에서 도달 불가능하며, 쓰기-읽기 비대칭이 생긴다(디코드 측 `varint.nim:138-140`는 ≥2^63을 거부하는데, 쓰기 측은 절단 후 저장). 이것이 C5의 실체이며 survey 기록(`01_nim_libp2p_full_survey.md:122-124`)과 정확히 일치한다. 한편 "∀v ≥ 2^63: LP.putUVarint = Overflow"라는 양의 명제는 참이지만 VBuffer 경로에서는 도달 불가능(survey :124와 동일 판정).

---

## §2. 오버레이 문법 표현력 정밀 검증 (실행 증거)

### §2.1 문법 소스 (Axiom @ work/vs-d = origin/main 474392b11)

- 클로즈드 절 문법의 파서: `src/cli/axiom_engine.nim`
  - `isIntLiteral` :894-898 — 숫자(0-9)만 허용하는 형태 검사(모듈 private).
  - `parseRoundtripClause` :900-922 — 정확히 2중 중첩 `<outer>(<inner>(<v>)) == <v>` 형태만, `arg == rhs` 강제.
  - `parseUpperDomainClause` :924-936 — `<ident> <= <INT>`, 리터럴은 `safeParseInt` (:932).
  - `parseLowerDomainClause` :938-950 — `<INT> <= <ident>`, 리터럴은 `safeParseInt` (:946).
  - 절 루프와 모호성 검사 :983-998, **필수 절 3종 강제** :999-1001 (`'0 <= n'`, `'n <= <bound>'`, `'<outer>(<inner>(n)) == n'` — 하나라도 없으면 err), 1변수 결합 :1005-1006, roundtrip 기호가 subject.symbols 멤버여야 함 :1007-1008.
- 리터럴 상한의 근원: `src/core/parsers/safe_parsers.nim:11-19` — `parseInt(s, val)`을 `int`(64비트)에 대해 수행, `ValueError` → `err("failed to parse integer")`. **int64.max를 넘는 리터럴은 파싱 자체가 실패**한다.
- `src/cli/axiom_engine.nim:32`가 `core/parsers/safe_parsers`를 임포트 — 오버레이 파서들의 모든 리터럴 상한은 이 int64 천장을 공유한다(다른 오버레이 파서들도 동일: :1064, :1078-1079, :1135, :1222, :1396, :1411).
- 능력·관측 폐쇄집합: `src/cli/external_subject_registry.nim`
  - `ExternalSubjectCapability` :57-62 — {constructed-gate, arithmetic-law, body-carry, term-splice, beta-composition} 5종.
  - `ReplayObservationKind` :68-72 — {raise-bool, single-call-int, single-call-bool} 3종.
  - 클로즈드 replay 템플릿 레지스트리 :141-151 — {d2-gate-reject-v1, bv-slice-len-v1, single-call-bool-v1} 3종; 미지 templateId → `err("UNKNOWN replay templateId … fail-closed")`.
  - subject 모듈/심볼 이름은 **열린 문자열**(`validateSubjectPinObject` :227-252 — 비어있지 않은 문자열 요구, repository/commit/sourceLines 필수 :245-247, blobSha256 64-hex :248-251). 따라서 varint 관련 함수(putUVarint/getUVarint 등)를 subject 심볼로 **참조하는 것은 가능**하다. 그러나 이를 **실행할** replay 템플릿은 존재하지 않는다 — 3개 템플릿 본문(:110-139)은 모두 Toml 디코드/BytesView 슬라이스 길이/gateAccept 호출이고, varint 인코딩-디코딩을 수행하는 본문은 없다. 새 템플릿 등록이 필요하며 그 전에는 미지 templateId로 fail-closed 거부된다.
- SpecID 계약: `src/core/trusted/specification_artifact.nim` — 주석 :8 `SpecID = H(canonicalSpecIR, origin, ruleVersion)`, 실제 계산 `specIdentity` :45-48:
```nim
func specIdentity*(spec: SpecificationArtifact): SpecID {.raises: [].} =
  let sortedIR = spec.canonicalSpecIR.sorted()
  let data = sortedIR.join("|") & "|" & $ord(spec.origin) & "|" & spec.ruleVersion
  sha256Hex(data)
```
주의: 해시 입력에는 **ruleId가 포함되지 않는다** (identity = (sorted IR, origin 서수, ruleVersion)). `explicitSpecFromOverlay` :68-97은 origin을 `soExplicit`로 핀하고 다른 선언은 fail-closed(:77-78).

### §2.2 실행 방법 (정적 추측 금지 — 실제 파서 체인 구동)

`parseUpperDomainClause`/`parseLowerDomainClause`/`parseRoundtripClause`는 export 마커(`*`)가 없는 모듈 private 심볼이라 임포트로 직접 호출할 수 없다(최소 프로브에서 `undeclared identifier` 확인 — 컴파일러가 강제하는 가시성 경계). 공개 진입점은 실제 로더 `loadBase36OverlayDomain*`(:952)뿐이므로, **실제 로더가 실제 절 파서 체인(isIntLiteral → safeParseInt → 절 루프 → 필수 절 검사)을 통과하도록** 오버레이 문서를 교차 투입하는 방식으로 구동했다:

1. `bin/ax` release 빌드(AXIOM_HERMETIC_BUILDING=1, nim 2.2.10; SourceCoherence·merkle 무결성 검사 통과) — config/integrity.nims 후크가 `nim r`마다 bin/ax 존재+merkle을 요구.
2. 프로브(`tests/cli/c5_varint_grammar_probe.nim` — 커밋 전 삭제, 전문은 §5 부록)가 `loadBase36OverlayDomain()` + `safeParseInt` + `specIdentity`를 호출하고 결과를 정확히 출력.
3. `config/spec/base36_sizing_relational_spec.json`을 **본 워크트리에서만 임시 교체**하며 7회 구동(RUN1-7), 매 실행 후 `git checkout --`로 원본 복구. RUN6에서 원본 오버레이 로드 재확인(bound=33297371974204966, ok) — 복구 무결성 입증. 커밋 시점 git status는 원본 변경 없음을 확인.
4. 원시 로그: `runs/c5_grammar_probe.log` (sha256 `13748d2677e7ca8e693d668bbc53fa102557d06b3f60da32b2129e064ca0edbc`).

각 RUN의 canonicalSpecIR 입력 (공통: specOrigin=soExplicit, ruleId=probe:c5-varint-expressiveness, ruleVersion=0.0.0, subject.module=libp2p/varint.nim, subject.symbols=[putUVarint, getUVarint]; RUN5만 symbols=[writeLPVarint, readVarint]):

| RUN | canonicalSpecIR 절 | 기대 | 실제 결과 (로그 행) |
|---|---|---|---|
| 1 | `["0 <= v", "v <= 9223372036854775807", "getUVarint(putUVarint(v)) == v"]` | (b) 그대로 로드 | **ok** — domainVar=v, domainLower=0, **domainBound=9223372036854775807**, outer=getUVarint inner=putUVarint (:206-210) |
| 2 | 상한을 `9223372036854775808` (2^63)로 | fail-closed | **err** `spec overlay: canonicalSpecIR must contain the '0 <= n', 'n <= <bound>' and '<outer>(<inner>(n)) == n' clauses` (:421) |
| 3 | 상한을 `18446744073709551615` (2^64−1)로 | fail-closed | **동일 err** (:632) |
| 4 | 하한을 `9223372036854775808` (2^63)로, 유효한 상한 | fail-closed | **동일 err** (:843) |
| 5 | roundtrip 절을 단일 호출 `"writeLPVarint(v) == v"`로 | fail-closed | **동일 err** — roundtrip 절 부재로 판정 (:1054) |
| 6 | 원본 base36 오버레이 (git checkout 복구 후) | 원본 로드 | **ok** — domainBound=33297371974204966 (:1265-1268) |
| 7 | (a) 절 형태 `["0 <= b", "b <= 9223372036854775807", "putUVarint(getUVarint(b)) == b"]` | 형태만 통과, b 정수 강제 | **ok** — domainVar=b, domainLower=0, domainBound=9223372036854775807, outer=putUVarint inner=getUVarint (로그 말미) — **b가 정수로 코어싱됨 = 의미 변질** |

직접 safeParseInt 관측(모든 RUN 공통, :211-213 등):
```
safeParseInt("9223372036854775807") => ok(9223372036854775807 : int)
safeParseInt("9223372036854775808") => err("failed to parse integer")
safeParseInt("18446744073709551615") => err("failed to parse integer")
```

### §2.3 판정

- **(i) 도메인 상한 리터럴 9223372036854775807 (int64.max)**: **표현 가능**. 형태 검사 통과 + safeParseInt ok + 실제 로더가 domainBound=9223372036854775807로 로드(RUN1). 실행 증거로 확정.
- **(ii) int64.max 초과 리터럴 (2^63, 2^64−1)**: **fail-closed 거부**. safeParseInt가 err를 반환하고(`safe_parsers.nim:18-19`), 해당 절은 파서에서 none이 되어 로더의 필수 절 검사(:999-1001)가 명시적 에러로 실패한다(RUN2/3/4). 값의 랩어라운드나 절단 없이 **문서 전체가 로드 거부**된다 — fail-closed.
- **레지스트리 판정**: varint 함수 참조( subject 심볼 선언)는 가능하나, varint 관찰을 실행할 폐쇄 템플릿/능력 조합은 오늘 존재하지 않는다(§2.1).

---

## §3. 명제 (a) — 정준성 (canonicality)

**명제**: `putUVarint(getUVarint(b)) == b` — 단, **b는 디코더가 실제로 소비한 정확한 바이트 구간**(getUVarint의 outlen 바이트)으로 정의한다. 전체 입력 버퍼가 아니다: 디코더는 접두만 소비하므로, 전체 버퍼 정의로는 후행 바이트 때문에 등식이 성립하지 않는다. 이 구간 정의가 명제의 일부다.

**코드 관측(근거, 증명 아님)**: LP 디코드는 비정준을 거부하고(`varint.nim:142-143`) 소비 길이를 정확히 보고하며(:128-147 outlen 계약), 인코더는 LEB128 정준 출력을 낸다(`varint.nim:175-181`). 정준 입력(1..9바이트, 값 <2^63)에 대해 재인코딩이 동일 바이트를 내는 것은 이 관측과 일치한다. 그러나 이것은 **코드 관측 + 테스트 근거일 뿐, 보편 명제의 증명이 아니다**.

**표현력 판정: 불가능**. roundtrip 절 **형태** `putUVarint(getUVarint(b)) == b`는 파서를 통과한다(RUN7 — 이는 RUN1에서 검증된 형태 전용 파서 `parseRoundtripClause` :900-922가 기호 의미를 모르기 때문). 그러나 같은 문서가 반드시 포함해야 하는 정수 도메인 절(`0 <= b`, `b <= <INT>` — 필수, :999-1001)은 b를 **정수**로 결합한다. RUN7의 실제 결과: `domainVar=b, domainLower=0, domainBound=9223372036854775807` — b가 정수로 코어싱되어 "바이트 구간" 명제의 의미가 변질된다. 바이트열 정의역·소비 구간 개념을 표현하는 절 종류는 어떤 오버레이 문법에도 존재하지 않는다(base36 절 루프 :983-1001; rem 절 :1055-1099; bytesview 레인도 정수 정의역 — `nim_libp2p_bytesview_slice.json:22-29`). 형태 파싱 가능성은 명제 표현 가능성이 아니다.

**필요 capability 목록 (구현 없이 나열만)**:
1. 바이트열 정의역 절 종류(예: `bytes(b)` 바인더 또는 "소비 접두" 합성 항) — 문법 확장.
2. 2결과 디코드(값+outlen) 모델링 또는 소비 구간 항 — 현재 roundtrip 문법은 단일 값 왕복만 표현.
3. varint 관찰용 클로즈드 replay 템플릿(바이트 버퍼 fixture; `external_subject_registry.nim:141-151`에 새 templateId).
4. varint 레인 엔진 배선(validate+load; bytesview 레인 `validateNimLibp2pBytesviewSliceOverlayNode` :2009+와 유사한 형태).
5. adoption 레코드 + subject blob 핀(§7).

**제안서 레코드 + 해시** (SpecID 아님 — 아래 해시 원칙 §6):

```text record-a
proposition-id: c5-varint-canonicality-a
class: canonicality (re-encode the decoded value; compare against the consumed bytes)
statement: putUVarint(getUVarint(b)) == b
binding: b := the exact byte range getUVarint consumed from its input (the decoder's outlen bytes); NOT the whole input buffer
quantifier: forall b over byte sequences on which getUVarint succeeds (canonical LP varint: 1..9 bytes, value < 2^63)
status: NOT_ADOPTED
expressibility: NOT canonically expressible in any current Axiom overlay grammar; the roundtrip clause shape parses only by coercing b to an integer domain (0 <= b / b <= int64-bound), which alters the proposition's meaning (probe RUN7)
hash-kind: proposal-record-hash — NOT a SpecID (no canonical form exists to mint one)
```

**proposal-record-hash (a)** = `c03ffe17eda6e8062323f074ea3ba0bc5570a53927e2ccf15e26ed1ad9d02218`
(재검증: `awk '/^```text record-a$/{f=1;next} /^```$/{f=0} f' PROPOSAL_C5_VARINT.md | sha256sum`)

---

## §4. 명제 (b) — 값 왕복 (value roundtrip, 63비트 도메인)

**명제**: `getUVarint(putUVarint(v)) == v` (작업 지시의 `decode(putUVarint(v)) = v`에서 decode = nim-libp2p API 기호 getUVarint, LP 인스턴스), 도메인 **`0 ≤ v ≤ 9223372036854775807`** (리터럴 그대로 — int64.max).

**canonical 표현력 판정: 가능 — 실행으로 입증(RUN1)**. 다음 3절이 현재 클로즈드 문법에 그대로 들어가며 실제 로더가 로드했다:
```
canonicalSpecIR = ["0 <= v", "v <= 9223372036854775807", "getUVarint(putUVarint(v)) == v"]
```
→ `loadBase36OverlayDomain => ok; domainVar=v; domainLower=0; domainBound=9223372036854775807; outer=getUVarint; inner=putUVarint` (로그 :206-210). roundtrip 기호는 subject.symbols 멤버 요건(:1007-1008)을 충족하는 실제 API 기호다. canonicalSpecIR 순서는 SpecID에 무관하다(specIdentity가 정렬함, `specification_artifact.nim:46`).

**SpecID (후보 신원 — NOT adopted)**: 실제 `specIdentity`(`specification_artifact.nim:45-48`)가 위 canonical 형태 + origin=soExplicit + ruleVersion=1.0.0으로 계산한 값 (프로브 로그 :214):
```
ddf7eca1151d672f963b04716c4772940e5e59b69045428b5385151d764f0607
```
입력 데이터 = `"0 <= v|getUVarint(putUVarint(v)) == v|v <= 9223372036854775807|0|1.0.0"` (정렬된 IR | origin 서수 0 | ruleVersion; ruleId는 해시 입력이 아님). ruleId는 `external:libp2p/varint/lp-encode-decode-roundtrip`(기존 관례 준수: `external:libp2p/bytesview/slice-length-law` 등). 이 SpecID는 **채택 객체가 존재하지 않는 한 아무 권한도 만들지 않는다** — soExplicit 핀(`:77-78`)과 채택 행위의 authority 구조상, 채택은 §7의 사용자 행위다.

**증거 등급**: 코드 관측 + 테스트 근거(인코더 정준 출력 `varint.nim:175-181`, 디코더 overlong/overflow 거부 `:142-143`/`:138-140`) — **보편 명제(∀v∈[0,2^63−1])의 증명이 아니다**. 채택될 경우 검증(솔버/슬라이싱)의 입력이 될 뿐이다.

**필요 capability 목록 (구현 없이 나열만)**:
1. varint 레인 엔진 배선 — 문법 자체는 충분(RUN1 입증), bytesview 레인 형태의 validate+load만 없음.
2. 솔버 측 63비트 도메인 처리 확인 — 상한이 int64.max 자체이므로, 채택 시점에 솔버 허용 범위 관측 필요(기존 오버레이 최대 상한은 33297371974204966).
3. (선택) encode→decode 왕복 replay용 클로즈드 템플릿 — 새 templateId 필요.
4. adoption 레코드 + subject blob 핀 (§7; blob = `libp2p/varint.nim` = `cb534bcd…`).

---

## §5. 명제 (c) — C5 결함 명제 (거짓; 반례 증인 기록)

**명제**: `∀v ∈ [2^63, 2^64)`: `writeLPVarint`가 v를 **절단 없이** 인코딩한다(쓴 바이트를 디코드하면 v). **이 명제는 거짓이다.**

**반례 증인 (코드 순서 기반 정적 추론)**: `vbuffer.nim:63`가 `value and 0x7FFF_FFFF_FFFF_FFFF` 마스킹을 `LP.putUVarint` 호출(`vbuffer.nim:65`)보다 먼저 수행하고, 그 Overflow 검사는 `varint.nim:171-173`에 있다. 따라서 v = 2^63은 0x00 한 바이트(디코드값 0)로, v = 2^64−1은 2^63−1로 쓰인다 — 에러 없이. survey 기록(`01_nim_libp2p_full_survey.md:122-124`)과 동일 판정. 주의: 이것은 **replay 반증 실행 결과가 아니다** — 반증 실행은 아래 capability가 갖춰진 후에야 가능하다(그 전까지 본 제안서의 판정은 코드 순서의 정적 추론 + survey 합치에 근거한다).

**표현력 판정: 불가능 (이중)** — 실행 증거:
1. **정의역 리터럴 자체가 무표현**: 하한 `9223372036854775808`(2^63)과 상한 `18446744073709551615`(2^64−1)는 모두 int64.max 초과 → safeParseInt err → 절 none → 로더 fail-closed(RUN2/3/4, §2.2). 즉 [2^63, 2^64) 정의역을 **현재 어떤 오버레이 문법으로도 명명할 수 없다**. 모든 오버레이 파서의 리터럴이 int64 천장을 공유하기 때문이다(§2.1, `safe_parsers.nim:11-19` + `axiom_engine.nim:32`).
2. **사후조건 형태 무표현**: 절단 부정 명제는 단일 호출 성질(`writeLPVarint(v)`의 결과가 v와 일치)인데, roundtrip 문법은 정확히 2중 중첩 `outer(inner(v)) == v`만 받는다(`parseRoundtripClause` :900-922; RUN5에서 단일 호출 절은 roundtrip 부재로 fail-closed).

**함의**: 현재 문법으로는 이 **거짓 명제조차 채택(그리고 기계적 반증)할 수 없다** — Axiom이 명제를 상태화하려면 문법·능력 확장이 먼저다. 그 확장(uint64 리터럴, 단일 호출 사후조건 절 등)은 **구현이므로 본 슬라이스에서 수행하지 않았다**. 그때까지 C5는 (i) 본 제안서 레코드와 (ii) survey 기록 :122-124에만 존재한다.

**필요 capability 목록 (구현 없이 나열만)**:
1. int64 초과 리터럴(uint64) 문법 지원 또는 스케일링 절 — `safeParseInt` 천장 확장.
2. 단일 호출 사후조건 절 종류(현재 roundtrip 전용).
3. 반증 레인: witness v=2^63에서 vbuffer write+read를 실행해 관측값 0을 기록하는 replay(명제가 거짓이므로 채택은 **반증**을 승인한다).
4. 클로즈드 템플릿 등록 + 레인 배선.
5. adoption 레코드(vbuffer.nim blob = `847ee42b…`).

**제안서 레코드 + 해시** (SpecID 아님 — §6):

```text record-c
proposition-id: c5-varint-defect-c
class: defect proposition (FALSE — counterexample witness recorded)
statement: forall v in [2^63, 2^64): writeLPVarint(vb, v) encodes v without truncation, i.e. the written bytes decode back to v
witness: libp2p/vbuffer.nim:63 masks v with 0x7FFF_FFFF_FFFF_FFFF BEFORE LP.putUVarint can apply its Overflow check (libp2p/varint.nim:171-173); v = 2^63 is written as byte 0x00 (decodes to 0), v = 2^64-1 is written as 2^63-1 — silent truncation, no error
status: NOT_ADOPTED
expressibility: NOT canonically expressible — the domain literals 9223372036854775808 and 18446744073709551615 exceed int64 and are fail-closed rejected by the overlay grammar (probe RUN2/RUN3/RUN4), and the single-call postcondition shape writeLPVarint(v) == v has no clause kind in the roundtrip grammar (probe RUN5)
hash-kind: proposal-record-hash — NOT a SpecID (no canonical form exists to mint one)
```

**proposal-record-hash (c)** = `c42e064e4d5dbfb48fbed21a1229077b77b0a7b5d928727971f612c17e4bcc15`
(재검증: `awk '/^```text record-c$/{f=1;next} /^```$/{f=0} f' PROPOSAL_C5_VARINT.md | sha256sum`)

---

## §6. 해시 원칙 — SpecID와 제안서 해시의 구분 (HARD)

- **SpecID는 canonical form으로 표현 가능한 명제에만 부여**된다. 계약: `specification_artifact.nim:8`(`SpecID = H(canonicalSpecIR, origin, ruleVersion)`) + :45-48. 본 제안서에서 (b)만 해당 → SpecID `ddf7eca1…`.
- **표현 불가능한 명제 (a), (c)에는 SpecID를 부여하지 않는다.** 이 명제들의 유일한 담지체는 본 제안서 문서이므로, 해시는 "제안서 해시"로만 기록하고 **절대 SpecID라고 부르지 않는다**.
- 자기 참조 제약(파일은 자기 해시를 담을 수 없음) 때문에 제안서 해시는 두 층으로 기록한다:
  1. **record hash (문서 내 기록, 재검증 가능)**: §3/§5의 fenced 레코드 블록 바이트에 대한 SHA-256 — (a) `c03ffe17…02218`, (c) `c42e064e…bcc15`. 위에 적은 awk 추출 명령으로 재계산해 일치시킬 수 있다.
  2. **file hash (최종 파일 전체 SHA-256)**: 본 파일의 최종 바이트에 대한 SHA-256으로, 커밋 메시지와 PR 본문에 기록한다(문서 내부에는 기록 불가).
- 어느 층도 SpecID가 아니며, 어떤 검증 권한도 수반하지 않는다.

---

## §7. NOT_ADOPTED 상태와 채택 경로

**현재 상태**: 3건 모두 NOT_ADOPTED. 채택 객체(adoption object)는 어디에도 존재하지 않고, `config/spec/`에는 새 파일을 추가하지 않았다. (b)의 SpecID는 후보 신원일 뿐이다.

**채택 메커니즘은 이미 존재한다** (재구축 불필요 — 재사용 경로만 기술):

1. **스키마**: adoption 객체(adoptedSpecHash/adopter/adoptedAt/basis/grammarVersion/subject{source,module,symbol,commit,blobSha256}/provenance)의 실례 = `config/spec/nim_stew_base36_sidecar.json:27-41`. 타입 계약 = `axiom_engine.nim:2235-2245`(SidecarAdoptionRecord)+`external_subject_registry.nim:227-252`(subject 핀 필수 필드).
2. **2단계 로드 검사** (채택의 기계적 의미):
   - (i) **SpecID 재계산 일치**: 로더가 로드된 명제 내용에서 `specIdentity`를 재계산해 `adoption.adoptedSpecHash`와 바이트 일치 확인 — 채택 후 내용/ruleVersion 변경은 기계적으로 채택을 무효화(`axiom_engine.nim:2542-2552`; 개념 주석 :2196-2211).
   - (ii) **blob 핀**: 기록된 경로의 모듈 바이트 sha256이 `adoption.subject.blobSha256`과 일치해야 함(`verifySidecarSubjectPin` :2561-2577 → 공유 `verifySubjectBlobPin` `external_subject_registry.nim:183-215`; 불일치 시 "…the proposition was not adopted for these bytes" :210-214).
3. **(b)의 채택 경로** (사용자 승인 선행 — 명제 채택권은 사용자에게 있음):
   - 새 `config/spec/nim_libp2p_varint_roundtrip.json` (Axiom-owned, soExplicit 핀) — canonicalSpecIR = §4의 3절, adoption.adoptedSpecHash = `ddf7eca1…`, subject = {module: libp2p/varint.nim, symbols: [putUVarint, getUVarint], commit: a130a7f32…, blobSha256: cb534bcd…}.
   - bytesview 레인 형태의 엔진 배선(§4 capability 1) + 필요 시 클로즈드 템플릿 등록 — 별도 구현 슬라이스.
   - 승인 구조는 기존 실례와 동일: bytesview 오버레이의 adoptionRef가 기록하듯(`nim_libp2p_bytesview_slice.json:10-11`) 내용 저작과 무관하게 **권한은 명시적 채택 행위**다(`external_subject_registry.nim:17-22` "Authorship confers NO authority" 계열).
4. **(a)/(c)의 채택 경로**: §3/§5 capability가 먼저 착지해야 하고, 그 후 동일 스키마로 (a)는 바이트 정의역 문법 위에, (c)는 **반증 목적**으로 채택한다(거짓 명제의 채택 = 반증 실행 승인).
5. **선행 발견 기록**: `discovery/01_nim_libp2p_full_survey.md:122-124` — C5 최초 정식 기록. 본 제안서는 그 발견을 형식 명제 후보로 상태화하되 채택하지 않는다(발견 ≠ 권한).

---

## §8. 비주장 (nonClaims)

- NOT adopted — 어떤 명제도 채택되지 않았고, 채택이 만드는 어떤 검증 권한·dispatch 입력도 존재하지 않는다.
- NOT a proof — (a)(b)의 "코드 관측 + 테스트 근거"는 보편 명제의 증명이 아니다. 테스트/로드 통과는 표현 가능성의 증거일 뿐이다.
- (c)의 "거짓" 판정은 코드 순서 기반 정적 추론 + survey 합치다 — replay 반증 실행은 아니다(capability 부재).
- NOT an implementation — 본 PR은 `src/`·`config/` 기능 구현(uint64 리터럴, 문법 확장, 템플릿, 레인 배선)을 전혀 포함하지 않는다.
- NOT a nim-libp2p modification — 대상 트리는 READ-ONLY이며 무변경이다(Zero-Footprint).
- 프로브는 본 워크트리의 tracked 오버레이 파일을 임시 교체한 뒤 `git checkout`으로 복구했다; 커밋 트리에는 원본 바이트만 있다(RUN6 재확인 + 커밋 시 git status 확인).
- NOT a claim about nim-libp2p's overall correctness/safety.

---

## §9. 증거 부록

### §9.1 프로브 전문 (커밋 전 트리에서 삭제됨; 재현용 보존)
```nim
## TEMPORARY evidence probe (deleted before commit) — drives the REAL public
## overlay loader `loadBase36OverlayDomain` (src/cli/axiom_engine.nim:952) over
## a temporarily-swapped overlay document whose canonicalSpecIR clauses are the
## C5-varint propositions' clauses in the SAME closed grammar. Observation of
## the existing parser chain only — no src/ change, no capability work.
## The clause parsers themselves (parseUpper/parseLowerDomainClause,
## parseRoundtripClause, isIntLiteral) are module-private (no export marker);
## the public loader is their only executable surface, so this probe observes
## their real behavior end-to-end and prints the loader verdict verbatim.
import ../../src/core/results
import ../../src/core/parsers/safe_parsers
import ../../src/core/trusted/specification_artifact
import ../../src/cli/axiom_engine

let d = loadBase36OverlayDomain()
if d.isOk:
  let dom = d.get()
  echo "loadBase36OverlayDomain => ok"
  echo "  domainVar=" & dom.domainVar
  echo "  domainLower=" & $dom.domainLower
  echo "  domainBound=" & $dom.domainBound
  echo "  outer=" & dom.outerSymbol & " inner=" & dom.innerSymbol &
    " module=" & dom.modulePath
else:
  echo "loadBase36OverlayDomain => err: " & d.error

let rMax = safeParseInt("9223372036854775807")
if rMax.isOk:
  echo "safeParseInt(\"9223372036854775807\") => ok(" & $rMax.value & " : int)"
else:
  echo "safeParseInt(\"9223372036854775807\") => err"
let r63 = safeParseInt("9223372036854775808")
if r63.isOk:
  echo "safeParseInt(\"9223372036854775808\") => ok(" & $r63.value & " : int)"
else:
  echo "safeParseInt(\"9223372036854775808\") => err(\"" & r63.error & "\")"
let r64 = safeParseInt("18446744073709551615")
if r64.isOk:
  echo "safeParseInt(\"18446744073709551615\") => ok(" & $r64.value & " : int)"
else:
  echo "safeParseInt(\"18446744073709551615\") => err(\"" & r64.error & "\")"

let propB = SpecificationArtifact(
  canonicalSpecIR: @["0 <= v", "v <= 9223372036854775807",
                     "getUVarint(putUVarint(v)) == v"],
  rawPreConditions: @[], rawPostConditions: @[],
  origin: soExplicit,
  ruleId: "external:libp2p/varint/lp-encode-decode-roundtrip",
  ruleVersion: "1.0.0")
echo "proposition (b) SpecID (specIdentity, specification_artifact.nim:45-48) = " &
  propB.specIdentity
echo "== probe end =="
```

실행 명령: `nim r --verbosity:0 --hints:off tests/cli/c5_varint_grammar_probe.nim` (오버레이 스왑 상태에서 7회; 각 실행 후 `git checkout -- config/spec/base36_sizing_relational_spec.json`).

### §9.2 빌드·환경 신원
- Nim 2.2.10 (저장소 고정 버전); 워크트리 `<user-home>/axwt/vsd` = `work/vs-d` @ 474392b113cc646d2a93e9efd36c3f1e29d31dd9 (origin/main).
- `bin/ax` release 빌드 sha256 `e4cdb6df979a47e3e036955f742af07bbc7f625b72e23f55bea157dc081f1de4` (gitignored 빌드 산출물; SourceCoherence·merkle 검사는 probe 실행마다 통과).
- 원시 로그: `runs/c5_grammar_probe.log`, sha256 `13748d2677e7ca8e693d668bbc53fa102557d06b3f60da32b2129e064ca0edbc`.
- subject 모듈 해시: `libp2p/varint.nim` = `cb534bcd3af603f46b319e8f60df6539a9714dad80ed4512d24a87260ee22845`, `libp2p/vbuffer.nim` = `847ee42b9218b78d8911a062c8780545e642a9f71bad10eee46e6f3833720d1f` @ a130a7f32219909bdcda14b7f1e64d0804fc832c.

### §9.3 최종 파일 해시
- 본 제안서 파일 전체 SHA-256은 커밋 메시지와 PR 본문에 기록된다(자기 참조 불가 — §6 참조).
