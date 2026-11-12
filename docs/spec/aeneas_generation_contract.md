# Aeneas/Charon Generation Contract (SSOT)

> **Status**: Normative contract (v1, 2026-11-04) — B-2 Stage 1a에서 사전등록. B-2 hermetic proof capsule(본체, 별도 문서)가 결속하는 정식 계약이다. 본 문서는 세대(generation)의 identity 결속·실행 경계·갱신 절차를 규정하며, 지원 범위를 확장하지 않는다.
> **Created**: 2026-11-04
> **Registered at**: branch `work/b2-1a-generation-contract-2026-11-04` (base main `50d781e82f6a90058a610dc92db99453ea3fd676`)
> **Related**: [docs/spec/productization_contract.md](productization_contract.md) · [docs/spec/verifier_build_identity.md](verifier_build_identity.md) (Nim verifier의 `engineBuild` — 본 계약과 **별개 identity**) · [docs/spec/rust_certified_subset.md](rust_certified_subset.md) · [docs/spec/upstream_reporting_contract.md](upstream_reporting_contract.md)
> **근거 증거**: [docs/evidence/b1_gate_a_minimal_proof_2026-11-04.md](../evidence/b1_gate_a_minimal_proof_2026-11-04.md) (이하 "Gate A") · [docs/evidence/b1_gate_b_capability_census_2026-11-04.md](../evidence/b1_gate_b_capability_census_2026-11-04.md) (이하 "census")
> **원칙**: identity는 측정된 곳에서만 결속된다 — 주장에서 오지 않는다. 실행하지 않은 단계를 실행한 것처럼 기록하는 것을 금지한다(§4.2). 검증 불가·오래된 증거는 fail-closed다(§9).

---

## §1. 목적

B-1 Gate A가 측정한 Rust→LLBC→Lean 생성 파이프라인 세대를 **immutable하게 사전등록**하여, B-2 캡슐이 (a) 어떤 identity의 세대를 소비하며, (b) 그 세대의 어느 부분만 실행하는지, (c) 언제 새 세대로 갈아타야 하는지를 계약으로 고정한다.

- 세대의 **생성 단계는 B-1에서 실행 완료**됐다. 캡슐(Stage B)은 세대를 재생성하지 않는다 — 증명 입력만 실행한다(§4 A안).
- §5의 결속 요소 중 **하나라도 달라지면 같은 세대가 아니다** — "업데이트"라는 개념은 존재하지 않는다(§8).
- 본 문서는 측정 문서가 아니다: §5의 값은 전부 B-1 측정치이며, 본 문서는 그 결속과 규칙을 등록한다.

## §2. 적용 범위

**범위 안**: 위 세대(single generation)의 identity 결속, Stage B 실행 경계(A안), identity 기록 규칙(§6), 1토큰 수정본 결속(§7), 세대 갱신 절차(§8), 비준수 판정(§9).

**범위 밖 (non-goals)**:

- Nim verifier의 build identity — `engineBuild`는 [verifier_build_identity.md]가 별도 규정한다. 두 identity는 서로를 대체하지 않는다.
- 저장소 핀 변경 아님: Axiom4 저장소 핀 Lean v4.33.0은 무변경·공존한다(Gate A §4.1 — 본 세대의 Lean v4.35.0은 실험 스코프 도구이다).
- serde_json·Aeneas·Charon 상류의 품질·보안·일반 지원 범위에 대한 주장 없음. census 결과의 새 함수·크레이트 일반화 없음.
- 제품 판정 아님 — 본 계약은 v1 CLI·레인·게이트·인증서의 어떤 동작도 주장하지 않는다.

## §3. 용어 정의

| 용어 | 정의 |
|---|---|
| **세대 (generation)** | §5의 identity 결속 요소 전체로 고정되는, B-1 Gate A에서 한 번 생성(실행)된 도구·입력·산출물의 집합. 결속 요소 중 하나라도 다르면 다른 세대다(§8). |
| **identity 결속** | 실행 없이 sha256·버전·커밋·지문의 **기록만으로** 고정하는 것. 결속은 측정에서 온다; 기록은 계보(append-only)에 남는다. |
| **실행 입력** | Stage B(캡슐)에서 **실제 실행되어** 증명을 산출하는 입력. 실행의 증거(exit·로그·산출 artifact)는 실행 입력에만 존재한다. |
| **Stage B (캡슐)** | 세대의 Lean 증명 입력을 hermetic 환경에서 실행·검증하는 단계 — B-2 hermetic proof capsule. |
| **A안** | 실행 경계 설계 A안(§4): 생성은 재실행하지 않고 identity로 결속하며, 캡슐은 증명 입력만 실행한다. |
| **근거 (anchor)** | 각 결속 값이 측정·기록된 위치. 착지된 증거 문서의 경로+절(예: Gate A §4.1) 또는 "B-1 측정(등록)"(§6.2 — 본 계약이 등록 위치인 값). |

