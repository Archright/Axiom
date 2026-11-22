# Contributing to Axiom

Axiom is a developer CLI for deterministic verification results, assurance grades, and
locally replayable verification artifacts over a supported Nim kernel scope. This
document describes what a contribution must satisfy before it can land on `main`.

## 1. Read the CLA first

Do not open a pull request before reading the applicable Contributor License
Agreement. Axiom accepts contributions only under one of:

- [`CLA/Individual-CLA.md`](CLA/Individual-CLA.md) -- for contributions you own
  personally, submitted in your individual capacity.
- [`CLA/Corporate-CLA.md`](CLA/Corporate-CLA.md) -- for contributions owned by your
  employer, a client, or any organization you belong to. It requires an Authorized
  Representative to accept and a completed Schedule A listing the company and the
  GitHub usernames and organizations authorized to contribute on its behalf.

What both agreements do, in summary:

- Grant the Licensor (Suhyok Yoon) a perpetual, worldwide, non-exclusive,
  royalty-free, irrevocable copyright license to use, reproduce, modify, distribute,
  sublicense, and relicense your contributions, including under separate commercial
  terms.
- Grant a patent license for claims necessarily infringed by your contributions, with
  termination if you initiate patent litigation over the project.
- Waive moral rights to the maximum extent permitted by applicable law.
- Impose no obligation on the Licensor to accept or use a contribution, and create no
  employment, agency, or partnership relationship.
- Allow withdrawal at any time by written notice to wintrover@gmail.com, prospectively
  only: contributions submitted before withdrawal remain licensed.
- Are governed by the laws of the Republic of Korea, with disputes submitted to the
  courts of Seoul. The English text is authoritative.

Acceptance is by signing and emailing the agreement to wintrover@gmail.com, or by an
electronic acceptance mechanism if the project operates one. If you are unsure which
agreement applies, use the corporate one when any employer or client may own or claim
rights in your work. The full texts control; the summary above does not.

## 2. Language policy

English is the single language for:

- source code, comments, identifiers, and user-facing strings;
- documentation, specifications, ADRs, and evidence records;
- commit messages;
- issues, pull requests, and reviews.

Private conversational dialogue may be Korean. That exception covers conversation
between people, not tracked text and not the repository-side record of a change.

The English-only rule is defined in
[`docs/spec/english_only_policy.md`](docs/spec/english_only_policy.md) and decided in
[ADR-0045](docs/adr/0045-english-only-canonical-main.md). Two things it is not:

- It is not the existing `script-scan` dimension of `publication-integrity`. That
  dimension is a Unicode Script allowlist over added diff lines; it does not detect
  Latin-script non-English prose and it is not an English-only guarantee.
- It is not a reason to rewrite history. Past Git objects stay as they are.

**Translated changes require a translation lineage record.** A change that translates
existing text must include a batch manifest under `data/translation_lineage/` that
records the source blobs, the translated blobs, the engine pin, the glossary digest,
and the review state. The schema and rules are in
[`docs/spec/translation_lineage.md`](docs/spec/translation_lineage.md). Legal
provenance (`compliance/provenance/source-origin.yml`) and translation lineage are
separate records and must not be merged.

## 3. Local setup

The pinned toolchain is Nim 2.2.10 and Lean 4.29.0 via `elan`. Do not substitute a
different compiler version for a landing-bound change.

In a fresh worktree:

```bash
make -f ci/checker.mk setup-hooks     # install .githooks as core.hooksPath
make ci-bootstrap                      # build tools, init hooks, baseline
```

A fresh worktree has no `bin/` and no generated `src/generated/build_env.nim`. Copying
`bin/` from an existing clone is acceptable for local verification; copying
`src/generated/build_env.nim` is not, because it carries a build-source hash stamped
for a different tree. `make ci-bootstrap` regenerates it. Never commit generated
artifacts.

The closed-world build entry points are `nimble build` and `nimble test`; runtime
network access is not available to the build.

## 4. Run the local gates before you push

```bash
make local-verify-static              # 16 in-place verify-static gates
tools/local_purity_check              # runs the 15-gate suite in an isolated worktree
```

`local-verify-static` is the fast static surface. `local_purity_check` reproduces a
fresh checkout and catches the "works only with my untracked files" class of failure.
Run it before every push that changes tracked content.

Commit through the gated path, not raw `git commit`:

```bash
bin/axiom-gate commit -m "<English message>"
```

Synchronize a branch with `ax git sync`. Raw `git rebase` and raw `git merge` in the
terminal are prohibited by policy; `ax git sync` is the only approved local sync path.

Explicitly forbidden, with no exception for small changes:

- `git commit --no-verify` and `git push --no-verify`;
- `gh pr merge --admin`;
- any other bypass of a required check, a hook, or a ruleset rule.

A hook that is inconvenient is a signal to fix the change, not to skip the hook.

