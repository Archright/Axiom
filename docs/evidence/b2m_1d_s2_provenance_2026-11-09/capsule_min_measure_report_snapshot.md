# 최소 의존성 폐쇄 — 공식 방법 확정 및 캡슐 정적 측정 보고 (2026-11-05)

> **작업**: Lean 증명 프로젝트의 최소 의존성 폐쇄(minimal dependency closure) 계산의 공식 방법을
> Lean/Lake/Mathlib 공식 문서로 확정하고, B-2 캡슐(`efdced76…` 세대)에 정적으로 적용해 실제 필요
> 집합을 측정한다. 축소 '채택'은 별도 계약 작업 — 본 보고는 방법 확정·측정까지만.
> **규율 문서**: docs/spec/mathlib_hermetic_boundary.md(1c) · docs/spec/proof_dependency_closure.md(1b)
> · docs/spec/aeneas_generation_contract.md(1a) — 전부 원격 main에서 전문 확보(본 디렉터리 보관).

---

## 0. 선행 사실 — 캡슐 본체 소실 (fail-closed 선언)

- **`/tmp/b2_capsule`(180,040파일·11,353,320,247B)·`/tmp/b2_run1..3`·`/tmp/b1_gate_a`·`/tmp/b2_wt`는
  이 기기에 존재하지 않는다** (2026-11-05 실측; `/tmp` 재조사 + `/home` 전역 find 2회 시도 모두 부재 —
  tmpfs 정리 추정, 2026-11-04 실험 이후 기기 재부팅 등이 원인으로 추정되나 원인은 미확정).
- **잔존물(전부 읽기 전용으로만 접촉)**:
  - `~/.cache/mathlib/` — `.ltar` **9,031개·455,355,304B**. 개수·총 바이트가 generation.json
    `stage_a_stats.cache`(file_count 9,031 / total_bytes 455,355,304)와 **바이트 단위 정확 일치** —
    캡슐 `cache/`가 봉입한 것과 동일 집합(§2.3 전수 검증).
  - `~/.elan/toolchains/leanprover--lean4---v4.35.0/` — 캡슐 `toolchain/`의 원본 툴체인.
  - 서브젝트 `~/바탕화면/Axiom_CLI/json` @ `8c535a26…`(무접촉).
  - 원격 GitHub(main)의 계약 3종 + 증거 3종 전문 — generation.json 전문(15,272B)·run1/2/3 로그
    원문 인용을 포함하므로 캡슐 소실에도 **문서로 결속된 관측치**는 사용 가능.
- **결론**: 캡슐의 `.lake/packages`(약 7.3GB)와 leanproj 소스 9파일(내용)이 소실 →
  **캡슐 대상 정적 import 폐쇄 계산은 불가 → 해당 항목은 전부 UNKNOWN(fail-closed)** (§6).
  측정 가능한 잔존물(캐시 전수)·문서 결속 관측치(빌드 플랜)·상류 공개 저장소(핀 커밋)로
  측정 가능한 범위만 측정했다. 측정 근거는 전부 기록 파일로 보관(§8).

---

## 1. 공식 문서 근거의 최소 폐쇄 계산 방법 (산출물 1)

### 1.1 정본 정의 — Lake의 빌드 플랜이 곧 폐쇄다

Lake 공식 문서(leanprover/lean4 `src/lake/README.md`):

- **모듈**: "A **module** is the **smallest unit of code visible to Lake's build system** …
  Modules can import one another in order to use each other's code and Lake exists primarily
  to facilitate this process." (Glossary of Terms)
- **라이브러리 globs**: "`globs`: An `Array` of module `Glob`(s) to build for the library …
  A submodule glob builds every Lean source file within the module's directory …
  **Local imports of glob'ed files (i.e., fellow modules of the workspace) are also
  recursively built.**" (Lean Libraries)
- **모듈 경로 ↔ 파일**: 표준 구조(`Hello/Basic.lean` ↔ `import Hello.*`; `srcDir`가 `lean`의
  `-R` 루트). `import A.B` → `<srcDir>/A/B.lean`.
- **lake-manifest.json**: "Information on the specific revision cloned will then be saved to
  `lake-manifest.json` to **enable reproducibility** … To update … you will need to run
  `lake update`" (Adding Dependencies) — 의존 패키지·리비전의 정본 기록.

