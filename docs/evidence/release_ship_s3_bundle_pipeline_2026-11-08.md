# release-ship §1b 바이너리 배포 파이프라인 구현 — 기계 검증 증거 (2026-11-08)

> **종류**: 구현·검증 증거 기록. **판정 권위는 기계 관측이며, 이 문서는 그 기록이다.**
> **Date**: 2026-11-08 · **Branch**: `workstream/release-ship-bundle` (base `5e740d7e` = main @ PR #14 merge)
> **대상**: Phase 6 S3 — §1b Binary Distribution Contract(`docs/spec/productization_contract.md` §1b)의 출하 파이프라인: assemble-bundle·attest-bundle 잡 신설 + publish 잡의 Archright/axiom-cli cross-repo 발행 확장.
> **범위 밖**: 첫 실제 릴리즈 발행(운영자가 S2b 런딩 후 workflow_dispatch로 실행). 본 슬라이스는 파이프라인 역학의 로컬 재현 검증까지.

---

## §1. 변경 파일 (3)

| 파일 | 변경 |
|---|---|
| `tools/release/bundle_tool.nim` | 신규 — §1b 조립·검증 단일 도구(Nim). Language Ban(`src/gate/runners/language_ban_gate.nim` — tools/ 신규 `.sh` FAIL; `src/policy/python_shell_exemptions.nim` CLOSED)에 따라 bash 초안 2종은 폐기하고 Nim 정경로로 구현. 초안은 untracked 상태에서 삭제(커밋 이력 없음) |
| `.github/workflows/release-ship.yml` | 잡 2종 신설(assemble-bundle·attest-bundle) + publish cross-repo 확장 + validation-only-assert 단언 확장 (§5) |
| `docs/evidence/release_ship_s3_bundle_pipeline_2026-11-08.md` | 본 문서 |

## §2. bundle_tool 계약

`assemble`(필수 플래그: `--repo-root --binary --expected-binary-sha256 --version --source-commit --build-sha --out-dir`):
- nimble 버전 == 태그 재단언(§1b, verify-metadata 게이트와 동일 규칙의 지역 재단언)
- 바이너리 sha256 결속(L2 빌드 체인) + tracked §1b 입력(`git ls-files` 9경로) dirty 거부(`git diff --quiet HEAD -- <paths>`)
- **조립 2회 바이트 cmp**(동일 환경 결정성 자기검증) — tar(`--sort=name --owner=0 --group=0 --numeric-owner --mtime='@0' --format=gnu`) → plain 파일 → gzip(`-n -9`) 2단계, 각 exit 독립 검증(gzip 출력은 셸 리다이렉션으로 직접 파일 기록 — 프로세스 stdout 문자열 캡처는 바이너리 손상, 실측)
- 산출: `axiom-bundle-<tag>-linux-x86_64.tar.gz` + `manifest.json`(스키마 `axiom.release-bundle.manifest.v1`, 고정 키 순서, 타임스탬프 무삽입) + `SHA256SUMS`(tar.gz+manifest 2자산)

`verify`(`--dir --extract-to` 필수; 선택 `--repo-root --expect-version --expect-source-commit --expect-build-sha --run-binary --attestation-bundle`) 8단계:
①manifest 스키마·필드 ②SHA256SUMS 재검증 ③manifest↔bundle 바이트 결속 ④tar 목록 정적 레이아웃(§1b: 단일 최상위 `axiom-<tag>-linux-x86_64/`, **ax 번들 루트 직접 배치 — `bin/` 서브트리 명시 거부**, `.axiom_root`, LICENSE·LICENSES/·THIRD-PARTY-NOTICES.md, config/spec≥1, data 3종) ⑤해제+바이너리 sha256 결속+config/spec JSON 유효성 ⑥`--repo-root` 트리 완전 동치(집합·바이트) ⑦`--run-binary` 번들 루트 `./ax --version` == 태그 ⑧`--attestation-bundle` 오프라인 `gh attestation verify --bundle … --repo Archright/Axiom --signer-repo Archright/Axiom`.

fail-closed(exit 1)·사용법 오류(exit 2). 검증 로직의 단일 구현을 릴리즈 빌드 측과 고객측이 공유(극장 금지: 느슨한 사본 없음).

## §3. 기계 관측 (2026-11-08, 로컬 — worktree `/tmp/ax-s3` @ `5e740d7e`)

**컴파일** (workflow 컴파일 스텝과 동일 명령 — verify-metadata의 release_version_gate 컴파일 패턴):

```
$ CH="$(nimble path checksums | head -1)"
$ nim c --hints:off --skipParentCfg --skipProjCfg \
    --path:src --path:tools --path:"$CH" \
    -o:/tmp/bundle_tool tools/release/bundle_tool.nim
→ exit 0
```

**양성 — assemble** (bin/ax = `nimble build` 산출, sha256 `f1788a7499ea94f47873318a5d90544d37e82ad12e09234c82576f41f3e4eade`, nim 2.2.10):

```
$ /tmp/bundle_tool assemble --repo-root /tmp/ax-s3 --binary /tmp/ax-s3/bin/ax \
    --expected-binary-sha256 f1788a7499ea… --version v0.6.0 \
    --source-commit 5e740d7e4c78… --build-sha 5e740d7e4c78… --out-dir /tmp/s3-assets
[BUNDLE_TOOL] OK — §1b bundle assembled (determinism self-check passed)
bundleSha256: 25e099d98e1c81ff8b1e2cc54c09af26b6f99742c3bf4815131ef6d646deb5b0
version: v0.6.0 (axiom.nimble=0.6.0) · payload: ax + 18 tracked inputs
→ exit 0
$ gzip -t <bundle> → exit 0
```

**양성 — verify** (전수: 결속·레이아웃·트리 동치·실실행):

```
$ /tmp/bundle_tool verify --dir /tmp/s3-assets --extract-to /tmp/s3-extract \
    --repo-root /tmp/ax-s3 --expect-version v0.6.0 \
    --expect-source-commit 5e740d7e4c78… --expect-build-sha 5e740d7e4c78… --run-binary
[BUNDLE_TOOL] tree-equality: bundle payload == repo tracked §1b inputs (byte-exact, set-exact)
[BUNDLE_TOOL] runtime: ./ax --version == v0.6.0 (executed at bundle root)
[BUNDLE_TOOL] PASS — SHA256SUMS, manifest↔bundle↔binary binding, §1b layout verified, tree equality, runtime
→ exit 0
```

**번들 레이아웃 실측** (tar -tzf, 30 엔트리 = 최상위 1 + 파일 19[ax 포함] + 디렉터리 10): 최상위 `axiom-v0.6.0-linux-x86_64/` 단일 — `ax`(루트 직접) · `.axiom_root` · `LICENSE` · `LICENSES/`(4) · `THIRD-PARTY-NOTICES.md` · `config/spec/`(7문서) · `data/verification_scope.lock` · `data/baseline.json` · `data/bug_attribution/`(2). manifest 실측: version `0.6.0` / tag `v0.6.0` / platform `linux-x86_64` / sourceCommit=buildSha=`5e740d7e…` / binarySha256 `f1788a7499ea…` / bundleSha256 `25e099d98e1c…`.

**음성 6종 — 전부 exit 1 (fail-closed)**:

| # | 조작 | 관측 메시지(요지) | rc |
|---|---|---|---|
| neg1 | bundle tar.gz 1바이트 변조 | sha256 mismatch … (SHA256SUMS re-verification) | 1 |
| neg2 | manifest.json 해시 필드 변조 | sha256 mismatch for 'manifest.json' (SHA256SUMS re-verification) | 1 |
| neg3 | ax → `bin/ax` 재배치(자산 해시 재결속 후 — 해시 축 통과 상태로 레이아웃 위반만 심음) | §1b: ax not directly at bundle root | 1 |
| neg4 | `--expect-version v9.9.9` | expected version 'v9.9.9' != manifest.tag 'v0.6.0' | 1 |
| neg5 | tracked §1b 입력 dirty(`data/baseline.json` 개행 추가, assemble) | bundle input paths have uncommitted modifications | 1 |
| neg6 | nimble 버전 0.6.0→0.6.1 치환, assemble `--version v0.6.0` | axiom.nimble version '0.6.1' != release version '0.6.0' | 1 |

neg5/neg6 조작 후 원본 복구 — `git status --porcelain` tracked 변경 0(§3 시점 tree = base + 본 슬라이스 diff만).

## §4. 게이트 관측 (본 슬라이스 diff 상태)

| 게이트 | 관측 | exit |
|---|---|---|
| `bash tools/ci/validate_workflow_shell.sh` | PASS — run blocks checked=257 failures=0 lane-guard violations=0 (신설 컴파일 run 블록 2종 포함) | 0 |
| `bash tools/ci/git_access_scan.sh` | PASS — 0 history/parent access on depth-1 CI paths | 0 |
| `bash tools/ci/verify_trusted_writer_set.sh` | PASS — contents:write holders == TrustedWriterSet(무변경; 신설 잡은 `contents: read` + attest-bundle만 `id-token/attestations: write`) | 0 |
| YAML parse (python3 yaml.safe_load) | OK — jobs 9: freeze → verify-metadata → full-l2 → assert-l2-scope → verify-binary → assemble-bundle → attest-bundle → publish → validation-only-assert | 0 |
| `make check-debt` | PASS — Checks: 1573 total, 1573 passed, 0 failed · Freshness: fresh | 0 |
| `make check-arch` (nimtry) | **FAIL — 사전 존재(base 상속)**: `[soc-surface-area] src/cli/axiom_engine.nim:4729 function runVerificationWaves spans 79 effective SLOC (max 50)` 1건. base `5e740d7e` 원본 worktree에서 동일 게이트 재실행 — **동일 위반 1건으로 동일 실패** (make rc≠0). 본 슬라이스 diff는 `.nim` 파일 1종(bundle_tool.nim)만 추가하며 위반 0 추가(양쪽 실행 모두 신규 위반 = 동일 1건). 본 PR이 고칠 범위 밖 — 기록만 남긴다 | ≠0 |
| `make check-repository-surface` | 커밋 후 관측 — §7 | — |

## §5. release-ship.yml 변경 요약

- **assemble-bundle** (needs: 전 5종 + 전부 success; `contents: read`+`actions: read`): checkout(frozen sha) → download ci-bootstrap-artifacts → libpcre3 설치 → `setup-axiom-toolchain`(B-restore만 — `cache-save-enabled: 'false'`, `cache-build-source: frozen_sha`) → `nim c -o:/tmp/bundle_tool`(도구 소스 = 체크아웃 트리; freeze ② 바인딩으로 frozen SHA == github.sha) → assemble 스텝(BUILD_SHA==TARGET_SHA·artifact bin/ax sha256==ci manifest·`--check-provenance` 재단언 후 `/tmp/bundle_tool assemble`) → `/tmp/bundle_tool verify`(--repo-root 전수 + --run-binary) → upload `release-bundle-assets`.
- **attest-bundle** (needs +assemble-bundle; `contents: read`+`id-token: write`+`attestations: write`): checkout(github.sha) → download 자산 → setup-axiom-toolchain + 컴파일(워크플로 ref 트리) → `actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8 # v4.2.2`(SHA 핀) → `gh attestation download` → `/tmp/bundle_tool verify --attestation-bundle …`(고객측 경로: `--bundle` + `--signer-repo Archright/Axiom` 핀) → upload `release-bundle-final`.
- **publish** 확장: needs/if에 assemble·attest 추가; peel-assert 뒤 — download release-bundle-final → `actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510 # v3.3.0`(신규 시크릿 `AXIOM_CLI_RELEASE_APP_ID`/`AXIOM_CLI_RELEASE_PRIVATE_KEY`, owner Archright, repositories axiom-cli, contents:write) → cross-repo 4단계: ① axiom-cli 기존 release/tag 404 단언(clobber 금지, 5xx는 fail-closed) ② POST /repos/Archright/axiom-cli/releases(body에 provenance·검증 절차·해시 기록) ③ `gh release upload` 자산 4종 ④ readback(자산 4개 존재 + octet-stream 재다운로드 sha256 결속). 부분 실패 의미론: immutable releases — 절대 자동 삭제 없음, 수동 조정(주석 명시).
- **validation-only-assert**: assemble-bundle·attest-bundle `skipped` 단언 추가.

## §6. 자격 증명 조사 (§2.4 준수 — 파일시스템·환경·시크릿 값 스캔 없음; 출처 = 저장소 워크플로 선언·ADR-0024)

- 기존 시크릿(선언 기준): `RELEASE_AUTHORITY_APP_ID`/`RELEASE_AUTHORITY_PRIVATE_KEY`(Axiom 발행 App — ADR-0024 In Scope #8 "Axiom 핀"이라 cross-repo 재사용 불가), `DIAG_APP_*`, `CI_ROUTER_APP_*`, `DEPENDABOT_APP_*`, `REARM_APP_PRIVATE_KEY`, `AXIOM_READ_TOKEN`(cross-repo 읽기 전용), `SUBJECT_REPORT_TOKEN`.
- **axiom-cli 쓰기 권한 시크릿 부재 → 신규 프로비저닝 필요(운영자 단계)**: GitHub App `axiom-cli-release-authority`(Contents: read & write, Archright/axiom-cli에만 설치) 생성 → release-authority environment 스코프 시크릿 2종 등록. 워크플로는 선언적으로 소비만 — 시크릿 부재 시 잡 실패 = fail-closed(조용한 우회 없음).

## §7. §1b 대비 미구현분·한계 (과장 금지)

1. cross-repo 발행 시크릿 미프로비저닝(§6 — 운영자: App 생성→설치→environment 시크릿 등록).
2. 첫 실제 발행은 범위 밖 — 운영자가 S2b 랜딩 후 workflow_dispatch 실행(이 문서의 검증은 파이프라인 역학의 로컬 재현).
3. freeze NO-OP(동일 tag+SHA 재디스패치)는 downstream 전부 skip → axiom-cli 누락분 자동 재발행 경로 없음(수동 조정 — 워크플로 주석에 명시 기록).
4. tar.gz 컨테이너의 환경 간(tar/gzip 버전 차이) 바이트 재현은 미주장 — 결정성 주장은 동일 환경 내(2회 조립 cmp). 페이로드 결속 권위는 manifest `binarySha256`/`bundleSha256`(도구 헤더에 명시).
5. 현재 main 바이너리는 S2b(런타임 시임) 이전 상태 — 본 검증은 파이프라인 역학(조립·해시·manifest·`./ax --version`)만 입증. 단 `findRepoRoot` 상향 탐색은 현존하여 번들 루트에서 `./ax --version` 실측 동작(§3).
6. attestation 서명은 CI OIDC 필요 — 로컬 재현 불가. gh CLI 인터페이스만 실측: `gh attestation verify --bundle` 모드에서도 owner/repo 플래그 그룹 필수("at least one of the flags in the group [owner repo] is required"), `gh attestation download`는 CWD에 `sha256-<digest>.jsonl` 기록(출력 경로 플래그 없음), `--signer-repo` 존재. 종단간 서명·검증은 첫 CI 실행에서 관측한다.
7. 대상 저장소 실측(2026-11-08 `gh repo view Archright/axiom-cli`): PUBLIC, default main, immutable releases 활성, 릴리즈 0건 — 첫 발행 전제 확인.

## §8. 착지

PR `workstream/release-ship-bundle` → main. 커밋 후 `make check-repository-surface` 재관측(base policy 판정: `release-ship.yml` CONTROLLED MODIFY, `tools/release/bundle_tool.nim`·본 문서 defaultClass PRODUCT) 결과는 본 슬라이스 최종 보고에 기록.
