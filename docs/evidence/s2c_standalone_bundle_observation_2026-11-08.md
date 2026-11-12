# S2c 무소스·무토큰 자립 번들 수용 관측 — 기계 검증 증거 (2026-11-08, 재관측)

> **종류**: 수용 관측(acceptance observation) 기록. **판정 권위는 기계 관측이며, 이 문서는 그 기록이다.**
> **Date**: 2026-11-08 · **Branch**: `workstream/s2c-standalone-bundle-observation` (base `2c48285d` = main @ PR #20 merge — 발행 기대 base `c82e36aa` = PR #23 merge의 직계 자손, §5.3)
> **관측 대상**: §1b Binary Distribution Contract(`docs/spec/productization_contract.md` §1b) 번들이 **소스 트리·토큰 없이**(AXIOM_ROOT·AXIOM_READ_TOKEN 제거) 스스로 루트를 해석해 `capability`·`prove` 전 제품 표면을 산출하는지 — PR #23(toml 루트 해석 §1b 회전) 랜딩 후 main 전체에서의 클린 수용 관측.
> **선행 관측 참조**: 1차 관측(결함 발견)·수정 구현 관측(실패→통과 아치) — `docs/evidence/prove_toml_root_bundle_seam_2026-11-08.md`. 본 문서의 모든 값은 새로 실측했다(재사용 값 없음).

---

## §1. 관측 계약

관측 기준은 §1b Binary Distribution Contract의 다음 조항이다(`docs/spec/productization_contract.md` §1b):

- **배포 자산**: 번들 tar.gz = `ax`(루트 직접 배치) + `config/spec/` + `data/verification_scope.lock`·`data/baseline.json`·`data/bug_attribution/` + 루트 앵커 `.axiom_root` — axiom.toml은 미동반.
- **루트 해석**(§1b:40): `AXIOM_ROOT` env 최우선 → 미설정 시 바이너리 위치에서 상향 `.axiom_root`/`axiom.toml` 앵커 탐색(첫 앵커 종료). 트리 밖 앵커 미스는 카탈로그 read fail-closed(Q-013).
- **상태**: `AXIOM_STATE_DIR` 지정(시드는 `$AXIOM_STATE_DIR/data` 우선 탐색).
- **exit 5-state 무변경**: `ax prove`의 확정 disproof는 exit 1(VERIFICATION_FAILURE) — DISPROVED→FAIL 매핑은 고객 워크플로우 어댑터 소관.

판정 양성 기준(1차·수정 관측에서 확정된 기대치): capability 양성 exit 0·7 entries(6 EQUIPPED + `SPEC-LIBP2P-VARINT-RT` NOT_EQUIPPED) / capability 음성 exit 2 fail-closed / **prove exit 1(VERIFICATION_FAILURE)** — 실제 결함 발견(toOpenArray slice 계약 disproof)이므로 exit 1이 이 관측의 성공 결과다 / Zero-Footprint: 서브젝트 트리 pre/post 불변.

## §2. 환경

| 항목 | 값 |
|---|---|
| 관측 시각 | 2026-11-08 21:35–21:44 KST (12:35–12:44 UTC) |
| SOURCE_SHA | `2c48285d0121c04b4c447d2551652d8952bd431e` (main @ PR #20 merge) |
| 기대 base 검증 | `git merge-base --is-ancestor c82e36aab25a7642d84ccdfd4f2f0d7511ca8ac7 2c48285d0121…` → PR #23 merge가 직계 조상(수정 포함 확인). §5.3 경위 |
| BIN_SHA (bin/ax) | `300589531e1755da172cb795ec95c4165bbcfe6d9ccc7c466a30de93b1f12895` (12,442,184 bytes) |
| bundleSha256 | `8579affce23470c8c0030a280a852e176d3274d4215c911663e9ab1812f54bce` |
| 번들 경로 | `/tmp/s2c2-release-assets/axiom-bundle-v0.6.0-linux-x86_64.tar.gz` (4,583,605 bytes) · 추출 `/tmp/s2c2-bundle/axiom-v0.6.0-linux-x86_64/` |
| manifest.json | `axiom.release-bundle.manifest.v1` · version `0.6.0` · tag `v0.6.0` · platform `linux-x86_64` · sourceCommit=buildSha=`2c48285d…` · binarySha256=`3005895…` · bundleSha256=`8579affc…` |
| 번들 루트 목록(관측) | `ax` · `.axiom_root` · `config/spec/` 7종(base36_sizing_relational, nim_libp2p_bytesview_slice, nim_libp2p_varint_roundtrip, nim_stew_base32_rem, nim_stew_base36_cout, nim_stew_base36_sidecar, toml_d2_agent) · `data/` 3종(`baseline.json`, `bug_attribution/`{SPEC-B36-COUT, SPEC-LIBP2P-BV-SLICE}, `verification_scope.lock`) · `LICENSE`·`LICENSES/`·`THIRD-PARTY-NOTICES.md` |
| 서브젝트 | `Archright/nim-libp2p` @ `a130a7f32219909bdcda14b7f1e64d0804fc832` (`/tmp/s2c-subject`, 1차 관측 동일 핀 재사용·§4.6 pre 검증) |
| 무토큰 환경 | `env -u AXIOM_ROOT -u AXIOM_READ_TOKEN` · `AXIOM_STATE_DIR=/tmp/s2c2_state` · `AXIOM_PROVE_VAULT_DIR=/tmp/s2c2_vault` |

## §3. 기계 관측 (전부 명령→관측→exit, 2026-11-08 로컬)

### 3.1 브랜치

```
$ git fetch origin                                        → 2c48285 (c82e36a..2c48285 main)
$ git log origin/main..workstream/s2c-standalone-bundle-observation
  → (빈 출력 — 0커밋 선도 확인)
$ git switch workstream/s2c-standalone-bundle-observation && git reset --hard origin/main
  → HEAD의 현재 위치는 2c48285입니다
$ git rev-parse HEAD → 2c48285d0121c04b4c447d2551652d8952bd431e
```

### 3.2 빌드

```
$ nimble build                            → exit 0 (140.9s; C 경고는 LTO 노이즈)
$ bin/ax --version                        → v0.6.0 (첫 줄), exit 0
$ sha256sum bin/ax                        → 300589531e1755da172cb795ec95c4165bbcfe6d9ccc7c466a30de93b1f12895
```

### 3.3 bundle_tool 컴파일 (CI 동일 플래그)

```
$ nim c --hints:off --skipParentCfg --skipProjCfg --path:src --path:tools \
    --path:"$CH" -o:bin/bundle_tool tools/release/bundle_tool.nim
  → exit 0  ($CH = nimble path checksums → checksums-0.2.2-6357ab195e…)
```

### 3.4 provenance + assemble + verify (fresh `/tmp/s2c2-*`)

```
$ AXIOM_ROOT="$PWD" bin/ax --check-provenance
  → AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (-1704019420050468118)
  → exit 0

$ bin/bundle_tool assemble --repo-root "$PWD" --binary bin/ax \
    --expected-binary-sha256 "$BIN_SHA" --version v0.6.0 \
    --source-commit "$SOURCE_SHA" --build-sha "$SOURCE_SHA" --out-dir /tmp/s2c2-release-assets
  → [BUNDLE_TOOL] OK — §1b bundle assembled (determinism self-check passed)
  → bundleSha256: 8579affce23470c8c0030a280a852e176d3274d4215c911663e9ab1812f54bce
  → payload: ax + 18 tracked inputs (.axiom_root + config/spec(7) + data + licenses)
  → exit 0

$ bin/bundle_tool verify --dir /tmp/s2c2-release-assets --extract-to /tmp/s2c2-bundle \
    --repo-root "$PWD" --expect-version v0.6.0 \
    --expect-source-commit "$SOURCE_SHA" --expect-build-sha "$SOURCE_SHA" --run-binary
  → [BUNDLE_TOOL] tree-equality: bundle payload == repo tracked §1b inputs (byte-exact, set-exact)
  → [BUNDLE_TOOL] runtime: ./ax --version == v0.6.0 (executed at bundle root)
  → [BUNDLE_TOOL] PASS — SHA256SUMS, manifest↔bundle↔binary binding, §1b layout verified, tree equality, runtime
  → exit 0
```

### 3.5 무소스 자립 실측 — capability (CWD=/tmp, `env -u AXIOM_ROOT`)

**(a) 양성 — 번들 루트에서:**

```
$ /tmp/s2c2-bundle/axiom-v0.6.0-linux-x86_64/ax capability --json
  → {"axiomVersion":"v0.6.0","capabilities":[
       SPEC-LIBP2P-VARINT-RT NOT_EQUIPPED (body-carry),
       SPEC-B36-SIDECAR EQUIPPED, SPEC-B36-COUT EQUIPPED,
       SPEC-B36-RELATIONAL EQUIPPED (beta-composition),
       SPEC-B32-REM-RANGE EQUIPPED (term-splice),
       SPEC-TOML-D2-AGENT EQUIPPED (constructed-gate),
       SPEC-LIBP2P-BV-SLICE EQUIPPED (arithmetic-law)]}
  → exit 0   — 7 entries = 6 EQUIPPED + 1 NOT_EQUIPPED ✓
```

**(b) 음성 — 앵커 없는 복제본(/tmp/s2c2-bare, ax만 복사):**

```
$ /tmp/s2c2-bare/ax capability --json
  → [AXIOM] ax capability: committed catalog unavailable (fail-closed): catalog root unresolved
    (fail-closed): AXIOM_ROOT is unset and no .axiom_root/axiom.toml anchor found from
    "/tmp/s2c2-bare" — a tree-external binary must set AXIOM_ROOT (productization contract §1b, Q-013)
  → exit 2   — fail-closed ✓
```

### 3.6 무토큰 prove 실측 — nim-libp2p (본 관측의 핵심)

시드: `verification_scope.lock` → `/tmp/s2c2_state/data/`. 실행(출력은 `2>&1` 병합 캡처 — 스트림 분리 관찰은 본 관측 범위 밖):

```
$ cd /tmp && env -u AXIOM_ROOT -u AXIOM_READ_TOKEN \
    AXIOM_STATE_DIR=/tmp/s2c2_state AXIOM_PROVE_VAULT_DIR=/tmp/s2c2_vault \
    /tmp/s2c2-bundle/axiom-v0.6.0-linux-x86_64/ax prove \
    --project /tmp/s2c-subject --target "libp2p/utils/bytesview.nim::toOpenArray"
  → exit 1  (VERIFICATION_FAILURE) ✓
```

관측된 엔진 완주·판정 발췌(bytesview 계약 §6 인수기준 — exit 1 = 확정 disproof·서브젝트 버그 발견):

```
[INFO] axiom_engine: external subject registry parity summary: entries=7 … mismatches=1
[INFO] axiom_engine: --target filter: 1 node(s) match 'libp2p/utils/bytesview.nim::toOpenArray'
[INFO] ir_pipeline_runner: [ce-replay] bvSliceLenActual — replay agreed; PROPOSITION_DISPROVED payload assembled (17 records)
[ERROR] loop_driver:   [1/1] libp2p/utils/bytesview.nim::toOpenArray — failed
[INFO] axiom_engine: phase-13: vault manifest synced — 6 entries → /tmp/s2c2_vault/manifest.json
[INFO] axiom_engine: done: verifiedRatio=0.0000, verified=0/40
[WARN] axiom_engine: canonical run accounting: contestedCount=0 ∨ unsatisfiedCount=1 ⇒ GateVerdict=FAIL (fail-closed; see reportJson.runOutcome)
[Depth 1/1] Checking: bytesview.nim::toOpenArray... [FAILED]
```

저널 `run_result` 이벤트(`/tmp/s2c2_state/logs/ax_prove_trajectory.jsonl`, ts `2026-11-08T12:43:05.942Z`):

```json
{"event":{"type":"run_result"},
 "canonicalRunDigest":"294180890d20a35a46eb17a3b3d50bed8cb651f7bc581b25470532c91c44b590",
 "runAccountingDigest":"a8b56f0a9be3645377ce3a8e8d1e5129ba268d8c308f7eefa3d676e94367899d",
 "runOutcomeDigest":"d9b254d4d834cea34e2aed3c4e3986e5308d0588f648fc102c24e60ab2a354e9",
 "gateVerdict":"FAIL","verdict":"FAIL","basis":"NONE",
 "universeDigestRef":"34cf28ba1e051d3913d4b590c07d5c3d31e10e0ca7455a9989fdb32b57269caa"}
```

(원문 라인은 `ts`·`phase:skRunAccounting`·`status:ssStarted` 등을 포함한 JSONL 1행이며, 위는 판정 필드 추출본 — 전체 구조 관측: digest 4종·gateVerdict·verdict·basis는 `extra` 아래.)

상태(`ax_proof_state.json`): `runOutcome` = `{planComplete:true, executionComplete:true, verificationComplete:false, verdict:"FAIL", basis:"NONE", gateVerdict:"FAIL"}` · `verificationOutcome:"UNSATISFIED"` · `claimOutcome:"clDisproved"` · `canonicalRunDigest` = 저널과 동일(`2941808…`). vault manifest(`/tmp/s2c2_vault/manifest.json`, 6 entries): `libp2p/utils/bytesview.nim::toOpenArray` → `certRed`(smCLI), `bvSliceLenActual`(PROPOSITION_DISPROVED 산출) → `certZ3Candidate`, 나머지 4 항목은 파이프라인 확산 fail(`certRed`)·candidate 혼합 — prove 대상 노드의 판정은 toOpenArray certRed 단일 정본. VSR 저널(`vsr_ledger.jsonl`): `{"ts":"2026-11-08T12:43:05Z","vsr":"0.0000","vkd":"0.0000","verified":0,"total":40,"delta":0}`.

**결정론 교차검증**: `canonicalRunDigest`·`runAccountingDigest`·`runOutcomeDigest` 3종이 PR #23 증거 문서(`prove_toml_root_bundle_seam_2026-11-08.md` §4)의 독립 관측과 **동일**하다 — 상이한 base(9db1dd5+c0fe3bb vs 2c48285)·상이한 번들·상이한 상태 디렉터리에서 동일 서브젝트·동일 타깃에 동일 판정·동일 digest 산출(§0.2 Deterministic 재확인).

어휘 참고(§0.11): "BUG_FOUND"의 실측 산출물 표기는 `PROPOSITION_DISPROVED`(확정 disproof = 서브젝트 버그 발견)와 `GateVerdict/verdict=FAIL`이며, 본 관측에서 전부 재현됐다.

## §4. Zero-Footprint 단언 (pre/post)

| 시점 | HEAD | `git status --porcelain` | `sha256sum libp2p/utils/bytesview.nim` |
|---|---|---|---|
| pre (prove 직전) | `a130a7f32219909bdcda14b7f1e64d0804fc832` | 빈 출력 (0 dirty) | `b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee` |
| post (prove 직후) | `a130a7f32219909bdcda14b7f1e64d0804fc832` | 빈 출력 (0 dirty) | `b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee` |

prove의 모든 기록은 `AXIOM_STATE_DIR`(/tmp/s2c2_state)·`AXIOM_PROVE_VAULT_DIR`(/tmp/s2c2_vault)에 한정 — 서브젝트 트리 무기록·불변 ✓.

## §5. 경위

### 5.1 1차 관측 → 결함 발견 (오늘 아침)

S2c 1차 관측에서 §1b 번들 prove가 엔진 초기화 단계 exit 2(`cannot open: /tmp/axiom.toml`)로 종료하는 결함을 발견 — 원인은 toml 탐색 루트의 `bin/`-레이아웃 가정(`parentDir.parentDir`) + 선택 설정을 필수로 취급하는 로드. 전문: `docs/evidence/prove_toml_root_bundle_seam_2026-11-08.md` §1–§2.

### 5.2 수정 → PR #23 MERGED

회전(`findRepoRootStrict` §1b:40 시임 + `loadTomlConfigIfPresent`) 구현 커밋 `c0fe3bb` — 실패(exit 2)→통과(exit 1) 아치를 기계 관측으로 기록(같은 문서 §3–§4). PR #23 `workstream/prove-toml-root-seam`이 **MERGED** — merge commit `c82e36aab25a7642d84ccfd4f2f0d7511ca8ac7` (2026-11-08 12:09:38Z).

### 5.3 본 재관측 — base 이동 (정직 기록)

작업 발행 시점 검증 base는 `c82e36aa`(12:26:36Z fetch)였다. 실행 시점(12:35Z fetch) origin/main은 `2c48285d`로 전진 — PR #20 "Publication integrity: generalize trust-surface runner and legacy repo comments"가 12:34:22Z에 auto-merge 랜딩했다(4파일: workflow 주석 2·`src/cli/merge_cli.nim` 주석 1·`config/trusted_writer_set.json` 해당 핀 갱신 1 — prove/capability/bundle 경로 미접촉, diff로 검증). `c82e36aa`는 `2c48285d`의 직계 조상(`merge-base --is-ancestor` true — §2)이므로 PR #23 수정은 관측 base에 포함된다. "랜딩된 main 전체에서의 클린 수용 관측"이라는 목적에 따라 현재 main 값 `2c48285d`를 base로 관측을 수행했다.

### 5.4 재관측 판정

1차(결함 발견)·수정 관측(수정 PR 내 아치)에 이어, **랜딩된 main 전체**에서 무소스·무토큰 자립 번들이 전 기대치를 재현했다: capability 양성 exit 0·7 entries / 음성 exit 2 fail-closed / prove exit 1 VERIFICATION_FAILURE(반례·17-record payload·FAIL 판정·digest 3종) / Zero-Footprint 불변. 발행 기대치와의 유일한 차이는 base SHA(§5.3)이며, 이는 기대 base가 포함된 main 전진이지 기대치 미달이 아니다.

## §6. 착지

PR: `workstream/s2c-standalone-bundle-observation` → main. 본 문서 커밋(증거 문서만 — 빌드 산출물 `bin/ax`·`bin/bundle_tool`은 커밋 제외) 후 PR 생성, 즉시 `gh pr merge --auto --merge --match-head-commit "$(git rev-parse HEAD)"`로 auto-merge 무장(수동 merge 금지 — merge authority는 GitHub, §2.3). merge SHA·랜딩 상태는 최종 보고서에 기록한다(정본 = GitHub).
