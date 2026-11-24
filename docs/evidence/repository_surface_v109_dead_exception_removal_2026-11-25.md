# Repository surface v109 — dead-exception removal (2026-11-25)

- **Nature**: a policy amendment (`config/repository_surface.json` `policyVersion` 108 → 109) plus two new tools. No workflow host is wired, and no class other than the five dead paths changes.
- **Recorder is not approver**: the disposition executed here follows the observation record `docs/evidence/repository_surface_dead_exceptions_2026-11-24.md` and the in-session blanket execution authorization of 2026-11-25. The authority to change policy is the human architect's.
- **Scope discipline**: this record executes the part of that observation which the policy itself can decide (remove physically-absent registrations). It does **not** re-open the question of which non-authority `.github` paths should stay FROZEN — see §5.

## §0. Conclusion

Five of the 116 `frozenExceptions.paths` registrations at v108 pointed at paths that **do not exist** in the tree. A dead exception is not inert: because the guard's dead-exception check is a **policy-internal intersection test** and never consults the filesystem, a surviving registration for a deleted path keeps granting that path `CONTROLLED` (`ADD/MODIFY/DELETE = PASS`) and thereby **cancels the FROZEN `ADD = FAIL` default deny**. Measured both ways at §3.

Removing the five registrations turns them from a pre-approved re-introduction lane into ordinary FROZEN paths. Every one of the five transitions is `CONTROLLED → FROZEN` (**TIGHTENED**). There is no `LOOSENED` transition anywhere in the 41-path table.

## §1. The five removals

Both halves of each registration are removed together — the `classes.CONTROLLED` exact entry and the `frozenExceptions.paths` entry. Removing only the exception leaves an *unregistered* exact/FROZEN conflict, which the guard rejects as `POLICY_INVALID`; removing only the CONTROLLED entry leaves a *dead* exception, which the guard also rejects. The guard forces the pair to move as one unit, which is why the two edits are not separable.

| # | path | group | why it is absent | disposition |
|---|---|---|---|---|
| 1 | `.github/workflows/gateway-jobs-measure.yml` | `ci-infra` | retired by `6f875c45` (VS-C1); the commit states "the policy file is left untouched" | remove |
| 2 | `.github/workflows/h4-routing-measure.yml` | `ci-infra` | same commit | remove |
| 3 | `.github/workflows/hardware-falsification-smoke.yml` | `ci-infra` | same commit | remove |
| 4 | `.github/workflows/trust-surface-pin-notice.yml` | `ci-infra` | pre-registered in v87; the body PR never landed, zero commits in history | remove |
| 5 | `src/gate/orchestrator.nim` | `gate-infra` | `data/debt_registry.json` DEBT#476 `historicalFiles` already records it as `DELETED 2026-10-04` | remove |

Verification that these five are exactly the absent set (no more, no less):

```bash
jq -r '.frozenExceptions.paths | keys[]' config/repository_surface.json \
| while read -r p; do
    git cat-file -e "HEAD:$p" 2>/dev/null || echo "ABSENT  $p"
  done
# -> exactly the five paths in §1, nothing else
```

The set matches §2-7 of `docs/evidence/repository_surface_dead_exceptions_2026-11-24.md` exactly (that record computed 5 ABSENT / 111 present over 116).

## §2. What changed in the policy file

| field | v108 | v109 |
|---|---|---|
| `policyVersion` | 108 | **109** |
| `frozenExceptions.paths` | 116 | **111** |
| `classes.CONTROLLED` | 264 | **259** |
| `classes.FROZEN` | 12 | 12 (unchanged) |
| `rules` | unchanged | unchanged |
| `selfAmendment.allowedPaths` | 4 paths | unchanged |
| `resolutionOrder` | unchanged | unchanged |

`classes.FROZEN` is untouched — including the `.github/**` glob. This amendment removes five *exceptions to a glob*; it does not touch the glob, so a newly invented `.github` workflow is still denied by `FROZEN.ADD = FAIL`.

## §3. The security effect, measured with the shipped binary

