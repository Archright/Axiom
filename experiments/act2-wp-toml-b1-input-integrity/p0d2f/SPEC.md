# P0-D2-F — D2 결함의 정형명세 S1과 `ax prove --project` 반증 실험 명세 (TOML 1.1 `\xHH`)

Experiment: `act2-wp-toml-b1-input-integrity/p0d2f` · Date: 2026-10-17

**목적**: nim-toml-serialization @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9`의 D2 결함(TOML `\xHH` 디코드가 U+00HH의 UTF-8 인코딩 대신 raw byte를 삽입)을 단일 함수 명세 **S1**으로 정형화하고, `ax prove --project`(`src/cli/axiom_engine.nim:3027` — explicit subject root) 파이프라인이 결함 커널은 **SAT(반례)**로 반증하고 대조 커널은 **UNSAT**로 통과시키는 판별력을 시험한다.

선행 기록: `../p0d2/RT_EXPERIMENT.md` — 같은 결함의 바이트 수준 런타임 관측(결함 경로 `E9` vs 정상 경로 `C3 A9`, `canonicalProjectionHash 18bfdc76f9b4bfdab1d0da2fa3fb1f2b7a3f56200bc15a7c79196c588d22192c`). 본 문서는 그 결함을 정형 영역으로 운반하는 **실험 명세**다 — 실행 결과는 `runs/`, 변이 환경은 `variant.patch`(baseline 트리 대상 유일 delta: `d2kernels.nim` 추가)와 `env/subject_baseline/`·`env/subject_variant/`가 운반한다.

---

## 정형명세 S1 (UTF-8 바이트 길이 법칙)

```text
∀ code ∈ [0x00, 0xFF]:  byteLen( decode("\x" ‖ hex2(code)) ) = ( code ≤ 0x7F ? 1 : 2 )
```

- `decode("\x" ‖ hex2(code))` — D2 디코더가 `\xHH` 이스케이프를 처리한 뒤 결과 문자열에 삽입한 바이트열
- `byteLen(b)` — 바이트열 `b`의 길이
- `hex2(code)` — `code`의 2자리 16진 표기 (예: `0xE9` → `"E9"`)

커널 프라그마 형태(`variant.patch`의 `d2kernels.nim` 선언과 동일):

```nim
{.axiom: [
  pre:  (code >= 0 and code <= 255),
  post: (result == (if code < 128: 1 else: 2))].}
