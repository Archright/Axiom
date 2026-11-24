# Repository surface dead exceptions — the five paths that do not exist (2026-11-24 UTC)

- **Nature**: an observation record. Policy and config files are **not modified**. No verdict is issued — only disposition candidates are recorded.
- **Observation window**: `2026-11-24T05:38Z` – `2026-11-24T05:49Z` (UTC)
- **Observed target**: live default branch `Archright/Axiom` `main` = `c07b8354b6af6db666c99f9480856ab37b9ed6c4`
- **Policy reference**: `config/repository_surface.json` `policyVersion 108` (blob `7643eebb1e4f7b33e5529cce65a3a0b06f687514`)
- **Recorder is not approver**: the author is an agent; the authority to decide dispositions rests with the human architect.

## §0. Conclusion

**5 of the 116** entries in `frozenExceptions.paths` do not exist on live `main`. The five are **two distinct phenomena**, and treating them as one produces the wrong disposition.

| # | phenomenon | paths | basis |
|---|---|---|---|
| 1 | **residue after an intended retirement** | `gateway-jobs-measure.yml`, `h4-routing-measure.yml`, `hardware-falsification-smoke.yml` | deletion commit `6f875c45` states "the policy file is left untouched" |
| 2 | **body PR never landed** | `trust-surface-pin-notice.yml` | policy registration in v87 (2026-10-23) only; zero body commits |
| 3 | **double-historical registration mismatch** | `src/gate/orchestrator.nim` | DEBT#476 already records it under `historicalFiles` (`DELETED 2026-10-04`); the policy exception does not reflect that |

The key finding is that "dead exceptions are harmless" is **not** true. As §5 shows by measurement, a dead exception is still a **valid CONTROLLED pre-approval**, and it **passes the re-introduction** of a path that the FROZEN glob would otherwise deny by default.

## §1. Per-path observation rows

All five rows returned `lookup_result = NOT_FOUND (HTTP 404)`. `observed_at` is the time of each call, and the commands in §2 reproduce them exactly.

| path | observed_main_sha | observed_at | lookup_result | exception_group | disposition |
|---|---|---|---|---|---|
| `.github/workflows/gateway-jobs-measure.yml` | `c07b8354b6af6db666c99f9480856ab37b9ed6c4` | `2026-11-24T05:48:52Z` | `NOT_FOUND (HTTP 404)` | `ci-infra` | `RETIRE_RESIDUE` — retired as VS-C1 by `6f875c45`; only the exception registration remains |
| `.github/workflows/h4-routing-measure.yml` | `c07b8354b6af6db666c99f9480856ab37b9ed6c4` | `2026-11-24T05:48:53Z` | `NOT_FOUND (HTTP 404)` | `ci-infra` | `RETIRE_RESIDUE` — same commit |
| `.github/workflows/hardware-falsification-smoke.yml` | `c07b8354b6af6db666c99f9480856ab37b9ed6c4` | `2026-11-24T05:48:53Z` | `NOT_FOUND (HTTP 404)` | `ci-infra` | `RETIRE_RESIDUE` — same commit |
| `.github/workflows/trust-surface-pin-notice.yml` | `c07b8354b6af6db666c99f9480856ab37b9ed6c4` | `2026-11-24T05:48:54Z` | `NOT_FOUND (HTTP 404)` | `ci-infra` | `NEVER_LANDED` — pre-registered in v87, body never landed, zero commits in this repository's history |
| `src/gate/orchestrator.nim` | `c07b8354b6af6db666c99f9480856ab37b9ed6c4` | `2026-11-24T05:48:55Z` | `NOT_FOUND (HTTP 404)` | `gate-infra` | `STALE_VS_DEBT_REGISTRY` — DEBT#476 `historicalFiles` already records it as historical |

`disposition` is a **candidate label**, not an executed change. No policy or config file was modified.

## §2. Reproduction commands

Every lookup queried the live API directly. The local clone does not contain `c07b8354` (§3), so this record cannot be reproduced with local `git` alone.

