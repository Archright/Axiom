# serde_json 모순후보 기계 판정 캠페인 — 종착 판정 증거 (세 경계층 관측, 2026-10-31)

> **Status**: Observation evidence record — 관찰 전용 (새 실험 실행 없음, `src/` 무수정, 원본 데이터 무수정)
> **Created**: 2026-10-31
> **Written at**: branch `docs/serde-json-claim-2026-10-31`, Axiom4 HEAD `1d94d5040da0ef96e621eae85eadba9f906d9b8c` (= branch base; 캠페인 등록·런 산출물은 문서화 시점에 untracked working-tree 파일 — `?? experiments/serde-json-claim-2026-10-31/`, `?? gh_env.txt`)
> **Governing docs**: [experiments/serde-json-claim-2026-10-31/FREEZE.md](../../experiments/serde-json-claim-2026-10-31/FREEZE.md) (§0–§8 + §9 Amendment 1) · [experiments/serde-json-claim-2026-10-31/ACCEPTANCE.md](../../experiments/serde-json-claim-2026-10-31/ACCEPTANCE.md)
> **원칙**: 기계 `status`·`reason` 문자열은 원문 그대로 인용한다 (재작성·요약·번역 없음). 이 문서는 관찰을 기록하며 판정 대상 프로젝트(serde_json)에 대한 어떤 주장도 하지 않는다 (§9).

7-field identity (FREEZE.md §1 형식 준용 — 값은 본 문서 정체성):

- PROJECT_UNDER_TEST: serde_json (Rust crate) v1.0.154, default features — 모순후보 캠페인 C1~C8의 기계 판정 종착 기록
- REVISION: `8c535a260ce561eaab4111aafc29038eb9f77ff3` (subject HEAD, clean; 문서화 시점 재확인 일치)
- AXIOM_REVISION: `1d94d5040da0ef96e621eae85eadba9f906d9b8c` (branch base = origin/main at branch creation, "Merge pull request #1144 from Archright/work/ledger-update"; campaign branch `docs/serde-json-claim-2026-10-31`; 문서화 시점 branch tip == base)
- CONFIG: 관찰 전용 — 문서화 시점 preflight gate 재실행(exit 0) 외 새 실행 없음; 캠페인 런타임 구성은 FREEZE §1/§7/§9.3 그대로 (AXIOM_STATE_DIR/AXIOM_PROVE_VAULT_DIR per run, CARGO_NET_OFFLINE=true, GITHUB_TOKEN via `gh auth token` — 값 미출력)
- TOOLCHAIN_ID: documentation-time preflight — Nim 2.2.10; 캠페인 핀은 FREEZE §1/§2 그대로 (charon `0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)`, rustc 1.95.0 (59807616e 2026-04-14), cargo 1.95.0 (f2d3ce0bd 2026-03-21), charon lane nightly-2026-09-17, Lean 4.33.0 (d8b18978322de05a8f3dba51ef03cf5461676c17), Z3 4.13.3)
- SCOPE: probe·d1·d2 세 런의 기계 관측 + 종착 판정(SCOPE_LIMIT_CONFIRMED) 기록; d3(포스트랜딩 정준 재현)과 랜딩 본체는 범위 밖 — pending (문서 말미 Landing record)
- EXPERIMENT_ID: serde-json-claim-2026-10-31

---

## 1. Question

이 문서가 답하는 질문:

1. 사전등록된 예측(FREEZE §6, §9.2)과 실제 기계 관측은 어디에서 갈렸는가?
2. probe → d1 → d2로 관측된 세 개의 경계층은 각각 무엇이며, 어느 층이 실제 거부를 만들었는가?
3. 이 관측은 종착 3-way(VERIFICATION_COMPLETE / SCOPE_LIMIT_CONFIRMED / BLOCKED) 중 어디에 해당하며, 그 근거는 무엇인가?
4. — 그리고 가장 중요하게 — 이 실험은 C1~C8 모순후보에 대해 무엇을 확정했는가, 확정하지 않았는가? (답: §9. 아무것도 판정하지 않았다.)

## 2. Context

캠페인 계보 (전부 FREEZE.md/ACCEPTANCE.md 기록):

