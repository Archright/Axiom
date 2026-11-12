## Base36 C_out out-sizing binding — S2 slice tests.
##
## SSOT: docs/spec/nim_stew_base36_cout_contract.md +
## config/spec/nim_stew_base36_cout_spec.json (SPEC-B36-COUT).
##
## Measured here:
##   1. The committed overlay loads through the soExplicit authority path and
##      pins the domain (3 <= L <= 3), the K claim constant (2, EXTERNAL
##     _OBSERVATION provenance cross-checked against the claim clause), and
##      the canonical decision vector (s="kzz", L=3). Every tampered shape
##      fails closed (pure validation core).
##   2. The synthesized single-origin carrier over the VERBATIM golden
##      fixture: body unchanged, OPEN obligation over L (literal domain pin,
##      not a closed proposition), postcondition `result >= 2` β-spliced with
##      exactly one body instance, census-eligible (rule F does not reject a
##      contract-post claim).
##   3. The single-origin replay shape: `outer(<carrier>, <valueLit>)` —
##      harness rendering plus a real-toolchain end-to-end replay of
##      decodedLength(Base36Types, 3) = 1 against the spliced claim
##      (propertyHolds == false → rvAgree).
##   4. The pipeline verdict: the C_out obligation over the honest subject is
##      SAT (L=3), P4-confirmed, and projects clDisproved + vsDisproved with
##      the §2.2 four-element PROPOSITION_DISPROVED payload (or fails closed on a dirty
##      worktree — exactly two accepted states, never a fabricated verdict).
import std/[json, os, osproc, options, tables, strutils, sequtils, unittest]

import ../../src/core/results
import ../../src/core/crypto/hash_kernel
import ../../src/core/utils/repo_root
import ../../src/core/trusted/specification_artifact
import ../../src/core/trusted/evidence_calculus
import ../../src/core/trusted/assurance_profile
import ../../src/core/trusted/claim_authority
import ../../src/core/trusted/axiom_ir
import ../../src/core/trusted/axiom_ir_helpers
import ../../src/core/trusted/axiom_pragmas
import ../../src/infrastructure/external_ir_materializer
import ../../src/cli/axiom_engine
import ../../src/verification/obligation/canonical_verification
import ../../src/verification/counterexample_replay
import ../../src/verification/batch_uap/ir_pipeline_runner
import ../../src/core/trusted/verification_result_types as vrt

putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_b36_cout_test_state")

let testsRoot = currentSourcePath().parentDir().parentDir()
let goldenRoot = testsRoot / "golden" / "base36_subject"

proc fixtureResolver(root: string): ModuleContentResolver =
  result = proc(modulePath: string): Option[string] {.raises: [].} =
    try:
      some(readFile(root / modulePath))
    except CatchableError:
      none(string)

proc committedOverlayNode(): JsonNode =
  parseJson(readFile(repoRootConst() / "config" / "spec" /
                     "nim_stew_base36_cout_spec.json"))

proc synthCout(root: string): Option[ExternalIrEntry] =
  ## Synthesize the C_out carrier from the committed overlay over `root`.
  var census = ExternalCandidateCensus()
  let domainRes = loadBase36CoutOverlayDomain()
  if domainRes.isErr:
    return none(ExternalIrEntry)
  let synth = synthesizeBase36CoutCandidate(
    "decodedLength", domainRes.get().modulePath,
    fixtureResolver(root), domainRes.get(), census)
  if synth.isErr:
    return none(ExternalIrEntry)
  if census.eligible.len != 1:
    return none(ExternalIrEntry)
  some(census.eligible[0])

# ---------------------------------------------------------------------------
# Suite 1 — overlay loader (soExplicit authority, fail-closed validation)
# ---------------------------------------------------------------------------

