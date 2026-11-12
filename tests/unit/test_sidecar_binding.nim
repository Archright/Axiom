## Nim proposition sidecar with HASH-BOUND adoption — slice tests.
##
## SSOT: docs/spec/nim_stew_base36_sidecar_contract.md +
## config/spec/nim_stew_base36_sidecar.json (SPEC-B36-SIDECAR).
##
## Measured here:
##   1. The committed sidecar loads through the soExplicit authority path and
##      the adoption record hash-binds the loaded proposition content
##      (specIdentity recomputed vs adoptedSpecHash, byte-exact). Every
##      tampered shape fails closed (pure validation core): a mutated clause,
##      a mutated ruleVersion, a foreign grammar version, a grammar-outside
##      expression, an unknown identifier.
##   2. The subject pin is a REAL check (not the d2 lane's format check):
##      verifySidecarSubjectPin hashes the module bytes found at the recorded
##      path under the subject root and fails closed on any mismatch; a root
##      without the governed module is inert.
##   3. The synthesized carrier pair over the VERBATIM golden fixture:
##      defect + control, each carrying the ORIGINAL subject body unchanged,
##      the adopted pre asserted, the adopted post β-spliced exactly once,
##      expectedObligation declared, census-eligible, single-origin parse
##      bound measured on decodedLength with the typedesc carrier token.
##   4. The replay shape: `decodedLength(<carrier>, <valueLit>)` — harness
##      rendering plus a real-toolchain end-to-end replay of
##      decodedLength(Base36Types, 1) = 0 against the adopted claim
##      (result == (length + 4); propertyHolds == false → rvAgree).
##   5. The pipeline verdict for the defect carrier: SAT → P4 → replay
##      rvAgree → PROPOSITION_DISPROVED (or the documented dirty-worktree fail-closed
##      demotion — exactly two accepted states, never a fabricated verdict).
##      The control carrier's UNSAT rides the same z3 machinery and is the
##      frozen experiment's injection guard (P2 runs it; not re-run here).
import std/[json, os, osproc, options, tables, strutils, sequtils, unittest]

import ../../src/core/results
import ../../src/core/crypto/hash_kernel
import ../../src/core/utils/repo_root
import ../../src/core/trusted/specification_artifact
import ../../src/core/trusted/axiom_pragmas
import ../../src/core/trusted/axiom_ir
import ../../src/core/trusted/axiom_ir_helpers
import ../../src/infrastructure/external_ir_materializer
import ../../src/cli/axiom_engine
import ../../src/verification/obligation/canonical_verification
import ../../src/verification/counterexample_replay
import ../../src/verification/batch_uap/ir_pipeline_runner
import ../../src/core/trusted/verification_result_types as vrt

putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_sidecar_test_state")

let testsRoot = currentSourcePath().parentDir().parentDir()
let goldenRoot = testsRoot / "golden" / "base36_subject"

proc fixtureResolver(root: string): ModuleContentResolver =
  result = proc(modulePath: string): Option[string] {.raises: [].} =
    try:
      some(readFile(root / modulePath))
    except CatchableError:
      none(string)

proc committedSidecarNode(): JsonNode =
  parseJson(readFile(repoRootConst() / "config" / "spec" /
                     "nim_stew_base36_sidecar.json"))

proc synthSidecar(root: string): Option[ExternalIrEntry] =
  ## Synthesize the sidecar carrier pair from the committed sidecar over
  ## `root`; return the wave-facing DEFECT entry.
  var census = ExternalCandidateCensus()
  let domainRes = loadNimSidecarOverlayDomain()
  if domainRes.isErr:
    return none(ExternalIrEntry)
  let synth = synthesizeNimSidecarCandidates(
    "decodedLength", domainRes.get().modulePath,
    fixtureResolver(root), domainRes.get(), census)
  if synth.isErr:
    return none(ExternalIrEntry)
  if synth.get != true:
    return none(ExternalIrEntry)
  for e in census.eligible:
    if e.funcDef.name == sidecarCarrierName(domainRes.get(), "defect"):
      return some(e)
  none(ExternalIrEntry)

