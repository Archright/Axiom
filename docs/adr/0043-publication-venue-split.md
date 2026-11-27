# ADR-0043: Publication-integrity venue split — PR pays a preflight, merge_group pays the full check

## Status

**Accepted (2026-11-21)** — 아키텍처 결정 기록이며 구현을 수반한다 (#282). 본 ADR은
[ADR-0032](0032-admission-venue-split.md) **(e)항을 개정**한다 (아래 §Decision (e')).

## Context

`Archright` 조직의 플랜은 `free`이고, 표준 호스팅 러너의 동시 실행 한도는 **20**이다
(조직 전체 공유 — 같은 풀을 쓰는 다른 저장소의 실행도 포함된다).

실측 (2026-11-21, `publication-integrity` run `44853943828`, PR 이벤트):

| job | started | completed |
|---|---|---|
| sbom | 02:05:57 | 02:06:50 |
| dependency-scan | 02:06:02 | 02:06:38 |
| secret-scan | 02:06:31 | 02:07:37 |
| license-scan-shards (0) | 02:07:11 | 02:11:51 |
| license-scan-shards (1) | 02:07:28 | 02:11:14 |
| license-scan-shards (2) | 02:06:52 | 02:12:28 |
| provenance | 02:07:39 | 02:08:30 |
| license-scan | 02:12:30 | 02:12:55 |
| publication-integrity | 02:12:58 | 02:13:54 |

**9 job 전부가 PR 이벤트에서 실행된다.** `merge_group`에서도 동일한 9 job이 실행된다
(run `44854381094`). 그 위에 `admission-gate`가 PR 1회당 실행 job 13개(나머지 8개는
skip)와 8~9분의 critical path를 점유한다.

따라서 **PR push 한 번이 약 31개의 runner 할당을 요구한다** — Free 조직의 20 한도를
단일 push로 초과한다. #282가 관측한 678초 대기는 이 구조의 필연적 결과다.

`max_entries_to_build: 2 → 1` (VS-1, 2026-11-21 readback 검증)은 merge queue의
동시 dispatch를 1로 낮춰 포화를 해소했다(관측: in_progress run 4 · queued 0). 그러나
그 변경은 **PR 이벤트가 만드는 부하를 줄이지 않는다** — PR 1회의 31 할당은 불변이다.
즉 PR-venue 비용은 merge-queue 설정으로 대체할 수 없다.

## Decision

**(a) 차원을 venue별로 분리한다.** `publication-integrity.yml`은 5개 차원을 갖는다:

| 차원 | job | venue |
|---|---|---|
| secret-scan | `secret-scan` | preflight **+** landing |
| license-scan | `license-scan-shards (0..4)` → `license-scan` | landing only |
| dependency-scan | `dependency-scan` | landing only |
| provenance | `provenance` | landing only |
| sbom | `sbom` | landing only |

- **preflight** (`pull_request`) = `{secret-scan}`. 1 job.
- **landing** (`merge_group` · `schedule` · `workflow_dispatch`) = 5 차원 전부. 9 job.

**(b) 분기 지점은 job-level `if:`이고, 판정 근거는 `github.event_name`이다.**
`steps.*.outputs`는 **이미 실행 중인 job 내부**의 값이므로 job-level `if:`에서 쓸 수
없다(GitHub Actions context 가용성). 따라서 event 이름을 직접 술어로 쓴다.

근거는 비가역성이다: 공개 저장소에서 PR 브랜치의 push는 즉시 공개된다. 자격 증명
유출은 되돌릴 수 없으므로, PR에서 **가장 먼저** 잡아야 하는 위험이 secret-scan이다.
나머지 4개 차원(라이선스·의존성·출처·SBOM)은 공개 준비성 판정이며, 최종 병합 후보에
대한 landing 판정으로 완전히 복구된다.

**preflight 집합을 실행 시간으로 정하지 않는다.** 빠른 검사와 중요한 검사는 다른
개념이다. 집합은 위 표로 **명시적으로 고정**되며, 변경은 본 ADR의 개정을 요구한다.

**(c) skip은 성공으로 읽지 않는다 — 평가기가 venue를 필수 인자로 받는다.**
`tools/ci/publication_report.nim`에 `--venue` (필수, 폐쇄 enum)를 추가한다.

| 입력 | 판정 |
|---|---|
| 인식 불가 venue | exit 1 (관측 부재가 아니라 **거부된 입력**) |
| 요구 차원 success | PASS |
| 요구 차원 skipped / failure / report 부재 | UNKNOWN / FAIL |
| **비요구 차원이 success 보고** | **FAIL(BLOCKER)** — 실행하지 않은 검사에 credit 금지 |
| **비요구 차원 report 공급** | **UNKNOWN** — 게이팅 드리프트 |

양 venue에서 **job 자체는 항상 실행**되고 venue별 요구 집합만 다르다. 따라서 GitHub의
"skip된 job은 Success로 보고된다"는 의미론에 의존하지 않는다 — 그 의미론은 required
check를 조용히 통과시키는 경로이기 때문이다.

**(d) required context 이름 · job id · workflowPath 는 바이트 수준 불변이다.**
`publication-integrity` context, `publication-integrity` job, 동일 경로. 따라서
ruleset `27097366`의 required status check 등록과 SL-21 producer tuple
(`config/policy/merge_admission.json` `requiredValidations[]`) 은 **함께 갱신할 필요가
없다**. `merge_admission.json`과 `src/cli/merge_cli.nim` `RequiredWorkflowIds`도
불변이다(둘을 함께 회전해야 하는 drift 조건이 발생하지 않는다).

**(e') ADR-0032 (e)항 개정 — "job skip 금지"의 범위를 좁힌다.**
ADR-0032 (e)는 "leg 생략(DAG 수준 분기)·job skip 금지"를 선언했고, 그 근거는
**admission 5-leg DAG의 무결성**(`ALLGREEN + 1:1` 형상, 부분 인증 subject 금지)이었다.
본 ADR은 그 근거를 훼손하지 않는다 — `admission-gate-v2.yml`의 5 leg는 전 venue에서
전부 유지되고, `admission-check` job은 **모든 venue에서 실행**된다(SL-21
`PRODUCER_SKIPPABLE`은 `if:`가 정확히 `always()` 또는 `!cancelled()`일 것을 요구하며,
aggregator `publication-integrity` job은 `if: !cancelled()`로 그 요구를 충족한다).

개정의 범위는 **비-admission 차원 job**으로 한정된다: `publication-integrity.yml`의
차원 job 4종이 venue에 따라 실행 범위를 달리한다. 이는 ADR-0032 (b)가 이미 확립한
"PR = preflight, MG = 정본" 원칙의 **일관된 적용**이지 예외가 아니다. ADR-0032 (e)의
"job skip 금지"는 **required context를 발행하는 aggregator job과 admission leg**에
대한 불변식으로 재해석되며, 그 범위에서 본 ADR은 아무것도 완화하지 않는다.

**(f) fail-closed는 "다른 대상의 증거로 실패를 만들라"는 뜻이 아니다.**
venue 판정에서 증거가 요구 집합 밖이면 **credit을 주지 않는다**(FAIL/BLOCKER/UNKNOWN).
요구 집합 안에서 실패하면 FAIL이다. 어느 경우에도 **실행하지 않은 검사를 success로
승격하지 않는다** — 이것이 본 ADR이 지키는 fail-closed의 정의다.

## Consequences

- **PR push 1회의 runner 할당이 약 31 → 약 23으로 감소**한다 (publication 9 → 1,
  admission-gate 13 + 기타 9 불변). 단일 push가 20 한도를 초과하는 상태는 남는다 —
  완전 해소는 admission-gate PR DAG 축소(별도 계약, 외부 App 5795152 의존)의 몫이다.
- **PR에서 발견되지 않는 결함이 남는다**: 라이선스·의존성·출처·SBOM 위반은 merge_group
  에서 처음 red가 된다. 이는 ADR-0032 (b)가 이미 수용한 격차의 연장이며, landing
  판정이 정본이므로 착지 자격은 약화되지 않는다.
- **`publication-integrity` context는 여전히 모든 venue에서 발행**된다. required check가
  Pending으로 남는 경로(path/branch 필터로 워크플로 자체가 skip되는 경우)는 생기지
  않는다 — 트리거는 불변이고 job-level `if:`만 venue를 본다.
- **규범 판정 J1–J4**: J1(의미론 동일성)·J2(증거 등가성)는 landing 입력에서 투영 필드
  `{gate, verdict, verdictSemantics, dimensions, blockers, unresolvedUnknowns,
  unresolvedUnknownCount, binding}` 필드 값이 동일함으로 통과했다(additive 필드만 추가).
  J3(캐시 건전성)·J4(Worker 결정론)는 이 워크플로에 `actions/cache`/`AXIOM_PROVE_WORKERS`
  사용이 0건이므로 **정의역 밖**이며, 적용 불가로 기록한다 — 검증 의무의 생략이 아니다.
- **재검토 조건**: preflight에서 잡히지 않는 landing 결함의 빈도가 유의미해지면 preflight
  집합에 차원을 추가한다 — 이는 본 ADR의 개정이지 집행 완화가 아니다.

## References

- `docs/adr/0032-admission-venue-split.md` — PR preflight / MG 정본 원칙, (e) 개정 대상.
- `docs/adr/0041-free-authority-migration.md` §2.6 — trust-surface PR은 auto-merge 큐를
  타지 않고 break-glass 레인으로 착지한다. `publication-integrity.yml`은 trust surface
  18경로 중 하나이므로 본 개정도 그 레인을 따른다.
- `docs/spec/publication_integrity_gate.md` §2.1–§2.2 — venue 분리 표와 불변식.
- `docs/spec/ci_optimization_tcb_judgments.md` — J1–J4 판정 규범.
- `docs/spec/ci_critical_path_metric.md` — 측정 규약.
- AGENTS.md §0.9(극장 금지) · §0.12(제품 계약 선행) · §2.3(merge-admission 관측) ·
  §2.5(CI 세대 전환).