## §4. 실행 경계 — A안 경계 표

### 4.1 경계 표

세대의 모든 구성 요소는 둘 중 하나에 속한다. **중간 지위는 없다.**

| 구분 | 구성 요소 | 결속 내용 (§5 상세) | Stage B(캡슐)에서 |
|---|---|---|---|
| **Stage B 실행 입력** | Lean 증명 입력 — 생성 Lean(Types·Funs·TypesExternal_Template) + 프로젝트 Funs 수정본 + 손모델(TypesExternal) + 독립 명제(`as_bool_bool_some`·`as_bool_non_bool_none`, sorryAx 0) | identity 결속(sha256 — Gate A §4.7·§4.8·§5.3) | **실행** — `lake build`로 Lean 커널 검증 |
| **Stage B 실행 입력** | Mathlib 캐시 — pin `56a0058…1679`, endpoint `cache.mathlib.org`, 9,031 파일 + inherited 8 의존 | identity 결속(manifest pin — Gate A §4.6·§5.5) | **실행** — olean 소비. **캡슐 hermeticity는 이 캐시를 사전 수록해야 한다**(증명 파이프라인만 네트워크 1회 의존이 관측됐다 — Gate A §5.5) |
| **Stage B 실행 입력** | Lean toolchain v4.35.0 — lean·lake·leantar·clang | identity 결속(바이너리 sha256 — §5.3) | **실행** |
| **identity-only 결속** (B-1에서 실행 완료) | 추출용 rustc nightly-2026-09-17 (1.100.0-nightly, 923c95cdf) | identity 결속만 (Gate A §4.1) | 재실행 없음 — 실행 주장 금지 |
| **identity-only 결속** (B-1에서 실행 완료) | charon 0.1.304 (7b462d91…, 번들 charon-pin 일치) | identity 결속만 (Gate A §4.1) | 재실행 없음 — 실행 주장 금지 |
| **identity-only 결속** (B-1에서 실행 완료) | aeneas nightly-2026.11.03-ab34bd2 (ab34bd28…) | identity 결속만 (Gate A §4.1) | 재실행 없음 — 실행 주장 금지 |
| **identity-only 결속** (B-1에서 실행 완료) | Rust 원본 — serde_json v1.0.154 `8c535a26…`, 매니페스트 지문 `8045f3b1…`, 잠금 Cargo.lock `1bc62b1a…` | identity 결속만 (Gate A §4.1·§4.3) | 재실행 없음 — 실행 주장 금지 |
| **identity-only 결속** (B-1에서 실행 완료) | LLBC (input of record) — `cfa5a04f…5dfc`, 287,322 B | identity 결속만 (Gate A §4.3·§5.3) | 재실행 없음 — 실행 주장 금지 |

### 4.2 미실행 단계의 실행 기록 금지 (명문 조항)

- Stage B의 실행 기록(exit·로그·산출물)은 **Stage B 실행 입력의 실행에만** 존재할 수 있다.
- identity-only 구성 요소(rustc·charon·aeneas·Rust 원본·LLBC)를 Stage B에서 (재)실행하고 그것을 같은 세대의 증명 활동으로 기록하는 것을 **금지한다**. 그런 실행이 필요하면 그것은 같은 세대가 아니라 **신세대**다(§8) — 채택 요건 없이는 어떤 판정·증거로도 결속되지 않는다.
- 실행하지 않은 단계를 실행한 것처럼 기록하는 것(실행 로그 유·산출물 무, 재사용 산출물의 신규 실행 표기 등)은 극장이다 — AGENTS.md §0.9에 따라 등록·차단 대상이며, 본 계약에서는 세대 무효 사유다(§9).

## §5. Immutable generation 요소 목록

### 5.0 세대 식별자 (파생형)

세대 식별자는 결속 필드의 순수 함수(파생값)이며 독자 명명이 아니다. 구성요소 변경 시 기계적으로 변경된다 — 같은 식별자의 재사용은 불가능하다.

