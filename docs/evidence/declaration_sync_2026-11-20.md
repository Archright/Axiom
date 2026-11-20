# Declaration vs Implementation Sync — 2026-11-20

**Worktree**: topic worktree `vs-declaration-sync` (clone-local; path intentionally omitted)
**Branch**: `workstream/declaration-sync` (base `origin/main` `f895944`)
**Scope**: documentation only. No product code, `AGENTS.md`, or `data/debt_registry.json` was modified. Trust-surface files (`config/policy/merge_admission.json` `trustSurface`) were read only; none of the changed paths is listed there. `tools/readiness_evaluator.nim` is a trust-surface entry but was not modified — the doc was aligned to its existing signature.

---

## 1. `policy.schema.json` and other dangling schema paths

Measurement:

```
grep -rn "policy\.schema\.json" --include="*.md" --include="*.nim" --include="*.json" \
  --include="*.toml" --include="*.yml" --include="*.yaml" .
```

Observed: exactly one reference — `docs/design/phasec_identity_design.md:172`. No code, config, gate, or test references it.

Target verification:

```
ls data/readiness/*.schema.json
→ data/readiness/closure_state.schema.json

find . -path ./.git -prune -o -name "*.schema.json" -print
→ ./config/policy/contract_layer.schema.json
→ ./config/policy/policy_layer.schema.json
→ ./data/readiness/closure_state.schema.json
→ ./src/gate/gate_manifest.schema.json
```

Conclusion: `data/readiness/policy.schema.json` does **not** exist. It is not a live-file claim — the containing table is explicitly a plan for three draft-07 schemas. Two factual defects were corrected in that section:

- the parenthetical "only `config/policy/contract_layer.schema.json`, `config/policy/policy_layer.schema.json`, and `src/gate/gate_manifest.schema.json` are present" was stale (`data/readiness/closure_state.schema.json` exists today); the replacement states that none of the three planned paths exists and cites the measured `ls`;
- the policy row claimed the planned schema "mirrors `independent_policy.json` keys: `policyId`, ... `r1`/`r4`/`r5`/`r7`/`r8`, `freshness`, `tierCountsContract`, `semanticMapping`". Measured keys of `data/readiness/independent_policy.json` are `schemaVersion`, `independentPolicyId`, `ratifiedAt`, `ratifiedBeforeCollection`, `supersedes`, `productContract`, `stateSemantics`, `blockingPolicy`, `preRatifiedNotApplicable`, `invariants` (each `invariants.R*` has `name`, `criticality`, `observationKeys`). The row now names that real policy DOM and lists the measured keys; the planned path is marked "(planned; absent)".

Other schema paths: a scan of every backticked `*.schema.json` reference under `docs/` found no other path-qualified reference whose target is absent. Remaining records are the two still-planned paths (`data/readiness/evidence_manifest.schema.json`, `data/readiness/decision.schema.json`) in the same planned-schema table.

---

## 2. CLI subcommand surface

Measurement (`src/cli/cli_types.nim`, `src/cli/action_plan_cli.nim`):

```
awk '/AxSubcommandKind\* = enum/,/^ *$/' src/cli/cli_types.nim | grep -c "axSubcommand"
→ 34

awk '/func parseAxSubcommandKind/,/none\(AxSubcommandKind\)/' src/cli/action_plan_cli.nim | grep -c 'of "'
→ 34

grep -c 'name: "ax ' src/cli/action_plan_cli.nim
→ 28

awk '/CliCommandKind\* = enum/,/^ *$/' src/cli/cli_types.nim | grep -c "cliCommand"
→ 32
```

`parseAxSubcommandKind` occupies `src/cli/action_plan_cli.nim:174-245`; `AxSubcommandKind` occupies `src/cli/cli_types.nim:84-118`; `CliCommandKind` occupies `:50-82`.

