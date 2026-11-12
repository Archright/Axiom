# CI Epoch Record — publication-integrity nim-scope toolchain 재사용 (epoch pi-toolscope)

> **성격**: AGENTS.md §2.5(CI Epoch Cutover Protocol) 단계 1–3 — **FREEZE / RECORD / TOMBSTONE**. 변경 = `.github/actions/setup-axiom-toolchain`에 `provision-scope: nim` 변형 추가 + `publication-integrity.yml`의 6개 평가 호출자를 그 변형으로 전환. 목적은 **도구 획득 비용만** 제거하는 것이며, 검증 의미(스캔 대상·판정 로직·증거 스키마·required checks)는 전부 불변이다. §2.6(변경 불변조건)에 따라 authority·state transition·failure semantics·proof를 아래에 고정한다.
> **작성일**: 2026-11-12 (KST).
> **작업 브랜치**: `workstream/pi-toolscope` (clone-first — AGENTS.md §2.7).
> **결정 바인딩**: AGENTS.md §2.5·§2.6·§0.12 · `docs/spec/ci_optimization_tcb_judgments.md` §3.2/§3.5(같은 커밋). 선례: [epoch_record_pi_shard_2026-11-10.md](epoch_record_pi_shard_2026-11-10.md) · [ci_toolchain_scope_2026-09-30.md](ci_toolchain_scope_2026-09-30.md).

---

## 1. FREEZE (AGENTS.md §2.5 단계 1)

| 항목 | 값 |
|---|---|
| freeze tag (의도) | `ci-frozen-2026-11-12-pi-toolscope` (annotated) — 대상 commit **`681d130489fa73b2c4744bbedbee32b0d2d92f25`** (= `origin/main` tip at drafting, 실측) |
| 태그↔커밋 일치 | `git rev-parse ci-frozen-2026-11-12-pi-toolscope^{commit}` == `681d1304…` — 생성 후 실측으로 확정한다 |
| frozen workflow blob | **`bb06468484d2dced6187d7116104acb4cd06abcc`** (`git rev-parse origin/main:.github/workflows/publication-integrity.yml`, 554줄) |
| frozen action blob | **`7110cc66980b3074e60458273fe91980956c5b7e`** (`git rev-parse origin/main:.github/actions/setup-axiom-toolchain/action.yml`) |
| rollback 기준 | 위 두 blob — 복구 시 정확히 이 내용으로 되돌린다 (단일 revert PR) |

### 1.1 배포본 = 로컬 기준선

`gh api repos/Archright/Axiom/actions/workflows/publication-integrity.yml` → id **414024007**, state `active`. 로컬 `origin/main` blob은 554줄이며 이는 현행 배포본의 샤딩 세대와 동일하다(2026-11-10 epoch `bf96c07d…` 착지분). **로컬 HEAD와 배포본의 불일치는 본 epoch에서 관측되지 않았다** — 최적화 대상이 실제 운영 코드와 동일함을 전제로 한다.

## 2. RECORD (단계 2)

### 2.1 변경 요약 (본문 4파일 + CI가 강제한 라이선스 귀속 1건)

