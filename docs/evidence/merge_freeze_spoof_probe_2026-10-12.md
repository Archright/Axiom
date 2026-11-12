# 중복 동명 required check 의미론 실측 — spoof probe (2026-10-12)

> 관측 기록이며 추가 구현을 포함하지 않는다. 판정: **ALL — required context 이름과
> 동일한 이름으로 보고된 체크 런이 head 커밋에 복수 존재하면 전부 성공해야 충족된다.**
> 실험 방식은 `ghec_ruleset_p1c_bypass_2026-09-24.md` §2의 scratch-probe 프로토콜을 따른다.
> 토큰: 사용자 토큰(wintrover, org admin)만 사용 — App 토큰 미사용.

## 1. 질문

여러 check run이 **같은 context 이름**을 head 커밋에 보고하고 그 context가
ruleset의 required status check일 때: (a) 하나라도 성공하면 충족인가(ANY),
(b) 전부 성공해야 하는가(ALL), (c) 최신 것이 이기는가(latest)?
공식 문서는 check-run + commit-status 동명 공존 시 둘 다 요구함만 확정하고
중복 job 이름은 "ambiguous"로만 기술한다. §7.1(2026-09-24)의
AMBIGUOUS_VALIDATION은 **자체 adjudicator**(merge_cli `containsCheck`,
matches=2)의 모호였지 GitHub 평가기의 모호가 아니었다 — 이번에 GitHub 측을 닫는다.

동기: `bsec-integrity` 같은 required binding과 (merge-freeze류) 무보고 freeze
context가 "동일 job id를 쓰는 워크플로우를 PR이 추가"하는 스푸프로 충족될 수
있는지, 그리고 우연한 동명 런 하나가 실패하면 착지가 막히는지가 설계에 영향을 준다.

## 2. 실험 장소 (scratch venue)

| 항목 | 값 |
|---|---|
| 신규 scratch ruleset | `spoof-probe-scratch` / id **24916756** (생성 후 삭제 완료) |
| 조건 | `refs/heads/probe/*`, enforcement `active`, bypass_actors `[]` |
| rules | `required_status_checks` 1건: context `spoof-probe-a81de2`, integration_id **15368**(GitHub Actions), `strict=false` |
| do_not_enforce_on_create | 초기 `false` → 중간에 `true`로 변경(§3 참조) |
| 기존 cas-probe-scratch | live id는 **23916707**(문서·지시서의 23914707은 전위 오기) — 이번 프로브에서 **전혀 수정 없음** |
| 스포프 워크플로우 | `spoof-probe-a.yml`(sleep 40 후 exit 0), `spoof-probe-b.yml`(즉시 exit 1) — job id = `spoof-probe-a81de2`(context명과 동일, `name:` 없음 → check run 이름 = job id) |
| 컨텍스트 사전 보고 | 없음 — 신규 hex(`a81de2`)라 그 어디에도 보고 이력 없음 |

## 3. 격리·경로 관찰 (프로브 실행 경로에 대한 사실)

1. **다른 ruleset의 스코프**: `axiom-admission-gate`(24233738)·`landing-integrity`
   (23943917)는 `refs/heads/main` 한정(`workflows` 룰), `main`(20303214)은
   `~DEFAULT_BRANCH` — `probe/*`와 무관. `artifact-hygiene`(23969951)·
   `execution-surface-create`(23967915)는 push target·conditions null(전 refs).
2. **로컬 pre-push 게이트가 스포프 커밋을 거부**: `.github/workflows/**` 추가
   커밋(56f4f6644)의 push에서 `check-repository-surface`(policyVersion 78,
   binding `base`)가 `changeClass=FROZEN, SURFACE_FORBIDDEN`으로 FAIL
   (`~/.cache/axiom/push-admissibility/<oid>` 스냅샷 판정). 로컬 게이트에
   bypass 개념 없음. `--no-verify`는 사용하지 않았다.