→ **최소 의존성 폐쇄 = 루트 라이브러리 glob의 모듈들에서 출발한 `import` 전이 폐쇄**.
이것이 Lake 스스로가 빌드 플랜으로 계산하는 집합이며, 결정적(동일 입력 → 동일 플랜)이다.

### 1.2 정적(읽기 전용) 계산의 공식 선례 — Mathlib 자체 스크립트

Mathlib 공식 저장소(`scripts/README.md` — "Analyzing Mathlib's import structure"):

- `dag_traversal.py` — "**Reusable parallel DAG traversal for Lean import graphs. Parses the
  import DAG from `.lean` source files**" (`DAG.from_directories(Path("."))`,
  `--backward --module '…'` = 역방향 = 전이 import 폐쇄 순회).
- `topological_sort.py` — "Prints Mathlib modules in topological (import-DAG) order".

→ **.lean 소스의 `import` 문을 텍스트로 파싱해 DAG를 만드는 것이 Mathlib 공식의 정적 분석 방법**.
전처리기/매크로로 동적 import가 발생하지 않는 한(Lean 모듈 import는 정적 선언) 결정적이다.

### 1.3 캐시의 공식 최소 확보 수단 — 선택적 다운로드

Mathlib `Cache/README.md` §Arguments (get/get!/get-/lookup 공통):

> Module names: `Mathlib.Algebra.Group.Basic` / File paths / Folder names / Glob patterns …
> **"When arguments are provided, only the specified files and their transitive imports are
> downloaded."**

- 사용 예(README 원문): `lake exe cache get Mathlib/Algebra/Group/Basic.lean` 또는
  `lake exe cache get Mathlib.Algebra.Group.Basic`.
- `lookup [ARGS]` — "Show information about cache files for the given Lean files." (모듈→캐시
  파일 대응 확인용).
- 이 기능은 1c 계약 §3.4가 "향후 캡슐 축소 실험의 **공식 수단**"으로 명시한 바와 동일하다.

### 1.4 `.ltar` 파일명의 인코딩 — 모듈 경로가 아니라 캐시 키 해시다

- `Cache/Requests.lean` `downloadFile`: `let fileName := hash.asLTar` — 파일명은 **UInt64 해시의
  16진수 표기**(실측: 전 9,031개가 `^[0-9a-f]{16}\.ltar$`, 선두 니블 분포 균형 — 해시 명명과
  정합, §2.1).
- 해시 구성(`Cache/README.md` §How It Works > File Hashing): root hash(lakefile.lean +
  lean-toolchain + **lake-manifest.json** + Lean 컴파일러 git hash + generation counter)에
  파일 경로·내용 해시·**import된 파일들의 해시**를 혼합 → "any change to toolchain,
  dependencies, or source files produces a different cache key".
- 즉 **`.ltar` 파일명에서 모듈 경로를 역산할 수 없다**. 모듈→`.ltar` 대응은 캐시 키 계산
  (또는 `cache get/lookup` 실행)으로만 얻는다 — 본 측정은 이를 우회해 **아카이브 내부의
  평문 경로 문자열**(`./.lake/build/lib/lean/<모듈>.olean` 등)을 정적으로 읽어 전수 매핑했다(§2.2).
- `.ltar` 내용(공식): `.olean`·`.ilean`·`.trace`·`.c`·`.hash` — 모듈당 1파일(실측 §2.2).
  내부 콘텐츠는 zstd 압축(magic `28 B5 2F FD` 실측).

### 1.5 빌드 플랜 크기의 관측적 정의 — "N jobs"

Lake 소스(툴체인 커밋 `eb6cafb7290e8…`의 `src/lake/Lake/Build/Run.lean` — 본 디렉터리 보관):

- `MonitorState.totalJobs`는 **큐에 등록된 작업 전체**를 센다(`drainQueue`:
  `totalJobs := s.totalJobs + newJobs.size`). up-to-date(no-op) 모듈 작업도 포함.
- `reportJob`의 출력 가드: `hasOutput || canceled || …` — 출력 없는 up-to-date 작업은
  **줄을 인쇄하지 않지만 카운트에는 포함**.
- 요약 문장: `Build completed successfully ({numJobs} jobs)` (`reportResult`).

