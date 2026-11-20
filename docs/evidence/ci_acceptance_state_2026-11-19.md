# CI 수용 상태 — 경계 `aa0f78a8` (2026-11-19)

> **Status**: 관측 증거 동결(freeze). 본 문서는 코드·정책·워크플로·CI 배선·임계값을 변경하지 않는다 — 실측값과 재현 명령만 기록한다.
> **Created**: 2026-11-19
> **Measured at**: 2026-11-19T11:30Z–11:50Z (UTC). collector는 `tools/ci/ci_acceptance_collect.nim`에서 직접 빌드해 실행했다(Nim 2.2.10).
> **Boundary**: `aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356` — #145, #186, 계약(#208), collector 수정(#210)이 모두 착지한 뒤의 최종 merge.
> **재실행 주의**: `window`/`shortfall`은 새 `merge_group` 후보가 착지하면 바뀐다. `check-runs`의 `total_count`도 시간 함수다(§5.2 — 측정 시 48, 재조회 시 49).

## §0. 결론

1. **경계 `aa0f78a8`의 수용 창은 비어 있다.** `status=INCOMPLETE window=0/20 shortfall=20 excluded_before_boundary=16`, `gaps=[]`, exit **2**. 정규화(normalization)는 **선언되지 않았다** — 상태는 `INCOMPLETE`이며 본 문서는 그것을 `ACCEPTED`로 바꾸지 않는다.
2. **창이 빈 이유는 결함이 아니라 후보 부재다.** 경계 이후의 `merge_group` 후보가 아직 없다. 후보를 만들기 위해 무변경 PR이나 장식 변경을 넣는 것은 금지다(무변경 PR은 git에 존재할 수 없고, 장식 변경은 AGENTS.md §0.9 극장 금지에 해당한다). 따라서 이 PR은 수용 창을 채우지 않는다 — padding이 아니다.
3. **baseline은 재현된다.** canonical `n=40 p50=558.0s mean=708.4s min=378s max=2848s`, legacy `n=40 p50=560.5s mean=711.2s`, exit 0. 역사적 `546/560/574.5` 값은 어느 공식으로도 재현되지 않아 **부적격**이다(§3).
4. **collector 결함 2건은 PR #210에서 수정됐다**(§4): `/attempts` 목록 엔드포인트 404, 경계 이전 attempt gap의 수용 창 누출.
5. 이 변경은 authority·threshold·CI 배선을 바꾸지 않는다. merge authority는 여전히 GitHub ruleset `27097366`이다(§6).

## §1. 경계와 착지 체인

경계 `aa0f78a8`은 아래 착지 체인의 마지막 merge다. 각 merge commit은 `Merge pull request #N` 메시지를 가지며, 각 head에 App `5795152`(`axiom-admission-verifier`)의 `admission-check: success`가 결속되어 있다(§5.1에서 재확인).

| merge commit | PR | 브랜치 |
|---|---|---|
| `082e7245d288909cfa821aa7305564cd012446b3` | #205 | `vs/145-replay-subject-deps` (#145) |
| `c0eeeaf1c1b34ec2f8ac94b912e8251d2531d1c9` | #206 | `vs/186-invalid-input-exit` (#186) |
| `c97983cf3d9ef8506264d89d9622f68c85329bfc` | #209 | `vs/145-companions` |
| `907eba34c6f35879d036b5d37f77bf4b07313847` | #207 | `docs/free-parity-and-authority-evidence` |
| `5cee92e18034061d671add9fac99da6dd4ce9f82` | #208 | `vs/ci-acceptance-v2` (계약) |
| `aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356` | #210 | `vs/ci-acceptance-v3` (collector 수정) |

```console
$ git log --oneline --first-parent -6 aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356
aa0f78a Merge pull request #210 from Archright/vs/ci-acceptance-v3
5cee92e Merge pull request #208 from Archright/vs/ci-acceptance-v2
907eba3 Merge pull request #207 from Archright/docs/free-parity-and-authority-evidence
c97983c Merge pull request #209 from Archright/vs/145-companions
c0eeeaf Merge pull request #206 from Archright/vs/186-invalid-input-exit
082e724 Merge pull request #205 from Archright/vs/145-replay-subject-deps
```

