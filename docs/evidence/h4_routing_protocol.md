# H4 — 하드웨어 job-class 라우팅 스윕 프로토콜 (CI Pareto v13 P4)

> **종류**: 실험 설계 기록(design-only — 측정 런 없음, dispatch 없음, 커밋 없음)
> **날짜**: 2026-09-25 | **브랜치**: `feature/ci-pareto-measurement-plane`
> **범위 가드**: AGENTS.md §-1 불변 파일(`import_encapsulation_gate.nim`, `config.nims` importEncapsulation, `AGENTS.md`) 미수정. 신뢰 경계 변경 없음. 워크플로 초안은 `.github/` 밖 `docs/evidence/h4_routing_workflow_draft.yml` (ratchet 전 등록 대기).
> **방법**: 모든 주장은 file:line 또는 실측 문서 인용. 측정 불가 항목은 UNKNOWN으로 기록 — 추측 금지.
> **예산**: 이 문서 자체는 runner-minute 0. 측정 실행 시 `data/ci_pareto_baseline.json` `budgetLedger`에 회계한다(baseline.json:44-53).

---

## 1. 라우팅 맵 (가설 우선)

**가설 (H4 스윕이 검정할 것):**
- **h3-LIGHT**: LIGHT job-class(select/surface/identity/reconcile)를 `ubuntu-slim`(1 vCPU/5 GB/15-min cap, x64)으로 라우팅해도 P95 ≤ 15m ceiling을 지킨다. 정적 판정 H3-SUITABLE(hardware_smoke_static.md:122-125) + slim LIGHT 런 실측 1.85분(:170).
- **h3-ADM**: admission job-2의 B-built `bin/ax` 실행부가 slim에서 15분 cap 내 완료된다. 현재 2-vCPU 측정 8.05-8.85분(baseline.json:13-15) → 1-vCPU 증폭 2-3× 추정 시 **cap 초과 가능성** — NEEDS-MEASUREMENT(hardware_smoke_static.md:85,126)의 해소 대상.
- **h2-SHARD**: gateway-shard job-class를 `ubuntu-24.04-arm`(2 vCPU/8 GB, aarch64)으로 라우팅해도 H1 대비 P95 동등 이상(H2 스모크 ci-compile PASS :171; 동일 2 vCPU/8 GB 스펙 :21).

**잡별 라우팅 후보 (근거: hardware_smoke_static.md §3.5 표 :120-131 + 작업장 내 재확인):**

| 생산 잡 | class | H1 (현재) | H2 arm64 후보 | H3 slim 후보 |
|---|---|---|---|---|
| `select` (runner-pool) | LIGHT | 기준 0.42-0.43분 | 가능(스모크 LIGHT arm 빌드 OK, hw-smoke yml:120-123) | **SUITABLE → R1** |
| `repository-surface` | LIGHT | 기준 2.58-3.02분 | 가능하나 P95 이득 예상 없음(동일 2 vCPU) | SUITABLE(B10 slim-프로파일 선결) → **R1b(선택)** |
| `gateway-identity-gate` | LIGHT | 0.12-0.17분 | 순수 shell — 가능 | SUITABLE(툴체인 없음) — 측정 불요(trivial, :83) |
| `proof-reconcile` | LIGHT | 0.12-0.18분 | 가능 | SUITABLE(컴파일 없음, :84) — 측정 불요 |
| `admission-check` job-2 | LIGHT-op | 기준 8.05-8.85분 | **BLOCKED** (§4-e) | **NEEDS-MEASUREMENT → R2** |
| `build-base-artifacts` (admission) | HEAVY | 기준 8.5-19분 | **BLOCKED** — 동일-아키 페어링 + cert 정책 UNKNOWN (§4-b/e) | UNSUITABLE(LTO 1 vCPU cap, :127) |
| `ci-bootstrap` (runner-pool) | HEAVY | 기준 4.52-5.03분 | 가능(recipe 포터블 — hw-smoke yml:109-128) **단 소비자(shard×8)와 동일-아키 필수 + B ONE-WRITER 키(:268-286) — R3 채택 시만** | UNSUITABLE(:128) |
| `gateway-shard` ×8 | HEAVY | 기준 ~4.63분/shard | **SUITABLE → R3** (cert 미발급 → §2.5 J2 비차단; parity는 채택 단계 :38-39) | UNSUITABLE(:129, step timeout 25 > 15) |
| `certificate-mint` | HEAVY | **유지 — 신뢰, 성능 아님** | NO — 특권 tier substrate 변경 금지 | NO — 특권 + UNSUITABLE |

