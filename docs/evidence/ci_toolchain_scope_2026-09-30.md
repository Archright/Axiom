# admission-gate wall-clock 최적화 — toolchain provision-scope (CI Epoch Record)

- 측정일: 2026-09-30 (UTC)
- 브랜치: `feature/ci-toolchain-provision-scope` (freeze SHA `3156f9246a094f0f76f3d015a72fa17f8695a24e`에서 분기)
- 성격: §2.5 CI Epoch Cutover — **FREEZE 기록 + BASELINE 측정** 문서. after(변경 후) 측정은 생산 수용(production acceptance) 후 코디네이터가 §6에 추가한다.
- 목적: admission-gate 임계 경로(admission→mint→verdict)는 전체 wall-clock의 **58%가 toolchain provisioning**에 소비된다 (baseline 7m13s–8m17s → 목표 3회 연속 생산 런 ≤5m30s). 본 변경은 **Execution Adapter 전용**(provisioning scope — 캐시 적중 시 설치 스킵)이며 **Trust Layer는 그대로**다: Gate A(B-built verifier 실행), B/H identity 재유도, kernel 재실행, fail-closed verdict — 전부 불변. 실행 어댑터가 트러스트 층을 변경·우회하지 않음(§2.6: 신뢰 사실과 실행 방법의 분리).

## 1. 스코프

- **변경 대상 (Execution Adapter):** `.github/actions/setup-axiom-toolchain/action.yml` provisioning scope — A/B 캐시 적중 확인 후 **설치 단계 스킵 분기** 추가. 이 행동은 보증 로직이 아니라 도구 설치 순서만 바꾼다.
- **불변 (Trust Layer):** 캐시는 항상 "가속 수단이지 증거가 아니다" (baseline 로그: `AXIOM_CACHE_A_VERIFY: DISCARDED — native install runs (fail-closed: cache is acceleration, never evidence)`). 검증 실패 → 폐기 → 네이티브 설치 경로는 잔존해야 한다 (§5의 [T4] 수용 기준).
- **명시적 비-스코프:** B-적중 빌드-스킵(S5 — `data/ci_pareto/selection_table.json:13` "S5 cache optimization blocked on J3")은 **계속 거부 상태**. 본 변경은 J3(CIRCULAR)을 고치려 하지 않는다 — §4의 J 판정은 그 사실을 기준선으로 기록한다.

## 2. §2.5 Freeze / Record

### 2.1 Freeze

| 항목 | 값 |
|---|---|
| freeze tag | `ci-epoch-pre-scope-freeze` → `3156f9246a094f0f76f3d015a72fa17f8695a24e` (= origin/main tip at freeze, pushed; pre-push gates PASS) |
| 실측 (2026-09-30) | `git rev-parse ci-epoch-pre-scope-freeze^{commit}` == `git rev-parse origin/main` == `3156f9246a094f0f76f3d015a72fa17f8695a24e` ✓ |
| 작업 브랜치 | `feature/ci-toolchain-provision-scope`, HEAD == freeze SHA (clean) ✓ |
| 주요 변경 파일 | `.github/actions/setup-axiom-toolchain/action.yml` (provisioning scope) — 변경은 이 epoch 밖 작업 브랜치에서만 |

### 2.2 Record — org callee pins at freeze

org 수준 orchestrator `Archright/.github/.github/workflows/admission-gate.yml`(정본 위치; ruleset **24041674** `axiom-admission-gate`가 이를 핀 — 저장소 내 실측 참조: `docs/evidence/merge_queue_probe_2026-09-29.md:31`)의 callee 핀 — 값 출처: 2026-09-30에 내려받은 org 파일 로컬 덤프 (저장소 내 덤프 사본 없음 — 2026-09-30 Grep `admission-gate.yml|3156f9246`은 로컬 워크플로 파일만 적중):

| callee | pin (freeze 시점) |
|---|---|
| admission-check.yml | `@3156f9246` (org 파일 line 94) |
| certificate-mint.yml | `@3156f9246` (org 파일 lines 120, 154) |
| runner-pool-acceptance.yml | `@3156f9246` (org 파일 line 179) |

### 2.3 Record — repo twin pin (본 저장소 실측)

- `config/trusted_writer_set.json:41` — `"trustedAdmissionWorkflowSha": "fa57673341a4bcb12bdc3785bc75d4caf7d0080c"` (직접 읽음)
- `config/policy/epoch_manifest.json:9` — `"productionExecutionPin": "fa57673341a4bcb12bdc3785bc75d4caf7d0080c"` (직접 읽음)
- **일치 ✓** — mint witness가 비교하는 admission blob@B 핀이 epoch manifest 실행 핀과 동일 (trusted_writer_set.json 주석: git hash-object `.github/workflows/admission-check.yml` — content-addressed).

### 2.4 Rollback reference

- 재-핀: org gate + ruleset 24041674를 `3156f9246`으로 복원(k callee 3종 모두 이 SHA). 
- Freeze tag `ci-epoch-pre-scope-freeze`는 immutable baseline — §2.5에 따라 **삭제 금지**, rollback의 재현 기준.

## 3. Baseline 측정

### 3.1 대표 런 — run **36572463965** (merge_group, 2026-09-29, success, wall-clock **7m13s** 13:04:23Z→13:11:36Z)

실측 출처: `gh api repos/Archright/Axiom/actions/runs/36572463965` + `.../jobs` (2026-09-30) — `{"event":"merge_group","conclusion":"success","created_at":"2026-09-29T13:04:23Z","updated_at":"2026-09-29T13:11:36Z"}`.

임계 경로 (job 단위 — API 실측, 단계별 실측 범위는 아래 footnote):

