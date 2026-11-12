# GO-critical admission 테스트 실측 비용 — s1a 포함 per-test 분해 (2026-10-08)

> **종류**: 측정 증거 (AGENTS.md §0.11 — 숫자는 원 계산 경로에서 기록).
> **측정 대상**: `admission-gate`(merge_group·pull_request) 런의
> `attest / admission-check` job 내 스텝
> **`[check] GO-critical admission tests (DEBT#432 — isVkdAdmissible/S1A/D2, fail-closed)`**
> (`.github/workflows/admission-check.yml:751` — DEBT#432 Slice B로 배선된 4종:
> `tests/unit/proof_integrity_test.nim` · `tests/unit/test_s1a_lean_golden.nim` ·
> `tests/unit/test_d2_golden.nim` · `tests/unit/test_d2_persist.nim`).
> **소비처**: `docs/spec/test_judgment_cas_contract.md` (test-judgment 재사용 계약의 비용 근거).
> **측정일**: 2026-10-08 (실행 주체: wintrover 세션 — API 읽기 전용).

## 1. "309초" 수치의 출처 확정 (실측)

"≈309초"는 **`test_s1a_lean_golden` 단일 테스트의 소요**(컴파일+실행, `make test-fast-one`
1회)의 실측값이다. 오늘 실측 창에서:

