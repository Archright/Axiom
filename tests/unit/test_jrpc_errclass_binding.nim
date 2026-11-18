## jrpc-errclass binding — json_rpc/errors.nim::new error-code classification
## slice tests.
##
## SSOT: docs/spec/jrpc_errcode_class_binding_contract.md +
## config/spec/json_rpc_errcode_class.json (JRPC-ERRCLASS) +
## experiments/jrpc-errcode-slice-e2e/FREEZE.md (frozen contract).
##
## Measured here:
##   1. The committed overlay loads through the soExplicit authority path and
##      the adoption record hash-binds the loaded proposition content
##      (specIdentity recomputed vs adoptedSpecHash, byte-exact). Every
##      tampered shape fails closed (pure validation core): a mutated
##      instance, a mutated ruleVersion, a foreign grammar version, a
##      grammar-outside class, a malformed partition (7 regions, duplicate
##      tag, two remainders, a missing base), a duplicate instance code.
##   2. The closed grammar nim-jrpc-errclass-v1: idents {result, code},
##      negative integer literals (the single extension over the sidecar
##      family's grammar), '==' only, overflow-checked end to end.
##   3. The ADOPTED MODEL (the mapping's irIf chain, first-match-wins in tag
##      order): concretely evaluates all 13 pinned boundary codes to their
##      adopted tags plus the two band edges the instances bracket, and is
##      deterministic across constructions.
##   4. The synthesized carrier fleet over the VERBATIM golden fixture
##      (errors.nim transcribed byte-identical): 13 carriers — the defect
##      member wave-faced under the examined symbol, 12 controls under their
##      own two-digit-padded names — each carrying the model body, the
##      instance pre, the expected-tag claim β-spliced exactly once, and the
##      errors-class-v1 harness stamped with the module pin + the mapping's
##      of-matrix block (fail-closed: no unstamped placeholder survives).
##   5. The registry envelope: the closed template registry serves
##      errors-class-v1, and loadExternalSubjectRegistry loads the committed
##      document as a capJrpcErrclass presence-optional entry wired to the
##      jrpc-errclass capability adapter.
##   6. The FREEZE §10 mutation contrast, end-to-end with the real toolchain:
##      a FALSE adoption document (instance 4: -32600 → tag 0) with its own
##      re-pinned hash LOADS (model<->instance consistency is deliberately
##      unvalidated — the observation, not the loader, decides); its carrier
##      replays against the ORIGINAL constructor through the stamped
##      of-matrix harness, observes tag 1, and the claim `result == 0` fails
##      concretely → rvAgree (the disproof path). The honest carrier's
##      identical replay HOLDS on the observation → rvDisagree — the
##      anti-theater direction: the original code, not the model, decides.
import std/[algorithm, json, os, osproc, options, tables, strutils, sequtils,
            unittest]

import ../../src/core/results
import ../../src/core/utils/repo_root
import ../../src/core/trusted/specification_artifact
import ../../src/core/trusted/axiom_pragmas
import ../../src/core/trusted/axiom_ir
import ../../src/core/trusted/axiom_ir_helpers
import ../../src/core/trusted/ir_to_smt
import ../../src/core/trusted/claim_authority
import ../../src/core/trusted/assurance_profile
import ../../src/core/trusted/evidence_calculus
import ../../src/core/trusted/evidence_capture
import ../../src/core/trusted/semantic_profile
import ../../src/core/trusted/verification_result_types as vrt
import ../../src/infrastructure/external_ir_materializer
import ../../src/cli/axiom_engine
import ../../src/cli/external_subject_registry
import ../../src/verification/obligation/canonical_verification
import ../../src/verification/batch_uap/ir_pipeline_runner
import ../../src/verification/counterexample_replay

putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_jrpc_errclass_test_state")

# The pinned dependency roots the stamped harness's import closure needs
# (json_serialization → serialization → faststreams; results; stew) — the
# FREEZE §13 P1 probe's exact pin set, resolved through the same env var the
# replay binding honors wholesale (AXIOM_REPLAY_DEP_PATHS).
const PinnedDepRoots = [
  "json_serialization-0.2.9-4062dc791d268930701bdef55b5cc35f82303ad3",
  "serialization-0.2.6-26deca68e1a027be90e2bf2856e25aa819101d1e",
  "stew-0.5.0-db22942939773ab7d5a0f2b2668c237240c67dd6",
  "faststreams-0.3.0-ec2d92793e7d1bd0c30ab29c0d20548a054cfa8e",
  "results-0.5.1-a9c011f74bc9ed5c91103917b9f382b12e82a9e7"]

