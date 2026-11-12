# B-2 0b — Gate B census CRASH 14행 원인 분류 (읽기 전용 진단, 2026-11-04)

> **Status**: Observation evidence record — **읽기 전용 진단** (재측정·재실행·패치 없음; 기존 관측 산출물의 인용·대조만. `src/` 무수정, 제품 코드 무변경, main worktree 무수정, `/tmp/b1_gate_b/`·`/tmp/b1_gate_a/` 산출물 무수정)
> **Created**: 2026-11-04
> **Written at**: branch `work/b2-0b-crash-classification-2026-11-04` (worktree `/tmp/b2_wt/0b`), branch base = main `50d781e82f6a90058a610dc92db99453ea3fd676` (PR #1262 merge)
> **Governing docs**: [docs/evidence/b1_gate_b_capability_census_2026-11-04.md](b1_gate_b_capability_census_2026-11-04.md) (B-1 Gate B census — 본 문서의 분류 대상 데이터의 정본; §5.2 28행표·§5.2 digest 전수표·§5.5 C7 원문) · [docs/evidence/b1_gate_a_minimal_proof_2026-11-04.md](b1_gate_a_minimal_proof_2026-11-04.md) (B-1 Gate A — as_bool 병행 증명 실험, 본 문서의 대조 계보)
> **원칙**: 기계 출력과 오류 문자열은 원문 그대로 인용한다(재작성·요약·번역 없음; 터미널 이스케이프 제거는 표기 목적뿐). 이 문서는 관찰을 기록하며 serde_json·Aeneas·Charon에 대한 어떤 참·거짓 주장도 하지 않는다 (§Non-claims). census 정본 문서는 **Read만** 수행했다(수정 0건 — 같은 문서의 §5.7 정정 PR이 병렬 진행 중이므로).

7-field identity (FREEZE.md §1 형식 준용 — 값은 본 문서 정체성):

- PROJECT_UNDER_TEST: **분류 대상은 관측 데이터다** — B-1 Gate B census(PR #1259)가 기록한 28행 중 **CRASH 14행**의 실패 원문(logs/*.aeneas.log·census_rows.csv·llbc/*). 서브젝트 참조 identity: serde_json (Rust crate) v1.0.154 @ `8c535a260ce561eaab4111aafc29038eb9f77ff3` (census와 동일 — 재측정 없음)
- REVISION: `8c535a260ce561eaab4111aafc29038eb9f77ff3` (서브젝트 — census 정본 인용)
- AXIOM_REVISION: `50d781e82f6a90058a610dc92db99453ea3fd676` (branch base; census 본체 `76efe1fcccc9e0dd0fc60e3c6e310dad4b63d7fe` 이후의 main)
- CONFIG: **읽기 전용 진단 — 새로운 charon/aeneas/lean 실행 0건**. 데이터는 `/tmp/b1_gate_b/`(읽기만), Axiom4 변경은 본 문서 1건뿐(§-1·FROZEN 목록 미접촉, `src/` 무변경)
- TOOLCHAIN_ID: **신규 실행 없음** — 인용 데이터의 toolchain은 census §4.1 정본 원문(charon **0.1.304** (`7b462d9159db2ed3015162352183906a30bfafc6`) + aeneas `nightly-2026.11.03-ab34bd2`, Lean v4.35.0 요구는 컴파일 단계 사항 — 본 문서 범위 밖)
- SCOPE: CRASH 14행(28행 기준) 각각을 5분류 체계로 판정하고 근거 원문을 고정. **범위 밖**: C1~C8 참/거짓 판정, 어느 함수의 "증명 가능성" 판정, 제품·lane·핀 판정, 상류 이슈 보고, census 문서 수정, PARTIAL 2행·TRANSLATED 12행의 재분류
- EXPERIMENT_ID: b2-0b-crash-classification-2026-11-04

---

## 1. Question

이 문서가 답하는 질문:

1. census CRASH 14행의 실패 원인은 다음 5분류 중 어디에 해당하는가 — **Extraction failure** / **Translation unsupported** / **Translator crash** / **Model missing** / **Lean compile failure** (판정 불가 행은 UNKNOWN)?
2. **상류 도구 crash(Translator crash)와 의미론적 미지원(Translation unsupported)을 분리하면** 각각 몇 행인가 — 종단(fatal termination) 원문 기준?

## 2. Context

- 정본 사실(B-1 census, PR #1259, 461행): 28행 = **TRANSLATED 12 · PARTIAL 2 · CRASH 14**. json 실함수 21 기준 = TRANSLATED 6 · PARTIAL 2 · CRASH 13(앵커 as_bool 행은 실함수 우주에 포함, 앵커 C7 행은 별도). 옛 표현 "C7 12개 CRASH"는 수치 오류로 정본 문서 기준을 따른다.
- CRASH 14행 라벨(census §5.2): `c7_parse_line_col`, `de_from_trait`, `de_from_reader`, `de_from_slice`, `de_from_str`, `error_make_error`, `ser_to_writer`, `ser_to_writer_pretty`, `ser_to_vec`, `ser_to_vec_pretty`, `ser_to_string`, `ser_to_string_pretty`, `value_parse_index`, `value_to_value`.
- census §5.5는 C7 행에 대해 "aeneas 블로커는 … `core::str::rfind` 시그니처 Unimplemented → CFailure로 이동했다"고 기록한다. 본 문서는 그 판정을 C7 1행이 아니라 **CRASH 전체 14행의 원문으로 확장·검증**하는 것이며(§5), 이는 C7의 SCOPE_LIMIT 판정에 대한 측정 근거 보강이 목적이다.
- 5분류 정의(본 실험의 채택 정의 — 종단 원문 기준):
  - **Extraction failure**: charon 추출 단계 실패(charon_exit≠0 또는 LLBC 미생성)
  - **Translation unsupported**: aeneas가 명시적 미지원 이유로 종료(exit≠0, 오류 원문이 지원 부재를 서술 — 예: `Unimplemented`/`CFailure`)
  - **Translator crash**: aeneas 예외·크래시(스택트레이스/failwith/내부 오류 원문이 종단 원인)
  - **Model missing**: 외부 손모델 부재로 실패
  - **Lean compile failure**: 번역물 생성됐으나 Lean 컴파일 단계 실패
  - 판정 불가는 UNKNOWN으로 남기고 이유를 밝힌다(추측 금지 — 기계 출력 원문 인용만 근거).

## 3. Scope

- **범위 안**: §1의 2개 질문에 해당하는 읽기 전용 대조 — census_rows.csv 29행 열람, CRASH 14행의 llbc/item_*.llbc 실물 sha256·바이트 크기 재계산(census §5.2 digest 전수표와 대조), logs/*.aeneas.log 14건 원문 인용·클래스 집계.
- **범위 밖**: 어떤 새 charon/aeneas/lean 실행도 없다. `/tmp/b1_gate_b/`·`/tmp/b1_gate_a/`는 읽기만(수정 0건). census 정본 문서는 Read만(병렬 정정 PR 존재). PARTIAL 2행(aeneas exit 1, 부분 파일 생성)과 TRANSLATED 12행은 본 분류의 대상이 아니다.
- **Non-claim 기준**: "행 X가 Translation unsupported"는 **이 입력·이 쌍(aeneas nightly-2026.11.03-ab34bd2 + charon 0.1.304)·이 시점**의 종단 원문 분류일 뿐, 상류의 일반 동작에 대한 주장이 아니다(census §9의 원칙 준용).

## 4. Procedure (읽기 전용 명령열)

```
# (0) 정본·데이터 위치 확인 (수정 없음)
git -C /tmp/b2_wt/0b rev-parse HEAD                       # 50d781e82f6a90058a610dc92db99453ea3fd676
cat /tmp/b1_gate_b/census_rows.csv                        # 29행(헤더+28행) — label|start_from|charon_exit|wall|lock_in|lock_out|llbc_sha256|llbc_size|aeneas_exit|lean_files|porcelain

# (1) CRASH 14행 LLBC 실물 대조 (읽기 전용; census §5.2 digest 전수표와 비교)
cd /tmp/b1_gate_b
for l in c7_parse_line_col de_from_trait de_from_reader de_from_slice de_from_str \
         error_make_error ser_to_writer ser_to_writer_pretty ser_to_vec ser_to_vec_pretty \
         ser_to_string ser_to_string_pretty value_parse_index value_to_value; do
  sha256sum llbc/item_${l}.llbc; stat -c%s llbc/item_${l}.llbc
done

# (2) 행별 aeneas 로그 원문 (ANSI 이스케이프 제거는 표기 목적 — 재작성 없음)
sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r//g' /tmp/b1_gate_b/logs/<label>.aeneas.log | tail -14   # 종단 블록
sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r//g' /tmp/b1_gate_b/logs/<label>.aeneas.log | head -1    # 입력 LLBC 확인

# (3) 행별 오류 클래스 집계 (기계 출력의 uniq — 해석 없음)
sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r//g' /tmp/b1_gate_b/logs/<label>.aeneas.log \
  | grep -E '^\[Error\]' | sort | uniq -c | sort -rn
```

## 5. Result

### 5.1 행 공통 사실 (14/14)

- charon exit **0**(14/14), lock in==out `1bc62b1a…`, porcelain empty — census §5.2 원문 유지. **Extraction failure 근거 없음**(charon 실패·LLBC 미생성 행 없음).
- LLBC 실물 14건의 sha256·바이트 크기를 재계산(census_rows.csv의 llbc_sha256·llbc_size와 census §5.2 digest 전수표 기준): **14/14 완전 일치** — 즉 14행 전부 aeneas에 동일 정본 입력이 주어졌음이 실물로 재확인됨.
- aeneas exit **2**(14/14), 생성 Lean 파일 **0**(14/14) — Lean 컴파일 단계에 도달한 행 없음(**Lean compile failure 0의 근거**).
- 각 로그 첫 행 원문(`[Info ] Imported: /tmp/b1_gate_b/llbc/item_<label>.llbc`) 14/14 확인 — 입력 파일 대응 고정.

### 5.2 CRASH 14행 분류표

분류는 **종단(fatal termination) 원문** 기준이다. 모든 행의 종단 블록은 §5.3 원문과 동일 클래스(행별 차이는 §5.4·§5.5). `[Error]` 라인 총개수는 §4(3) uniq 집계값(해석 없는 카운트).

| 행 | llbc_sha256 (§5.2 정본표 일치 재확인) | aeneas_exit | `[Error]` 총수 | 분류 |
|---|---|---|---|---|
| c7_parse_line_col | `db32749bbed1c145e3f381531778307cb3c6ff501aa0a4cb98ebf8fb2b687650` | 2 | 2 | Translation unsupported |
| de_from_trait | `8eb87e4ab7c1fc6d27dc3c497b8428fce05f97a959bf3298d178bd9a424598d6` | 2 | 30 | Translation unsupported |
| de_from_reader | `67ddfef159c5d675f80a250e2c1071fcd8c89050b107d67be868c5f26b74df00` | 2 | 69 | Translation unsupported |
| de_from_slice | `224f511cfa81b1f407e54957ee612ab928d2960800b86ad617eaeb6c129eb472` | 2 | 71 | Translation unsupported |
| de_from_str | `6fff9631a8a35149615d67019fa4cea1152db41f20152ccffb4e5626a154c70e` | 2 | 85 | Translation unsupported |
| error_make_error | `8e3a408e32fb531debc6d17c026421c8861e3d44c759d0b4aacc0013139e45bf` | 2 | 2 | Translation unsupported |
| ser_to_writer | `2a37845ddf977236b5ffe739cc759329f6d882823f6bdf6905bb24b8eeadee71` | 2 | 12 | Translation unsupported |
| ser_to_writer_pretty | `af6d45f2afd1cb0668775afa042c690b27bde92f09667003f3cbf60b35c1a5ea` | 2 | 21 | Translation unsupported |
| ser_to_vec | `2d5b48f65df8b250301d6fe3c9f0f6fe2a1082179a82026af14b06063a0c4f6f` | 2 | 13 | Translation unsupported |
| ser_to_vec_pretty | `0ca4cde09bfaee9d740cc14cdcab7675d96259b175ca2939fb39b2fe249b4eda` | 2 | 22 | Translation unsupported |
| ser_to_string | `f769a1868d1224db3782690a0769ea82ef7c26f8dd913c3ef6cf7ff390817dc0` | 2 | 14 | Translation unsupported |
| ser_to_string_pretty | `b1735211812f1d332f1ea03ee086be375bd1ad94903a36c26c008bc09a76b24c` | 2 | 23 | Translation unsupported |
| value_parse_index | `51613eb9bcae81f47def11476917cb4add269372d07a7c092cbadaff75eb3371` | 2 | 1 | Translation unsupported |
| value_to_value | `adb4aca7735c772c736bdc63eb9e92f037b59987a2d0f4a00c1e25f4b8069e4c` | 2 | 13 | Translation unsupported |

**분류별 집계(14행)**: Extraction failure **0** · Translation unsupported **14** · Translator crash **0** · Model missing **0** · Lean compile failure **0** · UNKNOWN **0**.

### 5.3 종단 블록 공통 원문 (14/14 — ANSI 제거)

모든 행의 마지막 `[Error]` 블록과 종단 원문(c7_parse_line_col.aeneas.log 16–29행; 다른 13행에서 동일 블록 — `Stdlib__List.map` 프레임 수만 2~3으로 상이하고, 나머지는 행마다 동일):

```
[Error] Unimplemented
Source: '/rustc/library/core/src/str/pattern.rs', lines 99:0-99:24
Fatal error: exception Aeneas.Errors.CFailure(_)
Raised at Aeneas__Errors.craise_opt_span in file "Errors.ml", line 127, characters 4-46
Called from Aeneas__Errors.cassert_opt_span in file "Errors.ml" (inlined), line 156, characters 16-50
Called from Aeneas__SymbolicToPureTypes.translate_fwd_ty in file "symbolic/SymbolicToPureTypes.ml", lines 392-394, characters 6-23
Called from Aeneas__SymbolicToPureTypes.translate_inst_fun_sig_to_decomposed_fun_type in file "symbolic/SymbolicToPureTypes.ml", line 787, characters 19-60
Called from Aeneas__SymbolicToPureTypes.translate_fun_sigs in file "symbolic/SymbolicToPureTypes.ml", lines 1042-1043, characters 4-32
Called from Aeneas__Translate.translate_crate_to_pure.translate_method_sig in file "Translate.ml", lines 405-406, characters 10-45
```

- 종단 직전 오류 원문은 `[Error] Unimplemented` — **지원 부재를 서술하는 aeneas 고유 마커**이며, 위 분류 정의의 Translation unsupported 예시(`Unimplemented`/`CFailure`)와 정확히 일치한다. 14행 전부 exit≠0이며 종단 원문이 지원 부재를 서술한다 → **14행 전부 Translation unsupported**.
- 종단 위치는 14행 공통으로 `translate_fun_sigs`(함수 시그니처 번역 단계)다 — 본문 번역 완료 전 단계의 종단이다(스택트레이스 원문 위 참조).

### 5.4 행별 상이점 — 종단에 이르기 전의 Unimplemented 서명 목록 (원문)

census §5.5에서 고정한 rfind 원문이 13행에 선행한다(value_parse_index 제외 — §5.4(3)):

```
[Error] Unimplemented
Source: '/rustc/library/core/src/str/mod.rs', lines 1542:4-1544:53
[Warn ] Could not translate the function signature of 'core::str::{str}::rfind because of previous error
Name pattern: 'core::str::{str}::rfind'
Definition span: '/rustc/library/core/src/str/mod.rs', lines 1542:4-1544:53

This definition is (transitively) used at the following locations:
Source: 'src/error.rs', lines 495:32-495:54

Source: '/rustc/library/core/src/str/mod.rs', lines 1542:4-1544:53
Compiler source: Translate.ml, line 390
```

(1) **c7_parse_line_col · error_make_error**(`[Error]` 총 2행): 위 rfind 블록 + §5.3 종단 블록 — 전부.
(2) **de_from_trait · ser_to_writer · ser_to_writer_pretty · ser_to_vec · ser_to_vec_pretty · ser_to_string · ser_to_string_pretty · value_to_value**(각 `[Error]` 12~30행): 위 rfind 블록 + §5.3 종단 블록 + §5.5의 비종단 클래스들(§5.5 표).
(3) **value_parse_index**(`[Error]` 총 1행): rfind 선행 블록 **없음** — §5.3 종단 블록만으로 구성된다. 즉 이 행은 rfind 경고 없이 `/rustc/library/core/src/str/pattern.rs', lines 99:0-99:24`의 Unimplemented가 유일한 오류이다.
(4) **de_from_reader · de_from_slice · de_from_str**(`[Error]` 총 69/71/85행): 위 (2)에 더해 rfind 외에 서명 번역 실패 Unimplemented가 추가로 존재한다(de_from_str 원문 예 — 나머지 2행도 동일 클래스):

```
[Error] Unimplemented
Source: 'src/read.rs', lines 128:4-128:19
[Warn ] Could not translate the function signature of 'serde_json::read::Reference::{impl core::ops::function::FnOnce<(&'b T,), serde_json::read::Reference<'b, 'c, T>> for serde_json::read::Reference::Borrowed<'b, 'c, T>}::call_once because of previous error
Name pattern: 'serde_json::read::Reference::{core::ops::function::FnOnce<@, (&'b @T), serde_json::read::Reference<'b, 'c, @T>>}::call_once'
Definition span: 'src/read.rs', lines 128:4-128:19
Source: 'src/read.rs', lines 128:4-128:19
Compiler source: Translate.ml, line 390
```

   — de_from_reader·de_from_slice·de_from_str의 Unimplemented 전체 Source span 원문: `'/rustc/library/core/src/str/mod.rs', lines 1542:4-1544:53`(rfind) · `'/rustc/library/core/src/str/pattern.rs', lines 99:0-99:24`(종단) · `'src/read.rs', lines 128:4-128:19`(de_from_slice·de_from_str) · `'src/read.rs', lines 129:4-129:17`(3행 공통) · `'src/read.rs', lines 903:0-921:1`(3행 공통).

### 5.5 비종단 오류 조성 — 상류 crash 클래스 원문의 "발생"과 "종단"의 분리

11행(de_from_* 4 + ser_to_* 6 + value_to_value 1)에는 종단 원인과 별개로 **내부 오류 원문이 다수 발생**한다. 이는 상류 결함 후보로 관측 가치가 있으나 **종단 원인이 아니므로 Translator crash로 분류하지 않는다** — 분리 기술이 본 문서의 요구 사항이다(census §5.1의 전체 크레이트 관측에서는 이 클래스가 종단 원인이었다 — 본 14행 census 행에서는 종단 원인이 아니다).

행별 `[Error]` 라인 uniq 집계(ANSI 제거, 카운트만):

| 행 | `Internal error: please file an issue` | `Unimplemented` | `Mixed declaration groups … not supported yet` | `Detected groups of mixed mutually recursive definitions` | `Ignoring the body of …` | 기타 |
|---|---|---|---|---|---|---|
| de_from_trait | 22 | 2 | 1 | 1 | 4 | — |
| de_from_reader | 59 | 4 | 1 | 1 | 4 | — |
| de_from_slice | 59 | 5 | 1 | 1 | 4 | `Early returns inside of loops are not supported yet` ×1 |
| de_from_str | 73 | 5 | 1 | 1 | 4 | `Early returns inside of loops are not supported yet` ×1 |
| ser_to_writer | 8 | 2 | 1 | 1 | 0 | — |
| ser_to_writer_pretty | 17 | 2 | 1 | 1 | 0 | — |
| ser_to_vec | 9 | 2 | 1 | 1 | 0 | — |
| ser_to_vec_pretty | 18 | 2 | 1 | 1 | 0 | — |
| ser_to_string | 10 | 2 | 1 | 1 | 0 | — |
| ser_to_string_pretty | 19 | 2 | 1 | 1 | 0 | — |
| value_to_value | 9 | 2 | 1 | 1 | 0 | — |

위 표의 클래스 원문 표본(de_from_str.aeneas.log에서 ANSI 제거, 원문 그대로):

```
[Error] Internal error: please file an issue
Source: 'src/de.rs', lines 2709:0-2714:1
[Warn ] Could not translate the function signature of 'serde_json::de::from_str because of previous error
Name pattern: 'serde_json::de::from_str'
Definition span: 'src/de.rs', lines 2709:0-2714:1
```

```
[Error] Mixed declaration groups (which contain both type and function declarations or functions and traits, for instance) are not supported yet: [7, 44, 61, 62, 67, 68, 69, 70, 71, 72, 19, 192, 20, 193, 194, 24, 208, 52, 381, 382, 383, 384, 23, 207, 72, 495, 484, 485]
```

```
[Error] Ignoring the body of 'serde_json::de::{serde_json::de::Deserializer<R>}::scan_integer128' because of previous error
[Error] Early returns inside of loops are not supported yet
```

- `Internal error: please file an issue`는 11행 각각에서 **서명 번역 실패의 선행 원인 원문**으로 발생한다(위 표본 원문: 대상 함수 시그니처 앞의 내부 오류 마커). 종단 원인(`Unimplemented` at pattern.rs 99)과는 별개 발생이다 — 14행 중 11행이 이 클래스를 포함하지만, 어느 행도 이 원문으로 종료되지 않았다(모든 행의 마지막 `[Error]`는 §5.3의 `Unimplemented`).
- `Mixed declaration groups … are not supported yet`·`Early returns inside of loops are not supported yet`·`Ignoring the body of …`는 지원 부재 서술 클래스로서 비종단 발생이다.
- **Model missing에 해당하는 원문은 14행 어디에도 없다**(손모델/axiom 부재를 서술하는 오류 문자열 없음 — 기계 출력 기준).

### 5.6 집계 재확인

- 28행 기준(census §5.2): TRANSLATED 12 · PARTIAL 2 · **CRASH 14** — 본 문서는 CRASH 14행만 다룬다.
- json 실함수 21 기준: TRANSLATED 6 · PARTIAL 2 · CRASH 13(CRASH 14 중 앵커 C7 행 제외).
- CRASH 14행의 5분류: **Translation unsupported 14, 그 외 0, UNKNOWN 0** (§5.2).

## 6. Non-claims

- **어떤 함수의 증명 가능성 판정도 아니다.** "CRASH"는 번역 단계 실패의 관측 라벨일 뿐이며, 본 문서는 C1~C8을 포함한 어느 대상의 참/거짓·증명 가능 여부도 판정하지 않는다.
- **제품 판정이 아니다.** Axiom 제품 표면·lane·핀·게이트에 대한 어떤 변경·판정도 없다(`src/` 무수정, FROZEN 무접촉).
- **상류 동작의 일반화가 아니다.** 본 분류는 특정 릴리스 자산(aeneas `nightly-2026.11.03-ab34bd2`, charon `0.1.304 (7b462d91…)`, 서브젝트 `8c535a26…`)에 대한 관측일 뿐이다. "Unimplemented" span이 무엇을 가리키는지의 해석(예: pattern.rs 99의 실제 정의)은 본 문서가 수행하지 않는다 — 기계 출력이 기록한 span 원문만 남긴다.
- **인과 주장의 한계.** "종단 원인 = pattern.rs 99 Unimplemented"는 로그의 종단 순서 원문에 대한 기술이며, 그 앞의 `Internal error` 다수가 종단에 기여했을 가능성에 대한 주장은 하지 않는다(추측 금지 원칙).
- **상류 이슈 보고·패치 없음.** 발견된 상류 오류 원문은 관측 기록일 뿐이며, Axiom4 극장 레지스트리 대상이 아니다(우리가 도입·은폐한 것이 아니라 외부 도구의 관측된 한계 — census §8.3 준용).

## 7. Deviations

해당 없음 — 본 실험은 실행·수정이 전혀 없는 인용 전용 진단이다(새 명령은 §4의 읽기 전용 명령열뿐). census 산출물·census 문서에 대한 쓰기 0건, 재실행 0건, 데이터 삭제 0건.

## 8. Interpretation

- **"상류 도구 crash"와 "의미론적 미지원"의 분리 결과**: 종단 원문 기준으로 CRASH 14행은 전부 의미론적 미지원(`Unimplemented`) 종단이며, aeneas 예외형 크래시(failwith 등)로 종단한 행은 0이다. 단, 비종단으로 `Internal error: please file an issue`(11행, 8~73건)와 `Mixed declaration groups`(11행)·`Early returns inside of loops`(2행)·본문 무시 4건(de_from_* 4행)이 발생했다 — §5.5.
- **C7 SCOPE_LIMIT 근거 보강**: census §5.5가 C7 1행에서 기록한 종단 클래스(`Unimplemented` → `CFailure`)가 **CRASH 나머지 13행에서도 종단 원문으로 동일하게 나타난다**(14/14 — §5.3). rfind 선행 블록은 13행에 존재하고 value_parse_index 1행에는 없다(§5.4(3)). 즉 C7의 SCOPE_LIMIT 판정은 단일 행 이변이 아니라 CRASH 클래스 전체의 공통 종단 패턴 위에 놓인다(측정 근거 서술 — 판정 변경 없음).
- **Blocker 집약**: 종단 span `/rustc/library/core/src/str/pattern.rs', lines 99:0-99:24`의 Unimplemented가 14/14 공통 종단점이고, `/rustc/library/core/src/str/mod.rs', lines 1542:4-1544:53`(`core::str::{str}::rfind` 시그니처)의 Unimplemented가 13/14 선행점이다 — 두 span이 CRASH 14행의 기계 기록상 최소 공통 블로커 후보다(원문 서술이며, span 내용에 대한 해석·주장은 §6대로 하지 않는다).

## Repro Block

```
# 읽기 전용 재현 (새 실행 없음 — 관측 데이터 인용 대조만; /tmp/b1_gate_b 수정 금지)
git -C /tmp/b2_wt/0b rev-parse HEAD        # 50d781e82f6a90058a610dc92db99453ea3fd676
sed -n '112,143p;147,176p' /tmp/b2_wt/0b/docs/evidence/b1_gate_b_capability_census_2026-11-04.md
   # census §5.2 28행표 + digest 전수표 (정본)

cd /tmp/b1_gate_b
for l in c7_parse_line_col de_from_trait de_from_reader de_from_slice de_from_str \
         error_make_error ser_to_writer ser_to_writer_pretty ser_to_vec ser_to_vec_pretty \
         ser_to_string ser_to_string_pretty value_parse_index value_to_value; do
  sha256sum llbc/item_${l}.llbc; stat -c%s llbc/item_${l}.llbc
  sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r//g' logs/${l}.aeneas.log | head -1          # [Info ] Imported: …
  sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r//g' logs/${l}.aeneas.log | tail -14         # 종단 블록 (§5.3)
  sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r//g' logs/${l}.aeneas.log | grep -E '^\[Error\]' | sort | uniq -c | sort -rn
done
# 기대: sha256·크기 14/14 일치, 종단 블록 14/14 [Error] Unimplemented (str/pattern.rs 99:0-99:24) + CFailure,
#       aeneas_exit 2 · lean_files 0 (census_rows.csv 열 기준)
```

## Landing record

- (착지 후 기록 안함 — PR 번호·head sha·merge 상태는 본 섹션에 추가하지 않고 최종 인계 보고에 기재된다. 본 문서는 단일 커밋으로 착지된다.)