## 5. Pull request and landing path

Axiom lands through GitHub, not through a local merge:

1. Push the topic branch: `git push -u origin <branch>`.
2. Open the PR against `main`: `gh pr create --base main --head <branch>`.
3. Arm auto-merge with the GitHub primitive:
   `gh pr merge <n> --auto --match-head-commit <head>`.

The `main` ruleset requires seven status contexts. All seven must be `success` in the
merge queue:

| context | producer |
|---|---|
| `admission-check` | Axiom admission App (`integration_id 5795152`) |
| `bsec-integrity` | GitHub Actions (`integration_id 15368`) |
| `debt-registry-gate` | GitHub Actions |
| `generation-acceptance` | GitHub Actions |
| `axiom-operational-slice` | GitHub Actions |
| `publication-integrity` | GitHub Actions |
| `readiness-verdict` | GitHub Actions |

The merge queue groups with `ALLGREEN`, builds one entry at a time, and lands with the
native **MERGE** commit. Squash and rebase merges are disabled at the repository level
because the certified-landing invariant binds the PR head as `parent2` of the merge
commit. Do not rebase or rewrite a PR head after checks have started; push new commits
instead.

`publication-integrity` is the only required context that judges repository content.
Its dimensions are secret scanning, license scanning, dependency scanning, provenance,
SBOM, and the Unicode Script allowlist. A PR that changes a workflow, a policy file, or
another trust-surface path cannot receive `admission-check` and therefore cannot land
through the queue; see section 6.

## 6. Paths an ordinary contributor must not change

Two lists bound the authority surface. The files are the SSOT; the lists below are a
snapshot and may move.

**App trust surface** -- `config/policy/trust_surface_manifest.json` (18 paths). A PR
that alters any of them cannot receive the independent verifier's `admission-check`,
because that check requires every listed path to be byte-identical between the
merge-group commit and its base:

- `.github/actions/setup-axiom-toolchain/action.yml`
- `.github/workflows/admission-gate-v2.yml`
- `.github/workflows/admission-check.yml`
- `.github/workflows/axiom-operational-slice.yml`
- `.github/workflows/bsec-integrity.yml`
- `.github/workflows/certificate-mint.yml`
- `.github/workflows/debt-registry-gate.yml`
- `.github/workflows/generation-acceptance.yml`
- `.github/workflows/publication-integrity.yml`
- `.github/workflows/runner-pool-acceptance.yml`
- `config/app_landing_binding.json`
- `config/policy/epoch_manifest.json`
- `config/policy/merge_admission.json`
- `config/policy/trust_surface_manifest.json`
- `config/repository_surface.json`
- `config/trusted_writer_set.json`
- `tests/ci/test_vs0_admission_aggregate_fail_closed.nim`
- `tools/surface_guard.nim`

**FROZEN class** -- `config/repository_surface.json`. Add, modify, and delete all fail
for these paths:

- `AGENTS.md`
- `config/repository_surface.json`
- `config/executor_authority.json`
- `config/app_landing_binding.json`
- `config/publication_scope.json`
- `config/policy/**`
- `.github/**`
- `.githooks/**`
- `tools/hooks/**`
- `src/gate/**`
- `vendor/**`
- `tools/surface_guard.nim`

If you believe a change to one of these paths is necessary, do not open a normal PR
for it. Explain the need in an issue first; these changes require an audited
break-glass lane and, where applicable, an epoch rotation.

## 7. What a reviewable change looks like

- One intent per PR. Unrelated refactoring is out of scope, even when it is nearby.
- A stated terminal outcome with machine-checkable evidence: the command, the
  observable result, and the pass condition.
- Tests only where the project already has tests for the area; do not invent a test
  framework for a documentation change.
- Documentation in English, links that resolve, and no duplicated normative statement
  that already lives in its SSOT.
- Evidence for behavior changes: the run output or artifact that shows the behavior,
  not a claim that it works.

## 8. Further reading

- [`AGENTS.md`](AGENTS.md) -- the project constitution: facts, invariants, authority,
  acceptance.
- [`docs/agents/task-process.md`](docs/agents/task-process.md) -- task scope and
  completion policy.
- [`docs/agents/operations.md`](docs/agents/operations.md) -- local operations, gate
  pipeline, and the canonical landing sequence.
- [`docs/agents/quality-gates.md`](docs/agents/quality-gates.md) -- pre-commit and
  pre-push gate detail.
- [`docs/agents/rules_workflow.md`](docs/agents/rules_workflow.md) -- git and landing
  rules, including the native-MERGE landing policy.
- [`docs/spec/english_only_policy.md`](docs/spec/english_only_policy.md) -- language
  scope, modes, metrics, terminal criteria.
- [`docs/spec/translation_lineage.md`](docs/spec/translation_lineage.md) -- translation
  batch manifest.