```bash
# 0. identify the target and pin the default branch
gh api repos/{owner}/{repo} --jq '{full_name, default_branch}'
# -> {"default_branch":"main","full_name":"Archright/Axiom"}
gh api repos/Archright/Axiom/git/ref/heads/main --jq '.object.sha'
# -> c07b8354b6af6db666c99f9480856ab37b9ed6c4

# 1. existence check per path (5 calls) — read the HTTP status directly
SHA=c07b8354b6af6db666c99f9480856ab37b9ed6c4
for p in \
  .github/workflows/gateway-jobs-measure.yml \
  .github/workflows/h4-routing-measure.yml \
  .github/workflows/hardware-falsification-smoke.yml \
  .github/workflows/trust-surface-pin-notice.yml \
  src/gate/orchestrator.nim ; do
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  code=$(gh api "repos/Archright/Axiom/contents/$p?ref=$SHA" --silent --include | head -1 | awk '{print $2}')
  echo "$ts HTTP=$code $p"
done
# -> 5 rows, all 2026-11-24T05:48:5xZ HTTP=404

# 2. positive control — proves the query shape itself is valid (404 is not "bad query")
gh api "repos/Archright/Axiom/contents/.github/workflows/admission-check.yml?ref=$SHA" \
  --jq '{name, sha, size}'
# -> {"name":"admission-check.yml","sha":"433be3c34c51cfc3fc6f8741009135cfa5906a03","size":327211}
gh api "repos/Archright/Axiom/contents/config/repository_surface.json?ref=$SHA" \
  --jq '{name, sha, size}'
# -> {"name":"repository_surface.json","sha":"7643eebb...","size":103648}

# 3. exhaustive tree comparison — 7,581 entries, not truncated
gh api "repos/Archright/Axiom/git/trees/$SHA?recursive=1" --jq '.truncated'
# -> false
gh api "repos/Archright/Axiom/git/trees/$SHA?recursive=1" --jq '.tree[].path' > /tmp/tree.txt
for p in <the 5 paths above>; do grep -qxF "$p" /tmp/tree.txt && echo PRESENT || echo ABSENT; done
# -> 5 rows, all ABSENT

# 4. directory listing — rules out case and path variants
gh api "repos/Archright/Axiom/contents/.github/workflows?ref=$SHA" --paginate --jq '.[].name' | sort
# -> 25 files, none of the 5 paths
gh api "repos/Archright/Axiom/contents/src/gate?ref=$SHA" --paginate --jq '.[].name' | sort
# -> no orchestrator.nim; src/gate/orchestrator/ contains hook/ only

# 5. history query — distinguishes "was deleted" from "never existed"
gh api "repos/Archright/Axiom/commits?path=.github/workflows/trust-surface-pin-notice.yml&sha=main" --jq 'length'
# -> 0
gh api "repos/Archright/Axiom/commits?path=src/gate/orchestrator.nim&sha=main" --jq 'length'
# -> 0

# 6. confirm the deletion commit and its ancestry (not in the local clone, so via the API)
gh api "repos/Archright/Axiom/commits/6f875c45535e6bcc28032db48bbe7fe42158302d" \
  --jq '{sha, date: .commit.committer.date, msg: (.commit.message | split("\n")[0])}'
# -> 2026-11-14T14:28:16Z "ci: retire three zero-run measurement workflows (VS-C1)"
gh api "repos/Archright/Axiom/compare/6f875c45...main" --jq '{status, behind_by}'
# -> {"status":"ahead","behind_by":0}  (= an ancestor of main)

# 7. exhaustive scan of frozenExceptions — verify the brief's 5 are complete
#    (config/repository_surface.json @ c07b8354, 116 frozenExceptions.paths entries)
#    -> 5 ABSENT, 111 present. The list matches §1 exactly. Nothing else.
```

## §3. Environment caveat — the local clone is not live `main`

Local clone `HEAD` = `160e70cda364e5745133d3f04d2e1295b4a026df` (local `main`, based on the commit at 2026-11-24T03:27:38Z); live `main` = `c07b8354`. The local clone does **not contain** `c07b8354`.

Every verdict in this record rests on live API responses. Local `git log` was used only as **supporting evidence** for §1's "zero commits in history" claim; the final confirmation was performed with the `commits?path=` API (§2-5). The reason: when a local clone is stale, "absent from history" can be a false negative.

## §4. Residual protection — do other devices reference these five paths

Per `AGENTS.md`, "a dead exception inside the App byte-identity set" and "a dead exception referenced nowhere" are different findings. Three files were read directly at the live SHA.

| device | file | size | references among the 5 | note |
|---|---|---|---|---|
| surface guard policy | `config/repository_surface.json` | 116 exceptions / 264 CONTROLLED | **5/5** | the only referrer (§4.1) |
| App byte-identity | `config/policy/trust_surface_manifest.json` | **18 paths** | **0/5** | blob-equality comparison set |
| merge admission manual audit | `config/policy/merge_admission.json` → `trustSurface` | **39 entries** | **0/5** | includes 1 glob (`.github/actions/setup-axiom-toolchain/**`) |
| checker closure | `config/trusted_checker_closure.json` → `trustedCheckerTreeClosure` | **891 entries** | **0/5** | 0 wildcard keys — glob bypass impossible |
| CODEOWNERS | `.github/CODEOWNERS` | — | 0/5 | no measurement/orchestrator entries |
| required context | `merge_admission.requiredValidations` | 6 entries | 0/5 | the 5 paths produce no required check |

