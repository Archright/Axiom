# P0-D2-G — AGENT SPEC: 정형 검증 대상 후보 선정 및 명세 패키지 (문자열 내부 제어문자 수용)

Experiment: `act2-wp-toml-b1-input-integrity/p0d2g` · Date: 2026-10-17

**출처·방법론**: 본 문서는 SPEC INFERENCE 에이전트의 1차 저작물이다. 입력은 두 독립 블라인드 분석 보고서 `discovery/agentA_raw.md`·`discovery/agentB_raw.md`(verbatim 보존)이며, 후보 풀은 전적으로 이 보고서들에서 취했다. 주체 저장소 `nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9`(read-only)에 대해 **상속 인용을 전수 대조 검증**했고(§11 정정 기록), **컴파일·실행 없이** 정적 분석만으로 작성했다 — 재생 절차의 컴파일 검증은 후속 단계 소관이다. 문체·커널 구도는 선행 슬라이스 [`../p0d2f/SPEC.md`](../p0d2f/SPEC.md)를 따른다. 특히 p0d2f 개정에서 실증된 **프론트엔드 if-표현식 손실 문제**(p0d2f/SPEC.md Amendment)를 반영해, 본 명세의 전건·후건은 `if` 없이 비교·`and`/`or`/`not`만 사용한다.

---

## 1. 후보 풀 채점표

두 보고서에서 추출한 고유 후보 11건(중복 병합, 발견 에이전트 표기). 채점 기준: **C1** 진짜 결함(코드가 저장소 자신의 부합 주장·API 계약을 위반 — 문서만 틀린 doc-stale은 약점), **C2** 형식화 가능성(단일 정수 위의 집합/산술로 결정 속성 기술 가능), **C3** 원본 재생 가능성(pristine 주체 공개 API 호출로 관측), **C4** 차동 대조(같은 명세가 성립하는 형제 입력 존재). ◎ 우수 · ○ 양호 · △ 보통/유보 · ✕ 불충분.

| # | 후보 | 발견 | C1 | C2 | C3 | C4 | 판정 |
|---|---|---|---|---|---|---|---|
| 1 | **문자열 내부 제어문자 수용** — 렉서 거부 집합 `{8,16,31,127}`(단일행)/`{16,31,127}`(멀티라인) vs README v1.1.0 부합 주장(`lexer.nim:554,588` vs `README.md:65`) | A3+B3 | ● | ◎ | ◎ | ◎ | **선정** |
| 2 | **writeKey 특수문자 미인용** — `=` 등을 인용하지 않아 "full spec TOML" 주장(`README.md:44`) 위반 출력(`writer.nim:166-180`) | A7 | ● | ○ | △ | ● | **차점** |
| 3 | **loadFile↔decode tomlCase 배선 불일치** — loadFile 경로가 `init`에 tomlCase 미전달(`decoder.nim:48` vs `:73`) | B4 | ● | △ | ◎ | ◎ | 3위 |
| 4 | **innerValue `dateDimte` 오타** — TomlDate/TomlTime 접근자 브랜치가 컴파일 불능(`value_ops.nim:32,36`) | A4 | ● | △ | ◎ | ◎ | 4위 |
| 5 | **enum 빌트인 writer 문자열 출력** — README "ordinal built-in writer" vs `$value` 출력(`writer.nim:482-484`); 코드+테스트가 일치하고 문서만 틀림 | A2+B1 | △ doc-stale | ○ | ◎ | △ | — |
| 6 | **README fruits 예제가 기본 설정에서 실패** — `fruit2 = 1` 디코드가 기본 플래버에서 raise(`README.md:350-353` vs `reader.nim:134-136,154`); 코드+테스트가 의도적 기본 거부 | B2 | △ doc-stale | ○ | ◎ | ○ | — |
| 7 | **규격 러너 스킵 50건** vs "pass these test suites" 주장(`spec_test/run_test.sh`, 총 `-skip=` 50개; datetime·hex-escape·control 포함) | A1 (B3 일부) | ○ | ✕ | △ | ✕ | — |
| 8 | **후행쉼표 테스트 공허** — 테스트 입력이 `:`에서 먼저 실패해 뒤따름 쉼표를 검사하지 않음(`test_decoder.nim:634-636` vs 기본 플래버 v1.1.0 문서화 동작) | A6 | △ | ○ | ◎ | ◎ | — |
| 9 | **미지 필드 거부의 순서 의존** — `fieldsDone >= totalFields` 조기 break(`reader.nim:345-346`); README가 예외를 명시 약속하지 않아 테스트가 행동을 성문화 | B5 | △ | ○ | ◎ | ◎ | — |
| 10 | **TomlHourMinute 인코더 출력 축약** — 파싱 관용으로 문서화된 플래그가 기본 플래버 출력에서 `:00`을 생략(`writer.nim:88-89` + `format.nim:36`) | B6 | ○ | △ | ◎ | ○ | — |
| 11 | **nimble 0.2.18 vs README "Since v0.3.0"** — 메타데이터 드리프트(`toml_serialization.nimble:4` vs `README.md:54-57`; 태그 최대 v0.2.18) | A5+B7 | △ 메타 | ✕ | ✕ | ✕ | — |