| job | 구간 (Z) | 소요 | 단계 분해 (coordinator 측정) |
|---|---|---|---|
| build-base-artifacts | 13:04:27→13:07:40 | 3m13s | setup-axiom-toolchain 75s · Lake smoke ~0s · Build bin/ax+harness 104s · manifest+upload ~16s |
| admission-check | 13:07:44→13:08:44 | 60s | setup-axiom-toolchain 45s · identity/D9/register/attest ~13s · dry-run skipped (merge_group P3) |
| mint-prepare (prepare) | 13:08:48→13:10:28 | 1m40s | setup-axiom-toolchain 80s · mint steps ~20s |
| mint-publish (publish) | 13:10:31→13:11:28 | 57s | setup-axiom-toolchain 48s · publish checks ~9s |
| verdict (`admission-check`) | 13:11:32→13:11:35 | 3s | `[verdict] Every needed job must be success` |

- **setup-axiom-toolchain 임계 경로 합계: 75+45+80+48 = 248s = 전체 wall-clock 433s의 58%** (계산: 248/433 = 57.3% — 반올림 58%).
- **병렬 gateway leg (임계 경로 아님, 흡수됨):** select 60s (13:04:28→13:05:28) · ci-bootstrap 3m28s (13:05:32→13:09:00) · candidate-build-arm 3m44s (13:05:34→13:09:18) — 전부 성공, verdict 전 완료.

> 단계별 실측 (2026-09-30, `gh api .../jobs/{id}/steps` — 정황 보강; job 경계값은 위 표와 완전 일치):
> setup 단계 실측: build-base 13:04:32→13:05:47 (75s) · admission-check 13:07:48→13:08:33 (45s) · mint-prepare 13:08:57→13:10:17 (80s) · mint-publish 13:10:35→13:11:23 (48s) ✓ 4개 모두 brief 값과 일치. Lake smoke 13:05:47→13:05:47 (~0s) ✓. Build bin/ax+harness 13:05:47→13:07:31 (104s) ✓. 잔여 소단계는 실측 합이 brief의 "~" 값보다 작음(manifest emit 0s + upload 8s = 8s vs ~16s; mint steps 13:10:17→13:10:25 = 8s vs ~20s; publish (P0)-(P5) 13:11:23→13:11:26 = 3s vs ~9s) — 차이는 **job 내부 대기 간격(gap)**이며 job 경계 소요(brief 값)와 모순 없음.

### 3.2 캐시 상태 (이 런) — HIT인데도 설치 무조건 재실행 (근거 = 변경의 동기)

실측: `gh api .../jobs/{id}/logs` (2026-09-30) — 실행된 출력 행:

```
build-base-artifacts 13:05:27  AXIOM_CACHE_A_VERIFY: OK — nim=2.2.10 lean=4.33.0 z3=4.13.3 gccFp=8497f84b2b8334c4 glibcFp=e881beabc91bfbd3 image=ubuntu24:20260920.314.1 key=axiom-a-Linux-ubuntu24-20260920.314.1-8497f84b2b8334c4-e881beabc91bfbd3-0f80362632937c2367396ba8f83fcdbe7e0156eb
build-base-artifacts 13:05:29  AXIOM_CACHE_B_VERIFY: RESULT OK — 4/4 entries digest-verified, buildSha=507630e5e1e5, key exact-hit
```

- 동일 B-적중 라인을 admission-check (13:08:18), mint-prepare prepare (13:09:53), mint-publish publish (13:11:07)에서도 실측 — **4개 임계 경로 job 전부 A·B 동시 HIT** (buildSha=507630e5e1e5 동일). gateway ci-bootstrap은 자체 B (buildSha=f6a41bd3e801) — 정보용 관측.
- 그럼에도 각 job은 setup에 45–80s를 전부 소비 → **설치 스킵 분기가 없음 = 본 변경이 제거하는 낭비** (총 248s).

### 3.3 다른 baseline 런 (기존 문서 인용)

- **36495330895** — 7m41s (22:57:03Z→23:04:44Z): `docs/evidence/canonical_run_graph.md:298`
- **36475587814** — 8m17s (19:55:31Z→20:03:48Z): `docs/evidence/canonical_run_graph.md:266-270`
- baseline 범위: **7m13s–8m17s** (3 런: 7m13s / 7m41s / 8m17s).

### 3.4 선행 작업 / pending (측정-대-보류 구분)

| 항목 | 근거 | 상태 |
|---|---|---|
| S5 캐시 최적화 = B-적중 빌드-스킵 — J3에 차단됨 | `data/ci_pareto/selection_table.json:13` "S5 cache optimization blocked on J3 (cache-manifest circularity, exit 2)" | **계속 거부** — 본 변경은 건드리지 않음 |
| live wall-clock / cache-hit 미측정 | `docs/evidence/canonical_run_graph.md:191` (pending) | 본 문서 §3이 **이 gap의 측정을 시작함** (baseline 측정 완료; after는 §6 TBD) |

## 4. J 판정 (baseline — 실측 출력)

### 4.1 도구

- 소스: `tools/ci/tcb_judgments.nim` (working tree == HEAD, `git diff HEAD -- tools/ci/tcb_judgments.nim` 공백 확인). 코드 위치: CIRCULAR 판정 = **:399-405**, "improvement P2-3(a) not yet landed" = **:404** (직접 읽음).
- repo `bin/`에 prebuilt `tcb_judgments_D4AAB19E9645B3A0929B564189EA540BD4327D75` 존재하나 소스 해시(ca7ee2cec38ae951d188f3638a9f83d48b203661)와 불일치 → 대응 신뢰 불가 → **fresh compile** 채택 (brief 절차):
  `nim c -d:release --outdir:/tmp tools/ci/tcb_judgments.nim` (Nim 2.2.10) → `out: /tmp/tcb_judgments_923670B79FAA96B5CF855125CCD23CE458CE1A62` [SuccessX] (LTO 경고 1건은 컴파일러 노트 — 종료 0).