- 채굴: serde_json v1.0.154에서 모순후보 C1~C8 채굴 (FREEZE §5). 건식 스캐너 재고: 2,134 fun_decls (296 null, 675 Opaque, 1 Intrinsic, 1,162 Structured); 엄격 인문법 스캔 13 후보 전부 zero-param const — {인문법 실함수} ∩ {채굴 후보} = ∅.
- 선출 1차: C3 formalization을 `serde_json::number::<impl>::is_f64`에 등록 (FREEZE §5, §1 SCOPE). 시그니처 게이트 거부(Ref &self — 인부분집합 밖)가 예측됐고, 기계의 정직한 SCOPE_LIMIT 관측이 기대 종착이었다 (FREEZE §0, §6).
- probe (run 3): exit **3** INVALID_INPUT(NotFound) — §6 예측(exit 0 + unknown)과 불일치. 기계적 원인 측정: 2,134 fun_decls 중 nameable(all-Ident) 152, 그중 이름이 `is_f64`인 것 0 → C3 심볼은 구조적 비주소가능 (FREEZE §9.1).
- 수정안 (§9 Amendment 1, run 4, d1 실행 전 선기록): C7 (error column lower-bound pair)을 자유함수 `serde_json::error::parse_line_col`로 재선출 — 정확히 1 full-name 매치, lastSegment 자체도 유일 (FREEZE §9.2). §6/§8 표는 원문 보존, 충돌 시 §9가 우선.
- d1 (declared target + token, state_d1/vault_d1): exit 0; d2 (cold, state_d2/vault_d2, d1 산출물 미재사용): exit 0. 양쪽 모두 `targets[0].status = "unknown"` — 그러나 reason은 §9.2 예측(서명 게이트 out-of-subset)이 아니라 **producer의 LLBC files-table 사전검증 거부**였다 (ACCEPTANCE ⑥4).
- 선기록 순서 입증: `runs/pre_d1_amendment_timestamps.txt` (sha256 `bbb48ae273110932ee22c0fed374ec16531a67797327599c44faeed80778cb0b`) — 1차 스냅샷(2026-10-31T20:28:55+09:00)에서 FREEZE.md mtime `2026-10-31 20:28:47.810412064 +0900`에 specs/rust_targets는 아직 미편집(`20:01:29.758145678 +0900`); 2차 스냅샷(2026-10-31T20:29:33+09:00)에서 `axiom.specs.json` `20:29:08.479549859 +0900` < `inputs/verification_scope.rust_targets.json` `20:29:14.558590152 +0900` < d1 시작(epoch 1793446239.155085945 = 20:30:39 +0900, ACCEPTANCE ①). 즉 FREEZE §9 → sidecar 등록 → 입력 치환 순서가 d1 이전임이 mtime으로 입증된다.

### 정체성 분리 (engine / subject / evidence)

| 층 | 항목 | 값 |
|---|---|---|
| 엔진 정체성 | Axiom4 base commit | `1d94d5040da0ef96e621eae85eadba9f906d9b8c` (FREEZE §1) |
| 엔진 정체성 | `bin/ax` sha256 | `6dcd7f96a89f55f4d3e0ce1b0d163cd149705891a51a59d1931d2ce5e04e483e` (git-untracked 로컬 산출물 — 기록만, 커밋 안 함; FREEZE §2) |
| 엔진 정체성 | provenance | `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (-1171924972364171515)`, exit 0 (run-4 시작 재실행; ACCEPTANCE ①) |
| 서브젝트 정체성 | subject HEAD | `8c535a260ce561eaab4111aafc29038eb9f77ff3` (FREEZE §3; 문서화 시점 재확인 일치) |
| 서브젝트 정체성 | tree merkle | `d0c2d891838c3c188f084bdafa0442e063b04d62` (FREEZE §3) |
| 서브젝트 정체성 | `src/number.rs` blob OID / sha256 | `a056f9912ed0dbcc24753a0f1ca18cdba64c41d6` / `5cf1e7e46001fd46860c906d9c353d950632af742cbb7c154049ca22d3925073` (FREEZE §3) |
| 서브젝트 정체성 | `Cargo.toml` sha256 | `51f085a96d8951975aeef57cfa97851325d30f854a559d57de5eb2632c826d34` (FREEZE §3) |
| 서브젝트 정체성 | C7 anchor signatureHash | `48c4dc5b55757f7c444e8a6d0bf5fdaadd10f48791a6dea9df39484db7367851` — `fn parse_line_col(msg: &mut String) -> Option<(usize, usize)>` (error.rs:494, 규약: brace·들여쓰기·개행 없음) (FREEZE §9.4) |
| 증거 정체성 | 런 산출물 sha256 | §6 표 (ACCEPTANCE 표와 일치; 문서화 시점 재해시로 재확인) |

셋은 서로 대체 불가다: 엔진 정체성은 게이트 코드 세대를, 서브젝트 정체성은 판정 대상 상태를, 증거 정체성은 관측 기록 자체를 고정한다.

## 3. Scope