```
generationId = "aeneas-gen/" + <aeneas-tag> + "+charon-" + <charon-version> + "+lean-v" + <lean-version>
             = "aeneas-gen/nightly-2026.11.03-ab34bd2+charon-0.1.304+lean-v4.35.0"
```

### 5.1 추출·번역 도구 (identity-only — B-1에서 실행 완료)

| 요소 | 값 | 근거 |
|---|---|---|
| aeneas 릴리스 태그 | `nightly-2026.11.03-ab34bd2` | Gate A §4.1 |
| aeneas 소스 commit | `ab34bd28458a08c150b7cbf1873e59af74588138` (클론 tag 동일, `backends/lean/lean-toolchain` = `leanprover/lean4:v4.35.0`) | Gate A §4.1 |
| aeneas 실행 바이너리 sha256 | `12e6042cfb00aba8ea8b6ef2811f55867e4fc8bf56bcc96c5a7d52ab9fd53a9c` (`-version` → `aeneas nightly-2026.11.03-ab34bd2`) | Gate A §4.1 |
| charon 버전 | `0.1.304 (7b462d9159db2ed3015162352183906a30bfafc6)` — **번들 내장 charon-pin과 정확 일치** | Gate A §4.1 |
| charon 실행 바이너리 sha256 | `4226741660099a31be54bde273e9193dd5a44154df7eb203c3c333d83b32a59c` | Gate A §4.1 |
| charon toolchain-version | `nightly-2026-09-17` (번들 `rust-toolchain` 채널과 일치) | Gate A §4.1 |

번들 매니페스트 전체(tar.gz·charon-driver 등)는 Gate A §4.1·§8이 원문 기록한다 — 본 표는 계약이 직접 결속하는 핵심 identity만 담는다.

### 5.2 이중 rustc identity (별개 필드 — 두 컴파일러는 서로 다른 컴파일러다)

| 필드 | 값 | 근거 |
|---|---|---|
| 추출(Extraction) rustc | `1.100.0-nightly (923c95cdf 2026-09-16)`, 채널 `nightly-2026-09-17` — charon 번들 `rust-toolchain` 지정 | Gate A §4.1 (버전·해시·채널) · 커밋 날짜 B-1 측정(등록) — §6.2 |
| 실행(Execution) baseline rustc | stable `1.95.0 (59807616e 2026-04-14)` — Rust 실행 대조·소비자 크레이트 | Gate A §4.1 |

두 필드는 서로 대체 불가능한 **별개 필드**다 — 하나의 rustc identity로 병합 기록하는 것은 비준수다(§9).

### 5.3 증명 도구·의존성 (Stage B 실행 입력)

| 요소 | 값 | 근거 |
|---|---|---|
| Lean 버전 | `4.35.0`, commit `eb6cafb7290e8bd5f2937522d8d804f58f02bafc` (`Lake 5.0.0-src+eb6cafb`, elan 경유) | Gate A §4.1 |
| lean 바이너리 sha256 | `bf8d54e4714cc4b03d3f6bb34c83b7202b87e49c8bfcbff6895c085bb90ceb38` | B-1 측정(등록) — §6.2 |
| lake sha256 | `8ba83c98f76562d03b8dbc33f1057151ba6cbb121679dde76b2260ccc90495e1` | B-1 측정(등록) — §6.2 |
| leantar sha256 | `06d613dffd2a6fd996b095bfd835c2bb720886f9eb7e13ed2adddd7df4507bf3` (**static** — 동적 closure 없음) | B-1 측정(등록) — §6.2 |
| clang sha256 (toolchain C 컴파일러) | `df2e7d9b9e23822587cf04ac28f206a1ddaac5053312a4c875acf5608701b9d2` | B-1 측정(등록) — §6.2 |
| mathlib pin | `56a005855ea17e0b0958f73ec801ae140b0a1679` (lake-manifest 실핀, v4.35.0 — inherited 8 의존) | Gate A §4.6 |
| mathlib 캐시 endpoint | `cache.mathlib.org` — `lake update`가 9,031 파일 확보(네트워크 1회 — §4.1 표의 hermeticity 요구) | Gate A §4.6·§5.5 |
| lake-manifest.json sha256 | `fd3d5b0ebd1063cceb318f9efc1e7346a7f53a742cb8602d62cb99b57fa44bd7` | B-1 측정(등록) — §6.2 |

### 5.4 손모델 2종 (Stage B 실행 입력 — 최소·정직, sorry 전면 부재)

