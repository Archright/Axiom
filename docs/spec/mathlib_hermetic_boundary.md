# Mathlib hermetic 실행 경계 계약 — Stage A(프로비저닝)·Stage B(검증)

> **종류**: 실행 경계 사전계약 — B-2 hermetic proof capsule(진행 중)의
> Stage A(프로비저닝)·Stage B(검증) 실행 경계를 **사전에** 계약으로 고정한다.
> authority·state transition·failure semantics가 정의되지 않은 상태에서 실행
> 경계를 변경하지 않는다(AGENTS.md §2.5/§2.6 — 본 문서가 그 정의다).
> **상태**: 계약 확정(2026-11-04) — Stage A/B의 실행·관측은 별도 작업이다.
> **착지 범위**: 이 착지는 계약 사전등록이며, 캡슐의 실제 프로비저닝·격리
> 실행·관측 기록은 별도이다. 본 문서는 Stage A/B가 수행됐다는 주장을 포함하지
> 않는다.
> **선행 문서**:
> [docs/evidence/b1_gate_a_minimal_proof_2026-11-04.md](../evidence/b1_gate_a_minimal_proof_2026-11-04.md)
> (B-1 Gate A — §4.6 mathlib 핀 `56a005855ea17e0b0958f73ec801ae140b0a1679`,
> §5.5 증명 파이프라인(lake)이 mathlib 캐시 9,031 파일을 네트워크에서 1회
> 확보한 유일한 전임 관측 — "추출 파이프라인과 증명 파이프라인의 네트워크
> 경계는 다르다"),
> [docs/spec/verifier_build_identity.md](verifier_build_identity.md)
> (identity 해시의 "무엇을 주장하지 않는가" 의미론 선례),
> [docs/spec/obligation_semantics.md](obligation_semantics.md)
> (저장소 핀 증명 경계(v4.33.0)의 현재 정책 — mathlib 미사용 axiom allowlist;
> 본 계약은 그 경계를 변경하지 않는다).
> **공식 문서 근거**: mathlib4 핀 커밋
> [`Cache/SECURITY.md`](https://github.com/leanprover-community/mathlib4/blob/56a005855ea17e0b0958f73ec801ae140b0a1679/Cache/SECURITY.md)
> (캐시 신뢰모델 — artifact byte-identity 검증의 명시적 out of scope 선언)·
> [`Cache/README.md`](https://github.com/leanprover-community/mathlib4/blob/56a005855ea17e0b0958f73ec801ae140b0a1679/Cache/README.md)
> (CLI·환경변수·endpoint·컨테이너), Lean 4 Lake
> `src/lake/Lake/Config/Env.lean`(`LAKE_NO_CACHE` 파싱·재수출)·
> `src/lake/Lake/CLI/Main.lean`(`--try-cache` — env 우선 override).

## 1. 목적

B-1 Gate A의 관측(§5.5)처럼 mathlib 의존 Lean 증명의 최초 빌드는 mathlib
캐시(`cache.mathlib.org`)를 네트워크에서 확보한다 — 증명 파이프라인은 추출
파이프라인과 달리 네트워크 의존을 갖는다. B-2 hermetic proof capsule은 이
의존을 두 단계 실행 경계로 분리해 닫는다:

- **Stage A(프로비저닝)** — 네트워크 사용 가능한 통제 환경에서 고정 의존성을
  준비하고, 그 집합의 identity를 generation에 결속해 기록한다.
- **Stage B(검증)** — 외부 네트워크 통신 불가능 상태에서 Stage A generation만을
  소비해 검증을 수행한다.

본 계약은 두 경계의 정의, Stage B 격리 구성 요구사항, 해시가 증명하는 범위,
캐시와 판정의 분리, 증거 identity 결속 목록, fail-closed 조항을 규정한다.

## 2. 적용 범위

- **범위 안**: mathlib 캐시 의존 Lean 증명 캡슐의 Stage A/B 실행 경계 —
  의존성 준비의 identity 기록, 격리 구성 요구사항, acceptance 판정 조건.
- **범위 밖**: 캡슐 축소 실험의 설계·실행·판정(§3.4 — 공식 수단의 참조만),
  저장소 핀 증명 경계(Lean v4.33.0 — `proofs/lean-toolchain`)의 변경,
  캐시 산출물 원천 진위의 검증(§5 — 가능 여부를 판단하는 것이 아니라 mathlib
  신뢰모델이 불가능을 선언한 영역), 제품 레인·게이트·인증서 계약의 변경.
- 본 계약의 계층은 B-2 캡슐 실험이다. `src/`와 FROZEN 표면은 무수정이며, 이
  착지는 문서 1건뿐이다.

## 3. Stage A — 프로비저닝 (네트워크 사용 가능한 통제 환경)

### 3.1 정의

네트워크 사용 가능한 통제 환경에서 고정 의존성(mathlib 캐시 `.ltar` 집합)을
준비하는 단계. Stage A의 산출물은 **generation에 결속**된다 — Stage B는
자신이 선언한 generation의 산출물만 소비하며, 그 외 어떤 캐시 소스도 없다.

### 3.2 Stage A가 기록·결속하는 항목 (generation 결속 산출물)

| 항목 | 내용 |
|---|---|
| `.ltar` 캐시 인벤토리 | 파일 **개수·이름·크기·SHA-256 목록** + **manifest 전체 SHA-256** — generation에 결속 |
| 캐시 endpoint | `cache.mathlib.org` (mathlib 공용 캐시 endpoint — Cache/README.md "Public cache endpoint") |
| mathlib commit | `56a005855ea17e0b0958f73ec801ae140b0a1679` (B-1 Gate A §4.6과 동일 핀 — mathlib v4.35.0) |
| 신뢰한 캐시 namespace | mathlib 캐시 컨테이너(`master`/`forks`) 중 신뢰를 선언한 namespace (Cache/SECURITY.md 신뢰모델) |

### 3.3 `MATHLIB_CACHE_DIR` — exact-path 오버라이드

`MATHLIB_CACHE_DIR` 환경변수는 지정 경로를 **그대로** 사용하는 exact-path
오버라이드다(기본값 `$XDG_CACHE_HOME/mathlib` 또는 `~/.cache/mathlib`를
대체한다). Stage A는 이 경로에 generation 캐시를 확보하고, Stage B는 동일
경로만 노출한다(§4.2) — 경로 해석·재배치 로직이 개입하는 다른 방식은 본
계약의 구성이 아니다.

### 3.4 캐시 CLI 선택적 다운로드 — 참조만

mathlib 캐시 CLI는 인자(모듈명·파일경로·폴더·glob) 지정 시 "지정 파일과 그
전이 import 의존성만" 다운로드한다(Cache/README.md §Arguments 원문: "When
arguments are provided, only the specified files and their transitive imports
are downloaded"). 이는 향후 캡슐 축소 실험의 **공식 수단**이지만, 본 계약은
참조만 하며 축소 실험의 실행·판정은 범위 밖이다(§2).

## 4. Stage B — 검증 (격리 실행 경계)

### 4.1 정의

외부 네트워크 통신이 불가능한 상태에서 Stage A generation 산출물만을 소비해
검증을 수행하는 단계. Stage B의 authority는 자기 격리 구성(§4.2)과 acceptance
판정(§6)이며, Stage A의 네트워크 권한은 Stage B로 이전되지 않는다.

### 4.2 격리 구성 요구사항 (전부 필수 — 어느 하나라도 빠지면 Stage B가 아니다)

| 구성 | 요구사항 | 메커니즘·근거 |
|---|---|---|
| 네트워크 | 외부 네트워크 통신 불가능 | `bwrap --unshare-net` — Linux namespace 차단 |
| 파일시스템 | 최소 노출 | `/usr` 읽기 전용 + 캡슐 경로만(Stage A 캐시 경로 §3.3 포함, 그 외 비노출) |
| 환경변수 | `LAKE_NO_CACHE=true` **프로세스 환경 전체** 적용 | Lake 시작 시 파싱 → 모든 하위명령 + `lake env`/`lake exe` 자식 프로세스에 재수출 (Lake `src/lake/Lake/Config/Env.lean`) |
| 캐시 조작 | 다운로드 경로가 없는 순수 로컬 복원 명령만 허용 | `lake exe cache unpack` (Cache/README.md: "Decompress linked already downloaded files" — 네트워크 경로 없음) |

### 4.3 금지 목록

1. **`--try-cache` CLI 플래그** — CLI 플래그가 env를 우선 override하므로
   `LAKE_NO_CACHE=true`의 환경 전체 적용을 무력화한다(Lake
   `src/lake/Lake/CLI/Main.lean`). `LAKE_NO_CACHE`를 env로 세팅하더라도
   `--try-cache` 병용은 금지다 — §4.2 환경변수 행의 구성을 무효화하는
   조합이기 때문이다.
2. **다운로드 경로가 있는 캐시 명령** — `lake exe cache get` 계열 등.
   Stage B에서 허용되는 캐시 조작은 `unpack`뿐이다(§4.2).
3. **§4.2 격리 구성의 생략·약화** — `--unshare-net` 미적용, 파일시스템
   과노출, `LAKE_NO_CACHE` 미적용 상태의 실행은 Stage B가 아니다(§9
   fail-closed).
4. **Stage A generation 외 캐시 소스의 혼입** — 다른 경로의 `.ltar`, 다른
   namespace(`--cache-from` 확장, `--scope`, `--unsafe`)에서 읽은 캐시는
   Stage A가 선언한 generation이 아니다.

## 5. 해시가 증명하는 범위 (원문 그대로)

> **이 manifest는 특정 시점에 확보한 캐시 파일 집합의 identity를 고정하며
> Stage B에서 동일한 파일 집합이 유지됐는지 검사한다. 캐시 산출물의 원천적
> 진위는 Mathlib의 신뢰된 CI·저장소·캐시 제공자의 신뢰에 의존한다.**

이 경계는 mathlib 공식 신뢰모델 문서(핀 커밋의 `Cache/SECURITY.md`)와
정합하다 — "Explicitly out of scope" 절은 **Validation of artifact
byte-identity**("the cache key identifies inputs, not bytes")와 **Substituted
read endpoint**("the cache does not verify downloaded bytes")를 명시적으로
out of scope로 선언한다. 따라서 SHA-256(manifest 전체 + 파일별)은 **Stage A→B
전송 무결성만 보장**한다 — 원천 진위 아님. 어떤 파생 표현도 이 범위를 넓히지
않으며, §3.2 인벤토리 해시를 "캐시 산출물이 정당하다"는 증거로 인용하는 것은
본 계약 위반이다.

## 6. 캐시 hit ≠ 검증 성공 (acceptance)

Stage B의 acceptance는 **루트 프로젝트 모듈의 실제 새 컴파일·Lean 커널 증명
검사**다. 캐시 복원(`unpack`)의 성공, `.olean` 파일의 존재, 캐시 hit 그
자체는 acceptance가 아니다.

- **재컴파일 강제**: 증명 대상 산출물은 루트 프로젝트의 `.lake/build`를
  **삭제한 후 빌드**해야 하며, 빌드가 루트 모듈을 실제로 새로 컴파일하고
  Lean 커널이 증명을 검사했는지가 acceptance의 판정 대상이다.
- mathlib 캐시(의존 라이브러리)의 hit는 재컴파일 비용 절감 수단일 뿐이며,
  루트 프로젝트(증명 대상)의 판정을 대체하지 않는다.

## 7. Axiom 증거 identity — Mathlib 캐시 identity와 별개

Axiom 증거 identity는 Mathlib 캐시 identity와 **별개**다. §3.2의 manifest
SHA-256은 Stage A→B 전송 무결성 검사용이며, Axiom 증거 identity의 구성
요소가 아니다. Axiom 증거는 아래 목록을 **바깥에 결속**한다:

| # | 결속 항목 | 내용 |
|---|---|---|
| 1 | Rust subject | commit · 파일 manifest |
| 2 | 명제 identity | 증명 대상 명제의 identity |
| 3 | LLBC digest | charon 추출 산출물(LLBC)의 digest |
| 4 | aeneas 출력 Lean digest | aeneas 번역 생성 Lean의 digest |
| 5 | 손모델 | 외부 타입의 최소·정직한 모델(B-1 `TypesExternal.lean` 계열) |
| 6 | 허용된 가정 | `#print axioms` 기준 허용 가정 집합 |
| 7 | Lean/Lake/Mathlib 환경 | Lean·Lake 버전, mathlib commit(§3.2) 등 환경 identity |
| 8 | 실행 기반 | OS · 아키텍처 · 바이너리 · ldd 동적 라이브러리 identity |
| 9 | MERGE_SHA | GitHub 네이티브 MERGE 커밋 SHA (merge authority — AGENTS.md §2) |

분리 규칙: 캐시 identity가 증거 identity를 대체하지 않고, 증거 identity가
캐시 identity를 함축하지 않는다. 위 표의 "Lean/Lake/Mathlib 환경"은 환경의
identity(핀·버전·commit)를 결속하는 것이지, §3.2의 `.ltar` manifest 전체
SHA-256과 동일시되는 것이 아니다.

## 8. 실행 기반 (참고값)

Stage A/B 실행 기반의 참고값이다 — 버전 핀 계약이 아니라 관측 환경 기록이며,
Stage A/B의 실제 실행 기록은 자기 환경을 새로 관측해 기록해야 한다(§7
결속 항목 8과 연동):

| 항목 | 값 |
|---|---|
| OS | Linux Mint 22.3 (noble) |
| 아키텍처 | x86_64 |
| kernel | 6.17.0-42-generic |
| glibc | 2.39 |
| bwrap | 0.9.0 |

## 9. Fail-closed 조항

1. **의존성 누락**: Stage A generation 산출물(`.ltar` 인벤토리·manifest 전체
   SHA-256)의 부재, Stage B에서의 인벤토리 불일치(개수·이름·크기·SHA-256 중
   하나라도 상이) → Stage B 진행 금지.
2. **불확실**: 격리 구성의 적용을 관측할 수 없거나(예: `--unshare-net` 효과의
   관측 불능), 해시 재계산 불능, 환경 요구사항 충족 여부의 판정 불능 → 진행
   금지·UNKNOWN 보고.
3. **required checks 0건 = UNKNOWN / NOT READY** — SUCCESS로 해석하지
   않는다(AGENTS.md §2.3). merge-admission의 authority는 GitHub다.
4. **검증 불가/오래된 증거 = fail closed**(AGENTS.md §4). §5의 신뢰 경계를
   벗어난 주장과 §4.3 금지 위반 실행의 산출물은 Axiom 증거로 수용하지
   않는다.
5. 본 계약(및 그 개정)의 착지 authority는 GitHub 네이티브 MERGE 커밋이다
   (AGENTS.md §2 — merge authority는 GitHub다).

## 10. 본 계약의 위치 (범위 명시)

이 착지는 **계약 사전등록**이며, Stage A/B의 실제 실행·관측·기록은 B-2
workstream의 별도 작업이다. 본 문서는 "캡슐이 검증됐다", "hermetic이
달성됐다"는 주장을 포함하지 않는다. §4.2/§4.3을 위반한 실행의 결과물은 Stage
B 검증이 아니며, 그런 실행을 "Stage B였다"고 기록하는 것은 극장이다
(AGENTS.md §0.9 — 발견 시 `data/debt_registry.json` 등록 대상).

## 참조

- [docs/evidence/b1_gate_a_minimal_proof_2026-11-04.md](../evidence/b1_gate_a_minimal_proof_2026-11-04.md)
  — §4.6(mathlib 핀 `56a0058…`·캐시 9,031 파일 확보), §5.5(네트워크 경계
  관측), §4.7(손모델 선례 — TypesExternal.lean)
- mathlib4 핀 커밋 `56a005855ea17e0b0958f73ec801ae140b0a1679`:
  - [Cache/SECURITY.md](https://github.com/leanprover-community/mathlib4/blob/56a005855ea17e0b0958f73ec801ae140b0a1679/Cache/SECURITY.md)
    — 캐시 신뢰모델: 컨테이너(`master`/`forks`)·4층 강제, "Validation of
    artifact byte-identity" 명시적 out of scope, "the cache does not verify
    downloaded bytes"
  - [Cache/README.md](https://github.com/leanprover-community/mathlib4/blob/56a005855ea17e0b0958f73ec801ae140b0a1679/Cache/README.md)
    — CLI 명령표(`get`/`unpack`), §Arguments(선택적 다운로드), §Public cache
    endpoint(`cache.mathlib.org`), §Environment
    Variables(`MATHLIB_CACHE_DIR`), `.ltar` 형식(leantar), 루트 해시 구성
    (lakefile·lean-toolchain·lake-manifest·컴파일러 git hash·generation
    counter)
- Lean 4 Lake(`leanprover/lean4`):
  - `src/lake/Lake/Config/Env.lean` — `LAKE_NO_CACHE` 파싱·자식 프로세스
    재수출
  - `src/lake/Lake/CLI/Main.lean`, `src/lake/Lake/CLI/Help.lean` —
    `--try-cache` CLI 플래그(env 우선 override)
- [docs/spec/verifier_build_identity.md](verifier_build_identity.md) —
  identity 해시 의미론 선례(§7 "What the identity does NOT claim")
- [docs/spec/obligation_semantics.md](obligation_semantics.md) — 저장소 핀
  경계의 현재 axiom allowlist 정책("If mathlib were imported…" — 본 계약은
  이 경계를 변경하지 않는다)
