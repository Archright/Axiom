# ADR-0047: Which reading of #218 survives -- option 1, re-derive #238 on main's settled semantics (#386)

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

1. It does not revert, rebase, or otherwise touch `main`. No code, test, spec, or
   policy changes here.
2. It does not amend `DECISION-0830`, and it does not create, move, or widen any
   verdict authority.
3. It does not widen the rotation allowlist. section 0 records the exact amendment the
   fresh PR will need; granting it is a separate act with its own approval slot.
4. It does not validate #238's content. It selects a reading; the content still
   has to be re-derived and proven against the current base.
5. It does not close or reopen anything. #218 stays closed, #238 stays closed,
   #386 stays open.

## 0. Tracking

Every execution step that remains unexecuted. This table is the tracker that lets
issue #386 close on the decision without losing the work. "ROTATION" is the
candidate-delta path of ADR-0025 section 7 (`docs/adr/0025-gateway-landing-authority.md:210`).

| # | Unexecuted step | Artifact it must change | Lane |
|---|---|---|---|
| 1 | Recover #238's payload as a diff. `refs/pull/238/head` = `ed14f2fd3d80561a7d0996736f6df1c80c204353` is still advertised by origin (measured 2026-11-23). Do not merge, rebase, or adopt the old branch. | a new branch off `origin/main` | none (local) |
| 2 | Resolve all five collision points to main's semantics (issue #386 table): (1) absolute `modulePath` read as-is; (2) predicate stays in `src/verification/`, not `src/cli/`; (3) main's 4-key replay input set, not #238's 6; (4) `DECISION-0830`, no `AXIOM_CLAIMS_POLICY`; (5) `--allow-missing` retained. | `src/verification/certificate_verifier.nim` (keep `:48`-`:50`), `src/cli/rust_lane_cli.nim` (keep `:705`, `:708`), the re-derived test imports and CLI members | content PR (see row 5) |
| 3 | Regenerate, never hand-edit: closure values, architecture debt, type registry. | `config/trusted_checker_closure.json`, `data/architecture_debt.json`, `src/generated/type_registry_metadata.json` -- writers `bin/reanchor_pin`, `--regen-arch`, `make build` | ROTATION companion |
| 4 | Register the four companion paths the fresh PR needs. See section 2.5 for the measured set (`docs/spec/cert_lifecycle_contracts.md`, `tests/unit/test_cert_writer_v3.nim`, `tests/unit/test_certificate_trust_closure.nim`, `tests/unit/test_scope_lock_rust.nim`). This is the NEXT A2 (i) amendment (A11): A10 is already spent on #388's test path (`docs/adr/0025:1105`, `:1114`). | `src/cli/merge_cli.nim:300` (`RotationAllowlistExtra`), a new `docs/adr/0025` amendment slot, and its bound tests in `tests/cli/test_merge_cli.nim` (A10's shape, `:1118`) | ROTATION -> break-glass (the amendment changes a `trustSurface` member) |
| 5 | The content PR itself: re-derived #238 payload (rows 1-3) plus the amendment (row 4) or after it. | the re-derived file set | measure the candidate delta at execution time; the App's byte-identity check is not implicated if no manifest path is touched (see section 2.4) |
| 6 | Acceptance evidence for the original defect: `ax cert verify --project <subject>` with an absolute `modulePath` must neither re-root the path nor report `dvcNotCurrent` immediately after issuance (issue #218). `tests/verification/test_cert_source_path_resolution.nim:19` must stay present and green -- it is the pin for the surviving reading, not a candidate for deletion. | test suite + a run record | observation |
| 7 | Fresh verdict: a new App check and a new `merge_group` run for the fresh head. #238's PASS (`touched=19 manifest_touched=0`) certifies a different base and must not be reused. | the run and its journal | observation |
| 8 | Reconcile the salvage set that is already in the tree (section 2.3) against #238's intent, file by file, instead of assuming identity. `src/verification/certificate_identity.nim`, `src/verification/cert_writer.nim`, the two spec docs and the three unit tests all exist on main today; which of their contents came from #238 is unmeasured. | those files | content PR |

## 1. Query

Which reading of #218 survives: main's, or the one PR #238 asserts?

#238 is not stale code awaiting a rebase. `main` committed decisions that
contradict it in five places, and resolving the conflicts by hand would silently
re-decide all five (issue #386).

## 2. Facts

Measured 2026-11-23 at `origin/main` = `5b14bbfce4e559b174a6c18a2e7af62fa76719ea`.

### 2.1 main's reading is committed, and test-pinned

`src/verification/certificate_verifier.nim:45`-`:50`:

```nim
  # Nim's `/` (joinPath) does not discard the head for an absolute tail -- it
  # concatenates ("usr/" / "/lib" == "usr/lib"). An absolute cert modulePath
  # already identifies the subject's module bytes and must not be re-rooted.
  let sourcePath =
    if isAbsolute(certModulePath): certModulePath
    else: repo / certModulePath
```

`tests/verification/test_cert_source_path_resolution.nim:19`:
`test "absolute modulePath is read as-is, not re-rooted under projectRoot"`.

The pair is committed and green. The test is not a description of the code; it is
the predicate that inverts if the reading changes.

### 2.2 Verdict authority is committed and single

`src/cli/rust_lane_cli.nim:708` carries
`{.axiomDecision(id = "DECISION-0830", reason = "Rust lane exit projection consumes
the lane's own summary as its declared contract ...` and the docstring at `:709`-`:713`
states the prohibition: "it does NOT route through `projectRunOutcome` -- a summary
inside the shared run rule would be a second verdict authority."

#238's item 4 adds `AXIOM_CLAIMS_POLICY` + `evaluateClaimsPolicy` +
`required_claims_satisfied` as an admission surface on that lane (issue #386
collision table, row 4). That is the second verdict authority `DECISION-0830`
forbids. Option 2 would have to amend a committed decision on its own epoch.

### 2.3 The salvage set is already in the tree

All of #238's non-colliding files exist on `main` today (measured with
`git cat-file -e origin/main:<path>`):

- `src/verification/certificate_identity.nim` (blob `e2306d87c49d733f78fe113b09b5044b4f91f3e4`)
- `src/verification/cert_writer.nim`
- `docs/spec/cert_lifecycle_contracts.md`, `docs/spec/rust_certified_subset.md`
- `tests/unit/test_cert_writer_v3.nim`, `tests/unit/test_certificate_trust_closure.nim`,
  `tests/unit/test_scope_lock_rust.nim`

Two consequences. First, option 1's work is a **content reconciliation**, not a
file creation. Second, "keep the non-colliding parts" cannot be executed by
copying files: whether a file on `main` already equals #238's version is unmeasured
and must be diffed, not assumed. The `certificate_identity.nim` blob above is the
one identity this record fixes; it was introduced at the clean-room baseline
`c021c338` (2026-11-12).

Issue #386's split-check table and its collision table also disagree about one
file: the split-check lists three unit tests as no-conflict, while collision row 2
lists `tests/unit/test_certificate_trust_closure.nim` as conflicting because it
imports `../../src/cli/cert_cli`. That disagreement is unresolved here and must be
re-measured against the fresh base (row 8).

### 2.4 The App was never the blocker for #238

Issue #386 records PR #238's App verdict as `PASS -- touched=19 manifest_touched=0
reasons=none`, and the landing blocker as `ROT_ALLOWLIST`: 4 changed paths outside
the rotation allowlist. Separately: 303 commits behind, 9 conflicted files /
24 hunks, and `PUT /pulls/238/update-branch` returning
`422 {"message":"merge conflict between base and head"}` with HEAD unchanged.

So the content was admissible to the verifier and blocked by two things that do not
mention trust: a mechanical allowlist and a semantic conflict with `main`. Neither
is evidence about which reading of #218 is right.

### 2.5 The rotation allow set, re-measured today

`rotationAllowlistOk` (`src/cli/merge_cli.nim:1020`-`:1036`) admits a path iff it
is a closure member (pin@B), or in `RotationAllowlistExtra` (`:300`-`:681`), or is
`RotationPinBPath` / `RotationClosurePath`, or matches `RotationAdrGlob`
(`docs/adr/**`, `:228`).

Of #238's 19 changed paths, at the current base: 11 are closure members, 3 are
already in `RotationAllowlistExtra` (`data/architecture_debt.json`,
`docs/spec/rust_certified_subset.md`, `src/generated/type_registry_metadata.json`),
and `config/trusted_checker_closure.json` is `RotationClosurePath`
(`src/core/policy/rotation_closure_facts.nim:36`). Four are outside the set:

```text
docs/spec/cert_lifecycle_contracts.md
tests/unit/test_cert_writer_v3.nim
tests/unit/test_certificate_trust_closure.nim
tests/unit/test_scope_lock_rust.nim
```

That is the same count #386 measured, independently reproduced at a later base.
All four are rotation-companion class -- a spec doc and the unit contracts of
changed closure members -- and **none is production `src/`**, so registering them
does not violate A2 (i) ("NON-member production src/ still fails",
`src/cli/merge_cli.nim:1026`-`:1027`). The amendment is available and is the same
companion class as A5 or A7, and smaller than either (A5 registered 16 paths,
A7 nine, A10 one).

The amendment's home is the NEXT slot. A10 is already spent: it registered
`tests/unit/test_axiom_probe_unknown_not_empty.nim` for #388
(`docs/adr/0025:1105`, `:1114`). Citing "an A10 amendment" as the instrument for
this work would be a stale reference; the instrument is A11.

### 2.6 The two readings are exclusive

- #238: "absolute modulePath -> source staleness FAIL (never read as absolute)";
  realpath containment required.
- `main`: the absolute path "already identifies the subject's module bytes and
  must not be re-rooted" (`certificate_verifier.nim:46`-`:47`).

Both sides assert their reading in a test. Whichever side is dropped, a
currently-green test must be deleted or inverted. That is why this is a decision
and not a merge resolution (issue #386, "Why an agent must not resolve this").

### 2.7 The record's state

- Issue #218: `CLOSED`, 2026-11-20T23:47:39Z -- closed with main's reading in place.
- PR #238: `CLOSED` (not merged), 2026-11-23T03:53:43Z, head
  `ed14f2fd3d80561a7d0996736f6df1c80c204353`, 19 files, branch
  `workstream/rust-authority-verdict`.

## 3. Options

### Option 1 -- Re-derive #238 on main's settled semantics, fresh PR (SELECTED)

Keep main's reading of #218 and of the rust-lane verdict authority; re-derive the
rest on the current base; open a fresh PR; register the four companion paths.

- **Selecting measurement**: section 2.1 (the committed pair is green and test-pinned) and
  section 2.2 (`DECISION-0830` forecloses a second verdict authority). Option 2 must
  invert a passing test **and** amend a committed decision on its own epoch --
  strictly the larger act. Option 1 moves neither decision and pays, instead, the
  re-derivation plus one single-class allowlist amendment (section 2.5).
- **Cost**: content reconciliation of files that already exist (section 2.3), one
  amendment (A11) that is itself a trust-surface change, and one fresh verdict.
- **Boundary**: #238 itself is not the vehicle. The branch stays as the record of
  the competing design.

### Option 2 -- Adopt #238's reading, revert main, amend `DECISION-0830`

Ruled out by section 2.1 and section 2.2. It requires inverting
`tests/verification/test_cert_source_path_resolution.nim:19` -- a green test that
pins a security property, not a formatting choice -- and amending `DECISION-0830`
in its own epoch, to reintroduce a second verdict authority the decision names
explicitly. Two committed decisions move so that one unlanded branch can win.

### Option 3 -- Wontfix; main's reading stands, #238 recorded as unlanded

Not selected. It is honest about the outcome (main's reading does stand) but it
discards the one piece of real salvage measured in #386: the non-colliding content
that is already in the tree (section 2.3). Wontfix would also leave the boundary between
"#218 is closed" and "#238's design is still unimplemented" recorded nowhere, so
the next reader would re-litigate it.

## 4. Decision

**Option 1: main's reading of #218 survives unchanged; #238 is not adopted; its
non-colliding content is re-derived on main's settled semantics and lands through a
fresh PR that carries its own rotation-allowlist amendment (A11).**

## 5. Consequences

- **No test is inverted.** `tests/verification/test_cert_source_path_resolution.nim:19`
  stays, unchanged and green; the absolute `modulePath` is read as-is.
- **`DECISION-0830` is untouched.** The rust lane keeps exactly one verdict
  authority; `AXIOM_CLAIMS_POLICY` does not become an admission surface.
- **#238 becomes a record, not a vehicle.** The branch
  `workstream/rust-authority-verdict` @ `ed14f2fd` stays advertised as the competing
  design; the landing carries a re-derived copy.
- **A rotation amendment is now a known prerequisite.** section 2.5 fixes the exact four
  paths at the current base; a different base may re-open the measurement, and the
  amendment must be enumerated from the delta it actually carries (`A4` rule: no
  globs).
- **The amendment is the trust-relevant act, not the content.** `src/cli/merge_cli.nim`
  is a `trustSurface` entry (`config/policy/merge_admission.json:78`), so the
  amendment cannot ride the normal lane. The content PR's own lane depends on its
  measured delta and is not assumed here.
- **#218's closure is not disturbed.** It stays closed; this decision confirms why.
- **A disagreement inside #386 is carried forward as work, not resolved by
  assertion** (section 2.3, row 8).

## 6. Boundary invariance

What does not change, now or as a consequence of this decision:

- `src/verification/certificate_verifier.nim:48`-`:50` -- unchanged. The absolute
  `modulePath` continues to be read as-is.
- `src/cli/rust_lane_cli.nim:708` -- unchanged. `DECISION-0830` and
  `axiom.rust-lane.exit.v1` (`:705`) continue to be the lane's declared contract,
  and the lane continues not to emit canonical `runOutcome`.
- CLI absence semantics: `--allow-missing` (landed via #268, A8 (ii)) unchanged.
- The replay input key set stays main's 4 keys, not #238's 6 (issue #386 collision
  row 3).
- `config/trusted_checker_closure.json`, `data/architecture_debt.json`,
  `src/generated/type_registry_metadata.json` are unchanged by this ADR; their
  regeneration belongs to the execution step that changes the code.
- Issue state: #218 stays closed, #238 stays closed, #386 stays open.
- No policy JSON, pin, workflow, gate, ruleset, or required-check change.

## 7. Why this record lands through the normal lane

- `docs/adr/**` is in none of the protection lists: not among the 39 `trustSurface`
  entries (`config/policy/merge_admission.json:78`), not among the 18 manifest paths
  (`config/policy/trust_surface_manifest.json:6`-`:24`), and not in the closure
  document (`grep docs/adr config/trusted_checker_closure.json` -> 0 matches).
- `docs/adr/**` is explicitly allowed on the ROTATION path: `src/cli/merge_cli.nim:228`
  (`RotationAdrGlob`), relied on at `:400`.
- New ADR files need no surface registration: `docs/adr/0044-unicode-script-allowlist-admission.md`
  was added by `4c429074`, and `config/repository_surface.json` contains no
  `docs/adr/004[0-9]` entry.

**Decision-only text is landing-eligible. Every step it authorises -- the code
re-derivation, the closure regeneration, the A11 amendment -- is ROTATION or
break-glass.** The separation is the point of writing this as a record.

## References

- Issue #386 -- the five collisions, the three options, the App/rotation split (section 2.4).
- PR #238 -- head `ed14f2fd3d80561a7d0996736f6df1c80c204353`, 19 files, closed
  2026-11-23 (section 2.7).
- Issue #218 -- closed 2026-11-20 with main's reading in place.
- `src/verification/certificate_verifier.nim:45`-`:50`;
  `tests/verification/test_cert_source_path_resolution.nim:19`.
- `src/cli/rust_lane_cli.nim:705`, `:708`, `:709`-`:713` (`DECISION-0830`).
- `src/cli/merge_cli.nim:228`, `:300`-`:681`, `:1020`-`:1036`;
  `src/core/policy/rotation_closure_facts.nim:32`, `:36`.
- `docs/adr/0025-gateway-landing-authority.md` `:417` (A2), `:1105`, `:1114`,
  `:1118` (A10 -- spent).
- `config/policy/merge_admission.json:78`; `config/policy/trust_surface_manifest.json:6`-`:24`.
- `src/verification/certificate_identity.nim` (main blob `e2306d87`).