| 파일 | 변경 | blob (전 → 후) |
|---|---|---|
| `.github/actions/setup-axiom-toolchain/action.yml` | 1,142 → **1,154줄**. ① `nim-version` 입력 신설(default `2.2.10`) ② nim scope 키 = `axiom-a-nim-${RUNNER_OS}-${RUNNER_ARCH}-nim${nim-version}-${gcc_fp}-${glibc_fp}-${script_hash}` ③ nim scope 경로 = `~/.nimble` + `~/.choosenim` + `~/.local/bin` (`~/.elan`만 제외) ④ **restore 관측 스텝**(requested/primary/matched key 로그) ⑤ **non-exact discard 스텝**(`cache-hit != 'true'` → 스코프 디렉터리 `rm -rf`, `~/.local/bin`은 `$RUNNER_TEMP`로 격리) ⑥ nim scope = nim/z3/jq만 설치·검증, elan/Lake probe 스킵 ⑦ **Nim-scope verification stamp**(`$RUNNER_TEMP/.axiom-nim-toolchain-verified`) ⑧ **save authority 스텝**(표식/락/runtime 3분기) — save `if:`가 이 출력만 참조 ⑨ 미지 scope **fail-closed** | `7110cc6` → `d0dd690` |
| `.github/workflows/publication-integrity.yml` | 554 → **608줄**. 6개 호출자(secret-scan·license-scan·dependency-scan·provenance·sbom·publication-integrity)에 `provision-scope: nim` + 근거 주석. `license-scan-shards`는 toolchain 미사용이라 제외. 잡 id·needs·판정 스텝·아티팩트 이름 **무접촉** | `bb06468` → `ac90161` |
| `docs/spec/ci_optimization_tcb_judgments.md` | §3.2에 nim 네임스페이스/경로/키 결속, §3.5에 "restore-keys 0건 ≠ exact-only" + non-exact 폐기 의미(디렉터리 삭제 vs `~/.local/bin` 격리) 명문화 | — → `27b20eb` |
| `compliance/provenance/license-attribution.yml` | 새 증거 파일의 `json_8.RULE` 경로 토큰 매칭을 정확 (file, atom) 쌍으로 등재(§2.9 #4) | — → `61ea1d0` |

### 2.2 trust binding 불변 선언 (평가기·정책·판정 표면 0접촉)

| 요소 | 상태 |
|---|---|
| 6개 평가기 소스 (`tools/ci/publication_{secret,license,dependency,sbom,report}*.nim`, `publication_provenance_validator.nim`) | **무변경**. import 전수 확인: `std/[json, options, os, parseopt, strutils]`(+`osproc`) + `core/*` + `tools/ci/publication_*` — **lean/z3/nimble 의존 0건**. `provenance_validator`의 `osproc`는 `git -C <root>` 호출(§:98-102)이며 러너 기본 제공 |
| 정책 6종 (license-policy·security-policy·provenance-policy·secret-scan-baseline·source-origin·license-attribution) | **무변경** |
| 액션 핀 | `actions/cache/restore@55cc8345…`(v6.1.0)·`actions/cache/save@55cc8345…` — 기존 핀 재사용, **신규 핀 0건** |
| ruleset required 6 contexts | **무변경**. ruleset **26996019**, contexts = admission-check·bsec-integrity·debt-registry-gate·generation-acceptance·axiom-operational-slice·publication-integrity. `merge_queue` MERGE/ALLGREEN, `bypass_actors` 없음 |
| 스캔 대상·샤드·프로세스·명령행 | **무변경** — license-scan의 크기-그리디 2-분할·`--processes 4`·스테이징 단일 루트 스캔 그대로 |
| 차원 보고서 artifact (`publication-report-*`) | **존속** — 이름·스키마·retention 불변 |

**두 변경 파일 모두 `config/policy/merge_admission.json` trustSurface 32경로에 포함된다** (`.github/actions/setup-axiom-toolchain/**`, `.github/workflows/publication-integrity.yml`) → Axiom auto-merge 대상이 아니며 **MUST-T2 수동 레인**이다. 본 PR 본문에 운영자 1회성 `gh pr merge <N> --merge` 대행 위임(`--auto` 금지)을 기록한다.

### 2.3 기준선 실측 (변경 전 — 런 ID 명시)

**기준선 런 42980750324** (merge_group, conclusion `success`) — 잡별 소요 초:

| 잡 | 초 |
|---|---|
| license-scan-shards (0) | 807 |
| license-scan-shards (1) | 660 |
| secret-scan | 119 |
| dependency-scan | 121 |
| provenance | 107 |
| sbom | 103 |
| license-scan (병합·판정) | 101 |
| publication-integrity (aggregator) | 103 |
| **합** | **2,121** |

**비용 원장 (최근 10런 평균, job-min/run)** — required-gate 시간의 지배 항:

| 워크플로 | job-min/run | 비중 |
|---|---|---|
| publication-integrity | **40.0** | required-gate 합계의 **~73%** |
| axiom-operational-slice | 7.5 | |
| repository-surface | 2.6 | |
| debt-registry-gate | 2.0 | |
| bsec-integrity | 1.4 | |
| generation-acceptance | 1.2 | |

**A-레이어 복원 실측 비용** (본 슬라이스가 제거하려는 것, 기준선 런 42980750324 job 130390334312 로그 타임스탬프): full 페이로드 **1,160MB (1,216,667,161 B)**, restore 스텝 **31.7s**(07:37:09.13→07:37:40.87), a-verify 0.4s, B restore 0.7s, Lake probe 포함 functional probe **8.7s**, apt 7.7s → **setup 합계 44.6s**. nim scope는 `~/.elan`(full 페이로드의 지배 성분)을 제외하고 Lake probe를 실행하지 않는다. **실측 확정(§4.3)**: nim 페이로드 197,797,057 B, HIT setup 스텝 평균 **14.0s** (기준선 동일 스텝 평균 60.3s). B-레이어는 88MB 0.7s로 무시 가능.

**캐시 저장 사용량**: 3,861,681,066 B (~3.86GB) / 10GB 기본 한도.

### 2.4 외부 authority·공급자 사실 (공식 문서 + 실측, 재조회 불필요)

| 사실 | 출처·상태 |
|---|---|
| 캐시 매칭 순서 = exact(key+version) → **primary key의 prefix match** → restore-keys → default branch 재시도 | GitHub Docs "Cache key matching" — **확정** |
| `cache-hit` = exact만 `'true'`, 부분 일치 `'false'`, **완전 미스는 unset** | actions/cache v6.1.0 소스 — **확정** |
| `cache-matched-key`는 restore 액션 출력에만 존재(combined `actions/cache`는 `cache-hit`만) | v3.2.0+ / v6.1.0 — **확정** |
| cache version hash = sha256(paths + compression + salt) → **paths가 다르면 cross-hit 불가** | 소스 — **확정**. nim scope(`~/.choosenim`+`~/.local/bin`)와 full(4경로)은 구조적으로 교차 복원 불가 |
| PR 캐시는 merge ref 스코프 → 그 PR 재실행만 복원. **PR 런은 default/base branch 캐시를 읽을 수 있다** | GitHub Docs — **확정** |
| **merge_group 런의 캐시 스코프는 공식 문서 침묵 → UNKNOWN.** merge_group 런의 HIT를 "main 시드 재사용"의 증거로 쓰지 않는다 | — **UNKNOWN(정직 기록)** |
| 7일 미사용(마지막 access 기준) 제거, 저장소당 10GB, 초과 $0.07/GB-month, LRU eviction | GitHub Docs — **확정** |
| 캐시는 GitHub가 서명·검증하지 않는다 | GitHub Docs — **확정** |
| job 단위 **분 올림** 후 합산. Linux 2-core x64 = **$0.006/min**. self-hosted compute 무료 | GitHub Docs — **확정** |
| 포함량은 분이 아니라 **USD 크레딧**(Enterprise $300 ≈ 50,000분). 49,511분/$297.07은 크레딧 소진액이며 **현금 청구 여부 UNKNOWN** | `GET /orgs/Archright/settings/billing/actions` → **403**(PAT 권한 밖) |

### 2.5 nim scope 계약 (본 epoch가 신설하는 실행 어댑터)

| 항목 | 값 |
|---|---|
| 키 | `axiom-a-nim-${RUNNER_OS}-${RUNNER_ARCH}-nim${nim-version}-${gcc_fp}-${glibc_fp}-${script_hash}` |
| 경로 | `~/.nimble` (nimble 패키지 폐쇄) + `~/.choosenim` (nim toolchain 루트) + `~/.local/bin` (z3 4.13.3, jq 1.7.1). `~/.elan`만 제외 |
| 키 결속 | RUNNER_ARCH + nim 버전 → arch/버전 변경은 **새 캐시 세대**. `nim-version` 변경 시 arm64 tarball sha256 핀 재핀 필요(불일치 = fail-closed) |
| exact 판정 | `cache-hit == 'true'` 단일. 그 외(부분 일치·미스)는 **복원물 폐기 후 네이티브 설치** |
| 사용 권한 | exact-hit **그리고** fingerprint verify 통과(`nim --version`, `compiler/ast.nim` 존재, z3/jq 버전)일 때만 |
| 저장 권한 | run-local 표식 `$RUNNER_TEMP/.axiom-nim-toolchain-verified` — 캐시 경로 **밖**. 표식은 verify 통과 후에만 생성되고 save 스텝이 재확인. **저장 권한 ≠ 사용 권한** |
| 단일 writer | A-save는 잡당 1회, 첫 save 승리. 동일 키 동시 save는 플랫폼이 거부(`cache entry already exists`) → `continue-on-error` |
| full/runtime 키 | **레거시 형태 유지** — arch를 추가하면 1.16GB full 페이로드가 fleet-wide 무효화되므로 무이득. nim scope만 arch/버전 결속 |
| script_hash | 본 변경은 `script_hash`를 바꿔 **모든 A/B 키를 1회 무효화**한다(헤더 계약). 착지 후 첫 런은 전부 MISS, 시드 후 HIT를 관측한다 — 첫 런은 acceptance 집계에서 제외 |

### 2.6 로컬 검증 (본문 커밋 전, 워킹트리 실측)

| 검증 | 결과 |
|---|---|
| `nim c --nimcache:/tmp/nc_tcb -o:/tmp/tcb_judgments tools/ci/tcb_judgments.nim` | **exit 0** |
| `/tmp/tcb_judgments selftest` | **12 passed, 0 failed**, exit 0 |
| `--judgment cache-manifest --workflow action.yml` | **exit 0 (PASS)** — COVERAGE-GAP 2건(nimcache, .axiom/cache)은 report-only |
| YAML `safe_load` (2파일) | **OK** — publication-integrity 584줄 |
| 6개 호출자 `provision-scope` 실측 | 전부 `nim` |
| 6개 평가기 import 전수 | 전부 stdlib + in-repo, lean/z3/nimble 0건 |

### 2.7 비용 산식 (기존 보고서 수치 정정)

기존 보고서의 "6 잡 × 25–40s 절감 → 월 1,200 job-min ≈ $7"는 산술적으로 재현되지 않는다. 정정:

- 잡당 40s 절감 가정 → **6 × 40 = 240s/런**
- 1일 6런 × 30일 = 180런/월 → **240 × 180 / 60 = 720 job-min/월**
- 720 × $0.006 = **$4.32/월** (Linux 2-core hosted 단가, 분 올림 전)

$7/1,200 job-min은 400s/런 절감을 함의하므로 **과대 추정**이다. 또한:

1. job은 **분 단위 올림** 과금이므로 잡별 절감이 60s 경계를 넘지 못하면 청구 분은 줄지 않는다.
2. 포함량은 USD 크레딧이므로, 크레딧 내 소진이면 절감은 **현금이 아니라 포함량 여유**다. 49,511분/$297.07(포함 $300) 조건에서는 월말 잔여 크레딧이 늘어날 뿐이다.
3. GHEC-hosted와 Ubicloud(self-hosted)는 과금 모델이 다르다 — self-hosted는 Actions 분 과금 0. 본 슬라이스의 절감분은 **runner 위임 여부와 무관하게 runner-min을 줄인다**는 사실로만 주장하고, 현금 절감은 플랜·빌링 확인 후 별도 판정한다.

측정 지표는 5개로 분리 기록한다: ①A-레이어 복원 스텝 시간 ②전체 잡 실행 시간 ③총 러너 사용 시간 ④실제 청구/크레딧 ⑤캐시 저장량.

### 2.8 관측된 blocker (범위 밖, 기록)

dependabot PR 런 43031425898·43031418856에서 `setup-axiom-toolchain`의 `apt-get install libpcre3`가 DNS 실패(`azure.archive.ubuntu.com`)로 364s 재시도 후 **exit 100** → license-scan·aggregator 동시 적색. **libpcre3는 B-레이어 provenance probe가 실행하는 `bin/ax`의 동적 링크에 필요**하므로 nim scope에서 제거하지 않는다(제거 시 B 폐기 → 콜드 빌드). 본 epoch는 이 blocker를 수정하지 않으며, nim scope는 apt 스텝을 그대로 유지한다.

### 2.9 감사·실측이 확정한 수정 (초안 → 착지본)

초안 작성 후 (a) 자기 감사, (b) `tools/ci/tcb_judgments.nim` 판정, (c) 운영 음성 테스트가 아래 4건을 바꿨다. **모두 계약을 약화시키지 않고 강화하는 방향**이며, 각 항목은 실측 런 ID로 뒷받침된다.

| # | 초안 | 착지본 | 근거 |
|---|---|---|---|
| 1 | `provision-scope` 미지 값이 `else` 분기(full)로 흘러 **fail-open** | `case ... full\|runtime\|nim ;; *) exit 1` — 미지 scope는 즉시 실패 | scope 오타 하나가 1.16GB full 페이로드를 조용히 프로비저닝하던 경로 제거 |
| 2 | nim 버전이 스크립트 상수 | `nim-version` 입력 신설(default `2.2.10`) → **키에 결속**. arm64 tarball URL/sha256 핀도 변수화 | 버전 변경이 키 세대를 바꾸지 않으면 다른 컴파일러 페이로드를 복원하게 된다 |
| 3 | non-exact discard = `rm -f ~/.local/bin/{z3,jq}` | **`~/.local/bin` 디렉터리 전체를 `$RUNNER_TEMP`로 격리(mv)** + 빈 디렉터리 재생성 + `test -z "$(ls -A …)"` 단언 | **런 43067710160이 실제 fail-open을 적발**: 부분 일치 페이로드의 `~/.local/bin/PARTIAL-CANARY`만 생존(`~/.nimble`·`~/.choosenim` 캐너리는 소멸). `~/.local/bin`은 PATH에서 시스템 디렉터리보다 앞이므로 페이로드가 심은 임의 이름이 `git`·`python3`·`sha256sum`을 섀도잉한다 — "구성원은 z3/jq뿐"이라는 가정이 미검증 페이로드에서 성립하지 않음 |
| 4 | 새 증거 파일의 라이선스 귀속 미등록 | `license-attribution.yml`에 `data/ci_optimization/pi_toolscope_2026-11-12/summary.json` × `JSON` 정확 쌍 등재 | **런 43069682531이 적발**: `LICENSE UNACCOUNTED … -> json` (요약 44행의 `…/report_license.json` 경로 토큰에 `json_8.RULE` 매칭). glob·catch-all 없이 (file, atom) 쌍만 추가 — fail-closed 성질 보존 |

추가로 §2.3의 "이론 복원 비용 ~10s"는 실측으로 대체되었다(§4.3): HIT setup 스텝 평균 **14.0s**.

## 3. TOMBSTONE (단계 3)

**폐기되는 동작 없음 — 해당 없음(no-op).** 사유:

1. `full` scope는 다른 호출자(admission-check의 build-base/attest/verdict, closure-watcher, observation)가 계속 사용한다 — 폐기 대상이 아니다.
2. `runtime` scope도 mint 계열이 계속 사용한다.
3. 폐기되는 것은 **"publication-integrity 평가 잡이 full 페이로드를 받던 선택"** 하나이며, 이는 구성 선택의 변경이지 구현의 종료가 아니다.
4. required check·게이트·검증 면제는 어떤 형태로도 발생하지 않는다. `config/decision_binding.waiver.*` 등록 없음.

따라서 본 epoch의 tombstone 레코드는 존재하지 않는다. 이는 `docs/agents/ci_epoch_cutover.md`의 tombstone 정의(구현의 END)에 해당하는 대상이 없기 때문이며, tombstone 생략이 면제·우회를 의미하지 않는다.

## 4. 검증 계획 — J1–J4 (착지 판정)

동일 커밋·동일 입력으로 비교한다. 하나라도 실패하면 캐시 최적화는 VALID가 아니다.

| 판정 | 질문 | 방법 | 합격 조건 |
|---|---|---|---|
| **J1 — 의미론적 동일성** | 기존 환경과 캐시 환경의 **최종 판정**이 동일한가 | 기준선 런 42980750324의 차원 artifact를 `gh run download` → 후보 런(브랜치) artifact와 `publication_report` verdict·위반 수 비교 | 6개 차원 verdict 전부 동일 |
| **J2 — 증거 등가성** | 생성된 **증거 내용**이 동일한가 | 6차원 산출물 비교: ①Secret scan 탐지 결과 ②License scan 파일별 판정 ③Dependency scan 결과 ④Provenance 의미 필드 ⑤SBOM 구성요소·라이선스 ⑥Publication integrity 최종 판정. 원본 JSON은 `sort_by(path)` 정규형의 **sha256 비교**, 불가능한 경우 필드 단위 비교. 정규화 허용 = timestamp·runId·경로 prefix **3종뿐**, 각각 근거 기록 | 차원별 산출물이 정규화 후 동등. **N/A 처리 금지** — 스키마 동일성은 내용 동일성이 아니다 |
| **J3 — 캐시 건전성** | 정확한 키와 검증된 지문만 사용되는가 | ①부분 일치 **부정 테스트**: 동일 키 공식으로 `${A_KEY}-probe` 캐시를 만든 뒤 nim scope 실행 → `PARTIAL-CANARY` 미존재 + `AXIOM_CACHE_A_RESTORE: DISCARDED` 로그 ②exact-hit 런에서 `cache-hit=true` + `matched-key` == `requested-key` 로그 ③표식 없는 실패 설치가 save되지 않음(`save-allowed=false`) 확인 ④fingerprint verify 실패 시 discard→재설치 경로 로그 | 4개 전부 관측. 부정 테스트가 통과하지 못하면 슬라이스 폐기 |
| **J4 — 실행 결정론** | 실행 방식에 새 변수가 없는가 | nim scope는 **도구 획득 방법만** 바꾼다: 샤드 분할·`--processes 4`·스캔 인자·평가기 소스·정책 전부 무변경(`git diff`로 기계 확인) | diff에 스캔 명령·샤드·process 수 변경 0건. **J4는 "변경 없음"이 계약이므로 diff 검사로 판정 가능** |

### 4.1 운영 acceptance (J5)

착지 후 관측 항목은 §4.4에 있다. **경로 필터로 required workflow를 스킵하는 절감은 제외**한다 — GitHub은 required workflow가 경로 필터로 스킵되면 check가 Pending으로 남아 병합을 차단한다고 명시한다.

### 4.2 merge_group 캐시 스코프 (UNKNOWN 처리)

merge_group 런의 캐시 스코프는 공식 문서에 없다. 따라서 merge_group 런의 HIT를 "main 시드가 PR에 재사용됐다"의 증거로 쓰지 않는다. 대신:

- **main 시드**: merge 후 `gh workflow run publication-integrity.yml --ref main` → `Cache saved with key: axiom-a-nim-…` 로그
- **PR/브랜치 소비**: `--ref workstream/pi-toolscope` dispatch 또는 PR 런에서 `cache-hit=true` + `matched-key == requested-key` 로그

### 4.3 실측 결과 (브랜치, 동일 커밋 `c8f4ab0`)

**J3 — 캐시 건전성: PASS (4/4 관측)**

| 관측 | 런 | 증거 |
|---|---|---|
| ① 부분 일치 부정 테스트 | **43067710160** (FAIL — 결함 적발) → **43068818512** (PASS) | 1차: `exact-hit=false`, `matched-key=…-probe`, `DISCARDED`, 그러나 `~/.local/bin` 캐너리 생존 → §2.9 #3 수정. 2차: `QUARANTINED partial ~/.local/bin -> /home/runner/work/_temp/a-partial-discarded-local-bin-…`, 캐너리 3종 전부 `gone`, `a-cache-hit=false` |
| ② exact-hit 런의 키 일치 | **43075884704** | 6개 잡 전부 `exact-hit=true`, `matched-key == primary-key == requested-key` (`axiom-a-nim-Linux-X64-nim2.2.10-8497f84b2b8334c4-e881beabc91bfbd3-fd22f703ed73544834a6d8ec9ffbd5b8ef73715c`), `AXIOM_CACHE_A_VERIFY: OK`, `AXIOM_CACHE_A_PROBE: OK` |
| ③ 표식 없는 설치의 save 차단 | 43072873191 / 43075884704 | save는 `A-layer save authority` 출력만 참조. 표식은 verify 통과 후 생성되고 save 스텝이 재확인 — `AXIOM_CACHE_A_SAVE: nim toolchain verified (nim=2.2.10 nimble=checksums) — save authority granted`가 **설치 성공 이후에만** 출력됨 |
| ④ verify 실패 시 discard→재설치 | 43067710160 / 43068818512 | `cache-hit != 'true'` 경로에서 discard 후 네이티브 설치 → `Cache saved with key: axiom-a-nim-…` (검증된 신규 설치본만 저장) |

**J1/J2 — 의미론적 동일성·증거 등가성: PASS**

- J1: 두 런(43072873191 MISS, 43075884704 HIT) 모두 8개 잡 `success`, 6개 차원 verdict 전부 `PASS` — 기준선 42980750324와 동일.
- J2: 격리 HOME에서 6개 평가기를 재컴파일·재실행한 산출물이 기준선 아티팩트와 **6/6 바이트 동일**(`jq` key-sort 정규화 후 sha256 일치, `data/ci_optimization/pi_toolscope_2026-11-12/summary.json`). 정규화는 **키 정렬 하나뿐**이며 timestamp·runId·경로 prefix 정규화는 사용하지 않았다.
- **J2 범위 명시(정직 기록)**: 이 비교는 **동일 입력 트리**에서 도구 획득 방식만 바꾼 효과를 분리하기 위한 것이다. 본 슬라이스 자신의 증거 파일(`data/ci_optimization/pi_toolscope_2026-11-12/**`)이 트리에 추가되면 스캔 대상 집합이 늘어나 산출물이 **정당하게** 달라진다(런 43069682531의 `files=7253`). 따라서 "바이트 동일"은 도구 등가성의 증거이지 트리 불변성의 증거가 아니다.

**J4 — 실행 결정론: PASS (기계 확인)**

`git diff 681d130..HEAD -- .github/workflows/publication-integrity.yml`에서 `provision-scope`·주석을 제외한 변경 라인 = **0건**. 샤드 분할·`--processes 4`·스캔 인자·평가기 소스·정책 파일 무변경.

**시간 실측 (setup-axiom-toolchain 스텝, 초)**

| 잡 | 기준선 42980750324 (full HIT) | 43072873191 (nim, MISS) | 43075884704 (nim, HIT) | HIT 절감 |
|---|---|---|---|---|
| secret-scan | 45 | 49 | 15 | **30** |
| dependency-scan | 75 | 53 | 13 | **62** |
| provenance | 52 | 68 | 14 | **38** |
| sbom | 71 | 72 | 15 | **56** |
| license-scan (병합·판정) | 47 | 31 | 14 | **33** |
| publication-integrity (aggregator) | 72 | 13¹ | 13 | **59** |
| **합 / 평균** | **362 / 60.3** | — | **84 / 14.0** | **278 / 46.3** |

¹ MISS 런에서 aggregator는 14분 뒤 실행되어, secret-scan이 17:57:03에 저장한 항목을 **같은 런 안에서** HIT했다(first-save-wins의 정상 동작). 따라서 MISS 런의 setup 값은 혼합 상태이며 절감 계산에 쓰지 않는다.

- 잡당 절감 **최소 30s**(secret-scan) — 사전 하한(≥25s/잡) **충족**.
- 런당 setup 절감 **278s = 4.63 job-min** (6개 잡).
- 잡 전체 시간 합: 기준선 2,121s → HIT 1,878s. 나머지 차이는 `license-scan-shards`(toolchain 미사용, 807/660 → 626/864)의 러너 노이즈이며 본 슬라이스의 효과가 아니다.

**비용 환산 (분 올림 전, Linux 2-core $0.006/min)**

| 실행 빈도 | job-min/월 | USD/월 |
|---|---|---|
| 5회/주 (≈21.7런) | 100 | **$0.60** |
| 6회/일 (180런) | 833 | **$5.00** |

기존 보고서의 "월 1,200 job-min ≈ $7"는 400s/런 절감을 함의해 **과대**였다(§2.7). 또한 포함량이 USD 크레딧인 한 이 절감은 **현금이 아니라 크레딧 여유**다.

**캐시 저장량**: 착지 전 4,115,929,236 B(24개) → nim 페이로드 1개 **197,797,057 B** 추가. 10GB 한도 대비 여유 충분.

### 4.4 운영 acceptance (J5) — 착지 후 관측 항목

1. PR이 GitHub native merge queue를 통과해 main에 착지한다.
2. main의 실제 운영 워크플로가 새 세대를 호출한다 (blob 일치 확인).
3. 캐시 적중과 fingerprint 검증 결과가 실행 로그에 남는다.
4. 캐시 MISS·손상 상황에서도 전체 검증이 정상 재수행된다.
5. required 6 contexts가 전부 정확한 `success`를 기록한다.
6. 실제 운영 런의 러너 사용량과 경과 시간이 개선됐는지 측정한다 (잡당 ≥25s 감소 하한, 미달 시 슬라이스 폐기 기록).
7. `gh api repos/Archright/Axiom/actions/cache/usage`로 저장량 증가분이 ≤10GB 내인지 확인한다.

### 4.5 운영 acceptance 실측 (착지 후 — 7/7 관측)

| # | 관측 | 증거 |
|---|---|---|
| 1 | **native MERGE 착지** | PR **#17**, `mergedAt 2026-11-11T19:35:49Z`, `mergeCommit 3cd6e916bb4d28ce0b5b032b24baf2af62dd9f52`, 부모 `52b2c456`(main)·`bcb040d`(head) → 2-parent merge 커밋(스쿼시·리베이스 아님). merge authority = GitHub merge queue |
| 2 | **main이 새 세대를 호출** | `git rev-parse origin/main:.github/actions/setup-axiom-toolchain/action.yml` = **`d0dd6903`**, `…:publication-integrity.yml` = **`ac90161c`** — 착지본 blob과 정확히 일치. workflow id 414024007 `active` |
| 3 | **merge_group 검증** | 런 **43086206125** success, 8/8 잡 green, 총 1,929s (기준선 2,121s). **스코프는 별도다**: 앞 4개 잡 `exact-hit` unset(미스) → sbom이 19:41:38에 저장 → 뒤 2개 잡(license-scan 17s, aggregator 14s) HIT. merge_group HIT를 main 시드 증거로 쓰지 않는다는 §4.2 원칙이 실측으로 확인됨 |
| 4 | **main 시드** | 런 **43089370179** success → `Cache saved with key: axiom-a-nim-…-fd22f703…`, `ref=refs/heads/main`, **197,849,383 B**, `last_accessed 19:56:03Z` |
| 5 | **main HIT (전 잡)** | 런 **43092549569** success — 6/6 평가 잡 `exact-hit=true`, `AXIOM_CACHE_A_VERIFY: OK`, `AXIOM_CACHE_A_PROBE: OK`. requested == primary == matched |
| 6 | **시간 개선** | main HIT setup 스텝: dependency-scan 18s, provenance 12s, sbom 14s, secret-scan 15s, license-scan 15s, aggregator 33s(이상치) → **평균 14.8s**(aggregator 제외) / 17.8s(포함). 기준선 동일 스텝 평균 60.3s. 잡 합계 1,601s (기준선 2,121s, 차이는 주로 `license-scan-shards` 519/676 vs 807/660의 러너 노이즈) |
| 7 | **저장량** | `active_caches_size_in_bytes` = **8,471,829,967 B (7.89GB) / 10GB**, 35개. nim 항목 4개(refs/heads/main, merge queue ref, refs/pull/17/merge, 브랜치) × ~188MB = **752MB**. 지배 성분은 여전히 full 페이로드 1,160MB × 5. 7일 미사용 제거로 PR/브랜치 스코프 항목은 자연 소거된다 |

**required contexts**: PR #17의 12개 워크플로가 전부 `success`(dependabot-auto-merge만 정상 skip) → `mergeStateStatus` BLOCKED → **CLEAN** 전이 후 큐 진입. merge queue는 그 SHA에 대해 merge_group 런을 다시 돌려 8/8 green을 확인한 뒤 착지시켰다.

**남은 정직한 UNKNOWN**: (a) 실제 현금 청구액 — 빌링 API 403. (b) merge_group 스코프의 문서상 정의 — 관측(별도 스코프)만 기록. (c) exact-hit인데 verify 실패하는 "나쁜 엔트리"의 키 회전 — 저장 불가 제약은 §6 debt로 기록.

## 5. ROLLBACK

| 상태 | 행위 |
|---|---|
| nim scope 결함 (CI red·J1/J3 FAIL) | **단일 revert PR** — 본 커밋 3파일을 한 번에 되돌린다. freeze blob `bb06468…`/`7110cc6…`이 복구 기준 |
| 판정 불가 상태 | rollback을 선언하지 않고 조사한다 — 어느 경우도 게이트 우회 수단을 만들지 않는다 |

## 6. 잔여 / 후속

- **10런 추적**: 착지 후 첫 10회 실행의 ①캐시 적중률 ②잡별 시간 ③총 러너 분 ④캐시 저장량 ⑤실패율을 기록한다. 첫 런은 script_hash 무효화로 전부 MISS이므로 집계에서 제외하고, 시드 후부터 센다.
- **VS-2 (보류)**: ScanCode `--processes` 조정 — 샤드 수·버전 유지, 1/2/4 프로세스의 출력 동등성 검증 후에만.
- **VS-3 (보류)**: 샤드 구성 최적화 — J1/VS-2 완료 후에도 병목이 남을 때만. 현재 지배 비용은 `license-scan-shards`(626–864s)이며 **toolchain 미사용**이므로 본 슬라이스의 대상이 아니다.
- **VS-4 (보류)**: 과금 구조(플랜) 최적화 — CI 코드 변경과 분리해 사업적 순비용 비교 후 결정.
- **blocker (범위 밖)**: dependabot 런의 `apt-get` DNS 실패(§2.8). libpcre3 유지가 요구되므로 별도 작업.
- **문서 SSOT (감사 완료)**: `provision-scope`를 열거하는 `docs/spec/` 문서는 `ci_optimization_tcb_judgments.md` **하나뿐**임을 확인(`grep -rn provision-scope docs/spec/*.md`). 나머지 후보(`verification_dag_contract.md`, `repository_state_model.md`, `byo_agent_proposition_contract.md`)는 열거하지 않으므로 갱신 불필요.
- **debt (범위 밖, 기록)**: exact-hit인데 verify가 실패한 "나쁜 엔트리"는 `cache-hit != 'true'` 게이트 때문에 재저장이 불가능하다(actions/cache는 키 덮어쓰기 불가). 현재는 매 런 재설치로 fail-closed 동작하며, 키 회전 정책은 별도 작업이다.
- **후속 후보 (VS-1b)**: `~/.choosenim/downloads`의 122MB tarball이 nim 페이로드에 포함되어 있다. 제외하면 복원량이 ~40% 줄지만, 설치 경로가 그 캐시를 재사용하는지 먼저 검증해야 한다.