## Rust replay-seal drift probe — standalone negative control (G2 predicate v2).
##
## The replay seal's CONFIRMED path was restored (2026-11-03) to the G2
## contract's relative semantics ("the subject tree is unchanged across the
## run" — docs/spec/replay_evidence_policy.md §4, `worktreeStable`): the
## pre-run vs post-run pair must be equal for (a) the subject module
## sha256, (b) the subject-inputs digest, and (c)+(d) the combined repo
## footprint (status -uall + tracked diff). These tests pin the NEGATIVE
## side of that predicate with REAL run-made drift — the replacement for
## the old "dirty vs clean" pair documented (as a historical observation)
## in docs/spec/build_metadata_stamp_porcelain_quirk.md:
##
##   N1a  drift_new_file_add — the subject CREATES a new untracked file
##        during the replay run. The status line, the ls-files entry and
##        the subject-inputs content digest all move → rvUnavailable +
##        the pinned drift diagnostic + worktreeStable == false.
##   N1b  drift_overwrite_add — the subject OVERWRITES a pre-created
##        untracked file (seeded AFTER the git commit, so it is untracked).
##        The status line and the tracked diff NEVER move; only the (b)
##        content digest detects it. This is the exact gap that sailed
##        through as rvAgree under any porcelain-only reading — the (b)
##        digest catching it is this slice's core proof (asserted via
##        repoFootprintPre == repoFootprintPost ∧ subjectInputsPre !=
##        subjectInputsPost, so the ORACLE proves WHICH component caught
##        the drift, never just that something did).
##   Contrast  drift_clean_add — a plain pure function, no drift:
##        rvAgree + worktreeStable == true must HOLD (the seal still
##        admits honest agreement).
##
## PLACEMENT / LEVEL: adapter-direct, standalone — the drift functions are
## deliberately NOT lane targets (no .llbc / axiom.specs.json / scope
## lock: the file-writing side effect is outside the certified subset
## grammar — see the fixture README), so this file drives
## `runRustCounterexampleReplay` directly with the Nim-assembled
## postcondition `result == a + b`. The filename intentionally does NOT
## match the gateway lane's `*_feature_test.nim` collection glob, so it
## runs standalone (`nim c -d:release -r
## tests/gateway/rust_drift_probe_test.nim`) without distorting the
## landing lane — the recorded pattern of
## rust_subject_three_cases_test.nim.
##
## Zero-Footprint: each case materializes a throwaway git repo under
## getTempDir() and copies the fixture's REAL source UNCHANGED — the
## Axiom working tree (and the fixture tree) is never written, and the
## drift files land inside the throwaway repo only.

import std/[os, osproc, strutils, unittest]

import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers       ## irEq/irAdd/irVar constructors
import verification/counterexample_replay   ## rv* vocabulary + markers (shared)
import verification/rust_replay_adapter

proc repoRoot(): string =
  ## tests/gateway/<file> -> project root (location-based — the pattern of
  ## rust_subject_three_cases_test.nim).
  absolutePath("../..", currentSourcePath().parentDir)

let
  RepoRoot = repoRoot()
  DriftSourcePath = RepoRoot / "tests" / "fixtures" / "rust" /
      "axiom_drift_probe" / "src" / "lib.rs"

let rustcPresent = findExe("rustc").len > 0

if not rustcPresent:
  echo "SKIP: rustc not on PATH — drift probe suites skipped (explicit skip, not a failure)"

proc materializeDriftSubject(dirName: string): string =
  ## The replay adapter binds subject identity through git against the
  ## materialized root itself — the fixture's REAL source is copied
  ## UNCHANGED into a throwaway git repo and committed (Zero-Footprint
  ## Integrity; the materializeProbeSubject pattern).
  let root = getTempDir() / dirName
  removeDir(root)
  createDir(root)
  copyFile(DriftSourcePath, root / "subject.rs")
  discard execCmdEx("git -C \"" & root & "\" init -q")
  discard execCmdEx("git -C \"" & root & "\" add -A")
  discard execCmdEx("git -C \"" & root &
    "\" -c user.name=ax -c user.email=ax@test commit -q -m init")
  root

let bv64 = irTypeBitVec64()
## The spec under test: f(a,b) = a+b — the drift functions return a+b+1,
## so WITHOUT drift the replay would AGREE with the solver (rvAgree).
proc specAddAdd(): IRExpr =
  irEq(irVar("result", bv64), irAdd(irVar("a", bv64), irVar("b", bv64)))

## The contrast case's spec: result == a+b+1 — `drift_clean_add` (a plain
## pure `a + b`) VIOLATES it on every input, so the contrast drives the
## AGREEMENT path (violation reproduced, rvAgree) without any drift — the
## same shape as the u64_add_mutant negative control.
proc specAddAddPlusOne(): IRExpr =
  irEq(irVar("result", bv64),
       irAdd(irAdd(irVar("a", bv64), irVar("b", bv64)), irLit(1)))

