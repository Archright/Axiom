## Rust counterexample replay adapter tests (feat/rust-subject-v1).
##
## Contract under test (docs/spec/counterexample_replay_adapter.md §3 —
## language-partitioned adapter):
##   1. Positive — a Rust subject (`fn add_u8`) whose SAT model binding
##      violates the postcondition concretely: the real `rustc` harness
##      reproduces the violation → rvAgree (the observation a PROPOSITION_DISPROVED
##      requires; sat alone never promotes).
##   2. Negative — a binding that does NOT violate: the harness contradicts
##      the solver model → rvDisagree (fail-closed for the caller).
##   3. Fail-closed — unbound parameter (exact-input), missing toolchain,
##      compile failure, violated/unverifiable declared pin → rvUnavailable;
##      a NON-git subject root (no `git init`, discovery mode) fails closed
##      at the exact-commit binding — rroUnavailable + "subject repo root
##      not discoverable", never an agreement, never a panic observation.
##   4. Pure literals — ModelBinding → Rust source literal projection +
##      exact-input gate (rust_symbolic_test_synth).
##   5. Panic observation — an overflowing in-subset call under the PINNED
##      compile profile: the harness panics (exit 101) → the DISTINCT
##      `rroPanicked` outcome + verbatim panic evidence, never rvAgree and
##      never conflated with the generic unavailable fold (the shared
##      `verdict` fail-closes to rvUnavailable — the projection, not the
##      classification). Also pins the recorded compile profile
##      (`overflow-checks=on` + `debug-assertions=on`) and run-to-run
##      determinism of the verdict + evidence class.
##   6. BuildInvocation — the replay build identity as a pure record
##      (`rustBuildInvocation`): the cmdLine RECOMPUTES the pinned build
##      command (rustBuildCommand — the exact template pinned in suite 1,
##      strings unchanged), profileFlags == RustReplayProfileFlags, and
##      `rustReplayCommandMismatch` is the record-consistency gate: "" iff
##      the record's compileCommand/compileProfile match the invocation,
##      a non-empty diagnostic on any forged field (tampered profile or
##      command — fail-closed).
##
## Environment gate: the whole file skips with an explicit message when
## `rustc` is not on PATH (skip, not failure).

import std/[unittest, options, strutils, os, osproc, sequtils, tables]

import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/symbol_table_types
import core/crypto/hash_kernel
import core/types/obligation_evidence
import verification/counterexample_replay  ## rv* verdicts + inputLiteralsPayload (shared vocabulary)
import verification/rust_replay_adapter
import verification/rust_symbolic_test_synth

let rustcPresent = findExe("rustc").len > 0

if not rustcPresent:
  echo "SKIP: rustc not found on PATH — Rust replay adapter tests skipped (explicit skip, not a failure)"
  quit(0)

let bv64 = irTypeBitVec64()

func bvHex(v: int64): string =
  "#x" & v.toHex(16).toLowerAscii()

# ─── Suite 1: Rust literal projection + exact-input gate (pure) ────────────

