# Trust Surface Dual-Authority Quirks (App manifest vs repository_surface.json)

> AGENTS.md section 0.5 Quirk Mandate record -- discovered 2026-11-25 while
> investigating the PR #476 deadlock.
> Measured at `origin/main` `57f2067b58560d39236ce34f1e14f45d662652f0`,
> PR #476 head `46b3f99f6f5ceace8d9191dd1981ec1c2c32e3f5`.
>
> This document records a platform/architecture quirk: Axiom defines its
> "trust surface" **twice**, in two files, with two different comparison
> semantics and two different enforcement points, and the two definitions
> disagree on **8 of 18 paths**. The verdict-layer contract itself belongs to
> [repository_surface_contract.md](repository_surface_contract.md) and
> [merge_authority_integrity.md](merge_authority_integrity.md); this document
> does not redefine that contract. It records only **which side is
> authoritative when the two definitions give different answers.**
>
> Tagging: **[measured]** = re-verified directly for this document.
> **[documented]** = checked against official documentation. **[inferred]** =
> judged from the cited measurements and documents.

---

## Q1 -- "Trust surface" has two definitions: blob equality (App) vs class classification (guard)

### Symptom [measured]

The same protected set is declared in two files, in two forms, with
fundamentally different comparison semantics.

**Definition A -- `config/policy/trust_surface_manifest.json`** (18 paths)

```
"comparison": "blob-based: every path's Git blob SHA at G must equal its blob SHA at B_mg"
"readFrom": "B_mg (merge_group.base_sha), never from G"
```

- `purpose` states that a change requires "the audited break-glass lane and an
  explicit epoch rotation".
- It is a pure blob equality test: no allow-list, no field awareness, no version
  monotonicity, and **no notion of a legitimate self-amendment**.
- Enforcement is **out of repo**: GitHub App `axiom-admission-verifier`
  (id `5795152`), a preflight that publishes the required check
  `admission-check`.

**Definition B -- `config/repository_surface.json`** (`policyVersion` 108)

- 3 classes, `resolutionOrder: ["PRODUCT","CONTROLLED","FROZEN"]`,
  `defaultClass: "PRODUCT"`.
- `classes`: PRODUCT 30 / CONTROLLED 264 / FROZEN 12 patterns;
  `frozenExceptions` 116 paths across 8 groups.
- Enforcement is **in repo** by `tools/surface_guard.nim`:
  `resolveClass()` (`tools/surface_guard.nim:245`) does a first match over
  PRODUCT then CONTROLLED then FROZEN, falling back to `defaultClass`; glob
  semantics are `globMatch()` (`tools/surface_guard.nim:186`), where `**`
  swallows zero or more whole segments.
- It **does** have a legal self-evolution mechanism:
  `selfAmendment.allowedPaths` is exactly 4 paths
  (`config/repository_surface.json`, `tools/surface_guard.nim`,
  `tests/unit/test_surface_guard.nim`, `docs/spec/repository_surface_contract.md`).
  For a MODIFY of an allowed path with a strictly newer head `policyVersion`,
  `classify()` returns `verdict=PASS, reasonCode=AMENDED`; otherwise
  `FAIL/SURFACE_FORBIDDEN` (`tools/surface_guard.nim:104-118`; unit tests in
  `tests/unit/test_surface_guard.nim:592`,
  `suite "selfAmendment exception (v2)"`).
- Wiring: the `[SL-20]` step in `.github/workflows/admission-check.yml`
  (`:1018`, `:1036`) runs a guard **compiled from the B tree** against the
  **base policy at B** crossed with the changed paths, and accepts an optional
  `--head-policy` (`:1120-1128`).

### Consequence [measured]

Neither definition reads the other. The App never reads
`repository_surface.json`, and the guard never reads the manifest -- the
manifest has no `frozenExceptions` key (its only top-level keys are `schema`,
`purpose`, `comparison`, `readFrom`, `paths`), and the guard references no
manifest path. Agreement between the two is therefore **accidental only**.

### Boundary