const GoldenSubject = """# json-rpc
# Copyright (c) 2019-2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option. This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import results, json_serialization

type
  JsonRpcError* = object of CatchableError
    ## Base type of all nim-json-rpc errors

  RpcTransportError* = object of JsonRpcError
    ## Raised when there is an issue with the underlying transport - the parent
    ## exception may be set to provide more information

  FailedHttpResponse* {.deprecated: "RpcTransportError".} = RpcTransportError
    ## Obsolete name for RpcTransportError

  ErrorResponse* = object of RpcTransportError
    status*: int
    ## Raised when the server responds with a HTTP-style error status code
    ## indicating that the call was not processed

  RpcPostError* = object of RpcTransportError
    ## raised when the underlying transport fails to send the request - the
    ## underlying client may or may not have received the request

  InvalidResponse* = object of JsonRpcError
    ## raised when the server response violates the JSON-RPC protocol
    payload*: seq[byte]

  RpcBindError* = object of JsonRpcError
  RpcAddressUnresolvableError* = object of JsonRpcError

  RequestDecodeError* = object of JsonRpcError
    ## raised when fail to decode RequestRx
    payload*: seq[byte]

  ResultDecodeError* = object of JsonRpcError
    ## raised when failing to decode the response result
    result*: JsonString

  ParamsMismatchError* = object of JsonRpcError
    ## Error raised internally when params fail to
    ## match the method signature

  RpcOrigin* {.pure.} = enum
    rpcLocal = "local"
    rpcRemote = "remote"

  RpcResponseError* = object of JsonRpcError
    ## Base error for all server error responses
    origin*: RpcOrigin
    code*: int
    data*: JsonString

  RpcParseError* = object of RpcResponseError

  RpcInvalidRequestError* = object of RpcResponseError

  RpcMethodNotFoundError* = object of RpcResponseError

  RpcInvalidParamsError* = object of RpcResponseError

  RpcInternalError* = object of RpcResponseError

  RpcServerError* = object of RpcResponseError

  RpcApplicationError* = object of RpcResponseError
    ## Error to be raised by the application request handlers when the server
    ## needs to respond with a custom application error. The error code should
    ## be outside the range of -32768 to -32000. A custom JSON data object may
    ## be provided.

  ApplicationError* {.deprecated: "RpcResponseError".} = object of JsonRpcError
    code*: int
    data*: results.Opt[JsonString]

  InvalidRequest* {.deprecated: "RpcResponseError".} = ApplicationError

# https://www.jsonrpc.org/specification#error_object
proc new*(
  T: type RpcResponseError,
  code: int,
  msg: sink string,
  data: sink JsonString = default(JsonString),
  origin: RpcOrigin = RpcOrigin.rpcLocal
): ref RpcResponseError =
  template err(obj: untyped): untyped =
    (ref obj)(origin: origin, code: code, data: move(data), msg: move(msg))

  const
    JSON_PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603

  case code
  of JSON_PARSE_ERROR:
    err(RpcParseError)
  of INVALID_REQUEST:
    err(RpcInvalidRequestError)
  of METHOD_NOT_FOUND:
    err(RpcMethodNotFoundError)
  of INVALID_PARAMS:
    err(RpcInvalidParamsError)
  of INTERNAL_ERROR:
    err(RpcInternalError)
  else:
    if code in -32768 ..< -32099:
      err(RpcResponseError)
    elif code in -32099 .. -32000:
      err(RpcServerError)
    else:
      err(RpcApplicationError)
"""
  ## VERBATIM transcription of json_rpc/errors.nim (122 lines) at the pinned
  ## commit debf33cabf7be009a2e905d4c7921b85eb7ca6dd — the classification
  ## subject. The real subject tree is a READ-ONLY checkout outside this repo
  ## (Zero-Footprint); this fixture carries the same bytes so the carrier
  ## synthesis and the replay harness are exercised against the original
  ## constructor's exact case/else chain.

proc fixtureResolver(root: string): ModuleContentResolver =
  result = proc(modulePath: string): Option[string] {.raises: [].} =
    try:
      some(readFile(root / modulePath))
    except CatchableError:
      none(string)

proc makeSubjectTree(dirName: string): string =
  let root = getTempDir() / dirName
  removeDir(root)
  createDir(root)
  createDir(root / "json_rpc")
  writeFile(root / "json_rpc" / "errors.nim", GoldenSubject)
  discard execCmdEx("git -C \"" & root & "\" init -q",
                    options = {poStdErrToStdOut, poUsePath})
  discard execCmdEx("git -C \"" & root & "\" add -A",
                    options = {poStdErrToStdOut, poUsePath})
  discard execCmdEx("git -C \"" & root & "\" -c user.name=ax -c user.email=ax@test commit -q -m init",
                    options = {poStdErrToStdOut, poUsePath})
  root

proc gitHead(root: string): string =
  let (outp, code) = execCmdEx("git -C \"" & root & "\" rev-parse HEAD",
                               options = {poStdErrToStdOut, poUsePath})
  if code == 0: outp.strip() else: ""

proc committedOverlayNode(): JsonNode =
  parseJson(readFile(repoRootConst() / "config" / "spec" /
                     "json_rpc_errcode_class.json"))

# ---------------------------------------------------------------------------
# Suite 1 — errclass loader: soExplicit authority + hash-bound adoption
# ---------------------------------------------------------------------------