suite "rust_symbolic_test_synth — literal projection and exact-input gate":

  test "bv64 hex/decimal binding → decimal Rust integer literal":
    check bindingToRustLiteral(ModelBinding(name: "a", value: bvHex(5), sort: "(_ BitVec 64)"), bv64) == "5"
    check bindingToRustLiteral(ModelBinding(name: "a", value: "42", sort: "(_ BitVec 64)"), bv64) == "42"
    # bit63-set model values print as their UNSIGNED decimal — the Rust
    # lane's canonical types are rsgUnsigned-only, so the signed "-1" a raw
    # int64 reinterpretation would print never reaches a u64 call site
    check bindingToRustLiteral(ModelBinding(name: "a", value: bvHex(-1), sort: "(_ BitVec 64)"), bv64) ==
      "18446744073709551615"
    check bindingToRustLiteral(ModelBinding(name: "a", value: bvHex(-4611686018427387904), sort: "(_ BitVec 64)"), bv64) ==
      "13835058055282163712"

  test "bool binding → true/false literal":
    let boolTy = irTypeBool()
    check bindingToRustLiteral(ModelBinding(name: "f", value: "true", sort: "Bool"), boolTy) == "true"
    check bindingToRustLiteral(ModelBinding(name: "f", value: "false", sort: "Bool"), boolTy) == "false"
    check bindingToRustLiteral(ModelBinding(name: "f", value: "garbage", sort: "Bool"), boolTy) == "false"

  test "outside the certified subset → empty literal (fail-closed)":
    check bindingToRustLiteral(ModelBinding(name: "l", value: "nil", sort: "List"), irTypeList(bv64)).len == 0

  test "exact-input gate names every unbound parameter, positional order":
    let params = @[IRFuncParam(name: "a", ty: bv64, constraint: none(IRExpr)),
                   IRFuncParam(name: "b", ty: bv64, constraint: none(IRExpr))]
    let full = @[ModelBinding(name: "a", value: bvHex(5), sort: ""),
                 ModelBinding(name: "b", value: bvHex(3), sort: "")]
    check unboundParameters(full, params).len == 0
    let partial = @[ModelBinding(name: "a", value: bvHex(5), sort: "")]
    check unboundParameters(partial, params) == @["b"]
    check unboundParameters(@[], params) == @["a", "b"]

  test "modelToRustTestInputs: bound by name; unbound → empty (never a default)":
    let params = @[IRFuncParam(name: "a", ty: bv64, constraint: none(IRExpr)),
                   IRFuncParam(name: "b", ty: bv64, constraint: none(IRExpr))]
    let bindings = @[ModelBinding(name: "b", value: bvHex(3), sort: ""),
                     ModelBinding(name: "a", value: bvHex(5), sort: "")]
    check modelToRustTestInputs(bindings, params) == @["5", "3"]
    check modelToRustTestInputs(@[], params) == @["", ""]

  test "harness synthesis: include! splice + shared marker protocol":
    let h = renderRustReplayHarness("/tmp/ax/subject.rs", "add_u8", @["5", "3"])
    check h.contains("include!(\"/tmp/ax/subject.rs\");")
    check h.contains("println!(\"AXIOM_REPLAY_BEGIN\");")
    check h.contains("println!(\"{}\", add_u8(5, 3));")
    check h.contains("println!(\"AXIOM_REPLAY_END\");")

  test "build command template is rustc (not nim c -r), profile pinned":
    let cmd = rustBuildCommand("rustc", "/h/replay_harness.rs", "/h/bin")
    check cmd.contains("rustc")
    check cmd.contains("--edition 2021")
    check not cmd.contains("nim")
    # The replay compile profile is PINNED to the extraction profile (the
    # LLBC AddChecked/Assert overflow lowering is the structural witness,
    # docs/spec/rust_toolchain_quirks.md Q5) — never left to rustc's
    # emergent opt-level-derived defaults:
    check cmd.contains("-C overflow-checks=on")
    check cmd.contains("-C debug-assertions=on")

# ─── Suite 2: harness end-to-end on a synthetic Rust subject fixture ────────

proc gitCapture(root: string; args: string): string =
  let (outp, code) = execCmdEx("git -C \"" & root & "\" " & args,
                               options = {poStdErrToStdOut, poUsePath})
  if code == 0: outp.strip() else: ""

proc makeSubjectFixture(dirName: string; source: string; gitBind: bool = true): string =
  ## Synthetic subject: a temp dir holding one real Rust source file.
  ## `gitBind` additionally materializes a real git repo (init + add + commit)
  ## so the adapter's exact-commit binding can fold a git identity; without
  ## it the subject is NON-git — binding must fail closed.
  let root = getTempDir() / dirName
  removeDir(root)
  createDir(root)
  writeFile(root / "subject.rs", source)
  if gitBind:
    discard execCmdEx("git -C \"" & root & "\" init -q", options = {poStdErrToStdOut, poUsePath})
    discard execCmdEx("git -C \"" & root & "\" add -A", options = {poStdErrToStdOut, poUsePath})
    discard execCmdEx("git -C \"" & root & "\" -c user.name=ax -c user.email=ax@test commit -q -m init",
                      options = {poStdErrToStdOut, poUsePath})
  root

const RustSubject = """fn add_u8(a: u8, b: u8) -> u8 {
    a + b
}
"""

