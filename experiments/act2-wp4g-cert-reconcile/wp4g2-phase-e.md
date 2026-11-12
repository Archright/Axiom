# WP4-g.2 완료 문서화 — `ax cert reconcile` 실측 (Phase E)

> **실험 ID**: `act2-wp4g-cert-reconcile`
> **본 문서 역할**: WP4-g.2(`act2-wp4g-cert-reconcile`) 완료를 기록한다. WP4-g(전체) 완료나 다음 WP 시작을 강제하지 않는다.
> 모든 수치는 실측 결과를 그대로 기록한 것이며, 추측은 포함하지 않는다.

---

## Question

WP4-g.2에서 구현·검증된 `ax cert reconcile` 원시(--check/--apply, --cert 스코핑, all-or-nothing)가 의도한 대로 동작하는가? 특히 tracked reference cert의 재물질화, kernel 정규화, AMBIGUOUS 분류, stale_cert_gate 연동이 실제 환경에서 관측 가능한가?

## Context

- **PROJECT_UNDER_TEST**: Axiom CLI (`.`)
- **PROJECT_REVISION**: `089251924` (HEAD, `feat/act2-external-verification` 브랜치)
- **AXIOM_REVISION**: `feat/act2-external-verification` 워크트리
- **AXIOM_CONFIGURATION**: WP4-g.2 (`act2-wp4g-cert-reconcile`) — `src/verification/cert_reconcile.nim`, `src/cli/cert_cli.nim`, `tests/unit/cert_reconcile_test.nim` (24/24 PASS)
- **TOOLCHAIN_IDENTITY**: Nim 2.2.10 [Linux: amd64]
- **EXPERIMENT_ID**: `act2-wp4g-cert-reconcile`
- **VERIFICATION_SCOPE**: `ax cert reconcile` CLI 원시의 --check/--apply, --cert 스코핑, all-or-nothing 동작, stale_cert_gate 연동
- **참조 문서**: `docs/spec/cert_lifecycle_contracts.md` §7, `experiments/act2-wp4g-cert-reconcile/wp4g-plan.md`, `experiments/act2-wp4g-cert-reconcile/wp4g0-authority-audit.md`

## Scope

- **포함**: `--cert f3d17f0e` 스코핑 --check/--apply, full --check/--apply, stale_cert_gate 연동, all-or-nothing 동작
- **제외**: 코드 로직 수정 (src/verification/cert_reconcile.nim, src/cli/cert_cli.nim 등 미수정), 새로운 기능 도입, WP4-g 전체 또는 다음 WP

## Procedure

아음의 명령을 순차적으로 실행하고 출력을 기록하였다.

### Step B — `--cert f3d17f0e --check`

```
ax cert reconcile --cert f3d17f0e --check
```

**실측 결과**: RESOLVED proximityScore commit `4b0301c13`, EXIT=0

### Step C — `--apply` (--cert f3d17f0e)

```
ax cert reconcile --cert f3d17f0e --apply
```

**실측 결과**: f3d17f0e.json content 재물질화 완료.
- sourceHash=`825f7f16...`
- kernel=`false`
- certZ3Candidate
- verificationTier=`z3-verified`
- trustCommitId=`4b0301c13...`
- solverStatus=`unsat`
- irHash=`891b6daee9...`

### Step D — `stale_cert_gate`

```
stale_cert_gate
```

**실측 결과**: EXIT=0 PASS

### Step E — full `--check`

```
ax cert reconcile --check
```

**실측 결과**: RESOLVED proximityScore + AMBIGUOUS 5건 → MATERIALIZATION_UNDEFINED, EXIT=2 (expected observation)

### Step F — full `--apply`

```
ax cert reconcile --apply
```

**실측 결과**: REFUSED exit 2, `.new` leftover 없음 (all-or-nothing 확인)

## Result

WP4-g.2 실측 결과를 요약하면 다음과 같다:

| Step | 명령 | EXIT | 판정 |
|---|---|---|---|
| B | `--cert f3d17f0e --check` | 0 | RESOLVED proximityScore, commit `4b0301c13` |
| C | `--cert f3d17f0e --apply` | 0 | f3d17f0e.json content 재물질화 (kernel=false, irHash=`891b6daee9...`) |
| D | `stale_cert_gate` | 0 | PASS |
| E | `full --check` | 2 | RESOLVED proximityScore + AMBIGUOUS 5건 → MATERIALIZATION_UNDEFINED |
| F | `full --apply` | 2 | REFUSED, `.new` leftover 없음 |

## Evidence