- **범위 안**: probe(런 3)·d1·d2(런 4)의 기계 출력, 상태·볼트 산출물, 사전등록 문서(FREEZE §0–§9, ACCEPTANCE ①–⑦), 선기록 순서 증거, 선출 이력(C3 → C7), 종착 판정 기록.
- **범위 밖**: d3(포스트랜딩 정준 재현 — 랜딩 후에만 실행 가능), PR/머지 본체, C1~C8 어느 후보에 대한 참·거짓 판정, v1 엔진의 기능 확장. 이 문서는 어느 것도 시도하지 않았다.
- 선언된 편차만 포함한다: Cargo.lock 배치(§8 선언, place→verify→remove, 서브젝트 기록 "declared deviation, restored"), probe 후 §9 수정안(선기록), 템플릿 치환(§9.4). 전체 편차 목록 = ACCEPTANCE ⑥ 5항.

## 4. Procedure

실행 절차는 FREEZE §7/§9.3 동결 명령 그대로였다 (요지): per-run lock 프로토콜 `cp inputs/Cargo.lock <subject>/Cargo.lock` → sha256 → 실행 → sha256(in==out) → `rm` → find-based 사전/사후 매니페스트 대조; d1/d2 상태 락은 `jq --slurpfile e inputs/verification_scope.rust_targets.json '.rust_targets += [$e[0]] | .vksRust = 3'`로 조립; `--target`은 full LLBC 이름 셸 인용. 재현 비교는 FREEZE §7 3축(① exit ② lock in==out ③ canonical skReport payload `jq -S .extra` 바이트 동일성).

문서화 시점 재검증 (read-only 관찰, 2026-10-31):

| 점검 | 방법 | 결과 |
|---|---|---|
| preflight | `nim c -r src/gate/runners/agent_preflight.nim` | **exit 0**; verbatim: `[decision-binding] WARN: 47 function(s) missing {.axiomDecision.} pragma — escalation threshold 30 days not yet reached` + `[INFO] logger: [SUCCESS] Agent Pre-flight Guard: Workspace 무결성 검증 통과.` |
| 런 산출물 해시 | `sha256sum` 6 파일 | ACCEPTANCE 표와 전부 일치 (§6 표) |
| C7 signatureHash | error.rs:494 서명 라인 재해시 | `48c4dc5b…7851` 일치 |
| 서브젝트 HEAD | `git rev-parse HEAD` | `8c535a260ce561eaab4111aafc29038eb9f77ff3` 일치 |
| 게이트 코드 인용 | `src/cli/rust_lane_cli.nim:134-161` 재독 | `enumerateFunDeclNames` — all-Ident가 아닌 이름 경로는 `continue`로 등록 제외 확인 |

## 5. Result

### probe (run 3, target `serde_json::number::<impl>::is_f64`)

- exit code: **3** (INVALID_INPUT(NotFound)); stdout 전체 1줄, 원문:

```
[ERROR] action_interpreter_cli: [ERROR] [AXIOM] --target serde_json::number::<impl>::is_f64 resolved to no extraction targets (NotFound or Ambiguous). The rust lane requires exactly one match; 0 matches = NotFound, >1 = Ambiguous. Refusing an implicit verification run on an unresolved target.
```

- 서브젝트 수용 자체는 확인됐다: charon 추출 성공(`state_probe/.axiom/rust-lane/1398235db249fc8b/subject.llbc` 생성), lock sha256 in==out, find-based 사후 매니페스트 == 사전 (FREEZE §9.1).

### d1 / d2 (run 4, target `serde_json::error::parse_line_col`)

- d1 exit **0**, wall 13.241 s (start 1793446239.155085945 → end 1793446252.396510343); d2 exit **0**, wall 13.008 s (start 1793446379.061531827 → end 1793446392.069070280) (ACCEPTANCE ①).
- stdout — d1, d2 공통(바이트 동일, sha256 `9ddc5dbc7b104135a353c3144f1f466e3d7e10c1db7c6f6126f9c4bce59e298d`), 3줄 전부, 원문:

```
[AXIOM][rust-lane] charon pinned='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' measured='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' ok=true
[AXIOM][rust-lane] ledger transport armed (live); repo=Archright/Axiom
[AXIOM][rust-lane] done: verified=0/1 failed=0 unknown=1 error=0
```

- d1 `targets[0]` 원문 (`runs/d1/skreport_payload.json`; schemaVersion `axiom.report.v1`, subjectLane `rust`, charon ok=true pinned==measured, summary `{"failedCount":0,"statusCounts":{"error":0,"failed":0,"unknown":1,"verified":0},"timeoutCount":0,"verified":0,"verifiedRatio":0.0}`):