경계의 정의(무엇 뒤의 merge인가)는 `docs/spec/ci_acceptance_contract.md` §1 "Boundary"가 규정한다 — #145, #186, 계약이 모두 착지한 뒤의 main merge commit이며 기본값은 없다.

## §2. 수용 창 — `INCOMPLETE`, 창은 비어 있다

```console
$ bin/ci_acceptance_collect --repo Archright/Axiom \
    --boundary aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356 --window 20 --mode initial
[ci_acceptance_collect] boundary=aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356
[ci_acceptance_collect] mode=initial status=INCOMPLETE window=0/20 shortfall=20 excluded_before_boundary=16
[ci_acceptance_collect] counts: success=0 legitimate_policy=0 internal_defect=0 (identity=0 soundness=0 projection=0 authority=0) unclassified=0 cancelled_superseded=0
[ci_acceptance_collect] latency canonical n=0 p50=0.0s mean=0.0s min=0s max=0s
[ci_acceptance_collect] latency legacy n=0 p50=0.0s mean=0.0s
[ci_acceptance_collect] accepted=false predicate_holds=false observation_complete=false
$ echo $?
2
```

보고서 JSON의 해당 필드:

```console
$ jq '{status: .acceptance.status, observed: .acceptance.observed_entries,
       shortfall: .acceptance.shortfall, gaps: .acceptance.gaps,
       observation_complete: .acceptance.observation_complete}' \
    build/ci_acceptance/ci_acceptance_report.json
{
  "status": "INCOMPLETE",
  "observed": 0,
  "shortfall": 20,
  "gaps": [],
  "observation_complete": false
}
```

읽는 법:

- `excluded_before_boundary=16` — 경계 이전 `merge_group` 항목 16건이 측정 대상에서 제외됐다. 수용 창은 경계 이후 항목만 센다.
- `window=0/20`, `shortfall=20` — 전체 N 창 규칙(`docs/spec/ci_acceptance_contract.md` §5 "Full window only")에 따라 부분 창은 평가되지 않는다. exit 2는 계약 §8의 `INCOMPLETE`다.
- `observation_complete=false`는 여기서 **빈 창 규칙**이다(관측 항목 0건은 complete일 수 없다). `gaps=[]`이므로 결함·관측 실패로 인한 false가 아니다 — §4(b)의 옛 누출 결함은 재현되지 않는다.
- `counts`가 전부 0인 것은 실패 0건이 아니라 **평가할 항목이 0건**이라는 뜻이다. 성공로 읽으면 안 된다.

창이 빈 이유는 하나다: 경계 이후 큐에 들어간 후보가 아직 없다. 후보를 인위적으로 만들지 않는다 — 빈 PR은 git에 존재할 수 없고, 장식 변경으로 큐 항목을 만드는 것은 극장(AGENTS.md §0.9)이다. 따라서 이 PR은 창을 0/20으로 유지하며, 수용을 주장하지 않는다.

## §3. Baseline 재현 — canonical 558.0 / legacy 560.5

```console
$ bin/ci_acceptance_collect --repo Archright/Axiom --baseline-live \
    --window 40 --baseline-until 2026-11-19T08:00:00Z
[ci_acceptance_collect] baseline-live canonical: n=40 p50=558.0s mean=708.4s min=378s max=2848s
[ci_acceptance_collect] baseline-live legacy: n=40 p50=560.5s mean=711.2s
$ echo $?
0
```

- **canonical**은 terminal attempt의 job span이다(`GET .../actions/runs/{id}/jobs?per_page=100&filter=latest`의 `started_at..completed_at`).
- **legacy**는 run 타임스탬프(`run_started_at..updated_at`)이며 라벨이 다른 시계다.
- 두 공식은 `docs/spec/ci_acceptance_contract.md` §6 "Latency"에 정의되어 있고, 수용 지연은 canonical만 쓴다.

역사적 `546 / 560 / 574.5`는 **부적격**이다. 현재 창에서 어느 공식으로도 재현되지 않는다(canonical p50=558.0, legacy p50=560.5). 세 값은 `tests/ci/test_ci_acceptance_collect.nim`의 p50 산술 픽스처(`p50Seconds(@[546, 560, 574]) == 560.0`, `@[546, 560, 589, 600] == 574.5`)로만 남아 있으며, **측정된 수용 지연으로 인용해서는 안 된다**. baseline을 인용할 때는 위 명령과 두 출력 줄을 함께 인용한다.

