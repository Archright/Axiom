# serde_json B-1 의미 단위 선정 조사 — 측정 증거 기록 (2026-11-04)

> **Status**: Measurement evidence record — B-1 구현의 **입력 계약 생산**. 이 문서는 의미 단위를 결정하지 않는다. 측정된 근거와 후보 순위(결정 아님)만 제공하며, 선정 결정은 별도 계획에서 이루어진다.
> **Created**: 2026-11-04
> **Written at**: branch `work/b1-selection-survey-2026-11-04` (worktree `/tmp/b1_survey_wt`), branch base = canonical main `2f9c21693b401fb040991561b820718b9be0046d` (PR #1249 merge)
> **Governing docs**: [docs/evidence/serde_json_c7_adjudication_closure_2026-11-03.md](serde_json_c7_adjudication_closure_2026-11-03.md) · [docs/evidence/serde_json_c7_semantics_aeneas_2026-11-03.md](serde_json_c7_semantics_aeneas_2026-11-03.md) (B-0, §5.2–5.3 정독 완료) · [experiments/serde-json-claim-2026-10-31/FREEZE.md](../../experiments/serde-json-claim-2026-10-31/FREEZE.md) (§2 핀, §4 잠금 근거, §7 동결 명령 형식, §8 편차 표)
> **원칙**: 기계 출력·오류 문자열·문서 인용은 원문 그대로 기록한다. 이 문서는 관찰을 기록하며 serde_json·charon·Aeneas에 대한 어떤 참·거짓 주장도 하지 않는다. 실패·불일치는 전부 원문 정직 기록했다(§9 편차 레지스트리).

7-field identity (FREEZE.md §1 형식 준용 — 값은 본 문서 정체성):

- PROJECT_UNDER_TEST: serde_json (Rust crate) v1.0.154 — **B-1 의미 단위 선정 조사**: C7 의존성 그래프 정밀화 + charon 추출 옵션 3실험(triage 옵션 1 실측) + Aeneas 재사용 범위 분류 + 재사용 빈도 집계
- REVISION: `8c535a260ce561eaab4111aafc29038eb9f77ff3` (subject HEAD — 실험 개시 전 `git rev-parse`·`status --porcelain` 공백 재확인)
- AXIOM_REVISION: `2f9c21693b401fb040991561b820718b9be0046d` (canonical main, PR #1249 merge; branch base = worktree 생성 시점 main)
- CONFIG: 읽기 전용 관찰 + charon 추출 실험 3회 — **FREEZE §8 잠금 프로토콜을 매 실행마다 적용**(Cargo.lock 부재 확인 → find-매니페스트 → lock 복사+해시+trap → charon 실행 → out 해시 in==out → 제거+post 매니페스트 pre==post → porcelain 공백). charon LLBC·100MB 산출물은 커밋하지 않음(throwaway `/tmp/b1_survey`) — 해시·관측치만 본 문서에 기록. `src/` 무수정, FROZEN 파일 무수정, state_*/vault_*/d1–d5 산출물 무수정(읽기만), `data/verification_scope.lock` 무수정, `gh_env.txt` 미접촉
- TOOLCHAIN_ID: charon **0.1.281** (`798016509139eb51f0d764645f76d068d34ba5f6`) — 설치본 `<user-home>/.cargo/bin/charon`, `charon version` → `0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)` exit 0 (FREEZE §2 핀 일치); rustc 1.95.0 (59807616e 2026-04-14); cargo 1.95.0 (f2d3ce0bd 2026-03-21); charon toolchain `nightly-2026-09-17`
- SCOPE: 위 4개 측정 + 사용자 5기준·7조건 평가 틀의 후보 순위표(근거 포함, **결정 아님**). **범위 밖**: 의미 단위 구현 0건, B-1 계약·정책 변경 0건, 선정 확정 아님, `bin/ax prove` 미실행(런 산출물·state 생성 없음)
- EXPERIMENT_ID: serde-json-b1-selection-survey-2026-11-04

---

## 1. Question

이 문서가 답하는 질문:

1. C7 명제 판정에 **실제로 필요한** 실행 경로·의미 의존성은 무엇인가 — 본문에 "등장"하는 요소와 필요한 요소를 구분하면?("등장 = 검증 의무"가 아님)
2. charon 추출 옵션은 C7의 의미 단위 가용성을 어떻게 바꾸는가 — 기본 옵션의 Opaque 8 callee는 `--extract-opaque-bodies`로 추출되는가, `--start-from`은 최소 범위를 만드는가? (triage 옵션 1의 실측)
3. C7에 필요한 의미 단위 중 Aeneas가 위임 가능한 것(공식 문서 근거)과 Axiom 자체 구현 후보인 것은 무엇인가?
4. 각 의미 단위는 인증 범위 fixture와 serde_json 본체에서 실제로 얼마나 등장하는가 — "C7에만 필요한 단위"와 "여러 실제 프로그램에 재사용되는 단위"의 구분?

## 2. Context

- 선행 폐쇄: C7 Capability Adjudication Closure(PR #1247 `679eb49db` + #1249 `2f9c21693`) — B-0이 C7의 LLBC 실측 의미 범위(§5.2 서명: inputs=[Ref(Var,Ty,Mut)], output=Adt; §5.3 본문 293문 히스토그램·직접 callee 9 중 8 Opaque)와 Aeneas 적용성(4회 시험 전부 번역 도달 실패)을 기록했다.
- 본 조사의 위치: B-1(의미 단위 구현) 착수 전 **입력 계약 측정**. B-0이 남긴 미측정 지점 — (a) 기본 LLBC에서 Opaque로 남는 callee가 옵션 변이로 추출되는지, (b) "등장"과 "필요"의 단위별 구분, (c) 단위별 재사용 빈도 — 를 기계 관측으로 채운다.
- charon 옵션의 공식 문서 약속(Context7 `/aeneasverif/charon`, 2026-11-04 조회 — 실험 전 인용):
  - `--extract-opaque-bodies`: "**Makes all items transparent.** Internally changes the base pattern from `_ → Foreign` to `_ → Transparent` (see Pattern list below), so it affects all items including external ones." (docs/what_charon_translates.md)
  - FAQ: "`--extract-opaque-bodies` is **the hammer that removes this filter**. Now all definitions **reachable from the current crate** will be translated in full. That will still not include a foreign definition if it's not used (even indirectly) by the current crate. … note that `--extract-opaque-bodies` can cause a **lot** of code to be translated, which can be slow and/or hit some cases that Charon doesn't support." (docs/faq.md)
  - `--start-from <PATTERN>`: "**Entry points for translation.** Can be specified multiple times. Default: `crate` (the entire current crate)." (docs/what_charon_translates.md)
  - 기본 불투명도: "`_` → **Foreign** (default: everything starts as foreign)"; "Foreign — the default for items outside the current crate. … **for other items this is equivalent to Opaque**" (함수 = 서명만) (docs/what_charon_translates.md)
- Aeneas 공식 문서 약속(Context7 `/aeneasverif/aeneas`, 2026-11-04 조회 — §6에서 전문 인용): 지원 = safe 순차 Rust 부분집합; 미지원 = 중첩 루프 return·break-to-outer, 제네릭 `&mut` 인스턴스화, 함수 포인터/클로저, 시그니처 내 중첩 borrow, interior mutability, unsafe·동시성; 외부 함수 = `-split-files` 시 `FunsExternal_Template.lean`(sorry 바디) 생성 → 사용자가 `FunsExternal.lean`에 손모델 작성.

## 3. Scope

- **범위 안**: (a) FREEZE §7 형식의 charon 기본 추출(실험 A)과 B-0 §5.3 callee 대조, (b) `--extract-opaque-bodies` 추가 실행(실험 B), (c) `--start-from` 지정 실행(실험 C) — 각각 §8 잠금 프로토콜 전 단계 + 명령 원문·exit·wall·RSS·산출물 해시 기록, (d) C7 fun_decl 본문 전수 순회(문장 종류·rvalue·callee·지역변수)와 소스(error.rs:494-534) 대조에 의한 필요 경로 추출, (e) subject 본체 1,162개 Structured 본문 + 인증 범위 fixture 2종의 단위 빈도 집계, (f) C1~C8 레지스트리(FREEZE §5)에 대한 단위 요구 분류와 후보 순위표.
- **범위 밖**: 의미 단위 구현·Lean 모델 작성, `bin/ax prove` 실행(lane 런·state/vault 생성 수반 — 본 조사는 lane 밖 관찰), Aeneas 재시험(B-0이 BLOCKED 판정 — 재시험은 새 사전등록 필요), charon 0.1.304 재추출, C1~C8 참/거짓 판정.
- 편차: §9에 전수 등록(6건 — 전부 관찰 범위의 명시이며 프로토콜 위반 0건).

## 4. Procedure

### 4.1 공통: §8 잠금 프로토콜 하니스 (매 charon 실행마다 동일 적용)

`/tmp/b1_survey/run_exp.sh` (throwaway, 커밋 안 함 — 본 문서가 정본 복사본):

```sh
# 1) 부재 확인 — 존재 시 즉시 중단
[ -e "$JSON/Cargo.lock" ] && { echo "ABORT"; exit 42; }
# 2) 원 상태 find-매니페스트 (porcelain은 gitignored lock에 맹목 — FREEZE §4)
find "$JSON" -path '*/.git' -prune -o -type f -print | sort | xargs sha256sum > pre_N.sha256
# 3) lock 복사 + 별도 해시(in) + trap
cp $EXP/inputs/Cargo.lock "$JSON/Cargo.lock"; sha256sum "$JSON/Cargo.lock"
trap 'rm -f "$JSON/Cargo.lock"' EXIT
# 4) charon 실행 (cwd = subject; CARGO_NET_OFFLINE=true; timeout; /usr/bin/time -v)
# 5) out 해시 — in==out 필수
# 6) 제거 + post 매니페스트 pre==post + git porcelain 공백 + lock 부재 확인
```

사전 확인(실험 개시 전): `$JSON/Cargo.lock` 부재, subject `git status --porcelain` 공백, subject HEAD `8c535a26…`, lock 입력 sha256 `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` (= FREEZE §4 핀값, `sha256sum` 실측 일치).

### 4.2 세 실험 명령 (FREEZE §7 형식 + 옵션 변이만)

실행 형식: `run_exp.sh <NAME> <TIMEOUT> -- <charon cargo args...>` — cwd `$JSON`, `CARGO_NET_OFFLINE=true`, `timeout <T>`, `/usr/bin/time -v`.

```
# 실험 A — 기본 옵션 (FREEZE §7 run-1 명령 형식 그대로; dest/target-dir만 본 조사 throwaway로)
CARGO_NET_OFFLINE=true timeout 110 /usr/bin/time -v charon cargo --dest-file /tmp/b1_survey/subject_A.llbc -- --target-dir /tmp/b1_survey/charon-target-A

# 실험 B — 옵션 변이 1: hammer
CARGO_NET_OFFLINE=true timeout 230 /usr/bin/time -v charon cargo --extract-opaque-bodies --dest-file /tmp/b1_survey/subject_B.llbc -- --target-dir /tmp/b1_survey/charon-target-B

# 실험 C — 옵션 변이 2: 최소 서브그래프 (B-0 §4.3의 c7_min과 동일 start-from, 그러나 preset 없음 — §9-4)
CARGO_NET_OFFLINE=true timeout 110 /usr/bin/time -v charon cargo --start-from 'serde_json::error::parse_line_col' --dest-file /tmp/b1_survey/subject_C.llbc -- --target-dir /tmp/b1_survey/charon-target-C
```

### 4.3 분석 방법 (throwaway python — 커밋 안 함)

- LLBC는 JSON 직렬화(charon 0.1.281 기본 `--format json`; 파일 선두 원문 `{"charon_version":"0.1.281","translated":{…}`).
- 본문 순회: 문장 노드 = `'id'`와 `'kind'`를 모두 지닌 dict 전수 수집(continuation `statements`·Switch branches·on_unwind 포함) → 문장 종류 히스토그램은 **유니크 id 검증**(A: 308 nodes, unique 308, 중복 0) 후 집계. callee = `kind.Call.call.func.Regular.kind.Fun` (int FunId) → `fun_decls[fid]`의 body 종류(문자열 `'Opaque'` / dict `{'Structured': …}`).
- corpus 빈도: 각 non-null fun_decl의 시그니처 JSON 텍스트 클래스(ref_in/mut_in/tyvar_in/adt_out)와 Structured 본문 JSON 텍스트의 단위 키 출현(`"Switch"`,`"Loop"`,`"Assert"`,`"Aggregate"`,`"Discriminant"`,`"Ref"`,`"AddChecked"`,`"Projection"`,`"Str"`,`"BinaryOp"` 및 binop 키), Opaque-callee 호출 = callee body가 문자열 `'Opaque'`인 decl로의 Call.
- fixture LLBC: `tests/fixtures/rust/{axiom_rust_probe,axiom_u64_probe}/*.llbc` (커밋된 산출물, `charon_version 0.1.281`·`has_errors False` 확인 후 동일 분석기 적용 — fixture 자체 무수정).

## 5. Result

### 5.1 실험 실행 기록 — 3회 전부 원문 관측치

공통: 세 실험 모두 **lock sha256 in==out** (`1bc62b1a…b2e4`), **find-매니페스트 pre==post** (매니페스트 해시 `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` — 캠페인 d1/d2의 사전 매니페스트 동일성 기록(`b49abcb6…`, B-0 §4.1)과 일치), **porcelain 공백**, **lock 부재** — 프로토콜 위반 0건.

| 항목 | 실험 A (기본) | 실험 B (--extract-opaque-bodies) | 실험 C (--start-from) |
|---|---|---|---|
| exit | 0 | 0 | 0 |
| wall (wall_ns / `time -v` Elapsed) | 4,726,253,668 ns / 0:04.72 | 10,694,221,729 ns / 0:10.68 | 2,724,978,846 ns / 0:02.72 |
| max RSS (`/usr/bin/time -v`) | 339,160 KB | 766,324 KB | 285,008 KB |
| LLBC bytes | 27,695,330 | **100,442,024** | 327,985 |
| LLBC sha256 | `06a61d78aa597e5db23cf8eba637adb0f60b745b05b9ad8b11ec216a7ac95c96` | `da23478451c5ee0180d5c6e2ad239cd7600ae55b0e5fd3478af7829a9813612c` | `70fac12fe9e522131c9782745d9da34772e0c1d9bf348489a424fff183195c71` |
| has_errors | false | false | false |
| charon_version 내장 | 0.1.281 | 0.1.281 | 0.1.281 |
| fun_decls (총 / non-null) | 2,134 / 1,838 | **5,037 / 5,037** | 46 / 28 |
| body 종류 분포 | Structured 1,162 · Opaque 675 · null 296 · Intrinsic 1 | **Structured 4,974 · Intrinsic 54 · Extern 9** (Opaque·null 소멸) | Structured 2 · Opaque 26 · null 18 |
| files / type_decls / trait_decls / trait_impls / global_decls | 151 / 240 / 96 / 606 / 382 | 251 / 623 / 179 / 1,442 / 1,278 | 19 / 18 / 9 / 8 / 7 |

- 실험 A 해시는 run-1 정준 `f6eff161…`(27,695,318 B)과 다르다(§9-2). 원인 클래스의 실측 고정: A와 state_d1 LLBC의 files 테이블 비교 — `files[0]`(src/lib.rs)·`files[2]`(src/de.rs)는 **바이트 동일**, `files[1]`만 상이 — 내용 = 빌드스크립트 OUT_DIR 아티팩트 `private.rs`의 절대경로(원문: A = `/tmp/b1_survey/charon-target-A/x86_64-unknown-linux-gnu/debug/build/serde_json/3d1ca928f06c4d25/out/private.rs`, d1 = `…state_d1/.axiom/rust-lane/1398235db249fc8b/charon-target/…`). adjudication §8이 문서화한 "files[1]이 state 소유 charon-target 절대경로를 내장" 원인 클래스와 정확히 일치 — 해시 상이는 런 식별자 차이이며 fun_decl 내용 차이의 증거가 아니다.
- 실험 B의 LLBC 100MB는 커밋하지 않았다(LFS 정책·throwaway 규정) — 해시만 기록, 재현은 §4.2 명령으로.

### 5.2 측정 1 — C7 의존성 그래프 정밀화: "필요 경로" vs "등장 요소"

입력: 실험 A LLBC `fun_decls[5]` (def_id 5, name `[serde_json, error, parse_line_col]`, span `error.rs:494:0–534:1`, `item_meta.source_text` 선두 `fn parse_line_col(msg: &mut String) -> Option<(usize, usize)> {`) — B-0 §5.2의 LLBC 정체성·시그니처 원문과 **동일**(inputs `[{"Value": [220, {"Ref": [{"Var": {"Bound": [0, 0]}}, {"Deduplicated": 26}, "Mut"]}]}]`, output `{"Deduplicated": 217}`). 소스 앵커: subject `src/error.rs:494-534` (읽기 전용 열람, 원문).

#### 5.2.1 명제 판정에 필요한 실행 경로

P: parse_line_col(msg)=Some((line,col)) → line≥1 ∧ col≥1. 소스 대조로 확정한 **성공 경로의 의존 사슬**(순서대로):

1. `msg.rfind(" at line ")` → Option\<usize\> 분기(Switch; None → return None)
2. `start_of_line = start_of_suffix + 9`(문자열 리터럴 길이 산술 — AddChecked)
3. `while starts_with_digit(&msg[end_of_line..]) { end_of_line += 1 }` — **Loop 1** + 슬라이스 생성(Ref) + digit 검사 + AddChecked 증분
4. `msg[end_of_line..].starts_with(" column ")` 검사(Switch bool) — 실패 → None
5. `start_of_column = end_of_line + 8`; `while …` — **Loop 2** (동일 단위 조합)
6. `end_of_column < msg.len()` 검사(BinaryOp Lt) — 미충족 → None
7. `usize::from_str(&msg[start_of_line..end_of_line])` ×2 → Result 분기(Ok/Err; Err → None)
8. `msg.truncate(start_of_suffix)` — **mut String 상태 변이(부수효과)**
9. `Some((line, column))` — 튜플 + Option 구성(Aggregate)

즉 **P 판정은 (i) 서명 수용 + (ii) 4문장군 수용 + (iii) 8 std callee 의존 의미 + (iv) starts_with_digit 본문**을 동시에 요구한다 — B-0 §8.1의 "세 겹" 관찰을 실행 경로 단위로 재확정했다.

#### 5.2.2 단위별 "등장 vs 필요" 구분 (A LLBC 실측, 유니크 id 308 노드)

| 요소 | 등장(계수) | P 판정에 필요? | 근거 |
|---|---|---|---|
| Ref rvalue (borrow 생성) | 20 | **필요** — `&msg[…]` 슬라이스·deref 경유 | §5.3 rvalue; 경로 3·5·7 |
| Switch ×7 (ty197 enum ×3, bool ×3, literal ×1) | 7 | **필요** — Option/Result 분기·bool 검사 | §5.3 스크루티니; 경로 1·4·7 |
| Loop ×2 + Continue/Break ×2 | 2/2 | **필요** — digit 스캔 | 경로 3·5 (비중첩 단일 레벨) |
| Assert ×4 | 4 | **필요** — 슬라이스 경계·오버플로 패닉 경로의 비발생이 성공 경로 전제 | §5.3 |
| Aggregate(Adt) ×12 (Some/None/Ok/Err/튜플) | 12 | **필요** — Option·Result·(usize,usize) 구성 | 경로 1·7·9 |
| Discriminant ×3 | 3 | **필요** — enum 분기 판별 | 경로 1·7 |
| AddChecked ×4, Lt ×1 | 5 | **필요** — 인덱스 산술·길이 비교 | 경로 2·3·5·6 |
| 문자열 리터럴 ×2 (`" at line "` id339, `" column "` id342) | 2 | **필요** — 검색·prefix 인자 | 경로 1·4 |
| mut-ref 파라미터 `&mut String` | 서명 | **필요** — truncate 효과(경로 8) 포함 | §5.2 시그니처 |
| 리전 변수 서명(Bound region 0) | 1 | **필요** — Ref 서명의 일부 | §5.2 generics.regions |
| StorageLive 76 · StorageDead 97 | 173 | **불필요** — 지역 수명 플롬빙(의미 단위 아님) | 본 조사 신규 분리 |
| Borrowck ×10 (FakeRead) | 10 | **불필요** — 대여검사 인공문 | 본 조사 신규 분리 |
| UnwindResume ×20 · Return ×2 · UndefinedBehavior ×3 | 25 | **불필요** — unwinding·종료 플롬빙 | 본 조사 신규 분리 (B-0 §5.3 표 밖 종류) |
| 8 std callee 호출 (295-302) | 16 call sites | **필요(의존 의미)** — 본체는 LLBC 밖 → 외부 모델/공리 선행 | §5.3 |
| starts_with_digit (인크레이트, FunId 6) | 2 call sites | **필요(본문 존재)** — 36문(main-path)·Switch 2·Ge/Le·callee as_bytes+slice::first(Opaque) | B-0 §5.3 헬퍼 기록과 일치(C LLBC에서도 동일 관측) |

그래프 결론(측정된 것): C7 단위 조합 = **{mut-ref 서명(+리전), Ref/Deref, Projection(슬라이스·튜플), Switch(enum+bool), Loop(비중첩), Assert, Aggregate(Option/Result/tuple), Discriminant, AddChecked·Lt, 문자열 리터럴, 8 std callee 모델, 인크레이트 helper}** — 이 12그룹이 B-1이 C7을 판정 가능하게 만드는 최소 단위 집합이다.

### 5.3 측정 2 — charon 추출 실험 3회 (triage 옵션 1 실측)

#### 실험 A — 기본 옵션의 Opaque callee 대조 (B-0 §5.3과의 일치)

C7 직접 callee 9 distinct (16 call sites — 유니크 id 검증 계수):

| FunId | 이름(이름 경로 축약) | body (A) | call sites (A/B-0 §5.3) |
|---|---|---|---|
| 6 | serde_json::error::starts_with_digit | **Structured** | 2 / 2 |
| 295 | alloc::string::<impl>::deref | Opaque | 1 / 1 |
| 296 | core::str::<impl>::rfind | Opaque | 1 / 1 |
| 297 | core::str::<impl>::len | Opaque | 2 / 2 |
| 298 | alloc::string::<impl>::index | Opaque | **5 / 4** |
| 299 | core::str::<impl>::starts_with | Opaque | **1 / 2** |
| 300 | alloc::string::<impl>::len | Opaque | 1 / 1 |
| 301 | core::num::<impl>::from_str | Opaque | 2 / 2 |
| 302 | alloc::string::<impl>::truncate | Opaque | 1 / 1 |

- **분류 일치**: 9 distinct callee, 그중 8 Opaque + 1 Structured(인크레이트 helper) — B-0 §5.3과 동일.
- **call-site 분포 상이 1건** (§9-3): 298 index ×5(B-0 표 ×4), 299 starts_with ×1(B-0 표 ×2) — 총 16은 동일. 본 계수의 신뢰 검증: 문장 노드 308개 유니크 id, 중복 0; on_unwind 서브트리 제외 계수로도 동일 분포(unwind 서브트리는 UnwindResume만 추가로 포함 — main-path 계수 292, unwind 전용 16). 참고: B-0 §5.3 표 자체의 합계는 283으로 기재된 총계 293과 어긋나 있었다(내부 불일치 — B-0 문서는 동결이라 무수정, 본 문서에만 기록).
- 본문 히스토그램 일치(A vs B-0 §5.3): StorageDead 97·StorageLive 76·Assign 67·Call 16·Borrowck 10·Switch 7·Assert 4·Loop 2·Continue 2·Break 2 — 전 항목 동일. B-0 표 밖 종류 신규 관측: UnwindResume 20·Return 2·UndefinedBehavior 3 (합계 308).

#### 실험 B — `--extract-opaque-bodies`: **8개 callee 본문 전부 추출됨**

- C7의 8 Opaque callee(295-302)가 **전부 body=Structured로 전환** — 공식 문서의 약속("the hammer that removes this filter")과 정확히 일치하는 관측.
- 크레이트 전체: fun_decls 2,134 → **5,037**(non-null 5,037 — null 소멸), Opaque 675 → 0. **Extern 9 잔존**(hammer로도 추출 불가한 진짜 외부 — 원문 목록): `panic_impl` ×2, `__rust_alloc_error_handler`, `__rust_no_alloc_shim_is_unstable_v2`, `__rust_alloc_zeroed`, `__rust_alloc`, `__rust_dealloc`, `__rust_realloc`, `miri_promise_symbolic_alignment`. Intrinsic 54.
- parse_line_col 본문은 A와 동일 형태(같은 308 노드 히스토그램·동일 call-site 분포) — dedup 슬롯 id만 재번호(197→196, 83→366 등). has_errors false. 비용: wall 2.26배(4.73→10.68s), RSS 2.26배(339→766MB), LLBC 3.63배(27.7MB→100.4MB) — "can cause a lot of code to be translated" 경고의 실측 확인.

#### 실험 C — `--start-from 'serde_json::error::parse_line_col'`: 최소 범위 실측

- fun_decls 46(Structured 2 = parse_line_col + starts_with_digit; Opaque 26; null 18), files 151→19 — **C7 전이 의존성만의 부분 그래프**. parse_line_col은 `fun_decls[0]`(def_id 0)로 추출, 본문 형태 A와 동일, callee 분류 동일(8 Opaque + starts_with_digit Structured).
- 비용: wall 2.72s, RSS 285,008 KB — 기본 대비 wall 0.58배, LLBC 0.0118배.
- B-0의 c7_min(`--preset=aeneas` + 동일 start-from, 367,587 B / fun_decls 66·null 19)과의 차이(327,985 B / 46·null 18)는 **preset 유무의 옵션 변이** 관측치다(§9-4) — 어느 쪽도 정준 우위를 주장하지 않는다.

### 5.4 측정 3 — Aeneas 재사용 범위 분류 (공식 문서 원문 인용 + B-0 실측 결합)

Aeneas 공식 문서 인용(Context7 `/aeneasverif/aeneas`, 2026-11-04 조회 — 전부 원문):

- 지원 범위: "Aeneas currently **functionalizes a subset of safe Rust**, and we are in the process of extending the functional model with reasoning based on separation logic to support unsafe code and concurrent code." (README.md "Targeted Subset And Current Limitations")
- 루프: "**loops**: `return` inside *nested* loops, or `break`/`continue` to *outer* loops are not supported yet" — 비중첩 단일 루프는 지원 범위.
- mut ref: "**mutable references and generic types**: Instantiating a generic type (including `Self` through a trait implementation) with a mutable reference is not supported yet (e.g., calling `id(&mut x)`)" — **비제네릭** mut ref는 지원 범위.
- 기타: "no functions pointers/closures: ongoing work" · "limited type parametricity: it is not possible for now to instantiate a type parameter with a type containing a borrow" · "no nested borrows in function signatures: ongoing work" · "interior mutability: ongoing work. … ghost states" · "no concurrent execution" (docs/user/src/README.md "What it cannot do?")
- 외부 함수: "`FunsExternal_Template.lean` — **Template generated by Aeneas with `sorry` bodies for external functions**"; "When an axiom originates from a `FunsExternal_Template.lean` … **the model must be provided in `FunsExternal.lean`**"; "`FunsExternal.lean` — Hand-written models of external (e.g., std library) functions … (never overwritten during the translation)" (README.md + documentation/skills/aeneas-lean-core.instructions.md)

C7 필요 단위 → 위임 분류표 (5.2의 단위 집합 기준; "위임" = 번역·모델 계층을 Aeneas에 맡길 수 있는 후보. B-0 실측상 aeneas는 현 입력에서 번역 단계 도달 실패 — 아래 분류는 **공식 문서상 지원 범주** 기준이며 번역 성공을 주장하지 않는다):

| # | C7 필요 단위 | Aeneas 공식 문서상 위치 | 위임 후보 / 자체 구현 후보 |
|---|---|---|---|
| 1 | mut-ref 서명 `&mut String`(+리전) | 지원(제한은 제네릭 `&mut` 인스턴스화뿐 — 본 항목은 비제네릭) | **위임 후보** (단, charon-pin 호환 릴리스 필요 — B-0: 73b7cf9만 0.1.281 정확 일치) |
| 2 | Option\<(usize,usize)\> 반환·튜플 타입 | 지원 범주; 단 B-0 실측: NameMatcher가 Builtin-Tuple 이름에서 언커트 크래시(시험 2·3) | 위임 후보 — **상류 NameMatcher 수정 대기** (B-0 §7.2 재시험 조건) |
| 3 | Adt 구성/분해 (Some/None/Ok/Err) | 지원(Rust enum → Lean inductive) | **위임 후보** |
| 4 | Switch ×7 (enum discriminant·bool) | 지원(match → 함수형 분기) | **위임 후보** |
| 5 | Loop ×2 (비중첩) | 지원(미지원은 중첩 루프 return·break-to-outer) | **위임 후보** |
| 6 | Assert ×4 (경계·오버플로 패닉) | panic → Result 모나드 실패 모델링 (subset 기술 내) | **위임 후보** |
| 7 | AddChecked ×4 · Lt ×1 | checked 산술 → 모나드 실패 | **위임 후보** |
| 8 | 문자열 리터럴 ×2 | 지원(상수) | **위임 후보** |
| 9 | starts_with_digit (인크레이트, 본문 있음) | charon이 본문 추출하면 번역 대상 | **위임 후보** |
| 10 | **8 std callee 의존 의미** (rfind·str::len·string::index·starts_with·string::len·deref·from_str·truncate) | charon 기본 Opaque → aeneas는 sorry 템플릿 생성 → **손모델이 사용자 몫** ("the model must be provided in `FunsExternal.lean`") — aeneas가 std 모델을 제공한다는 문서 근거 없음 | **Axiom 자체 구현 후보** (외부 공리/모델 — aeneas 위임 불가; aeneas를 쓰더라도 동일 손모델 요구는 유지되어 재사용 가능) |
| 11 | Borrowck·StorageLive/Dead·UnwindResume 등 플롬빙 | 번역 대상 아님(의미 없음) | 불필요 (5.2.2 판정과 동일) |

분류 요약: **위임 후보 9 / 자체 구현 후보 1(외부 의미 모델 8종 묶음) / 불필요 1**. 즉 "Aeneas 위임"이 줄여주는 것은 본문 번역 계층이고, C7 판정의 필수 병목인 8 std callee 의미는 어느 경로에서도 손모델·공리 작성이 필요하다 — B-1의 최소 공통 선행 작업이다.

### 5.5 측정 4 — 재사용 빈도 집계 (subject corpus + 인증 범위 fixture + C1~C8)

#### (a) subject 본체 (실험 A LLBC, 1,162 Structured 본문)

단위 → 포함 함수 수 / 총 출현:

| 단위 | funcs (of 1,162) | 비율 | occurrences |
|---|---|---|---|
| Call | 978 | 84.2% | 2,542 |
| Projection (필드/인덱스) | 791 | 68.1% | 6,013 |
| **Ref (borrow)** | **772** | **66.4%** | 5,144 |
| **Aggregate(Adt)** | **557** | **47.9%** | 1,923 |
| Call → Opaque callee | 824 call sites | — | 824 |
| **Switch** | **307** | **26.4%** | 1,073 |
| **Discriminant** | **279** | **24.0%** | 686 |
| Assert | 37 | 3.2% | 124 |
| 문자열 리터럴(Str) | 43 | 3.7% | 90 |
| **Loop** | **32** | **2.8%** | 35 |
| BinaryOp | 91 | 7.8% | 366 |
| AddChecked | 29 | 2.5% | 51 |

binop 키 출현: Le 95 · Eq 64 · AddChecked 51 · Lt 40 · SubChecked 26 · Ge 10 · Gt 8 · MulChecked 7 · Ne 3.

시그니처 형태 클래스(non-null 1,838): scalar-only `(F,F,F,F)` 1,412 (76.8%) · **Ref-in 총 295 (16.0%)** · **mut-ref-in 총 137 (7.5%)** · type-var-in 총 348 (18.9%) · **Adt-out 총 157 (8.5%)**.

#### (b) 인증 범위 fixture (커밋된 LLBC 2종 — charon_version 0.1.281·has_errors false 확인)

| 단위 | axiom_rust_probe (3 funcs, 전부 scalar 서명) | axiom_u64_probe (5 funcs, 전부 scalar 서명) |
|---|---|---|
| AddChecked | 2 funcs / 3 occ | 2 funcs / 3 occ |
| Assert (오버플로 검사) | 2 funcs / 3 occ | 2 funcs / 3 occ |
| Eq | 1 func / 2 occ | 0 |
| Switch | 1 func / 1 occ | 0 |
| Projection | 2 funcs / 6 occ | 2 funcs / 6 occ |
| Move / BinaryOp | 3 / 14 · 3 / 5 | 2 / 11 · 2 / 3 |
| **Ref · Aggregate · Loop · Discriminant · Str · Call→Opaque** | **0 / 0** | **0 / 0** |

→ 인증 범위 fixture는 **Use·AddChecked·Eq·Assert·Switch·Projection만** 포함(Ref·Adt·Loop·문자열 0) — C7 단위 조합은 현재 fixture에 존재하지 않는다(7조건 ①의 실측 근거).

#### (c) "C7 전용 단위" vs "재사용 단위" (a×b 교차)

- **재사용 단위**(corpus에서 광범위·fixture 인접): Ref(66.4% funcs)·Aggregate(47.9%)·Switch(26.4%)·Discriminant(24.0%)·Projection(68.1%)·AddChecked·Eq·Assert — C7뿐 아니라 subject의 수백 함수가 사용. C1/C2/C3/C5/C6/C8 후보도 전부 이 그룹에 의존(아래 표).
- **C7(및 문자열 계열) 전용 단위**: 문자열 리터럴(3.7%)·Loop(2.8%)·mut-ref-truncate 효과 — corpus에서 낮은 빈도, fixture 0.
- **외부 의미 모델 8종**(rfind/index/starts_with/len×2/deref/from_str/truncate): 단일 callee가 아니라 **str/String 연산 모델 계열** — corpus 전체의 824 opaque-callee call sites가 같은 계열의 모델을 요구하는 구조(본 조사가 계수한 opaque 호출 총량).

#### (d) C1~C8 후보별 필요 단위 분류 (레지스트리 = FREEZE §5 원문; 실측 근거 표기)

| 후보 | 필요 단위(근거) | corpus 재사용 등급 |
|---|---|---|
| C1 trailing-input completeness | Adt(Result/Option) 분기·Ref(&mut self)·Loop·Switch — de.rs 파서 본문 | 고 (Adt/Ref/Loop 전부 상위 빈도) |
| C2 recursion limit 128 | Eq·Projection(remaining_depth 필드)·Adt(Err) — **독립 decl 부재 실측**(이름 검색 `check_recursion`·`remaining_depth` 0건 — 매크로 인라인; 본 조사) → 대형 deserializer 본문 안에 내장 | 중 (Eq/Projection은 이미 v1 인접) |
| C3 is_f64 iff | **LLBC 실측**: fun_decls[628], Structured, **11문장**(StorageLive 2·PlaceMention 1·Assign 3·Switch 1·Return 2·Borrowck 1·UndefinedBehavior 1), number.rs:113, callee 0(자체완결) — &self Ref 서명 + Number Adt 분기 | 고 (Adt 분기·Ref) |
| C4 f64 roundtrip pair | f64(비스칼라)·feature 상호배타 쌍(구성 축 — 단위 문제와 직교) | — |
| C5 NaN/Inf serialization | f64 분류 + serializer Switch/Loop 밀집 + std 위임 대량 | 중고 |
| C6 Map order duality | 제네릭 HashMap/Vec(타입 변수 18.9% funcs)·Loop·std 위임 최대 | 중 |
| C7 parse_line_col | 본 조사 §5.2 전 계층 실측 완료 | 고 (12그룹 최대 커버) |
| C8 overflow feature-monotone | AddChecked(29 funcs/51 occ 실측) + feature 쌍 | 고 (단위) / 직교 (구성) |

## 6. 후보 순위표 — 사용자 5기준·7조건 평가 틀 (근거 포함, **결정 아님**)

평가 틀(임무 지정): 5기준 = 재사용성·구현비용·외부위임·검증가능성·증명가치 / 7조건 = ① 실 Rust fixture 존재 ② Nim/Lean 독립 해석 ③ Rust 실행 결과 비교 ④ mutation test 탐지 ⑤ Lean 커널 soundness ⑥ 실명제 1건 증명/반증 ⑦ canonical main 재현. 순위는 측정 근거의 정렬이며 선정 결정이 아니다. 계수 근거는 §5.5, 실측은 §5.2–5.3, 공식 문서는 §5.4.

| 순위 | 후보(단위 조합) | 재사용성 | 구현비용(낮을수록 유리) | 외부위임 | 검증가능성 | 증명가치 | 7조건 요약 | 종합 |
|---|---|---|---|---|---|---|---|---|
| 1 | **C7** — 12그룹 전체 | 최고 — Ref 66.4%·Aggregate 47.9%·Switch 26.4%·Projection 68.1% funcs 등 corpus 최빈 단위를 전부 포함(§5.5a) | 최대 — 서명(Ref/Adt)·4문장군·외부 모델 8종의 3겹+α 동시 필요(§5.2.1 실측) | 번역 계층은 Aeneas 위임 가능(문서상 9단위) — 단 std 모델 8종은 자체(§5.4 #10) | witness 명확 — `" at line 0 column 0"` → Some((0,0)) 반증 경로(채굴 의심과 일치) | 입력상대 명제 — 증명/반증 양쪽 가치(B-0 §9.2 P·D 확정) | ① 부재→신규 fixture 필요(5.5b 실측) ② 가능(유한 파서 상태기계) ③ 가능(내부 fn — crate 내 harness 필요: pub 아님, error.rs:494) ④ 변이 설계 가능(미실시 — Non-claim) ⑤ std 모델 공리의 soundness 요구 ⑥ 있음 ⑦ 본 문서 명령열로 전 재현 | 후보 1 — 단위 커버 최대·판정 경로 유일 실측 |
| 2 | **C3** — {Ref(&self), Adt 분기, bool Eq} | 고 — Adt 분기·Ref는 corpus 최빈(§5.5a); C7과 공유 코어 | 최소 — **11문장·callee 0 실측**(§5.5d: C3 행) | std callee 없음 → 위임 불필요(자체완결 실측) | 실행 비교 가능(witness `18446744073709551616`, number.rs:111-127 — FREEZE §5) | iff 명제 — feature 상대성 주장 | ① 신규 fixture 필요(&self) ② 가능 ③ 가능(pub fn — 직접 호출 가능) ④ 분기 변이 설계 가능 ⑤ 자체완결이라 모델 공리 없음 ⑥ 있음(iff) ⑦ 재현 용이 | 후보 2 — 최저비용 Adt/Ref 진입점. **단점(실측)**: 이름 경로에 Impl 포함 → v1 주소가능성 게이트 구조적 미대응(FREEZE §9.1: enumerateFunDeclNames는 all-Ident만 등록) — B-1이 주소화 확장을 함께 정의해야 도달 가능 |
| 3 | **C2** — {Eq, Projection, Adt(Err)} | 중 — 단위 자체는 v1 인접(Eq/Projection) | 대형 — 독립 decl 부재(매크로 인라인 실측) → deserializer 대형 본문 전체가 맥락 | 중립 | 실행 비교 쉬움(한도 상수 128 — FREEZE §5) | 경계 상수 명제 | ① 신규 fixture 필요 ②~④ 가능(본문 대형) ⑤ 가벼움 ⑥ 있음 ⑦ 가능 | 후보 3 — 단위는 저비용이나 도달 경로 비용이 실측상 높음 |
| 4 | **C1** — {Adt, Ref, Loop, Switch} | 고 — corpus 최빈 그룹 | 대형 — de.rs 파서 본문 맥락 | 중(std 위임 일부) | witness 쉬움(trailing input) | completeness 명제 — 난이도 높음 | ①~④ 가능 ⑤ Loop 의미 요구 ⑥ 있음 ⑦ 가능 | 후보 4 |
| 5 | **C5** — {f64 분류, Switch/Loop 밀집} | 중고 | 대형 — serializer 기계 + f64 비스칼라 | std 위임 대량 | 가능(NaN/Inf 직렬화 결과) | NaN→null 명제 | ① 신규 fixture 필요 ⑤ f64 모델 soundness ⑥ 있음 | 후보 5 |
| 6 | **C6** — {제네릭 컨테이너, Loop} | 중 — 타입 변수 18.9% funcs | 대형 — HashMap/Vec + 제네릭 &mut 인스턴스화(aeneas 미지원 항목과 충돌) | 위임 의존 최대 | 가능 | 보존/손실 이중 명제 | ① 신규 fixture 필요 ⑤ 제네릭 모델 요구 | 후보 6 |
| 7 | **C8** — {AddChecked, feature 쌍} | 단위 고(29 funcs) / 구성 직교 | 중 — 단위는 v1 인접 | 낮음 필요 | feature 매트릭스 필요 | feature-monotone 명제 | ③ 두 설정 빌드 요구 | 후보 7 |
| 8 | **C4** — {f64, feature 쌍} | 직교 | witness 소스 확정(test.rs:990)이라 반증 실행은 쉬움 | — | 반증 용이 | 구성 상호배타 명제 | ③ feature 매트릭스 | 후보 8 — 단위 구현과 직교라 최후순위 |

공유 코어 관측(순위의 근거, 결정 아님): C7과 C3의 단위 교집합 = **{Ref 서명·본문, Adt 분기(Switch/Discriminant), Aggregate, Projection, bool Eq}** — 이 공유 코어만으로 subject non-null의 상당수 함수가 단위 커버에 들어오고(corpus 집계 §5.5a), C7 추가분(Loop·Assert·문자열·외부 모델 8종)은 C1·C5에도 재사용된다. 반대로 어느 후보도 "fixture 존재" 조건 ①을 현재 상태로 만족하지 않는다(§5.5b — fixture는 scalar 직선형만) — ①은 B-1 계획에서 신규 fixture 요건으로 기록될 측정 사실이다.

## 7. Evidence

산출물 해시(`/tmp/b1_survey` 측정, 2026-11-04 — 대용량 LLBC는 비커밋, 해시만 기록):

| 파일 | sha256 | bytes |
|---|---|---|
| subject_A.llbc (실험 A) | `06a61d78aa597e5db23cf8eba637adb0f60b745b05b9ad8b11ec216a7ac95c96` | 27,695,330 |
| subject_B.llbc (실험 B) | `da23478451c5ee0180d5c6e2ad239cd7600ae55b0e5fd3478af7829a9813612c` | 100,442,024 |
| subject_C.llbc (실험 C) | `70fac12fe9e522131c9782745d9da34772e0c1d9bf348489a424fff183195c71` | 327,985 |
| lock 입력 = inputs/Cargo.lock | `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` | — (FREEZE §4 핀 일치) |
| subject find-매니페스트 (pre/post 공통) | `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` | — |
| run 로그 원문 (charon_{A,B,C}.log, /tmp throwaway — 소멸성; 본 문서 §5.1·§5.3 수치가 정본 기록) | 3개 | — |

재현 명령열: §4.1(프로토콜 하니스) + §4.2(세 실험 명령) + §4.3(분석 방법)이 전부다. LLBC 재생성은 같은 명령·같은 subject commit·같은 charon 0.1.281이면 문장·callee 수준에서 동일(fun_decl 내용 동일성은 §5.1 files[0]/[2] 바이트 동일 관측과 §5.3 대조로 뒷받침) — 단 files[1] 절대경로로 **바이트 해시는 런마다 다르다**(§5.1, adjudication §8 원인 클래스).

## 8. Non-Conclusions (Non-claims)

- **의미 구현 0건** — B-1 단위(Ref/Adt/Loop/…)의 구현·Lean 모델 작성은 일절 이루어지지 않았다.
- **계약·정책 변경 0건** — B-1 입력 계약의 확정, `docs/spec/`·`config/`·`data/verification_scope.lock` 변경 없음. 본 PR은 증거 문서 1건뿐이다.
- **선정 확정 아님** — §6 순위는 측정 근거의 정렬이며, 의미 단위 선정 결정은 별도 계획에서 이루어진다.
- **serde_json에 대한 참/거짓 판정 없음** — C1~C8 어느 후보도 판정하지 않았다. `" at line 0 column 0"` 기술은 채굴 의심(B-0 §9.2 인용)의 재기록이며 본 조사가 실행 검증한 것이 아니다(실행 0회).
- **"Aeneas가 C7을 번역한다/못한다" 주장 없음** — §5.4 분류는 공식 문서상 지원 범주 기준이며, 번역 도달 실패(B-0 실측)는 그대로 유효하다.
- **charon 옵션 권고 없음** — 실험 B·C는 옵션의 **관측치**(비용·범위·가용성)일 뿐, lane 채택 권고는 별도 판정이다.

## 9. Deviation 레지스트리 (전수 등록)

| # | 편차 | 원문/근거 | 처리 |
|---|---|---|---|
| 1 | 작업 지시문의 base 해시에 오타(`…561820…`) — 실제 main = `…561b820…` | `git rev-parse main` 실측 | 실측 리포를 권위로 사용(작업 지시문의 worktree 명령형과 충돌 없음 — 실측값이 지시문 의도) |
| 2 | 실험 A LLBC 해시가 run-1 정준 `f6eff161…`(27,695,318 B)과 상이 — 본 측정 `06a61d78…`(27,695,330 B) | files[0]·[2] 바이트 동일, files[1]만 OUT_DIR 절대경로 상이(§5.1 원문) | adjudication §8 원인 클래스와 일치 — 재시도·우회 없이 원인 실측으로 고정 |
| 3 | C7 call-site 분포가 B-0 §5.3 표와 부분 상이(index ×5 vs ×4, starts_with ×1 vs ×2) | 유니크 id 308·중복 0 검증 + on_unwind 제외 재계수 동일(§5.3); B-0 표 자체 합계 283 vs 기재 293 내부 불일치 병기 | B-0 문서는 동결이라 무수정 — 본 문서에만 상이 기록. 어느 쪽도 "수정"하지 않고 양쪽 원문을 병기 |
| 4 | 실험 C를 `--preset=aeneas` 없이 실행(FREEZE §7 형식 순수 변이; B-0의 c7_min은 preset 부여) | 327,985 B / fun_decls 46 vs B-0 367,587 B / 66 | preset 유무의 옵션 변이 관측으로 기록(§5.3) — 우위 주장 없음 |
| 5 | 실험 B LLBC 100,442,024 B — 커밋 불가(LFS 정책·비커밋 규정) | §7 해시 표 | 해시·관측치만 문서에 기록, 재현 명령은 §4.2 |
| 6 | 이번 조사에서 `bin/ax prove` 미실행 — lane 런·state/vault 산출물 0건 | §3 범위 밖 명시 | 레인 검증은 B-1 본체의 범위 — 본 문서는 관찰 계층만 |

## 10. Next Experiment (B-1 계획의 입력 — 권한 없는 제안 목록)

1. **B-1 단위 구현 계획** — §6 공유 코어 {Ref, Adt 분기, Aggregate, Projection, bool Eq}와 C7 추가분 {Loop, Assert, 문자열, 외부 모델 8종}의 구현 순서·검증 전략을 별도 계획으로 확정(본 문서는 권한을 부여하지 않는다).
2. **주소가능성 확장의 대가 측정** — C3 등 Impl 포함 이름 경로의 대응(FREEZE §9.1 기계적 원인)은 B-1 계획에서 별도 항목으로.
3. **신규 Rust fixture** — C7 모양(mut-ref + slicing + loop)과 C3 모양(&self + enum 분기)의 fixture 설계 — 7조건 ①의 충족 수단.
4. **aeneas NameMatcher 수정 추적** — B-0 §10 항목 유지(재시험은 새 사전등록).

## Landing record

- (착지 후 기록 — PR 번호, merge commit oid는 본 섹션에 추가 없이 최종 보고에 기재된다.)