suite "C_out overlay — soExplicit load + fail-closed validation":

  test "the committed overlay loads and pins domain, K, and decision vector":
    let loaded = loadBase36CoutOverlayDomain()
    check loaded.isOk()
    let domain = loaded.get()
    check domain.modulePath == "stew/base36.nim"
    check domain.symbol == "decodedLength"
    check domain.domainVar == "L"
    check domain.domainLower == 3
    check domain.domainBound == 3
    check domain.claimConstant == 2
    check domain.decisionInput == "kzz"
    check domain.ruleId == "external:stew/base36/out-sizing-cout"

  test "the committed overlay is an authorized soExplicit spec":
    let specRes = explicitSpecFromOverlay(committedOverlayNode())
    check specRes.isOk()
    let spec = specRes.get()
    check spec.origin == soExplicit
    check isAuthorizedForVerification(spec.origin)

  test "overlayDeclaresCoutSubject governs only the claim symbol":
    let domain = loadBase36CoutOverlayDomain().get()
    check overlayDeclaresCoutSubject(domain, "decodedLength", "stew/base36.nim")
    check not overlayDeclaresCoutSubject(domain, "decode", "stew/base36.nim")
    check not overlayDeclaresCoutSubject(domain, "decodedLength", "stew/other.nim")

  test "fail-closed: a non-explicit origin is rejected":
    var node = committedOverlayNode()
    node["specOrigin"] = %"soMined"
    check validateCoutOverlayNode(node).isErr()

  test "fail-closed: claimConstant.K must equal the claim clause's K":
    var node = committedOverlayNode()
    node["claimConstant"]["K"] = %3
    check validateCoutOverlayNode(node).isErr()

  test "fail-closed: the decision vector's L must equal the domain pin":
    var node = committedOverlayNode()
    node["canonicalDecisionVector"]["L"] = %5
    check validateCoutOverlayNode(node).isErr()

  test "fail-closed: the decision vector input is required":
    var node = committedOverlayNode()
    delete(node["canonicalDecisionVector"], "input")
    check validateCoutOverlayNode(node).isErr()

  test "fail-closed: the claim clause must be '<fn>(<v>) >= <K>'":
    var node = committedOverlayNode()
    node["canonicalSpecIR"] = %["3 <= L", "L <= 3", "decodedLength(L) >= L + 2"]
    check validateCoutOverlayNode(node).isErr()

  test "fail-closed: the claim symbol must be a subject.symbols member":
    var node = committedOverlayNode()
    node["canonicalSpecIR"] = %["3 <= L", "L <= 3", "encodedLength(L) >= 2"]
    check validateCoutOverlayNode(node).isErr()

  test "fail-closed: an empty literal domain pin is rejected":
    var node = committedOverlayNode()
    node["canonicalSpecIR"] = %["5 <= L", "L <= 3", "decodedLength(L) >= 2"]
    check validateCoutOverlayNode(node).isErr()

  test "fail-closed: subject symbols must be non-empty":
    var node = committedOverlayNode()
    node["subject"]["symbols"] = %[""]
    check validateCoutOverlayNode(node).isErr()

# ---------------------------------------------------------------------------
# Suite 2 — synthesized single-origin carrier over the VERBATIM fixture
# ---------------------------------------------------------------------------