# ---------------------------------------------------------------------------
# Suite 1 — sidecar loader: soExplicit authority + hash-bound adoption
# ---------------------------------------------------------------------------

suite "sidecar loader — soExplicit load + hash-bound adoption":

  test "the committed sidecar loads and pins the adoption record":
    let loaded = loadNimSidecarOverlayDomain()
    check loaded.isOk()
    let domain = loaded.get()
    check domain.modulePath == "stew/base36.nim"
    check domain.symbol == "decodedLength"
    check domain.valueParam == "length"
    check domain.ruleId == "external:stew/base36/sidecar-adoption"
    check domain.propositions.len == 2
    check domain.propositions[0].kind == "defect"
    check domain.propositions[0].preText == "length == 1"
    check domain.propositions[0].postText == "result == (length + 4)"
    check domain.propositions[1].kind == "control"
    check domain.propositions[1].preText == "length == 2"
    check domain.propositions[1].postText == "result == 1"
    check domain.adoption.grammarVersion == "nim-sidecar-expr-v1"
    check domain.adoption.adoptedAt == "2026-10-19"
    check domain.adoption.adoptedSpecHash ==
      "3f55eaa79f3708894a04d62bc7ac32c9e2a8fe84d4f575348318d7290d237ea8"
    check domain.adoption.subject.commit ==
      "1853f20bdfeda61331a0b7e02f7aace0e88a0dfe"
    check domain.adoption.subject.blobSha256 ==
      "b8a42a6ac6d1057fca0be079aac5750463729fdad771823f1be53b8723a5e0a8"

  test "the committed sidecar is an authorized soExplicit spec":
    let specRes = explicitSpecFromOverlay(committedSidecarNode())
    check specRes.isOk()
    let spec = specRes.get()
    check spec.origin == soExplicit
    check isAuthorizedForVerification(spec.origin)

  test "the adoption record hash-binds the loaded proposition content":
    ## The mechanical adoption-binding invariant: the SpecID recomputed from
    ## the loaded content byte-equals the adoption record's pin.
    let node = committedSidecarNode()
    let specRes = explicitSpecFromOverlay(node)
    check specRes.isOk()
    let computed = specRes.get().specIdentity
    let pinned = node{"adoption"}{"adoptedSpecHash"}.getStr("")
    check computed == pinned
    let loaded = loadNimSidecarOverlayDomain()
    check loaded.isOk()
    check loaded.get().adoption.adoptedSpecHash == computed

  test "fail-closed: a non-explicit origin is rejected":
    var node = committedSidecarNode()
    node["specOrigin"] = %"soMined"
    check validateSidecarOverlayNode(node).isErr()

  test "fail-closed: mutating a proposition clause invalidates the adoption":
    ## THE hash-binding rejection: a self-consistent document (proposition
    ## block AND canonicalSpecIR agree) whose content differs from what the
    ## adoption record pinned — stage (ii) must refuse it. (The mutated
    ## control post `result == 2` is deliberately the false twin of the
    ## defect law: a self-consistent doc that adoption never saw.)
    var node = committedSidecarNode()
    node["propositions"][1]["post"] = %"result == 2"
    node["canonicalSpecIR"] =
      %["length == 1", "result == (length + 4)", "length == 2", "result == 2"]
    let res = validateSidecarOverlayNode(node)
    check res.isErr()
    check res.error.contains("adoption does not bind")

  test "fail-closed: the superseded generation-1 content is rejected against the current record":
    ## The first adoption's defect instance (length == 3 -> result == 2,
    ## adoptedSpecHash 8e9564842090…) is history, not a co-governing content:
    ## replaying it as a self-consistent document fails stage (ii) against
    ## the CURRENT adoption record (contract §8 hash chain).
    var node = committedSidecarNode()
    node["propositions"][0]["pre"] = %"length == 3"
    node["propositions"][0]["post"] = %"result == 2"
    node["canonicalSpecIR"] =
      %["length == 3", "result == 2", "length == 2", "result == 1"]
    let res = validateSidecarOverlayNode(node)
    check res.isErr()
    check res.error.contains("adoption does not bind")

  test "fail-closed: mutating ruleVersion invalidates the adoption":
    var node = committedSidecarNode()
    node["ruleVersion"] = %"1.0.1"
    let res = validateSidecarOverlayNode(node)
    check res.isErr()
    check res.error.contains("adoption does not bind")

  test "fail-closed: a foreign grammarVersion is rejected":
    var node = committedSidecarNode()
    node["adoption"]["grammarVersion"] = %"nim-sidecar-expr-v2"
    check validateSidecarOverlayNode(node).isErr()

  test "fail-closed: a missing adoption object is rejected":
    var node = committedSidecarNode()
    node.delete("adoption")
    check validateSidecarOverlayNode(node).isErr()

  test "fail-closed: a mutated adoptedSpecHash is rejected":
    var node = committedSidecarNode()
    node["adoption"]["adoptedSpecHash"] =
      %("0" & node{"adoption"}{"adoptedSpecHash"}.getStr("").substr(1))
    let res = validateSidecarOverlayNode(node)
    check res.isErr()
    check res.error.contains("adoption does not bind")

  test "fail-closed: a grammar-outside proposition is rejected (no '*')":
    var node = committedSidecarNode()
    node["propositions"][0]["post"] = %"result == length * 2"
    let res = validateSidecarOverlayNode(node)
    check res.isErr()
    check res.error.contains("outside the closed grammar")

  test "fail-closed: an unknown identifier is rejected":
    var node = committedSidecarNode()
    node["propositions"][0]["pre"] = %"width == 3"
    let res = validateSidecarOverlayNode(node)
    check res.isErr()
    check res.error.contains("unknown identifier")

  test "fail-closed: propositions must be exactly one defect + one control":
    var node = committedSidecarNode()
    node["propositions"][1]["kind"] = %"defect"
    check validateSidecarOverlayNode(node).isErr()

  test "fail-closed: canonicalSpecIR and propositions must state one content":
    var node = committedSidecarNode()
    node["canonicalSpecIR"] =
      %["length == 1", "result == (length + 4)", "length == 2", "result == 1", "1 <= length"]
    check validateSidecarOverlayNode(node).isErr()

  test "fail-closed: subject pin fields are format-checked":
    var node = committedSidecarNode()
    node["adoption"]["subject"]["commit"] = %"deadbeef"
    check validateSidecarOverlayNode(node).isErr()
    node = committedSidecarNode()
    node["adoption"]["subject"]["blobSha256"] = %"xyz"
    check validateSidecarOverlayNode(node).isErr()

  test "the sidecar governs only the pinned module+symbol key":
    let domain = loadNimSidecarOverlayDomain().get()
    check overlayDeclaresSidecarSubject(domain, "decodedLength", "stew/base36.nim")
    check not overlayDeclaresSidecarSubject(domain, "decode", "stew/base36.nim")
    check not overlayDeclaresSidecarSubject(domain, "decodedLength", "stew/other.nim")

  test "carrier names derive from the governed symbol per kind":
    let domain = loadNimSidecarOverlayDomain().get()
    check sidecarCarrierName(domain, "defect") == "decodedLength_sidecar_defect"
    check sidecarCarrierName(domain, "control") == "decodedLength_sidecar_control"

