# §1b prove config root 해석 결함→수정 아치 — 기계 검증 증거 (2026-11-08)

> **종류**: 구현·검증 증거 기록. **판정 권위는 기계 관측이며, 이 문서는 그 기록이다.**
> **Date**: 2026-11-08 · **Branch**: `workstream/prove-toml-root-seam` (base `9db1dd5` = main @ PR #17 merge) · **구현 커밋**: `c0fe3bb16bf9b5e3f5ecfc4aa3f32d9b26829b4f`
> **대상**: S2c-blocker — §1b Binary Distribution Contract(`docs/spec/productization_contract.md` §1b) 번들에서 `ax prove`가 엔진 초기화 단계 exit 2로 종료하던 결함. §1b:23(`ax prove` = v1 계약 표면)·§1b:34(번들 자산 — axiom.toml 미동반)·§1b:40(루트 해석 계약) 위반.

---

## §1. 결함 관측 (1차 S2c 관측, 본 PR 직전)

랜딩된 main(`9db1dd5`)에서 조립한 §1b 번들(루트 직접 `ax` + `.axiom_root`)에서:

- `ax capability --json` — **정상**: 양성 exit 0·7 entries(6 EQUIPPED + `SPEC-LIBP2P-VARINT-RT` NOT_EQUIPPED) / 음성(앵커 없는 복제) exit 2 fail-closed.
- `ax prove --project /tmp/s2c-subject --target "libp2p/utils/bytesview.nim::toOpenArray"` (AXIOM_ROOT·AXIOM_READ_TOKEN 제거, AXIOM_STATE_DIR 시드 완료, 서브젝트 핀 `a130a7f32219909bdcda14b7f1e64d0804fc832`) — **엔진 초기화에서 exit 2**. stderr 전문(보존본 `/tmp/s2c-prove-stderr.txt`):

```
[ERROR] action_interpreter_cli: [ERROR] cannot open: /tmp/axiom.toml
[ERROR] action_interpreter_cli: [STACK] syncio.nim(881)          readFile
```

## §2. 원인 분석 (이중, 코드 규명)

1. **toml 탐색 루트의 bin/-레이아웃 가정** — 구현 커밋 이전 `src/cli/axiom_engine.nim:5995`:
   `findRepoRoot(getAppFilename().parentDir.parentDir)`. 소스 트리(repo/bin/ax → repo 루트)를 가정한 2단계 상향. §1b 번들은 `ax`가 **루트에 직접** 배치되므로(§1b:34, SourceCoherence FATAL 방지) 2단계 상향이 번들 루트의 한 단계 위에 착지 → 앵커 워크가 번들 루트의 `.axiom_root`를 놓침 → legacy 폴백(`src/core/utils/repo_root.nim:51` 계열 1단계 상향) → `/tmp`(실행 CWD) → `/tmp/axiom.toml` 미존재 → `readFile` IOError → exit 2. `parentDir.parentDir` bin/-가정은 전 src에서 해당 콜사이트 유일.
2. **선택 설정을 필수로 취급하는 로드** — `loadTomlConfig`(`src/cli/config_loader.nim:56`, `raises:[IOError]`)가 미존재 파일에서 즉시 종료. 그러나 §1b:34 번들 자산 목록에 axiom.toml은 **설계상 없고**(배포 자산이 아님), prove가 toml에서 소비하는 전 필드가 안전 기본값을 가진다(`vault_dir` 기본 `""`, `budget_gas` 기본 `0`, leanstral은 값이 있을 때만 env 세팅 — 구현 커밋 이전 axiom_engine.nim:5998-6015). toml의 `[trust.axiom]`·`[gate.cache]`는 prove 경로 무소비(전 src grep 확인).

§1b:40이 이미 규정하는 루트 해석(AXIOM_ROOT 최우선 → 바이너리 위치 상향 앵커, 첫 앵커 종료)을 구현한 `findRepoRootStrict`가 `src/cli/external_subject_registry.nim`에 존재했으나 **모듈 비수출**이어서 prove의 toml 콜사이트가 접근 불가 — capability 경로는 이 시임을 써서 정상 작동이었다.

## §3. 수정 (구현 커밋 `c0fe3bb`)

| 파일 | 변경 |
|---|---|
| `src/cli/external_subject_registry.nim` | `findRepoRootStrict` **수출**(`:51`) + 모듈 문서 주석에 §1b prove-config 회전이 두 번째 소비자임을 한 줄 추가(`:37`) |
| `src/cli/axiom_engine.nim` | toml 콜사이트 회전(`:5992-6009`): ① `--project` 서브젝트에 axiom.toml가 있으면 서브젝트 루트 우선(기존 동작 보존) ② 아니면 `findRepoRootStrict()`(AXIOM_ROOT → 바이너리 위치 상향 앵커 워크) ③ 해석 실패(트리 밖 앵커 미스) → 빈 경로 → 선택 로드 기본값. CWD 상대 `"axiom.toml"` 폴백 제거·`bin/` 가정 제거. prove(`:6004`)·leanstral(`:6009`) 두 로드를 `loadTomlConfigIfPresent`로 교체 |
| `src/cli/config_loader.nim` | 신규 `loadTomlConfigIfPresent*`(`:62`): 빈 경로·미존재 → 기본(빈) TomlConfig, 존재 → 기존 `loadTomlConfig` 위임. **존재하지만 읽기 실패하는 진짜 IOError는 그대로 발생**(§0.9 — 진짜 I/O 오류 삼킴 금지). 기존 `loadTomlConfig` 본체·시그니처·config_cli·scope_cli 불변. `std/os` import 추가 |
| `tests/unit/test_toml_optional_load.nim` | 신규 유닛테스트 7케이스(§4.2) |
| `data/nimtry_baseline.json`·`data/architecture_debt.json` | 회전 동반 재앵커(S2b `753827a` 선례) — §4.3 |

실행 계약 시맨틱: 소스 트리 실행(getAppDir()=repo/bin → 워크 → repo 루트)은 기존과 동일 파일. 서브디렉터리 실행은 기존 IOError exit 2에서 repo toml 해석으로 개선(§1b:40 정합). 트리 밖 앵커 미스는 카탈로그 read에만 규정된 fail-closed(§1b:40·Q-013)가 아니라 선택 설정 기본값으로 랜딩 — 카탈로그(capability) 경로의 fail-closed는 그대로다.

## §4. 기계 관측 (2026-11-08, 로컬 — 전부 명령→관측→exit)

### 4.1 빌드

```
$ nimble build                          → exit 0
$ bin/ax --version                      → v0.6.0
```

### 4.2 단위테스트

```
$ nim r tests/unit/test_toml_optional_load.nim   → exit 0
  [OK] empty path yields the default (empty) config
  [OK] non-existent path yields the default (empty) config (§1b bundle ships no axiom.toml)
  [OK] existing file is read and parsed (section registry)
  [OK] a present-but-unreadable file raises IOError (fail-closed, not theater)
  [OK] anchor walk: repo root, repo subdir, and the test binary dir resolve to the repo root
  [OK] AXIOM_ROOT env wins, trailing slashes normalized
  [OK] tree-external anchor miss is err (fail-closed)

$ nim r tests/unit/test_external_subject_registry.nim  → exit 1
  34 [OK] / 2 [FAILED] — "six production lanes parse into schema v2 without touching the files",
  "two loads of config/spec produce identical projections (parity-summary determinism)"
```

**사전존재 판별**: clean main 워크트리(`git worktree add /tmp/ax-main-check origin/main --detach` @ `9db1dd5`, 상태 디렉터리 청소 후)에서 동일 명령 → 동일하게 34 [OK] / 2 [FAILED]·exit 1. 본 PR과 무관한 사전존재 실패 — 수정하지 않고 기록(§5).

### 4.3 게이트

```
$ make check-arch   (재앵커 전) → exit 2  — nimtry: 1 new violation not in baseline
  [soc-surface-area] src/cli/axiom_engine.nim:5877 runAxiomEngineCli spans 155 SLOC (max 50)
$ bin/nimtry src/ --diff-baseline     → New: 1 / Resolved: 1 / Stable: 4258
$ bin/nimtry src/ --update-baseline   → exit 0 (Baseline updated with 4259 violations — 1 fingerprint swap 156→155, 순수 개선)
$ make check-debt   (재앵커 전) → exit 2  — architecture_debt entry[5](axiom_engine)·entry[13](config_loader) canonical hash stale
$ bin/debt_engine --regen-arch        → exit 0 (Updated 2 entries)
$ make check-arch   (재앵커 후) → exit 0  (✅ No architecture violations)
$ make check-debt   (재앵커 후) → exit 0  (1574 checks passed · Metric evaluation 5 PASS 0 DRIFT · All debt validation checks passed)
```

재앵커는 게이트 우회가 아니라 S2b(`753827a`)가 동일 파일 편집 시 밟은 정규 경로 — 위반 총량 4259 불변·신규 부채 0·부채 총계 감소 없음(156→155 SLOC는 라인 수 순 감소의 지문 반영). main 워크트리에서 check-arch → exit 0("No architecture violations")으로 재앵커 필요성이 본 수정 유발임을 확인.

### 4.4 §1b 번들 아치 (전부 fresh /tmp/s2cf-* 경로)

```
$ CH="$(nimble path checksums | head -1)"
$ nim c --hints:off --skipParentCfg --skipProjCfg --path:src --path:tools --path:"$CH" \
    -o:bin/bundle_tool tools/release/bundle_tool.nim                    → exit 0
$ AXIOM_ROOT="$PWD" bin/ax --check-provenance
  AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (7417021610359126117) → exit 0
$ bin/bundle_tool assemble --repo-root "$PWD" --binary bin/ax \
    --expected-binary-sha256 6f13bcb5323a2359b825610280c7e82565d024be04f618fb33ea2074b9824bf0 \
    --version v0.6.0 --source-commit 9db1dd512ad8757d3459a44e2890b00ca4187787 \
    --build-sha 9db1dd512ad8757d3459a44e2890b00ca4187787 --out-dir /tmp/s2cf-release-assets
  → exit 0  (bundleSha256 2fe988b36621c43a96b200af884d19fe7f23de229f8f7816e1d108ac0d1f5033,
             payload: ax + 18 tracked inputs)
$ bin/bundle_tool verify --dir /tmp/s2cf-release-assets --extract-to /tmp/s2cf-bundle \
    --repo-root "$PWD" --expect-version v0.6.0 --expect-source-commit 9db1dd… --expect-build-sha 9db1dd… \
    --run-binary
  → exit 0  (SHA256SUMS·manifest↔bundle↔binary 결속·§1b 레이아웃·트리 동치·runtime v0.6.0 전 pass)
```

### 4.5 capability 회귀 (수정 무관 시임의 보존)

```
$ cd /tmp && env -u AXIOM_ROOT /tmp/s2cf-bundle/axiom-v0.6.0-linux-x86_64/ax capability --json
  → exit 0 · 7 entries: 6 EQUIPPED + SPEC-LIBP2P-VARINT-RT NOT_EQUIPPED  (1차 관측과 동일)
$ cd /tmp && env -u AXIOM_ROOT /tmp/s2cf-bare/ax capability --json   (앵커 없는 복제)
  → exit 2  "[AXIOM] ax capability: committed catalog unavailable (fail-closed): catalog root
     unresolved (fail-closed): AXIOM_ROOT is unset and no .axiom_root/axiom.toml anchor found
     from \"/tmp/s2cf-bare\" — a tree-external binary must set AXIOM_ROOT (productization
     contract §1b, Q-013)"  (fail-closed 보존)
```

### 4.6 prove — 수정의 핵심 증명 (결함→수정 아치)

서브젝트: 1차 관측이 남긴 `/tmp/s2c-subject` 재사용(실행 전 핀 `a130a7f32219909bdcda14b7f1e64d0804fc832`·porcelain 빈 출력 재확인). 상태: fresh `/tmp/s2cf_state`(`/tmp/s2cf-bundle/axiom-v0.6.0-linux-x86_64/data/verification_scope.lock` 시드)·vault `/tmp/s2cf_vault`.

```
$ mkdir -p /tmp/s2cf_state/data /tmp/s2cf_vault
$ cp /tmp/s2cf-bundle/axiom-v0.6.0-linux-x86_64/data/verification_scope.lock /tmp/s2cf_state/data/
$ cd /tmp && env -u AXIOM_ROOT -u AXIOM_READ_TOKEN \
    AXIOM_STATE_DIR=/tmp/s2cf_state AXIOM_PROVE_VAULT_DIR=/tmp/s2cf_vault \
    /tmp/s2cf-bundle/axiom-v0.6.0-linux-x86_64/ax prove \
    --project /tmp/s2c-subject --target "libp2p/utils/bytesview.nim::toOpenArray"
  → exit 1  (VERIFICATION_FAILURE)
```

관측된 엔진 완주·판정(정본 기대 = bytesview 계약 §6 인수기준, `docs/spec/nim_libp2p_bytesview_slice_contract.md:139-150` — exit 1은 "확정 disproof, pass 아님"):

```
[INFO] axiom_engine: external subject registry parity summary: entries=7 … mismatches=1
[INFO] axiom_engine: --target filter: 1 node(s) match 'libp2p/utils/bytesview.nim::toOpenArray'
[INFO] ir_pipeline_runner: [ce-replay] bvSliceLenActual — replay agreed; PROPOSITION_DISPROVED payload assembled (17 records)
[ERROR] loop_driver:   [1/1] libp2p/utils/bytesview.nim::toOpenArray — failed
[INFO] axiom_engine: phase-13: vault manifest synced — 6 entries → /tmp/s2cf_vault/manifest.json
[WARN] axiom_engine: canonical run accounting: contestedCount=0 ∨ unsatisfiedCount=1 ⇒ GateVerdict=FAIL (fail-closed; see reportJson.runOutcome)
[Depth 1/1] Checking: bytesview.nim::toOpenArray... [FAILED]
```

trajectory(`$AXIOM_STATE_DIR/logs/ax_prove_trajectory.jsonl`의 `run_result` 이벤트):

```json
{"canonicalRunDigest":"294180890d20a35a46eb17a3b3d50bed8cb651f7bc581b25470532c91c44b590",
 "runAccountingDigest":"a8b56f0a9be3645377ce3a8e8d1e5129ba268d8c308f7eefa3d676e94367899d",
 "runOutcomeDigest":"d9b254d4d834cea34e2aed3c4e3986e5308d0588f648fc102c24e60ab2a354e9",
 "gateVerdict":"FAIL","verdict":"FAIL","basis":"NONE"}
```

**아치 성립**: 동일 서브젝트·동일 번들 레이아웃·동일 환경에서 `cannot open: /tmp/axiom.toml` exit 2(§1) → `exit 1 VERIFICATION_FAILURE`·`verdict=FAIL`·`[ce-replay] replay agreed; PROPOSITION_DISPROVED payload assembled (17 records)`(본 절) — S2c-blocker가 §1b 계약 내 결과 산출로 복귀. 어휘 참고: "BUG_FOUND"의 실측 산출물 표기는 `PROPOSITION_DISPROVED`(확정 disproof = 서브젝트 버그 발견)와 `GateVerdict/verdict=FAIL`이다. 정직 기록: stdout은 0바이트(리포트는 stderr 표시·state/vault 기록으로 산출 — emitJson 표면은 본 PR 범위 밖 관찰로 §5 기록).

## §5. 범위 밖 관찰 (Follow-up 후보 — 본 PR 미수정)

1. **`parseTomlConfig` 값-저장 사전존재 결함** — `src/cli/config_loader.nim:53-54`: `var section = result.mgetOrPut(...)`가 Nim 2.2.10에서 테이블을 **복사**해 `section[key] = …` 돌연변이가 버려진다(마이크로 실측: var-할당 형태 propagates=false, 직접 색인 형태 propagates=true). 결과: 섹션 헤더는 등록되나 키/값이 저장되지 않음 — clean-origin root 커밋(`938a49e`)부터 존재. prove 소비 필드는 전부 기본값이라 실영향 0(번들 검증 결과와 무관), 본 PR 시임 검증은 섹션 레지스트리 판별로 수행. `[trust.axiom]` 등 다른 소비자의 의도된 값 로딩이 항상 기본값이었을 수 있음 — 후속 조사 권장.
2. **`test_external_subject_registry.nim` 사전존재 실패 2건** — §4.2: clean main에서 동일 재현. 본 PR 무관.
3. **`report_cli.nim:436` 계열 legacy `findRepoRoot`(CWD 기반)** — 전 src 58곳의 개발·게이트 표면. 번들(고객) 경로에서의 `ax report` 루트 해석은 미관측 — §1b 정합 후보로 기록만 함.
4. **prove emitJson stdout 0바이트** — §4.6. 표시는 stderr·산출물은 state/vault·판정은 exit 코드로 전달되는 형태로 관측됨. 계약 문서상 report JSON 방출 표면의 정합은 별도 관찰 과제.

## §6. Zero-Footprint 단언

- 서브젝트 `/tmp/s2c-subject` git porcelain: **pre 0 dirty entries / post 0 dirty entries**(prove 실행 전후).
- 서브젝트 HEAD: pre `a130a7f32219909bdcda14b7f1e64d0804fc832` = post `a130a7f32219909bdcda14b7f1e64d0804fc832` (불변).
- prove의 모든 기록은 `AXIOM_STATE_DIR`(/tmp/s2cf_state)·`AXIOM_PROVE_VAULT_DIR`(/tmp/s2cf_vault)에 한정 — 서브젝트 트리 무기록.
