import core/trusted/layer_declaration
axiomLayer "infrastructure"
# axiomIoBoundary — S5 Rust counterexample replay executes real subprocess I/O
# (`rustc` harness compile + run, read-only git queries, file hashing).
# Declared-marker resolution (io_module_registry is a FROZEN surface — same
# resolution the Nim adapter documents): every I/O proc carries an explicit
# axiomEffect pragma — §0.6 permits proc at the I/O boundary.
{.push raises: [].}
## Rust Counterexample Replay Execution Adapter (PROPOSITION_DISPROVED S4-S5, Rust
## subject partition — `feat/rust-subject-v1`).
##
## Language-partitioned sibling of `verification/counterexample_replay.nim`.
## The Nim path stays byte-stable; this module ADDS a Rust-specific execution
## adapter alongside it and plugs into the SAME fail-closed gate
## (`batch_uap/ir_pipeline_runner.nim:1450-1458` — no PROPOSITION_DISPROVED from solver
## sat alone; replay disagreement downgrades `vsDisproved` to
## `makeInconclusive(rkCandidateCounterexample)`). No new gate, no new
## authority, no new SHARED verdict vocabulary: this adapter REUSES
## `ReplayVerdict` (`rvAgree`/`rvDisagree`/`rvUnavailable`), the
## `AXIOM_REPLAY_BEGIN/END` marker protocol, `parseConcreteLiteral`,
## `evalConcreteIr`/`evaluatePostconditions` and `decideReplayVerdict`
## verbatim from the Nim module — output parsing and concrete re-evaluation
## are language-neutral. On top of the shared vocabulary the Rust record
## carries ONE internal, lossless outcome classification
## (`RustReplayOutcome`): it adds `rroPanicked` — the harness binary itself
## panicked at run time (exit 101 + the Rust panic report), which the shared
## 3-value enum has no room for. `record.verdict` stays the shared-vocabulary
## projection (a panic folds to `rvUnavailable` — never agreed, fail-closed
## for every existing consumer); `record.outcome` is the lossless lane state.
##
## What the adapter does, end to end (mirror of the Nim adapter):
##   1. fold the replay record identity: subjectGitRef, treeMerkle,
##      moduleSha256 (+ post-run re-hash), the worktree-stability predicate
##      (worktreeStable — subject inputs + repo status + tracked content,
##      RELATIVE pre/post equality, never a repo-wide clean requirement),
##      hostPlatformId,
##      and the Rust toolchain identity — MEASURED, not declared:
##      rustcVersion, rustc binary hash, sysroot `lib/rustlib/components`
##      hash (the measured install set) + parsed components, active channel,
##      and rustup profile (docs/spec/rust_toolchain_quirks.md Q1 — the pin
##      file alone under-determines the environment; profile and installed
##      component set are ambient and MUST be recorded);
##   2. synthesize a `.rs` harness under the AXIOM_STATE_DIR tmp tree that
##      splices the subject source via `include!("<abs path>")` — the subject
##      tree is never written;
##   3. compile with `rustc --edition 2021` PINNED to the extraction profile
##      (`-C overflow-checks=on -C debug-assertions=on` — the consumed LLBC's
##      `AddChecked` / `Assert{check_kind: Overflow, on_failure: Panic}`
##      lowering is the structural witness that the extraction rustc ran with
##      overflow checks enabled, docs/spec/rust_toolchain_quirks.md Q5; the
##      flags remove the dependence on rustc's emergent opt-level-derived
##      defaults), run the harness binary, and capture the observed output +
##      exit code (same marker protocol; a harness panic is classified as
##      the DISTINCT outcome `rroPanicked` with its evidence text —
##      observation only, never an agreement);
##   4. re-evaluate the violated postconditions concretely on the observed
##      result (`evaluatePostconditions`) — `propertyHolds == false` is the
##      replay agreement (the real toolchain reproduced the violation).
##
## Fail-closed: toolchain not found, declared pin unverifiable/violated,
## harness compile failure, harness panic, output marker missing,
## input/param arity mismatch, unparsable literal, property outside the
## certified subset, post-run subject drift — every one collapses to
## `rvUnavailable` + `diagnostics` in the shared vocabulary (a panic keeps
## its distinct `rroPanicked` outcome + `panicEvidence` on the record).
## `pure` functions never raise. Nothing here writes into the subject tree
## or the CAS — a failed replay is not reusable evidence.
##
## Acceptance anchor: a Rust execution result observed by THIS adapter is
## the only Rust lane evidence that may accompany a PROPOSITION_DISPROVED; sat alone
## must never promote (unchanged rule).

import std/[algorithm, options, os, osproc, strutils, tables]

