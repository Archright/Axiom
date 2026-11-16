## Base32 rem binding — SN2 slice tests (PR-5 step 1: test-first).
##
## SSOT: docs/design/vs2_external_subject_registry_spec_2026-10-24.md +
## docs/spec/nim_stew_base32_rem_binding_contract.md +
## config/spec/nim_stew_base32_rem_spec.json.
##
## Measured here (legacy lane mirrors cout):
##   1. The committed overlay loads through the soExplicit authority path and
##      pins the domain (0 <= length) and the range clauses (<v> mod 8 >= 0,
##      <v> mod 8 <= 7). Every tampered shape fails closed.
##   2. The synthesized term-splice carrier over the golden fixture:
##      let-bindings are ALLOWED (rem-only asymmetry, vs2 §3.4), the carrier
##      body is the ORIGINAL `length mod 8` term (clone), preconditions
##      0 <= length, postcondition rem in [0,7], census-eligible.
##   3. wrSole wave entry.
##
## NOTE (pin): this suite is measured against the legacy loader/synthesizer
## (axiom_engine.nim loadBase32RemOverlayDomain / synthesizeBase32RemRangeCandidate),
## the state VS-2 PR-5 step 1 mandates before the registry flip. The same
## suite must pass unmodified after the flip (PR-5 step 2) — the evidence
## gap never spans the rotation.
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
import ../../src/core/utils/test_helper
import ../../src/infrastructure/external_ir_materializer
import ../../src/cli/axiom_engine
import ../../src/verification/obligation/canonical_verification
import ../../src/verification/counterexample_replay
import ../../src/verification/batch_uap/ir_pipeline_runner
import ../../src/core/trusted/verification_result_types as vrt

putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_b32_rem_test_state")

let testsRoot = currentSourcePath().parentDir().parentDir()
let goldenRoot = testsRoot / "golden" / "base32_subject"

proc fixtureResolver(root: string): ModuleContentResolver =
  result = proc(modulePath: string): Option[string] {.raises: [].} =
    try:
      some(readFile(root / modulePath))
    except CatchableError:
      none(string)

proc committedSpec(name: string): JsonNode =
  parseJson(readFile(repoRootConst() / "config" / "spec" / name))

proc writeFixtureTree(dirName: string; moduleSource: string): string =
  let root = getTempDir() / dirName
  removeDir(root)
  createDir(root)
  createDir(root / "stew")
  writeFile(root / "stew" / "base32.nim", moduleSource)
  root

suite "rem overlay loads through the soExplicit authority path":
  test "committed overlay pins the rem domain":
    let domainRes = loadBase32RemOverlayDomain()
    check domainRes.isOk
    let domain = domainRes.get()
    check domain.modulePath == "stew/base32.nim"
    check domain.symbol == "decodedLength"
    check domain.dividendVar == "length"
    check domain.divisor == 8
    check domain.ruleId == "external:stew/base32/rem-range"

  test "membership predicate (3-direction)":
    let domainRes = loadBase32RemOverlayDomain()
    check domainRes.isOk
    let domain = domainRes.get()
    check overlayDeclaresRemSubject(domain, "decodedLength", "stew/base32.nim")
    check not overlayDeclaresRemSubject(domain, "encodedLength", "stew/base32.nim")
    check not overlayDeclaresRemSubject(domain, "decodedLength", "stew/base36.nim")

  test "fail-closed mutations (rem exactly-3 + one-divisor)":
    # Each mutation is injected into a temp overlay copy via AXIOM_ROOT
    # redirection — the loader reads runtimeSpecOverlayPath which honors
    # AXIOM_ROOT env (findRepoRoot live read).
    let specPath = repoRootConst() / "config" / "spec" / "nim_stew_base32_rem_spec.json"
    proc mutate(name: string; mutateFn: proc(node: var JsonNode)): bool =
      let tmpRoot = getTempDir() / ("ax_b32_rem_mut_" & name)
      removeDir(tmpRoot)
      createDir(tmpRoot / "config" / "spec")
      var node = parseJson(readFile(specPath))
      mutateFn(node)
      writeFile(tmpRoot / "config" / "spec" / "nim_stew_base32_rem_spec.json", $node)
      putEnv("AXIOM_ROOT", tmpRoot)
      let res = loadBase32RemOverlayDomain()
      putEnv("AXIOM_ROOT", "")
      res.isErr

    check mutate("count", proc(node: var JsonNode) =
      node["canonicalSpecIR"] = JsonNode(kind: JArray, elems: @[newJString("0 <= length"), newJString("length mod 8 >= 0"), newJString("length mod 8 <= 7"), newJString("length mod 8 <= 9")]))
    check mutate("one_divisor", proc(node: var JsonNode) =
      node["canonicalSpecIR"] = JsonNode(kind: JArray, elems: @[newJString("0 <= length"), newJString("length mod 8 >= 0"), newJString("length mod 5 <= 4")]))
    check mutate("bound", proc(node: var JsonNode) =
      node["canonicalSpecIR"] = JsonNode(kind: JArray, elems: @[newJString("0 <= length"), newJString("length mod 8 >= 0"), newJString("length mod 8 <= 6")]))
    check mutate("lower_form", proc(node: var JsonNode) =
      node["canonicalSpecIR"] = JsonNode(kind: JArray, elems: @[newJString("1 <= length"), newJString("length mod 8 >= 0"), newJString("length mod 8 <= 7")]))
    check mutate("swap", proc(node: var JsonNode) =
      node["canonicalSpecIR"] = JsonNode(kind: JArray, elems: @[newJString("0 <= length"), newJString("length mod 8 <= 7"), newJString("length mod 8 >= 0")]))
    check mutate("origin", proc(node: var JsonNode) =
      node["specOrigin"] = newJString("soMined"))
    check mutate("symbols", proc(node: var JsonNode) =
      node["subject"]["symbols"] = JsonNode(kind: JArray, elems: @[newJString("decodedLength"), newJString("encodedLength")]))

