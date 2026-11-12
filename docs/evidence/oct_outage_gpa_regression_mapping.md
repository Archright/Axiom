# 2026-10-12 → 2026-10-21 장애군의 GPA 회귀 매핑 (oct_outage_gpa_regression_mapping)

> **분류**: 실행 증거 (관측 기록 + 분석) · **작성**: 2026-10-22 · **관측 기준시각**: 2026-10-21T18:48:14Z (2026-10-22 03:48 KST) · **작업 주체**: Axiom Agent (읽기 전용 조사 — 저장소·조직·ruleset 미변경)
> **Related**: `docs/spec/rearm_recovery_status.md` (rearm INACTIVE 선언 + 수동 runbook) · `docs/adr/0027-queue-delegation.md` (rearm 정책) · `docs/spec/admission-generation.md` §7·§8 ("green = verified" 폐기 · 10-12 봉쇄 기록) · `docs/spec/test_judgment_cas_contract.md` (REUSED basis 계약) · `docs/agents/merge_admission_observation.md` (failure→recovery 유한 절차) · `docs/agents/rules_workflow.md` §Auto-Merge Default Policy (정본 arm 명령)
> **원자료**: `/tmp/oct12-21_timeline.md` · `/tmp/defense_failures.md` · `/tmp/defense_stack_audit.md` · `/tmp/v51_assumptions.md` (2026-10-22 조사 산출물, 저장소 외부). **네 파일 모두 존재 확인** — 재구성(재작성) 불필요. 본 문서는 그 산출물과 라이브 read-only 조회(§6)에만 근거한다.

---

## 0. 목적과 방법

**목적**: 10-12 → 10-21 장애군에서 관측된 실패 메커니즘 각각에 대해, **GPA(Generation Promotion Acceptance) 도입이 어떤 검증을 통해 사전에 잡는가 / 잡지 못하는가**를 **정직하게** 구분해 기록한다.

**방법 (3축 매핑)**:

1. **메커니즘** — 10-12~21 장애군에서 관측된 7개 주요 실패 메커니즘(§2). 각 메커니즘은 **run id · PR 번호**로 식별된다.
2. **GPA 검증 계층** — GPA 계획(Phase 1~4)이 정의한 검증 계층. 이 문서의 매핑 기준은 §1의 표이며, **계획 스펙에 기재된 범위를 넘어 확장하지 않는다**.
3. **판정** — 세 값 중 하나:
   - **닫음** — 해당 메커니즘의 발현이 GPA 도입으로 **사전에 차단**된다.
   - **부분** — 발현의 **일부**만 사전 차단된다 / 발현 지점은 옮겨지지만 원인 판별은 남는다.
   - **못 닫음** — GPA의 PREVENT가 **접하지 않는다**. 이 경우 **어느 계층이 담당하는지**를 명시한다(§3).

**정직성 규칙 (AGENTS.md §0.9 극장 금지 · §0.6 정적 우선)**:
- "GPA가 막아줄 것이다"는 **근거 없는 예측이 아니라** "어느 계층의 어느 검사가 어느 관측 증거를 잡는가"로 서술한다. 근거가 없는 계층은 **명시적으로 못 닫음**으로 기재한다.
- 매니페스트의 **추정**(inference)과 **직접 관측**(live API / 로그)을 구분해 인용한다. 매니페스트의 원문 caveat는 §6에 전사한다.
- **UNKNOWN은 UNKNOWN으로 둔다** — 닫힘을 주장하려고 UNKNOWN을 함부로 닫지 않는다.

---

## 1. GPA 검증 계층 (매핑 기준)

GPA 계획이 정의한 검증·증거 계층. 각 항목의 "무엇을 잡는가"는 **계획 스펙에 기재된 범위**를 그대로 옮긴 것이다.

| 계층 | 정의 | 잡는 것 (계획 스펙 기준) |
|---|---|---|
| **L1 — 정적** | 변경된 workflow yaml를 결정론적으로 파싱 | 후보 workflow 파일의 **구문·구조** |
| **L2 — 3-leg** | base 트리의 `tools/merge_ruleset_drift_monitor.nim` 재사용 | required-check SSOT 3-leg: **정책 파일 ↔ 컴파일된 상수 ↔ 라이브 ruleset ↔ 실제 producer** |
| **L3 — 승격 정합성** | `epoch_manifest.productionExecutionPin` == TWS blob == `admission-check.yml` blob | **핀의 3-way 정합** — 후보가 trustSurface·epoch 파일을 바꾸면 신규 값의 내부 정합성 요구 |
| **L4 — 자기 시험** | 후보 SHA에서 결정론 유도한 known-good / known-bad fixture | **후보 자신의 판정기가 정상인지**(known-good → PASS, known-bad → REJECTED). 후보가 bad에서 PASS를 보고하면 REJECTED |
| **관계 검증** | `tools/promotion/validate_manifest.sh` (gh + jq, 결정론) — PR #1024 착지 완료 — 2026-10-22 drift-signal v1 승격에서 5/5 관계 PASS 실증(data/promotions/drift-signal-v1/manifest.json) | 5개 **관계**(필드 존재가 아님): ① acceptanceRun(run↔SHA↔event↔conclusion) ② candidateSha == PR head ③ rulesetReadback(expected == actual, operator provenance) ④ productionRun@mergeSha ⑤ mergeSha == PR mergeCommit |
| **uniqueness 사전 검증** | 최근 main check-runs에 대상 컨텍스트 부재 + 전 workflow grep + dynamic 경로 확인 | **"유일 producer" 선언**의 사전 근거 |
| **ruleset readback** | 승격 전후 라이브 ruleset · pin 바이트 비교 | **승격이 라이브 불변을 깨지 않았음** |

