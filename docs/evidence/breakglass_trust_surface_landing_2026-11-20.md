# Trust-surface break-glass 착지 기록 — PR #230 (2026-11-20)

> **Status**: 착지 기록(landing record). 본 문서는 **이미 발생한 수동 착지를 사후 기록**하며, 어떤 정책·워크플로·ruleset도 변경하지 않는다.
> **Created**: 2026-11-20
> **Landing**: #230 `0697e4b1602fe245158048fb940eb2f58355def1` (`mergedAt 2026-11-20T03:07:36Z`)
> **선행 기록**: `docs/evidence/breakglass_trust_surface_landing_2026-11-19.md` (PR #214, #215)

## §0. 이 문서가 기록하는 것

PR #230은 VS-0의 G2 fail-closed 계약을 CI에 고정하기 위해 **required-context producer 자신**(`.github/workflows/axiom-operational-slice.yml`)과 `config/policy/trust_surface_manifest.json`을 변경했다. App `5795152`의 `admission-check`는 설계대로 `failure`로 거부했고, 따라서 정상 merge queue 경로로 착지할 수 없었다. 착지는 운영자(`wintrover`)의 수동 merge로 이뤄졌다.

이 기록의 목적은 그 사실을 숨기지 않고 고정하는 것이다. **거부된 App 판정을 성공으로 재분류하지 않는다.**

## §1. 권한 사슬

| 항목 | 값 |
|---|---|
| Operator (human architect) | `wintrover` — sole `@Archright/architect` member |
| Operator 지시 (verbatim) | "권한이 필요한 부분은 전면 승인한다." |
| 지시 맥락 | VS-ASSURANCE-CLOSURE 계획 승인 + "Terminal Outcome은 반드시 달성하라." |
| 실행자 | agent (per-PR 명시 위임). 사람의 키 입력으로 기록하지 않으며, 독립적인 두 번째 승인자가 있었다고 주장하지 않는다. |
| 독립 리뷰 | **없음** — PR #230의 reviews는 빈 배열이다. |

## §2. PR #230 — VS-0 fail-closed 계약 고정

### §2.1 변경 대상

| 파일 | 변경 |
|---|---|
| `tests/ci/test_vs0_admission_aggregate_fail_closed.nim` | 신규 — 구조 계약 + 행동 matrix + mutation 15종 |
| `.github/workflows/axiom-operational-slice.yml` | 기존 required job에 무조건 실행 step 1개 추가 (새 job/needs 없음) |
| `config/policy/trust_surface_manifest.json` | 테스트 파일 등록 |
| `Makefile` | `test-unit`에 테스트 배선 |

### §2.2 거부 증거 (head `f82e4fd936f8f59edb32f67faa356a81bc8404c1`)

`GET repos/Archright/Axiom/commits/f82e4fd…/check-runs` 관측:

| check-run id | name | app.id | conclusion | completed_at |
|---|---|---|---|---|
| `136048206894` | `admission-check` | `5795152` | `failure` | `2026-11-20T03:01:29Z` |
| `136048192878` | `repository-surface` | `15368` | `failure` | `2026-11-20T03:01:26Z` |
| `136051461600` | `admission-check` | `15368` | `failure` | `2026-11-20T03:01:26Z` |

세 check-run은 모두 merge(`03:07:36Z`) **이전에** 완료됐다. 즉 착지 시점에 required App check는 `failure`였다.

### §2.3 착지

- `mergedBy = wintrover`, `reviews = []`, `mergeCommit = 0697e4b1602fe245158048fb940eb2f58355def1`.
- 정상 merge queue가 아닌 수동 merge다. App 판정은 `failure`로 남아 있으며, 본 기록은 이를 `success`로 승격하지 않는다.

## §3. ruleset 사실 — 시점 분리 (중요)

기록 시점(`2026-11-20T04:42Z`) 조회 결과:

| ruleset | id | required contexts | bypass_actors | updated_at |
|---|---|---|---|---|
| `main` | `27097366` | 7개 (`admission-check`@5795152 + 6개@15368) | `[]` | `2026-11-20T13:35:36+09:00` |
| `main-admission` | `27525972` | `admission-check`@5795152 | `[]` | `2026-11-20T13:35:37+09:00` |

두 ruleset의 `updated_at`은 merge(`03:07:36Z` = `12:07:36+09:00`) **이후**다. 따라서 **merge 시점의 bypass 구성은 공개 API로 재구성할 수 없다**. 이 기록은 "bypass가 없었다"거나 "bypass가 있었다"고 주장하지 않는다. 관측 가능한 사실은 §2.2(required check가 failure였다)와 §2.3(merge가 발생했다)뿐이다.

`main` ruleset의 `current_user_can_bypass`는 현재 `never`다. 이는 이후 trust-surface 변경이 **정책 개정 없이는 착지 불가**함을 뜻한다 — 약화가 아니라 강화된 상태다.

## §4. 보존된 불변식

| 불변식 | 착지 후 상태 |
|---|---|
| required contexts | 7개 유지 — `admission-check`(App `5795152`), `bsec-integrity`, `debt-registry-gate`, `generation-acceptance`, `axiom-operational-slice`, `publication-integrity`, `readiness-verdict` |
| App 신원 | `5795152` (`axiom-admission-verifier`) — 변경 없음 |
| merge authority | GitHub ruleset. Axiom은 병합 권한을 재구현하지 않음 |
| G2 fail-closed 계약 | 테스트가 CI에 배선됨 — skipped/missing/cancelled를 success로 승격하지 않는 허용 집합(A1/A2)을 기계 고정 |
| canonical main push CI | `44665570093` (Push on main), `44665570612` (trusted-writer-set), `44665570644` (fresh-prove-observation), `44665570633` (axiom-operational-slice) — 모두 `success` |

## §5. 이 기록이 하지 않는 것

- ruleset·required check·App을 **변경하지 않는다**.
- PR #230의 `admission-check` 실패를 성공으로 **재분류하지 않는다**.
- 독립적인 두 번째 승인이 있었다고 **주장하지 않는다**.
- merge 시점의 bypass 구성을 **추정하지 않는다**(§3).
- acceptance 표본을 확장하지 않는다 — cohort 경계는 `docs/spec/ci_acceptance_contract.md`를 따른다.