import core/trusted/axiom_pragmas
import core/trusted/axiom_ir
import core/crypto/hash_kernel
import core/types/obligation_evidence  # ModelBinding / parseModelBindings
import core/trusted/ir_to_smt  # irExprToSmt — propertyViolated SMT projection
import verification/obligation/identity  # hostPlatformId
# Reused without change from counterexample_replay: ReplayVerdict (rv*),
# ReplayBeginMarker/ReplayEndMarker, ConcreteValue, parseConcreteLiteral,
# evaluatePostconditions, decideReplayVerdict, inputLiteralsPayload.
import verification/counterexample_replay
import verification/rust_symbolic_test_synth  # exact-input gate + Rust literals

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  RustReplayConfig* = object
    subjectRepoRoot*: string    ## git root of the subject ("" → discovered via git)
    subjectModulePath*: string  ## absolute path of the subject .rs file
    funcName*: string
    paramNames*: seq[string]    ## subject parameter names, positional order
    inputLiterals*: seq[string] ## Rust source literals, positional
                                ## (model → modelToRustTestInputs)
    paramBool*: seq[bool] = @[] ## positional bool-parameter flags from the
                                ## canonical (v1.4 bool-expression row). The IR
                                ## keeps ONE value sort (bitVec64), so a bool
                                ## model value arrives as "0"/"1"; the harness
                                ## call site needs the SOURCE type to render
                                ## `false`/`true`. Empty → all non-bool (the
                                ## pre-v1.4 callers' exact behavior).
    postconditions*: seq[IRExpr]## the violated property conjuncts (concretely re-evaluated)
    pinnedChannel*: string = "" ## declared toolchain pin ("stable",
                                ## "nightly-2026-09-17", …). "" → no pin check
                                ## (identity is still measured + recorded).
                                ## Non-empty → the MEASURED active channel
                                ## must name the pin, else fail-closed.
    rustcExe*: string = ""      ## explicit rustc path; "" → findExe("rustc")

  RustToolchainFingerprint* = object
    ## Measured Rust toolchain identity — the GateEnvLock mirror
    ## (nimToolchainFingerprint analogue). Every field is measured at run
    ## time; an absent measurement is folded as "" (the absent fold IS the
    ## diagnostic, never a silent pass).
    rustcPath*: string          ## command token executed ("rustc" PATH
                                ## dispatch preserving rustup multi-call
                                ## dispatch, or the explicit path;
                                ## "" → toolchain not found)
    rustVersion*: string        ## `rustc --version` first line
    rustcHash*: string          ## sha256 of the toolchain rustc binary
                                ## (<sysroot>/bin/rustc; the PATH entry may be
                                ## the rustup proxy, so the sysroot binary is
                                ## the one hashed when present)
    sysroot*: string            ## `rustc --print sysroot`
    componentsHash*: string     ## sha256 of <sysroot>/lib/rustlib/components —
                                ## the measured install set (quirks Q1)
    components*: seq[string]    ## measured installed components, file order
    channel*: string            ## measured active channel
                                ## (`rustup show active-toolchain`, target
                                ## triple retained; "" when rustup unavailable)
    profile*: string            ## measured rustup profile
                                ## (`rustup show profile`; "" when unavailable)

  RustReplayOutcome* = enum
    ## Lossless Rust-lane outcome classification — the record-level SUPERSET
    ## of the shared `ReplayVerdict`: adds `rroPanicked` (the harness binary
    ## itself panicked: exit 101 + the Rust panic report), which the shared
    ## 3-value enum has no room for (its home module is shared with the Nim
    ## lane and stays untouched). `RustReplayRecord.verdict` remains the
    ## shared-vocabulary PROJECTION of this classification — a panic folds
    ## to `rvUnavailable` there, so every existing consumer fail-closes —
    ## while `outcome` is the lane's own lossless state.
    rroAgree        ## violation reproduced on the real toolchain
    rroDisagree     ## property holds on the observed result — model contradicted
    rroUnavailable  ## observation could not be established (fail-closed fold)
    rroPanicked     ## harness panicked at run time (exit 101 + panic report) —
                    ## evidence about the profile, NEVER an agreement (a panic
                    ## is not an in-domain counterexample observation)

  RustReplayRecord* = object
    verdict*: ReplayVerdict     ## shared-vocabulary projection of `outcome`
                                ## (a panic folds to rvUnavailable — never
                                ## agreed, fail-closed for existing consumers)
    exitCode*: int              ## harness binary exit code (rustc exit code
                                ## when the compile itself failed)
    observedOutput*: string     ## verbatim harness stdout/stderr (trimmed)
    harnessDir*: string
    outcome*: RustReplayOutcome ## lossless lane classification (verdict is its
                                ## shared-vocabulary projection)
    panicEvidence*: string      ## verbatim Rust panic report ("" when outcome
                                ## != rroPanicked) — observation only, never
                                ## an agreement
    compileProfile*: string     ## the pinned compile profile — the `-C` flags
                                ## that pin the replay to the extraction
                                ## profile (docs/spec/rust_toolchain_quirks.md
                                ## Q5: the AddChecked structural witness)
    compileCommand*: string     ## the exact rustc invocation executed (measured
                                ## rustc dispatch token + pinned profile)
    ## Rust toolchain identity — measured by the ONE `rustToolchainFingerprint`
    ## call that also supplies the build's rustc dispatch token (never
    ## re-measured differently); the recorded identity pairs with
    ## `compileProfile` as the replay's profile state (quirks doc Q5)
    rustVersion*: string
    rustcHash*: string
    componentsHash*: string
    rustChannel*: string
    rustProfile*: string
    rustComponents*: seq[string]
    declaredPin*: string        ## cfg.pinnedChannel fold ("" → unpinned run)
    hostPlatform*: string       ## identity.hostPlatformId fold
    subjectGitRef*: string      ## exact subject commit (PROPOSITION_DISPROVED element 1)
    subjectTreeMerkle*: string  ## git tree OID of the subject commit
    moduleSha256*: string       ## sha256 of subject source bytes before the run
    moduleSha256AfterRun*: string  ## re-hash after the run — drift detection
    worktreeStable*: bool       ## worktree state unchanged across the run
                                ## (subject inputs + repo status + repo
                                ## tracked content — RELATIVE pre/post
                                ## equality, predicate v2; pre-existing
                                ## noise is on both sides and cannot break
                                ## the seal)
    subjectInputsPre*: string   ## (b) subject-inputs digest sha256, pre-run
    subjectInputsPost*: string  ## (b) subject-inputs digest sha256, post-run
    repoFootprintPre*: string   ## (c)+(d) combined repo-footprint sha256, pre-run
    repoFootprintPost*: string  ## (c)+(d) combined repo-footprint sha256, post-run
    diagnostics*: string        ## first failure reason ("" when verdict == rvAgree)

  RustBuildInvocation* = object
    ## The ONE immutable compile invocation: built once, executed, and recorded
    ## from the same object (no independent re-derivation on the record path).
    cmdLine*: string       ## exact rustc invocation execCmdEx runs
    profileFlags*: string  ## pinned -C profile (== RustReplayProfileFlags)
    rustcToken*: string    ## measured dispatch token (toolchain.rustcPath)
    harnessDir*: string

# ---------------------------------------------------------------------------
# Harness synthesis (pure string building)
# ---------------------------------------------------------------------------

func rustStringLiteral(s: string): string {.raises: [].} =
  ## Render `s` as a Rust string literal (backslash + quote escaping; paths
  ## are spliced verbatim otherwise).
  result = "\""
  for c in s:
    case c
    of '\\': result.add("\\\\")
    of '\"': result.add("\\\"")
    else: result.add(c)
  result.add("\"")

func rustHarnessLiteral(lit: string; isBool: bool): string {.raises: [].} =
  ## Replay call-site literal. A bool parameter arrives from the IR model as
  ## "0"/"1" (the IR keeps ONE bitVec64 value sort — the v1.4 Bool 0/1
  ## embed), but the Rust call site needs `false`/`true`; already-boolean
  ## literals pass through. Any other value for a bool parameter is not a
  ## Rust bool literal — "" means unplayable (the renderer refuses).
  if not isBool:
    return lit
  case lit
  of "0", "false": "false"
  of "1", "true": "true"
  else: ""

