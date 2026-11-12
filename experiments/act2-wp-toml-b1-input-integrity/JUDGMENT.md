# 판정 기록 — Vertical Slice B-1: Typed Decoder Input Integrity

**대상**: `status-im/nim-toml-serialization` @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9`
**범위**: typed 객체 역직렬화 경로의 입력 무결성. **심각한 취약점 자체를 입증하지 않는다.**
**산출**: 재현 가능한 관측 + 명세 대조. CVSS 등급 부여 안 함. upstream 제출 안 함.

---

## 0. 요약

세 시험 전부 예상대로 관측됐다. **두 개의 독립 결함**이 실측으로 확인됐다.

| 결함 | 내용 | 귀속 부위 | 관측 |
|---|---|---|---|
| **(i)** | 바이트 동일 중복키를 거부하지 않고 **적용**(last-wins) | `toml_serialization/private/utils.nim:75-87` wrap-around 재매칭 + seen-set 부재 | T2 Obs-1, Aux-i |
| **(ii)** | 필드가 채워지면 **조기 종료**하고 후행 입력을 **검증하지 않음** | `toml_serialization/reader.nim:334,345-346` + `decoder.nim:46-55`에 EOF 검사 없음 | T2 Obs-2, T3, Aux-ii |

두 결함은 **양방향 독립**이다. 한쪽을 고쳐도 다른 쪽이 남는다.

---

## 1. 산출물 1 — 고정된 소스와 의존성

### 1.1 대상
| 항목 | 값 |
|---|---|
| 저장소 | `status-im/nim-toml-serialization` |
| 커밋 | `4aa8e2223649fc0837c490a4acfca7b8b1e756f9` |
| 워킹 트리 | **불변** (`git status --porcelain` 0건, 실행 전후 확인) |

### 1.2 실제 사용 의존성 (경로 + 해시 — nimblemeta만이 아니라 컴파일러가 연 소스)

| 패키지 | 버전 | vcs rev | 핵심 파일 | sha256 |
|---|---|---|---|---|
| serialization | **0.5.4** | `b5473564e80a4908cf6c5a038e4c4a6ca7de2223` | `serialization/object_serialization.nim` | `049d26ae3e2050e63b788bb0356ac0cf33df70401581c7a00d95a861ced7cd1b` |
| serialization | 0.5.4 | 동일 | `serialization.nim` | `ee248aaa265209da63545a2a5a1479708b008b4d3894eebbe09badcdab72881d` |
| faststreams | **0.5.2** | `059bc2f52546ac14b583639c33372c14b1d46fa3` | `faststreams.nim` | `c3983ebfb4fd6136b3c780637bd335c96d42f2f3debc7b68e0e1b9b7a21b6a85` |
| stew | **0.5.0** | `4382b18f04b3c43c8409bfcd6b62063773b2bbaa` | — | — |

대상 측:

| 파일 | sha256 |
|---|---|
| `toml_serialization/reader.nim` | `9e860006d4a26533beddcd762e21390fb7bafb5cf45ab1547ad96efacff569b5` |
| `toml_serialization/private/utils.nim` | `452da999ac783ed28d369f202616d8f2db26b17ce26f952db0f3e0f04d60896e` |
| `toml_serialization/decoder.nim` | `b39162bf23ecd83e1ebfb9d2d14f7b39c478bc78ce0b4253900167603f71d5bb` |
| `toml_serialization/lexer.nim` | `19d69eed84f74c51fa1784b2e71a4525abc8d2b8aa854c567565d2d603133f4d` |

### 1.3 ⚠️ 버전 격차 — **이전 분석의 오류를 정정한다**

이전 코드 분석은 `serialization-0.2.6`의 `object_serialization.nim`을 읽고 "실제 사용 버전은 0.2.6"이라 결론지었다. **이것은 틀렸다.**

**실측 증거 — 대상은 0.2.6으로 아예 빌드되지 않는다:**
```
toml_serialization/desc.nim(16, 1) Error: type mismatch
Expression: serializationFormat Toml, mimeType = "application/toml", version = 1
Expected one of (first mismatch at [position]):
[3] template serializationFormat(Name: untyped; mimeType: static string = "")
  unknown named parameter: version
