# GO-critical 2-레인 job-matrix 재병렬화 사전등록 — 판정 기준 전체 고정 (2026-10-16)

> **종류**: 사전등록 문서 (pre-registration) — G2(GO-critical 재병렬화, Option A: 2-레인 job-matrix)의 **어떤 후보 런도 개시하기 전에** 가설·설계·진입 전제조건·실행 의미론·동결 측정·합격 기준·비용·롤백·S1 수용 조건을 전부 고정한다. 형식·규율 계보의 원전은 형제 문서 `docs/evidence/merge_latency_decision_prereg_2026-10-14.md`다 — 본 문서는 그 **append-only 형제**다(선대 문서의 고정 본문·§8 개정을 변경하지 않는다).
> **규율 원천**: `merge_latency_decision_prereg_2026-10-14.md` §8(레인 stderr 라이브 전사·always 업로드 = 재병렬화 필수 승격 조건 — 본 문서는 **인용만** 하고 중복 서술하지 않는다) · `go_critical_parallel_decomposition_2026-10-11.md` §5.3·§9.2(별도 job 분해의 지배·기각 근거와 δ≤60 s 채택 관문) · `docs/spec/admission-generation.md` §5·§5.7(세대 전환·롤백 정본 — verbatim 인용) · `docs/agents/merge_admission_observation.md`(관측 계약) · `tools/ci/validate_workflow_shell.sh` 레인-stderr 가드(PR #851, 기계 집행) · AGENTS.md §2.3·§2.5.
> **no-peeking**: 본 문서의 모든 기준은 후보(production-shaped matrix 코드)가 **한 번이라도 실행되기 이전**에 고정된다. 관측을 본 뒤의 기준 변경은 어떤 형태로도 허용되지 않으며, 변경은 새 날짜의 사전등록 문서로만 한다.
> **권위**: 본 문서는 Reporter다 — 병합 판정 권위(GitHub ruleset·required checks·merge queue)를 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3). 본 문서 자체는 docs-only 커밋이며 어떤 판정 권위도 이동·추가·약화시키지 않는다.
> **소유자 승인**: 2026-10-16 G2 계획(Option A: 2-레인 job-matrix) 승인 + 전면 허가. 본 문서는 그 결정의 정식 등록 전표이며, 확정 시점을 문서 커밋·PR·시각으로 추적 가능하게 한다.

---

## 1. 가설과 설계 (2-레인 분할 — Option A)

**설계 대상**: `admission-check.yml` attest stage의 `[check] GO-critical admission tests (DEBT#432)` 직렬 스텝(`.github/workflows/admission-check.yml:1120` — `make test-fast-one` 4종 순차, 컴파일 포함)을 **동일 attest stage 안의 2-레인 job-matrix**로 분해한다.

| 레인 | 테스트 | 측정 근거 (G-B — §4 동결) |
|---|---|---|
| **lane-0** | `tests/unit/test_s1a_lean_golden.nim` | 303–307.8 s — 직렬 스텝(중앙값 545 s)의 **56%** (critical path) |
| **lane-1** | `tests/unit/proof_integrity_test.nim` (48.3 s) + `tests/unit/test_d2_golden.nim` (156.8 s) + `tests/unit/test_d2_persist.nim` (32.7 s) | 합 **237.8 s** |

- **분할 근거 (G-A — critical-path matching)**: 최장 단일 테스트(s1a)를 단독 레인으로, 나머지 3종을 짝 레인으로 배치한다. **4-레인 대안은 기각**되었다 — job당 준비 비용이 4배 지불되어 경제성이 지배된다(`go_critical_parallel_decomposition_2026-10-11.md` §5.3이 접근 (b) 별도-job 분해를 기각한 것과 동일 구조: H 레짐 순절감 63.4 s, 준비비 상단(131 s)에서는 음수(−4.6 s)).
- **Option B(스텝 내 intra-job 레인 — 구 prereg 계보의 접근 (a)) 기각**. 독립 근거 2가지:
  1. **자기 저장소의 채택 관문 위반**: `go_critical_parallel_decomposition_2026-10-11.md` §9.2는 접근 (a) 채택을 **δ ≤ 60 s**(병렬 스텝 벽시계 − 최장 단일 테스트, 1회 검증 런) 관문으로 고정했다. G-A의 콜드 경로 추정은 **65–115 s**(가드 포함) — 관문이 사전에 거부하는 영역이다.
  2. **R1 잔존 위험**: 콜드 env-hash stamp 동시 오케스트레이션은 풀 가드 스택 이후에도 **봉인되지 않았다** — `config.nims`의 `AXIOM_GATE_BOND` 스킵 창이 잔존 위험으로 남아 있다.
