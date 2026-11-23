# ADR-0046: Next admission epoch for the S1 ancestry contract -- option 1, a rotation from current main (#383)

## Status

**Accepted -- option 1 (2026-11-23).** This ADR records the decision. It does not
execute it.

**Authority.** `wintrover`, the repository's sole Architect (`@Archright/architect`,
sole member), 2026-11-23. Approval basis, verbatim and factual: the owner's
session-level blanket authorization of 2026-11-23 to proceed without further
per-step confirmation ("approve everything") -- the same basis and wording
recorded in the Amendment A10 approval slot at
`docs/adr/0025-gateway-landing-authority.md:1124` -- relayed to this workstream as
the tasking for ADR-0046 and ADR-0047. No signature is invented, no second
reviewer and no committee is claimed, and no independent review is asserted. The
`App Owner` role for the out-of-tree `axiom-admission-verifier` is not established
by this repository and is not claimed here.

**What this decision does NOT authorise.**

1. It does not bump the epoch or move any pin. `ciEpochId` stays `N+11` and the
   triple stays `433be3c3...` until the rotation PR of section 0 lands.
2. It does not change any workflow, config pin, policy JSON, gate, test, or
   ruleset. This change adds one ADR file and nothing else.
3. It does not authorise a rebase of #333, a reuse of #333's App verdict, or the
   closing or reopening of any PR or issue.
4. It does not assert what the App will accept. The App is out-of-tree; its
   accepted next-epoch state cannot be read from this repository (issue #383;
   `docs/agents/axiom_admission_verifier_ops.md` section 1 records that the App source is
   not published in any public org repository).
5. It does not widen the rotation allowlist, the trust surface, or the
   required-check set. section 0 records that no allowlist amendment is needed for this
   rotation -- not that one is granted.

## 0. Tracking

Every execution step that remains unexecuted. This table is the tracker that lets
issue #383 close on the decision without losing the work. "ROTATION" is the
candidate-delta path of ADR-0025 section 7 (`docs/adr/0025-gateway-landing-authority.md:210`);
for these artifacts it resolves to the **audited break-glass lane** because the App
cannot admit a trust-surface change (`config/policy/trust_surface_manifest.json:3`).
No row is authorised by this ADR.