proc driftCfg(repo: string; fnName: string): RustReplayConfig =
  RustReplayConfig(
    subjectRepoRoot: repo,
    subjectModulePath: repo / "subject.rs",
    funcName: fnName,
    paramNames: @["a", "b"],
    inputLiterals: @["0", "0"],
    postconditions: @[specAddAdd()])

# ── N1a: run-made NEW untracked file ───────────────────────────────────────

suite "rust_drift_probe — N1a new untracked file during replay":

  if rustcPresent:
    test "run-made file creation fail-closes the seal (rvUnavailable + " &
        "pinned drift diagnostic + worktreeStable == false)":
      putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_drift_probe_state")
      let repo = materializeDriftSubject("ax_drift_n1a")
      let rec = runRustCounterexampleReplay(driftCfg(repo, "drift_new_file_add"))
      # The harness RAN (exit 0, value observed) — the refusal is the SEAL,
      # not an execution failure.
      check rec.exitCode == 0
      check rec.observedOutput.contains("AXIOM_REPLAY_BEGIN")
      check rec.observedOutput.contains("AXIOM_REPLAY_END")
      check rec.verdict == rvUnavailable
      check rec.diagnostics ==
        "subject tree drifted during replay (hash/porcelain mismatch)"
      check rec.worktreeStable == false
      # The relative components that caught it: the status line + inputs
      # listing moved (new file); the tracked diff stayed (untracked file).
      check rec.subjectInputsPre != rec.subjectInputsPost
      check rec.repoFootprintPre != rec.repoFootprintPost
      # The subject module itself is untouched — drift is NEXT TO it.
      check rec.moduleSha256AfterRun == rec.moduleSha256
      # PROPOSITION_DISPROVED discipline: the record folds carry the
      # fail-closed state.
      let payload = rustReplayRecordPayload(rec)
      check payload.contains("replay.worktreeStable=false")
      check payload.contains("replay.diagnostics=subject tree drifted " &
        "during replay (hash/porcelain mismatch)")

# ── N1b: run-made overwrite of a pre-created untracked file ────────────────

suite "rust_drift_probe — N1b untracked overwrite during replay":

  if rustcPresent:
    test "content-only drift on an untracked file is caught by the (b) " &
        "digest — the gap porcelain-only readings could never see":
      putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_drift_probe_state")
      let repo = materializeDriftSubject("ax_drift_n1b")
      # Seed AFTER the commit — drift_seed.txt is UNTRACKED for the whole
      # run: its status line ("?? drift_seed.txt") is identical pre/post,
      # and `git diff HEAD` never mentions it. Only the subject-inputs
      # content digest can see the overwrite.
      writeFile(repo / "drift_seed.txt", "seed\n")
      let rec = runRustCounterexampleReplay(driftCfg(repo, "drift_overwrite_add"))
      check rec.exitCode == 0
      check rec.verdict == rvUnavailable
      check rec.diagnostics ==
        "subject tree drifted during replay (hash/porcelain mismatch)"
      check rec.worktreeStable == false
      # THE core proof of this slice: the (c)+(d) footprint is IDENTICAL
      # pre/post (a porcelain-only gate would have passed this run as
      # rvAgree), and the (b) subject-inputs digest is what moved.
      check rec.repoFootprintPre == rec.repoFootprintPost
      check rec.subjectInputsPre != rec.subjectInputsPost
      check rec.moduleSha256AfterRun == rec.moduleSha256

# ── Contrast: no drift — the seal still admits honest agreement ────────────

suite "rust_drift_probe — contrast: clean agreement keeps CONFIRMED":

  if rustcPresent:
    test "pure subject (a+b vs the violated +1 spec), no drift → rvAgree + " &
        "worktreeStable == true":
      putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_drift_probe_state")
      let repo = materializeDriftSubject("ax_drift_clean")
      # `drift_clean_add` is a plain pure `a + b`; against the violated
      # result == a+b+1 spec the replay AGREES (violation reproduced) with
      # zero drift — the same shape as the u64_add_mutant negative control.
      var cfg = driftCfg(repo, "drift_clean_add")
      cfg.postconditions = @[specAddAddPlusOne()]
      let rec = runRustCounterexampleReplay(cfg)
      check rec.exitCode == 0
      check rec.verdict == rvAgree
      check rec.diagnostics.len == 0
      check rec.worktreeStable == true
      check rec.subjectInputsPre == rec.subjectInputsPost
      check rec.repoFootprintPre == rec.repoFootprintPost
      let payload = rustReplayRecordPayload(rec)
      check payload.contains("replay.worktreeStable=true")