- **세대 경계**: 이 변경은 활성 실행 경계의 in-place 부분 수정이 아니라 **coherent generation 전환**(AGENTS.md §2.5)이다 — S1(실험 수용, §8) → S2(승격) 절차로만 활성화되며, 본 문서는 그 전환의 판정 기준만 등록한다(구현 차량은 별도).

## 2. 진입 전제조건 (6 — 고정)

아래 6항이 **모두** 성립해야 S2 승격이 허용된다. 어느 하나라도 불성립이면 진입 금지(fail-closed).

**(i) 레인 stderr 보존** — matrix 구조가 **구조적으로(by construction)** 충족한다: 각 레인은 독립 GitHub job이므로 네이티브 job 로그·check-run이 GitHub에 그대로 보존된다. 단일 스텝 내 레인 패턴(`go-critical-lanes` / `lane_run` / `>…$d/run.log` 리다이렉트)이 존재하지 않으므로 bsec 레인-stderr 가드(`tools/ci/validate_workflow_shell.sh` — PR #851 추가)의 **트리거 조건 자체가 없다**. 이 필수 조건의 정본은 `merge_latency_decision_prereg_2026-10-14.md` §8이며, 본 문서는 그 적용 판정만 기록한다(중복 서술 없음).

**(ii) 공유 경로 경합 방지** — 구조적 보장: per-runner 파일시스템(GitHub-hosted ephemeral runner — 레인 간 공유 가변 상태 0), 레인은 서로 **아무것도 교환하지 않음**, 캐시는 **per-runner 로컬 전용**.

**(iii) 원자 캐시 노출** — per-lane 캐시는 러너와 함께 소멸한다(교차-레인 발행·게시 없음). J3 fold(test-mode nimcache의 base B-cache carrier 접기)에 미치는 영향은 G-A 실측 **≈ 0**.

**(iv) per-lane EXECUTED 증거** — 판정-CAS `basis=REUSED` 결과는 **새 구조의 검증으로 절대 계수하지 않는다**. 각 레인은 후보(신규 세대) 위에서 신선한 `EXECUTED`를 보여야 한다. REUSED는 설계된 재사용 경로일 뿐, 구조 전환의 수용 증거가 아니다(2026-10-14 REUSED 마스킹 계보 — `docs/spec/admission-generation.md` §7 "green = verified" 등식 기각의 재적용).

**(v) 실패 전파 (fail-closed)** — callee 런 결론 = **모든 matrix job의 success**. 하나라도 failure/skipped/cancelled이면 attest != success → 기존 fail-closed 집계(`Archright/.github` `admission-gate.yml` — "aggregate job requires all jobs to be `success`", skipped→FAILURE 규칙 내재)가 `admission-check` required check를 RED로 만들고 머지가 차단된다. **skipped/cancelled 레인 ≠ 성공.**

**(vi) rollback 준비** — §7의 앵커(then-current pinned generation sha + 태그)가 승격 시점에 실제로 기록·태그되어야 한다. 앵커 없는 승격은 금지.

## 3. 실행 의미론 (4 — 고정)

1. **`fail-fast: false`** — GitHub 매트릭스 기본값(true)은 한 job 실패 시 **진행 중·대기 중** matrix job을 취소한다(cite: GitHub Docs reusables fragment `reusables/actions/jobs/section-using-a-build-matrix-for-your-jobs-failfast` — "Using a build matrix for your jobs → Fail-fast"). 후보 구조는 `fail-fast: false`로 고정한다 — 한 레인이 실패해도 **모든 레인이 끝까지 실행되어 증거를 남긴다**(2026-10-13 리버트된 4-레인 blob의 stderr 소실 계보의 구조적 재발 방지 — prereg-2026-10-14 §8 위반 계보).
2. **집계는 기존 fail-closed 집계를 소비한다** — `needs` 결속 + 기존 admission-gate 집계의 skipped→FAILURE 규칙. 새 집계 권위를 도입·재구현하지 않는다(Authority ≠ Adapter).
3. **REUSED-as-verification 금지** — §2-(iv)의 실행 조항으로, 수용·판정 관측은 `EXECUTED`만 소비한다.
4. **레인 간 공유 가변 캐시 금지** — 레인 간 전달이 필요해지는 경우 **artifacts·불변 입력만** 허용한다. 가변 상태 교환은 §2-(ii) 위반이다.

## 4. 동결 측정 (G-B verbatim 등록)

G-B(2026-10-16 G2 계획의 측정 분석 — 본 문서가 그 등록 전표다)가 고정한 공식·표본·숫자를 그대로 옮긴다. 본 문서는 공식을 재정의하지 않으며, **S1·S3 실행자는 아래 공식·명령을 한 글자도 바꾸지 않고 재사용해야 한다**.

### 4.1 측정 공식 (D1–D4 — G-B 고정)

| 지표 | 공식 (G-B verbatim) |
|---|---|
| **D1** PR→green | `t(첫 green) − t(PR created_at)` — 첫 green = PR 헤드 required status-check contexts가 전부 success가 되는 최초 시각 |
| **D2** auto-merge→MG run | `t(auto-merge 진입) → 바운드 merge_group admission 런` — 바운드 런 = 실패 시 PR을 자동 dequeue시키는 admission-gate 런 |
| **D2′** companion | D2와 동일 공식을 동일 auto-merge 이벤트가 산출하는 동반(companion) MG 런에 적용 — D2와 쌍으로 수집 |
| **D3** PR→main | `t(GitHub native MERGE 커밋 mergedAt) − t(PR created_at)` — MERGE 커밋 parents==2 조건(`docs/agents/merge_admission_observation.md` 착지 정의) |
| **D4** GO-critical step | attest job 내 `[check] GO-critical` 스텝 duration — steps[] `started_at`→`completed_at`(API 초) 또는 로그 라인 1차값(소수 초) |

**P95 방법 (R-7)**: Hyndman–Fan type 7 선형 보간 — `h = (n−1)·0.95; P95 = x[⌊h⌋+1] + (h−⌊h⌋)·(x[⌊h⌋+2] − x[⌊h⌋+1])`(1-indexed). n=5→h=3.8, n=11→h=9.5.

### 4.2 직렬 베이스라인 (11-PR 창 — after-side 비교의 before, 동결)

단위: 초. 열 순서: mean / median / P95 / min / max.

| 지표 | mean | median | P95 | min | max |
|---|---:|---:|---:|---:|---:|
| D1 | 1071.5 | 377 | 4000.5 | 303 | 5585 |
| D2 | 849.1 | 418 | 2638.6 | 308 | 3579 |
| D2′ | 80.5 | 19 | 357.5 | 18 | 694 |
| D3 | 2361.7 | 1556 | 5203.5 | 1405 | 6783 |
| D4 | 517.8 | 545 | 555 | 421 | 557 |

동결 성분: attest job wall **654.7 s** · attest setup 스텝 **56.9 s** · MG(merge_group admission) 런 wall **1106.1 s**.

### 4.3 측정 명령 (S1/S3 실행자 verbatim 재사용 의무)

```bash
# 착지 정체성·TOT (D3) — GitHub native MERGE 커밋 권위
gh pr list -R Archright/Axiom --state merged --limit 100 --json number,createdAt,mergedAt,mergeCommit

# MG 런 경계 — go-live 탐지 + AFTER 데이터셋 정의 (세대 전환 경계)
tools/ci/golive_detect.sh --since <T_promotion> --tws-sha <신 TWS> --out data/merge_latency/golive_g2matrix
tools/ci/merge_latency_audit.sh --runs @data/merge_latency/golive_g2matrix.post_golive.ids \
  --out data/merge_latency/g2matrix_AFTER --boundary-note "smoke=<first_post_run_id> excluded; g2 matrix prereg 2026-10-16"

# D4 스텝 1차값 (로그 라인, 소수 초) — 레인 분해는 레인별 행
tools/ci/go_critical_parallel_extraction.sh runs <t_go_live> <out>
gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/<JOB_ID>/logs \
  | grep -E "\[admission-tests\] (RUN|PASS)|duration_ms=|\[test-supply\]"

# 단일 PR 착지 관측 (보조 — 관측 계약 준수 경로)
tools/ci/landing_observe.sh <PR>
```

## 5. 성능 합격 기준 (사전등록 통계)

**after-side 표본 정의**: 신규 세대(승격) 아래에서 착지한 PR **≥ 5건** — post-promotion steady state. **승격 PR 자체는 표본에서 제외한다.**

**PASS = 아래 (a)·(b)·(c) 전부**:

- **(a) D4-parallel-composite 중앙값 ≤ 400 s** — composite = `max(lane-0 GO, lane-1 GO) + per-lane setup`(setup 기준치: 직렬 attest setup 56.9 s, §4.2). 직렬 중앙값 545 s 대비 G-A 기대 ≈ **371 s**.
- **(b) D3 중앙값 개선 ≥ 300 s** (베이스라인 중앙값 1556 s 대비).
- **(c) MG-run 실패율 무증가** — 5런 창에서 **레인 구조에 귀인되는 admission red 런 0건**. 귀인 판정은 `docs/evidence/mg_red_forensics_2026-10-14.md`의 포렌식 어휘를 따른다.

**보고 규칙**: 모든 지표를 **mean AND P95 AND min/max를 나란히** 보고한다. P95는 n=5–11에서 R-7 보간 특유의 불안정성이 있다(작은 표본에서 최대·최소값 지배 보간 — 본 문서에 기록된 caveat) — 판정 근거로 P95 **단독 사용 금지**, min/max를 항상 나란히 제시한다.

**NON-IMPROVEMENT 결정 규칙** (사전 고정 — 관측 후 판정 아님):

- (a) 또는 (b)가 실패하고 신뢰성(§2 전제조건)이 온전하면 → **"reliability achieved, performance goal NOT met"**으로 보고한다(순화·스핀 금지 — 정직한 프레이밍). 세대는 **유지될 수 있으며**(MAY — 유지 판정을 기록으로 남긴다), 유지 여부는 **+39% 러너-분 비용**(§6) 대비로 평가한다.
- (c)가 실패하면 → **즉시 rollback 평가 개시**(§7 절차).

## 6. 비용 (성능과 별도 추적)

- **기대치 (G-A 표 verbatim)**: 지불 계층(paying layer) 러너-분 **+39%** — matrix `2×371 s + monolith` vs 직렬 `641 s`.
- 비용 목표를 착지시간 목표와 **혼합하지 않는다** — §5 (a)(b)는 착지시간 판정, 본 절은 회계 판정이다(서로 다른 수량 — 기호·판정을 공유하지 않는다).
- **실측치 기록 의무**: S3가 after-side 창의 러너-분 합계(레인 job 분해 포함)를 측정해 기대치와 나란히 기록한다. 실측이 기대치를 유의하게 초과하면 그 사실 자체를 보고한다 — 새 임계를 만들지 않으며, 유지·철회 판정은 소유자 몫이다.

## 7. 롤백 앵커 (동적)

- **앵커 기록 (S2 의무)**: 승격 시점에 S2가 그 시점의 **then-current pinned generation sha**를 기록한다 — 예상: `135644a302`(H₂), F2 착지 시 H₃ — 단 **S2가 live로 판독한 값이 권위다**(예상치는 예상일 뿐). 아울러 컨트롤러 원격에 태그 **`admission-gen-rollback-<date>`**를 남긴다(`admission-generation.md` §3.3의 immutable reference 원칙 준용 — 삭제 금지).
- **복원 절차 = `docs/spec/admission-generation.md` §5 verbatim**: (1) 빈 큐 확인(Axiom merge queue·in-flight merge_group 0) → (2) dispatch freeze(`max_entries_to_build` 2→0, readback) → (3) ruleset **24233738**을 **앵커 sha로** PUT(workflows 규칙 — ref 제거) → (4) ruleset **23943917** 동일 적용(3·4는 하나의 논리적 전환 단위) → (5) readback byte-consistency(앵커 sha 설정·그 외 모든 규칙·조건·bypass 무변경) → (6) freeze 해제(0→2)·readback.
- **롤백 행렬**: 같은 문서 §5.7 — failure(원복 대상: **앵커 sha 값**; `ref: main` 복원은 금지) · unknown(freeze 유지·조사) · 성공 선언은 readback 관측으로만.
- 세대 판독 채널은 E1–E4(`admission-generation.md` §6)를 따른다.

## 8. S1 장소와 수용 조건

- **장소(venue)**: `h4-routing-measure.yml` **dispatch 실험 브랜치** — `experiment=` 입력에 신규 실험 분기로 후보를 실행한다(dispatch-only 측정판 — required check 아님, H4 프로토콜의 측정판 원칙: `docs/evidence/h4_routing_protocol.md` §4-(c)). **`probe-merge-queue`는 동결(FROZEN) 상태로 유지** — 본 워크스트림이 사용하지 않는다.
- **후보(candidate) = 실제 production-shaped matrix 코드** — 실험 전용 단순화 판이 아니라, S2가 승격할 그 코드 그대로를 후보로 실행한다(측정 대상과 승격 대상의 동일성 — 대리 판 금지).
- **수용(acceptance) = 3항 전부**:
  1. 양 레인이 실제 GO 테스트에서 **EXECUTED green**(§2-iv — REUSED 불산입);
  2. **injected-failure 런에서 양 레인의 증거가 모두 수집됨** — `fail-fast: false`의 실증 관측(실패 레인과 성공 레인의 로그가 동시에 존재);
  3. **집계 fail-closed** — injected failure가 집계 required check RED로 전파됨을 관측.

## 9. 검증 가능성 (GET-only 재현)

```bash
gh pr view <본 PR> --json state,mergedAt,mergeCommit        # 본 사전등록의 착지·확정 시점
gh pr view <S2 승격 PR> --json state,mergedAt,mergeCommit   # 세대 전환 시점 (T_promotion — §4.3 명령의 --since 입력)
tools/ci/golive_detect.sh --since <T_promotion> --tws-sha <신 TWS> --out data/merge_latency/golive_g2matrix
tools/ci/merge_latency_audit.sh --runs @data/merge_latency/golive_g2matrix.post_golive.ids \
  --out data/merge_latency/g2matrix_AFTER   # §5 (a)(b)(c) 판정 입력 데이터셋
gh api orgs/Archright/rulesets/24233738      # rollback anchor readback (§7)
```

---

*본 문서는 후보 실행(첫 production-shaped matrix 런) 이전에 고정되었다. 결과를 본 뒤의 규칙 변경은 어떤 형태로도 허용되지 않는다 — 변경은 새 날짜의 사전등록 문서로만 한다.*

---

## §10. 측정-정의 보존 적응 재결 (Q1·Q2) — 2026-10-16 (append-only adjudication)

> **성격**: 본 절은 착지 이후 추가된 append-only 재결 기록이다. §1–§9의 고정 본문은 한 글자도 변경하지 않는다. S3 동결 명령 드라이런(PR #864 — 첫 production MG 관측 amendment, MERGED 2026-10-16T02:33:57Z)이 **질문으로만 기록하고 적용하지 않은** 2건의 측정-정의 보존 적응(no-peeking 규율상 부모 판정 유보 항목)에 대한 재결이다. 재결 근거 = PR #864 드라이런 원문 기록(런 38805085401 관측). 본 재결은 관측 후 기준 변경이 아니다 — 동결 명령이 **매트릭스 형상에서 1차값 수집에 실패**함을 드라이런이 정확히 재현했고, 본 절은 그 수집 채널의 완결·적응만 판정한다(값 정의·창 의미론·합격 기준 불변).

### Q1 — golive 동결 명령의 `--until` 누락 → **APPROVED** (완결형으로 수집)

- **드라이런 관측 (PR #864)**: §4.3 동결 텍스트 그대로의 `golive_detect.sh` 호출은 필수 `--until` 누락으로 **FAIL exit 2** — 명령이 창의 끝 경계 입력 없이는 실행 불가. `--until`(수집 시각)을 보강한 **완결형은 PASS** — 창 내 2런 분류, boundary=38805085401@20:49:46Z, post=[38805085401].
- **재결**: `--until` 부재는 명령의 **불완결성(incompleteness)**이지 창 정의의 변경이 아니다. 수집 시각 타임스탬프를 채워 명령을 완결하는 것을 **승인**한다. **창 의미론·등식 불변** — `--since <T_promotion>` … `--until <수집시각>`의 반개방 창과 런 분류 규칙(boundary/post 구분, 승격 PR 제외)은 §4.3 그대로 유지된다.
- **실행 의무**: S3 실행자는 완결형만 사용하며, `--until`에 사용한 수집 시각을 산출물 metadata·기록 문서에 함께 남겨 창 재현 가능성을 보존한다.

### Q2 — D4 추출기의 레인-어웨어 job 소싱 → **APPROVED** (수집 채널 적응)

- **드라이런 관측 (PR #864)**: (i) `merge_latency_audit.sh --runs @…` **PASS exit 0**이나 `go_step=null`·`UNKNOWN_LOG` — GO 스텝의 lane job 이동을 fail-closed로 기록; (ii) `go_critical_parallel_extraction.sh runs …`는 기계적 exit 0이나 **D4 전부 NA**(`go_mode=none`) — **동결 명령이 매트릭스 형상에서 1차값 수집에 실패하는 것의 정확한 재현**; (iii) D4 로그 1차값 경로(레인 job 로그 + `duration_ms` grep, §4.3 명령)는 **PASS** — LANE `duration_ms` 4행 전수 추출.
- **재결**: D4의 1차 값 정의(§4.1 — attest job 내 `[check] GO-critical` 스텝 duration: steps[] `started_at`→`completed_at` **또는 로그 라인 1차값**)와 합격 기준의 D4-parallel-composite(§5 (a) — `max(lane-0 GO, lane-1 GO) + per-lane setup`)은 **이미 matrix 형상으로 정의되어 있다** — 값 정의의 변경은 없다. 배치 추출기의 job 소스를 레인 job으로 확장하는 것은 **수집 채널 적응**이며, §4.1이 애초에 인정한 로그 라인 1차값 경로(레인 job 로그의 `duration_ms`)와 **동일한 1차값**에 도달한다. **승인**한다. **1차 값 정의 불변.**
- **범위 포함 (audit steps-matcher)**: `merge_latency_audit.sh`의 steps-matcher도 동일 취지의 **레인-어웨어 job 소싱**으로 확장한다(레인 job에서 GO 스텝을 소싱 — `go_step=null` fail-closed 기록의 해소). 이는 D4-parallel-composite과 audit 수치가 동일 소스에서 나오는 일관성을 유지하기 위한 것이며, 감사 판정 규칙 자체는 변경하지 않는다.
- **경계**: 본 재결은 측정 정의(§4.1)·합격 기준(§5)·비용 회계(§6)를 변경하지 않는다. 도구 구현 변경은 별도 차량에서 수행하며, 본 문서는 판정만 등록한다(Reporter — Authority ≠ Adapter 유지).
