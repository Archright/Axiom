# B-2 — Hermetic Proof Capsule: as_bool 증명의 격리 재현 run1·run2 (2026-11-04)

> **Status**: Observation evidence record — **읽기 전용 캡슐 재실행 관측** (`src/`·Makefile·`config/policy/**`·`.github/**` 무수정, 제품 코드 무변경, main worktree 무수정, FROZEN 무수정; 캡슐·서브젝트 경로는 전부 읽기 전용으로만 접촉. Axiom4에 착지하는 것은 본 문서 1건)
> **Created**: 2026-11-04
> **Written at**: branch `work/b2-capsule-2026-11-04` (worktree `/tmp/b2_wt/s2`), branch base = origin/main `7483f64436419a41926fe763fae898e05c845cd8` (PR #1269 merge — 1a `0010bbd94`·1b `b2f807e5e`·1c `b56c3c512` 계약 커밋 포함)
> **Governing docs**:
> - 작업 계획 v6.1 — A안 "Minimal Hermetic Proof Capsule" (에이전트 세션 작업 계획; 저장소 미수록 — 본 문서가 그 S2-B 단계를 수행)
> - [docs/spec/aeneas_generation_contract.md](../spec/aeneas_generation_contract.md) (1a 세대 계약 — PR #1268, MERGE_SHA `0010bbd94a50602e44e2136598ef56ac97083289`)
> - [docs/spec/proof_dependency_closure.md](../spec/proof_dependency_closure.md) (1b 증명 의존성 폐쇄 규칙 — PR #1266, MERGE_SHA `b2f807e5e37fd438359c258712cf9aaab29b9750`)
> - [docs/spec/mathlib_hermetic_boundary.md](../spec/mathlib_hermetic_boundary.md) (1c Mathlib hermetic 실행 경계 — PR #1267, MERGE_SHA `b56c3c512c94b43965c7d799b12146f66e35ece9`)
> - [docs/evidence/b1_gate_a_minimal_proof_2026-11-04.md](b1_gate_a_minimal_proof_2026-11-04.md) (B-1 Gate A — MERGE_SHA `c3a4164324c479b34c5caefd94b08fe5ad263014`; §4.1 도구 identity·§4.7 손모델·§4.8 axioms·§4.9 Rust 대조·§4.10 mutation·§5.3 해시·§5.4-3 1토큰 수정)
> - [docs/evidence/b1_gate_b_capability_census_2026-11-04.md](b1_gate_b_capability_census_2026-11-04.md) (B-1 Gate B — MERGE_SHA `356dbb6b935f02623d7c97a33f5c812912082e8c`)
>
> **원칙**: 기계 출력과 오류 문자열은 원문 그대로 인용한다(재작성·요약·번역 없음). 이 문서는 관찰을 기록하며 serde_json·Aeneas·Charon에 대한 어떤 참·거짓 주장도 하지 않는다 (§Non-claims).

7-field identity (FREEZE.md §1 형식 준용 — 값은 본 문서 정체성):

- PROJECT_UNDER_TEST: **Hermetic Proof Capsule `/tmp/b2_capsule`** — B-1 Gate A가 확정한 as_bool 증명 입력(번역 Lean·손모델·명제·mathlib 캐시·Lean 툴체인)을 세대 고정 단위로 봉입한 캡슐(180,040파일·11,353,320,247B). 서브젝트 참조 identity: serde_json v1.0.154 @ `8c535a260ce561eaab4111aafc29038eb9f77ff3` (B-1 §4.1 결속)
- REVISION: `8c535a260ce561eaab4111aafc29038eb9f77ff3` (서브젝트 — generation.json `subject.git_head` 정본, 본 세션은 서브젝트에 접촉 0건)
- AXIOM_REVISION: `7483f64436419a41926fe763fae898e05c845cd8` (origin/main — 본 문서 작성 시점, branch base)
- CONFIG: 캡슐·서브젝트(`/tmp/b2_capsule`·`<workspace>/json`·`/tmp/b1_gate_a`·`/tmp/b1_gate_b`·`~/.cache/mathlib`·`~/.elan`) 전부 **읽기 전용** — run2의 쓰기는 격리 실행 내부(tmpfs `/tmp`·`--bind` workspace)에서만 발생. Stage B는 bwrap `--unshare-net` 샌드박스에서 네트워크 단절 상태로 실행
- TOOLCHAIN_ID: 캡슐 고정 Lean **4.35.0** (`toolchain/bin/lean` sha256 `bf8d54e4…ceb38`, generation.json 정본) + 실행 게이트 bwrap **0.9.0** (binary sha256 `e3189038…30f71`) — 도구 세대는 generation.json에 봉입되어 실행 사이 고정(1a 세대 계약)
- SCOPE: **Stage B(재컴파일·커널 판정) 독립 재실행의 관측만** — run1과 run2의 판정·`#print axioms`·olean digest 대조. **범위 밖**: rustc·charon·aeneas 재실행(봉입 identity로만 결속 — §4.2), 캡슐 축소(import closure 기반 최소화), 타 머신 재현, Stage 3 채택 adjudication, C1~C8 판정
- EXPERIMENT_ID: b2-minimal-hermetic-proof-capsule-2026-11-04

---

## 1. Question

이 문서가 답하는 질문:

1. **고정 generation·격리 실행에서 as_bool 증명이 재현 가능한가** — pristine 캡슐의 독립 Stage B 재실행(run2)이 run1과 동일한 Lean 커널 판정(`#print axioms`), 동일한 산출물 identity(olean digest)를 산출하는가?
2. 재실행이 캡슐 자체를 변경시키지 않았는가 — 실행 전·후 캡슐 불변성(inventory 전수 재해시)이 유지되는가?

## 2. Context

- B-1 Gate A(MERGE `c3a4164324c479b34c5caefd94b08fe5ad263014`)는 serde_json `Value::as_bool`의 Rust 소스→LLBC→Lean 번역→손모델→커널 증명(§4.8, sorryAx 0)→Rust 실행 대조(§4.9, 7입력 불일치 0)→mutation 음성(§4.10, clause 1 킬)까지 관측했다. 그러나 B-1의 Lean 증명은 `/tmp/b1_gate_a/leanproj` 가변 경로에서 실행됐고, mathlib 캐시는 네트워크 1회 확보(B-1 §5.5)였다.
- 본 B-2는 그 증명 입력 전체를 **세대 고정 캡슐**(`/tmp/b2_capsule`)에 봉입하고(Stage A — 세부는 §4.1), 봉입된 입력만으로 봉입된 툴체인·네트워크 단절 환경에서 Stage B를 재실행한다(Stage B). 세대 identity·실행 경계는 1a·1b·1c 계약(Governing docs)에 사전등록되어 있으며, 본 문서는 그 계약에 결속된 첫 실행 증Evidence다.
- Stage B의 정본 실행 구성은 **generation.json `sandbox_config`**다 — 하네스 스크립트·임의 판단이 아니라 봉입된 구성이 실행을 결정한다(§4.3).

## 3. Scope

- **범위 안**: (a) 캡슐 사전 무결성 검증(generation.json/inventory.json digest + 코어 9파일 + toolchain bin 4종 + lib 5종 + `.ltar` 개수 + F4 cache — §5.6), (b) pristine 캡슐의 `/tmp/b2_run2/` 독립 Stage B 실행(generation.json sandbox_config 준용), (c) run1↔run2 비교(판정·axioms·olean digest 5종), (d) 실행 후 캡슐 불변성 재검(사전 항목 + inventory 전수 재해시), (e) 본 문서 착지.
- **범위 밖**: rustc·charon·aeneas 재실행(A안 경계 — Stage B는 B-1 산출 Lean 증명 입력의 재컴파일·커널 판정만 수행), 캡슐 축소, 타 머신 재현, Stage 3 채택 adjudication, detached cold acceptance(후속 별도 단계).
- 원본 clone 워킹트리 무수정 — 커밋·push는 전용 worktree(`/tmp/b2_wt/s2`)에서만. 캡슐 내부에는 어떤 파일도 쓰지 않는다(§5.6 전수 재해시로 기계 검증).

## 4. Procedure

### 4.1 Stage A — 캡슐 조립 요약 (S2-A, 본 세션 이전 단계)

- 캡슐: `/tmp/b2_capsule` — 180,040파일·11,353,320,247B. 구성: `inputs/`(153,082파일 — B-1 leanproj 전체: 번역 Lean·손모델·명제·mathlib 패키지) + `toolchain/`(17,925파일 — Lean 4.35.0 툴체인·leantar·clang) + `cache/`(9,031파일 — mathlib 캐시 `.ltar` 전수) + `provenance/`(2파일 — B-1 LLBC 2종, 참조 전용·샌드박스 미마운트) + `generation.json`·`inventory.json`.
- **generation.json**(15,272B)이 세대 정본이다: 서브젝트 identity·B-1 결속·stage_b_inputs(코어 9파일·toolchain bin 4종·lib 5종 sha256)·실행 기록(execution_base — bwrap·stage_b.sh sha256, ldd closure 전수)·sandbox_config(bwrap 인자·env)·expected_verdict·stage_a_stats. inventory의 digest만 기록(자기참조 회피)하므로 **generation.json 자신의 sha256 `efdced76b105cc4843aad99cbe2f4eedab039439742870c34d85107e5d1b5133`은 본 문서에 기록**한다. `sha256(inventory.json)=742ec2c0f78c3490621d42c67e6f88698f5588422f95b1fcf612a5af9f1d781e`(전문 §5.2 인용).
- S2-A에서 run1을 실행해 expected_verdict 충족을 확인(§5.3) — 하네스 관측 코드 수정 1건 발생·처리(§7 Deviations 1).

### 4.2 Stage B 실행 경계 — 도구 세대는 봉입 identity로만 결속 (실행 안 함)

- Stage B에서 **실행하는 것**: 캡슐 `toolchain/bin/`의 lean·lake(그리고 캡슐 cache의 `.ltar`를 소비하는 `lake exe cache unpack`, 링크 클로저의 `/usr` 공유 라이브러리). 
- Stage B에서 **실행하지 않는 것**(1a 세대 계약의 identity-only 결속 — generation.json `identity_only_bound_not_executed`): rustc(추출 1.100.0-nightly `923c95cdf` / 실행 1.95.0 `59807616e`)·charon(0.1.304, `7b462d91…`, sha256 `42267416…32a59c`)·aeneas(nightly-2026.11.03-ab34bd2, sha256 `12e6042c…53a9c`). 이들은 **B-1에서 실행 완료·증Evidence 결속**이며 캡슐에 도구 바이너리로서 포함되지 않는다(aeneas·charon·rust 원본은 캡슐 미포함). 아래 섹션들이 재실행 없이 인용하는 근거:
  - 도구 identity: B-1 §4.1 (릴리스 태그·sha256·버전 원문)
  - Rust 실행 대조(7입력 불일치 0): B-1 §4.9 — **인용, 재수행 아님**
  - mutation 음성(clause 1 킬·clause 2 생존): B-1 §4.10 — **인용, 재수행 아님**
  - Funs.lean 1토큰 수정의 근거: B-1 §5.4-3 (§5.7 F1)

### 4.3 Stage B 실행 — run1과 run2

- **정본 구성**: generation.json `sandbox_config.bwrap_args`(전문 §5.2) — `--unshare-net` + `/usr` ro-bind + `/toolchain`·`/cache`·`/tmp/b1_gate_a/leanproj` ro-bind(캡슐 서브패스) + `--tmpfs /tmp` + workspace rw-bind + `--clearenv` 환경 고정(PATH·HOME·LANG·TMPDIR·LAKE_NO_CACHE·MATHLIB_CACHE_DIR) + `--die-with-parent`. 실행 명령: `/bin/bash /workspace/stage_b.sh`.
- **stage_b.sh** (sha256 `9197a0f02f829455b62660f9f8894bfa04430a1060b4ee731c0ee52d3fd54e39` — run1 최종본·generation.json `execution_base.stage_b_sh_sha256`·run2 배치 사본 3자 일치 실측): `[0]` 샌드박스 상태(id·/home·/root·curl) → `[1]` 캡슐 leanproj를 `/workspace/leanproj`로 복사 → `[2]` `.lake/build` 삭제(강제 신선 컴파일) → `[3]` `lake exe cache unpack` → `[4]` `lake build` → `[5]` `lake env lean PrintAxioms.lean` → `[6]` olean 전수 sha256 → `[7]` ro-mount 3종 write test.
- **run1** (`/tmp/b2_run1/`): bwrap_args의 workspace 소스 = `/tmp/b2_run1/workspace`. 1차 시도는 하네스 stage_b.sh 결함(set -e와 curl 관측 코드 충돌)으로 실패 → 관측 코드만 수정 후 generation.json 갱신·pristine 캡슐 재실행(§7-1).
- **run2** (`/tmp/b2_run2/`): 동일 bwrap 구성에서 workspace 소스만 `/tmp/b2_run2/workspace`로 치환한 유일 편차(§7-2)로 독립 실행. bwrap 명령은 **generation.json을 직접 읽어 생성**(run2 구성 파일 `bwrap_cmd_generated.sh`) — run1 로그의 재타이핑 없음. stage_b.sh는 정본 digest와 일치하는 새 파일을 run2 workspace에 배치(digest 대조로 동일성 검증). 캡슐은 전 과정 읽기 전용.
- **비교 기준**: 브리프·계약상 필수 기준은 **Lean 커널 판정**(`#print axioms`, sorryAx 0)이며 olean digest는 동일 기대 산출물 identity다. digest 불일치 시 원인을 기록하되 판정 기준은 커널 판정이다(§5.5 — 본 실행에서는 5종 전부 동일해 기준 논점 미발생).

## 5. Result

### 5.1 캡슐 정본 digest (머릿 요약)

| 항목 | sha256 |
|---|---|
| `generation.json` (세대 정본 — 자기참조 회피로 inventory digest만 기록) | `efdced76b105cc4843aad99cbe2f4eedab039439742870c34d85107e5d1b5133` |
| `inventory.json` (전수 파일 인벤토리 — 180,040항목) | `742ec2c0f78c3490621d42c67e6f88698f5588422f95b1fcf612a5af9f1d781e` |

### 5.2 generation.json 전문 (세대 정본 — /tmp/b2_capsule/generation.json, 15,272B)

```json
{
 "experiment": "b2-minimal-hermetic-proof-capsule-2026-11-04",
 "approach": "A안(Minimal Proof Capsule)",
 "subject": {
  "crate": "serde_json",
  "git_head": "8c535a260ce561eaab4111aafc29038eb9f77ff3",
  "file_manifest_sha256": "8045f3b1ce56398fe506aeec9f9344405e32cd7dffda64ddaff4dbd0db6c7cd4",
  "target": "serde_json::value::Value::as_bool (src/value/mod.rs:708)"
 },
 "b1_binding": {
  "gate_a_merge_sha": "c3a4164324c479b34c5caefd94b08fe5ad263014",
  "evidence_doc": "docs/evidence/b1_gate_a_minimal_proof_2026-11-04.md",
  "llbc": [
   {
    "path": "provenance/as_bool.llbc",
    "bytes": 287322,
    "sha256": "cfa5a04f99d55a54ebe098b30256712078c6ff271791ab8b6200de311a5e3dfc"
   },
   {
    "path": "provenance/as_bool_mut.llbc",
    "bytes": 286712,
    "sha256": "4e73fe6051f897d1e704d2602f8e6a7bbff587a26ce2dc6b9e75034c53ff4373"
   }
  ],
  "llbc_note": "provenance/ 참조 전용 — Stage B 샌드박스에 마운트하지 않는다(A안 경계의 구조적 표현)",
  "f1_funs_lean": {
   "generated_original": {
    "sha256": "e0fec2a836a12ffd6588f501218522ceb2895f8d16b866f9b727d9e841951b32",
    "bytes": 1306
   },
   "project_one_token_edited": {
    "sha256": "abaca6f68ab304c935f2d87564c5f19be6e80ba8aac4ddd0a2db724807e1e0e8",
    "bytes": 1313
   },
   "diff": "Option Bool → Option _root_.Bool",
   "justification": "B-1 §5.4-3 (enum 변형명이 기본형과 동일한 aeneas 생성 버그)"
  },
  "mutation_observation_source": "§4.10 (⊢ False · clause 1 킬 · clause 2 생존)",
  "rust_execution_comparison": "§4.9 (7입력 불일치 0)"
 },
 "stage_b_inputs": {
  "core_files": [
   {
    "path": "inputs/leanproj/lakefile.lean",
    "bytes": 149,
    "sha256": "8a435a42eda30704adec48469951ad86fa7d7f6b5569e9cdd24fe6924a80dcb9"
   },
   {
    "path": "inputs/leanproj/lean-toolchain",
    "bytes": 25,
    "sha256": "ca5f1f601d34c49079e38d7e7041eb0f2a9c227fbc1df0f404820069a052330c"
   },
   {
    "path": "inputs/leanproj/lake-manifest.json",
    "bytes": 3350,
    "sha256": "fd3d5b0ebd1063cceb318f9efc1e7346a7f53a742cb8602d62cb99b57fa44bd7"
   },
   {
    "path": "inputs/leanproj/PrintAxioms.lean",
    "bytes": 126,
    "sha256": "73bb45f72693448aeff6f1b96dbe1c8f18d4bd5252288629b04d1ff616746b50"
   },
   {
    "path": "inputs/leanproj/AsBool.lean",
    "bytes": 121,
    "sha256": "a57ea4165520f3af03e05aed2d97f0b6c768820b8d9bebba0dbd771365d84934"
   },
   {
    "path": "inputs/leanproj/AsBool/Funs.lean",
    "bytes": 1313,
    "sha256": "abaca6f68ab304c935f2d87564c5f19be6e80ba8aac4ddd0a2db724807e1e0e8"
   },
   {
    "path": "inputs/leanproj/AsBool/Spec.lean",
    "bytes": 2680,
    "sha256": "c072867f5db02c7ff7b06a6e7da2045266611ea081b3182a2360f4fe455e7e17"
   },
   {
    "path": "inputs/leanproj/AsBool/Types.lean",
    "bytes": 1729,
    "sha256": "229ec1768d814171269674227bfebc75c96950516ffbf4a7c96cb63002914f60"
   },
   {
    "path": "inputs/leanproj/AsBool/TypesExternal.lean",
    "bytes": 2520,
    "sha256": "646ebd427928385ab89ce1b96dff0fb80cb5ae978eec0856168edfdce8196bf4"
   }
  ],
  "deps_aeneas_lean_tree_digest": "1d5bd051b63b3af0e75810de372e8bdf36ab62354878bc9e8145a7f50175f567",
  "lake_packages_tree_digest": "11509afcd86ac32000ffe4c9d77143175f801a69bafdd2534513d27c4c885f9d",
  "cache_inventory_digest": "bd84699134ce5115d85245871af2f8eb15deccb754774e7f8c4f9a4eae3babff",
  "cache_ltar_file_count": 9031,
  "toolchain_bins": [
   {
    "path": "toolchain/bin/lean",
    "bytes": 9024,
    "sha256": "bf8d54e4714cc4b03d3f6bb34c83b7202b87e49c8bfcbff6895c085bb90ceb38"
   },
   {
    "path": "toolchain/bin/lake",
    "bytes": 13416,
    "sha256": "8ba83c98f76562d03b8dbc33f1057151ba6cbb121679dde76b2260ccc90495e1"
   },
   {
    "path": "toolchain/bin/leantar",
    "bytes": 2692960,
    "sha256": "06d613dffd2a6fd996b095bfd835c2bb720886f9eb7e13ed2adddd7df4507bf3"
   },
   {
    "path": "toolchain/bin/clang",
    "bytes": 119280,
    "sha256": "df2e7d9b9e23822587cf04ac28f206a1ddaac5053312a4c875acf5608701b9d2"
   }
  ],
  "toolchain_lib_lean_so": [
   {
    "sha256": "7831b707e868cee76c353d26649fbd8981b2f4d7e0329af55bbf4fa9e0c69350",
    "path": "/tmp/b2_capsule/toolchain/lib/lean/libInit_shared.so"
   },
   {
    "sha256": "d68867df340056b40726fde3939a9d2021901cc6944f971dd6a6a778bd9ea25b",
    "path": "/tmp/b2_capsule/toolchain/lib/lean/libLake_shared.so"
   },
   {
    "sha256": "efef27df56f2197139afe12f1a2b63913a05f1aba81ce88824c44100431ed8c4",
    "path": "/tmp/b2_capsule/toolchain/lib/lean/libleanshared.so"
   },
   {
    "sha256": "691bf49d9e542a15808fad9d1f8c5df45860166f77efa57961b5335e65a3a0ed",
    "path": "/tmp/b2_capsule/toolchain/lib/lean/libleanshared_1.so"
   },
   {
    "sha256": "141cbfdb3bc2016cd68e0bebc2e5494818213b462ed985afa6d975d4872fb8ec",
    "path": "/tmp/b2_capsule/toolchain/lib/lean/libleanshared_2.so"
   }
  ]
 },
 "identity_only_bound_not_executed": {
  "statement": "이 도구들은 Stage B에서 실행하지 않는다(B-1에서 실행 완료·증Evidence 결속)",
  "rustc": {
   "extraction": {
    "version": "1.100.0-nightly",
    "commit": "923c95cdf"
   },
   "execution": {
    "version": "1.95.0",
    "commit": "59807616e"
   }
  },
  "charon": {
   "version": "0.1.304",
   "git_rev": "7b462d9159db2ed3015162352183906a30bfafc6",
   "sha256": "4226741660099a31be54bde273e9193dd5a44154df7eb203c3c333d83b32a59c"
  },
  "aeneas": {
   "version": "ab34bd2",
   "sha256": "12e6042cfb00aba8ea8b6ef2811f55867e4fc8bf56bcc96c5a7d52ab9fd53a9c"
  },
  "rust_original": "B-1에서만 실행; 캡슐에 미포함"
 },
 "execution_base": {
  "os": "Linux Mint 22.3 (22.3 (Zena)), ID_LIKE=ubuntu debian",
  "arch": "x86_64",
  "kernel": "6.17.0-42-generic",
  "glibc": "2.39-0ubuntu8.9",
  "glibc_ldd_line": "ldd (Ubuntu GLIBC 2.39-0ubuntu8.9) 2.39",
  "libc6_package": "ii libc6:amd64 2.39-0ubuntu8.9 amd64",
  "bwrap_version": "bubblewrap 0.9.0",
  "bwrap_binary_sha256": "e318903862396f96de3df57264e0158682b952fd3fb53ac23d876413e7b30f71",
  "stage_b_sh_sha256": "9197a0f02f829455b62660f9f8894bfa04430a1060b4ee731c0ee52d3fd54e39",
  "ldd_closures_verbatim": {
   "lean": "\tlinux-vdso.so.1 (0x00007ed1e9b6c000)\n\tlibInit_shared.so => /tmp/b2_capsule/toolchain/bin/../lib/lean/libInit_shared.so (0x00007ed1e9b5c000)\n\tlibleanshared_2.so => /tmp/b2_capsule/toolchain/bin/../lib/lean/libleanshared_2.so (0x00007ed1e9b58000)\n\tlibleanshared_1.so => /tmp/b2_capsule/toolchain/bin/../lib/lean/libleanshared_1.so (0x00007ed1e9b54000)\n\tlibleanshared.so => /tmp/b2_capsule/toolchain/bin/../lib/lean/libleanshared.so (0x00007ed1e0000000)\n\tlibc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007ed1dfc00000)\n\tlibpthread.so.0 => /lib/x86_64-linux-gnu/libpthread.so.0 (0x00007ed1e9b36000)\n\tlibdl.so.2 => /lib/x86_64-linux-gnu/libdl.so.2 (0x00007ed1e9b31000)\n\tlibm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x00007ed1dff17000)\n\t/lib64/ld-linux-x86-64.so.2 (0x00007ed1e9b6e000)\n\tlibrt.so.1 => /lib/x86_64-linux-gnu/librt.so.1 (0x00007ed1e9b2c000)",
   "lake": "\tlinux-vdso.so.1 (0x00007d02f9d92000)\n\tlibLake_shared.so => /tmp/b2_capsule/toolchain/bin/../lib/lean/libLake_shared.so (0x00007d02f9200000)\n\tlibInit_shared.so => /tmp/b2_capsule/toolchain/bin/../lib/lean/libInit_shared.so (0x00007d02f9d81000)\n\tlibleanshared_2.so => /tmp/b2_capsule/toolchain/bin/../lib/lean/libleanshared_2.so (0x00007d02f9d7d000)\n\tlibleanshared_1.so => /tmp/b2_capsule/toolchain/bin/../lib/lean/libleanshared_1.so (0x00007d02f9d79000)\n\tlibleanshared.so => /tmp/b2_capsule/toolchain/bin/../lib/lean/libleanshared.so (0x00007d02ef600000)\n\tlibc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007d02ef200000)\n\tlibpthread.so.0 => /lib/x86_64-linux-gnu/libpthread.so.0 (0x00007d02f9d5b000)\n\tlibdl.so.2 => /lib/x86_64-linux-gnu/libdl.so.2 (0x00007d02f9d56000)\n\tlibm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x00007d02f9c6d000)\n\t/lib64/ld-linux-x86-64.so.2 (0x00007d02f9d94000)\n\tlibrt.so.1 => /lib/x86_64-linux-gnu/librt.so.1 (0x00007d02f9c68000)",
   "leantar": "\tstatically linked",
   "clang": "\tlinux-vdso.so.1 (0x000072359c87a000)\n\tlibpthread.so.0 => /lib/x86_64-linux-gnu/libpthread.so.0 (0x000072359c838000)\n\tlibclang-cpp.so.23.1 => /tmp/b2_capsule/toolchain/bin/../lib/libclang-cpp.so.23.1 (0x0000723598600000)\n\tlibLLVM.so.23.1 => /tmp/b2_capsule/toolchain/bin/../lib/libLLVM.so.23.1 (0x0000723593a00000)\n\tlibc++.so.1 => /tmp/b2_capsule/toolchain/bin/../lib/libc++.so.1 (0x000072359c72a000)\n\tlibc++abi.so.1 => /tmp/b2_capsule/toolchain/bin/../lib/libc++abi.so.1 (0x000072359c6e1000)\n\tlibm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x0000723593917000)\n\tlibgcc_s.so.1 => /tmp/b2_capsule/toolchain/bin/../lib/libgcc_s.so.1 (0x0000723593600000)\n\tlibc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x0000723593200000)\n\t/lib64/ld-linux-x86-64.so.2 (0x000072359c87c000)\n\tlibrt.so.1 => /lib/x86_64-linux-gnu/librt.so.1 (0x000072359c6da000)\n\tlibdl.so.2 => /lib/x86_64-linux-gnu/libdl.so.2 (0x000072359c6d5000)\n\tlibz.so.1 => /tmp/b2_capsule/toolchain/bin/../lib/../lib/libz.so.1 (0x0000723592e00000)\n\tlibatomic.so.1 => /tmp/b2_capsule/toolchain/bin/../lib/../lib/libatomic.so.1 (0x0000723592a00000)\n\tlibunwind.so.1 => /tmp/b2_capsule/toolchain/bin/../lib/../lib/libunwind.so.1 (0x000072359c6c3000)"
  },
  "ldd_resolved_file_identities": [
   {
    "sha256": "3a15d66867d83762c7f2f1e37359cb8f6c5743edb369c65285cb0b1c4f7498bf",
    "path": "/lib/x86_64-linux-gnu/libc.so.6"
   },
   {
    "sha256": "c2994527172cc23b7fb0f7d611b71e00a37da27af12c2e5e9e0dc1a742886c96",
    "path": "/lib/x86_64-linux-gnu/libdl.so.2"
   },
   {
    "sha256": "fce00b6f25f459cf4ae0b7fae4257909a1a8a86f9149e7c029a5d617baf1ccd0",
    "path": "/lib/x86_64-linux-gnu/libm.so.6"
   },
   {
    "sha256": "90491a21ce44efcf3bd4b65ec82501c091d7ebe7f8d9b341dd01d721001d9ecd",
    "path": "/lib/x86_64-linux-gnu/libpthread.so.0"
   },
   {
    "sha256": "6d072187d88e092e81561a44c03a4a41397319022c6d43519757cc051c576d82",
    "path": "/lib/x86_64-linux-gnu/librt.so.1"
   },
   {
    "sha256": "c20a2dc8917c755f02b94049356320fe1f62ac7d9f8994731f807d9df39302da",
    "path": "/lib64/ld-linux-x86-64.so.2"
   },
   {
    "sha256": "b2d3f7d9ebf9a0d5dc9caedcb33a43f6ac1b33221ada1f029147d8a66db43c09",
    "path": "/tmp/b2_capsule/toolchain/bin/../lib/../lib/libatomic.so.1"
   },
   {
    "sha256": "da12c79a1651232a6c36a2844e01c612d5e002d759401356c5a8ac597f7e2890",
    "path": "/tmp/b2_capsule/toolchain/bin/../lib/../lib/libunwind.so.1"
   },
   {
    "sha256": "d0aeafffcfe309a107a857dfa1f9afd0db90796d32c2b735a3959eccb317f5b4",
    "path": "/tmp/b2_capsule/toolchain/bin/../lib/../lib/libz.so.1"
   },
   {
    "sha256": "7831b707e868cee76c353d26649fbd8981b2f4d7e0329af55bbf4fa9e0c69350",
    "path": "/tmp/b2_capsule/toolchain/bin/../lib/lean/libInit_shared.so"
   },
   {
    "sha256": "d68867df340056b40726fde3939a9d2021901cc6944f971dd6a6a778bd9ea25b",
    "path": "/tmp/b2_capsule/toolchain/bin/../lib/lean/libLake_shared.so"
   },
   {
    "sha256": "efef27df56f2197139afe12f1a2b63913a05f1aba81ce88824c44100431ed8c4",
    "path": "/tmp/b2_capsule/toolchain/bin/../lib/lean/libleanshared.so"
   },
   {
    "sha256": "691bf49d9e542a15808fad9d1f8c5df45860166f77efa57961b5335e65a3a0ed",
    "path": "/tmp/b2_capsule/toolchain/bin/../lib/lean/libleanshared_1.so"
   },
   {
    "sha256": "141cbfdb3bc2016cd68e0bebc2e5494818213b462ed985afa6d975d4872fb8ec",
    "path": "/tmp/b2_capsule/toolchain/bin/../lib/lean/libleanshared_2.so"
   },
   {
    "sha256": "d156f2240517cf3e363dbe74492491494f74300a2a0513f8606f802dca2f2fbe",
    "path": "/tmp/b2_capsule/toolchain/bin/../lib/libLLVM.so.23.1"
   },
   {
    "sha256": "f074b78d387f3b0db490e3e61289300ee4cf3c4cdb89a7485983e5605cee6c68",
    "path": "/tmp/b2_capsule/toolchain/bin/../lib/libc++.so.1"
   },
   {
    "sha256": "43ae4baf280de152662d88ed938cef229022900e13457683b6a19ae82fafac66",
    "path": "/tmp/b2_capsule/toolchain/bin/../lib/libc++abi.so.1"
   },
   {
    "sha256": "d7adb9dfd7170742a0dce7773e4ffe5903830b11c2af316908058516017fcc92",
    "path": "/tmp/b2_capsule/toolchain/bin/../lib/libclang-cpp.so.23.1"
   },
   {
    "sha256": "3f499bb3b14f33c5c321f52015d385c145c7bd4551a66c5fcff4262c833f2d2a",
    "path": "/tmp/b2_capsule/toolchain/bin/../lib/libgcc_s.so.1"
   }
  ],
  "note": "leantar는 statically linked(공유 라이브러리 closure 없음). toolchain 내부 해석 파일은 캡슐 toolchain의 실제 파일이며 inventory에 포함됨."
 },
 "sandbox_config": {
  "bwrap_args": [
   "--unshare-net",
   "--ro-bind",
   "/usr",
   "/usr",
   "--symlink",
   "usr/lib",
   "/lib",
   "--symlink",
   "usr/lib64",
   "/lib64",
   "--symlink",
   "usr/bin",
   "/bin",
   "--symlink",
   "usr/sbin",
   "/sbin",
   "--proc",
   "/proc",
   "--dev",
   "/dev",
   "--tmpfs",
   "/tmp",
   "--ro-bind",
   "/tmp/b2_capsule/toolchain",
   "/toolchain",
   "--ro-bind",
   "/tmp/b2_capsule/inputs/leanproj",
   "/tmp/b1_gate_a/leanproj",
   "--ro-bind",
   "/tmp/b2_capsule/cache",
   "/cache",
   "--bind",
   "/tmp/b2_run1/workspace",
   "/workspace",
   "--clearenv",
   "--setenv",
   "PATH",
   "/toolchain/bin:/usr/bin:/bin",
   "--setenv",
   "HOME",
   "/tmp/home",
   "--setenv",
   "LANG",
   "C.UTF-8",
   "--setenv",
   "TMPDIR",
   "/tmp",
   "--setenv",
   "LAKE_NO_CACHE",
   "true",
   "--setenv",
   "MATHLIB_CACHE_DIR",
   "/cache",
   "--chdir",
   "/workspace",
   "--die-with-parent",
   "/bin/bash",
   "/workspace/stage_b.sh"
  ],
  "env": {
   "clearenv": true,
   "PATH": "/toolchain/bin:/usr/bin:/bin",
   "HOME": "/tmp/home",
   "LANG": "C.UTF-8",
   "TMPDIR": "/tmp",
   "LAKE_NO_CACHE": "true",
   "MATHLIB_CACHE_DIR": "/cache"
  },
  "design_note": "lakefile.lean의 절대경로 require를 무변경 해석하기 위해 캡슐 leanproj를 /tmp/b1_gate_a/leanproj 경로에 ro-bind — 해시 8a435a42 유지. /tmp는 tmpfs로 비우고 서브패스 ro-bind; --tmpfs /tmp 이후 서브패스 bind가 거부되는 경우의 대안은 --bind /tmp/b2_run1/sbx_tmp /tmp 후 동일 서브패스 bind(실행된 구성만 이 파일에 기록)."
 },
 "expected_verdict": {
  "lake_build_exit": 0,
  "print_axioms_expected_lines": [
   "'AsBool.Spec.as_bool_bool_some' depends on axioms: [propext, Quot.sound]",
   "'AsBool.Spec.as_bool_non_bool_none' depends on axioms: [propext, Quot.sound]"
  ],
  "sorryAx_count": 0,
  "network": "curl_exit=6 예상(DNS 실패) — '외부 네트워크 통신 불가능 상태에서 실행'으로 기록(시도 부재 증명이 아님)"
 },
 "stage_a_stats": {
  "file_count": 180040,
  "total_bytes": 11353320247,
  "per_dir": {
   "inputs": {
    "file_count": 153082,
    "total_bytes": 7759453116
   },
   "toolchain": {
    "file_count": 17925,
    "total_bytes": 3137937793
   },
   "cache": {
    "file_count": 9031,
    "total_bytes": 455355304
   },
   "provenance": {
    "file_count": 2,
    "total_bytes": 574034
   }
  }
 },
 "inventory_manifest_sha256": "742ec2c0f78c3490621d42c67e6f88698f5588422f95b1fcf612a5af9f1d781e",
 "cache_exe": {
  "path": "inputs/leanproj/.lake/packages/mathlib/.lake/build/bin/cache",
  "sha256": "a8b0bf258ad991ba40561bffcbcadc88ad429eef6e4ac2cd8ae99b229590d624",
  "status": "present ([F4] 패키지 영역 존재 — 루트 .lake/build 삭제와 무관; 실행 관측이 정본)"
 }
}
```

### 5.3 run1 관측 원문 (하네스 출력 그대로 — `/tmp/b2_run1/records/run1_full.log`)

```
== [0] sandbox state ==
uid=1000 gid=1000 groups=1000,65534
ls: cannot access '/home': No such file or directory
ls: cannot access '/root': No such file or directory
curl_exit=6
== [1] workspace copy ==
== [2] force fresh root compile ==
== [3] cache unpack ==
Already decompressed 9031 file(s)
== [4] build ==
✔ [1796/1801] Built AsBool.TypesExternal (5.5s)
✔ [1797/1801] Built AsBool.Types (2.2s)
✔ [1798/1801] Built AsBool.Funs (1.8s)
✔ [1799/1801] Built AsBool.Spec (1.7s)
✔ [1800/1801] Built AsBool (1.5s)
Build completed successfully (1801 jobs).
== [5] print axioms ==
'AsBool.Spec.as_bool_bool_some' depends on axioms: [propext, Quot.sound]
'AsBool.Spec.as_bool_non_bool_none' depends on axioms: [propext, Quot.sound]
== [6] artifact digests ==
e5b1ef421f5ebccb6aa35ebeff066db35dd944e97dbfcace61362c8d43340d58  /workspace/leanproj/.lake/build/lib/lean/AsBool.olean
bdf7f0ff6dfc84804d36a640348e9a5af6fe9f1d7e8c8a63b41ce099a6133ad9  /workspace/leanproj/.lake/build/lib/lean/AsBool/Funs.olean
5f604d403600172d402091048aebdba1e646c39a30fbe19ff095dfec6601f816  /workspace/leanproj/.lake/build/lib/lean/AsBool/Spec.olean
d66574f5f531a479d158654351aef301446b61ab7da47684526360a2fd396db8  /workspace/leanproj/.lake/build/lib/lean/AsBool/Types.olean
a41a0bed960f683f4134dddd3edb72da8cd067f369ea66c5d516404ff8bd09b8  /workspace/leanproj/.lake/build/lib/lean/AsBool/TypesExternal.olean
== [7] ro-mount check ==
touch: cannot touch '/toolchain/.write_test': Read-only file system
toolchain_readonly=ok
touch: cannot touch '/cache/.write_test': Read-only file system
cache_readonly=ok
touch: cannot touch '/tmp/b1_gate_a/leanproj/.write_test': Read-only file system
inputs_readonly=ok
```

run1 bwrap exit = 0 (1차 시도는 §7-1 편차 — 하네스 관측 코드 결함, bwrap_exit=6; 재실행은 pristine 캡슐에서 동일 구성).

### 5.4 run2 관측 원문 (하네스 출력 그대로 — `/tmp/b2_run2/records/run2_full.log`, 2026-11-04T17:05:30+09:00 시작 · 17:06:26 종료)

```
run2_start: 2026-11-04T17:05:30+09:00
== [0] sandbox state ==
uid=1000 gid=1000 groups=1000,65534
ls: cannot access '/home': No such file or directory
ls: cannot access '/root': No such file or directory
curl_exit=6
== [1] workspace copy ==
== [2] force fresh root compile ==
== [3] cache unpack ==
Already decompressed 9031 file(s)
== [4] build ==
✔ [1796/1801] Built AsBool.TypesExternal (3.4s)
✔ [1797/1801] Built AsBool.Types (2.0s)
✔ [1798/1801] Built AsBool.Funs (1.9s)
✔ [1799/1801] Built AsBool.Spec (1.9s)
✔ [1800/1801] Built AsBool (1.7s)
Build completed successfully (1801 jobs).
== [5] print axioms ==
'AsBool.Spec.as_bool_bool_some' depends on axioms: [propext, Quot.sound]
'AsBool.Spec.as_bool_non_bool_none' depends on axioms: [propext, Quot.sound]
== [6] artifact digests ==
e5b1ef421f5ebccb6aa35ebeff066db35dd944e97dbfcace61362c8d43340d58  /workspace/leanproj/.lake/build/lib/lean/AsBool.olean
bdf7f0ff6dfc84804d36a640348e9a5af6fe9f1d7e8c8a63b41ce099a6133ad9  /workspace/leanproj/.lake/build/lib/lean/AsBool/Funs.olean
5f604d403600172d402091048aebdba1e646c39a30fbe19ff095dfec6601f816  /workspace/leanproj/.lake/build/lib/lean/AsBool/Spec.olean
d66574f5f531a479d158654351aef301446b61ab7da47684526360a2fd396db8  /workspace/leanproj/.lake/build/lib/lean/AsBool/Types.olean
a41a0bed960f683f4134dddd3edb72da8cd067f369ea66c5d516404ff8bd09b8  /workspace/leanproj/.lake/build/lib/lean/AsBool/TypesExternal.olean
== [7] ro-mount check ==
touch: cannot touch '/toolchain/.write_test': Read-only file system
toolchain_readonly=ok
touch: cannot touch '/cache/.write_test': Read-only file system
cache_readonly=ok
touch: cannot touch '/tmp/b1_gate_a/leanproj/.write_test': Read-only file system
inputs_readonly=ok
bwrap_exit=0
run2_end: 2026-11-04T17:06:26+09:00
```

run2 bwrap exit = 0 (1회 성공 — 재시도 없음).

### 5.5 run1 ↔ run2 비교 (기계 대조)

**판정·axioms·olean digest — 필수 기준 전부 동일**:

| 축 | run1 | run2 | 판정 |
|---|---|---|---|
| bwrap exit | 0 | 0 | **동일** |
| lake build | exit 0, `Build completed successfully (1801 jobs)` | exit 0, `Build completed successfully (1801 jobs)` | **동일** |
| `#print axioms` (커널 판정) | `'AsBool.Spec.as_bool_bool_some' depends on axioms: [propext, Quot.sound]`<br>`'AsBool.Spec.as_bool_non_bool_none' depends on axioms: [propext, Quot.sound]` | 원문 2행 바이트 동일 | **동일** |
| sorryAx 개수 | 0 | 0 | **동일** |
| 타임스탬프 외 정규화 로그 diff | — | — | **동일** (하네스 래퍼 3행 `run2_start`/`bwrap_exit`/`run2_end`만 상이) |

**olean digest 5종 (전부 동일 — 빌드 산출물 identity)**:

| olean | run1 = run2 sha256 |
|---|---|
| `AsBool.olean` | `e5b1ef421f5ebccb6aa35ebeff066db35dd944e97dbfcace61362c8d43340d58` |
| `AsBool/Funs.olean` | `bdf7f0ff6dfc84804d36a640348e9a5af6fe9f1d7e8c8a63b41ce099a6133ad9` |
| `AsBool/Spec.olean` | `5f604d403600172d402091048aebdba1e646c39a30fbe19ff095dfec6601f816` |
| `AsBool/Types.olean` | `d66574f5f531a479d158654351aef301446b61ab7da47684526360a2fd396db8` |
| `AsBool/TypesExternal.olean` | `a41a0bed960f683f4134dddd3edb72da8cd067f369ea66c5d516404ff8bd09b8` |

**관측 보조 축 — 전부 동일**: curl_exit=6(양쪽 — DNS 실패; 네트워크 통신 불가능 상태에서 실행, 시도 부재의 증명은 아님)·`/home`·`/root` 부재·cache unpack `Already decompressed 9031 file(s)`·ro-mount 3종 ok(toolchain·cache·inputs).

**유일한 상이 축 — 타이밍(예고된 변동 클래스)**: 모듈 컴파일 wall — run1 TypesExternal 5.5s·Types 2.2s·Funs 1.8s·Spec 1.7s·AsBool 1.5s vs run2 3.4s·2.0s·1.9s·1.9s·1.7s. wall은 판정·identity 축이 아니다.

### 5.6 캡슐 불변성 검증 (사전 → 실행 → 사후)

- **사전 검증(run2 직전)** — 실측값이 generation.json 기록값과 전부 일치:
  - self digest: `generation.json` `efdced76…b5133` ✓ · `inventory.json` `742ec2c0…d781e` ✓
  - 코어 9파일(`inputs/leanproj/` — lakefile.lean `8a435a42…`·lean-toolchain `ca5f1f60…`·lake-manifest.json `fd3d5b0e…`·PrintAxioms.lean `73bb45f7…`·AsBool.lean `a57ea416…`·AsBool/Funs.lean `abaca6f6…`·AsBool/Spec.lean `c072867f…`·AsBool/Types.lean `229ec176…`·AsBool/TypesExternal.lean `646ebd42…`) ✓
  - toolchain bin 4종(lean `bf8d54e4…`·lake `8ba83c98…`·leantar `06d613df…`·clang `df2e7d9b…`) ✓ · toolchain lib 5종(libInit_shared `7831b707…`·libLake_shared `d68867df…`·libleanshared `efef27df…`·libleanshared_1 `691bf49d…`·libleanshared_2 `141cbfdb…`) ✓
  - `cache/` `.ltar` 파일 개수 **9,031** = `cache_ltar_file_count` ✓ · F4 cache exe `a8b0bf25…` ✓
- **사후 재검(run2 직후)**: 사전과 동일 항목 전부 재실측 일치 + **inventory 전수 재해시** — 180,040항목 전수 sha256 대조 `matched=180,040 · mismatched=0 · missing=0 → INVARIANT_PASS` (기계 판정 기록: `/tmp/b2_run2/records/inventory_full_rehash.json`). run2 실행이 캡슐에 어떤 파일 변경도 발생시키지 않았다.

### 5.7 F1~F4 identity 보완

- **F1 — 번역 산출물 Funs.lean identity**: aeneas 생성 원본 sha256 `e0fec2a836a12ffd6588f501218522ceb2895f8d16b866f9b727d9e841951b32`(1,306B) / 프로젝트 1토큰 수정본 sha256 `abaca6f68ab304c935f2d87564c5f19be6e80ba8aac4ddd0a2db724807e1e0e8`(1,313B). diff는 `Option Bool` → `Option _root_.Bool` 1곳뿐 — 근거 B-1 §5.4-3(enum 변형명이 기본형과 동일한 aeneas 생성 버그; 생성 원본 무수정 보존). 전체 해시·diff 원문은 B-1 증Evidence(MERGE `c3a4164324c479b34c5caefd94b08fe5ad263014`) §5.3·§5.4-3에서 인용 — 본 세션은 수정을 수행하지 않았다(캡슐 inputs에 수정본이 봉입됨).
- **F2 — 실행 게이트 identity**: bwrap 바이너리 sha256 `e318903862396f96de3df57264e0158682b952fd3fb53ac23d876413e7b30f71`(bubblewrap 0.9.0 — generation.json `execution_base.bwrap_binary_sha256`와 실측 일치), stage_b.sh sha256 `9197a0f02f829455b62660f9f8894bfa04430a1060b4ee731c0ee52d3fd54e39`(run1 최종본 — generation.json `execution_base.stage_b_sh_sha256`와 실측 일치; run2 workspace 배치 사본도 동일 digest 실측 — 3자 일치).
- **F3 — 동적 라이브러리 파일 identity**: ldd closure의 해석 **파일 sha256 전수**가 generation.json `execution_base.ldd_resolved_file_identities`(20종 — libc `3a15d668…`·libLLVM `d156f224…`·캡슐 toolchain 내부 해석파일 포함)에 기록되어 있다(경로가 아니라 실제 파일 identity). 원문 ldd 출력은 `ldd_lean.txt`·`ldd_lake.txt`·`ldd_leantar.txt`·`ldd_clang.txt`(leantar는 statically linked)·`toolchain_lib_lean_so.sha256`(run1 records) 참조. 본 세션은 toolchain lib 5종을 run2 사전·사후 검증에서 재실측해 일치를 확인했다(§5.6).
- **F4 — mathlib 캐시 실행 파일**: `inputs/leanproj/.lake/packages/mathlib/.lake/build/bin/cache` sha256 `a8b0bf258ad991ba40561bffcbcadc88ad429eef6e4ac2cd8ae99b229590d624` — run2 사전·사후 재실측 일치(§5.6). 루트 `.lake/build`는 stage_b.sh [2]에서 삭제되지만 패키지 영역은 봉입 상태로 존재하며, 컴파일에 소비된 것은 unpack된 캡슐 cache 9,031 `.ltar`다.

## 6. Non-claims

- 본 문서는 **제품 판정이 아니다** — v1 CLI·레인·게이트·인증서의 어떤 동작도 주장하지 않는다.
- **일반 Aeneas 채택이 아니다** — 단일 함수 `as_bool`의 고정 세대 재현 관측일 뿐이며, Stage 3 채택 adjudication은 본 문서 범위 밖이다.
- **Rust 전체 지원 확대가 아니다** — CRASH 14행 등 나머지 census 분포는 B-1 Gate B(MERGE `356dbb6b935f02623d7c97a33f5c812912082e8c`) 정본 그대로이며 본 세션에서 재측정하지 않았다.
- **타 머신 재현이 아니다** — 본 재현은 동일 호스트(Linux Mint 22.3·x86_64·kernel 6.17.0-42-generic·glibc 2.39)·동일 bwrap 0.9.0에서의 독립 실행 재현이다. 머신 간 이식성은 주장하지 않는다.
- **캡슐 축소를 수행하지 않았다** — import closure 기반 최소화는 Out of Scope였다(180,040파일 전체가 세대 단위).
- rustc·charon·aeneas의 어떤 재실행도 수행하지 않았다 — 이들 도구 세대는 봉입 identity(generation.json `identity_only_bound_not_executed`)로만 결속된다. 본 세션의 실행은 캡슐 툴체인의 lean·lake와 bwrap뿐이다.
- curl_exit=6은 "네트워크 단절 상태에서의 실패 관측"이며 DNS·방화벽 경로의 부재 증명은 아니다(expected_verdict 원문 그대로).

## 7. Deviations (전수)

1. **run1 하네스 stage_b.sh 관측 코드 수정 1건 (S2-A 시점, 규율대로 처리)** — 1차 시도가 `bwrap_exit=6`로 실패: stage_b.sh는 `set -euo pipefail` 하에서 `curl -s -m 10 …; echo "curl_exit=$?"` 형태였고 `--unshare-net`에서 curl이 DNS 실패(exit 6)로 죽자 set -e가 스크립트를 즉시 종료해 관측 라인 자체가 미출력됨. 수정은 **하네스 stage_b.sh의 관측 코드만** — `curl_exit=0` 초기화 + `curl … || curl_exit=$?` 형태로 의도(네트워크 단절 관측을 curl_exit 라인으로 기록)를 보존하는 최소 변경. 캡슐·마운트 구성은 무변경, generation.json 갱신(stage_b_sh_sha256 `9197a0f0…` 반영) 후 **pristine 캡슐에서 run1 재실행**. 1차 실패 로그는 `/tmp/b2_run1/logs/run1_attempt1_failed.log`로 보존되며 정식 run1_full.log는 재실행 출력이다(§5.3 — 현재 원문은 재실행분).
2. **run2의 workspace 바인드 소스 경로 치환 1건 (유일한 run2 구성 편차 — 독립 실행에 필연)** — bwrap_args 중 `--bind /tmp/b2_run1/workspace /workspace`를 `--bind /tmp/b2_run2/workspace /workspace`로 치환. 나머지 인자·순서·env는 generation.json sandbox_config 무변경(명령은 generation.json을 직접 읽어 생성 — `/tmp/b2_run2/bwrap_cmd_generated.sh` 보존). 캡슐 마운트 3종(ro-bind toolchain·inputs 서브패스·cache)은 무변경.
3. **run2 실행 중 발생 편차: 없음** — bwrap exit 0, 1회 성공, 재시도·수정·중단 없음.

## 8. Repro Block

```bash
# 0) 세대 정본 확인 (pristine 캡슐 — 읽기 전용)
sha256sum /tmp/b2_capsule/generation.json   # efdced76b105cc4843aad99cbe2f4eedab039439742870c34d85107e5d1b5133
sha256sum /tmp/b2_capsule/inventory.json    # 742ec2c0f78c3490621d42c67e6f88698f5588422f95b1fcf612a5af9f1d781e
find /tmp/b2_capsule/cache -name '*.ltar' -type f | wc -l   # 9031

# 1) run2 workspace 준비 (stage_b.sh는 정본 digest와 동일한 새 파일)
mkdir -p /tmp/b2_run2/workspace /tmp/b2_run2/records /tmp/b2_run2/logs
# stage_b.sh 배치 — digest 검증:
sha256sum /tmp/b2_run2/workspace/stage_b.sh
# 9197a0f02f829455b62660f9f8894bfa04430a1060b4ee731c0ee52d3fd54e39
#   = generation.json execution_base.stage_b_sh_sha256

# 2) bwrap 명령은 generation.json에서 생성 (workspace 소스 치환만 — §7-2)
python3 - <<'EOF'
import json
g = json.load(open('/tmp/b2_capsule/generation.json'))
args = g['sandbox_config']['bwrap_args']
i = args.index('/tmp/b2_run1/workspace')
assert args[i-1] == '--bind' and args[i+1] == '/workspace'
args = args[:i] + ['/tmp/b2_run2/workspace'] + args[i+1:]
print('exec bwrap \\\n  ' + ' \\\n  '.join(f"'{a}'" for a in args))
EOF

# 3) Stage B 실행 (네트워크 단절·캡슐 ro — 격리 실행 내부로만 쓰기)
/tmp/b2_run2/bwrap_cmd_generated.sh          # → run2_full.log 기록, bwrap_exit=0
# 기대: curl_exit=6 · Already decompressed 9031 file(s)
#       Build completed successfully (1801 jobs).
#       'AsBool.Spec.as_bool_bool_some' depends on axioms: [propext, Quot.sound]
#       'AsBool.Spec.as_bool_non_bool_none' depends on axioms: [propext, Quot.sound]
#       olean digest 5종 = §5.5 표 값과 동일
#       toolchain_readonly=ok · cache_readonly=ok · inputs_readonly=ok

# 4) run1↔run2 비교 (판정·axioms·olean digest — 필수 기준)
# run1: /tmp/b2_run1/records/  ·  run2: /tmp/b2_run2/records/
# 타임스탬프·wall 제외 정규화 diff = 하네스 래퍼 3행만 상이

# 5) 캡슐 불변성 재검 (사전·사후)
# 코어 9파일+toolchain 4+5종 sha256 대조 + inventory 전수 재해시:
# 180,040항목 matched=180040 mismatched=0 missing=0 → INVARIANT_PASS
```

실행 기반: Linux Mint 22.3 (noble base) · x86_64 · kernel 6.17.0-42-generic · glibc 2.39-0ubuntu8.9 · bwrap 0.9.0 (`e3189038…30f71`).