The split of responsibility is itself defensible: the App guards one invariant
("blob identity against B_mg"), and the guard decides per-class op rules plus
lawful self-amendment. The defect is the **divergent outcome**, not the
existence of two layers.

---

## Q2 -- 8 of 18 paths diverge: `.github/**` being FROZEN does not make those 7 FROZEN

### Symptom [measured]

Resolving the 18 manifest paths with Definition B's real `resolveClass`:

| Resolved class | Count |
|---|---|
| FROZEN | **10** |
| CONTROLLED | **7** |
| `defaultClass` PRODUCT | **1** |

**CONTROLLED (7):**

- `.github/actions/setup-axiom-toolchain/action.yml`
- `.github/workflows/admission-check.yml`
- `.github/workflows/admission-gate-v2.yml`
- `.github/workflows/certificate-mint.yml`
- `.github/workflows/publication-integrity.yml`
- `config/policy/epoch_manifest.json`
- `config/trusted_writer_set.json`

**PRODUCT via `defaultClass` (1):**
`tests/ci/test_vs0_admission_aggregate_fail_closed.nim`

**FROZEN (10):**
`.github/workflows/axiom-operational-slice.yml`,
`.github/workflows/bsec-integrity.yml`,
`.github/workflows/debt-registry-gate.yml`,
`.github/workflows/generation-acceptance.yml`,
`.github/workflows/runner-pool-acceptance.yml`,
`config/app_landing_binding.json`,
`config/policy/merge_admission.json`,
`config/policy/trust_surface_manifest.json`,
`config/repository_surface.json`,
`tools/surface_guard.nim`

### Cause -- why the resolution order defeats `.github/**` [measured]

FROZEN contains `.github/**`, so reading "`.github/**` is FROZEN" is not wrong,
but it is **insufficient**. `resolveClass` is first-match:

- 10 of the 18 manifest paths live under `.github/`, and **5 of those are
  registered as exact paths in `classes.CONTROLLED`**
  (`setup-axiom-toolchain/action.yml`, `admission-check.yml`,
  `admission-gate-v2.yml`, `certificate-mint.yml`,
  `publication-integrity.yml`).
- CONTROLLED sits after PRODUCT and **before** FROZEN. The exact registration
  matches before the `.github/**` glob, so **the more specific registration
  wins and the class is CONTROLLED**.
- The other 5 have no exact registration, fall through to `.github/**`, and
  become FROZEN.

`config/policy/epoch_manifest.json` is the same shape: `config/policy/**` is
FROZEN, but the exact CONTROLLED registration matches first.
`config/trusted_writer_set.json` has no FROZEN match at all -- only an exact
CONTROLLED registration.

This is exactly why the divergence is **invisible without applying the
resolution order**. Directory-level inspection shows all 7 as FROZEN, and
reading only the glob pattern list produces the same misreading.

The contract document states this ordering rule explicitly
(`docs/spec/repository_surface_contract.md`): the resolution order is PRODUCT
then CONTROLLED then FROZEN with first match winning, and a CONTROLLED entry
that overlaps a FROZEN glob makes the FROZEN rule inert.

### Consequence [measured]

For those 8 paths, **every in-repo gate says the change is allowed while the
App refuses and demands break-glass**: rewriting the `admission-check.yml`
generation, rotating `epoch_manifest.json`, or re-anchoring
`trusted_writer_set.json` are all PASS under the guard and FAIL under the App.

### Boundary

The `frozenExceptions` block makes this state **intentional** (see Q5), so it
cannot be called a plain bug -- Q5's two readings must be evaluated together.

---

## Q3 -- The self-amendment contract is unreachable: guard AMENDED vs App FAIL on PR #476

### Symptom [measured]

`config/repository_surface.json` and `tools/surface_guard.nim` are
**simultaneously**

1. members of `selfAmendment.allowedPaths`, and
2. members of the App manifest.

The repo therefore declares that a version bump is a lawful way to amend its own
policy, the guard implements and unit-tests exactly that, and the App's blob
comparison overrides it unconditionally.

### Measurement -- PR #476 [measured]