Policy = v108 (before) and v109 (after). Diff = `A` (add) of the four removed workflow paths.

**Before (v108) — the dead exceptions pre-approve re-introduction:**

```bash
build/sg --policy <v108>.json --diff /tmp/add4.txt
# { "verdict": "PASS", "reasonCode": "OK", "policyVersion": 108 }
# exit 0
```

**After (v109) — the same change is refused:**

```bash
build/sg --policy config/repository_surface.json --diff /tmp/add4.txt
# { "verdict": "FAIL", "reasonCode": "SURFACE_FORBIDDEN", "policyVersion": 109 }
# violations: 4 x { changeClass: "FROZEN", reasonCode: "SURFACE_FORBIDDEN" }
# exit 1
```

This is the whole point of the slice: the FROZEN rule says `ADD: FAIL`, yet at v108 an `ADD` of a **retired** workflow returned `PASS`. At v109 it returns `FAIL`. The direction of the change is a **hardening**.

## §4. Invariance table — zero loosened transitions

Produced by `tools/ci/surface_invariance_table.nim` over the 29 tracked `.github` paths, the five removed paths, and the representative control paths named in the task (`AGENTS.md`, `src/gate/x.nim`, `config/policy/epoch_manifest.json`, `docs/x.md`, `tools/surface_guard.nim`), plus two synthetic probes for paths that do not exist yet (`.github/workflows/brand-new-workflow.yml`, `.github/agents/new-agent.md`).

```bash
build/sit --old policy_v108.json --new policy_v109.json \
  --paths repr_paths_plus.txt --manifest config/policy/trust_surface_manifest.json \
  --intent no-regression
```

Result: **41 paths evaluated, 36 SAME, 5 TIGHTENED (the §1 removals), 0 LOOSENED, verdict PASS, exit 0.**

The two distinct `.github` outcomes that matter:

| path | v108 | v109 | direction |
|---|---|---|---|
| `.github/workflows/brand-new-workflow.yml` (does not exist) | `FROZEN` | `FROZEN` | `SAME` — new-workflow ADD denial is intact |
| `.github/agents/new-agent.md` (does not exist) | `FROZEN` | `FROZEN` | `SAME` — non-workflow `.github` ADD denial is intact |

The full table is in the PR body. Nothing moved from a permissive class into FROZEN except the five dead paths, and nothing moved out of FROZEN at all.

## §5. Deliberately NOT done — the App-manifest overlay question

The task framing proposed removing the `.github/**` FROZEN glob and re-registering the tracked `.github` paths as exact `CONTROLLED`, excluding the App-manifest members. Measurement does not support that change, and it was **not** made:

1. **Only 3 of the 8 FROZEN `.github` paths are outside the App manifest** — `.github/CODEOWNERS`, `.github/pull_request_template.md`, `.github/workflows/observation.yml`. The other five (`axiom-operational-slice.yml`, `bsec-integrity.yml`, `debt-registry-gate.yml`, `generation-acceptance.yml`, `runner-pool-acceptance.yml`) are manifest members. So the premise "8 resolve FROZEN while only 10 are governed by the App manifest, 19 are FROZEN-only" does not describe this tree.
2. **For those three, FROZEN is the *only* lock.** They are outside the manifest, so the App blob-equality comparison does not cover them. Re-registering them as `CONTROLLED` would not remove a *redundant* lock — it would remove the *only* lock, which is a security regression. `.github/CODEOWNERS` additionally **is** the owner-binding device the manifest's rationale relies on.
3. **v101 already closed this exact class in the other direction.** It *removed* `observation.yml` from `CONTROLLED` precisely because an exact `CONTROLLED` entry defeats the FROZEN glob (`DEBT#545`). Re-adding it as `CONTROLLED` at v109 would re-open the class v101 closed.
4. **The schema has no per-op, per-path granularity.** `ruleValue` (`tools/surface_guard.nim`) reads `rules[class][op]` only, so an "ADD-only FROZEN" mechanism for `.github/workflows/*` cannot be expressed. The task's fallback ("keep the glob, register the tracked paths in `frozenExceptions`") is what the policy *already does* — 25 of the 116 exceptions are `.github` paths.