suite "C_out synthesis — single-origin carrier shape":

  let synth = synthCout(goldenRoot)

  test "the carrier is census-eligible (rule F does not reject the claim post)":
    check synth.isSome
    # The claim post ((L*179) div 277) >= 2 is not an okSafetyDiv ¬(d == 0)
    # obligation, so the nonTrivial count drives eligibility — measured.

  test "the carrier parse bound is single-origin, measured on decodedLength":
    let ve = synth.get
    check ve.parseBound.synthesizedComposite
    check ve.parseBound.claimCarrierSingleOrigin
    check ve.parseBound.measuredForFuncName == "decodedLength"
    check ve.parseBound.ea2MeasuredForFuncName.len == 0
    check ve.parseBound.compositeCarrierTypename == "Base36Types"
    check ve.parseBound.eaAgreed
    check ve.parseBound.synthesisDerivationDigest.len > 0

  test "the carrier body is the subject body, unchanged":
    let fd = synth.get.funcDef
    check fd.name == "decodedLength_cout_binding"
    check fd.body != nil
    check fd.body.kind == irBinOp
    check fd.body.binOp == boDiv
    check fd.body.binRhs.kind == irLit
    check fd.body.binRhs.litVal == 277
    check fd.body.binLhs.kind == irBinOp
    check fd.body.binLhs.binOp == boMul
    check fd.body.binLhs.binLhs.kind == irVar
    check fd.body.binLhs.binLhs.varName == "length"
    check fd.body.binLhs.binRhs.kind == irLit
    check fd.body.binLhs.binRhs.litVal == 179

  test "the obligation is OPEN over L — literal domain pin, not a closed proposition":
    let fd = synth.get.funcDef
    check fd.preConditions.len == 2
    check fd.preConditions[0].kind == irBinOp
    check fd.preConditions[0].binOp == boGe
    check fd.preConditions[0].binLhs.kind == irVar
    check fd.preConditions[0].binLhs.varName == "length"
    check fd.preConditions[0].binRhs.kind == irLit
    check fd.preConditions[0].binRhs.litVal == 3
    check fd.preConditions[1].kind == irBinOp
    check fd.preConditions[1].binOp == boLe
    check fd.preConditions[1].binLhs.kind == irVar
    check fd.preConditions[1].binLhs.varName == "length"
    check fd.preConditions[1].binRhs.kind == irLit
    check fd.preConditions[1].binRhs.litVal == 3

  test "the claim post is `result >= 2` β-spliced with exactly one body instance":
    let fd = synth.get.funcDef
    check fd.postConditions.len == 1
    let post = fd.postConditions[0]
    # The result slot was REPLACED (not left dangling, not duplicated):
    # a zero-splice claim would keep an irVar named `result`; the exactly-once
    # splice substitutes exactly one structural clone of the subject body.
    check post.kind == irBinOp
    check post.binOp == boGe
    check post.binRhs.kind == irLit
    check post.binRhs.litVal == 2
    check post.binLhs.kind == irBinOp
    check post.binLhs.binOp == boDiv
    check post.binLhs.binRhs.litVal == 277
    check post.binLhs.binLhs.binOp == boMul
    check post.binLhs.binLhs.binLhs.varName == "length"
    check post.binLhs.binLhs.binRhs.litVal == 179

  test "fail-closed: a let-bound subject body refuses synthesis (scope guard)":
    let root = getTempDir() / "ax_b36_cout_letbound"
    removeDir(root)
    createDir(root / "stew")
    writeFile(root / "stew" / "base36.nim", """type Base36Types* = object

func decodedLength*(btype: typedesc[Base36Types], length: int): int =
  let scaled = length * 179
  return scaled div 277
""")
    var census = ExternalCandidateCensus()
    let domain = loadBase36CoutOverlayDomain().get()
    let synth = synthesizeBase36CoutCandidate(
      "decodedLength", domain.modulePath, fixtureResolver(root), domain, census)
    check synth.isErr()
    check synth.error.contains("let-bindings")
    check census.records.len == 0

  test "fail-closed: a body referencing two value parameters refuses synthesis":
    let root = getTempDir() / "ax_b36_cout_twoparam"
    removeDir(root)
    createDir(root / "stew")
    writeFile(root / "stew" / "base36.nim", """type Base36Types* = object

func decodedLength*(btype: typedesc[Base36Types], a: int, b: int): int =
  return ((a + b - b) * 179) div 277
""")
    var census = ExternalCandidateCensus()
    let domain = loadBase36CoutOverlayDomain().get()
    let synth = synthesizeBase36CoutCandidate(
      "decodedLength", domain.modulePath, fixtureResolver(root), domain, census)
    check synth.isErr()
    check synth.error.contains("exactly one value parameter")
    check census.records.len == 0