func renderRustReplayHarness*(subjectSourceAbsPath: string; funcName: string;
                              inputLiterals: seq[string];
                              paramBool: seq[bool] = @[]): string {.raises: [].} =
  ## The wrapper body: splices the subject source file into the harness crate
  ## root via `include!` (resolved at compile time from the absolute path —
  ## the subject tree is never written), calls the subject function with the
  ## exact model input, and echoes the observed result between the SAME
  ## markers the Nim adapter parses. Plain (non-pub) subject fns are visible
  ## because `include!` splices them into the crate root — no `pub` rewrite
  ## of the subject is ever needed. `paramBool` (positional, from the
  ## canonical) selects the bool call-site rendering; "" is returned when any
  ## literal is unplayable so the caller fails closed instead of emitting a
  ## source that cannot compile.
  var args = ""
  for i, lit in inputLiterals:
    if i > 0:
      args.add(", ")
    let rendered = rustHarnessLiteral(lit, i < paramBool.len and paramBool[i])
    if rendered.len == 0:
      return ""
    args.add(rendered)
  "include!(" & rustStringLiteral(subjectSourceAbsPath) & ");\n" &
  "fn main() {\n" &
  "    println!(" & rustStringLiteral(ReplayBeginMarker) & ");\n" &
  "    println!(\"{}\", " & funcName & "(" & args & "));\n" &
  "    println!(" & rustStringLiteral(ReplayEndMarker) & ");\n" &
  "}\n"

const RustReplayProfileFlags* = "-C overflow-checks=on -C debug-assertions=on"
  ## The replay compile profile, PINNED to the extraction profile. WHY: the
  ## consumed LLBC's `AddChecked` + `Assert{check_kind: Overflow,
  ## on_failure: Panic}` lowering is the STRUCTURAL WITNESS that the
  ## extraction rustc ran with overflow checks enabled (an overflow-checks-off
  ## extraction lowers plain `BinaryOp["Add"]` with no Assert, and
  ## `llbc_to_canonical` rejects that form out-of-grammar — fail-closed), so
  ## the replay harness MUST run the same arithmetic semantics. Without the
  ## flags the match is emergent: rustc derives debug-assertions from
  ## opt-level (`cg.debug_assertions.unwrap_or(opt_level == OptLevel::No)`)
  ## and overflow checks from debug-assertions when unset — both were on only
  ## because this invocation happens to be non-optimized. `on` is a
  ## documented value of both boolean codegen options (rustc book,
  ## codegen-options); the Rust Reference: with debug assertions enabled,
  ## implementations MUST insert dynamic checks that panic on overflow
  ## (RFC 560). docs/spec/rust_toolchain_quirks.md Q5.

func rustBuildCommand*(rustcExe: string; harnessPath: string;
                       binPath: string): string {.raises: [].} =
  ## Build command template: `rustc --edition 2021 -Awarnings` + the pinned
  ## replay profile (`RustReplayProfileFlags`) — NOT `nim c -r`. `-Awarnings`
  ## mirrors the Nim adapter's `--warnings:off` — compiler noise must not
  ## masquerade as observation; the `-C` flags pin the overflow-check profile
  ## instead of trusting rustc's emergent defaults (the AddChecked witness —
  ## see the const above). Edition and `-Awarnings` are unchanged from the
  ## pre-pin invocation; only the profile flags were added. The harness
  ## binary is emitted under the harness dir, then executed as a separate
  ## step so a compile failure is distinguishable from a harness run failure
  ## (both fail closed, with distinct diagnostics).
  "\"" & rustcExe & "\" --edition 2021 -Awarnings " & RustReplayProfileFlags &
    " -o \"" & binPath & "\"" &
    " \"" & harnessPath & "\""

func rustBuildInvocation*(rustcToken, harnessPath, binPath,
                          harnessDir: string): RustBuildInvocation {.raises: [].} =
  ## Assemble the ONE compile invocation from the measured dispatch token:
  ## `cmdLine` is exactly what `execCmdEx` runs, `profileFlags` is the pinned
  ## replay profile, and `rustcToken`/`harnessDir` carry the identity the
  ## record-side defense (`rustReplayCommandMismatch`) needs to recompute the
  ## command independently. `rustBuildCommand` stays the recomputation
  ## primitive (test-pinned); this constructor binds execution and record fold
  ## to the SAME object — the record path never re-derives the command.
  RustBuildInvocation(
    cmdLine: rustBuildCommand(rustcToken, harnessPath, binPath),
    profileFlags: RustReplayProfileFlags,
    rustcToken: rustcToken,
    harnessDir: harnessDir)

# ---------------------------------------------------------------------------
# Observation parsing + agreement decision (pure — fail-closed)
# ---------------------------------------------------------------------------

func rustReplayCommandMismatch*(invocation: RustBuildInvocation;
                                record: RustReplayRecord): string {.raises: [].} =
  ## Evidence-integrity defense over the record pair: "" iff the recorded
  ## compile pair IS the one executed invocation — `compileCommand` equals the
  ## executed `cmdLine`, `compileProfile` equals the executed profile flags,
  ## AND an independent recomputation of the command from the recorded
  ## dispatch token + harness layout (`rustBuildCommand`) reproduces the
  ## recorded command. Any divergence returns a short diagnostic naming the
  ## mismatched member(s); the caller folds to rvUnavailable (observer-only —
  ## never a false agreement, never a panic).
  var members: seq[string] = @[]
  if record.compileCommand != invocation.cmdLine:
    members.add("recorded compileCommand != executed cmdLine")
  if record.compileProfile != invocation.profileFlags:
    members.add("recorded compileProfile != executed profileFlags")
  let recomputed = rustBuildCommand(invocation.rustcToken,
                                    invocation.harnessDir / "replay_harness.rs",
                                    invocation.harnessDir / "replay_harness_bin")
  if recomputed != record.compileCommand:
    members.add("recomputed rustc command != recorded compileCommand")
  if members.len == 0:
    return ""
  "replay build invocation mismatch: " & members.join("; ")

func extractObservedResult(output: string): Option[string] {.raises: [].} =
  ## Value echoed between the harness markers ("" marker lines excluded) —
  ## same protocol, same parsing shape as the Nim adapter.
  let lines = output.splitLines()
  var inBlock = false
  for line in lines:
    let t = line.strip()
    if t == ReplayBeginMarker:
      inBlock = true
      continue
    if t == ReplayEndMarker:
      if inBlock:
        return none(string)  # no value line between markers
      continue
    if inBlock and t.len > 0:
      return some(t)
  none(string)

