# ADR-0048: Whether `certificate-mint.yml` May Advance to Its Next Content -- Lane Decision for the DEBT#554 Fail-Open Path

## Status

**Accepted -- Option 2 (trust ceremony) adopted, Option 1 rejected (2026-11-23)**

- **Date and authority**: 2026-11-23 -- records the blanket approval granted in this session by the sole architect of the repository (`wintrover`, sole member of `@Archright/architect`) for the decision-recording work. This approval is a session-level blanket authorization, not a signed or sealed document; this record does not claim a signing artifact, an independent second reviewer, or a committee (AGENTS.md §0.9 honest-executor; same recording precedent: `docs/evidence/breakglass_trust_surface_landing_2026-11-19.md:21`).
- **Decision and effect**:
  1. **Option 2 adopted** -- perform the trust ceremony that fixes the **next accepted content** of `.github/workflows/certificate-mint.yml`, and reopen PR #293 on top of it (§3.2).
  2. **Option 1 (advancing the pin) explicitly rejected** -- for the two measured reasons in §3.1.
  3. **Option 3 (wontfix) not adopted** -- for the reasons in §3.3; option 3 is not chosen silently.
  4. **DEBT#554 remains Open** -- this document does not modify `docs/DEBT_REGISTRY.md:263` or `data/debt_registry.json`.
- **Boundary invariant**: Accepting this document changes no workflow, policy, schema, pin, or registry. The ceremony and its landing are a **break-glass + epoch rotation independent of this ADR**, and landing this ADR does not fix the fail-open defect -- the `2>/dev/null` pipelines at `:2272` and `:2286` remain live after this document merges (measured: §2.1). This PR adds a single file under `docs/adr/**`; that path is absent from the 39 entries of `config/policy/merge_admission.json` `trustSurface` (the string `docs/adr` appears only in description prose at `:4`), absent from the 18 paths of `config/policy/trust_surface_manifest.json` (0 hits), absent from the 891 entries of `config/trusted_checker_closure.json` `trustedCheckerTreeClosure` (0 hits), and permitted by the rotation allowlist in `src/cli/merge_cli.nim:1036` (`RotationAdrGlob = "docs/adr/**"`, `:228`). Therefore this PR uses the normal lane.

## 0. Tracking

- **Issue #384** -- canonical tracking issue for this decision (Open). This document does not close the issue.
- **DEBT#554** -- `docs/DEBT_REGISTRY.md:263` (Medium, `CI/Pipeline Health`, **Open**). Canonical tracking entry for the decision-pending state of this drift; this document does not modify the registry. Resolution is recorded in step 6 after step 3 of §0.1 lands.
- **Decision pair**: this document is paired in the same session with ADR-0049 (whether `config/trusted_writer_set.json` may accept the `trustedWriterJobs` field) -- both targets are members of the 18-path manifest, so their execution lanes have the same shape.
- Measurement baseline: `origin/main` **5b14bbfc** (2026-11-23). All facts below are read-only observations, and the PR authoring this document adds only one file (this document).

### 0.1 Unexecuted Execution Steps (Exhaustive)

This table is the tracker that lets issue #384 close without losing work. **None of the steps below has been executed.**

| # | Unexecuted execution step | Artifact changed | Lane |
|---|---|---|---|
| 1 | **Designate owner of App accepted manifest** -- ADM-01 records "no such owner is recorded anywhere in this repository" (`docs/evidence/trust_surface_ratification_366_2026-11-23.md:78-79`) | Out-of-tree App (`axiom-admission-verifier`, 5795152) accepted manifest -- not a repository file | **Authority decision** (prerequisite, neither break-glass nor rotation) |
| 2 | **Fix next accepted content** -- fix as a pair the exact bytes to which `certificate-mint.yml` will advance and the corresponding App accepted state | 1 new record under `docs/evidence/` | Normal PR (docs) |
| 3 | **DEBT#554 fail-closed fix** -- remove `2>/dev/null` at `:2272` and `:2286`, require `ledger-list` exit 0 before interpreting output (bounded retry, fail-closed on exhaustion), and distinguish unreadable from absent in the branch condition | `.github/workflows/certificate-mint.yml` (bytes) | **break-glass + epoch rotation** |
| 4 | **Record epoch rotation** -- advance the content fixed in step 2 into the new epoch and record the rotation | Advance App accepted manifest + rotation record under `docs/evidence/` | **epoch rotation** |
| 5 | **Reopen #293** -- rebase onto the new base, run a fresh preflight, and run a fresh landing-venue run (the current verdict is pinned to head `59640ca3`) | PR #293 | Normal lane after landing |
| 6 | **Update DEBT#554 status** | `docs/DEBT_REGISTRY.md:263` + `data/debt_registry.json` | Normal PR (registry is not a trust-surface member) |
| 7 | **Ordering link to ADR-0049 execution** -- if both ceremonies fall in the same epoch, combine steps 3-4 with ADR-0049 §0.1 step 1 in one rotation record | Artifacts of steps 3-4 + ADR-0049 §0.1 | **break-glass + epoch rotation** |