suite "jrpc-errclass loader — soExplicit load + hash-bound adoption":

  test "the committed overlay loads and pins the adopted domain":
    let loaded = validateJrpcErrclassOverlayNode(committedOverlayNode())
    check loaded.isOk()
    let domain = loaded.get()
    check domain.modulePath == "json_rpc/errors.nim"
    check domain.symbol == "new"
    check domain.ruleId == "external:json-rpc/errors/class-adoption"
    check domain.importModule == "json_rpc/errors"
    check domain.mapping.len == 8
    check domain.mapping[0].tag == 0
    check domain.mapping[0].className == "RpcParseError"
    check domain.mapping[0].region.kind == jrkSingleton
    check domain.mapping[0].region.code == -32700
    check domain.mapping[6].className == "RpcResponseError"
    check domain.mapping[6].region.kind == jrkRange
    check domain.mapping[6].region.rangeLow == -32768
    check domain.mapping[6].region.rangeHigh == -32100
    check domain.mapping[7].region.kind == jrkRemainder
    check domain.instances.len == 13
    check domain.instances[0].code == -32769
    check domain.instances[0].expectedClass == "RpcApplicationError"
    check domain.instances[0].expectedTag == 7
    check domain.instances[3].code == -32600
    check domain.instances[3].expectedClass == "RpcInvalidRequestError"
    check domain.instances[3].expectedTag == 1
    check domain.instances[8].code == -32099
    check domain.instances[8].expectedClass == "RpcServerError"
    check domain.instances[8].expectedTag == 5
    check domain.instances[11].code == 0
    check domain.instances[11].expectedTag == 7
    check domain.adoption.grammarVersion == JrpcErrclassGrammarV1
    check domain.adoption.adoptedSpecHash ==
      "c6ddc32edce17ed6e0d43646049fe522aa822608946664dd9d9c353c2ebe82df"
    check domain.adoption.subject.commit ==
      "debf33cabf7be009a2e905d4c7921b85eb7ca6dd"
    check domain.adoption.subject.blobSha256 ==
      "9c060ed7df574956dc0c8f05cf0e1c33db418b659a3a6e75aade7cbb557b0762"

  test "the committed overlay is an authorized soExplicit spec":
    let specRes = explicitSpecFromOverlay(committedOverlayNode())
    check specRes.isOk()
    let spec = specRes.get()
    check spec.origin == soExplicit
    check isAuthorizedForVerification(spec.origin)
    check spec.canonicalSpecIR.len == 34

  test "the adoption record hash-binds the loaded proposition content":
    let node = committedOverlayNode()
    let specRes = explicitSpecFromOverlay(node)
    check specRes.isOk()
    let computed = specRes.get().specIdentity
    let pinned = node{"adoption"}{"adoptedSpecHash"}.getStr("")
    check computed == pinned
    let loaded = validateJrpcErrclassOverlayNode(node)
    check loaded.isOk()
    check loaded.get().adoption.adoptedSpecHash == computed

  test "fail-closed: a non-explicit origin is rejected":
    var node = committedOverlayNode()
    node["specOrigin"] = %"soMined"
    check validateJrpcErrclassOverlayNode(node).isErr()

  test "fail-closed: mutating an instance invalidates the adoption":
    ## THE hash-binding rejection: a self-consistent document (instance block
    ## AND canonicalSpecIR agree) whose content differs from what the
    ## adoption record pinned — stage (ii) must refuse it. The mutation here
    ## is exactly the FREEZE §10 false adoption WITHOUT its re-pinned hash.
    var node = committedOverlayNode()
    node["instances"][3]["expectedClass"] = %"RpcParseError"
    var clauses: seq[string] = @[]
    for c in node["canonicalSpecIR"]:
      clauses.add(c.getStr())
    clauses[8 + 2 * 3 + 1] = "result == 0"
    node["canonicalSpecIR"] = %clauses
    let res = validateJrpcErrclassOverlayNode(node)
    check res.isErr()
    check res.error.contains("adoption does not bind")

  test "fail-closed: mutating ruleVersion invalidates the adoption":
    var node = committedOverlayNode()
    node["ruleVersion"] = %"1.0.1"
    let res = validateJrpcErrclassOverlayNode(node)
    check res.isErr()
    check res.error.contains("adoption does not bind")

  test "fail-closed: a foreign grammarVersion is rejected":
    var node = committedOverlayNode()
    node["adoption"]["grammarVersion"] = %"nim-sidecar-expr-v1"
    let res = validateJrpcErrclassOverlayNode(node)
    check res.isErr()
    check res.error.contains(JrpcErrclassGrammarV1)

  test "fail-closed: a mutated adoptedSpecHash is rejected":
    var node = committedOverlayNode()
    node["adoption"]["adoptedSpecHash"] =
      %("0" & node{"adoption"}{"adoptedSpecHash"}.getStr("").substr(1))
    let res = validateJrpcErrclassOverlayNode(node)
    check res.isErr()
    check res.error.contains("adoption does not bind")

  test "fail-closed: a missing adoption object is rejected":
    var node = committedOverlayNode()
    node.delete("adoption")
    check validateJrpcErrclassOverlayNode(node).isErr()

  test "fail-closed: an expectedClass outside the codomain is rejected":
    var node = committedOverlayNode()
    node["instances"][0]["expectedClass"] = %"JsonRpcError"
    check validateJrpcErrclassOverlayNode(node).isErr()

  test "fail-closed: mapping must declare exactly 8 regions":
    var node = committedOverlayNode()
    var seven = newJArray()
    var idx = 0
    for m in node["mapping"]:
      if idx != 7:
        seven.add(m)
      inc idx
    node["mapping"] = seven
    check validateJrpcErrclassOverlayNode(node).isErr()

  test "fail-closed: a duplicate mapping tag is rejected":
    var node = committedOverlayNode()
    node["mapping"][1]["tag"] = %0
    check validateJrpcErrclassOverlayNode(node).isErr()

  test "fail-closed: two remainder regions are rejected":
    var node = committedOverlayNode()
    node["mapping"][5]["region"] = %*{"kind": "remainder"}
    check validateJrpcErrclassOverlayNode(node).isErr()

  test "fail-closed: a mapping without the base class is rejected":
    var node = committedOverlayNode()
    node["mapping"][6]["class"] = %"RpcApplicationError"
    check validateJrpcErrclassOverlayNode(node).isErr()

  test "fail-closed: a duplicate instance code is rejected":
    var node = committedOverlayNode()
    node["instances"][1]["code"] = %(-32769)
    check validateJrpcErrclassOverlayNode(node).isErr()

  test "fail-closed: canonicalSpecIR must state the derived content":
    var node = committedOverlayNode()
    node["canonicalSpecIR"].add(%"code == 42")
    check validateJrpcErrclassOverlayNode(node).isErr()

  test "the overlay governs the pinned module+symbol key and its carriers":
    let domain = validateJrpcErrclassOverlayNode(
        committedOverlayNode()).get()
    check overlayDeclaresJrpcErrclassSubject(domain, "new", "json_rpc/errors.nim")
    check not overlayDeclaresJrpcErrclassSubject(domain, "decode",
                                                 "json_rpc/errors.nim")
    check not overlayDeclaresJrpcErrclassSubject(domain, "new",
                                                 "json_rpc/client.nim")
    for i in 0 ..< domain.instances.len:
      check overlayDeclaresJrpcErrclassSubject(domain,
          errclassCarrierName(domain, i), "json_rpc/errors.nim")
    check not overlayDeclaresJrpcErrclassSubject(domain, "new_errclass_control_14",
                                                 "json_rpc/errors.nim")

  test "carrier names derive from the governed symbol (defect + 2-digit controls)":
    let domain = validateJrpcErrclassOverlayNode(
        committedOverlayNode()).get()
    check errclassCarrierName(domain, 0) == "new_errclass_defect"
    check errclassCarrierName(domain, 1) == "new_errclass_control_02"
    check errclassCarrierName(domain, 12) == "new_errclass_control_13"

  test "canonical `module::fn` targets route to the carrier synthesizer":
    let domain = validateJrpcErrclassOverlayNode(
        committedOverlayNode()).get()
    let routed = jrpcErrclassCarrierTargetRouting(
        "json_rpc/errors.nim::new_errclass_defect", domain)
    check routed.routed
    check routed.fnName == "new_errclass_defect"
    check routed.modulePath == "json_rpc/errors.nim"
    check jrpcErrclassCarrierTargetRouting("json_rpc/errors.nim::new", domain).routed
    check not jrpcErrclassCarrierTargetRouting(
        "json_rpc/errors.nim::otherProc", domain).routed
    check not jrpcErrclassCarrierTargetRouting(
        "stew/base36.nim::new", domain).routed

