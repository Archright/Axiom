# 명세 정본 기준 (Spec Baseline) — follow-up 판정의 오라클

판정의 권위는 **명세**다. 참조 파서·다수결이 아니다.
본 문서는 follow-up 판정이 인용할 정본 조항을 고정한다.

출처: `toml-lang/toml` **tag `1.0.0`** (고정) + `main`(= 1.1.0 초안) 병기.
- 1.0.0: https://raw.githubusercontent.com/toml-lang/toml/1.0.0/toml.md
- 1.0.0 ABNF: https://raw.githubusercontent.com/toml-lang/toml/1.0.0/toml.abnf
- main: https://raw.githubusercontent.com/toml-lang/toml/main/toml.md

---

## 1. 이스케이프 시퀀스 — **버전이 판정을 좌우한다**

### TOML 1.0.0 (tag `1.0.0`, line 272-291) — **9개뿐**

```
\b         - backspace       (U+0008)
\t         - tab             (U+0009)
\n         - linefeed        (U+000A)
\f         - form feed       (U+000C)
\r         - carriage return (U+000D)
\"         - quote           (U+0022)
\\         - backslash       (U+005C)
\uXXXX     - unicode         (U+XXXX)
\UXXXXXXXX - unicode         (U+XXXXXXXX)
```

> "All other escape sequences not listed above are **reserved**; if they are used, TOML **should produce an error**."

**→ `\e` 없음. `\xHH` 없음.** 둘 다 1.0.0에서 **예약된(=오류를 내야 하는) 이스케이프**다.

### TOML 1.1.0 (main, `toml.md:285-302`) — **11개로 확장**

```
\b \t \n \f \r \e \" \\ \xHH \uHHHH \UHHHHHHHH
```

ABNF(main)에도 명시: `escape-seq-char =/ %x65 ; e escape U+001B`, `escape-seq-char =/ %x78 2HEXDIG ; xHH`.

### 판정 규칙
| 출력 | v1.0.0 | v1.1.0 |
|---|---|---|
| `\e` | **무효** (예약 이스케이프) | 유효 |
| `\xHH` | **무효** (예약 이스케이프) | 유효 |

→ **writer가 `\e`를 내보내면 v1.0.0 출력은 무효, v1.1.0 출력은 유효.** 반드시 버전을 붙여 판정한다.

---

## 2. 키 — bare key 허용 문자 집합

`toml.abnf` (tag `1.0.0`, line 50):
```abnf
unquoted-key = 1*( ALPHA / DIGIT / %x2D / %x5F ) ; A-Z / a-z / 0-9 / - / _
```

**→ bare key는 `A-Za-z0-9_-`만 허용.** `[`, `]`, `=`, `{`, `}`, `,`, 공백 전부 **무효**. 그 외는 `quoted-key`(basic/literal string)로만 표현 가능.

---

## 3. 키-값 쌍 사이의 개행 — **허용되지 않는다**

`toml.abnf` (tag `1.0.0`, line 26-28, 55):
```abnf
ws      = *wschar
wschar  =  %x20  ; Space
wschar  =/ %x09  ; Horizontal tab
keyval-sep = ws %x3D ws ; =
```

**`ws`는 SP/HTAB뿐이다. 개행(`%x0A`)이 아니다.**
→ `key =\n5`는 `keyval-sep`에 대응하지 않는다 = **무효한 TOML.**

판정: `Toml.decode("key =\n5", ...)`가 **수용되면 명세 위반**이다.

---

## 4. UTF-8 요구사항

> "A TOML file **must** be a valid UTF-8 encoded Unicode document." (Preliminaries)

문자열도 UTF-8이어야 한다. 유효하지 않은 UTF-8을 결과 문자열로 내보내면 위반.

---

## 5. 중복 키 (이미 확정된 것 — B-1 참조)

> "Defining a key multiple times is **invalid**." (§ Keys, tag 1.0.0 line 178)

## 6. 문서 전체 유효성

```abnf
toml = expression *( newline expression )
```
후행이 어떤 production에도 대응하지 않으면 문서는 무효이며, 파서는 거부해야 한다.

---

## 7. 판정 분리 규율 (모든 follow-up에 적용)

- **(A) 명세 위반** — 위 조항에 어긋나는 관측
- **(B) 앱 정책 결함** — 스펙이 규율하지 않는 영역 (예: 미지 키 처리, typed 디코드 정책)
- **절대 병합 금지.** (B)를 (A)로 부르지 않는다.
- 버전 스코프를 붙인다: `\e`/`\xHH` 관련은 **v1.0.0 / v1.1.0을 각각** 판정.
- 오라클은 **명세**다. 참조 파서(tomllib = 1.0.0 전용, tomlkit, rust toml)는 보조 교차일 뿐이다.