# ---------------------------------------------------------------------------
# Suite 2 — the closed grammar (nim-sidecar-expr-v1)
# ---------------------------------------------------------------------------

suite "sidecar closed grammar — nim-sidecar-expr-v1":

  test "the frozen propositions parse to the pinned IR shapes":
    let pre = parseSidecarClosedExpr("length == 1", @["length"], "defect pre")
    check pre.ok
    check pre.expr.kind == irBinOp
    check pre.expr.binOp == boEq
    check pre.expr.binLhs.kind == irVar
    check pre.expr.binLhs.varName == "length"
    check pre.expr.binRhs.kind == irLit
    check pre.expr.binRhs.litVal == 1
    let post = parseSidecarClosedExpr("result == (length + 4)",
                                      @["length"], "defect post")
    check post.ok
    check post.expr.kind == irBinOp
    check post.expr.binOp == boEq
    check post.expr.binLhs.kind == irVar
    check post.expr.binLhs.varName == "result"
    check post.expr.binRhs.kind == irBinOp
    check post.expr.binRhs.binOp == boAdd
    check post.expr.binRhs.binLhs.kind == irVar
    check post.expr.binRhs.binLhs.varName == "length"
    check post.expr.binRhs.binRhs.kind == irLit
    check post.expr.binRhs.binRhs.litVal == 4

  test "additive chains and parentheses parse":
    let e = parseSidecarClosedExpr("(length + 1) == 4", @["length"], "probe")
    check e.ok
    check e.expr.kind == irBinOp
    check e.expr.binOp == boEq
    check e.expr.binLhs.kind == irBinOp
    check e.expr.binLhs.binOp == boAdd

  test "fail-closed: multiplication is outside the grammar":
    let e = parseSidecarClosedExpr("result == length * 2", @["length"], "probe")
    check not e.ok
    check e.reason.contains("outside the closed grammar")

  test "fail-closed: comparisons beyond '==' are outside the grammar":
    check not parseSidecarClosedExpr("length <= 2", @["length"], "probe").ok
    check not parseSidecarClosedExpr("length > 2", @["length"], "probe").ok

  test "fail-closed: a single '=' is outside the grammar":
    let e = parseSidecarClosedExpr("length = 3", @["length"], "probe")
    check not e.ok
    check e.reason.contains("only '=='")

  test "fail-closed: an unknown identifier is outside the grammar":
    let e = parseSidecarClosedExpr("btype == 3", @["length"], "probe")
    check not e.ok
    check e.reason.contains("unknown identifier")

  test "fail-closed: integer literal overflow is outside the grammar":
    let e = parseSidecarClosedExpr("length == 99999999999999999999999",
                                   @["length"], "probe")
    check not e.ok
    check e.reason.contains("overflow")

  test "fail-closed: trailing input after the equality is outside the grammar":
    check not parseSidecarClosedExpr("length == 3 length", @["length"],
                                     "probe").ok

