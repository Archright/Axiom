# Admission Gate 성능 개선 설계 — 구현 승인 대기

상태: **DRAFT — 아키텍트 승인 대기.** 본 문서의 저장소 착지(MERGE)는 구현 승인이 아니며, 승인 요청 사항(§8)이 별도 판정 지점으로 명시된다.

작성 근거: 12개 merge_group 표본의 잡 단위 해부(대표 run 43399299637·43359261607 — 모든 수치는 run ID에 결속) + 5중 핀 지도·10단계 절차 매핑 실측 + 계약 원문 검증. 관측 시점 원격 main 923633f, admission-check.yml blob `8db2ad30` (= TWS = epoch_manifest 핀).

## 1. 목적과 비목적

목적: merge queue 배치 시간의 실측 임계 레그인 admission 레그(484-511s)를, 검증 의미론·증거 무결성·병합 권한을 불변으로 유지하면서 단축할 수 있는 변경의 **계약 분류와 착지 절차**를 확정한다.

비목적: 검사 항목 축소, lane 독립성 약화, required check identity 변경, 병합 권한 이전. 이들은 본 설계의 경계 밖이며 후보 분류(§3)에서 명시적으로 배제 또는 승인 요건으로 격리된다.

## 2. 실측: 임계경로의 실체

### 2.1 임계 연쇄 (MG 배치, 12 표본)