| Item | Value |
|---|---|
| PR | #476 (`ci/vs1-frozen-overlay-alignment`), state `OPEN`, `mergeStateStatus` `BLOCKED` |
| head | `46b3f99f6f5ceace8d9191dd1981ec1c2c32e3f5` |
| base | `de570c771554fcda57cea44f7a9c293b5f3753f6` |
| merge-base (= App `diff_base`) | `551e42ae2bf2c87830350c2bcd06a58a61c8df23` |
| changed files | 4 (`changed_files: 4`, total +615/-12) |
| `config/repository_surface.json` | `+2/-12` (`policyVersion` 108 to 109) |

Content: removal of 5 FROZEN-exception entries whose target files are all
**absent from main** (`contents?ref=main` returns HTTP 404 for
`.github/workflows/h4-routing-measure.yml`,
`.github/workflows/trust-surface-pin-notice.yml`,
`.github/workflows/gateway-jobs-measure.yml`,
`.github/workflows/hardware-falsification-smoke.yml`, and
`src/gate/orchestrator` + `.nim`). A dead exception is `POLICY_INVALID`
(DEBT#545), so this PR is a **required** repair under the guard.
(The last path is written with its extension split: the prose pattern in
`tools/ci/doc_path_validator.nim` extracts `src/**.nim` shapes as references,
and here absence is the fact being stated, so "a reference that must resolve"
and "a citation of absence" are kept distinct.)

**App check-run** (id `138595004925`, `axiom-admission-verifier` / app id
`5795152`, conclusion `failure`), verbatim:

```
trust_surface=FAIL -- venue=pull_request manifest_ref=deb44e5 touched=4 manifest_touched=1 diff_base=551e42a reasons=mismatch:config/repository_surface.json
output_title: Preflight verification rejected
```

`touched=4` and `manifest_touched=1` match the PR's 4 files, of which only 1 is
in the manifest.

**The guard's verdict on the same change** -- base policy at `de570c77` crossed
with head policy at `46b3f99f`, diff `M config/repository_surface.json`, run by
compiling `tools/surface_guard.nim` from `origin/main`:

```json
{"verdict":"PASS","reasonCode":"AMENDED","policyVersion":108,"binding":"base",
 "changeCount":1,"violations":[],
 "amendments":[{"path":"config/repository_surface.json","status":"M",
                "changeClass":"FROZEN","op":"MODIFY","reasonCode":"SURFACE_FORBIDDEN"}]}
```

exit 0. **Same change, same generation: the guard says AMENDED, the App says
mismatch.**

**Control** -- dropping `--head-policy` makes the guard return
`FAIL/SURFACE_FORBIDDEN` with exit 1. AMENDED therefore appears only when
`--head-policy` and a monotonic `policyVersion` bump both hold, and that
condition is precisely what the App does not recognise.

### Cause [inferred]

The App's judging function is the single predicate `blob(G) == blob(B_mg)`, and
its input file has no `selfAmendment` key. The App source lives outside the
repository (`~/.config/axiom-verifier-app/worker/src/index.js`, not a git
repository -- `docs/evidence/vs_authority_separation_phase0_delta_2026-11-18.md`
section 8), so "the App **ignores** selfAmendment" is an **inference**, not a
code reading. What is measured is that the judging input is the manifest alone
and that the manifest has no such key.

### Consequence

Every PR that lawfully amends `config/repository_surface.json` -- removing dead
exceptions, moving classes, adding patterns -- **cannot land without
break-glass**. Even with a green guard, the required check `admission-check` is
red, so the merge queue will not pass it.

---

## Q4 -- Auditability limit: the org-scope ruleset *history* endpoint needs `Administration: write`

### Symptom [measured + documented]

The App's comparison semantics live in an out-of-repo Cloudflare Worker, so **no
PR can change them** (deploy path `npx wrangler@latest deploy`; `wrangler.toml`
name `axiom-admission-verifier`; see
`docs/evidence/vs_authority_separation_phase0_delta_2026-11-18.md:261`). To
audit, via ruleset *history*, the basis on which that App became required:

- **[documented]** `GET /repos/{owner}/{repo}/rulesets/{ruleset_id}/history` and
  `GET /orgs/{org}/rulesets/{ruleset_id}/history` require
  `"Administration" repository/organization permissions (write)`
  (<https://docs.github.com/en/rest/repos/rules>,
  <https://docs.github.com/en/rest/orgs/rules>; REST schema
  `progAccess.permissions`, checked 2026-11-25).
- **[documented]** The `permissions:` key of `GITHUB_TOKEN` accepts no
  `administration` scope at all -- the documented set is `actions`,
  `artifact-metadata`, `attestations`, `checks`, `code-quality`, `contents`,
  `copilot-requests`, `deployments`, `id-token`, `issues`, `discussions`,
  `packages`, `pages`, `pull-requests`, `security-events`, `statuses`,
  `vulnerability-alerts`. A job token therefore cannot call that endpoint.
  (Supporting measurement: `.github/workflows/generation-acceptance.yml:41-46`
  records that repo ruleset reads do succeed without an `administration` entry,
  while **org** ruleset and bypass-actor management needs Administration org
  write and is outside the GPA read scope.)

### Precision -- this is NOT "auditing is impossible" [measured]

The correct limit is: **the org-scope ruleset history endpoint requires
`Administration: write`, which the job token cannot hold and which a read-only
minted token does not grant.** These stronger claims do **not** hold:

- **Repo-scope ruleset reads do succeed on the plain `GITHUB_TOKEN`** --
  measured: `GET /repos/Archright/Axiom/rulesets/27097366` returns
  `{"name":"main","enforcement":"active","bypass":[]}` with
  `required_status_checks[0] = {context:"admission-check", integration_id:5795152}`
  and `bypass_actors: []`. The **required binding itself is auditable by a job
  token.**
- **`Administration: read` is reachable** -- the repository already mints it
  with `actions/create-github-app-token` and `permission-administration: read`
  (`.github/workflows/admission-ssot-drift.yml:124`; comment at `:118` says the
  rulesets API needs Administration:read). A read-only minted token path
  therefore exists.

So the limit is not "no audit path exists" but **"history (a write-scope
endpoint) is a credential class CI cannot hold, and what CI holds is
current-state read only."**