suite "rust_replay_adapter — harness end-to-end (real rustc)":
  ## Postcondition `result <= 7`: a=5,b=3 → 8 (violated, no u8 overflow —
  ## debug overflow panics must never masquerade as observations);
  ## a=1,b=2 → 3 (holds).

  let propLeSeven = irLe(irVar("result", bv64), irLit(7))

  proc violatedCfg(root: string; pinnedChannel: string = ""): RustReplayConfig =
    RustReplayConfig(
      subjectRepoRoot: root,
      subjectModulePath: root / "subject.rs",
      funcName: "add_u8",
      paramNames: @["a", "b"],
      inputLiterals: @["5", "3"],
      postconditions: @[propLeSeven],
      pinnedChannel: pinnedChannel)

  test "violation reproduced on the real toolchain → rvAgree with full record":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_rust_replay_state")
    let root = makeSubjectFixture("ax_rust_replay_violated", RustSubject)
    let record = runRustCounterexampleReplay(violatedCfg(root))
    check record.verdict == rvAgree
    check record.exitCode == 0
    check record.subjectGitRef == gitCapture(root, "rev-parse HEAD")
    check record.subjectGitRef.len == 40
    check record.subjectTreeMerkle == gitCapture(root, "rev-parse HEAD^{tree}")
    check record.moduleSha256 == sha256Hex(RustSubject)
    check record.moduleSha256AfterRun == record.moduleSha256
    check record.worktreeStable
    check record.rustVersion.len > 0
    check record.rustcHash.len > 0
    check record.rustComponents.len > 0
    check record.hostPlatform.len > 0
    check record.diagnostics.len == 0
    # Profile state: the replay compile is pinned to the extraction profile
    # and the exact command is recorded.
    check record.compileProfile.contains("overflow-checks=on")
    check record.compileProfile.contains("debug-assertions=on")
    check record.compileCommand.contains("--edition 2021")
    check record.compileCommand.contains("-C overflow-checks=on")
    check record.compileCommand.contains("-C debug-assertions=on")
    # PROPOSITION_DISPROVED payload folds — measured toolchain identity included.
    let payload = rustReplayRecordPayload(record)
    check payload.contains("replay.verdict=rvAgree")
    check payload.contains("replay.subjectGitRef=" & record.subjectGitRef)
    check payload.contains("replay.rustVersion=" & record.rustVersion)
    check payload.contains("replay.rustChannel=" & record.rustChannel)
    check payload.contains("replay.rustProfile=" & record.rustProfile)
    check payload.anyIt(it.startsWith("replay.rustComponents="))
    check payload.contains("replay.rustDeclaredPin=")
    # Predicate-v2 folds: the relative worktree-stability state rides the
    # payload (deterministic order — worktreeStable, subjectInputs pair,
    # combined repo-footprint pair).
    check payload.contains("replay.worktreeStable=true")
    check payload.contains("replay.subjectInputsPre=" & record.subjectInputsPre)
    check payload.contains("replay.subjectInputsPost=" & record.subjectInputsPost)
    check payload.contains("replay.repoFootprintPre=" & record.repoFootprintPre)
    check payload.contains("replay.repoFootprintPost=" & record.repoFootprintPost)
    check inputLiteralsPayload(@["a", "b"], @["5", "3"]) == @["input.a=5", "input.b=3"]

  test "property actually holds on observed result → rvDisagree (fail-closed input)":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_rust_replay_state")
    let root = makeSubjectFixture("ax_rust_replay_sound", RustSubject)
    var cfg = violatedCfg(root)
    cfg.inputLiterals = @["1", "2"]  # 1+2=3 → result <= 7 holds
    let record = runRustCounterexampleReplay(cfg)
    check record.verdict == rvDisagree
    check record.exitCode == 0
    check record.diagnostics.len > 0

  test "measured channel satisfies the declared pin → still rvAgree":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_rust_replay_state")
    let root = makeSubjectFixture("ax_rust_replay_pin_ok", RustSubject)
    # Pin with the MEASURED channel identity from a first (unpinned) run —
    # environment-independent: the measured channel trivially names itself.
    let unpinned = runRustCounterexampleReplay(violatedCfg(root))
    check unpinned.verdict == rvAgree
    check unpinned.rustChannel.len > 0
    let record = runRustCounterexampleReplay(violatedCfg(root, unpinned.rustChannel))
    check record.verdict == rvAgree
    check record.declaredPin == unpinned.rustChannel

  test "declared pin violated → rvUnavailable (fail-closed, no execution)":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_rust_replay_state")
    let root = makeSubjectFixture("ax_rust_replay_pin_bad", RustSubject)
    let record = runRustCounterexampleReplay(violatedCfg(root, "nightly-2099-01-01"))
    check record.verdict == rvUnavailable
    check record.diagnostics.contains("does not satisfy the declared pin")

  test "missing toolchain → rvUnavailable before anything executes":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_rust_replay_state")
    let root = makeSubjectFixture("ax_rust_replay_notool", RustSubject)
    var cfg = violatedCfg(root)
    cfg.rustcExe = getTempDir() / "ax_no_such_rustc" / "rustc"
    let record = runRustCounterexampleReplay(cfg)
    check record.verdict == rvUnavailable
    check record.diagnostics.contains("rustc not found")
    check record.exitCode == -1

  test "harness compile failure → rvUnavailable (unknown function fail-closed)":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_rust_replay_state")
    let root = makeSubjectFixture("ax_rust_replay_badfn", RustSubject)
    var cfg = violatedCfg(root)
    cfg.funcName = "no_such_fn_in_subject"
    let record = runRustCounterexampleReplay(cfg)
    check record.verdict == rvUnavailable
    check record.diagnostics.contains("harness compile failed")

  test "input/param arity mismatch → rvUnavailable":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_rust_replay_state")
    let root = makeSubjectFixture("ax_rust_replay_arity", RustSubject)
    var cfg = violatedCfg(root)
    cfg.inputLiterals = @["5"]
    let record = runRustCounterexampleReplay(cfg)
    check record.verdict == rvUnavailable
    check record.diagnostics.len > 0

  test "missing subject source → rvUnavailable before anything executes":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_rust_replay_state")
    let cfg = RustReplayConfig(
      subjectRepoRoot: "",
      subjectModulePath: getTempDir() / "ax_rust_replay_missing" / "nope.rs",
      funcName: "add_u8",
      paramNames: @["a", "b"],
      inputLiterals: @["5", "3"],
      postconditions: @[propLeSeven])
    let record = runRustCounterexampleReplay(cfg)
    check record.verdict == rvUnavailable
    check record.exitCode == -1

  test "NON-git subject root → rroUnavailable fail-closed at the exact-commit " &
      "binding (never an agreement, never a panic observation)":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_rust_replay_state")
    # A plain temp dir — NO `git init` — plus discovery mode
    # (subjectRepoRoot = ""): the adapter's read-only rev-parse root
    # discovery fails, so the integrity binding refuses BEFORE anything
    # executes (no harness dir, no rustc invocation, exit code stays -1).
    let root = makeSubjectFixture("ax_rust_replay_nongit", RustSubject,
                                  gitBind = false)
    var cfg = violatedCfg(root)
    cfg.subjectRepoRoot = ""
    let record = runRustCounterexampleReplay(cfg)
    check record.outcome == rroUnavailable
    check record.verdict == rvUnavailable
    check record.outcome != rroPanicked
    check record.outcome != rroAgree
    check record.verdict != rvAgree
    check record.exitCode == -1
    check record.diagnostics ==
      "subject repo root not discoverable (exact-commit binding required)"

  test "overflowing in-subset call → DISTINCT panic observation " &
      "(never rvAgree, never the plain unavailable classification)":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_rust_replay_state")
    let root = makeSubjectFixture("ax_rust_replay_overflow", RustSubject)
    var cfg = violatedCfg(root)
    # (200, 56): both inputs inside the u8 domain, but 200+56 overflows u8 —
    # under the PINNED profile the harness panics (Rust Reference: with
    # debug assertions enabled implementations MUST insert dynamic checks
    # that panic on overflow; RFC 560). A panic is evidence about the
    # compile profile, never an in-domain counterexample observation.
    cfg.inputLiterals = @["200", "56"]
    let record = runRustCounterexampleReplay(cfg)
    # The DISTINCT lane classification — not agreement, and explicitly not
    # the generic unavailable outcome:
    check record.outcome == rroPanicked
    check record.outcome != rroUnavailable
    check record.outcome != rroAgree
    check record.exitCode == 101
    check record.panicEvidence.contains("panicked at")
    check record.diagnostics.contains("harness panicked")
    # `verdict` is the shared-vocabulary PROJECTION (ReplayVerdict has no
    # panic value and its home module is shared with the Nim lane): a panic
    # folds to rvUnavailable there — fail-closed for every existing
    # consumer, and replayConfirmedRustDisproof confirms nothing from it.
    check record.verdict == rvUnavailable
    check record.verdict != rvAgree
    # Zero-Footprint Integrity holds through the panic path.
    check record.worktreeStable
    check record.moduleSha256AfterRun == record.moduleSha256

  test "recorded profile state: compileProfile + compileCommand carry the pin":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_rust_replay_state")
    let root = makeSubjectFixture("ax_rust_replay_profstate", RustSubject)
    let record = runRustCounterexampleReplay(violatedCfg(root))
    check record.verdict == rvAgree
    check record.compileProfile.contains("overflow-checks=on")
    check record.compileProfile.contains("debug-assertions=on")
    check record.compileCommand.contains("-C overflow-checks=on")
    check record.compileCommand.contains("-C debug-assertions=on")
    check record.compileCommand.contains("--edition 2021")
    # The measured identity rides the same record (one fingerprint, never
    # re-measured): identity + profile are the recorded profile state.
    check record.rustVersion.len > 0

  test "determinism: same overflow inputs twice → identical verdict + evidence class":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_rust_replay_state")
    let root = makeSubjectFixture("ax_rust_replay_det", RustSubject)
    var cfg = violatedCfg(root)
    cfg.inputLiterals = @["200", "56"]
    let r1 = runRustCounterexampleReplay(cfg)
    let r2 = runRustCounterexampleReplay(cfg)
    check r1.outcome == r2.outcome
    check r1.verdict == r2.verdict
    check r1.exitCode == r2.exitCode
    check r1.outcome == rroPanicked
    check r1.panicEvidence.contains("panicked at")
    check r2.panicEvidence.contains("panicked at")
    # Evidence CLASS is identical — same panic location, message and note.
    # The verbatim report differs only by the run-specific OS thread id the
    # Rust runtime embeds in the report header (`thread 'main' (58025)
    # panicked at …`) — a PID-like environment artifact, not evidence; the
    # record keeps the verbatim text, the determinism contract is the class.
    let class1 = r1.panicEvidence.substr(r1.panicEvidence.find("panicked at"))
    let class2 = r2.panicEvidence.substr(r2.panicEvidence.find("panicked at"))
    check class1 == class2