```json
{
  "name": "serde_json::error::parse_line_col",
  "reason": "producer: LLBC files table pre-validation failed: files[1]: absolute path '.4/experiments/serde-json-claim-2026-10-31/state_d1/.axiom/rust-lane/1398235db249fc8b/charon-target/x86_64-unknown-linux-gnu/debug/build/serde_json/211aa9d180883da9/out/private.rs' (subject-relative POSIX path required)",
  "status": "unknown"
}
```

- d2 `targets[0]` 원문 (`runs/d2/skreport_payload.json`):

```json
{
  "name": "serde_json::error::parse_line_col",
  "reason": "producer: LLBC files table pre-validation failed: files[1]: absolute path '.4/experiments/serde-json-claim-2026-10-31/state_d2/.axiom/rust-lane/1398235db249fc8b/charon-target/x86_64-unknown-linux-gnu/debug/build/serde_json/8b65d3d27583c0f0/out/private.rs' (subject-relative POSIX path required)",
  "status": "unknown"
}
```

- 상태 락: d1·d2 모두 sha256 `0c1f4abca316f8c26a247731cadc1eacc93ace2b49c2f3b55f4eb43909b6004e` (동일); jq 검증 `{"n": 3, "vksRust": 3, "dupPairs": 0, "badHashes": []}`; 심볼 `axiom_rust_probe::add_u8`, `axiom_rust_probe::add_u8_mutant`, `serde_json::error::parse_line_col`; baseline 2항목 `jq -S` diff empty. `vault_d1/`, `vault_d2/`는 비어 있음 (ACCEPTANCE ①).
- 서브젝트 무결성: d1·d2 모두 find-매니페스트 사전==사후 (93 파일, 양쪽 매니페스트 sha256 `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4`), d2 사전 == d1 사전; 종료 시 서브젝트 porcelain empty, Cargo.lock 부재 (ACCEPTANCE ④).
- trajectory envelope (런당 1줄, 원문):

  - d1: `{"ts":"2026-10-31T11:30:51.688Z","phase":"skReport","nodeId":"","detail":"rust subject lane completed","elapsedMs":0,"status":"ssStarted"}`
  - d2: `{"ts":"2026-10-31T11:33:11.371Z","phase":"skReport","nodeId":"","detail":"rust subject lane completed","elapsedMs":0,"status":"ssStarted"}`

- 서명 게이트 / spec-decode 단계는 두 런 모두 출력 한 줄 없었다 — 도달하지 못했다 (ACCEPTANCE ③).

## 6. Evidence

증거 산출물 (sha256 — ACCEPTANCE 표 값; 문서화 시점 `sha256sum` 재해시로 전부 재확인 일치):

| 파일 | sha256 |
|---|---|
| `runs/d1/stdout.log` | `9ddc5dbc7b104135a353c3144f1f466e3d7e10c1db7c6f6126f9c4bce59e298d` |
| `runs/d2/stdout.log` | `9ddc5dbc7b104135a353c3144f1f466e3d7e10c1db7c6f6126f9c4bce59e298d` (d1과 바이트 동일) |
| `runs/d1/skreport_payload.json` | `0604043fdb7ebc277f54f7cb4505b8e5cdc92d96ddc9b8ce93cebb6dc7472f06` |
| `runs/d2/skreport_payload.json` | `edfd70515453e3dda5e8270f0f23ecabfaa6300d14497901d2d322ebb1b2c949` |
| `runs/d1/subject_manifest_pre.sha256` | `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` |
| `runs/d1/subject_manifest_post.sha256` | `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` |
| `runs/d2/subject_manifest_pre.sha256` | `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` |
| `runs/d2/subject_manifest_post.sha256` | `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` |
| `runs/probe/stdout.log` | `9589b119907aeeb1f09f801012abe41cc67e077173098f26eef492469c127a9f` (문서화 시점 재해시) |
| `runs/pre_d1_amendment_timestamps.txt` | `bbb48ae273110932ee22c0fed374ec16531a67797327599c44faeed80778cb0b` |
| `state_d1/logs/ax_prove_trajectory.jsonl` | `21a3977d741eebf8f98ccf75a6179c6647ccf0a1548c9ac8c38de134b20f40d9` (1줄) |
| `state_d2/logs/ax_prove_trajectory.jsonl` | `b53d0d166762dc39204432961bb65b6b44428cd6b6eb527edc22b5342313d77a` (1줄) |

입력·디스커버리 (FREEZE §4 표 + 파일 직접 열람):