### Reconciliation with DEBT#560 [measured]

DEBT#560 in `data/debt_registry.json` records that "All 39 versions of ruleset
27097366 (main) were retrieved via rulesets/27097366/history and each version
detail was fetched individually". This does **not** contradict the present
entry: that retrieval was a manual audit performed with **operator credentials**
(Administration: write), not with a CI job token, and its output is
`docs/evidence/vs1_trust_rotation_audit_2026-11-18/README.md`. DEBT#560 itself
also records the platform audit surface limit: rule-suites returns 404,
org audit-log returns 404, org rulesets returns 403 on the free plan, so
ruleset history is the only API-visible authority. Generalised:

| Path | Credential | Holds |
|---|---|---|
| current ruleset state (repo scope) | `GITHUB_TOKEN` | **yes** (measured) |
| current ruleset state (org scope) | `GITHUB_TOKEN` | no (free plan 403 -- DEBT#560) |
| ruleset history (repo/org scope) | `Administration: write` | job token **no** / operator admin **yes** (DEBT#560 precedent) |
| App comparison semantics change | Cloudflare deploy rights | **no** via PR (out of repo) |

That is: **auditing is possible, continuous CI auditing is not** -- and that
distinction was not documented anywhere.

### Consequence

CI can verify the **current state** ("the App is required and there is no
bypass") by itself, but it cannot continuously verify "when, and by whom, that
required binding was configured". When that history is needed, it depends on a
manual audit with operator credentials (the DEBT#560 precedent), and that fact
appears nowhere -- so the next agent wrongly assumes CI auditing suffices.

---

## Q5 -- The divergence is "documented but not authoritative", not an undocumented bug

### Symptom [measured]

Two readings are **equally consistent** with the evidence. This document asserts
neither.

**Reading 1 -- the manifest is intentionally stricter, and
`repository_surface.json` has simply not been reconciled.** Evidence: 5 of the 8
`frozenExceptions` groups explicitly cite the App manifest and describe the
narrowing as intended.

- `ci-infra`: "CI infrastructure workflows that are NOT part of the App trust
  surface. New workflow files remain FROZEN ADD=FAIL; this exact registration
  records the **intentional** CONTROLLED carve-out for existing reviewed
  workflows. The nine trust-surface workflows and the setup action are FROZEN."
- `trust-supply-path`: "the App trust-surface manifest (17 paths) is the binding
  control for this file and denies admission-check to any PR that modifies it,
  so its merge still requires the MUST-T2 delegation lane. The repository-surface
  FROZEN class added a second, **redundant** lock that made that sanctioned lane
  unpushable."
- `epoch-rotation` / `admission-mint-pin-rotation` / `publication-venue-split`:
  the same statement -- the App manifest is the binding control, the
  repository-surface FROZEN class is a redundant lock, and the exact
  registration (no wildcard) narrows only that path to CONTROLLED. "The App
  trust surface, the blob-equality comparison, the required checks and merge
  authority are unchanged."

**Reading 2 -- the manifest is accidentally stricter, and the two files evolved
independently.** Evidence: the two files never reference each other (Q1), and the
`ci-infra` rationale says "The nine trust-surface workflows and the setup action
are FROZEN" while **5 of them actually resolve to CONTROLLED** (Q2). That
suggests the rationale is stale or imprecise.

Both readings are consistent with observation. Recorded as **undecidable**.

### Cause -- why the divergence stays invisible [measured]

`docs/spec/repository_surface_contract.md` defines CONTROLLED as follows:
CONTROLLED is not an enforcement boundary but an **inventory** ("this path is
registered, so it has been looked at"), and the rule itself is PASS for every
op. Its grade table confirms CONTROLLED is ADD/MODIFY/DELETE all `PASS`.

So **a path resolving to CONTROLLED does not mean the path is free -- it only
means it is registered**, and the verdict itself is always PASS unless the class
is FROZEN. A reader of `repository_surface.json` therefore concludes "these 7
paths are free", while the App blocks them. The divergence leaves **no trace in
the verdict output**, which is why it goes unnoticed.

### Consequence -- precisely what the problem is

The problem is not CI latency. It is that **the set of paths requiring
break-glass is larger than, and not derivable from, the set the repo's own
policy declares protected.** An agent that reads
`config/repository_surface.json` -- the file whose entire job is to say what is
free and what is frozen -- gets the **wrong answer for 8 paths**, and finds out
only after the App rejects the PR. This is a **truth/authority split**: the
platform (App plus manifest) is authoritative, the repo policy is advisory, and
**nothing declares that fact.**

### Boundary

This document does not rule that "the manifest is wrong" or "the guard is
wrong". Which definition prevails is a matter of contract amendment; the
observed fact is only that **two answers coexist and which one is authoritative
is nowhere declared.**

---

## What this does NOT mean

- **The App must not be removed, bypassed, or weakened.** The App is the
  **correct authority** for the B_mg blob-identity property. That property
  guarantees "a PR cannot shrink its own verification list"
  (`readFrom: B_mg, never from G`); removing it would remove the protection.
  Basis: required `admission-check` is bound to integration `5795152` with
  `bypass_actors: []` (measured 2026-11-25), and that binding must stay.
- **It does not decide which side is the "bug".** Q5's two readings are equally
  consistent with the evidence.
- **It does not propose a resolution for the Q3 deadlock.** This is a
  phenomenon record; a contract amendment is a separate decision (AGENTS.md
  section 0.12, product contract first).
- **It is not "auditing is impossible".** Repo-scope current state is auditable
  by a job token, and a minted `Administration: read` token path is already in
  use. The limits are history (write scope) and the App's semantics (out of
  repo) -- see Q4.

**The direction of any fix is stated in exactly one form**: make the in-repo
declaration **agree** with the platform -- not weaken the App. *How* to
reconcile (manifest alignment vs policy re-registration vs an explicit
declaration) is outside this document's scope.

---

## Reproduction

```bash
# Resolve the 18 paths (authority: the real resolveClass -- do not read by eye)
#   import tools/surface_guard.nim with --path:. and call resolveClass(policy, path)
#   measured: FROZEN 10 / CONTROLLED 7 / PRODUCT 1

# Guard verdict (PR #476 change)
git show <base>:config/repository_surface.json   > base.json
git show <head>:config/repository_surface.json   > head.json
printf 'M\tconfig/repository_surface.json\n'      > diff.txt
nim c -o:surface_guard tools/surface_guard.nim
surface_guard --policy base.json --head-policy head.json --diff diff.txt   # PASS/AMENDED exit 0
surface_guard --policy base.json --diff diff.txt                          # FAIL/SURFACE_FORBIDDEN exit 1

# App check-run (external authority -- observation only)
gh api "repos/Archright/Axiom/commits/<head>/check-runs?per_page=100" \
  --jq '.check_runs[] | select(.app.id==5795152) | .output.summary'

# Required-binding audit (holds with a job token)
gh api repos/Archright/Axiom/rulesets/27097366 \
  --jq '{bypass:.bypass_actors, req:[.rules[]|select(.type=="required_status_checks")|.parameters.required_status_checks[]|{context,integration_id}]}'
```

The `check-runs` listing must pass `per_page=100` -- the default 30-item
truncation is covered by Q19 of `docs/spec/gh_run_observation_quirks.md`.

---

## Related documents

- `docs/spec/repository_surface_contract.md` -- Definition B's contract (grades,
  rule table, resolution order, `selfAmendment`, `frozenExceptions` schema,
  CONTROLLED = inventory not enforcement).
- `docs/spec/merge_authority_integrity.md` -- where merge-admission authority
  lives and the invariant that the diagnostician must not modify the object it
  diagnoses (M1-M7).
- `docs/spec/gh_run_observation_quirks.md` Q19 -- the `per_page` rule for
  check-runs observation.
- `docs/agents/axiom_admission_verifier_ops.md` -- App operating contract
  (identity, judging inputs, the `readFrom` invariant, and the rule that the
  path count must not be hardcoded).
- `docs/evidence/ci_critical_path_protection_matrix_2026-11-24.md` -- an
  independent measurement of the four control devices (A = manifest 18,
  B = trustSurface 39, C = checker closure 891, D = surface classes) over 14
  files. Its verdicts for the 7 CONTROLLED paths agree with Q2 independently.
## Addendum -- v111 (2026-11-27, `app-trust-mirror`): the divergence is now the intended state

Q2's measurement above (**8 of 18 paths diverge**, manifest 18) is a snapshot of
v108. It is preserved as history, not as the current state. Current, machine-read
values: manifest **17** paths, convergent **2**, divergent **15** -- printed by
`tools/ci/trust_surface_divergence.nim` and pinned in
`tests/unit/test_trust_surface_divergence.nim` case (a).

v111 registers the seven remaining App-manifest paths that were still resolved
FROZEN as exact CONTROLLED under a new group, `app-trust-mirror`. The reasoning
is the same one v105-v108 used for six earlier paths, and that repetition is the
point: a single-path exception per lane was treating a symptom. The cause is
that `FROZEN` denies MODIFY and DELETE with no scoped escape on paths whose merge
is *already* decided by the App's blob comparison, so the only way to push such a
PR was `--no-verify`, which skips all nine pre-push gates rather than one.

The two paths that are deliberately **not** registered are the interesting ones:

- `config/repository_surface.json` and `tools/surface_guard.nim` stay FROZEN.
  FROZEN on those two is what arms the `selfAmendment` AMENDED verdict (guard v2
  conditions a-d). Carving them would not weaken merge authority -- the App still
  denies admission-check -- but it would convert an audited amendment into an
  untracked plain `PASS`, which is the §0.9 failure mode this quirk document
  exists to describe.

Divergence is therefore not a defect to drive to zero. It is the measured shape
of a policy whose binding control lives outside the repository on those paths.
The ledger (`data/ci_optimization/trust_surface_divergence/ledger.json`) still
ratchets: unregistered divergence and dead entries both fail, so a path cannot
drift out of FROZEN silently or stay registered after the App stops protecting it.