# ─── Suite 3: pipeline entry — replayConfirmedRustDisproof ──────────────────

suite "rust_replay_adapter — replayConfirmedRustDisproof (pipeline entry)":
  let propLeSeven = irLe(irVar("result", bv64), irLit(7))

  proc entryFuncDef(name: string): IRFuncDef =
    IRFuncDef(
      name: name,
      params: @[IRFuncParam(name: "a", ty: bv64, constraint: none(IRExpr)),
                IRFuncParam(name: "b", ty: bv64, constraint: none(IRExpr))],
      retType: bv64,
      body: irBinOp(boAdd, irVar("a", bv64), irVar("b", bv64)),
      postConditions: @[propLeSeven],
      symbolTable: SymbolTable(symbols: @[], nameIndex: initTable[string, int]()))

  test "agreement: exact inputs from the model reply, PROPOSITION_DISPROVED payload assembled":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_rust_replay_state")
    let root = makeSubjectFixture("ax_rust_replay_entry_agree", RustSubject)
    let modelRaw = "sat\n" &
                   "(define-fun a () (_ BitVec 64) " & bvHex(5) & ")\n" &
                   "(define-fun b () (_ BitVec 64) " & bvHex(3) & ")\n"
    let replay = replayConfirmedRustDisproof(root, "subject.rs",
                                             entryFuncDef("add_u8"), modelRaw)
    check replay.agreed
    check replay.diagnostics.len == 0
    # Exact input (element 2) + violation statement + replay record folds.
    check replay.payload.contains("input.a=5")
    check replay.payload.contains("input.b=3")
    check replay.payload.anyIt(it.startsWith("propertyViolated="))
    check replay.payload.anyIt(it == "replay.verdict=rvAgree")
    check replay.payload.anyIt(it.startsWith("replay.rustVersion="))

  test "partial model → exact-input fail-closed (defaulted input never replayed)":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_rust_replay_state")
    let root = makeSubjectFixture("ax_rust_replay_entry_partial", RustSubject)
    let modelRaw = "sat\n(define-fun a () (_ BitVec 64) " & bvHex(5) & ")\n"
    let replay = replayConfirmedRustDisproof(root, "subject.rs",
                                             entryFuncDef("add_u8"), modelRaw)
    check not replay.agreed
    check replay.payload.len == 0
    check replay.diagnostics ==
      "rvUnavailable:model does not bind parameter 'b' (exact-input required)"

  test "panic replay → NOT agreed (a panic never confirms a disproof)":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_rust_replay_state")
    let root = makeSubjectFixture("ax_rust_replay_entry_panic", RustSubject)
    let modelRaw = "sat\n" &
                   "(define-fun a () (_ BitVec 64) " & bvHex(200) & ")\n" &
                   "(define-fun b () (_ BitVec 64) " & bvHex(56) & ")\n"
    let replay = replayConfirmedRustDisproof(root, "subject.rs",
                                             entryFuncDef("add_u8"), modelRaw)
    # The overflow panic fail-closes: no PROPOSITION_DISPROVED payload is assembled from
    # a panic — only exit-0 observed disagreement confirms a disproof
    # (negative-control norm: in-domain, profile-independent evidence only).
    check not replay.agreed
    check replay.payload.len == 0
    check replay.diagnostics.contains("harness panicked")

