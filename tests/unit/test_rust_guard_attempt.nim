## Guard-obligation attempt tests (feat/rust-guard-obligation-attempts).
##
## Contract under test (the DECLARATION-FREE proof-attempt lane — no subject
## spec, no scope-lock declaration, no certificate):
##   1. rustGuardGoals(canonical) — one `irLt(irAdd(lhs, rhs), irLit(2^width))`
##      per DISTINCT AddChecked of the INLINED body; empty for no-arithmetic
##      bodies. These are the code's own checked-add guards, not a caller
##      spec.
##   2. renderRustGuardObligationLean(canonical, digest, goal) — same result
##      record type as renderRustObligationLean, but hypotheses = TYPE RANGES
##      ONLY. THEATER GUARD: the goal under proof must never re-enter as a
##      hypothesis — an assumption-laundered theorem is trivially provable
##      and guarantees nothing (the tmp/guard_spike S1 hazard). The kernel
##      verdicts are the mechanical truth: a FALSE guard (a+b<256) must be
##      DECLINED, a TRUE guard (a+0<256) must PASS sorry-free, and a sorry
##      substitution must be flagged by scanSorryMarkers exactly where the
##      kernel still accepts.
##   3. rustCanonicalToIrFuncDef(canonical, post) — the shared canonical as a
##      full IRFuncDef, the SMT leg's input.
##   4. rustGuardObligationAttempt(llbcText, funcName, subjectModulePath) —
##      the attempt record with deterministic reasons (no raw model values):
##      proved / declined+sat / declined+unsat / zero-goals; an
##      out-of-grammar producer rejection never attempts. A declined+SAT
##      goal is replay-CONFIRMED when the subject module sits in a git repo
##      (`subjectModulePath` bound): the recorded-profile replay observes
##      the overflow panic (log-only evidence, never reason text) and the
##      reason upgrades to the confirmed class — the status stays unknown.
##      Without a git-bound subject the fallback reason (confirmation
##      unavailable) stays live.
##   5. SMT semantics (real z3): the offset goal is SAT under the u8 type
##      ranges (200+56=256 ≥ 256 — refuted MATHEMATICALLY; 64-bit bvadd
##      cannot wrap under those ranges) and the bump0 goal is UNSAT —
##      the (200,56)/(255,1) refutation class, not a wrap artifact.
##
##   6. Two-add attribution (add_u8_mutant = a+b+1 — TWO AddChecked — from the
##      committed rust probe fixture): the goals carry first-occurrence order
##      — goals[0] = outer `(a+b)+1 < 256`, goals[1] = inner `a+b < 256`.
##      THE ATTRIBUTION GUARANTEE, at query level: every counterexample of
##      the INNER goal (a+b ≥ 256) violates the OUTER sibling (`(a+b)+1 < 256`
##      forces a+b < 255), so the inner goal's constrained query (the outer
##      goal asserted as a precondition via preExtra) is UNSAT — a goal whose
##      only counterexamples violate a sibling is never confirmable; the
##      OUTER goal's constrained query (inner sibling asserted) is SAT
##      exactly on the a+b = 255 boundary — a model that SATISFIES the inner
##      sibling. guardModelAttributionSafe pins the same guarantee on the
##      model side (siblings satisfied → true; a sibling violated by the
##      model → false; unparseable/missing param → false) and
##      guardPanicIsAttributedAdd pins the confirmation gate to the
##      add-overflow panic class ONLY ("attempt to add with overflow" —
##      never multiply, never a bare "with overflow" fragment).
##   7. guardObservationAdmitted — the SINGLE G1 observation-admission
##      predicate the gate consumes: (rroPanicked, add-overflow report) is
##      the only admitted shape; a wrong panic class, a bare fragment, empty
##      evidence, and every exit-0 value observation / unavailable outcome
##      (rroAgree/rroDisagree/rroUnavailable, the profile-off shapes) are
##      rejected by construction.
##
## Fixture: tests/fixtures/rust/axiom_guard_probe/ (committed, see its
## README — measured 2026-10-18, charon 0.1.281): offset(a,b)=a+b,
## bump0(a)=a+0 (Const 0 NOT folded by rustc's MIR), echo(a)=a (no
## arithmetic), tri(a,b) (Switch — outside the closed grammar).
## Two-add attribution additionally uses the committed
## tests/fixtures/rust/axiom_rust_probe/ LLBC (add_u8_mutant = a+b+1).
##
## Environment gates (explicit skip, not failure): lake absent → the
## kernel-bearing suites skip; z3 absent → the attempt + SMT suites skip.

