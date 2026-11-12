# make build stamps tracked build_metadata.json → Zero-Footprint porcelain fail-close

Status: documented 2026-11-02 (discovered during the ③ u64 slice cold
acceptance at MERGE_SHA `d1e59a9f5b33dc4ea78537e5f6e01249fb8a5622`; the
run1-vs-run2 pair in `experiments/u64-scalar-2026-11-02/OBSERVATION.md`
§3-a/§3-b is the machine-observed evidence).

## 1. Symptom

In a clean detached worktree at a fixed merge SHA, `make build` and
`bin/ax --check-provenance` succeed, but the first counterexample case of
`ax prove` returns `unknown — counterexample unconfirmed (cvUnresolved)`
even though the replay harness compiled, ran, and observed the violating
output (`AXIOM_REPLAY_BEGIN/8/AXIOM_REPLAY_END` — 8 ≠ the claimed 7).

`git status --porcelain` shows exactly one dirty tracked file:

     M src/generated/build_metadata.json

## 2. Root Cause

`make build` regenerates the tracked stamp
`src/generated/build_metadata.json` (gitHash, commitCount, generatedAt,
source path list). The copy committed on main is typically stale (stamped
at an older commit — a merge commit cannot contain its own hash), so any
build dirties the worktree.

The Rust lane's counterexample confirmation then runs the replay, but its
post-run Zero-Footprint integrity check
(`src/verification/rust_replay_adapter.nim:704-728`) executes
`git -C <subjectRoot> status --porcelain`, which reports REPO-WIDE state
even from a subdirectory. The build stamp is therefore seen as subject-tree
drift (`worktreeStable=false`; spelled `porcelainClean=false` at discovery
time) → `rvUnavailable` → fail-closed
`cvUnresolved` in `src/cli/rust_lane_cli.nim:539-552`.

The gating's PROTECTED value was always correct — an observation may anchor
a CONFIRMED counterexample only of the subject tree as hashed — but the
repo-wide empty-porcelain reading was WRONG about what counts as drift:
pre-existing noise (a stale build stamp, untracked files) is present before
AND after the run and says nothing about the run. The G2 contract ("the
subject tree is unchanged across the run" — `replay_evidence_policy.md` §4)
is RELATIVE. The 2026-11-03 restoration (predicate v2, `worktreeStable`)
seals only drift the run itself made (subject inputs + repo status +
tracked content, pre/post equality); the build → prove order is no longer
able to silently degrade the counterexample leg to unconfirmed.

## 3. Correct pattern

Cold-acceptance flows that need a CONFIRMED counterexample at a fixed SHA:

1. `make build` (this stamps the metadata file);
2. `git checkout -- src/generated/build_metadata.json` (restore the
   committed content) — after the 2026-11-03 `worktreeStable` restoration
   this step is UNNECESSARY for a CONFIRMED verdict (the stamp's
   pre-existing dirt sits on both sides of the relative pre/post
   comparison) and is kept only as a harmless hygiene step;
3. verify `git status --porcelain` is empty;
4. run the prove cases.

Observation status after the 2026-11-03 restoration (predicate v2,
`worktreeStable`): dirty → unconfirmed was a valid observation of the OLD
repo-wide gate and remains valid as a record of that era; after the
restoration a dirty-but-STABLE tree CONFIRMS (pre-existing dirt is present
on both sides of the comparison), and only drift the run itself made
seals fail-closed. The negative control is accordingly replaced: not
"dirty vs clean" but the RUN-MADE drift probe
(`tests/fixtures/rust/axiom_drift_probe/` — subjects that write files
during replay; adapter-direct only, no lane registration) which must land
`rvUnavailable` + "subject tree drifted during replay
(hash/porcelain mismatch)". A dirty → unconfirmed pair produced by the old
gate stays honest historical evidence — it is simply not reproducible
post-restoration.
Do NOT "fix" the gate to ignore build-stamped paths: that would mask real
drift with an unproven exemption. (The 2026-11-03 change is a REDEFINITION
of what counts as drift — the run-relative predicate the G2 contract
always stated — not a path exemption: build-stamped paths remain fully
inside the measured footprint; no path is ignored or exempted.)

## 4. Scope note

The stale-committed stamp (main's `build_metadata.json` older than HEAD) is
normal repo state, not a gate defect; re-stamping is a build artifact. No
source change was made for this quirk in the ③ slice — it is recorded so
future cold-acceptance runners order their steps correctly.