const RustPanicExitCode = 101
  ## The Rust runtime exits 101 when the harness binary panics. The compile
  ## step is a separate rustc process whose failures land in the
  ## "harness compile failed" path before this projection can run — so a
  ## post-compile exit 101 is the harness's own runtime panic (a compiler
  ## ICE also exits 101, but on the BUILD step, classified earlier).

const RustPanicMarker = "panicked at"
  ## Stable prefix of the Rust panic report line ("thread '<name>' panicked
  ## at <location>: ...") — carried verbatim by both the pre-1.73 and the
  ## current report formats.

func harnessPanicked(exitCode: int; output: string): bool {.raises: [].} =
  ## Distinct panic classification: the harness binary exited 101 AND its
  ## captured output carries the Rust panic report marker. Runtime-only by
  ## construction — see RustPanicExitCode.
  exitCode == RustPanicExitCode and output.contains(RustPanicMarker)

func rustPanicEvidence(output: string): string {.raises: [].} =
  ## The panic report proper: from the first panic-marker line to the end of
  ## the capture (the BEGIN marker echo may precede it on stdout; the report
  ## follows on the merged stderr). "" when no marker — the caller only
  ## invokes this on a `harnessPanicked` classification.
  let lines = output.splitLines()
  for i, ln in lines:
    if ln.contains(RustPanicMarker):
      return lines[i .. ^1].join("\n").strip()
  ""

func decideRustReplayAgreement(cfg: RustReplayConfig; rawOutput: string;
                               record: var RustReplayRecord) {.raises: [].} =
  ## Agreement decision — pure projection over the observation: the violated
  ## postconditions are re-evaluated concretely on the observed result
  ## (evaluatePostconditions / evalConcreteIr — language-neutral). `false`
  ## (violation reproduced) is the PROPOSITION_DISPROVED agreement.
  let observed = extractObservedResult(rawOutput)
  if observed.isNone:
    record.diagnostics = "harness output missing " & ReplayBeginMarker & "/" & ReplayEndMarker & " value"
    record.verdict = rvUnavailable
    return
  let paramCount = min(cfg.paramNames.len, cfg.inputLiterals.len)
  if paramCount != cfg.paramNames.len or paramCount != cfg.inputLiterals.len:
    record.diagnostics = "input/param arity mismatch"
    record.verdict = rvUnavailable
    return
  var env = initTable[string, ConcreteValue]()
  for i, lit in cfg.inputLiterals:
    let v = parseConcreteLiteral(lit)
    if v.isNone:
      record.diagnostics = "input literal unparsable: " & lit
      record.verdict = rvUnavailable
      return
    env[cfg.paramNames[i]] = v.get
  let observedVal = parseConcreteLiteral(observed.get)
  if observedVal.isNone:
    record.diagnostics = "observed result unparsable: " & observed.get
    record.verdict = rvUnavailable
    return
  env["result"] = observedVal.get
  let holds = evaluatePostconditions(cfg.postconditions, env)
  record.verdict = decideReplayVerdict(harnessRan = true, propertyHolds = holds)
  # Lossless lane classification — the exhaustive projection of the shared
  # verdict onto the outcome superset. No silent default: the case covers
  # the FULL shared enum, so a future shared value is a compile error here
  # (fail-closed by construction), and no consumer of `outcome` can inherit
  # an unmapped verdict.
  record.outcome = case record.verdict
    of rvAgree: rroAgree
    of rvDisagree: rroDisagree
    of rvUnavailable: rroUnavailable
  if record.verdict == rvUnavailable:
    record.diagnostics = "property not concretely evaluable (outside certified subset)"
  elif record.verdict == rvDisagree:
    record.diagnostics = "property holds on observed result — replay disagrees with solver model"

# ---------------------------------------------------------------------------
# PROPOSITION_DISPROVED payload projection (pure)
# ---------------------------------------------------------------------------

func rustReplayRecordPayload*(record: RustReplayRecord): seq[string] {.raises: [].} =
  ## Replay record folds (PROPOSITION_DISPROVED element 4) for the Rust partition: the
  ## shared folds plus the measured Rust toolchain identity (version, binary
  ## hash, measured component-set hash + set, channel, profile, declared
  ## pin). Deterministic emission order.
  result = @[]
  result.add("replay.verdict=" & $record.verdict)
  result.add("replay.exitCode=" & $record.exitCode)
  result.add("replay.subjectGitRef=" & record.subjectGitRef)
  result.add("replay.treeMerkle=" & record.subjectTreeMerkle)
  result.add("replay.moduleSha256=" & record.moduleSha256)
  result.add("replay.moduleSha256AfterRun=" & record.moduleSha256AfterRun)
  result.add("replay.worktreeStable=" & $record.worktreeStable)
  result.add("replay.subjectInputsPre=" & record.subjectInputsPre)
  result.add("replay.subjectInputsPost=" & record.subjectInputsPost)
  result.add("replay.repoFootprintPre=" & record.repoFootprintPre)
  result.add("replay.repoFootprintPost=" & record.repoFootprintPost)
  result.add("replay.rustVersion=" & record.rustVersion)
  result.add("replay.rustcHash=" & record.rustcHash)
  result.add("replay.componentsHash=" & record.componentsHash)
  result.add("replay.rustChannel=" & record.rustChannel)
  result.add("replay.rustProfile=" & record.rustProfile)
  result.add("replay.rustComponents=" & record.rustComponents.join(","))
  result.add("replay.rustDeclaredPin=" & record.declaredPin)
  result.add("replay.hostPlatform=" & record.hostPlatform)
  if record.diagnostics.len > 0:
    result.add("replay.diagnostics=" & record.diagnostics.replace('\n', ' '))

# ---------------------------------------------------------------------------
# Worktree-stability predicate v2 (pure assembly — unit-tested)
# ---------------------------------------------------------------------------

