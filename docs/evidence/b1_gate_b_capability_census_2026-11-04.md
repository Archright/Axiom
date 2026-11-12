# serde_json Gate B 재사용 범위 census — 공식 호환 Charon/Aeneas 쌍 전수 측정 + Aeneas 어댑터 채택 결정 근거 (2026-11-04)

> **Status**: Observation evidence record — 읽기 전용 측정 (`src/` 무수정, 제품 코드 무변경, main worktree·서브젝트 원본 무수정; 모든 실행은 `/tmp/b1_gate_b/` 샌드박스와 전용 worktree에서 수행)
> **Created**: 2026-11-04
> **Written at**: branch `work/b1-gate-b-2026-11-04` (worktree `/tmp/b1_gate_b/ax_wt`), branch base = main `76efe1fcccc9e0dd0fc60e3c6e310dad4b63d7fe` (origin/main)
> **Governing docs**: [docs/evidence/serde_json_c7_semantics_aeneas_2026-11-03.md](serde_json_c7_semantics_aeneas_2026-11-03.md) (B-0 — §8 잠금 프로토콜·재현 명령열·§12 결정론 형식의 선행 정독 및 재사용) · [docs/evidence/serde_json_claim_adjudication_2026-10-31.md](serde_json_claim_adjudication_2026-10-31.md) · PR #1255 (MERGE `f8db2c85`, B-1 의미 단위 선정 조사 — `--extract-opaque-bodies` 선행 관측의 대조 기준)
> **원칙**: 기계 출력과 오류 문자열은 원문 그대로 인용한다(재작성·요약·번역 없음). 이 문서는 관찰을 기록하며 측정 대상 프로젝트(serde_json)와 Aeneas/Charon 상류에 대한 어떤 참·거짓 주장도 하지 않는다. **Aeneas 어댑터 채택 vs 자체 구현의 "결정" 자체는 본 문서가 내리지 않는다** — 측정 기반 근거만 제공하며, 결정은 별도 계약 개정(§0.12) 사항이다.

7-field identity (FREEZE.md §1 형식 준용 — 값은 본 문서 정체성):

