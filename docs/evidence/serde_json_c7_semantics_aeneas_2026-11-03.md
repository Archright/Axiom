# serde_json C7 의미 범위 실측 + Aeneas 적용성 평가 — 증거 기록 (2026-11-03)

> **Status**: Observation evidence record — 읽기 전용 조사 (`src/` 무수정, 제품 코드 무변경, main worktree 무수정; 모든 시험은 `/tmp`와 전용 worktree에서 수행)
> **Created**: 2026-11-03
> **Written at**: branch `work/b0-c7-aeneas-2026-11-03` (worktree `/tmp/b0_c7_aeneas_wt`), branch base = main `95623dbf7391f570a75c22cc0b39152ae554287e`
> **Governing docs**: [docs/evidence/serde_json_claim_adjudication_2026-10-31.md](serde_json_claim_adjudication_2026-10-31.md) (§0–§9 선행 정독 완료) · [experiments/serde-json-claim-2026-10-31/FREEZE.md](../../experiments/serde-json-claim-2026-10-31/FREEZE.md) (§3 서브젝트 핀, §4 잠금 프로토콜, §7 동결 명령)
> **원칙**: 기계 출력과 오류 문자열은 원문 그대로 인용한다(재작성·요약·번역 없음). 이 문서는 관찰을 기록하며 판정 대상 프로젝트(serde_json)에 대한 어떤 참·거짓 주장도 하지 않는다.

7-field identity (FREEZE.md §1 형식 준용 — 값은 본 문서 정체성):

- PROJECT_UNDER_TEST: serde_json (Rust crate) v1.0.154 — 모순후보 **C7** (`serde_json::error::parse_line_col`, error.rs:494)의 **LLBC 실측 의미 범위 열거 + Aeneas(Lean 백엔드) 적용성 평가**
- REVISION: `8c535a260ce561eaab4111aafc29038eb9f77ff3` (subject HEAD — 2026-11-03 `/tmp/b0_c7_work/json_clone` 신규 클론으로 재확인, clean)
- AXIOM_REVISION: `95623dbf7391f570a75c22cc0b39152ae554287e` (main; branch base = worktree 생성 시점 main). 캠페인 본체는 이미 PR #1149(merge commit `ee87f0a70a8a518e490c74499b5e134ef112ea08`)로 랜딩되어 main에 존재 — 본 문서는 그 후속 조사다
- CONFIG: 읽기 전용 관찰 + `/tmp` 측 시험만; Axiom4 저장소 본체에는 커밋 없음(본 문서 1건뿐). charon 실행은 `CARGO_NET_OFFLINE=true`로 오프라인 수행(네트워크 fetch 0건 관측 — 아래 §4.3)
- TOOLCHAIN_ID: charon **0.1.281** (`798016509139eb51f0d764645f76d068d34ba5f6`) — 설치본 `<user-home>/.cargo/bin/charon` (sha256 `dfa2ee6ca63f150f825c6853edb828a8730817e632444e9f02fb0bb07b7d6057`) 및 Aeneas 번들본 `aeneas_1013/charon` (sha256 `cccbb77cd02c34677fd30f152938b15d8f35574292d25086b7ea8cf359774a72`) — 양쪽 모두 `charon version` → `0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)`, exit 0; rustc 1.95.0 (59807616e 2026-04-14); cargo 1.95.0 (f2d3ce0bd 2026-03-21); charon toolchain `nightly-2026-09-17`; Lean 4.33.0 (d8b18978322de05a8f3dba51ef03cf5461676c17, elan 경유) — **미사용**(아래 §5.4)
- SCOPE: C7의 LLBC 의존성 전수 열거(문법 재고의 "등장" vs "증명 필요" 구분) + Aeneas 적용성 시험(동일성 기록 포함, 4회 시험 전부 원문 기록) + Go/No-Go 표. **범위 밖**: Aeneas에 의한 실제 번역 산출물·Lean 모델 빌드·C1~C8 참/거짓 판정·v1 엔진 기능 확장 — 어느 것도 도달하지 못했다(§7)
- EXPERIMENT_ID: serde-json-c7-aeneas-2026-11-03

---

## 1. Question

이 문서가 답하는 질문:

1. C7 `parse_line_col`의 증명 의무에 **실제로 필요한** 의미 구성요소는 무엇인가 — 그중 어느 것이 LLBC에 본체로 존재하고, 어느 것이 LLBC 밖(본체 없는 외부 함수)인가? ("LLBC에 등장" ≠ "증명에 필요"의 구분)
2. Aeneas(Charon LLBC → Lean 파이프라인)는 이 캠페인의 산출물을 입력으로 소비할 수 있는가 — charon 핀(`0.1.281`)과 정확히 호환되는 Aeneas 바이너리가 존재하는가, 존재하면 동일 LLBC를 실제로 번역하는가?
3. 이 관측은 B-0 슬라이스(추출 계층 직후의 다리)에 대해 무엇을 확정했고, 무엇을 확정하지 못했는가?

## 2. Context

- 캠페인 계보: [adjudication 2026-10-31] — serde_json v1.0.154의 C1~C8 기계 판정 캠페인이 SCOPE_LIMIT_CONFIRMED로 종착했다. C7은 probe(run 3)의 층 1(주소가능성) 거부 후 §9 Amendment 1로 재선출된 타깃이며, d1/d2는 **producer의 LLBC files-table 사전검증**(층 2)에서 `unknown`으로 거부됐고, 서명 게이트(층 3)에는 도달하지 못했다. 층 3의 예측 — C7 서명(inputs=[Ref(Var,Ty,Mut)], output=Adt)은 v1 인증 문법 밖 — 은 **예측으로만 존재**했고 LLBC 실측 문서화는 §8에 기록되어 있다.
- 본 실험의 위치: 층 2가 막은 것을 우회하지 않고, **LLBC 산출물 자체**를 제3의 소비자(Aeneas)에 넣어보는 advisory 관찰. Aeneas는 추출 단계를 Charon과 공유하므로 **독립 검증이 아니라** 독립 번역 계층의 적용성 측정이다(§8 정직 범위).
- C7 앵커(불변, 캠페인에서 확정): `fn parse_line_col(msg: &mut String) -> Option<(usize, usize)>` (error.rs:494), signatureHash `48c4dc5b55757f7c444e8a6d0bf5fdaadd10f48791a6dea9df39484db7367851` (규약: brace·들여쓰기·개행 없음).