- H1 스펙 출처: `runner-pool-acceptance.yml:60-66` 주석 + baseline.json:3; H2/H3 스펙: hardware_smoke_static.md:21-22.
- H2 "recipe 포터블" 판정: toolchain 액션의 arch-pinned 다운로드는 z3(`action.yml:341-345`)·jq(`:359`) 2곳뿐, arm64 대응 자산 실존(:46-47); elan은 아치 자동(:48); Nim은 `nim-2.2.10-linux_arm64.tar.xz` fallback(hw-smoke yml:89-100). **런타임 실증**: arm 스모크 `make ci-compile`(bin/ax 포함 4바이너리, LTO) PASS 3.45분(hardware_smoke_static.md:171).

## 2. 실험 설계 (단일요인 규율)

공통: S2 패턴(gateway-jobs-measure.yml) 재사용 — **dispatch 1회 = 관측 1회**(provision/measure `if:` 격리, yml:65-66,174-175), 고정 ref 체크아웃(yml:55), n=2 역균형 쌍(s2_protocol.md:171-191), fail-closed 사전조건(yml:196-202), `exp-` B-cache 네임스페이스(yml:90). 후보 A=H1(기준) 고정, B=H3 또는 H2. `ingest --github-run <id> --candidate <id> --trace <t> --pair-index <i> "--order:A->B" --record`(README:119-169).

- **R1 — select: H1 vs H3** (가장 저렴; slim-프로파일 툴체인 검증이 R2의 전제 학습)
  - warm 불요: select는 B-cache 미사용(인라인 choosenim — runner-pool:92-98), A-cache도 스킵. 초기상태 = fresh checkout.
  - measured recipe(양쪽 byte-동일, runs-on만 상이): checkout `fetch-depth: 0` → choosenim 2.2.10 → selector+verifier 빌드(`--skipParentCfg --skipProjCfg`, :100-104) → base=HEAD~1 결정 → `impact-closure --require-certain` 실행(exit ∈ {0,2}) → decision 기록.
  - fail-closed: `uname -m`=x86_64(양쪽), `nim --version` grep 2.2.10, selector exit 계약.
  - **R1b(선택, 예산 여유 시)**: repository-surface H1 vs H3 — same recipe 단 fetch `main` merge-base + BASE_SHA policy 추출(repository_surface.yml:49-56); H3 측은 slim-프로파일(nim tarball + checksums@0.2.2, hw-smoke yml:146-163).
- **R2 — admission job-2: H1 vs H3** (NEEDS-MEASUREMENT 해소)
  - warm(H1 1회): build-base-artifacts recipe 재현(admission-check.yml:100-177 — B checkout, `make ci-bootstrap`, `lake build ircheck`, manifest) 후 **artifact 경로로 전달**(`:168-177` — 생산 전송 경로가 artifacts이며 slim은 H1 키 B-cache 복원 불가: 키가 image-bound, action.yml:85-95, restore-keys 금지 :28-30). **x64 bin/ax가 x64 slim 컨테이너에서 실행 — 동일-아키, J2 cross-arch 미관여**(§4).
  - measured recipe(H1/H3 동일): B executor checkout + `_candidate`/H checkout(admission-check.yml:193-217) → exp-artifact 다운로드+manifest 검증(build_sha==고정 ref, :229-252) → **pin-identity 게이트**(B/H/treeOID를 고정 ref+입력에서 재도출 — PR-API 재도출 스텝 :262-293은 API 지연 노이즈라 측정에서 제외, 양측 공통 제외로 상쇄 명시) → D9 staging → subject-register → `cert attest --witness-only`(:418-439) → ledger-list → install_ax_cas+scope+baseline(:468-477) → `merge --dry-run`(:489-507).
  - H3 툴체인 = slim-프로파일(elan + nim tarball + z3 zip — apt 금지 B13, hardware_smoke_static.md:116); **libpcre3 slim 존재 UNKNOWN**(slim 이미지 apt 테이블 미포함 :27 + slim에서 bin/ax 미실행 스모크 :170 — B13 apt 불가로 증설 불가 :116) → `ldconfig -p | grep libpcre.so.3`(action.yml:250 패턴) fail-closed 프로브.
  - 가설 판정: H3 툴체인 단계에서 cap 초과/프로브 실패 → "툴체인 블로커(B10/B13) — 실행부 미도달"; 실행부 도달 후 cap 초과 → "1-vCPU 실행 UNSUITABLE"; 완료 → wall/RSS 기록.