func subjectInputsDigestFrom*(entries: seq[tuple[relPath, fileSha: string]]): string {.
    raises: [].} =
  ## The (b) subject-inputs digest: "relPath:fileSha256\n" lines sorted by
  ## relPath and hashed WHOLE. Pure over the already-measured pairs — the
  ## I/O boundary runs `git ls-files --full-name --cached --others
  ## --exclude-standard` over the subject project root and hashes each
  ## file. An added entry, a removed entry, a renamed path (relPath moves)
  ## and a content-only change (fileSha moves) each move this digest —
  ## which is how a run-made overwrite of a pre-existing UNTRACKED file is
  ## detected even though the status line and the tracked diff never move.
  var ordered = entries
  ordered.sort(proc (a, b: tuple[relPath, fileSha: string]): int =
    if a.relPath < b.relPath: -1
    elif b.relPath < a.relPath: 1
    else: 0)
  var acc = ""
  for e in ordered:
    acc.add(e.relPath & ":" & e.fileSha & "\n")
  sha256Hex(acc)

func combineFootprintDigest*(statusSha, trackedDiffSha: string): string {.
    raises: [].} =
  ## The (c)+(d) repo-footprint fold: sha256 over the two component digests
  ## in FIXED order (status, tracked diff). The components are measured
  ## separately — `git status --porcelain --untracked-files=all` (the -uall
  ## fold is required: the default collapses untracked directories, hiding
  ## run-made files) and `git diff HEAD --no-color --no-renames
  ## --no-ext-diff` (tracked content) — so neither can mask the other.
  sha256Hex("status=" & statusSha & ";tracked=" & trackedDiffSha)

func rustWorktreeStable*(moduleShaPre, moduleShaPost, subjectInputsPre,
                         subjectInputsPost, repoFootprintPre,
                         repoFootprintPost: string): bool {.raises: [].} =
  ## Predicate v2 — the G2 condition "the subject tree is unchanged across
  ## the run" (replay_evidence_policy.md §4) as RELATIVE pre/post equality
  ## over (a) the subject module sha256, (b) the subject-inputs digest and
  ## (c)+(d) the combined repo footprint. Pre-existing worktree noise (a
  ## stale build stamp, untracked files) is present on BOTH sides of every
  ## comparison and can never break the seal; only drift the run itself
  ## made moves one side. This is a redefinition of what counts as drift,
  ## NOT a path exemption — nothing is ignored.
  moduleShaPre == moduleShaPost and
  subjectInputsPre == subjectInputsPost and
  repoFootprintPre == repoFootprintPost

# ---------------------------------------------------------------------------
# I/O boundary — measurements and subject binding
# ---------------------------------------------------------------------------

