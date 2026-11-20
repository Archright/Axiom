# CI 성능 기준선 — cohort A (2026-11-19)

> **Status**: 기준선 기록(baseline record). 본 문서는 측정값만 기록하며, 어떤 워크플로·정책·임계값도 변경하지 않는다.
> **Created**: 2026-11-19
> **Cohort**: `docs/spec/ci_acceptance_contract.md` 의 cohort A (boundary `aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356`, n=5)
> **선행 증거**: `docs/evidence/supply_policy_registration_2026-11-19.md`, `docs/evidence/breakglass_trust_surface_landing_2026-11-19.md`

## §0. 목적

W6(성능 최적화)은 **측정 정의를 먼저 고정한 뒤** 수치로 판정한다. 본 문서는 그 기준선이다. acceptance 판정은 이 문서가 아니라 수용 계약과 수집기(`tools/ci/ci_acceptance_collect.nim`)가 수행하며, 본 문서의 수치는 **최적화 전후 비교용**이다.

## §1. 측정 정의 (고정)

| 지표 | 정의 | 정본 소스 |
|---|---|---|
| canonical merge latency | terminal attempt의 job들 중 `started_at`·`completed_at`이 모두 있는 job에 대해 `max(completed_at) − min(started_at)` | 수용 계약 §6, collector `latency.p50_seconds` |
| legacy wall (비정본) | terminal attempt의 `updated_at − run_started_at` | collector `latency.legacy_p50_seconds` (연속성 보고 전용) |
| runner-seconds | terminal attempt의 각 job `completed_at − started_at`의 **합** | Actions jobs API (`/attempts/{n}/jobs`) |
| supply step 실행 수 | 이름에 `setup-axiom-toolchain`을 포함하는 step 수 (composite action 호출 지점) | Actions jobs API `steps[]` |
| supply 실패 빈도 | `setup-axiom-toolchain` step의 `conclusion = failure` 수 | 동일 |
| external_dependency 빈도 | collector 분류 `external_dependency` entry 수 | collector report |

기존 문서의 546/560/574.5초는 legacy 공식(`updated_at − run_started_at`)으로 계산된 값이다. 위 canonical 공식과 **다른 측정값**이므로 서로 대체할 수 없다.

## §2. cohort A 실측 (n=5)

수집 명령(읽기 전용):

```
./bin/ci_acceptance_collect --repo Archright/Axiom \
  --boundary aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356 \
  --window 20 --mode initial --out /tmp/acc-cohortA-v3
```

결과 요약(collector 출력 그대로):

```
mode=initial status=INCOMPLETE window=5/20 shortfall=15 excluded_before_boundary=16
counts: success=3 legitimate_policy=0 internal_defect=0 unclassified=0
        external_dependency_blocked=2 recovered_degradation=0 cancelled_superseded=0
latency canonical n=5 p50=574.0s mean=598.8s min=430s max=763s
latency legacy    n=5 p50=578.0s mean=601.2s
accepted=false predicate_holds=false observation_complete=true
```

| run_id | entry wall (s) | job wall (s) | runner-seconds | supply steps | supply 결론 |
|---|---:|---:|---:|---:|---|
| 44519217624 | 708 | 708 | 1366 | 9 | success 8, skipped 1 |
| 44521587339 | 763 | 763 | 1282 | 9 | failure 4, success 3, skipped 2 |
| 44542633420 | 430 | 430 | 818 | 9 | success 8, skipped 1 |
| 44548437642 | 519 | 519 | 854 | 9 | success 8, skipped 1 |
| 44553449785 | 574 | 574 | 979 | 10 | success 9, skipped 1 |

측정 명령(읽기 전용, job span·step 집계):

```
gh api "repos/Archright/Axiom/actions/runs/<run_id>/attempts/1/jobs?per_page=100" --paginate
```

## §3. 기준선 수치

| 지표 | 값 (n=5) |
|---|---|
| canonical p50 | **574.0 s** |
| canonical mean | 598.8 s |
| canonical min / max | 430 s / 763 s |
| legacy p50 (비정본) | 578.0 s |
| runner-seconds p50 | **979 s** |
| runner-seconds mean | 1059.8 s |
| supply step 실패 빈도 | 4회 / 5 entry 중 1 entry (20%) |
| external_dependency entry | 2 / 5 (40%) |

n=5는 수용 창(20)에 미달하므로 **수용 판정용 기준선이 아니라 최적화 비교용 사전 기준선**이다. 수용 계약의 `baseline-live` 재유도 값(n=40, canonical p50 558.0 s)은 계약 문서에 별도로 기록되어 있다.

## §4. 공급 복구 착지 후 참조점 (비수용)

`64d0fe2` canonical main push의 `axiom-operational-slice` job(수용 entry가 아님):

- 공급 step: `Install system deps (canonical system_deps parity — libpcre3)` → `outcome=success`, `duration_ms=38236`.
- 사용 tier: **tier 1** (기본 apt 소스에 고정 버전 `2:8.39-15build1` 직접 설치). tier 2/3 메시지 없음, `external_dependency` 없음, 최종 `ldconfig` 확인 성공.

tier 2(Release asset)와 tier 3(공식 미러 순회)는 로컬 하네스(`sudo`/`ldconfig` 스텁)에서 검증되었다: 정상 설치, 자산 변조 시 `sha256 mismatch` 후 다음 tier로 이행, 전 tier 실패 시 `external_dependency` 종료. 실제 운영에서의 tier 2/3 발동은 후속 cohort에서 관측 대상이다.

## §5. 최적화 시 지켜야 할 경계

- runner-seconds와 wall latency를 **함께** 본다(한쪽만 개선하고 다른 쪽을 악화시키지 않는다).
- 공급 실패를 성공으로 바꾸는 방식의 "개선"은 금지한다(fail-closed 유지).
- 캐시는 속도만 담당한다. 판정 근거로 사용하지 않는다.
- merge-group admission에는 일반 concurrency cancellation을 적용하지 않는다(검증 대상 생명주기 훼손 방지).