채점표 각 후보의 대표 인용도 주체 바이트와 대조했다(불일치 없음 — 세부 정정은 §11).

## 2. 선정 근거

후보 1은 네 기준을 모두 상위권에서 충족하는 유일한 후보다. 결함의 책임이 코드 쪽에 있다: `README.md:65`가 선언하는 TOML v1.1.0 부합 주장에 대해 렉서는 문자열 내부 바이트를 집합 `{8,16,31,127}`/`{16,31,127}`으로만 검사해 v1.0.0·v1.1.0 공통의 문자열 제어문자 금지를 위반하며, 저장소 어디에도 이 축소 집합을 정당화하는 문서가 없다. 결정적 속성이 단일 바이트 값에 대한 집합 멤버십이므로 BitVec 8 친화적 최소 산술 모델로 축소되고, 반례 관측은 pristine 주체에 대한 `Toml.decode` 호출 한 줄로 정의된다(예외 vs 반환+값 보존). 대조 입력(0x08·0x10·0x7F·탭)에서 코드가 명세와 정확히 일치하므로 보편적 수용이 아니라 누락된 집합 멤버에 국한된 결함임이 입증된다. 게다가 같은 파일의 주석 경로가 정확한 전체 집합(`lexer.nim:75`)을 사용하고, 문자열용 픽스처·단위테스트가 전부 `{0x00,0x10,0x1F,0x7F}`만 검사해 기존 스위트가 이 갭을 구조적으로 못 잡으므로 형식 검증의 한계가정 가치가 가장 크다.

**차점**: 후보 2(writeKey 미인용) — C1·C4는 강하나, 반례 재생에 `TomlValueRef` 테이블 AST의 수동 구성이 필요해 C3이 무겁고, 결정 속성이 "키 문자열에 금지 문자가 존재"라는 존재 정량자를 포함해 C2에서 후보 1보다 크다.

## 3. P (명제)

README가 부합을 선언한 TOML 명세(README.md:65)에서 문자열 내부의 원시 바이트 c가 금지 제어문자면 `Toml.decode`는 실패해야 하는데, 주체의 렉서는 c ∈ {8,16,31,127}(단일행) 또는 c ∈ {16,31,127}(멀티라인)일 때만 실패하므로, 예컨대 원시 0x07을 포함한 문서를 예외 없이 수용하고 그 바이트를 디코딩 값에 보존한다.

## 4. 형식 명세 S2 (pre/post)

```text
S2:  ∀ c ∈ D:  reject(c) = forbid(c)

  D          = { c | (c ≥ 1) ∧ (c ≤ 255) ∧ (c ≠ 10) ∧ (c ≠ 13) ∧ (c ≠ 34) ∧ (c ≠ 92) }
  forbid(c)  = (c ≤ 8) ∨ (c ≥ 10 ∧ c ≤ 31) ∨ (c = 127)
  reject(c)  = (c = 8) ∨ (c = 16) ∨ (c = 31) ∨ (c = 127)
  defect(c)  = forbid(c) ∧ ¬reject(c)
```

