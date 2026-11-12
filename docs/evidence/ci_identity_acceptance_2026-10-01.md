# CI Identity 수용 실측 — S/D 사이클 시딩 기록 (2026-10-01 UTC)

- 규범: 수용 측정 프로토콜(agent-fsh68eth) + C0 실측 보고(agent-5v95n9xc) + AGENTS.md §2.3
  (완료된 런만 열람, 네이티브 waiter, 단발 쿼리 ≥30s, 수동 폴링 금지).
- 이 파일 = S 사이클(본 PR)의 프레임 기록 — 근거는 저장소/런 실측만, 주장 금지.
- 시간대: 전부 UTC (머신 시계 2026-10-01; 로컬 KST 10-01).

## ① 목적 (Terminal Outcome ①②③) + build identity 정의

Terminal Outcome(측정 규범 §3~§5, C0 보고 ②):

- **①** 동일 build identity당 콜드 컴파일 ≤1회 (면제: 각 identity의 창 내 첫 콜드 1회 = 시딩)
- **②** 검증 산출물 매 run 전건 신규 발행
- **③** push@main run 0건

**build identity 정의** = b-key 전체 = `axiom-b-<b-identity>-<recipe_hash32><a_fp32>`; b-identity =
빌드-소스 **tree OID**, a_fp = toolchain/script 결속(script_hash 경유). 등식: 동일 b-key ⟺
(동일 트리 ∧ 동일 레시피 ∧ 동일 toolchain fp) — contract = 실행되는 action.yml/script 집합
(script_hash) (census §2).

**base b-key = base 트리 OID 결속** → main 변경(=어떤 머지)마다 새 identity.
cross-PR 소비 실증 구조: S·D가 **같은 main(3729788d6, tree T2=`c4d687965453ff83ef05691a2af8e7d60cd26f6c`)을 base**로 갖고,
S의 PR 페이즈 퍼블리셔가 T2를 시딩 → D의 PR 페이즈가 T2를 소비(HIT) — 그 실측이 본 기록의 목적.

> **재기준 각주 (v38)**: 정책 선등록 PR #408(2026-10-01 18:24Z 병합, 기록 경로 CONTROLLED 등록
> `config/repository_surface.json` v38) 후 본 사이클 base가 61ee9090(T1, tree `c4d18677eaf3`)에서
> 3729788d6(T2, tree `c4d6879654`)로 **재기준**됨. #407 착지=61ee9090(T1) 사실은 아래 역사 서술로 보존한다.

## ② PR #407 L1/L2/L3 증거(JSON 원문) + 런 ID

**L1** — `gh api repos/Archright/Axiom/commits/e369ed67fd78791927599f518379b07e47315bf6/check-runs`
(2026-10-01 재관측, 정본):
```json
[{"completed_at":"2026-09-30T16:09:25Z","conclusion":"success","name":"admission-check","status":"completed"},
 {"completed_at":"2026-09-30T16:07:45Z","conclusion":"success","name":"admission / admission-check","status":"completed"},
 {"completed_at":"2026-09-30T16:06:16Z","conclusion":"success","name":"admission / build-base-artifacts","status":"completed"},
 {"completed_at":"2026-09-30T16:09:18Z","conclusion":"success","name":"gateway / ci-bootstrap","status":"completed"},
 {"completed_at":"2026-09-30T16:08:43Z","conclusion":"success","name":"mint-publish / publish","status":"completed"},
 {"completed_at":"2026-09-30T16:08:20Z","conclusion":"success","name":"mint-prepare / prepare","status":"completed"}]
```
- C0 보고 원문(머지 직전): `[{"completed_at":"2026-09-30T16:07:45Z","conclusion":"success","name":"admission / admission-check","status":"completed"}]`.
- **L1 교차**: ruleset 24233738
  `{"enforcement":"active","id":24233738,"name":"axiom-admission-gate","req":[],"target":"branch"}`
  — required checks **`[]`** → §2.3 불변식 3 귀속(0 checks = UNKNOWN/NOT READY, SUCCESS 해석 금지).
  org ruleset 24041674은 현재 토큰 404(목록에도 없음) → **UNKNOWN-by-scope**.

**L2** — merge queue GraphQL (2026-10-01 재관측, 착지 후):
```json
{"data":{"repository":{"mergeQueue":{"entries":{"nodes":[]}}}}}
```
- #407 큐 진입 직후 원문(C0 보고): `{"data":{"repository":{"mergeQueue":{"entries":{"nodes":[{"state":"AWAITING_CHECKS","position":1,"pullRequest":{"number":407}}]}}}}}`