# ---------------------------------------------------------------------------
# Suite 3 — single-origin replay shape: outer(<carrier>, <valueLit>)
# ---------------------------------------------------------------------------

suite "C_out replay — single-origin shape":

  const CarrierSubject = """type Base36Types* = object

func decodedLength*(btype: typedesc[Base36Types], length: int): int =
  return (length * 179) div 277
"""

  proc gitHead(root: string): string =
    let (outp, code) = execCmdEx("git -C \"" & root & "\" rev-parse HEAD",
                                 options = {poStdErrToStdOut, poUsePath})
    if code == 0: outp.strip() else: ""

  proc makeSubjectFixture(dirName: string; moduleSource: string): string =
    let root = getTempDir() / dirName
    removeDir(root)
    createDir(root)
    writeFile(root / "subject_mod.nim", moduleSource)
    discard execCmdEx("git -C \"" & root & "\" init -q",
                      options = {poStdErrToStdOut, poUsePath})
    discard execCmdEx("git -C \"" & root & "\" add -A",
                      options = {poStdErrToStdOut, poUsePath})
    discard execCmdEx("git -C \"" & root & "\" -c user.name=ax -c user.email=ax@test commit -q -m init",
                      options = {poStdErrToStdOut, poUsePath})
    root

  proc coutParseBound(): SubjectParseBoundComponents =
    SubjectParseBoundComponents(
      synthesizedComposite: true,
      claimCarrierSingleOrigin: true,
      measuredForFuncName: "decodedLength",
      compositeCarrierTypename: "Base36Types")

  proc coutFuncDef(): IRFuncDef =
    let length = irVar("length", irTypeBitVec64())
    let body = irDiv(irMul(length, irLit(179)), irLit(277))
    IRFuncDef(
      name: "decodedLength_cout_binding",
      params: @[IRFuncParam(name: "length", ty: irTypeBitVec64())],
      retType: irTypeBitVec64(),
      body: body,
      preConditions: @[irGe(length, irLit(3)), irLe(length, irLit(3))],
      postConditions: @[irGe(body, irLit(2))])

  test "shape derivation: one origin, empty inner, measured carrier token":
    let shape = compositeReplayShape(coutFuncDef(), coutParseBound())
    check shape.outerSymbol == "decodedLength"
    check shape.innerSymbol.len == 0
    check shape.carrierTypename == "Base36Types"
    check shape.valueParam == "length"

  test "shape derivation fails closed on an unmeasured carrier token":
    var pb = coutParseBound()
    pb.compositeCarrierTypename = ""
    let shape = compositeReplayShape(coutFuncDef(), pb)
    check shape.outerSymbol.len == 0
    check shape.innerSymbol.len == 0
    check shape.carrierTypename.len == 0

  test "shape derivation is empty for a non-synthesized entry (zero-diff)":
    let shape = compositeReplayShape(coutFuncDef(),
                                     SubjectParseBoundComponents())
    check shape.outerSymbol.len == 0

  test "harness rendering emits the single-origin call expression":
    let harness = renderReplayHarness("subject_mod", "decodedLength_cout_binding",
                                      @["3"],
                                      "decodedLength(Base36Types, 3)")
    check harness.contains("echo $decodedLength(Base36Types, 3)")
    check harness.contains("include subject_mod")

  test "end-to-end: replay of decodedLength(Base36Types, 3) returns 1 → rvAgree":
    ## The real toolchain reproduces the violation the solver derived: the
    ## model binds L=3, the subject's own body evaluates to 1, and the claim
    ## `result >= 2` concretely fails on the observed result (propertyHolds
    ## == false). rvAgree does NOT validate decode's accuracy (Authority 0) —
    ## it re-measures the carrier arithmetic only.
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_b36_cout_test_state")
    let root = makeSubjectFixture("ax_b36_cout_replay", CarrierSubject)
    let modelRaw = "sat\n(define-fun length () (_ BitVec 64) " &
                   "#x0000000000000003)\n"
    let replay = replayConfirmedDisproof(root, "subject_mod.nim",
                                         coutFuncDef(), modelRaw,
                                         coutParseBound())
    check replay.agreed
    check replay.diagnostics.len == 0
    check replay.payload.anyIt(it == "input.length=3")
    check replay.payload.anyIt(it.startsWith("propertyViolated=") and
                               it.contains("bvsge") and
                               it.contains("bvsdiv") and
                               it.contains("bvmul"))
    check replay.payload.anyIt(it == "replay.verdict=rvAgree")
    check replay.payload.anyIt(it.startsWith("replay.subjectGitRef=") and
      it.substr("replay.subjectGitRef=".len).len >= 40)
    check gitHead(root).len == 40