- **Step B**: `--cert f3d17f0e --check` → RESOLVED proximityScore commit `4b0301c13`, EXIT=0
- **Step C**: `--cert f3d17f0e --apply` → f3d17f0e.json content 재물질화 — sourceHash=`825f7f16...`, kernel=`false`, certZ3Candidate, verificationTier=`z3-verified`, trustCommitId=`4b0301c13...`, solverStatus=`unsat`, irHash=`891b6daee9...`
- **Step D**: `stale_cert_gate` → EXIT=0 PASS
- **Step E**: full `--check` → RESOLVED proximityScore + AMBIGUOUS 5건 (safeSpeedupRatioCore, calcDynamicTimeoutCore, clampTimeoutMs, normalizeMaxWorkers, firstBoolCore) → MATERIALIZATION_UNDEFINED, EXIT=2 (expected observation)
- **Step F**: full `--apply` → REFUSED exit 2, `.new` leftover 없음 (all-or-nothing 확인)
- **관련 문서**: `docs/spec/cert_lifecycle_contracts.md` §7.10.7 (5 AMBIGUOUS 표현 규정), §7.10.11 (kernel 정규화 규칙), §7.10.12 (--cert 스코핑 및 trackedCertName replace-in-place 세마닉스)

## Classification

- Step B/C/D: **Verified** — 의도한 대로 동작 (RESOLVED 재물질화, kernel=false, stale_cert_gate PASS)
- Step E: **Verified (expected observation)** — full --check에서 AMBIGUOUS 5건이 MATERIALIZATION_UNDEFINED로 분류되고 EXIT=2가 반환되는 것은 설계에 부합하는 예상 관측
- Step F: **Verified** — full --apply에서 all-or-nothing 정책이 적용되어 REFUSED exit 2, `.new` leftover 없음

## Interpretation

- **--cert 스코핑 정상 동작**: `--cert f3d17f0e`로 on-disk 파일명 prefix 매치 시, tracked reference cert가 1개 발견되어 RESOLVED proximityScore를 반환하고 EXIT=0이다. 매치 0 시 CERT_NOT_FOUND 반환코드 2가 설계에 부합한다.
- **trackedCertName replace-in-place semantics**: --apply 후 f3d17f0e.json 파일명은 유지되고 content만 교체되었다. content irHash는 새 evidence의 irHash(`891b6daee9...`)로 갱신되었다. 이는 tracked reference cert 파일명이 안정적 identity이고 재물질화는 content만 교체한다는 §7.10.12의 계약과 일치한다.
- **kernel 정규화**: --apply 후 kernel=`false`가 관측되었다. certZ3Candidate + leanCompilerVerified=true → kernel=false 규칙(§7.10.11)이 적용된 것으로 해석된다. 이 규칙은 legacy metadata를 표준화할 뿐 kernel 의미를 재정의하지 않는다.
- **5 AMBIGUOUS 분류**: full --check에서 proximityScore는 RESOLVED이지만, safeSpeedupRatioCore/calcDynamicTimeoutCore/clampTimeoutMs/normalizeMaxWorkers/firstBoolCore 5개는 run-residue AMBIGUOUS로 MATERIALIZATION_UNDEFINED로 분류되어 EXIT=2이다. 이는 §7.10.7의 5 AMBIGUOUS 표현 규정과 일치한다.
- **all-or-nothing**: full --apply에서 AMBIGUOUS 항목이 존재하면 전체 적용이 거부되어 REFUSED exit 2, `.new` leftover 없음이다. 이는 §7.10.5의 전체 vault 원자 트랜잭션 계약과 일치한다.
- **stale_cert_gate 연동**: --apply 후 stale_cert_gate가 EXIT=0 PASS를 반환한다. 이는 reconcile로 f3d17f0e.json이 재물질화된 후 stale 상태가 해소되었음을 의미한다.

## Non-Conclusions

- 이 phase-e는 WP4-g.2 완료만을 기록한다. WP4-g(전체) 완료나 다음 WP(WP4-h 등) 시작을 강제하지 않는다.
- Step E의 EXIT=2는 오류가 아니라 설계에 부합하는 예상 관측(expected observation)이다. AMBIGUOUS 5건이 MATERIALIZATION_UNDEFINED로 분류되어 부분 적용이 불가능한 것이다.
- Step C의 kernel=`false`는 certZ3Candidate에 대한 kernel 정규화 결과이다. 이것이 kernel 의미의 재정의가 아니라 legacy metadata 표준화임을 §7.10.11에서 명시한다.
- Step F의 REFUSED는 all-or-nothing 정책의 정상 동작이다. `.new` leftover가 없음으로 원자적 폴백이 수행되지 않았음을 확인한다 (§7.10.5).
- 특정 명령의 정확한 stdout/stderr 출력은 본 문서에 기재하지 않는다 (추측 방지). 실제 터미널 출력은 CI/실험 기록에서 확인 가능하다.