## §4. PR #210이 고친 collector 결함 2건

### §4.1 `/actions/runs/{id}/attempts` 목록 엔드포인트는 404다

```console
$ gh api repos/Archright/Axiom/actions/runs/44506268193/attempts
{
  "message": "Not Found",
  "documentation_url": "https://docs.github.com/rest",
  "status": "404"
}
gh: Not Found (HTTP 404)
# 공개 대조군에서도 동일:
$ gh api repos/github/docs/actions/runs/44502292697/attempts
{
  "message": "Not Found",
  "documentation_url": "https://docs.github.com/rest",
  "status": "404"
}
gh: Not Found (HTTP 404)
# 관측 표면은 per-attempt다:
$ gh api repos/Archright/Axiom/actions/runs/44506268193/attempts/1
{"conclusion":"success","run_attempt":1,"run_started_at":"2026-11-19T10:30:20Z","status":"completed"}
```

따라서 attempt 관측은 `/attempts/{n}` 단위로만 가능하다. 목록 응답을 전제한 코드는 attempt를 통째로 놓치고, 그 부재는 "성공"이 아니라 gap으로 남아야 한다(fail-closed). 이 저장소 run과 공개 대조군 run 모두에서 404를 반환했다 — 저장소 설정의 문제가 아니라 엔드포인트 표면의 문제다.

### §4.2 경계 이전 attempt gap이 수용 창으로 누출됐다

이전 구현은 모든 항목의 attempt gap을 수용 창의 gap으로 집계했다. 경계 이전 run의 attempt 조회 실패(예: 404)가 창에 섞이면 `observation_complete`가 **영구히 false**가 되고, 수용 상태가 측정 불가로 고정된다.

#210은 gap 집계를 **경계 이후 항목으로 한정**한다. 픽스처가 이를 고정한다(`tests/ci/test_ci_acceptance_collect.nim`):

- `pre-boundary attempt gaps never make the measured window incomplete`
- `in-window attempt gaps are reported with the run identity`

현재 실행에서 `gaps=[]`, `excluded_before_boundary=16`이므로, 창이 빈 지금도 옛 누출은 재현되지 않는다.

## §5. 신원 증거 — App `5795152`와 required context

### §5.1 착지 체인의 App `admission-check`

```console
$ for sha in 082e7245 c0eeeaf1 c97983cf 907eba34 5cee92e1 aa0f78a8; do
    gh api "repos/Archright/Axiom/commits/$sha/check-runs?per_page=100&filter=all" \
      --jq '[.check_runs[] | select(.name=="admission-check" and .app.id==5795152) | .conclusion] | join(",")'
  done
success
success
success
success
success
success
```

여섯 merge head 모두 App `5795152`가 발행한 `admission-check: success`를 가진다. 이름이 같은 Actions(`15368`) check는 별개이며 authority가 아니다(계약 §4.7).

### §5.2 `per_page=100&filter=all`은 필수다 — 기본 페이지는 App run을 숨긴다

```console
$ gh api "repos/Archright/Axiom/commits/aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356/check-runs?per_page=100&filter=all" \
    --jq '{total: .total_count, admission: [.check_runs[]|select(.name=="admission-check")|.app.id]}'
{"admission":[15368,5795152],"total":49}
$ gh api "repos/Archright/Axiom/commits/aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356/check-runs" \
    --jq '{total: .total_count, n: (.check_runs|length), admission: [.check_runs[]|select(.name=="admission-check")|.app.id]}'
{"admission":[15368],"n":30,"total":49}
```

- 기본 `filter`는 `latest`, 기본 `per_page`는 30이다(문서 근거 §8). 기본 페이지(30건)에는 App `5795152` run이 없다 — `per_page=100`이 필수다. (`per_page=100` 단독으로도 App run은 보인다: `{"admission":[15368,5795152],"n":49,"total":49}`.) collector와 이 문서는 이름당 최신 1건이 아니라 전체 check-run을 읽기 위해 `filter=all`도 함께 쓴다.
- `total_count`는 시간 함수다. 앞선 측정 기록은 48건이었고, 위 재조회는 49건이다. 재조회에서 가장 늦게 완료된 check-run은 push CI `readiness-verdict`(`completed_at 2026-11-19T11:14:10Z`)다. 개수를 인용할 때는 조회 시각과 `per_page=100&filter=all`을 함께 적는다.

