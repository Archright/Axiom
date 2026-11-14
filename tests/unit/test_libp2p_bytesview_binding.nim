## nim-libp2p BytesView.toOpenArray slice-length binding — slice tests.
##
## SSOT: docs/spec/nim_libp2p_bytesview_slice_contract.md +
## config/spec/nim_libp2p_bytesview_slice.json (SPEC-LIBP2P-BV-SLICE).
##
## Measured here:
##   1. The committed overlay loads through the soExplicit authority path and
##      pins the adopted length domain (1 <= e <= 5), the two carrier MODELS
##      (e at b = 1 — the FIXED template's actual length, law conformance;
##      e + 1 at b = 0), the two adopted LAW sides (e at
##      b = 1, e + 1 at b = 0 — stated as DATA in canonicalSpecIR, not as
##      engine prose), the exact-commit subject pin, and the adoption
##      provenance. Every tampered shape fails closed (pure validation core).
##   2. The subject pin is a REAL check (not the d2 lane's format check):
##      verifyLibp2pBytesviewSubjectPin hashes the module bytes found at the
##      recorded path under the subject root and fails closed on any
##      mismatch; a root without the governed module is inert.
##   3. The synthesized carrier pair: CONSTRUCTED-IR length models — the
##      defect body is e (the FIXED template's actual length at b = 1), the
##      control body is e + 1; the preconditions
##      are the domain conjuncts; the claim `model == law` is β-spliced with
##      exactly one body instance; the parse bound carries the honest
##      single-origin legs (the subject symbol is a TEMPLATE — no extraction
##      happened) plus the stamped replay harness template.
##   4. The replay binding: the stamped harness observes the ORIGINAL
##      template through its defining module — an end-to-end replay against
##      the BYTE-EXACT pinned subject decides the observed length against
##      `result == e` (e = 3 → the FIXED template observes 3 → a
##      hypothetical counterexample is contradicted (rvDisagree); the PRE-FIX
##      bytes observed 2 → rvAgree; the observation, not the model, decides).
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
import ../../src/core/trusted/verification_result_types as vrt

putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_libp2p_bv_test_state")

# The BYTE-EXACT pinned subject module (Archright/nim-libp2p @ d9e8769c,
# fix/bytesview-toopenarray-slice-bounds, libp2p/utils/bytesview.nim, blob
# sha256 e5c73a4fc4b4f390a74a95078809639f4773510e029673c3fb7884d53f584c85).
# The fixture is a COPY for the out-of-tree replay: the subject tree itself is
# READ-ONLY (Zero-Footprint) and is never written by this test. The bytes are
# embedded verbatim so the pin check and the replay observe the SUBJECT's own
# template arithmetic — the runtime assertion below re-measures the digest, so
# a drifted copy fails loudly instead of silently passing.
const BvSubjectModuleBytes* =
  "# SPDX-License-Identifier: Apache-2.0 OR MIT\n" &
  "# Copyright (c) Status Research & Development GmbH\n" &
  "\n" &
  "type BytesView* = object\n" &
  "  data: seq[byte]\n" &
  "  rpos: int\n" &
  "\n" &
  "proc init*(t: typedesc[BytesView], data: sink seq[byte]): BytesView =\n" &
  "  BytesView(data: data, rpos: 0)\n" &
  "\n" &
  "func len*(v: BytesView): int =\n" &
  "  v.data.len - v.rpos\n" &
  "\n" &
  "func consume*(v: var BytesView, n: int) =\n" &
  "  doAssert v.data.len >= v.rpos + n\n" &
  "  v.rpos += n\n" &
  "\n" &
  "template toOpenArray*(v: BytesView, b, e: int): openArray[byte] =\n" &
  "  v.data.toOpenArray(v.rpos + b, v.rpos + e)\n" &
  "\n" &
  "template data*(v: BytesView): openArray[byte] =\n" &
  "  v.data.toOpenArray(v.rpos, v.data.len - 1)\n"

proc fixtureResolver(root: string): ModuleContentResolver =
  result = proc(modulePath: string): Option[string] {.raises: [].} =
    try:
      some(readFile(root / modulePath))
    except CatchableError:
      none(string)