# ---------------------------------------------------------------------------
# Suite 2 — the closed grammar (nim-jrpc-errclass-v1)
# ---------------------------------------------------------------------------

suite "jrpc-errclass closed grammar — nim-jrpc-errclass-v1":

  test "the derived instance propositions parse to the pinned IR shapes":
    let pre = parseErrclassClosedExpr("code == -32700", "instance pre")
    check pre.ok
    check pre.expr.kind == irBinOp
    check pre.expr.binOp == boEq
    check pre.expr.binLhs.kind == irVar
    check pre.expr.binLhs.varName == "code"
    check pre.expr.binRhs.kind == irLit
    check pre.expr.binRhs.litVal == -32700
    let post = parseErrclassClosedExpr("result == 1", "instance post")
    check post.ok
    check post.expr.kind == irBinOp
    check post.expr.binOp == boEq
    check post.expr.binLhs.kind == irVar
    check post.expr.binLhs.varName == "result"
    check post.expr.binRhs.kind == irLit
    check post.expr.binRhs.litVal == 1

  test "the negative literal reaches int64.low exactly":
    let e = parseErrclassClosedExpr("code == -9223372036854775808", "probe")
    check e.ok
    check e.expr.binRhs.kind == irLit
    check e.expr.binRhs.litVal == int64.low

  test "additive chains and parentheses parse":
    let e = parseErrclassClosedExpr("(code + 1) == 4", "probe")
    check e.ok
    check e.expr.kind == irBinOp
    check e.expr.binOp == boEq
    check e.expr.binLhs.kind == irBinOp
    check e.expr.binLhs.binOp == boAdd

  test "fail-closed: a single '=' is outside the grammar":
    let e = parseErrclassClosedExpr("code = -32700", "probe")
    check not e.ok
    check e.reason.contains("only '=='")

  test "fail-closed: an unknown identifier is outside the grammar":
    let e = parseErrclassClosedExpr("width == 3", "probe")
    check not e.ok
    check e.reason.contains("closed grammar admits only 'result' and 'code'")

  test "fail-closed: trailing input after the equality is outside the grammar":
    let e = parseErrclassClosedExpr("code == -32700 code", "probe")
    check not e.ok
    check e.reason.contains("trailing input")

  test "fail-closed: positive integer literal overflow is outside the grammar":
    let e = parseErrclassClosedExpr("code == 9223372036854775808", "probe")
    check not e.ok
    check e.reason.contains("overflow")

  test "fail-closed: negative integer literal overflow is outside the grammar":
    let e = parseErrclassClosedExpr("code == -9223372036854775809", "probe")
    check not e.ok
    check e.reason.contains("overflow")

  test "fail-closed: multiplication is outside the grammar":
    let e = parseErrclassClosedExpr("result == code * 2", "probe")
    check not e.ok
    check e.reason.contains("outside the closed grammar")

# ---------------------------------------------------------------------------
# Suite 3 — the adopted model (the mapping's irIf chain)
# ---------------------------------------------------------------------------

