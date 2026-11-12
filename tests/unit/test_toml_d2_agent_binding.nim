## toml d2-agent string-control-gate binding — S2 slice tests.
##
## SSOT: docs/spec/toml_d2_agent_binding_contract.md +
## config/spec/toml_d2_agent_spec.json (SPEC-TOML-D2-AGENT) +
## experiments/act2-wp-toml-b1-input-integrity/p0d2g/AGENT_SPEC.md (adopted
## spec content).
##
## Measured here:
##   1. The committed overlay loads through the soExplicit authority path and
##      pins the adopted byte domain (1 <= c <= 255, structural exclusions
##      10/13/34/92), the forbid set (<=8, 10..31, 127), the code's actual
##      gate ({8,16,31,127}), the exact-commit subject pin, and the adoption
##      provenance. Every tampered shape fails closed (pure validation core).
##   2. The synthesized carrier pair: CONSTRUCTED-IR bool predicates — the
##      defect body is the four-member gate, the control body is forbid
##      exactly; preconditions are the domain conjuncts; the claim
##      `result == forbid` is β-spliced with exactly one body instance; the
##      parse bound carries the honest single-origin legs (EA unmeasured on
##      the generic gate procs) plus the stamped replay harness template.
##   3. The replay binding: the stamped harness observes the ORIGINAL decoder
##      through its public API — an end-to-end replay against a fixture
##      module decides the observed raise-boolean against `result == forbid`
##      (c=7 → rvAgree; a control member c=16 → rvDisagree — the observation,
##      not the model, decides).
import std/[algorithm, json, os, osproc, options, tables, strutils, sequtils, unittest]
import ../../src/core/results
import ../../src/core/crypto/hash_kernel
import ../../src/core/utils/repo_root
import ../../src/core/trusted/specification_artifact
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

putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_toml_d2_test_state")

proc fixtureResolver(root: string): ModuleContentResolver =
  result = proc(modulePath: string): Option[string] {.raises: [].} =
    try:
      some(readFile(root / modulePath))
    except CatchableError:
      none(string)

proc committedOverlayNode(): JsonNode =
  parseJson(readFile(repoRootConst() / "config" / "spec" /
                     "toml_d2_agent_spec.json"))

# ---------------------------------------------------------------------------
# Suite 1 — overlay loader (soExplicit authority, fail-closed validation)
# ---------------------------------------------------------------------------