proc committedOverlayNode(): JsonNode =
  parseJson(readFile(repoRootConst() / "config" / "spec" /
                     "nim_libp2p_bytesview_slice.json"))

proc bvFixtureRoot(dirName: string; moduleBytes: string): string =
  ## A subject-root fixture carrying the governed module at the overlay's
  ## pinned path. No git repository here: the pin check reads the module
  ## bytes only (the git identity belongs to the replay's own fixture).
  let root = getTempDir() / dirName
  removeDir(root)
  createDir(root / "libp2p" / "utils")
  writeFile(root / "libp2p" / "utils" / "bytesview.nim", moduleBytes)
  root

# ---------------------------------------------------------------------------
# Suite 1 — overlay loader (soExplicit authority, fail-closed validation)
# ---------------------------------------------------------------------------

suite "bytesview slice overlay — soExplicit load + fail-closed validation":

  test "the committed overlay loads and pins the adopted domain, models, and laws":
    let loaded = loadNimLibp2pBytesviewSliceOverlayDomain()
    check loaded.isOk()
    let domain = loaded.get()
    check domain.modulePath == "libp2p/utils/bytesview.nim"
    check domain.symbols == @["toOpenArray"]
    check domain.importModule == "libp2p/utils/bytesview"
    check domain.subjectBlobSha256 ==
      "e5c73a4fc4b4f390a74a95078809639f4773510e029673c3fb7884d53f584c85"
    check domain.domainVar == "e"
    check domain.domainLower == 1
    check domain.domainBound == 5
    check domain.ruleId == "external:libp2p/bytesview/slice-length-law"
    # The DEFECT model: the FIXED template's actual length at b = 1 → e
    # (law conformance — the model equals the law side for every e).
    check domain.defectModel.kind == irVar
    check domain.defectModel.varName == "e"
    # The defect LAW side: the inclusive view-relative law at b = 1 → e.
    check domain.defectLaw.kind == irVar
    check domain.defectLaw.varName == "e"
    # The CONTROL model: the same template at b = 0 → e + 1.
    check domain.controlModel.kind == irBinOp
    check domain.controlModel.binOp == boAdd
    check domain.controlModel.binLhs.varName == "e"
    check domain.controlModel.binRhs.litVal == 1
    # The control LAW side: the inclusive law at b = 0 → e + 1.
    check domain.controlLaw.kind == irBinOp
    check domain.controlLaw.binOp == boAdd
    check domain.controlLaw.binRhs.litVal == 1
    check domain.defectGroundingSymbol == "toOpenArray"
    check domain.controlGroundingSymbol == "toOpenArray"
    check domain.defectGroundingLines == "18-19"
    check domain.controlGroundingLines == "18-19, 21-22"

  test "the committed overlay is an authorized soExplicit spec":
    let specRes = explicitSpecFromOverlay(committedOverlayNode())
    check specRes.isOk()
    let spec = specRes.get()
    check spec.origin == soExplicit
    check isAuthorizedForVerification(spec.origin)
    # The law is DATA: the canonical spec IR names one law symbol per
    # carrier, so the engine binds the claim without hardcoding law content.
    check spec.canonicalSpecIR.len == 6
    check spec.canonicalSpecIR.contains("bvSliceLenLaw1(e) == e")
    check spec.canonicalSpecIR.contains("bvSliceLenActual(e) == e")
    check spec.canonicalSpecIR.contains("bvSliceLenLaw0(e) == (e + 1)")
    check spec.canonicalSpecIR.contains("bvSliceLenControl(e) == (e + 1)")

  test "overlayDeclaresLibp2pBytesviewSubject governs only the pinned subject":
    let domain = loadNimLibp2pBytesviewSliceOverlayDomain().get()
    check overlayDeclaresLibp2pBytesviewSubject(domain, "toOpenArray",
                                                 "libp2p/utils/bytesview.nim")
    check not overlayDeclaresLibp2pBytesviewSubject(domain, "len",
                                                      "libp2p/utils/bytesview.nim")
    check not overlayDeclaresLibp2pBytesviewSubject(domain, "toOpenArray",
                                                      "libp2p/utils/other.nim")
    check not overlayDeclaresLibp2pBytesviewSubject(domain, "toOpenArray",
                                                      "stew/base36.nim")

  test "overlayDeclaresLibp2pBytesviewSubject matches the constructed carrier names":
    ## The carriers are constructed IR with no subject-parse presence, so
    ## without carrier-name matching a canonical --target naming one is not
    ## frontier-addressable at all. The module gate stays.
    let domain = loadNimLibp2pBytesviewSliceOverlayDomain().get()
    check overlayDeclaresLibp2pBytesviewSubject(domain, BvSliceLenDefectCarrierName,
                                                 "libp2p/utils/bytesview.nim")
    check overlayDeclaresLibp2pBytesviewSubject(domain, BvSliceLenControlCarrierName,
                                                 "libp2p/utils/bytesview.nim")
    check not overlayDeclaresLibp2pBytesviewSubject(domain,
                                                      BvSliceLenDefectCarrierName,
                                                      "libp2p/utils/other.nim")

  test "libp2pBytesviewCarrierTargetRouting routes canonical carrier targets, nothing else":
    let domain = loadNimLibp2pBytesviewSliceOverlayDomain().get()
    block:
      let (routed, fn, module) = libp2pBytesviewCarrierTargetRouting(
        "libp2p/utils/bytesview.nim::" & BvSliceLenDefectCarrierName, domain)
      check routed
      check fn == BvSliceLenDefectCarrierName
      check module == "libp2p/utils/bytesview.nim"
    block:
      let (routed, fn, module) = libp2pBytesviewCarrierTargetRouting(
        "libp2p/utils/bytesview.nim::" & BvSliceLenControlCarrierName, domain)
      check routed
      check fn == BvSliceLenControlCarrierName
      check module == "libp2p/utils/bytesview.nim"
    # Governed parsed symbols route through the same predicate
    block:
      let (routed, fn, module) = libp2pBytesviewCarrierTargetRouting(
        "libp2p/utils/bytesview.nim::toOpenArray", domain)
      check routed
      check fn == "toOpenArray"
      check module == "libp2p/utils/bytesview.nim"
    # A BARE carrier name routes to the overlay's own module (the constructed
    # carrier exists in exactly one module, so the bare name is unambiguous).
    block:
      let (routed, fn, module) = libp2pBytesviewCarrierTargetRouting(
        BvSliceLenDefectCarrierName, domain)
      check routed
      check fn == BvSliceLenDefectCarrierName
      check module == "libp2p/utils/bytesview.nim"
    # Malformed / non-governed targets never route
    check libp2pBytesviewCarrierTargetRouting(
      "::" & BvSliceLenDefectCarrierName, domain).routed == false
    check libp2pBytesviewCarrierTargetRouting(
      "libp2p/utils/bytesview.nim::", domain).routed == false
    check libp2pBytesviewCarrierTargetRouting(
      "bvSliceLenUnknown", domain).routed == false
    # Ungoverned symbols / other modules never route
    check libp2pBytesviewCarrierTargetRouting(
      "libp2p/utils/bytesview.nim::len", domain).routed == false
    check libp2pBytesviewCarrierTargetRouting(
      "libp2p/utils/other.nim::" & BvSliceLenDefectCarrierName,
      domain).routed == false

  test "fail-closed: a non-explicit origin is rejected":
    var node = committedOverlayNode()
    node["specOrigin"] = %"soMined"
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()

  test "fail-closed: a missing overlay document never yields a domain":
    ## The loader's read path (missing/unreadable document) and the pure
    ## validation core agree: no document, no domain.
    check validateNimLibp2pBytesviewSliceOverlayNode(nil).isErr()
    check validateNimLibp2pBytesviewSliceOverlayNode(newJObject()).isErr()

  test "fail-closed: the canonicalSpecIR must be a non-empty array":
    var node = committedOverlayNode()
    node["canonicalSpecIR"] = %[]
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()

  test "fail-closed: the clause count is exact (six roles)":
    var node = committedOverlayNode()
    node["canonicalSpecIR"].elems.delete(3)
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()
    node = committedOverlayNode()
    node["canonicalSpecIR"].elems.add(%"bvSliceLenExtra(e) == e")
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()

  test "fail-closed: clause 1 must be '<low> <= <var>'":
    var node = committedOverlayNode()
    node["canonicalSpecIR"].elems[0] = %"e >= 1"
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()

  test "fail-closed: the domain must bind one variable":
    var node = committedOverlayNode()
    node["canonicalSpecIR"].elems[1] = %"n <= 5"
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()

  test "fail-closed: the named definitions must name the carriers and their laws":
    var node = committedOverlayNode()
    node["canonicalSpecIR"].elems[2] = %"bvSliceLenLawX(e) == e"
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()
    node = committedOverlayNode()
    node["canonicalSpecIR"].elems[3] = %"bvSliceLenModel(e) == (e - 1)"
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()

  test "fail-closed: a law body outside the closed grammar is rejected":
    var node = committedOverlayNode()
    node["canonicalSpecIR"].elems[2] = %"bvSliceLenLaw1(e) == (e * 2)"
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()
    node = committedOverlayNode()
    node["canonicalSpecIR"].elems[3] = %"bvSliceLenActual(e) == (e - 1 + 2)"
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()

  test "fail-closed: the subject pin needs the exact-commit fields":
    var node = committedOverlayNode()
    delete(node["subject"], "blobSha256")
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()
    node = committedOverlayNode()
    node["subject"]["blobSha256"] = %"b205c969"
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()
    node = committedOverlayNode()
    delete(node["subject"], "commit")
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()

  test "fail-closed: the adoption provenance is required":
    var node = committedOverlayNode()
    delete(node["claimOwnership"], "provenance")
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()

  test "fail-closed: caveats and non-claims must be non-empty":
    var node = committedOverlayNode()
    node["nonClaims"] = %[]
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()

  test "fail-closed: exactly one defect and one control carrier":
    var node = committedOverlayNode()
    node["carriers"].elems.delete(1)
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()
    node = committedOverlayNode()
    node["carriers"][0]["kind"] = %"advisory"
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()
    node = committedOverlayNode()
    node["carriers"][1]["groundingSymbol"] = %""
    check validateNimLibp2pBytesviewSliceOverlayNode(node).isErr()