import std/[json, options, os, osproc, strutils, unittest]

import core/crypto/hash_kernel
import core/results
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/ir_to_smt
import core/trusted/rust_canonical
import core/types/obligation_evidence  ## ModelBinding (attribution-guard units)
import verification/llbc_to_canonical
import verification/obligation/canonical_verification
import verification/obligation/lean_kernel_boundary
import verification/rust_extraction_agreement
import verification/rust_obligation_render
import verification/rust_replay_adapter  ## RustReplayOutcome (the G1 admission units)
import verification/rust_rust_pipeline

proc repoRoot(): string =
  ## tests/unit/<file> -> project root (location-based, so the compiled
  ## binary resolves the fixture from any CWD — the gateway suites' pattern).
  absolutePath("../..", currentSourcePath().parentDir)

let
  RepoRoot = repoRoot()
  GuardProbePath = RepoRoot / "tests" / "fixtures" / "rust" /
      "axiom_guard_probe" / "axiom_guard_probe.llbc"

let lakePresent = findExe("lake").len > 0
let z3Present = findExe("z3").len > 0 or
    fileExists(getHomeDir() / ".local" / "bin" / "z3")

if not lakePresent:
  echo "SKIP: lake not on PATH — kernel-bearing suites skip (explicit skip, not a failure)"
if not z3Present:
  echo "SKIP: z3 not found — attempt/SMT suites skip (explicit skip, not a failure)"

let probeText = readFile(GuardProbePath)
let parsed = parseLlbcFile(GuardProbePath)

proc canonicalOf(name: string): RustCanonical =
  let ext = llbcFunctionToCanonical(parsed.root, name)
  doAssert ext.ok, "fixture canonical extraction failed for " & name & ": " &
    ext.reason
  ext.canonical

let OffsetCanonical = canonicalOf("offset")
let Bump0Canonical = canonicalOf("bump0")
let EchoCanonical = canonicalOf("echo")

let CanonicalDigest = sha256Hex("guard-attempt-unit-canonical-digest")

proc materializeGuardProbeCopy(dirName: string; gitBind: bool): string =
  ## The guard-probe crate copied UNCHANGED into a throwaway temp dir — never
  ## written in place (Zero-Footprint). `gitBind` additionally materializes a
  ## real git repo (init + add + commit) so the replay adapter's exact-commit
  ## binding can fold a git identity; without it the subject is non-git —
  ## the honest confirmation-unavailable fallback shape.
  let src = RepoRoot / "tests" / "fixtures" / "rust" / "axiom_guard_probe"
  let root = getTempDir() / dirName
  removeDir(root)
  copyDir(src, root)
  if gitBind:
    discard execCmdEx("git -C \"" & root & "\" init -q")
    discard execCmdEx("git -C \"" & root & "\" add -A")
    discard execCmdEx("git -C \"" & root &
      "\" -c user.name=ax -c user.email=ax@test commit -q -m init")
  root

let
  ## The git-bound subject: replay confirmation CAN occur (the overflow
  ## panic is observed under the recorded profile).
  GuardGitSubject = materializeGuardProbeCopy(
    "ax_guard_attempt_git_subject", gitBind = true)
  ## The non-git subject: replay confirmation CANNOT occur — the fallback
  ## reason stays live.
  GuardNonGitSubject = materializeGuardProbeCopy(
    "ax_guard_attempt_plain_subject", gitBind = false)

proc isAddVarsLt(e: IRExpr; lhsName, rhsName: string; bound: int64): bool =
  ## Goal shape `irLt(irAdd(irVar lhs, irVar rhs), irLit bound)`.
  if e.isNil or e.kind != irBinOp or e.binOp != boLt:
    return false
  let add = e.binLhs
  if add.isNil or add.kind != irBinOp or add.binOp != boAdd:
    return false
  add.binLhs.kind == irVar and add.binLhs.varName == lhsName and
    add.binRhs.kind == irVar and add.binRhs.varName == rhsName and
    e.binRhs.kind == irLit and e.binRhs.litVal == bound