**구조적 전제 (GPA의 PREVENT가 성립하는 조건)**:

- **신뢰 분리** — Driver(검증 로직·fixture·판정 기준)는 base ref에서, 후보는 `path: candidate`로 **데이터로** 체크아웃. merge commit 기본 체크아웃을 명시적으로 배제.
- **execution surface** — `merge_admission` trustSurface ∪ `.github/workflows/**` ∪ `config/policy/**` ∪ `dynamic/**` 변경 시에만 전체 검증. 그 외는 fast-path green + verdict `NO_SURFACE_DELTA`.
- **fail-closed** — GPA 자체가 파손되면 check 미보고 → required check 미충족 → **병합이 막힌다**(안전 정지).

> **이 표가 아닌 계층은 존재하지 않는다.** 아래 매핑에서 "L1/L2/L3/L4/관계검증/uniqueness/readback" 이외의 계층을 만들어 PREVENT를 주장하지 않는다.

---

## 2. 7개 메커니즘 × GPA 계층 매핑표

### M-A — 0-job dispatch (parse poison), 10-12 · 병해 기간 최대 단일 장애

| 항목 | 값 |
|---|---|
| **관측** | 2026-10-12 10:38:01Z 첫 0-job run `38237548129` (`merge_group`, pr-788, `jobs.total_count=0`) · 10-12 총 **266 failed run** 중 **~219건이 0-job** `admission-check.yml`/`admission-gate.yml` run · 동일 계열 `38239637198` · `38251477288`(#794 착지 후에도 지속) · `38289641939`(S5 acceptance, green) |
| **원인** | org caller의 callee pin이 PR #780 세대로 회전(09:50:31Z) → 그 세대의 `run:` 스칼라가 **interpolation token을 포함**하고 **25,954자**(GitHub 표현식 한도 21,000자 초과) → **call graph가 planning 단계에서 거부** → 0 job, check-run 없음 → required check `admission-check`가 **구조적으로 생성 불가** → 큐 봉쇄 |
| **증거 위치** | `docs/evidence/admission_parse_poison_oracle_2026-10-13.md` (21,000자 한도 오라클: 25,954자 token-bearing FAIL / 26,282자 token-free PASS) · `docs/spec/admission-generation.md` §8 ("223런 · ~9시간 구조적 봉쇄") |
| **GPA 계층** | **L1 (정적)** — 단, **조건부** |
| **판정** | **부분 → 조건부로 닫힘** |
| **닫히는 이유** | 저장소에는 이미 21,000자 상한을 **강제하는 정적 하네스**가 존재한다: `tools/ci/validate_workflow_shell.sh`(`EXPR_LEN_CAP = 21000`, token 보유 run 스칼라에만 적용) + 자체시험 `tools/ci/test_workflow_poison_lint.sh` (5-피처 판정 행렬: 21001 FAIL / 21000 PASS / 20999 PASS / 30000 token-free PASS / 25954 FAIL). 그리고 이 하네스는 `.github/workflows/bsec-integrity.yml:113-114`에서 **이미 후보 디렉터리(`../candidate/.github/workflows`)를 스캔**한다. GPA의 L1이 이 하네스를 재사용하면 → PR #780의 스칼라가 **승격 전에** 차단된다 |
| **잔여 (닫히지 않는 부분)** | ① **GPA L1의 현 스펙은 "yaml parse"뿐**이다 — poison 하네스 포함은 **범위 확장**이 필요하고, 확장하지 않으면 L1은 이 결함을 잡지 못한다. ② org 측 caller 회전(`Archright/.github`의 `uses:` 핀)은 Axiom의 execution surface **밖**이라 GPA fast-path(`NO_SURFACE_DELTA`)에 걸린다 — 다만 결함의 **원천(Axiom 측 스칼라)**은 `.github/workflows/**` 안이므로 surface 안이다. ③ 10-20 재발(M2, 아래 §4)은 **차단이 아니라 재발** — 10-12의 처치가 "차단이 아니라 핀 회전"이었다는 점이 이 메커니즘의 본질이다 |
| **책임 계층** | PREVENT (L1 확장 시). 재발 지속성은 **PREVENT + 배선** — 하네스가 design doc + 하네스 수준에 머물렀다면 차단 게이트로 승격되어야 한다 |

### M-B — B/M-split 순차 결함 (promote-then-validate), 10-14 · 10-20

| 항목 | 값 |
|---|---|
| **관측** | B/M 세대 강제(`34f34a86e`, 2026-10-20 21:19Z) 이후: run `39537491732` (2026-10-21T03:14:39Z, `merge_group`, failure — job `119017747613`) → `[FATAL] Engine source/source mismatch (SourceCoherence FAIL) tree=4001324870617279706 embedded=-4862258572969452841` · overlay 계열: `39472598522` (`overlay identity outputs missing — the overlay step must run first (fail-closed)`), `39490305583` (`exec record[s1a] overlayManifestDigest != recomputed overlay digest (fail-closed)`) · 10-14 계열: 4-lane 병렬 레짐(#826) 후 첫 green MG `38543329104`가 **전 레인 SKIP(REUSED)**으로 green — 병렬 경로가 green MG 안에서 한 번도 실행되지 않음 |
| **원인** | **새 세대를 live에 승격한 뒤 production merge_group이 그 세대의 acceptance 테스트가 됨** — "첫 production 실행 = 첫 테스트" 구조. plan이 overlay **이후**에 실행되어 B-clean 작업공간 조건이 깨짐 |
| **증거 위치** | `docs/evidence/ci_generation_repair_2026-10-21.md` §2 (D1) · `docs/evidence/mg_red_forensics_2026-10-14.md` §(a) |
| **GPA 계층** | **L3 (승격 정합성)** + **관계 검증** + **PREVENT 절차 자체** |
| **판정** | **닫음 (강)** — 절차 차원에서 |
| **닫히는 이유** | GPA는 **"승격 전 acceptance 통과"를 구조적으로 필수화**한다. 이 메커니즘은 정의상 "승격 후 첫 실행이 첫 테스트"이므로 GPA 세대에서는 **발현 경로 자체가 사라진다**. L3는 핀의 3-way 정합(`epoch_manifest.productionExecutionPin` == TWS `trustedAdmissionWorkflowSha` == `admission-check.yml` blob — 현재 관측값 `83260f72a8e47645f30618fc426bc1fd7561587f`)을 검증하고, 관계 검증 ④는 **착지 후 production 실행을 mergeSha에 결속**해 "착지했으나 실행 안 됨"을 잡는다. TWS의 880 멤버 spot-check 4건(`tested_tree_closure.nim` · `judgment_cas.nim` · `semantic_set_derivation.nim` · `merge_cli.nim`)에 대한 `git hash-object` == 핀 sha 실측도 그 결속의 근거다 |
| **잔여** | **단계 순서 자체**(overlay이 plan보다 먼저 실행되어야 한다)는 워크플로 yaml의 정적 속성이므로 L1이 단언할 수 있으나, **현 L1 스펙("parse")에는 순서 단언이 없다**. 순서 단언 없이는 "실행 순서" 결함은 닫히지 않고 "승격 절차"만 닫힌다 |
| **책임 계층** | PREVENT (L3 + 관계 검증). 순서 단언은 L1 확장 |

### M-C — shadow ruleset의 check-run 이름 충돌 → 정상 PR 차단, 10-21

| 항목 | 값 |
|---|---|
| **관측** | org ruleset `25514358`(`generation-shadow-evaluate`, `enforcement=evaluate`)을 2026-10-21 00:52:52Z 다른 controller sha(`22a9a0ed`)로 재핀 → 같은 head `4d7709e95`에 **check-run 이름이 `admission-check`로 동일한 2개** 동시 존재: `118976093208`(active, success) / `118975654295`(shadow, **failure**) → **PR #1005가 차단**됨(`gh pr checks`는 `admission-check pass`로 표시 — 진실과 불일치). run `39523975594`(active, success) + `39523975608`(shadow, cancelled) |
| **원인** | `evaluate`는 **규칙**을 비강제화할 뿐 **check-run 이름을 네임스페이스하지 않는다**. 실패한 check-run은 API로 **삭제 불가** → 새 head(`79f179357`)가 필요 → #1005는 closed unmerged |
| **GPA 계층** | **없음** |
| **판정** | **못 닫음 — PREVENT 외** |
| **못 닫는 이유 (3중)** | ① shadow ruleset은 **조직 레벨**(`Archright/.github`) 산출물이라 Axiom의 execution surface(`.github/workflows/**` ∪ trustSurface ∪ `config/policy/**` ∪ `dynamic/**`) **밖**이다 → GPA fast-path(`NO_SURFACE_DELTA`)로 들어가지 않는다. ② 충돌은 **ruleset 핀 불일치가 아니라 check-run 이름 충돌**이다 — GPA의 ruleset readback는 **핀된** ruleset(repo `20303214`, org `25218071`/`23943917`)의 **값 일치**를 검증하지, "같은 이름을 내는 다른 ruleset이 존재하지 않는다"를 검증하지 않는다. ③ **uniqueness 사전 검증은 `generation-acceptance` 계열 컨텍스트의 유일성**만 확인하므로 `admission-check` 이름 충돌을 잡지 않는다 |
| **책임 계층** | **PREVENT 밖** — shadow 설계 자체의 잔여. 실측상 "evaluate 모드 단독으로는 격리를 제공하지 않는다"가 확정된 finding이며, 차후 설계는 **별도 canary ref 또는 별도 이름의 harness**로 갈아타야 한다. **GPA는 이 메커니즘의 예방 수단이 아니다** — 사실이 이 계층에 남는다는 기록 자체가 본 매핑의 산출물이다 |
| **증거 위치** | `/tmp/defense_failures.md` C4 · `/tmp/oct12-21_timeline.md` 10-21 00:52~01:06 항목. **주의**: 이 실험의 유일한 1차 기록은 커밋되지 않은 로컬 세션 export이며(매니페스트 caveat), 저장소 내 영구 기록은 없다 — `docs/spec/vs3_phase2_scratch.md`는 #1005가 closed unmerged 상태로 `origin/main`에 남아 있다 |

### M-D — drift monitor의 schedule 미발화 + 자체 빌드 실패, 10-16 → 10-21

| 항목 | 값 |
|---|---|
| **관측** | `admission-ssot-drift` (workflow id `391703936`) run **4건 전부 `event=workflow_dispatch`** — `39603184495` FAIL(12:52:54Z) · `39604571246` FAIL(13:02:50Z) · `39610756667` FAIL(13:45:17Z) · `39622835490` success(15:07:22Z). **schedule run 0건** — cron `37 4 * * *`의 첫 발화는 2026-10-22T04:37Z. 4건 **모두**에 `nimble install` 부트스트랩이 존재했고 **green run을 포함** 실패(log lines 1028/1032) — PR #1019 `5affbcd27`가 부트스트랩을 제거했으나, 유일한 green은 15:07:22Z로 **수정(16:08:11Z)보다 61분 앞** → **수정 후 재실행이 아직 없음** |
| **원인** | (a) cron은 **자기 미발화를 감지할 수 없다**(플랫폼 제약). (b) monitor의 own 빌드가 `buildtemp` 복사본에서 hermetic `generated/build_env` 없이 `nimble install`을 돌려 **구조적으로 실패**. (c) tier-2 모드에서 `--allow-unavailable-ruleset`이 붙으면 **ruleset leg이 통째로 불가** → monitor가 "NOT PERFORMED … DEGRADED MODE"로 보고해도 workflow는 **GREEN** |
| **GPA 계층** | **L2 (3-leg)** — 단, L2는 **monitor를 재사용**하므로 결함이 **전이**된다 |
| **판정** | **못 닫음 — DETECT 계층** |
| **못 닫는 이유** | ① **cron 미발화는 GPA의 판정 대상이 아니다** — GPA는 PR 트리거(merge_group 포함)이며, 주기 실행의 부재를 스스로 관측할 수 없다. ② **monitor own 빌드 실패는 L1의 대상이 아니다** — L1은 *후보 workflow yaml*의 정적 파싱이고, monitor는 **Nim 도구 빌드**다. L2가 base 트리의 monitor를 재사용하므로, base에 monitor가 깨져 있으면 **GPA의 L2도 같이 못 돈다**(전이 위험). ③ **DEGRADED MODE의 GREEN 위장**은 L2 재사용 시 그대로 전이한다 — 부분 판정을 전체 GREEN으로 올리는 경로가 plan에 차단 장치로 없다 |
| **책임 계층** | **DETECT** — watchdog(독립 cron `17 */6 * * *`의 closure-watcher freshness)이 "두 번째 GPA 승격"(SUSTAIN 실증)으로 착지한다. **그 전에는 "cron 누락 자동 감지"를 주장하지 않는다**(플랫폼 제약, §1.2) |
| **증거 위치** | `/tmp/defense_stack_audit.md` §2.1 · `/tmp/defense_failures.md` C5a·C5b · `docs/evidence/admission_generation_pin_divergence_2026-10-15.md` |

### M-E — 정책↔구현 predicate 불일치로 인한 false red (skip-only lane / REUSED basis), 10-20 → 10-21

| 항목 | 값 |
|---|---|
| **관측** | **C2b/M3**: run `39578751740` · `39581030837` (pr-1010) · `39613168689` (pr-1017) · `39614674867` · `39620683879` (pr-1018) — 로그 job `119267813230`: `[admission-tests] FAIL — REUSED-only lane — 0/3 GO-critical tests EXECUTED (a skip-only lane is never green, fail-closed)`. **PR #1017·#1018이 closed unmerged** — 내용이 #1019 안에 재차지되어야 착지했다. **C2a**: `39519429046` (pr-1003, 00:07:59Z) · `39525976099` (pr-1005, 01:12:45Z) — s1a의 REUSED 하드 실패 vs 계약(`docs/spec/test_judgment_cas_contract.md`)의 "REUSED는 유효 basis" 규정. **검출은 우연**: VS-3 fixture PR이 걸린 것으로만 드러남 — **어떤 게이트도 이 불일치를 잡지 않았다** |
| **원인** | 정책 문서(계약)와 그 정책을 구현하는 fail-closed predicate가 **서로 다른 판정을 냈다**. 정규 정책 변경이 구현 predicate에 반영되지 않으면, 합법한 work가 차단된다 |
| **GPA 계층** | **L4 (자기 시험)** + PREVENT 절차 |
| **판정** | **부분** |
| **닫히는 부분** | L4는 후보 SHA에서 결정론 유도한 known-good/known-bad fixture로 **후보 자신의 가드를 후보가 직접 실행**하게 한다. 후보 가드가 정상 동작하는지, 그리고 known-bad를 놓치지 않는지가 **승격 전**에 관측된다. 더 근본적으로, PREVENT 절차는 "live 큐에서 처음 실행 = 첫 테스트"를 제거하므로 이 결함의 **발현 지점이 acceptance로 이동**한다(PR closed unmerged → 후보가 사유와 함께 REJECTED) |
| **닫히지 않는 부분 (잔여)** | **계약(정책 문서) ↔ 구현 predicate의 정합성을 자동 검증하는 계층이 GPA에 없다.** L2의 drift monitor는 **required-check SSOT(정책 ↔ 컴파일 상수 ↔ 라이브 ruleset ↔ producer)**만 다룬다 — 워크플로 내부 predicate의 semantics는 다루지 않는다. 게다가 PREVENT는 "오탐"을 **구분**하지 않는다: 후보 acceptance에서 같은 가드가 red를 내면 GPA는 그 PR을 REJECTED한다 — 그 자체는 올바른 PREVENT지만 **원인이 "정책 불일치"인지 "진짜 결함"인지를 판별하는 수단이 없다**. v5.1에도 그 수단은 없다 |
| **책임 계층** | PREVENT (발현 지점 이동, 부분) + **잔여는 별도 계층** — 계약↔predicate 정합성 모니터는 존재하지 않으며, 존재한다고 가정하지 않는다 |
| **증거 위치** | `/tmp/defense_failures.md` C2a·C2b·M3 · `docs/evidence/ci_generation_repair_2026-10-21.md` §2 (D2) |

### M-F — "green = verified" 마스킹 (REUSED skip으로 인한 가짜 green), 10-14

| 항목 | 값 |
|---|---|
| **관측** | PR #826(4-lane 병렬 GO-critical 레짐)이 2026-10-14 05:02:17Z 착지 → **#828의 첫 merge_group 이전 유일한 MG run `38543329104`(09:34:22Z, `conclusion=success`)** 은 4-lane GO set 전체가 **REUSED로 SKIP**되어 green. 즉 **병렬 레인 경로가 green merge_group 안에서 한 번도 실행되지 않았다**. 첫 red까지 **4 h 41 m** (09:34:22Z green → 14:15:39Z `38578920996`) |
| **원인** | judgment CAS의 **reuse가 "실행 없음"과 "green"을 구별하지 못함**. "green ⇒ verified" 등식이 깨짐 |
| **GPA 계층** | **L4 (자기 시험)** + 관계 검증 |
| **판정** | **닫음 (강)** |
| **닫히는 이유** | L4는 **후보 SHA에서** fixture를 결정론 유도해 known-good(→PASS)·known-bad(→REJECTED)을 실행한다. 후보가 bad에서 PASS를 **보고**하면 REJECTED — 즉 **"skip이 green을 위장"하는 것 자체가 검사 대상**이다. 이는 M-F가 요구한 것과 정확히 같은 형태의 방어다. 절차적으로도 GPA는 "후보의 첫 실행이 production이 아닌 acceptance"를 구조적으로 보장한다 |
| **잔여** | L4 fixture는 **GPA가 지정한 경로만** 커버한다. 후보 내부의 다른 skip 경로(4-lane GO set 같은)가 fixture 커버리지에 없으면 그 경로는 여전히 가짜 green을 낼 수 있다 → **커버리지 의존의 잔여** |
| **증거 위치** | `/tmp/defense_failures.md` C1a · `docs/evidence/mg_red_forensics_2026-10-14.md` §(a) · `docs/evidence/emergency_evaluate_window_2026-10-14.md` · `docs/spec/admission-generation.md` §7 ("green = verified" 폐기) |

### M-G — rearm 0 arms (자동 복구 경로 부재), 10-12 → 10-21

| 항목 | 값 |
|---|---|
| **관측** | `merge-queue-rearm.yml` **267 run / 0 arm**. arm 명령에 도달한 run은 **2건**(2026-10-13, PR #820)이고 **둘 다 실패**: run `38440666593`(17:41:19Z) · `38441126650`(17:44:47Z) — 원문: `SKIPPED: arm command failed — verbatim error below (fail-safe no-arm, no escalation):` / `GraphQL: Resource not accessible by integration (enablePullRequestAutoMerge)`. arm 성공 시에만 부착되는 `rearmed@<head12>` 라벨은 PR 60건 스캔 결과 **0건**(유일하게 존재하는 `rearmed@caab865d8a76`은 description이 `"Slice B retry-budget marker (simulation)"` — 시뮬레이션 표식) |
| **원인** | 워크플로의 `GITHUB_TOKEN`이 `enablePullRequestAutoMerge` 뮤테이션에 대한 권한을 갖지 않음. `permissions:`는 `pull-requests: write` · `contents: read` · `actions: read` · `checks: read`만 선언하고 **큐 write 권한이 없다** |
| **GPA 계층** | **PREVENT 아님 — RECOVER 계층** |
| **판정** | **못 닫음 — 구조적으로 다른 계층** |
| **못 닫는 이유** | GPA는 **승격의 결함을 막는다**. 이미 큐에서 빠진 PR의 **복구**는 별개의 문제다. GPA 계획 자체가 네 보장을 **PREVENT / DETECT / RECOVER / SUSTAIN**으로 구분하고, RECOVER의 정의를 **"자격 없는 자동 복구 = 정직한 비활성 선언"**으로 못박는다 — 즉 rearm 자동화는 GPA의 PREVENT에 **포함되지 않는다**. 현재 상태는 **INACTIVE**(정직한 비활성 선언) + 수동 runbook이며, 자동화는 **명시적 인간 결정**(App 프로비저닝) 사항으로 남아 있다 |
| **책임 계층** | **RECOVER** — 자동 복구 도입 시 §4.6의 6단계 게이트(권한 사전 실측 포함)를 통과해야 하며, 그 전까지는 수동 runbook이 유일 경로다. 상세: `docs/spec/rearm_recovery_status.md` §3·§4 |
| **증거 위치** | `docs/spec/rearm_recovery_status.md` §1 (본 문서 작성 시점의 재실측) · `/tmp/defense_stack_audit.md` §2.3 |

---

## 3. PREVENT가 닫는 것 / 못 닫는 것 — 명시적 구분

### 3.1 닫음 (GPA 도입으로 사전 차단)

| 메커니즘 | 닫는 계층 | 닫히는 방식 |
|---|---|---|
| **M-F** "green = verified" 마스킹 | L4 + 절차 | 후보가 own 가드로 bad에서 PASS를 보고하면 REJECTED. "첫 production 실행 = 첫 테스트" 구조 자체가 제거됨 |
| **M-B** B/M-split 순차 결함 (promote-then-validate) | L3 + 관계 검증 + 절차 | 승격 전 acceptance가 구조적으로 필수. 핀 3-way 정합 + 착지 후 production 실행의 mergeSha 결속 |
| **M-A** 0-job dispatch (parse poison) | L1 (**poison 하네스 포함 시**) | 21,000자 상한을 강제하는 정적 하네스가 후보 디렉터리를 이미 스캔한다 — 승격 전에 차단 |

### 3.2 부분 (일부만 사전 차단)

| 메커니즘 | 닫히는 부분 | 남는 부분 |
|---|---|---|
| **M-E** 정책↔구현 predicate 불일치 | 발현 지점이 live 큐 → acceptance로 이동. 후보 가드의 정상 동작이 사전 관측됨 | 계약↔predicate 정합성 자동 검증기가 없다. PREVENT는 "오탐"과 "진짜 결함"을 **구분**하지 않는다 |
| **M-B**의 순서 부분 | (위 닫힘에 포함) | overlay/plan **순서 단언**은 L1 스펙에 없다 — 단언 없이는 순서 결함은 닫히지 않는다 |

### 3.3 못 닫음 (PREVENT가 접하지 않는다) — 담당 계층 명시

| 메커니즘 | 담당 계층 | 왜 GPA가 접하지 못하는가 |
|---|---|---|
| **M-C** shadow ruleset check-run 이름 충돌 | **PREVENT 밖** (shadow 설계 잔여) | org 레벨 산출물이라 execution surface 밖. 충돌이 ruleset 핀 불일치가 아니라 **check-run 이름** 충돌이라 readback·uniqueness 모두 접하지 못함 |
| **M-D** drift monitor schedule 미발화 + own 빌드 실패 | **DETECT** | cron 미발화는 자기 감지 불가. monitor own 빌드 실패는 L1 대상이 아니며, L2가 monitor를 **재사용**하므로 결함이 **전이**한다. DEGRADED→GREEN 경로도 전이 |
| **M-G** rearm 0 arms | **RECOVER** | GPA는 승격 결함의 방어다. 복구는 별 계층이며, 자동화는 인간 결정 사항으로 남아 있다 |

### 3.4 요약 문장

> **GPA의 PREVENT는 "승격이 라이브를 깨뜨리는" 결함을 닫는다. 그 밖은 닫지 않는다.**
> 닫힘 3건(M-F·M-B·M-A) 중 **2건은 "개념이 아니라 절차"로 닫힌다** — 후보의 첫 실행이 acceptance가 되기 때문에, 개별 결함의 정밀한 탐지 능력 없이도 **그 결함이 처음 나타나는 곳**이 사라진다. 부분 1건(M-E)은 **발현 지점만** 옮긴다. 못 닫음 3건(M-C·M-D·M-G)은 **PREVENT 밖**이며, 각자 다른 계층(DETECT·RECOVER·설계 잔여)이 담당한다.
> **이 구분을 축소해 서술하면** "GPA가 10월 장애군을 막았다"는 위장이 된다(AGENTS.md §0.9).

---

## 4. 7개 외 잔여 메커니즘 (보조 표 — 같은 기준으로 매핑)

| 메커니즘 | 관측 | GPA 판정 | 담당 계층 |
|---|---|---|---|
| **M2** 0-job dispatch **재발** (10-20) | `runner-pool-acceptance.yml` **23 run** (11:13:35Z → 19:31:02Z) 전부 `jobs.total_count=0` — `39413430950` · `39415300998` · `39416709432` · `39418765629` · `39428852102` · `39430849301` · `39452486004` · `39453367620` · `39454592364` · `39455349953` · `39457192685` · `39458301551` · `39458560283` · `39459595029` · `39460691010` · `39461805886` · `39463079026` · `39464119570` · `39466388644` · `39468268341` · `39470711136` · `39471210395` · `39484127005`. 10-12의 근본 원인은 **닫히지 않았고**, 처치는 **design doc + lint 하네스** 수준에 머물렀다 | **부분** (M-A와 동일) + **차단 게이트 승격 필요** | PREVENT (차단 게이트로 승격 시) |
| **M4** lane가 base를 테스트 (후보 아님) — 자기참조 | `39364761754` · `39374305024` · `39390453929` · `39507820332` · `39508463576` — 전부 `FAIL — tests/unit/test_s1a_lean_golden.nim (make test-fast-one non-zero)`. 수리 PR이 **고친 테스트가 레인에서 실행되지 않아** 수리 PR이 자기 결함에 막힘 | **부분** — 후보 acceptance는 **후보를** 실행하므로 이 자기참조 구조는 GPA에서 **구조적으로 해소**된다(레인이 base가 아니라 후보를 본다). 단, s1a 이외 사안의 일반적 자기참조는 별도 추적 항목으로 남아 있다 | PREVENT (GPA 절차) |
| **M6** `ADM_IDENTITY` / `CANDIDATE_TREE_MERGE_ERROR` | `39405339725` · `39483852628` — `ADM_IDENTITY FAIL — CANDIDATE_MERGE_BASE_UNRESOLVED: ancestry(…) unresolved after 8x64-commit deepening (history cap reached — fail-closed)` · `39295768242` · `39494927042` — `CANDIDATE_TREE_MERGE_ERROR: merge-tree($B_EVT, $H_EVT) rc=… (output unspecified per the git merge-tree contract — fail-closed)` | **못 닫음 (_PREVENT 층위)** — history 깊이 상한(`8x64`)은 **깊은 이력에서 반드시 실패하도록 설계된** 검사다. GPA는 후보의 *acceptance*를 더하지만 이 상한은 동일하다. hardening은 매니페스트에 "비급한 후속"으로 남아 있고 **GPA가 닫지 않는다** | PREVENT 잔여 (설계 결함) |
| **M7** MINT_A0 base-SHA binding의 false red | `39579485358` (job `119154329556`, `pull_request`, pr-1010) — `MINT_A0_ACTIVATION: FAIL — PR #1010 base.sha '29f820c1ff85' != baseSha input '791dd162e720' (fail-closed)`. `mint-prepare/prepare` `119154329556` · `mint-publish/publish` `119154614020` · `admission-check` `119154822313` 전부 실패 | **부분** — 검사는 옳고(승인된 base에 결속되어야 한다), 오탐은 base 이동의 결과다. GPA L4가 base 이동 중의 후보를 사전에 관측할 수 있으나 **"base가 이동했으니 재인가"라는 재인가 경로**는 여전히 필요하다(문서화·도구화 여부 미확인) | PREVENT + 운영 절차 |
| **M9** 소유자의 직접 병합 (merge gate 우회), 10-13 | PR #814 MERGED 13:10:38Z (`fdd8703c84dc…`) · PR #815 MERGED 13:10:43Z (`aa051134359e…`) — 둘 다 `mergedBy=wintrover`, `committer=web-flow`, **review 0건**, merge_group 평가가 **진행 중·red**인 상태. red run 6건: `38401843972` · `38402599853` · `38402732819`(#814) / `38401846277` · `38402601651` · `38402734886`(#815), 실패 지점 `(P7b) [SL-15] evidence record → evidence CAS ledger append (exactly-once)`. 마지막 merge_group 평가는 **13:22:47Z** — 병합 **이후**에 끝남. **어떤 통제도 우회를 탐지하지 못했다** | **못 닫음 — PREVENT 밖** — GPA는 **PR의 후보**를 검증한다. 관리자가 규칙셋을 우회해 직접 push하는 경로는 **GitHub의 관리자 권한**이며, GPA가 개입할 수 없다. `bypass_actors: []` / `current_user_can_bypass: never`가 규칙셋 수준에서 봉쇄하지만 **직접 병합 경로는 그 밖**이다 | **PREVENT 밖** (권한 경계) |
| **C6** org 자체 venue의 0-job (public → private callee) | `Archright/.github`의 `admission-gate-v2.yml` 자기 실행 **27/27 failure, 0 jobs** (2026-10-16T06:54:45Z → 2026-10-21T16:21:15Z): `39633995282` · `39597714019` · `39551173894` · `39518387976` · `39518228125` · `39518124737` · `39517930630` · `39502394633` · `39496816603` · `39486895886` · `39478494324` | **해당 없음 (inert)** — public org repo가 private reusable workflow를 호출할 수 없어 call-graph planning이 실패한다. **Axiom의 merge gate에 영향 없음**(ruleset `25218071`은 Axiom의 private 컨텍스트에서 실행, `repository_id 1182157951`) — ADR-0035 §4가 **P1 비권위**로 문서화·수락 | 비권위 노이즈 (수락) |
| **C7a/b** emergency ruleset window + 그 감사 기록 | window: trigger `39395675848` → #965의 green `39398959763`(job `118549349258`, 09:15:08.503Z)가 **이미 18초 앞**에 green — operator의 오진단으로 **불필요한** window 개방. `20303214` disabled 09:15:26.483Z → enabled 09:15:50.416Z (**23.933 s**), `enforcement`만 변경, body `RESTORED_BYTE_IDENTICAL`, #965 직접 병합 09:15:37Z. 감사 기록: ruleset history version `53933458`/`53933497`가 **약 1일간** 존재하지 않음 | **부분** — window는 **PREVENT 밖의 운영 도구**다. GPA가 승격 결함을 막으면 window의 **필요 빈도**는 줄지만, 창 개방 자체(22~24초 ruleset 무력화)는 남는다. 감사 기록의 **기한 조항**은 PR #1010(`e24990bef5`)으로 추가됐으나 **창 종료 시 기록 작성을 강제하는 장치는 여전히 없다** | **PREVENT 밖** (운영 도구 + 감사) |

---

## 5. 관측 · 인용 규칙

- §2·§4의 모든 run id · PR 번호 · job id · check-run id는 **원자료 매니페스트와 저장소 문서에서 전사**했다. 매니페스트가 **직접 읽은 로그/API 관측**인 것과 **저장소의 포렌식 기록에 의존한 추론**인 것이 섞여 있으므로, §6에 원문 caveat를 전사한다.
- **GPA 계층 판정의 근거가 되는 GPA 설계는 본 문서 작성 시점에 origin/main에 없다** — §1의 계층 표는 **GPA 계획(Phase 1~4)**의 정의이며, 구현이 아니다. 따라서 §2·§3의 판정은 **"계획에 정의된 이 계층이 이 메커니즘을 잡는가"**에 대한 것이고, **"구현이 이 메커니즘을 잡는다"에 대한 실측이 아니다**. 이 구분은 §6에서 다시 명시한다.
- "닫는다"는 표현은 **"이 계층의 관측 대상에 이 메커니즘의 증거가 포함된다"**는 뜻이다. 실행·관측이 아니다(AGENTS.md §2.2 — "코드는 테스트·코드 성공만으로 완료를 주장할 수 없다").

---

## 6. 근거 범위 · 한계 (정직 기록)

원자료 매니페스트의 caveat를 전사하고, 본 문서에서 추가한 한계를 명시한다.

1. **매니페스트의 "223런 / ~9시간"**은 **저장소 내 수치**(`docs/spec/admission-generation.md` §8)다. 10-12 API census는 **failed run 총 266건**이며, 그중 **~219건이 0-job** `admission-check.yml`/`admission-gate.yml` run이다 — **266건 전부를 job-count 하지는 않았다** → 223 수치는 **상호검증되지만 정확히 재도출된 것은 아니다**. 본 문서의 "219"는 이 "~219"를 그대로 인용한 것이며, **개별 run 검증 결과가 아니다**.
2. **10-12와 10-14의 근본 원인**은 **저장소 자체의 기록에 의존한 추론**(F1/F2 포렌식)이며, 10-14 기록 자체가 **레인 트랜스크립트 소실**을 인정한다 → **증명으로 승격될 수 없다**. 그 외 항목은 라이브 API 관측 또는 직접 읽은 run/job 로그다.
3. **C4(shadow)·C7(emergency window counterfactual)의 유일한 1차 기록**은 **커밋되지 않은 로컬 세션 export**(`kimi-export-session_-20261021-033254.md`)이며 **저장소에 없고 지속되지 않는 증거**다. shadow ruleset `25514358`은 이미 삭제되어 `GET`이 404를 반환한다.
4. **C6(org 자체 venue)의 0-job run은 inert**하다 — Axiom의 merge gate에 영향을 주지 않는다. 10-12의 org repo 자체 ruleset history는 조사되지 않았다.
5. **emergency window의 counterfactual**("#965는 어차피 큐에서 병합되었을 것이다")은 **명시적으로 미관측**이다 — 실제 병합은 직접 병합이었고 큐 병합이 아니다. 사실로 승격하지 않는다.
6. **448 failed run을 전수 분류하지 않았다** — 10-19→10-21의 `admission-gate` merge_group 실패 **37건**(6+21+10)은 각각 실패 job 로그를 읽어 분류했고, 10-13/10-14는 저장소의 포렌식 기록 + API 총계로 처리했다. **10-12(266)와 10-13(54) 모집단은 run-by-run이 아니라 워크플로 이름과 저장소 포렌식 기록으로 기술되었다.**
7. **[본 문서 추가]** §1의 GPA 계층 정의는 **계획**이며 구현이 아니다. §2·§3의 "닫음/부분/못 닫음"은 **계획에 정의된 계층과 실패 메커니즘의 대응 판정**이고, **구현에 의한 실측이 아니다**. GPA v1이 착지한 뒤에는 **이 표를 갱신해 실제 계층 이름·판정 코드와 일치시켜야** 하며, 그 전까지 이 표를 "GPA가 막는다"는 운영 근거로 인용하지 않는다.
8. **[본 문서 추가]** §2 M-G의 rearm 수치(267 run / 0 arm, arm-failed 원문)는 **본 문서 작성 시점(2026-10-21T18:48:14Z)에 재실측**한 값이며, 1차 관측은 `docs/spec/rearm_recovery_status.md` §1에 기록되어 있다. run 수는 이후 증가하므로 **관측 시각과 함께 인용**한다.