# ---------------------------------------------------------------------------
# Suite 2 — the REAL subject-pin check (module bytes, not a format check)
# ---------------------------------------------------------------------------

suite "bytesview slice subject pin — byte-level blob verification":

  test "the embedded fixture IS the pinned subject (the digest is re-measured)":
    let domain = loadNimLibp2pBytesviewSliceOverlayDomain().get()
    check sha256Hex(BvSubjectModuleBytes) == domain.subjectBlobSha256

  test "the pin verifies against matching module bytes":
    let root = bvFixtureRoot("ax_libp2p_bv_pin_ok", BvSubjectModuleBytes)
    let domain = loadNimLibp2pBytesviewSliceOverlayDomain().get()
    let pin = verifyLibp2pBytesviewSubjectPin(domain, root)
    check pin.isOk()
    check pin.get == true

  test "fail-closed: a blob mismatch rejects the subject tree":
    let root = bvFixtureRoot("ax_libp2p_bv_pin_ok", BvSubjectModuleBytes)
    let domain = loadNimLibp2pBytesviewSliceOverlayDomain().get()
    writeFile(root / "libp2p" / "utils" / "bytesview.nim",
              BvSubjectModuleBytes & "# mutated\n")
    let pin = verifyLibp2pBytesviewSubjectPin(domain, root)
    check pin.isErr()
    check pin.error.contains("blob mismatch")
    check pin.error.contains("does not bind this subject tree")

  test "fail-closed: a WRONG pinned digest (the stale v1.0.0-era digest) fails the pin":
    let root = bvFixtureRoot("ax_libp2p_bv_pin_wrong", BvSubjectModuleBytes)
    var node = committedOverlayNode()
    node["subject"]["blobSha256"] = %"b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ef"
    let domain = validateNimLibp2pBytesviewSliceOverlayNode(node).get
    check domain.subjectBlobSha256 !=
      "b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee"
    let pin = verifyLibp2pBytesviewSubjectPin(domain, root)
    check pin.isErr()
    check pin.error.contains("blob mismatch")

  test "inert: a subject root without the governed module is ok(false)":
    let root = getTempDir() / "ax_libp2p_bv_pin_absent"
    removeDir(root)
    createDir(root)
    let domain = loadNimLibp2pBytesviewSliceOverlayDomain().get()
    let pin = verifyLibp2pBytesviewSubjectPin(domain, root)
    check pin.isOk()
    check pin.get == false

  test "a non-file governed path (directory) is treated as absent (inert)":
    let root = getTempDir() / "ax_libp2p_bv_pin_notfile"
    removeDir(root)
    createDir(root / "libp2p" / "utils" / "bytesview.nim")  # a DIRECTORY
    let domain = loadNimLibp2pBytesviewSliceOverlayDomain().get()
    let pin = verifyLibp2pBytesviewSubjectPin(domain, root)
    check pin.isOk()
    check pin.get == false