- `inputs/Cargo.lock` sha256 `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4`, 47 lock 항목, 10,807 bytes; 직접 의존 itoa 1.0.18, memchr 2.8.3, serde_core 1.0.229, serde 1.0.229, zmij 1.0.23 (FREEZE §4).
- `inputs/dependency_table.json` — `cargo metadata --locked` 정준 투영, 46 패키지 (lock의 47 항목과의 차이는 serde_json의 워크스페이스 멤버+레지스트리 이중 기록).
- `inputs/verification_scope.rust_targets.json` — parse_line_col 항목 (commit `8c535a26…`, module `src/error.rs`, signatureHash `48c4dc5b…7851`, specRef → axiom.specs.json). §9.4에 따라 d1 전에 is_f64 템플릿을 대체; is_f64 항목은 그 어떤 런에도 소비되지 않았다 (타깃은 항상 커맨드라인으로 전달).
- `axiom.specs.json` — 2 키 보유: `serde_json::number::<impl>::is_f64`(C3 기록 유지)와 `serde_json::error::parse_line_col`. 양쪽 post 모두 "the v1 closed spec grammar (result == additive over u8/u32/bool) cannot express …"를 명시하는 **formalization-intent** 선언이다 — 폐쇄 문법으로 표현 불가함을 선언하는 등록이지, 기계가 검증한 사양이 아니다.
- `discovery/` — `discovery_inventory.md` (10,334 B, `09a46109e067aa96cca40ea9b9c7140587d7c089c2bbff06dfc6bb2878f69e0a`), `scan_results.json` (6,185 B, `6dacb9cfb99b815809c1f59b11b5fdf21564dd1a101f0c056b562b757363edca`), `charon_run.log` (249 B, `b1a51d8540b2dfed62e0c7bffe6c838fe538bdfb02c05b67febc8d713468a6aa`), `charon_time.txt` (36 B, `b57789693985dd790c09e25f372d84e1a83a9ba427a050f938957a1c0510d56d`) — 원본 재해시, 사본 바이트 동일 (FREEZE §4).
- LLBC 추출물 (probe·d1·d2 각 `state_*/.axiom/rust-lane/1398235db249fc8b/subject.llbc`; §4 정준 sha256 `f6eff161420fe8fefc4b2e7c5986c8fad5f3b3050cb12dc33b2881d59566f569` — 27 MB, LFS 정책상 저장소 미보존, §7 동결 명령으로 결정적 재생성 가능).

## 7. Classification

### Per-run 분류 (status·reason 원문 그대로)

**probe** (run 3, target `serde_json::number::<impl>::is_f64`):

- status: exit **3** INVALID_INPUT(NotFound) — targets 미생성 (skReport 미발행)
- reason (stdout 유일 1줄, 원문):

```
[ERROR] action_interpreter_cli: [ERROR] [AXIOM] --target serde_json::number::<impl>::is_f64 resolved to no extraction targets (NotFound or Ambiguous). The rust lane requires exactly one match; 0 matches = NotFound, >1 = Ambiguous. Refusing an implicit verification run on an unresolved target.
```

**d1** (run 4, target `serde_json::error::parse_line_col`):

- status: `unknown`
- reason (원문):

```
producer: LLBC files table pre-validation failed: files[1]: absolute path '.4/experiments/serde-json-claim-2026-10-31/state_d1/.axiom/rust-lane/1398235db249fc8b/charon-target/x86_64-unknown-linux-gnu/debug/build/serde_json/211aa9d180883da9/out/private.rs' (subject-relative POSIX path required)
```

**d2** (run 4, target `serde_json::error::parse_line_col`):

- status: `unknown`
- reason (원문):

```
producer: LLBC files table pre-validation failed: files[1]: absolute path '.4/experiments/serde-json-claim-2026-10-31/state_d2/.axiom/rust-lane/1398235db249fc8b/charon-target/x86_64-unknown-linux-gnu/debug/build/serde_json/8b65d3d27583c0f0/out/private.rs' (subject-relative POSIX path required)
```

### 예측 대 실측 — 3회 모두 불일치 (정직한 기록)

| # | 예측 (사전등록) | 실측 | 판정 |
|---|---|---|---|
| 1 | §6 probe 행: exit 0, `unknown`, reason `out-of-subset grammar (fail-closed): <producer reason — predicted signature: Ref (&self)>` | exit **3** INVALID_INPUT(NotFound) | 불일치 |
| 2 | §9.2 d1/d2 행: exit 0 + `unknown` + reason `out-of-subset grammar (fail-closed): <producer reason — predicted: signature Ref input / Adt output>` | exit 0 + `unknown` 일치; reason 클래스 불일치 — 실제 거부는 서명 게이트가 아니라 **producer files-table 사전검증** | 부분 불일치 (reason) |
| 3 | §7 3축: d2/d3 canonical skReport payload가 d1과 바이트 동일 | axis ③ **불일치** — 단일 헝크 차이 (reason 내 런 상대 절대경로) | 불일치 |