suite "d2-agent overlay — soExplicit load + fail-closed validation":

  test "the committed overlay loads and pins the adopted domain, sets, and pin":
    let loaded = loadTomlD2AgentOverlayDomain()
    check loaded.isOk()
    let domain = loaded.get()
    check domain.modulePath == "toml_serialization/lexer.nim"
    check domain.symbols == @["scanString", "scanSingleLineString",
                              "scanMultiLineString"]
    check domain.domainVar == "c"
    check domain.domainLower == 1
    check domain.domainBound == 255
    check domain.exclusions == @[10'i64, 13, 34, 92]
    check domain.forbidLow == 8
    check domain.forbidMidLo == 10
    check domain.forbidMidHi == 31
    check domain.forbidEq == 127
    check domain.defectGates == @[8'i64, 16, 31, 127]
    check domain.importModule == "toml_serialization"
    check domain.defectGroundingSymbol == "scanSingleLineString"
    check domain.controlGroundingSymbol == "nonws"
    check domain.ruleId == "external:toml-serialization/string-control-gate"

  test "the committed overlay is an authorized soExplicit spec":
    let specRes = explicitSpecFromOverlay(committedOverlayNode())
    check specRes.isOk()
    let spec = specRes.get()
    check spec.origin == soExplicit
    check isAuthorizedForVerification(spec.origin)

  test "overlayDeclaresD2AgentSubject governs only the pinned subject":
    let domain = loadTomlD2AgentOverlayDomain().get()
    check overlayDeclaresD2AgentSubject(domain, "scanString",
                                        "toml_serialization/lexer.nim")
    check overlayDeclaresD2AgentSubject(domain, "scanSingleLineString",
                                        "toml_serialization/lexer.nim")
    check overlayDeclaresD2AgentSubject(domain, "scanMultiLineString",
                                        "toml_serialization/lexer.nim")
    check not overlayDeclaresD2AgentSubject(domain, "parseValue",
                                            "toml_serialization/lexer.nim")
    check not overlayDeclaresD2AgentSubject(domain, "scanString",
                                            "toml_serialization/reader.nim")
    check not overlayDeclaresD2AgentSubject(domain, "decodedLength",
                                            "stew/base36.nim")

  test "overlayDeclaresD2AgentSubject matches the constructed carrier names (standalone targetability)":
    ## The carriers are constructed IR with no subject-parse presence, so
    ## without carrier-name matching a canonical --target naming one is not
    ## frontier-addressable at all (exit 2 NotFound). The module gate stays:
    ## carrier names in a DIFFERENT module stay ungoverned.
    let domain = loadTomlD2AgentOverlayDomain().get()
    check overlayDeclaresD2AgentSubject(domain, D2AgentControlCarrierName,
                                        "toml_serialization/lexer.nim")
    check overlayDeclaresD2AgentSubject(domain, D2AgentDefectCarrierName,
                                        "toml_serialization/lexer.nim")
    check not overlayDeclaresD2AgentSubject(domain, D2AgentControlCarrierName,
                                            "toml_serialization/reader.nim")
    check not overlayDeclaresD2AgentSubject(domain, D2AgentDefectCarrierName,
                                            "stew/base36.nim")

  test "d2AgentCarrierTargetRouting routes canonical carrier targets, nothing else":
    let domain = loadTomlD2AgentOverlayDomain().get()
    block:
      let (routed, fn, module) = d2AgentCarrierTargetRouting(
        "toml_serialization/lexer.nim::" & D2AgentControlCarrierName, domain)
      check routed
      check fn == D2AgentControlCarrierName
      check module == "toml_serialization/lexer.nim"
    block:
      let (routed, fn, module) = d2AgentCarrierTargetRouting(
        "toml_serialization/lexer.nim::" & D2AgentDefectCarrierName, domain)
      check routed
      check fn == D2AgentDefectCarrierName
      check module == "toml_serialization/lexer.nim"
    # Governed parsed symbols route through the same predicate
    block:
      let (routed, fn, module) = d2AgentCarrierTargetRouting(
        "toml_serialization/lexer.nim::scanString", domain)
      check routed
      check fn == "scanString"
      check module == "toml_serialization/lexer.nim"
    # Non-canonical targets never route
    check d2AgentCarrierTargetRouting(D2AgentControlCarrierName, domain).routed == false
    check d2AgentCarrierTargetRouting("::" & D2AgentControlCarrierName, domain).routed == false
    check d2AgentCarrierTargetRouting(
      "toml_serialization/lexer.nim::", domain).routed == false
    # Ungoverned symbols / other modules never route
    check d2AgentCarrierTargetRouting(
      "toml_serialization/lexer.nim::parseValue", domain).routed == false
    check d2AgentCarrierTargetRouting(
      "toml_serialization/reader.nim::" & D2AgentControlCarrierName,
      domain).routed == false

  test "fail-closed: a non-explicit origin is rejected":
    var node = committedOverlayNode()
    node["specOrigin"] = %"soMined"
    check validateTomlD2AgentOverlayNode(node).isErr()

  test "fail-closed: the clause count is exact (nine roles)":
    var node = committedOverlayNode()
    node["canonicalSpecIR"].elems.delete(3)
    check validateTomlD2AgentOverlayNode(node).isErr()

  test "fail-closed: clause 1 must be '<low> <= <var>'":
    var node = committedOverlayNode()
    node["canonicalSpecIR"].elems[0] = %"c >= 1"
    check validateTomlD2AgentOverlayNode(node).isErr()

  test "fail-closed: exclusion clauses must be '<var> != <INT>'":
    var node = committedOverlayNode()
    node["canonicalSpecIR"].elems[3] = %"c == 10"
    check validateTomlD2AgentOverlayNode(node).isErr()

  test "fail-closed: the domain must bind one variable":
    var node = committedOverlayNode()
    node["canonicalSpecIR"].elems[1] = %"b <= 255"
    check validateTomlD2AgentOverlayNode(node).isErr()

  test "fail-closed: the forbid definition must be the canonical disjunction":
    var node = committedOverlayNode()
    node["canonicalSpecIR"].elems[6] =
      %"forbid(c) == ((c <= 8) or (c <= 31) or (c == 127))"
    check validateTomlD2AgentOverlayNode(node).isErr()

  test "fail-closed: the control carrier must be set-equal to forbid":
    var node = committedOverlayNode()
    node["canonicalSpecIR"].elems[8] =
      %"d2CommentGateReject(c) == ((c <= 8) or ((10 <= c) and (c <= 30)) or (c == 127))"
    check validateTomlD2AgentOverlayNode(node).isErr()

  test "fail-closed: the defect gate must be a four-member equality chain":
    var node = committedOverlayNode()
    node["canonicalSpecIR"].elems[7] =
      %"d2StringGateReject(c) == ((c == 8) or (c == 16) or (c == 127))"
    check validateTomlD2AgentOverlayNode(node).isErr()

  test "fail-closed: the carrier names are the binding's kernel names":
    var node = committedOverlayNode()
    node["canonicalSpecIR"].elems[7] =
      %"wrongGateName(c) == ((c == 8) or (c == 16) or (c == 31) or (c == 127))"
    check validateTomlD2AgentOverlayNode(node).isErr()

  test "fail-closed: the subject pin needs the exact-commit fields":
    var node = committedOverlayNode()
    delete(node["subject"], "blobSha256")
    check validateTomlD2AgentOverlayNode(node).isErr()
    node = committedOverlayNode()
    node["subject"]["blobSha256"] = %"19d69eed"
    check validateTomlD2AgentOverlayNode(node).isErr()
    node = committedOverlayNode()
    delete(node["subject"], "commit")
    check validateTomlD2AgentOverlayNode(node).isErr()

  test "fail-closed: the adoption provenance is required":
    var node = committedOverlayNode()
    delete(node["claimOwnership"], "provenance")
    check validateTomlD2AgentOverlayNode(node).isErr()

  test "fail-closed: caveats and non-claims must be non-empty":
    var node = committedOverlayNode()
    node["nonClaims"] = %[]
    check validateTomlD2AgentOverlayNode(node).isErr()

  test "fail-closed: exactly one defect and one control carrier":
    var node = committedOverlayNode()
    node["carriers"].elems.delete(1)
    check validateTomlD2AgentOverlayNode(node).isErr()
    node = committedOverlayNode()
    node["carriers"][0]["kind"] = %"advisory"
    check validateTomlD2AgentOverlayNode(node).isErr()
    node = committedOverlayNode()
    node["carriers"][1]["groundingSymbol"] = %""
    check validateTomlD2AgentOverlayNode(node).isErr()

# ---------------------------------------------------------------------------
# Suite 2 — synthesized constructed-IR carrier pair
# ---------------------------------------------------------------------------

proc synthCarriers(root: string): Option[ExternalCandidateCensus] =
  ## Synthesize the carrier pair from the committed overlay over `root`.
  var census = ExternalCandidateCensus()
  let domainRes = loadTomlD2AgentOverlayDomain()
  if domainRes.isErr:
    return none(ExternalCandidateCensus)
  let synth = synthesizeTomlD2AgentCandidate(
    "scanString", domainRes.get().modulePath,
    fixtureResolver(root), domainRes.get(), census)
  if synth.isErr:
    return none(ExternalCandidateCensus)
  some(census)

proc carrier(census: ExternalCandidateCensus; name: string): ExternalIrEntry =
  for e in census.eligible:
    if e.funcDef.name == name:
      return e
  # Unreachable when the suite's eligibility expectations hold; an empty
  # funcDef makes the failure loud instead of segfaulting.
  ExternalIrEntry(funcDef: IRFuncDef(name: "<missing>"))

# A minimal subject stub: the synthesizer is INDEPENDENT of the subject body
# (constructed IR), so the fixture only needs the module bytes the entries
# carry for the §2.1a binding inputs.
const D2SubjectStub = """## toml_serialization/lexer.nim fixture stub (binding-inputs carrier only)
proc nonws*(lex: var int, skip: static[bool]): char = ' '
proc scanSingleLineString*[T](lex: var int, res: var T, kind: static[bool]) =
  discard
"""

suite "d2-agent subject pin — REAL byte-hash verification":
  ## The lane's subject pin is a REAL check (the historical format-only
  ## 64-hex validation is retired): the governed module's bytes under the
  ## run's subject root must hash to the overlay's pinned digest. A tree
  ## that presents the module with any other content fails closed; a tree
  ## without the governed module keeps the binding inert.

  proc pinDomain(pinned: string): TomlD2AgentOverlayDomain =
    var d = loadTomlD2AgentOverlayDomain().get()
    d.subjectBlobSha256 = pinned
    d

  test "the committed overlay carries the pinned subject digest":
    let d = loadTomlD2AgentOverlayDomain().get()
    check d.subjectBlobSha256 == "19d69eed84f74c51fa1784b2e71a4525abc8d2b8aa854c567565d2d603133f4d"

  test "matching bytes verify (ok(true))":
    let root = getTempDir() / "ax_toml_d2_pin_ok"
    removeDir(root)
    createDir(root / "toml_serialization")
    writeFile(root / "toml_serialization" / "lexer.nim", D2SubjectStub)
    let d = pinDomain(sha256Hex(D2SubjectStub))
    let res = verifyTomlD2AgentSubjectPin(d, root)
    check res.isOk()
    check res.get() == true

  test "mismatched bytes fail closed (blob mismatch)":
    let root = getTempDir() / "ax_toml_d2_pin_bad"
    removeDir(root)
    createDir(root / "toml_serialization")
    writeFile(root / "toml_serialization" / "lexer.nim", D2SubjectStub)
    let d = pinDomain(sha256Hex("not the subject bytes"))
    let res = verifyTomlD2AgentSubjectPin(d, root)
    check res.isErr()
    check "blob mismatch" in res.error

  test "absent governed module stays inert (ok(false))":
    let root = getTempDir() / "ax_toml_d2_pin_absent"
    removeDir(root)
    createDir(root)
    let d = pinDomain(sha256Hex("x"))
    let res = verifyTomlD2AgentSubjectPin(d, root)
    check res.isOk()
    check res.get() == false

proc d2FixtureRoot(dirName: string): string =
  let root = getTempDir() / dirName
  removeDir(root)
  createDir(root / "toml_serialization")
  writeFile(root / "toml_serialization" / "lexer.nim", D2SubjectStub)
  root

suite "d2-agent synthesis — two constructed-IR carriers":

  let census = synthCarriers(d2FixtureRoot("ax_toml_d2_synth"))

  test "both carriers are recorded, and the eligible pair rides the census":
    check census.isSome
    let c = census.get
    check c.records.len == 2
    let names = c.records.mapIt(it.functionName).sorted
    check names == @["d2CommentGateReject", "d2StringGateReject"]
    check c.eligible.len == 2

  test "the defect carrier is wave-faced under the examined symbol":
    let defect = census.get.eligible.filterIt(
      it.entry.name == "scanString")
    check defect.len == 1
    check defect[0].funcDef.name == "d2StringGateReject"

  test "the defect body is the code's actual four-member gate":
    let fd = census.get.carrier("d2StringGateReject").funcDef
    check fd.name == "d2StringGateReject"
    check fd.params.len == 1
    check fd.params[0].name == "c"
    check fd.retType != nil and fd.retType.kind == irtBool
    # (c == 8) or (c == 16) or (c == 31) or (c == 127) — left-associated or
    var node = fd.body
    var members: seq[int64]
    for i in 0 ..< 3:
      check node.kind == irBinOp
      check node.binOp == boOr
      check node.binRhs.kind == irBinOp
      check node.binRhs.binOp == boEq
      check node.binRhs.binLhs.kind == irVar
      check node.binRhs.binLhs.varName == "c"
      check node.binRhs.binRhs.kind == irLit
      members.add(node.binRhs.binRhs.litVal)
      node = node.binLhs
    check node.kind == irBinOp
    check node.binOp == boEq
    check node.binLhs.kind == irVar and node.binLhs.varName == "c"
    check node.binRhs.kind == irLit
    members.add(node.binRhs.litVal)
    check members == @[127'i64, 31, 16, 8]

  test "the control body is forbid exactly":
    let fd = census.get.carrier("d2CommentGateReject").funcDef
    check fd.name == "d2CommentGateReject"
    # (c <= 8) or ((10 <= c) and (c <= 31)) or (c == 127)
    let node = fd.body
    check node.kind == irBinOp
    check node.binOp == boOr
    # left disjunct: (c <= 8) or ((10 <= c) and (c <= 31))
    let left = node.binLhs
    check left.kind == irBinOp and left.binOp == boOr
    check left.binLhs.kind == irBinOp and left.binLhs.binOp == boLe
    check left.binLhs.binLhs.varName == "c" and left.binLhs.binRhs.litVal == 8
    let mid = left.binRhs
    check mid.kind == irBinOp and mid.binOp == boAnd
    check mid.binLhs.binOp == boGe and mid.binLhs.binLhs.varName == "c" and
      mid.binLhs.binRhs.litVal == 10
    check mid.binRhs.binOp == boLe and mid.binRhs.binRhs.litVal == 31
    # right disjunct: c == 127
    check node.binRhs.kind == irBinOp and node.binRhs.binOp == boEq
    check node.binRhs.binRhs.litVal == 127

  test "preconditions are the adopted domain conjuncts":
    let fd = census.get.carrier("d2StringGateReject").funcDef
    check fd.preConditions.len == 6
    check fd.preConditions[0].binOp == boGe
    check fd.preConditions[0].binRhs.litVal == 1
    check fd.preConditions[1].binOp == boLe
    check fd.preConditions[1].binRhs.litVal == 255
    for i in 2 ..< 6:
      check fd.preConditions[i].kind == irUnaryOp
      check fd.preConditions[i].unaryOp == uoNot
      check fd.preConditions[i].unaryArg.binOp == boEq
    check fd.preConditions[2].unaryArg.binRhs.litVal == 10
    check fd.preConditions[3].unaryArg.binRhs.litVal == 13
    check fd.preConditions[4].unaryArg.binRhs.litVal == 34
    check fd.preConditions[5].unaryArg.binRhs.litVal == 92

  test "the claim post is `result == forbid` β-spliced with exactly one body instance":
    let defectFd = census.get.carrier("d2StringGateReject").funcDef
    check defectFd.postConditions.len == 1
    let post = defectFd.postConditions[0]
    # The result slot was REPLACED by a structural clone of the gate body;
    # the RHS is the forbid set.
    check post.kind == irBinOp
    check post.binOp == boEq
    check post.binLhs.kind == irBinOp and post.binLhs.binOp == boOr
    check post.binLhs.binRhs.binRhs.litVal == 127
    check post.binLhs.binLhs.binRhs.binRhs.litVal == 31
    check post.binRhs.kind == irBinOp
    # the spliced claim carries NO dangling `result` var (the debug printer
    # renders every irVar as `name:Type`)
    check "result:" notin $post
    check "c:" in $post
    # the control carrier's spliced claim is forbid == forbid
    let controlFd = census.get.carrier("d2CommentGateReject").funcDef
    let controlPost = controlFd.postConditions[0]
    check controlPost.binOp == boEq
    check controlPost.binLhs.binOp == boOr and controlPost.binRhs.binOp == boOr
    check controlPost.binLhs.binRhs.binRhs.litVal == 127
    check controlPost.binRhs.binRhs.binRhs.litVal == 127

  test "the parse bound is single-origin with honest legs and the stamped harness":
    let defect = census.get.carrier("d2StringGateReject")
    check defect.parseBound.synthesizedComposite
    check defect.parseBound.claimCarrierSingleOrigin
    check defect.parseBound.measuredForFuncName == "scanSingleLineString"
    check defect.parseBound.ea2MeasuredForFuncName.len == 0
    check defect.parseBound.synthesisDerivationDigest.len > 0
    # The EA differential measures EA_UNSUPPORTED on the generic gate proc —
    # the legs record the honest unmeasurability, never a fabricated agreement.
    check not defect.parseBound.eaAgreed
    check defect.parseBound.eaDetail.contains("EA_UNSUPPORTED")
    check defect.parseBound.compositeCarrierTypename.len == 0
    let control = census.get.carrier("d2CommentGateReject")
    check control.parseBound.measuredForFuncName == "nonws"
    check not control.parseBound.eaAgreed

  test "the stamped harness template names the public API and the model slot":
    let defect = census.get.carrier("d2StringGateReject")
    let tpl = defect.parseBound.replayHarnessTemplate
    check tpl.len > 0
    check tpl.contains("import toml_serialization")
    check tpl.contains(
      "Toml.decode(\"k = \\\"a\" & chr(<lit>) & \"b\\\"\", TomlValueRef)")
    check tpl.contains("except TomlError")
    check tpl.contains("AXIOM_REPLAY_BEGIN")
    check tpl.contains("AXIOM_REPLAY_END")
    check tpl.contains("<module>") == false

  test "dedupe: a second governed hit records nothing new":
    var census2 = synthCarriers(d2FixtureRoot("ax_toml_d2_dedupe")).get
    let domain = loadTomlD2AgentOverlayDomain().get()
    let second = synthesizeTomlD2AgentCandidate(
      "scanSingleLineString", domain.modulePath,
      fixtureResolver(d2FixtureRoot("ax_toml_d2_dedupe")), domain, census2)
    check second.isOk()
    check second.value == false
    check census2.records.len == 2
    check census2.eligible.len == 2

  test "fail-closed: unreadable subject module bytes refuse synthesis":
    var census3 = ExternalCandidateCensus()
    let domain = loadTomlD2AgentOverlayDomain().get()
    let missing = synthesizeTomlD2AgentCandidate(
      "scanString", domain.modulePath,
      fixtureResolver(getTempDir() / "ax_toml_d2_missing_root"), domain, census3)
    check missing.isErr()
    check missing.error.contains("module bytes unavailable")
    check census3.records.len == 0

# ---------------------------------------------------------------------------
# Suite 3 — the replay binding: the ORIGINAL decoder decides
# ---------------------------------------------------------------------------

proc evalIr(e: IRExpr; env: Table[string, ConcreteValue]): Option[bool] =
  let v = evalConcreteIr(e, env)
  if v.isNone or v.get.kind != ckBool: none(bool) else: some(v.get.b)

proc gitHead(root: string): string =
  let (outp, code) = execCmdEx("git -C \"" & root & "\" rev-parse HEAD",
                               options = {poStdErrToStdOut, poUsePath})
  if code == 0: outp.strip() else: ""

proc makeSubjectFixture(dirName: string): string =
  ## A fixture subject whose PUBLIC API behaves like the pristine decoder's
  ## reject decision on string content: raise on {8,16,31,127}, accept
  ## otherwise. The replay harness binds against this module exactly the
  ## way it binds against the pristine subject (import + Toml.decode).
  let root = getTempDir() / dirName
  removeDir(root)
  createDir(root / "toml_serialization")
  writeFile(root / "toml_serialization" / "lexer.nim", D2SubjectStub)
  writeFile(root / "toml_serialization.nim", """type
  TomlError* = object of CatchableError
  TomlValue* = object
  TomlValueRef* = ref TomlValue

type TomlDecoder* = object

proc decode*(d: TomlDecoder, doc: string, T: type TomlValueRef): TomlValueRef =
  for ch in doc:
    if ord(ch) in {8, 16, 31, 127}:
      raise newException(TomlError, "invalid control char: " & $ord(ch))
  result = TomlValueRef()

let Toml* = TomlDecoder()
""")
  discard execCmdEx("git -C \"" & root & "\" init -q",
                    options = {poStdErrToStdOut, poUsePath})
  discard execCmdEx("git -C \"" & root & "\" add -A",
                    options = {poStdErrToStdOut, poUsePath})
  discard execCmdEx("git -C \"" & root & "\" -c user.name=ax -c user.email=ax@test commit -q -m init",
                    options = {poStdErrToStdOut, poUsePath})
  root

proc modelRawFor(v: int64): string =
  "sat\n(define-fun c () (_ BitVec 64) #x" & toHex(v, 16) & ")\n"

suite "d2-agent replay — stamped harness, observed raise-boolean":

  test "compositeReplayShape is empty for the stamped binding (template owns the harness)":
    let d2 = synthCarriers(d2FixtureRoot("ax_toml_d2_shape")).get
    let defect = d2.carrier("d2StringGateReject")
    let shape = compositeReplayShape(defect.funcDef, defect.parseBound)
    check shape.outerSymbol.len == 0
    check shape.innerSymbol.len == 0
    check shape.carrierTypename.len == 0

  test "dry-run: the observed raise-boolean is evaluated against forbid concretely":
    ## c=7: observed false (no raise), forbid(7) = true → propertyHolds=false
    ## → rvAgree. The observation enters the decision — the model alone
    ## cannot produce it.
    let d2 = synthCarriers(d2FixtureRoot("ax_toml_d2_dry")).get
    let defectFd = d2.carrier("d2StringGateReject").funcDef
    var env = initTable[string, ConcreteValue]()
    env["c"] = ConcreteValue(kind: ckInt, i: 7)
    env["result"] = ConcreteValue(kind: ckBool, b: false)
    check evaluatePostconditions(defectFd.postConditions, env) == some(false)
    # control member: c=16 raises → observed true, forbid(16) = true → holds
    env["c"] = ConcreteValue(kind: ckInt, i: 16)
    env["result"] = ConcreteValue(kind: ckBool, b: true)
    check evaluatePostconditions(defectFd.postConditions, env) == some(true)
    check decideReplayVerdict(harnessRan = true,
      propertyHolds = some(false)) == rvAgree
    check decideReplayVerdict(harnessRan = true,
      propertyHolds = some(true)) == rvDisagree

  test "end-to-end: replay against the ORIGINAL decoder — c=7 agrees, c=16 disagrees":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_toml_d2_test_state")
    let root = makeSubjectFixture("ax_toml_d2_replay")
    let d2 = synthCarriers(root).get
    let defect = d2.carrier("d2StringGateReject")
    # The model's gap member: the decoder accepts the raw byte (no raise) →
    # observed false, forbid(7) = true → the violation reproduces → rvAgree.
    let agreed = replayConfirmedDisproof(root,
      "toml_serialization/lexer.nim", defect.funcDef, modelRawFor(7),
      defect.parseBound)
    check agreed.agreed
    check agreed.diagnostics.len == 0
    check agreed.payload.anyIt(it == "input.c=7")
    check agreed.payload.anyIt(it == "replay.verdict=rvAgree")
    check agreed.payload.anyIt(it.startsWith("propertyViolated=") and
                               it.contains("="))
    check agreed.payload.anyIt(it.startsWith("replay.subjectGitRef=") and
      it.substr("replay.subjectGitRef=".len).len >= 40)
    check gitHead(root).len == 40
    # A gate member (c=16): the decoder RAISES → observed true, forbid(16) =
    # true → the property holds on the observation → the solver model is
    # contradicted (rvDisagree). This is the anti-theater direction: the
    # ORIGINAL code, not the model, decides.
    let disagreed = replayConfirmedDisproof(root,
      "toml_serialization/lexer.nim", defect.funcDef, modelRawFor(16),
      defect.parseBound)
    check not disagreed.agreed
    check disagreed.diagnostics.startsWith("rvDisagree")

# ---------------------------------------------------------------------------
# Suite 4 — pipeline verdict projection over the honest fixture subject
# ---------------------------------------------------------------------------

proc runD2Pipeline(root: string; name: string): IrPipelineResult =
  var memo = initTable[string, IrPipelineResult]()
  let c = synthCarriers(root).get
  let ve = ValidatedIrEntry(entry: c.carrier(name).entry,
                            funcDef: c.carrier(name).funcDef,
                            parseBound: c.carrier(name).parseBound)
  runIrPipelineWithCas(ve, nil, memo, bpRequire, root)

suite "d2-agent pipeline — the differential decides":

  let root = makeSubjectFixture("ax_toml_d2_pipeline")

  test "the defect carrier's obligation is refuted — or fails closed":
    # Exactly two accepted states, as for the C_out binding: the clean-tree
    # PROPOSITION_DISPROVED terminal state (replay agreed on the ORIGINAL code) and the
    # dirty-worktree fail-closed demotion — never a fabricated verdict.
    let res = runD2Pipeline(root, "d2StringGateReject")
    check not res.success
    if res.counterExample.len > 0:
      check res.verification.status == vsDisproved
      check res.counterExample.anyIt(it == "replay.verdict=rvAgree")
      # The exact replay input is the SOLVER's witness byte — a forbid-set
      # member outside the defect gate (the claim is refuted exactly there).
      # The binding contract commits the witness SET ("every forbid member
      # outside {8,16,31,127}, e.g. c = 7" — contract §body), not z3's model
      # choice; the concrete byte is solver-deterministic, never
      # contract-pinned. Checked against the adopted overlay domain.
      let inputLines = res.counterExample.filterIt(it.startsWith("input.c="))
      check inputLines.len == 1
      let witness: int64 = int64(parseInt(inputLines[0]["input.c=".len .. ^1]))
      let domain = loadTomlD2AgentOverlayDomain().get()
      check witness >= domain.domainLower and witness < domain.domainBound
      check not domain.exclusions.contains(witness)
      let forbidHolds = (witness <= domain.forbidLow) or
        (domain.forbidMidLo <= witness and witness <= domain.forbidMidHi) or
        (witness == domain.forbidEq)
      check forbidHolds
      check not domain.defectGates.contains(witness)
    else:
      check res.verification.status == vsInconclusive
      check res.verification.evidence.len > 0 or
            res.verification.reason != rkNone

  test "the control carrier (forbid == forbid) does not refute":
    # The control is set-equal to forbid on the domain — a SAT there would
    # indict the spec injection itself. Honest states: no replayed PROPOSITION_DISPROVED
    # payload, and a verdict that is not a disproof (proved / no-obligation /
    # fail-closed inconclusive all carry no counterExample payload).
    let res = runD2Pipeline(root, "d2CommentGateReject")
    check res.counterExample.len == 0
    check res.verification.status != vsDisproved

  echo "d2-agent binding tests done (state dir: " & getEnv("AXIOM_STATE_DIR") & ")"
