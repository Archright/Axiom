# merge-queue rearm 자동 복구 상태 선언 (rearm_recovery_status)

**Status**: Normative contract — 현재 상태 **INACTIVE** (자동 복구 아님) · 관측 기준시각 **2026-10-21T18:48:14Z** (2026-10-22 03:48 KST) · 최초 작성 2026-10-22.
**Related**: `docs/adr/0027-queue-delegation.md` (ADR-0027 Amendment C/D/E — rearm 정책 원본) · `.github/workflows/merge-queue-rearm.yml` (실행체) · `docs/agents/merge_admission_observation.md` §(c) (failure→recovery 유한 절차) · `docs/agents/rules_workflow.md` §Auto-Merge Default Policy (정본 arm 명령) · `docs/spec/diagnostic_execution_delegation.md` §2 (App 등록 = 인간 게이트 선례) · `docs/spec/gh_run_observation_quirks.md` Q12 (dequeued 이벤트는 이탈 사유를 운반하지 않음) · AGENTS.md §0.9 (극장 금지) · §2.4 (자격 증명 권한).

> **이 문서의 정본 성격**: "rearm가 무엇을 하는가"의 설계 정본은 ADR-0027과 `.github/workflows/merge-queue-rearm.yml`에 있다. **이 문서가 정본인 것은 "지금 실제로 무엇이 되는가"의 상태 선언**이다 — 즉 기능의 설계가 아니라 **운영 사실의 기록**이며, 이 두 개는 충돌하지 않는다.

---

## 0. 상태 선언 (INACTIVE)

**현재 상태: INACTIVE. 이 저장소의 `merge-queue-rearm`은 자동 복구가 아니다.**