## 3. Scope

- **범위 안**: (a) 캠페인 LLBC 4종(probe/d1/d2/d3)의 디스크 존재·해시 실측, (b) C7 fun_decl의 LLBC 정체성·시그니처·지역변수·문장 종류·rvalue·연산자·callee 전수 실측, (c) Aeneas 바이너리 조달(charon-pin 정확 일치 검색 포함)·동일성 실측, (d) 동일 LLBC 입력 4회 시험과 원문 출력, (e) 크래시 루트 컴파운드의 LLBC 측 위치 확정, (f) 구성요소별 Go/No-Go 표.
- **범위 밖**: Aeneas 번역 산출물(Lean 파일) 생성·빌드 — 4회 시험 모두 임포트/버전 검증 단계에서 거부·크래시하여 단 한 개의 함수도 번역되지 않았다; aeneas 소스 빌드(OCaml 툴체인 부재 — opam/dune/ocaml 모두 PATH에 없음을 실측); charon 0.1.304 재추출(입력 동일성 요건을 깨는 대체 경로 — §10 후속).
- 편차 없음: 캠페인 FREEZE의 잠금 프로토콜을 재사용해 그대로 집행했다(§4.3).

## 4. Procedure

### 4.1 입력 LLBC 확보 (FREEZE — 디스크 존재 확인)