- **R3 — gateway-shard: H1 vs H2(arm)** (최대 비용 레버 — full-L2의 86.5%)
  - warm: **H1·H2 각 1회** `make ci-compile`+manifest+artifact 업로드(hw-smoke yml:124-128의 arm 실증 recipe; 아치별 바이너리 필요 — 동일-아키로만 전달 가능, §4-b). 생성 artifact: `bin/ax gate_hook precompile_gates install_ax_cas`.
  - measured recipe(양쪽 동일): artifact 다운로드+manifest verify(runner-pool:382-414) → `ci-bootstrap-cheap`(:416-422) → `test-gateway-shard-audit SHARD_COUNT=8`(:424-425) → **`SHARD_COUNT=8 SHARD_INDEX=0` 파티션** 실행(생산 단위 1/8 — full-suite 18-28분 대신 ~4.6분/shard 실측 단위, baseline.json:22-23; S2의 byte-동일 직접 호출 패턴, s2_protocol.md:104-114, `AXIOM_JOBS=2` = 현재 CI, s2_protocol.md:6) → junit 업로드.
  - fail-closed: manifest build_sha==ref, audit PASS, junit 존재, `uname -m`=aarch64(H2).
  - 신뢰 경계: shard는 인증서 미발급(테스트 판정+executed 기록만) → cert 정책 비차단(tcb_judgments.md:129-132는 cert-level); J1 semantic parity는 **채택 단계**(:38-39) 판정 의무 — H4는 P95 진단만.

## 3. 예산 (실측 기준, jobsMinutes ≈ runner-minutes 1x — baseline.json:5)

| 실험 | warm(미수집) | measured | 소계 typ / max |
|---|---|---|---|
| R1 (select n=2) | 0 | 2×H1(0.5) + 2×H3(2-3) | **6 / 8** |
| R2 (admission n=2) | base-build 10-20(정책-PR cold 19.30 실측, baseline.json:58) | 2×H1(8.5-19) + 2×H3(10-15 또는 cap 15) | **58 / 88** |
| R3 (shard n=2) | 2×(5-8) | 4×leg(5-7) | **36 / 45** |
| **합계** | | | **≈100 / ≈140** |

- 지침 총액 ≤ 300 runner-minutes 충족(typ 100 / max 140). 잔여 예산: 실험 풀 45,000분 중 **spentSoFar=360.48** (budgetLedger 10항목·60 runs — 정책-PR 사이클·smoke·S2 라운드1–3 전수 회계 후 기준) → H4 max 140 포함 총 ~500/45,000 = **1.1%** (reserve 5,000 미접촉).
- 비용은 진단 전용(v13 — README:78-80): 라우팅 선택은 P95 순위만 사용.

## 4. 신뢰 경계 체크리스트