| 항목 | 값 |
|---|---|
| 선언 | **INACTIVE — 자동 복구 아님** |
| 관측 기준시각 | 2026-10-21T18:48:14Z (2026-10-22 03:48 KST) |
| 워크플로 run 총계 | **267** (전량 `pull_request_target` 240 / `workflow_dispatch` 27) |
| **실제 arm 발생 횟수** | **0** (267 run 전체 로그 스캔) |
| arm 명령을 실제로 시도한 run | **2** (2026-10-13, PR #820) — **둘 다 실패** |
| 판정 근거 | `gh run list` 총계 + 267 run 로그 전문 스캔 + arm 결과 라벨(`rearmed@*`) 부존재 교차검증 (§1.4) |

"rearm가 PR을 복구한다"는 문장은 이 저장소에서 **거짓**이다. 정직한 문장은 다음 하나다.

> rearm 워크플로는 큐에서 빠진 PR을 **관측하고 분류하며**, 자동 복구는 **수동(operator)** 으로 수행된다. 워크플로가 수행하는 유일한 복구 행위 arm(`gh pr merge --auto --match-head-commit`)는 **실행 한 번도 성공하지 않았다** — 워크플로 자신의 `GITHUB_TOKEN`이 `enablePullRequestAutoMerge` 호출 권한을 갖지 않기 때문이다.

> **Arm credential 계보 갱신 (2026-10-30, 워크플로 Phase A wiring)**: 위 인용문은 GITHUB_TOKEN 시대(§1.2)의 기록이다. 이후 arm은 operator 승인 PAT(`REARM_ARM_TOKEN`, Actions secret, 2026-10-23)로 수행되었고, 이제 **job 내부에서 민팅한 GitHub App installation token**(pinned `actions/create-github-app-token`, `REARM_APP_ID`/`REARM_APP_PRIVATE_KEY`, per-issuance pull-requests:write + issues:write + contents:read, job 종료 시 revoke)으로 전환하는 워크플로 wiring이 착지된다. App 등록·시크릿 예치는 §4.1의 인간 게이트로 남는다 — wiring만으로는 arm이 활성화되지 않는다(시크릿 부재 시 기존대로 fail-safe no-arm). §1–§3의 실측 수치는 GITHUB_TOKEN 시대의 역사로 그대로 보존한다(수정 없음).

### 0.1 세 상태의 구분 (이 문서가 사용하는 어휘)

runbook과 감사 기록은 이 세 상태를 **엄격히 구분**한다. 혼동은 곧 극장이다.

| 상태 | 정의 | 관측 표식 |
|---|---|---|
| **성공(success)** | arm 명령이 **성공**하여 PR이 auto-merge 등록됨 | `REARM_ARMED=1` + `REARMED pr#<N> key=(...)` 런타임 출력 + `rearmed@<head12>` 라벨 부착 |
| **실패(failure)** | arm 명령을 **시도했으나** 실패 | `SKIPPED: arm command failed — verbatim error below` + 플랫폼 오류 원문 + `evidence.line = "arm-failed"` |
| **미실행(not-executed)** | arm 단계에 **도달하지 않음** (게이트·분류기가 사전에 차단) | `evidence.line` ∈ {`state=MERGED`, `no-anchor`, `intersection`, `historical-guard`, …} |

**실측: 267 run 중 성공 0 · 실패 2 · 미실행 225.** 워크플로의 **run conclusion은 성공(232/240)이어도 arm은 0건**이다 — conclusion은 "워크플로가 실패 없이 끝났다"만 뜻하고 복구 성공을 뜻하지 않는다. 이 구분이 없는 보고는 위장이다.

---

## 1. 실측 근거

### 1.1 run 총계

```bash
gh run list -R Archright/Axiom --workflow=merge-queue-rearm.yml -L 1000 \
  --json databaseId,event,conclusion
```

기대 출력(관측 기준시각 2026-10-21T18:48:14Z): 총 **267** 건.

| 이벤트 | 총계 | conclusion=success | conclusion=failure |
|---|---|---|---|
| `pull_request_target` | 240 | 232 | 8 |
| `workflow_dispatch` | 27 | 25 | 2 |
| **합계** | **267** | **257** | **10** |

최신 run: `39642086623` (2026-10-21T17:14:56Z, PR #1021).

### 1.2 arm 시도 2건 — 실패 원인 라인 (원문 인용)

267 run의 **로그 전문**을 스캔한 결과 `arm-failed` / `arm-ok` / `REARM_ARMED` 표식은 **0건**이고, arm 명령에 **실제로 도달한 run은 2건**뿐이다. 둘 다 2026-10-13, PR #820, head `2d0dfc2be235`이다.

| run id | 생성 (UTC) | PR | arm 결과 |
|---|---|---|---|
| `38440666593` | 2026-10-13T17:41:19Z | #820 | 실패 |
| `38441126650` | 2026-10-13T17:44:47Z | #820 | 실패 |

원문 로그 (run `38440666593`, 스텝 `condition 8: arm (only here; dispatch = validation, never arms)`):

```
SKIPPED: arm command failed — verbatim error below (fail-safe no-arm, no escalation):
GraphQL: Resource not accessible by integration (enablePullRequestAutoMerge)
```

run `38441126650`의 동일 스텝이 **바이트 동일하게** 같은 두 줄을 출력한다:

```
SKIPPED: arm command failed — verbatim error below (fail-safe no-arm, no escalation):
GraphQL: Resource not accessible by integration (enablePullRequestAutoMerge)
```

> **해석 (근본 원인)**: `enablePullRequestAutoMerge`는 큐 편입(auto-merge 등록) 뮤테이션이다. GitHub은 **그 뮤테이션을 호출할 권한이 없는 주체에 대해** `Resource not accessible by integration`을 반환한다. 이 워크플로의 `permissions:` 블록은 `pull-requests: write` · `contents: read` · `actions: read` · `checks: read` 4개만 선언하고(`.github/workflows/merge-queue-rearm.yml:141-145`) **큐 write 권한을 선언하지 않는다**. 따라서 **권한 없는 자동 복구**가 된다 — 워크플로는 fail-safe로 no-arm하고, 에러를 삼키지 않고 원문 그대로 stderr에 남긴다(Amendment E의 "error swallowing 금지" 계약 준수).
>
> **정직 기록 (UNKNOWN)**: "어떤 권한 부여가 이 오류를 해소하는가"는 **이 문서에서 확정하지 않는다**. 그 확정은 §4의 App 프로비저닝(인간 결정)에서만 가능하며, 본 문서는 그 도입을 **시행하지 않는다**.

> **시각화 주의 (리비전 차이)**: 위 2건은 **구 리비전** 워크플로(스텝 이름이 `condition 8: arm`)의 실행이다. 현 리비전은 스텝이 `condition 9: arm + budget label`이고, 실패 시 `evidence.line = "arm-failed"` 구조화 레코드를 추가로 emit한다. **현 리비전으로는 arm 단계에 도달한 run이 0건**이므로 `arm-failed` 레코드 자체가 관측되지 않는다. 두 사실은 함께 읽어야 한다 — "실패가 0건"이 아니라 **"시도가 2건이고 둘 다 실패"**다.

### 1.3 arm 단계 이전의 종료 지점 분포

267 run에서 구조화 emit(`{"rearm":{…,"evidence":{…,"line":…}}}`)이 관측된 226건의 `evidence.line` 분포:

| `evidence.line` | 건수 | 의미 |
|---|---|---|
| `state=MERGED` | 157 | PR이 이미 MERGED — arm 불필요 |
| `no-anchor` | 35 | 명시적 evidence anchor 미일치 → DEFAULT-NO-ARM (분류기 정책) |
| `intersection` | 13 | trust-surface 교차 — 재arm 금지 게이트 |
| `historical-guard` | 4 | historical 모드 하드 가드 — arm/label 경로 구조적 도달 불가 |
| `in-progress` | 3 | 대상 merge_group run 진행 중 — fail-closed |
| `conclusion=success` | 3 | 최신 MG run green + 수동 dequeue = 의도적 제거로 판정 |
| `no-run` | 3 | 대상 merge_group admission-gate run 부재 |
| `state=CLOSED` | 1 | PR이 CLOSED |
| `graphql` | 1 | PR 상태 질의 실패 (fail-safe no-arm) |
| `historical=true dry_run=false` | 1 | historical+dry_run=false 조합 거부 |
| `would-arm` | 1 | validation 모드(workflow_dispatch) — "would ARM" 출력만, 실제 arm 아님 |
| `label=rearmed@caab865d8a76` | 1 | 재시도 예산 소진 (budget exhausted) |
| `no-verdict-check-run` | 1 | 대상 커밋에 `verdict / admission-check` check-run 부재 |
| `head=caab865d8caa` / `head-mismatch` | 1 / 1 | head SHA 불일치 (fail-safe) |
| **`arm-ok`** | **0** | — |
| **`arm-failed`** | **0** | (구 리비전 2건은 §1.2 참조) |

`action` 분포: `no-arm` 225 · `exhausted` 1.

> **읽는 법**: 대부분(225/226)은 **arm 시도 이전**에 종료되었다. 즉 워크플로가 "복구를 시도했지만 실패"한 것이 아니라 **애초에 복구를 시도하지 않은** 경우가 지배적이다. 두 가지는 **다른 실패**다 — §2에서 구분한다.

### 1.4 교차검증 (arm 0건의 독립 확인)

arm이 성공했다면 워크플로가 arm **직후에만** 부착하는 예산 표식 라벨(`rearmed@<head12>`)이 남아야 한다(`.github/workflows/merge-queue-rearm.yml`의 `condition 9` — arm 성공 후 `gh api -X POST …/labels`).

```bash
gh api "/repos/Archright/Axiom/labels?per_page=100" --jq '.[] | select(.name|test("rearm")) | .name'
```

관측 결과: `no-auto-rearm` · `rearm-exhausted` · `rearmed@caab865d8a76` — **3개 라벨 정의는 존재하나, 그중 `rearmed@*`는 어느 PR에도 부착되어 있지 않다** (PR 60건 대상 스캔 결과 0건). 유일하게 존재하는 `rearmed@caab865d8a76`의 description은 `"Slice B retry-budget marker (simulation)"` — **시뮬레이션 표식**이며 라이브 arm 산출물이 아니다.

**결론: 267 run / 0 arm은 로그 스캔과 라벨 부재라는 독립된 두 경로에서 동일하게 성립한다.**

### 1.5 "success" 결론의 의미 (오독 금지)

| 명령 | 관측값 | 의미 |
|---|---|---|
| `gh run list --workflow=merge-queue-rearm.yml -L 1000` | 257 success | 워크플로가 **예외 없이 종료**함 (no-arm도 정상 종료) |
| `gh api …/issues/<N>` 의 `rearmed@*` 라벨 | 0건 | **arm이 한 번도 성공하지 않음** |

**run conclusion은 복구 지표가 아니다.** §0.1의 세 상태 구분을 무시하고 "rearm 워크플로가 257회 성공했다"로 요약하면 **극장**이다(§2).

---

## 2. 왜 이 상태를 위장하면 안 되는가

AGENTS.md §0.9는 **극장(Theater)** = "보장하는 척/보이는 척 하면서 아무것도 보장하지 않는 것"을 **작업 실패**로 규정하고, 발견된 극장은 `data/debt_registry.json`에 등록하도록 요구한다. `docs/adr/0008-theater-prohibition.md`가 그 전문이다.

**존재하지 않는 복구 능력을 성공으로 표시하는 것은 극장이다.** 구체적으로 금지되는 세 가지:

| 위장 형태 | 왜 금지인가 | 대체 |
|---|---|---|
| "rearm가 267회 **성공**했다" (run conclusion을 복구 지표로 제시) | 결론이 복구 성공이 아님을 §1.5가 실측으로 보여준다. 관측값의 의미를 바꾸어 진술하는 것은 §0.9의 theater 정의 그 자체 | "267 run, **0 arm**" (§0 표) |
| "rearm가 큐를 **자동으로 복구**한다" (문서·README·대외 문구) | arm은 0건이었고 구조적으로 성공 경로가 없다. 운영자가 이 문장을 믿으면 **큐가 막혔을 때 기다린다** — 실제 복구는 수동 절차에 있다 | "복구는 **수동**(§3), 자동화는 **미도입**(§4)" |
| "rearm 워크플로가 **fail-safe로 동작한다**" (성공으로 서술) | fail-safe no-arm은 **기능 부재**다. fail-safe는 "고치지 못하면 아무것도 하지 않는다"지 "고친다"가 아니다. §1.3의 225건은 그 증명이다 | "관측·분류는 동작, **복구 행위는 0건**" |

**부수 원칙 — 실측과 추측의 분리**: 이 문서의 모든 숫자는 위의 `gh` 명령으로 재현 가능하다. "충분히 권한을 주면 될 것이다" 같은 **추측은 쓰지 않는다** — §1.2의 UNKNOWN 표기에 따라, 해소는 App 프로비저닝 단계(§4)에서만 한다.

---

## 3. 수동 복구 runbook (queue가 막혔을 때)

**권위**: 큐 편입(auto-merge 등록)의 권위는 **GitHub**다(AGENTS.md §2.3). 아래 arm 명령은 **operator 행위**이며 Axiom이 개입하지 않는다. 관측 명령은 GET/query만 사용한다.

**전제**: 운영자는 `Archright` 조직 admin이며, `gh` CLI에 GitHub 네이티브 인증(`gh auth`)이 되어 있다(AGENTS.md §2.4 — 자격 증명은 네이티브 클라이언트로만). **본 절의 arm 명령은 §1.2의 워크플로 arm과 본질이 다르다 — human PAT은 해당 뮤테이션에 대한 권한을 갖기 때문에 성공할 수 있다.** 이 차이 자체가 "자동 복구는 권한 문제"라는 §0 선언의 근거다.

> **fail-safe 규칙 (절차 규율)**: 각 단계는 **관측 → 판단 → 중단** 순서다. 관측이 안 되면 **멈추고 보고**한다(무한 대기 금지, 추측 서사 금지). PR head SHA는 단계 3에서 재취득하고, 단계 4 arm 직전에도 `--match-head-commit`로 재확인한다.

### 단계 0 — 준비 (관측)

```bash
gh auth status                       # GitHub 네이티브 인증 상태
gh pr view <N> --repo Archright/Axiom --json number,state,mergeStateStatus,headRefOid
```

기대 출력: `state` = `OPEN`, `headRefOid` = 40-hex. `state`가 `MERGED`/`CLOSED`면 복구 대상이 아니다 → **단계 1로 진행 금지, 보고**.

### 단계 1 — 큐 상태 확인 (merge-queue 엔드포인트)

```bash
gh api graphql -f query='
query { repository(owner:"Archright", name:"Axiom") {
  mergeQueue { entries(first:20) { totalCount nodes { position state enqueuedAt
    pullRequest { number title headRefName headRefOid } } } } } }'
```

기대 출력:
- **큐가 정상** → `{"mergeQueue":{"entries":{"totalCount":N,"nodes":[...]}}}` (N≥1, 각 node에 `position`·`state`·`pullRequest.number`).
- **큐가 비었는데 PR이 "큐에 막혔다"는 보고를 받은 경우** → `totalCount: 0` + `nodes: []`. **이것이 dequeue 소실 상태다**(§3.1). PR 단위로는:

```bash
gh api graphql -f query='
query { repository(owner:"Archright", name:"Axiom") { pullRequest(number:<N>) {
  number state isInMergeQueue mergeQueueEntry { state position headCommit { oid } } } } }'
```

기대 출력: `isInMergeQueue: false`, `mergeQueueEntry: null` → **큐에 없다**. `mergeQueueEntry.state`가 `QUEUED`/`LOCKED`이면 큐 안이므로 진단 불필요.

> **측정 팁**: `gh pr checks` / GraphQL `statusCheckRollup`은 **merge_group phase를 관측할 수 없다**(PR head sha 결속). 큐 phase의 유일한 관측 경로는 위 merge-queue 엔드포인트와 merge_group run discovery다 — `docs/spec/gh_run_observation_quirks.md` 및 `docs/agents/merge_admission_observation.md` §(d)가 같은 제한을 기록한다.

### 단계 2 — 실패한 merge_group run 진단 (GET만)

```bash
gh api "/repos/Archright/Axiom/actions/runs?event=merge_group&status=failure&per_page=20" \
  --jq '.workflow_runs[] | "\(.id) \(.created_at) \(.head_branch)"'
```

기대 출력: `gh-readonly-queue/main/pr-<N>-<base_sha>` 형태의 `head_branch` 행들. `head_branch`의 `pr-<N>`이 대상 PR을 가리킨다.

```bash
gh api /repos/Archright/Axiom/actions/runs/<run_id>/jobs \
  --jq '.jobs[] | "\(.id) \(.name) \(.conclusion)"'
```

기대 출력: `conclusion`이 `failure`인 job 줄. **실패 job의 로그**를 읽어 원인을 사실로 기록한다(추측 서사 금지):

```bash
gh api /repos/Archright/Axiom/actions/jobs/<job_id>/logs
```

> **인식된 실패 코드와 해석** (`.github/workflows/admission-check.yml` / `docs/spec/admission-generation.md` 기준 — readback 원칙):
> `ADM_IDENTITY` / `CANDIDATE_MERGE_BASE_UNRESOLVED` / `CANDIDATE_TREE_MERGE_ERROR` → 후보 identity 해석 실패 · `NOT_ADMIT_STALE_BASE` → base 이동 · `ROT_*` / `TRUST_SURFACE*` / `NO_CERT*` / `MUST_*` → **영구 실패(재시도 무의미)** · `NOT_ADMIT_BINDING_MISMATCH` → 세대 불일치.
> **영구 실패 계열은 단계 4로 넘어가지 않는다** — 재삽입해도 같은 verdict가 나온다. 여기서 멈추고 원인을 PR에 반영한다.

### 단계 3 — 결함 반영 (PR 수정)

- PR에 커밋을 반영한다. **head identity가 바뀌면 재판정 대상**이다 — 무심코 `gh run rerun`으로 재시도하지 않는다.
- `gh run rerun <run_id>`는 **재-enqueue가 아니다**(죽은 큐 브랜치 위 job의 재실행일 뿐이다 — `docs/agents/merge_admission_observation.md` §(c) 3절). 재진입은 4절뿐이다.
- base가 이동한 경우(`NOT_ADMIT_STALE_BASE`): `gh api repos/Archright/Axiom/pulls/<N> --jq .base.sha`와 `gh api repos/Archright/Axiom/git/ref/heads/main --jq .object.sha`가 일치할 때까지 **관측**한 뒤, 승인된 유일한 base 스냅샷 리프레시 수단(빈 커밋 synchronize)을 쓴다. **raw rebase는 금지**(HARD RULE).

### 단계 4 — PR 재삽입 (operator arm — 유일한 복구 행위)

<!-- monitor-purity:begin -->
```bash
gh pr merge <N> --repo Archright/Axiom --auto --match-head-commit <headSha>
```
<!-- monitor-purity:end -->

기대 출력: 성공 시 아무 출력이 없거나 arm 확인 메시지. **명령은 `--merge` 전략 플래그를 쓰지 않는다** — MERGE-method 권위는 ruleset 큐에 있고 CLI가 아니다(정본: `docs/agents/rules_workflow.md` §Auto-Merge Default Policy, 2026-10-03 개정). `--match-head-commit`은 arm 시점의 head 일치 사전조건이며 지속적 head 고정이 아니다.

**arm 증거 (둘 중 하나면 충분)**:

```bash
gh pr view <N> --repo Archright/Axiom --json autoMergeRequest     # ≠ null
gh api graphql -f query='query { repository(owner:"Archright",name:"Axiom"){ pullRequest(number:<N>){ isInMergeQueue } } }'
```

기대 출력: `autoMergeRequest` ≠ `null`, 또는 `isInMergeQueue: true`.

> **트러스트 서피스 PR (MUST-T2)**: `config/policy/merge_admission.json`의 `trustSurface`에 걸치는 PR은 **자동 병합 등록을 금지**한다 — 수동 병합 경로를 따른다(`docs/agents/rules_workflow.md` MUST-T1/T2). 이 절의 arm 명령은 그런 PR에 적용하지 않는다.

### 단계 5 — ruleset readback 확인

```bash
gh api /repos/Archright/Axiom/rulesets/20303214 --jq '{
  enforcement, target, required: [.rules[]|select(.type=="required_status_checks")
    | .parameters.required_status_checks[]|{context,integration_id}],
  merge_queue: [.rules[]|select(.type=="merge_queue")|.parameters][0],
  bypass_actors }'
```

기대(관측 기준시각 2026-10-21T18:48:14Z, 정상 상태):

```json
{"enforcement":"active","target":"branch",
 "required":[{"context":"admission-check","integration_id":15368},
             {"context":"bsec-integrity","integration_id":15368},
             {"context":"debt-registry-gate","integration_id":15368}],
 "merge_queue":{"merge_method":"MERGE","grouping_strategy":"ALLGREEN",
                "max_entries_to_build":2,"max_entries_to_merge":1,
                "min_entries_to_merge":1,"min_entries_to_merge_wait_minutes":0,
                "check_response_timeout_minutes":120},
 "bypass_actors":[]}
```

**판정**: `enforcement: active` · `bypass_actors: []` · required check **3건** · `merge_method: MERGE`가 **모두** 보일 것. 하나라도 다르면 **복구 완료로 주장하지 말고** 보고한다(복구 = 큐 편입 + 통과 + MERGED까지다).

> **조직 ruleset은 operator-adapter 경로다**: org ruleset `25218071`(axiom-admission-gate)·`23943917`(landing-integrity)의 `workflows[].sha`는 **Administration org write**가 필요한 조회다 — `GITHUB_TOKEN`의 직접 보장 범위 밖이다. 필요 시 조직 admin 자격으로:
> ```bash
> gh api /orgs/Archright/rulesets/25218071 --jq '{id,name,enforcement,
>   workflows:[.rules[]|select(.type=="workflows")|.parameters.required_workflows[]|{path,repository_id,sha}]}'
> ```
> 기대 출력: `enforcement: active`, `workflows[0].sha` = `7fffee318b9fada32d13dd9c88d74869e343f9cc` (관측 기준시각). **조회 결과를 "검증됨"으로 기록할 때 provenance를 명시**한다 — §4.2의 자격은 여기서 끝난다.

### 단계 6 — 종결 관측

```bash
gh pr view <N> --repo Archright/Axiom --json state,mergedAt,mergeCommit
```

기대 출력: `state: MERGED` + `mergedAt` + `mergeCommit.oid`. **이것이 복구 완료의 증거다** — "arm이 성공했다"는 사실은 복구 완료를 뜻하지 않는다(§0.1).

### 3.1 dequeue 소실 — 이 runbook이 존재하는 이유

PR #787 사례(2026-10-13, `docs/agents/merge_admission_observation.md` 부록 (b))가 확정한 사실:

- merge_group 실패 직후 `github-merge-queue[bot]`의 **자동 dequeue**가 관측되었고, 그 결과 **auto-merge가 소멸**한다.
- GitHub 공식 문서의 auto-merge 취소 조건은 3종(무권한 push · base 브랜치 전환 · 수동 disable)뿐이며, **dequeue로 인한 소멸은 미문서 플랫폼 동작**이다. 이 실측이 계약 근거다.
- 플랫폼의 **자동 재enqueue 기능은 없다**(큐는 남은 entry의 그룹 재구성만 수행한다) — dequeue된 PR의 재진입은 **operator arm이 유일 경로**다.

**따라서 §4의 자동화가 도입되기 전까지 — 그리고 도입 후에도 자동 arm이 권한을 갖지 않는 한 — 복구는 본 절의 operator 행위에 의존한다.**

---

## 4. 자동화 전향 조건 (도입 시 요구사항 — **지금 도입하지 않는다**)

> **범위 명시**: 본 절은 **요구사항 명세**다. 본 작업(Phase 5)은 rearm App을 프로비저닝하지 않고, 워크플로를 수정하지 않고, §0의 INACTIVE 선언을 유지한다. App 프로비저닝은 **명시적 인간 결정**이다(AGENTS.md §2.4 — "발견은 대체 수단 아님"; `docs/spec/diagnostic_execution_delegation.md` §2 — "GitHub은 App 생성 API를 제공하지 않는다 … 등록은 **인간이 수행하는 게이트**이며, 에이전트는 이 스펙을 제공하는 것만이 범위다").

### 4.1 인간 게이트 (도입 시점)

| 단계 | 주체 | 근거 |
|---|---|---|
| App 생성·설치·키 발급 | **인간(조직 owner)** — GitHub UI / 조직 settings | GitHub은 App 생성 API를 제공하지 않는다. `docs/spec/diagnostic_execution_delegation.md` §2의 인간 게이트 선례를 준용 |
| 설치 대상 결정 | **인간** — `Archright/Axiom` **단일 저장소 한정** | 설치 상한(installation ceiling) 원칙. 다른 저장소 설치는 구조적 배제 |
| 키 취급 | **인간** — App private PEM은 **저장소·로컬 파일시스템에 저장 금지** | AGENTS.md §0.4c/§2.4 · `docs/spec/diagnostic_execution_delegation.md` §2 (환경 시크릿 보관) |
| 권한 집합 승인 | **인간** — §4.2의 최소 권한과 상한 | §2.4 — 자격 증명 권한은 인간에게 있음 |
| 워크플로 wiring | **인간 승인 후** 별도 세대 | §2.5 CI Self-Bootstrap — 일관된 세대 전환으로 착지해야 함 |

### 4.2 자격 요구사항 (최소 권한 — 도입 시 검증해야 하는 요구사항)

§1.2의 `Resource not accessible by integration (enablePullRequestAutoMerge)`는 **"이 권한이면 된다"가 아니라 "이 권한으로는 안 된다"의 증거**다. 따라서 아래는 **검증 대상 요구사항**이며, **현재 검증되지 않았다**.

| 요구 | 값 | 상태 |
|---|---|---|
| 대상 | `enablePullRequestAutoMerge` 뮤테이션 호출 권한이 있는 **App installation token** | **요구사항** — 미검증 |
| 최소 쓰기 스코프 (후보) | `Pull requests: write` + `Merge queues: write` | **요구사항** — 미검증. GitHub이 `enablePullRequestAutoMerge`에 요구하는 정확한 스코프 조합은 §4.6의 사전 검증으로 확정한다 |
| 읽기 스코프 (분류기 필요) | `Contents: read` · `Metadata: read` · `Actions: read` · `Checks: read` | `docs/spec/diagnostic_execution_delegation.md` §2의 read-only 5개 어휘와 정합. `merge-queue-rearm.yml:141-145`의 현 선언과 동일 |
| 명시적 부정 | `Administration: write` 등 **큐 외 write 스코프 불허** · 저장소 2곳 이상 설치 불허 | `docs/spec/diagnostic_execution_delegation.md` §2 "설치 권한 상한" 원칙 준용 |
| 발급 방식 | **단기 토큰** — job 내부에서만 사용, job 종료 시 revoke, 로컬으로 유출 금지 | `docs/spec/diagnostic_execution_delegation.md` §1 (채택된 해소: 토큰을 로컬로 가져오지 않는다) |
| 발급 경로 | protected environment + required reviewers | `docs/spec/diagnostic_execution_delegation.md` §2 |

### 4.3 재시도 예산 (도입 시 요구사항)

현 워크플로의 예산 판정(`.github/workflows/merge-queue-rearm.yml` condition 8/9, ADR-0027 Amendment E)이 **그대로 유지**되어야 한다. 자동화 도입이 예산을 느슨하게 해서는 안 된다.

| 항목 | 현 규칙 | 도입 시 요구 |
|---|---|---|
| 동일 key 상한 | `rearmed@<head12>` 1회 → 2회째는 `rearm-exhausted` | **유지**. 자동 경로가 추가 budget을 만들면 안 됨 |
| key 정체성 | `(PR, head, G, class)` — 완전 키 | **유지**. `docs/spec/gh_run_observation_quirks.md` Q5·Q12와 정합 |
| exhausted 시 | `no-arm`, 구조화 summary, escalate | **유지** |
| 백오프 | **현 규칙에 없음** — 도입 시 정의하거나 "없음"을 명시 | 자동 경로는 무한 재시도 위험이 있으므로, 도입 시점에 명시적으로 결정 |

### 4.4 재진입 조건 (도입 시 요구사항)

자동 arm이 **발화해도 되는** 조건. 현 분류기(Amendment D/E)의 증거 앵커를 그대로 승계한다.

| 조건 | 현 규칙 |
|---|---|
| 분류 | `TRANSIENT` 판정 (T1 allowlist title ∪ T2 evidence anchor)만. `PERMANENT`(ROT_*/TRUST_SURFACE*/NO_CERT*/MUST_*)는 **재arm 금지** |
| 앵커 미일치 | `UNKNOWN` → **DEFAULT-NO-ARM** |
| trust-surface | 교차 시 재arm 금지 (MUST-T1/T2) |
| dequeued 사유 | 이벤트 페이로드에 사유 필드가 없다 — **분류 스텝이 유일한 판별자** (`docs/spec/gh_run_observation_quirks.md` Q12) |
| PR 상태 | arm 직전 `OPEN` 재확인 (이미 MERGED/CLOSED면 중단) |
| head 정합 | `--match-head-commit`로 arm 시점 head 일치 확인 |

### 4.5 성공 / 실패 / 미실행의 구분 (도입 시 요구사항)

**자동화가 도입되면 §0.1의 세 상태 구분을 반드시 유지한다.** 자동 경로가 "실패"와 "미실행"을 같은 성공 컨테이너로 합치면, 도입 자체가 새로운 극장이 된다.

| 상태 | 판정 기준 | 산출물 |
|---|---|---|
| **성공** | arm 뮤테이션이 실제로 성공 (auto-merge 등록 확인) | `rearmed@<head12>` 부착 + 구조화 레코드 `action=armed` |
| **실패** | arm을 **시도했고** 실패 | 원문 오류 + `action=no-arm` + `evidence.line="arm-failed"` |
| **미실행** | arm 단계에 도달하지 않음 | `action=no-arm` + `evidence.line=<게이트 사유>` |

**요구**: 성공·실패·미실행은 **각각 집계 가능**해야 하고, run conclusion(`success`)이 이 셋을 구분해 주지 않는다면 **보고 계층이 그 구분을 대신해야 한다**. §1.5가 보인 오독이 자동화 후에도 재발하지 않게 하는 것이 이 항의 목적이다.

### 4.6 도입 게이트 (착지 전 통과해야 하는 것)

1. **uniqueness 사전 검증** — `generation-acceptance` 계열과 신규 rearm 컨텍스트의 유일 producer 확인(동일 규칙을 `docs/adr/0036` 계열 설계가 사용).
2. **권한 사전 검증(실측)** — §4.2의 후보 권한으로 arm이 실제로 성공하는지 **dry-run이 아닌 실측**으로 1회 확인. 확인 전까지 "권한이 충분하다"는 주장을 문서에 쓰지 않는다.
3. **fail-safe 정합** — 분류기·예산·마커·에러 비삼킴이 현 리비전과 **바이트 동일하게** 유지됨을 확인.
4. **관측 신호** — 성공/실패/미실행 3상태가 **운영자가 읽을 수 있는** 곳(구조화 summary + issue)에 남는지 확인.
5. **롤백** — 워크플로를 **원래 리비전으로 되돌리는** 절차가 살아 있는지 확인(되돌리기 불가한 상태로 만들지 않는다 — AGENTS.md §2.5).
6. **§0 상태 갱신** — 실측이 1회 이상 arm 성공을 관측한 뒤에야 이 문서의 §0을 INACTIVE → ACTIVE로 **기계 관측 증거와 함께** 갱신한다.

---

## 5. 잔여 · UNKNOWN · 근거 범위

| 항목 | 상태 | 해소 경로 |
|---|---|---|
| `enablePullRequestAutoMerge`에 필요한 정확한 권한 조합 | **UNKNOWN** | §4.6-2의 실측 (App 프로비저닝 단계) |
| 현 리비전에서 `arm-failed` 구조화 레코드 실측 | **미관측** (arm 도달 run 0건) | §4.6-2 통과 후 1회 관측 |
| 10-13의 2회 arm 실패가 **구 리비전**에서의 관측이라는 점 | **확인** — 스텝 이름 `condition 8` | 본 문서 §1.2 각주 |
| 큐 dequeue 시 auto-merge 소멸의 **플랫폼 공식 문서** | **없음** — 미문서 동작, 실측이 계약 근거 | `docs/agents/merge_admission_observation.md` 부록 (b) (정본) |
| 운영자 arm의 성공률 | **미측정** | 본 절이 최초의 계측 경로다 — 도입 시 §4.5의 3상태 집계로 정량화 |

**근거 범위 (정직 기록)**:
- §1의 모든 수치는 **2026-10-21T18:48:14Z** 시점의 라이브 조회다. run 수는 이후 증가할 수 있으므로, **수치를 인용할 때 관측 시각을 함께 인용**한다.
- §1.3의 분포는 **267 run 로그 전문 스캔**에서 `{"rearm":{…}}` 구조화 emit을 추출한 결과다. emit이 없는 run은 해당 행에 집계되지 않는다(226/267) — **267개 run 전부의 행이 아니며**, 이 한계는 표 아래에 명시되어 있다.
- 본 문서는 **runbook의 명령을 실행해 복구한 사례를 기술하지 않는다**(복구는 operator 행위이며 본 작업은 읽기 전용 관측만 수행했다). §3의 기대 출력은 **관측 기준시점의 실측 readback**과, 실패 코드 해석은 저장소의 기존 문서(`.github/workflows/admission-check.yml` · `docs/spec/admission-generation.md` · `docs/adr/0027-queue-delegation.md`)에 근거한다.