| # | Unexecuted step | Artifact it must change | Lane |
|---|---|---|---|
| 1 | Recover #333's payload as a diff. `refs/pull/333/head` = `e35af1fb6531a733b19c63ba9b14e286480e541e` is still advertised by origin (measured 2026-11-23), so the payload is addressable without the closed PR body. Do not merge, rebase, or fast-forward that branch. | a new branch off `origin/main` | none (local) |
| 2 | Land the S1 Phase A content itself. | `.github/workflows/admission-check.yml` (+114/-93 in #333's own diff) and `tests/ci/test_sl02_consumer_binding.nim` (+259) | ROTATION -> break-glass |
| 3 | Epoch transaction, one commit: `ciEpochId` `N+11` -> `N+12`; `productionExecutionPin` = the new `blob(admission-check.yml)`; `trustedAdmissionWorkflowSha` = the same blob. AGENTS.md section 2.5 coherent generation, ADR-0025 section 7. | `config/policy/epoch_manifest.json:2` and `:28`; `config/trusted_writer_set.json:41`; the workflow | ROTATION -> break-glass |
| 4 | Closure re-anchor, derived not hand-edited. | `config/trusted_checker_closure.json` values; `config/trusted_writer_set.json` `pathSetDigest` only if the closure PATH SET changes. Writer: `bin/derive_checker_closure` (ADR-0042). | ROTATION -> break-glass (same commit) |
| 5 | Allowlist check: **no amendment is required** for this rotation. All four #333 paths are already allowed -- `.github/workflows/admission-check.yml` (`src/cli/merge_cli.nim:301`), `tests/ci/test_sl02_consumer_binding.nim` (`:312`), `config/policy/epoch_manifest.json` (`:318`), and `config/trusted_writer_set.json` as `RotationPinBPath` (`src/core/policy/rotation_closure_facts.nim:32`). | nothing | none |
| 6 | Break-glass landing record, written on the same PR: the App's refusal verbatim, the MUST-T2a per-PR delegation comment id **recorded before the merge** (`docs/agents/rules_workflow.md:129`), both rulesets' before/after snapshots, and the revert. Precedents: `docs/evidence/breakglass_trust_surface_landing_2026-11-19.md`, `..._2026-11-20.md`. | new `docs/evidence/breakglass_trust_surface_landing_<YYYY-MM-DD>.md` | commit on the same PR; the merge is MUST-T2a |
| 7 | Post-landing verification of the triple at the merge commit: `git rev-parse main:.github/workflows/admission-check.yml` == `productionExecutionPin` == `trustedAdmissionWorkflowSha`; canonical main push CI green (Push on main, trusted-writer-set, axiom-operational-slice, fresh-prove-observation). | nothing | observation |
| 8 | Fresh acceptance evidence: a new `merge_group` run on the new epoch whose `admission-check` is `success` from App `5795152`. #333's verdict at `e35af1fb` must not be reused -- it certifies a different base (issue #383 reopen condition). | the run and its journal | observation |
| 9 | Discharge the debt: S1 Phase A is open until step 8 exists, regardless of step 3 landing. | issue #383's terms; any `data/debt_registry.json` entry opened for it | none |

## 1. Query

Which option becomes the next admission epoch for the S1 ancestry contract, so
that `.github/workflows/admission-check.yml`, `config/policy/epoch_manifest.json`
and `config/trusted_writer_set.json` can move to their next state together?

The three options are #383's own: (1) epoch ceremony plus reopening #333, (2)
advance the App's `manifest_ref` pin, (3) wontfix.

## 2. Facts

Measured 2026-11-23 at `origin/main` = `5b14bbfce4e559b174a6c18a2e7af62fa76719ea`.
Blob oids are `git rev-parse <rev>:<path>`; `git hash-object` takes file paths and
does not resolve `rev:path` (it fails with "could not open ... for reading"), so
the reproducible command is recorded rather than the tool name.

### 2.1 The triple is coherent today

| Artifact | Line | Value |
|---|---|---|
| `config/policy/epoch_manifest.json` | `:2` | `"ciEpochId": "N+11"` |
| `config/policy/epoch_manifest.json` | `:28` | `"productionExecutionPin": "433be3c34c51cfc3fc6f8741009135cfa5906a03"` |
| `config/trusted_writer_set.json` | `:41` | `"trustedAdmissionWorkflowSha": "433be3c34c51cfc3fc6f8741009135cfa5906a03"` |
| `git rev-parse origin/main:.github/workflows/admission-check.yml` | -- | `433be3c34c51cfc3fc6f8741009135cfa5906a03` |

Three independent records and one blob agree. The epoch is not in a torn state:
there is nothing to repair, only a decision to make about the next one.

### 2.2 N+11 landed through the rotation lane, after the App became the producer

- `config/policy/merge_admission.json:4`, v1.24.0 (2026-11-17): "The required
  'admission-check' context is now produced by the independent GitHub App
  axiom-admission-verifier (id 5795152), recorded in requiredCheckSources.byContext".
- `7f3424cc` (2026-11-20, `chore(ci): epoch N+11 -- rotate pin for cert_export
  closure member`) advanced the triple in one commit and exactly three files:
  `.github/workflows/admission-check.yml` +5/-0,
  `config/policy/epoch_manifest.json` +3/-3, `config/trusted_writer_set.json`
  +1/-1 (git numstat; 9 insertions and 4 deletions in total).
- The same commit message states the consequence it accepted: "The trust-surface
  change means the independent verifier cannot admit this PR through the normal
  lane: landing uses the documented audited break-glass procedure
  (docs/evidence/breakglass_trust_surface_landing_2026-11-19.md)."

The rotation lane accepted the triple three days after the App became the
producer. That is the load-bearing precedent for option 1, and it is stronger than
an inference from the policy text: it is a landed commit.

### 2.3 Why no pull_request-venue verdict on a content change can exist

`config/policy/trust_surface_manifest.json:3` states the contract:

> "Execution surface that must be byte-identical between a merge-group commit G
> and its base B_mg. A PR that alters any listed path cannot receive the
> independent verifier's admission-check; such changes require the audited
> break-glass lane and an explicit epoch rotation."

The three artifacts are all on that list:
`config/policy/trust_surface_manifest.json:9` (`.github/workflows/admission-check.yml`),
`:18` (`config/policy/epoch_manifest.json`), `:22` (`config/trusted_writer_set.json`).
`docs/agents/axiom_admission_verifier_ops.md` section 3.2 records the same comparison over
all 18 manifest paths (`blob(G) == blob(B_mg)` per path).

This is a contract clause, not a stale pin. #383's measured blocker is the clause
executing exactly as written:

```text
venue=pull_request
head=e35af1fb6531a733b19c63ba9b14e286480e541e
base=1c935b3f84a7c1f2be83f1091d1078be42865305
evaluated_commit=e35af1fb6531a733b19c63ba9b14e286480e541e
run=44987541306 attempt=1 conclusion=success
trust_surface=FAIL -- venue=pull_request manifest_ref=1c935b3 touched=4 manifest_touched=3
  diff_base=1c935b3
  reasons=mismatch:.github/workflows/admission-check.yml,
          mismatch:config/policy/epoch_manifest.json,
          tws_protected_field:trustedAdmissionWorkflowSha
ledger=not-required(preflight venue)
```

`touched=4 manifest_touched=3` is the observation that closes the "just put them
in one commit" theory: #333 already did, and it was still refused. Necessary is
not sufficient.

### 2.4 #333 is closed and its payload is still addressable

- #333 (head `e35af1fb`) was closed 2026-11-23 without merge.
- origin still advertises `refs/pull/333/head` = `e35af1fb6531a733b19c63ba9b14e286480e541e`
  (measured 2026-11-23), so "reopen" does not depend on recovering the branch.
- Its shape is the same three-file trust transaction plus the contract test:
  `.github/workflows/admission-check.yml` +114/-93,
  `config/policy/epoch_manifest.json` 1 line,
  `config/trusted_writer_set.json` 1 line (`trustedAdmissionWorkflowSha`),
  `tests/ci/test_sl02_consumer_binding.nim` +259.

The defect the payload fixes is still on main: the admission workflow carries
ancestry logic in more than one place -- the candidate-preparation fetch and its
`CANDIDATE_MERGE_BASE_UNRESOLVED` fail-closed path
(`.github/workflows/admission-check.yml:2797`, `:2810`) and the judgment path
whose own rule is stated at `:3594`-`:3598` ("the merge-tree rc is the ancestry
gate. No separate ancestry probe"). S1 Phase A's requirement is one deterministic
ancestry contract for both consumers (issue #383 origin line, #333 title).

### 2.5 Option 2 is neither executable here nor sufficient by construction

- The App is out-of-tree. `docs/agents/axiom_admission_verifier_ops.md` section 1 lists
  its source location as unavailable -- no public org repository carries it; issue #383
  records the `App Owner` role as `UNKNOWN`. No act in this repository moves
  `manifest_ref`.
- Even if the pin moved, `config/policy/trust_surface_manifest.json:4` defines the
  comparison as "blob-based: every path's Git blob SHA at G must equal its blob
  SHA at B_mg" and `:5` fixes the read side: "B_mg (merge_group.base_sha), never
  from G". Moving the comparison base does not make two different blobs equal. A
  content change to a listed path fails this predicate at any pin.

Option 2 would leave the byte-identity contract intact -- which is exactly why it
cannot admit a content change.

## 3. Options

### Option 1 -- Epoch ceremony plus reopening #333 (SELECTED)

Perform the next-epoch ceremony, then land the S1 Phase A payload.

- **Selecting measurement**: section 2.2 (the rotation lane accepted this exact triple,
  post-App, in a landed commit) together with section 2.3 (no other venue can admit it)
  and section 2.4 (the payload is still addressable, and its shape is the same
  three-file transaction section 2.2 proved).
- **Cost**: one manual landing, one MUST-T2a delegation record, one fresh
  `merge_group` run, and re-derivation of the payload against current main.
  No allowlist amendment (see section 0 row 5).
- **Execution shape, fixed by this decision**: a rotation PR from current main,
  **not** a rebase of #333. A rebase would carry #333's base (`1c935b3`) into a
  candidate whose certified state no longer exists; every artifact must be
  re-derived against the new base so that the epoch transaction and the content
  are one coherent generation.

### Option 2 -- Advance the App's `manifest_ref` pin

Ruled out by section 2.5: not executable by this repository (the App owner is not
established here) and not sufficient in principle (blob equality is base-relative;
a moved base does not admit a changed blob). Even a cooperative App owner would be
doing something other than what this option says.

### Option 3 -- Wontfix

Not selected. It keeps the defect as unowned debt while section 2.2 shows the lane that
accepts the fix exists and was used three days ago. Wontfix is a legitimate act,
but it is a decision not to fix, and nothing measured supports it: the payload is
ready, the lane is proven, and the only missing ingredient was this decision.

## 4. Decision

**Option 1: the next admission epoch for the S1 ancestry contract is produced by an
epoch ceremony and executed as a rotation PR re-derived from current main -- not as
a rebase of #333 -- landing through the audited break-glass lane.**

## 5. Consequences

- **The triple advances atomically or not at all.** `ciEpochId`,
  `productionExecutionPin`, `trustedAdmissionWorkflowSha` and the workflow blob are
  one transaction (AGENTS.md section 2.5; ADR-0025 section 7). A commit that moves three of the
  four is the failure mode this shape exists to prevent.
- **The landing is not a merge-queue landing.** It is MUST-T2a: operator
  authorization recorded per PR and before the command
  (`docs/agents/rules_workflow.md:129`), plus the break-glass record of section 0 row 6.
  The App's refusal stays on the record and is not reclassified as success.
- **#333 is not rebased.** Its branch remains the record of a ready payload;
  the landing carries a re-derived copy.
- **The epoch number changes.** Every artifact that names the epoch moves in the
  same commit; section 0 enumerates them.
- **S1 Phase A stays open as debt until section 0 row 8.** A landed epoch is a trust-state
  change, not acceptance evidence.
- **The App's acceptance remains a bounded claim.** The in-repo evidence is that a
  previous rotation landed and that the post-landing triple check holds. Anything
  stronger would be a claim about a verifier this repository cannot read.

## 6. Boundary invariance

What does not change, now or as a consequence of this decision:

- `config/policy/merge_admission.json` -- unchanged. Still 7 required contexts,
  `admission-check` still produced by App `5795152` (`:4`, v1.24.0), `trustSurface`
  still 39 paths (`:78`).
- `config/policy/trust_surface_manifest.json` -- unchanged. Still 18 paths
  (`:6`-`:24`), `readFrom: B_mg` unchanged (`:5`).
- `config/trusted_checker_closure.json` -- unchanged by this ADR; its re-anchor is
  a derived write in the rotation commit (section 0 row 4).
- `src/cli/merge_cli.nim` -- unchanged. `RotationAdrGlob` (`:228`) and
  `RotationAllowlistExtra` (`:300`-`:681`) untouched. **No allowlist amendment is
  required or granted.**
- No test is added, deleted, inverted, or skipped by this ADR.
- The App, rulesets `27097366` / `27525972`, the merge queue parameters and
  `bypass_actors: []` are unchanged.
- No issue or PR state changes: #383 stays open, #333 stays closed.

## 7. Why this record lands through the normal lane

The separation this decision depends on, stated as measurement:

- `docs/adr/**` is in none of the protection lists: not among the 39 `trustSurface`
  entries (`config/policy/merge_admission.json:78`), not among the 18 manifest paths
  (`config/policy/trust_surface_manifest.json:6`-`:24`), and not in the closure
  document (`grep docs/adr config/trusted_checker_closure.json` -> 0 matches).
- `docs/adr/**` is explicitly allowed on the ROTATION path:
  `src/cli/merge_cli.nim:228` (`RotationAdrGlob`), relied on at `:400` for an
  earlier ADR.
- New ADR files need no surface registration: `docs/adr/0044-unicode-script-allowlist-admission.md`
  was added by `4c429074` and `config/repository_surface.json` contains no
  `docs/adr/004[0-9]` entry.

**Decision-only text is landing-eligible. Every step it authorises is break-glass.**
Conflating the two would be the theater AGENTS.md section 0.9 forbids.

## References

- Issue #383 -- the three options and the App verdict quoted in section 2.3.
- PR #333 -- payload shape (section 2.4); head `e35af1fb6531a733b19c63ba9b14e286480e541e`.
- `7f3424cc` -- epoch N+11, the landed precedent (section 2.2).
- `config/policy/trust_surface_manifest.json` `:3`, `:4`, `:5`, `:9`, `:18`, `:22`.
- `config/policy/epoch_manifest.json` `:2`, `:28`; `config/trusted_writer_set.json` `:41`.
- `config/policy/merge_admission.json` `:4` (v1.24.0), `:78` (`trustSurface`).
- `docs/adr/0025-gateway-landing-authority.md` `:210` (section 7 rotation lifecycle).
- `docs/agents/axiom_admission_verifier_ops.md` section 1, section 3.2.
- `docs/agents/rules_workflow.md:129` (MUST-T2a).
- `docs/evidence/breakglass_trust_surface_landing_2026-11-19.md`, `..._2026-11-20.md`.
- `src/cli/merge_cli.nim:228`, `:300`, `:1020`; `src/core/policy/rotation_closure_facts.nim:32`.