proc isAddVarLitLt(e: IRExpr; lhsName: string; rhsConst, bound: int64): bool =
  ## Goal shape `irLt(irAdd(irVar lhs, irLit rhsConst), irLit bound)` — the
  ## bump0 shape (the Const 0 operand is NOT folded; it owes its own goal).
  if e.isNil or e.kind != irBinOp or e.binOp != boLt:
    return false
  let add = e.binLhs
  if add.isNil or add.kind != irBinOp or add.binOp != boAdd:
    return false
  add.binLhs.kind == irVar and add.binLhs.varName == lhsName and
    add.binRhs.kind == irLit and add.binRhs.litVal == rhsConst and
    e.binRhs.kind == irLit and e.binRhs.litVal == bound

proc hypCountOf(proposition: string): int =
  ## The number of hypotheses in a family proposition: the " → " arrows
  ## separating `∀ (p…), <hyp₁> → … → <hypₖ> → <conclusion>`.
  proposition.count(" → ")

proc introTokens(leanSource: string): seq[string] =
  ## The tokens of the template's `intro` line (params + hypotheses).
  for rawLine in leanSource.splitLines():
    let line = rawLine.strip()
    if line.startsWith("intro "):
      return line["intro ".len .. ^1].splitWhitespace()
  @[]

proc runZ3WithModel(script: string): string =
  ## Run the local z3 on the script + "(get-model)" (the spike S5 channel);
  ## returns the raw solver output. The z3 resolution order mirrors the
  ## solver suites' convention (PATH lookup, home-dir fallback).
  let path = getTempDir() / ("axiom_guard_test_" & sha256Hex(script) & ".smt2")
  writeFile(path, script & "\n(get-model)\n")
  let z3 = (if fileExists(getHomeDir() / ".local" / "bin" / "z3"):
              getHomeDir() / ".local" / "bin" / "z3"
            else: findExe("z3"))
  let (outp, code) = execCmdEx(quoteShell(z3) & " " & quoteShell(path),
                               options = {poUsePath})
  try:
    removeFile(path)
  except CatchableError:
    discard # axiom:best-effort(test temp cleanup — a residual script must not mask the verdict)
  # The STATUS line is the verdict channel ("sat"/"unsat" always print
  # first when the query ran); z3 exits NON-ZERO exactly when (get-model)
  # follows unsat ("model is not available") — an expected shape here, so
  # the exit code only surfaces when no verdict was produced at all.
  if outp.startsWith("sat") or outp.startsWith("unsat"):
    return outp
  "z3-exit-" & $code & "\n" & outp

# ─── Suite 1: rustGuardGoals — the mechanical goal set (pure) ───────────────

suite "rust guard attempt — rustGuardGoals over the committed guard probe":

  test "offset: exactly ONE goal, irLt(irAdd(a, b), 256) — 2^8 from the u8 width":
    let goals = rustGuardGoals(OffsetCanonical)
    check goals.len == 1
    check isAddVarsLt(goals[0], "a", "b", 256)

  test "bump0: exactly ONE goal, irLt(irAdd(a, 0), 256) — Const 0 is NOT folded":
    let goals = rustGuardGoals(Bump0Canonical)
    check goals.len == 1
    check isAddVarLitLt(goals[0], "a", 0, 256)

  test "echo: ZERO goals (no arithmetic — no obligation is invented)":
    check rustGuardGoals(EchoCanonical).len == 0

# ─── Suite 2: the guard renderer — THEATER GUARD (pure shape + kernel) ──────

