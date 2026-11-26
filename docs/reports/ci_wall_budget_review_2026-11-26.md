# CI 벽시계 예산 검토 기록 — 제안된 "Evidence-First Incremental CI"의 반박과 채택 범위

> **목적**: "검증 기능을 계속 늘려도 CI를 10분 이내로 유지할 수 있는가"라는 질문에 대해 제출된
> 설계안(diff-scoped 실행 → L0/L1/L2 티어 → input_closure_digest 기반 Evidence CAS → license
> scan 재사용을 첫 슬라이스로)을 저장소 실측과 외부 공식 문서로 반박하고, 채택 가능한 범위만
> 남긴다.
> **일자**: 2026-11-26
> **방법**: 저장소 정본 문서·실측 데이터 대조, **Context7 MCP로 GitHub Actions / Bazel 공식
> 문서 원문 조회**(§2에 인용), 4개 독립 감사(CI 토폴로지 / 기존 기제 존재 검증 / license scan
> 실행가능성 / 헌법 비판).
> **결과물**: 이 기록은 **아무 권한도 만들지 않는다**. 규범 규칙은
> `docs/spec/ci_admission_budget_contract.md`가 소유하며, 이 문서는 그 규칙이 어떤 근거로
> 성립했는지를 남기는 감사 기록이다.

---

## 1. 판정 요약