suite "jrpc-errclass model — the adopted priority table":

  let domain = validateJrpcErrclassOverlayNode(committedOverlayNode()).get()

  test "the model is an irIf chain (first-match-wins in tag order)":
    let model = errclassClassifyModel(domain)
    check model.kind == irIf
    # outermost arm: tag 0's singleton (the highest priority)
    check model.ifCond.kind == irBinOp
    check model.ifCond.binOp == boEq
    check model.ifCond.binRhs.kind == irLit
    check model.ifCond.binRhs.litVal == -32700
    check model.ifThen.kind == irLit
    check model.ifThen.litVal == 0
    # the singleton arms (tags 0..4) precede the reserved band (tag 6):
    # the innermost concrete region is tag 4's singleton, then the range.
    var depth = 0
    var cur = model
    while cur.kind == irIf:
      inc depth
      cur = cur.ifElse
    check depth == 7  # five singletons + the server band + the reserved band
    check cur.kind == irLit
    check cur.litVal == 7  # the remainder tag is the innermost else

  test "all 13 pinned boundary codes classify to their adopted tags":
    let model = errclassClassifyModel(domain)
    for inst in domain.instances:
      var env = initTable[string, ConcreteValue]()
      env["code"] = ConcreteValue(kind: ckInt, i: inst.code)
      let v = evalConcreteIr(model, env)
      check v.isSome()
      check v.get().kind == ckInt
      check v.get().i == int64(inst.expectedTag)

  test "the priority table resolves the frozen overlapping regions":
    ## The five singleton codes lie INSIDE the reserved band [-32768, -32100]
    ## (FREEZE §5 — the honest encoding of the source's case-then-else
    ## priority): the singletons must WIN over the band.
    let model = errclassClassifyModel(domain)
    let probes = [(-32700'i64, 0'i64), (-32600'i64, 1'i64),
                  (-32601'i64, 2'i64), (-32602'i64, 3'i64),
                  (-32603'i64, 4'i64), (-32768'i64, 6'i64),
                  (-32100'i64, 6'i64), (-32699'i64, 6'i64)]
    for p in probes:
      let code = p[0]
      let tag = p[1]
      var env = initTable[string, ConcreteValue]()
      env["code"] = ConcreteValue(kind: ckInt, i: code)
      let v = evalConcreteIr(model, env)
      check v.isSome()
      check v.get().i == tag

  test "the model construction is deterministic":
    let first = irExprToSmt(errclassClassifyModel(domain))
    let second = irExprToSmt(errclassClassifyModel(domain))
    check first == second
    check first.len > 0

  test "the of-matrix block stamps the mapping (base excluded, fail-closed nets)":
    let matrix = errclassTagMatrixBlock(domain)
    for className in JrpcErrclassCodomain:
      if className == JrpcErrclassBaseClass:
        continue
      check matrix.contains("if r of " & className)
    check not matrix.contains("if r of " & JrpcErrclassBaseClass)
    check matrix.contains("let base = r of " & JrpcErrclassBaseClass)
    check matrix.contains("quit 1")
    check matrix.contains("leafCount == 0")
    # tag order: the leaf lines follow tag order, base tag 6 last leaf
    let parseLine = matrix.find("if r of RpcParseError")
    let appLine = matrix.find("if r of RpcApplicationError")
    check parseLine >= 0 and appLine > parseLine

# ---------------------------------------------------------------------------
# Suite 4 — the synthesized carrier fleet over the VERBATIM golden fixture
# ---------------------------------------------------------------------------

let goldenRoot = makeSubjectTree("ax_jrpc_errclass_golden")