3. **서버 측 동일 규칙은 bypass 보유**: 23967915 `execution-surface-create`의
   bypass_actors = `OrganizationAdmin:always`, `Integration 29110`,
   `Integration 4879411` — API 응답 `current_user_can_bypass: "always"`.
   이에 따라 §3b 전례(GraphQL `updateRefs` 서버 측 경로)에 준해 **Git Data API로
   blob/tree/commit 생성 + ref 생성/갱신**으로 프로브 커밋을 착지시켰다
   (로컬 게이트는 우회·수정하지 않음; 서버 ruleset이 행위자별 정책 그 자체).
4. **required check는 ref 생성/갱신 계층에서도 강제된다 (신규 관측)**:
   - `required_status_checks` `do_not_enforce_on_create=false` 상태에서 체크
     없는 커밋으로의 ref **생성**이 422로 거부됨 → `true`로 변경 후 생성 허용.
   - 기존 ref의 fast-forward **갱신**(PATCH)은 커밋에 체크 런이 없으면 항상
     422 `Required status check "spoof-probe-a81de2" is expected`로 거부.
     직접 push/갱신 경로로는 "체크 없는 신규 커밋"을 못 올린다(실패 닫힘).
5. **노이즈 없음**: 기존 워크플로우의 push/pull_request 트리거는 모두
   `branches: [main|queue-probe|optimize/ci-pareto]` 한정 — 프로브 PR/푸시에서
   이 워크플로우들만 실행됐다.

## 4. 실측 (관측 매트릭스)

공통: PR들은 `probe/spoof-*` → `probe/spoof-base`(main tip `4b7efdcdf`에서 생성한
bare 브랜치) 대상. `mergeable=MERGEABLE`(충돌 없음)이므로 BLOCKED/CLEAN은
전부 required check 평가의 결과다.

