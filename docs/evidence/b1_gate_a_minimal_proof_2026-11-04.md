# B-1 Gate A — 최소 증명 실험: serde_json `Value::as_bool` Rust→LLBC→Lean 커널 증명 (2026-11-04)

> **Status**: Observation evidence record — 읽기 전용 조사 (`src/` 무수정, 제품 코드 무변경, main worktree 무수정; 모든 시험은 `/tmp` 샌드박스에서 수행, 본 문서 1건만 Axiom4에 착지)
> **Created**: 2026-11-04
> **Written at**: branch `work/b1-gate-a-2026-11-04` (base = origin/main `76efe1fcccc9e0dd0fc60e3c6e310dad4b63d7fe`)
> **Governing docs**: [docs/evidence/serde_json_c7_semantics_aeneas_2026-11-03.md](serde_json_c7_semantics_aeneas_2026-11-03.md) (B-0 — §8 잠금 프로토콜·aeneas 시험 4회 전임 관측) · [experiments/serde-json-claim-2026-10-31/FREEZE.md](../../experiments/serde-json-claim-2026-10-31/FREEZE.md) (§3 서브젝트 핀, §4 잠금 프로토콜)
> **원칙**: 기계 출력과 오류 문자열은 원문 그대로 인용한다(재작성·요약·번역 없음). 이 문서는 관찰을 기록하며 serde_json이나 Aeneas에 대한 어떤 참·거짓 주장도 하지 않는다 (§Non-claims).

7-field identity (FREEZE.md §1 형식 준용 — 값은 본 문서 정체성):

