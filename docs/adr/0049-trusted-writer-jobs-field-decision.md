# ADR-0049: Per-Job Authority Dimension of `TrustedWriterSet` -- Decision to Admit the `trustedWriterJobs` Field (DEBT#557)

## Status

**Accepted -- Option 2 (admit field with empty set) adopted (2026-11-23)**

- **Date and authority**: 2026-11-23 -- records the blanket approval granted in this session by the sole architect of the repository (`wintrover`, sole member of `@Archright/architect`) for the decision-recording work. This approval is a session-level blanket authorization, not a signed or sealed document; this record does not claim a signing artifact, an independent second reviewer, or a committee (AGENTS.md §0.9 honest-executor; same recording precedent: `docs/evidence/breakglass_trust_surface_landing_2026-11-19.md:21`).
- **Decision and effect**:
  1. **Option 2 adopted** -- `config/trusted_writer_set.json` **may carry** the `trustedWriterJobs` field. The value accepted by this decision is the **empty array**, so no job receives job-level writer authority (§3.2).
  2. **Option 1 (field + named set) is not adopted in this ADR** -- this is a **deferral**, not a rejection (§3.1).
  3. **Option 3 (wontfix) is not adopted** -- see §3.3.
  4. **DEBT#557 remains Open** -- this document does not modify `docs/DEBT_REGISTRY.md:139` or `data/debt_registry.json`.
- **Boundary invariant**: This document **does not add** the field. Today the file has only two fields, `trustedWriterWorkflow` (`:40`) and `trustedAdmissionWorkflowSha` (`:41`), and `trustedWriterJobs` is absent (measured: §2.1). It remains absent after this ADR lands -- adding it is §0.1 step 1. R3 remains dormant (`tools/ci/trusted_writer_set_gate.nim:334`). This PR adds a single file under `docs/adr/**`; that path is absent from the 39 entries of `trustSurface`, the 18 paths of the manifest, and the 891 entries of the closure, and is permitted by the rotation allowlist in `src/cli/merge_cli.nim:1036` (`RotationAdrGlob`, `:228`), so it uses the normal lane.

## 0. Tracking

- **Issue #385** -- canonical tracking issue for this decision (Open). This document does not close the issue.
- **DEBT#557** -- `docs/DEBT_REGISTRY.md:139` (High, `Theater/Trusted-Writer-Set`, **Open**). Canonical tracking entry for the decision-pending state; this document does not modify the registry.
- **Decision pair**: this document is paired in the same session with ADR-0048 (whether `certificate-mint.yml` may advance to its next content) -- both targets are members of the 18-path manifest, so their execution lanes have the same shape.
- Measurement baseline: `origin/main` **5b14bbfc** (2026-11-23). The observed set in §2.6 is **measured output** obtained by running `tools/ci/trusted_writer_set_gate.nim` on that same tree. The PR authoring this document adds only one file (this document).

### 0.1 Unexecuted Execution Steps (Exhaustive)

This table is the tracker that lets issue #385 close without losing work. **None of the steps below has been executed.**

| # | Unexecuted execution step | Artifact changed | Lane |
|---|---|---|---|
| 1 | **Admit `trustedWriterJobs: []` field** -- empty array; `pathSetDigest` (`:48`) unchanged | `config/trusted_writer_set.json` (add field after `:40-41`) | **break-glass + epoch rotation** |
| 2 | **Extend App accepted schema** -- resolve `tws_new_field` rejection | Out-of-tree App (`axiom-admission-verifier`, 5795152) accepted schema -- not a repository file | **App owner** (ADM-01: owner UNKNOWN -- designation is a prerequisite) |
| 3 | **Append third fact class to ADR-0042 fact-class table** -- `trustedWriterJobs` is neither an anchor, `pathSetDigest`, nor value closure; quote before/after, do not rewrite existing body | `docs/adr/0042-trust-epoch-closure-split.md` | Normal PR (`docs/adr` allowlist, `merge_cli.nim:1036`) |
| 4 | **R3 activation decision -- actual grant of per-job authority.** Because the named set must equal the observed set (`⊆ ∧ ⊇`), the 3 items observed at grant time are pinned as-is: `.github/workflows/admission-gate-v2.yml#mint-prepare`, `#mint-publish`, `.github/workflows/certificate-mint.yml#publish` | `config/trusted_writer_set.json` | **Separate break-glass + separate authority decision** |
| 5 | **Reopen #301** -- rebase (debt counters conflict), fresh preflight, fresh landing-venue run | PR #301 | Normal lane after schema barrier clears |
| 6 | **Update DEBT#557 status** | `docs/DEBT_REGISTRY.md:139` + `data/debt_registry.json` | Normal PR |
| 7 | (Optional) Extend `.sh` observation scope to job-level -- **original defect** of DEBT#557 | `tools/ci/verify_trusted_writer_set.sh` (`:108-114`) | Normal PR (`repository_surface` CONTROLLED, 0 closure hits) |