→ **"Build completed successfully (N jobs)"의 N은 루트 타깃 폐쇄 전체의 작업 수**이며,
실제 컴파일된 모듈만 세는 수치가 아니다. 이 해석이 run1–3 로그와 정합이다(§4).

### 1.6 방법 확정 (요약)

| 질문 | 공식 답 | 근거 |
|---|---|---|
| (a) Lake의 의존성 해석 규칙 | 루트 라이브러리 glob 모듈의 `import` 전이 폐쇄 = 빌드 플랜; 모듈명↔`<srcDir>/경로.lean`; 패키지·리비전은 lake-manifest가 정본 | Lake README (Lean Libraries·Glossary·Adding Dependencies) |
| (b) 필요 집합만 캐시에서 가져오는 공식 기능 | **있다** — `lake exe cache get <모듈|파일|폴더|glob>`: "only the specified files and their transitive imports are downloaded" | Cache/README.md §Arguments (1c 계약 §3.4가 참조한 바와 동일) |
| (c) `.ltar` 파일명 인코딩 | **모듈 경로를 인코딩하지 않는다** — UInt64 캐시 키 해시(root hash+경로+내용+import 해시). 모듈→파일명은 키 계산·`lookup`으로만 | Cache/Requests.lean `hash.asLTar`·Cache/README.md §File Hashing |

**최소 폐쇄의 가장 근본적·결정적 공식 방법**: ① 정적 — .lean 소스에서 `import` 문을 파싱(Mathlib
`dag_traversal.py` 방식)해 전이 폐쇄를 계산한다(읽기 전용·결정적). ② 실행 — `lake exe cache get
<루트 모듈>`이 동일 폐쇄의 캐시 파일만 확보한다(공식 선택적 다운로드). ③ 검증 — `lake build`의
"Build completed successfully (N jobs)" N이 정적 폐쇄와 정합하는지로 기계 대조한다.

---

## 2. 측정 결과 (산출물 2)

### 2.1 잔존 캐시의 실측 (`~/.cache/mathlib` — 정적·읽기 전용)

| 항목 | 실측값 | 캡슐 기록값(generation.json) | 일치 |
|---|---|---|---|
| `.ltar` 파일 수 | 9,031 | `cache_ltar_file_count` 9,031 | ✓ |
| 총 바이트 | 455,355,304 | `stage_a_stats.cache.total_bytes` 455,355,304 | ✓ (바이트 정확) |
| 파일명 형식 | 전원 `^[0-9a-f]{16}\.ltar$` (니블 균형 ~565/버킷) | — | 해시 명명과 정합 |
| provenance 문자열 | 전원 `git=mathlib4@56a005855ea17e0b0958f73ec801ae140b0a1679` | mathlib 핀(1a §5.3) | ✓ 전수 일치 |

### 2.2 `.ltar`→모듈 전수 매핑 (아카이브 내부 평문 경로에서 정적 파싱 — 도구 실행 0)

각 `.ltar`는 **정확히 1개 모듈**의 산출물 묶음이다(`.olean`·`.olean.server/private`·`.ilean`·
`.trace`·`.ir`·`.ir.sig`·각 `.hash`·경우에 따라 `.c`). 내부 경로에서 모듈명을 추출한 전수 매핑
(미매칭 0):

| 패키지 | 모듈 수 | `.ltar` 바이트 합 | 상류 트리(핀 커밋) 모듈 수 | 대조 |
|---|---:|---:|---:|---|
| **mathlib4** (56a0058) | **8,625** | 422,490,461 | 8,625 (`Mathlib/**` 8,624 + `Mathlib.lean` 1) | **정확 일치** |
| batteries (66e4691) | 195 | 10,985,288 | 195 | **정확 일치** |
| aesop (4a174c4) | 132 | 12,154,178 | 138 | −6 (아래) |
| importGraph (a41f0e9) | 35 | 3,035,834 | 51 | −16 (CLI 도구 모듈) |
| Qq/quote4 (dce0ad7) | 14 | 1,798,214 | 14 | **정확 일치** |
| proofwidgets (df72b02) | 13 | 3,281,599 | 43 | −30 (위젯 컴포넌트·데모) |
| plausible (dfa4f38) | 13 | 1,157,615 | 13 | **정확 일치** |
| LeanSearchClient (d6b4c7b) | 4 | 452,115 | 4 | **정확 일치** |
| **합계** | **9,031** | **455,355,304** | — | ✓ |

