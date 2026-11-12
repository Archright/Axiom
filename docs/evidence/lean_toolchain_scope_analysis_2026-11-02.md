# Lean 툴체인·~/.local/bin 설치/복원 축소 스코프 — 사전 분석 (구조·비용·공식문서·설계-계약)

> **문서 성격**: PR #1192(`36650c059`, `docs/evidence/arestore_optimization_blocked_2026-11-02.md` §5)가 BLOCKED 종결 시 참고로 남긴 잔여 후송 — "attest의 A-restore를 Lean + ~/.local/bin 전용 축소 스코프로 줄이는 것(~12-15s)" — 에 대한 **사전 분석**이다. 본 문서는 **측정·관측·계약 검증의 사실만 나열**하며, **GO/NO-GO 판정·권고는 하지 않는다**. 후보 선정은 WP-B2 소유자의 사전등록 워크스트림 검토 판단 사항이다.
> **관측 프로토콜**: 본 분석 전 과정 GET-only(`gh api`·`gh run view`·`git`·파일 읽기) — 저장소 mutation 0건. `.github/**`·`Makefile`·`src/gate/**`는 FROZEN(읽기 전용 관측).
> **측정 환경**: 관측 시점 2026-11-02(UTC). 베이스 `origin/main = 291cb2f081eb3f25a74b78db2d3fdd36ab4a731e`(PR #1194 랜딩 직후). file:line 인용은 이 트리 기준.

---

## 1. 후보의 정의 (#1192 §5 인용)

attest 스테이지의 provision 스코프를 full(4경로)에서 **Lean(~/.elan) + ~/.local/bin(z3/jq) 전용**으로 축소하고, attest가 nim을 소비하는 유일 지점(`core_purity_gate` 빌드)을 base artifact 멤버로 이동해 `~/.choosenim`+`~/.nimble`을 attest 공급에서 탈락시키는 경로. #1192는 이를 "~12-15s 절감"으로 추정하고 "별도 사전등록 워크스트림으로만 검토 가치"로 종결했다. 본 문서는 그 절감 수치의 3성분(§6)과 계약 영향(§5)을 관측으로 확정한다.

---

## 2. 구조 관측 (전수) — 설치·복원 지점과 캐시 커버

### 2.1 composite action (`setup-axiom-toolchain`) — A-layer는 이미 ~/.elan·~/.local/bin을 커버한다

| 항목 | 위치 (origin/main) | 내용 |
|---|---|---|
| A-layer 캐시 경로 | `.github/actions/setup-axiom-toolchain/action.yml:54` | "Contents: ~/.nimble, ~/.choosenim, **~/.elan, ~/.local/bin** (z3/jq) ONLY" |
| full 스코프 경로 해상 | `action.yml:317-327` | `a_paths = ~/.nimble ~/.choosenim ~/.elan ~/.local/bin` (full) / `~/.local/bin` (runtime) |
| A-restore 스텝 | `action.yml:329-335` | `actions/cache/restore@0057852b` (v4, SHA 핀) — exact key only |
| A-save 스텝 | `action.yml:942-962` | MISS 시 저장, first-save-wins, lock-completeness 가드 |
| Lean 설치 (elan) | `action.yml:824-858` | `curl elan.lean-lang.org/elan-init.sh`(:849, **내용 해시 핀 없음**) + `-y --default-toolchain leanprover/lean4:v4.33.0`(:851) — MISS/verify/probe 실패 시에만 실행 |
| Z3 설치 | `action.yml:860-881` | 릴리스 바이너리 → `$HOME/.local/bin/z3` |
| jq 설치 | `action.yml:883-906` | 핀 바이너리 → `$HOME/.local/bin/jq` |
| Lean 핀 검증 3중 | `action.yml:362-365`(A-verify lean==4.33.0), `:696-728`(Lake 기능 프로브 — `import Lake` 실행), `:908-924`(pins verify: nim/lean/lake/z3/jq) | 버전+기능+핀 |
| runtime 스코프 선례 | `action.yml:134-147`, `:58-67` | mint 잡 전용: `~/.local/bin`만 복원·저장 (`axiom-a-rt-*` 네임스페이스) — "path list에서 파생된 cache version 때문에 스코프 간 절대 교차 없음"(:66-67) |
| restore-keys 금지 | `action.yml:86-88` | exact-match만 HIT로 간주(공식 문서와 일치, §4a) |

**결론 1**: "Lean·~/.local/bin이 캐시 미커버"라는 전제는 **성립하지 않는다** — 두 경로 모두 full 스코프 A-layer의 캐시 커버 하에 있다. 후보가 다루는 것은 **커버 추가가 아니라 스코프 축소**(attest 잡의 공급 단위를 4경로 → 2경로로)다.

### 2.2 attest 스테이지 — full 스코프인 이유는 core_purity_gate다

- attest 스테이지 setup: `.github/workflows/admission-check.yml:872-877` — `provision-scope: 'full'` 명시.
- 그 이유의 SSOT: `admission-check.yml:858-871` 스테이지 게이트 주석 — "The ATTEST stage builds bin/core_purity_gate from B (`make bin/core_purity_gate`) **and needs scope=full**". 실제 빌드: `admission-check.yml:1007` + `Makefile:380-381` (nim 컴파일, `tools/ci/core_purity_gate.nim`).
- verdict 랜딩 레그는 반대 선례: **프로비저닝 전무** + jq 자체 핀(`admission-check.yml:763-775`) — toolchain-handoff 패턴(`docs/evidence/verdict_payload_gate_2026-10-12.md` GO scope (a')). 후보가 재사용하려는 바로 그 패턴이다.
- runtime 스코프 소비자: `certificate-mint.yml:600-606`, `:1300-1304` (mint 2잡 — prebuilt bin/ax만 실행, 커널 실행 없음, `src/cli/cert_cli.nim` runSignWitnessCli 검증은 action.yml:58-60 기재).

### 2.3 캐시 밖 Lean 설치 경로 (측정 워크플로 2건 — 커버 없음)

- `h4-routing-measure.yml:96-98`, `:242-244` — 인라인 `elan-init.sh` 설치, 캐시 없음.
- `hardware-falsification-smoke.yml:77-81` — 동일(lean-toolchain 4.33.0 자동 설치 검증 목적).
- 이 2개 측정 워크플로가 본 저장소 CI에서 **유일한 캐시 미커버 Lean 설치 경로**다. `Makefile`·`scripts/`·`docs/guides/`에는 elan 설치 절차가 없다(Makefile은 pin 확인 `Makefile:249`과 개발 타깃 `lake env lean --run` `Makefile:1274`만 존재).

### 2.4 attest 체인의 실행 재료 소비 지점 (검증 의미론의 물리적 위치)

| 스테이지 | 소비 | 근거 (origin/main) |
|---|---|---|
| witness-only = (a)-(f) 전체 | "Runs the kernel chain stages (a)-(f) EXACTLY as the full attest does" | `src/cli/cert_cli.nim:835` |
| stage-b 추출 대조 | `runExtractionAgreement(... ircheckExe ...)` — ircheck 부재 시 sentinel -2 fail-closed | `src/verification/attestation_orchestrator.nim:681`, `src/verification/extraction_agreement.nim:177` |
| ircheck 정체 | lake `lean_exe ircheck` (Lean 런타임 링크) | `proofs/lakefile.lean:35` |
| stage-c lean 재실행 | 기본 호출 `lake env lean` | `src/verification/attestation_orchestrator.nim:698`, `src/verification/kernel_reexecution.nim:290` |
| stage-c z3 재실행 | `reexecuteZ3` — 바이너리 미핀/부재 시 krZ3Error fail-closed | `attestation_orchestrator.nim:703`, `kernel_reexecution.nim:290` 부근·`:316-341` |
| z3 경로 해석 | AXIOM_Z3_PATH → **`$HOME/.local/bin/z3`** → PATH | `src/core/types/z3_solver_config.nim:19-28` |
| 같은 키를 공유하는 상류 공급 | build-base·lane·단일잡 워크플로 5종 (S5 lane `cd proofs && lake build ircheck`) | `admission-check.yml:331-334`, `runner-pool-acceptance.yml:746`, `axiom-operational-slice.yml:55`, `gateway-jobs-measure.yml:117` |

**결론 2**: attest는 **lean(lake)+z3(+ircheck 바이너리)를 매 착지 실행에서 소비**하며, 이 소비는 복원 채널과 무관하다(§5). 후보의 대상 경로(~/.elan, ~/.local/bin)는 attest 체인의 실제 실행 재료와 정확히 일치하고, 탈락시킬 경로(~/.choosenim, ~/.nimble)는 `core_purity_gate` 한 지점(nim c)과만 연결된다.

### 2.5 아이덴티티 도메인 분리 — org 핀 action (실측 재확인)

2026-11-02 PR #1189 배치에서 동일 커밋 근방의 두 잡이 **서로 다른 a-key**를 소비했다:

- admission-gate(org 오케스트레이터) 쪽 — `attest / build-base-artifacts`: key `axiom-a-Linux-…-7483645eecae53da…` (main 트리 action 바이트)
- repo PR-트리 잡 — debt-registry-gate·op-slice 등: key `axiom-a-Linux-…-c3b6ac315024dc1a…` (PR #1189의 회전된 action 바이트)

gcc_fp/glibc_fp는 동일, script_hash(`action.yml:194` = sha256(action.yml+nimble.lock))만 상이. #1192 §3a·§4의 "org 핀(`@18b180094a`)은 repo action 변경과 별개 세대" 주장을 독립 로그로 재확인한다. **함의**: action.yml을 편집하는 모든 변경(축소 스코프 포함)은 repo 도메인의 전면 키 회전 = 1회 콜드 시대를 수반하며(§6 참조), org 핀 도메인에는 전파되지 않는다.

---

## 3. 비용 증가 (관측 원천 — run ID 명시)

모든 수치는 GitHub Actions 로그의 `##[end-action …duration_ms=]` 레코드에서 산출했다. 단위는 초(s), 밀리초(ms) 표기 준수.

### 3.1 콜드 설치 사슬 (전 경로) — run 41370265270 (debt-registry-gate, job 125039022029, attempt 1, 2026-11-02 01:01-01:04 UTC, 새 키 `c3b6ac31` MISS)

| 스텝 | 소요 | 후보 대상 |
|---|---|---|
| keygen | 1067ms | — |
| A-restore (MISS "Cache not found") | 306ms | — |
| Install system deps (libpcre3) | 6.9s | — |
| Install Nim (choosenim) | 8.5s | 탈락 대상 |
| Install project Nim deps (nimble) | 56.2s | 탈락 대상 |
| **Install Lean 4.33.0 (elan)** | **18.2s** | **대상** |
| **Install Z3 4.13.3** | **2.1s** | **대상** |
| **Install jq 1.7.1** | **0.24s** | **대상** |
| Verify toolchain pins | 0.2s | — |
| A-save (업로드) | 23.4s | — |

→ **후보 대상 경로의 콜드 설치 합 = 20.5s** (18.2+2.1+0.24), nim 쪽(choosenim+nimble) = 64.6s, 전체 = 85.1s.

### 3.2 콜드 실패 사례 (설치 실패의 실측 비용) — run 41370265172 attempt 1 (op-slice, job 125039021460)

choosenim 설치 117.7s 후 nim-lang.org CURL 실패로 red — 이 시점에 elan/z3/jq는 미실행(스텝 체인 순서상 nim 설치가 선행). 콜드 시대의 실패 비용은 nim 쪽 네트워크 의존에 집중된다.

### 3.3 웜 복원 wall — attest 스테이지 A-restore (full 4경로, 랜딩 merge queue 5건, 2026-11-02 01:26-02:03 UTC)

| run | attest 잡 wall | 그중 a-restore |
|---|---|---|
| 41372519688 | 111s | 53.3s |
| 41372908404 | 129s | 59.8s |
| 41373196087 | 91s | 29.1s |
| 41374535265 | 133s | 61.1s |
| 41374953293 | 129s | 59.3s |

p50: 잡 wall 129s, a-restore 59.3s (n=5, 단일 일자 — 기술표본). 참조: preflight 콜드 시대 attest 잡 HIT 복원 32.7s(run 41370265354, job 125039396721), 동일 배치 build-base 첫 복원 54.5s(경합 창).

### 3.4 엔트리 크기 (경로별 비중의 유일한 실측 앵커) — `gh cache list`, 2026-11-02

| 엔트리 | 크기 |
|---|---|
| full A (`axiom-a-Linux-…7483645e`, 4경로) | **1,122,320,875 B ≈ 1.12 GB** |
| runtime A (`axiom-a-rt-…`, ~/.local/bin만) | **14,112,449 B ≈ 14.1 MB** |
| runtime A 복원 wall (동일 스코프 mint 잡, run 41374953293) | **238ms** |
| B (빌드 아티팩트) | 91.8 MB |

→ **~/.local/bin의 아카이브 비중 ≈ 1.3%** (14.1MB/1.12GB). **~/.elan 단독 비중은 미측정**이다(elan-only 엔트리가 존재하지 않음). #1192 §2는 "Lean 툴체인(~0.5GB+)"을 인용하나 이 역시 본 분석에서 독립 실측되지 않았다.

### 3.5 빈도 (관측 창 기준)

- 랜딩(merge_group admission-gate): 2026-11-02 01:26-01:55 UTC에 5건 관측. attest 스테이지는 **랜딩 DAG당 1회** full-scope A-restore를 수행한다.
- preflight(PR당): PR 오픈/푸시마다 attest(build-base+attest job2) DAG 1회.
- 동일 키 full-scope 복원 당사자는 attest 외에 build-base·lane·단일잡 5종(§2.4 표) — **후보가 attest 잡만 축소하면 이들은 full 엔트리를 계속 소비**한다(즉 full 1.12GB 엔트리는 소멸하지 않고, 축소 엔트리가 **추가**된다 — §4a 저장 한계 참조).

### 3.6 미측정 항목 (명시)

1. **축소 스코프(elan+~/.local/bin) 엔트리의 아카이브 크기·복원 wall** — 해당 스코프의 엔트리/실행이 존재하지 않아 측정 불가. §6-(i)의 값은 선형 외삽 추정이다.
2. **~/.elan 단독 아카이브 비중** — 미측정 (#1192의 ~0.5GB 인용 포함).
3. attest 잡 내부의 stage-b/stage-c 개별 소요 분해 — 잡 wall(91-133s)−setup(~74s)로만 경계 관측됨.

---

## 4. 공식문서 대조 (context7: /actions/cache·/actions/runner-images·/leanprover/lean4·GitHub Actions billing docs)

### (a) actions/cache 공식 동작

- **exact-key HIT 의미**: "`cache-hit` will be set to `true` only when cache hit occurs for the exact `key` match" — restore-keys 접두 폴백은 HIT=false("may be stale" 휴리스틱). 본 repo의 restore-keys 금지(`action.yml:86-88`)는 공식 의미론의 정확한 이용이다.
- **스코프**: "The cache is scoped to the key, version, and branch. The default branch cache is available to other branches." 피처 브랜치 간 공유는 금지(격리).
- **eviction·한계**: "A repository can have up to 10GB of caches. Once the 10GB limit is reached, older caches will be evicted based on when the cache was last accessed. Caches that are not accessed within the last week will also be evicted." (LRU + 7일 미접근 삭제)
- **version**: "hash … for a combination of compression tool used … and the `path` of directories being cached" — **path list가 바뀌면 별개 엔트리**. 이것이 runtime 스코프 선례(`action.yml:66-67`)가 "스코프 간 절대 교차 없음"이라고 서술하는 근거이며, 축소 스코프 신설도 동일 메커니즘으로 full 엔트리와 충돌하지 않는다.

### (b) GitHub hosted runner images 사전설치 여부

- ubuntu-24.04 툴셋(`actions/runner-images` `images/ubuntu/toolsets/toolset-2404.json`)의 apt vital/common/cmd 3개 리스트에 **lean·elan·nim은 부재**, **jq는 포함**(vital_packages) — toolcache도 Python/Go/Node 등만 포함. 즉 **Lean/elan과 Nim은 hosted 이미지에 사전설치되지 않으므로 어떤 설치/복원 경로도 필요하다**(경로 제거는 불가, 공급 방식 전환만 가능).
- jq는 이미지에 사전설치됨에도 repo가 핀 jq를 별도 설치하는 이유는 문서화돼 있다: 호스트 이미지 드리프트(2026-09-08 runner-3 무 jq 관측) + runner pool `system_deps` 계약(`action.yml:884-889`, `admission-check.yml:763-775`).

### (c) elan/Lean 툴체인 설치의 결정론

- 공식 dev 문서(leanprover/lean4)는 `elan-init.sh --default-toolchain none` 설치와 **`lean-toolchain` 파일 기준 디렉터리별 툴체인 선택**을 표준으로 기술한다.
- 본 repo는 root+`proofs/lean-toolchain` = `leanprover/lean4:v4.33.0` 핀(§2.4: lake 빌드·`lake env lean`이 모두 이 핀을 따름). **툴체인 버전의 재현성은 이 파일 핀에 의해 결정**된다.
- 단, 설치 스크립트 자체(`elan-init.sh`)는 내용 해시 핀이 없다(`action.yml:849` 순수 curl — choosenim init은 `init_sha256` 내용 핀 `:788-793`과 대조). 캐시 HIT 경로는 이 네트워크 다운로드를 **대체**할 뿐, MISS 시 네트워크 설치가 fail-closed 폴백으로 남는다(`action.yml:28-30`).

### (d) 과금 — 잡별 사용시간 분 올림 (핵심 규칙)

> "Billable job execution minutes are only shown for jobs run on **private repositories** that use GitHub-hosted runners and are **rounded up to the next minute**. There are no billable minutes when using GitHub Actions in **public repositories** or for jobs run on self-hosted runners." (docs.github.com, "View job execution time")

- 본 저장소는 **private** 확인(`gh repo view` → `isPrivate: true`) — 분 올림 규칙이 **실체로 적용**된다.
- 올림은 **잡 단위**: 잡 wall이 분 경계를 넘지 않는 한 잡 내 수 초 절감은 청구분 변화 0. 경계를 넘는 표본에서만 1분 절감으로 등록된다(§6-(iii) 정량화).

---

## 5. 설계-계약 검증 — "캐시는 계산 재사용이지 증거가 아니다"

### 5.1 확정: 축소/캐싱은 검증 의미론을 바꾸지 않는다 (실행 관측 근거 포함)

1. **판정은 매 실행 재계산된다.** 랜딩 attest 잡(run 41374953293, PR #1194 랜딩)은 A HIT(59.3s 복원, A-verify+Lake 프로브+pins 통과) 후에도 attest 체인 전체를 실행했다 — 잡 로그에서 lean/ircheck/z3 관련 흔적 58건(stage-b 추출 대조·stage-c 커널 재실행). 복원은 **실행 재료의 공급**이지 판정의 재사용이 아니다. 이것은 `action.yml:22-30`의 자기 서술("cache is acceleration, never evidence")과 공식 문서의 캐시 의미론(§4a)이 일치하는 지점이다.
2. **#1192 메커니즘 2(재복원 제거)와의 결정적 차이.** 제거는 attest 체인의 실행 재료(ircheck·lean·z3) 공급 자체를 끊어 fail-closed 체인을 파괴한다(기각 사유). 축소 스코프는 **같은 재료를 더 작은 전용 채널(신설 스코프 엔트리 + 네이티브 설치 폴백)으로 계속 공급**한다 — 실행 대상(stage-b/stage-c)은 1바이트도 불변이며, 핀(lean-toolchain v4.33.0)·검증(A-verify `:362-365`·Lake 기능 프로브 `:696-728`·pins `:908-924`)은 스코프 내에 그대로 이동한다. 증명 재현성을 좌우하는 입력은 툴체인 버전 핀이지 공급 채널이 아니다.
3. **플랫폼 의미론 뒷받침**: 새 스코프 = 새 path list = 새 cache version(§4a) — full 엔트리와 교차 불가능이 플랫폼이 보장하고, runtime 선례가 동일 구조로 운영 중이다(238ms 복원 실측 §3.4).

**경계 조건(본 검증의 적용 범위)**: 위 확정은 attest 잡이 **lean+z3+jq만 실행 재료로 소비할 때** 성립한다. 현재 attest는 `core_purity_gate` 빌드로 nim도 소비하므로(`admission-check.yml:858-871`이 그 이유를 명시), 축소 성립의 **필요 전제는 core_purity_gate의 base artifact 멤버 이동**이다. 이 이동 자체는 verdict handoff 선례(`verdict_payload_gate_2026-10-12.md` — verdict 레그가 "lean/lake/z3/ircheck 실행 없음"을 실행 테스트로 증명해 GO)와 반대 방향의 검증 요구를 갖는다: attest는 정반대로 "실행 있음"이 계약이므로, 이동 후 attest가 nim 실행 없음을 유지하는지가 별도 사전등록 검증 항목이 된다. attest 잡이 MISS→네이티브 설치→체인 통과로 이어지는 전체 경로는 본 표본에서 미관측이다(콜드 시대 attest 잡은 HIT였음) — 이는 코드 계약(`:28-30`, `:832-858`)에 근거한 확정이며 실행 표본 밖이다.

### 5.2 부수 구조 사실 (계약 무관 · 관측)

- attest slice-engine의 jq는 composite 실행 **이전** 단계(`admission-check.yml:802`)에서 hosted 이미지 사전설치 jq로 소비된다(§4b) — 축소 스코프의 jq 공급 논의는 그 이후 단계 소비에만 해당한다.
- full 1.12GB 엔트리는 build-base·lane·단일잡 5종이 계속 소비하므로 축소로 소멸하지 않는다(§3.5). repo 캐시 총량은 10GB 상한·LRU(§4a) 내에서 1엔트리 증가한다.
- action.yml 편집 자체가 script_hash 회전 → repo 도메인 전면 1회 콜드(§2.5 실측: 콜드 시대 설치 85.1s/잡 + A-save 업로드 23.4s/잡, 콜드 실패 사례 §3.2). 이는 후보 고유가 아니라 action.yml을 건드리는 모든 변경의 공통 비용이다(#1192 §4와 동일 메커니즘).

---

## 6. 절감 추정 3분리

### (i) 원 절감 (관측 소요 × 빈도의 초)

- **웜(HIT) 성분 — 후보의 본체**: attest full-scope A-restore 실측 p50 **59.3s**(§3.3, n=5). 축소 스코프 복원 wall은 **미측정**(§3.6-1). 선형 외삽 앵커: 14.1MB→0.24s, 1.12GB→59.3s(실효 ~19MB/s). ~/.local/bin은 1.3%에 불과하므로 절감은 사실상 **~/.elan 비중의 함수**다: elan 비중 0.5GB(#1192 인용, 미실측) 가정 시 축소 복원 ≈27s → 절감 ≈**32s/잡**; elan 비중 0.75GB 가정 시 절감 ≈**17s/잡**. 즉 관측된 절감치가 아니라 **비중 미실측에 매인 추정 밴드 17-32s**다(#1192의 ~12-15s는 이 밴드 하단과 정합).
- **콜드(MISS) 성분 — 키 회전 시 1회성**: attest 잡 기준 full 설치 85.1s → 축소 설치 20.5s(§3.1 실측) = 절감 **64.6s**, 단 콜드 시대가 열리는 빈도는 action.yml 편집 시 1회(§5.2). 빈도곱: 랜딩 DAG당 attest 1회 + PR preflight당 1회(§3.5).

### (ii) P95 ±1200s 노이즈 대비 식별 가능성

- **전체 CI wall / R-7 n≥30 Before-After 기준**: 식별 불가 — provider 세대 스윙 P95 ±1200s(DAG 보고서 §8.4: failover 2310.7s vs gen12 1133.4s, `merge_queue_dag_attribution_2026-11-01.md`) 아래에서 17-32s는 노이즈 미달. #1192가 ~23s 경합 완화를 기각한 것과 동일 프레임이다.
- **잡 단위 지표(attest 잡 wall 또는 a-restore 스텝 duration)로 좁히면**: 절감 후보 크기(17-32s)와 잡 wall 표본 산포(91-133s, 범위 42s)가 동일 스케일이므로 **잡 단위 재측정 설계에서는 식별 가능성이 존재**한다. 단 이 경우 분 올림(아래 iii)이 별도 관문으로 남는다.

### (iii) 분 올림 규칙 하 실제 청구 반영

- 적용 조건 충족: private + GitHub-hosted(§4d) — **청구분은 실체**다.
- attest 잡 wall 실측 표본 5건(91/111/129/129/133s)의 청구분 = **2/2/3/3/3분** — 120s 경계가 표본 분포 **내부**에 있다.
- 절감치별 청구 반영(동일 표본 기계 적용): **−17s 가정** → 74/94/112/112/116s = 2/2/2/2/2분 → **5건 중 3건이 −1분**. **−32s 가정** → 5건 전부 −1분. 하단에서도 **−12s**는 129s 표본 2건이 −1분(133−12=121s는 미넘음), **−15s**는 133−15=118s까지 포함해 3건이 −1분. 즉 경계 근처 표본 분포상 절감이 밴드 하단(12s)이어도 청구 반영이 0이 아니며, 상단(32s)에서는 잡당 최대 1분(기대 ≈0.6분/잡, n=5 기준)이다.
- **한정**: 절감치 자체가 미측정 추정이므로(§6-i) 청구 절감액도 조건부다. 또한 청구분 감소는 월 단위 집계에서 attest 잡 빈도(랜딩+preflight, §3.5)로 선형 증가하나, 본 분석은 일자 표본만으로 월간 총량을 추계하지 않는다(미측정).

---

## 7. 사실 요약 (판정 없음)

1. ~/.elan·~/.local/bin은 **이미 full 스코프 A-layer 캐시 커버 하**다 — 후보는 커버 추가가 아니라 attest 공급 단위의 **축소**다(§2.1).
2. attest 체인은 lean(lake)+z3+ircheck를 **매 착지 실행**에서 소비하며, 그 소비는 복원 채널과 무관하게 재계산된다(§2.4·§5.1 — 랜딩 로그 관측).
3. 축소 스코프는 실행 재료의 공급 채널 전환이고 #1192 메커니즘 2(제거)와 달리 fail-closed 체인을 유지한다 — **단, 필요 전제는 core_purity_gate(nim)의 base artifact 이동**이며, 이동의 계약 검증은 별도 항목이다(§5.1 경계 조건).
4. 측정된 원 수치: 콜드 대상 경로 설치 20.5s·nim 쪽 64.6s·full A 복원 p50 59.3s·rt 복원 0.24s·엔트리 1.12GB vs 14.1MB. **elan 단독 비중과 축소 스코프 복원 wall은 미측정**(§3.6) — 절감 밴드 17-32s는 외삽 추정이다.
5. 경제 실체: 본 저장소는 private이므로 분 올림이 유효하며, attest 잡 wall 표본이 120s 경계에 걸쳐 있어 절감의 청구 반영은 경계 근처 표본에서만 발생한다(§6-iii).
6. **본 문서는 GO/NO-GO 권고를 포함하지 않는다.** 후보의 선정·사전등록 여부는 WP-B2 소유자의 판단 사항이다.

---

*관측 원천 run ID 일람: 41370265270(debt-registry-gate 콜드 설치), 41370265172(op-slice 콜드 실패+재실행), 41370265354(admission-gate preflight 콜드 시대), 41372519688·41372908404·41373196087·41374535265·41374953293(랜딩 merge queue 5건). 공식 문서는 context7 경유(actions/cache, actions/runner-images, leanprover/lean4, docs.github.com actions). 측정 스크립트 없음 — 로그 레코드(`##[end-action …duration_ms=]`) 직접 인용.*