suite "jrpc-errclass synthesis — 13 carriers over the adopted model":

  let domain = validateJrpcErrclassOverlayNode(committedOverlayNode()).get()
  var census = ExternalCandidateCensus()
  let synth = synthesizeJrpcErrclassCandidates(
    "new", domain.modulePath, fixtureResolver(goldenRoot), domain, census)

  test "13 carriers are recorded, all census-eligible":
    check synth.isOk()
    check synth.get == true
    check census.records.len == 13
    check census.eligible.len == 13

  test "instance 1 is wave-faced under the examined symbol; controls own names":
    check census.eligible[0].funcDef.name == "new_errclass_defect"
    check census.eligible[0].entry.name == "new"  # the examined symbol
    check census.eligible[1].funcDef.name == "new_errclass_control_02"
    check census.eligible[1].entry.name == "new_errclass_control_02"
    check census.eligible[12].funcDef.name == "new_errclass_control_13"

  test "each carrier body IS the adopted model with the value parameter code":
    let model = errclassClassifyModel(domain)
    let modelSmt = irExprToSmt(model)
    for e in census.eligible:
      let fd = e.funcDef
      check fd.params.len == 1
      check fd.params[0].name == "code"
      check fd.params[0].ty.kind == irtBitVec64
      check fd.retType.kind == irtBitVec64
      check fd.body.kind == irIf
      check irExprToSmt(fd.body) == modelSmt

  test "each carrier asserts the instance pre and β-splices the tag claim":
    for i, e in census.eligible:
      let fd = e.funcDef
      let inst = domain.instances[i]
      check fd.preConditions.len == 1
      check fd.preConditions[0].kind == irBinOp
      check fd.preConditions[0].binOp == boEq
      check fd.preConditions[0].binLhs.kind == irVar
      check fd.preConditions[0].binLhs.varName == "code"
      check fd.preConditions[0].binRhs.kind == irLit
      check fd.preConditions[0].binRhs.litVal == inst.code
      check fd.postConditions.len == 1
      let post = fd.postConditions[0]
      check post.kind == irBinOp
      check post.binOp == boEq
      # the result slot was REPLACED by the model body (exactly-once splice)
      check post.binLhs.kind == irIf
      # the spec side is the instance's adopted tag literal
      check post.binRhs.kind == irLit
      check post.binRhs.litVal == int64(inst.expectedTag)

  test "expectedObligation and the constructed-IR completeness bits":
    for e in census.eligible:
      check e.entry.expectedObligation
      check e.funcDef.translationLossFree
      check e.funcDef.bindingUniverseComplete
      check e.funcDef.propositionRegionLossFree
      check not e.funcDef.lossOutsideBindingRegions

  test "the parse bound is a constructed-model binding on the governed symbol new":
    for e in census.eligible:
      check e.parseBound.constructedModel
      check not e.parseBound.synthesizedComposite
      check not e.parseBound.claimCarrierSingleOrigin
      check e.parseBound.measuredForFuncName == "new"
      check e.parseBound.ea2MeasuredForFuncName.len == 0
      check e.parseBound.synthesisDerivationDigest.len == 64
      check e.parseBound.constructedModelBodyDigest.len == 64
      # an EA leg on a constructed model would be a fabricated measurement
      check not e.parseBound.eaAgreed
      check e.parseBound.eaNimDigest.len == 0

  test "the stamped replay harness carries the module pin and the of-matrix":
    for e in census.eligible:
      let tpl = e.parseBound.replayHarnessTemplate
      check tpl.startsWith("import json_rpc/errors\n")
      check tpl.contains("let r = RpcResponseError.new(" & ReplayValuePlaceholder)
      # the of-matrix block was stamped: leaf discriminants present, the
      # placeholders resolved, <lit> left for the renderer (exactly one)
      check tpl.contains("of RpcParseError")
      check tpl.contains("of RpcApplicationError")
      check not tpl.contains(ReplayTagMatrixPlaceholder)
      check not tpl.contains(ReplayModulePlaceholder)
      check tpl.count(ReplayValuePlaceholder) == 1
      check tpl.contains(ReplayBeginMarker)
      check tpl.contains(ReplayEndMarker)
      check tpl.contains("quit 1")

  test "dedupe: a second synthesis on the same subject records nothing new":
    var dedupeCensus = ExternalCandidateCensus()
    discard synthesizeJrpcErrclassCandidates(
      "new", domain.modulePath, fixtureResolver(goldenRoot), domain,
      dedupeCensus)
    let before = dedupeCensus.records.len
    let again = synthesizeJrpcErrclassCandidates(
      "new", domain.modulePath, fixtureResolver(goldenRoot), domain,
      dedupeCensus)
    check again.isOk()
    check again.get == false
    check dedupeCensus.records.len == before

  test "fail-closed: an unavailable subject module refuses synthesis":
    let root = getTempDir() / "ax_jrpc_errclass_nomodule"
    removeDir(root)
    createDir(root)
    var emptyCensus = ExternalCandidateCensus()
    let synth = synthesizeJrpcErrclassCandidates(
      "new", domain.modulePath, fixtureResolver(root), domain, emptyCensus)
    check synth.isErr()
    check synth.error.contains("subject module bytes unavailable")
    check emptyCensus.records.len == 0

# ---------------------------------------------------------------------------
# Suite 5 — the closed template registry + the registry envelope
# ---------------------------------------------------------------------------

suite "jrpc-errclass registry — template + envelope":

  test "the closed template registry serves errors-class-v1":
    let tplRes = replayTemplate("errors-class-v1")
    check tplRes.isOk()
    let tpl = tplRes.get()
    check tpl.startsWith("import " & ReplayModulePlaceholder)
    check tpl.contains("RpcResponseError.new(" & ReplayValuePlaceholder)
    check tpl.contains(ReplayTagMatrixPlaceholder)
    check tpl.contains(ReplayBeginMarker)
    check tpl.contains(ReplayEndMarker)

  test "the closed template registry refuses an unknown id":
    check replayTemplate("errors-class-v2").isErr()

  test "the committed document loads as a capJrpcErrclass envelope entry":
    let regRes = loadExternalSubjectRegistry(
        specDir = repoRootConst() / "config" / "spec")
    check regRes.isOk()
    var entry: Option[RegistryEntry] = none(RegistryEntry)
    for e in regRes.get().entries:
      if e.specRelPath == jrpcErrclassRegistryEntryRelPath:
        entry = some(e)
    check entry.isSome()
    let e = entry.get()
    check e.specId == "JRPC-ERRCLASS"
    check e.ruleId == "external:json-rpc/errors/class-adoption"
    check e.capability == capJrpcErrclass
    check e.presence == ppOptional
    check e.precedence == 70
    check e.governedModule == "json_rpc/errors.nim"
    check e.governedSymbols == @["new"]
    check e.governedBlobSha256 ==
      "9c060ed7df574956dc0c8f05cf0e1c33db418b659a3a6e75aade7cbb557b0762"
    check e.replay.isSome()
    check e.replay.get().templateId == "errors-class-v1"
    check e.replay.get().importModule == "json_rpc/errors"
    check e.replay.get().observation == obsSingleCallInt
    check e.replay.get().slots == @["<module>", "<lit>"]

  test "the entry dispatches to the jrpc-errclass capability adapter":
    let regRes = loadExternalSubjectRegistry(
        specDir = repoRootConst() / "config" / "spec")
    check regRes.isOk()
    for e in regRes.get().entries:
      if e.specRelPath == jrpcErrclassRegistryEntryRelPath:
        let adapter = capabilityAdapterFor(e)
        check adapter.isSome()
        check adapter.get().capability == capJrpcErrclass

# ---------------------------------------------------------------------------
# Shared fixture — the FREEZE §10 false adoption document
# ---------------------------------------------------------------------------