**L3** — `gh pr view 407 --json state,mergedAt,mergeCommit,headRefOid` (2026-10-01 재관측):
```json
{"headRefOid":"e369ed67fd78791927599f518379b07e47315bf6","mergeCommit":{"oid":"61ee909020a24e5392ee89643bf37bf80ee63734"},"mergedAt":"2026-09-30T16:19:15Z","state":"MERGED"}
```
- 착지 SHA 61ee9090 == MG 런 head_sha 일치(등식 실측, C0 보고). merge commit tree =
  `git/commits/61ee9090` REST 재관측: `{"sha":"61ee909020a24e5392ee89643bf37bf80ee63734","tree":"c4d18677eaf320c7fa14eabde5b5949fd68f931b"}`.

**C0 4런 + 퍼블리셔 2런 (전부 completed+success)**:

| 런 | 역할 | ID | 구간(UTC) |
|---|---|---|---|
| PR | admission-gate pull_request | 36741228869 | 16:02:05→16:09:26 |
| PR-fire | ci-cache-publisher (RUN_ID: 36741228869) | 36742139904 | 16:09:30→16:09:49 |
| MG | admission-gate merge_group (head 61ee9090) | 36742427910 | 16:11:51→16:18:50 |
| MG-fire | ci-cache-publisher (RUN_ID: 36742427910) | 36743284565 | 16:18:54→16:19:15 |

## ③ C0 실측 표 (구/신 혼재를 base 트리 소유로 귀속 — C0 = pre-change baseline)

키 정의: `b_key = axiom-b-<트리>-<recipe d807d897… 고정><a_fp>`; script_hash 실측: 구(main)=
`569fa1dae70f5ab…`, 신(PR head)=`f68ce8afffa41d…`. 형태 판별 = a-key 이미지 라벨 세그먼트 유무.

| 런·잡 | KEYGEN 형태 | b-identity(트리) | a_fp | B 상태 |
|---|---|---|---|---|
| PR·build-base-artifacts(base 트리) | **구**(`…ubuntu24-20260920.314.1-…-569fa1dae…`) | 16a83f1a2d19 | 14fc017c… | **MISS(콜드)** |
| PR·ci-bootstrap lane(merge ref 트리) | **신**(`…-8497f84b…-e881beabc…-f68ce8af…`) | c4d18677eaf3 | f53165a6b8… | **MISS(콜드)** — 신 scheme 첫 등장 |
| PR·admission-check(base) | 구(image 20260927.320.1) | 16a83f1a2d19 | 3cfae1a3… | MISS(복원 소비) |
| PR·mints(B 트리) | 구 rt | — | — | 비계수(컴파일 없음) |
| **PR-fire 36742139904** | 신(keygen) | c4d18677eaf3 | f53165a6b8… | **`Cache saved with key: axiom-b-c4d18677…-f53165a6b8…`**(lane 시드) / verdict `[publish] guard=true trees=true verify=true key=…` / **base 라인 없음(구 publisher 코드)** |
| MG·build-base-artifacts(base) | 구(…20260920.314.1…) | 16a83f1a2d19 | 14fc017c… | **MISS(콜드)** — 동일 b-key C0 내 2회째(주의: pre-change baseline, 계수 아님) |
| MG·ci-bootstrap lane(queue head 61ee9090) | 신 | c4d18677eaf3 | f53165a6b8… | **HIT**: `Cache hit for:` + `Cache restored from key: axiom-b-c4d18677…-f53165a6b8…` + `AXIOM_CACHE_B_VERIFY: RESULT OK — 4/4 entries digest-verified, buildSha=c4d18677eaf3, key exact-hit` |
| MG·mints(B 트리) | 구 rt | — | — | 비계수 |
| **MG-fire 36743284565** | 신(keygen) | c4d18677eaf3 | f53165a6b8… | verdict verify=true + `Failed to save: Unable to reserve cache with key … another job may be creating this cache`(중복 save 비치명) / **base 라인 없음(구 코드)** |

- **귀속**: C0는 base 트리(2b35e1f3=main) 소유의 **구 action**으로 실행(구 script_hash
  `569fa1dae…` = main 재현값 일치) → **C0 = pre-change baseline**. lane/퍼블리셔의 신 키는
  변경 PR 자신의 트리(합성 머지 트리) 신 action 산출 — 구·신 혼재를 base 트리 소유로 판별.