실험 전 예측 3회(§6 서명 게이트 예측, §9 수정 후 예측, §7 재현 동일성 예측)가 모두 실제 게이트와 달랐다는 사실 자체가 이 판정의 관측적 토대다.

### Terminal Outcome (아키텍트 판정)

**SCOPE_LIMIT_CONFIRMED** — 근거 3점:

1. 서로 다른 세 개의 경계층(§8: 주소가능성 / files-table 입력계약 / 서명 게이트)이 기계적으로 관측됐고, 어느 층도 실험 전 예측과 달랐다 (위 표 — 예측 3회 모두 불일치).
2. 원인이 환경·provenance·도구 문제가 아니라 **v1의 구조적 한계**로 재실행 불변이다 — d1과 cold d2가 동일 관측을 재현했다 (§8 재현 3축; BLOCKED 요인 없음).
3. **BLOCKED 아니다** — FREEZE §8의 BLOCKED 트리거(offline fetch failure, charon timeout, token procurement refusal, lock in≠out) 어느 것도 발화하지 않았다 (lock in==out 확인, ACCEPTANCE ⑤).

범주 병치 명시: 종착 3-way(VERIFICATION_COMPLETE / SCOPE_LIMIT_CONFIRMED / BLOCKED)는 per-run taxonomy(`verified` / `failed` / `unknown` / `error`)를 **대체하지 않고 병치**된다. d1/d2의 `targets[0].status = "unknown"`은 그대로 유효한 기계 기록이며, SCOPE_LIMIT_CONFIRMED는 그 위에서 캠페인 단위 종착을 선언하는 상위 판정이다. 어느 런도 `verified`로 rewrite되지 않았다.

## 8. Interpretation

### 세 경계층 구조

**층 1 — 주소가능성 (addressability).** `enumerateFunDeclNames` (`src/cli/rust_lane_cli.nim:134-161`)는 fun_decl 이름 경로가 **all-Ident일 때만** 등록한다; `Impl` 세그먼트를 포함하는 경로(예: `serde_json::number::<impl>::is_f64`)는 매칭 공간 밖(unnameable, skip)이다. probe 추출물 실측(FREEZE §9.1): 2,134 fun_decls 중 nameable 152, 그중 이름이 `is_f64`인 것 0 — 수정 탐색 공간(152개 nameable 경로)에 그 심볼이 없으므로 "fix and re-run"으로 코버되지 않는 구조적 비주소가능. 결과: probe exit 3 INVALID_INPUT(NotFound). §8의 `exit 3 … fix and re-run` 행이 다루지 못하는 'unfixable' 경우를 §9.1이 선(先)폐쇄했다.

**층 2 — files-table 입력계약 (실제 거부 지점).** d1/d2 = exit 0 + `targets[0].status="unknown"` + 위 원문 reason. serde_json은 `build.rs`를 보유하고, charon 빌드가 생성하는 build-script 산출물(`out/private.rs`)이 **상태 소유 charon-target 절대경로**로 LLBC `translated.files` 테이블에 기록된다. lane의 사전검증은 files 테이블의 서브젝트-상대 POSIX 경로 요구를 fail-closed로 집행하고, 절대경로 항목에서 거부한다 — reason 원문: `… files[1]: absolute path '…' (subject-relative POSIX path required)`. 실측: probe·d1·d2의 LLBC 모두 151항목 중 `files[1]`만 절대경로 (`files[0]`, `files[2]`+는 `src/lib.rs`, `src/de.rs`, `src/error.rs`, … 상대경로 — ACCEPTANCE ③). 즉 **build.rs 보유 서브젝트는 서명 게이트 도달 이전의 v1 구조적 지원 밖**이다.

**층 3 — 서명 게이트 (예측됐으나 미도달).** §6/§9가 예측한 거부 지점. 실제로는 도달하지 못했다(두 런 모두 시그니처 게이트/spec-decode 출력 없음). 그러나 도달했어도 거부됐을 것이다 — C7 `serde_json::error::parse_line_col`의 LLBC 서명 실측(FREEZE §9.2): **inputs = [Ref(Var, Ty, Mut)], output = Adt**(Option 튜플) — v1 인증 문법(u8/u32/bool 스칼라 파라미터·반환) 밖. `axiom.specs.json`의 spec은 "formalization-intent"(폐쇄 문법으로 표현 불가를 스스로 선언하는 등록)임이 기록되어 있다 — d1의 실제 거부는 files-table 계약에서 발생했지만, C7 서명(Ref/Adt)도 어차피 인증 문법 밖이었다.