# ---------------------------------------------------------------------------
# Suite 3 — the synthesized constructed-IR carrier pair
# ---------------------------------------------------------------------------

proc synthCarriers(root: string): Option[ExternalCandidateCensus] =
  ## Synthesize the carrier pair from the committed overlay over `root`.
  var census = ExternalCandidateCensus()
  let domainRes = loadNimLibp2pBytesviewSliceOverlayDomain()
  if domainRes.isErr:
    return none(ExternalCandidateCensus)
  let synth = synthesizeNimLibp2pBytesviewSliceCandidate(
    "toOpenArray", domainRes.get().modulePath,
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

# The carrier pair is synthesized ONCE for the whole test: the §2.1a
# parse-bound legs are re-measured per synthesis and that measurement is the
# expensive part of the run. The lazy module-level binding keeps the
# measurement at exactly one occurrence.
let bvCensus = synthCarriers(bvFixtureRoot("ax_libp2p_bv_synth", BvSubjectModuleBytes))

suite "bytesview slice synthesis — two constructed-IR length carriers":

  let census = bvCensus

  test "both carriers are recorded, and the eligible pair rides the census":
    check census.isSome
    let c = census.get
    check c.records.len == 2
    let names = c.records.mapIt(it.functionName).sorted
    check names == @["bvSliceLenActual", "bvSliceLenControl"]
    check c.eligible.len == 2

  test "the defect carrier is wave-faced under the examined symbol":
    let defect = census.get.eligible.filterIt(
      it.entry.name == "toOpenArray")
    check defect.len == 1
    check defect[0].funcDef.name == "bvSliceLenActual"

  test "the defect body is the FIXED template's actual length at b = 1 (e)":
    let fd = census.get.carrier("bvSliceLenActual").funcDef
    check fd.name == "bvSliceLenActual"
    check fd.params.len == 1
    check fd.params[0].name == "e"
    check fd.retType != nil and fd.retType.kind == irtBitVec64
    check fd.body.kind == irVar and fd.body.varName == "e"

  test "the control body is the same template at b = 0 (e + 1)":
    let fd = census.get.carrier("bvSliceLenControl").funcDef
    check fd.name == "bvSliceLenControl"
    check fd.params.len == 1
    check fd.params[0].name == "e"
    check fd.body.kind == irBinOp
    check fd.body.binOp == boAdd
    check fd.body.binLhs.kind == irVar and fd.body.binLhs.varName == "e"
    check fd.body.binRhs.kind == irLit and fd.body.binRhs.litVal == 1

  test "preconditions are the adopted domain conjuncts":
    let fd = census.get.carrier("bvSliceLenActual").funcDef
    check fd.preConditions.len == 2
    check fd.preConditions[0].kind == irBinOp
    check fd.preConditions[0].binOp == boGe
    check fd.preConditions[0].binLhs.varName == "e"
    check fd.preConditions[0].binRhs.litVal == 1
    check fd.preConditions[1].kind == irBinOp
    check fd.preConditions[1].binOp == boLe
    check fd.preConditions[1].binLhs.varName == "e"
    check fd.preConditions[1].binRhs.litVal == 5

  test "the claim post is `model == law` β-spliced with exactly one body instance":
    let defectFd = census.get.carrier("bvSliceLenActual").funcDef
    check defectFd.postConditions.len == 1
    let post = defectFd.postConditions[0]
    check post.kind == irBinOp
    check post.binOp == boEq
    # LHS: the spliced model (e) — the result slot was REPLACED by a
    # structural clone of the carrier body (a bare variable).
    check post.binLhs.kind == irVar and post.binLhs.varName == "e"
    # RHS: the adopted LAW side (e) — the law is data, not engine prose.
    check post.binRhs.kind == irVar and post.binRhs.varName == "e"
    # the spliced claim carries NO dangling `result` var (the debug printer
    # renders every irVar as `name:Type`)
    check "result:" notin $post
    check "e:" in $post
    # the control carrier's spliced claim is (e + 1) == (e + 1)
    let controlFd = census.get.carrier("bvSliceLenControl").funcDef
    let controlPost = controlFd.postConditions[0]
    check controlPost.kind == irBinOp and controlPost.binOp == boEq
    check controlPost.binLhs.kind == irBinOp and controlPost.binLhs.binOp == boAdd
    check controlPost.binRhs.kind == irBinOp and controlPost.binRhs.binOp == boAdd
    check controlPost.binLhs.binRhs.litVal == 1
    check controlPost.binRhs.binRhs.litVal == 1

  test "the parse bound is single-origin with honest legs and the stamped harness":
    let defect = census.get.carrier("bvSliceLenActual")
    check defect.parseBound.synthesizedComposite
    check defect.parseBound.claimCarrierSingleOrigin
    check defect.parseBound.measuredForFuncName == "toOpenArray"
    check defect.parseBound.ea2MeasuredForFuncName.len == 0
    check defect.parseBound.synthesisDerivationDigest.len > 0
    # The subject symbol is a TEMPLATE: no extraction happened, so the EA legs
    # record the honest unmeasurability, never a fabricated agreement.
    check not defect.parseBound.eaAgreed
    check defect.parseBound.eaDetail.len > 0
    let control = census.get.carrier("bvSliceLenControl")
    check control.parseBound.measuredForFuncName == "toOpenArray"
    check not control.parseBound.eaAgreed

  test "the stamped harness template names the subject module and the model slot":
    let defect = census.get.carrier("bvSliceLenActual")
    let tpl = defect.parseBound.replayHarnessTemplate
    check tpl.len > 0
    check tpl.contains("import libp2p/utils/bytesview")
    check tpl.contains("var bv = BytesView.init(@[byte 1, 2, 3, 4, 5, 6])")
    check tpl.contains("$(bv.toOpenArray(1, <lit>).len)")
    check tpl.contains("AXIOM_REPLAY_BEGIN")
    check tpl.contains("AXIOM_REPLAY_END")
    check tpl.contains("<module>") == false

  test "dedupe: a second governed hit records nothing new":
    # The census is REUSED (not re-synthesized): the dedupe branch is the
    # first thing the synthesizer decides, so the §2.1a parse-bound legs are
    # not re-measured for a second hit.
    var census2 = census.get
    let domain = loadNimLibp2pBytesviewSliceOverlayDomain().get()
    let second = synthesizeNimLibp2pBytesviewSliceCandidate(
      "toOpenArray", domain.modulePath,
      fixtureResolver(getTempDir() / "ax_libp2p_bv_synth"), domain, census2)
    check second.isOk()
    check second.value == false
    check census2.records.len == 2
    check census2.eligible.len == 2

  test "fail-closed: unreadable subject module bytes refuse synthesis":
    var census3 = ExternalCandidateCensus()
    let domain = loadNimLibp2pBytesviewSliceOverlayDomain().get()
    let missing = synthesizeNimLibp2pBytesviewSliceCandidate(
      "toOpenArray", domain.modulePath,
      fixtureResolver(getTempDir() / "ax_libp2p_bv_missing_root"), domain, census3)
    check missing.isErr()
    check missing.error.contains("module bytes unavailable")
    check census3.records.len == 0

# ---------------------------------------------------------------------------
# Suite 4 — the replay binding: the ORIGINAL template decides
# ---------------------------------------------------------------------------

proc evalIr(e: IRExpr; env: Table[string, ConcreteValue]): Option[bool] =
  let v = evalConcreteIr(e, env)
  if v.isNone or v.get.kind != ckBool: none(bool) else: some(v.get.b)

proc modelRawFor(v: int64): string =
  "sat\n(define-fun e () (_ BitVec 64) #x" & toHex(v, 16) & ")\n"

proc makeSubjectFixture(dirName: string): string =
  ## A git-backed fixture subject whose libp2p/utils/bytesview.nim carries the
  ## BYTE-EXACT pinned module: the replay harness binds against it exactly
  ## the way it binds against the pristine subject (import + the template's
  ## own expansion).
  let root = getTempDir() / dirName
  removeDir(root)
  createDir(root / "libp2p" / "utils")
  writeFile(root / "libp2p" / "utils" / "bytesview.nim", BvSubjectModuleBytes)
  discard execCmdEx("git -C \"" & root & "\" init -q",
                    options = {poStdErrToStdOut, poUsePath})
  discard execCmdEx("git -C \"" & root & "\" add -A",
                    options = {poStdErrToStdOut, poUsePath})
  discard execCmdEx("git -C \"" & root & "\" -c user.name=ax -c user.email=ax@test commit -q -m init",
                    options = {poStdErrToStdOut, poUsePath})
  root

const BvPreFixModuleBytes* =
  "# A FIXTURE subject carrying the PRE-FIX (v1.0.0-pinned) template body —\n" &
  "# v.data.toOpenArray(v.rpos + b, v.rpos + e - b) — the historical defect.\n" &
  "# It exists so the replay can be observed AGREEING with a solver\n" &
  "# counterexample model: the mechanism that produced the v1.0.0 disproof\n" &
  "# still detects the defect bytes (historical control).\n" &
  "type BytesView* = object\n" &
  "  data: seq[byte]\n" &
  "  rpos: int\n" &
  "\n" &
  "proc init*(t: typedesc[BytesView], data: sink seq[byte]): BytesView =\n" &
  "  BytesView(data: data, rpos: 0)\n" &
  "\n" &
  "func len*(v: BytesView): int =\n" &
  "  v.data.len - v.rpos\n" &
  "\n" &
  "template toOpenArray*(v: BytesView, b, e: int): openArray[byte] =\n" &
  "  v.data.toOpenArray(v.rpos + b, v.rpos + e - b)\n"

proc makePreFixSubjectFixture(dirName: string): string =
  ## The historical-control fixture: the same subject shape, but the PRE-FIX
  ## (v1.0.0-era) template body whose length violates the adopted law.
  let root = getTempDir() / dirName
  removeDir(root)
  createDir(root / "libp2p" / "utils")
  writeFile(root / "libp2p" / "utils" / "bytesview.nim", BvPreFixModuleBytes)
  discard execCmdEx("git -C \"" & root & "\" init -q",
                    options = {poStdErrToStdOut, poUsePath})
  discard execCmdEx("git -C \"" & root & "\" add -A",
                    options = {poStdErrToStdOut, poUsePath})
  discard execCmdEx("git -C \"" & root & "\" -c user.name=ax -c user.email=ax@test commit -q -m init",
                    options = {poStdErrToStdOut, poUsePath})
  root

suite "bytesview slice replay — the ORIGINAL template's length decides":
  # The carrier pair is REUSED from the synthesis suite: the replay consumes
  # the funcDef + the stamped harness template, and the §2.1a parse-bound
  # legs are measured once per run (they are the expensive part).

  test "compositeReplayShape is empty for the stamped binding (template owns the harness)":
    let defect = bvCensus.get.carrier("bvSliceLenActual")
    let shape = compositeReplayShape(defect.funcDef, defect.parseBound)
    check shape.outerSymbol.len == 0
    check shape.innerSymbol.len == 0
    check shape.carrierTypename.len == 0

  test "dry-run: the observed length is evaluated against the adopted law concretely":
    ## e = 3: the FIXED template yields 3 where the law demands 3 → the
    ## conformance claim HOLDS for the pinned instance; a hypothetical solver
    ## counterexample would be contradicted by the observation. The
    ## observation enters the decision — the model alone cannot produce it.
    let defectFd = bvCensus.get.carrier("bvSliceLenActual").funcDef
    # The claim the solver decided is the SPLICED model-equals-law equality
    # ((e) == e) — it holds for every e in the domain (law conformance).
    let claim = defectFd.postConditions[0]
    check claim.kind == irBinOp and claim.binOp == boEq
    var env = initTable[string, ConcreteValue]()
    env["e"] = ConcreteValue(kind: ckInt, i: 3)
    check evaluatePostconditions(defectFd.postConditions, env) == some(true)
    # The REPLAY postcondition (what the adapter evaluates on the OBSERVED
    # value) is `result == <law side>` — the observed length against the
    # adopted law.
    let replayPost = irEq(irVar("result", defectFd.retType), claim.binRhs)
    env["result"] = ConcreteValue(kind: ckInt, i: 2)
    check evaluatePostconditions(@[replayPost], env) == some(false)
    # a law-satisfying observation (the law's own value) HOLDS → the solver
    # model would be contradicted (rvDisagree)
    env["result"] = ConcreteValue(kind: ckInt, i: 3)
    check evaluatePostconditions(@[replayPost], env) == some(true)
    check decideReplayVerdict(harnessRan = true,
      propertyHolds = some(false)) == rvAgree
    check decideReplayVerdict(harnessRan = true,
      propertyHolds = some(true)) == rvDisagree

  test "end-to-end: replay against the FIXED pinned template — a hypothetical counterexample disagrees":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_libp2p_bv_test_state")
    let root = makeSubjectFixture("ax_libp2p_bv_replay")
    let defect = bvCensus.get.carrier("bvSliceLenActual")
    # The FIXED template's actual length at b = 1, e = 3 is 3 — equal to the
    # law — so a (hypothetical) solver counterexample claim is CONTRADICTED
    # by the observation (rvDisagree): the pipeline cannot report a disproof
    # it did not observe. Under the v1.1.0 conformance model no counterexample
    # exists, so this lane is the anti-theater backstop.
    let disagreed = replayConfirmedDisproof(root,
      "libp2p/utils/bytesview.nim", defect.funcDef, modelRawFor(3),
      defect.parseBound)
    check not disagreed.agreed
    check disagreed.diagnostics.startsWith("rvDisagree")

  test "end-to-end: the observation decides — the PRE-FIX defect bytes still agree (historical control)":
    ## The anti-theater direction: the ORIGINAL template's arithmetic, not the
    ## model, decides the agreement. The v1.0.0-era subject (v.rpos + e - b)
    ## observes 2 at (b = 1, e = 3) where the law demands 3 — a solver
    ## counterexample over THOSE bytes would be CONFIRMED (rvAgree): the
    ## replay mechanism that produced the v1.0.0 disproof still detects the
    ## defect bytes.
    let root = makePreFixSubjectFixture("ax_libp2p_bv_replay_agree_prefix")
    let defect = bvCensus.get.carrier("bvSliceLenActual")
    let agreed = replayConfirmedDisproof(root,
      "libp2p/utils/bytesview.nim", defect.funcDef, modelRawFor(3),
      defect.parseBound)
    check agreed.agreed
    check agreed.diagnostics.len == 0
    check agreed.payload.anyIt(it == "input.e=3")
    check agreed.payload.anyIt(it == "replay.verdict=rvAgree")

  echo "bytesview slice binding tests done (state dir: " &
        getEnv("AXIOM_STATE_DIR") & ")"