| 구간 | 소요 (PR#20 / PR#8) |
|---|---|
| attest/build-base-artifacts | 54s / 49s |
| **attest/go-critical-lane(0)** | **294s / 302s** |
| attest/admission-check | 55s / 56s |
| mint-prepare | 22s / 27s |
| mint-publish | 36s / 54s |
| 최종 집결 | 2s / 4s |
| 잡 간 큐·핸드오프 대기 (~7 간극 × 2-4s) | 21s / 19s |
| **admission 레그 합계 (잡 소요 합 463s/492s + 간극)** | **484s / 511s** |

12 표본 전수: 511/453/342/424/455/499/492/396/441/441/395/484 — SLO(480s) 초과 4건(511·499·492·484), 임계 레그 11/12에서 admission(PR#6 단일 반례: pub-int 368s > admission 316s — 별세대).

### 2.2 lane(0)의 분해 — 병목은 테스트 실행이다

- lane(0) 294s = 오버헤드 ~45s(toolchain 28s·셋업·업로드) + **evidenceId contract 배터리 99s** + **s1a 단일 테스트 150s**(로그 실측 `duration_ms=150148` — 컴파일 아님, 런 간 안정, nimcache warm 237 entries).
- lane(1) 184s = 오버헤드 ~54s + evidenceId 77s + GO 테스트 3건 53s.
- 캐시 A/B-layer는 전 관측 잡 exact-hit(1.07GB A-layer, `a-restore` 14.8s/잡) — 컴파일 재수행 0건, 러너 큐 대기 2-4s/잡, `timed_out` 0건. **남은 시간의 본질은 toolchain 복원 + 테스트 실행 + 직렬 오케스트레이션이다.**

### 2.3 배치 시간의 포화점

PR#20 배치: 총 498s = admission 484s(최장) + gap 14s; 차점 레그 pub-int 381s(내부 license-scan 샤드(1) 324s). **admission을 381s 이하로 단축해도 배치 시간은 ≈395s(381+gap)에서 포화** — 그 시점부터 pub-int가 신임계 레그가 된다. admission 단독 개선의 상한이다.

## 3. 개선 후보의 계약 분류 (후보 — 미승인)

전제 교정(본 설계의 핵심 발견): lane 매트릭스는 사전등록 스펙 `docs/evidence/go_matrix_parallelization_prereg_2026-10-16.md`(§1 분할·§2 진입 전제·§3 실행 의미론 = "the binding spec of this job", admission-check.yml:3332-3336)에 결속되어 있고, **s1a 단독 lane**(“G-A critical-path matching: the longest single test runs solo”, :3428)과 **per-lane evidenceId 배터리**(“EXECUTED always”, :3910)가 분할을 핀한다. 따라서:

- **C1(단순 lane 재분배)의 절감 ~55s 가정은 반박됨** — lane-1의 3테스트를 재배치해도 max(lane)=lane(0)=294s는 불변(s1a+evidenceId가 lane(0)을 구성). 계약 보존 재분배의 절감은 **0s**다. 55s는 "lane 작업의 자유 재분배" 가정의 산물이었다.
- lane(0)을 294s 이하로 만드는 방법은 셋뿐이고 전부 계약 개정을 수반한다: (a) evidenceId 배터리의 lane 밖 재배치(독립성 계약 개정), (b) s1a 단독 완화(1/1 GO-critical 계약 개정), (c) 배터리·테스트 자체의 실행 시간 단축(제품/도구 코드).

### Tier 분류

| Tier | 후보 | 계약 상태 | 예상 절감 (admission 레그) | 산출 근거 |
|---|---|---|---|---|
| **1 — 계약 보존 (CI 토폴로지 변경, Epoch Cutover 범위)** | C3: toolchain 스코프 축소 — attest/admission-check 잡(사전빌드 ax 소비, mint류의 runtime 범위 선례: 7-11s vs 풀 스코프 28s) | 보존(단 경로 의존적 — §7) | ~15-20s | a-restore 14.8s/잡 실측·mint 대조 |
| | C6: deriver 중복 컴파일 통합 | 보존 | ~1-4s | closure-deriver 4s + build-base 1s(동일 B deriver) |
| | C7: 적색 경로 단축(verdict 실패 후 mint-publish 계속) | 보존 | 그린 SLO 0s(실패 PR당 ~15s) | run 43399756546 관측 |
| **2 — 바인딩 사전등록 개정 (아키텍트 승인 필수)** | C1-rev: lane 분할 개정 — evidenceId 배터리를 lane 밖 병렬 잡으로 재배치(+ s1a lane은 1/1 계약 유지) | **개정**: prereg §1·G-A 의도 재정의 + per-lane 독립성 약화 승인 | **~99s** (Tier 1 합산 시 ~115s) — critical: build-base 54 + max(lane-0≈195, 배터리잡≈144, lane-1≈184) + admission-check 55 + mint 60 + 간극 ≈21 ≈ **~385s** (Tier 1+2 ≈ **~369s**) | §2.1·§2.2 분해 산술 |
| | (대안) s1a 단독 완화 | **개정**: 1/1 GO-critical 계약(:4126) 수정 | 유사 규모, 계약 위반이 더 직접적 — 권고하지 않음 | — |
| **3 — 제품/도구 코드 (CI 토폴로지 밖, 별도 슬라이스)** | C5: s1a 테스트 실행 150s | 보존(GO-critical 의미론 불변) | lane(0) 비례 절감 | duration_ms=150148 실측 |
| | 배터리 최적화: evidenceId self-check 2건 실행 99s/77s | 보존 | lane 비례 | 스텝 타임라인 |
| **명시적 배제** | C2: evidenceId 배터리 dedup(양 lane 공유 1회) | **§0.9 인접 위반** — "EXECUTED always" per-lane 독립 계약 파기 | ~99s | 채택 금지 권고 |

Tier 1 단독: admission ≈ 460-468s → 배치 ≈ 474-482s(480s SLO 경계). Tier 1+2: admission ≈ 369s → **pub-int(381s) 포화점 도달, 배치 ≈ 395s, SLO 여유 ~85s**. Tier 3은 추가 이득이나 별도 제품 슬라이스다.

### C3+C6+C7 및 C1-rev의 절감 모델 (직렬 DAG 기반)

임계 연쇄 = build-base → lane(0) → admission-check → mint-prepare → mint-publish → 최종(§2.1). C3는 admission-check 잡의 스코프 축소만 가정(빌드·lane 잡은 컴파일·테스트에 풀 스코프 필요)하고, C1-rev는 lane(0)에서 배터리 제거(99s)와 배터리 잡의 병렬화(임계 비편입)를 가정한다. 수치는 §2.2 분해 성분의 산술이며, 실측 확정은 착지 후 Production Acceptance 관측이 한다(§6).

## 4. 보존 불변식 (계약 원문 — 착지 PR이 반드시 유지·재검증)

1. **1/1 GO-critical (s1a lane)**: `admission-check.yml:4126` — "expected exactly 1 (the 1/1 GO-critical contract)". lane 구성 변경 시 이 검사가 여전히 참이어야 한다.
2. **evidenceId 배터리 per-lane 독립 실행**: `:3910` "[lane] evidenceId contract check (B-owned checker — self-check battery, EXECUTED always)" — C1-rev는 이 계약의 개정을 명시적으로 승인받아야 한다(Tier 2).
3. **4테스트 완전성**: `:3342-3347` — 네 테스트는 "the ONLY direct tests of the terminal admission machinery", 은폐 축소는 `productization_contract_freeze_v1.md`(FROZEN E1-E5) 위반.
4. **SKIPPED≠GREEN·GATE A(B 실행 트리)·JUDGMENT CAS(SL-15, "the plan never invents a reuse")·FAILS 누적·fail-fast:false·CACHE ISOLATION**: `:3352-3410` 불변식군.
5. **required check context `admission-check`·집결 잡 구조 이름 불변** — 존재 조건(ruleset 27097366의 6 required checks).
6. **TWS·epoch_manifest 원자 페어**: admission-check.yml 변경 PR은 같은 커밋에서 `.trustedAdmissionWorkflowSha`(`config/trusted_writer_set.json:41`)·`.productionExecutionPin`(`config/policy/epoch_manifest.json:25`) 갱신 — 4곳 fail-closed 검증(landing-integrity pairing·`verify_trusted_writer_set.sh:164-172`·`epoch_transaction_gate.nim` G2a·`certificate-mint.yml:841`).

## 5. 전환 구조 — 10단계 Epoch Cutover 매핑 (5중 핀)

핀 지도(2026-11-13 라이브 API readback — `GET /orgs/Archright/rulesets/25218071`·`/23943917`, `GET /repos/Archright/.github/contents/.github/workflows/admission-gate-v2.yml?ref=6b91c6e7`; 저장소 내 종전 기록인 2026-11-01 `d76caf95`·2026-11-03 `498c5570`은 2026-11-12 Gen-4 회전 PR #267로 갱신됨): ① admission-check.yml blob `8db2ad30` ② TWS ③ epoch_manifest(원자 일치) ④ Archright/.github 래퍼 `admission-gate-v2.yml`가 Axiom callee 3종+action을 `@c021c338` 커밋 핀(workflow_call) ⑤ org ruleset 25218071·23943917이 .github@`6b91c6e7` SHA 핀(ref 없음).

**Axiom main의 admission-check.yml 변경만으로는 게이트 실행이 바뀌지 않는다**(callee가 c021c338에 핀) — 다음이 하나의 cutover이다:

1. 절차 1-3 Freeze·Record·Tombstone — **Axiom 변경 이전**.
2. Axiom 착지 = 절차 4. admission-check.yml·TWS·epoch_manifest는 trustSurface — `§4.2` 자기 핀 자기 등록 구조상 Axiom 큐 착지가 불가하므로 **ROT_ALLOWLIST 사전등록** 또는 운영자 rotation 경로 필수.
3. 컨트롤러(.github) callee 핀 회전 PR + **양 org ruleset 동시 재핀 + readback** = 절차 5, 하나의 논리 단위(§5: 빈 큐 확인 → repo ruleset `max_entries_to_build` 2→0 freeze → 동시 재핀 → byte-consistency readback → 복원. ref:main 복원 금지).
4. 절차 6-7 Local/Targeted·Short Validation — 성능 개선이므로 실측 지표 포함.
5. 절차 8 Canonical Cutover — required check identity·trust semantics 무변경 확인.
6. 절차 9 Production Acceptance — 실제 landing 1건 + 4중 독립 채널(E1 referenced_workflows·E2 job 로그 Uses·E3 핀-트리플 지문+시간 경계·E4 required check+native MERGE) + 발산 테스트.
7. 절차 10 Rollback — frozen epoch를 명시적 rollback reference로 보존.

## 6. 성공 판정 기준 (관측 가능)

| 항목 | 기준 |
|---|---|
| 검증 의미 보존 | 6/6 required checks SUCCESS + §4 불변식 재검증 통과 + E1-E4 수용 채널 |
| Tier 1 | admission 레그 ≤ 465s (≥2 관측) |
| Tier 1+2 | admission 레그 ≤ 385s (≥2 관측) — pub-int 포화 진입 |
| 배치 총시간 | Tier 2 착지 후 ≥2 관측에서 ≈395-410s (480s SLO 여유) |
| P95 | 표본 축적 후 별도 판정(초기 acceptance와 지속 SLO 구분 — 2회 관측은 P95 확정 아님) |
| 회귀 감시 | lane(0) 292-302s·s1a 150s·evidenceId 99s 기준선 대비 이상 |

## 7. 비용과 부작용 (명시)

- **C3 경로 의존성**: toolchain 스코프가 action 입력이 아닌 `setup-axiom-toolchain/action.yml` 내부에 있으면 수정 → `script_hash` 회전(:232, sha256sum 기반) → A/B-layer 캐시 전체 1회 무효화 = **one-shot fleet cold**(헤더 :51-53 계약). 착지 시 첫 런 exact-hit=false 관측·재시드 확인 필수. 워크플로 측 해결(액션 미호출·입력 경로)이 가능한지 착지 전 확인한다.
- **부수 동승 후보**: .github 래퍼의 낡은 주석 2건(헤더 "ref:main/구 ruleset 24233738" 서술, mint "@d117ae8e2 epoch N+7") — 절차 5의 컨트롤러 핀 회전 PR에 동승 권고(외부 저장소라 본 설계 문서에서는 기록만).
- Tier 2의 per-lane 독립성 약화는 §0.9(극장 금지) 인접 판정 대상 — 승인 시 독립성 상실을 문서로 정당화해야 한다.

## 8. 승인 요청 사항 (판정 지점 — 본 문서 MERGE와 별개)

- **[승인-1] Tier 1(C3·C6·C7) 착지 개시**: 계약 보존, 절감 ~16-24s. script_hash 경로 확인 후 진행.
- **[승인-2] Tier 2(C1-rev lane 분할 개정) 승인 여부**: prereg §1 개정 + per-lane evidenceId 독립성 약화 + G-A 의도 재정의 — 절감 ~99s(Tier 1 합산 시 ~115s). **아키텍트 판정 전제.**
- **[승인-3] Epoch Cutover 개시**: 위 승인 범위 확정 후 §5 절차 실행.

본 문서의 MERGE는 [승인-1/2/3] 중 어느 것도 의미하지 않는다.