### §5.3 tip `aa0f78a8`의 required context

| context | producer `integration_id` | conclusion |
|---|---|---|
| `admission-check` | `5795152` (App) | `success` |
| `bsec-integrity` | `15368` | `success` |
| `debt-registry-gate` | `15368` | `success` |
| `generation-acceptance` | `15368` | `success` |
| `axiom-operational-slice` | `15368` | `success` |
| `publication-integrity` | `15368` | `success` |
| `readiness-verdict` | `15368` | `success` |

push CI 워크플로도 같은 head에서 성공했다(워크플로 이름 / check 이름):

| 워크플로 | check name | conclusion |
|---|---|---|
| `axiom-operational-slice.yml` | `axiom-operational-slice` | `success` |
| `fresh-prove-observation.yml` | `fresh-prove-observation` | `success` |
| `trusted-writer-set.yml` | `verify-trusted-writer-set` | `success` |

주의: 세 번째 check의 이름은 `trusted-writer-set`이 아니라 **`verify-trusted-writer-set`**이다(`.github/workflows/trusted-writer-set.yml:41`).

## §6. Ruleset `27097366` — merge authority

```console
$ gh api repos/Archright/Axiom/rulesets/27097366 \
    --jq '{enforcement, bypass_actors, mq: [.rules[]|select(.type=="merge_queue")|.parameters]}'
{"bypass_actors":[],"enforcement":"active","mq":[{"check_response_timeout_minutes":120,"grouping_strategy":"ALLGREEN","max_entries_to_build":2,"max_entries_to_merge":1,"merge_method":"MERGE","min_entries_to_merge":1,"min_entries_to_merge_wait_minutes":0}]}
```

| 필드 | 실측값 |
|---|---|
| `enforcement` | `active` |
| `bypass_actors` | `[]` |
| `merge_queue.grouping_strategy` | `ALLGREEN` |
| `max_entries_to_build` / `max_entries_to_merge` | `2` / `1` |
| `merge_method` | `MERGE` |

required status checks 7개는 §5.3과 동일하며, producer는 `admission-check`만 App `5795152`, 나머지는 Actions `15368`이다. 이 문서는 ruleset 파라미터를 바꾸지 않는다.

## §7. 잔여 리스크 — 위험으로 기록하고 고치지 않는다