# ─── Suite 4: BuildInvocation — the build identity + record consistency ─────

suite "rust_replay_adapter — rustBuildInvocation / rustReplayCommandMismatch (pure)":

  # The adapter's own harness layout (rust_replay_adapter.nim run path):
  # harnessPath = harnessDir / "replay_harness.rs", binPath =
  # harnessDir / "replay_harness_bin" — the layout the record-side defense
  # recomputes the command from.
  let HarnessDir = "/tmp/ax_inv_harness"
  let inv = rustBuildInvocation("/toolchains/measured/bin/rustc",
                                HarnessDir / "replay_harness.rs",
                                HarnessDir / "replay_harness_bin",
                                HarnessDir)

  test "cmdLine RECOMPUTES the pinned build command — the suite-1 template " &
      "strings unchanged, profile flags present":
    check inv.cmdLine == rustBuildCommand("/toolchains/measured/bin/rustc",
                                          HarnessDir / "replay_harness.rs",
                                          HarnessDir / "replay_harness_bin")
    check inv.cmdLine.contains("-C overflow-checks=on -C debug-assertions=on")
    check inv.cmdLine.contains("--edition 2021")
    check not inv.cmdLine.contains("nim")

  test "profileFlags == RustReplayProfileFlags; rustcToken + harnessDir " &
      "identity":
    check inv.profileFlags == RustReplayProfileFlags
    check inv.rustcToken == "/toolchains/measured/bin/rustc"
    check inv.harnessDir == HarnessDir

  test "rustReplayCommandMismatch: '' for a consistent record":
    var rec = RustReplayRecord()
    rec.compileCommand = inv.cmdLine
    rec.compileProfile = inv.profileFlags
    rec.harnessDir = inv.harnessDir
    check rustReplayCommandMismatch(inv, rec) == ""

  test "rustReplayCommandMismatch: non-empty diagnostic for a forged " &
      "compileProfile":
    var rec = RustReplayRecord()
    rec.compileCommand = inv.cmdLine
    rec.compileProfile = "-C overflow-checks=off -C debug-assertions=off"
    check rustReplayCommandMismatch(inv, rec).len > 0

  test "rustReplayCommandMismatch: non-empty diagnostic for a tampered " &
      "compileCommand":
    var rec = RustReplayRecord()
    rec.compileCommand = inv.cmdLine.replace("-C overflow-checks=on",
                                             "-C overflow-checks=off")
    rec.compileProfile = inv.profileFlags
    check rustReplayCommandMismatch(inv, rec).len > 0