- **Anchors unchanged**: this rotation alters neither `trustedWriterWorkflow` (path) nor `trustedAdmissionWorkflowSha` (`admission-check.yml` blob) -- `certificate-mint.yml` is not the target of either anchor field and its path is unchanged. Thus the rotation is **fixing accepted content + advancing the App accepted manifest**, not rewriting TWS anchors. That distinction must be stated explicitly in the rotation record per ADR-0042's value/path split (`docs/adr/0042-trust-epoch-closure-split.md:109-111`).
- **Until step 3 completes**, `:263` stays Open and the fail-open path remains live. Because steps 1-2 are prerequisites for step 3, the first blocker for the ceremony is **owner designation**, not code.

## 1. Query

Can `.github/workflows/certificate-mint.yml` advance to its next content -- and if permitted, through which lane and in what order?

There is no code-edit degree of freedom in this query. PR #293's diff is **1 file** (`+40 -5`, `touched=1`, §2.5), and issue #384's split check concluded negatively ("the whole PR is the protected file"). Therefore no option exists to split a code fix out from the policy decision.

## 2. Facts

### 2.1 Measured Location of the Fail-Open Path

```
:2272  if ( cd "$B_CHECKOUT_DIR" && bin/ax cert ledger-list 2>/dev/null | grep -qx "$SUBJECT_ID" ); then
:2286  if ( cd "$B_CHECKOUT_DIR" && GITHUB_TOKEN="$GITHUB_TOKEN" bin/ax cert ledger-list 2>/dev/null | grep -qx "$SUBJECT_ID" \
```

- The pipeline exit status comes from `grep`, not `ledger-list`. `2>/dev/null` discards transport/auth/5xx failures, and `grep` exits 1 on empty stdin. Consequently the `else` branch (`:2279-2280`) invokes `bin/ax cert ledger-append` -- **a read failure is indistinguishable from absence**.
- `:2286` is the reconciliation leg after an append failure. It shares the exact same pipeline shape and defect.
- The registry entry cites `:2263` (`docs/DEBT_REGISTRY.md:263`). The measured line is now `:2272` -- the cited line drifted by +9, and `:2263` is currently `[ -x "$ax" ] || fail "B-built bin/ax missing at $ax"`. This document uses the **measured line numbers**.

### 2.2 Debt Tracking State

- DEBT#554 = **Open**, `docs/DEBT_REGISTRY.md:263` (Medium, `CI/Pipeline Health`).
- The same entry already specifies the remediation direction: "run ledger-list without discarding stderr, require exit 0 before interpreting output (bounded retry on transient failure, fail-closed on exhaustion), and distinguish unreadable from absent in the branch condition." This ADR invents no new fix direction -- §0.1 step 3 executes that specification.
- DEBT#553 (first-attempt uniqueness) was fixed in PR #297 (cited at `:263`). Thus the residual failure mode is **not a permanent duplicate, but "confusing duplicate append attempt followed by abort"**. Reducing the blast radius does not eliminate the defect -- silent misreading remains.

### 2.3 Protection Surface -- Verified Across All Three Lists

| List | `certificate-mint.yml` |
|---|---|
| `config/policy/trust_surface_manifest.json` (18 paths) | **`:12`** |
| `config/policy/merge_admission.json` `trustSurface` (39 entries) | **`:82`** (index 3) |
| `config/trusted_checker_closure.json` (`trustedCheckerTreeClosure`, 891 entries) | **0 hits** -- the workflow is not a closure member |

The first two lists govern the lane of this decision. Zero hits in the third affects only the rotation allowlist calculation (§Status boundary invariant).

### 2.4 Manifest Contract -- Why "Blob", Not "Pin"

- `:3` -- "Execution surface that must be byte-identical between a merge-group commit G and its base B_mg. **A PR that alters any listed path cannot receive the independent verifier's admission-check; such changes require the audited break-glass lane and an explicit epoch rotation.**"
- `:4` -- `"comparison": "blob-based: every path's Git blob SHA at G must equal its blob SHA at B_mg"`
- `:5` -- `"readFrom": "B_mg (merge_group.base_sha), never from G"`