1. **단일 계정.** 승인 요구는 `required_approving_review_count=0`, `require_code_owner_review=false`이고 collaborator·org member는 1명이다(`docs/evidence/github_free_parity_2026-11-19.md` §9.2). CODEOWNERS는 강제되지 않는다. 승인 요구를 켜면 승인 가능한 제2 주체가 없어 모든 PR이 정지하므로, 이 문서는 정책 변경을 제안하지 않는다.
2. **App preflight head-이동 레이스.** admission run이 in-flight인 동안 head가 움직이면, stale run의 완료가 **그 시점의 현재 head**에 `run_head_mismatch` failure를 발행하고, 이후 새 run의 success는 그 check-run을 대체하지 않는다. 회복은 같은 head 재실행이 아니라 **새 head**다. 실측 타임라인은 `github_free_parity_2026-11-19.md` §7.6(PR #207), App 동작 서술은 `docs/agents/axiom_admission_verifier_ops.md:55`. `workflow_run`은 이전 run의 conclusion과 무관하게 발화하므로(문서 근거 §8), cancelled run의 완료도 같은 평가 경로를 탄다.
3. **PR-venue admission의 base 신선도.** `pull_request` 경로의 A0 guard는 `pulls/N.base.sha`와 run 시작 시점의 main tip(`B_STAR`)을 비교하고 불일치면 fail-closed한다. `.base.sha`는 base 브랜치 tip이 아니라 merge-base이므로, main이 전진한 뒤에는 **rebase 후 push**해야 한다(`github_free_parity_2026-11-19.md` §7.7 실측: `MINT_A0_ACTIVATION: FAIL`).
4. **미등록 실패 서명은 `unclassified`(fail-closed).** 허용목록 밖 artifact와 log가 모두 텍스트 증거를 주지 못하거나, 어떤 알려진 서명과도 일치하지 않으면 `unclassified`이며 gap이 붙는다 — 추측 분류는 없다(계약 §4.6, `tests/ci/test_ci_acceptance_collect.nim`).
5. **관측 표면의 시간 의존성.** `check-runs` `total_count`는 새 run이 완료되며 변한다(§5.2: 48→49). 인용 시 조회 시각과 `per_page=100&filter=all`을 함께 남긴다. 이는 권위 변경이 아니라 인용 규율이다.

## §8. 문서 근거 (Context7 공식 문서 확인)

본 문서의 비자명한 API 서술은 Context7의 `GitHub Docs`에서 확인했다. 아래 문장은 확인된 원문 인용이다.

| 주장 | 근거 URL | 확인한 문장 |
|---|---|---|
| check-runs의 `filter` 기본값은 `latest`이고 `per_page` 기본값은 30(최대 100) | <https://docs.github.com/en/rest/checks/runs#list-check-runs-for-a-git-reference> | "Filters check runs by their `completed_at` timestamp. `latest` returns the most recent check runs." (enum `latest`, `all`, default `latest`) / "The number of results per page (max 100)." (default `30`) |
| `compare` 응답의 `status`는 `diverged` / `ahead` / `behind` / `identical` | <https://docs.github.com/en/enterprise-cloud@latest/rest/commits/commits#compare-two-commits> | "**status** (string, enum: `diverged`, `ahead`, `behind`, `identical`) - Required" |
| `workflow_run`은 run이 요청되거나 완료될 때 발생하며 conclusion과 무관하다 | <https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run> | "This event occurs when a workflow run is requested or completed." / "A workflow run is triggered regardless of the conclusion of the previous workflow." |

`compare`의 `status`는 collector의 경계·replacement 판정에도 그대로 쓰인다: `ahead`/`identical`만 경계 이후(또는 후속 base)로 인정하고, `behind`/`diverged`는 제외한다(`tools/ci/ci_acceptance_collect.nim`의 `fetchAncestry`, `queueBaseContains`).

Context7 확인 중 불일치(문서가 주장을 부정하는 사례)는 없었다. 다만 `compare`의 `status` enum은 `/github/docs` 청크에서는 노출되지 않고 `/websites/github_en`(GHEC 렌더 페이지)에서만 확인됐다 — 인용 URL은 확인된 그 페이지다.

## §9. 이 문서가 주장하지 않는 것

- 수용이 정규화됐다는 주장. 창은 `0/20`이고 상태는 `INCOMPLETE`다.
- authority·threshold·required check·ruleset 변경. 이 PR은 테스트 픽스처와 본 문서만 추가한다.
- CI 배선 추가. collector는 어떤 워크플로에도 연결되지 않았고, 호출은 수동이다.
- merge. 이 PR은 큐에 등록되지 않으며 auto-merge도 켜지 않는다.
- `github_free_parity_2026-11-19.md`의 값 재측정. 그 문서는 그 시점의 스냅샷이고, 본 문서는 수용 상태만 동결한다.

## §10. 재현 명령

```console
# 수용 창 (exit 2 = INCOMPLETE)
bin/ci_acceptance_collect --repo Archright/Axiom \
  --boundary aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356 --window 20 --mode initial

# baseline (exit 0)
bin/ci_acceptance_collect --repo Archright/Axiom --baseline-live \
  --window 40 --baseline-until 2026-11-19T08:00:00Z

# 착지 체인과 App admission-check (6회)
for sha in 082e7245 c0eeeaf1 c97983cf 907eba34 5cee92e1 aa0f78a8; do
  gh api "repos/Archright/Axiom/commits/$sha/check-runs?per_page=100&filter=all" \
    --jq '[.check_runs[] | select(.name=="admission-check" and .app.id==5795152) | .conclusion] | join(",")'
done

# 기본 페이지가 App run을 숨기는지
gh api "repos/Archright/Axiom/commits/aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356/check-runs" \
  --jq '[.check_runs[]|select(.name=="admission-check")|.app.id]'

# attempts 목록 404 / per-attempt 관측
gh api repos/Archright/Axiom/actions/runs/44506268193/attempts
gh api repos/Archright/Axiom/actions/runs/44506268193/attempts/1

# ruleset
gh api repos/Archright/Axiom/rulesets/27097366
```