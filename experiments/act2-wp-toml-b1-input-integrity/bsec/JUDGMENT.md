# B-SEC 판정 기록 — 외부 소비자 보안 영향 (GO / NO-GO / N/A / UNKNOWN)

**주체**: `status-im/nim-toml-serialization` @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9` (읽기 전용)
**기반 슬라이스**: Vertical Slice B-1 typed decoder input integrity (`../JUDGMENT.md` — 실행 입증된 결함 2건)
**판정 단위**: (결함 × 소비자 × 공격자 모델) 3원조
**운용**: `replay.sh judge`가 관측 튜플 + 규칙 테이블(`rules/rule_table.tsv`)로 판정을 **재유도**한다. 사람이 쓴 판정문 재독은 재유도가 아니다 — 본 기록의 판정은 `verdicts_recorded.tsv`에 보존되며, 스크립트는 이를 **교차 검증**할 뿐 입력으로 쓰지 않는다. 판정 세대의 **정본 원장은 `bsec/verdict_generations.tsv`(append-only)**다 — `verdicts_recorded.tsv`와 본 문서는 각 lineage의 **현재 세대 + 선행 취소 체인**을 투영한 파생 문서다 (2026-10-12 D2 정정; 불변식 recorded == derived, fail-closed, 재정 경로 없음).
**금지**: CVSS·심각도 평가 없음. upstream 이슈 제출 없음. 증거가 입증하지 않는 영향은 주장하지 않는다.

---

## 0. 판정 요약 (3원조)

| 3원조 | 판정 | 핵심 근거 |
|---|---|---|
| **B-SEC-01 × nph** × "공격자가 `.nph.toml`을 쓸 수 있다" | **NO-GO** | 구조적 동치: 모든 결함 입력이 **유효한 설정**으로 재현됨 (C0–C12 바이트 기록; 능력 증가 0) |
| **B-SEC-02 × nph** × "공격자가 로드되는 `.toml`을 제어" | **UNKNOWN** | 도달 가능한 소비자 미발견; 해석 핀 `b5b387e6`은 SIGSEGV 형태(`71ed139`) **이전** |
| **B-SEC-02 × ImThemes** × 동일 | **UNKNOWN** | lock 체인 해석 핀 `b5b387e6`(2025-09-25)는 71ed139 이전 — 핀에서 형태 부재; 생태계 노출 미결정 |
| **B-SEC-03 × nph** × "공격자가 테마/설정 입력 제공" | **N/A** | **호출부 아티팩트 `evidence/callsite.md` 확보.** 해석 리비전 `b5b387e6`에서 `TomlHexEscape` 게이트(`lexer.nim:391-392`)가 결함 삽입(`:431`) **이전에** 오류 → 결함 경로 미실행. 정적(무 `format.nim`, `flags={}`) + 동적(`\x45`/`\x80` 거부) 양쪽 증거. 규칙 R1. **범위 조건**: nph는 lockfile 부재 → 신규 in-range 태그 출현 시 freshness RE-EVALUATE (반사실 `4aa8e22`는 같은 "0.2.18" 문자열인데 수용) |
| **B-SEC-03 × ImThemes** × 동일 | **N/A** | **호출부 아티팩트 확보** — 소비자 `Patitotective/ImThemes @ d67592d`, lock 고정 dep `b5b387e6`(nimble.lock vcsRevision). 동일 게이트로 결함 경로 미실행. 규칙 R1. **범위 조건**: lock 재해석 시 freshness RE-EVALUATE |
| **B-SEC-03 × nimbus-eth1** × "공격자가 `--config-file` TOML을 쓸 수 있다" | **UNKNOWN** | 현재 세대 **VG-0003** (규칙 R11, fail-closed; 정본 원장 `bsec/verdict_generations.tsv`). P0 3-way 대조 (`p0d2/experiment.md`, 핀 `73529768` vendor 서브모듈): **긍정 발견** — devp2p Hello clientId 와이어 lone `0x80` 배출(결함 없는 입력 도달 불가) + **부정 발견** — CORS 능력 증가 없음(결함 ≡ 대조, 동일 Http403; 원자화 클레임 H1a-CORS = NO-GO 표면 한정, VG-0004) + 프로세스 상태 동일(H1a-PROC = NO-GO 표면 한정, VG-0005). 미검증 경계: 피어 측 수용 처리 — 런타임 미시험(H1b-runtime 공백) → 규칙 R11 (§2.4 판정 + 세대 투영) |

NO-GO를 강제 승격하지 않는다. 미조사 잔여는 UNKNOWN이다. **UNKNOWN은 "안전"이 아니라 "미결정"이다.**

**판정 어휘 (2026-10-11 정정; 구속 부호 = `rules/rule_table.tsv` 헤더):**
- **GO** — 진술된 공격자 모델 하 + 실제 소비자 경로에서 보안 영향 재현.
- **NO-GO** — 진술된 경로·영향 가설의 범위가 **시험되었고** 관측이 보안 영향 주장을 뒷받침하지 않음. **범위화된 판정이지 "영향 없음"/생태계 안전의 증명이 아니다.** 유효 대조 입력 1건 + fail-closed 관측으로는 시험 범위 밖의 가능한 영향을 배제하지 못한다 — 범위 밖은 전부 UNKNOWN으로 남는다.
- **N/A** — 증거가 이 정확한 소비자 AND 버전에서 경로 도달 불가를 확인 (호출부 아티팩트 필수).
- **UNKNOWN** — 도달 가능성·공격자 통제·영향이 불충분하게 확립됨.

---

## 1. 결함 정의 (기반 — B-1 슬라이스에서 실행 입증됨, 본 기록은 재증명하지 않음)

| 결함 | 메커니즘 | 귀속 부위 | 실행 증거 |
|---|---|---|---|
| **B-SEC-01** (B-1 쌍) | (i) 바이트 동일 중복키 거부 없이 적용(last-wins) + (ii) 필드 충원 시 조기 종료, 후행 입력 미검증 | `toml_serialization/private/utils.nim:75-87`, `toml_serialization/reader.nim:334,345-346`, `decoder.nim:46-55` | `../JUDGMENT.md` T2/T3/Aux + 본 번들 `offline/observations/` (`replay.sh run`이 매 실행 재관측 + 바이트 동일성 대조) |
| **B-SEC-02** | 부재 키 typed `TomlValueRef` 접근자 — nil 역참조, SIGSEGV(139), catch 불가, 선언된 `raises: [KeyError]` 불발 | `toml_serialization/value_ops.nim:87 → innerValue:16` | `../followup/defects3/report.md` (HEAD에서 관측); **형태 도입 = `71ed1393853a1fa5d8c47d12fbf9400e15a7970c`** (2026-06-14, "Add raises" #105, value_ops.nim 포함) |
| **B-SEC-03** | `\e`/`\xHH` 이스케이프 — writer는 `\e`를 무조건 배출(v1.0.0 출력 무효), reader는 `\e` 무조건 수용, `\x`는 `TomlHexEscape` 플래그 게이트 | `lexer.nim:420-421`(`\x` 게이트), `lexer.nim:438`(`\e` 무게이트), `format.nim` flavor 바인딩 | `../followup/writer/report.md`, `../followup/utf8/report.md`, `../followup/SPEC_BASELINE.md` §1 |

---

## 2. 3원조 판정 본문

각 3원조: (1) 호출부 증거 → (2) 공격자 모델(능력 비용 별도 필드) → (3) 효과 관측 + 대조 실험 → (4) 판정 + 이유 + 범위 조건.

### 2.1 B-SEC-01 × nph × "공격자가 `.nph.toml`을 쓸 수 있다" — **NO-GO**

**1. 호출부 증거** (`offline/callform/consumer_nph.txt`):
- 소비자: `arnetheduck/nph`; **소비자 커밋 = `2cacf6cc28116e4046e0b67a13545af5c4e756bd`** (신규 GitHub 클론 재검증, 2026-10-11; `--version` = `prerelease-0-g2cacf6c`).
- **해석된 의존성 커밋 = `b5b387e6fb2a7cc75d54a269b07cc6218361bd46`** (nph 설치 스냅샷 nimblemeta vcsRevision; pkgs2 설치 디렉터리 해시 `76ae1c2a`). **안정성 경고**: nph 선언 `">= 0.2.18 & < 0.3.0"`은 `4aa8e22`(2026-09-11)도 매칭하며 그 리비전의 기본 flavor는 `TomlHexEscape`를 포함한다 — **같은 `"0.2.18"` 문자열, 다른 보안 동작**이 실행으로 입증됐다(`evidence/probes/probe_head_profile`). 해석 커밋은 스냅샷에 대한 관측이지 선언 범위의 속성이 아니다.
- 호출형: `src/nph.nim:103` `Toml.loadFile(configFile, NphConfig)` — un-keyed typed 디코드, 플래그 인자 없음; 설정 기본값 `.nph.toml` (`src/nph.nim:320`). CI 래퍼: `arnetheduck/nph-action@v1`가 PR 체크아웃에서 `./nph .` + `git diff --exit-code` (`action.yml:42-49, :58-64`).
- 호출부 조사 아티팩트: **있음** — `capdelta/capdelta.md` (신규 클론 재검증), `link_b_consumer/raw/` C0–C12 (바이트 기록), `link_a_flavor/` (flavor 전이 확인).

**2. 공격자 모델** (영향 서술 **이전**에 진술):
- **능력**: 저장소 내 `.nph.toml` 파일 생성/수정 (PR 콘텐츠).
- **신뢰 경계**: PR 제출자는 콘텐츠 작성 권한이 이미 있음; formatter·CI는 그 콘텐츠를 실행·판정.
- **능력 비용 (별도 필드)**: `.nph.toml` 작성 ≡ `.nim` 작성과 **동일한 커밋 권한** — 추가 능력 취득 비용 0.
- **이 모델 하에서 목표 능력**: 유효한 설정으로는 얻을 수 없는 동작을 결함 입력으로 유발.

**3. 효과 관측 + 대조 실험** (`capdelta/capdelta.md` — 신규 클론에서 C0–C12 전례 재실행, 바이트 기록):
- **dead-code 재검증** @ `2cacf6cc`: `src/nph.nim:429`의 `matchesFilters`는 short-circuit으로 **평가되지 않음**(`:327/:334/:370`이 모든 infile을 `explicitFiles`에 삽입). `exclude`/`extend-exclude`/`include` = **dead code**; 유일한 live 필드 `color`는 `--diff` ANSI 장식뿐이고 nph-action은 `--diff`를 쓰지 않음(`:58-64`).
- **3자 대조** (결함 입력 vs 유효 설정 vs 기준선 — 실측, 전부 바이트 동일):
  - C1(중복 `exclude`) ≡ C2(유효 단일) ≡ C0(기준선)
  - C3(`color` t+f 중복) ≡ C4(`color=false`); C5(f+t) ≡ C6(`color=true`) — **양방향 last-wins, 제3 상태 없음**
  - C7(4필드+`!!!`+`[[attacker_table]]` 가비지) 출력 ≡ C8(유효 절단 문서); **C10b**(3필드+`!!!`)는 `Warning` 후 거부 — 후행 바이트가 도달하는 메커니즘 증명(조기 종료가 스킵함)
  - C10 ≡ C11 ≡ C12 in-place: touched-file 목록·결과 바이트 동일
- **보호 경계 실측**: nph-action이 판정하는 트리는 **공격자 자신의 PR 콘텐츠**; CODEOWNERS 없음(채택 5곳 + nph 저장소 자체 재검증 empty).

**4. 판정: NO-GO.** 이유: 결함은 라이브러리 수준 계약 위반이 맞으나(TOML 1.0.0 중복키 금지, strict 디시리얼라이저 보증 무력화 — `../JUDGMENT.md` §4), 이 소비자에서 **능력 증가 0**. 동치는 구조적(config 데이터 모델 = 단순 덮어쓰기)이라 리비전 불변 — C0–C12가 실측으로 고정.
**범위 조건**: (a) nph 의존성 해석은 범위 내에서 이동 가능 — B-SEC-03과 결합한 활성화 질문은 본 3원조 범위 밖; (b) 채택처 조사는 전수가 아니다; (c) 다른 소비자로의 확산 금지(생태계 잔여 = UNKNOWN).

### 2.2 B-SEC-02 × nph / B-SEC-02 × ImThemes — **UNKNOWN** (양자 모두)

**1. 호출부 증거**: 소비자 핀 — nph = `2cacf6cc…` → **의존성 해석 `b5b387e6`**(2025-09-25); ImThemes = 소비자 커밋 `d67592d…`(기록됨 — `evidence/callsite.md` + GitHub API/lock 체인; 본 문장의 구판 "UNRECORDED" 표기는 스냅샷이 앞선다) → lock 체인 niprefs `0.3.5 @ 30f522ac…` → **의존성 해석 `b5b387e6`**.
**2. 공격자 모델**: "공격자가 로드되는 `.toml`을 제어"(테마/설정 파일 주입). 능력 비용: 파일 쓰기 권한(앱별 상이 — 미조사).
**3. 효과 관측 + 대조**: 결함 관측은 HEAD(`4aa8e22`)에서 존재(`followup/defects3` — SIGSEGV 139, debug·release 공통, `except Defect` 무효; 대조: 배열 경로는 깨끗한 IndexDefect). 그러나 **SIGSEGV 형태는 `71ed139`(2026-06-14, #105)에서 도입** — **두 소비자의 의존성 해석(`b5b387e6`)보다 뒤**다. 핀에서 형태 부재(이제 두 소비자 모두 해석 커밋이 기록됨) + `value_ops` 접근자 사용의 호출부 아티팩트 부재 + 도달 가능한 소비자 미발견 → 3자 대조가 성립하지 않는다.
**4. 판정: UNKNOWN.** 이유: 도달 가능한 소비자 없음(알려진 2 소비자의 해석 핀은 형태 이전). 범위 조건: (a) 형태 도입 커밋 귀속은 git 이력 기록에 근거(실행 재입증 안 함); (b) 알려진 2곳 외 생태계는 미조사 — 발견 시 각각 신규 3원조; (c) `value_ops` 접근자(`import toml_serialization/value_ops`) 도달성은 소비자별 호출부 조사 아티팩트가 필요하며 현재 없음(callsite_artifact=absent).

### 2.3 B-SEC-03 × nph / B-SEC-03 × ImThemes — **N/A** (호출부 아티팩트로 입증된 경로 미실행)

**1. 호출부 증거**: nph — 해석된 의존성 커밋 `b5b387e6` (§2.1; 단 선언 범위 내 이동 가능); ImThemes — lock 체인 경유 `b5b387e6`, 호출형 `src/browseview.nim:193` `Toml.loadFile(path, TomlValueRef)["themes"].getTables()` (value-tree 경로, 플래그 없음).
**2. 공격자 모델**: "공격자가 테마/설정 입력을 제공"하며 그 입력이 `\xHH` 이스케이프를 포함. 능력 비용: 입력 파일 쓰기 권한.
**3. 효과 관측 + 대조** — **동적 + 정적 + 반사실 3층** (`evidence/probes/` + raw 로그):
- **동적 음의 결과 (nph의 실제 호출형, 해석 리비전 `b5b387e6`)**: `probe_nph_profile` — `\x45`, `\x80` 모두 **REJECTED** ("invalid hex escape, not supported by standard, please use `TomlHexEscape`") → **TomlHexEscape 비활성**.
- **동적 음의 결과 (ImThemes의 실제 호출형, lock 체인 경유 `b5b387e6`)**: `probe_imthemes_profile` — `\x45`, `\x80` 모두 **REJECTED** → **비활성**.
- **반사실 (`probe_head_profile` @ `4aa8e22` — 같은 `"0.2.18"` 문자열)**: 두 호출형 모두 **OK**(수용) → 활성화는 **문자열이 아니라 해석 리비전의 속성**이다. 버전 문자열 비식별성이 실행으로 입증됐다.
- **정적 핀 사실 (재검증 완료)**: `b5b387e6`에서 `format.nim` 부재, `TomlReader.init` 기본 `flags={}`, `scanHexEscape` 플래그 게이트(`lexer.nim:391-392`).
**4. 판정: N/A** (규칙 R1: present|not_used|*|*|present — 호출부 아티팩트 필수, 확보됨; §0 표 및 `verdicts_recorded.tsv` 동일). **기록된 해석 리비전에서 결함 경로가 실행되지 않음**이 정적+동적으로 확보됐다: 해석 핀 `b5b387e6`에서 `TomlHexEscape` 게이트(`lexer.nim:391-392`)가 결함 삽입(`lexer.nim:431`) **이전에** 오류 — nph의 실제 호출형 프로브(`probe_nph_profile`)와 ImThemes의 실제 호출형 프로브(`probe_imthemes_profile`) 모두 `\x45`/`\x80`를 게이트 메시지로 거부한다. 다만 활성화는 소비자의 속성이 아니라 **해석 시점의 속성**이다 — 반사실 프로브(`probe_head_profile` @ `4aa8e22`, 같은 "0.2.18" 문자열)는 수용한다. 따라서 이 N/A는 **해석 커밋에 묶인다**: nph의 신규 in-range 태그 / ImThemes의 lock 재해석 시 freshness RE-EVALUATE이며, 그 시점의 반사실 값은 활성화다. REACHABLE 주장 없음. (2026-10-12 정정: 구판 본 단락의 "판정: UNKNOWN"은 호출부 아티팩트 확보 **이전** 문구가 남은 것으로, §0·헤딩·정본 기록의 N/A와 모순이었다 — 원장 `bsec/verdict_generations.tsv`는 이 두 3원조를 별도 lineage로 다시 쓰지 않는다; N/A 판정의 근거는 `evidence/callsite.md` + 프로브 로그에 보존된다.)
**범위 조건**: U+0080 인코딩 프레이밍 — `\xHH`=`U+00HH`, TOML 문자열은 Unicode 스칼라열이므로 이것은 **UTF-8 인코딩 무결성** 질문이다(`followup/SPEC_BASELINE.md` §4). v1.0.0에서 `\x`는 예약 이스케이프(=오류여야), v1.1.0에서 유효 — 버전 스코프 필수. writer의 `\e` 무조건 배출은 별도 신뢰 경계(리라이트 파이프라인 — plan Out-of-Scope)다.

### 2.4 B-SEC-03 × nimbus-eth1 — **UNKNOWN** (P0 3-way 소비자 대조)

**1. 호출부 증거**: 소비자 `status-im/nimbus-eth1`; 디코드 형태 = nim-confutils `addConfigFile` → `loadFile(Toml, path, SecondarySources)`, 플래그 인자 없음 → reader가 `Toml_v110_Flags`(`TomlHexEscape` 포함)를 강제 병합. 핀: 핀 추출 앵커 소비자 커밋 `0c023085…`(2026-07-04) — 판정 시점 upstream master `97d1f982…`도 동일 서브모듈 sha 확인 → **`vendor/nim-toml-serialization` 서브모듈 = `73529768ced1…`** (`p0d2/target.md` §Consumer identity).
**2. 공격자 모델**: "공격자가 `--config-file`로 로드되는 TOML을 쓸 수 있다"(로컬 연산자 구성). 능력 비용: 구성 파일 쓰기 권한.
**3. 효과 관측 + 대조** — 3-way (baseline / defect `\x80`/`\xE9` / defect-free contrast `\u0080`), 동일 고정 환경 (`p0d2/experiment.md` + `p0d2/raw/`; 2회 cold replay 바이트 동일). 두 발견을 **원문 그대로** 기록한다 — 하나만 골라 인용하는 것을 금지한다:

> **긍정 발견 (wire-byte delta)**: "**devp2p Hello `clientId` egress: YES.** The defect input's wire byte string (`87 6E 69 6D 62 75 73 80`) contains a **lone `0x80`**, which the defect-free contrast cannot produce: every decoded string reachable from defect-free TOML input is well-formed UTF-8 (established in the parent proof, and re-observed here — the same intended value encodes as `C2 80`). No valid config makes this node put that byte string on the wire; the defect input does."

> **부정 발견 (CORS — as-is 기록)**: "**CORS `sameOrigin`: NO.** Defect and contrast produce the **identical** decision (Http403). The appended bytes land in the parsed Uri's port in both cases, so neither can match a browser Origin. No capability increase on this path — both are equally (over-)restrictive relative to the baseline's allow." / "The CORS result is a **negative** finding recorded as-is: on that path the defect adds no new capability beyond what a valid (escape-carrying) config already reaches."

- 프로세스 상태: 3케이스 모두 decode SUCCESS, exit 0 — 프로세스 상태 차이 없음.

**4. 판정: UNKNOWN** (규칙 R11: present|executes|differs|boundary-unknown → UNKNOWN, fail-closed). 와이어 델타의 보안 의의는 다음 **미확보 증거**에 묶여 있다 — **peer-side handling of an ill-formed devp2p Hello clientId** (원문: "No claim is made about what a devp2p **peer** does with a clientId containing a lone `0x80` (peer-side parsing/rejection was not tested)."). 부정 발견(CORS)을 이유로 NO-GO로 내리지 않고, 긍정 발견(와이어 델타)을 이유로 GO로 올리지도 않는다.

**5. 판정의 세대 투영 (2026-10-12 정정; 정본 = `bsec/verdict_generations.tsv`, append-only)**. 이 3원조의 판정은 정본 원장의 **현재 세대**에서 투영된다 — 과거 세대는 원장에 보존되며(편집·삭제 금지) 이 문서는 투영일 뿐이다. 같은 lineage 내부의 supersedes 체인:

| 세대 | 판정 | 규칙 | 입력 튜플 boundary | 기록 시각 (at) | 비고 |
|---|---|---|---|---|---|
| VG-0001 | UNKNOWN | R11 | unknown | 2026-10-11T23:18:52+09:00 (commit `1e3abc449`) | 최초 세대 — 경계 미확정, fail-closed |
| VG-0002 | NO-GO | R10 | **neutralizes** | 2026-10-12T01:04:31+09:00 (commit `699adcf61`) | **선행 취소된 무효 세대** — 피어 소스 조사를 protection_boundary 관측으로 취급한 설계 밖 사용 |
| **VG-0003 (현재)** | **UNKNOWN** | R11 | unknown | 2026-10-12T09:18:53+09:00 | 경계 미확정 — fail-closed; VG-0002를 supersedes |

- **VG-0002가 무효인 이유 (기록됨, 재발 방지)**: R10 `neutralizes`의 설계 의도는 **실측된(live-observed) 보호 경계**다(선례: nph-action이 공격자 자신의 PR 콘텐츠를 판정 — `capdelta/capdelta.md` §4). "일부 코드 경로에서 보안 관련 소비자를 찾지 못한" 읽기 전용 **소스 조사**는 보호 메커니즘이 아니며, 규칙이 결론할 수 있는 것을 넓히는 것은 관측이 아니라 **결정**이다 (`DEFERRED.md` CAND-A 선례). 해당 triples 값(`bsec/offline/consumers/triples_facts.tsv`)은 `unknown`으로 되돌려졌고 → R11 → UNKNOWN.
- **불변식**: **recorded == derived**, fail-closed. 판정은 (관측 튜플 + 규칙 테이블)의 순수 함수이며 사람 재정·override 경로는 없다 (`docs/spec/productization_contract.md` — "the verdict is decided by a pure function, never by a human"). `verdicts_recorded.tsv`의 이유 셀은 현재 세대 VG-0003의 `payload.reason`과 **바이트 단위로 일치**해야 한다. (구판 문장 "UNKNOWN 유지가 기록 값이다 — `verdicts_recorded.tsv` 동일"은 2026-10-12 01:04에 verdict 열만 NO-GO로 변경되어 본문과 모숕인 상태가 존재했고, 이 정정으로 해소됐다.)
- **H1b-source (보고형 한정 클레임 — 판정 행 아님)**: 피어 구현 **소스 조사**(`p0d2/peer_survey.md`, refs pinned 2026-10-12: go-ethereum·Nethermind·Besu·Erigon·nimbus-eth1 수신 경로 + devp2p spec `rlpx.md`)가 **확립한 것**: 조사된 커밋의 조사된 경로 한정에서 ill-formed clientId는 보안 관련 결과를 바꾸지 않는다(깨끗한 음성; 3개 이름 파생 dispatch 지점 모두 trailing `0x80`에 불변). **포함하지 않은 것**: Reth·Grandine·기타/비공개 클라이언트, 라이브 피어 실행, Erigon RPC 표면 일부, Besu `PeerClientName` 미조사 모듈(플러그인 가능), 비공개 보안 보고.
- **H1b-runtime (공백 기록 — 판정 행 없음)**: 피어 측 **런타임** 수용 처리는 시험되지 않았다 → **UNKNOWN, NOT tested**. 행으로 판정을 주장하지 않고 공백으로 명시 기록한다 (VG-0003의 missing-evidence 항과 동일).
- **H2 (생태계 open-set 존재 클레임 — 행 금지, 보고서에만 기록)**: "소비자 생태계 어딘가 영향이 존재하는가"는 열린 집합에 대한 존재 클레임이다. **NO-GO는 금지된다** — 조사된 저장소에서의 부재는 집합을 닫지 못하고, 입증된 영향 1건이면 GO가 된다. 열거된 소비자 집합 밖의 3원조는 존재하지 않는 것이 아니라 **미생성**(UNKNOWN의 한형)이다 (§3).

**원자화된 클레임 (claim atomization — 각 행은 `bsec/verdict_generations.tsv`의 독립 lineage; scope selector는 정확히 자신의 하나의 표면만 이름짓는다, 와일드카드 금지):**

| 클레임 | 표면 (scope selector) | 현재 세대 | 판정 |
|---|---|---|---|
| **H1a-CORS** | nimbus-eth1 `0c023085` — 관측된 CORS `sameOrigin` 결정 표면만 (`p0d2/experiment.md` 3-way 대조, Origin `http://localhost:8080`) | VG-0004 (R2) | **NO-GO (표면 한정)** — 결함 ≡ 결함 없는 대조, 동일 Http403; clientId 이그레스 표면으로 전이 없음 |
| **H1a-PROC** | nimbus-eth1 `0c023085` — 관측된 프로세스 상태 표면만 (디코드 성공 + exit 0, 3케이스 동일) | VG-0005 (R2) | **NO-GO (표면 한정)** — 프로세스 상태 능력 델타 0; 동일하게 전이 없음 |