The contract compares **per-path blobs rather than a manifest revision number**, and reads the baseline from `B_mg`, never from `G`.

### 2.5 Measured App Verdict -- Verbatim #293 Output

App verdict quoted by issue #384 (verbatim):

```
venue=pull_request
head=59640ca354b3f6862c40412a634c1819e5987ed9
base=1ce9ac26d70ede9fcb1ba70c6fcdf47e81e463a5
evaluated_commit=59640ca354b3f6862c40412a634c1819e5987ed9
run=44900423461 attempt=1 conclusion=success
trust_surface=FAIL — venue=pull_request manifest_ref=e22f4eb touched=1 manifest_touched=1
  diff_base=05139b3
  reasons=mismatch:.github/workflows/certificate-mint.yml
ledger=not-required(preflight venue)
```

- **`manifest_touched=1` is decisive**: the App actually **included** that path in its enforcement set. The rejection reason is a **blob mismatch** on that path, not pin staleness.
- `touched=1` -- the PR diff is that single file; there is no second file to split out.
- Ruleset facts: `bypass_actors: []`, `current_user_can_bypass: "never"` (issue #384) -- no bypass exists.

### 2.6 App Enforcement Set != In-Repo Array, and Owner UNKNOWN

- `docs/evidence/trust_surface_ratification_366_2026-11-23.md:40-43` records two `trustSurface` landings with `manifest_touched=0`: "The App's enforced manifest and the in-repo 39-entry `merge_admission.trustSurface` array are **not the same set**: a change to a `trustSurface` member that is absent from the App manifest passes `admission-check`."
- The same document (`:70-79`, ADM-01): "It needs a named owner for `axiom-admission-verifier`'s accepted manifest. No such owner is recorded anywhere in this repository, so the owner is **UNKNOWN** here."
- Two implications: (a) the in-repo contract (`:4`-`:5`) cannot be bypassed by any manifest reference; (b) the App-side lever has **no recorded owner** in this repository.

## 3. Options

### 3.1 Option 1 -- Advance the App's `manifest_ref` Pin (Rejected)

Measured facts eliminate this option.

1. **The comparison target is the blob, not a pin.** `:4` requires `blob(G) == blob(B_mg)` and `:5` reads the baseline from `B_mg`. Because PR #293's diff is that 1 path (`touched=1`), `blob(G) != blob(B_mg)` holds -- `B_mg` is by definition the base **before** the change. No `manifest_ref` value can make that equality true.
2. **The contract rules out an in-band path in principle.** `:3` -- "A PR that alters any listed path cannot receive the independent verifier's admission-check." A PR changing a listed path cannot receive `admission-check` under *any* pin state. Option 1 is a circular condition that only holds **after the file has already landed on `B_mg`**.
3. **Option 1's only lever lives outside this repository.** `manifest_ref` is an out-of-tree value appearing only in the App verdict, absent from this repository's contract files. The owner of that accepted manifest is UNKNOWN (ADM-01, `:78-79`), so not even an executor is designated for that operation.
4. **`manifest_touched=1` refutes the "App does not recognize the file" reading.** The rejection is a byte mismatch, not lack of recognition.

Issue #384 framed option 1 conditionally: "If the `e22f4eb` pin is the only obstacle, this is the whole fix." `manifest_touched=1` in §2.5 and `:4`-`:5` establish empirically that the condition is **false**.

### 3.2 Option 2 -- Trust Ceremony + Reopen #293 (Adopted)

- **Without a ceremony, the approved target is undefined.** "Next content" is not prose -- it is a **pair of exact bytes and the corresponding App accepted state**, and fixing that pair is the ceremony. Opening break-glass without fixing it fails to record what was approved -- the exact shape prohibited by §0.9 (landing that merely looks like assurance).
- **The fix direction is already registered.** The three requirements at `:263` (§2.2) are execution step 3. This ADR invents no new fix content; it decides only the procedure that puts the fix into a **landable state**.
- **The lane is already documented** -- `docs/evidence/breakglass_trust_surface_landing_2026-11-19.md:10` and `:38-41`: record the MUST-T2a delegation in a PR comment **before** merge, snapshot both rulesets (`27097366` `main`, `27525972` `main-admission`), apply bypass to **both rulesets simultaneously** (one alone returns merge API 405), perform REST native merge, restore immediately, and re-query to verify `bypass_actors=[]`. This ADR references that shape as-is without redefining it.
- **Honest limitation**: the ceremony does not fix the fail-open path; step 3 does. The ceremony only creates the state in which step 3 can land, and §0.1 preserves that distinction.

### 3.3 Option 3 -- Wontfix (Not Adopted)

- `:263` records a read-failure-as-absent path in the **sole privileged publisher**. While that path stays open, a ledger read error is misread as "absent" and enters `ledger-append` (`:2279-2280`). After DEBT#553, the residual failure mode is "confusing duplicate append attempt followed by abort", which still begins with a **silent misread**.
- Choosing wontfix would require **re-filing** the item as accepted risk rather than leaving it looking like pending work (issue #384, "What closing PR #293 does not decide"). That re-filing is a separate decision that this ADR does not make.
- Moreover, option 3 makes the fail-open path **permanent** while the file remains frozen. That trade must be explicit (issue #384), and this ADR does not approve it. Therefore option 3 is not chosen silently.

## 4. Decision

**Decision (one sentence)**: `.github/workflows/certificate-mint.yml` **may** advance to its next content -- provided that advancement occurs solely via (i) a trust ceremony fixing the next accepted content and (ii) audited break-glass + epoch rotation, and never via pin advancement (option 1).

### Consequences

1. **DEBT#554 remains Open.** This ADR does not fix the fail-open path. Status update belongs to §0.1 step 6.
2. **#293 remains unreachable until the ceremony completes.** Even after the ceremony, a rebase is required -- the current verdict is pinned to head `59640ca3`, and a new base requires a fresh preflight and a fresh landing-venue run (issue #384 "Reopen condition").
3. **Rejection of option 1 is reusable precedent.** Any request claiming "advancing the pin will pass" for a PR modifying a trust-surface-manifest path is rejected on the basis of this ADR. Re-opening that question requires a new decision.
4. **One unresolved prerequisite remains.** The owner of the App accepted manifest is UNKNOWN (ADM-01, `:78-79`). The ceremony cannot complete without that owner -- §0.1 step 1. Code cannot resolve this prerequisite.
5. **Anchors do not move.** This rotation alters neither `trustedWriterWorkflow` (path unchanged) nor `trustedAdmissionWorkflowSha` (`admission-check.yml` blob). `certificate-mint.yml` is not the target of either anchor field. The rotation record must state this distinction explicitly (ADR-0042 value/path split, `docs/adr/0042-trust-epoch-closure-split.md:109-111`).
6. **Scope of effect is strictly the lane.** This ADR settles only "advancement is permitted" and "the permitted lane is break-glass + epoch rotation". It does not settle fix contents, timing, or executor.

## 5. Decision Authority and Procedure

- **Decision authority**: sole repository architect. This document records that approval and does not substitute for a decision.
- **Basis**: AGENTS.md §0.10 decision binding (changes bound to committed decisions/policies; no bypass without waiver); §2.3 (GitHub is merge-admission authority -- 0 required checks is UNKNOWN/NOT READY, never promoted to SUCCESS); `config/policy/trust_surface_manifest.json:3` (requires break-glass + epoch rotation).
- **Procedure**: land this ADR -> §0.1 steps 1-2 (owner designation, content fixation) -> steps 3-4 (break-glass + epoch rotation) -> step 5 (rebase and re-evaluation) -> step 6 (registry update). **None of those steps is included in landing this ADR.**
- **This document is not closure**: DEBT#554 stays Open, the ceremony stays unexecuted, and issue #384 stays Open. Landing this document canonicalizes that pending state.

## References

- Issue **#384** -- "policy(trust-surface): decide whether certificate-mint.yml may advance (DEBT#554 fail-open path)" (Open)
- DEBT#554 -- `docs/DEBT_REGISTRY.md:263` (Medium, `CI/Pipeline Health`, **Open**)
- `.github/workflows/certificate-mint.yml` -- `:2272`, `:2279-2280`, `:2286`
- `config/policy/trust_surface_manifest.json` -- `:3`, `:4`, `:5`, `:12` (18 paths)
- `config/policy/merge_admission.json` -- `:82` (trustSurface index 3, 39 entries)
- `config/trusted_checker_closure.json` -- `trustedCheckerTreeClosure` 891 entries (`docs/adr` 0 hits)
- `src/cli/merge_cli.nim` -- `:228` (`RotationAdrGlob`), `:1036` (allowlist check)
- ADR-0042 -- `docs/adr/0042-trust-epoch-closure-split.md:109-111` (value/path split)
- ADR-0049 -- `docs/adr/0049-trusted-writer-jobs-field-decision.md` (decision pair)
- Break-glass lane precedent -- `docs/evidence/breakglass_trust_surface_landing_2026-11-19.md` `:10`, `:21`, `:38-41`
- ADM-01 / App enforcement set -- `docs/evidence/trust_surface_ratification_366_2026-11-23.md` `:40-43`, `:70-79`