| 모델 | 정의 | 계약·근거 |
|---|---|---|
| `Aeneas.Std.F64` | `structure F64 where val : Float` | aeneas 라이브러리에 `f64`/`F64` 모델 부재 — 부동소수점 산술 의미는 일절 주장하지 않음 (Gate A §4.7) |
| `alloc.collections.btree.map.BTreeMap K V A` | `structure … where entries : List (K × V)` (연결리스트 추상화 — 트리 순서·할당자 미모델) | 템플릿 `axiom` 형태는 커널 거부 — datatype 모델로 교체 (Gate A §4.7·§5.4-2) |

두 모델의 최소성은 as_bool이 payload를 읽지 않는다는 LLBC 서명 사실에서 확정됐다(추측 아님 — Gate A §4.7). 모델 자체의 일반적 정확성은 주장하지 않는다(Gate A §6 Non-claims).

### 5.5 생성 입력·산출물 identity

| 산출물 | sha256 | bytes | 근거 |
|---|---|---|---|
| 서브젝트 serde_json HEAD | `8c535a260ce561eaab4111aafc29038eb9f77ff3` (v1.0.154, clean) | — | Gate A §4.1 |
| 서브젝트 파일 매니페스트 지문 | `8045f3b1ce56398fe506aeec9f9344405e32cd7dffda64ddaff4dbd0db6c7cd4` | — | Gate A §4.1 |
| 잠금 Cargo.lock | `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` (lock in==out 실측) | — | Gate A §4.3 |
| LLBC (input of record) | `cfa5a04f99d55a54ebe098b30256712078c6ff271791ab8b6200de311a5e3dfc` | 287,322 | Gate A §4.3·§5.3 |
| 생성 `Types.lean` | `229ec1768d814171269674227bfebc75c96950516ffbf4a7c96cb63002914f60` | 1,729 | Gate A §5.3 |
| 생성 `Funs.lean` (aeneas 원본) | `e0fec2a836a12ffd6588f501218522ceb2895f8d16b866f9b727d9e841951b32` | 1,306 | Gate A §5.3 |
| 프로젝트 `Funs.lean` (1토큰 수정본 — §7) | `abaca6f68ab304c935f2d87564c5f19be6e80ba8aac4ddd0a2db724807e1e0e8` | 1,313 | Gate A §5.3 |
| 생성 `TypesExternal_Template.lean` | `514fbfd947d7cb617d81046e60e874b59301b766a52a4b16af4bd72cccfef485` | 1,134 | Gate A §5.3 |

독립 명제(`AsBool.Spec.as_bool_bool_some`·`as_bool_non_bool_none`)의 사용 전제는 `[propext, Quot.sound]`, sorryAx 0 — Gate A §4.8 원문 기록. cold 재현 5축 폐쇄와 LLBC 경로-내장 필드 동등성은 Gate A §4.11이 기록한다.

### 5.6 실행 기반 (B-1 측정 — 캡슐이 기록·대조할 기준값)

| 요소 | 값 |
|---|---|
| OS · arch | Linux Mint 22.3 `[noble]` · x86_64 |
| kernel | `6.17.0-42-generic` |
| glibc | `2.39-0ubuntu8.9` |
| sandbox (bwrap) | `0.9.0` |
| lean 동적 library closure (ldd) | toolchain `lib/lean`의 `libInit_shared.so`·`libleanshared.so`·`libleanshared_1.so`·`libleanshared_2.so` + `/lib/x86_64-linux-gnu`의 `libc`·`libpthread`·`libdl`·`libm`·`librt` + `ld-linux-x86-64.so.2` |
| lake 동적 closure | 위에 `libLake_shared.so` 추가 |
| leantar | static (동적 closure 없음) |

근거: **B-1 측정(등록) — §6.2**. 이 표는 캡슐이 자신의 실제 실행 기반을 기록하고 대조할 기준값이다. identity 심판의 최종 기준은 바이너리 sha256(§5.3)과 lake-manifest sha256이며, 실행 기반의 상이 판정 규칙은 B-2 캡슐 계약이 정의한다 — 본 계약은 무음 PASS를 금지한다(§9).

## §6. Identity 결속 규칙

### 6.1 sha256 기록 vs 실행 구분

