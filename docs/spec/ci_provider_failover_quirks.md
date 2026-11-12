# GHEC ↔ Fallback Provider (Ubicloud/OVH) CI Provider Failover Quirks (GitHub Actions billing/concurrency/identity + Ubicloud/OVH runner infrastructure)

> AGENTS.md §0.5 Quirk Mandate — documented toolchain quirks must live in
> `docs/spec/` and be referenced from `docs/agents/constitution_details.md`
> §0.5b (AGENTS.md 본문은 FROZEN — §-1).
>
> **Discovered**: 2026-10-23 (GHEC↔Ubicloud 양방향 failover 제어기 설계·구현 —
> `feat/ci-provider-router`; 측정/부트스트랩 기록
> `docs/evidence/ci_provider_failover_2026-10-23.md`)
> **Class**: external platform behavior — GitHub Actions billing/budget
> hard-stop, `workflow_run`/`rerun`/`concurrency` semantics, `GITHUB_TOKEN`
> permission surface, GitHub-hosted vs self-hosted (Ubicloud/OVH) runner identity.
> 인접 문서: `docs/spec/runner_group_addressing_quirks.md`(runner group 주소
> 지정·rerun 0-step 재실행 실측), `docs/spec/gh_run_observation_quirks.md`
> (rerun identity 재생), `docs/spec/gh_org_required_workflow_run_quirks.md`.
>
> Tagging: **[documented]** = verified against official documentation
> (live docs.github.com fetch — URL + quoted sentence given) or the vendor's
> public source/console (Ubicloud — source cited as recorded in the 2026-10-23
> plan session). **[measured]** = observed live on the cited run/command.
> **[documented↔measured mismatch]** = live observation contradicts the
> documented contract. **[derived]** = judgment derived from the cited
> observations and documented contracts (simulations marked as such).
> **[pending-U*]** = open measurement item from the
> failover plan's UNKNOWN table.

---

## Q1 — `workflow_run` fires for 0-step budget-blocked runs: run-lifecycle events do not require any step to have executed

### Symptom [measured]

Block window 2026-10-23 (03:10Z — see
`docs/evidence/ci_provider_failover_2026-10-23.md`): admission-gate run
**39893960477** (pull_request event) failed at 03:14:40Z with **every failed
job 0-step** — `runner_id: 0`, `steps: []`, labels `["ubuntu-24.04"]`,
`runner_group_name: ""` (16 jobs measured; failures within ~17s of run
creation, no job ever reached a runner). The Actions budget hard-stop was the
cause (Q2). Despite **zero executed steps**, the run's completion still emitted
a `workflow_run` (completed) event: `ci-cache-publisher` run
**39893993637** started 03:15:02Z as `event: workflow_run` — 22s after the
blocked run's creation. Measured **10/10** across the block window (plan
session measurement, 2026-10-23).

### Documented basis

- **[documented]** Events that trigger workflows, `workflow_run`
  (https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run,
  fetched 2026-10-23): "This event occurs when a workflow run is requested or
  completed." The event is emitted by the **run lifecycle**, not by job
  execution — and a 0-step blocked run IS a completed run (`conclusion:
  "failure"`). The same page requires the listener workflow to exist on the
  default branch for the event to fire.

### Cause

The scheduler never assigns a runner (budget gate rejects before dispatch), but
the run object still completes with `failure`. `workflow_run` delivery is
keyed on run-state transitions, so a run in which nothing ran is an
indistinguishable event source from a fully-executed run.

### Sanctioned workaround / consequence

- The provider-failover controller MAY rely on `workflow_run` as its
  block-detection trigger even while the budget hard-stop is active — detection
  does not need a successful run first.
- The controller MUST classify by **job fields** (`runner_id == 0`/`null`,
  `steps == 0`, expected GHEC labels), never by `conclusion` alone — a 0-step
  failure and an executed failure emit identical run-level conclusions.

---

## Q2 — the Actions budget hard-stop blocks GitHub-hosted runners ONLY; self-hosted (Ubicloud) dispatch is outside its reach

### Symptom [measured]