캠페인 산출물은 모두 main에 랜딩되어 있어(PR #1149), `state_*/.axiom/rust-lane/1398235db249fc8b/subject.llbc`가 디스크에 존재했다. **재추출 불요** — state_d1 산출물을 입력으로 확정했다. 관측:

- 캠페인 정준 run-1 LLBC(FREEZE §4: sha256 `f6eff161420fe8fefc4b2e7c5986c8fad5f3b3050cb12dc33b2881d59566f569`, 27,695,318 B)의 재생성원 `/tmp/axexp/subject.llbc`는 **존재하지 않았다**(`/tmp/axexp` 부재 실측). run-1 산출물 자체는 미보존(LFS 정책)이므로, 본 실험의 입력은 **캠페인 잔존 산출물 state_d1**이다.
- 정준값과의 상이는 예고된 클래스다: adjudication §8 — files[1]이 state 소유 charon-target 절대경로를 내장하며 빌드해시가 런마다 다르다(d1 `211aa9d180883da9` / d2 `8b65d3d27583c0f0` / d3 `4bceeb2bfd3e9415`). 4종 state LLBC가 서로 다른 해시인 것은 이 원인과 일치한다(§5.1 표). fun_decl 내용의 등가성은 캠페인 d1=d2 매니페스트 사전 동일성(`b49abcb6…`)과 files[2]+ 상대경로 일치 관측으로 뒷받침되며, 본 문서는 state_d1을 **입력으로 기록**하고 그 해시를 고정한다.

### 4.2 Aeneas 조달 (charon-pin 정확 일치 검색)

- `git ls-remote https://github.com/AeneasVerif/aeneas` — 태그 계열은 `nightly-<날짜>-<커밋7>`, main HEAD `ab34bd28458a08c150b7cbf1873e59af74588138` (2026-11-03 기준).
- aeneas 저장소는 **OCaml 프로젝트**(`src/*.ml`, `charon-pin` 파일)로 전환되어 있고, 로컬에 OCaml 툴체인이 없다(`which ocaml dune opam ocamlfind` → 전부 부재 실측). 소스 빌드 대신 **릴리스 사전빌드 번들**(aeneas + 번들 charon/charon-driver + `backends/` + Lean 빌드 산출물)을 사용했다.
- charon-pin 정확 일치 검색: blob-none 부분 클론 후 `charon-pin` 파일의 전 커밋 히스토리를 훑어 `798016509139eb51f0d764645f76d068d34ba5f6`를 pin하는 커밋을 검색 → **정확히 1개 구간** 존재:
  - pin 변경 커밋 `155a41f1d2846179c2a0b234436bde4a33d5ab74` (2026-10-08 12:08 +0200, "Inline promoted constants in the pure micro-passes rather than in LLBC (#1404)")에서 pin이 `7980165…`로 설정됨
  - `pin@155a41f1 = 7980165…`, `pin@d119a47 = 7980165…`, `pin@73b7cf9 = 7980165…` (git show 실측)
  - 이후 `pin@bbc0151 = b05c4774638599608f26b777b6bc49120446365a` (2026-10-14), `pin@cd41995 = 26abff028ced534ebf8e861f2d3dd1743e2aa318` (2026-10-15) — 불일치
  - → 정확 일치 구간 = 155a41f1(10-08) ~ 73b7cf9(10-12). 릴리스 보유 구간: `nightly-2026.10.09-d119a47` … `nightly-2026.10.13-73b7cf9`. **최선 선택 = `nightly-2026.10.13-73b7cf9`** (정확 일치 구간의 마지막 릴리스).
- **"정확히 일치하는 태그가 없으면 가장 근접한 것" 조건은 발동하지 않았다** — 정확 일치 릴리스가 존재해 그것을 사용했다. (근접 대조군으로 최신 `nightly-2026.11.03-ab34bd2`도 §5.4 시험 4에 기록.)
- 조달 경로 기록: 시험 중 GitHub API core 쿼터가 **0/5000**에 도달하는 관측(`gh api rate_limit`; 곧 reset되어 4753/5000으로 회복 — 로컬 시간대 기준 시간당 창). 릴리스 자산은 **자격 증명을 일절 사용하지 않는 퍼블릭 URL 직접 다운로드**(curl, 인증 헤더 없음)로 확보했다 — §2.4(자격 증명은 네이티브로만) 위반 없음, `gh_env.txt` 미접촉.

### 4.3 동일 LLBC 입력 + preset 재추출 (잠금 프로토콜 준수)

- 시험 1은 **캠페인 입력 그대로**(state_d1 LLBC, 해시 고정)를 소비했다. aeneas는 `--preset=aeneas` 옵션 메타데이터를 요구하므로(§5.4 시험 1 원문), 번역 관측을 위해 핀 Charon으로 **preset 재추출**을 수행했다 — 이는 FREEZE §7이 규정한 charon 재생성 경로와 동일 형태이며, 서브젝트 원본을 보호하기 위해 **서브젝트 저장소를 `/tmp/b0_c7_work/json_clone`으로 신규 클론**한 뒤 그 안에서만 실행했다(원본 클론 무수정).
- 잠금 프로토콜(FREEZE §4 준용, 재추출 run):
  1. `cp inputs/Cargo.lock <clone>/Cargo.lock` → sha256 `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` (캠페인 핀값과 일치 — FREEZE §4 측정값 재확인)
  2. 사전 find-매니페스트: `find . -path './.git' -prune -o -type f -print | sort | xargs sha256sum` → 매니페스트 sha256 `775211468c43222389d05908e15fc11c2c89c9d4545911f1eb32f529ede5c7e0`
  3. `CARGO_NET_OFFLINE=true <aeneas_1013>/charon cargo --preset=aeneas --dest-file /tmp/b0_c7_work/aeneas_preset.llbc -- --target-dir /tmp/b0_c7_work/charon-target` → **exit 0, wall 4.335 s**, cargo 네트워크 fetch 0건(오프라인 캐시 사용 — `Compiling zmij v1.0.23 / serde_core v1.0.229 / serde_json v1.0.154 (/tmp/b0_c7_work/json_clone) / itoa v1.0.18 / memchr v2.8.3 / Finished dev profile`)
  4. 사후 Cargo.lock sha256 — **in==out** (`1bc62b1a…b2e4`)
  5. 사후 find-매니페스트 — **사전과 diff empty** (사전==사후)
  6. `rm Cargo.lock` (부재 재확인)
- 최소 서브그래프 진단(시험 3 용): 동일 프로토콜로 `--preset=aeneas --start-from 'serde_json::error::parse_line_col'` 실행 → exit 0, wall 2.742 s, Cargo.lock in==out 동일값 확인(매니페스트 사전/사후 대조는 이 run에서는 재실행하지 않았다 — 기록).

### 4.4 Aeneas 시험 명령 (동일 LLBC, 해시 고정)

```
cd /tmp/b0_c7_work/aeneas_1013
./aeneas -backend lean -dest <out-dir> -print-unknown-externals <input.llbc>
```

`-print-unknown-externals`는 aeneas `--help`에 "Print all the external definitions which are not listed in the builtin functions"로 문서화된 옵션으로, 미구현 외부 목록 관측을 위해 모든 시험에 부여했다.

## 5. Result

### 5.1 LLBC 해시 인벤토리 (입력 동일성의 기록)

| 산출물 | sha256 | bytes |
|---|---|---|
| 캠페인 run-1 정준 (FREEZE §4, `f6eff161…`) — **디스크 부재, 미보존** | `f6eff161420fe8fefc4b2e7c5986c8fad5f3b3050cb12dc33b2881d59566f569` | 27,695,318 |
| state_probe `subject.llbc` | `5df292162354078767dcb454c5d4ac530ef8ac1df66ac9936125056c39c5be7b` | 27,695,560 |
| **state_d1 `subject.llbc` — 본 실험 입력 (input of record)** | `17113512a770a39e0614254f4bbd09211a955f9dde1b00bd8354552985ce5784` | 27,695,554 |
| state_d2 `subject.llbc` | `f651bc80460ea6d495bfe5dd57cbc6a3ad4eaf35ee88a99ca9574cafd02abc62` | 27,695,554 |
| state_d3 `subject.llbc` | `d4385ccc3935f275a94a7d1dae0f9abb84e6f7fbb9a6e89448c80704f833fc6d` | 27,695,554 |
| aeneas_preset.llbc (charon 0.1.281 `--preset=aeneas` 재추출) | `8d2951da76dd8fef08e5935d2779e77ee85c436b42fa82666b5d13f725039d19` | 29,914,620 |
| c7_min.llbc (`--preset=aeneas --start-from serde_json::error::parse_line_col`) | `756810f5f3e09c5b385392668f8410b5cfe234ffa3a22452f5e14b0871e4f2a8` | 367,587 |

정직 기록: 4종 state LLBC는 서로도, run-1 정준과도 바이트 다르다 — files[1] 절대경로(state 경로 + 런별 빌드해시) 삽입이라는 이미 문서화된 원인 클래스(adjudication §8)와 일치한다. 본 실험은 이 상이를 마스킹하지 않고 입력으로 채택한 산출물의 해시를 고정했다.

### 5.2 C7의 LLBC 정체성 (fun_decls[5], def_id 5)

- 위치: `translated.files[3]` = `{"id": 3, "name": {"Local": "src/error.rs"}, "crate_name": "serde_json", …}`; `translated.fun_decls[5]`; span `file_id 3, line 494:0 – 534:1` — error.rs:494와 일치. `item_meta.source_text` 원문 선두: `fn parse_line_col(msg: &mut String) -> Option<(usize, usize)> {`.
- 시그니처(원문 JSON):
  - inputs: `[{"Value": [220, {"Ref": [{"Var": {"Bound": [0, 0]}}, {"Deduplicated": 26}, "Mut"]}]}]` — 단일 Value 입력, `Ref` 타입, **Mut**; `generics.regions = [{"index": 0, …}]`, `generics.types = []` (리전 변수 1개가 서명에 존재)
  - output: `{"Deduplicated": 217}` — 반환 지역(index 0, 무명)의 타입과 동일; Adt 테이블에서 `57 = core::option::Option` (locals 내 `Adt {"id": 57, generics: {types: [Deduplicated 51]}}` — 즉 `Option<usize>` 계열 인스턴스가 본문에 존재)와 조합되어 `Option<(usize, usize)>`에 대응
  - → **adjudication §8 층 3 예측(inputs=[Ref(Var,Ty,Mut)], output=Adt)의 LLBC-근거 사후 확정**: 층 2(files-table)가 먼저 막았기 때문에 도달하지 못했던 서명 게이트는, 도달했다면 이 서명에서 거부했을 것이다.
- 지역변수: `arg_count 1`, locals 77개(index 0–76). named locals: `msg`, `start_of_suffix`, `index`, `start_of_line`, `end_of_line`, `start_of_column`, `end_of_column`, `line`(×2 슬롯), `column`(×2 슬롯) — 원본 소스의 변수 전체가 관측됨. 반환 지역(index 0) 타입 = `Deduplicated 217`.
- 타입 id → 이름 해석은 Adt id에서 확정되었다: `57 = core::option::Option`, `54 = core::result::Result`, `105 = core::ops::range::RangeFrom`, `106 = core::num::error::ParseIntError`, `107 = core::ops::range::Range`. 스칼라/alloc 타입(str, String, usize, bool)은 `Deduplicated` id로 표기되며(예: &str 참조 temp들 = `Ref(…, 29, Shared)`, 시그니처 pointee = `Deduplicated 26`, `msg` 지역 = `Deduplicated 218`) 동일 Rust 타입이 복수 dedup 슬롯에 나타날 수 있어 슬롯별 1:1 고정은 하지 않았다(관찰 수준 기록). `Adt id 58`의 이름은 Builtin 클래스 경로 요소다.

### 5.3 구성요소 전수 실측 — "등장"과 "증명 필요"의 구분

본문(body.Structured) 전수 순회 히스토그램(총 293 statements):

| statement kind | 개수 |
|---|---|
| StorageDead | 97 |
| StorageLive | 76 |
| Assign | 67 |
| Call | 16 |
| Borrowck | 10 |
| Switch | 7 |
| Assert | 4 |
| Loop | 2 |
| Continue | 2 |
| Break | 2 |

- Place: `Local` 108, `Projection` 20 (필드/인덱스 투영 — `&mut String` 플레이스 접근 포함).
- Rvalue: `Use` 27, `Ref` 20, `Aggregate(Adt)` 12 (Some/None/Ok/Err/튜플 구성), `Discriminant` 3, `BinaryOp` 5 — 세부: **`BinaryOp:AddChecked` ×4** (두 루프의 `end_of_line += 1` / `end_of_column += 1` 및 산술 — 오버플로 체크 산술), `BinaryOp:Lt` ×1 (`end_of_column < msg.len()`).
- Operand: `Move` 22, `Const` 2 — Const 2건은 문자열 리터럴 `" at line "`(LLBC 상수 id 339)과 `" column "`(id 342).
- Switch 7건의 스크루티니(관측 그대로): ty 197 지역 ×3 (2 explicit branches + fallback — enum discriminant), ty 83(bool) 지역 ×3, ty 83 리터럴 분기 ×1 (`[{"Bool": false}, …]`).
- **Assert 4건 = 패닉 경로의 실체**(인덱스 경계·오버플로 등의 실행 검사) — straight-line 문법 밖.

직접 callee 16 call sites → 9 distinct (FunId → 이름, body 종류 — LLBC JSON 경로 증거 포함):

| FunId | 이름 | body | call sites |
|---|---|---|---|
| 6 | `serde_json::error::starts_with_digit` | **Structured** (인크레이트, 본체 존재) | 2 |
| 295 | `alloc::string::<impl>::deref` | Opaque (본체 없음) | 1 |
| 296 | `core::str::<impl>::rfind` | Opaque (본체 없음) | 1 |
| 297 | `core::str::<impl>::len` | Opaque (본체 없음) | 2 |
| 298 | `alloc::string::<impl>::index` | Opaque (본체 없음) | 4 |
| 299 | `core::str::<impl>::starts_with` | Opaque (본체 없음) | 2 |
| 300 | `alloc::string::<impl>::len` | Opaque (본체 없음) | 1 |
| 301 | `core::num::<impl>::from_str` | Opaque (본체 없음) | 2 |
| 302 | `alloc::string::<impl>::truncate` | Opaque (본체 없음) | 1 |

- 구조적 사실: **직접 callee 9개 중 8개는 std/alloc/core 함수로 본체가 LLBC에 없다.** rfind의 패턴 탐색, from_str의 숫자 누적, truncate/index의 경계·panics — 이 의미들은 C7의 증명 의무에 **필요**하지만 산출물에 존재하지 **않는다**. 어떤 검증자(Aeneas 포함)도 LLBC 단독으로는 이들을 검증할 수 없고 외부 공리/stub이 필요하다.
- 유일한 인크레이트 callee `starts_with_digit`(def_id 6, Structured): 본문 36 statements — StorageLive 10, Assign 10, Call 2, StorageDead 11, Switch 2, Borrowck 1; 직접 callee 2건: `core::str::<impl>::as_bytes`(303, Opaque), `core::slice::<impl>::first`(304, Opaque).
- 최소 서브그래프 실측(c7_min.llbc): files 21, fun_decls 66(null 19) — C7 + 전이 의존성 규모의 기록.

### 5.4 Aeneas 시험 — 4회, 전부 원문 (함수 번역 0건 도달)

Aeneas 정체성(사용 바이너리): release **`nightly-2026.10.13-73b7cf9`**, aeneas 커밋 **`73b7cf9f7442c5aba550c224bd7fd212d39ba32f`** (2026-10-12 "Update Lean to v4.35.0-rc4 (#1417)"), `-version` 출력 원문 `aeneas nightly-2026.10.13-73b7cf9`. 번들 `charon version` → `0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)` exit 0 — **캠페인 핀·입력 LLBC 내장 `charon_version: 0.1.281`과 정확 일치**. (대조: 최신 main `ab34bd28458a08c150b7cbf1873e59af74588138`의 charon-pin = `7b462d9159db2ed3015162352183906a30bfafc6` = charon 0.1.304.)

**시험 1 — 동일 캠페인 LLBC(input of record, `17113512…`) + 정확-핀 aeneas**: exit **1**, 1.3 s. 출력 원문(전부 2행):

```
[Info ] Imported: /tmp/b0_c7_work/input_d1.llbc
[Error] Invalid option detected: the serialized crate was generated by Charon without the `--preset=aeneas` option. Please regenerate the crate by calling Charon with `--preset=aeneas`.
```

→ **Axiom lane의 charon 호출형(`charon cargo --dest-file …`)은 aeneas 소비 계약을 만족하지 않는다** — fail-closed 거부. "동일 LLBC 입력" 요건은 이 시험이 그대로 충족했다(임포트된 파일 = `17113512…`).

**시험 2 — charon 0.1.281 `--preset=aeneas` 재추출 LLBC(`8d2951da…`) + 정확-핀 aeneas**: 추출 exit 0 (§4.3 프로토콜 전부 충족). aeneas: exit **2**, 1.380 s — **임포트 직후 언커트 예외, 함수 번역 0건**. 출력 원문:

```
[Info ] Imported: /tmp/b0_c7_work/aeneas_preset.llbc
Uncaught exception:
  
  (Failure "Can't convert the name of a tuple to a pattern")

Raised at Stdlib.failwith in file "stdlib.ml", line 29, characters 17-33
Called from Charon__NameMatcher.name_to_pattern_aux in file "charon-ml/src/NameMatcher.ml" (inlined), lines 914-915, characters 2-33
Called from Charon__NameMatcher.name_to_pattern in file "charon-ml/src/NameMatcher.ml", line 1117, characters 12-39
Called from Aeneas__LlbcAstUtils.name_to_pattern in file "llbc/LlbcAstUtils.ml", line 130, characters 8-50
Called from Aeneas__LlbcAstUtils.name_with_crate_to_pattern_string in file "llbc/LlbcAstUtils.ml", line 143, characters 12-41
Called from Dune__exe__Main.(fun) in file "Main.ml", lines 688-689, characters 16-60
Called from Stdlib__List.map in file "list.ml", line 86, characters 15-19
Called from Dune__exe__Main in file "Main.ml", lines 685-693, characters 10-52
```

`-use-lean-modules false`를 부여해도 동일 크래시(재현 관측).

**시험 3 — 최소 서브그래프(`c7_min.llbc`, `756810f5…` — C7+전이 의존성만, fun_decls 66) + 정확-핀 aeneas**: exit **2**, 0.245 s — **동일 크래시 원문 동일**. 크래시 원인이 serde_json의 어떤 무관한 항목이 아니라 **C7 서브그래프 내부**에 있음을 분리 관측.

**루트 컴파운드 확정(LLBC 측)**: `c7_min.llbc`의 `type_decls`에는 튜플 클래스 이름이 **정확히 1개** 존재한다 — `def_id 0`, `kind: Opaque`, name = `[{"Builtin": [{"Tuple": 0}, 0]}]` — 즉 C7 시그니처의 **`(usize, usize)` 튜플 타입의 charon 이름(`<tuple 0>`) 자체**. aeneas의 NameMatcher(`name_to_pattern`)는 이 이름 요소를 패턴으로 변환할 수 없어 임포트/기동 단계(Main.ml:685-693의 List.map — 외부 정의 매칭 테이블 구성)에서 언커트 예외로 사망한다. **크래시 트리거가 C7의 증명 의무에 필요한 구성요소(튜플 타입)에서 직접 발생**한다는 것이 이 실험의 핵심 부정 관측이다.

**시험 4 — 동일 preset LLBC(`8d2951da…`) + 최신 aeneas(`nightly-2026.11.03-ab34bd2`, 번들 charon 0.1.304)**: exit **1**, 1.201 s. 출력 원문:

```
[Error] error: Incompatible version of charon: this program supports llbc emitted by charon v0.1.304 but attempted to read a file emitted by charon v0.1.281.
```

→ 최신 aeneas는 버전 게이트에서 명시 거부. (입력 재생성은 charon 0.1.304가 요구되므로 본 실험의 "동일 LLBC" 경계 밖 — §10 후속으로 기록.)

### 5.5 관측되지 못한 것 (정직 목록)

- 함수별 번역 성공/실패 목록 — **미관측** (4회 모두 임포트/버전 단계에서 종료; 단 한 개의 함수도 번역되지 않았다).
- 생성 Lean 모델 빌드 결과 — **N/A** (모델 미생성; Lean 4.33.0/elan은 소비되지 않았고, aeneas 73b7cf9가 기대하는 Lean은 v4.35.0-rc4 — 커밋 제목 "Update Lean to v4.35.0-rc4 (#1417)" — 즉 사용했어도 저장소 핀 Lean 4.33.0과 다른 툴체인이 필요했을 것이다).
- 미구현 외부 함수·타입 템플릿 목록(`-print-unknown-externals` 출력) — **미획득** (기동 실패로 출력되지 않음). 대신 **LLBC 측 opaque 목록**을 §5.3에 기록했다(직접 callee 8종 + helper 수준 2종 — 이것이 "증명에 필요한데 본체가 없는" 외부 의미 집합의 LLBC 근거다).

## 6. Evidence

산출물 해시(`/tmp/b0_c7_work` 측정, 2026-11-03):

| 파일 | sha256 | bytes |
|---|---|---|
| `input_d1.llbc` (입력 of record = state_d1 사본) | `17113512a770a39e0614254f4bbd09211a955f9dde1b00bd8354552985ce5784` | 27,695,554 |
| `aeneas_preset.llbc` | `8d2951da76dd8fef08e5935d2779e77ee85c436b42fa82666b5d13f725039d19` | 29,914,620 |
| `c7_min.llbc` | `756810f5f3e09c5b385392668f8410b5cfe234ffa3a22452f5e14b0871e4f2a8` | 367,587 |
| `aeneas_1013/aeneas` (바이너리) | `d510194ed1e51758849451a361869325b0f4227f231fc25ba4fd2f6d53e2a50e` | — |
| `aeneas_1013/charon` (번들) | `cccbb77cd02c34677fd30f152938b15d8f35574292d25086b7ea8cf359774a72` | — |
| `aeneas_1013/charon-driver` (번들) | `888096bc2471ca8e959b5e04eeb2eb2c4c879f2983fdd7afc4a6d42921bc2594` | — |
| `dl_1013/aeneas-linux-x86_64.tar.gz` (릴리스 자산) | `89af369c3c27cbe2b0dbf7599a09e945aceb3a65532cc7875213a53f95272a83` | 157,294,816 |
| `dl_1013/lean-build-aeneas-x86_64-unknown-linux-gnu.tar.gz` (릴리스 자산, 미소비) | `41436a415d9a88309619d4df1782121e648f2ec235163f088928cea4e263a379` | 67,270,277 |
| `dl/aeneas-linux-x86_64.tar.gz` (대조군 nightly-2026.10.31 자산, 미사용 시험) | `7754a62bb94b63f7b286ada4d7431923984734af036fe7304cdf59ebe54b7ca6` | — |
| `dl/lean-build-aeneas-x86_64-unknown-linux-gnu.tar.gz` (대조군, 미소비) | `080967101fab806fca2d3654a0c236ec42afb038119e76adde43f621e6b02e2c` | — |
| 설치본 `<user-home>/.cargo/bin/charon` | `dfa2ee6ca63f150f825c6853edb828a8730817e632444e9f02fb0bb07b7d6057` | — |
| `clone_manifest_pre.sha256` (재추출 잠금 프로토콜 사전) | `775211468c43222389d05908e15fc11c2c89c9d4545911f1eb32f529ede5c7e0` | — |

런 로그 원문 보존(§5.4 인용의 원본): `/tmp/b0_c7_work/aeneas_run.log`(시험 1), `aeneas_preset_run.log`(시험 2), `aeneas_c7min_run.log`(시험 3), `aeneas_latest_run.log`(시험 4) — `/tmp` 소멸성 기록이므로 본 문서의 인용이 정본 복사본이다.

## 7. Classification

### 7.1 Go/No-Go 표 (구성요소별)

"Aeneas 처리(실측)" 열의 값은 **이 실험에서 관측된 것**만 적는다 — aeneas 문서상 지원 범주는 추정으로 기록하지 않는다. 4회 시험 모두 번역 단계에 도달하지 못했으므로 대부분의 행은 "미관측"이다.

| # | 구성요소 | LLBC 경로 증거 | Aeneas 처리(실측) | Axiom v1 최소 구현 후보 | 판정 |
|---|---|---|---|---|---|
| 1 | `&mut String` 입력 — `Ref`(리전 변수, Mut) | §5.2 signature.inputs[0] + generics.regions[0] | 번역 도달 실패(시험 1–4) | 없음 — v1 서명 문법(u8/u32/bool 스칼라 파라미터) 밖 | **SCOPE_LIMIT** |
| 2 | `Option<(usize, usize)>` 반환 — Adt + 내장 튜플 | §5.2 output 217; locals[0]; Adt 57; **type_decls `<tuple 0>` (c7_min def_id 0)** | **튜플 타입 이름이 NameMatcher 크래시 직접 유발(시험 2·3)** | 없음 — Adt 반환 밖 | **SCOPE_LIMIT** |
| 3 | Adt 구성/분해 — Aggregate(Adt) ×12, Discriminant ×3 | §5.3 히스토그램 | 미관측 | 없음 | **SCOPE_LIMIT** |
| 4 | match/Switch 분기 ×7 (enum discriminant·bool) | §5.3 스크루티니 기록 | 미관측 | 없음 — v1은 straight-line만 | **SCOPE_LIMIT** |
| 5 | 루프 Loop ×2 + Continue/Break ×2 (비중첩 단일 레벨) | §5.3 히스토그램 | 미관측 (비중첩이라 aeneas 문서의 중첩-루프 한계와는 인접하지 않음 — 그러나 관측 없음) | 없음 | **SCOPE_LIMIT** |
| 6 | usize 오버플로-체크 산술 — AddChecked ×4, Lt ×1 | §5.3 BinaryOp 세부 | 미관측 | **유일한 부분 적합** — AddChecked/Eq는 v1 인증 문법 내 rvalue; 그러나 단독으로는 C7 명제를 만들지 못한다 | 부분 적합(구성요소 단위) |
| 7 | 패닉 경로 — Assert ×4 | §5.3 히스토그램 | 미관측 | 없음 — 패닉 의미론 부재 | **SCOPE_LIMIT** |
| 8 | str 슬라이스 인덱싱 — `alloc::string::<impl>::index` (Opaque) ×4 | §5.3 callee 298 | 미관측 — 본체가 LLBC에 없음 | 없음 — 외부 의미 공리 선행 필요 | **SCOPE_LIMIT** |
| 9 | `core::str::<impl>::rfind` (Opaque) | §5.3 callee 296 | 미관측 — 본체 없음 | 없음 | **SCOPE_LIMIT** |
| 10 | `str::starts_with`/`str::len`/`String::len`/`String::deref` (Opaque ×6 sites) | §5.3 callee 299/297/300/295 | 미관측 — 본체 없음 | 없음 | **SCOPE_LIMIT** |
| 11 | `core::num::<impl>::from_str` (Opaque) ×2 — 숫자 파싱 의미 | §5.3 callee 301 | 미관측 — 본체 없음 | 없음 | **SCOPE_LIMIT** |
| 12 | `alloc::string::<impl>::truncate` (Opaque) — 경계·길이 의미 | §5.3 callee 302 | 미관측 — 본체 없음 | 없음 | **SCOPE_LIMIT** |
| 13 | `starts_with_digit` — 인크레이트 Structured (36 statements, callee as_bytes/first Opaque) | §5.3 callee 6 + 본문 히스토그램 | 미관측 | 잠재 후보 — 그러나 Switch/Borrowck 포함으로 함수 단위로는 v1 밖 | **SCOPE_LIMIT** (구성요소 단위 부분) |
| 14 | 문자열 리터럴 상수 ×2 (`" at line "`, `" column "`) | §5.3 Const operands (id 339/342) | 미관측 | 없음 — v1 문법 밖 | **SCOPE_LIMIT** |

### 7.2 Terminal Outcome (관찰자 판정)

- **Aeneas 적용성: No-Go (현 상태)** — 정확-핀 바이너리(charon 0.1.281 완전 일치)가 존재하고 조달·실측에 성공했음에도, (i) 캠페인 산출물은 aeneas 소비 계약(`--preset=aeneas`) 밖이고, (ii) 계약을 맞춰 재추출하면 aeneas가 **C7 서명의 튜플 타입 이름에서 언커트 크래시**로 사망하며, (iii) 최신 aeneas는 charon 버전 게이트로 거부한다. 번역 계층 관측 0건 — "Aeneas가 C7을 번역한다/못한다"의 함수 수준 판정은 **이 입력에서는 성립하지 않았다**.
- **Aeneas 다리 = BLOCKED (ToolchainFailure)** — BLOCKED 처리 규정대로 우회 없이 원문 4건과 루트 컴파운드를 그대로 착지한다. 재시도 조건: (a) aeneas 측 NameMatcher의 Builtin-Tuple 이름 지원 수정이 릴리스되고, (b) 그 릴리스의 charon-pin이 0.1.281과 동일하거나 LLBC를 0.1.304로 재추출하는 별도 사전등록 실험 — 어느 쪽이든 **새로운 사전등록**이 필요하다(본 문서는 그 권한을 부여하지 않는다).
- **Axiom v1 판정: SCOPE_LIMIT_CONFIRMED 유지 + 층 3 예측의 사후 확정** — C7 시그니처(Ref/Adt)가 LLBC 실측으로 직접 확인됐다(§5.2). 캠페인에서 files-table(층 2)이 먼저 막아 서명 게이트(층 3)에 도달하지 못했던 예측은, 본 LLBC 관측으로 **근거가 고정**되었다. 새로운 허용 범위는 열리지 않았다.
- BLOCKED가 아니라 정상 관측인 부분: charon preset 재추출(2회)은 전부 성공이고 잠금 프로토콜을 충족했다 — B-0의 "핀 Charon 재추출 능력"은 입증됐다(오프라인, lock in==out, 매니페스트 사전==사후).

## 8. Interpretation

### 8.1 "LLBC에 등장" ≠ "증명에 필요"

문법 재고(캠페인 §4)는 2,134 fun_decls 중 1,162 Structured / 675 Opaque를 셌다. 본 실험은 그 축을 C7 하나에 대해 **증명 의무 기준**으로 다시 셌다: C7의 직접 callee 9개 중 **8개가 Opaque** — LLBC에 "등장"하지만(참조로서) "증명에 필요한 의미"는 산출물에 존재하지 않는다. 즉 B-0 슬라이스의 실질 결론: **C7의 증명 의무는 (a) 서명 자체가 v1 문법 밖이고, (b) 본문의 문장 종류(Switch/Loop/Assert/Aggregate)가 전부 v1 밖이며, (c) 의존 callee의 의미 대부분이 산출물 밖에 있다** — 세 겹의 한계가 동시에 성립한다. 이 세 겹은 독립적 관찰로, 어느 하나만 고쳐도 C7은 인증되지 않는다.

### 8.2 Aeneas는 advisory 제3다리다 (정직 범위)

- Aeneas는 추출 단계를 Charon과 **공유**한다 — LLBC가 틀리면 Aeneas도 같은 입력을 받는다. 따라서 Aeneas가 번역에 성공해도 **독립 검증은 아니다**; 비교는 LLBC→번역 계층에 한정된다.
- 본 실험에서 Aeneas는 번역 계층에 도달조차 못 했다 — 위 표의 "미관측"은 실패가 아니라 **도달 실패**이며, 그 원인 3종(preset 계약, NameMatcher 튜플 크래시, charon 버전 게이트)을 원문으로 고정했다. 특히 (ii)는 C7 고유 구성요소가 트리거했다는 점에서 serde_json 일반성과 무관한 **C7 특이적** 장애물이다.
- 극장 금지 준수: 4건의 실패를 모두 원문 기록했고, " Lean 빌드 산출물 다운로드(67MB)를 구했다"는 사실을 성공으로 재포장하지 않았다(§6 미소비 명시). 발견된 것은 등록 대상 극장이 아니다(둘러싸기·우회·위장 없음 — aeneas 소스 패치도 하지 않았다).

### 8.3 gh 쿼터 사건

시험 중 GitHub API core 잔여가 0/5000에 도달했다(공유 계정 창). 자격 증명을 쓰지 않는 퍼블릭 자산 다운로드로 전환해 §2.4를 준수했다. rate-limit 우회가 아니라 **자격 증명 자체를 사용하지 않는 경로**다.

## 9. Non-Conclusions

- **C7 및 serde_json에 대한 참/거짓 판정은 없다.** 반례 산출 0건, 검증 0건.
- **"Aeneas가 C7을 번역할 수 없다"고 일반화할 수 없다.** 성립한 것은 이 입력(charon 0.1.281 LLBC) + 이 바이너리(73b7cf9) + 이 시점(2026-11-03)에서의 4건 실패 관측이다. 최신 aeneas + charon 0.1.304 재추출 조합은 시험되지 않았다(입력 동일성 계약을 깨는 별도 실험이 필요 — §10).
- **"파싱/락/매니페스트가 Axiom lane에서도 동일하게 작동한다"는 검증이 아니다.** 본 실험의 charon 실행은 lane 밖 /tmp 클론에서 수행됐다.
- `targets[0].status = "unknown"` 등 캠페인 런의 기계 표기에 대한 과대해석 금지는 그대로 유효하다.

## 10. Next Experiment

1. **NameMatcher 튜플 이름 지원** — aeneas 상류에 Builtin-Tuple 이름 요소의 패턴 변환 지원(또는 명시적 거부 메시지)이 있는지 추적. 수정 릴리스의 charon-pin이 0.1.281과 호환되는지 확인 후 재시험(사전등록 필요).
2. **charon 0.1.304 LLBC 경로** — aeneas 최신과의 계약 일치를 위해 charon 0.1.304로 재추출하는 별도 사전등록 실험. 이때 입력 동일성은 "서브젝트 commit + charon 커밋 + 옵션" 튜플로 재정의되어야 한다(해시 단일 기준은 버전을 넘어 유지 불가 — 본 문서 §5.1이 그 이유의 실측 증거다).
3. **서명 부분집합 확장(Ref/Adt)** — adjudication §10.3 후속의 LLBC-근거 보강으로 본 문서 §5.2를 참조할 수 있다.

## 결정론 기록 (Determinism Record — 미션 항목 (a)–(i))

| 항목 | 값 |
|---|---|
| (a) Rust 대상 commit + C7 signatureHash | subject `8c535a260ce561eaab4111aafc29038eb9f77ff3`; C7 signatureHash `48c4dc5b55757f7c444e8a6d0bf5fdaadd10f48791a6dea9df39484db7367851` (error.rs:494, 규약 동일 — 캠페인 sidecar 값 재확인) |
| (b) Charon 실행 identity | 번들 사용: `/tmp/b0_c7_work/aeneas_1013/charon` — `charon version` → `0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)` exit 0; sha256 `cccbb77cd02c34677fd30f152938b15d8f35574292d25086b7ea8cf359774a72`; `charon toolchain-version` → `nightly-2026-09-17`; 명령: `charon cargo --preset=aeneas [--start-from 'serde_json::error::parse_line_col'] --dest-file <f> -- --target-dir <t>` (CARGO_NET_OFFLINE=true). 참조: 설치본 `<user-home>/.cargo/bin/charon` 동일 버전 문자열, sha256 `dfa2ee6ca63f150f825c6853edb828a8730817e632444e9f02fb0bb07b7d6057` |
| (c) 입력 LLBC 해시 | 시험 1 = 캠페인 state_d1 `17113512a770a39e0614254f4bbd09211a955f9dde1b00bd8354552985ce5784`; 시험 2·4 = `aeneas_preset.llbc` `8d2951da76dd8fef08e5935d2779e77ee85c436b42fa82666b5d13f725039d19`; 시험 3 = `c7_min.llbc` `756810f5f3e09c5b385392668f8410b5cfe234ffa3a22452f5e14b0871e4f2a8` (전부 §5.1 표) |
| (d) Aeneas 버전/커밋 | `73b7cf9f7442c5aba550c224bd7fd212d39ba32f` (release `nightly-2026.10.13-73b7cf9`, `-version` 원문 `aeneas nightly-2026.10.13-73b7cf9`); charon-pin@커밋 = `7980165…` (git show 실측 — 정확 일치); 참조 대조: 최신 `ab34bd28458a08c150b7cbf1873e59af74588138` (charon 0.1.304) |
| (e) 동일 LLBC가 Aeneas에 입력된 증거 | 시험 1: aeneas 출력 1행째 원문 `[Info ] Imported: /tmp/b0_c7_work/input_d1.llbc` + 입력 파일 sha256 고정. 시험 2·3·4: 동일 `aeneas_preset.llbc`/`c7_min.llbc` 파일을 여러 aeneas 바이너리에 그대로 입력(파일 재생성 없음 — cp 없이 절대경로 참조) |
| (f) 생성 Lean 모델 빌드 결과 | **N/A — 모델 미생성**(4회 모두 임포트/버전 단계 종료; 번역된 함수 0건). aeneas 73b7cf9 기대 Lean = v4.35.0-rc4(커밋 제목) — 저장소 핀 Lean 4.33.0과 상이하는 사실도 기록 |
| (g) 미구현 외부 목록 | `-print-unknown-externals` 부여했으나 기동 실패로 미획득. LLBC 측 대응물(§5.3): 직접 Opaque callee 8종(deref/rfind/str::len/string::index/starts_with/string::len/from_str/truncate) + helper 수준 2종(as_bytes/slice::first) |
| (h) 구성요소별 지원 표 | §7.1 (14행, Aeneas 실측 열 = 관측된 것만) |
| (i) 재현 명령열 | 아래 블록 |

```sh
# (1) 입력 of record 해시
sha256sum .4/experiments/serde-json-claim-2026-10-31/state_d1/.axiom/rust-lane/1398235db249fc8b/subject.llbc
# → 17113512a770a39e0614254f4bbd09211a955f9dde1b00bd8354552985ce5784

# (2) charon identity
charon version
# → 0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)

# (3) 서브젝트 /tmp 클론 (원본 무수정) + preset 재추출 (잠금 프로토콜)
git clone <workspace>/json /tmp/b0_c7_work/json_clone
cd /tmp/b0_c7_work/json_clone
cp .4/experiments/serde-json-claim-2026-10-31/inputs/Cargo.lock Cargo.lock
sha256sum Cargo.lock   # 1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4
CARGO_NET_OFFLINE=true /tmp/b0_c7_work/aeneas_1013/charon cargo --preset=aeneas \
  --dest-file /tmp/b0_c7_work/aeneas_preset.llbc -- --target-dir /tmp/b0_c7_work/charon-target
sha256sum Cargo.lock   # in==out (동일값)
rm Cargo.lock

# (4) 최소 서브그래프 (진단용)
CARGO_NET_OFFLINE=true /tmp/b0_c7_work/aeneas_1013/charon cargo --preset=aeneas \
  --start-from 'serde_json::error::parse_line_col' \
  --dest-file /tmp/b0_c7_work/c7_min.llbc -- --target-dir /tmp/b0_c7_work/charon-target2

# (5) aeneas 시험 (4회의 입력 조합은 §5.4)
cd /tmp/b0_c7_work/aeneas_1013
./aeneas -backend lean -dest /tmp/b0_c7_work/lean_out -print-unknown-externals /tmp/b0_c7_work/aeneas_preset.llbc
# → exit 2, Uncaught exception: (Failure "Can't convert the name of a tuple to a pattern")
```

## Landing record

- (착지 후 기록 — PR 번호, merge commit oid, landing_observe 결과는 본 섹션에 추가 없이 최종 보고에 기재된다. 본 문서는 단일 커밋으로 착지된다.)
