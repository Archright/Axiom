# Admission Chain L3 — 잡 의존성 감사 (job2 병렬 이동 가능성)

**문서 종류**: docs/evidence — 읽기 전용 **진단 감사(탐색적 추정 포함)** — 관측·분석 보고서. 코드·워크플로우·게이트·판정 의미론 변경 0. 본 감사는 판정을 만들지 않는다(Reporter).
**표본 규칙**: `slo_official_measurement_prereg_2026-11-01.md` §5·§7 — **본 표본(=census 진단 코호트 15배치)은 공식 SLO 모집단을 대체하지 않는 진단 표본**이며 기존 관측 데이터(`data/ci_provider/census_20261103T025821Z/`)를 **재사용**한다(신규 수집 0, 배치 선택·제외 0).
**권위**: 잡·스텝 존재·타임스탬프·결론 = GitHub Actions REST API(gh, GET-only) · 잡 그래프 = 원본 워크플로 정의(E-2 재검증, §2) · 병합 판정 권위 = GitHub ruleset·merge queue. 본 문서는 **Reporter다** — 병합 판정 권위를 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3).
**측정 기준**: api-second-granularity(±1s) · wall = `completed_at − started_at` epoch 차 · skipped 판별자 = `conclusion == "skipped"`(0초 실행 아님).

> **명명 주의**: 본 문서의 "L3"는 CI 최적화 로드맵의 레인 3(**잡 의존성 재검토**; L1=J1–J4 계약 확장 설계, L2=WP-B2 판정)이며, `cross_venue_b_reuse_closure_2026-11-02.md` §1의 증거 사다리 "L3(부정 시험 입증)"과 **다른 개념**이다. 인용 시 문맥으로 구분한다.

---

## §0. 요약·판정

전제 질문: admission 체인(med 727s, 15/15 임계경로 — census §4) 내부의 직렬 구간 중 GO 판정과 **실제 데이터 의존 없이** 레인과 병렬로 올릴 수 있는 구간이 있는가.

**판정**:

| 대상 | 판정 | 근거 |
|---|---|---|
| **이동 슬랩** = Core purity gate · Re-derive admission identity · Stage D9 evidence · Register subject (4스텝) | **GO(진단)** — 효과 게이트 PASS | §3: GO-lane 산출물 소비 0(원본 전수 확인) · §6: median Saving 25s [18,38] > 2×SE 3.2s (15/15 배치 개별 상회) · §7: 구현은 별도 사전등록 소관 |
| **witness 이동** (`Attest witness-only` 포함 일체) | **BLOCKED** | 계약상 GO 데이터 종속 — `GO_TESTED_TREE_OID` fail-closed 요구(admission-check.yml:1739-1741), judgment-decision 파일 직접 소비(:1812-1854), 존재 목적 "실패한 lane이 재사용 가능한 PASS record를 mint하지 못하게 함"(:1554-1567). 이동 = 검증 의미론 변경 |
| 3번째 toolchain restore의 동시실행 큐 리스크 · 신규 아티팩트 전송 오버헤드 | **UNKNOWN** | 관측되지 않음(§6.4) — 조용한 추정 대신 UNKNOWN 유지. **정밀화(2026-11-03, l3_followup_evidence §1·§2)**: ① 부분 해소(메커니즘 확정)·② 해소(실측·+2s 타당) — §6.4·§6.5 참조 |

효과 규모 25s는 체인 중앙값 727s의 **~3.4%**로 선례 레버(43–55s, serial-chain DAG)의 절반 이하다 — 비용-편익 평가는 구현 사전등록의 소관으로 정직 기록한다(§7). 원 가설 "~80–100s 절감"은 **기각**됐다(§6.1).

본 감사의 착지는 보고서·데이터까지다. GO 판정이 나더라도 구현은 별도 사전등록(계약 + 부정 시험 + coherent generation 설계 + 신뢰 표면 인간 승인)의 소관이다.

## §1. 조사 설계·모집단

**지위 선언**: 본 감사는 **진단 감사(탐색적 추정)**이다 — 이미 관측한 census 데이터로 가설을 세우고 같은 데이터로 효과를 계산했다. 관측 후 규약을 고정하면 탐색적 선택이 확증적 주장으로 위장된다(§0.9 극장 — `e3_measurement_contract_2026-10-11.md:13`). 따라서 본 보고서의 효과 수치는 **진단 추정이지 확증적 주장이 아니다**.