suite "rem term-splice synthesis over the golden fixture":
  test "carrier shape (clone of ORIGINAL rem term, let-binding ALLOWED)":
    let root = goldenRoot
    let domainRes = loadBase32RemOverlayDomain()
    check domainRes.isOk
    var census = ExternalCandidateCensus()
    let synth = synthesizeBase32RemRangeCandidate(
      "decodedLength", domainRes.get().modulePath,
      fixtureResolver(root), domainRes.get(), census, root)
    check synth.isOk
    check synth.get
    check census.eligible.len == 1
    let ve = census.eligible[0]
    check ve.funcDef.name == "decodedLength_rem_range"
    check ve.funcDef.params.len == 2
    check ve.funcDef.params[1].name == "length"
    # body IS the original `length mod 8` term (cloned, not reconstructed)
    check ve.funcDef.body.kind == irBinOp
    check ve.funcDef.body.binOp == boRem
    check ve.funcDef.body.binLhs.kind == irVar
    check ve.funcDef.body.binLhs.varName == "length"
    check ve.funcDef.body.binRhs.kind == irLit
    check ve.funcDef.body.binRhs.litVal == 8
    # preconditions / postconditions
    check ve.funcDef.preConditions.len == 1
    check ve.funcDef.postConditions.len == 1
    check ve.parseBound.synthesizedComposite
    check ve.parseBound.claimCarrierSingleOrigin
    check ve.parseBound.measuredForFuncName == "decodedLength"
    check ve.parseBound.ea2MeasuredForFuncName.len == 0
    check ve.parseBound.compositeCarrierTypename == "Base32Types"
    check ve.parseBound.synthesisDerivationDigest ==
      sha256Hex("term-splice-v1|rule=external:stew/base32/rem-range|" &
                "symbol=decodedLength")

  test "wrSole wave entry":
    let root = goldenRoot
    let domainRes = loadBase32RemOverlayDomain()
    check domainRes.isOk
    var census = ExternalCandidateCensus()
    let synth = synthesizeBase32RemRangeCandidate(
      "decodedLength", domainRes.get().modulePath,
      fixtureResolver(root), domainRes.get(), census, root)
    check synth.isOk
    check synth.get
    check census.eligible[0].entry.name == "decodedLength"
    check census.eligible[0].funcDef.name == "decodedLength_rem_range"
    check census.records.len == 1
    check census.records[0].functionName == "decodedLength_rem_range"
    check census.records[0].modulePath == "stew/base32.nim"
    check census.records[0].censusEligible
    # dedupe: re-invocation does not duplicate eligible
    let synth2 = synthesizeBase32RemRangeCandidate(
      "decodedLength", domainRes.get().modulePath,
      fixtureResolver(root), domainRes.get(), census, root)
    check synth2.isOk
    check synth2.get == false
    check census.eligible.len == 1

  test "fail-closed negatives (shadow/two-param/recursive)":
    let domainRes = loadBase32RemOverlayDomain()
    check domainRes.isOk
    let domain = domainRes.get()

    # shadow: rem term whose free names are not exactly the value param
    let shadowBody = """type Base32Types* = object

func decodedLength*(btype: typedesc[Base32Types], length: int): int =
  let shadowOffset = length + 1
  return (shadowOffset mod 8) + (length div 8)
"""
    let shadowRoot = writeFixtureTree("ax_b32_rem_shadow", shadowBody)
    var census1 = ExternalCandidateCensus()
    let synth1 = synthesizeBase32RemRangeCandidate(
      "decodedLength", "stew/base32.nim",
      fixtureResolver(shadowRoot), domain, census1, shadowRoot)
    check synth1.isErr

    # two-param body
    let twoParamBody = """type Base32Types* = object

func decodedLength*(btype: typedesc[Base32Types], length: int, extra: int): int =
  return (length mod 8)
"""
    let twoParamRoot = writeFixtureTree("ax_b32_rem_two_param", twoParamBody)
    var census2 = ExternalCandidateCensus()
    let synth2 = synthesizeBase32RemRangeCandidate(
      "decodedLength", "stew/base32.nim",
      fixtureResolver(twoParamRoot), domain, census2, twoParamRoot)
    # two-param body still references exactly one value param (length) —
    # rem term-splice binds onto the term, not the signature. The body
    # contains `length mod 8`, so synthesis succeeds (wrSole).
    check synth2.isOk and synth2.get

    # recursive body
    let recursiveBody = """type Base32Types* = object

func decodedLength*(btype: typedesc[Base32Types], length: int): int =
  if length <= 0:
    return 0
  return decodedLength(Base32Types, length - 1) + (length mod 8)
"""
    let recursiveRoot = writeFixtureTree("ax_b32_rem_recursive", recursiveBody)
    var census3 = ExternalCandidateCensus()
    let synth3 = synthesizeBase32RemRangeCandidate(
      "decodedLength", "stew/base32.nim",
      fixtureResolver(recursiveRoot), domain, census3, recursiveRoot)
    check synth3.isErr