- **Step 1 and step 4 are separate decisions.** Step 1 creates the expression slot (0 authority grants); step 4 grants authority. The empty array in step 1 does not activate R3 (`:334`), so step 1 alone makes no job a writer.
- **Step 2 completes outside this repository.** Landing step 1 alone passes the in-tree gate while the App still rejects with `tws_new_field` -- steps 1 and 2 are a pair.
- **Step 7 is not closed by this decision.** Option 2 does not fix the `.sh` top-level-only observation (§2.7). DEBT#557's original defect remains live until step 7 lands.

## 1. Query

Can `TrustedWriterSet` (`config/trusted_writer_set.json`) carry a **per-job authority dimension** -- and if it can, what value does this decision accept for that dimension?

This query is not a matter of schema taste. That file declares "which CI jobs may act with writer authority" (issue #385), so adding a per-job dimension means **admitting a job into the trust boundary**. An implementer cannot answer that decision.

## 2. Facts

### 2.1 Field Absence -- Measured

```
:40  "trustedWriterWorkflow": ".github/workflows/certificate-mint.yml",
:41  "trustedAdmissionWorkflowSha": "433be3c34c51cfc3fc6f8741009135cfa5906a03",
...
:48  "pathSetDigest": "axiom.trusted-checker-closure.path-set.v1:757310d4..."
```

- `trustedWriterJobs` is **absent**. The last key in the file is `pathSetDigest` (`:48`).
- Thus the current authority dimension is **workflow-level only**. There is no vocabulary to express "this job may write" at job granularity.

### 2.2 R3 Is Already Coded -- and Self-Declares That It Is Break-Glass

`tools/ci/trusted_writer_set_gate.nim:26-28`:

```
## R3 declared job set -- when `config/trusted_writer_set.json` carries an
##    optional `trustedWriterJobs` array, the observed job-level writer set
##    must equal it exactly (⊆ ∧ ⊇). The field cannot be introduced by a PR:
##    the verifier rejects unknown TWS fields (`tws_new_field`) and the file is
##    blob-pinned in the trust-surface manifest, so R3 activating is itself an
##    audited break-glass event.
```

- The loader already exists -- `:370-371`: `if node.hasKey("trustedWriterJobs")`.
- So the in-tree gate is **tolerant** of the field; the rejecting party is the out-of-tree App (§2.5).
- That comment defines the nature of the decision itself: **activating R3 = audited break-glass event.** This ADR adopts that classification directly.

### 2.3 Activation Condition Is Element Count, Not Field Presence (`:334`)

```nim
if declared.writerJobs.len > 0:
```

- **An empty array does not activate R3.** That is the mechanical meaning of option 2 -- a code predicate, not prose rhetoric. `trustedWriterJobs: []` loads with 0 elements (`:370-373`) and does not take the R3 branch at judgment time.
- Result: **an empty array and an absent field are indistinguishable to the gate verdict.** Hence the effect of option 2 lies on the **App accepted schema axis**, not the in-tree judgment axis. Leaving this unstated would turn option 2 into theater (§0.9) -- this document records the distinction in §3.2 and §4.

### 2.4 Remaining Enforcement While R3 Is Inactive -- and Its Honest Label

- When `--base` is supplied, R2 delta remains active: a job-level writer present in head and absent in base emits `tws_job_level_write_added:` (`:341-344`).
- Without `--base` and without R3, only a **note** is emitted -- `:345-348`: `"job-level writers observed without a declared job set (absolute closure requires trustedWriterJobs; delta mode requires --base)"`.
- This state **honestly records** "no absolute closure" as a note and never claims closure. Option 2 preserves this behavior.

### 2.5 The App Is the Real Rejector -- Field Introduction Was Attempted

- #301 verdict (quoted verbatim in issue #385): `trust_surface=FAIL — ... reasons=tws_new_field:trustedWriterJobs`.
- In-repo measurement record: `data/ci_optimization/ancestry_three_state_gate_2026-11-22/measurement.json:35` -- `{ "pr": 301, "head": "356f2872...", "kind": "trust_surface=FAIL", "reasons": "tws_new_field:trustedWriterJobs" }`.
- Thus introducing the field is not hypothetical -- it was **actually attempted and rejected at the schema boundary**.

### 2.6 Three Observed Job Writers -- Measured (`origin/main` `5b14bbfc`)

Output obtained by building and running `tools/ci/trusted_writer_set_gate.nim` on that tree:

```
observed job-level contents:write holders: 3
  .github/workflows/admission-gate-v2.yml#mint-prepare
  .github/workflows/admission-gate-v2.yml#mint-publish
  .github/workflows/certificate-mint.yml#publish
```

- Identifier format is `jobWriterId` = `wf.path & "#" & job.name` (`:286-287`).
- Source sites: `.github/workflows/admission-gate-v2.yml:535` (`mint-prepare`), `:592` (`mint-publish`), `.github/workflows/certificate-mint.yml:1282` (`publish`).
- Inheritance measured: `effectiveContents` (`:275-281`) specifies that a job block **overrides** the workflow block. In `certificate-mint.yml`, top-level is write (`:175-178`), while the `prepare` job overrides with read in its own block (`:206-209`), yielding only 1 job writer -- confirming inheritance does not inflate the writer count.
- **Record drift**: DEBT#557 recorded on 2026-11-17 six jobs in `admission-gate-v2.yml`, two in `release-ship.yml`, and one in `dependabot-auto-merge.yml` (`:139`). Today's measurement is 3. The tree changed in the meantime -- the named set is **bound to measurement time**, and copying historical records verbatim would fail on today's tree with `tws_declared_job_not_observed:`.

### 2.7 Original Defect of DEBT#557 Is Top-Level-Only Observation

- The `.sh` verifier collects only column-0 `permissions:` -- the awk script in `tools/ci/verify_trusted_writer_set.sh:108-114` starts at `^permissions:` (column 0) and ends at the next column-0 key. Its own parser comment (`:108-110`) states "only the top-level permissions block counts".
- Thus the gate prints `PASS` while reporting the observed set as `{certificate-mint.yml}` -- job-level grants are **unobserved**. `:139` records this as "a masking claim".
- Option 2 does not fix this defect (§3.3, §0.1 step 7).

### 2.8 Protection Surface

| List | `config/trusted_writer_set.json` |
|---|---|
| `config/policy/trust_surface_manifest.json` (18 paths) | **`:22`** |
| `config/policy/merge_admission.json` `trustSurface` (39 entries) | **`:87`** (index 8) |
| `config/trusted_checker_closure.json` (891 entries) | 0 hits |

### 2.9 ADR-0042 Fact Classes -- The Two-Class Split Becomes Incomplete

`docs/adr/0042-trust-epoch-closure-split.md:28-33` divides facts in this document into two classes: **anchors** (`trustedWriterWorkflow`, `trustedAdmissionWorkflowSha`) + `pathSetDigest` as "epoch rotation only", and **mutable derived closure** as value re-anchor.

`trustedWriterJobs` is **neither** -- it is neither an anchor, nor a path-set summarized by `pathSetDigest`, nor a value closure. It is a third class. Therefore executing this change makes ADR-0042's table incomplete, which may be repaired only via an append-only amendment (§0.1 step 3; format precedent: ADR-0025 Amendment A2 `docs/adr/0025-gateway-landing-authority.md:417`, Amendment E `:769` -- quote before/after, do not rewrite existing body).

## 3. Options

### 3.1 Option 1 -- Field + Named Set (Not Adopted in This ADR / Deferred)

- **Feasible in mechanics**: R3 is already coded (`:26-28`) and extending the App is a policy act.
- **Naming them now grants new authority.** Because the named set must equal the observed set **exactly** (`⊆ ∧ ⊇`, `:26-27`), and today's observation has 3 jobs (§2.6), naming them now is not retroactively endorsing an existing grant -- it is **declaring per-job authority for the first time**. "Which jobs may hold writer authority at job granularity" is the explicit question issue #385 escalated to the architect, and this ADR does not lock in that answer now.
- **No documented justification exists for that decision.** Nothing records why each job must hold writer authority; `:139` records instead that "observed grants are undeclared".
- **Copying historical records fails.** Due to the drift in §2.6, copying the 9 items from Nov 17 triggers `tws_declared_job_not_observed:` on today's tree.
- Therefore this option is the **larger decision**, lacks supporting rationale today, and is deferred to §0.1 step 4. It is deferred, not rejected, and remains available.

### 3.2 Option 2 -- Field + Empty Set (Adopted)

- **Zero authority grant is enforced by code predicate.** An empty array does not activate R3 (`:334` -- `len > 0`). No job acquires new authority. The core property of this option is that "mechanism without grant" is a predicate, not rhetoric.
- **It buys the expression slot.** Once the field exists in the App accepted schema, `tws_new_field` rejections clear and a subsequent named-set PR (§0.1 step 4) is no longer blocked by schema mismatch. Option 2 **lowers future decision cost while keeping granted authority at zero**.
- **Residual enforcement stays intact.** R2 delta (`:341-344`) continues to reject new job-level writers relative to base, and absence of absolute closure is recorded honestly as a note (`:345-348`). An empty set never claims "closed" -- which is why it does not conflict with §0.9's theater prohibition.
- **Honest limitations (two)**:
  1. An empty array and an absent field are identical to the gate verdict (`:334`). What option 2 buys is an **expression slot**, not enforcement power.
  2. Therefore **DEBT#557 is not closed by option 2** -- the `.sh` top-level-only observation defect (§2.7) stays untouched. Citing option 2 as "job-level closure is now enforced" would be theater, and this document forbids that citation.
- **Blob-change cost**: admitting the field alters the bytes of this file, which is an App-protected path (`:22`) -> break-glass + epoch rotation (`trust_surface_manifest.json:3`). `pathSetDigest` (`:48`) is keyed on the path set and does not change -- the rotation record must state that distinction explicitly (ADR-0042 value/path split, `:109-111`).

### 3.3 Option 3 -- Wontfix (Not Adopted)

- The original defect at `:139` is that `.sh` observes only the top-level block. **Option 2 does not fix that either** -- `.sh` still inspects only column-0 `permissions:` (`:108-114`).
- **Why wontfix is still not chosen**: option 3 declares "job-level writer authority is out of scope" and forbids `trustedWriterJobs` from ever appearing in the tree (issue #385 option 3). Yet the 3 observed grants are **real existing grants** -- `:345-348` says not "none exist", but "**observed without a declared job set**". Erasing real grants from the vocabulary via wontfix contradicts measured fact.
- Choosing wontfix would require re-filing DEBT#557 as "mechanism was rejected" (issue #385). That re-filing is a separate decision that this ADR does not make.

## 4. Decision

**Decision (one sentence)**: `TrustedWriterSet` **may carry** the `trustedWriterJobs` field -- provided the value accepted by this decision is the **empty array**, no job acquires per-job writer authority, and R3 remains inactive (`:334`).

### Consequences

1. **DEBT#557 remains Open.** Option 2 does not fix the `.sh` top-level-only observation defect (§2.7). Status update belongs to §0.1 step 6.
2. **R3 remains dormant.** Because activation requires `len > 0`, an empty array is harmless and **has no enforcement effect**. That non-effect is the content of this decision, not a flaw -- zero authority grants.
3. **The effect of option 2 lies in the App accepted schema.** In-tree judgment is unchanged. Thus admitting the field and extending the App (§0.1 step 2) form a pair; neither alone clears #301-class rejections.
4. **Admitting the field is a blob change** -> break-glass + epoch rotation. `pathSetDigest` (`:48`) does not change -- the rotation record must state that distinction explicitly (ADR-0042 value/path split, `:109-111`).
5. **ADR-0042's two-class table becomes incomplete.** `trustedWriterJobs` is neither an anchor nor a value closure -- an append-only amendment is required upon execution (§0.1 step 3; format precedent: ADR-0025 Amendment A2 `:417`, Amendment E `:769`).
6. **Actual grant of per-job authority remains open.** Option 1 is deferred (§3.1); without that decision no job receives new authority -- this ADR creates **zero** authority.
7. **The App accepted schema is out-of-tree and owner UNKNOWN (ADM-01)** -- half of admitting the field completes outside this repository (`docs/evidence/trust_surface_ratification_366_2026-11-23.md:78-79`).

## 5. Decision Authority and Procedure

- **Decision authority**: sole repository architect. This document records that approval and does not substitute for a decision.
- **Basis**: AGENTS.md §0.10 decision binding; §0.9 theater prohibition (basis forbidding citing an empty set as "closed"); `tools/ci/trusted_writer_set_gate.nim:26-30` (R3 activation = audited break-glass event -- the gate itself defines the nature of the decision); `config/policy/trust_surface_manifest.json:3` (requires break-glass + epoch rotation).
- **Procedure**: land this ADR -> §0.1 steps 1-2 (admit field + extend App) -> step 3 (ADR-0042 amendment) -> step 5 (rebase #301) -> step 6 (update registry). Step 4 (R3 activation) is a **separate decision** outside this ADR's procedure. **None of these steps is included in landing this ADR.**
- **This document is not closure**: DEBT#557 stays Open, the field stays absent, R3 stays dormant, and issue #385 stays Open. Landing this document canonicalizes that pending state.

## References

- Issue **#385** -- "policy(authority): decide whether trustedWriterJobs may join TrustedWriterSet (DEBT#557)" (Open)
- DEBT#557 -- `docs/DEBT_REGISTRY.md:139` (High, `Theater/Trusted-Writer-Set`, **Open**)
- `config/trusted_writer_set.json` -- `:40`, `:41`, `:48` (`trustedWriterJobs` absent)
- `tools/ci/trusted_writer_set_gate.nim` -- `:26-28` (R3 contract / break-glass self-declaration), `:275-281` (`effectiveContents`), `:286-287` (`jobWriterId`), `:334` (R3 activation condition), `:341-344` (R2 delta), `:345-348` (note on absence of absolute closure), `:370-371` (field loader)
- `tools/ci/verify_trusted_writer_set.sh` -- `:108-114` (top-level-only observation)
- `.github/workflows/admission-gate-v2.yml` -- `:535`, `:592`
- `.github/workflows/certificate-mint.yml` -- `:175-178` (top-level write), `:206-209` (`prepare` read override), `:1282` (`publish` job write)
- `config/policy/trust_surface_manifest.json` -- `:3`, `:22`
- `config/policy/merge_admission.json` -- `:87` (trustSurface index 8, 39 entries)
- `data/ci_optimization/ancestry_three_state_gate_2026-11-22/measurement.json:35` (#301 `tws_new_field:trustedWriterJobs` measured)
- ADR-0042 -- `docs/adr/0042-trust-epoch-closure-split.md:28-33`, `:109-111`
- ADR-0025 -- `docs/adr/0025-gateway-landing-authority.md:417` (Amendment A2), `:769` (Amendment E) -- append-only amendment format precedent
- ADR-0048 -- `docs/adr/0048-certificate-mint-next-content-decision.md` (decision pair)
- ADM-01 / App enforcement set -- `docs/evidence/trust_surface_ratification_366_2026-11-23.md` `:40-43`, `:70-79`