2026-10-23, org `Archright` enterprise billing (plan session measurement):
`actions_linux` **<linux-min>** + `slim` **<slim-min>** minutes > <budget-minutes> included;
Actions budget **$0** with `prevent_further_usage=true`. From **03:10Z** every
GitHub-hosted job failed pre-dispatch (Q1's 0-step signature). No Ubicloud
runner existed yet (repo runners `total_count: 0`, measured 2026-10-23), so no
self-hosted dispatch was attempted in the window.

### Documented basis

- **[documented]** Billing docs, "About billing for GitHub Actions"
  (https://docs.github.com/en/billing/concepts/product-billing/github-actions,
  fetched 2026-10-23): included minutes and Actions spending apply to
  **GitHub-hosted runner** usage; self-hosted runners do not consume Actions
  minutes. A budget whose enforcement domain is Actions usage therefore cannot
  deny a self-hosted (Ubicloud) job.
- **[pending-U1]** That the *dispatch path* for a self-hosted-labeled job
  actually succeeds while the budget gate is tripped is the failover plan's
  open measurement U1 — `runner-pool-acceptance.yml` (workflow_dispatch) on a
  live Ubicloud runner is the sanctioned probe. Do not declare the failover
  design "proven" until U1 is observed.

### Cause

The budget gate is an enforcement point in the GitHub-hosted dispatch path
(minute accounting), not a repo-wide Actions freeze.

### Sanctioned workaround

- Treat "0-step blocked run" as the machine-observable signal of budget
  exhaustion; the sanctioned recovery is routing the required checks to
  Ubicloud labels via `CI_RUNNER_MAP` — never raising the budget.
- GitHub net billing must remain 0 across any failover (G6 contract).

---

## Q3 — `GITHUB_TOKEN` has no `variables` permission: repository-variable writes require a GitHub App (Variables read/write)

### Symptom (would-be)

`gh api -X PATCH repos/<owner>/<repo>/actions/variables/CI_RUNNER_MAP ...`
authenticated with `GITHUB_TOKEN` fails with 403 regardless of the workflow
`permissions:` block.

### Documented basis

- **[documented]** Workflow syntax for GitHub Actions, `permissions`
  (https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions,
  fetched 2026-10-23): the enumerated GITHUB_TOKEN scopes are `actions`,
  `artifact-metadata`, `attestations`, `checks`, `code-quality`, `contents`,
  `copilot-requests`, `deployments`, `discussions`, `id-token`, `issues`,
  `packages`, `pages`, `pull-requests`, `security-events`, `statuses`,
  `vulnerability-alerts` — **`variables` is not in the list**. Same page:
  "If you specify the access for any of these permissions, all of those that
  are not specified are set to none."
- **[documented]** Automatic token authentication
  (https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication,
  fetched 2026-10-23): "If you need a token that requires permissions that
  aren't available in the GITHUB_TOKEN, create a GitHub App and generate an
  installation access token within your workflow."

### Sanctioned workaround

- Mint a short-lived installation token **in-job** from a GitHub App whose
  repository permission ceiling is `Variables: read/write` (+ `Metadata: read`
  for the App to resolve the installation) — pinned
  `actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510`
  with `permission-variables: write`, `permission-metadata: read`; secrets
  held in the `ci-provider-router` environment
  (`.github/workflows/ci-provider-router.yml`).
- `GITHUB_TOKEN` keeps `actions: write` + `checks: read` for
  rerun/dispatch/polling — the two tokens are never interchangeable.

---

## Q4 — `rerun-failed-jobs` re-runs never-started (0-step) failures: the sanctioned post-transition verification path

### Symptom [measured 2026-10-11]

`POST /repos/Archright/Axiom/actions/runs/38110128893/rerun-failed-jobs`
re-executed `closure-deriver` — a job whose attempt-1 object was
`runner_id: 0`, `steps: []` (pre-dispatch failure). Attempt 2 ran it on a real
runner (`runner_id: 1000016520`, 9 steps). Full measurement:
`docs/spec/runner_group_addressing_quirks.md` Q4 (in-progress 403 "This
workflow is already running" is undocumented but real; re-runs replay the
original event's SHA/ref/actor).

### Applied by design [2026-10-23, pending-U5]

The failover controller's GHEC→Ubicloud transition writes `CI_RUNNER_MAP`
FIRST and only then calls `rerun-failed-jobs` once on the blocked run —
because 0-step failures count as "failed jobs", the rerun re-dispatches them
under the NEW label map. Run **39893960477** is the designed live target
(U5); production mutation was 0 at authoring time (evidence doc §8).

### Deterministic consequence

- Attempt-2 routing evidence is asserted per-job:
  `runner_id > 0`, `steps > 0`, labels ⊇ the new (Ubicloud) label. A rerun
  whose jobs still report 0-step leaves the transition write
  "successful-but-unverifiable" → the controller records `state=UNKNOWN`
  (mode unchanged) and fails the job (H16 — distinct from a failed write,
  which writes nothing at all).
- Rerun is bounded: `conclusion == failure ∧ run_attempt == 1 ∧ terminal ∧
  non-fork`, at most once per run id.

---

## Q5 — concurrency `queue: max` caps at 100 pending; a FULL queue cancels new runs (single-writer serialization is lossy)

### Documented basis

- **[documented]** Workflow syntax, `concurrency`
  (https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#concurrency,
  fetched 2026-10-23): "queue property accepts the following values: single
  (default): At most one job or workflow run can be pending… **max**: Up to
  100 jobs or workflow runs can be pending in the concurrency group. **When
  the queue is full, any additional jobs or workflow runs are canceled.**"
- **[documented]** Same section: "The combination of queue: max and
  cancel-in-progress: true is not allowed and will result in a workflow
  validation error."
- **[documented]** Same section, ordering: "Jobs or workflow runs in the same
  concurrency group are processed in first-in-first-out (FIFO) order according
  to the time each one started waiting on the concurrency group… Since the
  actual start time of a job or run may vary, **ordering is not guaranteed**."

### Consequence (controller design)

- `ci-provider-router` uses `concurrency: {group: ci-provider-router,
  cancel-in-progress: false, queue: max}` — five simultaneous required-check
  completions serialize behind one router run; variable-write races are
  structurally impossible (single writer).
- The serialization is **lossy by contract**: a burst > 100 pending cancels
  the newest router runs silently. The `7,37 * * * *` schedule is the
  designated reconciliation path — a canceled event-driven run converges on
  the next tick. Do not "fix" this by widening triggers or dropping the
  concurrency group.

---

## Q6 — `workflow_run.path` may carry an `@ref` suffix: normalize before comparing; exact bare-path matching is unsound

### Documented basis

- **[documented]** REST "Get a workflow run" response examples
  (docs.github.com REST reference, Actions → Workflow runs) show `"path"` as
  `.github/workflows/main.yaml` **and** suffixed forms such as
  `...yaml@main` in current examples (recorded in the 2026-10-23 plan
  session's live docs read).

### Measured [2026-10-23]

Run **39893960477**'s run object reports `path` **without** a suffix:
`.github/workflows/admission-gate-v2.yml`. Both shapes therefore occur in the
wild — suffix presence is not stable across API generations/events.

### Sanctioned workaround

- Identity guard = strip everything from the first `@` onward
  (`NPATH="${RAW_PATH%%@*}"`), THEN compare against the known-path set
  (`.github/workflows/admission-gate-v2.yml` — the org required workflow's
  observed path, display name `admission-gate` — plus the four in-repo
  required-check workflows). Never exact-match the raw path, and never
  exact-match a bare path either.
- The workflow-name trigger filter (`workflows:` list) is a wide net only
  (H11 — renames de-synchronize it); the path guard is the identity
  authority.

---

## Q7 — Ubicloud runner identity: Default group id 1, support-only custom labels, NO hard spending cap, per-job ceil billing

### Documented basis (Ubicloud public source / console, recorded in the 2026-10-23 plan session)

- **[documented]** Ubicloud JIT runners register into the repository-level
  **Default runner group (id 1)** — `runner_group_id: 1` on jobs they execute.
- **[documented]** Custom labels on Ubicloud runners are created only by the
  Ubicloud support team via an internal admin console — a tenant cannot mint
  them from the public API/console.
- **[documented]** Ubicloud provides **no hard spending cap**. The only cost
  control is a `UsageAlert` (email-only, configured on the console Billing
  page, no API/CLI) and "no action is taken automatically" — declare
  `COST_CAP_UNVERIFIED`; never claim a total-CI-cost hard cap.
  Source-level confirmation [2026-10-23]: `model/usage_alert.rb` sends an
  informational email whose body states the alert "is only for informational
  purposes and no action is taken automatically"; `Prog::CheckUsageAlerts`
  runs every 5 minutes and only triggers the email. The only structural brake
  is `ProjectQuota` (per-project vCPU quotas by account reputation tier,
  enforced at resource-creation time) — it bounds *concurrent* runners, not
  spend.
- **[documented]** Ubicloud bills per job with per-minute **ceiling** rounding
  (minimum 1 minute per job) — every router/canary run costs ≥ 1 minute on its
  SKU regardless of actual duration.
- **[measured 2026-10-23]** SKU and rate resolved (supersedes the earlier
  `[pending-U4]` console question): the failover map runs `ubicloud-standard-2`.
  These are ephemeral JIT runners — the registered set churns with demand
  (observed `total_count` 5–10 during active merges, every entry `online`,
  label set exactly `["ubicloud-standard-2"]`); jobs observe
  `Image: ubuntu-24.04`, `VM Family standard`, `Image github-ubuntu-2404`.
  Rate from Ubicloud's own
  billing table (`config/billing_rates/github.yml`, `active_from`
  2026-09-01): `standard-2` = **$0.00125/min**, `standard-4` = $0.0025,
  `standard-8` = $0.005, `premium-2` = $0.002. Billing is per minute actually
  run, never while idle. The 2026-04-27 "new customers cannot use standard
  x64" caveat does not apply to this account — standard-2 runners are
  provisioned and executing.

### Measured [2026-10-23]

- GitHub-hosted identity on **executing** jobs: `runner_group_id: 0` ∧
  `runner_group_name: "GitHub Actions"` (plan session measurement). Pre-dispatch
  blocked jobs report `runner_group_id: 0`, `runner_group_name: ""` (run
  39893960477 job table) — the group id alone never discriminates without the
  running-state fields.
- Org installations include `ubicloud-managed-runners`
  (`repository_selection: all`); repo runners `total_count: 0` (pre-bootstrap;
  JIT runners only appear on first workflow_job). Delta vs the plan session's
  "App absent" recorded in the evidence doc §7.

### The alias collision (H15/M9)

A support-created custom label aliasing `ubuntu-24.04` to Ubicloud runners
would let a `runs-on: ubuntu-24.04` GHEC canary **succeed on Ubicloud** — a
false return-to-GHEC signal (routing predicate passes, identity is wrong).

### Sanctioned workaround

- Never use custom-label aliases for required checks or the canary; route via
  the `CI_RUNNER_MAP` label fields only.
- Verify provider identity by **assignment metadata**, separately from labels:
  GHEC ⇔ `runner_group_id == 0` ∧ `runner_group_name ∈ {"", "GitHub
  Actions"}`; Ubicloud ⇔ `runner_group_id == 1` (Default group). The canary
  fails `WRONG_PROVIDER` (exit 1) on any non-zero group id regardless of job
  success.

---

## Q8 — self-hosted (Ubicloud) runners have no isolation: environment secrets are repo-secret-grade exposures

### Documented basis

- **[documented]** Comparing GitHub-hosted and self-hosted runners /
  security hardening (https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners,
  fetched 2026-10-23): self-hosted runners do not guarantee a clean, isolated
  container per job; workflows run with access to the host environment, and
  secrets available to the job are exposed to anything the job executes.

### Sanctioned workaround (controller posture)

- The router and canary execute **no repository code** — no `checkout`, no
  PR-controlled input reaches a `run:` block (workflow_run security boundary:
  the triggering run's code is never executed by the listener).
- The App token is minted in-job (per-run), `add-mask`ed, never written to
  logs/artifacts, and revoked by the action's post step; the App's ceiling is
  `Variables: read/write` only.
- Environment secrets on a self-hosted runner are treated as repo-secret-grade
  exposure: rotation cadence is a human handoff item (H10/H18).

---

## Q9 — `actions/create-github-app-token@64ab729a` (v3.3.0): undeclared `permission-variables` is passed through as request key `variables`, mismatching the installation's `actions_variables` → 422

### Symptom [measured 2026-10-23, run 39925970647]

Router App-token mint step failed with
`422 The permissions requested are not granted to this installation` at
`POST /app/installations/174407656/access_tokens`, while the runner printed
`Unexpected input(s) 'permission-variables', valid inputs are […no
variables-like key at all…]` — the action's v3.3.0 input schema declares no
`permission-variables` input, yet the value still reached the token request as
the request key `variables`.

### Cause

- The installation's granted permission key is **`actions_variables`**
  (measured via `GET /orgs/Archright/installations` →
  `{"actions_variables":"write","metadata":"read"}`; the App's
  `GET /apps/axiom-ci-provider-router` returns the same shape). The REST docs
  render this permission as "Actions variables" (display) while the
  installation-token API keys it as `actions_variables`.
- The action passes undeclared `permission-*` inputs through to the token
  request verbatim after the `permission-` prefix (`permission-variables` →
  `variables`), which this installation does not hold → 422. Declared
  per-issuance reduction inputs are therefore unusable for this permission
  with this action version.

### Sanctioned workaround

- Omit ALL `permission-*` inputs and let the token **inherit the
  installation's permissions** (the action's documented default). For a
  least-privilege App (`actions_variables:write + metadata:read` only),
  inheritance IS the minimal set — the per-issuance reduction goal is met by
  the App installation itself, not the token request.
- The minted token is then verified functionally: the router's variable GET
  (and every PATCH) fails closed on any 4xx, so a wrong-scope token can never
  silently pass.

---

## Q10 — `schedule` is not a dependable clock in this repository: a 30-minute cron stayed silent for its first 9+ slots, then fired severely late and irregularly (delayed-and-irregular, not dead)

### Symptom [measured 2026-10-23]

- `ci-provider-router` (workflow id 393813610) landed on `main` carrying
  `schedule: ['7,37 * * * *']`, is `state: active`, and the `on:` block parses
  correctly (PyYAML: `schedule: [{'cron': '7,37 * * * *'}]`).
- Nevertheless all five elapsed slots (09:07Z, 09:37Z, 10:07Z, 10:37Z, 11:07Z)
  produced **zero** runs: `GET /actions/workflows/ci-provider-router.yml/runs?event=schedule`
  returns an empty set, and no run is left pending/queued either.
- Ruled out: concurrency saturation (last 18 runs average 22.7 s — ~10%
  occupancy), YAML error, workflow disabled (`state: active`), and
  repository-wide schedule suppression (schedules of `admission-ssot-drift`
  and `closure-watcher` did fire in the same window).

### Measured addendum [live 2026-10-24] — the cron does fire; late and irregular, not dead

- The first firing landed the same day: `ci-provider-router` schedule run
  **`39963885722`**, created **2026-10-23T13:45:39Z** — its slot was 13:37Z,
  so it fired **~8.5 minutes late** — conclusion `success`, decision line
  `{"router":{"event":"schedule","mode":"ubicloud","action":"noop","result":"OK","reason":"trial_not_eligible"}}`
  (job log, verbatim). Slots 09:07Z–13:07Z (9 consecutive) remained at zero.
- Schedule-run history re-observed 2026-10-24 (`GET
  /actions/workflows/ci-provider-router.yml/runs?event=schedule&per_page=20`):
  **4 runs total to date**, all `success` — `39963885722` (13:45:39Z),
  `40001694634` (18:14:37Z), `40027952697` (21:36:03Z), `40042558687`
  (23:58:12Z). Measured gaps between the four firings: **4h28m58s, 3h21m26s,
  2h22m09s** — a 30-minute cron delivering at hour-scale irregular intervals.
- Corrected statement: the 30-minute cron is **severely delayed and
  irregular, not dead** — it does eventually fire, so it can still serve as a
  best-effort backstop (e.g. the 23:58:12Z firing carried the first
  post-cooldown trial after the #1068 guard). It is still **not a dependable
  clock**: nothing near the nominal cadence, gaps of hours, and no local way
  to distinguish "delayed" from "dropped" until a run appears. The
  activity-event carrier (rule 5) remains the operative fix.

### Documented basis

- GitHub docs: "The `schedule` event can be delayed during periods of high
  loads… If the load is sufficiently high enough, some queued jobs may be
  dropped." (`events-that-trigger-workflows#schedule`) — `schedule` is
  best-effort, not a guarantee.
- This repository already documents the same phenomenon: `closure-watcher`'s
  header defines "slot +60 minutes = on-time" and states the structural limit
  that "cron cannot detect its own non-firing". Measured drift is large —
  `admission-ssot-drift` (cron `37 4 * * *`) last fired at 09:32Z, ~5 hours
  after its nominal slot.

### Cause

- Undetermined (platform-internal). What IS established is the observed
  behavior: using a 30-minute cron as the sole trigger for the GHEC return
  leaves the return untriggered across hour-scale gaps (measured: 9+
  consecutive silent slots, then firings 8.5 minutes to ~4h29m off the nominal
  cadence) — delivery timing cannot be planned on it.

### Sanctioned workaround

- Evaluate the GHEC-return trial on an **activity event** as well: add
  `push: branches: [main]` so every merge to `main` re-evaluates trial
  eligibility. The eligibility gate, cooldown, and canary predicate are reused
  unchanged (zero shell-logic delta), so the return is decided
  deterministically on the first `main` merge of the new billing period.
- Keep `schedule` as the best-effort backup for idle periods, but **never make
  the return depend on cron alone** — the reason rule 5 is stated as it is.

---

## Q11 — 예산 hard-stop과 "포함량 소진"은 같은 사건이 아니다: 차단은 `prevent_further_usage` 예산 도달의 서명이고, 소진 자체는 과금 전환일 뿐이다

### Documented basis

- **[documented]** Billing cycles
  (https://docs.github.com/en/billing/concepts/billing-cycles,
  fetched 2026-10-24): "Metered products, and all payments made using an
  Azure subscription ID, have a fixed **billing period** that starts at
  00:00:00 UTC on the first day of each month and ends at 23:59:59 UTC on the
  last day of the month." — GHEC 표준 러너 월 포함량 **<budget-minutes>**의 리셋은
  **고정 달력월 경계**(매월 1일 00:00:00 UTC 시작 ~ 말일 23:59:59 UTC 종료)다.
  포함량 수치는 About billing for GitHub Actions
  (https://docs.github.com/en/billing/concepts/product-billing/github-actions,
  fetched 2026-10-24)의 included-quotas 표(GHEC 플랜 "Minutes (per month)"
  <budget-minutes>)와 같은 페이지의 "Your free minutes reset to the full amount at the
  start of each billing cycle"가 함께 규정한다.
- **[documented]** 같은 페이지: "Any usage beyond the included amounts is
  billed to your account." — **소진 자체는 실행을 막지 않는다**. 결제수단이
  있으면 초과분은 과금된다. 실행 차단은 ① 결제수단 부재 또는 ② hard budget
  (`prevent_further_usage` — REST Budgets
  https://docs.github.com/en/rest/billing/budgets 의 limit-enforcement 필드,
  콘솔 라벨 "Stop usage when budget limit is reached") 도달 때 발생한다. Set
  up budgets (https://docs.github.com/en/billing/how-tos/set-up-budgets,
  fetched 2026-10-24): "if any budget with **Stop usage when budget limit is
  reached** enabled is exhausted, additional usage is blocked", 그리고 Actions
  예산 소진 예시의 결론 문장 — "Members are now blocked from using all
  GitHub-hosted runners **until the next billing cycle or until the 'Actions'
  product budget is increased**." 즉 예산 재개 조건은 다음 청구 주기 또는
  예산액 상향뿐이다(우리는 예산 상향 금지 — M3).
- **[measured 2026-10-24]** 이 조직의 Actions product budget은
  `budget_amount: 1`, `prevent_further_usage: true`
  (`GET /organizations/Archright/settings/billing/budgets`; $0 표기 정정 이력은
  `docs/evidence/ci_provider_failover_2026-10-23.md` [live 2026-10-24]
  참조). 따라서 블록 창(2026-10-23T03:10Z, Q1/Q2)에 관측한
  `runner_id=0/steps=0` 사전 실패는 **예산 hard-stop의 서명**이지 포함량
  소진의 직접 효과가 아니다 — 포함량 <linux-min>분 소진(Q2 재관측값)만으로는
  차단이 성립하지 않는다.

### 리셋 감지 수단 — 전부 부재다 (관측 계약)

- **[documented]** GitHub에는 리셋 전용 플래그·웹훅이 없다 — 워크플로 트리거
  이벤트 카탈로그(events-that-trigger-workflows, fetched 2026-10-24)의 이벤트
  전수 열거에 billing/리셋 관련 이벤트가 0건이다.
- **[documented]** usage API `GET /organizations/{org}/settings/billing/usage`
  (+`/usage/summary` — "This endpoint is in public preview",
  https://docs.github.com/en/rest/billing/usage, fetched 2026-10-24)는
  fine-grained 토큰에 **"Administration" organization permissions (read)** 를
  요구한다(같은 페이지 권한 테이블). 라우터 App은 `actions_variables:write` +
  `metadata:read`뿐이라(Q9) 이 엔드포인트에 접근할 수 없다 — 접근은 fail-closed.
- **[documented↔measured mismatch]** 기본 월 파라미터(2026-10-24, owner 토큰
  `gh api` 실측): `/usage/summary` 무파라미터 → `timePeriod {2026, 10}` —
  **현재 월**(문서 "Default value is the current month"과 일치).
  `/usage`(report) 무파라미터 → **2026-09 행과 2026-10 행이 함께 반환** — 문서
  기본값("Default value is the current year/current month")과 상이하게 전월
  데이터가 포함된다. `year`/`month`를 명시하면 해당 월만 정확히 반환(2026-10,
  2026-9 각각 실측). → 월 경계 판독에 이 API를 쓴다면 year/month **명시 고정**이
  필수이고, 그 전제조차 App 권한 때문에 무의미하다. 리셋 감지는 (a) 고정
  달력월 경계의 계산적 판정(매월 1일 00:00:00 UTC)과 (b) canary 시험으로만
  수행한다.
- **[measured 2026-10-24]** 예산 API에 소비량 필드가 없다:
  `GET /organizations/Archright/settings/billing/budgets` 실측 응답(4개 예산,
  전부 `ProductPricing`/`organization` 범위)에는 `consumed_amount`가 없다 —
  OpenAPI 스키마(github/rest-api-description `budget`)에는 존재하지만 설명이
  "The amount consumed for a **user-scoped** budget, or for a multi-user
  budget when filtering by user"로 한정되므로 organization 범위 Actions 예산에는
  반환되지 않는다. 즉 예산 API로도 "예산 대비 소비량"을 판독할 수 없다.

### Ubicloud — usage/billing API 부재 (비용 추정 엔진을 의도적으로 만들지 않는다)

- **[documented]** ubicloud/ubicloud `openapi/openapi.yml`(main, fetched
  2026-10-24): 전체 경로 열거 기준 billing/usage/invoice/cost 경로 **0건**
  (유일한 usage 매치는 inference 메트릭 예시 `cpu_usage`). `ubi` CLI는 같은
  OpenAPI의 Go 클라이언트(`cli/ubi.go`, billing/usage 문자열 0건)이므로 SDK/
  CLI 경로도 없다 — **웹 콘솔 전용**.
- Q7(`UsageAlert` email-only, "no action is taken automatically")과 합치면:
  소비량 판독·지출 강제 모두 제공자 API 계약에 없다. 비용 추정 엔진은 권위
  없는 두 번째 제어계가 되므로 **의도적으로 구현하지 않는다** — 월 1회
  콘솔/인보이스 수동 확인이 유일한 비용 관측이다(런북:
  `docs/evidence/ci_provider_monthly_trial_2026-10-24.md`).

---

## Q12 — 실행 메타데이터 판정식은 문서 계약이 아니라 이 저장소 전용 실측 predicate다: `runner_group_id`만으로는 실행/차단을 구분할 수 없다

### Documented basis

- **[documented]** REST "Get a job for a workflow run"
  (https://docs.github.com/en/rest/actions/runs?apiVersion=2022-11-28#get-a-job-for-a-workflow-run,
  fetched 2026-10-24): `runner_group_id` = "The ID of the runner group to
  which this job has been assigned. (If a runner hasn't yet been assigned,
  this will be null.)" — **example: 2**, nullable.
  **"`0`을 GitHub-hosted로 정의하는 문장은 어디에도 없다.** (`runner_id`
  example 1, `runner_group_name` example "my runner group" — 네 필드 모두
  배정을 서술할 뿐 제공자 식별값을 규정하지 않는다.)
- **[documented]** 같은 스키마의 `steps` 예시는 `Set up job`/`Complete job`
  (자동 스텝)을 포함한다 → **`steps > 0`은 자동 스텝만으로 성립한다** —
  "사용자 워크로드가 실행됐다"의 증거가 될 수 없다.

### Measured [2026-10-24, `gh api` 재관측]

- **실행 성공 사례** — run **39887775254**(워크플로 `debt-registry-gate`,
  event `merge_group`, created 2026-10-23T02:06:41Z — 블록 창 03:10Z 이전),
  job `debt-registry-gate`, conclusion **success**: `runner_group_id=0`,
  `runner_group_name="GitHub Actions"`, `runner_id=1000034800`,
  `runner_name="GitHub Actions 1000034800"`, `labels=["ubuntu-24.04"]`,
  steps 9개 — `Set up job`, `Run actions/checkout@…`, …, `Complete job`.
- **차단 사례** — canary run **39985651083**(failure, 복귀수용 문서 §8):
  `runner_group_id=0`이지만 `runner_group_name=""`, `runner_id=0`,
  `runner_name=""`, steps 0개.
- **[derived]** 두 사례가 `runner_group_id=0`을 공유한다 — **group id 단독으로는
  실행/차단을 구분할 수 없다**. 구분은 `runner_group_name` + `runner_id` +
  steps의 결합으로만 가능하다. 이는 0-step 차단 canary에서
  `all_ghec_identity=true`였던 관측(복귀수용 문서 §8)과 정합 — group id는
  "배정 슬롯의 제공자"만 말하지 "실행 가능성"을 말하지 않는다.
- **[derived]** 따라서 GHEC 판정은 **이 저장소 전용 실측 predicate**이며 다른
  조직/러너 구성으로 일반화하지 않는다: "GHEC에서 실행됐다" ⇔
  `runner_group_id == 0` ∧ `runner_group_name ∈ {"", "GitHub Actions"}` ∧
  `runner_id > 0` ∧ **canary의 명명된 identity 스텝 성공**(ghec-canary의
  `Verify GitHub-hosted provider identity (runner_group_id==0 + group name +
  API/local coherence)` 스텝 — steps>0 단독은 자동 스텝으로 충족되므로
  불충분).

### Rerun 의미론 (Q12 부속) — 재실행은 복귀 acceptance 증거가 아니다

- **[documented]** Re-running workflows and jobs
  (https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs,
  fetched 2026-10-24): "The workflow will also use the same `GITHUB_SHA`
  (commit SHA) and `GITHUB_REF` (git ref) of the original event that
  triggered the workflow run."; "A workflow run can be re-run a maximum of
  **50 times**. This limit includes both full re-runs and re-runs of a subset
  of jobs."; 도입문: "…up to **30 days** after its initial run."
- **[documented]** 재실행 시 `vars`가 재평가되는지는 같은 페이지에 **없다**
  (침묵 — 보존을 명시하는 것은 권한·SHA·ref뿐) → 재실행을 "복귀 acceptance"
  증거로 쓰지 않는다. acceptance는 **전환 이후 새로 생성된** required run으로만
  판정한다(재평가 침묵 하에서 rerun이 옛 변수를 그대로 옮긴다는 가정이 유일한
  안전 가정이다).
- **[documented]** self-hosted 큐: "If the job remains queued for more than
  **24 hours**, the job will fail."
  (https://docs.github.com/en/actions/reference/runners/self-hosted-runners,
  fetched 2026-10-24); `timeout-minutes`는 "The maximum number of minutes to
  let a job run before GitHub automatically cancels it" — **실행 시간**에만
  적용(러너 대기 시간 제외, workflow-syntax).
- **[documented]** 필수 체크 성공 집합: "Successful check statuses are
  `success`, `skipped`, and `neutral`."
  (https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks,
  fetched 2026-10-24); 보고되지 않은(queued) 체크는 pending으로 남아 병합을
  막는다 — 같은 페이지 "Associated checks stay in a 'Pending' state and block
  merging".

---

## Q13 — `workflow_run` 기반 워크플로의 체크는 PR 필수 체크가 아니다

### Documented basis

- **[documented]** Troubleshooting required status checks
  (https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks,
  fetched 2026-10-24): "For checks created by workflow jobs to be evaluated
  for a pull request, the workflow run must be triggered by one of these
  events: **`push`, `pull_request`, `pull_request_review`,
  `pull_request_target`, `deployment`, `deployment_status`**." 같은 절:
  `workflow_dispatch`로 PR 헤드 브랜치에서 돌린 워크플로의 잡 체크는 PR checks
  섹션에 나타나지 않고, 헤드 커밋에서 통과해도 branch ruleset의 required
  status check를 만족하지 않는다. "This restriction applies only to checks
  created by workflow jobs, not to checks created by an external GitHub App."
- 라우터는 체크를 만들지 않고 변수만 바꾸므로(`CI_RUNNER_MAP` PATCH 단일 쓰기,
  Q3/Q9) 현행 설계는 영향 없다 — 이 항목은 **향후 "workflow_run 워크플로에
  필수 체크를 기대"하는 설계를 막기 위해 기록한다**: `workflow_run`은 허용
  이벤트 6종에 없으므로 그 잡의 체크는 required 슬롯을 채울 수 없다.
- **[documented]** `workflow_run`의 식별 의미론(events-that-trigger-workflows
  이벤트 표, fetched 2026-10-24): 그 실행의 `GITHUB_SHA` = "Last commit on
  default branch", `GITHUB_REF` = "Default branch"; `workflows:` 필터는
  워크플로 **이름** 매칭이다. → 트리거 원인 실행을 식별하려면 리스너 run의
  SHA가 아니라 페이로드의 `workflow_run.created_at`/`head_sha`/`path`를 써야
  하며(Q6의 `@ref` 정규화와 결합), 이름 필터는 Q6/H11대로 identity
  authority가 아니다.

---

## Q14 — provider policy table: mode→state/label authority, the `fallback_provider` field, and the OVH fallback [2026-10-26]

### Context [derived — policy generalization]

The failover state machine was Ubicloud-specific at five write/classification
sites (schema mode/state enums + label pin, UNKNOWN resolution, the (2-b)
observation branch, the GHEC-block transition write, the schedule-path
summaries). Generalizing to N fallback providers replaces those literals with
ONE policy table and ONE optional policy field; the provider name and labels
are never hardcoded at a write site again.

### The policy table (single authority — `ci-provider-router.yml` [router] step)

| mode | state | x64 | slim | arm64 |
|---|---|---|---|---|
| `ghec` | `GHEC_ACTIVE` | `ubuntu-24.04` | `ubuntu-slim` | `ubuntu-24.04-arm` |
| `ubicloud` | `UBICLOUD_ACTIVE` | `ubicloud-standard-2` | `ubicloud-standard-2` | `ubicloud-standard-2-arm` |

The `ovh` row was removed from the execution policy on 2026-10-30 (see the
2026-10-30 update at the end of this section); its 2026-10-26 form is
preserved verbatim in git history and in the dated bullets below.

- The router schema validates `mode`/`state` consistency and the label pin by
  lookup into this table (`$p[.mode]`) instead of per-provider literal rows —
  adding a provider is a table edit, not a schema fork.
- `fallback_provider` is an absent-allowed optional field (v2-style): as of
  2026-10-30 the only valid value is `ubicloud` (the default when the field
  is absent or empty). `ovh` was removed from the execution policy on
  2026-10-30 and — like any other non-table key, including `ghec` — now fails
  schema validation via the unchanged `$p[.fallback_provider]` lookup
  (→ null) → fail-closed. This is an explicit schema rejection: no quiet
  substitution, no automatic fallback to `ubicloud`. The GHEC
  0-step-block transition writes
  `mode/state/x64/slim/arm64` FROM THE TABLE for the configured fallback,
  and the UNKNOWN→ACTIVE resolution reads the same table for the map's own
  mode.
- **OVH labels [documented — control-plane registration; historical — the
  `ovh` execution-policy row was removed 2026-10-30, record preserved in git
  history]**: the OVH control
  plane JIT-registers runners with the single label **`ci-axiom-x64`** — no
  slim/arm64 label exists in that pool. The `ovh` row therefore pins
  `x64`/`slim` to `ci-axiom-x64` and KEEPS the existing
  `ubicloud-standard-2-arm` label for `arm64`: arm64 jobs continue to
  dispatch on the Ubicloud arm pool, and OVH serves as the x64/slim fallback
  pool. **[verified 2026-10-26]** live dispatch observed: three
  `axiom-operational-slice` runs on commit `fd37e9614` were scheduled onto
  OVH ephemeral runners (`ci-axiom-121451767326`, `…-121460907375`), i.e. the
  `ci-axiom-x64` label resolves to the OVH pool while `arm64` stays on
  Ubicloud (`Archright/Axiom` runner group 3, `axiom-ci`).

### Backward compatibility [derived — machine-verified]

- With the production map (mode=ubicloud, no `fallback_provider`), every
  derived value is identical to the previous literals: the schema accepts
  exactly the old value set (superset only by `ovh` rows and
  `fallback_provider`), the block transition write produces the same bytes,
  UNKNOWN resolution yields the same state, and the step-summary
  `mode`/`action`/`reason` strings are unchanged (`ubicloud_active`,
  `transition_ubicloud`, `ubicloud_jobs_rerun_non_success`).
- The tightening is one-directional and additive: maps carrying
  `fallback_provider` values other than `ubicloud`/`ovh` were previously
  accepted (field unconstrained) and are now rejected — such a value never
  existed in production.

### 2026-10-30 update — OVH removed from the execution policy [2026-10-30]

The `ovh` row was removed from `PROVIDER_POLICY` in `ci-provider-router.yml`
on 2026-10-30, following the completed CI execution-plane cutover
OVH/GARM → Ubicloud (2026-10-30T07:46:09Z; org variable `CI_RUNNER_MAP`:
`mode=ubicloud, generation=12, fallback_provider=ubicloud`) and the full
teardown of the OVH/GARM infrastructure.

- **ovh inputs are now explicit schema rejections (fail-closed)**: with the
  row gone, the unchanged `$p[.mode]` and `$p[.fallback_provider]` lookups
  return null for `ovh`, so a map carrying `mode=ovh` or
  `fallback_provider=ovh` fails the router schema (job result UNKNOWN,
  variable write FORBIDDEN, existing routing kept). There is no quiet
  substitution and no automatic fallback to `ubicloud`.
- **No effect on the production map (machine-verified)**: with
  `mode=ubicloud, fallback_provider=ubicloud`, every derived value — schema
  acceptance, the GHEC-block transition write bytes, UNKNOWN resolution, and
  the step-summary `mode`/`action`/`reason` strings — is unchanged by the
  removal; the 2026-10-26 equivalence verification above remains valid for
  the remaining table entries.
- **History preservation**: the OVH policy row, the OVH label registration
  notes, and the 2026-10-26 live-dispatch verification above are preserved
  verbatim as dated historical records; the authoritative history of the
  removed rows and of past OVH operations is the git history of this file
  and of `ci-provider-router.yml`. Q15's OVH compute-class measurements
  remain valid as historical measurements of the retired pool.

---

## Q15 — OVH compute class decides the kernel re-execution outcome: `d2` exhausts the fixed 120 s budget, `c3-4` completes in ~49 s [2026-10-26]

### Context [documented + measured]

`axiom-operational-slice`'s final step replays a trusted certificate through the
kernel. The leanchecker leg is bounded by `defaultLeanReexecTimeoutMs = 120_000`
(`src/verification/kernel_reexecution.nim:49-53`), a compile-time constant with
**no env, CLI or config override** — the only runtime lever is the binary
(`AXIOM_LEANCHECKER_CMD` / `AXIOM_LEAN_CMD`), never the budget. That 120 s is
spent twice on this path (fresh `-o` compile at `:398-401`, then the `--fresh`
checker at `:478-482`), plus a 30 s `lake env` probe (`:414`); the lean and z3
legs carry their own separate 120 s each.

### Measured [same commit `fd37e9614`, certificate `e57ee939…`, binary `ce52659c…`]

| provider / flavor | vCPU / RAM | `[Depth 1/1]` → `[cert] Verify` | outcome |
|---|---|---|---|
| OVH `d2-4` | 2 / 4 GB | 123 s | `KERNEL_REEXECUTION_FAILED` |
| OVH `d2-8` | 4 / 8 GB | 123 s | `KERNEL_REEXECUTION_FAILED` |
| Ubicloud `standard-2` | — | 65 s | PASS |
| **OVH `c3-4`** | **2 / 4 GB** | **48.60 / 48.98 / 48.86 s** | **PASS** |

Runs `40286643639`, `40287990788`, `40289482905`. Each ended with
`leanchecker=passed`, `certVerifyKernelExit=0`, `timeoutCount=0`, and the OVH
pool back at 0 instances.

### Why the class, not the core count

`d2-8` doubling `d2-4`'s vCPU budget while landing on the same 123 s isolates
per-core throughput. OVH documents `d2` as the shared-resource class ("shared
resources, delivering stable performance at a very affordable price … perfect
for test, development and sandbox environments") and `c3` as "Compute
Optimised", whose "vCores are clocked at 2.3 GHz and higher". The conclusion is
therefore a **flavor-class** property, not a sizing bug:

- `d2` is **not admissible** for `axiom-operational-slice` (required check).
- `c3-4` is admissible with ~2.5× headroom.
- Cost moves the *wrong* way: `c3-4` is S$0.0686/h against `d2-8`'s S$0.0558/h
  in SGP1 (+23% for half the vCPU). Its compensating property is structural:
  `c3` carries **no monthly commitment plan** (`planCodes.monthly = null`,
  hourly `c3-4.consumption` only), so a deletion that slips past a month
  boundary cannot escalate to a full-month charge — the failure mode `d2`'s
  `d2-8.monthly.postpaid` plan still admits.

### The observability gap — a failure here is not self-describing

- A timeout (`execCmdWithTimeout` → exit `-1`) and a genuine mismatch collapse
  into the **same** verdict: `lcMismatch` →
  `[cert] Verify: KERNEL_REEXECUTION_FAILED — leanchecker re-validation
  MISMATCH`. The "timed out" wording exists only on the `reexecuteLean`/z3 path.
- Duration, exit code and process output are discarded (`let (_, code)` at
  `:398` and `:478`; the temp output file is deleted in `finally`).
- Consequence: `123 s` proves only that *one* leg consumed its budget. Which
  leg, and whether it needed 121 s or 400 s, is unobservable from the log —
  only step timestamps remain.

### Fail-open trap — never "fix" this check with a missing wrapper

`AXIOM_LEANCHECKER_CMD` naming a non-existent path yields `lcSkipped`, and the
overall verify still **PASSES** with `leanchecker=SKIPPED (additive deep
check)`. Any diagnostic wrapper installed through that variable MUST first
assert the wrapper exists; otherwise the required check silently loses its deep
check while reporting green. The skip is logged, which is what keeps this a
documented fail-open rather than an unannounced one.

---

## Q16 — jobs-API `labels`는 문자열 배열이다: `.name` 인덱싱은 jq exit 5로 판정 전에 사망한다 (canary M6 labels 게이트 결함)

### Documented basis

- **[documented]** List jobs for a workflow run
  (https://docs.github.com/en/rest/actions/workflow-jobs, fetched 2026-11-01):
  response schema — `labels: array of string`, `runner_id: integer or null`,
  `runner_name`/`runner_group_name: string or null`, `steps: array of
  {name,status,conclusion,…}`. 이 엔드포인트의 라벨 원소에 `{name}` 객체 형태는
  존재하지 않는다(객체형은 runner 등록 API의 별개 표현).
- **[measured 2026-11-01]** canary run 41261811139 / job 124716440849:
  `labels=["ubuntu-24.04"]`(문자열), `runner_group_id=0`,
  `runner_name="GitHub Actions 1000035432"`. identity 스텝 로그:
  `jq: error (at <stdin>:1): Cannot index string with string "name"` →
  `Process completed with exit code 5` — 스크립트의 어떤 명시적 `exit 1`
  경로도 아닌, jq 런타임 에러 종료코드가 `set -e`로 전파된 것이다.
- **[measured 2026-11-01]** 로컬 재현: `gh api …/actions/jobs/124716440849 |
  jq -c '[.labels[]?.name]'` → 동일 error/exit 5. 수정식
  `[.labels[]? | (.name? // .)]` → `["ubuntu-24.04"]`.
- **[measured 2026-11-01]** canary 9회 전체 이력: 41261811139만 identity
  스텝에 도달했다(스크립트 본문의 첫 실제 실행 — 10/23~10/26의 8건은 전부
  0-step 예산 차단, Q1/Q11). 결함은 첫 실행에 발화했으며 이전에는 관측될 수
  없었다.

### 의미론 — 실패는 판정 이전에 사망한다

- `[.labels[]?.name]`에서 `?`는 `.labels[]` 반복에만 결합한다 — 문자열 원소에
  대한 `.name` 인덱싱은 보호되지 않는다. 사망 시점이 M9/M6 판정과
  `runner_group_id=` echo **이전**이므로, 이 결함은 WRONG_PROVIDER·쿼터 실패와
  conclusion이 동일한(failure) 진단 불가 실패를 만든다(라우터 결과
  GHEC_TRIAL_FAILED는 동일 — 하락하는 것은 진단 등급뿐).
- 라우터는 이미 양형을 정규화한다: `map(.name? // .)`
  (ci-provider-router.yml :368/:402/:519/:733/:949). canary :94는 동일 원소
  매핑을 **평탄 배열**로 소비해야 한다 — :111의 `index("ubuntu-24.04")`
  검사가 평탄 문자열 배열을 기대하므로, 중첩 배열(`[[…]]`)을 내는 "수정"은
  이번엔 그 검사를 깨뜨린다(라우터 :949의 기록용 값은 중첩이어도 무해하다 —
  판정은 라벨을 소비하지 않는다).

---

## Q17 — jq 객체 축약 `{name,…}`을 배열 입력에 스트림 없이 적용하면 exit 5로 전이 write 직전에 사망한다 (라우터 return-acceptance 기록 결함)

### Documented basis

- **[documented]** jq Manual — Object construction의 축약 필드
  (`{user, project}` = `{user: .user, project: .project}`)는 입력이 **단일
  객체**일 때만 전개된다. 배열 입력에는 `.[]` 분배가 선행되어야 하며, 분배
  없이 축약을 적용하면 입력 배열 자체에 대해 키 색인을 시도해
  `Cannot index array with string "name"` 런타임 에러가 된다.
- **[measured 2026-11-01]** 라우터 run 41296106985(10:08:20Z 로그):
  `[acceptance] … executed=1 blocked=0 all_ghec=true` 판정 출력 **직후**
  `jq: error (at <stdin>:0): Cannot index array with string "name"` →
  exit 5 → `shell: /usr/bin/bash -e`가 잡을 죽인다. 동일 결함으로
  41295714292(10:02:50Z)·41295753737(10:03:21Z)까지 3회 연속 failure —
  판정 조건 충족 관측 이후 `return_acceptance=confirmed` write(:476-478)
  도달 불가, CI_RUNNER_MAP은 `pending`으로 정체.
- **[measured 2026-11-01]** 로컬 재현: 배열 JSON에 `jq -c '{name,…}'` →
  동일 error/exit 5. 수정식 `jq -c '.[] | {name,…}'` → 정상 출력 exit 0.

### 의미론 — 관측 로그 라인이 판정 경로를 차단한다

- 결함 라인(ci-provider-router.yml :464)은 `[acceptance-job]` **관측 로그
  출력용**일 뿐 판정값에 기여하지 않는다 — 그러나 `set -e` 하에서 jq
  exit 5는 곧 잡 실패이므로, 판정(:474 조건)과 write(:475-478)을 포함한
  **이후 전체 경로가 로그 라인 하나에 지배**된다. "로그는 무해하다"는
  가정이 비용 0이 아니다.
- 발화 시퀀스(:440-495): applicable 판정(created_at > last_transition_at,
  :449) → ACC_* 계산(:459-462) → 관측 echo(:463) → **결함 라인(:464)** →
  성공 분기(:468-495). Q16(canary :94, labels `.name` 인덱싱)과 동일
  계열의 "판정 전 jq 사망"이지만 결함 원인(배열 축약 vs labels 인덱싱)이
  다른 별개 인스턴스다.
- 치료: `.[] |` 스트림 분배 1줄 — 판정·의미론 불변, 출력만 잡(row별
  `[acceptance-job]` 라인이 의도한 형태로 복원된다).

---

## Q18 — `gh api`의 HTTP 에러 본문은 `--jq` 결과 스트림에도 출력된다: `>file` 리다이렉트는 에러 JSON을 관측 파일로 오염시킨다

### Documented basis

- **[documented]** gh CLI — `gh api`는 4xx/5xx 응답 본문을 stdout에 출력하고
  nonzero로 종료한다. `2>/dev/null`은 stderr 요약만 숨길 뿐 본문 출력을
  막지 않는다.
- **[measured 2026-11-01]** 전수조사(48h lookback, 3,090 run): rate limit
  403 시점에 처리된 250개 run의 `jobs` 응답을 `--jq '{…}' >"$part"`로
  기록한 결과, part 파일에 **에러 JSON**(`{"message":"API rate limit
  exceeded…","status":"403"}`)이 truncate-write로 잔류했다 — jq 파이프가
  실패해도 리다이렉션이 파일을 생성한다. exit code 재시도 루프는 재시도
  성공 시 파일을 다시 쓰지만 최종 실패 part가 그대로 남았고, 집계 jq에서
  `.m == null` 250행으로 검출되었다(rid 키 부재로 식별).
- **[measured 2026-11-01]** 치료 계약: 관측 파일 수용은 exit code 성공
  **후**에만(임시파일 + 검증 후 이동, 또는 결과 스키마 검증 —
  `has("message")` 탐지). 오염 탐지는 집계 단계 키 존재 검사로 이중화했다.

### 의미론 — 관측 파일의 "존재"는 신뢰성이 아니다

- `[ -s "$file" ]` 존재 검사는 에러 JSON을 통과시킨다 — 관측 계약
  (fail-closed)은 파일 **내용 스키마**까지 검증해야 한다.
- 이 결함은 250 run의 잡을 일시적으로 미판정 상태로 만들었다 — 재조회
  (exit code 판별 worker)로 전수 계약을 복원했고, K=0 판정은 오염
  분리·재조회 **이후**에만 유효하다.

---

## Q19 — `gh api --paginate` 페이지 결합 형태는 endpoint 유형에 따라 다르다: 최상위 배열 endpoint는 단일 배열로 병합(공식 매뉴얼 서술과 불일치), 봉투 객체 endpoint는 별개 JSON 객체 연결 — 판정 입력 fetch는 exit-code 게이트 + 수용 전 스키마 검증 없이는 무보호다

### Symptom — [documented↔measured mismatch] [measured 2026-11-02]

`gh api --paginate`의 페이지 결합 동작은 공식 매뉴얼 서술과 실측이 다르고,
endpoint 응답 유형에 따라 실측도 둘로 갈린다 (gh 2.102.0 실측):

- **최상위 배열 endpoint**(`GET /repos/{owner}/{repo}/releases`, `/tags` 등):
  실측상 **모든 페이지가 하나의 JSON 배열로 병합**된다.
  `repos/cli/cli/tags?per_page=100`(210 tags → 3 페이지) 실측 — jq가 본
  문서는 **정확히 1개**(총합 210 1줄 출력, 페이지당 1줄 아님).
  `release-ship.yml` freeze 단계의
  `gh api --paginate "repos/$GITHUB_REPOSITORY/releases" | jq '[.[] | …]'`
  는 이 **병합 동작에 의존**한다 — 별개 JSON이면 jq가 첫 문서만 보거나
  파싱에 실패한다.
- **봉투 객체 endpoint**(`GET /repos/…/actions/runs/{id}/jobs`,
  `/actions/artifacts` — `{total_count, jobs[]|artifacts[]}`):
  실측상 **각 페이지가 별개 JSON 객체로 stdout에 연결**된다.
  run 41298669695 `jobs?per_page=20`(22 jobs → 2 페이지) 실측 — `jq -s`가
  slurp한 봉투 문서 = 2개(`[2, [true, true]]`).
  `ci-provider-router.yml` jobs fetch의 `jq -sc '[.[].jobs[]]'`는 이
  **연결 동작에 의존**한다(단일 배열이면 `.jobs` 인덱싱이 실패).

공식 매뉴얼(cli.github.com/manual/gh_api, 2026-11-02 인용): "In `--paginate`
mode, all pages of results will sequentially be requested… **Each page is a
separate JSON array or object.** Pass `--slurp` to wrap all pages of JSON
arrays or objects into an outer JSON array." — "separate JSON array" 서술은
최상위 배열 endpoint의 실측 병합 동작과 **불일치**한다(배열 병합은 gh 내부에서
수행되며 매뉴얼 문구는 구버전 동작을 서술하는 것으로 보인다).

### 치료 계약 — 무보호 판정 입력 fetch의 실패 의미 분리 (2026-11-02 수리)

수리 전 `ci-provider-router.yml:357`은
`JOBS_ALL="$(gh api --paginate … | jq -sc '[.[].jobs[]]')"` 무보호
파이프라인이었다: HTTP 404(존재하지 않는 run)·403 rate-limit(Q18: 에러 본문이
stdout에 출력됨)·빈 stdout 전송 실패 전부가 jq exit 5 또는 pipefail로 step을
**조용히** 죽였고, (2-a) UNKNOWN 해소, return-acceptance 판정·confirmed/
inconclusive write, 0-step 차단 전환, rerun 전부 불도달 —
`return_acceptance=pending` 침묵 정체(Q17과 동일 계열)를 **판정 이전**에
재현했다. `probe-merge-queue.yml`의 :220(목록 파이프라인 — 에러 본문이
`.artifacts`=null로 **rc 0으로 통과**한 뒤 하류 `.[]`에서 exit 5)·:238
(리다이렉트가 에러 JSON을 .zip에 착지)도 동일 클래스다. 수리 계약:

1. fetch 실패는 판정 데이터가 아닌 **별개 의미** — 어떤 전환·acceptance
   확정도 내리지 않는다(변수·`return_acceptance` 현재값 보존).
2. 귀결은 기존 UNKNOWN 기록 의미론 재사용(result=UNKNOWN + step summary +
   exit 1) — 새 상태·새 변수 필드 없음.
3. 수용은 exit-code 성공 **후** 봉투 스키마 검증으로 한정된다:
   `length > 0 and all(.[]; type == "object" and has("jobs"|"artifacts") and
   (has("message") | not))` — `has("message")` 오염 탐지(Q18 치료 계약).
   주의: `jq -s`가 만드는 **배열**에 대해 판별하므로 `type == "object"`를
   배열이 아니라 `.[0]`/`all(.[])`에 적용해야 한다.
4. 스트림 분리 — 판정값(stdout 캡처)과 gh stderr 관측 로그(파일 → 접두사
   부착 후 관측 출력)의 생명주기 분리(Q17 교훈: 로그 라인이 값 파이프라인을
   죽이지 않는다).
5. endpoint·jq 표현식·재시도 계약 불변 — happy path 결과는 byte-identical
   (`tools/ci/test_workflow_jq_contracts.sh`가 실측 fixture로 고정).

### 결정 규칙

- `--paginate`의 페이지 결합 형태는 endpoint 유형별 실측 계약이지 매뉴얼
  문구가 아니다: 최상위 배열 → 단일 배열 병합, 봉투 객체 → 별개 객체 연결.
  소비자 jq는 각 형태에 맞는 소비기(`-s` slurp + 봉투 flat, 또는 직접 배열
  순회)를 쓰고, 그 가정은 계약 테스트로 고정한다.
- 판정 입력 fetch는 무조건 `$(gh api … | jq …)`로 인라인하지 않는다 —
  exit code 관측이 가능한 형태(`VAR="$(gh api … 2>errfile)" || RC=$?`)로
  취득을 분리하고, 수용 전 스키마 검증을 통과시킨 뒤 조립한다.
- `release-ship.yml`의 배열 병합 의존은 이 quirk로 고정된 관측 계약이며,
  gh 버전이 바뀌면 최우선 재검증 대상이다(본 수리에서 파일 변경 없음).

---

## Deterministic rules

1. `workflow_run` is a valid block-detection trigger for 0-step budget-blocked
   runs; classification MUST inspect `runner_id`/`steps`/labels per job, never
   `conclusion` alone.
2. The budget hard-stop's enforcement domain is GitHub-hosted dispatch only;
   recovery routes labels via `CI_RUNNER_MAP` and never touches the budget.
   U1 (self-hosted dispatch under a tripped budget) gates the whole design.
3. Repository-variable writes go through a GitHub App token (Variables
   read/write, in-job minted, environment-scoped); `GITHUB_TOKEN` can never
   write variables.
4. Post-transition verification uses `rerun-failed-jobs` (0-step failures are
   re-run), bounded to one call per run at `run_attempt == 1`, and asserts
   routing evidence per job (`runner_id > 0`, `steps > 0`, new label present);
   unverifiable-but-written ⇒ variable `state=UNKNOWN` (mode unchanged);
   write-failed ⇒ variable untouched + job UNKNOWN + exit 1.
5. `concurrency.queue: max` is lossy at >100 pending. Reconciliation must NOT
   depend on `schedule` alone: five consecutive 30-minute slots produced zero
   runs (Q10). Activity events (`push` on `main`) carry the reconciliation
   path; `schedule` is best-effort backup — never widen triggers to compensate.
6. `workflow_run.path` is normalized (strip `@ref`) before comparison against
   the known required-workflow path set; the trigger name filter is not an
   identity authority.
7. Provider identity is assignment metadata (`runner_group_id`, verified
   together with `runner_group_name`), never a label: GHEC ⇔ group id 0, 
   every fallback provider (Ubicloud — Default group id 1; OVH — same
   self-hosted class) ⇔ non-zero group id; a succeeded canary on group id
   ≠ 0 is WRONG_PROVIDER and forbids return, regardless of which fallback
   is active.
8. No hard spending cap exists for Ubicloud (`UsageAlert` email-only) — record
   `COST_CAP_UNVERIFIED`; per-job ceil billing means every control-plane run
   costs ≥ 1 minute (trigger economy: early-exit guards, single concurrency).
9. Self-hosted runners are untrusted execution surfaces: control workflows
   check out nothing and execute nothing but their own file; App token
   lifetime is one job.
10. App tokens are minted with NO per-issuance `permission-*` inputs
    (Q9): the action's pass-through keys do not match the installation's
    `actions_variables` key; inheritance from the least-privilege installation
    is the minimal set, verified functionally by the fail-closed variable GET.
11. `schedule` is not a clock (Q10): a 30-minute cron produced zero runs across
    five consecutive slots while other workflows' schedules fired in the same
    window. Any time-based transition must also be reachable from an activity
    event; a return path that only cron can trigger is a dead path.
12. The mode→state/label provider policy table (Q14) is the single authority
    for schema pinning, UNKNOWN resolution, and the GHEC-block fallback
    transition; the fallback provider itself is the `fallback_provider` map
    field (absent ⇒ `ubicloud`; `ovh` remains valid — the router reads the
    absent/empty field as `ubicloud`, `ci-provider-router.yml`, 23d7b2998).
    Consumers never see a provider name hardcoded at a write site — a new
    fallback provider is a table row, and the value flip is a human-approved
    variable edit, never a workflow edit.
13. The kernel re-execution budget (Q15) is a fixed compile-time constant with
    no runtime override, so provider admission is a **measurement** question,
    never a configuration one: a flavor may serve `axiom-operational-slice` only
    if its measured `[Depth 1/1]`→`[cert] Verify` interval stays well under the
    budget. OVH `d2` is inadmissible (123 s, both sizes); `c3-4` is admissible
    (48.6/49.0/48.9 s over three runs). A timeout is indistinguishable from a
    mismatch in this path, so the budget must never be the only evidence that a
    run "completed".
14. `AXIOM_LEANCHECKER_CMD` is a fail-open switch (Q15): a path that does not
    exist turns the deep check into `leanchecker=SKIPPED` while the required
    check still reports PASS. Any wrapper installed through it must prove its own
    existence first, and any green run whose log carries `SKIPPED` is not
    evidence that the kernel was re-executed.
15. jobs-API `job.labels`는 문자열 배열이다(Q16): 라벨을 소비하는 판정식은
    `.name` 인덱싱이 아니라 문자열 정규화(`[.labels[]? | (.name? // .)]` 또는
    `map(.name? // .)`)로만 접근하고, 라벨 검사는 평탄 배열에 대해 수행한다 —
    객체 가정은 jq exit 5로 판정 전에 사망하고, 중첩 배열 출력은 index 검사를
    깨뜨린다. 라벨은 어디까지나 부가 증거이며 provider identity의 권위는
    `runner_group_id`/`runner_group_name`(rule 7)에 있다.
16. jq 객체 축약 `{k,…}`을 배열 입력에 적용할 때는 반드시 `.[] |` 분배가
    선행된다(Q17): 분배 누락은 `Cannot index array` exit 5로 사망하고,
    `set -e` 잡에서는 관측 로그 라인 하나가 이후 전체 판정·write 경로를
    차단한다.
17. `gh api` 에러 본문이 `--jq >file` 리다이렉트에 잔류하는 오염(Q18)에
    대비해 관측 파일 수용은 exit code 성공 후에만 하고, 집계 단계에서 응답
    스키마 키 존재(`has("message")` 등)로 이중 검증한다 — 파일 존재·크기는
    신뢰 근거가 아니다.
18. 판정 입력 fetch(`$(gh api … | jq …)` 인라인 파이프라인)는 전송 계층
    실패(404/403/네트워크/빈 stdout)에서 조용히 사망하므로 금지된다(Q19):
    취득은 exit code 관측형(`VAR="$(gh api … 2>errfile)" || RC=$?`)으로
    분리하고, 수용 전 봉투 스키마 검증(`has("jobs"|"artifacts")` +
    `has("message")` 오염 탐지, jq -s 배열에 대해 판별)을 통과시킨 뒤
    조립한다. 취득 실패의 귀결은 기존 UNKNOWN 기록 의미론
    (result=UNKNOWN + step summary + exit 1, 변수·`return_acceptance`
    현재값 보존, 새 상태·새 필드 없음)으로만 처리하고, `--paginate` 페이지
    결합 형태(Q19 실측: 최상위 배열=단일 배열 병합, 봉투 객체=별개 연결)는
    endpoint별 실측 계약으로 취급한다.

교차 참조 (2026-11-02, Q-P1 종결): 위 "endpoint별 실측 계약"은 fetch 게이트
(본 섹션 — exit code + 봉투 스키마)와 소비자 형태 무관 정규화(release-ship ⑥,
PR #1184 — `jq -s` slurp + 전 문서 배열 검증 + flatten)의 조합으로 닫혔다.
소비자는 병합 단일 배열(관측)·별개 문서 연결(공식 문서 — Context7 `/cli/cli`
api.go 인용) 양 형태를 수용하고 그 외 형태는 fail-closed한다. 버전 pin 기각
판정 + 워크플로 paginate 사용처 전수 감사 분류표 + 하니스 Q-P1 group
(section 8 — 교차 형태 byte-identical 골든 + 음성 통제):
`docs/spec/gh_api_paginate_output_quirks.md` Q-P1 판정 종결 참조.

## 2026-11-09 — 폴백 전이 로직 복원 (소유자 지시: 운영 연속성 트랙)

- **지시(소유자, 2026-11-09)**: 비공개 운영 창에서 GHEC 월 포함량 소진에
  대비해 GHEC→ubicloud 폴백 라우팅 로직을 보존한다. 이 트랙은 공개 무결성
  임계 경로와 독립이다(운영 연속성).
- **복원 범위**: PR #19(2026-11-08)이 `.github/workflows/ci-provider-router.yml`에
  시행한 폴백 봉인 중 2개 hunk(파일 헤더 주석의 봉인 선언 영역, 차단 확정
  경로의 fail-closed 교체 블록 — hunk `@@ -656,139 +656,13 @@`)만 원본
  텍스트로 역적용한다. 복원되는 전이 계약: 0-step 러너-게이트 차단 확정
  (N_BLOCKED>0) → PROVIDER_POLICY 폴백 state/라벨(FB_STATE/FB_X64/FB_SLIM/
  FB_ARM64) 추출 → CI_RUNNER_MAP PATCH(mode·state·generation+1·
  last_transition_reason="GHEC_RUNNER_GATE_BLOCKED"·라벨 교체, 재시도+readback
  검증) → rerun-failed-jobs(attempt==1 가드, 최대 1회) → attempt-2 라우팅
  증거 폴링(600s deadline). PR #19의 나머지 24파일 스크럽(CL·LICENSES·docs
  식별자·수치 마스킹 포함)은 유지된다.
- **재봉인 계획**: 공개 직전 최종 GHEC 통합 후 폴백을 재봉인한다(Publication
  Integrity 계획 Slice 4). 이 항목 추가 외 기존 엔트리는 수정·삭제하지
  않는다(역사 보존).