- **identity 결속 요소**(§5.1·§5.2·§5.5·§5.6)는 sha256·버전·커밋·지문의 **기록**으로 결속된다. 기록은 실행을 의미하지 않는다 — 실행 여부는 §4 경계 표의 지위 열이 유일하게 결정한다.
- **Stage B 실행 입력**(§4.1 1~3행)은 identity 결속(사전) + 캡슐 런타임 재측정·대조(실행 시)를 **둘 다** 요구한다. 런타임 재측정값이 §5 등록값과 불일치하면 그 세대로의 산출물 발행은 금지된다(§9).

### 6.2 근거(anchor) 표기 규칙 — 정직 기록

- 근거가 증거 문서 절(예: "Gate A §4.1")인 행은 그 절의 착지된 전문이 유일한 측정 근거다.
- 근거가 **"B-1 측정(등록)"**인 행(§5.3의 lean·lake·leantar·clang 바이너리 sha256·lake-manifest.json sha256, §5.6 전체)은 B-1 측정 세션에서 계측되어 **본 계약이 등록 위치**인 값이다 — 착지된 증거 문서에 전문이 없다. 이 행들에 대해 본 문서+Git 이력이 결속 위치다; 캡슐은 Stage B 실행 입력에 대해 런타임 재측정으로 독립 재확인한다(§6.1). 이 구분 없이 모든 행을 증거 문서 근거로 표기하는 것(유언장 극장)을 금지한다.

### 6.3 자기참조 회피 (기계판독 파일 스킴 — B-2 캡슐이 materialize할 때)

세대를 기계판독 파일로 materialize하는 경우(`inventory.json`·`generation.json`) 스킴은 다음으로 고정된다:

- `inventory.json` = §5 표 전체의 기계판독 투영(값 전부 + 각 행 근거).
- `generation.json` = 세대 메타(generationId §5.0 + `sha256(inventory.json)` + 계보 참조). 즉 **generation.json은 inventory.json의 SHA-256을 기록한다**.
- 세대 자신(generation)의 digest는 **어떤 파일에도 자기참조로 기록하지 않는다** — 세대의 최종 결속 위치는 본 문서(착지된 Git 이력)와 근거 증거 문서다(§6.2). 자기 digest를 자기 파일 안에 기록하려는 시도는 비준수다(§9).
- 두 파일의 생성은 본 계약의 투영일 뿐 authority가 아니다 — 파일은 캐시다(비유: [verifier_build_identity.md] §7 "No cache authority").

### 6.4 Append-only 계보

세대 기록은 소급 수정·삭제되지 않는다. 새 세대는 새 generationId와 새 근거 기록으로 추가된다(§8). 구세대 기록은 역사로 남으며 권한·면제를 갖지 않는다.

## §7. 1토큰 수정본 결속

aeneas 생성 `Funs.lean`은 생성 버그로 직접 컴파일 불가하므로, 이 세대는 **원본과 수정본을 구분해 둘 다 결속**한다.

| 문서 | identity | bytes |
|---|---|---|
| aeneas 생성 원본 (무수정 보존) | sha256 `e0fec2a836a12ffd6588f501218522ceb2895f8d16b866f9b727d9e841951b32` | 1,306 |
| 프로젝트 수정본 (빌드에 사용) | sha256 `abaca6f68ab304c935f2d87564c5f19be6e80ba8aac4ddd0a2db724807e1e0e8` | 1,313 |

- **diff**: `Option Bool` → `Option _root_.Bool` — **1곳(1토큰)**.
- **근거**: enum 변형명(`Value.Bool` 생성자)이 기본형(`_root_.Bool`)과 동일해 bare `Bool`을 가리는 aeneas 생성 버그 클래스 — 커널 오류 원문·해소 기록은 Gate A §5.4-3. 해시 2건은 Gate A §5.3 원문; bytes는 각각 Gate A §5.3(원본 1,306)·B-1 측정(등록)(수정본 1,313 — §6.2).
- **규칙**: (a) 생성 원본은 무수정 보존된다 — 원본 identity가 수정본 identity로 대체되는 것을 금지한다. (b) 수정은 이 1토큰으로 **한정**된다; 다른 어떤 수정도 이 세대의 "수정본"이 아니다 — 그런 파일은 신세대 요건(§8) 없이는 빌드 입력으로 결속될 수 없다. (c) mutation(변이) 프로젝트에도 동일 1토큰 수정을 적용해 음성 관측의 오염을 방지했다(Gate A §4.10·§7 Deviations 4).

## §8. 세대 갱신 절차

### 8.1 구성요소 변경 = 신세대 (업데이트가 아니다)