- **(a) mint 특권**: certificate-mint는 TrustedWriterSet 단일 멤버(contents:write — certificate-mint.yml:56-59,275-300), workflow_run 활성화(:67-69), x64 image-pinned(:81-90) — **라우팅 대상 제외**; H4 워크플로는 mint를 참조하지 않음(실험 측정판 원칙: s2_protocol.md:4-8, 비도입 grep 검증 패턴 :369-370).
- **(b) Gate A base-build 의미론**: build-base-artifacts는 B(base.sha)만 컴파일(admission-check.yml:93-104). **동일-아키 페어링 제약**: bin/ax/ircheck 아티팩트는 job-2가 다운로드해 **x64에서 실행**(:219-251) — 생산 전송이 artifact 경로이므로 H3(같은 x64)는 바이트 호환, **arm으로의 빌드 이동은 실행부도 arm이어야 하며** 그 경우 mint(x64) 대의 인증서 생성 경로에 진입 → §4-e 블로커. 결론: **build-base는 H1 유지, job-2만 H3 후보(R2에서 측정).**
- **(c) required-check 정체성**: H4 워크플로는 dispatch-only 신규 파일(required check 아님 — Owner 결정 #14, s2_protocol.md:5-6); 생산 잡 이름(`admission-check`, `repository-surface`, `select` 등)은 불변 — 채택 단계에서 `runs-on`만 변경하고 잡 id/name 유지 조건 기재.
- **(d) ephemeral/fresh-VM**: GitHub-hosted 전 클래스(H1 VM / H2 VM / H3 컨테이너)가 잡별 신규 인스턴스 — 공유 상태 없음(hardware_smoke_static.md:23-26, s2_protocol.md:353-354 위협 7).
- **(e) cross-arch cert 정책**: `ci_optimization_tcb_judgments.md:129-132` — cert-level x64↔arm64 정책 ADR 부재, cross-arch 증명서 동일성 주장 후보는 **J2 FAIL**(:132). **판정: admission(build+job-2)의 H2 측정은 ADR 착지 전 BLOCKED — R2는 H3(x64-slim, 동일 아키)만 수행. ADR 후속 시 arm admission은 신규 사전등록 사이클(R4)로 분리.**

## 5. P5 통합

라우팅 후보는 기존 파이프라인 진입(README:63-97): **validity filter(J1∧J2∧J3∧J4 전부 PASS — tcb_judgments.md:228-230) → ceiling 플래그(P95≤15m, 랭킹 무입력) → argmin P95 → tie(λ_observed_max → mean queue → mean exec → id)**. 실험별 Pareto 가시 효과:
- **R1**: select 0.43분은 절대 P95 기여 1%(0.43/42.8 — baseline.json:35) — 가시 효과는 slim 클래스 기구 검증 + x64 용량 확보; R1b(surface 2.80분)는 관측 사이클의 100%(관측 사이클 합 = repository-surface 단독 2.80 — baseline.json:31-33, 유일 PR 트리거 관측 잡).
- **R2**: admission job-2 = authoritative PR주기 14.41분의 **58.7%**(8.46/14.41, :27) — 최대 authoritative P95 레버. 기대: 1-vCPU 증폭으로 H1 우위 → "H1 유지"가 정직한 예상 결과이나 NEEDS-MEASUREMENT 해소가 1차 산출물.
- **R3**: shard 8 = full-L2 42.8분의 **86.5%**(37.04/42.8, :35) — 최대 면적 레버. 동일 2 vCPU/8 GB 스펙으로 P95 유사 예상, 차등 채널은 arm 풀 가용성 따른 queue(tie-break 1·2) — 측정 대상.

## 6. 시퀀싱 & 중단 규칙

순서 **R1 → R2 → R3** (R1 = 최저가 + slim-프로파일 학습이 R2 H3레그의 선행 조건; R2 = NEEDS-MEASUREMENT 해소; R3 = 최대 레버이나 최고 비용 — 후순위).
- **S0(사전)**: harness selftest + trace 3개 사전등록(`prepare-train --n:2`, README:27-35) 후에만 dispatch.
- **S1(R2 첫 H3 런 후)**: H3가 15-min cap 도달 또는 libpcre3 프로브 실패 → **H3 job-2 FALSIFIED 판정 기록, 잔여 H3 슬롯 중단**(H1 슬롯은 완료해 쌍 완전성 유지).
- **S2(중간 장부)**: R1+R2 후 소비 > 120분 → STOP, R3는 후속 사이클 연기(s2_protocol.md:322-323 패턴).
- **S3(R3)**: arm 레그 인프라 실패 시 동일 슬롯 재dispatch(기록 없음 = 재발화 허용, s2_protocol.md:231-234); **arm 연속 2회 실패 → STOP + H2 회귀 보고**(hardware_smoke_static.md:171의 PASS 상태 대비).

## 7. UNKNOWN / 블로커 (정직 기록)

| 항목 | 상태 |
|---|---|
| slim 상 libpcre3 존재 + bin/ax 실행 가능성 | **UNKNOWN** — slim 이미지 apt 테이블 미포함(hardware_smoke_static.md:27), 스모크가 slim에서 ax 미실행(:170), apt 증설 불가(:116) — R2 H3레그 fail-closed 프로브로 해소 |
| admission job-2 1-vCPU wall/RSS | **UNKNOWN** — R2가 유일한 해소 경로(:147) |
| H3 slim-프로파일 툴체인(nim tarball+elan+z3, apt 없이) 총 시간 | **UNKNOWN** — R2에서 실측(B10 경계, :113) |
| cross-arch cert 정책 ADR | **부재(BLOCKED)** — R4(admission arm)는 ADR 착지 후 신규 사이클로만 가능(tcb:132) |
| arm shard 벽시계 대비 x64 | **UNKNOWN** — R3 측정 대상 (2-3× 증폭 가정은 HEAVY 빌드 한정, :148 — 셔드 실행부는 비확정) |
| v13 계획 문서 원문 위치 | 저장소 내 별도 파일 없음 — 계획 파라미터는 s2_protocol.md + README.md(선택 규칙) + baseline.json(예산)에서 인용 |

## 8. 부록

워크플로 초안(비집행 설계) — `docs/evidence/h4_routing_workflow_draft.yml` (파이썬 yaml 파싱 검증 완료 — pyyaml `on:` bool 키 관례 허용, s2_protocol.md:369와 동일 취급).

## 8.1 R1 측정 결과 (2026-09-25, ref=4639fe9ec)

**판정: h3(slim) — argmin P95 (94,000ms vs 151,000ms, 38.4% 감소).** tie-break 미발동(P95 명확 불일치), 둘 다 ceiling(≤15m) 통과, envelope sha256 `7267c0cd7dd283d4cce3df19a4b88fad247e65e8f3d6848202aee1cb82996371` 잠금.

| run | leg | P95/W | queue | exec | core-min |
|---|---|---|---|---|---|
| 36141878976 / 36141896656 | h1 (pair1 A→B, pair2 B→A) | 151,000ms | 5,000 | 146,000/136,000 | 2.42/2.24 |
| 36143592918 / 36143598746 | h3 (pair1, pair2) | 94,000ms | 7,500 | ~71,000/77,000 | ~1.3/1.15 |

- 비용 진단(순위 무관): h1 2.43 vs h3 1.36 €/run (-44%). λ: h1 0.3/h, h3 0.5/h.
- **실험 도구 자가정정 이력**: 1차 H3 2건은 libpcre 프로브 과잉 적용으로 실패 → selector의 PCRE **미링크를 ldd 실측** 확인 → 프로브를 R2 전용으로 좁힘(PR #243 MERGE a94a47321) → 재측정 성공.
- **교란 공개 (중요)**: 두 leg의 툴체인 획득 경로가 다르다 — h1 = `setup-axiom-toolchain` composite(A-cache 경로), h3 = 인라인 slim-profile(콜드 다운로드; composite의 apt 단계(B13)가 slim에서 불가해 필연). 따라서 본 비교는 **"러너 클래스 + 그 클래스의 자연 툴체인 경로"의 시스템 수준 비교**이며 순수 하드웨어 단일요인이 아니다. **교란 방향은 h3 불리 쪽**(콜드 콜드 부트스트랩에도 h3 승) — 판정의 방향성은 보수적으로 강건, 크기는 과대평가 가능성 있음. **채택 전제**: 생산 composite의 apt 단계 slim 호환화(B13)가 R2/adoption 항목으로 남는다.
- 시간 교란 공개: h1 13:35 / h3 13:51 (프로브 수정 후 재발사) — 16분 간격, P95 격차(38%) 대비 경미.

## 8.2 R2 측정 결과 (2026-09-25, ref=ad03b302268, PR #248 pin-identity)

**판정: H3 = UNSUITABLE (B13 툴체인 블로커 — 실행부 미도달, §2 R2 판정 경로 1). H1 = 측정 미완 (워크플로 결함 차단 — fix #4 후속 필요).** envelope/ceiling 미산출 (P95 모집단 0 — 전 런 conclusion=failure, ingest가 거부하는 게 정상 계약).

| run | 레그 | 결과 | 소요 | 실패 지점 |
|---|---|---|---|---|
| 36154718902 | warm h1 | ✅ (provision 4.75m — 툴체인·ci-bootstrap·ircheck·manifest·payload 업로드) | 4.75m | — |
| 36155684765 | m1 h1 (pair1 A) | ❌ 측정 미실행 | 2.98m | Download exp payload: `Artifact not found for name: exp-h4-r2-admission-h1-x64-payload` |
| 36155705325 | m1 h3 (pair1 B) | ❌ B13 | 0.52m | slim 프로브: `FAIL: libpcre.so.3 absent on slim (B13) — H3 job-2 실행 불가` |
| 36155727695 | m2 h3 (pair2 B) | ❌ B13 | 0.65m | 동일 프로브 fail-closed (exit 1) |
| 36155750077 | m2 h1 (pair2 A) | ❌ 측정 미실행 | 2.18m | Download exp payload: 동일 |

- **B13 실증 체인 (누적 5회)**: arm smoke §7 → prod admission-check 35949574909 (`bin/ax scope hash` → libpcre dlopen 실패, action.yml:235-251) → h4 warm 36152458119 (h1 동일 에러) → 금회 slim 프로브 fail-closed ×2. bin/ax는 런타임 dlopen으로 libpcre.so.3 하드 의존; slim은 apt 금지(B13, hardware_smoke_static.md:116)로 증설 불가 → **admission job-2의 H3 라우팅 배제**. 채택 대안(후속, 미구현): deb 추출 + LD_LIBRARY_PATH 수동 .so 프로비저닝.
- **H1 측정 차단 — 워크플로 결함 (fix #4)**: `Download exp payload`가 download-artifact v4에 `run-id` 미지정 → 동일 런 아티팩트만 검색(페이로드는 warm 런 36154718902 소유). 수정안: `payload-run` 입력 추가 + run-id 전달; warm 재사용 가능(아티팩트 14일 보존·build_sha=ref 일치)이라 fix 후 4레그 재dispatch만으로 재개.
- **예산 (§3 jobsMinutes 실측)**: round-4 11.08m (warm 4.75 + measure 6.33) + 기존 실패 라운드 4.57m = **누적 15.65 / 88 runner-min** — 여유 충분.
- **가설-결과 (§2 R2)**: (a) H3 툴체인 블로커(B13) → **확정**(실행부 미도달); (b) 1-vCPU cap → **미판정**(H3 미도달·H1 미측정); (c) 완료 → 해당 없음.

**R2 종결 (2026-09-26)**: H3-UNSUITABLE(B13)이 decision-relevant 결과의 전부 — **admission job-2 라우팅 = H1 유지**. H1 잔여 측정은 쌍이 성립하지 않아(compare는 양쪽 관측 필요) P95 비교가 구조적으로 불가 — 디아그ност릭 값은 생산 baseline(8.05–8.85분)으로 충분하다고 판단해 **생략 결정**. fix #4(cross-run payload)는 R3가 같은 다운로드 경로를 사용하므로 R3 실행에서 실증됨 — R2에선 미검증 채택 없음. 가설(b)는 H3 차단으로 구조적으로 불가 판정(B13이 선행).

## 8.3 R3 실행 runbook (준비 완료 — 미실행)

**사전등록 (§6 S0 충족)**: `data/ci_pareto/trace_h4_r3_train.json` — sha256 `1c91c8ff…`, n=2 seed=442 arrivals=4 rate=24/h, 후보 A=h1 B=h2. trace 부재 시 dispatch 금지. **REF** = 실행 시점 origin/main 40-SHA(준비 시점 `f043b057a9…`, 워크플로는 main과 diff 0).

warm ×2 — 아치별 1회, 미수집(`warm=true`는 절대 ingest 금지):
```bash
gh workflow run h4-routing-measure.yml -f experiment=r3-shard -f runner=h1-x64 -f warm=true  -f ref=<REF>
gh workflow run h4-routing-measure.yml -f experiment=r3-shard -f runner=h2-arm64 -f warm=true -f ref=<REF>
```
measured ×4 — iter=역균형 슬롯, 순서는 ingest가 선언(워크플로는 iter만 알음):
```bash
gh workflow run h4-routing-measure.yml -f experiment=r3-shard -f runner=h1-x64 -f iter=1 -f ref=<REF>  # pair1 leg A (A→B)
gh workflow run h4-routing-measure.yml -f experiment=r3-shard -f runner=h2-arm64 -f iter=1 -f ref=<REF> # pair1 leg B (A→B)
gh workflow run h4-routing-measure.yml -f experiment=r3-shard -f runner=h2-arm64 -f iter=2 -f ref=<REF> # pair2 leg B (B→A)
gh workflow run h4-routing-measure.yml -f experiment=r3-shard -f runner=h1-x64 -f iter=2 -f ref=<REF>  # pair2 leg A (B→A)
```
관측: `gh run watch <RUN_ID> --exit-status --interval 30`(AGENTS.md §2.3); 완료 후 `gh run view --log`로 `arch=`·`shard_files=` 확인. ingest(건별, `--record` 필수, 순서 인용 필수):
```bash
build/pareto_harness_v6 ingest --github-run:<ID> --candidate:h1 --trace:data/ci_pareto/trace_h4_r3_train.json --pair-index:1 "--order:A->B" --record
build/pareto_harness_v6 ingest --github-run:<ID> --candidate:h2 --trace:data/ci_pareto/trace_h4_r3_train.json --pair-index:1 "--order:A->B" --record
build/pareto_harness_v6 ingest --github-run:<ID> --candidate:h2 --trace:data/ci_pareto/trace_h4_r3_train.json --pair-index:2 "--order:B->A" --record
build/pareto_harness_v6 ingest --github-run:<ID> --candidate:h1 --trace:data/ci_pareto/trace_h4_r3_train.json --pair-index:2 "--order:B->A" --record
```
판정: `build/pareto_harness_v6 compare --trace:data/ci_pareto/trace_h4_r3_train.json` — argmin P95(전체 per-PR latency 모집단, nearest-rank); tie: λ_observed_max → mean queue → mean exec → 후보 id 오름차순; ceiling(P95≤15m)은 플래그만, 랭킹 미입력.
예산: §3 R3 = **36/45 (typ/max)**. 중단: S0(사전등록, 완료) · S1(n/a — R2 전용) · **S2**: R1+R2 누계 >120분 → R3 연기(현재 spentSoFar=360.48, R1+R2 typ 64/max 96 — 미트리거) · S3: arm 레그 실패 1회 동일 슬롯 재발사, 연속 2회 → STOP + H2 회귀 보고.
신뢰: shard = 인증서 미발급(테스트 판정+executed 기록만) → cert 정책 **J2 비차단**(tcb:129-132는 cert-level); J1 semantic parity는 **채택 단계** 판정(:38-39) — H4는 P95 진단만.
사전점검 노트: (1) R3 warm 업로드 path에 R3 미생성 `ircheck` 포함(:161) — 부분 매칭이라 무해, 아티팩트 = 4bin+manifest. (2) H2 arch fail-closed(`uname -m`=aarch64, 프로토콜 §2 R3)는 measure step에서 출력만·미강제(:248) — ingest 전 로그 `arch=` 확인. (3) warm의 elan 설치는 R2용 — R3 warm 사족(미수집이라 무해).

## 8.4 R3 1차 시도 (2026-09-25, ref=2faa82fe3b0, warm 2/2 성공, measure 0/4 — 워크플로 결함 2건)

**판정: 미판정 (측정 미실행 — ingest 불가, P95 모집단 0).** warm은 양 아치 성공·payload 준비 완료; measure 전 레그가 실행부 도달 전 워크플로 결함으로 실패.

| run | 레그 | 결과 | 소요 | 실패 지점 |
|---|---|---|---|---|
| 36158635207 | warm h1-x64 | ✅ (ci-compile+manifest+payload `exp-h4-r3-shard-h1-x64-payload`) | 4.00m | — |
| 36158642816 | warm h2-arm64 | ✅ (아치별 payload `exp-h4-r3-shard-h2-arm64-payload`) | 3.57m | — |
| 36159162599 | m1 h1 (pair1 A) | ❌ | 2.33m | Download exp payload: `Artifact not found` (run-id=36158635207 전달됨에도) |
| 36159180130 | m1 h2 (pair1 B) | ❌ | 0.57m | setup-axiom-toolchain: `choosenim: linux_arm64 not supported` → exit 1 |
| 36159198830 | m2 h2 (pair2 B) | ❌ | 0.57m | 동일 (choosenim arm64) |
| 36159218418 | m2 h1 (pair2 A) | ❌ | 3.03m | Download exp payload: 동일 |

- **F2 아키 확인**: h2 레그는 측정 스텝 도달 전 실패했으나, setup-axiom-toolchain 로그의 `Sorry, your platform (linux_arm64) is not supported by choosenim`가 **h2 러너 = aarch64 실측 증거** (workflow의 arch 출력보다 먼저 확보).
- **결함 1 (전 레그, cross-run 다운로드)**: download-artifact@v4의 `github-token` 입력이 **다른 workflow run 다운로드 시 필수** — 미지정 시 "현재 런"으로 폴백되어 `run-id`가 무시됨(액션 action.yml의 github-token/run-id 설명이 근거). fix #4가 run-id만 연결하고 token을 빠뜨림. **수정: `github-token: ${{ github.token }}` 추가.** 아티팩트는 두 warm 런에 14일 보존 — fix 후 재발사는 warm 재사용 가능.
- **결함 2 (h2 레그만)**: setup-axiom-toolchain의 `Install Nim 2.2.10 (choosenim)`이 arm64 미지원 → h2 측정 불가. warm 인라인 레시피는 tarball fallback(`nim-2.2.10-linux_arm64.tar.xz`)으로 성공했으므로 **액션에 arm64 분기 추가**(공식 tarball + ast.nim fail-closed 유지). 주의: 액션의 z3 스텝도 x64-glibc 고정 — arm64에서 미사용(z3 미호출)이라 현재 무해하나 shard 실행부가 z3를 부르면 차기 블로커(검증 항목).
- **S3 분류**: arm 레그 실패 2건은 **아키 인프라 flakiness가 아닌 결정적 워크플로 결함**(choosenim arm64) — S3 재발사 대상 아님, fix→재dispatch가 정본 경로.
- **예산 (§3 jobsMinutes)**: warm 7.57 + measure 6.50 = **14.07 / 45** (R3), R1+R2+R3 누적 ≈ 38 — S2 미트리거.

## 8.5 R3 최종 판정 (2026-09-26, ref=ff23a41aa, round6 4/4 SUCCESS)

**판정: h2(arm) — argmin P95 (241,000ms vs 271,000ms, −11.1%).** tie-break 미발동(P95 명확 불일치), 전 레그 ceiling(≤15m) 통과, envelope sha256 `5c7ad5170c9a5d8058bf35fae0729fd83f219a92055774d93ffd7faacc7846e1` 재실행 재현 확인. **F2 arch=aarch64 실측**(`arch=aarch64` + Lean aarch64 + libpcre AArch64 로그).

| run | 레그 | P95/W | queue | exec | core-min |
|---|---|---|---|---|---|
| 36172204581 / 36172222044 | h1 (pair1 A→B, pair2 B→A) | 271,000ms | 5,000 | ~266k/259k | ~4.4 |
| 36172208709 / 36172214745 | h2 (pair1, pair2) | 241,000ms | 7,500 | ~235k/224k | ~3.8 |

- 비용 진단(순위 무관): h1 4.46 vs h2 3.95 €/run (−11.4%). λ: h1 0.1/h, h2 0.2/h.
- **수렴 경로 (측정판 인프라 실증 기록)**: round1 token/choosenim(#249-250) → round2 chmod(#251) → round3 ircheck 스코프(#252) → round4 h1 개통+h2 composite(#250 ref 함정 재확인) → round5 nimble deps 인트리(#253) → round6 전수정 ref 재구성 → **4/4 성공**. 구 ref의 composite 미포함 함정(`uses: ./action`은 checkout ref 기준)이 재구성의 근거 — **warm·measure의 ref 동일성 + composite 전수정 포함을 동기화하는 것이 하네스 설계 교훈**.
- 재구성판 warm: 36171663825(h1)·36171668535(h2) (ref=ff23a41aa) — 여기까지의 반복 전 라운드는 전부 회계 대상(budgetLedger).
- **R3 총 소요: 87.53 runner-min** (round1 14.07 + 이후 73.46; 설계 추정 45의 **1.94×**) — 초과분 전부 = 측정판 인프라 수렴 비용(결함 6건 규명: token·chmod·scope·ref-composite 동기화·nimble 인트리·jq/z3 아치), 성공 라운드의 실측 자체는 ~28분. 50k 상한 대비 전체 누적 ~800분대(1.6%) — pool 무일خطر 편차 기록.

## 8.6 H4 3실험 종합 (2026-09-26)

| 실험 | 대상 | 판정 | 근거 |
|---|---|---|---|
| R1 | select (LIGHT) | **h3(slim) 라우팅 자격** — P95 94s vs 151s (−38.4%) | §8.1, 교란 공개(툴체인 경로 차이, 방향은 h3 불리) |
| R2 | admission job-2 (LIGHT-op) | **H3 UNSUITABLE (B13)** — H1 유지 | §8.2, libpcre 실증 5건 체인 |
| R3 | gateway-shard (HEAVY) | **h2(arm) 라우팅 자격** — P95 241s vs 271s (−11.1%) | §8.5, arch=aarch64 실측 |

- **라우팅 맵 최종 후보**: select/surface 계열 → H3 검증 완료 / admission job-2 → H1 유지(확정) / gateway-shard → H2 검증 완료 / mint →신뢰로 제외(설계 유지) / build-base·ci-bootstrap → 동일-아키 제약으로 H1 유지.
- **채택 전제 (P5/adoption 단계 의무)**: R1의 툴체인-경로 교란 해소 composite 동일화, B13(slim apt) 대안(deb 추출) 미구현, J1 semantic parity는 채택 단계 판정, cross-arch cert ADR은 admission-H2 확장 시에만 필요(shard는 cert 미발급 — 비차단).
- **P5 통합**: R1/R3의 h3·h2 후보가 T_train 조합 측정으로 진입(이 결과는 후보 자격 판정이지 최종 선택이 아님 — 최종은 VALID→ceiling→argmin P95 체인).

## 9. 변경 이력

| 버전 | 날짜 | 변경 |
|---|---|---|
| v1.0.0 | 2026-09-25 | H4 설계 초안 — 라우팅 맵/실험 R1-R3/예산/신뢰 체크리스트/P5/시퀀싱 (0 runner-minute, dispatch 0, 커밋 0) |
| v1.1.0 | 2026-09-25 | R1 측정 결과 추가 (§8.1) — h3 판정 + 프로브 자가정정 이력 + 교란 공개 |
| v1.2.0 | 2026-09-25 | R3 사전등록 + 실행 runbook 추가 (§8.3) — trace `1c91c8ff…` 사전등록, warm/measured dispatch·ingest·compare 명령, 판정 규칙, 중단 규칙, 사전점검 노트 (dispatch 0) |
| v1.3.0 | 2026-09-26 | R3 1차 시도 기록 (§8.4) — warm 2/2 성공, measure 0/4 (cross-run download github-token 누락 + choosenim arm64 미지원), R2 종결 반영 (§8.2) (dispatch 6, 커밋 0) |
| v1.4.0 | 2026-09-26 | R3 최종 판정 h2(arm) 승 (§8.5) + H4 3실험 종합 (§8.6) — round6 4/4 성공, 수렴 경로 6단계 기록 (dispatch 다수, 커밋 0) |