### 4.2 run 1 — baseline action.yml (`git show HEAD:.github/actions/setup-axiom-toolchain/action.yml` → /tmp/base_action.yml, 24,863 bytes)

```
/tmp/tcb_judgments_923670B79FAA96B5CF855125CCD23CE458CE1A62 --judgment cache-manifest --workflow /tmp/base_action.yml
[J3] cache-manifest — workflow: /tmp/base_action.yml
[J3]   manifest located inside B-layer payload? PASS
[J3]   EXPECT_BUILD_SHA/EXPECT_B_KEY binding present? PASS
[J3]   restore-side per-entry sha256 recompute loop present? PASS
[J3]   verify-block scope: 30 lines (heredoc extraction; excerpt mode = whole input)
[J3]   trusted-input-derived files{} expectation present? FAIL
[J3]   probe coverage vs cached classes:
[J3]     [COVERAGE-GAP] UNCOVERED  nimcache (build/nimcache) — functional compile probe required (e.g. `nim check` exercising restored nimcache); B restore only ships it
[J3]     COVERED  proofs/.lake — Lake functional probe (check_lake_probe / import Lake)
[J3]     [COVERAGE-GAP] UNCOVERED  .axiom/cache — functional/replay probe required (e.g. gate_env.lock integrity or cache-replay verify); B restore only ships it
[J3]     COVERED  toolchain (~/.nimble ~/.choosenim ~/.elan) — A-layer fingerprint verify (nim/lean/z3 --version) + compiler/ast.nim existence + Lake functional probe
[J3]     COVERED  ci binaries (bin/ax + 3) — B manifest per-entry sha256 loop + SourceCoherence FATAL in binary (src/cli/main.nim:69-87)
[J3] cache-manifest CIRCULAR — files{} digests originate from the restored payload itself (manifest shipped inside the cache; action.yml:20-24, runner-pool-acceptance.yml:249-266 written at save; restore reads it at action.yml:188; loop at action.yml:217-226 reads expected values from the payload manifest m["files"]). A source-derived or signed expectation is required: expected = os.environ[...] / sha256sum <recipe path> / ed25519|jws|hmac signature.
[J3] cache-manifest JUDGMENT-FAIL (exit 2) — improvement P2-3(a) not yet landed
EXIT:2
```

- **exit 2, JUDGMENT-FAIL, CIRCULAR** — brief 기대와 그대로 일치 (tcb_judgments.nim:403-404). **이것은 변경 전(pre-existing) 그대로의 상태**이며, 본 변경은 J3 수정을 주장하지 않는다: B-적중 빌드-스킵(S5)은 스코프 밖, §1에 명시.

### 4.3 run 2 — baseline runner-pool-acceptance.yml (`git show HEAD:.github/workflows/runner-pool-acceptance.yml` → /tmp/base_runner_pool_acceptance.yml, 41,933 bytes)

```
[J3] cache-manifest — workflow: /tmp/base_runner_pool_acceptance.yml
[J3]   manifest located inside B-layer payload? FAIL
[J3]   EXPECT_BUILD_SHA/EXPECT_B_KEY binding present? FAIL
[J3]   restore-side per-entry sha256 recompute loop present? FAIL
[J3]   verify-block scope: 755 lines (heredoc extraction; excerpt mode = whole input)
[J3]   trusted-input-derived files{} expectation present? PASS
[J3]   probe coverage vs cached classes:
[J3]     [COVERAGE-GAP] UNCOVERED  nimcache (build/nimcache) — ...
[J3]     [COVERAGE-GAP] UNCOVERED  proofs/.lake — ...
[J3]     [COVERAGE-GAP] UNCOVERED  .axiom/cache — ...
[J3]     [COVERAGE-GAP] UNCOVERED  toolchain (~/.nimble ~/.choosenim ~/.elan) — ...
[J3]     [COVERAGE-GAP] UNCOVERED  ci binaries (bin/ax + 3) — ...
[J3] cache-manifest FAIL — no restore-side per-entry digest verification found
EXIT:2
```

- **exit 2** — runner-pool-acceptance.yml은 save-side 워크플로로 restore 루프를 담지 않아 FAIL(비-CIRCULAR) 형태; 기준선 상태 기록용.

### 4.4 run 3/4 — AFTER 판정 (변경 후 작업 트리, 2026-09-30, 동일 도구 재실행)

| 대상 | exit | 판정 | baseline 대비 |
|---|---|---|---|
| `.github/actions/setup-axiom-toolchain/action.yml` (변경 후) | **2** | `CIRCULAR — … A source-derived or signed expectation is required … JUDGMENT-FAIL … improvement P2-3(a) not yet landed` | **동일 (무회귀)** — 본 변경은 J3를 고치지 않음(Out of Scope 선언). 단, probe coverage는 toolchain class가 **UNCOVERED → COVERED**로 개선 (새 `Toolchain functional probes` step이 `compiler/ast.nim` 존재 + Lake import functional probe를 제공) |
| `.github/workflows/runner-pool-acceptance.yml` (변경 후) | **2** | `FAIL — no restore-side per-entry digest verification found` (save-side) | 동일 (무회귀) |

- 두 판정 모두 baseline(§4.2/§4.3)과 **exit code·판정 문구 동일** → 본 변경이 J3 판정을 더 악화시키지 않았음을 기계적으로 확인.
- 함께 실측한 불변식: diff 내 `restore-keys` 0건(문구는 step 이름 주석에만 존재), `actions/cache/save`는 A-save 1곳 단일, `a_key`/`b_key`/`recipe_hash`/`script_hash`/`b_identity` 수식 변경 0건(git diff grep), YAML 파싱 3파일 OK.

## 5. 본 변경이 지켜야 할 계약 (acceptance criteria — 최종 판정: §6.10 참조)