Measured set (34, enum order; the parser's `of` order differs only by `debt`/`budget`): `prove`, `report`, `help`, `topology`, `scaffold`, `gate`, `lint`, `cert`, `shadow`, `config`, `version`, `io`, `dag`, `cache`, `check`, `shape`, `git`, `cst`, `scope`, `release`, `observability`, `check-spec`, `baseline`, `invariants`, `vkd`, `verify`, `status`, `debt`, `budget`, `merge`, `admission`, `landing`, `evidence`, `capability`.

Correction: `docs/design/r7_cli_outcome_contract.md` claimed **29** subcommands and listed `infra`, which has no parser case. It now lists the measured 34, removes `infra`, adds `status`, `merge`, `admission`, `landing`, `evidence`, `capability`, updates the total, the Phase 4 "remaining 31" list, and the appendix line pins.

Report-only (product code, not edited here): the `ax help` table `axCommandHelpEntries` (`src/cli/action_plan_cli.nim:21`) has 28 entries. It advertises `seed-registry`, which `parseAxSubcommandKind` does not accept, and omits seven parser-accepted commands: `admission`, `budget`, `check`, `cst`, `evidence`, `git`, `shape`. This is the same declaration-vs-implementation class as item 2 but requires a code change.

---

## 3. `evaluateReadiness` contract vs implementation

Implementation measurement:

```
grep -n "proc evaluateReadiness\*" tools/readiness_evaluator.nim
→ 857:proc evaluateReadiness*(policy: JsonNode, bundle: JsonNode): ReadinessDecision =
```

`validateEvidence` (`:234`) takes `(raw: JsonNode, ctx: EvaluationContext, policy: JsonNode = newJObject())`; `normalizeBundle` (`:304`) returns `Result[JsonNode, string]`; `loadEvidenceFiles` is `:925`. No `CanonicalBundle` type exists in the implementation.

Document before correction: `docs/spec/productization_contract.md` §5 (`:242`) and §8 (`:440`) called `evaluateReadiness(policy, bundle, context)`; §9 declared `bundle: CanonicalBundle` and a `CanonicalBundle` return for `normalizeBundle`.

Decision: `tools/readiness_evaluator.nim` is named as part of the product-contract SSOT in `AGENTS.md` §0.12 ("`docs/spec/productization_contract.md` + `config/readiness_policy.json` + `tools/readiness_evaluator.nim`"). The implementation is therefore the contract, so the doc was aligned rather than escalated as a decision:

- §5 and §8 now read `evaluateReadiness(policy, bundle)`; `context` is stated to be used only by `validateEvidence`.
- §9 now lists the measured signatures with line pins (`:925`, `:234`, `:304`, `:857`) and records that `CanonicalBundle` was a design placeholder while the implemented type is `JsonNode`.

Verification: `grep -rn "evaluateReadiness([^)]*context" docs/ tools/ tests/` → no matches.

---

## 4. DEBT#416 — VKD ground truth

Registry entry (read only): `jq '.entries[]|select(.id=="DEBT#416")' data/debt_registry.json` → `status: "open"`, `resolution: "UNRESOLVED"`; its note records the 2026-08-11 observation "UNCHANGED at 5/40 (VKD 0.1250)" and the P1.2 result `Total 35, Pass 17, Fail 2, Skip 16` with the numerator intentionally unchanged.

Current measurements:

```
jq -c '{entries:(.entries|length), certGreen:([.entries[]|select(.status=="certGreen")]|length), statuses:([.entries[].status]|unique)}' \
  src/verification/certificates/manifest.json
→ {"entries":5,"certGreen":0,"statuses":[""]}

jq -c '{vkdFixed4,verifiedFunctions,kernelTotal,kernelExemptTotal,vksTotal,metrics}' data/baseline.json
→ {"vkdFixed4":"0.0000","verifiedFunctions":0,"kernelTotal":40,"kernelExemptTotal":17,"vksTotal":23,
   "metrics":{"vkd":{"verified":0,"total":23,"ratio":0.0},
              "rawKernelCoverage":{"verified":0,"total":40,"ratio":0.0},"ogr":1.0}}

jq -c '{schema_version,kernel_total,vksTotal,exempt:(.kernel_exempt_symbols|length)}' data/verification_scope.lock
→ {"schema_version":3,"kernel_total":40,"vksTotal":23,"exempt":17}
```

Ground truth: canonical VKD = **0/23 = 0.0%** (`metrics.vkd`, `vksTotal=23`); legacy raw kernel coverage = **0/40** (`vkdFixed4="0.0000"`, `kernelTotal=40`); the tracked certificate manifest has **0 certGreen out of 5 entries** (all five statuses are the empty string).

Authority caveat: the canonical projection `getCanonicalVkdMetrics` is journal-driven (TrustCommit), not manifest-driven; the header of `src/cli/shared/proof_hydration.nim:119` states that the reference certificate store `src/verification/certificates` is not authority and is never read by it. The manifest measurement therefore establishes the ceiling in the tracked reference store (0 certGreen), not a runtime journal count; both agree with `data/baseline.json` at 0/23.

Corrections made:

- `docs/spec/verification_density.md:134` — `rawKernelCoverage` example `5/40` → measured `0/40`.
- `docs/spec/cert_lifecycle_contracts.md:91` — "`vkdFixed4` = `5/40` 유지" → measured `0/40` (`"0.0000"`) plus canonical `0/23`.

No `0/23` claim needed correction: the claims in `docs/spec/verification_density.md`, `docs/spec/productization_contract.md:290`, `docs/reports/productization_metrics_README.md`, and `docs/reports/readiness_2026-08-18.md` all match the measurement. `docs/DEBT_REGISTRY.md:205` still reproduces the registry's "5/40" text, but it is auto-generated from the read-only `data/debt_registry.json` and was not hand-edited.

---

## 5. DEBT#420 — dead links

`lychee` is not installed in this environment (`which lychee` → no output). A throwaway checker was written at `/tmp/axiom_deadlink_check.py` (sha256 `a44e66bf4d1a60cc9d32164e378800dda7792fd39d9fb6675a7c535ab91bc809`; **not committed**). It:

- walks every `docs/**/*.md` plus `README.md` and `AGENTS.md`;
- removes fenced code blocks and inline code spans;
- extracts inline `[text](target)` links and reference definitions (excluding footnote definitions);
- checks only relative targets, resolved against the containing file's directory, percent-decoded, query/anchor stripped;
- ignores `http(s)`, `mailto:`, `tel:`, `ftp:`, `data:`, `javascript:`, `file:` and site-absolute `/...` targets;
- validates `.md` fragments against GitHub heading slugs (no hyphen collapsing; explicit `id=`/`name=` anchors included).

Result on the base tree: **667 relative targets checked, 48 missing-target rows, 0 missing-anchor rows**. After the fixes below: **35 rows — 27 pseudo-links, 1 line-reference pseudo-link, 7 real missing targets**.

Fixed (13 rows):

| File | Before | After |
|---|---|---|
| `docs/spec/debt_projection_contract.md` (4×) | `adr/0029-debt-projection-writer-authority.md` | `../adr/0029-debt-projection-writer-authority.md` |
| `docs/spec/debt_registry_schema.md` (1×) | `adr/0029-debt-projection-writer-authority.md` | `../adr/0029-debt-projection-writer-authority.md` |
| `docs/spec/query_no_obligations_debt.md` | `../core/proof/proof_integrity.nim` | `../../src/core/proof/proof_integrity.nim` |
| `docs/evidence/incident_emergency_disable_window_2026-10-20.md` (5×) | `../../spec/...` | `../spec/...` |
| `docs/evidence/jcas_phase1_observation_run_index.md` | `../../spec/gh_run_observation_quirks.md` | `../spec/gh_run_observation_quirks.md` |
| `docs/spec/legacy_migration_roadmap.md` | `AGENTS.md` | `../../AGENTS.md` |

Reported-only, real missing targets (7 rows, no unambiguous in-repo replacement):

| File | Target | Why not fixed |
|---|---|---|
| `docs/adr/0021-execution-authority.md` | `../spec/ci_admission_contract.md` | No such file has ever been committed (`git log --all -- docs/spec/ci_admission_contract.md` is empty); the link names a Phase-4 contract, not a renamed file. |
| `docs/evidence/s1a_causality_stage_a_2026-10-18.md` (2×) | `../../data/ci_pareto_baseline.json` | The data file is absent from the tree, not mis-pathed; it is also referenced by `config/repository_surface.json` and many evidence docs. Reconstructing measurement data is out of docs scope. |
| `docs/evidence/sal10_publication/DEPS_REPACKAGE_PROCEDURE.md` (2×) | `LICENSE-APACHE`, `LICENSE-MIT` | The same sentence explicitly describes these as nonexistent files referenced by the vendored headers ("존재하지 않는 파일을 참조") — the dead reference is the finding under discussion, not a navigation error. |
| `docs/history/hook_migration.md` | `../../.kimi-code/plans/dove-raven-wolverine.md` | A local session plan outside the repository; no tracked replacement exists. |
| `docs/spec/certification_continuity_contract.md` | `self_hosted_ci_migration.md` | The link sentence itself records that the target was deleted on 2026-09-20; the reference is historical provenance. |

Reported-only, link-like text with no intended target (28 rows):

- 27 occurrences of `[B2](b)` / `[B2](c)` across 9 ADR/audit/evidence files. Markdown renders these as dead links to a file named `b`/`c`; the evident intent is the literal label `B2(b)` / `B2(c)`. They were left untouched to avoid rewriting historical ADR/audit/evidence prose; a mechanical fix would escape the brackets.
- 1 occurrence of `[SKIPPED](:291-294)` in `docs/evidence/tests_ci_assurance_classification_2026-10-30.md`, a line-range reference rendered as a link.

Anchors: the initial run reported 3 missing anchors; all three were false positives of the checker's slug algorithm (GitHub preserves the double hyphen produced by removing `&`, an em dash, or `/` between spaces). After correcting the slug logic, **0 missing anchors** remain; no anchor edits were needed.

Gate context: `tools/ci/doc_path_validator.nim` deliberately skips `docs/design/` (forward-plan) and the archived scopes `docs/history/`, `docs/evidence/`, `docs/reports/`, `docs/audit/` per `tools/ci/archived_docs.json` (DEBT#403). A green doc-path gate is therefore not evidence that these links resolve.

---

## 6. Verification performed

- `git diff --check` → clean.
- Dead-link checker re-run on the edited tree → 667 relative targets, 0 missing anchors, 35 remaining rows (all enumerated above).
- `grep -rn "evaluateReadiness([^)]*context" docs/ tools/ tests/` → no matches.
- `grep -rn "policy\.schema\.json" ...` → only the corrected planned-schema row.
- Repository doc-path gate built from source and run: `nim c --hints:off -o:/tmp/doc_path_validator tools/ci/doc_path_validator.nim` (exit 0) and `/tmp/doc_path_validator .` → `[DOC-PATH-VALIDATOR] 모든 문서 경로가 유효합니다.` (exit 0). This gate skips `docs/design/` and the archived scopes, so it is supplementary to the relative-link scan, not a replacement.
- No full product build or test suite was run: every change is under `docs/`, and no test exercises these documents. The doc-path gate, dead-link scan, and signature checks above are the executed verification for this change.