### 재현 3축 (d1 vs d2)

| 축 | d1 | d2 | 판정 |
|---|---|---|---|
| ① exit code | 0 | 0 | 동일 |
| ② Cargo.lock sha256 in==out | `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` (in·out 동일) | 동일, in==out | 동일 |
| ③ canonical skReport payload (`jq -S .extra`) | `0604043f…7472f06` | `edfd7051…b1b2c949` | **불일치 — 단일 헝크** |

축 ③의 정직한 기록: 두 canonical payload의 유일한 차이는 `targets[0].reason` 내부의 **런-상대 절대경로**다 — state 디렉터리명(`state_d1` vs `state_d2`)과 charon-target 빌드해시(`211aa9d180883da9` vs `8b65d3d27583c0f0`)의 두 substrings. 원문 diff (ACCEPTANCE ②):

```diff
<       "reason": "producer: LLBC files table pre-validation failed: files[1]: absolute path '.4/experiments/serde-json-claim-2026-10-31/state_d1/.axiom/rust-lane/1398235db249fc8b/charon-target/x86_64-unknown-linux-gnu/debug/build/serde_json/211aa9d180883da9/out/private.rs' (subject-relative POSIX path required)",
>       "reason": "producer: LLBC files table pre-validation failed: files[1]: absolute path '.4/experiments/serde-json-claim-2026-10-31/state_d2/.axiom/rust-lane/1398235db249fc8b/charon-target/x86_64-unknown-linux-gnu/debug/build/serde_json/8b65d3d27583c0f0/out/private.rs' (subject-relative POSIX path required)",
```

- 마스킹 재검증: `state_dN` 치환 후에도 charon-target 빌드해시가 달라 불일치는 남는다 (ACCEPTANCE ②). 이 편차는 위장(마스킹·삭제)하지 않고 그대로 기록했다.
- stdout은 d1/d2 바이트 동일 (sha256 `9ddc5dbc…`); trajectory envelope은 `ts`만 다름; 소요는 각 약 13초(13.241 s / 13.008 s).
- **설계 전제의 반증**: FREEZE §7은 skReport payload가 "timestamps나 paths를 실어주지 않는다"고 전제했다. 이 reason 클래스에서는 payload가 런별 절대경로를 내장한다 — 전제가 이 클래스에서 반증됨을 관찰 사실로 기록한다 (ACCEPTANCE ⑥5). 이는 판정 로직의 결함이 아니라 비교 기준의 전제 수정을 요구하는 관찰이다.

### 선출 이력 요약 (판정 대상 재선택)

원 후보 C3(`is_f64`) → probe exit 3(Impl 비주소가능, 층 1) → d1 실행 전 §9 수정안 선기록 (mtime 순서 입증: FREEZE §9 `20:28:47` < `axiom.specs.json` `20:29:08` < `rust_targets.json` `20:29:14` < d1 시작 `20:30:39` +0900) → C7 `parse_line_col`(error.rs:494, 자유함수, 정확 1매치) 재선출 → d1/d2 실행. sidecar(`axiom.specs.json`)에 parse_line_col 항목 추가, is_f64는 C3 기록으로 유지. 재선출은 기계 관측에 근거했고 사전등록 문서 안에서 폐쇄됐다 (§6/§8 표 원문 보존 + §9 우선 규칙).

## 9. Non-Conclusions

이 섹션이 이 문서의 가장 중요한 내용이다.

- **C1~C8 어느 모순후보도 판정되지 않았다.** 판정에 도달한 심볼은 0이다. serde_json에 대한 버그 주장을 해서는 안 된다.
- **"명제 (P, D)에 대한 반례 확인"이 아니다.** 이번 실행에서 생성·확인된 반례는 하나도 없다 — 반례는 존재하지 않는다 (존재하지 않음이 증명됐다는 뜻이 아니라, 반례 산출이 없었다는 관찰이다).
- **Verified도 Counterexample도 확정되지 않았다.** 종착 3-way 중 VERIFICATION_COMPLETE는 아니다. SCOPE_LIMIT_CONFIRMED는 "한계를 관측했다"는 선언이지 어느 쪽 판정도 아니다.
- `targets[0].status = "unknown"`의 과대해석 금지: 이것은 "판정에 도달하지 못했다"는 기계 표기이지 "안전하다/문제없다"는 뜻이 아니다.
- 이번 실험으로 실제로 입증된 것: (a) 외부 프로젝트(serde_json v1.0.154) 수용 능력의 존재 — charon 추출 성공, lock 프로토콜 준수, 서브젝트 무결성 유지(매니페스트 사전==사후), (b) 그 수용이 막히는 세 경계층의 기계적 관측과 그 한계의 재실행 불변성(cold d2 재현).