- 합계가 9,031파일·455,355,304B와 정확히 닫힘. 상류 트리 카운트는 GitHub git-trees API(읽기
  전용)로 각 패키지 **매니페스트 핀 리비전**에서 실측.
- **차이의 정체(전수 특정)**: aesop −6(`Aesop.Builder`·`Aesop.Tree` 등), importGraph −16
  (`ImportGraph`·`ImportGraph.Export.*`·`ImportGraph.FromSource` 등 CLI 전용), proofwidgets −30
  (`ProofWidgets.Component.*`·`ProofWidgets.Demos.*`). mathlib 저장소의 비-라이브러리 .lean
  (Archive/ 등 약 595개)도 캐시에 없음.
- **핵심 발견**: 9,031 `.ltar`는 "전체 Mathlib"이 아니라 **mathlib CI의 기본 빌드 폐쇄** 자체다
  (Mathlib 라이브러리 8,625 + 그 빌드가 도달한 의존 패키지 모듈 406). 캡슐은 이 집합 전체를
  세대로 봉입했다.
- 매핑 상세: `ltar_module_map.json`(9,031항목)·`package_census.json`·`mathlib_subtree_census.json`.

### 2.3 Mathlib 서브트리 분포 (캐시 전수, 상위)

| 서브트리 | 모듈 | MB | | 서브트리 | 모듈 | MB |
|---|---:|---:|---|---|---:|---:|
| Mathlib.Algebra | 1,380 | 54.3 | | Mathlib.LinearAlgebra | 386 | 20.9 |
| Mathlib.CategoryTheory | 1,131 | 51.9 | | Mathlib.MeasureTheory | 339 | 15.1 |
| Mathlib.Analysis | 812 | 38.5 | | Mathlib.Order | 335 | 13.7 |
| Mathlib.RingTheory | 729 | 35.5 | | Mathlib.NumberTheory | 248 | 12.8 |
| Mathlib.Topology | 703 | 26.8 | | Mathlib.Combinatorics | 201 | 9.6 |
| Mathlib.Data | 661 | 21.1 | | Mathlib.Tactic | 398 | 54.3 |
| (그 외 23개 서브트리 + 루트 `Mathlib` 1) | | | | **합계 8,625** | | 422.5 |

### 2.4 필요 집합 — 기계 관측치와 상·하한 (정확값은 UNKNOWN)

**관측(문서 결속, run1=run2=run3 원문)**: `Build completed successfully (1801 jobs)`. 루트
컴파일은 5모듈뿐(`✔ [1796..1800/1801] Built AsBool.TypesExternal/Types/Funs/Spec/AsBool` — 각
시간 표기), 그 외 1,795 작업은 up-to-date로 silent(§1.5 가드로 설명과 정합). Aeneas 라이브러리
(경로 의존, 태그 `nightly-2026.11.03-ab34bd2`)는 `backends/lean`에 **249모듈**(Aeneas/ 248 +
루트 1)이며 prebuilt `.lake/build`(B-1 §4.6, 203MB)로 재사용됐다.

| 항목 | 값 | 성격 |
|---|---:|---|
| 빌드 플랜 총 작업 | 1,801 | 기계 관측(run1–3) |
| 루트 모듈(실컴파일) | 5 | 기계 관측 |
| 첫 루트 모듈 이전 완료 작업 | 1,795 | 기계 관측(로그 진행번호) |
| **필요 `.ltar` 상한** | **≤ 1,795 / 9,031 = ≤ 19.88%** | 유도(작업≥모듈 가정 하 상한; Aeneas 249·집계 작업 미차감) |
| 필요 `.ltar` 하한(추정) | ≥ 1,546 / 9,031 = 17.12% | 추정치(상한 − Aeneas 전모듈; 근거 약함) |
| 필요 바이트 상한(균등 밀도 가정) | ≤ 90.5 MB / 455.4 MB | 균등 가정은 부정확 — 실제 UNKNOWN |
| **정확한 필요 모듈·`.ltar`·바이트 집합** | **UNKNOWN** | **측정 불가 — 캡슐 소스 소실(§0)** |