What v109 does instead is remove the five registrations that were actively wrong (dead), which is the part of the measured problem the policy can actually decide.

## §6. Verification commands and results

```bash
# 1. policy is structurally valid at v109
build/sg --policy config/repository_surface.json --diff /dev/null
# -> {"verdict":"PASS","reasonCode":"OK","policyVersion":109}

# 2. the dead-exception lane is closed (§3, after)
build/sg --policy config/repository_surface.json --diff /tmp/add4.txt
# -> FAIL / SURFACE_FORBIDDEN, exit 1

# 3. invariance, zero loosened
build/sit --old policy_v108.json --new policy_v109.json \
  --paths repr_paths_plus.txt --manifest config/policy/trust_surface_manifest.json \
  --intent no-regression
# -> 41 paths, 36 SAME, 5 TIGHTENED, 0 LOOSENED, verdict PASS, exit 0

# 4. new tool unit test
nim c -r --hints:off --skipParentCfg --skipProjCfg --skipUserCfg \
  --noNimblePath --nimcache:build/nimcache/tsit -o:build/tsit \
  tests/unit/test_surface_invariance_table.nim
# -> 11 tests, all OK, exit 0

# 5. surface-guard test, before vs after this change
nim c -r --hints:off --skipParentCfg --skipProjCfg --skipUserCfg \
  --noNimblePath --nimcache:build/nimcache/tsg -o:build/tsg \
  tests/unit/test_surface_guard.nim
```

Surface-guard test, attributable diff: **59 `[OK]` and exactly one `[FAILED]` both before and after.** Only the two already-stale magic numbers inside that one test moved (`len == 109` saw 116 → 111; `policyVersion == 102` saw 108 → 109). No new failure was introduced. `tests/unit/test_surface_guard.nim` is owned by another slice and was **not** edited here.

## §7. Confirmed versus not confirmed

| claim | status |
|---|---|
| exactly five `frozenExceptions` paths are physically absent | **confirmed** (`git cat-file -e` over all 116) |
| those five are the set the 2026-11-24 record identified | **confirmed** (same five) |
| a dead exception lets an `ADD` of a retired workflow `PASS` at v108 | **confirmed** (real binary, §3 before) |
| removing them makes the same `ADD` `FAIL` at v109 | **confirmed** (real binary, §3 after) |
| the change introduces zero `LOOSENED` transitions over 41 paths | **confirmed** (§4) |
| the other 111 exceptions remain load-bearing (liveness test still green) | **confirmed** (surface-guard test `[OK]`) |
| 8 of the 18 App-manifest members already resolve non-FROZEN | **confirmed** and **pre-existing** — identical count at v108 and v109; left untouched, disclosed, not decided here |
| `src/gate/orchestrator.nim` is also a `config/topology.json` ghost entry | **inherited from the 2026-11-24 record, not re-checked** |

## §8. Follow-ups (not done here)

- **The 8 manifest members that resolve non-FROZEN** (`.github/actions/setup-axiom-toolchain/action.yml`, `admission-gate-v2.yml`, `admission-check.yml`, `certificate-mint.yml`, `publication-integrity.yml`, `config/policy/epoch_manifest.json`, `config/trusted_writer_set.json`, `tests/ci/test_vs0_admission_aggregate_fail_closed.nim`) are a real surface/manifest divergence. They were narrowed deliberately in v105–v108 on the recorded ground that the App lock is binding; whether the surface guard should *assert* agreement with the manifest is a policy question this slice does not decide. `surface_invariance_table --require-manifest-frozen` is the switch that would turn today's report into an assertion, and it would currently FAIL — by design, that is a decision for the architect.
- **`tests/unit/test_surface_guard.nim` remains red** on its two stale magic numbers. Owned elsewhere; see §6.
- **No workflow wiring.** The two tools are CLI-only and are invoked by the PR body reproduction, not by a required check. Adding a required context would change the ruleset, which this slice does not do.