- ② 관련(C0): 두 게이트 런 모두 `admission-check-base-artifacts`/`admission-check-<head>`/
  `subject-certificate-1`/`ci-bootstrap-artifacts` 존재. **executed-ci-bootstrap 부재**
  (PR·MG 둘 다 skipped). **MINT_PUB … append 1 라인 비발화** — slice-engine
  `epoch=N+6 implemented=[SL-08,SL-01,SL-03,SL-04,SL-12,SL-10] sl0713=NO-FIRE` 실측(설계 귀속);
  대신 `MINT_PUB_ART/DIGEST/AX/BIND: OK`×4 · `MINT_A0_ACTIVATION: OK` · `MINT_MBH: OK
  B=2b35e1f3de6a H=e369ed67fd78 PR=#407` · `MINT_BASEART: OK (id=11111110324, build_sha==B)` ·
  `MINT_ID: OK` 실측. `[verdict]`: **PR 페이즈 0건(부재)**, **MG 페이즈 실측** —
  `[verdict] OK — admission ∧ mint-prepare ∧ mint-publish ∧ gateway callee succeeded` (16:18:47Z).

## ④ 신 scheme cross-phase 소비 첫 실증 (C0 lane seed → MG HIT)

- **PR-fire 36742139904** (신 scheme, keygen): `Cache saved with key: axiom-b-c4d18677…-f53165a6b8…`
  — lane 시드 / verdict `[publish] guard=true trees=true verify=true key=…` — **base 경로 없음(구 코드)**.
- **MG 36742427910** ci-bootstrap lane: `Cache hit for:` + `Cache restored from key:
  axiom-b-c4d18677…-f53165a6b8…` + `AXIOM_CACHE_B_VERIFY: RESULT OK — 4/4 entries
  digest-verified, buildSha=c4d18677eaf3, key exact-hit`.
- 판정: 이미지 라벨 제거 신 scheme의 **cross-phase 소비 성립(재컴파일 0, 콜드 1회)**.
  단, **base 경로는 C0에서 미시딩(구 publisher 코드)** — base b-key 시딩 체인의 첫 실증은
  본 S 사이클(신 publisher 첫 발화) 이후의 측정이다.

## ⑤ ③ push=0 PASS (창·24h)

- `gh api "repos/Archright/Axiom/actions/runs?event=push&branch=main&created=>=…&created=<…"`:
  창(16:19:15Z 이후 관측 구간) 내 `total_count: 0` · 최근 24h `total_count: 0` (C0 보고 원문,
  2026-10-01 재관측 생략 — 창 내 신규 머지 0건이므로 상태 불변).

## ⑥ S/D 정의

- **본 PR(`ci/identity-acceptance-baseline`) = S**: base 3729788d6(T2, v38 재기준). 기대(측정 대기):
  base 잡 KEYGEN 신 형태(이미지 라벨 없음) + T2 base b-key **MISS(콜드 1회 = 시딩)**, lane
  상태(신 identity 콜드), 퍼블리셔 **신 코드 base 경로 첫 발화**(verdict `base-guard=… base-verify=…
  base-key=…` 라인 + `Cache saved with key: axiom-b-<T2>` = base 시드).
- **동일 base의 직후 PR(`ci/identity-residual-r10`) = D**: base 잡 b-key T2 →
  **HIT 기대**(`Cache restored from key: axiom-b-<T2>` + `AXIOM_CACHE_B_VERIFY: RESULT OK`) —
  cross-PR 소비 성립의 결정적 증거. **MISS면 원인(퍼블리셔 시드 실패/타이밍)과 함께 정직 기록**.
- 머지 순서(후속 단계): S 머지 → D 머지(동일 base 3729788d6 유지) → MG 페이즈 측정
  (S-MG의 T2 HIT, D-MG) — 본 PR은 **머지하지 않는다**.

## ⑦ UNKNOWN (C0 보고의 UNKNOWN 전부 재인용)

1. org ruleset 24041674 404 → L1 교차 권위 한계(UNKNOWN-by-scope). repo ruleset req=[] → 불변식 3 귀속.
2. **S/D 사이클 미발생 상태의 지표 ①② 판정 + 신 publisher 코드(base 경로 `[publish]
   base-guard=… base-verify=… base-key=…`)의 첫 발화 + base b-key 시딩 체인 소비 검증 —
   본 S/D 사이클(base T2)에서 측정 대기. (C0 관측 기준: base 키 T1은 C0 lane 시드와 동일
   키라 v38 사이클 PR/MG 모두 HIT — T1 신형 콜드는 v38 사이클에서 성립하지 않았음.)