- PROJECT_UNDER_TEST: serde_json (Rust crate) v1.0.154 — **Gate B 재사용 범위 census**: 공식 호환 Charon/Aeneas 쌍이 census 우주(실함수 21 + 앵커 2 + probe fixture 6)에서 어디까지 추출·번역·Lean 컴파일에 도달하는지의 전수 측정
- REVISION: `8c535a260ce561eaab4111aafc29038eb9f77ff3` (subject HEAD — `/tmp/b1_gate_b/json_copy` 검증 사본으로 확인, 원본 `<workspace>/json`은 clean·무수정)
- AXIOM_REVISION: `76efe1fcccc9e0dd0fc60e3c6e310dad4b63d7fe` (main; branch base = worktree 생성 시점 origin/main)
- CONFIG: 읽기 전용 관찰 + `/tmp` 샌드박스 측 시험만. charon 실행은 전부 `CARGO_NET_OFFLINE=true`. `gh_env.txt` 미접촉, GitHub 자격 증명은 `gh auth` 네이티브만. Axiom4 저장소 본체 변경은 본 문서 1건뿐(§-1·FROZEN 목록 미접촉, `src/` 무변경)
- TOOLCHAIN_ID: **공식 호환 쌍** — charon **0.1.304** (`7b462d9159db2ed3015162352183906a30bfafc6`, 번들 `charon version` exit 0) + aeneas `nightly-2026.11.03-ab34bd2` (`aeneas -version` 원문). **이중 rustc identity**: 추출용 rust `nightly-2026-09-17` = rustc **1.100.0-nightly (923c95cdf 2026-09-16)**, 실행 기준 stable rustc **1.95.0 (59807616e 2026-04-14)** / cargo 1.95.0 (f2d3ce0bd 2026-03-21). Lean: **v4.35.0** (`leanprover/lean4:v4.35.0`, commit `eb6cafb7290e8bd5f2937522d8d804f58f02bafc`, elan 4.2.4 (227caca13 2026-08-25) 경유) — Axiom4 저장소 핀(4.33.0)은 **무변경**, v4.35.0은 aeneas `backends/lean/lean-toolchain`이 요구하는 툴체인으로 샌드박스에서만 사용
- SCOPE: (a) census 우주 21+2+6 전수의 7필드·3단계 측정, (b) 전체 크레이트 플래그 없는 aeneas 관측, (c) C7 서브그래프 플래그 없는 관측(B-0 시험 2·3의 직접 대조), (d) `-print-unknown-externals` 음성 대조 1건, (e) `--extract-opaque-bodies` 변이 측정(C7·as_bool — PR #1255 선행 관측의 0.1.304 재현 판정), (f) 번역 성공 항목의 Lean 컴파일 단계 관측. **범위 밖**: sorry 없는 명제 증명(3단계)의 수행, C1~C8 참/거짓 판정, 제품 판정, lane·핀 변경, aeneas 소스 패치
- EXPERIMENT_ID: serde-json-gate-b-census-2026-11-04

---

## 1. Question

이 문서가 답하는 질문:

1. 공식 호환 Charon/Aeneas 쌍(charon 0.1.304 + aeneas `nightly-2026.11.03-ab34bd2`)은 census 우주(실함수 21 + 앵커 2 + probe fixture 6)의 각 항목에서 (1) 본문 추출 → (2) 모델 변환 → (3) sorry 없는 명제 증명의 어디까지 **실측으로** 도달하는가?
2. B-0에서 번역 계층 진입을 막았던 NameMatcher 튜플 크래시는 이 쌍에서 재현되는가 — 재현되지 않는다면 C7의 새로운 블로커는 무엇인가?
3. 진단 플래그(`-print-unknown-externals`)의 유무가 결과를 바꾸는가(음성 대조)?
4. PR #1255의 선행 관측(charon 0.1.281: `--extract-opaque-bodies`로 Opaque callee 본문 추출, fun_decls 2134→5037)은 charon 0.1.304 + `--preset=aeneas` 조합에서 재현되는가?
5. 이 전수 측정은 "Aeneas 어댑터 채택 vs Axiom 자체 최소 의미론 구현"의 결정에 어떤 **측정 기반** 근거(비용·범위·신뢰 경계)를 제공하는가?

## 2. Context

- B-0(2026-11-03)은 charon **0.1.281** + aeneas `nightly-2026.10.13-73b7cf9`에서 C7의 aeneas 시험 4회가 **전부** `-print-unknown-externals` 부여 상태였고, 그 플래그의 진단 블록(Main.ml:685-693 외부 정의 매칭 테이블 구성)이 NameMatcher 튜플-이름 크래시(`Can't convert the name of a tuple to a pattern`)의 유일한 Main.ml 트리거였음을 관측했다. **번역 경로 자체는 B-0에서 관측된 적이 없다.** 본 실험은 그 직접 후속으로, census의 **모든 aeneas 실행을 해당 플래그 없이** 수행한다.
- aeneas는 추출 단계를 Charon과 **공유**하므로(같은 LLBC 소비) 독립 검증이 아니라 독립 번역 계층의 적용성 측정이다(B-0 §8.2 정직 범위 유지).
- census 우주는 실측으로 확정된 것이다: `experiments/serde-json-claim-2026-10-31/discovery/scan_results.json`의 `example_names_local` 20개 + `serde_json::value::Value::as_bool`(src/value/mod.rs:708 — Gate A가 병렬로 증명 실험 중인 기준 선정 후보; 본 행은 독립 재현 측정) + 앵커 2(C3 `is_f64` src/number.rs:113, C7 `parse_line_col` src/error.rs:494 — 이미 SCOPE_LIMIT 판정, 대조 행) + probe fixture 6.
- probe fixture 6항목(axiom_rust_probe의 add_u8·add_u8_mutant, axiom_u64_probe의 u64_echo·u64_seven_mutant·u64_add·u64_add_mutant)은 **번역 정확성 시험으로만** 기록되며, 어떤 제품 검증 성공으로도 계산되지 않는다.
- `scan_results.json`의 candidates 13(`ser::BB/TT/NN/FF/RR/QU/BS/UU/__` + `read::<impl>::should_early_return_if_failed` ×4)은 **전부 zero-param const 항목**(`params: []`, 원문 `sig_line`: `const BB: u8 = b'b';` 등)으로, 함수 census에서 제외한다 — 제외 사유의 원문 근거는 §5.9.

## 3. Scope

- **범위 안**: §1의 5개 질문에 해당하는 측정 전부. 28개 census 행(charon 추출 → LLBC digest → 플래그 없는 aeneas 번역 → 성공·부분 항목의 Lean 컴파일 시도) + 전체 크레이트 1관측 + 음성 1건 + 변이 2건.
- **범위 밖**: 3단계(sorry 없는 명제 증명)의 수행 — 어느 행에서도 시도되지 않았으며, 도달한 곳은 없다(§7.1). mathlib 프로비전(§5.8의 요구사항 기록). aeneas 소스 빌드/패치. charon/aeneas 상류 이슈 보고. lane·게이트·핀 변경.
- **편차**: §10에 원문대로 기록. "다른 실험 디렉터리(/tmp/b1_gate_a 등) 불침범" 준수(전체 실행은 `/tmp/b1_gate_b/` 단일 샌드박스).

## 4. Procedure

### 4.1 조달 (퍼블릭, 자격 증명 무사용)

- 릴리스 자산: `https://github.com/AeneasVerif/aeneas/releases/download/nightly-2026.11.03-ab34bd2/aeneas-linux-x86_64.tar.gz` — curl 직접 다운로드(인증 헤더 없음, §2.4 준수). sha256 **`ed0e336c506dad37e4e1c53f6cc4d6d5959d7e3afab2fd55aead280775651f5e`**, 158,648,932 B.
- 번들 구성: `aeneas` / `charon` / `charon-driver` / `backends/`(lean·coq·fstar·hol4 — **lean에 사전 빌드 `.lake/build` 포함**) / `rust-toolchain`(nightly-2026-09-17).
- identity 원문:
  - `charon version` → `0.1.304 (7b462d9159db2ed3015162352183906a30bfafc6)` (exit 0); `charon toolchain-version` → `nightly-2026-09-17`
  - `aeneas -version` → `aeneas nightly-2026.11.03-ab34bd2`
  - 바이너리 sha256: `aeneas` `12e6042cfb00aba8ea8b6ef2811f55867e4fc8bf56bcc96c5a7d52ab9fd53a9c` · `charon` `4226741660099a31be54bde273e9193dd5a44154df7eb203c3c333d83b32a59c` · `charon-driver` `bb0f4073c59f7fab47f8e133d761806c17dad09dab9aa6c0116aa057380300e9`
- aeneas 저장소 동일 태그 읽기 전용 클론: `git clone --depth 1 --branch nightly-2026.11.03-ab34bd2` → HEAD `ab34bd28458a08c150b7cbf1873e59af74588138`, `backends/lean/lean-toolchain` = `leanprover/lean4:v4.35.0`.

### 4.2 서브젝트 검증 사본 + §8 잠금 프로토콜 (B-0 §4.3 재현)

1. 원본(`<workspace>/json`) 기록: HEAD `8c535a260ce561eaab4111aafc29038eb9f77ff3`, `git status --porcelain` **empty(clean)**, `Cargo.lock` tracked **아님** + 디스크 부재, find-매니페스트(excl `.git`) sha256 `8045f3b1ce56398fe506aeec9f9344405e32cd7dffda64ddaff4dbd0db6c7cd4`.
2. 사본 `/tmp/b1_gate_b/json_copy` = 원본 로컬 클론 — HEAD 동일, porcelain empty, **매니페스트 sha256 동일값**(`8045f3b1…c7cd4`) — 사본==원본 기록.
3. 각 charon 실행마다: `Cargo.lock` 부재 상태 확인 → 동결 lock 배치(`experiments/serde-json-claim-2026-10-31/inputs/Cargo.lock`, sha256 `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` — 캠페인 핀값과 일치) → 실행 → 사후 lock sha256 **in==out 확인** → `rm Cargo.lock` → porcelain empty 확인.
4. 전체 실행 종료 시점에 사본 find-매니페스트 재계산 → **사전==사후 동일값**(`8045f3b1…c7cd4`).

### 4.3 census 명령열 (28행 전수 동일 형식)

```
CARGO_NET_OFFLINE=true <sandbox>/charon cargo --preset=aeneas \
  --start-from '<정확한 LLBC 이름 — item_names에서 확인>' \
  --dest-file <f> -- --target-dir <t>        # (crate dir에서 실행)
./aeneas -backend lean -dest <out> -split-files <f>     # 플래그 없음 — B-0 §0-H 설계 사실 준수
```

- 시작 이름은 `scan_results.json`의 `example_names_local` 원문(LLBC 이름)과 B-0 §4.3에서 성공한 형태를 그대로 사용. `serde_json::value::Value::as_bool`·`serde_json::number::Number::is_f64`도 이 형태로 charon이 매칭함을 관측(charon exit 0, §5.2 표).
- charon 출력은 LLBC(JSON 직렬화, `charon_version: 0.1.304`)로 쓰이며, 각 행의 digest·fun_decls·시맨틱 특징은 LLBC JSON 파싱으로 산출했다(`item_names` 맵 + `fun_decls` 본문 순회 — 0.1.304는 0.1.281과 JSON 스키마가 다르다: `item_names` 맵 도입, `body`가 문자열(Opqaque 등) 또는 dict(Structured)). unknown-externals 정보는 `-print-unknown-externals`가 아니라 **생성물(TypesExternal_Template.lean / FunsExternal_Template.lean)과 LLBC Opaque 목록**으로 얻었다(§0-H).
- probe fixture 6항목: Axiom4 worktree `tests/fixtures/rust/` 내 각 크레이트에서 동일 명령. fixture `Cargo.lock`은 **repo 추적·의존성 0건** — §8 잠금 프로토콜 불요(선행 문서 판정 유지, 재확인: 실행 전후 `Cargo.lock` sha256 in==out `b1613b75`/`ebeac7d4` + `git status --porcelain` empty를 각 실행마다 관측).

## 5. Result

### 5.1 전체 크레이트 관측 (preset LLBC + 플래그 없는 aeneas)

- 전체 크레이트 추출: charon exit 0, wall 4.5 s (첫 실행, 오프라인 컴파일 `Compiling zmij/serde_core/serde_json/itoa/memchr … Finished dev profile`), lock in==out. LLBC: **`e505aad3ab9042140cd4a80269292c07af2e2326af47c7a0efa91bae372885fc`**, 30,953,117 B.
- LLBC 통계(LLBC JSON 파싱 원문): `fun_decls_total: 2128`, body kinds `{Opaque: 674, Structured: 1166, NULL: 288}`, `type_decls: 232`, `tuple_type_decls: 1`, `has_errors: false`.
- 플래그 없는 aeneas: exit **2**. 임포트·prepass(1840 items)는 **통과**했다 — B-0의 NameMatcher 튜플 크래시는 이 쌍에서 **재현되지 않았다**. prepass 중 6개 본문 무시(원문, ANSI 제거):

```
[Error] Early returns inside of loops are not supported yet
Source: 'src/de.rs', lines 418:4-438:5
[Error] Ignoring the body of 'serde_json::de::{serde_json::de::Deserializer<R>}::scan_integer128' because of previous error
… (parse_exponent:567-621, ignore_value:1102-1215 "Continue to outer loops are not supported yet", ignore_integer:1217-1240, visit_map, Value::serialize 동일 클래스)
```

  이후 원문 종단:

```
[Error] Internal error, please file an issue
Source: '/rustc/library/core/src/iter/traits/iterator.rs', lines 42:0-42:24
Fatal error: exception Aeneas.Errors.CFailure(_)
Raised at Aeneas__Errors.craise_opt_span in file "Errors.ml", line 127, characters 4-46
Called from Aeneas__Errors.cassert_opt_span in file "Errors.ml" (inlined), line 156, characters 16-50
Called from Aeneas__Errors.sanity_check_opt_span in file "Errors.ml" (inlined), line 186, characters 2-74
Called from Aeneas__SymbolicToPureTypes.translate_fun_sigs in file "symbolic/SymbolicToPureTypes.ml", lines 1005-1006, characters 4-57
Called from Aeneas__Translate.translate_crate_to_pure.translate_method_sig in file "Translate.ml", lines 405-406, characters 10-45
… (Stdlib__List.map ×2, translate_crate_to_pure Translate.ml:422-423, translate_crate Translate.ml:2218, Main.ml:765-766)
```

- 오류 클래스 집계(전체 로그 9,174행에서): `[Error] Internal error: please file an issue`(다수, closure 시그니처 클래스 — 예: number.rs:447:51-447:92의 `visit_f64::{{closure}}::call_once`), `[Error] Could not match the contexts`, `Ignoring the body of` 6건. **번역 완료까지 도달한 실행은 아니다** — 최종 종단은 closure 시그니처 sanity check의 CFailure.

### 5.2 census 28행 전수표

모든 행 공통: charon exit **0**(28/28), 잠금 프로토콜 lock in==out `1bc62b1a…`(json 행)·`b1613b75`/`ebeac7d4`(fixture 행, repo 추적 lock), 실행 후 porcelain **empty**(28/28). 열: LLBC 크기(B), 서브그래프 fun_decls(전체/Structured), 시맨틱 특징(대상 함수 본문의 Switch/Loop/Call/Assert 수 — LLBC 파싱), aeneas exit(플래그 없음), 생성 Lean 파일 수, 결과.

| 행 | start-from | identity | charon | LLBC B | funs | Struct | Sw | Lp | Call | Asrt | aeneas | files | 결과 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| c7_parse_line_col | `serde_json::error::parse_line_col` | src/error.rs:494 | 0 | 390,546 | 68 | 3 | 7 | 2 | 16 | 0 | 2 | 0 | CRASH |
| value_as_bool | `serde_json::value::Value::as_bool` | src/value/mod.rs:708 | 0 | 287,338 | 22 | 1 | 1 | 0 | 0 | 0 | 0 | 3 | TRANSLATED |
| number_is_f64 | `serde_json::number::Number::is_f64` | src/number.rs:113 | 0 | 153,596 | 21 | 1 | 1 | 0 | 0 | 0 | 0 | 2 | TRANSLATED |
| de_from_trait | `serde_json::de::from_trait` | src/de.rs:2507 | 0 | 9,033,755 | 456 | 147 | 2 | 0 | 3 | 0 | 2 | 0 | CRASH |
| de_from_reader | `serde_json::de::from_reader` | src/de.rs:2624 | 0 | 10,111,028 | 531 | 188 | 0 | 0 | 2 | 0 | 2 | 0 | CRASH |
| de_from_slice | `serde_json::de::from_slice` | src/de.rs:2667 | 0 | 10,338,643 | 567 | 187 | 0 | 0 | 2 | 0 | 2 | 0 | CRASH |
| de_from_str | `serde_json::de::from_str` | src/de.rs:2709 | 0 | 10,437,741 | 582 | 201 | 0 | 0 | 2 | 0 | 2 | 0 | CRASH |
| error_make_error | `serde_json::error::make_error` | src/error.rs:483 | 0 | 479,256 | 77 | 6 | 0 | 0 | 4 | 0 | 2 | 0 | CRASH |
| error_starts_with_digit | `serde_json::error::starts_with_digit` | src/error.rs:536 | 0 | 149,048 | 23 | 1 | 2 | 0 | 2 | 0 | 0 | 3 | TRANSLATED |
| ser_key_must_be_a_string | `serde_json::ser::key_must_be_a_string` | src/ser.rs:787 | 0 | 276,311 | 27 | 4 | 0 | 0 | 1 | 0 | 0 | 3 | TRANSLATED |
| ser_float_key_must_be_finite | `serde_json::ser::float_key_must_be_finite` | src/ser.rs:791 | 0 | 276,339 | 27 | 4 | 0 | 0 | 1 | 0 | 0 | 3 | TRANSLATED |
| ser_format_escaped_str | `serde_json::ser::format_escaped_str` | src/ser.rs:2069 | 0 | 1,376,172 | 254 | 45 | 2 | 0 | 3 | 0 | 1 | 4 | PARTIAL |
| ser_format_escaped_str_contents | `serde_json::ser::format_escaped_str_contents` | src/ser.rs:2079 | 0 | 1,344,411 | 253 | 44 | 7 | 1 | 14 | 0 | 1 | 4 | PARTIAL |
| ser_to_writer | `serde_json::ser::to_writer` | src/ser.rs:2177 | 0 | 4,289,003 | 481 | 151 | 0 | 0 | 2 | 0 | 2 | 0 | CRASH |
| ser_to_writer_pretty | `serde_json::ser::to_writer_pretty` | src/ser.rs:2197 | 0 | 4,548,552 | 527 | 164 | 0 | 0 | 2 | 0 | 2 | 0 | CRASH |
| ser_to_vec | `serde_json::ser::to_vec` | src/ser.rs:2213 | 0 | 4,353,902 | 497 | 152 | 1 | 0 | 2 | 0 | 2 | 0 | CRASH |
| ser_to_vec_pretty | `serde_json::ser::to_vec_pretty` | src/ser.rs:2229 | 0 | 4,612,142 | 543 | 165 | 1 | 0 | 2 | 0 | 2 | 0 | CRASH |
| ser_to_string | `serde_json::ser::to_string` | src/ser.rs:2245 | 0 | 4,380,552 | 499 | 153 | 1 | 0 | 2 | 0 | 2 | 0 | CRASH |
| ser_to_string_pretty | `serde_json::ser::to_string_pretty` | src/ser.rs:2264 | 0 | 4,638,980 | 545 | 166 | 1 | 0 | 2 | 0 | 2 | 0 | CRASH |
| ser_indent | `serde_json::ser::indent` | src/ser.rs:2276 | 0 | 516,153 | 169 | 1 | 2 | 1 | 3 | 0 | 0 | 4 | TRANSLATED |
| value_parse_index | `serde_json::value::parse_index` | src/value/mod.rs:259 | 0 | 236,830 | 46 | 1 | 3 | 0 | 7 | 0 | 2 | 0 | CRASH |
| value_to_value | `serde_json::value::to_value` | src/value/mod.rs:995 | 0 | 2,875,374 | 436 | 114 | 0 | 0 | 1 | 0 | 2 | 0 | CRASH |
| fx_add_u8 | `axiom_rust_probe::add_u8` | src/lib.rs:3 | 0 | 119,037 | 23 | 2 | 0 | 0 | 0 | 0 | 0 | 2 | TRANSLATED |
| fx_add_u8_mutant | `axiom_rust_probe::add_u8_mutant` | src/lib.rs:9 | 0 | 120,302 | 23 | 2 | 0 | 0 | 0 | 0 | 0 | 2 | TRANSLATED |
| fx_u64_echo | `axiom_u64_probe::u64_echo` | src/lib.rs:1 | 0 | 100,801 | 21 | 1 | 0 | 0 | 0 | 0 | 0 | 2 | TRANSLATED |
| fx_u64_seven_mutant | `axiom_u64_probe::u64_seven_mutant` | src/lib.rs:9 | 0 | 100,887 | 21 | 1 | 0 | 0 | 0 | 0 | 0 | 2 | TRANSLATED |
| fx_u64_add | `axiom_u64_probe::u64_add` | src/lib.rs:13 | 0 | 118,786 | 23 | 2 | 0 | 0 | 0 | 0 | 0 | 2 | TRANSLATED |
| fx_u64_add_mutant | `axiom_u64_probe::u64_add_mutant` | src/lib.rs:17 | 0 | 120,040 | 23 | 2 | 0 | 0 | 0 | 0 | 0 | 2 | TRANSLATED |

집계(json 22행): TRANSLATED 6 + PARTIAL 2 / CRASH 14. fixture 6행: TRANSLATED 6. **전체 28행 중 CRASH 14, PARTIAL 2, TRANSLATED 12.**

LLBC digest 전수표(sha256, bytes) — §5.2 표와 1:1:

| 행 | sha256 | bytes |
|---|---|---|
| c7_parse_line_col | `db32749bbed1c145e3f381531778307cb3c6ff501aa0a4cb98ebf8fb2b687650` | 390,546 |
| value_as_bool | `1df54183e9a9ec82d57ceb4b745d7c74f0cd2072649ba89025b3c7a474b73b31` | 287,338 |
| number_is_f64 | `1d08454be811395d4fbc6ed5e4808decb05a62c8334d81bf4a36452f6788717e` | 153,596 |
| de_from_trait | `8eb87e4ab7c1fc6d27dc3c497b8428fce05f97a959bf3298d178bd9a424598d6` | 9,033,755 |
| de_from_reader | `67ddfef159c5d675f80a250e2c1071fcd8c89050b107d67be868c5f26b74df00` | 10,111,028 |
| de_from_slice | `224f511cfa81b1f407e54957ee612ab928d2960800b86ad617eaeb6c129eb472` | 10,338,643 |
| de_from_str | `6fff9631a8a35149615d67019fa4cea1152db41f20152ccffb4e5626a154c70e` | 10,437,741 |
| error_make_error | `8e3a408e32fb531debc6d17c026421c8861e3d44c759d0b4aacc0013139e45bf` | 479,256 |
| error_starts_with_digit | `7582acde474adf50be5aee86109b2aeb0fc4aa695ee24ebff0d75cac95c76e65` | 149,048 |
| ser_key_must_be_a_string | `826e647f05c7941c73a7299b2090ee8efe11dd3b4c8265c3fc17d1762fb65384` | 276,311 |
| ser_float_key_must_be_finite | `71a7c42339b5378a04f950483e714e04dfd14fcb0bfce32a7e5b0ad26199867f` | 276,339 |
| ser_format_escaped_str | `2c8af1b6feea6a14133cf7489bf8b8945e382a090e3a02a5e7ee5318ed365764` | 1,376,172 |
| ser_format_escaped_str_contents | `bcb0597bf309a0255a455395eb7279332940b782f448adb1169e793317be88ca` | 1,344,411 |
| ser_to_writer | `2a37845ddf977236b5ffe739cc759329f6d882823f6bdf6905bb24b8eeadee71` | 4,289,003 |
| ser_to_writer_pretty | `af6d45f2afd1cb0668775afa042c690b27bde92f09667003f3cbf60b35c1a5ea` | 4,548,552 |
| ser_to_vec | `2d5b48f65df8b250301d6fe3c9f0f6fe2a1082179a82026af14b06063a0c4f6f` | 4,353,902 |
| ser_to_vec_pretty | `0ca4cde09bfaee9d740cc14cdcab7675d96259b175ca2939fb39b2fe249b4eda` | 4,612,142 |
| ser_to_string | `f769a1868d1224db3782690a0769ea82ef7c26f8dd913c3ef6cf7ff390817dc0` | 4,380,552 |
| ser_to_string_pretty | `b1735211812f1d332f1ea03ee086be375bd1ad94903a36c26c008bc09a76b24c` | 4,638,980 |
| ser_indent | `c1c55ef92f3b86ed7e992f15f1771d955b19c8cac3409c177da9d3094af2124f` | 516,153 |
| value_parse_index | `51613eb9bcae81f47def11476917cb4add269372d07a7c092cbadaff75eb3371` | 236,830 |
| value_to_value | `adb4aca7735c772c736bdc63eb9e92f037b59987a2d0f4a00c1e25f4b8069e4c` | 2,875,374 |
| fx_add_u8 | `b801045026be2ebe261444c3ff6af19540488c97daeac387c796b126d64bf2ad` | 119,037 |
| fx_add_u8_mutant | `b5e106ce0ed21d169bbb403058d659e365845e90d6db4b70c5ae7fd16015021d` | 120,302 |
| fx_u64_echo | `b39ee8241069ac2ba7f14439e8a6a9d541a3cf85667bdb39937f0f5cbb4f3626` | 100,801 |
| fx_u64_seven_mutant | `a2bf9c6f20bb4fd3629f16261f2ae8432cf7635af786d03baf28425ed8793271` | 100,887 |
| fx_u64_add | `2f7a6bc81f3a52a3acfaaafaecf37c9bd40621420923c73cb587815bc04a88c9` | 118,786 |
| fx_u64_add_mutant | `d0c6ffea5c7573dabfa80368f948bacb2045a56c1934eb07c424faa06eab285d` | 120,040 |

### 5.3 TRANSLATED 6행(json) + fixture 6행의 상세 — 7필드 완성형

**value_as_bool**(src/value/mod.rs:708, 원문 서명 `pub fn as_bool(&self) -> Option<bool>`): 생성 Lean 원문(`aeneas_out/value_as_bool/Funs.lean`):

```lean
/-- [serde_json::value::{serde_json::value::Value}::as_bool]:
    Source: 'src/value/mod.rs', lines 708:4-713:5
    Visibility: public -/
def value.Value.as_bool (self : value.Value) : Result (Option Bool) := do
  match self with
  | value.Value.Null => ok none
  | value.Value.Bool b => ok (some b)
  | value.Value.Number _ => ok none
  | value.Value.String _ => ok none
  | value.Value.Array _ => ok none
  | value.Value.Object _ => ok none
```

- 시맨틱 특징: 본문 stmt `{Switch: 1}`(enum discriminant match), Loop/Assert 0, 튜플 타입 이름 없음(서브그래프 `tuple_type_decls: 0`).
- opaque 경계(생성물 원문): `TypesExternal_Template.lean`에 외부 타입 1건 —

```lean
/-- [alloc::collections::btree::map::BTreeMap] … -/
@[rust_type "alloc::collections::btree::map::BTreeMap"]
axiom alloc.collections.btree.map.BTreeMap (K : Type _) (V : Type _) (A :
  Type _) : Type
```

  — `Value::Object`의 `Map`(BTreeMap)이 손모델(axiom) 요구로 나타난다. FunsExternal_Template 없음(외부 함수 0).
- aeneas 실행 원문 요지: `Translated transparent functions: 1/1`, `trait declarations: 5/5`, `trait impls: 8/8`, `Total execution time: 0.537343 seconds`, `Generated: …/TypesExternal_Template.lean`, `Types.lean`, `Funs.lean`.

**number_is_f64**(src/number.rs:113, 원문 서명 `pub fn is_f64(&self) -> bool`): 생성 Lean 본문 원문:

```lean
def number.Number.is_f64 (self : number.Number) : Result Bool := do
  match self.n with
  | number.N.PosInt _ => ok false
  | number.N.NegInt _ => ok false
  | number.N.Float _ => ok true
```

생성 파일 2개(Funs.lean, Types.lean) — TypesExternal/FunsExternal 템플릿 없음(외부 타입·함수 0).

**error_starts_with_digit**(src/error.rs:536): TRANSLATED(3 파일). FunsExternal_Template.lean 존재(외부 **함수** 템플릿 — str 연산 클래스), TypesExternal 없음. 시맨틱: Switch 2, Call 2.
**ser_key_must_be_a_string**(src/ser.rs:787)·**ser_float_key_must_be_finite**(src/ser.rs:791): 각 TRANSLATED(3 파일, FunsExternal_Template 존재 — float 클래스). Switch 0·Call 1.
**ser_indent**(src/ser.rs:2276): TRANSLATED(4 파일: Funs·Types·TypesExternal_Template·FunsExternal_Template — 외부 타입·함수 템플릿 **양쪽** 존재). 시맨틱: Switch 2, Loop 1, Call 3 — **루프 포함 서브그래프가 번역에 성공한 유일한 json 행**.

**probe fixture 6행**(번역 정확성 시험 전용): fx_add_u8 생성 Lean 원문(`Funs.lean`):

```lean
/-- [axiom_rust_probe::add_u8]:
    Source: 'src/lib.rs', lines 3:0-5:1
    Visibility: public -/
def add_u8 (a : Std.U8) (b : Std.U8) : Result Std.U8 := do
  a + b
```

u64 6항목도 동일 패턴(외부 템플릿 0, straight-line + AddChecked 산술). fixture 행은 제품 검증 성공으로 계산되지 않는다(§2).

### 5.4 PARTIAL 2행 — 원문

ser_format_escaped_str·ser_format_escaped_str_contents(subgraph가 서로를 포함). aeneas exit **1**, **부분 파일 생성** 원문:

```
[Error] Could not match the contexts
[Warn ] Could not translate the body of function 'serde_json::ser::format_escaped_str_contents because of previous error
[Info ] Generated the partial file (because of 1 errors, including 1 unique errors): /tmp/b1_gate_b/aeneas_out/ser_format_escaped_str/TypesExternal_Template.lean
[Info ] Generated the partial file (because of 1 errors, including 1 unique errors): /tmp/b1_gate_b/aeneas_out/ser_format_escaped_str/Types.lean
[Info ] Generated the partial file (because of 1 errors, including 1 unique errors): /tmp/b1_gate_b/aeneas_out/ser_format_escaped_str/FunsExternal_Template.lean
[Info ] Generated the partial file (because of 1 errors, including 1 unique errors): /tmp/b1_gate_b/aeneas_out/ser_format_escaped_str/Funs.lean
```

44개 transparent 함수 번역 진행 중 1개 본문(format_escaped_str_contents) 미번역 — "부분 파일"은 **불완전 생성물**이며 성공으로 계산하지 않는다.

### 5.5 C7 서브그래프 — 플래그 없음(B-0 시험 2·3의 직접 대조, 첫 관측)

`--start-from serde_json::error::parse_line_col`(start-from 이름은 B-0과 동일), aeneas **플래그 없이** 실행:

- 임포트·prepass(49 items) **통과** — B-0의 NameMatcher 튜플 크래시가 이 입력에서 재현되지 않음(음성 시험 §5.6의 대조로 진단 플래그가 트리거임이 확정).
- 이후 원문(B-0 §5.3의 Opaque callee 8종 중 `rfind`가 새 블로커로 관측됨):

```
[Error] Unimplemented
Source: '/rustc/library/core/src/str/mod.rs', lines 1542:4-1544:53
[Warn ] Could not translate the function signature of 'core::str::{str}::rfind because of previous error
Name pattern: 'core::str::{str}::rfind'
Definition span: '/rustc/library/core/src/str/mod.rs', lines 1542:4-1544:53

This definition is (transitively) used at the following locations:
Source: 'src/error.rs', lines 495:32-495:54
…
[Error] Unimplemented
Source: '/rustc/library/core/src/str/pattern.rs', lines 99:0-99:24
Fatal error: exception Aeneas.Errors.CFailure(_)
Raised at Aeneas__Errors.craise_opt_span in file "Errors.ml", line 127, characters 4-46
Called from Aeneas__Errors.cassert_opt_span in file "Errors.ml" (inlined), line 156, characters 16-50
```

- LLBC 측 동반 기록: C7 서브그래프 fun_decls 68(Structured 3, Opaque 46, null 19), 대상 본문 stmt 히스토그램 `{StorageLive:75, Assign:66, Call:16, StorageDead:191, UnwindResume:16, Switch:7, Borrowck:7, Loop:2, Continue:2, Break:2, Return:2}`, locals 76·named_locals 원문 일치(`msg, start_of_suffix, index, start_of_line, end_of_line, start_of_column, end_of_column, line×2, column×2` — B-0 §5.2와 동일), 서명 identity: `fn parse_line_col(msg: &mut String) -> Option<(usize,…`(src/error.rs:494).
- **판정 가능한 최소 문장**: charon 0.1.304로 동일 재추출했을 때 C7의 aeneas 블로커는 "튜플 타입 이름 크래시"에서 **`core::str::rfind` 시그니처 Unimplemented → CFailure**로 이동했다. B-0 §5.3에서 Opaque로 기록된 8개 직접 callee 중 rfind가 여전히 LLBC에 본체 없이(0.1.304 기본 preset) 참조되며, aeneas는 그 시그니처 번역 자체에 실패한다.

### 5.6 음성 대조 — `-print-unknown-externals` 부여 (C7 서브그래프, 동일 LLBC 입력 `db32749b…`)

```
Fatal error: exception Failure("Can't convert the name of a tuple to a pattern")
Raised at Stdlib.failwith in file "stdlib.ml", line 29, characters 17-33
Called from Charon__NameMatcher.name_to_pattern_aux in file "charon-ml/src/NameMatcher.ml" (inlined), lines 908-909, characters 2-33
Called from Charon__NameMatcher.name_to_pattern in file "charon-ml/src/NameMatcher.ml", line 1103, characters 12-39
Called from Aeneas__LlbcAstUtils.name_to_pattern in file "llbc/LlbcAstUtils.ml", line 130, characters 8-50
Called from Aeneas__LlbcAstUtils.name_with_crate_to_pattern_string in file "llbc/LlbcAstUtils.ml", line 143, characters 12-41
Called from Dune__exe__Main.(fun) in file "Main.ml", lines 688-689, characters 16-60
```

B-0 시험 2·3과 **동일 크래시 원문**(Main.ml 685-693의 진단 블록 — B-0 원문은 `Main.ml, lines 914-915`의 NameMatcher 내부 행 번호만 상이). → **§0-H 설계 사실의 재확정**: 그 플래그 없이는(본 census 전 행) 튜플 크래시는 발생하지 않았고, 부여 시 C7 서브그래프에서 정확히 재현된다. 번역 경로 관측은 플래그 없이만 수행했다.

### 5.7 변이 — `--extract-opaque-bodies` (PR #1255 선행 관측의 0.1.304 재현 판정)

**관측 1 — 플래그 존재 양상(원문)**: `charon --help`에는 `--opaque`(blacklist)만 문서화되고 `--extract-opaque-bodies`는 **목록에 없다**. 그러나 플래그를 부여한 charon cargo 실행은 **받아들여져 동작**했다(아래 관측 2·3 — 원문 기록). **[해석 정정 2026-11-04]** 위 문장의 이전 괄호 해석 "미문서화 플래그로서의 동작"은 오류였다 — `--extract-opaque-bodies`는 최상위 `charon --help` 목록에는 없으나 `charon help rustc`(하위명령 도움말)와 상류 공식 문서(charon 저장소 `docs/what_charon_translates.md`·`docs/faq.md`)에는 문서화돼 있다(상류 원문 인용 근거: 본 저장소 `docs/evidence/b1_semantic_unit_selection_survey_2026-11-04.md` §2 Context — "Makes all items transparent…" / "the hammer that removes this filter…"). 본 정정은 해석 오류의 정정이며 위 관측 문장은 불변으로 유지된다.

**관측 2 — as_bool 변이**: `charon cargo --preset=aeneas --extract-opaque-bodies --start-from 'serde_json::value::Value::as_bool'` → exit 0, lock in==out. LLBC `5a9663421be3f9f576206f46adf23ff7828e9cfa470f2420b000a44623a55eff`:
- 기본 행: fun_decls **22**(Structured 1 / Opaque 20 / null 1) → 변이: fun_decls **1525, 전부 Structured**(`{"Structured": 1525}`), type_decls 241. **Opaque 본문의 Structured 추출이 0.1.304+preset에서 재현**되었다 — PR #1255(agent-93, 0.1.281, Opaque 8종→Structured 본문, fun_decls 2134→5037)와 동일 클래스의 관측.
- 변이 LLBC의 aeneas: exit **1**, 부분 생성(`Generated the partial file (because of 52 errors, including 7 unique errors): …/Funs.lean`). 오류 클래스 원문: `[Error] Internal error: please file an issue`(다수), `Encountered an error when analyzing the following type declarations group`, `unsupported type: (Generated_Types.TPattern (…`, `unions are not supported`, `Breaks to outer loops are not supported yet`, `Continue to outer loops are not supported yet`. transparent 함수 진행 `0/1` 구간에서 종료된 부분 생성 — 변이는 **본문 추출을 늘리지만 번역 성공으로 이어지지 않았다**.

**관측 3 — C7 변이**: `charon cargo --preset=aeneas --extract-opaque-bodies --start-from 'serde_json::error::parse_line_col'` → exit 0, wall 2.13 s, lock in==out, porcelain empty. LLBC **`de507547ef6fd28c41f7efe7c5cb87841cbd87b3c06f7cda15f601d0fc3f5086`**, 24,146,374 B(기본 390,546 B의 ~62배), fun_decls **1553 전부 Structured**(기본 68/Structured 3).
- 변이 LLBC의 aeneas: exit **2**, 생성 파일 **0**. 오류 클래스 원문(집계): `[Error] Internal error: please file an issue` ×51, `Encountered an error when analyzing the following type declarations group` ×31, `unsupported type: (Generated_Types.TPattern (…` ×3, `unions are not supported` ×2, `Mixed declaration groups (which contain both type and function declarations or functions and traits, for instance) are not supported yet: [57, 58, 50, 87, 42]` ×1. rfind도 이제 본문이 추출되지만(str::pattern TwoWaySearcher 등), 번역은 새로운 클래스(union·혼합 선언 그룹·TPattern)에서 사망한다.
- 재현 판정 요지: **"본문 추출 확장"은 재현되지만, PR #1255가 보고한 "Opaque callee 8개 전부 Structured + 잔존 Extern 9" 수준의 정리 상태에서 번역 가능성이 열리는지는 이 쌍에서 관측되지 않았다** — C7 변이는 기본 행보다 더 이른 단계(타입 그룹 분석)에서 실패했다.

### 5.8 Lean 컴파일 단계 (TRANSLATED 항목의 3단계 전제 — 측정된 경계)

- 사용 환경: 번들 `backends/lean`(사전 빌드 `.lake/build` 426 MB 포함), `lean-toolchain` `leanprover/lean4:v4.35.0`, elan 경유 `Lean (version 4.35.0, …, commit eb6cafb7290e8bd5f2937522d8d804f58f02bafc, Release)`.
- as_bool 생성물 3파일을 `ItemValueAsBool/`로 배치(템플릿 지시 원문대로 `TypesExternal_Template.lean` → `TypesExternal.lean` 리네임), `LEAN_PATH=<…>.lake/build/lib/lean`으로 순서 컴파일 시도 → **전부 실패**, 원문:

```
ItemValueAsBool/TypesExternal.lean:4:0: error: unknown module prefix 'Mathlib'
No directory 'Mathlib' or file 'Mathlib.olean' in the search path entries:
/tmp/b1_gate_b/lake_ws/lean/.lake/build/lib/lean
<user-home>/.elan/toolchains/leanprover--lean4---v4.35.0/lib/lean
```

- 원인 기록: 생성물의 임포트는 `public import Aeneas`(플래그 `-use-lean-modules false`로 생성해도 `import Aeneas`)뿐이지만, **Aeneas 라이브러리 자체가 Mathlib을 require**하며(lakefile 원문: `require mathlib from git "https://github.com/leanprover-community/mathlib4.git" @ "v4.35.0"`, lake-manifest 원문에 mathlib·batteries·aesop 등 9패키지), 번들에는 Aeneas의 `.lake/build`만 있고 **Mathlib olean은 미포함**(`.lake/packages` 부재 실측). → 이 쌍의 생성물 컴파일은 **mathlib v4.35.0 프로비전이 선행 요구사항**이다. 본 실험은 mathlib fetch·build를 수행하지 않았다(범위 밖·시간 예산) — Lean 컴파일 단계는 **요구사항 기록으로 미완결**이며, 성공으로 계산되지 않는다.

### 5.9 const 13항목 제외 사유 (원문)

`scan_results.json` candidates 13은 전부 `params: []`인 const 항목이다. 원문 예: `{"name": "serde_json::ser::BB", "params": [], "ret": "u8", …, "sig_line": "const BB: u8 = b'b'; // \x08", "src": "serde_json:src/ser.rs:2135"}` 및 `{"name": "serde_json::read::<impl serde_json::read>::should_early_return_if_failed", "params": [], …, "sig_line": "const should_early_return_if_failed: bool = true;"}`. 함수 census가 아니라 상수항이므로 본 census에서 제외한다.

## 6. Evidence

산출물 해시(핵심 — `/tmp/b1_gate_b` 측정, 2026-11-04):

| 파일 | sha256 | 비고 |
|---|---|---|
| `aeneas-linux-x86_64.tar.gz` (릴리스 자산) | `ed0e336c506dad37e4e1c53f6cc4d6d5959d7e3afab2fd55aead280775651f5e` | 158,648,932 B |
| `aeneas_bundle/aeneas` | `12e6042cfb00aba8ea8b6ef2811f55867e4fc8bf56bcc96c5a7d52ab9fd53a9c` | `-version` 원문 §4.1 |
| `aeneas_bundle/charon` | `4226741660099a31be54bde273e9193dd5a44154df7eb203c3c333d83b32a59c` | `0.1.304 (7b462d91…)` |
| `aeneas_bundle/charon-driver` | `bb0f4073c59f7fab47f8e133d761806c17dad09dab9aa6c0116aa057380300e9` | — |
| `llbc/full_preset.llbc` | `e505aad3ab9042140cd4a80269292c07af2e2326af47c7a0efa91bae372885fc` | 30,953,117 B, 전체 크레이트 |
| `llbc/item_c7_opaque.llbc` (C7 변이) | `de507547ef6fd28c41f7efe7c5cb87841cbd87b3c06f7cda15f601d0fc3f5086` | 24,146,374 B |
| `llbc/item_as_bool_opaque.llbc` (as_bool 변이) | `5a9663421be3f9f576206f46adf23ff7828e9cfa470f2420b000a44623a55eff` | — |
| 동결 `Cargo.lock` (in==out, 22 json 행 전부) | `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` | B-0 §4.3 재확인 |
| 서브젝트 원본·사본 find-매니페스트 | `8045f3b1ce56398fe506aeec9f9344405e32cd7dffda64ddaff4dbd0db6c7cd4` | 사전==사후 |

행별 LLBC sha256 28건은 §5.2의 digest 전수표가 정본이다. 런 로그 원본(`/tmp` 소멸성) — 본 문서 인용이 정본 복사본이다: `aeneas_full_run.log`(전체), `logs/*.aeneas.log`(행별), `logs/c7_negative_flag.log`(음성), `logs/c7_opaque.aeneas.log`·`logs/as_bool_opaque.aeneas.log`(변이), `logs/c7_opaque2.log`(변이 charon).

## 7. Classification

### 7.1 3단계 구분 (측정된 곳만 완결 표기)

| 단계 | 측정 결과 | 근거 |
|---|---|---|
| (1) 본문 추출 | **28/28 성공** (charon exit 0, 대상 함수 Structured 본체 LLBC 존재 — §5.2 전 행; C7 원문 서명·named_locals까지 B-0 일치) | §5.2 표, §5.5 |
| (2) 모델 변환 | **12/28 성공**(TRANSLATED 6 json + 6 fixture), 2/28 부분(PARTIAL), 14/28 실패(CRASH) — json 실함수 기준으로는 **6 TRANSLATED / 2 PARTIAL / 14 CRASH** | §5.2–§5.5 |
| (3) sorry 없는 명제 증명 | **어디서도 도달하지 않음 — 요구사항 기록**: (a) 번역 성공 항목도 `Result`-모나드 모델 def일 뿐 명제·증명 없음, (b) TypesExternal/FunsExternal 템플릿의 손모델(axiom) 작성이 선행 요구(as_bool의 BTreeMap axiom 원문 §5.3), (c) 생성물 컴파일에는 mathlib v4.35.0 프로비전이 선행 요구(§5.8), (d) 공식 문서상 aeneas 생성물은 검증 증명이 아니라 모델이며 sorry-free 증명은 별도 작업이다. **Aeneas가 Lean 파일을 생성하는 것은 3단계가 아니다.** | §5.3, §5.8 |

### 7.2 Aeneas 어댑터 채택 vs Axiom 자체 최소 의미론 — 측정 기반 결정 근거

**결정 자체는 본 문서가 내리지 않는다(별도 계약 개정 사항 — §0.12).** 아래는 관측된 사실만의 정리다:

- **범위(커버리지) 관측**: json 실함수 21 중 이 쌍이 플래그 없이 완전 번역한 것은 **6**(as_bool, is_f64, starts_with_digit, key_must_be_a_string, float_key_must_be_finite, indent). 부분 2, 실패 13(C7 포함). fixture 6은 전부 성공(번역 정확성 시험용). 즉 **어댑터를 채택해도 인서먼트의 즉시 커버리지는 ~29%(6/21)이며, 실패 14행의 블로커는 aeneas 측 미구현/내부 오류(rfind 시그니처, closure sanity check, union, 혼합 선언 그룹, 루프 제어 흐름)로 상류 의존적이다.**
- **비용 관측**: (a) 번역 자체는 저비용(행당 charon 0.3–1.1 s + aeneas 0.25–2.9 s — 28행 전수가 수십 초)이나, (b) **생성물 소비 비용이 지배적**이다: Aeneas 라이브러리 의존(mathlib v4.35.0 포함 — lakefile 원문) + 손모델 템플릿 작성(TypesExternal/FunsExternal) + Axiom4 저장소 핀(Lean 4.33.0)과의 툴체인 분리 유지. (c) 추출 계약은 `--preset=aeneas` 필수(B-0 시험 1 원문 재확인 사항) — Axiom lane의 `charon cargo --dest-file` 호출형과는 별도 경로다.
- **신뢰 경계 관측**: aeneas는 추출을 Charon과 공유하므로 독립 검증이 아니다(B-0 §8.2). 변이 관측(§5.7)은 본문 추출 확장 시에도 번역 단계의 상류 버그 클래스(Internal error ×51, unions, Mixed declaration groups)가 새로 나타남을 보였다 — **어댑터 채택은 aeneas 상류의 미구현 집합을 Axiom의 신뢰 경계 안으로 수입하는 행위**에 해당한다(측정 사실 서술).
- **대안과의 접점 관측**: TRANSLATED 12행의 생성 모델은 Axiom v1 문법 밖의 구성요소(Result 모나드, enum match, Loop)를 포함한다 — 반면 fixture의 straight-line 산술(`add_u8 := do a + b`)은 v1 문법 내 구성요소다. 자체 최소 의미론 구현의 대상 범위는 fixture 관측과 일치하는 축소 집합이며, aeneas 성공 6행은 그보다 넓은 Adt/Switch/Loop 범위를 상류가 이미 처리함을 보였다.

### 7.3 Terminal Outcome (관찰자 판정)

- **번역 계층은 B-0의 No-Go에서 "부분 Go(6/21 실함수)"로 관측이 갱신되었다** — 단, 3단계(증명)는 어디서도 도달하지 않았고 Lean 컴파일 단계도 mathlib 요구로 미완결이다(요구사항 기록).
- C7: NameMatcher 튜플 크래시는 소멸(진단 플래그에 한해 재현 — §5.6), 신규 블로커 `core::str::rfind` Unimplemented(CFailure) 원문 고정. **C7은 SCOPE_LIMIT 유지의 측정 근거가 갱신**되었을 뿐, 어떤 판정도 변경되지 않았다.
- `--extract-opaque-bodies` 변이: 본문 추출 확장(as_bool 22→1525 전 Structured, C7 68→1553 전 Structured)은 재현 — 그러나 번역은 개선되지 않고 새 오류 클래스로 실패. PR #1255 관측의 "재현성"은 **추출 확장에 한해 yes, 번역 개선에 대해 no**.
- fixture 6/6 번역 성공은 **번역 정확성 시험의 입력 가능성**만 보이며 제품 성공 아님(§2).

## 8. Interpretation

### 8.1 census의 성공/실패 축은 "서브그래프 크기"와 상관한다

TRANSLATED 6행의 서브그래프는 funs 21–169(기본 preset, Opaque 본문 미포함), CRASH 14행은 funs 436–582(de/ser 진입점 — serde 트레이트 기계 흡수)다. aeneas는 작은 닫힌 서브그래프에서는 이미 실용적으로 번역한다. 이는 어댑터 채택 논의를 "전 크레이트 vs 단일 함수" 이분법에서 **"서브그래프 크기 제어(--start-from + --opaque 경계 설계)"** 축으로 옮겨야 함을 보인다(§7.2 범위 관측의 해석).

### 8.2 진단 플래그는 번역 경로의 일부가 아니다

§5.6의 음성 재현은 B-0 §0-H 설계 사실(플래그 진단 블록이 유일한 NameMatcher 크래시 트리거)을 정확히 재확인했다. 본 census의 모든 행은 플래그 없이 수행되었으므로, §5.2의 결과는 **번역 경로의 순수 관측**이다.

### 8.3 극장 금지 준수

실패 14행·부분 2행·Lean 미완결을 모두 원문 기록했다. "Lean 파일이 생성되었다"를 컴파일 성공이나 증명 성공으로 재포장하지 않았고(§5.8), fixture 성공을 제품 검증으로 계산하지 않았다(§2). 발견된 상류 오류는 Axiom4 극장 레지스트리 대상이 아니다(우리가 도입·은폐한 것이 아니라 외부 도구의 관측된 한계다 — 패치·우회도 하지 않았다).

## 9. Non-Conclusions

- **serde_json 및 C1~C8에 대한 참/거짓 판정은 없다.** 본 문서는 Gate A의 증명 실험과 독립이며 as_bool 행은 독립 재현 측정이다.
- **"Aeneas가 serde_json의 X를 검증한다"는 성립하지 않는다.** 성립한 것은 이 입력·이 쌍·이 시점의 번역 성공/실패 관측뿐이다. 생성물은 모델이지 증명이 아니다.
- **어댑터 채택/기각의 결정은 없다.** §7.2는 측정 근거 제공이며 결정은 별도 계약 개정으로만 가능하다.
- **제품 표면·lane·핀의 변경은 없다.** `src/` 무변경, FROZEN(src/gate/**·Makefile·config/policy/**·.github/**·AGENTS.md) 무접촉, Axiom4 Lean 핀 4.33.0 무변경(v4.35.0은 aeneas 샌드박스 전용), 서브젝트 원본·main worktree 무수정(§4.2 매니페스트 대조).
- charon/aeneas 상류 동작의 일반화("0.1.304에서 항상…")는 성립하지 않는다 — 본 관측은 특정 릴리스 자산(`ed0e336c…`)에 대한 것이다.

## 10. Next Experiment (제안 — 권한 부여 아님)

1. **mathlib v4.35.0 프로비전 하의 Lean 컴파일 완결** — TRANSLATED 12행 생성물 + 손모델 템플릿 최소 작성(BTreeMap axiom 등)으로 `lake build`까지의 관측. §5.8의 미완결을 닫는 직접 후속.
2. **서브그래프 경계 설계 측정** — `--opaque`/`--include` 조합으로 CRASH 14행(de/ser 진입점)을 축소 번역 가능한지의 행 추가. §8.1 해석의 검증.
3. **`-print-unknown-externals` 없이 unknown-externals 목록의 공식 경로 확보** — 본 실험은 생성물 템플릿으로 대체했으나, 상류가 진단 플래그를 리팩터링하면 NameMatcher 크래시 소멸 여부를 재관측해야 한다.
4. **Gate A as_bool 증명 실험과의 합류** — 본 문서 §5.3의 생성 모델은 Gate A가 독립 증명 중인 as_bool의 대조 모델이 될 수 있다(독립성 유지: 모델 소비는 어느 쪽 판정도 변경하지 않는다).

## Deviations

1. 변이 최초 실행 시 `--extract-opaque-bodies` 미부여 상태로 2행을 실행해 같은 라벨로 CSV에 기록한 실수가 있었다 — **해당 2행과 그 산출물은 삭제했고**(§5.7의 변이 데이터는 플래그 부여 재실행이 정본), 기록용 Census rows CSV는 정정본을 사용한다. 재실행 변이(charon exit 0·lock in==out·porcelain empty 포함)가 §5.7의 정본이다.
2. C7 변이의 첫 플래그 부여 실행이 잘못된 cwd(`/tmp/b1_gate_b`)에서 실행되어 `could not find Cargo.toml`로 실패했다 — 원문 보존. 올바른 cwd 재실행(§5.7 관측 3)이 정본이다.
3. per-item 실행마다의 find-매니페스트 사전/사후 대조는 수행하지 않았다(B-0 §4.3과 동일한 축소 — 대신 매 실행의 lock in==out + porcelain empty와 시작·종료 시점의 전체 매니페스트 대조로 대체).
4. lake 빌드는 `lake build`가 아니라 `LEAN_PATH` 직접 컴파일로 시도했다 — 이유: 번들 lakefile이 mathlib git require를 포함해 `lake build` 진입 자체가 네트워크·장시간 작업이 되기 때문. §5.8의 측정 성격(컴파일 가능성 관측)은 동일하다.

## 결정론 기록 (Determinism Record — B-0 §12 형식 항목 (a)–(i))

| 항목 | 값 |
|---|---|
| (a) Rust 대상 commit + 대상 identity | subject `8c535a260ce561eaab4111aafc29038eb9f77ff3`(원본 HEAD·clean·매니페스트 `8045f3b1…` 기록); 28행의 identity는 §5.2 표(span + source_text 원문) |
| (b) Charon 실행 identity | 번들 `/tmp/b1_gate_b/aeneas_bundle/charon` — `charon version` → `0.1.304 (7b462d9159db2ed3015162352183906a30bfafc6)` exit 0, sha256 `4226741660099a31be54bde273e9193dd5a44154df7eb203c3c333d83b32a59c`; `charon toolchain-version` → `nightly-2026-09-17`; 명령: `charon cargo --preset=aeneas [--extract-opaque-bodies] --start-from '<이름>' --dest-file <f> -- --target-dir <t>` (crate dir, CARGO_NET_OFFLINE=true). 추출용 rustc identity: **1.100.0-nightly (923c95cdf 2026-09-16)**; 실행 기준 stable rustc 1.95.0 (59807616e 2026-04-14) — **이중 identity 별기 기록** |
| (c) 입력 LLBC 해시 | 행별 §5.2 digest 전수표(28건); 전체 크레이트 `e505aad3…`; 변이 2건 `de507547…`·`5a966342…` |
| (d) Aeneas 버전/커밋 | release `nightly-2026.11.03-ab34bd2`, `-version` 원문 `aeneas nightly-2026.11.03-ab34bd2`, 바이너리 sha256 `12e6042c…`; 저장소 클론 HEAD `ab34bd28458a08c150b7cbf1873e59af74588138` |
| (e) 동일 LLBC가 aeneas에 입력된 증거 | 각 행의 aeneas 로그 첫 행 원문 `[Info ] Imported: /tmp/b1_gate_b/llbc/item_<행>.llbc` + 입력 파일 sha256 고정(§5.2). 음성 시험은 기본 행과 **동일 파일**(`item_c7_parse_line_col.llbc`, `db32749b…`)을 재사용(cp 없이 절대경로 참조) |
| (f) 생성 Lean 모델 빌드 결과 | **TRANSLATED 12행 생성물 컴파일 미완결** — 원인 원문 `unknown module prefix 'Mathlib'`(Aeneas 라이브러리의 mathlib require, 번들에 Mathlib olean 미포함). 요구사항: mathlib v4.35.0 프로비전 + 손모델 템플릿. Lean v4.35.0(elan, commit eb6cafb7…)은 사용됨 — 저장소 핀 4.33.0 무변경 |
| (g) 미구현 외부 목록 | `-print-unknown-externals` 미사용(§0-H). 대응물: (i) 생성물 템플릿 — as_bool `TypesExternal_Template.lean`(BTreeMap axiom 1건), starts_with_digit·key_must_be_a_string·float_key_must_be_finite `FunsExternal_Template.lean`, indent 양쪽, is_f64·fixture 템플릿 0건; (ii) LLBC Opaque 집계(§5.2 opaque 열 — 예: C7 서브그래프 Opaque 46, de_from_str 380) |
| (h) 구성요소별 지원 표 | §5.2(28행) + §7.1(3단계) — Aeneas 처리 열은 관측된 것만 |
| (i) 재현 명령열 | 아래 블록 |

```sh
# (0) 샌드박스·조달
mkdir -p /tmp/b1_gate_b && cd /tmp/b1_gate_b
curl -sL --fail -o aeneas-linux-x86_64.tar.gz \
  https://github.com/AeneasVerif/aeneas/releases/download/nightly-2026.11.03-ab34bd2/aeneas-linux-x86_64.tar.gz
sha256sum aeneas-linux-x86_64.tar.gz   # ed0e336c506dad37e4e1c53f6cc4d6d5959d7e3afab2fd55aead280775651f5e
mkdir -p aeneas_bundle && tar xzf aeneas-linux-x86_64.tar.gz -C aeneas_bundle
./aeneas_bundle/charon version         # 0.1.304 (7b462d9159db2ed3015162352183906a30bfafc6)
./aeneas_bundle/aeneas -version        # aeneas nightly-2026.11.03-ab34bd2
git clone --depth 1 --branch nightly-2026.11.03-ab34bd2 https://github.com/AeneasVerif/aeneas aeneas_src

# (1) 서브젝트 검증 사본 (원본 무수정)
git clone "<workspace>/json" /tmp/b1_gate_b/json_copy
cd /tmp/b1_gate_b/json_copy && git rev-parse HEAD   # 8c535a260ce561eaab4111aafc29038eb9f77ff3

# (2) §8 잠금 프로토콜 + census 행 (28행 전부 동일 형식; <name>은 §5.2 표)
cp .4/experiments/serde-json-claim-2026-10-31/inputs/Cargo.lock Cargo.lock
sha256sum Cargo.lock                   # 1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4
CARGO_NET_OFFLINE=true /tmp/b1_gate_b/aeneas_bundle/charon cargo --preset=aeneas \
  --start-from '<name>' --dest-file /tmp/b1_gate_b/llbc/item_<label>.llbc \
  -- --target-dir /tmp/b1_gate_b/charon-target
sha256sum Cargo.lock && rm Cargo.lock  # in==out 확인 후 제거
cd /tmp/b1_gate_b && mkdir -p aeneas_out/<label>
./aeneas_bundle/aeneas -backend lean -dest aeneas_out/<label> -split-files llbc/item_<label>.llbc
# → exit 0(TRANSLATED) / 1(PARTIAL) / 2(CRASH) — 원문 로그 logs/<label>.aeneas.log

# (3) 음성 대조 (진단 플래그 — §5.6)
./aeneas_bundle/aeneas -backend lean -dest aeneas_out_neg_c7 -split-files \
  -print-unknown-externals llbc/item_c7_parse_line_col.llbc
# → exit 2, Fatal error: exception Failure("Can't convert the name of a tuple to a pattern")

# (4) 변이 (§5.7)
cd /tmp/b1_gate_b/json_copy && cp ../inputs경로/Cargo.lock Cargo.lock
CARGO_NET_OFFLINE=true ../aeneas_bundle/charon cargo --preset=aeneas --extract-opaque-bodies \
  --start-from 'serde_json::error::parse_line_col' --dest-file ../llbc/item_c7_opaque.llbc \
  -- --target-dir ../charon-target-opq
# as_bool 동일. sha256sum Cargo.lock → in==out → rm

# (5) fixture 행 (§4.3) — Axiom4 worktree tests/fixtures/rust/<probe>에서 동일 명령
#     (Cargo.lock repo 추적·의존성 0 — lock 프로토콜 불요, in==out + porcelain 확인만)
```

## Landing record

- (착지 후 기록 — PR 번호, head sha, merge queue 진입 상태는 본 섹션에 추가하지 않고 최종 인계 보고에 기재된다. 본 문서는 단일 커밋으로 착지된다.)