§5의 결속 요소 중 **하나라도** 변경되면(aeneas 태그·charon 버전·rustc 채널·Lean 버전·mathlib pin·lake-manifest·손모델·1토큰 수정 위치의 변경을 포함) 그것은 기존 세대의 "업데이트"가 아니라 **신세대**다. 기존 세대 기록은 변경되지 않는다(§6.4).

### 8.2 신세대 채택 요건 (전부 만족 — 하나라도 부재·미측정이면 채택 불가, fail-closed)

1. **기존 성공 함수(as_bool) 전 파이프라인 재증명** — 추출→번역→손모델→커널 증명까지, Gate A §8 재현 명령열 준용.
2. **mutation 음성 대조 재수행** — 동일 1라인 변이에 대한 전 파이프라인 전파·동일 독립 명제의 killed 관측, Gate A §4.10 절차 준용.
3. **census CRASH 항목 중 1개 이상의 재검증** — 등록 대표 실패 대상: `c7_parse_line_col` (LLBC `db32749b…87650`, 390,546 B, aeneas exit 2 — census §5.2). census 집계(28행 중 CRASH 14·PARTIAL 2·TRANSLATED 12)는 census §5.2가 기록한다.

신세대는 새 generationId(§5.0 스킴의 기계적 파생)와 새 근거 기록으로 등록한다.

### 8.3 상류 지원 범위의 자동 편입 금지

상류(Aeneas/Charon)의 지원 범위 확대(새 릴리스·새 기능·버그 수정)는 **Axiom의 지원 범위로 자동 편입되지 않는다**. Axiom은 독립 관측 후 판정을 갱신한다 — 발견 ≠ 권한(AGENTS.md §2.2), 상류 보고 경로는 [upstream_reporting_contract.md]를 따른다.

## §9. 비준수 시 fail-closed

| 위반 | 결과 |
|---|---|
| 캡슐 런타임 재측정 identity ≠ §5 등록값 (Stage B 실행 입력) | 해당 세대로의 산출물 인서트·판정 발행 금지 — **UNKNOWN** (조용한 PASS 금지) |
| §4.2 위반 — 미실행 단계의 실행 기록, identity-only 요소의 같은-세대 재실행 주장 | **세대 무효** — 그 증거 기록 전체 기각 |
| §5에 없는 세대·근거 부재·오래된 증거 | **fail-closed (UNKNOWN)** — 검증 불가·오래된 증거 = fail closed |
| §7 위반 — 원본 identity의 소실·1토큰 외 수정의 무등록 반영 | **세대 무효** |
| §6.3 위반 — 자기참조 digest 기록 시도 | 비준수 — materialize 산출물 기각 |
| 손모델·명제의 sorry·외부 oracle 등 공허한 증명 대체 | 극장 — AGENTS.md §0.9에 따라 등록·차단, 세대 무효 |

UNKNOWN은 계약의 fail-closed 판정값이다([productization_contract.md] 상태 어휘와 동일 — 부재·무효·상충 증거는 PASS로 해석되지 않는다).

## §10. 참조

**근거 증거 (측정 원문)**:

- [docs/evidence/b1_gate_a_minimal_proof_2026-11-04.md](../evidence/b1_gate_a_minimal_proof_2026-11-04.md) — §4.1 도구 identity(번들 매니페스트 전체 포함) · §4.3 LLBC·lock · §4.6 mathlib·캐시 · §4.7 손모델 · §4.8 명제·공리 · §4.10 mutation · §4.11 cold 재현 · §5.3 해시 인벤토리 · §5.4-3 1토큰 수정 · §5.5 네트워크 경계 · §8 재현 명령열
- [docs/evidence/b1_gate_b_capability_census_2026-11-04.md](../evidence/b1_gate_b_capability_census_2026-11-04.md) — §5.2 census 28행 전수표·집계(CRASH/PARTIAL/TRANSLATED) · §7 분류

**관련 계약**:

- [docs/spec/productization_contract.md](productization_contract.md) — 상태 어휘(PASS/FAIL/UNKNOWN, fail-closed)
- [docs/spec/verifier_build_identity.md](verifier_build_identity.md) — Nim verifier `engineBuild` (별개 identity)
- [docs/spec/rust_certified_subset.md](rust_certified_subset.md) — Rust certified subset 경계
- [docs/spec/upstream_reporting_contract.md](upstream_reporting_contract.md) — 상류 보고 경로 (§8.3)