# ---------------------------------------------------------------------------
# Suite 3 — the REAL subject-pin check (module bytes, not a format check)
# ---------------------------------------------------------------------------

suite "sidecar subject pin — byte-level blob verification":

  proc pinnedDomain(blob: string): SidecarDomain =
    var node = committedSidecarNode()
    node["adoption"]["subject"]["blobSha256"] = %blob
    validateSidecarOverlayNode(node).get

  test "the pin verifies against matching module bytes":
    let root = getTempDir() / "ax_sidecar_pin_ok"
    removeDir(root)
    createDir(root / "stew")
    let bytes = "func decodedLength*(btype: typedesc[int], length: int): int =\n" &
                "  (length * 179) div 277\n"
    writeFile(root / "stew" / "base36.nim", bytes)
    let domain = pinnedDomain(sha256Hex(bytes))
    let pin = verifySidecarSubjectPin(domain, root)
    check pin.isOk()
    check pin.get == true

  test "fail-closed: a blob mismatch rejects the subject tree":
    let root = getTempDir() / "ax_sidecar_pin_mutated"
    removeDir(root)
    createDir(root / "stew")
    let bytes = "func decodedLength*(btype: typedesc[int], length: int): int =\n" &
                "  (length * 179) div 277\n"
    writeFile(root / "stew" / "base36.nim", bytes)
    let domain = pinnedDomain(sha256Hex(bytes))
    writeFile(root / "stew" / "base36.nim", bytes & "# mutated\n")
    let pin = verifySidecarSubjectPin(domain, root)
    check pin.isErr()
    check pin.error.contains("blob mismatch")
    check pin.error.contains("adoption does not bind this subject tree")

  test "inert: a subject root without the governed module is ok(false)":
    let root = getTempDir() / "ax_sidecar_pin_absent"
    removeDir(root)
    createDir(root)
    let domain = loadNimSidecarOverlayDomain().get()
    let pin = verifySidecarSubjectPin(domain, root)
    check pin.isOk()
    check pin.get == false

  test "a non-file governed path (directory) is treated as absent (inert)":
    let root = getTempDir() / "ax_sidecar_pin_notfile"
    removeDir(root)
    createDir(root / "stew" / "base36.nim")  # a DIRECTORY at the module path
    let domain = loadNimSidecarOverlayDomain().get()
    # fileExists is false for a directory: no module FILE exists at the
    # recorded path, so the lane is inert here (ok(false)) — the same
    # semantics as an absent module.
    let pin = verifySidecarSubjectPin(domain, root)
    check pin.isOk()
    check pin.get == false