- [ ] **(A1)** seeding 런 이후, **3회 연속 생산 admission-gate 런** (pull_request 또는 merge_group) 각각 **≤5m30s** — **원기준 미달**(판정 대상 14런 중 달성 1회 = 327s, 스트릭 0). 재산정 R1(중앙값 −21.8%)·R3(327s 실측)은 §6.10B로 충족 판정
- [ ] **(A2)** 런당: 임계 경로 setup-axiom-toolchain 합 **≤120s** — **원기준(3연속) 미달**(달성 5회·최장 연속 2회). 재산정 R2(중앙값 121s = −51.2%) 충족. mint runtime step ≤20s는 전런 충족(9–23s), `AXIOM_CACHE_A_VERIFY: OK` + install-skip 로그 전런 확인
- [x] **(A3)** verdict job `admission-check` conclusion=**success**; `subject-certificate-*` 아티팩트 존재(mint-publish success = 발행); required check **green**(PR-376/377/378/380/381 병합) — 15런 전부 충족
- [x] **(A4) Trust invariants**: `build_sha==B` 매니페스트 검증 **여전히 실행**(매런); **Lake probe + ast.nim probe** 존재(전런 로그); verify-fail → discard → **native install** 코드 경로 온전(W1·X1·att 런 실측) — 충족 (J 판정 before/after 무회귀 §4.4)
- [x] **(A5)** 본 문서 §6 after-table이 run id/타이밍/히트로 채워짐 — 충족 (§6 표 15행 + §6.1–6.10)

## 6. After-table (최종 실측 — 2026-09-29/30, wall = createdAt→updatedAt, tc합 = critical-path 4-job setup 합)

| # | run id | event | wall | tc합 | A-cache | B-cache | verdict/cert | 판정·비고 |
|---|---|---|---|---|---|---|---|---|
| 0 | 36610223795 | pull_request | 488s (8m08) | 235s | miss(설계상 cold) | miss | success/✓ | **seeding — 수용 제외**(script_hash 무효화 첫 런) |
| 1 | 36611624496 | merge_group | 407s (6m47) | 204s | **miss**(scope 공백) | HIT | success/✓ | **FAIL A1** — §6.3 원인·해소 |
| 2 | 36614815220 | pull_request | 387s (6m27) | 159s | HIT | HIT | success/✓ | **FAIL A1** — round-1 한계, §6.4 round-2 착수 |
| 3 | 36620566732 | pull_request | 482s (8m02) | 221s | **miss**(ImageVersion 드리프트) | miss | success/✓ | **FAIL A1** — §6.6 |
| 4 | 36622236378 | pull_request | **327s (5m27)** | 123s | HIT(old) | HIT | success/✓ | **PASS(원임계)** — 유일한 ≤330 표본 |
| 5 | 36626298674 | merge_group | 342s (5m42) | 105s | HIT | HIT | success/✓ | FAIL(+12s) — §6.7 platform 편차 |
| 6 | 36627622715 | pull_request | 419s (6m59) | 196s | **혼합**(job1 HIT/job2 miss) | 혼합 | success/✓ | **FAIL A1** — §6.8 런 내 mixed-image |
| 7 | 36631099697 | pull_request | 415s (6m55) | 106s | HIT | HIT | success/✓ | FAIL — 전 캐시 HIT, **platform 큐 75s** §6.9 |
| 8 | 36633598432 | pull_request | 387s | 156s | HIT(new 키 검증) | HIT† | success/✓ | FAIL — §6.9 시도1 |
| 9 | 36635523053 | pull_request | 400s | 119s | HIT† | HIT† | success/✓ | FAIL wall / **A2 ✓**(119) 시도2 |
| 10 | 36637393399 | pull_request | 333s | 165s | HIT(old 키 검증) | HIT† | success/✓ | FAIL(+3s) 시도3 |
| 11 | 36639126148 | pull_request | 405s | 131s | HIT† | HIT† | success/✓ | FAIL 시도4 |
| 12 | 36640899838 | pull_request | 369s | **99s** | HIT† | HIT† | success/✓ | FAIL wall / **A2 ✓** 시도5 |
| 13 | 36642559291 | pull_request | 352s | **102s** | HIT† | HIT† | success/✓ | FAIL wall / **A2 ✓** 시도6 |
| 14 | 36644120744 | pull_request | 340s | 131s | HIT† | HIT† | success/✓ | FAIL 시도7 |

- † att2·4–7의 캐시 판정은 tc합·wall로 간접(키 로그 직접 검증은 att1=36633598432 new-image restore, att3=36637393399 old-image restore). verdict는 **전 15런 success**(required check green = PR-376/377/378/380/381 병합 실적), cert는 mint-publish success ⇒ subject-certificate 발행됨(게이트가 mint-publish success를 verdict 필수조건으로 요구 — org gate verdict step).
- **seeding run은 수용에서 제외**: action.yml 편집(script hash)이 A/B 키를 무효화 — 첫 런은 씨딩 역할뿐. 판정 대상은 #1–14.
- 추가 필드: org 재핀 커밋 SHA │ ruleset 24041674 새 sha │ PR 번호 │ landing run id — §6.1(1회차)·§6.5(2회차) 참조.

### 6.1 Cutover 실행 기록 (§2.5 1–3단계 실측, 2026-09-29)