### 2.5 전체 캡슐 대비 (generation.json `stage_a_stats` 정본 + 본 측정)

| 캡슐 구성 | 파일 | 바이트 | 비고 |
|---|---:|---:|---|
| inputs/ (leanproj+packages+aeneas prebuilt) | 153,082 | 7,759,453,116 | `.lake/packages` 약 7.3GB 포함(과제문) — 소실, 내용 UNKNOWN |
| toolchain/ | 17,925 | 3,137,937,793 | 원본 `~/.elan` 잔존 |
| **cache/** | **9,031** | **455,355,304** | 잔존 캐시와 바이트 정확 일치 — 전수 재검증 완료 |
| provenance/ | 2 | 574,034 | LLBC 2종(참조 전용) |
| **합계** | **180,040** | **11,353,320,247** | generation.json 정본 |

---

## 3. 불필요 패키지/서브트리 (산출물 3 — 폐쇄 기준)

**증명 가능(기계 관측 + 전수 센서스의 논리)**:

- **Cli(lean4-cli, c24fe607…)** — 캐시에 Cli 모듈이 **0개**(매니페스트에는 존재하는 8개 의존 중
  하나). 런타임에 Cli 모듈이 컴파일됐다는 관측도 없음(빌드 로그의 "Built"는 루트 5개뿐).
  빌드 성공 관측 = 폐쇄 ⊆ (캐시 해제 9,031) ∪ (Aeneas prebuilt) ∪ (루트 5)이므로,
  **Cli 패키지는 AsBool 폐쇄에서 사용되지 않는다**가 관측으로 확정된다.
  (capsule의 `.lake/packages`에 Cli 소스가 봉입돼 있었 가능성 높음 — B-1 "inherited 8"·
  aeneas/mathlib 매니페스트와 정합 — 이는 소스 존재 여지이지 폐쇄 사용이 아니다.)

**강한 증거·미증명 (UNKNOWN)**:

- **importGraph 35모듈 + LeanSearchClient 4모듈**: 캐시에 존재하나 mathlib CI가 **도구 빌드**
  때문에 넣은 것으로 추정(수학 라이브러리 import가 아님). AsBool 폐쇄가 이들을 필요로 한다는
  관측은 없으나, 사용되지 않음을 **소스 없이는 증명 불가** → 후보(UNKNOWN).
- **aesop −6·importGraph −16·proofwidgets −30 등 캐시 바깥 모듈**: 정의상 폐쇄 후보 아님
  (mathlib CI 폐쇄에서도 제외됨) — 참고.
- **Mathlib 8,625모듈 중 플랜 밖 약 7,230+**: 1,801 작업 관측과 캐시 센서스의 차. 어떤
  서브트리가 플랜 밖인지는 **정적 폐쇄 계산 불가로 특정 불가**(예: Mathlib.CategoryTheory
  1,131모듈 중 다수가 Aeneas가 도달하지 않는 영역일 것으로 예상되나 예상일 뿐 — UNKNOWN).
- 폐쇄 기준의 정식 규칙은 1b 계약(§4·§5 — 포함·제외 모두 근거 기록 의무)이 정본이다.

---

## 4. run3 교차 검증 (산출물 4)

run3 기록 디렉터리(`/tmp/b2_run3/records/`)는 소실. 병합 증거 문서에 **원문 인용**으로 결속된
관측치로만 교차 검증했다:

| 축 | 관측치(문서 원문) | 본 측정과의 정합성 |
|---|---|---|
| 실제 컴파일 모듈 | 5개 루트 모듈(`Built AsBool.{TypesExternal,Types,Funs,Spec}` + `AsBool`) | 루트 라이브러리 glob 폐쇄의 시점집합과 일치 — 5종 모두 폐쇄 정의상 포함 ✓ |
| olean digest 5종 | `e5b1ef42…`·`bdf7f0ff…`·`5f604d40…`·`d66574f5…`·`a41a0bed…` (run1=run2=run3) | 대상 파일 소실 — 재해시 불가(관측 유지). 폐쇄-포함 검증에는 영향 없음 ✓ |
| 플랜 크기 | `Build completed successfully (1801 jobs)` | §1.5 소스 해석으로 '폐쇄 전체 작업 수'로 확정 — 캐시 9,031 ⊇ 플랜(규모 정합) ✓ |
| 캐시 전량 해제 | `Already decompressed 9031 file(s)` | 잔존 캐시 전수(9,031)와 일치 ✓ |
| 공리 | `[propext, Quot.sound]` ×2, sorryAx 0 | 변동 없음(무관) ✓ |
| **전수 ⊆ 검증**(실제 컴파일·해제된 모듈 전체가 정적 폐쇄에 포함되는지) | — | **불가** — 정적 폐쇄 자체를 계산할 수 없음(§0) → UNKNOWN |

부분 결론: 5개 실컴파일 모듈 ⊆ 폐쇄(자명·확정)·플랜 1,801 ⊆ 캐시 9,031(규모 정합·확정).
전수 포함 검증은 fail-closed.

---

## 5. 향후 최소 캡슐 실험 acceptance 기준 권고 (산출물 5 — 간략)

1c 계약(§3.4·§6·§9)에 결속된 절차를 따르되, 아래를 추가 권고:

1. **프로비저닝은 공식 수단만**: Stage A에서 `lake exe cache get <루트 모듈>`(선택적 다운로드)로
   최소 `.ltar` 집합을 확보하고, 1c §3.2 인벤토리(개수·이름·크기·SHA-256 목록 + manifest 전체
   SHA-256)를 세대에 결속. `generation.json`의 `cache_ltar_file_count`·`cache_inventory_digest`
   갱신 — **기존 세대 수정이 아니라 신세대**(1a §8: 구성요소 변경 = 신세대, append-only).
2. **정적 폐쇄 계산을 먼저 기록**: .lean 소스에서 import DAG를 정적 파싱(Mathlib
   `dag_traversal.py` 방식 준용 — 1b §4 절차: 출발점=명제, 포함·제외 근거 양방향 기록)해
   모듈 목록을 산출하고, `lake build`의 N jobs와 **정합(reconciliation)**을 acceptance 조건으로.
   N이 전량 세대(1,801)와 동일해야 한다 — 캐시 축소가 플랜을 바꾸면 안 된다.
3. **누락 0 증명**: 최소 캐시에서 Stage B 재빌드 시 **"Built" 라인은 루트 5개뿐**이어야 한다
   (Mathlib 측 재컴파일 라인 1개라도 나오면 최소 집합이 부족한 것 = FAIL). 루트 `.lake/build`
   삭제 후 강제 신규 컴파일은 1c §6 그대로.
4. **판정 축 무변동**: `#print axioms` 2행 바이트 동일·sorryAx 0·olean digest 5종이 전량 세대
   값과 동일(`e5b1ef42…` 등 §4 표) — 산출물 identity 불변이 최소화의 무결성 증거.
5. **Stage B 구성 무변동**: bwrap `--unshare-net`·`LAKE_NO_CACHE=true`·`MATHLIB_CACHE_DIR=/cache`·
   ro-bind 3종·`--die-with-parent` — 1c §4.2 전부 + §4.3 금지(`cache get` 계열·`--try-cache`) 유지.
   Stage B에서 허용되는 캐시 조작은 `unpack`뿐.
6. **축소의 측정값 기록**: 최소 `.ltar` 수·바이트·전량(9,031·455,355,304B) 대비 비율(본 보고
   상한 19.88% 대비 실측치)·제외 패키지 목록(Cli 확정 + 후보들은 근거와 함께)을 증거 문서에
   수치로 남긴다.
7. **fail-closed**: 위 어느 하나라도 관측 불능·불일치면 UNKNOWN(조용한 PASS 금지) — 1c §9·
   1a §9 준용.
8. (설계 유의 — 미해결 사항) `.lake/packages` 소스 트리 동반 축소 가능 여부는 별도 검증 필요:
   Lake의 up-to-date 판정이 소스 부재를 어떻게 다루는지 공식 문서로 확인되지 않았다
   (본 보고 범위 밖 — 신세대 계약 설계 시 확정 요망).

---

## 6. 정적으로 측정 불가한 부분 (산출물 6 — fail-closed 전수)

| 항목 | 상태 | 원인 |
|---|---|---|
| AsBool 프로젝트 5개 .lean의 import문·내용 | **UNKNOWN** | 캡슐 inputs 소실(해시·크기만 문서 결속) |
| `.lake/packages` 내 Mathlib/Aeneas 소스 import 그래프 | **UNKNOWN** | 약 7.3GB 트리 소실 |
| 정적 전이 import 폐쇄(필요 모듈 정확 집합) | **UNKNOWN** | 위 2항 — 폐쇄 계산의 입력 자체가 없음 |
| 필요 `.ltar` 정확 수·바이트 | **UNKNOWN** (상한 ≤1,795/≤90.5MB만 유도) | 폐쇄 없이는 모듈→`.ltar` 대응 불가 |
| run3 olean 전수 재해시·전수 ⊆ 검증 | **UNKNOWN** | run3 records 소실(문서 인용치만 존재) |
| 캡슐 `cache_inventory_digest`(bd846991…) 재계산 | **UNKNOWN** | 파일 소실 + 트리 digest 알고리즘이 문서에 미기록 |
| Cli 미사용의 반증 가능성 | 관측으로 '미사용' 확정(§3) | — |
| `~/.cache/mathlib`와 캡슐 `cache/`의 파일별 동일성 | 개수·총바이트·provenance 일치(§2.1) | 파일별 sha256 목록(inventory) 소실로 전수 대조 불가 — 유사 집합(동일 통계)임은 확정 |

**시도 기록(각 2회)**: `/tmp` 경로 2회 재확인(ls·find), 홈 전역 `b2_*`/`.ltar` find 2회 — 전부 부재.

---

## 7. 결론

- **공식 방법은 확정됐다**: 정적 import-DAG 파싱(Mathlib 공식 스크립트 방식) + Lake 빌드 플랜
  (globs의 전이 import = 플랜) + `lake exe cache get` 선택적 다운로드가 공식 최소 확보 수단이며,
  `.ltar` 파일명은 모듈 경로가 아니라 캐시 키 해시다(모듈→파일 대응은 키 계산/lookup 필요).
- **캡슐에 대한 실측은 캐시 전수로 폐쇄됐다**: 9,031 `.ltar` = mathlib CI 빌드 폐쇄 자체
  (mathlib4 8,625 + 7개 의존 패키지 406)임을 전수 매핑·상류 트리 교차검증으로 확정. 캡슐이 필요한
  집합은 이 안의 부분집합으로, 기계 관측(1,801 jobs)으로 **상한 ≤ 19.88%**.
- **정확한 최소 집합은 측정 불가였다**: 캡슐 본체 소실로 import 폐쇄 계산의 입력(leanproj·
  packages 소스)이 없다 — fail-closed로 UNKNOWN 처리. 축소 '채택'은 이 결함을 해소할
  신세대 프로비저닝(§5 권고 절차)과 함께 별도 계약 작업으로 수행해야 한다.

## 8. 보관 파일 (전부 `/tmp/capsule_min_measure/`)

- `report.md`(본 문서) · `summary_numbers.json`(표 수치)
- 원격 문서: `mathlib_hermetic_boundary.md`·`proof_dependency_closure.md`·
  `aeneas_generation_contract.md`·`b2_hermetic_proof_capsule_2026-11-04.md`·
  `b2_capsule_detached_acceptance_2026-11-04.md`·`b2_c7_crash_classification_2026-11-04.md`
- 측정 데이터: `ltar_module_map.json`(9,031 .ltar→모듈 전수)·`package_census.json`·
  `mathlib_subtree_census.json`·`mathlib_pin_files.txt`(9,397 경로)·
  `mathlib_pin_lake-manifest.json`·`dep_tree_counts.json`·`dep_tree_counts2.json`
- Lake 소스(툴체인 커밋): `lake_Build_Run.lean`(totalJobs·reportJob)·`lake_CLI_Build.lean`
- Aeneas(태그): `aeneas_lean_files.txt`(275)·`aeneas_lake-manifest.json`·`Aeneas_root.lean`
- `ltar_census_raw.txt`(초기 실행 기록)

**실행 도구**: lake/lean/elan/aeneas/charon/leantar **0회 실행**(하드 제약 준수). 사용한 것은
gh api(공개 저장소 읽기)·python/grep/find(정적 분석)뿐. 캡슐 잔존물·서브젝트·로컬 clone 전부
읽기 전용 접촉, 산출물은 `/tmp/capsule_min_measure/` 아래에만 작성.