# ─── Suite 5: worktree-stability predicate v2 (pure assembly) ───────────────

suite "rust_replay_adapter — worktree-stability predicate v2 (pure)":
  ## N3 negative-control unit matrix for the (b)/(c)(d) assembly + the
  ## relative decision (G2 "unchanged across the run" —
  ## replay_evidence_policy.md §4): pre==post holds, and an added entry,
  ## a removed entry, a path change and a content-only change each break
  ## exactly the component they belong to.

  test "subjectInputsDigestFrom: pre==post same entries → identical digest":
    let pre = rust_replay_adapter.subjectInputsDigestFrom(@[("a.rs", "aa"), ("b.txt", "bb")])
    let post = rust_replay_adapter.subjectInputsDigestFrom(@[("a.rs", "aa"), ("b.txt", "bb")])
    check pre.len == 64
    check pre == post

  test "subjectInputsDigestFrom: relpath-sorted — listing order never " &
      "moves the digest (determinism)":
    let x = rust_replay_adapter.subjectInputsDigestFrom(@[("b.txt", "bb"), ("a.rs", "aa")])
    let y = rust_replay_adapter.subjectInputsDigestFrom(@[("a.rs", "aa"), ("b.txt", "bb")])
    check x == y

  test "subjectInputsDigestFrom: a NEW entry moves the digest (N1a)":
    let pre = rust_replay_adapter.subjectInputsDigestFrom(@[("subject.rs", "aa")])
    let post = rust_replay_adapter.subjectInputsDigestFrom(@[("drift_new.txt", "cc"),
                                         ("subject.rs", "aa")])
    check post != pre

  test "subjectInputsDigestFrom: a REMOVED entry moves the digest":
    let pre = rust_replay_adapter.subjectInputsDigestFrom(@[("a.rs", "aa"), ("b.txt", "bb")])
    let post = rust_replay_adapter.subjectInputsDigestFrom(@[("a.rs", "aa")])
    check post != pre

  test "subjectInputsDigestFrom: a PATH change (rename) moves the digest " &
      "at identical content":
    let pre = rust_replay_adapter.subjectInputsDigestFrom(@[("old.txt", "cc")])
    let post = rust_replay_adapter.subjectInputsDigestFrom(@[("new.txt", "cc")])
    check post != pre

  test "subjectInputsDigestFrom: a CONTENT-only change moves the digest " &
      "(N1b — status line and tracked diff never move for an untracked " &
      "overwrite)":
    let pre = rust_replay_adapter.subjectInputsDigestFrom(@[("drift_seed.txt", "dd"),
                                        ("subject.rs", "aa")])
    let post = rust_replay_adapter.subjectInputsDigestFrom(@[("drift_seed.txt", "ee"),
                                         ("subject.rs", "aa")])
    check post != pre

  test "combineFootprintDigest: fixed-order composition; each component " &
      "moves the fold":
    let s1 = sha256Hex(" M stamp\n")
    let s2 = sha256Hex("?? untracked\n")
    let d1 = sha256Hex("diff-a")
    let d2 = sha256Hex("diff-b")
    check rust_replay_adapter.combineFootprintDigest(s1, d1) == rust_replay_adapter.combineFootprintDigest(s1, d1)
    check rust_replay_adapter.combineFootprintDigest(s1, d1) != rust_replay_adapter.combineFootprintDigest(s2, d1)  # (c) moves
    check rust_replay_adapter.combineFootprintDigest(s1, d1) != rust_replay_adapter.combineFootprintDigest(s1, d2)  # (d) moves
    check rust_replay_adapter.combineFootprintDigest(s1, d1) != rust_replay_adapter.combineFootprintDigest(d1, s1)  # order is fixed

  test "rustWorktreeStable: pre==post on every relative pair → stable":
    check rust_replay_adapter.rustWorktreeStable("m", "m", "s", "s", "f", "f")

  test "rustWorktreeStable: ANY side moving is fail-closed (per component)":
    check not rust_replay_adapter.rustWorktreeStable("m", "m2", "s", "s", "f", "f")   # (a) module bytes
    check not rust_replay_adapter.rustWorktreeStable("m", "m", "s", "s2", "f", "f")   # (b) subject inputs
    check not rust_replay_adapter.rustWorktreeStable("m", "m", "s", "s", "f", "f2")   # (c)+(d) repo footprint

  test "rustWorktreeStable: pre-existing noise folded on BOTH sides never " &
      "seals (the restoration — dirty-but-stable confirms)":
    # The stale build stamp / untracked file of
    # build_metadata_stamp_porcelain_quirk.md: the noise moves every
    # PRE digest, but the POST digests move identically — the relative
    # equality is unaffected, exactly as the G2 contract states.
    let noisy = sha256Hex(" M src/generated/build_metadata.json\n?? scratch.txt\n")
    check rust_replay_adapter.rustWorktreeStable(noisy, noisy, noisy, noisy, noisy, noisy)
