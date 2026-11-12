# serde_json C7 판정 폐쇄 — canonical main 정준 재현(d4) + 음성 대조 3종 (2026-11-03)

> **Status**: Closure evidence record — 문서·증거 산출물만 (`src/` 무수정, 제품 코드 무변경, main worktree 무수정; 모든 실행은 전용 worktree `/tmp/c7_d4_wt`에서 수행)
> **Created**: 2026-11-03
> **Written at**: branch `work/c7-closure-2026-11-03` (worktree `/tmp/c7_d4_wt`), branch base = main `2ff226d406d789f29609ad964b8a3324a04e82fb` (PR #1244 merge)
> **Governing docs**: [serde_json_claim_adjudication_2026-10-31.md](serde_json_claim_adjudication_2026-10-31.md) (Terminal Outcome 선언 — 본 문서는 재선언이 아니라 현재 canonical main에서의 재현·폐쇄 기록) · [serde_json_c7_semantics_aeneas_2026-11-03.md](serde_json_c7_semantics_aeneas_2026-11-03.md) (B-0 — 층 3 사후확정·구성요소 전수·Aeneas BLOCKED) · [FREEZE.md](../../experiments/serde-json-claim-2026-10-31/FREEZE.md) (§7/§9.3 동결 명령·§8 잠금 프로토콜) · [ACCEPTANCE.md](../../experiments/serde-json-claim-2026-10-31/ACCEPTANCE.md) (d1/d2/d3 역사 관측)
> **원칙**: 기계 출력과 오류 문자열은 원문 그대로 인용한다(재작성·요약·번역 없음). 이 문서는 관찰을 기록하며 판정 대상 프로젝트(serde_json)에 대한 어떤 참·거짓 주장도 하지 않는다. 역사 문서(FREEZE·ACCEPTANCE·adjudication·B-0·`rust_certified_subset.md`)는 무수정 — 본 문서가 참조만 한다.

7-field identity (FREEZE.md §1 형식 준용 — 값은 본 문서 정체성):

- PROJECT_UNDER_TEST: serde_json (Rust crate) v1.0.154 — 모순후보 **C7** (`serde_json::error::parse_line_col`, error.rs:494)의 **canonical main 정준 재현(d4) + 음성 대조 3종(N1 identity 변조 / N2 증명서 부재 / N3 스코프락 부재)에 의한 판정 폐쇄**
- REVISION: `8c535a260ce561eaab4111aafc29038eb9f77ff3` (subject HEAD — 매 런 전후 find-매니페스트로 무결성 재확인, §5·§6)
- AXIOM_REVISION: `2ff226d406d789f29609ad964b8a3324a04e82fb` (main = PR #1244 merge; d4 실행·빌드 브랜치 `work/c7-closure-2026-11-03`의 base이자 실행 시점 HEAD). 캠페인 본체는 PR #1149 (`ee87f0a70a8a518e490c74499b5e134ef112ea08`, d3 실행 시점) 이후 main이 이동했다 — 본 문서가 그 이동 후의 재현을 기록한다
- CONFIG: `AXIOM_STATE_DIR`/`AXIOM_PROVE_VAULT_DIR` per run (state_d4/state_n1/state_n3 + 각 vault); `CARGO_NET_OFFLINE=true`; `GITHUB_TOKEN` procured via `gh auth token` (native client, §2.4 — `gh_env.txt` 미접촉); FREEZE §8 잠금 프로토콜(pre-manifest → lock 투입·별도 해시 in==out → 제거 → post-manifest)
- TOOLCHAIN_ID: Nim 2.2.10; charon **0.1.281** (`798016509139eb51f0d764645f76d068d34ba5f6`) — d4 stdout 1행째 원문이 pinned==measured 일치를 기계 출력(`ok=true`); rustc 1.95.0; cargo 1.95.0; charon toolchain `nightly-2026-09-17`
- SCOPE: d4(현재 canonical main에서의 FREEZE §9.3 동결 명령형 재현, fresh state_d4/vault_d4) + N1/N2/N3 음성 대조 + 폐쇄 기록. **범위 밖**: C1~C8 참/거짓 판정, v1 서명·문법 확장, `src/` 코드 변경, 신규 기계 판정값/enum 생성(glossary §1 HARD RULE), per-run taxonomy 변경 — 어느 것도 수행하지 않았다
- EXPERIMENT_ID: serde-json-claim-2026-10-31 (캠페인 identity SSOT 재사용 — 재등록 없음; run row = d4)

---

## 1. Question

이 문서가 답하는 질문:

1. d3가 실행된 merge commit `ee87f0a70`(2026-10-31) 이후 엔진이 이동한 현재 canonical main `2ff226d40`에서, C7의 기계 판정 관측(exit 0 + `targets[0].status="unknown"` + producer fail-closed 거부)은 **동일하게 재현되는가**?
2. 판정의 무결성 장치는 실제로 차단하는가 — (N1) state lock의 선언 identity(signatureHash)를 변조하면, (N3) 스코프락을 결손시키면 기계는 어떻게 반응하는가? (N2) `unknown`이 `verified`로 승격되지 않음이 구조적으로 집행되는가?
3. 이 재현·음성 대조는 adjudication의 Terminal Outcome(SCOPE_LIMIT_CONFIRMED)을 현재 main까지 폐쇄하기에 충분한가 — 그리고 무엇이 관측적으로 변했는가?

## 2. Context

- 캠페인 계보: probe(exit 3 재선출) → d1/d2(files-table 층 2 거부, `unknown`) → PR #1149 착지 → d3(canonical 재현) → adjudication(Terminal Outcome = SCOPE_LIMIT_CONFIRMED, 병치 모델) → B-0(층 3 서명·본문 구성요소의 LLBC 사후확정 + Aeneas BLOCKED) — 본 문서는 그 다음 단계다.
- **d3 이후 main의 관련 이동 (기계 확인)**: baseline `data/verification_scope.lock`의 `rust_targets`는 d3 시점 2개 → `2ff226d40` 시점 6개 (u64 probe 2건 추가 — `git log ee87f0a70..2ff226d40 -- data/verification_scope.lock` = `b5fec7a38`(2026-11-02, "fixture axiom_u64_probe … declared lock entries") + `9c081ed95`(2026-11-02, "… lock vksRust 6")). 또한 lane 입력계약이 강화되었다(§5.1 reason 클래스 — 강제점 `src/verification/rust_input_contract.nim`). 이동 사실 자체가 d4를 필요하게 만든 이유다.
- C7 앵커(불변): `fn parse_line_col(msg: &mut String) -> Option<(usize, usize)>` (error.rs:494), signatureHash `48c4dc5b55757f7c444e8a6d0bf5fdaadd10f48791a6dea9df39484db7367851` (규약: brace·들여쓰기·개행 없음; FREEZE §9.4 재확인 일치).

## 3. Scope

- **범위 안**: (a) `make build`(worktree bin/ax) + `bin/ax --check-provenance` + `agent_preflight`, (b) d4 실행(FREEZE §9.3 동결 명령형 — `--target 'serde_json::error::parse_line_col'`, shell 인용 필수)과 §8 잠금 프로토콜 전 절차, (c) N1(선언 signatureHash 말미 1 hex 치환 → 동일 실행), (d) N2(vault 공석·`unknown` 유지·verified 재작성 부재 단언 — 실행 없음), (e) N3(스코프락 부재 state → 실행 차단 관측), (f) d1–d4 축별 대조와 폐쇄 판정 기록.
- **범위 밖**: C1~C8 판정, B-1 의미 단위 구현, Aeneas 재시험(B-0 §5.4 원문 보존 — 재현 명령열만 참조), Charon 추출 옵션 변경, 게이트·정책 변경, 역사 문서 재작성.
- 서브젝트는 읽기 전용이다 — Cargo.lock의 일시 배치만 FREEZE §8 프로토콜로 수행했고 매 런 in==out·제거·매니페스트 복귀를 검증했다(§6).

## 4. Procedure

### 4.1 빌드·사전 게이트 (worktree `/tmp/c7_d4_wt`, HEAD `2ff226d40`)

- `make build` → exit 0 (67.7s), `bin/ax` 28,294,872 B, sha256 `3d94a954425ec71578239bf6b7d4f768edf0666f75249bb93d371e29c34d2241` (git 비추적 로컬 산출물 — 기록 전용)
- `bin/ax --check-provenance` → `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (-7275307651492060493)`, exit 0
- `nim c -r src/gate/runners/agent_preflight.nim` → exit 0, `[INFO] logger: [SUCCESS] Agent Pre-flight Guard: Workspace 무결성 검증 통과.` (15.7s — ACCEPTANCE ①의 d1 사전 게이트 선례 준용)

### 4.2 동결 명령형 (FREEZE §9.3 형식 — d4)

CWD = worktree root; `EXP=experiments/serde-json-claim-2026-10-31`; `JSON=<workspace>/json`.

```
mkdir -p $EXP/state_d4/data $EXP/vault_d4 $EXP/runs/d4
jq --slurpfile e $EXP/inputs/verification_scope.rust_targets.json \
  '.rust_targets += [$e[0]] | .vksRust = (.rust_targets | length)' \
  data/verification_scope.lock > $EXP/state_d4/data/verification_scope.lock
# (1) 원 상태 확인: Cargo.lock 부재 — 존재 시 즉시 중단
# (2) 원 상태 find-매니페스트 (lock 투입 전) → runs/d4/subject_manifest_pre.sha256
# (3) cp inputs/Cargo.lock $JSON/Cargo.lock → 별도 해시 기록 (in) + cleanup trap
# (4) AXIOM_STATE_DIR=$EXP/state_d4 AXIOM_PROVE_VAULT_DIR=$EXP/vault_d4 \
#     CARGO_NET_OFFLINE=true GITHUB_TOKEN=$(gh auth token) \
#     bin/ax prove --project $JSON --target 'serde_json::error::parse_line_col' \
#     > $EXP/runs/d4/stdout.txt 2>&1   (exit 코드 별도 기록)
# (5) 임시 lock 해시 (out) — in==out diff
# (6) rm lock → post find-매니페스트 — pre==post diff
```

동결 명령 대비 **조립식 1개소 수정(사전등록)**: `.vksRust = 3` → `.vksRust = (.rust_targets | length)`. 원문 상수 `3`은 동결 시점 baseline 2개 + 캠페인 1개 = 3이라는 **당시 계산값**을 하드코딩한 것이다. 현재 baseline은 6개(§2)이므로 원문 형태 그대로는 `declared 3 vs computed 7`으로 스코프 선언 자체가 무효가 된다. 수정식은 엔진이 강제하는 불변식(선언 == `rust_targets` 계산값)과 계약 동등이며 타깃 추가·조립 절차는 동결형과 동일하다. 최초 시도(원문 형태)의 거부 관측은 §5.1a에 원문 보존했다. 이 외의 동결 절차(잠금 프로토콜 순서, 매니페스트, 실행 명령)는 일절 변경 없다.

### 4.3 음성 대조 (동일 worktree·엔진 — d4와 동일 임시 lock 프로토콜)

- **N1**: state_n1 lock을 §4.2와 동일 조립식으로 생성한 뒤, 선언 `signatureHash`의 **말미 1 hex만 치환** (`…db7367851` → `…db7367850`; `48c4dc5b55757f7c444e8a6d0bf5fdaadd10f48791a6dea9df39484db7367851`의 최종 문자). 변조 증명: d4 lock과의 `jq -S` diff가 정확히 1행 1문자(§5.3). state_n1/vault_n1 fresh.
- **N2**: 실행 없는 단언 — d4 후 `vault_d4` 내용물 0건, `runs/d4/skreport_payload.json`의 `targets[0].status`/`summary` 재확인, verified 재작성 부재. 구조적 집행점 인용(§5.4).
- **N3**: `state_n3`(data/ 없음 — 스코프락 부재) + vault_n3 fresh → 동일 실행. 스코프락 외 조건은 d4와 동일.

## 5. Result

### 5.1 d4 관측 (canonical main `2ff226d40`, state_d4/vault_d4, 2026-11-03)

- **exit code: 0**; wall 16.574s
- **stdout — 전부 3줄, sha256 `9ddc5dbc7b104135a353c3144f1f466e3d7e10c1db7c6f6126f9c4bce59e298d` — d1/d2/d3와 바이트 동일**:

```
[AXIOM][rust-lane] charon pinned='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' measured='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' ok=true
[AXIOM][rust-lane] ledger transport armed (live); repo=Archright/Axiom
[AXIOM][rust-lane] done: verified=0/1 failed=0 unknown=1 error=0
```

- **d4 `targets[0]` 원문** (skReport payload 전문 보존: `runs/d4/skreport_payload.json`, sha256 `e4082afc0b9d8341c4771cacbb165247fdc46835c63322638e1aa6c2d7be97db`; schemaVersion `axiom.report.v1`, subjectLane `rust`, charon ok=true pinned==measured, summary `{"verified":0,"failedCount":0,"timeoutCount":0,"verifiedRatio":0.0,"statusCounts":{"verified":0,"failed":0,"unknown":1,"error":0}}`, `identityBundleDigest` `a21e0c78d7035764f6c4fcd291af61573d5e7958ecdaa327ac29e5838d7f3eb5`):

```
name:   serde_json::error::parse_line_col
status: unknown
reason: producer: rust subject input contract FAILED (LLBC not current with the subject source — fail-closed): subject file(s) missing from the LLBC local table: [build.rs, fuzz/fuzz_targets/from_slice.rs, src/io/core.rs, src/io/mod.rs, src/lexical/algorithm.rs, src/lexical/bhcomp.rs, src/lexical/bignum.rs, src/lexical/cached.rs, src/lexical/cached_float80.rs, src/lexical/digit.rs, src/lexical/errors.rs, src/lexical/exponent.rs, src/lexical/float.rs, src/lexical/large_powers.rs, src/lexical/large_powers32.rs, src/lexical/large_powers64.rs, src/lexical/math.rs, src/lexical/mod.rs, src/lexical/num.rs, src/lexical/parse.rs, src/lexical/rounding.rs, src/lexical/shift.rs, src/lexical/small_powers.rs, src/macros.rs, src/raw.rs, tests/compiletest.rs, tests/crate/test.rs, tests/debug.rs, tests/lexical.rs, tests/lexical/algorithm.rs, tests/lexical/exponent.rs, tests/lexical/float.rs, tests/lexical/math.rs, tests/lexical/num.rs, tests/lexical/parse.rs, tests/lexical/rounding.rs, tests/macros/mod.rs, tests/map.rs, tests/regression.rs, tests/regression/issue1004.rs, tests/regression/issue1083.rs, tests/regression/issue520.rs, tests/regression/issue795.rs, tests/regression/issue845.rs, tests/regression/issue953.rs, tests/regression/issue979.rs, tests/stream.rs, tests/test.rs, tests/ui/missing_colon.rs, tests/ui/missing_comma.rs, tests/ui/missing_value.rs, tests/ui/not_found.rs, tests/ui/parse_expr.rs, tests/ui/parse_key.rs, tests/ui/unexpected_after_array_element.rs, tests/ui/unexpected_after_map_entry.rs, tests/ui/unexpected_colon.rs, tests/ui/unexpected_comma.rs]
```

- **무결성 축**: 임시 Cargo.lock in==out `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` (FREEZE §4 핀 일치), 제거 후 부재 복귀; find-매니페스트 pre==post (93 files, 파일 sha256 `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` — **d1/d2/d3의 매니페스트와 동일 sha256**, 즉 서브젝트 바이트 불변의 직접 증거); state lock sha256 `0775b285c11df0cb5e529e3dc822eabdaea3762e0ebe77f43711e1bb3c620e10` (8,749 B, `rust_targets` 7개 = baseline 6 + 캠페인 1, `vksRust` 7, dupPairs 0, 64-hex 검증 통과); trajectory `state_d4/logs/ax_prove_trajectory.jsonl` 1행 (sha256 `7b03eeed710863281a88452768f1be5729a58dd70c18535f92c49778bab82783`); `vault_d4` 비어 있음(0 파일).

#### 5.1a 최초 시도 (동결 원문 상수 `.vksRust = 3` 그대로) — 정직 기록

§4.2의 수정 이전, 동결 명령을 문자 그대로 실행한 최초 시도는 다음을 관측했다 (state_d4 최초 조립분 lock sha256 `0bd79392c5c0fbb28642dfe9581b4721fbf8c2248ea2aa0c56468c47eab5cfe0`, n=7/vksRust=3):

- **exit code: 3**; wall 0.252s — charon 호출 이전 스코프 로드 단계에서 거부 (무결성 축은 이 시도에서도 전부 성립: lock in==out, 매니페스트 pre==post, 제거 복귀)
- stdout 전부 1줄, sha256 `ea1d95a71b963a2a51c4aa90e824ff8b952c3e931bdedb4c8ccf45c3604ba289`:

```
[ERROR] action_interpreter_cli: [ERROR] [AXIOM] rust lane refuses an invalid vks_rust scope declaration (fail-closed): vksRust mismatch: declared 3 vs computed 7 from rust_targets
```

- 분류: FREEZE §6 판정표의 `exit 3 INVALID_INPUT … fix and re-run, recorded` 행과 동일 취지의 **기계적·자기기술적**(self-describing) INVALID_INPUT — 관측 대상 현상(C7 범위 한계)이 아니라 스코프 선언 상수의 진부화다. FREEZE §8의 BLOCKED 트리거 어느 것도 아니다. 수정(§4.2) 후 판정 런(d4)을 1회 실행했고 두 관측 모두 원문 보존했다. 이 거부 자체는 vksRust 선언 불변식의 정상 fail-closed 집행이다.

### 5.2 d1–d4 대조 (FREEZE §7 3축 + identity 축)

| 축 | d1 | d2 | d3 | **d4** | 판정 |
|---|---|---|---|---|---|
| ① exit code | 0 | 0 | 0 | **0** | **동일** |
| ② Cargo.lock in==out | `1bc62b1a…` | `1bc62b1a…` | `1bc62b1a…` | **`1bc62b1a…`** | **동일** |
| ③ stdout (sha256) | `9ddc5dbc…` | `9ddc5dbc…` | `9ddc5dbc…` | **`9ddc5dbc…`** | **바이트 동일** |
| ④ `targets[0].name`/`status` | parse_line_col / unknown | 동일 | 동일 | **동일** | **동일** |
| ⑤ 거부 reason 클래스 | files-table 절대경로 | 동일(빌드해시만 상이) | 동일(빌드해시만 상이) | **input-contract 파일셋 동등성(LLBC not current)** | **클래스 진화 — §8 참조** |
| ⑥ subject 매니페스트 pre==post | `b49abcbc…` | 동일 | 동일 | **동일** | **동일** |
| ⑦ state lock | `0c1f4abc…` (n=3, vksRust=3) | 동일 | 동일 | **`0775b285…` (n=7, vksRust=7)** | baseline 진화 반영 — §2 |
| ⑧ skReport payload | `0604043f…` | `edfd7051…` | `9bc2d1fc…` | **`e4082afc…`** | 런별 경로 헝크 + 신규 필드(§8) |

stdout이 바이트 동일한 이유: stdout 3줄은 charon identity·transport·summary 카운트만 운반하며, 거부 reason은 skReport payload(`targets[0].reason`)에만 존재하기 때문이다 — 즉 ③의 바이트 동일성과 ⑤의 reason 클래스 진화는 모순이 아니다.

### 5.3 N1 — 선언 identity 변조 (signatureHash 말미 1 hex)

- 변조: `48c4dc5b55757f7c444e8a6d0bf5fdaadd10f48791a6dea9df39484db7367851` → 말미 `1`→`0` (변조 후 `…db7367850`). d4 lock과의 canonical diff 원문 (유일 차이):

```diff
--- state_d4/data/verification_scope.lock (jq -S)
+++ state_n1/data/verification_scope.lock (jq -S)
-      "signatureHash": "48c4dc5b55757f7c444e8a6d0bf5fdaadd10f48791a6dea9df39484db7367851",
+      "signatureHash": "48c4dc5b55757f7c444e8a6d0bf5fdaadd10f48791a6dea9df39484db7367850",
```

- 기계 결과: **exit 0** (wall 16.587s), stdout sha256 `9ddc5dbc…` (d4와 바이트 동일), `targets[0].status="unknown"` 유지, **`vault_n1` 0 파일 — 증명서 미발행**, manifest pre==post, lock in==out.
- 변조의 기계 결속 — §6c v2 identity sidecar(`state_n1/.axiom/rust-lane/1398235db249fc8b/skreport-identity.json`, `src/cli/rust_lane_cli.nim:630-645` 경유)가 d4와 n1에서 **정확히 2필드** 상이:

```diff
-    "payloadSha256": "43f7796e3af40e2e138c8fb92019fbf63e52a26ad4310df4ede3998ff483dd9e"
+    "payloadSha256": "a325c5b2fb30cd05fb4c5844cb1a63228d9eeff62223e9cd75865b327a8b2e95"
-      "rustTargetsSha256": "0775b285c11df0cb5e529e3dc822eabdaea3762e0ebe77f43711e1bb3c620e10"
+      "rustTargetsSha256": "8c7cbdaa04a1cc6176dd4e2eff93475358a35f0f33df0e25ce4664da51a09511"
```

  (`rustTargetsSha256`은 각 런의 state lock 파일 sha256과 동일 — d4 `0775b285…`, n1 `8c7cbdaa04a1cc6176dd4e2eff93475358a35f0f33df0e25ce4664da51a09511`. skReport payload의 `identityBundleDigest`도 d4 `a21e0c78…` → n1 `b5b6061b7b7b7fa2ad4c84c45d6b1998d1a42cb5b8be920b00a242ab52583364`로 변조를 반영해 상이하며, 이것이 두 payload의 유일 차이다.)
- **정직 기록 (예측과의 불일치)**: 계약 기반 예측은 "합의 실패 → 명시적 거부"였다. 실측은 그러했다 — 명시적 identity-mismatch 거부 라인은 관측되지 **않았다**: 현 엔진 상태에서 producer 입력계약 거부(§5.1 reason)가 §6c identity 측정 단계보다 먼저 발화하여, 변조된 선언값은 identity 합의 판정에 **도달하지 못했다**. 그럼에도 (i) 증명서는 발행되지 않았고(vault 공석), (ii) `unknown`은 재작성되지 않았으며, (iii) 변조는 identity 번들 digest와 sidecar에 기계적으로 결속·기록됐다 — "발행·증명서 없음" 절반이 그대로 성립했다. 명시적 합의-실패 거부 클래스의 관측은 다른 실행 계열(producer 거부가 없는 in-subset 타깃)에서만 가능하다 — **팔로우업 노트** (범위 밖 발견, §2.2 발견 ≠ 권한).

### 5.4 N2 — 허위 Verified 승격 부재 (실행 없는 단언)

- `vault_d4` = 0 파일, `vault_n1` = 0 파일 — 발행된 증명서 없음.
- `runs/d4/skreport_payload.json`: `targets[0].status = "unknown"`, summary `verified: 0, verifiedRatio: 0.0` — **verified 재작성 없음** (adjudication "어느 런도 `verified`로 rewrite되지 않았다" 모델의 d4 준수).
- 구조적 집행점 (현재 `2ff226d40` 소스 인용): v1 폐쇄 문법 — `src/verification/llbc_to_canonical.nim:27-28` "REJECTED (fail-closed): every other statement kind (Switch, SwitchInt, Call, Loop, Drop, Abort, …)", `:1099` "outside the closed v1 grammar (Structured bodies only)"; 발행은 verified 경로에서만 — `src/cli/rust_lane_cli.nim:911` ("verified: <name> → <certPath>"), PENDING family는 "every declared target unverified; NEVER a certificate" (`:668`). 즉 `unknown` 상태에서 증명서 경로 자체가 열리지 않는다.

### 5.5 N3 — 스코프락 결손 (도구실행 차단 계열)

- state_n3: `data/verification_scope.lock` 부재 확인 후 실행 → **exit code: 3**; wall 0.241s — charon 호출 이전 즉시 거부. stdout 전부 1줄, sha256 `7012e5ed9ed293015810185145f8dafa3bb0b7e4fbb5be36d8833ce7a4cb8d25`:

```
[ERROR] action_interpreter_cli: [ERROR] [AXIOM] rust lane requires the verification scope lock (fail-closed): not found at '/tmp/c7_d4_wt/experiments/serde-json-claim-2026-10-31/state_n3/data/verification_scope.lock' — with --project the lock is resolved from the state root ($AXIOM_STATE_DIR/data/verification_scope.lock)
```

- 무결성 축: lock in==out, 매니페스트 pre==post, `vault_n3` 0 파일.
- **계열 차별 (판정 규칙)**: N3 = exit≠0 도구실행 차단(BLOCKED 계열 후보 — 실행 자체가 성립하지 않음) vs d4 = exit 0 + `unknown` + producer fail-closed reason(**scope-limit 관측 계열** — 실행은 성립하고 판정이 `unknown`으로 기록됨). 두 관측은 다른 계열이며 상호 대체되지 않는다.

## 6. Evidence

커밋 산출물 (d1–d3 선례 준용 — runs/dN 3파일 + state_dN data/logs):

| 파일 | sha256 |
|---|---|
| `runs/d4/subject_manifest_pre.sha256` | `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` |
| `runs/d4/subject_manifest_post.sha256` | `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` |
| `runs/d4/skreport_payload.json` | `e4082afc0b9d8341c4771cacbb165247fdc46835c63322638e1aa6c2d7be97db` |
| `state_d4/data/verification_scope.lock` (8,749 B) | `0775b285c11df0cb5e529e3dc822eabdaea3762e0ebe77f43711e1bb3c620e10` |
| `state_d4/logs/ax_prove_trajectory.jsonl` (1행) | `7b03eeed710863281a88452768f1be5729a58dd70c18535f92c49778bab82783` |

비커밋 디스크 관측치 (d1 관례 — stdout은 디스크에만 존재; 값은 본 문서가 정본 기록):

| 항목 | 값 |
|---|---|
| `runs/d4/stdout.txt` sha256 | `9ddc5dbc7b104135a353c3144f1f466e3d7e10c1db7c6f6126f9c4bce59e298d` (d1/d2/d3와 바이트 동일) |
| d4 exit / wall | 0 / 16.574s |
| 최초 시도(`runs/d4/attempt1_stale_vksRust3/`) | exit 3 / 0.252s, stdout sha256 `ea1d95a71b963a2a51c4aa90e824ff8b952c3e931bdedb4c8ccf45c3604ba289`, 당시 조립 lock sha256 `0bd79392c5c0fbb28642dfe9581b4721fbf8c2248ea2aa0c56468c47eab5cfe0` |
| `runs/n1/stdout.txt` sha256 / exit / wall | `9ddc5dbc…` / 0 / 16.587s — d4와 바이트 동일 |
| n1 변조 lock sha256 | `8c7cbdaa04a1cc6176dd4e2eff93475358a35f0f33df0e25ce4664da51a09511` |
| n1 payload sha256 / identityBundleDigest | `15229ba204bf90ab2aac94faf0a44aead147426a93c600967ba39ff516c4a3e8` / `b5b6061b7b7b7fa2ad4c84c45d6b1998d1a42cb5b8be920b00a242ab52583364` |
| `runs/n3/stdout.txt` sha256 / exit / wall | `7012e5ed9ed293015810185145f8dafa3bb0b7e4fbb5be36d8833ce7a4cb8d25` / 3 / 0.241s |
| 3런 공통 lock in==out | `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` (FREEZE §4 핀) |

## 7. Classification

### 7.1 Terminal Outcome — SCOPE_LIMIT_CONFIRMED (문서 계층, 유지)

현재 canonical main `2ff226d40`에서의 d4 + 음성 대조는 adjudication의 Terminal Outcome을 **변경 없이** 폐쇄한다:

1. **producer fail-closed 거부의 재현** — d4는 exit 0 + `targets[0].status="unknown"` + producer 입력계약 fail-closed reason을 출력했다. 거부 클래스는 d1–d3와 동일한 **입력계약 계열**(강제점 `src/verification/rust_input_contract.nim` — d1–d3는 (a) files-table 사전검증 `:179-183`, d4는 (a) 통과 후 (c2) 파일셋 동등성 `:217-221`; "First failure wins")이며, 계약 문서 `docs/spec/rust_certified_subset.md`의 v1 폐쇄 문법에는 어떤 확장도 일어나지 않았다.
2. **재실행 불변** — d1(브랜치)·d2(cold)·d3(merge commit)·d4(신규 canonical main, cold) 4회 모두 동일 종착 모양(exit 0 + unknown + producer 거부 + stdout 바이트 동일). BLOCKED 요인(FREEZE §8: offline fetch failure·charon timeout·token refusal·lock in≠out) 어느 것도 발화하지 않았다(전 런 lock in==out).
3. **음성 대조 통과** — identity 변조는 발행 없이 번들 digest에 결속 기록되고(N1), `unknown`은 구조적으로 verified로 승격되지 않으며(N2), 스코프락 결손은 exit 3으로 차단된다(N3). 즉 "기계가 모르는 것을 모른다고 기록하는" 장치가 실제로 작동한다.
4. **Aeneas는 판정 근거가 아니다** — B-0의 Aeneas 4회 시험은 별도 도구시험으로 **BLOCKED(ToolchainFailure)** 분리 기록이며(B-0 §5.4, §7.2), 본 폐쇄의 근거는 층 2(d4 producer 거부 실측)·층 3(서명 — B-0 §5.2 LLBC 사후확정: inputs=[Ref(Var,Ty,Mut)], output=Adt)·본문 구성요소(B-0 §5.3: Switch×7·Loop×2·Assert×4·Ref×20·Aggregate×12·AddChecked×4·직접 callee 9중 8 Opaque)의 **삼중 기계 근거**뿐이다. Aeneas 관측은 참조 only다.
5. **병치 모델 유지** — 종착 3-way는 per-run taxonomy(`verified`/`failed`/`unknown`/`error`)를 대체하지 않고 병치된다. d4의 `targets[0].status="unknown"`은 그대로 유효한 기계 기록이며, 어느 런도 verified로 rewrite되지 않았다. 신규 판정값·enum·producer·gate·required check는 도입하지 않았다(glossary §1 HARD RULE).

### 7.2 Non-claims

- **C1~C8 중 어느 것도 판정되지 않았다** — 본 문서는 C7의 캠페인 단위 종착(범위 한계 관측)의 현재 main 재현을 기록할 뿐, `parse_line_col` 또는 serde_json의 어떤 동작에 대한 참·거짓 주장도 하지 않는다. 버그 주장 0건, 반례 산출 0건, 검증 0건.
- "verified 0/1, unknown 1"은 기계의 한계 기록이지 부정 증명이 아니다 — adjudication/B-0의 과대해석 금지는 그대로 유효하다.
- d4의 reason 클래스 진화(§8)는 v1 지원 범위의 **확대도 축소도 아니다** — 입력계약 검사의 정밀화가 관측된 것이다(어느 쪽인지 단정하는 것은 본 문서 범위 밖).

## 8. Interpretation — d3 대비 관측 변동 (정직 목록)

모든 변동은 "판정 차이"가 아니라 **엔진·환경 진화의 관측**으로 기록한다:

1. **거부 reason 클래스 진화**: d1–d3 `producer: LLBC files table pre-validation failed: files[1]: absolute path '…' (subject-relative POSIX path required)` → d4 `producer: rust subject input contract FAILED (LLBC not current with the subject source — fail-closed): subject file(s) missing from the LLBC local table: [58 files]`. 강제점(`rust_input_contract.nim`)은 (a) files-table → (b) Cargo identity → (c) 파일셋 동등성 순서의 "First failure wins" 계약으로, d1–d3에서 (a)가 먼저 막혔고 d4에서는 (a)가 통과해 (c)가 막았다. 58개 결손 파일(build.rs·fuzz·tests·src/lexical·src/io 등)은 charon lib 추출이 커버하지 않는 서브젝트 소스다 — fail-closed 거부라는 점과 계열(입력계약)은 d1–d3와 동일하다.
2. **skReport 신규 필드**: `identityBundleDigest` (d1–d3 payload에는 없음) — §6c v2 production-time identity sidecar의 도입(`rust_lane_cli.nim:630-651`). N1의 변조 결속 관측을 가능하게 한 장치다.
3. **baseline lock 성장**: `data/verification_scope.lock` rust_targets 2→6 (u64 probe, 2026-11-02 2건) — 동결 상수 `.vksRust = 3`을 진부화시켰고(§5.1a), d4 lock sha256이 d1–d3(`0c1f4abc…`)와 다른 유일한 원인이다. 캠페인 타깃 항목 자체(8c535a26/parse_line_col/`48c4dc5b…`)는 d1–d3와 바이트 동일하게 보존됐다.
4. **wall time**: d1–d3 12.98–13.24s → d4/n1 16.6s (동일 머신, 엔진·베이스 진화 상태) — 판정과 무관한 실행 환경 관측.
5. **경로 헝크**: d1–d3와 마찬가지로 런 상대 경로는 state dir·빌드해시 헝크로 변동한다(선례된 정직 변동). d4 reason은 절대경로를 내장하지 않는 상대경로 목록 형태라 이전보다 헝크가 작다.

## 9. Deviations (전수 목록)

1. **§4.2 조립식 1개소 수정 (사전등록)** — `.vksRust = 3` → `.vksRust = (.rust_targets | length)`. 원인·근거·최초 시도 원문은 §2/§4.2/§5.1a. FREEZE §6의 기계적 INVALID_INPUT "fix and re-run, recorded" 선례 적용. 동결 절차의 나머지는 일절 불변.
2. **N1 변조 방향 표기** — 실행 브리프는 말미 `0→1`(`…367850→…367851`)로 적었으나, 실제 조립 lock의 선언값은 `…db7367851`(FREEZE §9.4 등록값과 일치)로 말미가 이미 `1`이었다. 실측값 기준 말미 1 hex 치환(`1→0`)으로 수행했고 변조 전후 원문을 §5.3에 보존했다 — 치환 규모(말미 1 hex)는 브리프 의도와 동일.
3. **declared deviation (FREEZE §8)** — Cargo.lock 일시 배치 3런(d4/n1/n3), 매 런 in==out·제거·매니페스트 복귀 검증 완료. 서브젝트는 "declared deviation, restored"로 기록된다.

## Landing record

> 본 섹션은 후속 기록 PR(`work/c7-closure-d5-record-2026-11-03`)이 추가한 것으로, 착지된 §1–§9(d4 본문)는 무수정이다. d5 실행은 **detached 워크트리 `/tmp/c7_d5_wt`**에서 수행됐다.

### L.1 실행·착지 계보 (SHA lineage — 두 SHA의 역할 구분)

본 기록은 "최종 main에서 d5를 실행했다"고 서술하지 **않는다**. d5는 `runtime_tested_sha`에서 실행됐고, `final_evidence_sha`는 그 관측 기록이 착지한 커밋이다.

- **`runtime_tested_sha`** = `679eb49db8050ba392e4efa1bb952c2c285cbfd5` (PR #1247 네이티브 MERGE, parents=2) — **d5 detached cold 재현을 실제 실행한 커밋**. 실행 바이너리는 이 커밋의 detached 워크트리에서 `make build`한 `bin/ax`이며(§L.2), baseline lock·조립식 입력도 이 커밋에서 취했다.
- **`final_evidence_sha`** = 본 후속 기록 PR의 MERGE_SHA — **착지 후 확정**되는 "착지 후 관측 기록"이다(PR 본문에 동일 문구 명시). d5의 실행 지점이 아니라, 본 Landing record 섹션과 d5 산출물(`runs/d5/` 3파일 + `state_d5/{data,logs}` 2파일, §L.8)이 착지한 커밋이다.
- 두 SHA 간 변경이 **증거 문서·증거 산출물뿐**임을 검증하는 명령 (착지 후 메인이 실행):

```
git diff --stat 679eb49db <final_evidence_sha>
# 예상 범위: docs/evidence/serde_json_c7_adjudication_closure_2026-11-03.md (본 섹션 확장) +
#            experiments/serde-json-claim-2026-10-31/runs/d5/ 3파일 +
#            experiments/serde-json-claim-2026-10-31/state_d5/{data,logs}/ 2파일 — 이 외 변경 0
```

### L.2 d5 실행 환경 — detached 워크트리 `/tmp/c7_d5_wt` @ `679eb49db`

- `make build` → exit 0 (63.7s), `bin/ax` 28,294,880 B, sha256 `92d2a4f79904534c4e71d263d2cfa0a3672e38e520c9cefdbf24f0f779e17859` (git 비추적 로컬 산출물 — 기록 전용; d4 §4.1의 `3d94a954…`와 상이. bin/ax sha256은 바이트 재현성 지표가 아니다 — 동일 `679eb49db` 소스의 재빌드도 상이한 sha256을 낸다(§L.6-4). 소스 일치는 `--check-provenance`가 담당: 본 빌드 `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (-7275307651492060493)`, exit 0)
- `bin/ax --check-provenance` → `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (-7275307651492060493)`, exit 0
- **baseline lock 변동 확인**: `git log 2ff226d40..679eb49db -- data/verification_scope.lock` = 공집합 — 구간 내 PR #1246 착지에도 baseline lock 불변. d5 조립 lock이 d4와 바이트 동일해야 하는 이유이며 실측도 그러했다(§L.4).
- §4.2 절차를 보완 ① 순서 그대로 수행 — (1) 서브젝트 Cargo.lock 부재 확인(실측: 부재 — 존재 시 중단 규정 미발화) → (2) 원 상태 find-매니페스트 → `runs/d5/subject_manifest_pre.sha256` → (3) `cp inputs/Cargo.lock $JSON/Cargo.lock` + 별도 해시(in) + `trap 'rm -f $JSON/Cargo.lock' EXIT` → (4) 동결 명령형 실행(§4.2와 동일 env — `AXIOM_STATE_DIR=$EXP/state_d5 AXIOM_PROVE_VAULT_DIR=$EXP/vault_d5 CARGO_NET_OFFLINE=true GITHUB_TOKEN=$(gh auth token)`, exit 코드·wall 별도 기록) → (5) 임시 lock 해시(out) — in==out → (6) `rm` lock + trap 해제 + post 매니페스트. 실행 후 서브젝트 `git status --porcelain` 공백·Cargo.lock 부재 재확인. state_d5/vault_d5/runs/d5는 신규 생성이며 기존 state_*/vault_* 디렉터리는 일절 접촉하지 않았다.

### L.3 d5×d4 5축 대조

| 축 | d4 (`2ff226d40`, §5.1) | **d5 (`679eb49db` = runtime_tested_sha)** | 판정 |
|---|---|---|---|
| ① exit code (wall) | 0 (16.574s) | **0 (15.887s)** | **동일** — wall은 실행 환경 관측(§L.6-2) |
| ② `targets[0].name`/`status` | `serde_json::error::parse_line_col` / `unknown` | **동일** | **동일** — 병치 모델 유지 |
| ③ 거부 사유 의미 | producer 입력계약 fail-closed(LLBC not current — 58개 상대경로) | **reason 원문 바이트 동일** (58개, 절대경로 0개 기계 확인) | **동일** — 클래스·원문 모두 |
| ④ 실행 위치 종속 필드 | state_d4 · trajectory ts `2026-11-03T11:45:35.322Z` · trajectory sha256 `7b03eeed…` · bin/ax `3d94a954…` | **state_d5 · ts `2026-11-03T12:35:25.866Z` · trajectory sha256 `405f4e11…` — ts 외 전 필드 동일(`del(.ts)` diff 공집합 입증) · bin/ax `92d2a4f7…`** | 헝크 변동만 — 판정 무관 |
| ⑤ stdout sha256 (3줄, 292 B) | `9ddc5dbc…` | **`9ddc5dbc…` — 바이트 동일** | **동일** |

d5 stdout 실측 원문 (d1–d4와 바이트 동일):

```
[AXIOM][rust-lane] charon pinned='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' measured='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' ok=true
[AXIOM][rust-lane] ledger transport armed (live); repo=Archright/Axiom
[AXIOM][rust-lane] done: verified=0/1 failed=0 unknown=1 error=0
```

### L.4 보조 축 (기록용)

| 항목 | d4 (§5/§6) | **d5** | 판정 |
|---|---|---|---|
| state lock sha256 | `0775b285…` (8,749 B, rust_targets 7, vksRust 7) | **동일 — 커밋된 d4 lock과 `diff` 공집합** | baseline 무변동(§L.2) 반영 |
| subject 매니페스트 (93 files) | `b49abc…` (pre==post) | **`b49abc…` — pre==post, d4 커밋본과 동일 sha256** | 동일 — 서브젝트 바이트 불변의 직접 증거 |
| skReport payload sha256 | `e4082afc…` | **`e4082afc…` — `cmp` 바이트 동일** | 동일 (§L.6-1 참조) |
| `identityBundleDigest` | `a21e0c78d7035764f6c4fcd291af61573d5e7958ecdaa327ac29e5838d7f3eb5` | **동일** | 동일 |
| identity sidecar (§6c v2, `state_d5/.axiom/rust-lane/1398235db249fc8b/skreport-identity.json`) | payloadSha256 `43f7796e…` · rustTargetsSha256 `0775b285…` (§5.3) | **동일값 실측** — subject commit `8c535a26…`, moduleSha256 `a13add05…`, cargoLock `1bc62b1a…`, charon `0.1.281`, rustc 1.95.0, Nim 2.2.10 포함 원문 확보(디스크 전용) | 동일 |
| Cargo.lock in==out | `1bc62b1a…` (FREEZE §4 핀) | **동일** | 동일 |
| vault | 0 파일 | **0 파일** | 동일 — 증명서 미발행 |

### L.5 무결성 축 (d5)

- 임시 Cargo.lock: in==out `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4`, 실행 후 제거·trap 해제 확인
- find-매니페스트 pre==post (93 files, `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` — **d4 커밋 매니페스트와 동일 sha256**)
- 실행 후 서브젝트: `git status --porcelain` 공백 + Cargo.lock 부재 재확인
- trajectory `state_d5/logs/ax_prove_trajectory.jsonl` 1행 (sha256 `405f4e11803c1e24bc28f3a6579dd4eb50c01940b0cf36130219f2ab75a551e5` — d4와 ts 외 동일)
- `vault_d5` 0 파일 — 발행 없음, `unknown` 재작성 없음 (N2 단언의 d5 준용 성립)

### L.6 전례·예상과의 차이 (정직 기록)

1. **skReport payload가 d4와 바이트 동일**(`e4082afc…`) — §5.2 ⑧축 전례(d1–d4 매 런 상이, "런별 경로 헝크")와 달리 d4↔d5 쌍은 동일하다. d4 이후 reason이 절대경로를 내장하지 않게 되어 payload에 실행 위치 헝크가 남지 않은 것이 원인이다(§8-5 헝크 관측의 소멸). 판정 차이 아니다.
2. **wall 15.887s** (d4 16.574s) — 동일 머신의 실행 환경 관측, 판정 무관.
3. **`make build` 출력의 기존 워닝 원문**: `[decision-binding] WARN: 50 function(s) missing {.axiomDecision.} pragma — escalation threshold 30 days not yet reached` — d5 빌드 단계에서 관측. d4 기록(§4.1)에는 빌드 워닝 유무가 기록돼 있지 않아 비교 불가하며, 본 폐쇄 판정과 무관한 기존 빌드 상태 관측이다(범위 밖 — 팔로우업 노트).
4. **bin/ax 비(非)바이트 재현**: 동일 커밋 `679eb49db`의 두 워크트리 빌드가 상이한 sha256 — d5 실행 워크트리 `92d2a4f7…` vs 기록 워크트리 재빌드 `21a30cec…`. bin/ax는 바이트 재현 불가 로컬 산출물이며(임베드 변동원의 식별은 본 문서 범위 밖), 소스 일치 판정은 BuildSourceHash가 담당한다(두 빌드 모두 `--check-provenance` OK, exit 0). d5 실행은 `92d2a4f7…` 빌드로 수행됐다 — 판정 축 아님.

### L.7 Terminal Outcome 영향

d5는 adjudication의 Terminal Outcome(SCOPE_LIMIT_CONFIRMED, §7.1)을 `runtime_tested_sha`에서 **변경 없이** 재폐쇄한다: exit 0 + `unknown` + producer fail-closed 거부(원문 동일) + stdout 바이트 동일 + 음성 장치 유지(vault 공석 · verified 승격 부재). BLOCKED 트리거(FREEZE §8: offline fetch failure · charon timeout · token refusal · lock in≠out) 미발화 — 전 구간 lock in==out. 신규 판정값 · enum · 게이트 · 정책 변경 없음. C1~C8 참·거짓 판정 없음(§7.2 Non-claims 유지).

### L.8 커밋 산출물 (d1–d4 선례 준용 — runs/d5 3파일 + state_d5 data/logs)

| 파일 | sha256 |
|---|---|
| `runs/d5/subject_manifest_pre.sha256` | `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` |
| `runs/d5/subject_manifest_post.sha256` | `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` |
| `runs/d5/skreport_payload.json` | `e4082afc0b9d8341c4771cacbb165247fdc46835c63322638e1aa6c2d7be97db` |
| `state_d5/data/verification_scope.lock` (8,749 B) | `0775b285c11df0cb5e529e3dc822eabdaea3762e0ebe77f43711e1bb3c620e10` |
| `state_d5/logs/ax_prove_trajectory.jsonl` (1행) | `405f4e11803c1e24bc28f3a6579dd4eb50c01940b0cf36130219f2ab75a551e5` |

비커밋 디스크 관측치 (d1 관례 — `/tmp/c7_d5_wt`에만 존재; 값은 본 문서가 정본 기록):

| 항목 | 값 |
|---|---|
| `runs/d5/stdout.txt` sha256 | `9ddc5dbc7b104135a353c3144f1f466e3d7e10c1db7c6f6126f9c4bce59e298d` (d1–d4와 바이트 동일) |
| d5 exit / wall | 0 / 15.887s |
| 임시 Cargo.lock in==out | `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` (FREEZE §4 핀) |
| `runs/d5/{exit_code.txt, wall_seconds.txt, cargo_lock_in.sha256, cargo_lock_out.sha256, state_lock.sha256}` | 디스크 전용 보조 기록 파일 — 위 표 값과 동일 |