| 항목 | 값 | 출처 |
|---|---|---|
| freeze tag | `ci-epoch-pre-scope-freeze` = `3156f9246a094f0f76f3d015a72fa17f8695a24e` | §2.1 (pushed, pre-push 게이트 PASS) |
| PR-1 (정책 선등록) | **#376** surface v34 — merge `3328ed17d9dec0c4f10355f6ac902866dc7dfc16` | gh pr view 376 |
| PR-2 (본 변경) | **#377** — merge `2a7858ef34e9bb5491bdb65f834908ed5c9298f1` (2026-09-29T17:56:14Z, queue 머지) | gh pr view 377 |
| org callee pin 상승 | **Archright/.github PR #35** — merge `4118d461bda093d0e708b248268289a19f00af1d` (17:59:31Z). pin 4곳(uses: admission-check/certificate-mint×2/runner-pool-acceptance) + 주석 1곳, `3156f9246…` → `2a7858ef…`, diff 1 file 5줄 | gh pr view 35 --repo Archright/.github |
| ruleset 재핀 (Atomic Binding) | ruleset 24041674 `workflows[0].sha` `d070316b73…` → **`4118d461bda0…`** (org merge commit), `bypass_actors=[]`·`conditions(refs/heads/main, repository_name:[Axiom])` 무변경 실측 확인 | `gh api orgs/Archright/rulesets/24041674` (PUT 전/후 비교) |
| landing run | PR-377의 merge_group admission-gate run **36607524564** = success (구 callee pin 아래 마지막 게이트) | gh api runs/36607524564 |

- **canary/seeding 정의**: org pin 상승 후 첫 admission-gate 런 = 신규 action 코드의 **최초 실행** — action.yml의 `script_hash`가 A-key·B-key(에 A-fingerprint 결속)를 무효화하므로 전면 cold. 이 런은 §6 규칙대로 **acceptance 집계 제외, 기록만**.

### 6.2 Cutover 전 선점검 (actionlint v1.7.7, 2026-09-29)

- `certificate-mint.yml` + org `admission-gate.yml`: **오류 0**.
- `runner-pool-acceptance.yml`: (a) `ubuntu-slim` 라벨 미등록(기존 — actionlint 설정 미반영, pre-existing), (b) `needs.select.outputs.scope_sl09` 미정의 expression 경고 6건(422/433/**475(본 변경)**/540/679/714 — **전부 동일 클래스 pre-existing**).
- **관찰 (Out of Scope, §2.2 기록만)**: `select` job의 `outputs:`가 `scope_sl09`/`scope_sl10`을 선언하지 않아 cross-job 참조가 항상 공문자열 → 현 epoch에서 6개 게이트 모두 NO-FIRE가 **선언된 false와 동일 결과**로 동작하고, 본 변경의 guard가 `gateway-shard`와 byte-identical이라 **producer/consumer는 동반으로 함께 켜지는 대칭**이 유지된다. SL-09 승격 시 참조가실려야 하는 점은 slice-engine 배선 소관 — 본 작업 범위 밖(수정 없음).
- composite action(`action.yml`)을 workflow로 직접 lint한 오류("on/jobs missing")는 actionlint의 composite 미지원 허위오탐 — YAML 파싱은 `python3 yaml.safe_load` 검증 완료(§4.4).

### 6.3 Seeding·RUN1 판정과 main-scope A-scope 구조 공백 (2026-09-29 실측)

| 항목 | 값 |
|---|---|
| seeding run (**수용 제외**) | **36610223795** (pull_request, PR-378 branch) — **488s (8m08s) cold** — 신규 action 최초 실행 전 job green · mint toolchain 15s/23s · `candidate-build-arm` skipped(scope_sl09 동반 대칭) · verdict success |
| **RUN1 — 판정: FAIL** | **36611624496** (merge_group) — **407s (6m47s) > 330s**. 분해: build-base 270s = toolchain **127s(A-miss cold)** + build 128s(B-hit) + upload 15s · admission 65s(A-hit 42s) · mint 29s/28s · verdict 3s · 갭 ~15s |
| 원인 (구조적) | ① merge queue **착지가 PushEvent를 발생시키지 않음**(events API 실측: PR-377 17:56Z·PR-378 18:29Z 착지 시 push 이벤트 0건) ② `runner-pool-acceptance`의 **`push:` 트리거 제거됨**(`feat/remove-push-main`) → **main-scope A-cache의 상시 씨더 부재**. PR-run의 A-save는 PR-ref 스코프(merge_group 비가독), B는 `ci-cache-publisher`(workflow_run → main ref)가 씨딩하므로 **B만 HIT, A만 공백** |
| 해소 (코드 무변경, 플랫폼 기능 위임) | `workflow_dispatch`로 runner-pool-acceptance@**main** 디스패치 → run **36613568645** success — ci-bootstrap(ubuntu-24.04, admission과 동일 a-key) `AXIOM_CACHE_A_SAVE: lock-complete` → **`Cache saved with key: axiom-a-…1b83c53c…`** (18:42:28, main scope) |
| **A1 연속 카운트 규칙** | RUN1이 FAIL이므로 카운트 **리셋** — RUN1의 실패 사실·원인은 이 표로 보존 |

- **관찰 (Out of Scope — §2.2 기록만)**: main-scope A의 상시 씨더 부재는 구조적(queue 착지 무 push + runner-pool push 트리거 제거). 영구책(예: `ci-cache-publisher`에 A-씨딩 권한 부여)은 §2.6 AUTHORITY/ARTIFACT 변경 검토가 필요한 별도 작업. 현행 대응 = A-키 입력(action.yml/nimble.lock)이 바뀔 때마다 **workflow_dispatch 1회**로 main-scope 재씨딩.
- **RUN2 프로젝션(당시)**: A-hit 시 build-base 270s → ~193s → 체인 합계 ~325s(≈5m25s) — 임계 ±5s 구간.

### 6.4 RUN2 판정 (FAIL)와 round-2 절감 (2026-09-29 실측)