suite "rust guard attempt — renderRustGuardObligationLean (theater guard)":

  let offsetGoals = rustGuardGoals(OffsetCanonical)
  let bump0Goals = rustGuardGoals(Bump0Canonical)
  doAssert offsetGoals.len == 1, "fixture drift: offset must yield one guard goal"
  doAssert bump0Goals.len == 1, "fixture drift: bump0 must yield one guard goal"
  let offsetR = renderRustGuardObligationLean(OffsetCanonical, CanonicalDigest,
                                              offsetGoals[0])
  let bump0R = renderRustGuardObligationLean(Bump0Canonical, CanonicalDigest,
                                             bump0Goals[0])

  test "offset guard: hypotheses are TYPE RANGES ONLY — the goal is never a " &
      "hypothesis (count \"< 256\" == 2 ranges + 1 conclusion)":
    check offsetR.ok
    # 2 param ranges + the goal as the ONLY occurrence of the bound in the
    # conclusion — an assumption-laundered copy of the goal as a hypothesis
    # would push this to 4 (the spike S1 theater shape).
    check offsetR.proposition.count("< 256") == 3
    # hypothesis count == param count: exactly two arrows, each a type range.
    check hypCountOf(offsetR.proposition) == OffsetCanonical.params.len
    check offsetR.proposition.contains(
      "((0 ≤ a) ∧ (a < 256)) → ((0 ≤ b) ∧ (b < 256)) → ")

  test "offset guard: the intro line binds params + range hypotheses ONLY " &
      "(hypothesis count == param count)":
    check offsetR.ok
    let toks = introTokens(offsetR.leanSource)
    check toks.len == 2 * OffsetCanonical.params.len  # a b h0 h1
    check toks[0] == "a" and toks[1] == "b"

  test "bump0 guard: one type-range hypothesis, goal in the conclusion":
    check bump0R.ok
    check bump0R.proposition.count("< 256") == 2
    check hypCountOf(bump0R.proposition) == Bump0Canonical.params.len
    check bump0R.proposition.contains("((0 ≤ a) ∧ (a < 256)) → ")

  if lakePresent:
    test "THE FALSE GUARD DECLINES: the kernel refuses offset's (a+b<256) " &
        "source (a+b is not < 256 in the ranges)":
      check offsetR.ok
      let kres = canonicalLeanKernelCheck(offsetR.leanSource,
                                          timeoutMs = 120_000)
      check kres.isErr

    test "THE TRUE GUARD PASSES: the kernel accepts bump0's (a+0<256) source " &
        "with clean sorry markers":
      check bump0R.ok
      let kres = canonicalLeanKernelCheck(bump0R.leanSource,
                                          timeoutMs = 120_000)
      check kres.isOk
      if kres.isOk:
        let markers = scanSorryMarkers(bump0R.leanSource,
                                       kres.get().receiptKernelObservation)
        check markers.len == 0

    test "sorry substitution: the kernel STILL ACCEPTS, scanSorryMarkers " &
        "FLAGS it (the second layer catches what the first accepts)":
      check bump0R.ok
      let sorrySource = bump0R.leanSource.replace("  omega\n", "  sorry\n")
      check sorrySource != bump0R.leanSource
      let kres = canonicalLeanKernelCheck(sorrySource, timeoutMs = 120_000)
      check kres.isOk
      if kres.isOk:
        let markers = scanSorryMarkers(sorrySource,
                                       kres.get().receiptKernelObservation)
        check markers.len > 0

# ─── Suite 3: rustGuardObligationAttempt — the declaration-free attempt ─────