| 제안된 주장 | 판정 | 근거 |
|---|---|---|
| 증거 재사용(Proof Unit + `input_closure_digest` CAS)은 새 아키텍처다 | **기각 — 이미 존재하고, 신규 구축은 금지 사항** | `src/verification/evidence_cas.nim` (SL-15), `src/verification/judgment_cas.nim` (4개 GO-critical 과목), `src/gate/orchestrator/hook/memo.nim` (gate memo). `docs/spec/verification_dag_contract.md:19` "제로베이스 planner/CAS 신규 구축"은 **비목표**, `:130`은 금지 사항으로 열거 |
| diff/impact 스코프로 무관 변경을 스킵 | **기각 — GitHub 의미론상 교착 또는 무음 통과** | required 워크플로를 `paths:`로 스킵 → 체크가 Pending → 머지 차단. 잡을 `if:`로 스킵 → **"Success"로 보고**(required여도 통과). 저장소도 동일 함정을 이미 명문화 |
| CI 누적(게이트 수)이 벽시계 상승의 원인 | **기각 — 고정 프로비저닝이 지배** | composite가 `runnerSeconds`의 **84%**(run `44521587339`: 1080/1286), `install_extract` 899.5/1076.6s. 레인 재배치 최대 이득 2–4s → **VS-CI-01 REJECTED** |
| `Operational slice 341s = 생산 132s + 판정 209s` | **기각 — 금지된 합산** | `docs/spec/ci_critical_path_metric.md` §2.1: 서로 다른 워크플로의 `wallSeconds`는 더하거나 max-fold하지 않는다. `T_exec`은 `T_verify + T_publication`이며 다섯 번째 phase가 아니다 |
| 10분 상한을 "설계"할 수 있다 | **조건부 — 이미 초과 상태이고, 초 단위 예산은 판정 입력이 될 수 없다** | `T_admission` p50 **639s**, p90 694.8s, max 718s (n=5). 그리고 `docs/spec/productization_contract.md:177`: 하드웨어 의존 wall-clock은 PASS/FAIL/UNKNOWN을 뒤집지 못한다 |
| license scan 재사용이 "가장 안전한 첫 슬라이스" | **기각 — 벽시계 기여 0 + 착지 비용 최대** | publication-integrity는 관측된 어떤 사이클에서도 last finisher가 아니다. 게다가 trust-surface 경로이고, 스캐너 핀은 버전 문자열뿐이라(DEBT#567) 키가 hermetic하지 않다 |
| 캐시를 증거 저장소로 사용 | **기각** | `src/verification/evidence_ledger.nim` "cache is acceleration, never evidence". GitHub 캐시는 10GB/저장소, 7일 미접근 축출, PR 캐시는 merge ref 스코프, 복원물은 untrusted |
| 입력 digest만 일치하면 결과 재사용 가능 | **전제 미충족** | 게이트 다수가 git history·host path에 의존해 전 게이트의 건전한 클로저 digest를 오늘 계산할 수 없다. Bazel 문서: 미선언 입력은 *incorrect incremental build*, 공유 캐시의 나쁜 엔트리는 팀 전체 오염 |

## 2. 외부 공식 문서로 확인한 사실

1. **경로 필터는 required check를 교착시킨다.** GitHub Actions 문서(Manage workflow runs →
   Skipping workflow runs): 워크플로가 path/branch 필터로 스킵되면 "checks associated with that
   workflow will remain in a **Pending** state. A pull request that requires those checks to be
   successful will be **blocked from merging**."
2. **잡 스킵은 성공으로 보고된다.** 같은 문서 계열(Control jobs with conditions): "A job that is
   skipped will report its status as **'Success'**. It will not prevent a pull request from
   merging, even if it is a **required check**."
   → 두 사실이 합쳐지면 diff-scoped 티어링은 **양쪽 끝이 모두 고장**이다: 워크플로 수준에서는
   교착, 잡 수준에서는 무음 통과.
3. **캐시는 증거 저장소가 될 수 없다.** Dependency caching 문서: 기본 10GB/저장소, 7일 미접근
   엔트리 제거, PR이 만든 캐시는 merge ref(`refs/pull/.../merge`)에 생성되어 **그 PR의 재실행만**
   복원할 수 있고 base 브랜치나 같은 base를 보는 다른 PR은 복원할 수 없다, 복원된 파일은
   untrusted input으로 취급. (방향에 주의: PR 실행이 *default 브랜치* 캐시를 복원하는 것은
   허용된다 — 툴체인 캐시가 동작하는 이유이며, 동시에 증거 재사용이 캐시를 탈 수 없는 이유다.
   신뢰 방향이 반대다.)
4. **증분 재사용의 건전성 조건.** Bazel sandboxing 문서: 미선언 입력이 있으면 Bazel은 최신이라고
   잘못 판단해 *incorrect incremental build*를 만든다. 공유 캐시의 잘못된 엔트리는 모든 개발자에게
   영향을 준다("a bad cache entry in a shared cache affects every developer on the project").

위 4개는 2026-11-26에 Context7 MCP(`/websites/github_en_actions`,
`/bazelbuild/bazel`)로 조회한 원문과 일치함을 확인했다. 저장소 실측으로 반박되지 않은 외부
주장은 이 4개가 전부이며, 나머지 판정(§1)은 저장소 정본에 근거한다.

## 3. 저장소 실측 (정본)

| 수치 | 값 | 출처 |
|---|---|---|
| `T_admission` (n=5) | p50 **639s**, p90 694.8s, min 588, max 718 | `docs/evidence/ci_admission_measurement_2026-11-24.md` |
| phase 분해 | queue 3% · **verify 94%** · publication 0% · merge 2% | same |
| last finisher | `readiness-verdict` **4/5**, `publication-integrity` 0/5 | same |
| publication slack | 139s (#415) / 208s (#416) → 제거 효과 **T_admission 기준 0** | same |
| `wall` / floor / ceiling (n=10) | 513s / 435s(85%) / 78s, **2/10에서 0** | `data/ci_optimization/admission_latency_2026-11-24/slack_reconciliation.md` |
| serial chain (#415) | 533s = slice job 304s + readiness 227s, 프로비저닝 **114s(21.4%)** | same, §"Where the time actually goes" |
| `Prove, replay the same certificate` | 205s (#415), 277s (#416) = 체인의 38–48% | same |
| 프로비저닝 비중 | composite 84% of runnerSeconds (run 44521587339, 1080/1286); `install_extract` 899.5/1076.6s; `libpcre3` 설치 1542.1s/40회(79% fetch) | `data/ci_optimization/ci_provisioning_decomposition_2026-11-20/summary.json` |
| 프로비저닝 cohort 비중 | provisioning family 2574s / step-seconds 4669s = **55.1%** (n=5) | `data/ci_optimization/ci_critical_path_baseline_2026-11-20/summary.json:145-147` |
| A-layer exact HIT 비용 | **~28.3s** — 히트율을 더 올려도 이 바닥 이하로 못 내려간다 | `docs/evidence/ci_admission_measurement_2026-11-24.md` |
| 레인 재배치 | 최대 이득 2–4s, lane당 고정 ~110s → **REJECTED** | `data/ci_optimization/vs_ci_01_lane_rebalance_decision_2026-11-22.json` |
| SLO of record | **480s P95**, 정책이며 헌법 불변식 아님, 이미 p50에서 위반 | `docs/evidence/ci_wall_clock_optimization_acceptance_2026-10-07.md` |

## 4. 채택 / 기각

**채택**

- 비용은 검증기 총수가 아니라 **무효화된 증거량**에 비례해야 한다는 원리 — 단, 이는
  `runnerSeconds` 법칙이며 `T_admission` 법칙이 아니다.
- 누락·불확실은 `PASS`가 아니라 `UNKNOWN` (`docs/spec/merge_admission_controller.md:57`
  "missing ≠ valid empty").
- 3계층 발상 — 이미 `venue split`(ADR-0043: `pull_request`=preflight `{secret-scan}`,
  `merge_group|schedule|dispatch`=landing 전체)으로 착지해 있다. 티어 선택 기준은 **비용이
  아니라 비가역성**이다.

**기각**

- diff-scoped skip set (교착/무음 통과, `Makefile:1515`가 이미 자동 선택을 금지).
- 초 단위 예산의 판정 입력화 (`productization_contract.md:177`, VM 간 1.4–1.5× 편차).
- "600초를 10분 상한의 완성"으로 표현하는 것 — 600초는 SLO가 아니라 **상한**이며, SLO of
  record(480s P95)를 대체하지 않는다. 600초를 목표로 삼으면 기존 약속을 조용히 낮추는 셈이다.
- license scan 재사용을 첫 슬라이스로 삼는 것 (효과 0, 착지 비용 최대, 키 비hermetic).
- 신규 Evidence CAS / planner 구축 (`verification_dag_contract.md:19`, `:125`, `:130`).

**계보 — 이 저장소는 이미 이 설계를 시도했고, 계약이 폐기됐다**

제안서의 L0/L1/L2 티어와 증분 재사용은 새 발명이 아니다. ADR-0017(증분 검증 엔진)과
ADR-0019(검증 티어 스케줄링)가 Work Unit W1–W11 모델, `inputClosure`, "provably false일
때만 skip" 규칙, L0/L1/L2 안전 사다리를 이미 정의했고, `tools/ci/impact_closure_selector.nim`이
그 셀렉터를 **shadow mode**(게이트를 실행하지 않고 리포트만 산출)로 구현해 남아 있다.

중요한 사실은 그 정본 계약 `docs/spec/incremental_ci_contract.md`가 **CI=0 cutover
(2026-09-20)로 삭제**되었고, `data/selector_soundness/mutation_catalog.json:170`이 이를
"surviving normative contract인 `docs/spec/productization_contract.md`로 재배정"했다고
기록한다는 점이다. 즉 이 축은 **계약 없는 도구**로 남아 있다. 따라서 본 작업은 삭제된 계약을
부활시키지 않고, **필요한 최소 조각(required context 위의 배치 규칙)만** 새 정본에 담았다.

부수 발견(수정하지 않음, 범위 밖): `tools/ci/IMPACT_CLOSURE.md:5`가 삭제된 그 계약을 여전히
정본으로 인용하는 dangling 참조이며, `data/debt_registry.json`에 미등재다(같은 파일을 가리키는
DEBT#468은 `canonical_execution_semantics.md` 쪽만 등재).

## 5. 이 기록이 주장하지 않는 것

- **분포를 주장하지 않는다.** n=5와 n=10은 첫 운영 창이며, p90은 산술값이다. SLO 주장에는
  metric §1.2의 `n≥20`이 필요하다.
- **개선을 주장하지 않는다.** 이 작업은 측정·규칙화만 했고 어떤 최적화도 적용하지 않았다.
- **`Prove` 스텝의 205–277s는 여전히 미귀속이다.** 체인의 38–48%인데 스텝 단위 원인 분해가
  없다. 이 계약 위에서 어떤 예산 주장도 하기 전에 그 측정이 선행되어야 한다.
- **사용자가 체감하는 대기는 `T_admission`보다 길다.** end-to-end 꼬리는 이벤트·인간 대기가
  지배하며, 어떤 CI 상한도 그 값을 한정하지 않는다.

## 6. 권한 변화

없음. 이 기록은 verdict·gate·check·required context를 추가하지 않으며,
`config/policy/merge_admission.json`의 7개 required context와 trustSurface를 변경하지 않는다.
Phase 2(중복 프로비저닝 제거)는 trust-surface 파일을 건드리므로 별도의 architect/rotation
경로가 필요하다.

## 7. 후속 착지 기록 — Phase 3 (R2/R3 기계적 강제)

계약 §9.2의 Phase 3를 같은 작업에서 착지했다. 새 게이트·체크·required context·Makefile
타깃은 만들지 않았고, 이미 required인 `bsec-integrity` 안에서 실행되는
`tools/ci/validate_workflow_shell.sh`(BASE 사본)에 술어를 추가했다 — 계약 §4 R1 형식 (a)이므로
한계 벽시계 비용은 0이다.

- **강제됨**: required 워크플로의 `paths` / `paths-ignore` / `branches-ignore` (R2),
  required **잡**의 `if:` 화이트리스트 — absent / `always()` / `!cancelled()` / 그 `&&` 결합 (R3).
- **강제되지 않음(문서에 locus로 명시)**: allow-list **커버리지**(트렁크 포함 여부)와 R1의
  headroom 조건. 트렁크 정본이 정책에 없고 두 번째 설정을 만드는 것이 R2가 금지하는 바로 그
  행위이기 때문이다. 이 잔여의 실패 모드는 무음 통과가 아니라 **눈에 보이는 Pending 교착**이다.
- **검증 증거**: 셀프테스트 판정 행렬 8/8(금지 필터 → FAIL, 이접 `if:` → FAIL, `always() &&
  !cancelled()` / `always()` / `!cancelled()` / absent → PASS, 비-required 파일 동일 필터 →
  PASS), 실제 `bsec-integrity.yml` 외부 변이 2종(각각 FAIL + `<required-context-rules>` 귀속),
  무변이 대조군 0건.
- **남은 전제**: 이 스크립트는 아직 `trustSurface`에 없다. BASE 사본이 후보를 판정하므로
  후보 PR의 약화는 그 PR에 대해 무력하지만, **착지된 약화는 다음 PR의 BASE**가 된다. 등재는
  `config/policy/merge_admission.json`(그 자체가 trust-surface) 개정이므로 architect/rotation
  레인 소관이며, 본 변경에 묶지 않았다.