# ---------------------------------------------------------------------------
# Suite 4 — synthesized carrier pair over the VERBATIM golden fixture
# ---------------------------------------------------------------------------

suite "sidecar synthesis — original-body carriers with adopted propositions":

  let domain = loadNimSidecarOverlayDomain().get()
  var census = ExternalCandidateCensus()
  let synth = synthesizeNimSidecarCandidates(
    "decodedLength", domain.modulePath, fixtureResolver(goldenRoot), domain,
    census)

  test "the carrier pair is census-eligible (defect wave-faced, control own)":
    check synth.isOk()
    check synth.get == true
    check census.eligible.len == 2
    check census.eligible[0].funcDef.name == "decodedLength_sidecar_defect"
    check census.eligible[0].entry.name == "decodedLength"
    check census.eligible[1].funcDef.name == "decodedLength_sidecar_control"
    check census.eligible[1].entry.name == "decodedLength_sidecar_control"

  test "the defect carrier body is the subject body, unchanged":
    let fd = census.eligible[0].funcDef
    check fd.name == "decodedLength_sidecar_defect"
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

  test "the defect carrier asserts the adopted pre and β-splices the adopted post":
    let fd = census.eligible[0].funcDef
    check fd.preConditions.len == 1
    check fd.preConditions[0].kind == irBinOp
    check fd.preConditions[0].binOp == boEq
    check fd.preConditions[0].binLhs.kind == irVar
    check fd.preConditions[0].binLhs.varName == "length"
    check fd.preConditions[0].binRhs.kind == irLit
    check fd.preConditions[0].binRhs.litVal == 1
    check fd.postConditions.len == 1
    # `result == (length + 4)` spliced: the result slot was REPLACED by the
    # original body (exactly-once; no dangling `result`, no duplication).
    let post = fd.postConditions[0]
    check post.kind == irBinOp
    check post.binOp == boEq
    # spliced body on the result slot: ((length * 179) div 277)
    check post.binLhs.kind == irBinOp
    check post.binLhs.binOp == boDiv
    check post.binLhs.binRhs.litVal == 277
    check post.binLhs.binLhs.binOp == boMul
    check post.binLhs.binLhs.binLhs.varName == "length"
    # the law's additive tail survives the splice: (length + 4)
    check post.binRhs.kind == irBinOp
    check post.binRhs.binOp == boAdd
    check post.binRhs.binLhs.kind == irVar
    check post.binRhs.binLhs.varName == "length"
    check post.binRhs.binRhs.kind == irLit
    check post.binRhs.binRhs.litVal == 4

  test "the control carrier carries the same body with the control proposition":
    let fd = census.eligible[1].funcDef
    check fd.name == "decodedLength_sidecar_control"
    check fd.body.kind == irBinOp
    check fd.body.binOp == boDiv
    check fd.preConditions.len == 1
    check fd.preConditions[0].binOp == boEq
    check fd.preConditions[0].binLhs.varName == "length"
    check fd.preConditions[0].binRhs.litVal == 2
    check fd.postConditions.len == 1
    check fd.postConditions[0].kind == irBinOp
    check fd.postConditions[0].binOp == boEq
    check fd.postConditions[0].binRhs.litVal == 1

  test "expectedObligation is declared on both carriers":
    check census.eligible[0].entry.expectedObligation
    check census.eligible[1].entry.expectedObligation

  test "the carriers' parse bound is single-origin, measured on decodedLength":
    for e in census.eligible:
      check e.parseBound.synthesizedComposite
      check e.parseBound.claimCarrierSingleOrigin
      check e.parseBound.measuredForFuncName == "decodedLength"
      check e.parseBound.ea2MeasuredForFuncName.len == 0
      check e.parseBound.compositeCarrierTypename == "Base36Types"
      check e.parseBound.eaAgreed
      check e.parseBound.synthesisDerivationDigest.len > 0

  test "fail-closed: a valueParam mismatch refuses synthesis":
    let root = getTempDir() / "ax_sidecar_param_mismatch"
    removeDir(root)
    createDir(root / "stew")
    writeFile(root / "stew" / "base36.nim", """type Base36Types* = object

func decodedLength*(btype: typedesc[Base36Types], a: int): int =
  return (a * 179) div 277
""")
    var mismatchCensus = ExternalCandidateCensus()
    let synth = synthesizeNimSidecarCandidates(
      "decodedLength", domain.modulePath, fixtureResolver(root), domain,
      mismatchCensus)
    check synth.isErr()
    check synth.error.contains("adoption does not bind this signature")
    check mismatchCensus.records.len == 0

  test "fail-closed: a let-bound subject body refuses synthesis (scope guard)":
    let root = getTempDir() / "ax_sidecar_letbound"
    removeDir(root)
    createDir(root / "stew")
    writeFile(root / "stew" / "base36.nim", """type Base36Types* = object

func decodedLength*(btype: typedesc[Base36Types], length: int): int =
  let scaled = length * 179
  return scaled div 277
""")
    var letCensus = ExternalCandidateCensus()
    let synth = synthesizeNimSidecarCandidates(
      "decodedLength", domain.modulePath, fixtureResolver(root), domain,
      letCensus)
    check synth.isErr()
    check synth.error.contains("let-bindings")
    check letCensus.records.len == 0

  test "dedupe: a second synthesis on the same subject records nothing new":
    var dedupeCensus = ExternalCandidateCensus()
    discard synthesizeNimSidecarCandidates(
      "decodedLength", domain.modulePath, fixtureResolver(goldenRoot), domain,
      dedupeCensus)
    let before = dedupeCensus.records.len
    let again = synthesizeNimSidecarCandidates(
      "decodedLength", domain.modulePath, fixtureResolver(goldenRoot), domain,
      dedupeCensus)
    check again.isOk()
    check again.get == false
    check dedupeCensus.records.len == before

