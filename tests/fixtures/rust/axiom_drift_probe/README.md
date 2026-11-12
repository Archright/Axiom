# axiom_drift_probe — replay-seal negative control (drift probe)

The Rust counterexample replay seal's NEGATIVE-CONTROL subjects
(docs/spec/replay_evidence_policy.md §4 G2 — predicate v2
`worktreeStable`): each `drift_*` function writes a file NEXT TO the
subject source at replay run time, so the RELATIVE pre/post worktree
comparison the seal performs must detect run-made drift and fail-closed
the observation (`rvUnavailable` + "subject tree drifted during replay
(hash/porcelain mismatch)").

| function | case | what moves during the run |
|---|---|---|
| `drift_new_file_add` | N1a — creates a NEW untracked file (`drift_new.txt`) | the `status --untracked-files=all` line, the `ls-files --others` entry AND the subject-inputs content digest |
| `drift_overwrite_add` | N1b — overwrites a PRE-CREATED untracked file (`drift_seed.txt`) | ONLY the subject-inputs content digest — the status line and the tracked diff never move (this is the gap the old repo-wide clean-porcelain reading could not see) |
| `drift_clean_add` | contrast — a plain pure function | nothing (rvAgree + `worktreeStable == true` must hold) |

Adapter-direct ONLY: this crate carries NO `.llbc`, NO
`axiom.specs.json` and NO scope-lock registration
(`data/verification_scope.lock`) — deliberately. The drift functions are
NOT lane targets: their filesystem side effect is outside the certified
straight-line-subset grammar (a Call to a file-writing function is
rejected by the producer upstream of the lane), so a lane registration
would be dead surface. The consumers are the standalone gateway tests
(`tests/gateway/rust_drift_probe_test.nim`), which materialize a
throwaway git repo per case (Zero-Footprint — the Axiom working tree is
never written) and drive `runRustCounterexampleReplay` directly with the
Nim-assembled postcondition `result == a + b`.

`file!()`-derived paths are the determinism anchor: the replay harness
splices this file via `include!("<abs path>")`, so `file!()` resolves to
the materialized subject's ABSOLUTE path at compile time and the drift
file lands inside the throwaway repo, never relative to the caller's
cwd and never inside `tests/fixtures/`.