proc measuredFileSha256(path: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## sha256 of file bytes ("" when unreadable).
  try:
    if not fileExists(path):
      return ""
    sha256Hex(readFile(path))
  except CatchableError:
    ""

proc gitCapture(args: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Read-only git query output ("" on failure). Never mutates the subject.
  try:
    let (outp, code) = execCmdEx("git " & args, options = {poStdErrToStdOut, poUsePath})
    if code == 0:
      outp.strip()
    else:
      ""
  except CatchableError:
    ""

proc subjectRepoRootFor(modulePath: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Git worktree root containing the subject source ("" when not a repo).
  let dir = if dirExists(modulePath): modulePath else: modulePath.parentDir()
  gitCapture("-C \"" & dir & "\" rev-parse --show-toplevel")

proc subjectProjectRootFor(modulePath, repoRoot: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## The subject project root for the (b) inputs digest: the first ancestor
  ## directory of the module (walking UP from the module's directory toward
  ## the repo root, repo root included) that carries a `Cargo.toml` — the
  ## crate boundary the subject belongs to. Fallback when no manifest is
  ## found: the module's parent directory (bare-subject materializations).
  var dir = if dirExists(modulePath): modulePath else: modulePath.parentDir()
  let fallback = dir
  while dir.len > 0:
    try:
      if fileExists(dir / "Cargo.toml"):
        return dir
    except CatchableError:
      discard  # axiom:best-effort(an unreadable dir contributes no manifest hit — the fallback below is the recorded behavior)
    if dir == repoRoot:
      break
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  fallback

proc measureSubjectInputsDigest(repoRoot, subjectProjectRoot: string): string {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## (b): `git ls-files --full-name --cached --others --exclude-standard`
  ## over the subject project root (read-only), each listed file hashed,
  ## assembled by the pure `subjectInputsDigestFrom` (relpath-sorted,
  ## whole-digest sha256). Never mutates the subject.
  let listing = gitCapture("-C \"" & repoRoot &
    "\" ls-files --full-name --cached --others --exclude-standard -- \"" &
    subjectProjectRoot & "\"")
  var entries: seq[tuple[relPath, fileSha: string]] = @[]
  for rel in listing.splitLines():
    let t = rel.strip()
    if t.len == 0:
      continue
    entries.add((t, measuredFileSha256(joinPath(repoRoot, t))))
  subjectInputsDigestFrom(entries)

proc measureRepoFootprintDigest(repoRoot: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## (c)+(d): the repo status output (`status --porcelain
  ## --untracked-files=all` — -uall so run-made files inside untracked
  ## directories stay visible) and the tracked-content diff output
  ## (`diff HEAD --no-color --no-renames --no-ext-diff`), hashed separately
  ## and combined in fixed order by `combineFootprintDigest`. Read-only.
  let statusOut = gitCapture("-C \"" & repoRoot &
    "\" status --porcelain --untracked-files=all")
  let diffOut = gitCapture("-C \"" & repoRoot &
    "\" diff HEAD --no-color --no-renames --no-ext-diff")
  combineFootprintDigest(sha256Hex(statusOut), sha256Hex(diffOut))

proc rustcCapture(rustcExe: string; args: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Read-only rustc query output ("" on failure).
  try:
    let (outp, code) = execCmdEx("\"" & rustcExe & "\" " & args,
                                options = {poStdErrToStdOut, poUsePath})
    if code == 0:
      outp.strip()
    else:
      ""
  except CatchableError:
    ""

proc rustupCapture(args: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Read-only rustup query output ("" when rustup is absent — the empty fold
  ## is the recorded identity gap, never a silent pass).
  try:
    let rustupExe = findExe("rustup")
    if rustupExe.len == 0:
      return ""
    let (outp, code) = execCmdEx("\"" & rustupExe & "\" " & args,
                                options = {poStdErrToStdOut, poUsePath})
    if code == 0:
      outp.strip()
    else:
      ""
  except CatchableError:
    ""

proc rustToolchainFingerprint*(explicitRustc: string): RustToolchainFingerprint {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Measure the Rust toolchain identity (channel + components + profile —
  ## the measured install set, not just the declared pin;
  ## docs/spec/rust_toolchain_quirks.md Q1). An empty `rustcPath` result IS
  ## the "toolchain not found" diagnostic — the caller fails closed.
  ##
  ## Measured dispatch hazard (findExe symlink resolution, 2026-10-12): Nim
  ## `findExe("rustc")` resolves the rustup shim symlink
  ## (`~/.cargo/bin/rustc → rustup`) to its multi-call target, and exec'ing
  ## THAT path makes rustup dispatch on argv[0] as the rustup CLI
  ## (`error: unexpected argument '--edition' found … Usage: rustup[EXE]`).
  ## Presence is therefore checked via findExe, but every query and the
  ## build execute the bare PATH name (poUsePath), which preserves the
  ## multi-call dispatch; the fingerprint hashes the REAL toolchain binary
  ## `<sysroot>/bin/rustc` (the PATH entry is the byte-identical dispatcher
  ## for every toolchain — not a rustc identity). Doc registration at the
  ## rust_toolchain_quirks.md registry linkage is a scoped follow-up.
  var rustcToken = ""
  try:
    if explicitRustc.len > 0:
      if fileExists(explicitRustc):
        rustcToken = explicitRustc
    else:
      if findExe("rustc").len > 0:
        rustcToken = "rustc"
  except CatchableError:
    rustcToken = ""  # axiom:best-effort(absent rustc is recorded as the diagnostic, never a silent pass)
  if rustcToken.len == 0:
    return RustToolchainFingerprint()
  result.rustcPath = rustcToken
  let versionLine = rustcCapture(rustcToken, "--version")
  let lines = versionLine.splitLines()
  if lines.len > 0:
    result.rustVersion = lines[0].strip()
  result.sysroot = rustcCapture(rustcToken, "--print sysroot")
  # Hash the REAL toolchain binary from the sysroot — the PATH entry is the
  # rustup dispatcher (byte-identical across toolchains). An unmeasurable
  # sysroot folds "" (the recorded gap), never a dispatcher-hash masquerade.
  var binaryPath = ""
  if result.sysroot.len > 0:
    let sysrootBinary = result.sysroot / "bin" / "rustc"
    if fileExists(sysrootBinary):
      binaryPath = sysrootBinary
  elif rustcToken != "rustc":
    binaryPath = rustcToken  # explicit caller-provided rustc path
  result.rustcHash = measuredFileSha256(binaryPath)
  # Measured install set: <sysroot>/lib/rustlib/components + parsed entries.
  if result.sysroot.len > 0:
    let componentsFile = result.sysroot / "lib" / "rustlib" / "components"
    try:
      if fileExists(componentsFile):
        let raw = readFile(componentsFile)
        result.componentsHash = sha256Hex(raw)
        for ln in raw.splitLines():
          let t = ln.strip()
          if t.len > 0:
            result.components.add(t)
    except CatchableError:
      discard  # axiom:best-effort(empty component fold is the recorded diagnostic, never a silent pass)
  # Measured channel + profile (ambient environment — quirk Q1). The trailing
  # parenthetical of `active-toolchain` (e.g. " (default)") is output
  # decoration, not identity — dropped, triple retained.
  let activeRaw = rustupCapture("show active-toolchain")
  if activeRaw.len > 0:
    let paren = activeRaw.find('(')
    result.channel = (if paren > 0: activeRaw[0 ..< paren].strip() else: activeRaw)
  let profileRaw = rustupCapture("show profile")
  if profileRaw.len > 0:
    let plines = profileRaw.splitLines()
    if plines.len > 0:
      result.profile = plines[0].strip()

proc subjectGitIdentity*(repoRoot: string): tuple[gitRef: string; treeMerkle: string] {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## The exact-commit identity of the subject at `repoRoot` — the SAME
  ## read-only git queries `bindRustSubjectIntegrity` folds (rev-parse HEAD,
  ## rev-parse HEAD^{tree}; never mutates the subject). ("", "") = the
  ## identity is unavailable (not a git repo / rev-parse failed) — the empty
  ## fold IS the diagnostic and the caller fails closed; a git value is
  ## never fabricated and no "absent" literal is invented (the replay
  ## adapter's own non-git handling is fail-closed, and the input-contract
  ## callers materialize a real git repo for non-git probe trees).
  (gitCapture("-C \"" & repoRoot & "\" rev-parse HEAD"),
   gitCapture("-C \"" & repoRoot & "\" rev-parse HEAD^{tree}"))

proc rustStateTmpBase(): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Harness scratch root: $AXIOM_STATE_DIR/.axiom/tmp/rust_replay, CWD-relative
  ## fallback (subject tree is never written — Zero-Footprint Integrity).
  ## Partitioned from the Nim adapter's `replay` leaf: different compiler
  ## generation, same marker protocol.
  let sr = getEnv("AXIOM_STATE_DIR", "").strip()
  if sr.len > 0:
    sr / ".axiom" / "tmp" / "rust_replay"
  else:
    try:
      getCurrentDir() / ".axiom" / "tmp" / "rust_replay"
    except CatchableError:
      ".axiom" / "tmp" / "rust_replay"

proc rustSubjectModulePath(subjectRepoRoot, sourcePath: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Resolve the subject source file for the adapter: absolute as-is;
  ## otherwise prefer subjectRepoRoot-joined, then CWD-relative. The adapter
  ## fail-closes when the resolved path does not exist.
  if sourcePath.len == 0:
    return ""
  if isAbsolute(sourcePath):
    return sourcePath
  if subjectRepoRoot.len > 0:
    let rooted = joinPath(subjectRepoRoot, sourcePath)
    if fileExists(rooted):
      return rooted
  var cwd = ""
  try:
    cwd = getCurrentDir()
  except CatchableError:
    cwd = "."
  let cwdJoined = joinPath(cwd, sourcePath)
  if fileExists(cwdJoined):
    return cwdJoined
  joinPath(subjectRepoRoot, sourcePath)

# ---------------------------------------------------------------------------
# I/O boundary — the adapter execution (staged)
# ---------------------------------------------------------------------------

proc bindRustSubjectIntegrity(cfg: RustReplayConfig; record: var RustReplayRecord): tuple[repoRoot: string; error: string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## ① Subject integrity binding — measured before anything runs (the Nim
  ## adapter's bindSubjectIntegrity semantics, unchanged). Folds the
  ## exact-commit identity (gitRef + tree OID), the pre-run source hash, and
  ## the predicate-v2 pre side: the subject-inputs digest (b) and the
  ## combined repo-footprint digest (c)+(d). Returns ("", error) on the
  ## first unverifiable step.
  if not fileExists(cfg.subjectModulePath):
    return ("", "subject source not found: " & cfg.subjectModulePath)
  record.moduleSha256 = measuredFileSha256(cfg.subjectModulePath)
  if record.moduleSha256.len == 0:
    return ("", "subject source unreadable")
  let repoRoot = if cfg.subjectRepoRoot.len > 0: cfg.subjectRepoRoot
                 else: subjectRepoRootFor(cfg.subjectModulePath)
  if repoRoot.len == 0:
    return ("", "subject repo root not discoverable (exact-commit binding required)")
  record.subjectGitRef = gitCapture("-C \"" & repoRoot & "\" rev-parse HEAD")
  record.subjectTreeMerkle = gitCapture("-C \"" & repoRoot & "\" rev-parse HEAD^{tree}")
  if record.subjectGitRef.len == 0 or record.subjectTreeMerkle.len == 0:
    return ("", "subject git identity unavailable (rev-parse failed)")
  record.subjectInputsPre = measureSubjectInputsDigest(
    repoRoot, subjectProjectRootFor(cfg.subjectModulePath, repoRoot))
  record.repoFootprintPre = measureRepoFootprintDigest(repoRoot)
  (repoRoot, "")

proc synthesizeAndRunRustHarness(cfg: RustReplayConfig; record: var RustReplayRecord;
                                 repoRoot: string): tuple[rawOutput: string; error: string; invocation: RustBuildInvocation] {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## ②③ Harness synthesis under the state tmp tree + `rustc` compile + harness
  ## binary execution. Folds the MEASURED toolchain identity; fails closed on
  ## toolchain absence and on a declared pin that is unverifiable or violated.
  # Measured toolchain identity (recorded even when rustc is missing —
  # the absent fingerprint IS the diagnostic).
  let toolchain = rustToolchainFingerprint(cfg.rustcExe)
  record.rustVersion = toolchain.rustVersion
  record.rustcHash = toolchain.rustcHash
  record.componentsHash = toolchain.componentsHash
  record.rustChannel = toolchain.channel
  record.rustProfile = toolchain.profile
  record.rustComponents = toolchain.components
  record.declaredPin = cfg.pinnedChannel
  if toolchain.rustcPath.len == 0:
    return ("", "rustc not found (pinned Rust toolchain required)", RustBuildInvocation())
  # Declared-pin verification against the MEASURED channel — fail closed on
  # both violation and unverifiability (never replay on a guessed toolchain).
  if cfg.pinnedChannel.len > 0:
    if toolchain.channel.len == 0:
      return ("", "declared toolchain pin '" & cfg.pinnedChannel &
                   "' unverifiable (rustup channel query unavailable)", RustBuildInvocation())
    if not toolchain.channel.startsWith(cfg.pinnedChannel):
      return ("", "measured toolchain channel '" & toolchain.channel &
                   "' does not satisfy the declared pin '" & cfg.pinnedChannel & "'", RustBuildInvocation())
  let bindingSeed = cfg.funcName & "|" & cfg.subjectModulePath & "|" &
                    cfg.inputLiterals.join(",") & "|" & record.subjectGitRef
  let harnessDir = rustStateTmpBase() / sha256Hex(bindingSeed)[0 ..< 16]
  try:
    createDir(harnessDir)
  except CatchableError:
    return ("", "cannot create harness dir: " & harnessDir, RustBuildInvocation())
  record.harnessDir = harnessDir
  let harnessPath = harnessDir / "replay_harness.rs"
  let harness = renderRustReplayHarness(cfg.subjectModulePath,
                                         cfg.funcName,
                                         cfg.inputLiterals,
                                         cfg.paramBool)
  if harness.len == 0:
    return ("", "cannot render harness: a parameter literal is outside the " &
            "Rust literal subset (bool parameters accept 0/1/true/false only)",
            RustBuildInvocation())
  try:
    writeFile(harnessPath, harness)
  except CatchableError as e:
    return ("", "cannot write harness: " & e.msg, RustBuildInvocation())
  let binPath = harnessDir / "replay_harness_bin"
  let invocation = rustBuildInvocation(toolchain.rustcPath, harnessPath, binPath, harnessDir)
  # Profile state on the record: the exact invocation + the pinned profile
  # flags, paired with the toolchain identity folded above (ONE fingerprint
  # measurement supplies both the dispatch token executed here and the
  # recorded identity — never re-measured differently).
  record.compileCommand = invocation.cmdLine
  record.compileProfile = invocation.profileFlags
  var buildOut = ""
  var buildCode = -1
  try:
    (buildOut, buildCode) = execCmdEx(invocation.cmdLine, options = {poStdErrToStdOut, poUsePath})
  except CatchableError as e:
    return ("", "harness build invocation failed: " & e.msg, invocation)
  if buildCode != 0:
    record.exitCode = buildCode
    record.observedOutput = buildOut.strip()
    var diag = "harness compile failed (exit " & $buildCode & ")"
    let trimmed = buildOut.strip()
    if trimmed.len > 0:
      diag.add(": " & (if trimmed.len > 200: trimmed[0 ..< 200] else: trimmed))
    return ("", diag, invocation)
  # The compile produced the harness binary; run it and capture the marker
  # protocol output.
  try:
    let (outp, code) = execCmdEx("\"" & binPath & "\"",
                                options = {poStdErrToStdOut, poUsePath})
    record.exitCode = code
    record.observedOutput = outp.strip()
    (outp, "", invocation)
  except CatchableError as e:
    record.observedOutput = ""
    ("", "harness execution failed: " & e.msg, invocation)

proc confirmRustPostRunIntegrity(cfg: RustReplayConfig; record: var RustReplayRecord;
                                 repoRoot: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## ④ Post-run subject integrity: the predicate-v2 worktree-stability
  ## decision (Zero-Footprint Integrity) plus the harness exit-code gate.
  ## The (b)(c)(d) post sides are re-measured here and compared against the
  ## bind-side pre captures — RELATIVE equality (G2 "unchanged across the
  ## run"); a repo-wide clean porcelain is NOT required, so pre-existing
  ## noise (stale build stamp, untracked files) never seals. "" when the
  ## observation is admissible; the failure diagnostic otherwise (verdict
  ## stays rvUnavailable).
  record.moduleSha256AfterRun = measuredFileSha256(cfg.subjectModulePath)
  record.subjectInputsPost = measureSubjectInputsDigest(
    repoRoot, subjectProjectRootFor(cfg.subjectModulePath, repoRoot))
  record.repoFootprintPost = measureRepoFootprintDigest(repoRoot)
  record.worktreeStable = rustWorktreeStable(
    record.moduleSha256, record.moduleSha256AfterRun,
    record.subjectInputsPre, record.subjectInputsPost,
    record.repoFootprintPre, record.repoFootprintPost)
  if record.exitCode != 0:
    if harnessPanicked(record.exitCode, record.observedOutput):
      # Distinct panic OBSERVATION (evidence/determinism only): classified
      # rroPanicked with the verbatim report. The shared-vocabulary verdict
      # stays rvUnavailable (the fail-closed fold) — never agreed, so no
      # consumer can confirm a disproof from a panic: a panic is evidence
      # about the compile profile, not an in-domain counterexample
      # observation (negative-control norm). Lane verdict/status/exit
      # behavior is unchanged — only the classification and its evidence
      # text are new.
      record.outcome = rroPanicked
      record.panicEvidence = rustPanicEvidence(record.observedOutput)
      let snippet = record.panicEvidence.replace('\n', ' ')
      return "harness panicked (exit " & $record.exitCode & "): " &
             (if snippet.len > 200: snippet[0 ..< 200] else: snippet)
    return "harness nonzero exit " & $record.exitCode
  if not record.worktreeStable:
    return "subject tree drifted during replay (hash/porcelain mismatch)"
  ""

# ---------------------------------------------------------------------------
# Public entries — observer-only (Authority = 0)
# ---------------------------------------------------------------------------

proc runRustCounterexampleReplay*(cfg: RustReplayConfig): RustReplayRecord {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Execute the Rust replay harness for one confirmed counterexample.
  ## Observer-only: every failure mode lands in `rvUnavailable` +
  ## `diagnostics`; nothing is promoted here and nothing is written to the
  ## subject tree or the CAS.
  var record = RustReplayRecord(
    verdict: rvUnavailable,
    exitCode: -1,
    hostPlatform: hostPlatformId,
    worktreeStable: false,
    outcome: rroUnavailable)  # explicit fail-closed init — never the enum's
                              # first value by accident
  let bound = bindRustSubjectIntegrity(cfg, record)
  if bound.error.len > 0:
    record.diagnostics = bound.error
    return record
  let ran = synthesizeAndRunRustHarness(cfg, record, bound.repoRoot)
  if ran.error.len > 0:
    record.diagnostics = ran.error
    return record
  # Evidence-integrity admission (observer-only): the recorded compile pair
  # must BE the ONE executed invocation. Any divergence folds to
  # rvUnavailable + appended diagnostic — never a false agreement, never a
  # panic.
  let cmdMismatch = rustReplayCommandMismatch(ran.invocation, record)
  if cmdMismatch.len > 0:
    if record.diagnostics.len > 0:
      record.diagnostics.add("; ")
    record.diagnostics.add(cmdMismatch)
    record.verdict = rvUnavailable
    record.outcome = rroUnavailable
    return record
  let integrityError = confirmRustPostRunIntegrity(cfg, record, bound.repoRoot)
  if integrityError.len > 0:
    record.diagnostics = integrityError
    return record
  decideRustReplayAgreement(cfg, ran.rawOutput, record)
  record

proc replayConfirmedRustDisproof*(subjectRepoRoot: string; sourcePath: string;
                                  funcDef: IRFuncDef; modelRaw: string;
                                  pinnedChannel: string = "";
                                  paramBool: seq[bool] = @[]):
    tuple[agreed: bool; payload: seq[string]; diagnostics: string] {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Single pipeline entry (S4-S5, Rust partition): replay one P4-confirmed
  ## disproof against the real subject `.rs` source. `modelRaw` is the raw
  ## solver output that carried the `(get-model)` assignment. `paramBool`
  ## carries the SOURCE-level bool flags (positional) — the IR keeps one
  ## bitVec64 sort, so the call-site rendering needs the canonical type.
  ## Agreement returns the PROPOSITION_DISPROVED payload (exact input + propertyViolated + replay
  ## record folds); ANY other outcome returns agreed=false + diagnostics and
  ## the caller decides fail-closed cvUnresolved. Authority = 0 — this proc
  ## never mutates a verdict.
  result.agreed = false
  let bindings = parseModelBindings(modelRaw)
  # S4 exact-input discipline (counterexample_replay.nim:734-747): replaying
  # a defaulted input would present it as the solver's counterexample —
  # theater. Fail closed unless the model binds every subject parameter.
  let unbound = unboundParameters(bindings, funcDef.params)
  if unbound.len > 0:
    result.diagnostics = "rvUnavailable:model does not bind parameter '" &
                         unbound[0] & "' (exact-input required)"
    return
  let replayInputs = modelToRustTestInputs(bindings, funcDef.params)
  var paramNames: seq[string] = @[]
  for p in funcDef.params:
    paramNames.add(p.name)
  let cfg = RustReplayConfig(
    subjectRepoRoot: subjectRepoRoot,
    subjectModulePath: rustSubjectModulePath(subjectRepoRoot, sourcePath),
    funcName: funcDef.name,
    paramNames: paramNames,
    inputLiterals: replayInputs,
    paramBool: paramBool,
    postconditions: funcDef.postConditions,
    pinnedChannel: pinnedChannel)
  let replay = runRustCounterexampleReplay(cfg)
  # Confirmation gate on the LOSSLESS lane classification, not the shared
  # projection: ONLY rroAgree confirms a disproof. rroPanicked in particular
  # NEVER confirms — a runtime panic (exit 101 + panic report) is evidence
  # about the compile profile, not an in-domain counterexample observation
  # (negative-control norm: profile-independent, in-domain counterexamples
  # only). Every non-agree outcome fail-closes to agreed=false + diagnostics
  # and the caller decides cvUnresolved.
  if replay.outcome != rroAgree:
    result.diagnostics = $replay.verdict & ":" & replay.diagnostics
    return
  result.agreed = true
  var propertySmt = ""
  for pc in funcDef.postConditions:
    if pc == nil:
      continue
    let pcSmt = irExprToSmt(pc)
    propertySmt = if propertySmt.len == 0: pcSmt
                  else: "(and " & propertySmt & " " & pcSmt & ")"
  result.payload = inputLiteralsPayload(paramNames, replayInputs) &
                   @["propertyViolated=" & propertySmt] &
                   rustReplayRecordPayload(replay)

{.pop.}