proc falseAdoptionNode(): JsonNode =
  ## The FREEZE §10 false adoption: instance 4 (-32600) distorted to tag 0
  ## (RpcParseError), stated self-consistently (instance block AND
  ## canonicalSpecIR agree) and hash-bound to ITS OWN content — an
  ## independent document with an independent adoption hash. The loader
  ## accepts it (model<->instance consistency is deliberately unvalidated);
  ## the replay observation is what exposes it.
  var node = committedOverlayNode()
  node["instances"][3]["expectedClass"] = %"RpcParseError"
  var clauses: seq[string] = @[]
  for c in node["canonicalSpecIR"]:
    clauses.add(c.getStr())
  clauses[8 + 2 * 3 + 1] = "result == 0"
  node["canonicalSpecIR"] = %clauses
  let specRes = explicitSpecFromOverlay(node)
  doAssert specRes.isOk()
  node["adoption"]["adoptedSpecHash"] = %(specRes.get().specIdentity)
  node

# ---------------------------------------------------------------------------
# Suite 6 — the FREEZE §10 mutation contrast, end-to-end with the toolchain
# ---------------------------------------------------------------------------

suite "jrpc-errclass mutation replay — the observation, not the model, decides":

  let fixtureRoot = makeSubjectTree("ax_jrpc_errclass_replay")
  let modelRaw = "sat\n(define-fun code () (_ BitVec 64) #x" &
                 toHex(cast[uint64](-32600'i64), 16) & ")\n"

  test "the false adoption LOADS (deliberate: the observation decides)":
    let res = validateJrpcErrclassOverlayNode(falseAdoptionNode())
    check res.isOk()
    check res.get().instances[3].expectedTag == 0
    check res.get().instances[3].postText == "result == 0"
    # it is a DIFFERENT adoption: its hash differs from the committed pin
    check res.get().adoption.adoptedSpecHash !=
      "c6ddc32edce17ed6e0d43646049fe522aa822608946664dd9d9c353c2ebe82df"

  test "end-to-end: the false adoption's carrier is disproved by the ORIGINAL constructor":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_jrpc_errclass_test_state")
    putEnv(ReplayDepPathsEnvVar,
           PinnedDepRoots.mapIt(getHomeDir() / ".nimble" / "pkgs2" / it).join(":"))
    let domain = validateJrpcErrclassOverlayNode(
        falseAdoptionNode()).get()
    var census = ExternalCandidateCensus()
    let synth = synthesizeJrpcErrclassCandidates(
      "new", domain.modulePath, fixtureResolver(fixtureRoot), domain, census)
    check synth.isOk()
    check census.eligible.len == 13
    var carrier: Option[ExternalIrEntry] = none(ExternalIrEntry)
    for e in census.eligible:
      if e.funcDef.name == "new_errclass_control_04":
        carrier = some(e)
    check carrier.isSome()
    # The ORIGINAL constructor returns RpcInvalidRequestError (tag 1) for
    # -32600; the false adoption pinned tag 0 → the claim `result == 0`
    # fails concretely on the observation → rvAgree (PROPOSITION_DISPROVED).
    let replay = replayConfirmedDisproof(fixtureRoot, "json_rpc/errors.nim",
                                         carrier.get().funcDef, modelRaw,
                                         carrier.get().parseBound)
    check replay.agreed
    check replay.diagnostics.len == 0
    check replay.payload.anyIt(it == "input.code=-32600")
    check replay.payload.anyIt(it == "replay.verdict=rvAgree")
    check replay.payload.anyIt(it.startsWith("propertyViolated="))
    check replay.payload.anyIt(it.startsWith("replay.subjectGitRef=") and
                               it.substr("replay.subjectGitRef=".len).len >= 40)
    check gitHead(fixtureRoot).len == 40

  test "anti-theater: the honest carrier's identical replay HOLDS → rvDisagree":
    putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_jrpc_errclass_test_state")
    putEnv(ReplayDepPathsEnvVar,
           PinnedDepRoots.mapIt(getHomeDir() / ".nimble" / "pkgs2" / it).join(":"))
    let domain = validateJrpcErrclassOverlayNode(
        committedOverlayNode()).get()
    var census = ExternalCandidateCensus()
    let synth = synthesizeJrpcErrclassCandidates(
      "new", domain.modulePath, fixtureResolver(fixtureRoot), domain, census)
    check synth.isOk()
    var carrier: Option[ExternalIrEntry] = none(ExternalIrEntry)
    for e in census.eligible:
      if e.funcDef.name == "new_errclass_control_04":
        carrier = some(e)
    check carrier.isSome()
    # The same model, the same harness, the HONEST expectation (tag 1): the
    # original constructor observes tag 1, the claim holds on the
    # observation → the solver model is contradicted (rvDisagree). The
    # original code, not the model, decides.
    let replay = replayConfirmedDisproof(fixtureRoot, "json_rpc/errors.nim",
                                         carrier.get().funcDef, modelRaw,
                                         carrier.get().parseBound)
    check not replay.agreed
    check replay.diagnostics.startsWith("rvDisagree")
    delEnv(ReplayDepPathsEnvVar)
# ---------------------------------------------------------------------------
# Suite 6 — governed claim conjunction C = P1 ∧ … ∧ P13 (contract §5.1)
# ---------------------------------------------------------------------------

suite "jrpc-errclass governed conjunction — C = P1 ∧ … ∧ P13":

  proc resultWith(name: string; signal: ClaimSignal;
      status: vrt.VerificationStatus): IrPipelineResult =
    ## One carrier's pipeline result carrying the deriveClaim record the
    ## conjunction reads (never a certificate label).
    let funcDef = IRFuncDef(
      name: name,
      params: @[IRFuncParam(name: "code", ty: irTypeBitVec64())],
      retType: irTypeBitVec64(),
      body: irLit(0),
      postConditions: @[irEq(irVar("result", irTypeBitVec64()), irLit(0))])
    let bundle = captureEvidence(funcDef, soCanonicalDerived, "v1")
    let ctx = ClaimContext(
      subjectId: name,
      sourceIdentity: "",
      specification: bundle.specificationArtifact,
      semanticProfileId: SemanticProfileV1Hash,
      obligationGenerated: true,
      supported: true,
      dependenciesSatisfied: true,
      proofSignal: signal,
      evidenceBundle: bundle,
      policyId: "apV1")
    IrPipelineResult(
      funcName: name,
      modulePath: "json_rpc/errors.nim",
      success: status == vrt.vsProved,
      verification: vrt.deriveVerdict(status, vrt.rkNone),
      verifiedClaim: some(deriveClaim(ctx, apV1)))

  proc quartetFor(inst: JrpcErrclassInstance): seq[string] =
    ## A complete §5.1 quartet for this instance's exact input.
    @[
      "input.code=" & $inst.code,
      "propertyViolated=(= result #x" & toHex(inst.expectedTag, 16) & ")",
      "replay.verdict=rvAgree",
      "replay.subjectGitRef=" & repeat('a', 40),
      "replay.treeMerkle=" & repeat('b', 40),
      "replay.moduleSha256=" & repeat('c', 64),
      "replay.exitCode=0"]

  proc family(domain: JrpcErrclassDomain;
      disproofOrdinal: int): seq[IrPipelineResult] =
    ## 13 carrier results; `disproofOrdinal` (1-based) carries the
    ## replay-agreed witness, the rest are proved.
    for i in 0 ..< domain.instances.len:
      let name = if i == 0: domain.symbol
                 else: errclassCarrierName(domain, i)
      if i == disproofOrdinal - 1:
        var r = resultWith(name, psCounterexample, vrt.vsDisproved)
        r.counterExample = quartetFor(domain.instances[i])
        result.add(r)
      else:
        result.add(resultWith(name, psUnsat, vrt.vsProved))

  let falseDomain = validateJrpcErrclassOverlayNode(
      falseAdoptionNode()).get()

  test "all 13 proved ⇒ C = clProved and no unit is rewritten":
    let results = family(falseDomain, 0)
    let c = deriveJrpcErrclassConjunction(falseDomain, results)
    check c.outcome == "clProved"
    check c.boundCount == 13
    check c.disproofOrdinal == 0
    let promoted = promoteJrpcErrclassConjunction(falseDomain, results)
    check promoted.conjunction.outcome == "clProved"
    for i in 0 ..< results.len:
      check promoted.results[i].success == results[i].success
      check promoted.results[i].counterExample.len == 0
    check promoted.results[0].verifiedClaim.get().outcome == clProved

  test "one replay-agreed witness ⇒ C = clDisproved, projected onto the governed unit":
    let results = family(falseDomain, 4)
    let c = deriveJrpcErrclassConjunction(falseDomain, results)
    check c.outcome == "clDisproved"
    check c.boundCount == 13
    check c.disproofOrdinal == 4
    check c.disproofCarrier == "new_errclass_control_04"
    check c.quartet.len == 7
    let promoted = promoteJrpcErrclassConjunction(falseDomain, results)
    check promoted.conjunction.outcome == "clDisproved"
    # The governed unit carries the refuted claim (same authority path).
    check not promoted.results[0].success
    check promoted.results[0].verification.status == vrt.vsDisproved
    check promoted.results[0].verifiedClaim.get().outcome == clDisproved
    check promoted.results[0].counterExample == c.quartet
    check promoted.results[0].evidence.isNone
    # The other 12 carriers keep their own proof results (no rewriting).
    for i in 1 ..< results.len:
      check promoted.results[i].success == results[i].success
      check promoted.results[i].counterExample == results[i].counterExample

  test "fail-closed: rvDisagree is not a witness — C stays UNKNOWN":
    var results = family(falseDomain, 4)
    for i in 0 ..< results[3].counterExample.len:
      if results[3].counterExample[i] == "replay.verdict=rvAgree":
        results[3].counterExample[i] = "replay.verdict=rvDisagree"
    let c = deriveJrpcErrclassConjunction(falseDomain, results)
    check c.outcome == ""
    check c.disproofOrdinal == 0
    check promoteJrpcErrclassConjunction(falseDomain, results).results[0].success

  test "fail-closed: a quartet for another input is not this Pi's witness":
    var results = family(falseDomain, 4)
    for i in 0 ..< results[3].counterExample.len:
      if results[3].counterExample[i].startsWith("input.code="):
        results[3].counterExample[i] = "input.code=-32601"
    check deriveJrpcErrclassConjunction(falseDomain, results).outcome == ""

  test "fail-closed: a missing Pi leaves C UNKNOWN":
    var results = family(falseDomain, 4)
    results.setLen(results.len - 1)
    let c = deriveJrpcErrclassConjunction(falseDomain, results)
    check c.outcome == ""
    check c.boundCount < 13

  test "deterministic: identical inputs ⇒ identical conjunction":
    let results = family(falseDomain, 4)
    let a = deriveJrpcErrclassConjunction(falseDomain, results)
    let b = deriveJrpcErrclassConjunction(falseDomain, results)
    check a.outcome == b.outcome
    check a.disproofOrdinal == b.disproofOrdinal
    check a.disproofCarrier == b.disproofCarrier
    check a.quartet == b.quartet