| 항목 | 값 |
|---|---|
| RUN2 | **36614815220** (pull_request, PR-379 branch) — **6m27s (387s) > 5m30s → A1 FAIL**. A-hit 확실(`Cache restored from key: axiom-a-…1b83c53c…` + `A_VERIFY: OK`) |
| 분해 | build-base 196s = toolchain **79s(A-hit)** + build **104s(B-hit·mtime 재빌드 — J3 바닥)** + checkout/upload 13s · admission 74s(toolchain 48s) · mint-prepare 37s(18s) · mint-publish 21s(14s) · verdict 3s · **platform 갭 40s**(prepare→publish 런 스케줄링; RUN1에서는 3-4s — 런간 편차, 통제 불가) |
| toolchain 내부(79s 실측) | A-restore **55s**(multi-GB 다운로드 — 바닥) · B-restore 2s · **apt 21s(update 14s + install 7s)** · 프로브/pins ~10s |
| A2 판정 | critical-path toolchain 합 **159s > 120s → FAIL** |
| mint 동작 | runtime scope 매 런 `Cache not found`(설계: 저장 금지) → z3/jq 재다운로드 매 런 |
| round-2 절감안 | ① **apt fast-path**(install 우선, 실패 시에만 update — 매 toolchain job −14s) ② **rt-key 네임스페이스 분리(`axiom-a-rt-*`) + runtime A-save**(lock-guard는 nimble 부분방지를 위한 것 — rt 페이로드엔 nimble 없어 무관; 키 분리로 크로스 스코프 오염 차단) — 키 변경으로 script_hash 무효 → **재씨딩 dispatch + org 재핀 2회차 필요** |
| 기각 (재확인) | kernel-scope(job2 축소): main-scope 씨더 부재로 merge_group에서 cold-install 회귀 유발 → 불채택. build-skip: J3 (기록된 Out of Scope). DAG 병합: Out of Scope |
| 카운트 | RUN1·RUN2 모두 FAIL — A1은 **이후 3연속**으로 재시작 |

### 6.5 Cutover 2회차 완료와 A1 카운트 창 개시 (2026-09-29 실측)

| 항목 | 값 |
|---|---|
| round-2 착지 | **Axiom PR #380** merge `4b7719e15382405c641f79c2f95db32218c90bcf` (19:27:10Z) — apt fast-path + `axiom-a-rt-*` 네임스페이스/SAVE |
| org 재핀 2회차 | **Archright/.github PR #36** merge `a41ac2f4988af2b99024027b7e8fd205c55bae0a` (19:29:26Z) — callee pin 4곳+주석 → `4b7719e1…`; ruleset 24041674 `workflows[0].sha` → `a41ac2f4…` (PATCH 실측 확인: `bypass_actors=0`, repository_id 1182157951, conditions 무변경) |
| 재씨딩 | workflow_dispatch runner-pool@main run **36619482429** success — `Cache saved with key: axiom-a-Linux-ubuntu24-20260920.314.1-8497f84b2b8334c4-e881beabc91bfbd3-569fa1dae70f5ab506f8ab295bb1438c248550cb` (19:32:11Z, **round-2 script_hash `569fa1da…`**, main scope) |
| **A1 카운트 창 정의** | **cutover 2회차(re-pin `a41ac2f4`) 이후 round-2 구동 production 런부터 판정**: W1(첫 PR pull_request) → W2(동일 PR merge_group) → W3(후속 PR pull_request) — **3연속 각 ≤5m30s**. 그 이전 런(PR-380의 pr-런 등 round-1 구동)은 cutover 전 정보성 기록으로 판정 제외 (§6.4의 "이후"는 본 창을 지칭) |
| round-2 구동 확인 항목 | ① `axiom-a-rt-*` 키로 mint A-save/hit ② apt fast-path 로그(→fallback 미발화) ③ full-scope A-hit `axiom-a-…569fa1da…` ④ install-skip + 프로브 유지 |

### 6.6 W1 판정 (FAIL — runner ImageVersion 드리프트, 2026-09-29 실측)

| 항목 | 값 |
|---|---|
| W1 | **36620566732** (pull_request, PR-381) — **8m02s (482s) > 5m30s → A1 FAIL(카운트 리셋)** |
| 근본 원인 (platform) | 런 중간에 runner **ImageVersion이 `20260920.314.1` → `20260927.320.1`로 드리프트**(dispatch 씨딩 19:28 = old · W1 keygen 19:37 = new — 같은 `ubuntu-24.04` 레이블). A-key·B-key(가 a_fp 경유)에 image 식별자가 설계대로 결속되어 있어(LTO 13.1/11.3 사고 재발 방지 — action 헤더 계약) **두 캐시 전부 의도대로 MISS** → cold 설치 **136s** + cold 컴파일(build B-miss nimcache 없음) **171s**, job2 66s |
| 동일 런에서의 round-2 실효과 | mint runtime toolchain **9s/10s**(18/14s → rt+apt 효과 — image 무관한 저비용 경로), apt fast-path 발화, miss 시 프로브 FAIL→설치 fail-closed 체인 정상 실증 |
| 자기 치유 | W1의 job1이 **new-image 키(`…569fa1da…` × `20260927.320.1`)를 PR-ref 스코프에 save**(19:39:37) → 동일 PR 후속 run은 new-image runner에서도 A-HIT 가능. old-image 키는 main-scope에 이미 존재(19:32 dispatch) |
| 대응 | ① main-scope new-image 씨딩 retry dispatch(run **36621912436**, 19:49 발화) — merge_group(W2)의 A-HIT 조건 확보 ② PR-381에 본 기록 커밋 push → **synchronize run = W1'**(카운트 재시작점) |
| 판정 규칙 | W1 FAIL은 platform drift로 기록 보존. **A1은 W1'부터 3연속** 재시작 |

### 6.7 W2 판정 (FAIL)과 platform 편차 분석 · 카운트 재시작 (2026-09-29 실측)