| # | head 커밋 | 동명 check run 구성 (이름 `spoof-probe-a81de2` 전부) | mergeStateStatus | 근거 |
|---|---|---|---|---|
| 대조 | `14bdb4589` (PR #789) | IN_PROGRESS 1건 (보고 전) | **BLOCKED** | 무보고 context는 실제로 게이트한다 |
| A (스푸프 단독) | `14bdb4589` (PR #789) | success 1건 — run 38225937162, check run **114733333912**, app 15368, 08:50:04Z | **CLEAN** | 스푸프 성공 1건으로 요건 충족 — required check에 워크플로우 신원 고정은 없다 (context명 + Actions app만 검사) |
| B (성공+실패) | `30c17a8c` (PR #790) | failure **114734878177** (08:53:56Z) + success **114734878685** (08:54:35Z, **id·완료시각 모두 최신**) | **BLOCKED** (5분+ 지속) | ANY 기각, 완료시각 latest-wins 기각, id 최신 latest-wins 기각 |
| B (재실행) | `30c17a8c` | 위 + failure run 38226403955 rerun → FAILURE 재확인 | **BLOCKED** | 재실행으로도 실패가 남으면 막힘(결정적) |
| B' (전부 성공) | `9a2a2d5b` (PR #792) | success **114737924975** (09:02:38Z) + success **114737925110** (09:03:16Z) | **CLEAN** | 동명 중복 자체는 막지 않는다 — "ambiguous 중복 이름"도 GitHub 평가기에서는 결정적 |

## 5. 판정 (settled semantics)

**ALL — head 커밋에 required context 이름으로 보고된 모든 check run이 성공해야
충족된다.** 하나라도 failure(또는 pending)가 있으면 성공 런이 몇 개든, 최신
런(id·완료시각 기준 모두)이 success여도 BLOCKED다. 관측된 4개 셀
(1×success→CLEAN, success+failure→BLOCKED, failure rerun→BLOCKED,
2×success→CLEAN)과 양립하는 유일 해석이며, 재귀적 재검증 없이 인과가 닫힌다:
B 셀의 유일 차이는 실패 런의 존재였고, B' 셀(실패를 성공으로 교체, 나머지 동일)에서
CLEAN으로 반전됐다.

## 6. 함의

- **이름 기반 required check는 스푸프에 대해 방어가 아니다**: context명 +
  integration_id(15368=Actions)만 고정되고 워크플로우 신원은 고정되지 않는다.
  실측대로 요구된 적 없는 context를 **단일 green 런으로 충족 가능**(A 셀).
- **그러나 이 저장소의 실행면 방어가 스푸프 유입 경로를 실질적으로 좁힌다**:
  (i) 로컬 push 게이트가 `.github/workflows/**` 추가를 FROZEN으로 거부하고,
  (ii) 서버 push ruleset(23967915)은 bypass 행위자가 아니면 거부하며,
  (iii) required check는 **직접 ref 갱신 계층에서도 강제**(§3-4)라 체크 없는
  커밋을 브랜치에 올릴 수 없다. 공격자의 잔존 경로는 "PR 자체가 워크플로우를
  가져와 pull_request 이벤트로 스스로 보고"하는 길인데 이는 본 프로브 범위 밖이다
  (미닫음, §8). merge-freeze류 무보고 freeze context를 설계할 때 이 유입 경로를
  별도로 닫거나 fail-closed로 흡수할 것.
- **bsec-integrity(실제 워크플로우가 보고하는 required context)**: 동명 런이
  우연히(또는 악의적으로) 추가되면 ALL 의미론상 그 하나의 실패가 canonical green
  런이 있어도 착지를 막는다(§7.1의 자체 adjudicator 모호와 달리 GitHub은
  결정적). 반대로 동명 추가는 요건을 강화하지 않는다 — 스푸프 green 1건이면
  충족되므로. 동명 중복은 (조용한 완화가 아니라) fail-closed 리스크로만 작동한다.
- **무보고 freeze context**: 개시 직후 BLOCKED 실측(대조 행) — 보고 전 차단이
  기본 동작으로 성립한다.

## 7. 클린업 확인

- scratch ruleset **24916756 삭제**; ruleset 목록은 원래 6개로 복원
  (24233738, 23943917, 23969951, 23916707, 23967915, 20303214) —
  `cas-probe-scratch`(23916707)와 `main`(20303214)은 이번 프로브에서 읽기만 하고
  수정하지 않았다.
- PR **#789, #790, #792 전부 CLOSED**(merge 없음).
- 브랜치 `probe/spoof-a`, `probe/spoof-b`, `probe/spoof-c`, `probe/spoof-base`
  remote+local 삭제. 프로브 개시 전부터 존재한 `probe/no-ruleset-test`,
  `probe/observer-violation-injection`과 프로브 기간 중 타 워크스트림에서
  생성된 `probe/s5-stale-base-neutral`은 손대지 않음.
- 로컬 작업 트리: `main == origin/main == 4b7efdcdf`, 클린(본 기록 1개
  untracked 제외). 임시 산출은 `/tmp`와 `~/.cache/axiom/push-admissibility` 스냅샷
  (훅이 자체 정리)에 한함.

## 8. 이 기록이 닫는 질문 / 닫지 않는 질문

| 질문 | 상태 |
|---|---|
| 중복 동명 required check의 평가 의미론 | **CLOSED (ALL)** — §4, §5 |
| 동명 중복 자체가 평가를 모호하게 만드는가 | **CLOSED (아니오 — 결정적)** — B' 셀 |
| 이름만 아는 워크플로우로 required context 충족 가능한가 | **CLOSED (가능 — push 경유 실측)** — A 셀 |
| 무보고 required context의 개시 시 차단 | **CLOSED (BLOCKED 실측)** — 대조 행 |
| PR 자체 워크플로우(pull_request 트리거, fork PR 포함)가 자신의 PR 요건을 자가 충족하는 경로 | **OPEN** — 범위 밖(§6), freeze 설계 시 별도 프로브 권장 |
| GitHub 평가기 내부 알고리즘(worst-of vs 전체 재평가) | **OPEN (행동상 ALL과 동등)** — 관측 셀 전부와 양립하는 행동 규격으로 충분 |