3. `MINT_PUB … append 1`: epoch N+6 SL-0713 미정착으로 설계상 비발화(창 내 모든 런 해당
   예상 — epoch manifest 변경 없음; slice-engine `sl0713=NO-FIRE` 실측 귀속).
4. executed-ci-bootstrap skip 조건(발화하는 decision 스코프) 미관측.
5. `[verdict]` PR-페이즈 부재의 org caller 배치 구조 — repo 표면에서 미관측.
6. C0 lane HIT의 컴파일 step 벽시계 절감 대조(미추출).
7. 창 밖 컴파일 이력(census §7: `c5f999f7`/`6f2ba8e9` identity의 창 전 컴파일) — 미측정.

## FOLLOW-UPS

- **`.github/workflows/certificate-mint.yml:166`** — 주석 "The two-layer cache key now ALSO
  binds the runner image identity (ImageOS/ImageVersion) + gcc/glibc fingerprints … so image
  drift can never re-enter the memo (Phase 3 L2)": a_key 이미지 라벨 제거(#407,
  LABEL_NOISE, 2026-10-01) 후 **stale 주석** (라벨은 더 이상 키 결속 원소가 아님 — R9 (b)
  참조). 금지 파일(callee 핀 등록 — org gate callee SHA pin 재등록 경로 외 수정 금지) →
  **callee 회전 시 후속 수정 대상**으로 기록만 한다.

---

# ⑧ 최종 판정 (Phase 5 — 2026-10-01, main 착지 후 `6fdfe8ba`/T_D)