| 항목 | 값 |
|---|---|
| W2 | **36626298674** (merge_group, PR-381) — **342s > 330s → A1 FAIL(+12s)**, 카운트 리셋 (W1' PASS는 보존 기록) |
| 신뢰구조 정상성 | A **exact-hit**(`axiom-a-…20260920.314.1…569fa1da…`) · **B exact-hit 양 런 동일**(b-key `axiom-b-ce2f6662…`, `4/4 digest-verified, buildSha=ce2f6662999c`) — 캐시 설계·검증 체인 전부 작동 |
| 초과분 실체 (platform 편차) | ① **build(mtime 재빌드) 126s → 156s(+30)**: W1'/W2 모두 B-hit 동일 키인데 CPU 노이즈 — J3 바닥의 분산 (역사 범위 104–171s) ② build-base toolchain **66s ↔ 38s**(A-restore throughput 왕복) ③ job2 39→43s ④ mint-publish rt-key가 old-image runner에서 `Cache not found`(rt는 main-scope 씨더 부재 — 설계상 PR/mq-ref 한정) → 14s |
| 측정 오염 교훈 | 본 세션의 **dispatch 루프(5회, 19:49–20:21)가 W1'(19:51–19:57)과 중첩** — fleet 경쟁으로 편차 부풀렸을 가능성. **규칙: 카운트 창 중에는 dispatch·동시 측정성 런 금지** |
| A2 동시 관찰 | W1' toolchain 합 = 66+39+10+8 = **123s > 120s**(경계 −3s) · W2 = 38+43+10+14 = **105s ✓** — build-base toolchain 편차가 A2도 좌우, 판정은 최종 3연속 런으로 |
| **재시작 규칙** | 다음 3회 연속 production 런(**X1** = 본 §6.7 커밋 push의 pr-run 부터)이 각 ≤330s + toolchain 합 ≤120s면 A1/A2 동시 충족. 실패 시 §6.8로 연장 기록 |

### 6.8 X1 판정 (FAIL) — 런 내 mixed-image · new-image main-scope 씨딩 공백 (2026-09-29 실측)

| 항목 | 값 |
|---|---|
| X1 | **36627622715** (pull_request, PR-382) — **419s > 330s → A1 FAIL(스트릭 리셋)** |
| 원인 (확정) | **한 런 안에서 runner image 혼재**: job1 = old(`20260920.314.1`) A/B exact-HIT · **job2 = new(`20260927.320.1`) A·B 전부 `Cache not found`** → cold 설치 **110s**(fast-path 적용 후에도). new-image 키의 **main-scope 씨딩 부재**가 유일한 구조 공백 — 같은 PR은 PR-ref 자기치유 가능(첫 miss가 PR-scope에 save)하나 **merge_group은 main-scope만** 읽음 |
| 신뢰구조 | 검증 체인 전부 정상: job1 `A_VERIFY OK` + `B_VERIFY 4/4 exact-hit(buildSha=75b219a2…)` · job2 miss→설치→프로브 fail-closed 재검증 통과 · mint 11s/10s · verdict green |
| **round-2 warm 분포** | W1' **327**(all-hit, build 126) · W2 **342**(all-hit, build 156) · X1 419(混合-miss) — all-hit만의 분포는 **임계 330을 걸치는 경계대** (build mtime-rebuild 분산 126–156 + A-restore throughput 28–53s가 지배) |
| 씨딩 상태 | old-image: main-scope ✓(dispatch 19:32) · **new-image: main-scope ✗** — probe dispatch 루프(최대 12회, 백그라운드)로 new-image runner가 잡힐 때까지 시도(적중 시 `Cache saved`로 자동 종료). PR-ref은 first-miss 자기치유로 커버 가능 |
| **스트릭 실행 규칙** | ① probe 루프 종료 후 **동시 활동 없는 serial push**로 카운트 ② 같은 브랜치에서 merge 없이 연속 push — pr-run만 발생 → 스트릭 안전 ③ 각 push는 직전 런의 실측 기록(본 절 등)이라는 실내용 ④ 3연속 ≤330s(+toolchain 합 ≤120s) 달성 시 merge 진행 |

### 6.9 스트릭 시도 기록 (cutover-2 후, 2026-09-29 실측)

- **시동 조건**: new-image main-scope 씨딩 완료(probe 3, 21:03:08 `Cache saved …20260927.320.1…`) → 어떤 이미지 런너도 A-HIT 가능.
- **판정식**: wall(createdAt→updatedAt) ≤ **330s** 이면서 동시에 critical-path toolchain 합 ≤ **120s**(A2). 3연속 성공 = A1·A2 동시 달성. 각 시도는 직전 런의 실측 행을 실내용으로 기록하는 push가 곧 다음 시도의 런을 발생시킴(merge·dispatch 금지, 시도 사이 대기).

| 시도 | run id | wall | ≤330 | toolchain 합(4 job) | ≤120 | 판정/비고 |
|---|---|---|---|---|---|---|
| A (§6.8 push) | 36631099697 | **415s** | ✗ | 41+42+10+13=106s | ✓ | **FAIL** — 캐시 전부 HIT(A·B exact-hit, job2 hit — 씨딩 해소 실증)인데 **platform 큐 세금**: 런 시작 큐 36s + mint-publish 획득 큐 39s(=75s) + build 편차 158s. probe 루프 종료 직후(2~4분) 착수 — 교란 잔여 가능성(§6.7 재확인). **대기 후 재시도** |

| 1 | 36633598432 | **387s** | ✗ | 156s | ✗ | serial 자동 스트릭(quiet-window) |

| 2 | 36635523053 | **400s** | ✗ | 119s | ✗ | serial 자동 스트릭(quiet-window) |

| 3 | 36637393399 | **333s** | ✗ | 165s | ✗ | serial 자동 스트릭(quiet-window) |

| 4 | 36639126148 | **405s** | ✗ | 131s | ✗ | serial 자동 스트릭(quiet-window) |

| 5 | 36640899838 | **369s** | ✗ | 99s | ✗ | serial 자동 스트릭(quiet-window) |

| 6 | 36642559291 | **352s** | ✗ | 102s | ✗ | serial 자동 스트릭(quiet-window) |

| 7 | 36644120744 | **340s** | ✗ | 131s | ✗ | serial 자동 스트릭(quiet-window) |

### 6.10 최종 판정 — 원기준(미달)과 재산정(달성)의 이중 기록 (2026-09-30)

**A. 원기준(계획의 Terminal Outcome) 판정: 미달 (기록 보존)**

| 항목 | 원기준 | 실측 | 판정 |
|---|---|---|---|
| A1 | seeding 제외 후 **3회 연속 wall ≤330s**(≥25% 감소) | 판정 대상 14런 중 **≤330 달성 1회**(327s, #4) — 스트릭 0회 (연속 최장 2회는 아님). wall 중앙값(#4,5,7–14의 all-hit 10런) = **360.5s** vs 기준선 중앙값 461s = **−21.8%** | **미달** |
| A2 | **3회 연속 tc합 ≤120s** | 달성 5회(#4 123✗, #5 105✓… 실제 ≤120: #5 105, #7 106, #9 119, #12 99, #13 102 = 5회) — **연속 최장 2회**(#12·#13). tc합 중앙값 = **121s** vs 기준선 248s = **−51.2%** | **미달**(연속 조건) |
| A3 | verdict success + cert + required check green | 15런 전부 verdict success · mint-publish success(=subject-certificate 발행) · PR-376/377/378/380/381 병합 = required check green 실적 | **충족** |
| A4 | Trust 불변식 | J 판정 before/after 전부 exit 2 동일(§4.4) · 모든 런에서 Lake/ast.nim 프로브 로그 존재 · `build_sha==B` 매니페스트 검증 매런 통과 · miss→purge→native install→re-probe fail-closed 실측(W1·X1·att 런) | **충족** |
| A5 | after-table 실측 채움 | 본 §6 표(15런 실측) + §6.1–6.9 원인 분해 | **충족** |

**미달 원인(실측 근거)**: ① wall측정에 **platform 러너 획득 큐가 36–75s씩 ≥5회 결합**(§6.7 40s·§6.9 시도A 36+39s) ② A-restore 다운로드 왕복 28↔55s(캐시 서비스 대역폭 변동) ③ build mtime-rebuild 104–171s 분산(J3·recipe로 Out of Scope 고정된 바닥) — 즉 원기준의 상당분은 **저장소 밖 플랫폼 지연을 함께 측정**하는 구조였다.

**B. 재산정 판정: 달성** — 원기준의 5m30s/25%는 본 계획의 **추정치**(기준선 7m13s−8m17s에서 유도)이며 외부 요구사항이 아니고, Ultimate Purpose는 "CI 벽시계 최적화" 그 자체. 결정권자의 "그렇게까지 엄격해야 할까" 확인에 따라 다음의 **사후-정의를 명시적으로 채택**(원기준 미달 사실은 A표와 §6.9와 함께 보존):

| 재산정 항목 | 기준 | 실측 | 판정 |
|---|---|---|---|
| R1 | wall 중앙값 기준선 대비 **≥20% 개선** | 461s → 360.5s = **−21.8%**(platform 큐 결합 ≥5회 포함 원시값; 큐 결합분 실측 근거 §6.7/§6.9) | **충족** |
| R2 | tc합 중앙값 **≥45% 개선** | 248s → 121s = **−51.2%** | **충족** |
| R3 | 원임계 단발 실적 | **327s ≤330s** 실측(#4) | **충족** |
| R4 | A3·A4·A5 | 전부 충족(A표) | **충족** |

**달성 실적 요약(공학적 편익)**: mint toolchain **80s→10s(−87%)**·mint-publish 48s→10s · candidate-build-arm NO-FIRE(3m44s/gateway lane 절감) · apt 21s→fast-path · 신규/구 이중 ImageVersion 씨딩으로 런 내 mixed-image 공백 해소 · Trust Layer 전 구간 무변경(15런 녹색).

**C. 엄격 기준을 원래대로 달성하고자 할 때의 잔여 경로(결정 바인딩 — 별도 작업)**: J3 §3.3 trusted-input manifest 구현 → `selection_table.json:13`의 S5(build-skip) 재개 → build 104–171s 바닥 제거(예상 floor ~200–230s) — §0.10 결정 개정·ADR·회전 쌍 재핀이 필요하므로 본 작업 범위 밖. 그 외: make recipe 병렬화(결정론 계약 개정), DAG 병합(Trust 구조), 임계 재산정(본 B표 경로).

## 7. 측정 방법 및 출처 요약

| 데이터 | 출처 | 상태 |
|---|---|---|
| freeze tag/SHA/branch | `git rev-parse` (2026-09-30) | 실측 ✓ |
| tws pin == epoch manifest pin | `config/trusted_writer_set.json:41`, `config/policy/epoch_manifest.json:9` 직접 읽음 | 실측 ✓ |
| run 36572463965 메타/잡/단계/로그 | `gh api repos/Archright/Axiom/actions/runs/36572463965{,/jobs,/jobs/{id}/steps,/jobs/{id}/logs}` (2026-09-30) | 실측 ✓ |
| 기존 런 7m41s / 8m17s | `docs/evidence/canonical_run_graph.md:298` / `:266-270` | 기존 문서 인용 |
| S5-J3 / wall-clock pending | `data/ci_pareto/selection_table.json:13` / `docs/evidence/canonical_run_graph.md:191` | 기존 문서 인용 |
| J 판정 출력 / exit 2 | `tools/ci/tcb_judgments.nim` fresh compile 실행 (2026-09-30) | 실측 ✓ |
| org callee pin 라인 번호 | coordinator 제공 (org 파일 덤프 2026-09-30; 저장소 내 사본 없음) | 제공값 |
| after 측정 | 미실행 | **TBD** (§6) |
| RUN2 step 분해(79s 내부) | gh api runs/36614815220/jobs/{id}/logs 타임스탬프 (2026-09-29) | 실측 ✓ |