# ---------------------------------------------------------------------------
# Suite 4 — pipeline verdict projection: PROPOSITION_DISPROVED(C_out) over the honest
# subject (the contract layer's disproof needs no mutant)
# ---------------------------------------------------------------------------

proc runCoutPipeline(root: string): IrPipelineResult =
  var memo = initTable[string, IrPipelineResult]()
  let ve = synthCout(root).get
  let pve = ValidatedIrEntry(entry: ve.entry, funcDef: ve.funcDef,
                             parseBound: ve.parseBound)
  runIrPipelineWithCas(pve, nil, memo, bpRequire, root)

suite "C_out pipeline — PROPOSITION_DISPROVED projection (glossary §2.2)":

  let res = runCoutPipeline(goldenRoot)

  test "the honest subject's C_out obligation is refuted — or fails closed":
    # The suite header documents exactly two accepted states: the clean-tree
    # PROPOSITION_DISPROVED terminal state and the dirty-worktree fail-closed demotion
    # (replay rvUnavailable → cvUnresolved) — never a fabricated verdict.
    check not res.success
    if res.counterExample.len > 0:
      # Clean Axiom worktree: the exact documented terminal state, with the
      # replay-agreement record the PROPOSITION_DISPROVED payload carries.
      check res.verification.status == vsDisproved
      check res.counterExample.anyIt(it == "replay.verdict=rvAgree")
    else:
      # Dirty Axiom worktree: the documented fail-closed demotion.
      check res.verification.status == vsInconclusive
      check res.verification.reason == rkCandidateCounterexample
      check res.verification.evidence.startsWith("replay:")

  test "the claim leg derives clDisproved":
    check res.verifiedClaim.isSome
    check res.verifiedClaim.get.outcome == clDisproved

  test "the counterexample payload carries the four PROPOSITION_DISPROVED elements — or fails closed":
    if res.counterExample.len > 0:
      # ① exact subject commit (the measured subject git identity)
      check res.counterExample.anyIt(it.startsWith("replay.subjectGitRef=") and
        it.substr("replay.subjectGitRef=".len).len >= 40)
      # ② exact input: the SAT model binds L=3
      check res.counterExample.anyIt(it == "input.length=3")
      # ③ the violated conjunct: ((L*179) div 277) >= 2
      check res.counterExample.anyIt(
        it.startsWith("propertyViolated=") and it.contains("bvsge") and
        it.contains("bvsdiv"))
      # ④ the replay observation (real-toolchain reproduction record)
      check res.counterExample.anyIt(it == "replay.verdict=rvAgree")
      check res.verification.status == vsDisproved
    else:
      # Dirty Axiom worktree: the adapter MUST fail closed — cvUnresolved
      # demotion carrying the replay diagnostics, never a fabricated
      # PROPOSITION_DISPROVED.
      check res.verification.status == vsInconclusive
      check res.verification.reason == rkCandidateCounterexample
      check res.verification.evidence.startsWith("replay:")

  echo "C_out binding tests done (state dir: " & getEnv("AXIOM_STATE_DIR") & ")"