# ---------------------------------------------------------------------------
# Suite 5 — replay shape + end-to-end: decodedLength(Base36Types, 1) = 0
# ---------------------------------------------------------------------------

suite "sidecar replay — single-origin shape, real toolchain":

  const SidecarSubject = """type Base36Types* = object

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

  proc sidecarParseBound(): SubjectParseBoundComponents =
    SubjectParseBoundComponents(
      synthesizedComposite: true,
      claimCarrierSingleOrigin: true,
      measuredForFuncName: "decodedLength",
      compositeCarrierTypename: "Base36Types")

  proc defectFuncDef(): IRFuncDef =
    ## The synthesized defect carrier, rebuilt standalone: the ORIGINAL body,
    ## the adopted pre (`length == 1` — the blind agent's suspected input),
    ## the adopted post β-spliced (`<body> == (length + 4)`). Only the VALUE
    ## parameter is a formal — the typedesc discriminator is rendered as the
    ## measured carrier token in the call.
    let length = irVar("length", irTypeBitVec64())
    let body = irDiv(irMul(length, irLit(179)), irLit(277))
    IRFuncDef(
      name: "decodedLength_sidecar_defect",
      params: @[IRFuncParam(name: "length", ty: irTypeBitVec64())],
      retType: irTypeBitVec64(),
      body: body,
      preConditions: @[irEq(length, irLit(1))],
      postConditions: @[irEq(body, irAdd(length, irLit(4)))])

  test "shape derivation: one origin, empty inner, measured carrier token":
    let shape = compositeReplayShape(defectFuncDef(), sidecarParseBound())
    check shape.outerSymbol == "decodedLength"
    check shape.innerSymbol.len == 0
    check shape.carrierTypename == "Base36Types"
    check shape.valueParam == "length"

  test "harness rendering emits the pinned call form decodedLength(Base36Types, 1)":
    let harness = renderReplayHarness("subject_mod", "decodedLength",
                                      @["1"],
                                      "decodedLength(Base36Types, 1)")
    check harness.contains("echo $decodedLength(Base36Types, 1)")

  test "end-to-end: replay of decodedLength(Base36Types, 1) returns 0 → rvAgree":
    ## The real toolchain reproduces the adopted defect: the model binds
    ## length=1, the ORIGINAL body evaluates to 0, and the adopted claim
    ## `result == (length + 4)` concretely fails on the observed result
    ## (0 == 5 is false; propertyHolds == false → rvAgree). rvAgree does NOT
    ## validate the sizing formula's accuracy (Authority 0) — it re-measures
    ## the carried original body.
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_sidecar_test_state")
    let root = makeSubjectFixture("ax_sidecar_replay", SidecarSubject)
    let modelRaw = "sat\n(define-fun length () (_ BitVec 64) " &
                   "#x0000000000000001)\n"
    let replay = replayConfirmedDisproof(root, "subject_mod.nim",
                                         defectFuncDef(), modelRaw,
                                         sidecarParseBound())
    check replay.agreed
    check replay.diagnostics.len == 0
    check replay.payload.anyIt(it == "input.length=1")
    # The adopted claim is an EQUALITY (`result == (length + 4)`) spliced
    # onto the original body: the SMT projection carries the div/mul body
    # tokens and the `=` comparison (no bvsge — that is the C_out `>=`
    # claim's token).
    check replay.payload.anyIt(it.startsWith("propertyViolated=") and
                               it.contains("bvsdiv") and
                               it.contains("bvmul") and
                               it.contains("bvadd") and
                               it.contains("="))
    check replay.payload.anyIt(it == "replay.verdict=rvAgree")
    check replay.payload.anyIt(it.startsWith("replay.subjectGitRef=") and
      it.substr("replay.subjectGitRef=".len).len >= 40)
    check gitHead(root).len == 40

# ---------------------------------------------------------------------------
# Suite 6 — pipeline verdict projection for the defect carrier
# ---------------------------------------------------------------------------

proc runSidecarDefectPipeline(root: string): IrPipelineResult =
  var memo = initTable[string, IrPipelineResult]()
  let ve = synthSidecar(root).get
  let pve = ValidatedIrEntry(entry: ve.entry, funcDef: ve.funcDef,
                             parseBound: ve.parseBound)
  runIrPipelineWithCas(pve, nil, memo, bpRequire, root)

suite "sidecar pipeline — defect SAT → P4 → replay (glossary §2.2)":

  let res = runSidecarDefectPipeline(goldenRoot)

  test "the adopted defect instance is refuted — or fails closed":
    # Exactly two accepted states: the clean-worktree PROPOSITION_DISPROVED terminal
    # state and the dirty-worktree fail-closed demotion (replay
    # rvUnavailable → cvUnresolved) — never a fabricated verdict.
    check not res.success
    if res.counterExample.len > 0:
      check res.verification.status == vsDisproved
      check res.counterExample.anyIt(it == "replay.verdict=rvAgree")
    else:
      check res.verification.status == vsInconclusive
      check res.verification.reason == rkCandidateCounterexample
      check res.verification.evidence.startsWith("replay:")

  test "the counterexample payload carries the four PROPOSITION_DISPROVED elements — or fails closed":
    if res.counterExample.len > 0:
      check res.counterExample.anyIt(it.startsWith("replay.subjectGitRef=") and
        it.substr("replay.subjectGitRef=".len).len >= 40)
      check res.counterExample.anyIt(it == "input.length=1")
      check res.counterExample.anyIt(
        it.startsWith("propertyViolated=") and it.contains("bvsdiv") and
        it.contains("bvmul") and it.contains("bvadd") and it.contains("="))
      check res.counterExample.anyIt(it == "replay.verdict=rvAgree")
      check res.verification.status == vsDisproved
    else:
      check res.verification.status == vsInconclusive
      check res.verification.reason == rkCandidateCounterexample
      check res.verification.evidence.startsWith("replay:")

  echo "sidecar binding tests done (state dir: " & getEnv("AXIOM_STATE_DIR") & ")"