suite "rust guard attempt — rustGuardObligationAttempt (kernel + z3 + replay confirmation)":

  test "bump0: attempted, the guard goal is PROVED, discharged reason":
    let rec = rustGuardObligationAttempt(probeText, "bump0",
                                         projectRoot = RepoRoot)
    check rec.attempted
    check rec.goalCount == 1
    check rec.goalOutcomes.len == 1
    check rec.goalOutcomes[0].proved
    check not rec.goalOutcomes[0].declinedByKernel
    check rec.goalOutcomes[0].goalText.len > 0
    check rec.reason.contains("guard obligation discharged")
    check rec.reason.contains("sorry-free")

  test "offset: DECLINED by kernel, z3 SAT, counterexample CONFIRMED by " &
      "replay (git-bound subject) — the deterministic confirmed reason " &
      "carries the model script digest":
    let rec = rustGuardObligationAttempt(probeText, "offset",
                                         projectRoot = RepoRoot,
                                         subjectRoot = GuardGitSubject,
                                         subjectModulePath =
                                           GuardGitSubject / "src" / "lib.rs")
    check rec.attempted
    check rec.goalCount == 1
    let g = rec.goalOutcomes[0]
    check not g.proved
    check g.declinedByKernel
    check g.z3Sat
    check g.z3ScriptDigest.len == 64
    check g.confirmed
    # the record-level reason aggregates under the goal-count prefix; the
    # GOAL outcome carries the verbatim contract format
    check g.reason.startsWith("guard goal '")
    check rec.reason.contains("guard goal '")
    check rec.reason.contains("declined by kernel")
    check rec.reason.contains("VIOLATED")
    check rec.reason.contains("counterexample confirmed by replay")
    check rec.reason.contains("model script digest")
    check rec.reason.contains("not a declared-spec failure")
    # No raw model values in the reason (deterministic by contract).
    check not rec.reason.contains("define-fun")
    # The panic observation is LOG-ONLY evidence — never reason text — and
    # the confirmed class retires the fallback wording entirely.
    check not rec.reason.contains("attempt to add with overflow")
    check not rec.reason.contains("confirmation unavailable")

  test "offset FALLBACK: non-git subject — the unconfirmed declined reason " &
      "stays live (confirmation unavailable, overflow-discretion class)":
    let rec = rustGuardObligationAttempt(probeText, "offset",
                                         projectRoot = RepoRoot,
                                         subjectModulePath =
                                           GuardNonGitSubject / "src" / "lib.rs")
    check rec.attempted
    check rec.goalCount == 1
    let g = rec.goalOutcomes[0]
    check not g.proved
    check g.declinedByKernel
    check g.z3Sat
    check g.z3ScriptDigest.len == 64
    check not g.confirmed
    check g.reason.startsWith("guard goal '")
    check rec.reason.contains("guard goal '")
    check rec.reason.contains("declined by kernel")
    check rec.reason.contains("Z3 confirms a refuting candidate exists")
    check rec.reason.contains("script digest")
    check rec.reason.contains("confirmation unavailable")
    # No raw model values in the reason (deterministic by contract).
    check not rec.reason.contains("define-fun")

  test "echo: attempted with ZERO mechanical goals — the exact zero-goals " &
      "reason (the attempt ran; nothing was skipped)":
    let rec = rustGuardObligationAttempt(probeText, "echo",
                                         projectRoot = RepoRoot)
    check rec.attempted
    check rec.goalCount == 0
    check rec.goalOutcomes.len == 0
    check rec.reason ==
      "no derivable guard obligation (attempt ran; zero mechanical goals)"

  test "tri: the producer rejects the grammar — the attempt NEVER runs " &
      "(fail-closed out-of-subset, not an internal error)":
    let rec = rustGuardObligationAttempt(probeText, "tri",
                                         projectRoot = RepoRoot)
    check not rec.attempted
    check rec.goalCount == 0
    check rec.goalOutcomes.len == 0
    check outcomeOutOfScopeUnknown(rec.outcome)

  test "determinism: the offset attempt is identical across two runs " &
      "(reason strings + z3ScriptDigest)":
    let a = rustGuardObligationAttempt(probeText, "offset",
                                       projectRoot = RepoRoot)
    let b = rustGuardObligationAttempt(probeText, "offset",
                                       projectRoot = RepoRoot)
    check a.attempted == b.attempted
    check a.reason == b.reason
    check a.goalOutcomes[0].reason == b.goalOutcomes[0].reason
    check a.goalOutcomes[0].z3ScriptDigest == b.goalOutcomes[0].z3ScriptDigest

# ─── Suite 4: SMT semantics — the goal refutes mathematically (real z3) ─────

suite "rust guard attempt — SMT semantics via rustCanonicalToIrFuncDef (z3)":

  let bv = irTypeBitVec64()
  let offsetGoal = irLt(irAdd(irVar("a", bv), irVar("b", bv)), irLit(256))
  let bump0Goal = irLt(irAdd(irVar("a", bv), irLit(0)), irLit(256))
  let fOffset = rustCanonicalToIrFuncDef(OffsetCanonical, offsetGoal)
  let fBump0 = rustCanonicalToIrFuncDef(Bump0Canonical, bump0Goal)
  let scriptOffset = irToSmtScript(fOffset)
  let scriptBump0 = irToSmtScript(fBump0)

  test "the script declares the width-uniform BitVec 64 params (u8 lifts to 64)":
    check scriptOffset.contains("(_ BitVec 64)")
    check scriptOffset.contains("(declare-fun a ()")
    check scriptOffset.contains("(declare-fun b ()")
    check scriptOffset.contains("(check-sat)")

  test "z3: the offset goal (a+b<256) is SAT under the u8 ranges — refuted " &
      "mathematically (200+56=256 class), NOT via 64-bit wrap":
    let outp = runZ3WithModel(scriptOffset)
    check outp.startsWith("sat")

  test "z3: the bump0 goal (a+0<256) is UNSAT under the u8 ranges — no " &
      "refuting candidate exists (255+0<256 holds)":
    let outp = runZ3WithModel(scriptBump0)
    check outp.startsWith("unsat")

# ─── Suite 5: two-add attribution — add_u8_mutant (the constrained query) ───

