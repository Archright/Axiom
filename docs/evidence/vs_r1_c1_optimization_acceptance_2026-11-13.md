# VS-R1 & VS-C1 Authority-First 컴파일·런타임 최적화 — 수용 증거 (2026-11-13)

> **종류**: 실행 증거 기록 (acceptance evidence). 목적은 VS-R1(Lean Toolchain Identity 및 파일/바이너리 다이제스트 단일 측정·변조 방어 메모이제이션)과 VS-C1(`hermetic_build` 단일 생성 Authority 일원화 · R6 MISS 자기차단 복구 · HIT 0-write 경로 · 클로저 스탬프 기반 Bootstrap)의 주장·측정·재현 명령과 `main` 착지 결과를 한 문서에 고정하는 것이다.
> **권위**: 본 문서는 기록이며 어떤 판정도 대체하지 않는다. 착지 판정 권위는 GitHub ruleset(`main` #27097366, `axiom-admission-gate` #25218071, `landing-integrity` #23943917)·6대 required checks·merge queue다(`Authority ≠ Adapter`, AGENTS.md §2.3).
> **브랜치**: `workstream/vs-r1-c1-authority-optimization` (base: `main` `c021c33801455a481e05b75c396d95c84bbdc45d`).

---

## 1. 주장 및 Authority 경계 (Claims & Authority Architecture)

| 대상 사실 | 단일 생성 Authority | 하위 소비자 역할 |
|---|---|---|
| 소스 트리 정체성 (`BuildSourceHash`) | `core/utils/build_provenance.nim` (`vs1-tree-hash/1`) | `bin/hermetic_build`, `config.nims`, `bin/ax --check-provenance`가 동일 해시 소비 (`src/generated/`는 입력 집합에서 명시적 제외 — 순환 의존 0) |
| Lean/Lake 바이너리 및 매니페스트 정체성 | `src/verification/obligation/measured_digests.nim` | `(cwd, normalizedPath, POSIX lstat+stat 9필드, racy-window fastHash)` + `stat→readFile→stat` 안정성 검증 후 스레드 내 재사용 (`canonicalLeanKernelCheck`, `measureToolchainBundleFingerprint`, `measureEvaluationImplementationDigests`가 소비) |
| Lean 실행 경로 (`resolveLeanBinaryPath`) | `src/verification/obligation/lean_kernel_boundary.nim` | `AXIOM_LEAN_CMD` 최우선 평가; 미설정 시 `(cwd, PATH, ELAN_HOME, ELAN_TOOLCHAIN, lean-toolchain 다이제스트 2종, lakefile 다이제스트 2종, lakePath)` 키 + 해결된 바이너리의 64-hex 다이제스트 유효성 확인 하에 재사용 |
| `src/generated/build_env.nim` 생성 | **`bin/hermetic_build` 단일 생성자** (`tools/hermetic_build.nim`) | `config.nims`는 읽기 전용으로 일관성(`BuildSourceHash`, `VerifierBuildSourceHash`, 64-hex `VerifierBuildId`, `BuildEnvGitHash`)만 조회하고 직접 파일을 재구성하거나 쓰지 않음 |
| Bootstrap 도구 (`feature_manifest_generator`, `sync_certs`) | `config/integrity.nims` 클로저 해시 스탬프 | 전이적 소스 클로저 + `NimVersion` + 컴파일 플래그 해시(`.axiom/cache/*.srchash`) 일치 시 중첩 `nim c` 없이 기존 바이너리(`ensure`/`--ensure`) 직접 실행; 미스 시 PID-unique 임시 경로 빌드 후 원자적 `mv` |

---

## 2. 변경 표면 (Change Surface)

| 파일 | 표면 등급 | 변경 요약 |
|---|---|---|
| `src/verification/obligation/measured_digests.nim` | `PRODUCT` | `MeasuredFileStat` (`lstat`+`stat` 9필드: `dev, ino, size, mtimeNs, ctimeNs, mode, linkIno, linkMtimeNs, linkCtimeNs`) + 50ms racy-window `fastHash` 검증 + `stat→readFile→stat` 안정성 검사로 `measuredBinaryDigest`/`measuredFileDigest` 통합; `lookupCachedLeanPath`/`storeCachedLeanPath` 및 계측 카운터(`measuredDigestStats`) 제공 (`nimtry` 경고 0건, LCOM=0.0) |
| `src/verification/obligation/lean_kernel_boundary.nim` | `PRODUCT` | `canonicalLeanKernelCheck`의 생 `readFile`+`sha256Hex` 우회 호출 2곳(`leanExePath`, `lakePath`)을 `measuredBinaryDigest`로 일원화; `measureToolchainBundleFingerprint`의 매니페스트 5종을 `measuredFileDigest`로 일원화; `resolveLeanBinaryPath`에 환경·매니페스트 결속 메모 적용 (함수 수 20개 유지, LCOM=0.5684 ≤ 0.60) |
| `tests/unit/test_capture_toolchain_fingerprint.nim` | `PRODUCT` | 10종 변조 및 무효화 회귀 배터리 추가 (15/15 PASS) |
| `tools/hermetic_build.nim` | `CONTROLLED` | Line 13–14의 자기차단(`if getEnv("AXIOM_HERMETIC_BUILDING") == "1": quit(0)`)을 제거하고 `putEnv("AXIOM_HERMETIC_BUILDING", "1")`로 교체하여 `config.nims` 위임 실행 시 정상 동작 보장; `generateBuildEnvPair` 단일 패스화 |
| `config.nims` | `CONTROLLED` | `hermeticPreBuild` 내 `build_env.nim` 직접 쓰기 제거(`bin/hermetic_build` 단일 생성자 위임); `liveSourceHash` 1회 계산; `VerifierBuildId` 전 입력 `envHash` 편입; Full HIT 시 0-write(`mtime`/`inode` 보존), Git-HEAD-only 변경 시 `--materialize`, MISS 시 `bin/hermetic_build` 실행 및 PID-unique 스탬프 갱신 |
| `config/integrity.nims` | `CONTROLLED` | `manifestBootstrap`/`certManifestBootstrap`에 전이적 클로저 콘텐츠 해시 스탬프(`.axiom/cache/*.srchash`) 및 PID-unique 원자적 빌드 도입 |
| `config/vendors.nims` | `CONTROLLED` | DEBT#417 이후 목적 상실(inert)된 `nimcache_leases` 쉘 포크 제거 |
| `data/architecture_debt.json` | `CONTROLLED` | `bin/debt_engine --regen-arch` 정합화 (`debt_engine --validate` 1610/1610 PASS) |
| `config/trusted_writer_set.json` | `CONTROLLED` (`trustSurface`) | `bin/reanchor_pin --ref HEAD --write`로 변경된 클로저 멤버 SHA 재앵커 (멤버십 수 890개 불변) |
| `compliance/policy/secret-scan-baseline.json` | `CONTROLLED` (`trustSurface`) | `origin/main` 전진(`12a9d8d`, PR #1 착지)으로 생성된 `origin/axiom/evidence-cas` 레저의 CAS `evidenceKey` 5건을 `synthetic-hash-or-cas-key`로 트리아지 등록 (§5.1) |

---

## 3. Trust Parity & 10종 변조 배터리 결과 (J1 · J2 · J3 · 5-State)

### 3.1 J1 Semantic Parity & J2 Evidence Equivalence
- **대상**: `make verify-contract-release-e2e-full` (`src/core/orchestrator/orchestrator_api.nim::normalizeMaxWorkers` 증명 + `ax report --json` + `ax cert verify --kernel`)
- **인증서 13-필드 `identityDigest` (`data/trusted/certificates/e57ee9394d16b8dcb8a859eb205f59a55dc3926227dc2250a21448c8d5ebf200.json`)**:
  - 변경 전: `3fbc5d0ddde2e76fc8b6e128becd95d472af97c3f25653d9824e6d3f39008bf9`
  - 변경 후: `3fbc5d0ddde2e76fc8b6e128becd95d472af97c3f25653d9824e6d3f39008bf9` (**바이트 동일**)
- **동일 빌드/입력 반복 실행 시 `ax report --canonical-digest` (`canonicalProjectionHash`)**:
  - Run A: `b84924540077a7676f5208122b8c565dc16f05ac88071ce4d30a5b0b1a4d5d3f`
  - Run B: `b84924540077a7676f5208122b8c565dc16f05ac88071ce4d30a5b0b1a4d5d3f` (**바이트 동일**)
- **커널 재실행 검증 (`bin/ax cert verify --kernel`)**:
  - `[cert] Verify: PASS (kernel re-execution — lean=re-executed, z3=unsat, leanchecker=passed)` (`exit 0`)

### 3.2 VS-R1 10종 변조 및 무효화 배터리 (`tests/unit/test_capture_toolchain_fingerprint.nim`)
명령: `AXIOM_HERMETIC_BUILDING=1 nim c -r --hints:off tests/unit/test_capture_toolchain_fingerprint.nim` → **15/15 PASS (`exit 0`)**

| # | 변조 시나리오 | 관측 결과 | 판정 |
|---|---|---|---|
| 1 | 동일 파일/바이너리 반복 호출 (`<= 1 MiB` 및 `> 1 MiB`) | `misses == 1`, 이후 호출은 `hits`만 증가하며 동일 64-hex 반환 | PASS |
| 2 | 파일 크기 변경 | 메모 즉시 무효화(`misses` 증가) 및 새 SHA-256 반환 | PASS |
| 3 | 파일 내용 + `mtime` 변경 | 메모 즉시 무효화 및 새 SHA-256 반환 | PASS |
| 4 | **동일 크기(`"ABCDEF"` → `"XYZDEF"`, 6B) 인플레이스 덮어쓰기 + 동일 ms 내 `setLastModificationTime`으로 구 `mtime` 복원** | `ctimeNs` 및 racy-window `fastHash`가 변경을 즉시 감지하여 새 SHA-256 반환 | PASS |
| 5 | 원자적 `moveFile`/`rename` 교체 (동일 크기·동일 `mtime`, `ino` 변경) | `ino` 변화 감지로 메모 무효화 및 새 SHA-256 반환 | PASS |
| 6 | `CWD` 변경 (`setCurrentDir(dirA)` → `setCurrentDir(dirB)`) | 상대경로 `"lean-toolchain"` 정체성 재평가 (`digestA != digestB`) | PASS |
| 7 | `"lean-toolchain"` 내용 변경 | `resolveLeanBinaryPath` 메모 및 `measureToolchainBundleFingerprint` 동시 무효화 | PASS |
| 8 | `AXIOM_LEAN_CMD` 환경변수 변경 | 캐시 우회하여 즉시 새 지정 경로 반영 | PASS |
| 9 | `timeoutMs` 변경 (`100_000` vs `200_000`) | `computeBundleDigest` 결과 즉시 변경 | PASS |
| 10 | 매니페스트(`lake-manifest.json`/`lakefile.toml`) 및 로어링 파일(`pnode_to_canon.nim`) 변경 | 해당 파일 `measuredFileDigest` 및 `computeBundleDigest` 즉시 변경 | PASS |

---

## 4. Operational & Performance 측정 증거 (Before vs After)

*(성능 시간 측정 실행과 `strace` 시스템 콜 계측 실행은 추적 오버헤드 분리를 위해 독립 실행함)*

### 4.1 VS-R1 런타임 측정 (`ax report --json` 및 `execution_identity_propagation_test`)

| 지표 | 변경 전 (Baseline) | 변경 후 (VS-R1) | 변화량 / 효과 |
|---|---|---|---|
| `ax report --json` Wall Time (n=5 중앙값) | **260.39 ms** (`260,392 us`) | **189.64 ms** (`189,644 us`) | **−70.75 ms (−27.2%)** |
| `ax report --json` 총 `execve` 호출 수 | 49회 (`lake env which lean` 2회 스폰) | **24회** (`lake env which lean` **단 1회** 스폰) | **−51.0% (경로 탐색 1회 고정)** |
| `ax report --json` 로어링 파일(4종) `openat` 횟수 | 8회 (2회씩 중복 오픈/해싱) | **4회** (파일당 정확히 1회) | **중복 해싱 100% 제거** |
| `ax report --json` 매니페스트 파일 `openat` 횟수 | 14회 | **8회** | **−42.9%** |
| `execution_identity_propagation_test` Wall Time | **14.60 s** (`14,604,362 us`) | **5.27 s** (`5,269,353 us`) | **2.77× 가속 (−9.33 s)** |
| `execution_identity_propagation_test` 120MB `lean` 바이너리 오픈/해싱 | 3회 (매 호출 생 `readFile`+`sha256Hex`) | **1회** (최초 1회 측정 후 메모 재사용) | **대용량 바이너리 중복 해싱 0회** |
| `execution_identity_propagation_test` 로어링 파일(4종) 오픈/해싱 | 16회 (4회 × 4파일) | **4회** (파일당 정확히 1회) | **−75.0% (중복 0회)** |

### 4.2 VS-C1 컴파일/빌드 측정 (`nim c` Warm HIT 및 R6 MISS 자동 복구)

| 지표 | 변경 전 (Baseline) | 변경 후 (VS-C1) | 변화량 / 효과 |
|---|---|---|---|
| Warm `nim c src/cli/version.nim` Wall Time | **17.82 s** (`17,824,811 us`) | **8.47 s** (`8,467,723 us`) | **2.11× 가속 (−9.36 s)** |
| Warm `nim c` 중첩 컴파일러(`nim`) 실행 수 | 3회 (부모 1 + 중첩 `nim c -r` 2) | **1회** (부모 컴파일러만 실행, 중첩 `nim c` **0회**) | **중첩 컴파일 100% 제거** |
| Warm `nim c` 총 `execve` 호출 수 | 71회 | **54회** | **−23.9%** |
| HIT 시 `src/generated/build_env.nim` 나노초 `mtime` & `inode` | 매 실행 덮어쓰기 (`00:44:16.073` → `00:44:39.781`) | **불변** (`00:59:40.186431128`, inode `21262643` 유지) | **0-write 달성** |
| HIT 시 `.axiom/cache/hermetic_env_hash.txt` 나노초 `mtime` & `inode` | 매 실행 덮어쓰기 (inode `22204523` → `22204506`) | **불변** (`00:59:42.008999613`, inode `22204520` 유지) | **0-write 달성** |
| **R6 MISS 복구 (`src/` 수정 후 단독 `nim c` 실행)** | `hermetic_build`가 `quit(0)`으로 조기 종료하여 `SourceCoherence FAIL` (`exit 1`) | `[hermetic] Environment changed (MISS)` → `bin/hermetic_build` 정상 실행 → `bin/ax --check-provenance` **즉시 `OK` (`exit 0`)** | **R6 근본 해결** |

---

## 5. 로컬 필수 게이트 및 회전 핀(Rotation Pin) 검증

| 게이트 / 테스트 | 명령 | 결과 |
|---|---|---|
| Canonical Build & Provenance | `make -f ci/checker.mk ci-compile -j4 && ./bin/ax --check-provenance` | `exit 0` (`AXIOM_PROVENANCE: OK`) |
| Verifier Build Identity | `AXIOM_HERMETIC_BUILDING=1 nim c -r --hints:off tests/unit/test_verifier_build_identity.nim` | `10/10 PASS` (`exit 0`) |
| Contract Preservation (Parallel G1/G2/G4/G6/G7) | `make verify-contract` | `[PASS] g2, g1, g6g4, g7` (`exit 0`) |
| Release E2E Full (`ax prove` + `ax report` + `cert verify --kernel`) | `make verify-contract-release-e2e-full` | `G7 pass (tier=dual-verified status=verified)` (`exit 0`) |
| Performance Regression Gate | `make perf-check` | `[PERF OK] LeanKernelVerification: 0.0% change` (`exit 0`) |
| Debt Engine & Theater Schema | `./bin/debt_engine --validate && python3 tests/ci/test_debt_schema_theater_rule.py` | `1610/1610 passed, 0 failed` (`exit 0`) |
| Layer Enforcement & Negative Liveness | `make check-layer-enforcement check-layer-negative` | `PASS` (`exit 0`) |
| Proof Unit / Reconcile / Epoch / Mirror / Workflow Syntax | `bin/proof_unit_consistency_gate && bin/proof_reconcile_gate && bin/epoch_transaction_gate && make check-merge-admission-cert-mirror check-workflow-shell-syntax` | 전부 `PASS` (`exit 0`) |

---

## 5.1 Main 동기화 및 publication-integrity `secret-scan` 정본 갱신 (2026-11-13)

PR #1 착지(`origin/main` `c021c33` → `12a9d8d`) 직후 `axiom/evidence-cas` 레저 브랜치에 5개의 CAS 레코드(`1378e20b…`, `55df844e…`, `21c9c18a…`, `53f06f99…`, `52c0f719….json`)가 추가되었다. 각 파일의 `"evidenceKey"` 64-hex 값이 gitleaks `generic-api-key` 규칙(line 1, col 87–165)에 매칭되어 `publication-integrity`의 `secret-scan`이 `FAIL (new=5)`로 판정했다.

- **동기화**: `./bin/ax git sync` (승인된 rebase 경로) → `main` `12a9d8d` 위로 리베이스; `bin/reanchor_pin --ref HEAD` `OK no-drift`.
- **트리아지**: 5건 모두 SHA-256 CAS 주소(비밀 아님)이므로 `classification: "synthetic-hash-or-cas-key"`로 `historyFindings`에 **spanFingerprint**(`<file>:generic-api-key:1:1:87:165`) 단위 등록 — baseline은 commit-SHA 독립이므로 레저 append마다 재등록이 필요 없다.
- **로컬 판정 (clean-tree 기준 — `git archive HEAD`로 추출한 트리에서 `gitleaks dir` 실행, CI와 동일 스코프)**:
  - `publication_secret_eval: PASS (history=398 tree=393 baseline=791 new=0)` (`exit 0`)
  - 참고: 작업 트리에는 `build/`(nimcache)와 `.axiom/cache/`가 존재하며 이는 git 추적 대상이 아니므로 CI 스코프(tree=393)와 로컬 미정리 트리 스코프(tree=832)가 다르다. CI 판정은 항상 clean checkout 기준이다.

---

## 6. MUST-T2a 수동 병합 위임 기록 (Pre-Merge Delegation Record)

본 변경은 Tier C checker closure에 속한 파일(`config.nims`, `tools/hermetic_build.nim`, `src/verification/obligation/lean_kernel_boundary.nim`, `src/verification/obligation/measured_digests.nim`)의 git blob SHA를 `config/trusted_writer_set.json`에 재앵커(`bin/reanchor_pin --ref HEAD --write`)하므로 `config/policy/merge_admission.json`의 `trustSurface`를 터치한다.

- **적용 규칙**: `docs/agents/rules_workflow.md` §2.8 `MUST-T1` / `MUST-T2` / `MUST-T2a`.
- **위임 원문 및 일자 (2026-11-13, 운영자 `wintrover`)**:
  - *"목표는 코드 작성 완료가 아니라 실제 운영 상태다. `구현 → 검증 → PR → merge → canonical main/production 실행 → acceptance`를 실제 명령과 관측 가능한 증거로 끝까지 확인하라. 선언, PR 생성, 로컬 테스트, 부분 CI 성공은 완료가 아니다."*
  - *"투두리스트 재정렬하고 백그라운드 병렬 서브에이전트로 모두 진행해. 권한이 필요한 부분은 전면 승인한다."*
- **Executor 기록**: `agent under explicit delegation from wintrover (2026-11-13)`.
- **준수 사항**: `--auto` arming 사용 금지(`MUST-T1`); PR 생성 후 6개 필수 체크(`admission-check`, `bsec-integrity`, `debt-registry-gate`, `generation-acceptance`, `axiom-operational-slice`, `publication-integrity`)가 모두 `success`로 완료된 것을 L1 관측으로 확인한 뒤, 단발 수동 큐 진입 명령 `gh pr merge <N> --merge`만 실행한다.

---

## 7. Canonical `main` 착지 및 프로덕션 수용 (Post-Merge Acceptance)

### 7.1 GitHub 착지 증거 (merge authority = GitHub)

| 항목 | 관측값 |
|---|---|
| PR | **#2 MERGED** (`mergedAt 2026-11-12T18:07:29Z`, `mergedBy wintrover`) |
| merge commit (native MERGE) | `13e1604a89fc4dc29783f2049107de1111f899dc` — parents `bd62a4557d36f6b99f8a2a8d5446bd7488d7ca12` + `71a9fed42a7fbde5b612e78b092e59d2872c3595` (2-parent MERGE, `git rev-list --parents`) |
| `main` tip | `13e1604a89fc4dc29783f2049107de1111f899dc` (`repos/Archright/Axiom/git/ref/heads/main`) |
| Merge Queue | `gh pr merge 2 --merge` → `gh-readonly-queue/main/pr-2-…` `merge_group` 워크플로 **9/9 success**: `admission-gate`, `axiom-operational-slice`, `bsec-integrity`, `debt-registry-gate`, `generation-acceptance`, `landing-integrity`, `observer-manifest-consistency`, `probe-merge-queue`, `publication-integrity` |
| post-merge `main` CI | `axiom-operational-slice` **success** (run `43276548000`, head `13e1604`) — prove → 동일 인증서 커널 replay → verdict/provenance assert → determinism ratchet → observation-reuse contract 포함 |
| `publication-integrity` (dispatch) | `bd62a45` run `43275230893` **success** (선행 실패 `12a9d8d` run `43263885083`는 §5.1의 CAS `evidenceKey` 원인과 동일) |

### 7.2 Canonical `main` 로컬 수용 (실행 명령 + 관측)

실행 위치: `13e1604a89fc4dc29783f2049107de1111f899dc` 체크아웃, clean working tree.

| # | 명령 | 관측 결과 |
|---|---|---|
| 1 | `git rev-list --parents -n 1 HEAD` | 2-parent native MERGE (위 표) |
| 2 | `make -f ci/checker.mk ci-compile -j4` | `exit 0` |
| 3 | `./bin/ax --check-provenance` | `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (vs1-tree-hash/1:-5133378971984752489)` (`exit 0`) |
| 4 | `make verify-contract-release-e2e-full` | `[cert] Verify: PASS (kernel re-execution — lean=re-executed, z3=unsat, leanchecker=passed)`; `G7 pass (tier=dual-verified status=verified cert=data/trusted/certificates/e57ee939….json)`; `✅ verify-contract-release-e2e-full PASSED` (`exit 0`) |
| 5 | `AXIOM_HERMETIC_BUILDING=1 nim c -r tests/unit/test_capture_toolchain_fingerprint.nim` | `Results: 15 passed, 0 failed` (`exit 0`) |
| 6 | `make perf-check` | `[PERF OK] LeanKernelVerification: 0.1% change` (`exit 0`, 상한 5.0%) |
| 7 | `./bin/ax report --json` ×3 + `strace -f -e trace=execve` | wall **0.18 / 0.19 / 0.19 s**; 총 `execve` **26회**; `lake` execve **2회** = `lake env which lean` 논리 실행 **1회**(elan shim + 실툴체인 바이너리) |
| 8 | `git status --short` | 출력 없음 (clean) |

### 7.3 Trust Parity 재확인 (landed commit 기준)

- **J2 Evidence Equivalence**: `git diff --stat c021c33 13e1604 -- data/trusted/` → **변경 0건**. `data/trusted/certificates/e57ee939….json`은 baseline 대비 **바이트 동일**(`git diff --quiet` → `IDENTICAL(bytes)`), `verificationTier=dual-verified`, `status=certGreen`. §3.1의 `identityDigest 3fbc5d0d…`는 `trustCommitId 62034512…` 시점의 journal claim identity이며, 착지 후에도 추적 증거 집합 자체가 불변임을 위 diff가 직접 증명한다.
- **J1 Semantic Parity (결정론)**: 동일 상태에서 `./bin/ax report --canonical-digest` 2회 → `2258bee293dbb698979a500bf64aeaf8ed018869323f9152092f6d5ee9841a7c` **완전 일치**. 이 값은 `canonicalProjectionHash(report proof state)`(`src/cli/report_cli.nim:336-355`)로, 입력 상태가 `ax prove` 실행에 따라 진화하므로 **시점 간 절대값 비교는 동등성 입력이 아니다** — 변경 전/후 코드의 동일-상태 바이트 동일성은 §3.1에서 이미 기록되었다. `--canonical-digest`는 지원 표면(`src/cli/report_cli.nim:332`)임을 확인했다.
- **J3 Cache Soundness**: 재사용 경로의 SHA-256/`executionEpoch` 재검증과 단일 발행 권한은 §1–§3의 변경 표면에서 그대로 유지되며, 위 4·5번 실행이 실제 커널 재실행·변조 배터리 통과로 이를 재확인한다.

### 7.4 잔여 관찰 (범위 밖, 기록만)

- `verify-contract-release-e2e-full` 로그의 `IR pipeline FAIL: calcDynamicTimeoutCore / safeSpeedupRatioCore`(Proof Summary 2/4)는 이번 변경 이전부터 존재하는 엔진 동작이며 G7 판정(`dual-verified`)과 독립이다. 기회적 리팩터링 금지(§0.12)에 따라 이번 범위에서 변경하지 않는다.
