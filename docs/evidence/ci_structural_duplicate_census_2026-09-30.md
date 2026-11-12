# CI 구조적 중복 전량 분류 (Phase 1A — 머지 사이클 빌드 identity census)

- 측정일: 2026-09-30 (UTC) — 창: 10:28:05Z–11:17:35Z
- 작업 브랜치: `fix/ci-build-identity-closure` (origin/main 1ef4e7229 동기화 완료, 측정은 main 통합 커밋 1ef4e7229 이전 데이터)
- 성격: **측정·분류 기록** (커밋 없음 — 파일 작성만; 커밋/게이트는 상위 에이전트 소관)
- 목적: 머지 사이클(PR 게이트 → merge_group 게이트 → ci-cache-publisher 발화) 내 빌드 이벤트를 build identity(빌드-소스 트리, 레시피, toolchain 지문) 기준 **A/B/C 전량 분류**하고, base/lane 콜드-핫 수치와 퍼블리셔 publish/skip 패턴을 정본 로그로 확정한다.
- 방법: 완료된 런만 REST(`gh api .../actions/runs|jobs|jobs/{id}/logs`, `git/commits`)로 관측 — §2.3 계약 준수(hand-rolled polling 없음, tail 금지 준수). admission-gate 런은 org ruleset 실행이라 `gh run view`가 404(cli/cli#9228 — AGENTS.md §2.3 각주 ①) → per-job REST 로그 사용.

## 1. 사이클 목록 (관측 대상 전량)

| 사이클 | PR # | 페이즈 | admission-gate 런 | head_sha | tree OID | 퍼블리셔 런 |
|---|---|---|---|---|---|---|
| A | 404 (chore/post-adoption-cleanup) | pull_request | **36702598836** (10:28:05→10:35:04, 419s) | 2264cf5a | 74ffa295 | **36703314113** (10:35:08→10:35:29, 21s) |
| A | 404 | merge_group | **36703362000** (10:35:38→10:42:24, 406s) | 2731b5684 | c5f999f7 | **36704039495** (10:42:26→10:43:40, 74s) |
| B | 405 (docs/agents-2-3-authority-adapter-separation) | pull_request | **36706133783** (11:03:05→11:09:43, 398s) | b7eaa2b4 | f94164db | **36706820963** (11:09:45→11:10:09, 24s) |
| B | 405 | merge_group | **36706884472** (11:10:21→11:17:11, 410s) | 1ef4e7229 | f94164db | **36707601415** (11:17:14→11:17:35, 21s) |

- 퍼블리셔의 trigger RUN_ID 실측: 36703314113→36702598836, 36704039495→36703362000, 36706820963→36706133783, 36707601415→36706884472 (워크플로 가드 로그 `RUN_ID:`).
- 랜딩: 사이클 A = 2731b5684 (10:35:18Z author), 사이클 B = 1ef4e7229 (11:10:01Z) — 모두 merge_group 런 완료 후 착지.

## 2. build identity 실측 (b-key = `axiom-b-<b_identity>-<recipe_hash><a_fp>`)

- `b-identity` = 빌드-소스 커밋의 **tree OID** (keygen 시 checkout에서 `git rev-parse HEAD^{tree}` — setup-axiom-toolchain keygen 로그 `AXIOM_CACHE_KEYGEN: b-identity=`).
- `recipe_hash` = Makefile·config.nims·config/effects.nims·src/gate/config.nims sha256 — **전 런 동일 `d807d897…`** (레시피 불변).
- `a_fp` = toolchain/이미지 결속 지문 — 구 이미지(`20260920.314.1`) 실행 시 접미사 `14fc017c…`, 신 이미지(`20260927.320.1`) 실행 시 `3cfae1a…` (러너 ImageVersion 드리프트가 fp를 바꾼다 — §0.5 doc: image drift 사고 예방 설계).
- → **동일 b-key = 동일 build identity = (동일 트리 ∧ 동일 레시피 ∧ 동일 toolchain fp)**. 이 등식이 아래 분류의 기준이다.

### 2.1 잡별 체크아웃·B 캐시·컴파일 실측 (per-job REST 로그)

| 런 (페이즈) | 잡 | 체크아웃 (source) | b-identity | B 캐시 | 컴파일 step | 소요 |
|---|---|---|---|---|---|---|
| 36702598836 (A·PR) | build-base-artifacts | **ef8bf224** (base.sha) | 6f2ba8e9 | MISS | Build bin/ax+harness from B | 182s |
| 36702598836 (A·PR) | gateway/ci-bootstrap | **d7d7c400** (target=merge ref) | c5f999f7 | MISS | Compile bootstrap artifacts | 169s |
| 36703362000 (A·mg) | build-base-artifacts | **ef8bf224** (base.sha) | 6f2ba8e9 | MISS | Build bin/ax+harness from B | 195s |
| 36703362000 (A·mg) | gateway/ci-bootstrap | **2731b5684** (target=queue head) | c5f999f7 | MISS | Compile bootstrap artifacts | 134s |
| 36706133783 (B·PR) | build-base-artifacts | **2731b5684** (base.sha) | c5f999f7 | MISS | Build bin/ax+harness from B | 188s |
| 36706133783 (B·PR) | gateway/ci-bootstrap | **ab8b9e1b** (target=merge ref) | f94164db | MISS | Compile bootstrap artifacts | 182s |
| 36706884472 (B·mg) | build-base-artifacts | **2731b5684** (base.sha) | c5f999f7 | MISS | Build bin/ax+harness from B | 187s |
| 36706884472 (B·mg) | gateway/ci-bootstrap | **1ef4e7229** (target=queue head) | f94164db | **HIT** | Compile bootstrap artifacts | 86s |

- B 캐시 라인 실측: `Cache not found for input keys: axiom-b-…` (MISS 7건) / `Cache hit for: axiom-b-f94164db…-d807d897…14fc017c…` + `Cache restored from key` + `AXIOM_CACHE_B_VERIFY: RESULT OK — 4/4 entries digest-verified, buildSha=f94164db62ef, key exact-hit` (HIT 1건 — B·mg lane).
- **B 캐시 write는 퍼블리셔 3건뿐** (`Cache saved with key: axiom-b-…`, §4): admission 잡은 B를 저장하지 않음 (A만 `AXIOM_CACHE_A_SAVE`). 따라서 base-build 키(6f2ba8e9·c5f999f7 × 구-fp)는 **어떤 주체도 씨딩한 적이 없다** → base 빌드는 구조적으로 항상 콜드.
- HIT lane(B·mg)도 `make ci-compile` 4개 nim 컴파일(gate_hook·precompile_gates·ax·install_ax_cas) **전부 재실행** — restored nimcache로 86s(콜드 134–195s 대비 약 절반)까지 단축되나 컴파일 자체는 소멸하지 않음. 이는 공지된 J3 바닥(mtime 재빌드, `data/ci_pareto/selection_table.json:13` S5 build-skip blocked)이다.

### 2.2 tree 등식 (Git Data API 실측)

| sha | 성격 | tree OID |
|---|---|---|
| 2264cf5a | 사이클 A PR head (H) | 74ffa295 |
| d7d7c400 | 사이클 A merge ref (lane) | **c5f999f7** |
| ef8bf224 | 사이클 A base / pr-403 merge (M₄₀₃) | 6f2ba8e9 |
| 2731b5684 | 사이클 A queue head·랜딩 (G/M) / 사이클 B base | **c5f999f7** |
| b7eaa2b4 | 사이클 B PR head (H) | **f94164db** |
| ab8b9e1b | 사이클 B merge ref (lane) | **f94164db** |
| 1ef4e7229 | 사이클 B queue head·랜딩 (G/M) | **f94164db** |

- **사이클 B: tree(H) == tree(merge ref) == tree(G/M)** — PR head 트리가 큐 head 트리와 동일 (ahead-invariant 성립). **사이클 A: tree(H)=74ffa295 ≠ tree(G/M)=c5f999f7** — 브랜치가 base(pr-403 착지)를 포함하지 않아 merge ref 트리가 head 트리와 다름 → 이 차이가 사이클 A PR-phase 퍼블리셔 skip의 직접 원인 (§3).
- 교차 관찰: **사이클 A lane identity (c5f999f7) == 사이클 B base identity (c5f999f7)** — 같은 트리가 연속 2사이클에서 lane→base로 이어져 4회 컴파일됨 (§5).

## 3. 퍼블리셔 verdict 패턴 (4 fires, 0 계산)

| 퍼블리셔 런 | trigger | verdict (로그 원문) | 결과 |
|---|---|---|---|
| 36703314113 | A·PR | `[publish] guard=true trees=true verify=false key=` + `[publish-skip] tree(build_sha)=c5f999f7… != tree(head_sha)=74ffa295… — content identity not landable as tested (ahead invariant absent)` | **SKIP** — A·mg lane 씨딩 공백 → mg lane 콜드 |
| 36704039495 | A·mg | `[publish] guard=true trees=true verify=true key=axiom-b-c5f999f7…-d807d897…3cfae1a…` + `Cache saved` | **PUBLISH** — 단, 러너가 신 이미지(fp 3cfae1a) → 구-fp 소비자(14fc017c)와 키 불일치 → 당장 소비 불가 |
| 36706820963 | B·PR | `[publish] guard=true trees=true verify=true key=axiom-b-f94164db…-d807d897…14fc017c…` + `Cache saved` | **PUBLISH** — B·mg lane 요구 키와 정확 일치 → **다음 페이즈에서 HIT 실현** (11:12:35) |
| 36707601415 | B·mg | `[publish] guard=true trees=true verify=true key=axiom-b-f94164db…-d807d897…3cfae1a…` + `Cache saved` | **PUBLISH** — 신-fp 중복 시드 (후속 신-이미지 런용) |

- **패턴**: PR-phase 발화가 다음 merge_group 페이즈의 lane에 씨딩하는 것이 유일한 온기 경로. 성립 조건 (실측) = ① tree(manifest build_sha)=tree(run head) — 즉 ahead-invariant (사이클 A는 불성립 → SKIP) ∧ ② 퍼블리셔 러너 이미지 fp == 소비 lane fp (사이클 A는 드리프트로 불일치). 둘 다 성립한 사이클 B만 씨딩 성공.
- 퍼블리셔 자체는 **계산 0** (아티팩트 검증+재발행만; J3: 캐시는 증거가 아님) → C-class (관측 발화).

## 4. B 캐시 write 전량 (창 내)

| 주체 | 런 | 키 | 시점 |
|---|---|---|---|
| 퍼블리셔 36704039495 | A·mg | axiom-b-c5f999f7…-3cfae1a… | 10:43:37 |
| 퍼블리셔 36706820963 | B·PR | axiom-b-f94164db…-14fc017c… | 11:10:05 |
| 퍼블리셔 36707601415 | B·mg | axiom-b-f94164db…-3cfae1a… | 11:17:32 |

- write 3건 외 B 키 write 0건. rt 키(`axiom-a-rt-*`)는 mint-prepare가 per-run 저장(prepare→publish 같은 런 내 히트; 크로스 런 재사용 불가 — 설계상 PR/mq-ref 한정).

## 5. 전량 분류표 (미분류 0건)

분류 정의: **A** = 다른 build identity (재계산 정당) · **B** = 같은 build identity 재계산 → **(i) identity-fixable**(캐시 씨딩/키 원인) vs **(ii) authority-contract**(플랫폼/정책상 재실행 필수) · **C** = 계산 없음 (발화/스킵 관측).

### 5.1 컴파일 이벤트 (8건 — 창 내 전량)

| # | 사이클 | 페이즈·잡 | identity (tree·recipe·fp) | B 상태 | 컴파일 | 분류 | 근거 |
|---|---|---|---|---|---|---|---|
| 1 | A | PR·base | 6f2ba8e9·d807d897·14fc017c | MISS | 182s | **A** | 창 내 최초 (identity 최초 발생) |
| 2 | A | mg·base | 6f2ba8e9·d807d897·14fc017c | MISS | 195s | **B(i)** | PR 페이즈와 동일 b-key — 씨딩 공백(이 키는 창 내 어떤 주체도 write 안 함 §4) |
| 3 | A | PR·lane | c5f999f7·d807d897·14fc017c | MISS | 169s | **A** | 창 내 최초 |
| 4 | A | mg·lane | c5f999f7·d807d897·14fc017c | MISS | 134s | **B(i)** | 동일 b-key 재계산 — PR-phase 퍼블리셔 SKIP(§3) + mg-phase 퍼블리셔 fp 불일치가 원인 |
| 5 | B | PR·base | c5f999f7·d807d897·14fc017c | MISS | 188s | **B(i)** | #3·#4와 동일 identity (교차 사이클 중복) — base 키 씨딩 부재 |
| 6 | B | mg·base | c5f999f7·d807d897·14fc017c | MISS | 187s | **B(i)** | #5와 동일 identity — 사이클 내 2회째 콜드 |
| 7 | B | PR·lane | f94164db·d807d897·14fc017c | MISS | 182s | **A** | 창 내 최초 |
| 8 | B | mg·lane | f94164db·d807d897·14fc017c | **HIT** | 86s | **B(i)** | 복원 성공·동일 identity 재컴파일 — 씨딩 체인 작동 실증, 잔여 재컴파일은 J3 바닥(S5 build-skip blocked) |

- **authority-contract(B(ii)) 해당 0건**: 페이즈/정책상 재컴파일이 필수라는 실측 근거 없음 — 오히려 반증 실측: ① admission-check 잡은 동일 identity의 base 페이로드를 캐시 복원 + digest 검증으로 소비하는 것이 정상 경로(§5.2)이고 ② B 복원은 설계상 "가속 수단, 증거 아님" (J3, action.yml 복원+검증 체인) — 다만 **"같은 identity 재컴파일이 증거 구조상 요구된다"는 명시 정책 문서는 미발견**이므로 B(ii) 판정의 근거가 될 만한 항목은 UNKNOWN §7로 보류.

### 5.2 소비·프로비저닝 이벤트 (컴파일 아닌 동일-identity 재계산/관측 — 창 내 전량)

| 이벤트 | 런 (페이즈) | identity | B/rt 상태 | 분류 | 근거 |
|---|---|---|---|---|---|
| admission-check B 복원 | A·PR / A·mg / B·PR | 6f2ba8e9 / 6f2ba8e9 / c5f999f7 | MISS ×3 | C (소비) | 복원 시도(가속) — 컴파일 아님; Gate A는 per-run 아티팩트(download) 경로로 검증 |
| admission-check B 복원 | B·mg | c5f999f7·3cfae1a (신-fp) | **HIT** | C (소비) | 36704039495(사이클 A mg-phase 퍼블리셔) 시드가 **교차 사이클**에서 적중 — `B_VERIFY RESULT OK buildSha=c5f999f7` |
| mint rt 준비 | A·PR / A·mg / B·PR / B·mg | c5f999f7·rt·구-fp (+A·mg-PUB 신-fp 1건) | prepare MISS → 같은 런 publish HIT 3회 / 모두 MISS 1회 (A·mg: prepare 구-fp·publish 신-fp 드리프트) | **B(i)** | rt 키 PR/mq-ref 한정 설계(`axiom-a-rt-*` 네임스페이스)로 크로스 런 재사용 불가 — 매 런 동일 identity 재프로비저닝(컴파일 아님, z3/jq 다운로드 수준) |
| gateway select / candidate-build-arm / gateway-shard / proof-reconcile / gateway-identity-gate | 전 런 | — | skipped (NO-FIRE) | C | 스킵 — 계산 없음 (관측 노이즈) |
| 퍼블리셔 4 fires | §3 | — | publish 3 / skip 1 | C | 계산 0 — 재발행만 (`[publish]` verdict 라인 실측) |

## 6. 수치 요약

- **동일 build identity당 컴파일 횟수 (창 내, 전부 레시피 d807d897·구-fp 14fc017c 일치 기준)**:
  - `6f2ba8e9` (pr-403 내용 = 사이클 A base 트리): **2회** (사이클 A PR+mg base)
  - `c5f999f7` (pr-404 내용 = A lane 트리 = B base 트리): **4회** (A-PR lane, A-mg lane, B-PR base, B-mg base — 전부 콜드)
  - `f94164db` (pr-405 내용 = B lane·queue head 트리): **2회** (B-PR lane 콜드, B-mg lane 온도복원+재컴파일)
- **base 트리 빌드 사이클 내 콜드 횟수 = 2회/사이클** — 잡 wall ≈ 3m58s–4m07s ×2 (컴파일 step 182–195s ×2) → "약 4m×2" 실측 일치. base 키는 창 내 어떤 주체도 write하지 않아 **구조적 항상-콜드** (§4).
- **lane hit/miss**: PR 페이즈 2/2 MISS (콜드) · mg 페이즈 HIT 1/2 (사이클 B — 앞선 PR-phase 퍼블리셔 시드 적중), MISS 1/2 (사이클 A — 퍼블리셔 SKIP + fp 드리프트).
- **퍼블리셔**: 4 fires → publish 3 / skip 1. skip 원인 = ahead-invariant 부재(tree 불등식); publish 3건 중 즉효 1건(사이클 B PR-phase), 지연효과 1건(사이클 A mg-phase → 사이클 B mg admission-check), 미소비 1건(사이클 B mg-phase 신-fp).
- 분류 집계: 컴파일 A 3건 / B 5건(전부 B(i) identity-fixable, B(ii) 0건) · 컴파일 아님 관측 — C 8건+스킵 잡군(admission B 복원 4 — hit 1/miss 3, 퍼블리셔 발화 4 — publish 3/skip 1, 스킵 잡군) · B(i) 추가 4건(mint rt 준비 — 컴파일 아님, 프로비저닝). 창 내 관측 이벤트 전량 분류 완료, 미분류 0건.

## 7. UNKNOWN 목록 (측정 불가/창 밖 — 추측 금지)

1. 창 밖 컴파일: `c5f999f7` identity의 pr-403 사이클 내 lane 컴파일 및 `6f2ba8e9` identity의 창 전 컴파일 발생 여부·횟수 (본 창 10:28–11:17 시작 전) — 미측정. 따라서 두 identity의 "창 밖 포함 총 컴파일"은 **UNKNOWN**.
2. B(ii) 판정 근거가 될 "게이트 런마다 base를 신규 컴파일해야 한다"는 명시 정책/계약 문서 — 저장소에서 미발견 (fail-closed 가속 경로 실측만 존재; 문서 위치 불명 → absent로 단정하지 않음).
3. `a-cache-hit`/`b-cache-hit` 리터럴 마커 — 관측 대상 로그(4 admission 런 per-job 로그 + 4 퍼블리셔 로그 전체)에서 **0건** (존재하지 않음). 동등 신호는 actions/cache `Cache hit for`/`Cache restored from key` + `AXIOM_CACHE_*` 라인으로 대체 실측 완료.
4. mint rt 페이로드 정확 구성(z3/jq 외 항목) — 로그 수준에서 페이로드 목록 미검증(문서 근거: rt 페이로드에 nimble 없음 — ci_toolchain_scope 문서 인용).
5. pr-403 사이클 전체 (PR 런 36694529252 · mg 런 36695386436 · 퍼블리셔 36695234678/36696034758) — 창 밖, 분류 미실시.
6. 퍼블리셔 러너 이미지 선택 규칙(어떤 이미지로 스케줄되는지) — 플랫폼 배정, 로그의 keygen a-key로 관측 결과만 기록(제어 불가).

## 8. 검증·출처 요약

| 데이터 | 출처 (2026-09-30) | 상태 |
|---|---|---|
| 런 메타/잡/단계/로그 | `gh api repos/Archright/Axiom/actions/runs/{id}{,/jobs,/jobs/{id}/steps,/jobs/{id}/logs}` — 4 admission 런 × 핵심 잡 13개 + 퍼블리셔 4 런 | 실측 ✓ (org ruleset 런이라 `gh run view` 404 → REST 경유) |
| tree OID | `gh api .../git/commits/{7 sha}` | 실측 ✓ (b-identity=tree 등식 전건 일치) |
| b-key/recipe/fp | 잡 로그 `AXIOM_CACHE_KEYGEN:` / B-복원 라인 | 실측 ✓ |
| 퍼블리셔 verdict | 퍼블리셔 로그 `[publish]`/`[publish-skip]` executed 라인 | 실측 ✓ |
| B write 전량 | `Cache saved with key: axiom-b-…` 전 로그 스캔 | 실측 ✓ (3건) |
| J3/S5 blocked | `data/ci_pareto/selection_table.json:13` | 기존 문서 인용 |
| repository_surface | `config/repository_surface.json` 클래스/규칙 직접 판독 | 실측 ✓ |

## 9. `config/repository_surface.json` 등록 판단

- 3-클래스 판정(defaultClass FROZEN, classResolutionOrder PRODUCT→CONTROLLED→FROZEN, rules 3): 신규 경로 `docs/evidence/ci_structural_duplicate_census_2026-09-30.md`(+동반 JSON)는 `docs/**` FROZEN 와일드카드로 **기본 분류 FROZEN — 명시 등록 불필요** (열거 규칙에 docs/evidence 미포함, 와일드카드만 존재).
- 단, **선례 관찰**: 최근 CI 권위 기록(`ci_toolchain_scope_2026-09-30.md`, `merge_queue_probe/operation_2026-09-29.md`, `epoch_record_oracle_select_2026-09-30.md`)은 CONTROLLED로 **명시 등록**되어 있음(policyVersion 36). 본 census가 후속 CI epoch 변경의 권위 근거가 될 예정이면 동일 선례로 **CONTROLLED 등록을 권장** (등록 시 policyVersion 상승 + 선례 인용 필요 — 이 파일 변경은 상위 에이전트 소관).
- 결론: **등록 필수 아님 (FROZEN 기본). 등록 필요 시 CONTROLLED 승격 — 결정은 상위 에이전트에 위임.**