let RustProbePath = RepoRoot / "tests" / "fixtures" / "rust" /
    "axiom_rust_probe" / "axiom_rust_probe.llbc"
let RustProbeParsed = parseLlbcFile(RustProbePath)

proc mutantCanonical(): RustCanonical =
  let ext = llbcFunctionToCanonical(RustProbeParsed.root, "add_u8_mutant")
  doAssert ext.ok, "fixture canonical extraction failed for add_u8_mutant: " &
    ext.reason
  ext.canonical

let MutantCanonical = mutantCanonical()
let MutantGoals = rustGuardGoals(MutantCanonical)

proc bvBinding(name: string; v: int64): ModelBinding =
  ## A z3-shaped bv64 binding (the exact channel parseModelBindings sees from
  ## runZ3WithModel: `#x` + 16 lowercase hex digits).
  ModelBinding(name: name, value: "#x" & v.toHex(16).toLowerAscii(),
               sort: "(_ BitVec 64)")

proc bvValue(bindings: seq[ModelBinding]; name: string): Option[int64] =
  ## The parsed bv64 value of one binding ("" / unparseable → none).
  for b in bindings:
    if b.name == name and b.value.startsWith("#x"):
      try:
        return some(int64(parseHexInt(b.value[2 .. ^1])))
      except ValueError:
        return none(int64)
  none(int64)

suite "rust guard attempt — two-add attribution (add_u8_mutant, committed rust probe)":

  test "exactly TWO goals, first-occurrence order: goals[0] = outer " &
      "(a+b)+1 < 256, goals[1] = inner a+b < 256":
    check MutantGoals.len == 2
    # goals[0] — the OUTER AddChecked: irLt(irAdd(irAdd(a, b), 1), 256)
    let outer = MutantGoals[0]
    check outer.kind == irBinOp and outer.binOp == boLt
    check outer.binLhs.kind == irBinOp and outer.binLhs.binOp == boAdd
    check outer.binLhs.binLhs.kind == irBinOp and
      outer.binLhs.binLhs.binOp == boAdd
    check outer.binLhs.binLhs.binLhs.kind == irVar and
      outer.binLhs.binLhs.binLhs.varName == "a"
    check outer.binLhs.binLhs.binRhs.kind == irVar and
      outer.binLhs.binLhs.binRhs.varName == "b"
    check outer.binLhs.binRhs.kind == irLit and outer.binLhs.binRhs.litVal == 1
    check outer.binRhs.kind == irLit and outer.binRhs.litVal == 256
    # goals[1] — the INNER AddChecked: irLt(irAdd(a, b), 256)
    check isAddVarsLt(MutantGoals[1], "a", "b", 256)

  test "QUERY-LEVEL NEGATIVE (the attribution guarantee): the inner goal's " &
      "constrained query (outer sibling asserted via preExtra) is UNSAT — " &
      "a goal whose only counterexamples violate a sibling is never " &
      "confirmable":
    let f = rustCanonicalToIrFuncDef(MutantCanonical, MutantGoals[1],
                                     @[MutantGoals[0]])
    check f.name == "add_u8_mutant"
    # 2 type ranges + the outer sibling = the full constraint set.
    check f.preConditions.len == 3
    let script = irToSmtScript(f, includeOverflowDefines = false)
    check script.contains("(check-sat)")
    # a+b ≥ 256 contradicts the asserted sibling (a+b)+1 < 256 — UNSAT.
    let outp = runZ3WithModel(script)
    check outp.startsWith("unsat")

  test "QUERY-LEVEL POSITIVE: the outer goal's constrained query (inner " &
      "sibling asserted) is SAT — the model sits on the a+b = 255 boundary " &
      "and SATISFIES the inner goal":
    let f = rustCanonicalToIrFuncDef(MutantCanonical, MutantGoals[0],
                                     @[MutantGoals[1]])
    check f.name == "add_u8_mutant"
    check f.preConditions.len == 3
    let script = irToSmtScript(f, includeOverflowDefines = false)
    check script.contains("(check-sat)")
    let outp = runZ3WithModel(script)
    check outp.startsWith("sat")
    # The refuting model satisfies the inner sibling exactly on the boundary:
    # a+b = 255 → inner 255 < 256 holds, outer (a+b)+1 = 256 ≥ 256 refuted.
    let bindings = parseModelBindings(outp)
    let va = bvValue(bindings, "a")
    let vb = bvValue(bindings, "b")
    check va.isSome and vb.isSome
    if va.isSome and vb.isSome:
      check va.get() >= 0 and va.get() < 256 and vb.get() >= 0 and
        vb.get() < 256
      check va.get() + vb.get() == 255