> 이 섹션은 전 사이클(S/D/F/F2/v38 + #407)의 실측을 원문(런 ID·로그 라인·L3 JSON)으로
> 계승한 종합 판정이다. 근거 없는 주장 없음 — 모든 수치는 아래 인용 관측에서만 도출.

## A. 사이클 결과 전표 (모두 §2.3 L1→L2→L3 경유)

| PR | 브랜치 | head | L3 mergeCommit (트리) | mergedAt | MG 런 | MG base 잡 | MG-fire 퍼블리셔 verdict |
|---|---|---|---|---|---|---|---|
| v38 **#408** | policy/surface-v38 | 09e5e2a5d | `3729788d6` (T2 `c4d6879654`) | 18:24:23Z | 36757540160 | **HIT** `Cache restored from key: axiom-b-c4d18677…` + `AXIOM_CACHE_B_VERIFY: RESULT OK — 4/4 … buildSha=c4d18677eaf3, key exact-hit` (18:18:20) | 36758292055: `guard=false … base-guard= base-verify= base-key=`(공란 — **구 코드** mode=none SKIP) |
| F **#411** | fix/ci-publisher-base-guard-decouple | e240e1c85 | `d53ac0f1` (T3 `e91a33fd`) | 19:22:59Z | 36764372183 | **MISS** `Cache not found …axiom-b-c4d6879654…` (19:15:38 — **결함2 시점 실측**: 키는 REST 존재) | 36765279251: `base-guard=true base-verify=true base-key=…c4d6879654…`(저장 conflict — 기존 키) |
| F2 **#412** | fix/ci-publisher-base-save-path | 205a6a561 | `49ff4c29e` (T4 `f79f4719`) | 19:59:48Z | 36768598544 | **HIT** `Cache restored from key: axiom-b-e91a33fd…` + `RESULT OK 4/4 … buildSha=e91a33fdc6aa` (19:51:57) | 36769475023: `base-guard=true base-verify=true base-key=…e91a33fd…`(9행 입력 저장 — 동일 키+version 존재 → `Unable to reserve`) |
| S **#409** | ci/identity-acceptance-baseline | 3e625abc4 | `3064ec7d` (T_S `67585b8c`) | 20:11:53Z | 36770241367 | **HIT** `Cache restored from key: axiom-b-f79f4719…` + `RESULT OK 4/4 … buildSha=f79f4719e307` (20:06:08) | 36770876844: **mode=none 풀 시연** — `guard=false trees=true verify=false key=` + `base-guard=true base-verify=true base-key=…f79f4719…` |
| D **#410** | ci/identity-residual-r10 | e6831267f | `6fdfe8ba` (T_D `18f47938`) | 20:20:53Z | 36771219320 | **MISS** `Cache not found …axiom-b-67585b8c…` (20:14:38, **T_S 콜드 #1 = 신규 identity 면제**; 원인 = S-MG lane 미빌드) | 36771956426: `base-guard=true base-verify=true base-key=…67585b8c…` + **`Cache saved with key: axiom-b-67585b8c…` (20:21:05) — 9경로 신규키 base 시드 최초 성공** |

- ⑧ 참조용 추가 실측: v38 1차 MG 36756331915 = FAIL(일시 인프라 — select의 choosenim curl `Couldn't resolve host name`) → 재인큐; F-MG lane `e91a33fd` HIT(19:16:31); F2-PR base `e91a33fd` HIT(19:40:36) — version 정합 최초 성공; S-MG ci-bootstrap skipped(mode=none), D-MG ci-bootstrap success(lane `18f47938` 콜드 #1 → D-MG-fire 시드).

## B. 결함→수정 1:1 대장 (원인-수정 1:1 원칙)

| | 결함 (실측 증거) | 수정 (PR) | 수용 실측 (HIT) |
|---|---|---|---|
| 결함1 | **base 시딩 경로가 lane 아티팩트 존재 게이트(`guard.proceed`)에 결속** — S #409 fire 36759930836: `[publish-skip] ci-bootstrap-artifacts absent (mode=none gate…)` → `[publish] base-guard= base-verify= base-key=` 전부 공란. admission-check-base-artifacts가 존재하는데도 시드 안 됨 → T2 base b-key S·D 2회 콜드(지표 ① strict FAIL 원인) | **F1 #411** `proceed_path` 분리: guard에 path∧!fork(아티팩트 무관) 신규 출력, `trees`(verify-base merge_group 앵커 HEAD_SHA)·`base-check`가 proceed_path로 진입, lane 전용 스텝은 guard.proceed 유지 | **S-MG-fire 36770876844 (mode=none 실사이클)**: `base-guard=true base-verify=true base-key=axiom-b-f79f4719…` — base 경로가 lane 부재와 무관하게 완주 |
| 결함2 | **base save 4경로 vs 소비자 restore 9경로 cache-version 불일치** — actions/cache 공식: version은 cache inputs(compression + path 목록)에서 유도. 실측: T1(lane 9경로 저장) `version=c0438c1375be…c782c1c06` 복원 성공 / T2(base 4경로 저장) `version=6a4c304ae08c…1ab9f7989` 복원 4회 전부 `Cache not found`(S·D·F-PR·F-MG — 캐시 REST에는 키 존재, 33,982,453 B) | **F2 #412** base save `path:`를 소비자 b-restore(action.yml 9행)와 **바이트-동일 9행**으로 정렬(lane save와 동일); R9 (a)-(d) 계약 명시 | **D-MG-fire 36771956426**: base `[publish] base fingerprint manifest written (buildSha=67585b8c11bf…)` + **`Cache saved with key: axiom-b-67585b8c…-d807d897…-f53165a6b8…`** — 9경로 신규키 base 시드 성공; S-MG base T4 HIT(20:06:08)로 소비 정합 재확인 |

## C. Terminal Outcome 기계 판정

- **① 동일 build identity(트리+recipe+toolchain fp+contract)당 콜드 ≤1회 — 달성**(9경로 정합 상태):
  b-key별 콜드 히스토그램(최종): T1 c4d18677 **0회**(전 HIT — v38-PR·v38-MG) / T3 e91a33fd **1회**(F-PR lane) → HIT 3건(F2-PR·F2-MG·S-MG base, B_VERIFY OK) / T4 f79f4719 **1회**(F2-PR lane) → HIT 2건(F2-MG lane·S-MG base) / T_S 67585b8c **1회**(D-MG base, 신규=면제) → D-MG-fire 시드 후 소비 가능 / T_D 18f47938 **1회**(D-MG lane, 신규=면제) → 시드 완료. **T2 c4d6879654 2회(S-PR·D-PR) = 결함2(4경로 version)의 과거 기록 — F2로 소거**; T2는 base identity 탈락(착지 진행)으로 실질 영향 없음(4경로 엔트리 수명 잔존 — UNKNOWN 2).
- **② 검증 산출물 매 run 전건 신규 발행 — 달성(부분)**: S-PR 36759141517·S-MG 36770241367·D-PR 36760288298·D-MG 36771219320 전 런에 `admission-check-<head>`(witness 내재)·`admission-check-base-artifacts`·`subject-certificate-1`·`tested-tree-digest`·`ci-select-decision/verifier` 존재(6~7종/런) + `MINT_PUB_ART/DIGEST/AX(/BIND): OK` 4런 실측(S-MG 20:11:14~17, D-MG 20:20:16~17). `MINT_PUB … append 1` = epoch N+6 **SL-0713 NO-FIRE 설계 귀속**(epoch manifest 미변경 — slice-engine 실측, C0와 동일).
- **③ push@main run 0건 — 달성**: `event=push&created=>=2026-09-30T16:19:15Z` **total_count 0** · 최근 24h(`created>=2026-10-01T00:00:00Z`) **0**(전 브랜치·main) · 최신 push 런 = 2026-09-29 07:37(probe-merge-queue) — #404~#412(9건 머지) 전부 push 이벤트 0(ADR-0025/E1 구조 재확인).

## D. 잔여·분리 (수정 범위 밖 — 기존 추적 계승)

- **R6** (mode=none: ci-bootstrap 미실행 → lane 키 무시드 — "다음 PR의 base 빌드가 콜드일 수 있음(가속만)"): base 경로는 F1로 독립 작동 실측(S-MG-fire) — 잔여 문구 그대로 유지.
- **R10** (lane 트리-헤드 등식 ahead-invariant 잔여 — stale PR 구간 lane 시드 생략 → 사이클 내 2회째 콜드 가능, bounded/fail-closed, census B(i) 실측) — **#410에서 병합**(docs/spec/github_delegation_residuals.md).
- **S5·J3 P2-3(a)** (cache-manifest 판정 — 신뢰 입력 기반 앵커링 미착지, `--judgment cache-manifest` exit 2 유지 — F1/F2 무회귀 실측) — 기존 추적(ci_toolchain_scope·tcb_judgments) 계승.
- **D5·D6·D8** (canonical_run_graph D-list) — 기존 추적 계승, 본 사이클 무변경.
- **certificate-mint.yml:166** stale 주석 — FOLLOW-UPS 계승(callee 회전 후속 수정 대상, 금지 파일).

## E. UNKNOWN 전부 (계승 + 신규)

1. org ruleset 24041674 404 → L1 교차 권위 한계(UNKNOWN-by-scope); repo ruleset 24233738 req=[] → 불변식 3 귀속.
2. T2 4경로 version 엔트리 수명 잔존(관리 삭제 미실시 — 스코프 밖; base identity 탈락으로 실질 영향 없음).
3. `[verdict]` PR 페이즈 부재의 org caller 배치 구조(레포 표면 미관측) · executed-ci-bootstrap 발화 조건(decision 스코프) · C0 lane HIT 벽시계 절감 대조.
4. T_S 시드(20:21:05) 후 최초 소비(향후 G_S-base 런) — 미관측; D-MG 콜드 #1 면제 판정의 ② 재검증은 S/D-MG mint/witness 원문 인용 수준.
5. ③ 무필터 카운트(2292/2113)의 정확한 REST 기본 창 — created 필터 관측만 판정 근거.
6. 모드=none + 9경로 base save 신규키 조합 실관측(S-MG-fire는 기존 키 conflict — 신규키 저장은 D-MG-fire(build 스코프)에서 실측) — 다음 docs-only 사이클 대기.
7. **DEBT#471 등록**(gate_memo FAIL_CACHED quirk — 아래)의 해소 경로(차기 memo 키 개선/스캐너 어휘 분리) — 미계획.

## F. 관측 계약 준수 기록 (§2.3)

- 네이티브 waiter만: `gh pr checks <N> --watch --interval 30` 전 PR(#408~#412) exit 0; `gh run watch`는 in-repo 런(퍼블리셔)에 한해 — 본 사이클은 REST 단발 쿼리(≥30s)로 통일 관측(org admission-gate 런 — cli/cli#9228).
- 완료된 런만 열람(진행 tail 0건); per-job REST 로그 + ANSI 스트립.
- L1: REST check-runs JSON(admission-check completed+success — 전 PR 인용) / L1 교차: ruleset 24233738 active req=[](org 404 → UNKNOWN-by-scope) / L2: GraphQL mergeQueue 전환 관측(QUEUED→⋄) / L3: `gh pr view --json state,mergedAt,mergeCommit` — MERGED+oid 확정.
- 증거 귀속: 각 관측에 PR 번호·head SHA·UTC 타임스탬프·원문(JSON/로그 라인) 첨부(위 표 및 이전 보고).
- 인터럽트 2건(③ 2차 쿼리·sleep-300 후속)은 재관측으로 완결 — 판정에 영향 없음.