- PROJECT_UNDER_TEST: serde_json (Rust crate) v1.0.154 — **B-1 Gate A 최소 증명 실험**: 공식 호환 Charon/Aeneas 쌍이 `serde_json::value::Value::as_bool` 1개를 Rust 소스→LLBC→Lean 번역→손모델 보강→커널 증명→Rust 실행 대조→mutation 음성→cold 재현까지 **운반할 수 있는가**의 관측
- REVISION: `8c535a260ce561eaab4111aafc29038eb9f77ff3` (subject HEAD — 2026-10-16 "Move test-only API of Number to extension trait", `git status --porcelain` 0행 clean 재확인)
- AXIOM_REVISION: `76efe1fcccc9e0dd0fc60e3c6e310dad4b63d7fe` (origin/main, PR #1257 merge — 브랜치 base)
- CONFIG: 읽기 전용 관찰 + `/tmp/b1_gate_a*` 샌드박스 시험만. charon·cargo 실행은 `CARGO_NET_OFFLINE=true`로 오프라인 수행(네트워크 fetch 0건 — §4.3). 증명 측 lake은 mathlib 캐시(`cache.mathlib.org`, 9,031 파일)와 git 의존을 **네트워크에서 1회 확보**했다(§5.5 — 추출 파이프라인과 증명 파이프라인의 네트워크 경계는 다르다).
- TOOLCHAIN_ID: **이중 rustc identity — 두 컴파일러는 서로 다른 컴파일러다** (§4.1). 참조: [docs/evidence/serde_json_claim_adjudication_2026-10-31.md](serde_json_claim_adjudication_2026-10-31.md) 캠페인 계보
- SCOPE: 단일 함수 `as_bool`의 전 파이프라인 운반 관측. **범위 밖**: C1~C8 참/거짓 판정·제품 레인/production 핀 변경·Aeneas 채택 결정·번역 경로의 일반화(함수 1개 관측)·증명 재사용 계약 설계
- EXPERIMENT_ID: b1-gate-a-minimal-proof-2026-11-04

---

## 1. Question

이 문서가 답하는 질문:

1. **공식 호환 Charon/Aeneas 쌍**(같은 릴리스 태그 번들)이 serde_json의 실제 함수 1개를 Rust 소스부터 Lean 커널 증명까지 운반할 수 있는가 — 각 단계의 exit·wall·해시·원문 출력으로 관측할 수 있는가?
2. 번역 산출물 위에 **sorry 없는 손모델**(외부 타입의 최소·정직한 추상화)을 얹어, 문서 계약 기반의 **독립 명제**를 커널이 승인하게 할 수 있는가 — `#print axioms`의 사용 전제는 무엇인가?
3. **Rust 원본의 단일 라인 변이**가 추출→번역→증명 전체에 전파하는가 (mutation 음성) — 그리고 동일 명령·신선 상태로 **cold 재현**이 5축(exit·status·identity 해시·의미 결과·stdout 차이 분석)에서 어떻게 닫히는가?

## 2. Context

- B-0([serde_json_c7_semantics_aeneas_2026-11-03.md])은 charon 0.1.281 핀의 LLBC 재추출 능력(오프라인, lock in==out, 매니페스트 사전==사후)을 입증했으나, Aeneas 번역은 4회 시험 전부 `-print-unknown-externals` 진단 블록의 NameMatcher 튜플-이름 크래시로 함수 번역 0건에 종료했다. **번역 경로(PrePasses→Translate)는 B-0에서 관측된 적 없다.**
- 본 실험은 §0-H 사실(크래시의 유일한 Main.ml 트리거가 `print_unknown_externals` 플래그 블록임)에 따라 **그 플래그를 부여하지 않고** 공식 호환 쌍(aeneas `nightly-2026.11.03-ab34bd2` + 번들 charon `0.1.304`)으로 번역 경로를 처음 관측한다.
- 대상 함수 선정 근거: `as_bool`은 (a) 문서 계약이 2절로 명확하고("If the `Value` is a Boolean, returns the associated `bool`. Returns `None` otherwise."), (b) 본문이 callee 0개의 순수 스위치여서 외부 함수 스텁 없이 독립 명제가 성립하며, (c) 6-변형 enum 전체를 case analysis가 통과하므로 타입 closure·손모델·mutation 음성이 모두 관측 가능한 최소 단위다.

## 3. Scope

- **범위 안**: (a) 공식 릴리스 번들 조달·동일성 기록, (b) §8 잠금 프로토콜 하의 `--start-from` 최소 추출과 타입 closure 전수 분석, (c) aeneas 번역(플래그 없음)과 생성물 원문 기록, (d) 생성 Lean의 lake 빌드(v4.35.0, Aeneas 라이브러리 path 의존), (e) 외부 타입 최소 손모델 2종(F64·BTreeMap)의 계약·근거 기록, (f) 독립 명제 2절 증명과 `#print axioms`, (g) stable rustc 실행 대조(7입력), (h) 전 파이프라인 mutation 음성, (i) detached cold 재현 5축.
- **범위 밖**: 다른 함수·크레이트로의 일반화, 증명 산출물의 제품화(lane·게이트·인증서), Aeneas 도구 결함의 수정 제안, 수학적 표준 라이브러리 모델 정합성 검증(Aeneas Std 자체는 TCB로 수용).
- 서브젝트 원본(`<workspace>/json`)은 무수정 — 작업은 전부 검증 사본(`json_copy`)·변이 사본(`json_mut`)·cold 사본에서 수행했다.

## 4. Procedure (결정론 기록 (a)–(i))

### 4.1 FREEZE — identity 고정

- **서브젝트**: `8c535a260ce561eaab4111aafc29038eb9f77ff3`, clean. 대상: `serde_json::value::Value::as_bool` — `src/value/mod.rs:708` `pub fn as_bool(&self) -> Option<bool>`, 본문 709–712행:
  ```rust
  match *self {
      Value::Bool(b) => Some(b),
      _ => None,
  }
  ```
  LLBC 관측 일치: fun_decls[11] def_id 11, span `708:4–713:5`, `item_meta.source_text` 원문이 위 본문과 정확히 일치.
- **파일 manifest(원본==사본==변이사본 사전)**: `find . -path './.git' -prune -o -type f -print | sort | xargs sha256sum | sha256sum` → `8045f3b1ce56398fe506aeec9f9344405e32cd7dffda64ddaff4dbd0db6c7cd4` (원본·사본·변이사본 사전 3곳 동일값 실측; 변이사본 사후 `e3db7576b149373b67482cd4a471dfcbd6622e3dd466cd84da7225cb7982b9f7` = 변이 1라인만 다름).
- **도구(공식 호환 쌍)** — GitHub `AeneasVerif/aeneas` 릴리스 태그 `nightly-2026.11.03-ab34bd2` 자산, 퍼블릭 조달(`gh release download`, 인증 헤더 사용한 프라이빗 경로 아님):
  | 항목 | 값 |
  |---|---|
  | `aeneas-linux-x86_64.tar.gz` | sha256 `ed0e336c506dad37e4e1c53f6cc4d6d5959d7e3afab2fd55aead280775651f5e`, 158,648,932 B |
  | `aeneas` | sha256 `12e6042cfb00aba8ea8b6ef2811f55867e4fc8bf56bcc96c5a7d52ab9fd53a9c`; `-version` → `aeneas nightly-2026.11.03-ab34bd2` |
  | `charon` | sha256 `4226741660099a31be54bde273e9193dd5a44154df7eb203c3c333d83b32a59c`; `charon version` → `0.1.304 (7b462d9159db2ed3015162352183906a30bfafc6)` — **번들 내장 charon-pin과 정확 일치** |
  | `charon-driver` | sha256 `bb0f4073c59f7fab47f8e133d761806c17dad09dab9aa6c0116aa057380300e9` |
  | `charon toolchain-version` | `nightly-2026-09-17` (번들 `rust-toolchain` 파일 채널과 일치) |
  | aeneas 저장소 클론 | tag `nightly-2026.11.03-ab34bd2`, HEAD `ab34bd28458a08c150b7cbf1873e59af74588138`, `backends/lean/lean-toolchain` = `leanprover/lean4:v4.35.0` |
- **이중 rustc identity (별개 필드 기록)**:
  - **추출(Extraction) toolchain**: rustc **1.100.0-nightly (923c95cdf 2026-09-17 채널 — `nightly-2026-09-17-x86_64-unknown-linux-gnu`)**, 컴포넌트 rustc-dev/llvm-tools/rust-src/miri installed 실측 — charon이 번들 `rust-toolchain`으로 지정
  - **실행(Execution) baseline**: rustc **1.95.0 (59807616e 2026-04-14)** stable (default) — Rust 실행 대조·소비자 크레이트; cargo 1.95.0 (f2d3ce0bd 2026-03-21)
  - **증명(Proof)**: Lean **4.35.0** `Lean (version 4.35.0, x86_64-unknown-linux-gnu, commit eb6cafb7290e8bd5f2937522d8d804f58f02bafc, Release)`, Lake 5.0.0-src+eb6cafb (elan 경유; Axiom4 저장소 핀 v4.33.0은 무변경·공존 — 저장소 밖 `/tmp` 프로젝트만 v4.35.0)

### 4.2 샌드박스

```
/tmp/b1_gate_a/
├── tools/            # 번들 추출본(aeneas·charon·charon-driver·backends·rust-toolchain) + tar.gz
├── aeneas-repo/      # 읽기 전용 클론 (tag nightly-2026.11.03-ab34bd2)
├── json_copy/        # 서브젝트 검증 사본 (manifest==원본 확인)
├── json_mut/         # 변이 사본 (사전 manifest==원본 확인 후 1라인 변이)
├── charon-target/    # 추출 target 디렉터 (사본용)
├── charon-target-mut/# 변이 사본용 (별도)
├── consumer/         # Rust 실행 대조 소비자 크레이트 (자체 Cargo.lock)
├── leanproj/         # AsBool lake 프로젝트 (생성 Lean + 손모델 + 명제)
├── leanproj_mut/     # AsBoolMut lake 프로젝트 (변이 Lean + 동일 명제)
├── out/              # LLBC·번역 산출물 (lean1, lean_mut)
└── logs/             # 전 단계 원문 로그
/tmp/b1_gate_a_cold/  # detached cold 재현 (신선 상태, 별도 경로)
```
다른 실험 디렉터(/tmp/b0_c7_work, /tmp/b1_gate_b 등) 불침범 실측.

### 4.3 charon 추출 (§8 잠금 프로토콜 — B-0 재현 명령열 준용)

절차: (1) 원래 Cargo.lock 부재 확인 → (2) frozen Cargo.lock 배치(`experiments/serde-json-claim-2026-10-31/inputs/Cargo.lock`, sha256 `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4`) → (3) `CARGO_NET_OFFLINE=true charon cargo --preset=aeneas --start-from <패턴> --dest-file <f> -- --target-dir <t>` → (4) lock 사후 sha256 in==out → (5) 매니페스트 사후 대조 → (6) `rm Cargo.lock`.

| 실행 | 패턴 | exit | wall | LLBC sha256 | bytes | lock in==out |
|---|---|---|---|---|---|---|
| 진단용 전체 추출 (`--start-from` 없음) | — | 0 | 4,528 ms | `825c717823a8b8922d02c62175145104f5be9e87caafeed2441ef1143e39faf9` | 30,953,114 | ✓ |
| **정식 실행 (run of record)** | `serde_json::value::_::as_bool` | 0 | 544 ms (warm target) | `cfa5a04f99d55a54ebe098b30256712078c6ff271791ab8b6200de311a5e3dfc` | 287,322 | ✓ |
| 변이 사본 재추출 | 동일 | 0 | 3,381 ms | `4e73fe6051f897d1e704d2602f8e6a7bbff587a26ce2dc6b9e75034c53ff4373` | 286,712 | ✓ |
| cold 재추출 (§9) | 동일 | 0 | 3,037 ms | `91735ca17c027e8dbfeb53cd5aed34c51b0cfe097ed17ea8feb2105464c649f4` | — | ✓ |

네트워크 fetch 0건 관측(모든 cargo 로그가 캐시 의존 컴파일만 표시: `zmij v1.0.23 · serde_core v1.0.229 · serde_json v1.0.154 · itoa v1.0.18 · memchr v2.8.3`). 매니페스트 사전==사후(excl. lock) 전 실행 충족.

**`--start-from` 패턴 편차 (정직 기록 — 미션 예상형 2종은 실패, 원문 보존)**:

1. `serde_json::value::<impl serde_json::value::Value>::as_bool` → **exit 101**:
   ```
   warning: failed to parse pattern `serde_json::value::<impl serde_json::value::Value>::as_bool` (error Eof at: <impl serde_json::value::Value>::as_bool)
   ```
   charon 0.1.304 핀 커밋 `7b462d91`의 `charon/src/name_matcher/parser.rs` 원문 관측: impl 요소 문법은 `{impl <경로>}` 형태(`PatElem::Impl`), `<impl …>`는 파서에 없음.
2. `serde_json::value::{impl serde_json::value::Value}::as_bool` → **exit 101**:
   ```
   warning: failed to resolve item path `serde_json::value::{impl serde_json::value::Value}::as_bool`: `--start-from` only supports impl patterns if they're the first element of the path
   ```
   동일 핀의 `charon/src/bin/charon-driver/translate/resolve_path.rs` 원문 관측: `--start-from`의 Impl 요소는 **trait impl 전용**이고 inherent impl(`InherentImplBlock`)은 명시적으로 거부 — `PatElem::Impl(_) => bail!("`--start-from` only supports impl patterns if they're the first element of the path")` 및 inherent 분기 bail. **즉 charon 0.1.304의 `--start-from`은 inherent-impl 메서드를 직접 시작점으로 지정할 수 없다(관측된 도구 제약).**
3. **성공 패턴**: `serde_json::value::_::as_bool` — glob 1개로 Impl 이름 요소를 건너뛰어 `as_bool`에 도달(결과 fun_decls 21개로 최소성 간접 확인: 대상 외에는 의존성만 포함).

### 4.4 타입 closure 전수 분석 (정식 LLBC, 287,322 B)

fun_decls **21개 non-null**: `as_bool`(def_id 11)만 `Structured` 본체, 나머지 20개 전부 `Opaque`(core slice/array 인덱싱·`get(_mut)`·`get_unchecked(_mut)`·`alloc::alloc::{Clone<Global>}::clone` — 번역기가 이 중 as_bool에서 참조 가능한 것만 소비; aeneas 번역기 관점 투명 함수는 1개뿐).

type_decls **11개 non-null** 전수:

| def_id | 이름 (LLBC name 원문 요약) | 분류 | 투명성 |
|---|---|---|---|
| 0 | `Builtin(Tuple)` | builtin | Opaque |
| 1 | `serde_json::value::Value` (Null/Bool/Number/String/Array/Object, `@[discriminant isize]`) | **local** | 투명 (Enum) |
| 5 | `core::ops::range::Range` | external | 투명 (Struct) |
| 6 | `serde_json::number::Number` (n: N) | **local** | 투명 (Struct) |
| 7 | `alloc::string::String` | external | **Opaque** |
| 8 | `alloc::vec::Vec` | external | **Opaque** |
| 9 | `alloc::alloc::Global` | external | 투명 (빈 Struct) |
| 10 | `serde_json::map::Map` (map: BTreeMap K V Global) | **local** | 투명 (Struct) |
| 11 | `core::option::Option` | external | 투명 (Enum) |
| 12 | `serde_json::number::N` (PosInt u64/NegInt i64/Float f64) | **local** | 투명 (Enum) |
| 13 | `alloc::collections::btree::map::BTreeMap` | external | **Opaque** |

- **local/external 분류**: local 4(Value·Number·N·Map), external 7 — external 중 Opaque 4(String·Vec·BTreeMap·Tuple), 투명 3(Range·Global·Option).
- **튜플-이름 존재 여부**: **존재가 관측됐다** — type_decls[0]이 `Builtin(Tuple)` 이름을 가진 builtin 타입 선언(가정 "서명상 부재"는 기각). 다만 `-print-unknown-externals` 미부여 상태에서는 이 선언이 NameMatcher를 트리거하지 않았고(§0-H 일치) 번역은 성공했다. (이 플래그를 부여하면 B-0 관측과 동일한 튜플-이름 크래시가 재발할 가능성은 본 실행에서 검증하지 않았다 — 범위 밖.)
- as_bool 서명(LLBC 원문): inputs `[Ref(Var Free 0, Value, Shared)]`(=`&self`), output `Option<bool>`(Adt 11, 타입인자 bool). **직접 callee 0개**(FunId 참조 없음 — 순수 스위치).

### 4.5 aeneas 번역 (플래그 없음 — §0-H 준수)

명령: `./aeneas -backend lean -dest /tmp/b1_gate_a/out/lean1 -split-files out/as_bool.llbc` → **exit 0, wall 839 ms**. stdout/stderr 원문(색상 코드 제거·진행바 축약 없는 완결 라인):

```
[Info ] Imported: /tmp/b1_gate_a/out/as_bool.llbc
Applied prepasses:  21/21 ✔️
Translated globals: 0/0 ✔️
Translated opaque functions: 0/0 ✔️
Translated transparent functions: 1/1 ✔️
Translated trait declarations: 0/5 ✔️
Translated trait impls: 0/8 ✔️
Post-processed translated opaque functions: 0/0 ✔️
Post-processed translated transparent functions: 1/1 ✔️
[Info ] Generated: /tmp/b1_gate_a/out/lean1/TypesExternal_Template.lean
[Info ] Generated: /tmp/b1_gate_a/out/lean1/Types.lean
[Info ] Generated: /tmp/b1_gate_a/out/lean1/Funs.lean
[Info ] Total execution time: 0.575720 seconds
```

- **캠페인 최초의 번역 경로 관측** — B-0의 4회 시험(전부 크래시)과 대비. PrePasses 21/21 → transparent 1/1(as_bool) 완주.
- 생성물: `Types.lean` 1,729 B / `Funs.lean` 1,306 B / `TypesExternal_Template.lean` 1,134 B. **FunsExternal_Template.lean 부재 = 미구현 외부 함수 0개** (as_bool callee 0과 일치).
- `Funs.lean` 생성 원문(핵심부):
  ```lean
  def value.Value.as_bool (self : value.Value) : Result (Option Bool) := do
    match self with
    | value.Value.Null => ok none
    | value.Value.Bool b => ok (some b)
    | value.Value.Number _ => ok none
    | value.Value.String _ => ok none
    | value.Value.Array _ => ok none
    | value.Value.Object _ => ok none
  ```
- `Types.lean`: `value.Value`·`number.N`·`number.Number`·`map.Map` 완전 생성. `TypesExternal_Template.lean`: 구멍은 `BTreeMap` **1개**(`axiom ... : Type` 형태 제안).

### 4.6 Lean 빌드 (v4.35.0, Aeneas 라이브러리 path 의존)

- 프로젝트: `lakefile.lean`이 `require Aeneas from "/tmp/b1_gate_a/leanproj/deps/aeneas-lean"` — **번들 `backends/lean`의 사본**(prebuilt `.lake/build` 203 MB 재사용, path 의존으로 네트워크 버션 드리프트 차단). 의존 확보: mathlib v4.35.0(pinned `56a005855ea17e0b0958f73ec801ae140b0a1679`) + inherited 8개 — `lake update`가 mathlib 캐시에서 **9,031 파일** 확보(`cache.mathlib.org`; 네트워크 1회 — §CONFIG 경계 기록).
- 최종 빌드: `lake build` → **exit 0, "Build completed successfully (1801 jobs)"** (deps 재사용 상태에서 wall ~5 s).
- **빌드 과정에서 관측된 생성물/라이브러리 갭 4종 (전부 원문 보존, §5.4 표)** — 해소는 전부 *소비자 측 최소 손모델·1토큰 수동 수정*으로 수행했고 생성 원본 파일은 무수정 보존(out/lean1, 해시 기록).

### 4.7 손모델 (TypesExternal.lean — 최소·정직, sorry 전면 부재)

| 모델 | 정의 | 계약·근거 |
|---|---|---|
| `Aeneas.Std.F64` | `structure F64 where val : Float` | aeneas 라이브러리(tag nightly-2026.11.03-ab34bd2) 전체에서 `f64`/`F64` 모델 **부재**(case-insensitive 검색 0건 — 바이너리는 bare `F64` 배출). Lean의 `Float`은 IEEE-754 binary64=Rust f64와 동일 폭. 부동소수점 산술 의미는 **일절 주장하지 않음** — as_bool은 변형자(disriminant)만 소비하므로 이 선택이 명제에 영항 불가능 |
| `alloc.collections.btree.map.BTreeMap K V A` | `structure ... where entries : List (K × V)` | 템플릿 제안 `axiom` 형태는 datatype이 아니어서 `value.Value.Object`의 `_nested` 커널 투영에서 거부됨(§5.4-2). 연결리스트 추상화: 트리 순서·할당자 파라미터 미모델. as_bool은 map 내용을 소비하지 않으므로 명제에 영항 불가능. `Object(Map::new())` 입력의 충실한 표현(entries=[])은 커널 평가에 사용 |

근거 원칙: 두 모델 모두 "as_bool 명제가 모델 내부에 의존할 수 없는 구조"(함수가 payload를 읽지 않음)를 LLBC 서명으로 보장받아, opaque-최소성이 추측이 아니라 추출 산출물에서 확정된다. `String`은 Aeneas 라이브러리 매핑(Lean core `String`, `body := .opaque`)을 그대로 수용, `Vec`은 라이브러리의 computable 모델(`ListN` 기반)을 그대로 수용 — 재모델링 없음.

### 4.8 명제·증명 (독립 정의 — 구현 역유도 금지)

명제 출처: serde_json 문서 계약("If the `Value` is a Boolean, returns the associated `bool`. Returns `None` otherwise.") — 구현 코드에서 역유도하지 않고 2절로 분리:

1. `as_bool_bool_some : ∀ (b : _root_.Bool), value.Value.as_bool (value.Value.Bool b) = ok (some b)`
2. `as_bool_non_bool_none : ∀ (v : value.Value), (∀ b : _root_.Bool, v ≠ value.Value.Bool b) → value.Value.as_bool v = ok none` (6-변형 전체 case analysis)

증명: `simp [value.Value.as_bool]` / `match` + `absurd rfl (h b)` — sorry·`native_decide`·외부 oracle 0. 커널 구체 입력 7건(`rfl`): Null, Bool true/false, Number(PosInt 1#u64), Array(빈 Vec), String "s", Object(빈 map 모델).

**`#print axioms` 결과 (원문)**:
```
'AsBool.Spec.as_bool_bool_some' depends on axioms: [propext, Quot.sound]
'AsBool.Spec.as_bool_non_bool_none' depends on axioms: [propext, Quot.sound]
```
- **sorryAx 0** — 요구 충족. 사용 전제는 Lean 표준 논리 공리 2개(propext·Quot.sound)뿐, `Classical.choice`조차 미사용.
- Rust 실행 대조에서 Lean 측 구성 불가 변형: 없음(손모델이 Object까지 구성 가능하게 됨) — 단, Object의 빈 map만이 Rust 입력과 대응되며 일반 map 내용은 명제의 전칭 case analysis가 담당한다(§4.7 계약과 일치).

### 4.9 Rust 실행 비교 (stable 1.95.0)

- 소비자 크레이트 `/tmp/b1_gate_a/consumer`: path 의존 `serde_json = { path = "../json_copy" }`(검증 사본), 자체 Cargo.lock sha256 `84b955531545e394ee33da614d32f43587d0438cdc352657c2c7e31e112b57c3`, `CARGO_NET_OFFLINE=true cargo +stable run --offline` → exit 0, wall 3,125 ms. harness identity: rustc 1.95.0 (59807616e 2026-04-14), cargo 1.95.0 (f2d3ce0bd 2026-03-21), edition 2021.
- 6-변형 전 포함 7입력 실행 결과(원문):
  ```
  Null=None
  Bool_true=Some(true)
  Bool_false=Some(false)
  Number=None
  String=None
  Array=None
  Object=None
  ```
- Lean 커널 평가 대조: 7입력 모두 동일 결과(`ok none` / `ok (some true)` / `ok (some false)`) — **불일치 0건**.

### 4.10 mutation 음성 (전 파이프라인 — 핵심 음성 대조)

- 변이: `json_mut/src/value/mod.rs` 1라인, `Value::Bool(b) => Some(b),` → `Value::Bool(b) => None,` (파일 sha256 `6331d59ea362a74b6cd3d302d08114a63a73a384ff56fef737de29edea2f8d91` → `878801abac2f0d8770ef00a7e6e1ea459ab80b292fdfb528742d45daa29b43d3`; 사본 매니페스트 `8045f3b1…` → `e3db7576…`, diff는 해당 1라인뿐).
- **Lean 파일만 변이하는 방식 미사용** — Rust 원본의 변화가 전체에 전파하는지가 검증 대상(§단계 9 요건).
- 전파 관측: charon 재추출(exit 0, LLBC `4e73fe60…4373`)에서 변이 본문이 `source_text` 원문으로 확인 → aeneas 재번역(exit 0, 773 ms)에서 생성 diff가 정확히 1의미행:
  ```diff
  -  | value.Value.Bool b => ok (some b)
  +  | value.Value.Bool _ => ok none
  ```
  (Types.lean은 루트 모듈명 `AsBool`→`AsBoolMut` 임포트 라인만 상이, TypesExternal_Template는 바이트 동일.)
- **동일한 독립 명제**를 변이 모델에 대해 재증명 → **실패 관측(원문)**:
  ```
  error: AsBoolMut/Spec.lean:15:62: unsolved goals
  b : Bool
  ⊢ False
  ```
  `lake build` exit 1. 즉 clause 1(Bool→Some)은 변이에 의해 **증명 불가로 사망(mutant killed)**.
- 대조: clause 2(비-Bool→None)와 비-Bool 구체 입력 5건은 변이 모델에서도 여전히 증명·커널 통과(`Built AsBoolMut.Spec2 ✔`) — 변이가 clause 1만 죽이고 clause 2의 진위를 뒤집지 않았음이 **음성 대조로 분리 관측**됨. (Bool 입력은 구성 가능하므로 이 축은 opaque 모델 선택과 무관하게 관측됐다.)

### 4.11 detached cold 재현 (신선 state, 동일 명령)

`/tmp/b1_gate_a_cold/`에 신서 사본(manifest==원본 확인) + 신선 target 디렉터 + 동일 명령열:

| 축 | 원 실행 | cold 실행 | 판정 |
|---|---|---|---|
| exit | 0 (charon) / 0 (aeneas) | 0 / 0 | 동일 |
| status·wall | 544 ms / 839 ms (warm) | 3,037 ms / 783 ms | exit 동일, wall은 캐시 온도 차로 변동(예고된 클래스) |
| identity 해시 | LLBC `cfa5a04f…5dfc` | `91735ca1…49f4` | **LLBC 바이트 상이** — 원인 필드 특정: `translated.options.dest_file` 경로 에코 1개(B-0 adjudication §8의 files[1] 경로-내장 클래스와 동계열). `fun_decls`·`type_decls`·`files`·기타 모든 필드 **구조 동등(True)** |
| 의미 결과 | fun 21 / type 11 / as_bool Structured | 동일 | 동일 |
| stdout 차이 | — | 생성 Lean 3파일 전부 **바이트 동일**(`LEAN_IDENTICAL` ×3; Funs.lean `e0fec2a8…` 동일 해시) | 경로 종속 필드는 Lean 산출물로 에코되지 않음 — 5축 폐쇄 |

## 5. Result 보충

### 5.1 구성요소 지원 표

| 구성요소 | 상태 | 비고 |
|---|---|---|
| charon `--preset=aeneas` 추출 | **Go** | 4회 전부 성공(§8 잠금 포함), 오프라인 |
| `--start-from` 최소 서브그래프 | **Go (우회 필요)** | inherent-impl 메서드 직접 지정 불가(관측 제약), glob 패턴으로 달성 |
| aeneas LLBC→Lean 번역 | **Go** | exit 0, transparent 1/1, 미구현 외부 함수 0 |
| 생성 Lean 빌드 | **Go (생성물 1토큰 수동 수정 필요)** | `Option Bool` 생성자/기본형 충돌(§5.4-3) |
| 외부 타입 손모델 | **Go (2종 수작업 필요)** | F64 모델 라이브러리 부재, BTreeMap axiom 형태 커널 거부 |
| 커널 증명 | **Go** | 2절 명제, sorryAx 0, 구체 7입력 |
| Rust 실행 대조 | **Go** | 7입력 불일치 0 |
| mutation 음성 | **Go** | clause 1 킬 관측, clause 2 생존 대조 |
| cold 재현 | **Go** | 5축 폐쇄(경로 종속 필드 별도 식별) |

### 5.2 미구현 외부 목록 (번역기 기준)

- 외부 **함수**: 0개 — `FunsExternal_Template.lean` 미생성(번역 stdout 원문에 Generated 항목 없음).
- 외부 **타입**: 구멍 1개(`BTreeMap`) — 템플릿 생성 + 본 실험의 datatype 모델로 충원. `String`·`Vec`·`Global`·`Option`·튜플은 번들 Aeneas 라이브러리가 모델 제공(투명 수용).

### 5.3 입력·산출물 해시 인벤토리

| 산출물 | sha256 | bytes |
|---|---|---|
| 진단 전체 LLBC | `825c717823a8b8922d02c62175145104f5be9e87caafeed2441ef1143e39faf9` | 30,953,114 |
| **정식 최소 LLBC (input of record)** | `cfa5a04f99d55a54ebe098b30256712078c6ff271791ab8b6200de311a5e3dfc` | 287,322 |
| 변이 LLBC | `4e73fe6051f897d1e704d2602f8e6a7bbff587a26ce2dc6b9e75034c53ff4373` | 286,712 |
| cold LLBC | `91735ca17c027e8dbfeb53cd5aed34c51b0cfe097ed17ea8feb2105464c649f4` | — |
| 생성 `Types.lean` | `229ec1768d814171269674227bfebc75c96950516ffbf4a7c96cb63002914f60` | 1,729 |
| 생성 `Funs.lean` (원본) | `e0fec2a836a12ffd6588f501218522ceb2895f8d16b866f9b727d9e841951b32` | 1,306 |
| 생성 `TypesExternal_Template.lean` | `514fbfd947d7cb617d81046e60e874b59301b766a52a4b16af4bd72cccfef485` | 1,134 |
| 프로젝트 사본 `Funs.lean` (1토큰 수정 후) | `abaca6f68ab304c935f2d87564c5f19be6e80ba8aac4ddd0a2db724807e1e0e8` | — |

### 5.4 생성물/라이브러리 갭 — 원문 기록

| # | 현상 | 원문 | 해소 |
|---|---|---|---|
| 1 | aeneas 라이브러리에 `f64` 모델 부재 | `error: AsBool/Types.lean:36:0: Constructor field F64 of serde_json.number.N.Float contains universe level metavariables at the expression Sort ?u.11` — bare `F64`가 다른 우주-다형 상수로 해석 | TypesExternal.lean에 `structure Aeneas.Std.F64 where val : Float` 손모델 |
| 2 | BTreeMap `axiom` 템플릿 형태가 커널 거부 | `error: AsBool/Types.lean:48:0: (kernel) arg #1 of '_nested.serde_json.map.Map_2.mk' contains a non valid occurrence of the datatypes being declared` | datatype 모델(`structure … where entries : List (K × V)`)로 교체 |
| 3 | 생성 `Funs.lean`의 기본형/생성자 이름 충돌 | `error: … 'Bool' has type _root_.Bool → Value of sort Type but is expected to have type Type ?u.4 … in the application Option Bool` — enum 변형 `Value.Bool` 생성자가 bare `Bool`을 가림(aeneas 생성 버그 클래스 — 변형 이름이 기본형과 동일한 enum에서 발생) | 생성 원본 무수정 보존 + 프로젝트 사본 1토큰 수정 `Option Bool`→`Option _root_.Bool` (diff·해시 §5.3 기록) |
| 4 | Lean 모듈 시스템 문법(4.35 `module`/`public import`) | `error: AsBool.lean:1:0: cannot use 'public', 'meta', or 'all' without 'module'` 등 3건 | 루트·Spec 파일에 `module` 선언 + `public import` 정렬 (생성물에는 해당 없음 — 생성물은 처음부터 module 문법) |

### 5.5 네트워크 경계 관측

- **추출 파이프라인(charon·cargo)**: 네트워크 fetch 0건(4회 전부).
- **증명 파이프라인(lake)**: mathlib 캐시 9,031 파일 + git 의존 확보 1회(최초 빌드 시). 번들 prebuilt Aeneas olean은 path 의존으로 재사용되어 Aeneas 소스 재빌드 0.
- 두 파이프라인의 오프라인 성질이 다르다는 것은 v1 CLI 재현성 계약 설계 시 유의점(follow-up 후보 — 판정 아님).

## 6. Non-claims

- 본 문서는 **제품 판정이 아니다** — v1 CLI·레인·게이트·인증서의 어떤 동작도 주장하지 않는다.
- serde_json의 어떤 동작·품질·보안에 대한 참/거짓 주장이 아니다 — as_bool의 명제는 **문서 계약에 대한** 증명이며 구현과의 일치는 추출·번역·실행 대조로 관측된 것뿐이다.
- production 레인·charon 핀·툴체인 핀은 **무변경** — Axiom4 저장소의 src/·Makefile·config·.github 전부 미수정, 저장소 핀 Lean v4.33.0 공존 유지.
- C1~C8 어느 항목도 판정하지 않았다. B-1 이후 작업(B-2 이상)의 전제를 대체하지 않는다.
- Aeneas 채택 여부는 **미결정** — 본 문서는 단일 함수에서의 파이프라인 관측일 뿐, 일반화·성능·유지비용은 측정 대상 밖이다.
- 손모델(F64·BTreeMap)의 충실성은 as_bool 명제의 필요 범위에서만 정당화된다 — 모델 자체의 일반적 정확성을 주장하지 않는다.
- `-print-unknown-externals` 부여 상태의 재발 크래시는 본 문서에서 재검증하지 않았다(§0-H 사실 수용).

## 7. Deviations (전수)

1. **`--start-from` 패턴**: 미션 예상형 `serde_json::value::<impl serde_json::value::Value>::as_bool`은 파서 오류(Eof), `{impl …}` 교정형은 inherent-impl 거부(§4.3 원문 2건) → glob 패턴 `serde_json::value::_::as_bool`로 달성. LLBC item_names에서 대상 fun_decl 식별(fun_decls[615]/def_id 615, span 708:4–713:5)은 예상과 일치.
2. **`-print-unknown-externals` 미부여**: 미션 §0-H 지시에 따라 생략 — unknown-externals 정보는 `TypesExternal_Template` 생성물과 LLBC 파싱으로 획득(§5.2).
3. **정식 실행의 wall 544 ms는 warm target-dir** — 신선 상태 wall(3,037 ms)은 cold 재현 축에 별도 기록.
4. **생성 `Funs.lean` 1토큰 수동 수정** — 생성물 자체가 이름 충돌로 컴파일 불가(§5.4-3). 원본 무수정 보존, 수정 diff·해시 기록. 변이 프로젝트에도 동일 적용하여 음성 관측의 오염 방지.
5. **손모델 2종 수작업** — F64(Bible 라이브러리 부재), BTreeMap(axiom 형태 커널 거부)(§4.7).
6. **증명 파이프라인의 네트워크 사용** — mathlib 캐시·git 의존 1회 확보(§5.5). 미션의 "퍼블릭 조달" 범위(릴리스 자산·공개 git)와 동일한 공개 경로.
7. **풀 LLBC 진단 추출 1회 선행** — as_bool의 LLBC 이름 구조(Impl 요소) 확정 목적; 산출물은 진단용으로만 사용(hash 기록), 정식 실행은 별도.
8. **소비자 크레이트의 Object 입력** — `Map::new()` 1종만 사용(일반 map 내용은 명제 전칭이 담당; §4.9).

## 8. 재현 명령열 (Repro Block)

```bash
# 0) 도구 (공식 릴리스 번들 — 퍼블릭 조달)
mkdir -p /tmp/b1_gate_a/tools && cd /tmp/b1_gate_a/tools
gh release download --repo AeneasVerif/aeneas nightly-2026.11.03-ab34bd2 \
  -p 'aeneas-linux-x86_64.tar.gz' -D .
sha256sum aeneas-linux-x86_64.tar.gz   # ed0e336c506dad37e4e1c53f6cc4d6d5959d7e3afab2fd55aead280775651f5e
tar xzf aeneas-linux-x86_64.tar.gz
./charon version        # 0.1.304 (7b462d9159db2ed3015162352183906a30bfafc6)
./aeneas -version       # aeneas nightly-2026.11.03-ab34bd2
./charon toolchain-version  # nightly-2026-09-17
git clone --depth 1 --branch nightly-2026.11.03-ab34bd2 \
  https://github.com/AeneasVerif/aeneas.git /tmp/b1_gate_a/aeneas-repo

# 1) 서브젝트 검증 사본 + §8 잠금
cp -a "<workspace>/json" /tmp/b1_gate_a/json_copy
cd /tmp/b1_gate_a/json_copy && git rev-parse HEAD   # 8c535a260ce561eaab4111aafc29038eb9f77ff3
find . -path './.git' -prune -o -type f -print | sort | xargs sha256sum | sha256sum
cp <Axiom4>/experiments/serde-json-claim-2026-10-31/inputs/Cargo.lock Cargo.lock
sha256sum Cargo.lock   # 1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4

# 2) charon 추출 (run of record — glob 패턴, §8)
CARGO_NET_OFFLINE=true /tmp/b1_gate_a/tools/charon cargo --preset=aeneas \
  --start-from 'serde_json::value::_::as_bool' \
  --dest-file /tmp/b1_gate_a/out/as_bool.llbc \
  -- --target-dir /tmp/b1_gate_a/charon-target
sha256sum /tmp/b1_gate_a/out/as_bool.llbc   # cfa5a04f99d55a54ebe098b30256712078c6ff271791ab8b6200de311a5e3dfc (warm-target run)
sha256sum Cargo.lock && rm Cargo.lock        # in==out 후 제거

# 3) aeneas 번역 (플래그 없음 — §0-H)
cd /tmp/b1_gate_a/tools
./aeneas -backend lean -dest /tmp/b1_gate_a/out/lean1 -split-files /tmp/b1_gate_a/out/as_bool.llbc

# 4) lake 프로젝트 (Aeneas path 의존 = 번들 backends/lean 사본, lean-toolchain v4.35.0)
#    lakefile.lean: package «AsBool»; require Aeneas from "/tmp/b1_gate_a/leanproj/deps/aeneas-lean"
#    AsBool/{TypesExternal,Types,Funs,Spec}.lean — Funs는 1토큰 수정본(§5.4-3)
cd /tmp/b1_gate_a/leanproj && lake update && lake build   # exit 0, 1801 jobs
lake env lean PrintAxioms.lean
# 'AsBool.Spec.as_bool_bool_some' depends on axioms: [propext, Quot.sound]
# 'AsBool.Spec.as_bool_non_bool_none' depends on axioms: [propext, Quot.sound]

# 5) Rust 실행 대조 (stable)
cd /tmp/b1_gate_a/consumer && CARGO_NET_OFFLINE=true cargo +stable run --offline
# Null=None / Bool_true=Some(true) / Bool_false=Some(false) / Number=None / String=None / Array=None / Object=None

# 6) mutation 음성: json_mut 1라인 변이 → 동일 charon 옵션(--dest-file as_bool_mut.llbc, 별도 target) →
#    aeneas -dest out/lean_mut → leanproj_mut에서 동일 명제 빌드
#    → error: AsBoolMut/Spec.lean:15:62: unsolved goals  b : Bool  ⊢ False  (exit 1, Spec2는 통과)

# 7) cold 재현: /tmp/b1_gate_a_cold에 신선 사본+target, 동일 명령열 → §4.11 5축
```

## 9. Follow-up 후보 (발견 ≠ 권한 — §2.2)

1. charon `--start-from`의 inherent-impl 메서드 미지원 — 사용성 갭으로 상위(charon) 보고 후보.
2. aeneas 생성물의 기본형/생성자 이름 충돌(`Value.Bool` vs `bool`)과 `f64` 라이브러리 모델 부재, BTreeMap axiom 템플릿 형태의 커널 부적합 — 상위(aeneas) 이슈 후보 3건.
3. 증명 파이프라인의 네트워크 의존(mathlib 캐시) — hermetic 재현 계약과의 정렬 검토.
4. NameMatcher 튜플-이름 크래시의 번역-경로 재현성(`-print-unknown-externals` 부여 상태) — B-0 §10 후속과 본 관측의 접합.
5. 다수 함수·트레이트 구현으로의 확장 시 손모델 재사용 계약 설계.