```

S1은 **길이 법칙만** 기술한다. 바이트 **값**(2바이트 케이스의 선행 바이트 등)은 법칙의 대상이 아니다(「범위 밖」 참조).

## 근거 (공식 문서)

- **TOML 공식 스펙 escape 표**: `\xHH - unicode (U+00HH)`; "The escape codes must be Unicode scalar values" (toml.md:285-302) — 이 이스케이프가 도입하는 것은 코드 포인트(스칼라 값)다.
- **"Keep in mind that all TOML strings are sequences of Unicode characters, _not_ byte sequences"** (toml.md:308-312) — 디코드 결과는 바이트열이 아니라 (UTF-8로 직렬화되는) 유니코드 문자열이어야 한다.
- **"A TOML file must be a valid UTF-8 encoded Unicode document"** (toml.md:37-47) — 문서 전체가 잘 형성된 UTF-8이어야 한다는 요구.
- **RFC 3629**: U+0080..U+07FF의 UTF-8 인코딩은 2바이트 (`110xxxxx 10xxxxxx`). U+00E9 → `C3 A9`.
- **Nim 공식 매뉴얼**: `char`은 1바이트 타입이며 "cannot represent a UTF-8 character, but a part of it"; 유니코드 문자는 `Rune`, 문자열은 UTF-8 관례. 따라서 `res.add char(code)`는 UTF-8 인코딩이 아니라 **단일 raw byte 삽입**이다.
- **p0d2 런타임 관측과 정합**: 결함 경로(`scanHexEscape`)는 `E9`(1바이트, invalid UTF-8), 정상 경로(`scanUnicode`)는 `C3 A9` — `../p0d2/RT_EXPERIMENT.md` case 2/3 관측과 S1의 예측이 정확히 일치한다.

## 커널 정의

| 커널 | 정의 | 원본 추출 근거 | 기대 판정 |
|---|---|---|---|
| `d2HexEscapeAppendLen` (결함 커널) | `func d2HexEscapeAppendLen*(code: int): int = 1` | `lexer.nim:428-429` — `scanHexEscape`의 `when T is string: res.add char(code)`의 기계적 추출: `char(code)` append는 임의 code에 대해 정확히 **1 raw byte**를 기여. 원본 lexer.nim sha256 @`4aa8e22`: `19d69eed84f74c51fa1784b2e71a4525abc8d2b8aa854c567565d2d603133f4d` | **SAT** — 반례 code ∈ [0x80, 0xFF] (예: 0xE9 → 관측 1, 명세 2) |
| `d2Utf8AppendLen` (대조 커널) | `func d2Utf8AppendLen*(code: int): int = if code < 128: 1 else: 2` | `lexer.nim:399-414` — `scanUnicode`의 `res.add unicode.toUTF8(Rune(code))`(:413-414)의 [0x00, 0xFF] 도메인 특수화(RFC 3629: U+0080..U+00FF는 2바이트) | **UNSAT** — `certZ3Candidate` (`src/core/types/certificate_types.nim:43,62`) |

- **차동(differential) 설계**: 두 커널 모두 **동일 스펙 S1**을 적용받는다. 결함 커널에서만 SAT가 나오고 대조 커널에서 UNSAT가 나오는 쌍이 파이프라인 판별력의 증거다. 대조 커널은 **음성 대조군**이다 — 대조 커널에서까지 SAT가 나오면 주체가 아니라 파이프라인·명세 주입의 결함이다.
- 두 커널의 대상 함수, 프라그마, 심을 포함한 변이 모듈은 `variant.patch`가 정의한다 — baseline 트리(`env/subject_baseline/`)에 대한 **유일 delta**로서 `d2kernels.nim` 추가다.

## 프라그마 심(shim) 설계

변이 파일(`d2kernels.nim`)은 다음 심을 포함한다:

```nim
template axiom*(val: untyped = "") {.pragma.}
```

필요한 이유는 두 파이프라인 단계의 요구가 충돌하기 때문이다:

1. **수집은 raw AST에서**: 외부 IR materializer는 `{.axiom: [pre: (…), post: (…)].}` **키워드 형식**을 함수 정의 프라그마 노드의 자식에서 태그 `"axiom"` `nkExprColonExpr` → `nkBracket` 인자로 수집한다 (`src/infrastructure/external_ir_materializer.nim:273-298`). 수집 시점에 심 템플릿의 존재는 무관하다 — 구문만 읽는다.
2. **재생은 실제 컴파일**: 반례 모델 재생은 변이 모듈을 실제 `nim c`로 컴파일해 모델을 주입한 하니스를 실행한다 (`src/verification/counterexample_replay.nim:499-504`). 프라그마가 컴파일 불가능하면 재생 단계 전체가 실패하므로, 프라그마는 **컴파일 가능해야** 한다.
3. **해소**: 심은 Axiom 자체 패턴의 미러다 — 동일 선언이 `src/core/trusted/axiom_pragmas_macros.nim:11`에 존재한다. `untyped` 인자는 의미분석 없이 구문으로만 운반되므로 `[pre: (…), post: (…)]` 키워드 형식 페이로드는 컴파일 타임에 안전하게 소성(inert)된다.

## 왕복 속성 분해 근거

p0d2의 계약 키는 `decode(encode(v)) == v`라는 **이항 관계 명세**였다. 파이프라인에는 관계 명세의 1급 형태가 없다 — 존재하는 것은 단일 함수의 pre/post뿐이다. 따라서 모순을 관계 전체에 두지 않고, 이 파이프라인이 소비 가능한 형태인 **S1(디코더의 바이트 법칙)으로 국소화**한다.

- 관계 `decode(encode(v)) == v` = 디코더 법칙(위반 지점) ∧ 인코더 법칙. 국소화는 위반 지점만 정형 대상으로 삼는다.
- **인코더 역할**(`writer.nim:141-146`의 `\xHH` 출력 — `append "\\x"` + `toHex(c.int, 2)`)의 런타임 담당은 본 슬라이스가 다시 수행하지 않는다 — `../p0d2/RT_EXPERIMENT.md`의 기록(case 2: 인코더가 `\xE9` = `5C 78 45 39`를 출력)이 담당한다.
- S1이 참이어도 왕복 등가성이 참이라는 뜻은 아니다 (「범위 밖」).

## 비판 검증표

| # | 비판 | 처분 | 반영 |
|---|---|---|---|
| 1 | **S1 firstByte 범위 정정** — 초안의 firstByte(2바이트 인코딩 선행 바이트) 서술이 일반 2바이트 형식(0xC0–0xDF)을 범위로 기술한 것은 부정확하다 — 본 도메인 U+0080..U+00FF에서 실현되는 선행 바이트는 0xC2·0xC3뿐이다 (RFC 3629) | **수용** | S1에서 firstByte 절을 제거하고 길이 법칙만 남겼다. 바이트 값 법칙은 아예 별개 명세로, 본 슬라이스에서는 범위 밖(§Non-Goals 1)으로 분리 |
| 2 | **∨ 비트표기 수정** — 명세식에서 논리합(∨)과 비트 OR 표기가 혼용될 여지가 있었다 | **수용** | S1의 경우 분할은 상호배타적 구간(`≤ 0x7F` / `≥ 0x80`)과 커널 post의 `if code < 128: 1 else: 2` 형태로 기술하고, 비트 연산자 표기는 명세에 사용하지 않는다 |
| 3 | **경로독립 별도축** — "동일 스칼라 값은 어느 이스케이프 경로로 디코딩해도 동일 바이트열"이라는 경로 독립 속성을 S1에 넣는 것은 범위 혼동이다 | **수용** | S1은 `\xHH` 경로(`scanHexEscape`)에만 국소화된다. 경로 독립은 별개 축의 별도 명세다 — `scanUnicode` 경로는 S1의 커널 **추출원**으로만 등장하며, 경로 간 동등성 주장은 하지 않는다 |
| 4 | **커널반증 ≠ 원본직접반증** — 결함 커널의 SAT는 원본 `scanHexEscape`의 직접 정형 반증이 아니다 | **수용** | SAT의 대상은 추출 커널이다. 원본에 대한 주장은 (i) 커널 SAT + (ii) 커널↔원본 최소 diff(`lexer.nim:428-429`의 1행 추출) + (iii) p0d2 런타임 정합 — 이 **우발적(accidental) 근거 체인까지만** 허용한다 (§Non-Goals 6) |
| 5 | **UNSAT 확대금지** — 대조 커널의 UNSAT를 원본의 정합성 증명이나 D2 부존재 증명으로 확대 해석하는 것은 무근거다 | **수용** | UNSAT가 담보하는 것은 "대조 커널이 S1을 전 도메인 [0x00, 0xFF]에서 만족한다"까지만이다. 원본 검증·S1의 일반 참으로의 확대는 금지된다 |
| 6 | **SAT·UNSAT 의미 확인** — 판정 어휘가 모호하게 쓰이지 않았는지 점검 | **확인** | SAT = S1 위반 모델의 존재(반례, 예: code = 0xE9 → 관측 1 ≠ 명세 2) — **반증**. UNSAT = 위반 모델의 부존재(pre를 만족하는 모든 code에서 post 성립) — 증명 후보(`certZ3Candidate`). 본 문서의 기대 판정 표기가 이 의미와 일치함을 확인했다 |

## 범위 밖 (Non-Goals)

1. **firstByte 법칙(바이트 값)** — 2바이트 케이스 선행 바이트 값(0xC2·0xC3 등)의 명세화·검증. S1은 길이만 다룬다.
2. **인코더 출력 행 인증** — `writer.nim:141-146`의 `\xHH` 출력 자체에 대한 정형 명세·검증. 런타임 담당은 p0d2 기록.
3. **원본 `scanHexEscape` 직접 IR 추출** — 제네릭·예외·플래그 경로를 포함한 원본 함수 통째 추출. 본 슬라이스는 1행 동작의 기계적 추출 커널만 사용한다.
4. **왕복 등가성 1급 명세** — `decode(encode(v)) == v` 관계 명세의 1급(파이프라인 네이티브) 도입. 관계는 S1 + 인코더 런타임 기록으로 분해해서만 다룬다.
5. **주체 업스트림 수정** — nim-toml-serialization 저장소에 대한 patch·PR·이슈. 변이는 본 슬라이스 환경(`env/subject_variant/`)에서만 존재한다.
6. **"원본 함수 직접 정형 반증" 주장** — 이 실험이 확립하는 것은 결함 커널의 SAT 반증, 원본과의 최소 diff, p0d2 런타임 관측의 정합으로 이루어지는 우발적 근거 체인까지만이다. 원본 `scanHexEscape`가 정형적으로 반증되었다는 주장은 하지 않는다.

## Amendment — 스펙 표기 변경: if 제거 (2026-10-17)

1차 실행(양 커널 exit 2 거부, `runs/defect.err`·`runs/control.err`)에서 후건의 if-표현식이
외부 스펙 Canon 프론트엔드에서 lossy로 판정됨이 실증됐다: raw parser는
`nkStmtListExpr(nkIfStmt(nkElifExpr…, nkElseExpr…))`를 생성하고 (1) `pnode_to_canon.nim`
`toCanonKind`에 `nkElifExpr`/`nkElseExpr` 매핑 부재, (2) `ast_to_ir.nim:1046`
`convertExprCanon`에 `ckIfStmt` 암 부재(NimNode 프론트엔드 `:465`만 커버) → `markLoss` →
`moUnsupportedDeclKind` → 프론티어 제외. 전건(`and`/비교만)은 무손실 통과.

**대응**: 법칙을 동치 표기로 재작성 — `[0,255]`에서 `1 + (code div 128)`은 분할 법칙
(code<128→1, code≥128→2)과 수학적으로 동치. pre/post와 대조 커널 본문 모두 이 표기 사용.
**S1의 의미는 불변이며 표기만 변경했다.** Axiom 측 if-표현식 커버리지 갭은 본 슬라이스의
실험 발견으로 기록하며(Axiom `src/` 수정은 범위 밖), 개선 후보로 남긴다.