## 10. Next Experiment

셋 전부 **별도 후속 과제**다. 이번 실험에서 범위 확장은 시도하지 않았으며, 다음도 이번 결과로부터 열리는 질문일 뿐 이번 캠페인의 소산이 아니다.

1. **build-script 보유 서브젝트의 files-table 상대경로 계약 진화** — 층 2의 계약: build.rs 생성물이 LLBC files 테이블에 기록될 때 상태 소유 절대경로 대신 서브젝트-상대 경로(또는 선언된 경로 클래스)를 요구하도록 producer·검증자 계약을 진화시키는 과제. authority·state transition·failure semantics 정의가 선행해야 한다 (변경 불변조건 프로토콜).
2. **Impl 메서드 주소가능성** — 층 1: `Impl` 세그먼트 포함 이름 경로의 타깃 해석 지원(또는 의도적 비지원의 문서화) 과제. `serde_json::number::<impl>::is_f64`류 심볼의 매칭 공간 편입 여부를 결정한다.
3. **서명 부분집합 확장 (Ref/Adt 등)** — 층 3: `&mut String` 파라미터·`Option<(usize, usize)>` 반환 같은 서명 클래스를 인증 문법에 편입하는 과제. 폐쇄 문법(`result == additive`)의 확장 정의와 함께 별도로 사전등록되어야 한다.

## Landing record

- PR: **#1149** — state MERGED, mergedAt `2026-10-31T12:22:33Z` (`gh pr view 1149 --json state,mergedAt,mergeCommit`); 캠페인 본체(본 문서 + probe/d1/d2 증거) 랜딩.
- merge commit.oid: **`ee87f0a70a8a518e490c74499b5e134ef112ea08`**
- post-landing d3 (pinned merge commit에서의 정준 재현, state_d3/vault_d3, §9.3 명령형): **실행 완료 — 세 축 전부 성립, 정준 재현 확인됨** (2026-10-31, branch `repro/serde-json-claim-2026-10-31` HEAD = merge commit `ee87f0a70a8a518e490c74499b5e134ef112ea08`, fresh `state_d3`/`vault_d3`). 축별 관측:
  - ① exit **0**, wall 12.980 s.
  - ② Cargo.lock in==out sha256 `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4`, 런 후 제거.
  - ③ stdout 3줄 바이트 동일 (d1/d2와 같은 sha256 `9ddc5dbc7b104135a353c3144f1f466e3d7e10c1db7c6f6126f9c4bce59e298d`) + skReport 의미상 동일 — `targets[0].name` `serde_json::error::parse_line_col`·`status` `unknown` 동일, reason 동일 클래스 (producer files-table 사전검증 거부; 전문 원문 `runs/d3/skreport_payload.json`, verbatim):

```
producer: LLBC files table pre-validation failed: files[1]: absolute path '.4/experiments/serde-json-claim-2026-10-31/state_d3/.axiom/rust-lane/1398235db249fc8b/charon-target/x86_64-unknown-linux-gnu/debug/build/serde_json/4bceeb2bfd3e9415/out/private.rs' (subject-relative POSIX path required)
```

  축 ③의 유일 변위는 reason 내부의 런 상대 substrings — state 디렉터리명 `state_d3`와 charon-target 빌드해시 `4bceeb2bfd3e9415` (d1 `211aa9d180883da9`, d2 `8b65d3d27583c0f0`와 상이) — 로, §8에서 이미 기록된 이 reason 클래스의 예고된 정상 변위다. 수반 관측: state 락 sha256 `0c1f4abca316f8c26a247731cadc1eacc93ace2b49c2f3b55f4eb43909b6004e` (6,383 B, d1/d2와 동일), `state_d3/logs/ax_prove_trajectory.jsonl` 929 B (1줄), `vault_d3/` 비어 있음, find-매니페스트 사전==사후 (`diff` empty, 양쪽 sha256 `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4`), 서브젝트 HEAD `8c535a260ce561eaab4111aafc29038eb9f77ff3` 핀 유지, 서브젝트 porcelain empty. **종착 판정(SCOPE_LIMIT_CONFIRMED)은 변경 없다** — d3는 §7 재현 축에서 이 관측의 재실행 불변성을 확정한 것일 뿐이다 (ACCEPTANCE ⑦).