```bash
# §4 reproduction
SHA=c07b8354b6af6db666c99f9480856ab37b9ed6c4
for f in config/policy/trust_surface_manifest.json \
         config/policy/merge_admission.json \
         config/trusted_checker_closure.json ; do
  gh api "repos/Archright/Axiom/contents/$f?ref=$SHA" --jq '.content' | base64 -d > /tmp/$(basename $f)
done
# then search each file for the 5 path strings -> 0 hits everywhere
```

### §4.1 The only referrer is the policy itself

`config/trusted_checker_closure.json` uses no wildcard keys at all (`[k for k in c if '*' in k]` → `[]`), so there is no implicit inclusion via glob. The five paths are **explicitly absent** from the 891 set. The only live device covering the five paths is therefore the exception registration in `repository_surface.json` itself.

## §5. Dead exceptions are not inert — measured

The dead-exception judgment in `tools/surface_guard.nim` is an **intersection check inside the policy text** and never looks at the filesystem (`isValidPolicy`, `tools/surface_guard.nim:464-466`: `for e in excPaths: if e notin conflicts: return false`). `conflicts` is computed from the intersection of exact patterns in `classes.CONTROLLED` with globs in `classes.FROZEN` (`tools/surface_guard.nim:447-460`); **on-disk existence is not an input**. So even after a file is deleted, if its exception registration remains in CONTROLLED the guard does not judge it "dead" — the guard's dead check catches only **policy inconsistency**, never **physical absence**.

That consequence was confirmed with the actual binary (`bin/surface_guard`, Linux ELF, run under WSL `Ubuntu-24.04`, policy = live v108).

| scenario | diff | verdict | reasonCode | exit | reading |
|---|---|---|---|---|---|
| A. no change | empty | `PASS` | `OK` | 0 | the 5 entries **pass** structural validation (not rejected as dead) |
| B. re-add the 5 paths | `A` × 5 | `PASS` | `OK` | 0 | **the dead exception neutralizes the FROZEN default deny** — re-introduction permitted |
| C. modify the 5 paths | `M` × 5 | `PASS` | `OK` | 0 | same |
| D. counterfactual: remove the 5 registrations, same `A` × 5 | `A` × 5 | `FAIL` | `SURFACE_FORBIDDEN` | 1 | FROZEN (`.github/**`, `src/gate/**`) works as designed |

```bash
# reproduction (B / D). D runs against a policy copy with both registrations removed
# (CONTROLLED exact + frozenExceptions.paths) before execution.
./bin/surface_guard --policy <policy.json> --diff <name-status>
```

**The B-versus-D contrast is the point**: the FROZEN rule is `ADD: FAIL`, yet under the live policy (B) an `ADD` of these five paths is `PASS`. So the `ci-infra` / `gate-infra` exceptions in §1 are not "dead but harmless residue" — they remain a **pre-approved lane for re-adding a retired workflow**. Remove the registration (D) and the same change is rejected as `FROZEN` / `SURFACE_FORBIDDEN`. The registrations are **load-bearing** for the verdict.

This is an observation from the §0.9 (theater prohibition) perspective: the exception registration guarantees nothing for the files that exist, while for files that do not exist it lifts the FROZEN default deny. This record nonetheless **issues no verdict** — the table above is an observation.

## §6. Separating the two phenomena — why dispositions must differ

### §6.1 Three retirement residues (`RETIRE_RESIDUE`)

The full message of deletion commit `6f875c45535e6bcc28032db48bbe7fe42158302d` (2026-11-14T14:28:16Z):

> `gateway-jobs-measure, h4-routing-measure, hardware-falsification-smoke` have zero runs and no consumer path (workflow_call, workflow_run, API dispatch, docs/ops, ruleset). None produces a required context. Baseline policy lists them as DELETE (always PASS); **the policy file is left untouched.**

The commit itself records that the policy file was not touched. So these three are an **explicit omission, not an oversight**. What the message does not record is that the omission left the ADD lane of §5 open.

All three paths **did exist** at baseline `c021c338` (`git cat-file -e c021c338:<path>` → PRESENT). They are files that once existed in this repository.

**Chronology (by the version notes in the policy description)**

| time | event | source |
|---|---|---|
| 2026-10-13 (v79) | `h4-routing-measure.yml` moved FROZEN → CONTROLLED | description v79 |
| 2026-11-12 (v97) | `gateway-jobs-measure.yml` and `hardware-falsification-smoke.yml` re-approved as CONTROLLED | description v97 |
| 2026-11-14T14:28:16Z | `6f875c45` deletes the three workflows, policy unmodified | commit message |
| 2026-11-18 (v102) | 109 entries organized into `frozenExceptions` — **including the three already deleted** | description v102 |