- run `37749269681` (PR #599 merge_group): s1a = **310.0s** (08:27:32.331 → 08:32:42.307 UTC)
- run `37746719386` (PR #598 merge_group): s1a = **309.2s** (08:03:59.175 → 08:09:08.409 UTC)

즉 "309초" 류 수치는 스텝 총량이 아니라 **s1a 단일 per-test 소요**이며, 스텝(4테스트
합계)은 같은 런에서 516.6–518.9s였다. s1a는 7개 실측 런에서 bimodal(≈230s vs ≈300–310s)
분포를 보인다(절 §3) — 스텝이 러너 워밍 상태에 따라 395–519s로 변동하는 주요 원인이다.

## 2. 측정 방법 (재실행 가능한 원 계산 경로)

GitHub Actions REST API(읽기 전용) — run → job → step → raw log 순:

```bash
# (1) 대상 런 나열 — admission-gate(organization workflow, 본 저장소 기록 기준) 성공 런
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&per_page=20" \
  --jq '.workflow_runs[] | select(.path==".github/workflows/admission-gate.yml"
        and .conclusion=="success") | "\(.id)|\(.created_at)|\(.head_branch)"'
# pull_request 단계 런도 동일 (event=pull_request)

# (2) GO-critical 스텝이 발화한 job 특정
gh api "repos/Archright/Axiom/actions/runs/<RUN_ID>/jobs" \
  --jq '.jobs[] | select(.name=="attest / admission-check") | .id'

# (3) 스텝·잡·런 총량 (steps[] 타임스탬프)
gh api "repos/Archright/Axiom/actions/jobs/<JOB_ID>" \
  --jq '.steps[] | select(.name | startswith("[check] GO-critical")) | "\(.started_at)|\(.completed_at)"'

# (4) per-test 소요 — job raw log의 밀리초 타임스탬프로 RUN→PASS 구간
gh api --allow-escape-sequences "repos/Archright/Axiom/actions/jobs/<JOB_ID>/logs" \
  | grep -E "\[admission-tests\] (RUN|PASS)"
```

스텝 로그는 `make test-fast-one T=<file>` 4회 순차 실행(스텝 블록 admission-check.yml:751-775;
레시피 = Makefile:965-968 `$(NIM) c -r --hints:off -o:/tmp/opencode/ax-one "$(T)"`)이므로
**per-test 소요에는 테스트 바이너리 컴파일이 포함된다** — 이것이 실제 어드미션 경로의
비용 정의다. 교차 검증: 7개 런 모두에서 per-test 4합계와 API 스텝 구간이 ±0.5s 이내 일치.

## 3. 실측 표 (2026-10-08, 모두 UTC, 단위 초)

GO-critical 스텝이 발화한 성공 런 전수(오늘 창: merge_group 7건 + pull_request 1건 비교).
s1a = `test_s1a_lean_golden`, pi = `proof_integrity_test`, d2g = `test_d2_golden`,
d2p = `test_d2_persist`. 합계 = per-test 4합. 스텝/잡/런은 API 타임스탬프 차.

### 3.1 merge_group (큐 단계 — 착지 판정 런)

| run ID | PR | s1a | pi | d2g | d2p | 4합 | 스텝 | 잡 | 런 총계 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `37745040825` | #597 | 299.6 | 37.0 | 143.2 | 23.3 | 503.1 | 503 | 566 | 940 |
| `37745212881` | #596 | 232.6 | 32.0 | 112.5 | 18.9 | 396.0 | 396 | 490 | 882 |
| `37746719386` | #598 | **309.2** | 38.2 | 145.4 | 23.8 | 516.6 | 517 | 578 | 945 |
| `37749269681` | #599 | **310.0** | 38.1 | 147.3 | 23.5 | 518.9 | 519 | 582 | 981 |
| `37755752639` | #601 | 229.5 | 35.2 | 110.4 | 19.5 | 394.6 | 395 | 496 | 831 |
| `37756164747` | #602 | 233.6 | 31.3 | 112.0 | 18.1 | 395.0 | 395 | 498 | 855 |
| `37757818150` | #603 | 303.3 | 38.9 | 146.1 | 24.0 | 512.3 | 512 | 600 | 1028 |

### 3.2 pull_request (체크 단계 — 같은 head가 같은 날 재실행한 사례)

| run ID | PR | s1a | pi | d2g | d2p | 4합 | 스텝 | 잡 | 런 총계 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `37755662845` | #603 | 310.0 | 39.5 | 150.1 | 24.2 | 523.7 | 523 | 587 | 946 |

### 3.3 요약 통계 (merge_group 7건)

| 항목 | min | max | mean | median |
|---|---:|---:|---:|---:|
| **s1a (test_s1a_lean_golden)** | **229.5** | **310.0** | **274.0** | **299.6** |
| proof_integrity_test | 31.3 | 38.9 | 35.8 | 37.0 |
| test_d2_golden | 110.4 | 147.3 | 131.0 | 143.2 |
| test_d2_persist | 18.1 | 24.0 | 21.6 | 23.3 |
| 스텝 총량 (4테스트) | 395 | 519 | 462.4 | 503 |
| 잡 (attest/admission-check) | 490 | 600 | 570.7 | 578 |
| 런 총계 | 831 | 1028 | 923.1 | 940 |

- s1a는 스텝 총량의 평균 **59.2%**, 런 총계의 평균 **29.7%**.
- s1a(및 d2g)의 bimodal 분포: ≈230s(3런) vs ≈300–310s(4런) — 스텝 내부는 4회 독립
  `nim c -r`(콜드 nimcache)이므로 러너/툴체인 웜 상태 차이가 그대로 벽시계 차이로 나타난다.
  본 기록은 분포를 확정하지 않는다(원인 실험은 본 문서 범위 밖 — 후속 측정 과제).
- **동일 head 이중 실행 실측**: PR #603은 같은 head tree(`8ae68ca8`)에 대해 pull_request
  런(37755662845, 4합 523.7s)과 merge_group 런(37757818150, 4합 512.3s)에서 **동일한
  4테스트를 하루 두 번 전부 재실행**했다(둘 다 PASS). ≈1,036s의 동일 계산이 한 착지에서
  발생 — test-judgment 재사용 계약(`docs/spec/test_judgment_cas_contract.md`)이
  겨냥하는 중복의 실측 사례다.

## 4. 측정 경계 (이 기록이 주장하지 않는 것)

- 스텝 타임스탬프는 API `steps[].started_at/completed_at`(초 단위)이며 per-test는 로그
  밀리초 타임스탬프 차 — 표의 스텝 열과 4합 열의 ±0.5s 차는 그 해상도 차다.
- job raw log는 GitHub 기본 보존 기한(90일)이 지나면 소실된다. run/job ID와 위 명령으로
  같은 창에서 재검증 가능하며, 재측정 시 이 파일을 새 날짜의 기록으로 대체한다(역사 개정
  금지 — AGENTS.md §5).
- 이 기록은 재사용 도입의 효과를 측정하지 않는다(도입 전 baseline만). HIT-path 효과
  측정은 계약 문서 §8(구현 전제 조건)에 따라 별도 슬라이스의 증거로 남긴다.
