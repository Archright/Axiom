# tests/ci 보증 범위 전수 분류 — 2026-10-30 (VS-B)

- **스냅샷**: `ci-epoch-pre-vs-b-2026-10-30` == `474392b11` (origin/main, Merge PR #1126). 워크트리 `<user-home>/axwt/vsb`에서 판독.
- **방법론**: tests/ci 소스 15개를 파일별로 전수 판독(총 4,735행). 실행 위치는 `.github/workflows/*.yml`·`Makefile`·`ci/checker.mk`·`config/*.nims` 전수 grep으로 file:line 실증. 환경 의존은 각 소스의 import 문과 subprocess 호출(`execCmdEx`/`startProcess`)을 소스 라인 단위로 실증. 무분류 0개.
- **정본 참조**: [docs/agents/ci_epoch_cutover.md] (AGENTS.md §2.5 절차), [docs/spec/diagnostic_execution_delegation.md §7] (required 승격 = 인간 액션), [docs/spec/repository_surface_contract.md] (.github/** FROZEN trust 계약).
- **착지 범위**: 본 PR은 **분류 문서(=본 문서)만 착지시킨다**. 신규 진단 워크플로(`tests-ci-unit-diagnostic.yml`)는 구성·로컬 검증까지 완료됐으나 push-admissibility 정적 게이트(FROZEN ADD=FAIL)가 착지를 차단한다 — §4에 절차 종결 상태와 필요한 권한을 기록했다(§-1·AGENTS.md §2 준수: 게이트 우회·감사 추적 없는 통과 금지). 구성 완료된 epoch YAML은 부록 A로 보존한다.

---

## 0. 종전 수치 정정 — "21개 중 1개 CI 실행"은 소스·바이너리 혼합 오계산

| 항목 | 종전 주장 | 본 관측(2026-10-30, 474392b11) |
|---|---|---|
| tests/ci 실제 소스 | "21개" | **15개** (14 nim + 1 py, `ls tests/ci` 실측) |
| CI 직접 실행 | "1개" | **2개** (test_debt_schema_theater_rule.py — debt-registry-gate.yml:36, test_landing_observe_acceptance.nim — axiom-operational-slice.yml:158-159) |

정정 근거:
- 직전 세대 freeze 태그 `ci-epoch-pre-publisher-job-if-2026-10-25`의 `git ls-tree --name-only <tag>:tests/ci | grep -c test_` = **13** — "구세대 13 소스" 성분 확인.
- 메인 클론 `bin/`에는 nim 유니크네임(hash-suffix) 테스트 바이너리가 `make test-unit` 반복 실행의 잔여물로 존재 — 총 `test_*` 77개, 그중 tests/ci 소스 이름과 일치하는 것은 **6개** (test_admission_check_stages_\*×1, test_derive_checker_closure_\*×2, test_rotation_pin_anchor_check_\*×2, test_verify_b_artifact_\*×1). 종전 "21"은 이 잔여 바이너리(소스가 아님)를 소스로 계수한 혼합이었다.
- `Makefile:63-97`의 `TESTS_FAST_UNIT`(test-fast 병렬 유닛 목록)에는 tests/ci 파일이 0개 — tests/unit·tests/·tests/verification만 포함.

---

## 1. 배선 실증 요약

**CI 직접 실행 — 2개 (둘 다 required check 잡 안에서 실행)**

| 소스 | 배선 | 실행 증거 |
|---|---|---|
| test_debt_schema_theater_rule.py | `.github/workflows/debt-registry-gate.yml:36` | `run: python3 tests/ci/test_debt_schema_theater_rule.py`; 트리거 pull_request(:4)·merge_group(:5-8) |
| test_landing_observe_acceptance.nim | `.github/workflows/axiom-operational-slice.yml:158-159` | `nim c … -o:build/landing_observe_contract tests/ci/test_landing_observe_acceptance.nim` 후 `./build/landing_observe_contract` **컴파일+실행**; 트리거 pull_request(:15)·merge_group(:16)·push main(:17-19)·workflow_dispatch |

**make 배선 로컬 커버 — 10개 (CI 실행 0)**

- `Makefile:1070` `test-unit` 타깃, tests/ci 멤버 9개: Makefile:1080-1088 — test_derive_checker_closure(1080), test_reanchor_pin(1081), test_verify_b_artifact(1082), test_b_cache_anchor(1083), test_admission_check_stages(1084), test_admission_venue_split(1085), test_s5_build_skip(1086), test_sl02_consumer_binding(1087), test_landing_observe_acceptance(1088).
- `Makefile:1096-1097` `test-oracle-evidence` 타깃: test_oracle_evidence_regression.nim.
- **로컬 전용의 결정적 실증**: `.github/workflows/` 전수 grep에서 `make test-unit`·`make test-oracle-evidence` 실행 워크플로 0건. axiom-operational-slice.yml:147-149가 자체 주석으로 동일 사실을 진술한다 — "The same file is listed in `make test-unit`, which no CI target runs — a check no CI target executes is a declaration, not a check (AGENTS.md §0.9)". landing_observe_acceptance가 이 주석의 계기로 slice에 단독 배선된 사례가 본 분류의 직접 선례다.

**무배선 — 4개**

- test_observer_fixture_adr_lint.nim, test_observer_manifest_fixtures.nim, test_observer_verdict_golden.nim, test_rotation_pin_anchor_check.nim — Makefile·workflows·ci/*.mk·config/*.nims 전수 grep에서 `tests/ci/` 경로 참조 0건.
- 단, test_rotation_pin_anchor_check.nim이 **검증하는 툴 자체**(`tools/ci/rotation_pin_anchor_check.nim`)는 landing 경로에서 매번 실행된다(`.github/workflows/admission-check.yml:2220-2223` — `nim c … -o:bin/rotation_pin_anchor_check tools/ci/rotation_pin_anchor_check.nim` 후 `bin/rotation_pin_anchor_check --derived-H … --pin-H …`). "테스트 파일 무배선"과 "테스트 대상 툴의 랜딩 배선"은 별개 사실이다.
- `ci/checker.mk`의 test 게이트(test-gateway :250 등)는 tests/gateway 레인이며 tests/ci를 실행하지 않는다(파일 전체에 `tests/ci` 참조 0건).

---

## 2. 파일별 전수 분류 (15개, 무분류 0)

공통 사실 (전 소스 판독 기준): **z3 의존 0, Lean 의존 0, gh CLI 실의존 0** (gh는 test_landing_observe_acceptance가 PATH 주입 stub으로만 사용, :41-77 — 실 API 호출 없음, 헤더 :6 "zero network, zero real GitHub state"), **테스트 실행 자체의 네트워크 의존 0** (sl02의 PR-context leg는 존재하지 않는 sandbox repo로 fail-closed, 헤더 :20-22). 아래 "외부 프로세스" 열은 테스트가 자식 프로세스로 호출하는 것.

### 2.1 test_admission_check_stages.nim (227행)

- **실행 위치**: make test-unit 로컬 (Makefile:1084). **본 PR에서 신규 비차단 진단 워크플로 1순위 대상으로 선정** (§3·§4 참조).
- **검증 속성**: admission-check.yml의 attest/verdict stage dispatch 계약 — witness 생산·업로드는 attest 전용, 인증서 소비·`ax merge --dry-run --json`은 verdict 전용, 프로비저닝 프리앰블은 무게이트, stage 배타성, artifact identity/attempt scoping 불변. 구조적 fail-closed 텍스트 단언 — 스텝 부재·이름 변경·복제는 raise로 실패(:70-93), 조용한 부분 일치 없음(:25-27).
- **환경 요구**: `import std/[unittest, os, strutils]`(:29) — **외부 프로세스 0**(execCmdEx/startProcess 0건), readFile(repo 루트의 admission-check.yml)만(:128). 네트워크 0.
- **실패 시 의미**: admission-check.yml의 stage conjunct 표류 = **제품 결함**(2026-10-04 실측 ~202분 재시도 루프 재조립, 헤더 :19-23). 환경 문제 가능성 거의 없음(대상 파일은 트리 상재).
- **분류 근거**: Makefile:1084; 소스 :29,:32,:128.

### 2.2 test_admission_venue_split.nim (503행)

- **실행 위치**: make test-unit 로컬 (Makefile:1085).
- **검증 속성**: ADR-0032 venue split — 4잡 첫 스텝 venue 결정(pull_request=preflight / merge_group·workflow_call=landing, 기타 fail-closed :242-274), heavy 스텝 landing 게드 정확 카운트(33+16, :296-344), 4개 preflight leg fail-closed 실증(:411-451), A2 핀 3-way 원자성(blob==TWS==epoch manifest, :453-467), artifact 표면 freeze 불변(:469-503).
- **환경 요구**: **python3+PyYAML**(스텝 TSV 추출 :95-117, run 본문 :154-167), **git**(A2 blob :455-456, freeze 태그 :60-72), **bash**(venue run 본문 실행 :189-210). freeze 태그 `ci-frozen-2026-10-09-venue-split` 부재 시 freeze 대비 구간이 **loud [SKIPPED]로 결정적 강등**(:488-491, §0.9 — 조용한 통과 아님). 네트워크 0.
- **실패 시 의미**: venue split·A2 핀·artifact 표면 표류 = **제품 결함**. freeze 태그 부재 SKIP은 환경 문제이나 출력으로 명시된다.
- **분류 근거**: Makefile:1085; 소스 :76-90(pyRun), :55-72(git), :488-491(skip).

### 2.3 test_b_cache_anchor.nim (782행)

- **실행 위치**: make test-unit 로컬 (Makefile:1083).
- **검증 속성**: J3 §3.3 B cache fingerprint 계약 — `.github/actions/setup-axiom-toolchain/action.yml`의 **실제 스텝 본문 원문**을 추출 실행: (h/i/a/b/c/m/v/r) 재유도 identity·digest 변조·vacuous·불완전 manifest 폐기, (p1-p5) semantic provenance probe 4종 바이너리+ircheck 감지, (c2) digest 자기일관 간을 probe가 닫음, (k1-k12) B-cache 키 입력 폐쇄(결정론·docs-only 무효화 소멸·closure 소화).
- **환경 요구**: **python3+PyYAML**(stepBody :73-84), **bash**(runStep :102-122), **git**(fixture repo :204-213, commit :519-525), **sha256sum**(:135-144, :143-146). /tmp fixture, 작업 저장소 비접촉(:45). 네트워크 0.
- **실패 시 의미**: B cache 무결성 계약 표류 = **제품 결함**(오염 캐시 재사용 = 검증 무효화).
- **분류 근거**: Makefile:1083; 소스 :47(imports os/osproc), :73-84, :204-213.

### 2.4 test_debt_schema_theater_rule.py (92행)

- **실행 위치**: **CI 직접** — debt-registry-gate.yml:36 (required check "debt-registry-gate", ruleset 20303214).
- **검증 속성**: Theater DEBT#357+ 5필드 계약(jsonschema Draft2020-12) — 유효 fixture 수용, 5필드(symbol/contentHash/lineRange/resolution/lastVerifiedAt) 결손·공란 각각 거부, non-Theater 카테고리는 rule 미적용, DEBT#356 이전 관행 허용, **실제 data/debt_registry.json 무오류**(:78-81).
- **환경 요구**: **python3 + jsonschema 라이브러리**(:7 import jsonschema). CI에서는 debt-registry-gate.yml:30이 `jsonschema==4.26.0` pip 설치(PyPI 이그레스 필요 — 테스트 로직 자체는 네트워크 불용). 저장소 내 data/*.json 판독.
- **실패 시 의미**: 극장 레지스트리 스키마 위반 = **제품 결함**(AGENTS.md §0.9a 직접 강제).
- **분류 근거**: debt-registry-gate.yml:30,:36; 소스 :7,:59-81.

### 2.5 test_derive_checker_closure.nim (227행)

- **실행 위치**: make test-unit 로컬 (Makefile:1080).
- **검증 속성**: closure 유도자(`tools/ci/derive_checker_closure.nim`) fail-closed 계약 — (a) hermetic walk 전체 성공+시드 포함+git ls-tree 포맷, (b) 실저장소 HEAD 양방향 단언(커밋 전 시드 부재 = UNRESOLVED, 조용한 skip 없음 :152-163), (c/d) 생성 바이너리 변수·eval 거부, --tree/--ref 결정론·상호배타·미존재 ref 거부.
- **환경 요구**: **nim**(deriver 컴파일 :40-50), **git**(fixture :105-110, :36-38). /tmp fixture. 네트워크 0.
- **실패 시 의미**: closure 유도자 표류 = **제품 결함**(checker closure의 신뢰 입력 무결성 근간).
- **분류 근거**: Makefile:1080; 소스 :18(imports os/osproc), :40-50, :165-183.

### 2.6 test_landing_observe_acceptance.nim (334행)

- **실행 위치**: make test-unit 로컬 (Makefile:1088) + **CI 직접** (axiom-operational-slice.yml:158-159 — 컴파일 후 `./build/landing_observe_contract` 실행).
- **검증 속성**: L4 관측자(`tools/ci/landing_observe.sh --main`) 종단간 계약 — 상태별 exit 코드(0 OBSERVED_SUCCESS/1 FAILURE/2 UNKNOWN/3 PENDING/4 STALE/5 NOT_RUN, :209-301), 관측 예산(콜드 3/warm 2/offline 0 API 콜 — 비용 주장의 근거 수치), L2 PR merge-queue 사전 dispatch phase PROGRESSING(QUEUED/AWAITING_CHECKS → exit 3, PR #1103 회귀 :303-334), 실패 쿼리·미문서 상태는 UNKNOWN fail-closed.
- **환경 요구**: **bash**(실제 스크립트 실행 :170-176), **stub gh 바이너리**(PATH 주입 :41-77, :131-138), sha256sum(:144), /tmp fixture. **gh는 stub만** — 네트워크 0, 실 GitHub 상태 무의존.
- **실패 시 의미**: 관측자 계약 표류 = **제품 결함**(상태를 성공으로 위보고하는 침묵 실패 모드, 헤더 :2-7).
- **분류 근거**: Makefile:1088; axiom-operational-slice.yml:158-159; 소스 :41-77(stub), :170-176.

### 2.7 test_observer_fixture_adr_lint.nim (131행)

- **실행 위치**: **무배선** (저장소 전수 grep 참조 0건; 헤더 :16에 단독 실행법만 기술).
- **검증 속성**: E-B fixture 디렉터리(tests/negative/observer_manifest_gate/) ↔ ADR-0033 "E-B fixture" 목록 1:1 lint — **섹션 부재 = fail(fail-closed)**(:95-100), 누락·유령 양방향 대조(:105-121).
- **환경 요구**: `import std/[os, strutils, algorithm]`(:19) — **외부 프로세스 0**, 순수 파일시스템 판독. 네트워크 0. 단독 main, exit 0/1(:127-129).
- **실패 시 의미**: ADR↔fixture 표류 = **문서-코드 정합 결함**(제품 부수 문서 계약 위반).
- **분류 근거**: grep 0건; 소스 :19, :95-100, :127-129.

### 2.8 test_observer_manifest_fixtures.nim (143행)

- **실행 위치**: **무배선**.
- **검증 속성**: 관측 오라클 음성 주입 fixture 3종(pass_control→PASS rc0 / violation_unregistered_runner→WOULD-BLOCK rc≠0 / fault_probe→OBSERVER-FAULT+fault_cause "gate") — rc AND verdict 이중 단언(:99-117), legacy 무인자 경로 exit 계약·stdout 공란(:120-125).
- **환경 요구**: **nim**(게이트 소스 컴파일 :51-72 — nimble pkgs2 checksums/fusion 경로 주입), **startProcess 서브프로세스**(:82-90). 네트워크 0.
- **실패 시 의미**: manifest_consistency_gate 관측 계약 표류 = **제품 결함**(ADR-0033 관측 오라클 신뢰성).
- **분류 근거**: grep 0건; 소스 :23(imports os/osproc/streams), :51-72, :82-90.

### 2.9 test_observer_verdict_golden.nim (143행)

- **실행 위치**: **무배선**.
- **검증 속성**: 게이트 구조화 verdict golden — 무인자 경로 바이트 불변(2회 실행 대조 :98-106), --json 고정키 순서(verdict→violations→judgmentKey→fault_cause)+재실행 결정론+정확히 1줄(:108-125), 건강 트리 verdict==PASS(:127-133).
- **환경 요구**: **nim**(게이트 컴파일 :52-73), **서브프로세스**(:82-91). 네트워크 0.
- **실패 시 의미**: verdict 안정성 계약 표류 = **제품 결함**(판정 소비자의 바이트·키순서 의존 깨짐).
- **분류 근거**: grep 0건; 소스 :22(imports), :52-73, :98-133.

### 2.10 test_oracle_evidence_regression.nim (789행)

- **실행 위치**: make test-oracle-evidence 로컬 (Makefile:1096-1097).
- **검증 속성**: 독립 오라클 oracle-evidence.json 5축 계약 — 셀렉터 `--oracle-evidence`(부재·스키마·digest 불일치 → exit 2, derivedEmpty=false인데 mode=none 금지), 게이트 `--oracle-evidence`·`--derived-h` fail-closed 페어, must-be-zero 5종(a-e) 픽스처, canonical form·derivationDigest 바이트 계약. **미지원 시 INTEGRATION-PENDING 정직 보고**(헤더 :47-49 — exit 0을 PASS로 위장 금지).
- **환경 요구**: **nim**(셀렉터·게이트 컴파일 :145, :397, :417-431), **git**(:153), **sha256sum**(:181). 네트워크 0.
- **실패 시 의미**: oracle evidence 계약 표류 = **제품 결함**(docs-only Δ 무효화 판정의 오라클 무결성).
- **분류 근거**: Makefile:1097; 소스 :64(imports os/osproc), :145-431(execCmdEx).

### 2.11 test_reanchor_pin.nim (226행)

- **실행 위치**: make test-unit 로컬 (Makefile:1081).
- **검증 속성**: 재앵커 writer/preflight 계약 — 판정은 공유 술어(`core/policy/rotation_closure_facts`) 위에서만(:71-124), pin@ref는 **ref의 트리**에서 판독(워킹 트리 오염 비혼입 :190-202), 표적 재작성 JSONC 보존+자기검증+멱등(:125-168), CLI 계약(exit 2 입력위반 :169-188), 멤버십 변경은 --write여도 미기록(:217-226).
- **환경 요구**: **nim**(프로젝트 모듈 import :18-20), **git**(임시 repo :58-69, :191-226). /tmp fixture. 네트워크 0.
- **실패 시 의미**: pin 재앵커 계약 표류 = **제품 결함**(trusted writer set 회전 신뢰성).
- **분류 근거**: Makefile:1081; 소스 :16-20(imports os/osproc+프로젝트 모듈), :58-69, :190-226.

### 2.12 test_rotation_pin_anchor_check.nim (151행)

- **실행 위치**: **무배선**(테스트 파일 기준). 단, 검증 대상 툴 자체는 landing 경로 배선 — admission-check.yml:2220-2223가 `tools/ci/rotation_pin_anchor_check.nim`을 컴파일·실행한다(툴 행동은 매 랜딩 검증, 이 테스트 파일은 별도).
- **검증 속성**: rotation preflight checker golden verdict — exit 0/1/2(PASS/ROT_NEW_PIN·ROT_GENESIS_INVALID/입력위반), 1줄 stdout 형태, JSONC pin 파싱, fail-closed 입력(파손·결손은 실행위반 — H2 판정 아님 :94-121), CLI 인자 계약(:123-137), cwd 기본 pin-B(:139-151).
- **환경 요구**: **외부 프로세스 0** — `import ci/rotation_pin_anchor_check` **인프로세스** 평가(:18, :61-64)+tmp 파일 fixture. nim 컴파일 필요. 네트워크 0.
- **실패 시 의미**: H2 checker verdict 계약 표류 = **제품 결함**.
- **분류 근거**: grep 0건(테스트 경로); 소스 :16-18, :94-137.

### 2.13 test_s5_build_skip.nim (439행)

- **실행 위치**: make test-unit 로컬 (Makefile:1086).
- **검증 속성**: S5 verified-supply build-skip 계약(J3 §3.1) — s5-supply 판정 스텝 유일성·위치·mode 중립(:247-263), 컴파일 경로 3스텝만 build 컨정크트(집합 닫힘 :265-275), 명시적 판정 라인(SUPPLY REUSE/S5 COLD BUILD — 조용한 skip 금지 :310-314), 실행 시뮬레이션(HIT/MISS 전체·부분 결손/폐기 상태 콜드 폴백/emit fail-closed :357-439), Q4 보간 토큰 금지(:328-339).
- **환경 요구**: **python3+PyYAML**(:78-108), **bash**(:180-200), **git**(freeze 태그 :164-176), **sha256sum**(:207-210). freeze 태그 부재 시 loud [SKIPPED](:291-294). 네트워크 0.
- **실패 시 의미**: S5 재사용 계약 표류 = **제품 결함**(무증 아티팩트 공급·조용한 skip = 극장).
- **분류 근거**: Makefile:1086; 소스 :41, :78-108, :291-294, :357-439.

### 2.14 test_sl02_consumer_binding.nim (417행)

- **실행 위치**: make test-unit 로컬 (Makefile:1087).
- **검증 속성**: SL-02 derived-closure consumer binding(ADR-0033+ADR-0025 Amendment F) — 5파일 all-or-none+L1 identity 바인딩+L2 재유도 digest 일치+candidate-delta leg의 **production bash 원문 실행**(T2/T2b/T3/T3b/T5 부정 행렬 :232-307, T6+positive는 실제 저장소·실제 deriver로 :388-417).
- **환경 요구**: **python3+PyYAML**(:46-70), **bash**(:91-142), **git**(sandbox repo :202-211, 실제 repo rev-parse/merge-tree :317-386), **nim**(deriver 컴파일 :328-332). 네트워크 0 — sandbox repo로 PR-context leg가 fail-closed(헤더 :20-22, :86).
- **실패 시 의미**: consumer binding 표류 = **제품 결함**(closure 아티팩트 위장 수용 = 검증 무효화).
- **분류 근거**: Makefile:1087; 소스 :24, :46-70, :91-142, :328-332.

### 2.15 test_verify_b_artifact.nim (132행)

- **실행 위치**: make test-unit 로컬 (Makefile:1082).
- **검증 속성**: SL-08 binding-only verifier(`tools/ci/verify_b_artifact.sh`) exit-code 계약 — happy(exit 0)/파일 변조·build_sha 불일치·manifest·artifact 결손(exit 1)/vacuous manifest(exit 1 — 극장 방지)/usage 오류(exit 2)/경로 이탈 ../ 탈출 거부(:63-133).
- **환경 요구**: **bash**(:56-59, :117), **sha256sum**(:30-33). /tmp fixture, 빌드 없이 텍스트 파일 페이로드(:35-54). 네트워크 0.
- **실패 시 의미**: B artifact 바인딩 계약 표류 = **제품 결함**(base-built verifier 신원 위조 수용).
- **분류 근거**: Makefile:1082; 소스 :17, :30-33, :56-59.

---

## 3. 차단 의미 결정 (Blocking Semantics)

**결정: 신규 진단 워크플로(`tests-ci-unit-diagnostic`)는 비차단(non-blocking) 진단이다. required 체크로 승격하지 않는다.**

근거:

1. **required 잡에 테스트를 추가하면 병합 계약이 확장된다.** 현재 ruleset 20303214(main, enforcement: active)의 required_status_checks는 5개 — `admission-check, bsec-integrity, debt-registry-gate, generation-acceptance, axiom-operational-slice`(2026-10-30 `gh api repos/Archright/Axiom/rulesets/20303214` 관측). 이 5개 워크플로 중 하나에 테스트 스텝을 추가하면 그 테스트의 실패가 required check 실패로 전파되어 병합을 차단한다 — 이는 병합 계약(무엇이 착지를 막는가)의 확장이며, **정책 결정이다**. 본 슬라이스의 범위는 진단 표면 추가이지 병합 계약 개정이 아니다(AGENTS.md §0.12 계약 보존 → 최소 변경).
2. **required 승격은 별도의 인간/정책 액션이다.** 선례: trusted-writer-set.yml 헤더 — "required check 승격(ruleset required checks 편입)은 인간 액션이며, 승격 전에는 어드바이저리 관측이다 (docs/spec/diagnostic_execution_delegation.md §7 미해결 인간 항목)". 본 워크플로는 어드바이저리 관측으로 착지하며, required 승격은 향후 명시적 정책 결정으로만 가능하다.
3. **workflow_dispatch 생성 체크는 PR 필수 상태 검사를 충족하지 않는다** (GitHub 플랫폼 공식 동작 — required status check로 인정되려면 check run이 PR 이벤트 경로에서 PR head에 대해 생성되어야 한다). 따라서 "비차단 진단이 실제로 PR 병합을 차단하지 않는다"는 보장의 증거 표준은 **실제 pull_request 이벤트 실행**이며, 본 PR 자체가 그 실행을 제공한다(§4 short validation). workflow_dispatch 수동 실행은 보조 시험 수단일 뿐 PR 계약 증거가 아니다 — 본 워크플로의 트리거를 pull_request로 한 이유다.
4. **실패 시 의미와의 정합**: §2에서 대부분의 무배선·로컬 테스트 실패가 "제품 결함"으로 분류됐다 — 그러나 "실패가 제품 결함을 시사한다"와 "실패가 병합을 차단해야 한다"는 별개 판정이다. 차단은 병합 계약에 대한 명시적 편입 결정을 요구하며, 진단 RED는 관측 신호로 남는다(극장 아님 — 실패가 로그로 관측 가능하고 조용히 삼켜지지 않는 한 §0.9 위반이 아니다).
5. **구조적 정합(착지 시점 관측)**: `.github/**`는 `config/repository_surface.json`(v90, base 바인딩)에서 **FROZEN(ADD=FAIL)** 으로 동결돼 있다 — docs/spec/repository_surface_contract.md의 trust 불변식("verification·authority·trust boundary에 닿는 표면은 명시적 승인 없이 변경 불가")이 그 근거다. 신규 워크플로 추가는 required 여부와 무관하게 그 자체가 trust 표면 진입점 추가다. 즉 "비차단 진단으로 착지시킨다"는 본 결정은 병합 계약 확장과 표면 정책 양축 모두와 정합하며, 워크플로 착지는 정책 승인 절차를 전제로 한다(§4 참조).

---

## 4. §2.5 세대 전환 기록 (CI Epoch Cutover Record)

[docs/agents/ci_epoch_cutover.md] 10단계 절차의 본 변경 적용 기록. 변경 범위: `.github/workflows/` 신규 파일 1개 추가(=ci_epoch_cutover.md §"다음 변경은 모두 CI 변경으로 간주한다" 1호 해당 — 규모 불문 절차 적용).

1. **Freeze** — 로컬 불변 태그 `ci-epoch-pre-vs-b-2026-10-30` → `474392b11`. 태그는 push하지 않는다: historical OID 태그 push는 push-admissibility 게이트가 fail-closed 심사한다(test_admission_venue_split.nim:60-66 실측 인용 — docs/evidence/freeze_tag_reproducibility_2026-10-11.md). freeze 태그 로컬 전용 관례는 저장소 기존 `ci-epoch-pre-*`·`ci-frozen-*` 태그군과 일치.
2. **Record** — frozen 세대 기록: commit `474392b11`; `.github/workflows/` 24파일; trusted writer = `certificate-mint.yml` 단일(`config/trusted_writer_set.json` trustedWriterWorkflow); A2 핀 3-way 동일값 `83260f72a8e47645f30618fc426bc1fd7561587f`(admission-check.yml blob == TWS trustedAdmissionWorkflowSha == epoch_manifest productionExecutionPin — 본 PR 착지 전 관측); required 5개는 §3 근거 1 참조.
3. **Tombstone** — **해당 없음**(명시 기록): 부가 세대다. 기존 워크플로·체크 identity·검증 경로를 하나도 폐기·비활성화하지 않는다. tombstone 부재는 required-check 우회·authority 제거를 의미하지 않는다(절차 3의 부정 조건 충족 없음).
4. **New Epoch** — `.github/workflows/tests-ci-unit-diagnostic.yml` 신규 구성: pull_request 트리거, permissions `contents: read` 단일, `test_admission_check_stages.nim` 실행. 기존 24 워크플로와 병렬인 독립 epoch.
5. **Atomic Binding Update** — 본 PR 단일 커밋 계열에 워크플로+본 기록 문서를 결속. **신뢰 소스 identity·SHA pin·digest 변경 0**: admission-check.yml 미접촉(A2 핀 불변), TWS 미개정(신규 워크플로는 `contents: read` — ADR-0022 contents:write writer 집합 등식에 영향 없음; trusted-writer-set.yml 등식 게이트가 PR에서 이를 검증), epoch_manifest 미개정. checkout 액션은 저장소 표준 SHA pin(`actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4`)을 사용. `ciGeneration` 값은 캐시 키·reuse record·verdict identity에 결속되지 않는다(ci_epoch_cutover.md 절대 금지 준수 — 본 변경은 어디에도 ciGeneration을 쓰지 않는다).
6. **Local / Targeted Verification** — 대상 테스트 로컬 PASS 관측: `nim c -r --skipParentCfg --skipProjCfg … tests/ci/test_admission_check_stages.nim` → 10/10 `[OK]`(~2초). 플래그 필요 근거: tests/ 이하 컴파일은 `tests/config.nims:8-12`가 bin/ax 존재를 요구(Test Domain Integrity Guard, env 탈출구 없음) — 본 테스트는 std-only로 핵심 아티팩트를 소비하지 않으므로, 저장소 자체 선례(src/gate 단독 컴파일 · src/gate/config.nims:10-16, sl02 deriver 컴파일 · test_sl02_consumer_binding.nim:328-332)와 동일한 `--skipParentCfg --skipProjCfg` 단독 컴파일 패턴을 사용한다. 이는 게이트 우회가 아니라 **도메인 밖 단독 빌드 경로**다 — guard가 보호하는 "핵심 아티팩트에 의존하는 테스트" 성분이 이 테스트에는 없다(import 문 단계에서 실증, §2.1). 워크플로 파일은 `tools/ci/validate_workflow_shell.sh` 로컬 통과(bsec-integrity와 동일 런블 — parse-poison·lane-stderr 룰).
7. **Short Validation** — **수행 불가로 종결(명시 기록)**. push 단계에서 push-admissibility 정적 게이트의 `check-repository-surface`(Makefile:536-546)가 본 OID를 FAIL 판정했다: `git show <merge-base>:config/repository_surface.json`(base 바인딩)의 FROZEN 클래스(`.github/**` — ADD=FAIL)가 신규 워크플로 추가를 `SURFACE_FORBIDDEN`으로 거절. 기계 증거: (i) 실제 push 실패 — `git push` → `make[1]: *** [Makefile:539: check-repository-surface] 오류 1` → `[Pre-push FAIL] Push-target OID 96ce298bc… failed static admissibility (snapshot)`; (ii) 동일 판정 재현 — `bin/surface_guard --policy <base> --diff <branch diff>` → `verdict: FAIL / changeClass: FROZEN / reasonCode: SURFACE_FORBIDDEN`; (iii) push 텔레메트리 `~/.cache/axiom/push-admissibility/log.jsonl` 2026-10-30T13:50:12Z `{"ref":"work/vs-b","oid":"96ce298bc…","result":"FAIL"}`. --no-verify 사용 없음(AGENTS.md §2 — 감사 추적 없는 게이트 우회 금지).
8. **Canonical Cutover** — **차단 확정(정책 경로 포함)**. 정책 선등록 2단계 선례(bab91d320 v85 … d37183f4e v90, `policy/surface-v*` 브랜치)가 존재하나, 정책 PR 자체도 base 바인딩에서 `config/repository_surface.json`(FROZEN) MODIFY=FAIL로 같은 게이트에 막힌다 — bin/surface_guard 재현: 정책 파일 1파일 diff → `verdict: FAIL / SURFACE_FORBIDDEN`. 즉 현행 게이트 구조에서는 에이전트가 훅을 준수하는 한 어떤 경로로도 새 워크플로·정책 개정을 push할 수 없고, 이 bootstrap은 인간 아키텍트의 명시적 승인(정책 개정 병합 또는 워크플로 추가에 대한 직접 승인)으로만 열린다. 선례 텔레메트리가 이를 교차 실증한다: 본 머신 기록에서 v86·v89 정책 push는 FAIL(2026-10-22T15:01:14Z, 2026-10-23T15:42:36Z)이며 해당 커밋들은 이후 main에 착지돼 있다 — 착지는 로컬 훅 경계 밖의 권한(훅 미설치 클론 push 또는 GitHub 병합 권위 행사)으로 수행됐다는 뜻이며, 그 권한은 에이전트에게 없다(AGENTS.md §2: 게이트 우회·감사 추적 없는 통과 금지).
9. **Production Acceptance** — 워크플로 미착지이므로 새 워크플로에 대한 production acceptance는 없다(없는 것을 있는 것으로 보고하지 않는다 — 극장 금지). 본 PR(분류 문서 착지) 자체의 landing은 별도로 관측한다: `tools/ci/landing_observe.sh --main <merge-sha> --stats` → OBSERVED_SUCCESS(L4).
10. **Rollback** — 불필요: 신규 epoch는 main에 하나도 결속되지 않았다(frozen 세대에서 변한 것은 문서뿐). 구성 완료된 pending epoch는 (i) 로컬 브랜치 `work/vs-b-pending-epoch` == `96ce298bc`(워크플로+본 문서 동결본)와 (ii) 부록 A의 YAML 원문으로 보존한다. 인간 승인이 내려지면 부록 A를 `.github/workflows/tests-ci-unit-diagnostic.yml`으로 착지시키고 §2.5 절차 7-9를 그 PR에서 재개한다.

**필요한 권한(정지 보고)**: `.github/**` FROZEN 개정 권한 — 구체적으로 (a) `config/repository_surface.json` 정책 개정(신규 워크플로 경로의 CONTROLLED 선등록, v85-v90 선례 준수)을 병합할 인간 아키텍트의 승인, 또는 (b) 승인된 정책 세대 아래 워크플로 파일을 착지시킬 병합 권위 행사. 에이전트는 훅 준수 push로는 어느 쪽도 수행할 수 없음이 (7)(8)의 기계 증거로 확정됐다.

---

## 5. 관측 한계 (미검증 항목)

- **워크플로 미착지**: 신규 진단 워크플로는 실제 PR 이벤트 실행 증거(short validation)가 존재하지 않는다 — §4 (7)(8)의 게이트 차단이 원인이며, 부록 A의 YAML은 검증된 구성물이지 실행 증거가 아니다. 구성 단계 검증만 관측됐다: 테스트 로컬 10/10 PASS, validate_workflow_shell.sh 229 blocks failures=0.
- 본 문서의 ruleset required 목록은 2026-10-30 관측값이다 — 병렬 착지 중인 다른 PR이 required 집합을 개정했다면 불변 확인은 그 시점 값과 비교해야 한다(비교 대상은 "신규 워크플로 미포함"이지 "5개 불변"이 아니다).
- freeze 태그 의존 구간(test_admission_venue_split, test_s5_build_skip)의 freeze 대비 단언은 해당 태그가 있는 클론에서만 무변경 실행된다 — 부재 시 loud SKIP이 계약된 동작이다(§0.9).
- "workflow_dispatch 생성 체크는 PR required를 충족하지 않는다"는 GitHub 플랫폼 동작에 관한 공식 문서 사실이며, 본 저장소의 ruleset 구성에서의 재실증은 하지 않았다(할 이유가 없다 — 본 워크플로는 애초 required가 아니다).
- v86/v89 정책 커밋의 실제 push 경로(어떤 클론·권한으로 착지됐는지)는 본 머신 텔레메트리만으로는 특정할 수 없다 — 특정 가능한 사실은 "본 머신 기록 FAIL → 이후 main 착지"라는 권한 비대칭의 존재뿐이다.

---

## 부록 A — 구성 완료된 pending epoch (승인 전 착지 금지 산출물)

아래는 §4 (4)(6)에서 구성·로컬 검증을 마친 워크플로의 전문이다. `.github/workflows/tests-ci-unit-diagnostic.yml`으로 착지하려면 §4 "필요한 권한"의 승인이 선행해야 하며, 착지 PR은 §2.5 절차 7-9(실제 pull_request 이벤트 실행 증거 → required 불변 확인 → landing OBSERVED_SUCCESS)를 재개한다.

```yaml
# tests-ci-unit-diagnostic — non-blocking diagnostic: runs one selected tests/ci unit test.
#
# [Blocking semantics — READ BEFORE PROMOTING]
# This workflow is deliberately NOT a required check and MUST NOT be promoted
# to the ruleset required_status_checks without an explicit policy decision:
#   * required checks are the merge contract (ruleset 20303214, main, active:
#     admission-check, bsec-integrity, debt-registry-gate,
#     generation-acceptance, axiom-operational-slice as of 2026-10-30) —
#     adding a test step to any of those jobs propagates its failures into
#     merge admission;
#   * required-check promotion is a human/policy action
#     (docs/spec/diagnostic_execution_delegation.md §7; trusted-writer-set.yml
#     header precedent — before promotion this is advisory observation);
#   * a check produced by workflow_dispatch does not satisfy PR required
#     status checks (GitHub platform behavior) — the PR pull_request event
#     run is the evidence-grade execution, which is exactly the trigger this
#     file declares.
# Classification SSOT: docs/evidence/tests_ci_assurance_classification_2026-10-30.md
# (per-file wiring/environment/failure-semantics table, zero unclassified).
#
# [Why this test] tests/ci/test_admission_check_stages.nim — std-only imports
# (unittest/os/strutils), zero external child processes, zero network, reads
# .github/workflows/admission-check.yml and pins the attest/verdict stage
# dispatch conjuncts. It is the only tests/ci source that runs hermetically
# with no python3/yaml/git/sha256sum dependencies, so this diagnostic job
# needs no extra provisioning beyond the pinned toolchain.
#
# [AGENTS.md §2.5 — coherent generation] Additive epoch: no existing workflow,
# check identity, or trusted binding is touched. Freeze record:
# docs/evidence/tests_ci_assurance_classification_2026-10-30.md §4 (freeze tag
# ci-epoch-pre-vs-b-2026-10-30 == 474392b11; tombstone: none — additive;
# atomic binding: contents: read → not a TrustedWriterSet contents:write
# writer, admission-check.yml blob/A2 pin untouched).
#
# [Q4 quirk] No GitHub expression tokens inside run: blocks
# (docs/spec/gh_run_observation_quirks.md Q4) — event-sourced values stay in
# with:/env:, never interpolated into run bodies.

name: tests-ci-unit-diagnostic

on:
  pull_request:

permissions:
  contents: read

concurrency:
  group: tests-ci-unit-diagnostic-${{ github.event.pull_request.number || github.sha }}
  cancel-in-progress: true

jobs:
  # The job id IS the check-run context — no job-level `name:` key
  # (same discipline as axiom-operational-slice.yml).
  tests-ci-unit-diagnostic:
    runs-on: [ "${{ fromJSON(vars.CI_RUNNER_MAP).x64 }}" ]
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
      - uses: ./.github/actions/setup-axiom-toolchain
        with:
          cache-build-source: ${{ github.sha }}
      - name: "Diagnostic: admission-check stage-dispatch contract (test_admission_check_stages)"
        # --skipParentCfg --skipProjCfg: standalone compile outside the Test
        # Domain guard (tests/config.nims requires bin/ax; this std-only test
        # consumes no core artifact — same standalone-compile recipe the repo
        # already uses for out-of-domain tool compiles). Failure here is a
        # RED diagnostic signal in this job's log; it does not gate merges.
        run: |
          set -euo pipefail
          nim c -r --hints:off --skipParentCfg --skipProjCfg --nimcache:build/nimcache/tests_ci_unit_diag -o:build/tests_ci_unit_diag/test_admission_check_stages tests/ci/test_admission_check_stages.nim
```