So the three dead entries were **re-registered into an exception group after deletion**. The v102 organization work did not check on-disk existence of the target paths (it passed because the §5 dead judgment is a structural check). That ordering means "they were already dead at registration time", and unlike §6.2 and §6.3, it is the shape where **deletion and re-registration did not know about each other**.

### §6.2 One never-landed path (`NEVER_LANDED`)

`.github/workflows/trust-surface-pin-notice.yml` is a path that v87 (2026-10-23) **pre-registered** under "stage 2 = the body lands as a normal push after this PR merges, in the trust-surface-pin-notice placement PR". Against the live API, the `commits?path=` response is **empty**, and the path is also absent at baseline `c021c338`. The body PR never landed in this generation.

Its disposition differs from §6.1: it was not retired, it **never arrived**. The disposition options are (a) land the body PR, or (b) withdraw the registration; this record decides neither.

### §6.3 One double-historical mismatch (`STALE_VS_DEBT_REGISTRY`)

`src/gate/orchestrator.nim` is already recorded as historical in the DEBT#476 entry of `data/debt_registry.json`:

```
"lineRange": "...; src/gate/orchestrator.nim:1-160 (DELETED 2026-10-04, zero importers)"
"historicalFiles": ["src/gate/orchestrator.nim"]
```

So **a second authority already declared the file absent**, while the `gate-infra` exception in `repository_surface.json` did not reflect that. Unlike §6.1 and §6.2 this is **an inconsistency between two registries inside the repository**, the shape where one fact exists in two states.

A side observation: `config/topology.json:1077` still declares this path with `domain: gate, subdomain: root`. Because `src/core/topology/suggest.nim:116` detects "declared in topology.json but missing on disk" as a ghost path, this path carries a **third** inconsistency axis (the topology declaration). Whether the topology detector actually reports this entry was not checked in this record — it remains unverified.

## §7. Confirmed versus not confirmed

| claim | status |
|---|---|
| the 5 paths are absent from live `main` | **confirmed** (HTTP 404 × 5, exhaustive tree comparison, directory listing) |
| exactly 5 of the 116 `frozenExceptions` entries are absent | **confirmed** (exhaustive scan) |
| no other protection device references the 5 paths (18/39/891/CODEOWNERS/required) | **confirmed** |
| the three workflows were retired intentionally and the policy was intentionally left unmodified | **confirmed** (`6f875c45` message) |
| `trust-surface-pin-notice.yml` has no commits in this repository's history | **confirmed** (API `commits?path=`, 0 results) |
| `orchestrator.nim` is recorded as historical in DEBT#476 | **confirmed** |
| a dead exception lifts the FROZEN ADD default deny | **confirmed** (§5 scenarios B vs D, real binary) |
| the `topology.json` ghost-path detector reports `orchestrator.nim` | **not confirmed** — the tool was not run |
| removing the exception registrations is the correct disposition | **no verdict** — human architect authority |

## §8. Out of scope and follow-ups

- No policy or config modification. `config/repository_surface.json`, `config/policy/*`, `config/trusted_checker_closure.json`, and `data/debt_registry.json` were all **read only**.
- The per-group presence rates in §8.1 aggregate the §2-7 exhaustive tree comparison by group, and are an **exhaustive** measurement of all 116 entries (not a sample).
- No gate was found in this record that mechanically checks consistency between DEBT#476's `historicalFiles` in `data/debt_registry.json` and `repository_surface.json`. Whether automated detection exists on that axis is unconfirmed.

### §8.1 Per-group on-disk presence (exhaustive)

| group | registered | absent | present | absent paths |
|---|---|---|---|---|
| `generated-manifest` | 52 | 0 | 52 | — |
| `gate-infra` | 38 | **1** | 37 | `src/gate/orchestrator.nim` |
| `ci-infra` | 19 | **4** | 15 | `gateway-jobs-measure.yml`, `h4-routing-measure.yml`, `hardware-falsification-smoke.yml`, `trust-surface-pin-notice.yml` |
| `epoch-rotation` | 2 | 0 | 2 | — |
| `admission-mint-pin-rotation` | 2 | 0 | 2 | — |
| `fresh-prove-observation` | 1 | 0 | 1 | — |
| `trust-supply-path` | 1 | 0 | 1 | — |
| `publication-venue-split` | 1 | 0 | 1 | — |
| **total** | **116** | **5** | **111** | |

The absences are distributed over only two groups: `ci-infra` (4/19 = 21.1%) and `gate-infra` (1/38 = 2.6%). The other six groups have zero absences. Both groups register **exact paths**, and `ci-infra`'s higher absence rate follows from the group collecting "carve-outs of existing reviewed workflows", so workflow retirements accumulate there directly.