**범위 조건**: (a) 효과 계산은 핀 하니스 안의 소비자 verbatim 로직 기반이지 라이브 풀노드 관측이 아니다; (b) `agent-string`/`allowed-origins` 두 필드 외 경로는 인용만 하고 재유도하지 않음; (c) 결함은 핀 `73529768`에서 **생존(live)** — upstream 시정은 인간 결정이며 이 기록의 완결에 포함되지 않는다 (§3 잔여 조건).

---

## 3. 범위 조건 (공통 — Scope Conditions)

- **열거된 소비자 집합**: 원 판정(2026-10-11)의 열거는 nph, ImThemes 2곳이었다. 2026-10-12 기준 판정의 유일한 권위는 원장 `verdict_generations.tsv`다 — `verdicts_recorded.tsv`는 원장 헤드의 교차 검증 투영이며, 본 문서를 포함한 산문 기록은 파생 보고 뷰다. `judge`가 강제하는 facts ↔ recorded ↔ 원장 헤드의 집합 전단사(bijection)는 일관성 검증일 뿐, 행 집합 권위를 recorded에 부여하지 않는다 (nph, ImThemes, nimbus-eth1, stickyshell, click + 36 D1/D-NIL closure 소비자 — `closure/D1_nileq.md`). **전수 조사 아님**: GitHub 의존성 역탐색 등 체계적 생태계 스캔은 이 기록에 없다 (H2 — §2.4). 미발견 소비자의 3원조는 존재하지 않는 것이 아니라 **미생성**이다 (UNKNOWN의 한 형태).
- **소비자 핀 상태** (2026-10-12 잔여 결속 기준 — 구속 값은 `snapshot/judgment_snapshot.tsv`): nph 소비자 커밋 `2cacf6cc…` 기록됨(클론 경로 `/tmp/bsec_consumer/nph` — 임시 경로, 소실 시 freshness fail-closed); ImThemes 소비자 커밋 `d67592d…` 기록됨(`evidence/callsite.md` + GitHub API/lock 체인); nimbus-eth1 = 판정 시점 upstream master `97d1f982…` + **vendor 서브모듈 핀 `73529768…`**(`p0d2/target.md`); stickyshell·click = freshness 술어 핀은 **UNRECORDED**(snapshot `consumer_commit` 행 — 해당 항은 구조적 fail-closed; **게이트의 실행 출력이 권위다**). 단, D2/D3 closure 워크스트림은 판정 스코프 핀을 자기 기록에 두었다: stickyshell = `df552203…`, click = `30584707…` (`followup/checkout_trio/report.md`; DEFERRED.md D2/D3 ACTIVATED — 각 NO-GO 행은 그 핀으로 스코프됨). **의존성 해석 커밋**: nph·ImThemes = `b5b387e6`, nimbus-eth1 = `73529768`(서브모듈) — 각각 동적 프로브/3-way 대조로 검증됨.
- **결함 번호 주의**: `capdelta/capdelta.md`는 B-1의 두 결함을 국지적으로 "B-SEC-01/B-SEC-02"라 부른다. 본 기록의 번호 체계에서 둘 다 **B-SEC-01**(B-1 쌍)이며, B-SEC-02는 SIGSEGV 형태, B-SEC-03은 이스케이프 활성화다.
- **관측 일자**: 2026-10-11 (Asia/Seoul) — B-1 실행 재관측, 소비자 능력-델타 기록, 핀 재검증, 번들 조립 전부 이 날짜.
- **관측→판정 분리**: `replay.sh judge`는 (관측 튜플 + 규칙 테이블)의 순수 함수로 판정을 재유도한다. 미정의 입력 → UNKNOWN (전함수, fail-closed). 총 규칙 테이블: `rules/rule_table.tsv` (R1–R11 + DEFAULT).
- **재유도 대상의 한계**: 소비자 연결 관측(nph 대조 실험, 핀 구조 사실)은 오프라인 재실행 불가 — 증거 포인터와 함께 `offline/consumers/triples_facts.tsv`에 **기록된 관측**으로 참조된다. B-SEC-01의 결함 사실만 라이브 실행이 재유도한다(라이브 결함 소멸 시 NO-GO도 소멸).
- **최신성**: `replay.sh freshness`가 판정 시점 스냅샷 대비 ∨ 술어를 평가한다. 술어(2026-10-12 잔여 결속 기준)는 subject HEAD + nph·ImThemes·nimbus-eth1 소비자 핀 + 세 소비자의 의존성 핀(nimbus-eth1 = 서브모듈 `73529768`) + stickyshell·click 행(커밋 UNRECORDED — 핀이 기록될 때까지 해당 항은 절대 FRESH로 닫히지 않는다)을 평가한다. **게이트의 실행 출력이 권위다 — 이 문장이 그 결과를 대신하지 않는다.** 기존 판정을 최신 결론으로 간주하지 마라.
- **잔여 조건 (residue condition)**: *"The defect remains live at consumer pin `73529768ced17720f78fb5b57191e863f8d8a9c1` (nimbus-eth1 `vendor/nim-toml-serialization` submodule, `TomlHexEscape` default-active); upstream remediation is a human decision and is NOT part of this record's completion."* 이 기록의 병합·완결은 결함을 고치지 않는다 — 핀에서의 결함 생존 여부는 `replay.sh freshness`와 upstream 저장소 상태가 답하며, 시정 여부는 이 기록 밖의 인간 결정이다.

## 4. 이 기록이 하지 않는 것

- **CVSS·심각도·우선순위 없음.** CVE 제출 없음. upstream 이슈/PR 없음.
- **"안전하다"는 주장 없음.** NO-GO는 "이 소비자에서 능력 증가가 입증되지 않았다"는 최소 주장이며, 타 소비자·타 공격자 모델로 확장되지 않는다.
- **UNKNOWN = 미결정**이지 결함 부정이 아니다. B-SEC-02·03은 열거된 소비자 집합에서 닫히지 않았다.
- main 병합 = **기록의 운영적 완결**이지 외부 세계에 대한 진실성 보장이 아니다 (README 참조) — *"main merge is the operational completeness of the record, not truth about the external world."*