- **모집단**: census 15배치(#1214–#1228, 2026-11-02T08:08Z~2026-11-03T02:58Z 자연 발생 merge_group, 각 배치 = 별도 merge_group, 전부 run_attempt=1). 신규 표본 0, 제외 0, 임의 재실행 0.
- **동결 효과 게이트(단일 공식 — 본 감사가 판정에 쓴 문자 그대로)**:

  > `GO_effect ⟺ median(Saving_i) > 2×SE(median)`, `SE(median) = 1.253·σ̂_S/√15`, `σ̂_S = Saving_i의 표본 SD(n−1)`. 각 배치 `Saving_i = wall_i − Residual_i`를 **먼저** 계산한 뒤 집계(클래스 중앙값끼리의 뺄셈 금지 — paired 상관 보존, `slo_official_measurement_prereg:32`).

  **사전 관측 공개 의무 이행**: 15배치 Saving_i 값이 이 게이트 문자 동결에 **선행**해서 산출됐음을 공개한다(`slo_official_measurement_prereg:9`). 동결은 판정 직전 1회, 사후 조정 0.
  **30s 고정 문턱 폐기**: `serial_chain_dag_prereg_2026-10-17.md:77`의 30s는 n=8 관측(range 77s → d₂=2.847 → σ̂≈27s → 판정 표본 n=5의 중앙값 SE≈15.1s)의 **2×SE 유도값**이지 이식 상수가 아니다. 코퍼스 전수(R-1)에서 유일한 절대 하한은 1s API 분해능뿐이며, census:114도 관측 노이즈 수치의 이식성을 명시 부정한다. n=15에는 위 단일 공식만 쓴다.
- **관측 한계**: ±1s 분해능 · job wall은 대기·러너 할당 포함 · `Residual_i`·`job2aWall_i`의 `+2s`는 신규 잡 오버헤드 수당의 **보수 고정값(사양, 측정 아님)** · job2aWall은 스텝 소요의 직렬 합산 추정(스텝 간 갭 미반영) · 통계 확증 어휘(p값·CI·CI 하한) 미사용(진단 계층 규율).
- **반사실 모델**: job2를 (job2a = MOVED 4스텝 + 공통 setup 11스텝 재지불) ∥ (job2b = 잔여 18 실행 스텝)로 분할했을 때 job2b 직렬 경로 감소분. witness·lane judgment 소비 스텝은 잔여 잡에 그대로 남는다(§3·§6.1).

## §2. 잡 그래프 — 원본 확정

E-2 재검증(2026-11-03, gh api GET-only): caller 원본 blob `0ef1a441bf0a01568beebab196cafb01ce3c359e`(50,775B, Archright/.github@main)가 census 사본과 **byte-identical** → 아래 DAG는 원본 기준. Archright/Axiom 호출 5개의 pin은 전부 `498c55704552291da926fae6eb34bc5c0c04ec1b`(구 pin 76aa3edb 아님)이고, callee `admission-check.yml@498c5570` blob `f0bb8fb5…`는 working tree `git hash-object`와 일치(프로덕션 정본 분석 확정). 부수 관찰: 원본 헤더 주석은 `@d117ae8e2`(조상 커밋)로 회전을 기술하는 **주석 drift**(기능 pin은 전부 498c5570 수렴, 무영향 — 기록으로 남긴다).

**caller(admission-gate-v2.yml) — 8잡**:

```
anchor-resolve (PR 전용) ─┬→ closure-deriver ─┬→ gateway (runner-pool-acceptance)
                          │                   └→ verdict (needs mint-prepare·deriver·anchor)
                          ├→ attest (stage=attest) ─→ mint-prepare (needs attest) ─┬→ mint-publish (needs prepare·gateway)
                          │                                                        └→ verdict
                          └────────────── 전 7잡 ──→ admission-check (aggregate, if: always())
```

**callee(admission-check.yml, stage=attest) — 4잡**:

| 잡 | 라인 | needs | 역할 |
|---|---|---|---|
| build-base-artifacts (job1) | :200 | (DAG head) | B-tree 산출물·bin/ax materialize |
| go-critical-lane (matrix 0/1) | :2890 | `[build-base-artifacts]` | GO 판정 실행 |
| go-critical-rollup | :3684 | `[go-critical-lane]` | lane 결과 fail-closed 집계(→ callee 결론 → 필수 check) |
| **admission-check (job2)** | :669 | **`[build-base-artifacts, go-critical-lane]`** (:676) | witness·judgment·admission records |

**잡 그래프 정정(census §4 대비)**: `go-critical-rollup`은 job2의 **needs가 아니다** — lane 이후의 **병렬 형제**다(rollup :3685의 needs는 lane뿐). census가 rollup(3s)→job2(110s)를 직렬로 표기한 것은 관측 순서일 뿐 DAG 간선이 아니다(§5 gap 관측과 정합 — rollup→job2 gap이 9배치에서 음수). job2 잡 시작의 실질 장벽은 `:670-675` 주석이 명시하는 **needs 소비 간선**("must start only after the lanes have published them")이며, 잡 레벨 `if: always()`(:702)는 lane 스킵 시 잡 생존 장치지 순서 완화가 아니다. lane artifact는 run-scoped 이름(`go-judgment-lane-{i}-<head>-<attempt>`, :3629-3649, lane 실패 시에도 `always()` 업로드)이므로 needs 없이는 존재하지 않고 다운로드가 fail-closed로 죽는다.

callee 4잡의 `outputs:`는 **전부 0개** — 잡 내 `$GITHUB_ENV`·워크스페이스 파일 체인은 러너를 넘지 못한다(§7 구현 전제).

## §3. job2 스텝 의존성 — 원본 라인 전수 대조

35스텝(실행 22 + 조건부 skipped 13, 배치 간 스텝 집합 완전 동질 — jq 검증 편차 0). 인용은 callee 원본 file:line(스텝 번호는 생략 — API 번호와 파일 순서가 Setup/Post/Complete 삽입으로 어긋난다).

**실행 22스텝 — 측정 사실 | 원인 판정 분리**:

| 스텝 (원본 라인) | 소비 입력 | GO-lane 산출물 소비 | 분류 | 실측 med |
|---|---|---|---|---|
| Set up job · Complete job · Post×2 (runner) | — | ✗ | 공통 | 합 ~1s |
| [venue] 결정 (:715-732) | `github.event_name` | ✗ | 공통 | 0s |
| Checkout B (:737-743) | baseSha·이벤트 | ✗ | 공통 | 4s |
| [slice-engine] scope (:802-856) | B epoch_manifest | ✗ | 공통 | 0s |
| **setup-axiom-toolchain (:872-877)** | B 소스 | ✗ | 공통 | **49s [43,76]** |
| Checkout H (:886-899) | head sha | ✗ | 공통 | 3s |
| Download base-built (:901-912) | job1 artifact | ✗ (job1 의존) | 공통 | 0–1s |
| Verify artifact manifest (:919-978) | job1 매니페스트 | ✗ | 공통 | 0–1s |
| **Core purity gate (:994-1011)** | B make + H tree | ✗ | **MOVED** | 4s |
| Download lane-0 judgment (:1055-1060) | lane-0 artifact | **✓** | GO의존(잔여) | 1s |
| Download lane-1 judgment (:1061-1066) | lane-1 artifact | **✓** | GO의존(잔여) | 1s |
| **Re-derive admission identity (:1094-1353)** | PR API·git·`_candidate` | ✗ | **MOVED** | **18s [16,22]** |
| Stage D9 evidence (:1399-1499) | B draft·vault manifest·policy | ✗ | **MOVED** | 0–1s |
| Register subject (:1507-1551) | bin/ax·D9 산출·identity env | ✗ | **MOVED** | 0–1s |
| GO execution cross-check (:1569-1675) | lane exec-records·decision 파일 | **✓** | GO의존(잔여) | 1s |
| **Attest witness-only (:1686-1859)** | `GO_TESTED_TREE_OID`(←17행 스텝) + `judgment-decision*.json`(←lane artifact) + SUBJECT_ID·evidence | **✓✓ (이중)** | **GO의존 — 이동 금지** | 8s [5,10] |
| Upload evidence record (:1861-1882) | witness 산출 | 간접 | GO의존(잔여) | 0–1s |
| Upload judgment record (:1884-1910) | witness 산출 | 간접 | GO의존(잔여) | 1s |
| Upload admission records (:2772-2805) | witness.json/.sha256 | 간접 | GO의존(잔여) | 1s |

**조건부 skipped 13스텝**: verdict-stage 전용(derived-closure load :1941-1953 · subject-certificate fetch :1972-1998 · preflight 3 · admission predicate :2257-2736 · fail-closed guard·verdict log·leg 스텝)과 preflight 전용(attest contrast :1369-1387 · pinned jq :763-777 · libpcre3 :779-801) — attest venue에서 조건식에 의한 상시 스킵(임의 제외 아님). skipped 스텝의 started≠completed 0건.

**의존성 판정 요지**:
- **witness는 GO 독립이 아니다**(가설 전제 기각): (i) `GO_TESTED_TREE_OID`를 GO cross-check의 `$GITHUB_ENV` 산출로 **fail-closed 강제 요구**(:1739-1741 — "the execution-accounting cross-check must run first"); (ii) lane 다운로드가 떨어뜨린 `judgment-decision*.json`을 직접 소비해 subject-set 동등성(:1812-1825)·merge_group basis 정책(:1834-1851) 검사; (iii) `AXIOM_JUDGMENT_CAS` arm 시 decision 파일 기준 ledger 재검증 분기(:1722-1755).
- **MOVED 4스텝은 GO-lane 산출물을 소비하지 않는다**: identity·D9·register 본문이 judgment/decision 파일을 읽는 코드 0건(grep 확증). 소비 입력 = job1 산출물·체크아웃·이벤트 페이로드·B draft·vault manifest.
- **잡 내 전방 상태 체인**: identity → D9 → register → witness가 `$GITHUB_ENV`(B/H/tree OID·SUBJECT_HEAD·SUBJECT_ID)와 워크스페이스 파일(`draft-assembled.json`·`evidence/<sid>.json`·`bin/ax`)로 연결 — 잡 분할 시 이 채널의 artifact화 + 소비측 fail-closed 재검증이 필수(§7).

## §4. 계약 조항 인벤토리 (L3가 터치하는 조항)

| 문서·조항 | 요지 | 본 감사 판정 |
|---|---|---|
| admission-check.yml :1048 | lane→job2 순서 = **needs 엣지 전용, polling 금지** | 분할을 needs 엣지로 수행 시 미위반; polling 대기 병렬화는 위반 |
| admission-check.yml :1739-1741 · :1554-1567 · :1055-1066 | witness의 GO 데이터 종속·다운로드 fail-closed·"실패한 lane이 PASS record mint 금지" | **witness 이동 = 데이터 인과 위반 → BLOCKED** |
| admission-check.yml :118-130 · :1861-1910 | artifact identity 계약(`admission-check-<H>-<attempt>` 등) | 분할 시 유지 필수 |
| ADR-0032 (e) :59-62 | 5-leg DAG·집계 불변, leg 생략·job skip 금지, **MG 스텝·아티팩트 이름 바이트 수준 불변** | 잡 추가·스텝 이동 = **명시 판정 대상**(구현 사전등록에서 준수 또는 ADR 개정 확정) |
| ADR-0032 (d) :51-57 | callee blob 변경 = **A2 원자 페어**(TWS + epoch manifest productionExecutionPin, 동일 커밋) | 구현 시 필수 절차 |
| ADR-0025 §8(a) :227-233 | 순서 보장 = needs DAG, polling/sleep 금지 | :1048과 동일 판정 |
| ADR-0025 §11 :287-295 · Amendment F :884-931 | identity 3계층·후보 트리 동등성 = 게이트 요소; 코드 동반 변경 시 A2 원자 페어 회전(:940-945) | 게이트 판정 체인 유지 전제 |
| ADR-0022 :494-496 · :537-539 | verdict → publication → native MERGE 순서; witness는 비권한 tier(publisher의 검증 입력) | L3는 verdict 이전 구간만 — 미위반; witness 계급 불변 유지 |
| certificate-mint.yml :1694-1885 (P4) · :1900-1979 (P5) | mint-publish의 witness 재다운로드·sha256 대조·3중 등가 | witness artifact 최종산출 정의 불변 전제 |
| admission-generation.md §4.1-4.3 | callee 변경 → 컨트롤러 핀 회전 → **양 ruleset(25218071·23943917) 재핀 + readback(HARD RULE)**; trustSurface 자기참조 잠금 → **ROT_ALLOWLIST 사전등록** 경로 | 구현 시 필수 절차 |
| ci_epoch_cutover.md :29-39 | **topology·parallelism 변경 = CI 변경** → Epoch Cutover 전 절차(freeze→record→tombstone→new epoch→atomic binding→검증→cutover→production acceptance); in-place 패치 위반 | L3는 명문의 적용 대상 |
| authority_invariant_protocol.md §4 :32-38 | **편의적 직렬화 금지** — 새 dependency edge는 필요성 설명 가능해야 함 | MOVED 슬랩 병렬화의 정당성 근거(데이터 의존 0 입증 전제) |
| verification_dag_contract.md :29 | evidence DAG ≠ job 토폴로지(substrate의 편의 사상) | 잡 재배치가 증거 의미를 자동으로 바꾸지 않는다는 논거(지지 조항) |
| census §7-③ | GO 실행 = 검증 의미론; 재사용 확장은 J1–J4 선행 | 본 감사는 재사용 확장이 아님(잡 배치만) |

선례 계보: `node24_merge_group_job_decomposition_2026-10-12.md` §4.2 — "GO 스텝 전부 제거해도 잡은 ~110s 아래로 안 내려간다"(본 감사 job2 wall med 110s와 일치하는 바닥치) · `serial_chain_dag_prereg_2026-10-17.md` §5 — 효과 게이트 형식(중앙값 > 2×SE, 관측 전 고정)과 후보 E 기각(bounded-poll = no-poll 계약 위반) — witness 이동 금지의 직접 선례 · `serial_chain_candidate_a_s3_adjudication_2026-10-17.md:33` — 승격 실측 판정 선례 · `ci_cost_waste_ledger_2026-11-03.md` R02행 — admission-gate-v2는 required_check로 **제거 불가, 실행 시간 최적화만 가능**(본 감사가 정확히 그 조사 경로).

## §5. 실측 정량 (측정 사실 | 해석 분리)

**클래스 합계 중앙값** (a=identity/D9/witness 추정군 · b=GO judgment 소비 · c=verdict upload · d=setup/기타):

| | a | b | c | d | wall | wall−Σsteps |
|---|---|---|---|---|---|---|
| 중앙값 | **27** | **4** | **1** | **66** | **110** | 3 |

- job2 wall의 실질 구성 = **toolchain 49s + identity 18s + witness 8s**(중앙값 기준 ~68%). GO 의존 스텝(b+c)은 **5s**에 불과하다 — **job2의 110s는 GO 판정 대기가 아니라 자체 setup·witness 비용이다.**
- **toolchain 이중 모드**: 43–50s 군집 9배치(med 45) vs 69–76s 군집 6배치(#1216·#1217·#1219·#1220·#1221·#1223, med 75), 50↔69 사이 값 없음 — 이 6배치가 job2 wall 최상위 6개(118–136s)로 대응. **job2 wall 분산의 주성분 = toolchain 모드(추정: 캐시 on/off 상태 차)**. **정밀화(2026-11-03, l3_followup_evidence §3)**: 캐시 on/off 가설 **기각** — 잡 로그 15배치 전수에서 A-cache 히트 15/15·키·아카이브 전배치 동일(~1161MB); 이중 모드의 실제 위치는 actions/cache extract(tar -xf) 단계(warm 22.4s med vs cold 50.2s med, 26s 공극)의 **러너 VM 수준 변동** — 물리 하위 원인은 UNKNOWN 유지.
- **핸드오프 gap**: lane 최종 종료 → job2 시작 med **3s** [3,14] — 잡 스케줄링 마찰은 무시할 수준. rollup→job2 gap이 9배치에서 음수(−15~−3s)는 병렬 형제 관계 + 문서화된 서브초 타임스탬프 역전 quirk(census §10)의 재확인.
- **REUSED 4배치**(#1214·#1218·#1221·#1226 — GO tests 0s, 판정 CAS 재사용 경로)도 본 감사에 포함: 재사용 배치에서도 job2 구조는 동질(스텝 집합 편차 0).
- lane wall: L0 med 377 [189,484] · L1 med 321 — job2a(이동 잡) 예상 wall med 87 [77,120]은 최소 minLane 156s(#1218)마저도 넘지 않는다(**완전 은폐 15/15**, §6.2).

## §6. 반사실·효과 게이트·판정

### 6.1 배치별 반사실 (n=15, 단위: 초 — paired 선행 계산)

반사실: MOVED 4스텝(identity·purity·D9·register)을 lane 병렬 잡(job2a)으로 분할, 잔여 잡(job2b)이 공통 setup을 재지불(공통 11스텝 = Set up job·venue·Checkout B·slice-engine·toolchain·Checkout H·base 다운로드·manifest 검증·Post×2·Complete). witness·GO 소비 스텝은 잔여에 유지.

| PR | wall | movedSum | residSum | slack | Residual | **Saving** | job2aWall | minLane | toolchain |
|---|---|---|---|---|---|---|---|---|---|
| 1214 | 91 | 22 | 67 | 2 | 69 | **22** | 78 | 188 | 43 |
| 1215 | 98 | 22 | 74 | 2 | 76 | **22** | 86 | 299 | 50 |
| 1216 | 136 | 20 | 103 | 13 | 105 | **31** | 112 | 321 | 75 |
| 1217 | 119 | 23 | 93 | 3 | 95 | **24** | 107 | 336 | 69 |
| 1218 | 105 | 24 | 77 | 4 | 79 | **26** | 85 | 156 | 45 |
| 1219 | 130 | 24 | 103 | 3 | 105 | **25** | 115 | 335 | 75 |
| 1220 | 118 | 18 | 98 | 2 | 100 | **18** | 107 | 239 | 70 |
| 1221 | 127 | 21 | 103 | 3 | 105 | **22** | 112 | 171 | 76 |
| 1222 | 105 | 22 | 78 | 5 | 80 | **25** | 85 | 336 | 49 |
| 1223 | 136 | 27 | 104 | 5 | 106 | **30** | 120 | 333 | 75 |
| 1224 | 109 | 27 | 77 | 5 | 79 | **30** | 89 | 340 | 46 |
| 1225 | 110 | 24 | 70 | 16 | 72 | **38** | 82 | 260 | 45 |
| 1226 | 113 | 23 | 81 | 9 | 83 | **30** | 87 | 190 | 46 |
| 1227 | 93 | 23 | 67 | 3 | 69 | **24** | 79 | 314 | 45 |
| 1228 | 91 | 23 | 65 | 3 | 67 | **24** | 77 | 280 | 43 |

`Residual_i = residSum_i + 2` · `Saving_i = wall_i − Residual_i`(모델 상수·가정은 §1·`manifest.json` 참조 — 측정 아님).

### 6.2 검증 (전부 통과)

- **Saving 이중 경로 일치 15/15**(`wall−(residSum+2)` == `movedSum+slack−2`, 배치별 독립 재계산).
- **클래스 합계 교차검증 15/15**(배치별 clsTotal == movedSum+residSum) — 사양 외 미분류 실행 스텝 0(실행 22스텝 전수가 MOVED/RESIDUAL에 대응).
- **job2a 완전 은폐 15/15**(job2aWall ≤ minLane; max 120s < min minLane 156s). 레인 wall이 대기 포함이므로 은폐 판정은 보수적 방향으로 작동.
- 이상 0(음수 slack 0 · 결측 타임스탬프 0 · success/skipped 외 conclusion 0 · 스텝 집합 동질 편차 0).

### 6.3 효과 게이트 (동결 단일 공식 적용 — 진단 추정치, n=15 진단 코호트 한정)

| 통계량 | 값 |
|---|---|
| median(Saving) | **25s** [18, 38] |
| σ̂_S (표본 SD, n−1) | 4.9493 |
| SE(median) = 1.253·σ̂_S/√15 | 1.6012 |
| 게이트 2×SE | **3.202s** |
| 판정 | **25 > 3.202 → PASS** (15/15 배치 개별 상회) |
| wall 변형(참고 — unpaired) | med 110, SD 15.4387, 게이트 9.990s — paired 형식이 정합(`slo_official_measurement_prereg:32`) |
| 30s 대비 | paired 게이트는 30s의 ~1/9.4 — 30s가 n=8 코호트 특정 유도값이었음을 확증 |

**효과-규모 기록(진단 수치 — 게이트와 별개)**: 25s는 admission 체인 중애값 727s의 ~3.4%, census wall 727s에서 job2가 임계경로 말단(뒤에 mint-prepare·verdict·aggregate가 직렬로 이어짐)이므로 **직렬 경로 감소는 병합 wall에 가산될 것으로 추정되나 본 코호트로는 일반화하지 않는다**. 원 가설 80–100s는 이중 계산 오류(잔여 잡의 setup 재지불·witness GO 종속 미반영)로 기각됐다.

### 6.4 UNKNOWN 항목 (추측 금지 — 관측 근거 없음)

1. **동시실행 큐 리스크**: 신규 병렬 잡 job2a의 setup-axiom-toolchain(3번째 toolchain restore)은 계산 비용 증가뿐 아니라, GitHub Actions 동시실행 한도 도달 시 신규 잡이 큐에 진입해 lane이나 다른 잡을 지연시킬 수 있다(공식 문서 확인). 본 코호트의 레인 wall은 대기 포함이므로 은폐 판정(15/15)은 이 리스크를 반증하지 않는다. **정밀화(2026-11-03, l3_followup_evidence §1)**: **부분 해소** — 메커니즘은 공식 문서로 확정(한도 도달 시 큐잉·실패 아님, 큐는 run 스코프 아님 → wall 지연 성격). 정량 변수(플랜 티어·가동률·큐 길이)는 API 미노출로 잔존 — 구현 사전등록 시 측정 4항 관측 필요.
2. **신규 아티팩트 전송 오버헤드**: MOVED 잡 산출물(identity env·D9 evidence·SUBJECT_ID)의 artifact 업로드/다운로드 비용은 미측정(모델의 +2s 수당으로만 충당). **정밀화(2026-11-03, l3_followup_evidence §2)**: **해소** — 475레코드 실측(소형 부류 1s/홉·업로드+다운로드 체인 med 2s). +2s 수당은 중앙값 등가로 타당(과소 아님; tail 최악 +4s, 대형 payload 경계 조건 명시 필요).
3. **코호트 외 일반화**: 개별 배치 병목이 전체 운영에서 반복된다는 일반화는 하지 않는다.

### 6.5 최종 판정

- **GO(이동 슬랩 — 진단)**: identity·D9·register·purity 4스텝 병렬 이동. 효과 게이트 PASS, 데이터 의존 0(§3), 은폐 15/15(§6.2). **구현은 별도 사전등록의 소관** — 본 판정은 "구현 승인"이 아니라 "구현 사전등록을 열 자격"이다.
- **BLOCKED(witness 이동)**: 계약 조항(:1739-1741·:1554-1567·:1812-1854)과 no-poll 계약(ADR-0025 §8(a)·후보 E 기각 선례)이 이동을 금지. witness는 GO 의존 잡에 잔존해야 하며, mint 시작은 GO 의존 잡 종료까지 불변(caller :464-471 소비 계약).
- **UNKNOWN**: §6.4의 3항목 — 추가 증거 없이 최적화하지 않는다. **정밀화(2026-11-03, l3_followup_evidence §1·§2)**: 항목 1은 부분 해소(메커니즘 확정·한도 실측 변수 잔존), 항목 2는 해소(실측·수당 타당 확정), 항목 3(코호트 외 일반화)은 UNKNOWN 유지.

## §7. 구현 전제 인벤토리 (GO가 구현 사전등록으로 넘어갈 경우의 의무 전체)

**절차·신뢰 전제 6종**:
1. **no-peeking**: 구현 판정 게이트는 착지 이전 고정·사후 조정 금지·변경은 새 날짜의 사전등록 문서로만(`serial_chain_dag_prereg:4,:125`).
2. **신규 관측**: 확증 집합은 고정 이후 런으로만 구성 — 기존 census 데이터 재사용 금지, 본 감사의 25s는 진단 추정으로만 참조(`e3_measurement_contract:164`).
3. **부정 시험**: 위조·변조·출처 불명 입력의 거부 실증 — 현재 **없음**으로 명시(cross_venue L3 사다리 — 본 감사의 L3 레인과 다른 개념, 명명 주의 참조). AGENTS.md §0.9b Triple-Closure가 원천.
4. **J1–J4 전부 PASS**(`docs/spec/ci_optimization_tcb_judgments.md:17-20`) — 단 "J1–J4 완전 증명"이라 쓰지 않는다: 정확한 표현은 "현재 publisher 경로의 불변식과 관측 근거를 명문화했다"(cross_venue :46-47·:90 규율).
5. **coherent generation 설계**: Epoch Cutover 전 절차(freeze→record→tombstone→new epoch→atomic binding update→검증→canonical cutover→production acceptance) — in-place 패치·혼합 세대 금지(AGENTS.md §2.5, `ci_epoch_cutover:29-77`).
6. **신뢰 표면(인간 아키텍트) 승인**: required check·실행 의미론 변경에 대한 명시적 인간 승인(AGENTS.md §2.5/§2.6, admission-generation §4.2).

**구조 전제(잡 분할의 기술 조건)**:
- callee `outputs:` 신설(현재 0개 — identity env·SUBJECT_ID의 잡 간 전달 채널 부재) + 중간 산출물 artifact화 + 소비측 **fail-closed 재검증**(artifact identity 계약 :118-130 준수).
- ADR-0032 (e) "5-leg DAG·집계 불변 / MG 스텝·아티팩트 이름 바이트 수준 불변"에 대한 **명시 판정**(준수 설계 또는 ADR 정식 개정 — authority_invariant_protocol :99-105 B 경로).
- A2 원자 페어 회전(callee blob 변경 = TWS + epoch manifest productionExecutionPin 동일 커밋) + ROT_ALLOWLIST 사전등록 + 컨트롤러(Archright/.github) 핀 회전 PR + **양 ruleset(25218071·23943917) 재핀 readback** + production acceptance(admission-generation §4.1-4.3).
- mint 계약 불변 확인: mint-prepare 소비 입력(`admission-check-base-artifacts` + witness artifact)과 needs:[attest] 구조 유지.
- **비용-편익 재판정**: 효과 25s(~3.4%) vs 절차 비용(위 전체) — 30s가 선행 세대의 2×SE였다는 사실이 효과가 작다는 것을 의미하지는 않으나, 선례 레버(43–55s)의 절반이라는 규모 비교는 사전등록에서 명시 판정해야 한다.

## §8. 재현 명령 (읽기 전용 · jq-1.7 · gh api GET-only)

정본 데이터: `data/ci_provider/census_20261103T025821Z/batch_*.jsonl`(15배치). 파생 데이터: `data/ci_provider/l3_dependency_audit_20261103T083621Z/`(batch_per_step·aggregate·manifest).

**[1] 배치별 반사실·집계·검증 전체 (aggregate.json의 산출 필터 전문)**:

```jq
def median: sort | if (length % 2) == 1 then .[(length-1)/2] else (.[length/2-1] + .[length/2])/2 end;
def sd: ((add/length) as $m | map((. - $m) * (. - $m)) | (add/(length-1)) | sqrt);
def dur: ((.completed_at|fromdateiso8601) - (.started_at|fromdateiso8601));
def isMoved: .name | test("Core purity gate|Re-derive admission identity|Stage D9 evidence|Register subject");
[ inputs | select(.type=="job") ] as $jobs
| ([ $jobs[] | select(.job_name | test("^attest / go-critical-lane \\([01]\\)$"))
     | {key: ((.pr|tostring) + (if (.job_name | endswith("(0)")) then "-0" else "-1" end)),
        value: ((.completed_at|fromdateiso8601) - (.started_at|fromdateiso8601))} ] | from_entries) as $L
| [ $jobs[] | select(.job_name == "attest / admission-check") | . as $j
    | ($j.started_at|fromdateiso8601) as $t0 | ($j.completed_at|fromdateiso8601) as $t1
    | ($t1 - $t0) as $wall | ($j.steps) as $st
    | ($st | map(select(.conclusion == "success"))) as $ex
    | ($ex | map(select(isMoved))) as $mv
    | ($mv | map(dur) | add) as $movedSum
    | ($ex | map(select((isMoved) | not))) as $rs
    | ($rs | map(dur) | add) as $residSum
    | ($wall - $movedSum - $residSum) as $slack
    | ($residSum + 2) as $residual | ($wall - $residual) as $svA
    | ($movedSum + $slack - 2) as $svB
    | ($rs | map(select(.name | test("Set up job|^\\[venue\\]|Checkout executor tree = B|slice-engine|setup-axiom-toolchain|Checkout candidate = H|Download base-built artifacts|Verify artifact manifest|^Complete job$")))
      | (map(dur) | add)) as $commonSum
    | ($movedSum + $commonSum + 2) as $j2a
    | ($rs | map(select(.name | test("setup-axiom-toolchain")) | dur) | .[0]) as $tc
    | {pr: $j.pr, wall: $wall, movedSum: $movedSum, residSum: $residSum, slack: $slack,
       residual: $residual, savingA: $svA, savingB: $svB, svMatch: ($svA == $svB),
       job2aWall: $j2a, minLane: ([$L[(($j.pr|tostring)+"-0")], $L[(($j.pr|tostring)+"-1")]] | min),
       toolchain: $tc} | sort_by(.pr) ] as $rows
| ($rows | map(.savingA)) as $sv
| {n: ($rows|length), saving: {median: ($sv|median), min: ($sv|min), max: ($sv|max),
    sd: ($sv|sd), seMedian: (1.253*($sv|sd)/($sv|length|sqrt)),
    gate2xSE: (2*(1.253*($sv|sd)/($sv|length|sqrt)))},
   svMatchAll: ($rows | map(.svMatch) | all)}
```

실행: `cd data/ci_provider/census_20261103T025821Z && jq -r '<위 필터>' batch_*.jsonl`. 공통 스텝 패턴은 `Checkout executor tree = B`·`Checkout candidate = H`가 본체+Post를 함께 매칭(총 11스텝, 배치별 nCommon=11 확인). 재현 주의: `group_by` 람다 내 job 필드 전파는 `. as $j` 캡처 필요(스코프 버그) · `test()`에서 괄호는 이스케이프 필요(`endswith` 권장).

**[2] 스텝 집합 동질성·분류 검증** (fjn §8 [4]와 동일 형식 — cls 함수 전문은 `batch_per_step.json` columns 주석과 E-1 원문 참조): 배치별 스텝 {num, name, cls, conclusion} → group_by(.num) → 이름/분류 편차·실행/스킵 균질성 검사 → 출력은 상시-skipped 13스텝의 스킵 카운트뿐(편차 0).

**[3] caller 원본·pin 재검증**:

```bash
gh api repos/Archright/.github/contents/.github/workflows/admission-gate-v2.yml --jq '{sha, size}'
gh api repos/Archright/.github/contents/.github/workflows/admission-gate-v2.yml --jq '.content' | tr -d '\n' | base64 -d | git hash-object --stdin
# blob 0ef1a441bf0a01568beebab196cafb01ce3c359e / 50,775B — tmp/census_20261103/workflow_defs 사본과 diff 공집합
git rev-parse 498c55704552291da926fae6eb34bc5c0c04ec1b:.github/workflows/admission-check.yml  # f0bb8fb5…
git hash-object .github/workflows/admission-check.yml  # f0bb8fb5… 일치
```

**[4] 배치 경계·필수 체크 원본**: census §9 재현 명령(`gh api repos/Archright/Axiom/rulesets/20303214 …` · org rulesets 25218071·23943917 readback)을 그대로 따른다.

## §9. 후속 기록

- **L1(차기 — J1–J4 계약 확장 설계)**: 기존 레인 내부 재사용 계약과 레인 간/신규 재사용의 권한·입력 동일성·실패 의미론을 구분 설계. 본 감사와 독립.
- **L2(차기 — WP-B2 판정)**: A-restore 축소 가능성(12–15s) 판정 — 기존 BLOCKED 선례(arestore) 재검토. 본 감사와 독립.
- **본 감사가 하지 않는 것**: 검증 스텝 제거·required check 변경·캐시 재사용 범위 확대·Workflow 수정·Ruleset 변경·인위적 CI 실행·GO witness 의미론 변경 — 전부 §7 사전등록의 소관이며, 본 감사 착지는 보고서·데이터 착지로 끝난다.
- **SLO 유지**: 본 감사는 #1166 공식 SLO 판정을 산출·선점하지 않는다. 공식 판정은 #1166 동결 계약의 모집단·판정창에서만 수행된다.

---

**데이터**: `data/ci_provider/l3_dependency_audit_20261103T083621Z/` (batch_per_step.json · aggregate.json · manifest.json — 전 수치의 원본 경로·모델 상수·재현 필터 포함).
**계보**: Node24 Merge-Queue Critical-Path Census(2026-11-03) → Dual-Lane Assurance Audit(2026-11-03) → **본 감사**(L3 잡 의존성) — 질문 계승: "병합을 늦추는 필수 경로에서, 검증 의무를 보존하며 없앨 수 있는 대기·재계산은 무엇인가".