```
→ `desc.nim:16`이 `version = 1` 인자를 전달하는데, 0.2.6의 `serializationFormat`에는 그 인자가 없다.

**따라서:**
- **실측 버전 = serialization 0.5.4** (선언 범위 `>= 0.5.3`을 만족하는 유일한 설치본)
- **선언 ≠ 실제 드리프트는 아니다** — 선언 범위 `>= 0.5.3`을 새로 resolve해도 **0.5.4**가 나온다. 즉 선언과 실제 빌드는 **같은 프로그램**이다. 잘못된 것은 "설치된 0.2.6 = 사용된 버전"이라는 이전 추론뿐이다. (`faststreams`는 선언 `>= 0.5.0`, 사용 0.5.2 — 이것도 범위 내. `stew`는 0.2.0/0.5.0 이중 설치이나 자동 탐색이 **0.5.0**을 고른다)
- 0.2.6 관련 정적 도출은 **폐기**한다
- **정적 도출을 0.5.4로 재확인했다** — `object_serialization.nim`에 seen-set 추적 없음:
  - `findFieldReader`(268행): wrap-around 스캔, 두 번째 루프가 `expectedFieldPos`를 **갱신하지 않고** 리더 반환
  - `makeFieldReadersTable`(217행): `field(obj, realFieldName) = readFieldIMPL(F, reader)` **무조건 대입**, 추적 없음
  - `fieldReadersTable`(249행): `const numFields = totalSerializedFields(T)` — `reader.nim:345`의 브레이크 카운트와 동일

→ **정적 도출과 실측이 같은 버전에서 정합한다.** 격차 해소.

**출처 입증 방식**: `nimblemeta.json`만이 아니라 **컴파일러가 실제로 연 소스**를 기록했다 — `strace -f -e trace=%file`로 실제 컴파일을 감싸 30개 파일의 성공적 `.nim` open을 캡처(`env/consumed_files_strace.txt`). 여기서 `serialization/object_serialization.nim` 등 핵심 파일의 절대경로·sha256이 확인된다(`env/dependency_sources.md`). `results`/`unittest2`는 **전혀 열리지 않는다**(nimble 전용 전이 의존성).

### 1.4 필드 카운트 프로브 (매크로 덤프 대체)
`static: doAssert totalSerializedFields == 3` 프로브로 필드 개수·순서를 컴파일 타임에 고정. 매크로 전개 덤프는 불일치 시에만 진단용으로 사용.

### 1.5 빌드 환경
```
nim 2.2.10 (git hash: bfeb3146d1638b39f69007a4ae5a23e23ae4e5ef), Linux amd64
--mm:orc --skipUserCfg --skipParentCfg --skipProjCfg
Toml_v100 flavor, TomlUnknownFields 미사용, un-keyed Toml.decode(input, T)
ulimit -s = 8192
```

### 1.6 재현 위험 요소 (제3자를 조용히 깨뜨린다)
1. **`nimble.lock`이 자동 탐색을 죽인다** — cwd 조상 체인에 `nimble.lock`이 있으면 nimblePath가 비활성화된다. Axiom3 내부에서 컴파일하면 nimble 패키지 **0개**가 해석된다(`lazyPaths: []`, pkgs2 접근 0건). **`/tmp` 등 중립 cwd에서 빌드할 것.**
2. **`env/` 아래 파일은 Axiom3의 `config.nims`를 상속한다** — hermetic bootstrap이 빌드를 가로챈다. → **`--skipParentCfg` 필수.**
3. 중립 cwd에서의 `nim c`도 같은 세트(최신 버전 선택)로 자동 해석된다. 즉 명시적 `--path`와 자동 탐색은 여기서 동치 — 단 **Axiom3 밖에서만**.
4. `--mm:refc`도 동일하게 동작함을 확인했다(프로브 재현). 본 기록의 실측은 `--mm:orc`.

---

## 2. 산출물 2 — 최소 재현 입력

`inputs/`에 저장, `sha256sums.txt`로 바이트 고정 (LF, 말미 개행).

**T2 (중복키 + 조기 종료)** — 순서가 결정적이다:
```
a = "first"
a = "second"
b = "third"
c = "fourth"
```

**T3 (후행 무효 입력)** — 필드를 **다 채운 뒤**여야 한다:
```
a = "first"
b = "second"
c = "third"
!!!
```

**분리 보조**:
- Aux-i (중복 순수 분리): `a = "first"` / `a = "second"` — EOF 브레이크로 종료
- Aux-ii (조기 종료 순수 분리): `a`/`b`/`c` + `d = "x"` — 중복 없음

---

## 3. 산출물 3 — 실제 관측

**결정론 재현 확인**: `repro.sh`를 2회 실행, 원시 출력 바이트 동일.

| 시험 | 예상 | 관측 | 판정 |
|---|---|---|---|
| **T1** 기준선 | 성공, `a=first b=second c=third` | 동일 | **CONFIRMED** |
| **T2 Obs-1** | 성공 + `a=="second"` | 예외 없음, `a=[second]` | **CONFIRMED** |
| **T2 Obs-2** | `c==""` (입력에 `c="fourth"` 존재) | `c=[]` | **CONFIRMED** |
| **T3** | 명세상 거부 | **성공, `!!!` 침묵 무시, exit 0** | **CONFIRMED** (거부 없음) |
| **Aux-i** | 중복 독립 수용 | `a=[second] b=[] c=[]`, 예외 없음 | **CONFIRMED** |
| **Aux-ii** | `d` 미검사 → 오류 없음 | 미지 필드 오류 **없이** 통과 | **CONFIRMED** |
| **대조** T2→`TomlValueRef` | 거부 | `TomlError: (2, 3) duplicate table key not allowed: 'a'` | **CONFIRMED** |

### 3.1 증거의 성격 구분 (관측마다 다르다)

| 관측 | 증거 성격 |
|---|---|
| T2 Obs-1 `a=="second"` | **직접 런타임 증거** — 중복키가 거부되지 않고 값에 적용됨. `"second"`는 2번째 줄에만 있고 `a`에 도달하는 유일한 경로는 중복 매칭·적용 |
| T2 Obs-2 `c==""` | **간접** — 단독으로는 "미제공"과 구별 못 함. **소스의 조기 종료 경로(`reader.nim:345-346`)와 결합해 해석** |
| **Aux-ii** | **Obs-2의 판별 증거** — 루프가 `d`에 도달했으면 `UnexpectedField`가 발동한다. 오류 부재 = `d` 줄이 검사되지 않았음 |
| **T3 성공** | **독립 직접 관측** — 후행 문법 오류가 검출되지 않음. 중복키와 무관한 별개 증거 |

---

## 4. 산출물 4 — 명세 대조 판정

**오라클 = TOML 명세.** 다수결이 아니다. 참조 파서는 교차 확인용.

### 4.1 (A) 명세 위반 — 2건

**A-1: 중복키 수용**

> **"Defining a key multiple times is invalid."**
> — TOML v1.0.0 § Keys, `toml.md` tag `1.0.0` line 178 · https://toml.io/en/v1.0.0

관측: T2에서 예외 없이 `a="second"`로 적용.
위반: 위 조항.

참조 파서 (전부 거부):
| 파서 | 메시지 |
|---|---|
| tomllib 3.12.3 | `Cannot overwrite a value (at line 2, column 13)` |
| tomlkit 0.15.1 | `ParseError: Key "a" already exists. at line 3 col 0` |
| rust toml 0.8.23 | ``duplicate key `a` in document root`` (line 2 col 1) |

**특기 — 참조 구현의 설계 대조**: rust toml의 **typed `toml::from_str::<Cfg>`도 파싱 단계에서 동일 오류로 거부**한다. 즉 참조 구현은 타깃 타입과 무관하게 **문서 전체를 먼저 검증**한다. 이 라이브러리만 typed 경로에서 그 검증을 하지 않는다.

**A-2: 후행 무효 입력 미검증**

> 문서 수준 ABNF: `toml = expression *( newline expression )` (`toml.abnf` line 18)
> 헤더: *"…certain invalid documents would need to be rejected as per the semantics described in the supporting text description."*

관측: T3에서 `!!!` 침묵 무시, 성공 반환.
위반: 문서 전체 유효성 — `!!!`는 어떤 production에도 대응하지 않는다.

참조 파서: tomllib `Invalid statement (at line 4, column 1)`, rust `invalid key` (line 4 col 1), tomlkit `EmptyKeyError`.

**규범 어휘 주의**: 스펙은 RFC 2119 보일러플레이트가 없고 중복키에는 **"invalid"**를 쓴다. 가장 강한 운용 형식은 *"must produce an error at parse time"*이며 이것은 배열-오브-테이블 조항에만 쓰인다. 보고서는 이 어휘 차이를 그대로 기술한다.

### 4.2 (B) 앱 정책 결함 — **명세 위반이 아님 (절대 병합 금지)**

후행 내용이 **유효한 TOML이지만 미지 키**인 경우:
- 스펙은 미지 키·typed 디코드·부분 소비를 **규율하지 않는다** (1.0.0 태그와 main 초안 모두 해당 어휘 0건)
- → **앱 계약의 문제**이지 conformance 위반이 아니다
- 다만 이 라이브러리는 **자기 정책과 모순**이다: 브레이크 **전** 미지 키는 `raiseUnexpectedField`, 브레이크 **후**는 침묵 소거

**판별 규칙**: 후행 내용이 *유효* TOML → (B). *무효* → (A).

---

## 5. 결정론 범위

| 구분 | 항목 |
|---|---|
| **기계 재현** | T1–T3의 accept/reject + T1 필드값 — 바이트+코드+flavor의 순수 함수. `repro.sh` 2회 실행 바이트 동일 확인 |
| **환경 종속** | 스택 고갈 깊이 (후보 A 전용, 본 슬라이스 밖) — 보편 잨계값 금지 |
| **사람 판단 (MANUAL)** | 보안 영향 · 능력-델타 · 오라클과 관측 충돌 시 최종 승인 |

---

## 6. 이 기록이 하지 않는 것

- **CVSS 등급 없음.** 취약점 확정 없음.
- **보안 파급력 미입증.** 이것이 심각한 취약점이라는 주장은 **하지 않는다.** 다음 단계에서 독립 입증해야 한다.
- **upstream 제출 없음.** 제출 여부는 사람이 결정한다.
- 후보 A(스택 고갈) · 인라인 테이블 · 대소문자 모드 · 프래그먼트 조합 · 미지 키 정책은 **범위 밖.**

---

## 7. 재현 방법

```bash
cd experiments/act2-wp-toml-b1-input-integrity
bash bsec/replay.sh verify   # MANIFEST 전수 해시 검증 (inputs 포함, fail-closed)
bash bsec/replay.sh run      # T1/T2/T3 + 분리 보조 + 대조 전체 재실행 + 사례당 바이트 동일성 대조
```

(2026-10-11 통합: 구 `observations/repro.sh`는 `bsec/replay.sh`로 흡수·삭제되었다. 구 드라이버는
`~/.nimble/pkgs2`를 무검증 소비했지만, `run`은 번들 vendor(`bsec/offline/deps.tar.gz`)만 사용한다.)

산출 디렉터리:
- `env/` — 의존성 출처·해시, 툴체인, 필드 프로브
- `inputs/` — 테스트 입력 (해시 장부 = `MANIFEST`)
- `observations/raw/` — 원시 stdout/stderr/exit code + 빌드 명령
- `observations/summary.md`, `bsec/replay.sh`
- `oracle/oracle.md` — 명세 조항 원문 + 참조 파서 실측 + Rust 하니스

---

## 8. B-SEC-03 × nimbus-eth1 판정 세대 투영 (2026-10-12 정정; 파생 문서)

이 절은 P0-D2 3원조 (`bsec/JUDGMENT.md` §2.4) 판정의 **현재 세대**를 정본 원장
`bsec/verdict_generations.tsv`(append-only)에서 투영한 것이다. 이 기록(B-1 슬라이스)의
T1–T3·Aux·대조 판정(§3)은 이 정정의 대상이 아니며 변경되지 않았다. 판정은 사람이 아니라
(관측 튜플 + `bsec/rules/rule_table.tsv`)의 순수 함수가 결정한다 — 재정·override 경로 없음
(recorded == derived, fail-closed).

- **현재 세대 VG-0003 — UNKNOWN** (규칙 R11: present|executes|differs|boundary-unknown →
  UNKNOWN, fail-closed). 3-way 대조는 관측된 두 표면에서 능력 증가를 배제했다 — 원자화
  클레임: **H1a-CORS = NO-GO (표면 한정, VG-0004)**, **H1a-PROC = NO-GO (표면 한정,
  VG-0005)**. 그러나 clientId 이그레스 표면의 보안 의의는 피어 측 런타임 처리에 묶여 있고
  그것은 시험되지 않았다(**H1b-runtime = UNKNOWN, 공백 기록**). 피어 소스 조사
  (**H1b-source**, `p0d2/peer_survey.md`)는 보고형 한정 클레임일 뿐 protection_boundary
  관측이 아니므로 R10의 근거가 될 수 없다.
- **세대 계보 (supersedes 체인 — 같은 lineage 내부)**: VG-0001 UNKNOWN via R11
  (2026-10-11T23:18:52+09:00, commit `1e3abc449`) ← VG-0002 **NO-GO via R10**
  (2026-10-12T01:04:31+09:00, commit `699adcf61` — **선행 취소된 무효 세대**: 피어 소스
  조사를 protection_boundary=neutralizes 관측으로 취급한 설계 밖 사용; widening what a
  rule may conclude is a decision, not an observation — `DEFERRED.md` CAND-A 선례; triples
  값은 `unknown`으로 되돌려짐) ← **VG-0003 UNKNOWN via R11 (현재; VG-0002를 supersedes),
  2026-10-12T09:18:53+09:00**.
- **원장과 투영의 역할 분리**: 과거 세대는 원장에 보존되며 편집·삭제되지 않는다. 이 문서와
  `bsec/JUDGMENT.md`, `bsec/verdicts.md`, `bsec/verdicts_recorded.tsv`는 투영이다 —
  `verdicts_recorded.tsv`의 이유 셀은 현재 세대의 `payload.reason`과 바이트 단위로 일치한다.
- **H2 (생태계 open-set 존재 클레임)**: 판정 행을 만들지 않는다 — **NO-GO는 금지된다**
  (조사된 저장소에서의 부재는 열린 집합을 닫지 못한다; 입증된 영향 1건이면 GO가 된다).
  소비자 열거 밖의 3원조는 미생성(UNKNOWN의 한형)으로 남는다 (`bsec/JUDGMENT.md` §3).