suite "rust guard attempt — guardModelAttributionSafe (model-vs-sibling units)":

  let bv = irTypeBitVec64()
  let innerSibling = irLt(irAdd(irVar("a", bv), irVar("b", bv)), irLit(256))
  let mutantParams = @[IRFuncParam(name: "a", ty: bv, constraint: none(IRExpr)),
                       IRFuncParam(name: "b", ty: bv, constraint: none(IRExpr))]

  test "siblings satisfied by the model → true (the boundary model a=255,b=0 " &
      "satisfies the inner goal 255 < 256)":
    check guardModelAttributionSafe(@[innerSibling],
                                    @[bvBinding("a", 255), bvBinding("b", 0)],
                                    mutantParams)
    # Same verdict for the fixture's own inner goal (shape-identical):
    check guardModelAttributionSafe(@[MutantGoals[1]],
                                    @[bvBinding("a", 255), bvBinding("b", 0)],
                                    mutantParams)

  test "a sibling violated by the model → false (a=255,b=1 → 256 < 256 fails)":
    check not guardModelAttributionSafe(@[innerSibling],
                                        @[bvBinding("a", 255),
                                          bvBinding("b", 1)],
                                        mutantParams)

  test "unparseable binding value → false (fail-closed, never guessed)":
    check not guardModelAttributionSafe(@[innerSibling],
                                        @[ModelBinding(name: "a",
                                                       value: "garbage",
                                                       sort: "(_ BitVec 64)"),
                                          bvBinding("b", 0)],
                                        mutantParams)

  test "missing param binding → false (no defaulted input is attributed)":
    check not guardModelAttributionSafe(@[innerSibling],
                                        @[bvBinding("a", 255)],
                                        mutantParams)

suite "rust guard attempt — guardPanicIsAttributedAdd (the confirmation gate)":

  let addPanic = "thread 'main' (58025) panicked at src/lib.rs:6:5:\n" &
    "attempt to add with overflow\n" &
    "note: run with `RUST_BACKTRACE=1` environment variable to display a " &
    "backtrace"

  test "true for the add-overflow panic report (the attributed class)":
    check guardPanicIsAttributedAdd(addPanic)

  test "false for multiply overflow (a different arithmetic class)":
    check not guardPanicIsAttributedAdd(
      "thread 'main' panicked at src/lib.rs:6:5:\n" &
      "attempt to multiply with overflow")

  test "false for a bare 'with overflow' fragment (no add attribution)":
    check not guardPanicIsAttributedAdd("with overflow")

  test "false for unrelated panic text":
    check not guardPanicIsAttributedAdd(
      "thread 'main' panicked at src/lib.rs:9:5:\n" &
      "index out of bounds: the len is 0 but the index is 0")

suite "rust guard attempt — guardObservationAdmitted (the G1 admission predicate)":

  let addPanic = "thread 'main' (58025) panicked at src/lib.rs:6:5:\n" &
    "attempt to add with overflow\n" &
    "note: run with `RUST_BACKTRACE=1` environment variable to display a " &
    "backtrace"

  test "true for (rroPanicked, the add-overflow report) — the only " &
      "admitted shape":
    check guardObservationAdmitted(rroPanicked, addPanic)

  test "false for rroPanicked with a multiply-overflow report (wrong " &
      "arithmetic class)":
    check not guardObservationAdmitted(rroPanicked,
      "thread 'main' panicked at src/lib.rs:6:5:\n" &
      "attempt to multiply with overflow")

  test "false for rroPanicked with a bare 'with overflow' fragment (no add " &
      "attribution)":
    check not guardObservationAdmitted(rroPanicked, "with overflow")

  test "false for rroPanicked with empty evidence (nothing to admit)":
    check not guardObservationAdmitted(rroPanicked, "")

  test "false for every exit-0 value-observation / unavailable outcome even " &
      "with the overflow text (the profile-off shape never admits G1)":
    check not guardObservationAdmitted(rroAgree, addPanic)
    check not guardObservationAdmitted(rroDisagree, addPanic)
    check not guardObservationAdmitted(rroUnavailable, addPanic)

echo ""