- 전건 D의 배제 항은 모델 게이트 밖의 구조 경로다: 10(LF)·13(CR)은 단일행 문자열 종단 검사(`lexer.nim:585-586`), 34(`"`)는 구분자, 92(`\`)는 이스케이프 경로로 빠진다. c=0은 `EOF* = '\0'` 별칭(`lexer.nim:72`)으로 인한 우연 거부 경로라 도메인에서 제외한다(§9).
- `forbid`는 S2가 요구하는 "반드시 거부" 집합이다. 탭(9)은 TOML 문자열 문법상 wschar(%x20/%x09)로 허용되므로 금지 집합에서 제외된다.
- 파이프라인 프라그마 형태(`if` 없음 — p0d2f 개정 교훈; 커널 함수는 bool 반환):

```nim
{.axiom: [
  pre:  (c >= 1 and c <= 255 and c != 10 and c != 13 and c != 34 and c != 92),
  post: (result == ((c <= 8) or (c >= 10 and c <= 31) or (c == 127)))].}
```

- 단일 구체 입력 평가: `defect(7) = true ∧ ¬false = true`(위반), `defect(8) = true ∧ ¬true = false`(충족), `defect(9) = false`(도메인 내 비금지, 충족).

## 5. 모델 명세 (인증 산술 모델)

| 커널 | 정의 | 원본 추출 근거 | 기대 판정 |
|---|---|---|---|
| `d2StringGateReject` (결함 커널) | `func d2StringGateReject*(c: int): bool = (c == 8) or (c == 16) or (c == 31) or (c == 127)` | `lexer.nim:588` — `scanSingleLineString`(`:565`) 루프의 유일한 바이트 분류 게이트의 기계적 추출. 멀티라인 확장은 `:554`. 원본 `lexer.nim` sha256 @`4aa8e22`: `19d69eed84f74c51fa1784b2e71a4525abc8d2b8aa854c567565d2d603133f4d` (동일 커밋 동일 파일 — `../p0d2f/SPEC.md` 커널 표에서 전승) | **SAT** — 반례 c = 7 (reject(7) = false ≠ forbid(7) = true) |
| `d2CommentGateReject` (대조 커널) | `func d2CommentGateReject*(c: int): bool = (c <= 8) or (c >= 10 and c <= 31) or (c == 127)` | `lexer.nim:75` — `invalidCommentChar = {'\x00'..'\x08', '\x0A'..'\x1F', '\x7F'}`의 기계적 추출(사용처 `:224`). 저장소 자신이 인접 텍스트 경로(주석)에 채택한 집합으로, S2의 forbid와 **집합으로 동일** | **UNSAT** — 모델이 전건 D 전체에서 forbid와 동치 |

- **모델 문장**: solver가 추론하는 대상은 정의역 D 위의 한 정수 변수 c에 대한 두 bool 멤버십 함수다 — 결함 커널은 코드의 실제 게이트, 대조 커널은 저장소 자신의 정합 집합이다. 차동 구도는 p0d2f와 동일하다: 결함 커널만 SAT, 대조 커널은 UNSAT여야 하며, 대조 커널에서 SAT가 나면 주체가 아니라 명세 주입의 결함이다.
- **대응 근거(1줄)**: 잘 형성된 문서 `k = "a⟨c⟩b"`에서 문자열 내부 문자 c에 대해 `scanSingleLineString` 루프가 수행하는 유일한 제어문자 판정이 `:588`의 집합 검사이고(구분자·CR/LF/EOF는 `:583-586`의 구조 종료로 별도 경로), UTF-8 검사기는 0x00–0x1F 전체를 수용(`private/utf8_validate.nim:17-18`의 테이블 첫 행 전부 0)하므로 decode의 성공/실패가 정확히 `reject(c)`의 부정으로 결정된다.
- 공개 API 유입 경로: `parseValue`의 `of '\"'` 분기(`lexer.nim:1805-1811`)가 `value = TomlValueRef(kind: TomlKind.String)` 후 `scanString(lex, value.stringVal, StringType.Basic)`을 호출 — `Toml.decode(…, TomlValueRef)`가 곧바로 이 게이트에 도달한다.

## 6. 반례 입력

| 항목 | 값 |
|---|---|
| 입력 문서 | `k = "a\x07b"` — 닫힌 따옴표 사이에 **원시 바이트 0x07(BEL)** 하나(16진: `6B 20 3D 20 22 61 07 62 22`) |
| 모델 출력 | `reject(7) = false` → decode 수용 예측 |
| 명세 요구 | `forbid(7) = true` → `TomlError` 발생이어야 함 |
| defect | `defect(7) = true` — 명세 위반 확정 |

보조 반례(같은 결함의 다른 실현, S2 평가와 동일): `k = """a\x08b"""`(멀티라인, `:554`가 8을 누락 — `reject_multi(8) = false`), `k = 'a\x07b'`(리터럴 문자열, 동일 게이트 `:588`).

## 7. 대조 입력

| 입력 | forbid | reject(코드) | 판정 |
|---|---|---|---|
| `k = "a\x08b"` (원시 0x08) | true | true → raise | **명세 충족** (1차 대조 — 같은 "문자열 내부 제어문자" 가족 내부의 차동) |
| `k = "a\x10b"` (원시 0x10) | true | true → raise | 명세 충족 |
| `k = "a\x7Fb"` (원시 0x7F) | true | true → raise | 명세 충족 |
| `k = "a\tb"` (원시 0x09 탭) | false | false → 수용 | 명세 충족 (비금지 측 — 보편 거부 아님을 배제) |

대조군이 성립하므로 SAT는 "렉서가 문자열 검사를 전혀 하지 않는다"가 아니라 "정확히 {1..7, 11, 12, 14..15, 17..30} ∖ (구조 경로)"의 멤버에서만 나오는 **집합 갭 결함**임이 입증된다.

## 8. 재생 절차 (공개 API — 컴파일 검증은 후속 단계)

하니스가 자체 포함해야 하는 타입 선언: **없다** — `Toml`, `TomlValueRef`, `TomlKind`, `TomlError`는 모두 `toml_serialization` 모듈에서 수출된다(`types.nim:106` `TomlValueRef* = ref TomlValue`, `TomlValue.stringVal*` `:120`). 유일한 추가 import는 16진 관측용 `std/strutils`(선택).

```nim
# replay.nim — pristine 주체에 --path: 만으로 컴파일 (주체 수정 없음)
import toml_serialization

# 반례: 원시 0x07 — 명세는 raise 요구, 결함 모델은 수용 예측
let vCx = Toml.decode("k = \"a\x07b\"", TomlValueRef)   # (A) 예외 없이 반환 ← 위반 관측
doAssert vCx.kind == TomlKind.Table                      # 키 "" → 루트 테이블 반환
doAssert vCx.tableVal["k"].kind == TomlKind.String
doAssert vCx.tableVal["k"].stringVal == "a\x07b"         # 0x07이 값에 보존됨

# 대조: 원시 0x08 — 명세 요구대로 raise
try:
  discard Toml.decode("k = \"a\x08b\"", TomlValueRef)
  doAssert false            # 도달하면 대조도 실패 → 결함의 판별력 상실
except TomlError:
  discard                   # 기대 동작

# 보조 반례(멀티라인 갭)·비금지 대조(탭)
discard Toml.decode("k = \"\"\"a\x08b\"\"\"", TomlValueRef)  # (B) 수용 ← 위반 관측
discard Toml.decode("k = \"a\tb\"", TomlValueRef)            # (C) 수용 — 정상
```

- **컴파일**: `nim c --skipParentCfg --skipUserCfg --path:<주체 루트> replay.nim` — `--skipParentCfg`는 Axiom3 트리 안에서 실행할 때 상위 `nim.cfg` 무결성 후크가 외부 빌드를 가로채는 것을 피하기 위함이다(주체 자체는 구성 개입이 없다).
- **비교 관측치**: (A)·(B)는 **exit 0 + 디코딩 값에 제어 바이트 보존**(명세는 `TomlError` 요구 → 불일치 = 결함), (C)·대조 0x08은 **`TomlError` 발생**(명세와 일치). (A)가 raise로 끝나면 반례가 기각되고, 0x08 대조가 raise하지 않으면 차동 구도 자체가 무효다.
- 본 문서는 이 재생을 실행하지 않았다(범위 교정). 참고(범위 밖, 근거로 미채택): 작성 과정에서 하니스 초안이 우연히 1회 실행되어 (A)의 decode가 예외 없이 반환되는 것이 관측되었으나, 해당 시도는 하니스 형태 단언 결함으로 불완전한 관측이므로 확정 판정은 후속 재생 단계에 맡긴다.

## 9. 가정·범위 한계

1. **S2가 다루지 않는 것**: 키 이름·주석 경로의 행동, 멀티라인 줄바꿈 규칙(LF/CRLF/bare-CR), 이스케이프 시퀀스 유효성, 다중바이트 UTF-8, 위치별 다중 제어문자 조합. 멀티라인 갭(`:554`)은 보조 반례로만 제시하며 1차 모델은 단일행 `:588`이다.
2. **forbid의 출처**: README `:65`가 부합을 주장하는 TOML v1.0.0 ABNF(basic/literal 문자열에서 제어문자 배제, wschar=%x20/%x09만 허용)가 결정 근거며 v1.1.0도 이를 유지한다고 본다 — 단, v1.1.0 초·본문 텍스트의 재대조는 본 슬라이스에서 수행하지 않았다. 대신 **v1.0.0-전용 독해만으로도 위반이 성립**하고(0x07은 v1.0.0에서 이미 금지), 저장소 자신이 `:75`의 주석 집합에 동일 집합을 채택한 점이 외부 문서 해석과 독립적인 내부 정합 근거다.
3. **코드↔모델 대응 중 근거(evidence)만 확보된 부분**: (i) "`:588`이 문자열 내부 문자의 유일한 제어문자 판정"이라는 명제는 루프 구조의 정적 판독 근거이지 형식 증명이 아니다. (ii) UTF-8 테이블 통과는 `utf8_validate.nim:17-18`의 테이블 값 판독이다. (iii) 대조 커널의 UNSAT는 "invalidCommentChar가 forbid와 집합 동일"이라는 구성적 사실이지, 주석 경로 런타임 행동의 검증이 아니다. (iv) c=0(NUL)은 `EOF*='\0'`(`:72`) 별칭 때문에 `:586`에서 **우연히** 거부되는 유일 도메인 외점이라 전건에서 배제했다 — 이 배제 자체도 코드 판독 근거다.
4. **관측 계약**: 반례/대조의 런타임 관측치는 후속 재생 단계가 확정한다. 본 문서의 기여는 인용이 검증된 명세와 기대 판정(SAT/UNSAT)뿐이다.

## 10. 근거 원장 (양측 인용 원문 — 전 항 주체 바이트 대조 완료)

**주장 측 (README)**:
- `README.md:64-66` — `## Spec compliance` / `nim-toml-serialization implements [v1.1.0](https://github.com/toml-lang/toml/releases/tag/1.1.0)` / `TOML spec and pass these test suites:` (`:68-69` iarna·burntsushi 나열)
- `README.md:43` — `Encode Nim data types into a **subset** of TOML.`(인코더는 subset임을 스스로 인정 — 디코더 부합 주장과의 비교 대조)

**코드 측 (결함)**:
- `lexer.nim:588-589` — `    if ord(next) in {8, 16, 31, 127}:` / `      raiseInvalidChar(lex, next)` (단일행, `scanSingleLineString` `:565` 내부)
- `lexer.nim:554-555` — `    if ord(next) in {16, 31, 127}:` / `      raiseInvalidChar(lex, next)` (멀티라인, `scanMultiLineString` `:468` 내부)
- `lexer.nim:583-586` — `if next == delimiter: break` / `if next in {CR, LF, EOF}:` / `raiseTomlErr(lex, errUnterminatedString)` (구조 종료 경로 — 전건 배제 근거)
- `lexer.nim:72` — `  EOF* = '\0'` (NUL 우연 거부 경로)
- `lexer.nim:1805-1811` — `of '\"':` / `advance(lex)` / `value = TomlValueRef(kind: TomlKind.String)` / `discard scanString(lex, value.stringVal, StringType.Basic)` (공개 API 유입 경로)
- `private/utf8_validate.nim:17-18` — `const utf8Table = [` / `  0'u8,0,0,…,0, # 00..1f` (0x00–0x1F 전체 수용)

**코드 측 (저장소 자신의 정합 집합 — 대조 커널·결함성 시증)**:
- `lexer.nim:75` — `  invalidCommentChar = {'\x00'..'\x08', '\x0A'..'\x1F', '\x7F'}` (S2의 forbid와 집합 동일)
- `lexer.nim:224` — `        elif next in invalidCommentChar:` (주석 경로 사용처)
- `writer.nim:131-134` — `proc writeValue*(w: var TomlWriter, s: string)` / `lowEscape = {'\0'..'\31'} - {'\b', '\e', '\f', '\n', '\r', '\t'}` / `highEscape = {'\127'..'\255'}` (인코더는 이 바이트들을 항상 이스케이프 — 디코더가 수용하는 문서는 인코더가 스스로 출력하지 않는 형태)

**테스트·픽스처 측 (스위트가 갭을 못 잡는 근거)**:
- `tests/test_decoder.nim:618-632` — `test "invalid chars in comment":` 블록(`# com\x00ment`, `\x08`, `\x0A`, `\x1F`, `\x7F` — **주석만** 검사)
- `tests/test_lexer.nim:264-265` — `expect TomlError:` / `testBasicString("hello\b", "hello\b")` (문자열 내용 검사는 0x08뿐 — 거부 집합 안의 멤버)
- `tests/test_lexer.nim:721-725` — `test "control char not allowed in comments":` / `testComment("# TOML \x01 doc\n[miaw]", '[')` (0x01도 주석에서만)
- `tests/tomls/iarna/invalid/string-basic-control-{1,2,3,4}.toml` — hexdump: 각각 `a = "null\x00"`, `a = "ctrl-P\x10"`, `a = "ctrl-_\x1F"`, `a = "0x7f\x7F"` — 픽스처의 제어 바이트가 정확히 **{0x00, 0x10, 0x1F, 0x7F} = 거부 집합 멤버뿐** (멀티라인 control-1/2 = 0x00/0x10 동일 구조) → 스위트는 갭 멤버(예: 0x07)를 영구히 검사하지 못함

## 11. 발견 보고서 대비 정정·주해 기록

1. **agentA 후보 3 위반 집합 오탈자**: 보고서의 단일행 위반 집합 표기 `{0x01..0x07, 0x0B, 0x0C, 0x0E..0x15, 0x17..0x1E}`에서 **0x16(22)이 누락**되어 있다 — 22 ∉ {8,16,31,127}이므로 위반 멤버가 맞다. 정정: 위반 멤버는 {1..7, 11, 12, 14, 15, **17..30**}이되, 10(LF)·13(CR)은 구조 경로(`:585-586`)라 반례 대상에서 제외.
2. **agentB 후보 1 README 범위**: `README.md:322-327` → 실제 주장 범위는 `:321-327`("ordinal built-in writer" 문장은 `:323`, "ordinal = TOML integer"는 `:327`). 경미.
3. **agentA 후보 1 스킵 블록 귀속**: v1.0.0 블록(47-64)과 v1.1.0 블록(73-108)의 개별 스킵 귀속이 두 보고 간 상이하다(예: `invalid/control/bare-cr`는 검증상 `run_test.sh:100`). 채택한 사실은 총계(파일 내 `-skip=` **50개**)와 대표 라인(`:77-81` datetime군, `:98` hex-escape, `:100-102` control군)뿐이다.
4. **c=0(NUL) 처리**: agentA의 "NUL only raises accidentally" 서술은 `lexer.nim:72` + `:586`로 검증됐고, 이를 모델 정의역 배제 사유로 형식화했다(§4 전건, §9-3).
5. **그 외**: 채점표·원장에 채택된 모든 인용(`lexer.nim:75/554/588/1805-1811`, `writer.nim:131-134/166-180/225-234/466/482-484/88-89`, `value_ops.nim:29-36/86-87`, `decoder.nim:48/73/77`, `reader.nim:134-136/152-154/324-325/345-346`, `format.nim:28-36`, `test_decoder.nim:303/338-345/592-598/618-632/634-636`, `test_lexer.nim:264-265/721-725`, `test_encoder.nim:196-208`, `test_toml_v110.nim:61-68`, `test_features.nim:276/347-351/398-401`, `test_spec.nim:70-73`, `toml_serialization.nimble:4`, `README.md:39-58/82/187-194/321-336/350-362`, `spec_test/run_test.sh`, 픽스처 hexdump, 태그 v0.2.18, 커밋 62dcb2c·096659b)는 주체 바이트와 일치했다. agentA의 `lexer.nim:714-715`(`scanName`의 `notin {'a'..'z','A'..'Z','0'..'9','_','-'}` → `raiseIllegalChar`)도 확인 — 후보 2의 "자기 렉서가 재파싱 거부" 근거로 유효.
