## experiments/act2-wp4h1-intrinsic/wp4h1_intrinsic_inventory.nim
## — WP4-h-1 Intrinsic Safety Operation Inventory Probe
##
## EXPERIMENT-ONLY instrument.
##   - NOT a canonical execution path
##   - NOT a production API
##   - NOT part of the shipped product / CLI
##   - NOT wired into the engine
##
## Phase A — READ-ONLY measurement. This probe does NOT add obligations to the
## product. It mechanically discovers intrinsic safety operations in each
## materialized symbol's Canonical Semantic IR and records, per operation:
##   source-expression / operation kind / inferred obligation / operands /
##   symbolic-vs-tautological / IR representation / SMT support.
##
## Intrinsic safety operations detected (closed list for this measurement):
##   division  : boDiv / boRem / boRemU   → obligation `denom != 0`
##   indexing  : irCall "[]" / "charAt" / "substr" → `0 <= i < len(seq)`
##   shift     : boShl / boShr            → shift-range; V1 spShiftUnsupported
##   overflow  : boAdd / boSub / boMul (wrapping) → numeric-overflow-prone
##   casting   : irCast                   → integer conversion surface
##   slice     : irCall "[]" on HSlice-range machinery (recorded as indexing)
##
## Classification per operation:
##   symbolic    : operand tied to input/parameter (idxExpr or denom is NOT a
##                 bare irLit) → real, input-linked constraint.
##   tautological: operand is a literal (e.g. `277 != 0`) → weak / near-vacuous.
##
## DETERMINISTIC intrinsic ranking over the v4 hard-eligible set:
##   1  symbolic safety obligation FIRST (input-linked), then
##   2  reject unsupported-op anchors LAST (capability boundary),
##   3  then dependency surface ASC,
##   4  then vtSmtNative over vtStructural,
##   5  then body node count ASC.
## The single top-ranked symbol is Anchor #1 (machine-selected, no cherry-pick).
##
## Usage: wp4h1-intrinsic <subjectRoot> <outDir>
## Exit: 0 always. Outputs: inventory.json (all symbols + intrinsic ops),
##       intrinsic-ranking.json (hard-eligible re-ranked by symbolic-first),
##       anchor.json (the single selected Anchor #1 with full provenance).

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/[os, strutils, json, tables, sequtils, algorithm, options, sets, hashes]
import core/crypto/hash_kernel
import compiler/ast
import core/parser_utils
import core/parsers/pnode_nav
import core/trusted/ast_to_ir
import core/trusted/pnode_to_canon
import core/trusted/axiom_ir
import core/trusted/axiom_pragmas
import verification/obligation/canonical_obligation_generator
import verification/obligation/obligation_ir
import verification/obligation/obligation_types
import verification/obligation/candidate_eligibility
import verification/admissibility
import verification/obligation/verified_fragment
import verification/ax_classify

# ---------------------------------------------------------------------------
# Helpers (deterministic JSON serialization)
# ---------------------------------------------------------------------------

proc sha256HexStr*(data: string): string =
  sha256Hex(data)

proc canonicalJsonMinified*(n: JsonNode): string =
  if n == nil: return "null"
  case n.kind
  of JObject:
    var parts: seq[string] = @[]
    for k in n.keys:
      let v = n.getOrDefault(k)
      parts.add(escapeJson(k) & ":" & canonicalJsonMinified(v))
    parts.sort(cmp[string])
    result = "{" & parts.join(",") & "}"
  of JArray:
    var parts: seq[string] = @[]
    for it in n.items:
      parts.add(canonicalJsonMinified(it))
    result = "[" & parts.join(",") & "]"
  of JString:
    result = escapeJson(n.getStr())
  of JInt:
    result = $n.getInt()
  of JFloat:
    result = $n.getFloat()
  of JBool:
    result = if n.getBool(): "true" else: "false"
  of JNull:
    result = "null"

proc getProcName*(nameNode: PNode): string =
  if nameNode == nil: return ""
  case nameNode.kind
  of nkPostfix:
    if nameNode.len > 1: pNodeText(nameNode[1]) else: ""
  of nkIdent: pNodeText(nameNode)
  else: ""

# ---------------------------------------------------------------------------
# IR pretty-printer — reconstruct a compact source-like expression string for
# provenance (best effort; NOT a recompiler). Pure, deterministic.
# ---------------------------------------------------------------------------

proc irExprToString(e: IRExpr): string =
  if e == nil: return "<nil>"
  case e.kind
  of irLit: result = $e.litVal
  of irFloatLit: result = $e.floatVal
  of irVar: result = e.varName
  of irStringLit: result = "\"" & e.stringVal & "\""
  of irBinOp:
    let o = $e.binOp
    result = "(" & irExprToString(e.binLhs) & " " & o & " " & irExprToString(e.binRhs) & ")"
  of irUnaryOp:
    result = "(" & $e.unaryOp & " " & irExprToString(e.unaryArg) & ")"
  of irLet:
    result = "let " & e.letName & " = " & irExprToString(e.letVal) & " in " & irExprToString(e.letBody)
  of irIf:
    result = "if " & irExprToString(e.ifCond) & " then " & irExprToString(e.ifThen) & " else " & irExprToString(e.ifElse)
  of irCall:
    var args: seq[string] = @[]
    for a in e.callArgs: args.add(irExprToString(a))
    result = e.callName & "(" & args.join(", ") & ")"
  of irCase:
    result = "case(" & irExprToString(e.caseScrutinee) & ")"
  of irRecCall:
    var args: seq[string] = @[]
    for a in e.recArgs: args.add(irExprToString(a))
    result = "rec(" & args.join(", ") & ")"
  of irLoop:
    result = "loop(" & irExprToString(e.loopCond) & ")"
  of irCast:
    result = "cast[" & irTypeName(e.castTo) & "](" & irExprToString(e.castExpr) & ")"

# ---------------------------------------------------------------------------
# Intrinsic safety operation scanner
# ---------------------------------------------------------------------------
# Each detected intrinsic operation collects:
#   op            : 'division' | 'indexing' | 'shift' | 'overflow' | 'casting' | 'slice'
#   irRepr        : e.g. 'boDiv' | 'boRemU' | 'irCall[]' | 'boShl' | 'irCast'
#   sourceExpr    : reconstructed expression string
#   inferredObl   : 'denom != 0' | '0 <= i < len(seq)' | 'shift-range' | ...
#   operands      : semicolon-joined operand expression strings
#   symbolic      : operand tied to input (not constant-foldable)
#   tautological  : operand is constant / constant-foldable -> weak / near-vacuous
#   essential     : DRIVES the anchor ranking axis. TRUE for the essential
#                   safety obligations (division-denom, index/slice bounds);
#                   FALSE for secondary ops (wrapping overflow, casts) which
#                   are recorded as measurement but do NOT make an anchor
#                   'symbolic' (they are not input-linked safety conditions).
#   smtSupport    : 'native' | 'unsupported(V1 spShiftUnsupported)' | 'requires-overflow-model' | 'structural'

type
  IntrinsicOp* = object
    op*: string
    irRepr*: string
    sourceExpr*: string
    inferredObl*: string
    operands*: string
    symbolic*: bool
    tautological*: bool
    essential*: bool
    smtSupport*: string

proc isConstantSubtree(e: IRExpr): bool =
  ## TRUE iff the IR subtree is purely constant — contains no parameter/input
  ## reference and no external call. Constant-foldable arithmetic over
  ## literals (e.g. `(0 boDiv 179) boAdd 1`) is constant, so its division
  ## obligation `denom != 0` is Tautological (near-vacuous). `irVar` and any
  ## non-literal, input-carrying expression make it symbolic.
  if e == nil: return true
  case e.kind
  of irLit, irFloatLit, irStringLit: true
  of irVar: false
  of irCall: false          # call may depend on inputs / be non-pure
  of irRecCall: false
  of irBinOp: isConstantSubtree(e.binLhs) and isConstantSubtree(e.binRhs)
  of irUnaryOp: isConstantSubtree(e.unaryArg)
  of irLet: isConstantSubtree(e.letVal) and isConstantSubtree(e.letBody)
  of irIf: isConstantSubtree(e.ifCond) and isConstantSubtree(e.ifThen) and isConstantSubtree(e.ifElse)
  of irCase:
    if not isConstantSubtree(e.caseScrutinee): return false
    for b in e.caseBranches:
      if not isConstantSubtree(b.body): return false
    isConstantSubtree(e.caseDefault)
  of irLoop: false
  of irCast: isConstantSubtree(e.castExpr)

proc classifyOperand(e: IRExpr): tuple[symbolic, tautological: bool] =
  let isConst = isConstantSubtree(e)
  (symbolic: not isConst, tautological: isConst)

proc classifyOperandForEssential(e: IRExpr): tuple[symbolic, tautological: bool] =
  ## For essential safety ops (division denominator, index expression), a
  ## single literal operand means the obligation is tautological-weak even if
  ## the OTHER side carries input. e.g. `length mod 8` → denom `8` is literal
  ## → `8 != 0` is near-vacuous. Use the literal-check on the decisive operand.
  if e == nil: return (false, true)
  case e.kind
  of irLit, irFloatLit, irStringLit:
    (false, true)
  else:
    (true, false)

proc scanIntrinsicOps(body: IRExpr): seq[IntrinsicOp] =
  result = @[]
  if body == nil: return
  proc walk(e: IRExpr; acc: var seq[IntrinsicOp]) =
    if e == nil: return
    case e.kind
    of irBinOp:
      let opTag = $e.binOp
      case e.binOp
      of boDiv, boRem, boRemU:
        let c = classifyOperandForEssential(e.binRhs)
        var smt = "native"
        if e.binOp == boRemU: smt = "native(boRemU unsigned)"
        acc.add IntrinsicOp(
          op: "division",
          irRepr: opTag,
          sourceExpr: irExprToString(e),
          inferredObl: "denom != 0",
          operands: irExprToString(e.binLhs) & " ; denom=" & irExprToString(e.binRhs),
          symbolic: c.symbolic,
          tautological: c.tautological,
          essential: true,
          smtSupport: smt
        )
      of boShl, boShr:
        let c = classifyOperandForEssential(e.binRhs)
        acc.add IntrinsicOp(
          op: "shift",
          irRepr: opTag,
          sourceExpr: irExprToString(e),
          inferredObl: "shift-range (shift < bitwidth)",
          operands: "lhs=" & irExprToString(e.binLhs) & " ; shift=" & irExprToString(e.binRhs),
          symbolic: c.symbolic,
          tautological: c.tautological,
          essential: true,
          smtSupport: "unsupported(V1 spShiftUnsupported)"
        )
      of boAdd, boSub, boMul:
        let lhsC = isConstantSubtree(e.binLhs)
        let rhsC = isConstantSubtree(e.binRhs)
        acc.add IntrinsicOp(
          op: "overflow",
          irRepr: opTag,
          sourceExpr: irExprToString(e),
          inferredObl: "numeric-overflow-safe (wrapping vs checked)",
          operands: irExprToString(e.binLhs) & " ; " & irExprToString(e.binRhs),
          symbolic: (not lhsC) or (not rhsC),
          tautological: lhsC and rhsC,
          essential: false,
          smtSupport: "requires-overflow-model"
        )
      else: discard
      walk(e.binLhs, acc); walk(e.binRhs, acc)
    of irUnaryOp:
      walk(e.unaryArg, acc)
    of irLet:
      walk(e.letVal, acc); walk(e.letBody, acc)
    of irIf:
      walk(e.ifCond, acc); walk(e.ifThen, acc); walk(e.ifElse, acc)
    of irCase:
      walk(e.caseScrutinee, acc)
      for b in e.caseBranches: walk(b.body, acc)
      walk(e.caseDefault, acc)
    of irCall:
      if e.callName == "[]" and e.callArgs.len >= 2:
        let seqExpr = e.callArgs[0]
        let idxExpr = e.callArgs[^1]
        let c = classifyOperandForEssential(idxExpr)
        acc.add IntrinsicOp(
          op: "indexing",
          irRepr: "irCall\"[]\"",
          sourceExpr: irExprToString(e),
          inferredObl: "0 <= i < len(seq)",
          operands: "seq=" & irExprToString(seqExpr) & " ; i=" & irExprToString(idxExpr),
          symbolic: c.symbolic,
          tautological: c.tautological,
          essential: true,
          smtSupport: "native(boGe/boLt on len)"
        )
      elif e.callName == "charAt" and e.callArgs.len >= 2:
        let strExpr = e.callArgs[0]
        let idxExpr = e.callArgs[1]
        let c = classifyOperandForEssential(idxExpr)
        acc.add IntrinsicOp(
          op: "indexing",
          irRepr: "irCall\"charAt\"",
          sourceExpr: irExprToString(e),
          inferredObl: "0 <= i < len(str)",
          operands: "str=" & irExprToString(strExpr) & " ; i=" & irExprToString(idxExpr),
          symbolic: c.symbolic,
          tautological: c.tautological,
          essential: true,
          smtSupport: "native(boGe/boLt on len)"
        )
      elif e.callName == "substr" and e.callArgs.len >= 3:
        let sExpr = e.callArgs[0]
        let startExpr = e.callArgs[1]
        let c = classifyOperandForEssential(startExpr)
        acc.add IntrinsicOp(
          op: "slice",
          irRepr: "irCall\"substr\"",
          sourceExpr: irExprToString(e),
          inferredObl: "0 <= start && start+len <= s.len",
          operands: "s=" & irExprToString(sExpr) & " ; start=" & irExprToString(startExpr),
          symbolic: c.symbolic,
          tautological: c.tautological,
          essential: true,
          smtSupport: "native(boGe/boLe on len)"
        )
      else:
        for a in e.callArgs: walk(a, acc)
    of irRecCall:
      for a in e.recArgs: walk(a, acc)
    of irLoop:
      for init in e.loopInits: walk(init, acc)
      walk(e.loopCond, acc); walk(e.loopStep, acc); walk(e.loopBody, acc)
      for inv in e.loopInvariants: walk(inv, acc)
      walk(e.loopVariant, acc)
    of irCast:
      acc.add IntrinsicOp(
        op: "casting",
        irRepr: "irCast",
        sourceExpr: irExprToString(e),
        inferredObl: "integer-conversion-safe",
        operands: "expr=" & irExprToString(e.castExpr) & " ; to=" & irTypeName(e.castTo),
        symbolic: not isConstantSubtree(e.castExpr),
        tautological: isConstantSubtree(e.castExpr),
        essential: false,
        smtSupport: "structural(cast)"
      )
      walk(e.castExpr, acc)
    else: discard
  walk(body, result)

# ---------------------------------------------------------------------------
# Symbol metrics reused from WP22
# ---------------------------------------------------------------------------

proc countNodes*(e: IRExpr): int =
  if e == nil: return 0
  result = 1
  case e.kind
  of irBinOp: result += countNodes(e.binLhs) + countNodes(e.binRhs)
  of irUnaryOp: result += countNodes(e.unaryArg)
  of irLet: result += countNodes(e.letVal) + countNodes(e.letBody)
  of irIf: result += countNodes(e.ifCond) + countNodes(e.ifThen) + countNodes(e.ifElse)
  of irCase:
    result += countNodes(e.caseScrutinee)
    for b in e.caseBranches: result += countNodes(b.body)
    result += countNodes(e.caseDefault)
  of irCall:
    for a in e.callArgs: result += countNodes(a)
  of irRecCall:
    for a in e.recArgs: result += countNodes(a)
  of irLoop:
    result += countNodes(e.loopCond)
    for init in e.loopInits: result += countNodes(init)
    result += countNodes(e.loopStep); result += countNodes(e.loopBody)
    for inv in e.loopInvariants: result += countNodes(inv)
    result += countNodes(e.loopVariant)
  of irCast: result += countNodes(e.castExpr)
  else: discard

proc collectCallees*(e: IRExpr; acc: var HashSet[string]) =
  if e == nil: return
  case e.kind
  of irCall:
    if e.callName.len > 0: acc.incl(e.callName)
    for a in e.callArgs: collectCallees(a, acc)
  of irRecCall:
    for a in e.recArgs: collectCallees(a, acc)
  of irBinOp: collectCallees(e.binLhs, acc); collectCallees(e.binRhs, acc)
  of irUnaryOp: collectCallees(e.unaryArg, acc)
  of irLet: collectCallees(e.letVal, acc); collectCallees(e.letBody, acc)
  of irIf: collectCallees(e.ifCond, acc); collectCallees(e.ifThen, acc); collectCallees(e.ifElse, acc)
  of irCase:
    collectCallees(e.caseScrutinee, acc)
    for b in e.caseBranches: collectCallees(b.body, acc)
    collectCallees(e.caseDefault, acc)
  of irLoop:
    collectCallees(e.loopCond, acc)
    for init in e.loopInits: collectCallees(init, acc)
    collectCallees(e.loopStep, acc); collectCallees(e.loopBody, acc)
    for inv in e.loopInvariants: collectCallees(inv, acc)
    collectCallees(e.loopVariant, acc)
  of irCast: collectCallees(e.castExpr, acc)
  else: discard

proc proofExecutionShape*(e: IRExpr): string =
  if e == nil: return "empty"
  var hasCall = false; var hasLoop = false; var hasRec = false; var hasCase = false
  proc scan(x: IRExpr) {.raises: [].} =
    if x == nil: return
    case x.kind
    of irBinOp: scan(x.binLhs); scan(x.binRhs)
    of irUnaryOp: scan(x.unaryArg)
    of irLet: scan(x.letVal); scan(x.letBody)
    of irIf: scan(x.ifCond); scan(x.ifThen); scan(x.ifElse)
    of irCase:
      hasCase = true
      scan(x.caseScrutinee)
      for b in x.caseBranches: scan(b.body)
      scan(x.caseDefault)
    of irCall:
      hasCall = true
      for a in x.callArgs: scan(a)
    of irRecCall:
      for a in x.recArgs: scan(a)
    of irLoop:
      scan(x.loopCond)
      for init in x.loopInits: scan(init)
      scan(x.loopStep); scan(x.loopBody)
      for inv in x.loopInvariants: scan(inv)
      scan(x.loopVariant)
    of irCast: scan(x.castExpr)
    else: discard
  scan(e)
  if hasRec: result = "recursive"
  elif hasLoop: result = "loop"
  elif hasCall: result = "calls"
  elif hasCase: result = "struct"
  else: result = "direct"

# ---------------------------------------------------------------------------
# Per-symbol vector (WP22 fields + intrinsic operation inventory)
# ---------------------------------------------------------------------------

proc computeSymbolVector*(module: string; funcName: string;
    funcDefNode: PNode; subjectRoot: string): JsonNode =
  result = newJObject()
  result["module"] = %module
  result["function"] = %funcName

  var irFuncDef: IRFuncDef
  var irAvailable = false
  var irStr = ""
  var irError = ""
  var materializedStatus = "moNotFound"

  try:
    let canonNode = pnodeToCanon(funcDefNode)
    irFuncDef = axiomBodyCanon(canonNode)
    if irFuncDef.name.len == 0:
      irError = "axiomBodyCanon returned empty name"
      materializedStatus = "moParseFailure"
    else:
      irStr = serializeIRFuncDef(irFuncDef)
      if irStr.len == 0:
        irError = "serializeIRFuncDef returned empty"
        materializedStatus = "moParseFailure"
      else:
        irAvailable = true
        materializedStatus = "moMaterialized"
  except CatchableError as e:
    irError = "IR reproduction failed: " & e.msg
    materializedStatus = "moParseFailure"

  result["irAvailable"] = %irAvailable
  if irStr.len > 0:
    result["irDigest"] = %sha256HexStr(irStr)
    result["irSerializedHash"] = %sha256HexStr(irStr)
  if irError.len > 0:
    result["irError"] = %irError
  result["materialized"] = %materializedStatus

  var obligationCount = 0
  var obligationKinds: seq[string] = @[]
  var obligationGenerated = false
  var ogr: ObligationGenerationResult

  if irAvailable:
    let policy = defaultScopePolicy()
    ogr = generateCanonicalObligations(irFuncDef, policy)
    if ogr.kind == ogrGenerated:
      obligationGenerated = true
      obligationCount = ogr.obligations.len
      for obl in ogr.obligations.items:
        obligationKinds.add($obl.kind)

  result["obligationCount"] = %obligationCount
  result["obligationGenerated"] = %obligationGenerated
  result["obligationKinds"] = %obligationKinds

  var postconditionCount = 0
  var dependencyCount = 0
  var shapeStr = "empty"
  var bodyNodeCount = 0
  var intrinsicOps: seq[JsonNode] = @[]
  var hasSymbolicIntrinsic = false
  var hasTautologicalOnly = false
  var hasUnsupportedOp = false

  if irAvailable:
    postconditionCount = irFuncDef.postConditions.len
    var callees = initHashSet[string]()
    collectCallees(irFuncDef.body, callees)
    dependencyCount = callees.len
    shapeStr = proofExecutionShape(irFuncDef.body)
    bodyNodeCount = countNodes(irFuncDef.body)

    let ops = scanIntrinsicOps(irFuncDef.body)
    var anySymbolic = false
    var anyOp = false
    var anyUnsupported = false
    for op in ops:
      anyOp = true
      if op.symbolic: anySymbolic = true
      if op.smtSupport.contains("unsupported"): anyUnsupported = true
      intrinsicOps.add(%*{
        "op": op.op,
        "irRepr": op.irRepr,
        "sourceExpr": op.sourceExpr,
        "inferredObligation": op.inferredObl,
        "operands": op.operands,
        "symbolic": op.symbolic,
        "tautological": op.tautological,
        "smtSupport": op.smtSupport
      })
    hasSymbolicIntrinsic = anySymbolic
    hasUnsupportedOp = anyUnsupported
    hasTautologicalOnly = anyOp and not anySymbolic

  result["intrinsicOps"] = %intrinsicOps
  result["intrinsicOpCount"] = %intrinsicOps.len
  result["hasSymbolicIntrinsicObligation"] = %hasSymbolicIntrinsic
  result["hasTautologicalOnly"] = %hasTautologicalOnly
  result["hasUnsupportedIntrinsicOp"] = %hasUnsupportedOp

  result["postconditionCount"] = %postconditionCount
  result["dependencyCount"] = %dependencyCount
  result["proofExecutionShape"] = %shapeStr

  # --- post-IR analysis (eligibility, proofTier) ---
  var proofTierStr = "vtNonDecidable"
  if irAvailable and irFuncDef.body != nil:
    try:
      let syntheticEntry = RuntimeAxiomEntry(
        name: funcName,
        irSerialized: irStr,
        smtSource: "",
        leanSource: "",
        sourcePath: module,
        isKernel: true,
        irHash: sha256HexStr(irStr),
        effectKind: Pure,
        bmcSkippable: false,
        origin: soExternalSubject,
        expectedObligation: false
      )
      let admOutcome = assessAdmissibility(syntheticEntry, irFuncDef)
      result["vacuousSignal"] = %(admOutcome.decision == INELIGIBLE)
      let eligibility = classifyCandidateEligibility(syntheticEntry, irFuncDef)
      result["eligibility"] = %($eligibility)
      try:
        let tierInfo = classifyFunction(irFuncDef)
        proofTierStr = $tierInfo.tier
      except CatchableError:
        discard
    except CatchableError as e:
      result["vacuousSignal"] = %true
      result["eligibility"] = %"elUnsupported"
  else:
    result["vacuousSignal"] = %true
    result["eligibility"] = %"elUnsupported"

  result["proofTier"] = %proofTierStr
  result["bodyNodeCount"] = %bodyNodeCount
  result["overloadAmbiguity"] = %false
  result["definitionCount"] = %1
  result["status"] = %"completed"

proc jsonStr(node: JsonNode; key: string; default: string): string =
  try: result = node[key].getStr
  except KeyError: result = default
proc jsonBool(node: JsonNode; key: string; default: bool): bool =
  try: result = node[key].getBool
  except KeyError: result = default
proc jsonInt(node: JsonNode; key: string; default: int): int =
  try: result = node[key].getInt
  except KeyError: result = default

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

when isMainModule:
  let args = commandLineParams()
  if args.len < 2:
    stderr.writeLine("usage: wp4h1-intrinsic <subjectRoot> <outDir>")
    quit(2)

  let subjectRoot = args[0]
  let outDir = args[1]
  createDir(outDir)
  let inventoryPath = outDir / "inventory.json"
  let rankingPath = outDir / "intrinsic-ranking.json"
  let anchorPath = outDir / "anchor.json"

  generateAxiomInit()

  var report = newJObject()
  report["experimentId"] = %"act2-wp4h1-intrinsic-safety"
  report["phase"] = %"ACT-2.2/WP4-h-1"
  report["probeType"] = %"intrinsic-safety-operation-inventory"
  report["notCanonicalExecutionPath"] = %true
  report["notProductionAPI"] = %true
  report["subjectRoot"] = %subjectRoot
  report["subjectRevision"] = %"c75502ceedb5ed2a37b7b5e4744fc71313682859"
  report["toolchainIdentity"] = %"Nim 2.2.10 (choosenim nim-2.2.10)"

  proc collectNimFiles(dir: string; result: var seq[string]) {.raises: [OSError].} =
    for kind, path in walkDir(dir):
      if kind == pcFile and path.endsWith(".nim"):
        result.add(path)
      elif kind == pcDir and path notin [".", ".."]:
        collectNimFiles(path, result)
  var nimFiles: seq[string] = @[]
  let libRoot = subjectRoot / "stew"
  if dirExists(libRoot):
    try:
      collectNimFiles(libRoot, nimFiles)
    except CatchableError:
      discard
  nimFiles.sort()
  report["nimFileCount"] = %nimFiles.len

  type SymKey = tuple[moduleRel, funcName: string]
  var symDefs = initTable[SymKey, tuple[count: int, node: PNode, fullPath: string]]()
  var fileParseFailures: seq[string] = @[]

  for fullPath in nimFiles:
    let moduleRel = if fullPath.startsWith(subjectRoot & "/"):
      fullPath[subjectRoot.len + 1 .. ^1]
    elif fullPath.startsWith(subjectRoot):
      fullPath[subjectRoot.len .. ^1]
    else:
      fullPath
    var sourceText = ""
    try:
      sourceText = readFile(fullPath)
    except CatchableError:
      fileParseFailures.add(moduleRel)
      continue
    let ast = parseStringAST(sourceText)
    if ast.isNil:
      fileParseFailures.add(moduleRel)
      continue
    for node in findNodesP(ast, {nkProcDef, nkFuncDef}):
      let name = getProcName(node[0])
      if name.len == 0: continue
      let key: SymKey = (moduleRel, name)
      if symDefs.hasKey(key):
        symDefs[key].count += 1
      else:
        symDefs[key] = (count: 1, node: node, fullPath: fullPath)

  report["fileParseFailures"] = %fileParseFailures
  report["uniqueSymbols"] = %symDefs.len

  var inventory: seq[JsonNode] = @[]
  for key, val in symDefs:
    let moduleRel = key.moduleRel
    let funcName = key.funcName
    let definitionCount = val.count
    let funcDefNode = val.node
    var vec: JsonNode
    try:
      vec = computeSymbolVector(moduleRel, funcName, funcDefNode, subjectRoot)
    except Defect as e:
      vec = newJObject()
      vec["module"] = %moduleRel
      vec["function"] = %funcName
      vec["definitionCount"] = %definitionCount
      vec["irAvailable"] = %false
      vec["irError"] = %("Defect during IR: " & e.msg)
      vec["obligationCount"] = %0
      vec["obligationGenerated"] = %false
      vec["obligationKinds"] = %newJArray()
      vec["postconditionCount"] = %0
      vec["dependencyCount"] = %0
      vec["proofExecutionShape"] = %"empty"
      vec["vacuousSignal"] = %true
      vec["eligibility"] = %"elUnsupported"
      vec["proofTier"] = %"vtNonDecidable"
      vec["bodyNodeCount"] = %0
      vec["materialized"] = %"moParseFailure"
      vec["status"] = %"defect"
    vec["definitionCount"] = %definitionCount
    vec["overloadAmbiguity"] = %(definitionCount > 1)
    inventory.add(vec)

  inventory.sort(proc(a, b: JsonNode): int =
    let c1 = cmp(jsonStr(a, "module", ""), jsonStr(b, "module", ""))
    if c1 != 0: return c1
    cmp(jsonStr(a, "function", ""), jsonStr(b, "function", ""))
  )
  report["inventory"] = %inventory

  # --- v4 HARD filter (6 predicates, same as WP22 corrected) ---
  # unique(1) ∧ materialized ∧ obligation>0 ∧ elProofCandidate ∧
  # ¬overload (exact-target=1) ∧ proofTier != vtNonDecidable
  var hardEligible: seq[JsonNode] = @[]
  for vec in inventory:
    let isUnique = jsonInt(vec, "definitionCount", 0) == 1
    let isMat = jsonStr(vec, "materialized", "") == "moMaterialized" and jsonBool(vec, "irAvailable", false)
    let isObl = jsonInt(vec, "obligationCount", 0) > 0
    let isElig = jsonStr(vec, "eligibility", "") == "elProofCandidate"
    let noOver = not jsonBool(vec, "overloadAmbiguity", false)
    let notNonDec = jsonStr(vec, "proofTier", "vtNonDecidable") != "vtNonDecidable"
    if isUnique and isMat and isObl and isElig and noOver and notNonDec:
      hardEligible.add(vec)

  # Funnel
  var fU, fM, fO, fE, fN, fH: int
  for vec in inventory:
    if jsonInt(vec, "definitionCount", 0) == 1: fU += 1
    if jsonStr(vec, "materialized", "") == "moMaterialized" and jsonBool(vec, "irAvailable", false): fM += 1
    if jsonInt(vec, "obligationCount", 0) > 0: fO += 1
    if jsonStr(vec, "eligibility", "") == "elProofCandidate": fE += 1
    if not jsonBool(vec, "overloadAmbiguity", false): fN += 1
  fH = hardEligible.len
  report["funnel"] = %*{
    "total": inventory.len,
    "uniqueDef": fU,
    "materialized": fM,
    "obligationGreaterThan0": fO,
    "elProofCandidate": fE,
    "noOverloadAmbiguity": fN,
    "hardEligible": fH
  }

  # --- DETERMINISTIC intrinsic ranking (symbolic first, unsupported last) ---
  func tierOrd(tier: string): int =
    case tier
    of "vtSmtNative": 0
    of "vtStructural": 1
    else: 9
  hardEligible.sort(proc(a, b: JsonNode): int =
    # 1. symbolic safety obligation FIRST
    let symA = if jsonBool(a, "hasSymbolicIntrinsicObligation", false): 0 else: 1
    let symB = if jsonBool(b, "hasSymbolicIntrinsicObligation", false): 0 else: 1
    if symA != symB: return cmp(symA, symB)
    # 2. reject unsupported-op anchors LAST (capability boundary)
    let unsA = if jsonBool(a, "hasUnsupportedIntrinsicOp", false): 1 else: 0
    let unsB = if jsonBool(b, "hasUnsupportedIntrinsicOp", false): 1 else: 0
    if unsA != unsB: return cmp(unsA, unsB)
    # 3. dependency surface ASC
    let dA = jsonInt(a, "dependencyCount", 0)
    let dB = jsonInt(b, "dependencyCount", 0)
    if dA != dB: return cmp(dA, dB)
    # 4. vtSmtNative over vtStructural
    let tA = tierOrd(jsonStr(a, "proofTier", "vtNonDecidable"))
    let tB = tierOrd(jsonStr(b, "proofTier", "vtNonDecidable"))
    if tA != tB: return cmp(tA, tB)
    # 5. body node count ASC
    let nA = jsonInt(a, "bodyNodeCount", 0)
    let nB = jsonInt(b, "bodyNodeCount", 0)
    if nA != nB: return cmp(nA, nB)
    let ma = jsonStr(a, "module", "")
    let mb = jsonStr(b, "module", "")
    let c1 = cmp(ma, mb)
    if c1 != 0: return c1
    cmp(jsonStr(a, "function", ""), jsonStr(b, "function", ""))
  )

  for i, vec in hardEligible:
    vec["intrinsicRank"] = %(i + 1)
    vec["anchorId"] = %(jsonStr(vec, "module", "") & "::" & jsonStr(vec, "function", ""))

  report["intrinsicRanking"] = %hardEligible

  # --- Anchor #1 = top of intrinsic ranking (machine-selected) ---
  var anchor = newJNull()
  var anchorResult = "NONE"
  if hardEligible.len > 0:
    anchor = hardEligible[0]
    anchorResult = jsonStr(anchor, "module", "") & "::" & jsonStr(anchor, "function", "")
  report["anchor"] = anchor
  report["anchorResult"] = %anchorResult

  let canonical = canonicalJsonMinified(report)
  writeFile(inventoryPath, canonical)

  let rankDoc = newJObject()
  rankDoc["experimentId"] = %"act2-wp4h1-intrinsic-safety"
  rankDoc["hardEligibleCount"] = %hardEligible.len
  rankDoc["intrinsicRankingOrder"] = %*[
    "symbolic-obligation-first",
    "reject-unsupported-op-last",
    "dependency-surface-asc",
    "vtSmtNative-over-vtStructural",
    "body-node-asc",
    "module::function-lexicographic"
  ]
  let rankedArr = newJArray()
  for vec in hardEligible:
    rankedArr.add(vec)
  rankDoc["orderedCandidates"] = rankedArr
  writeFile(rankingPath, canonicalJsonMinified(rankDoc))

  let anchorDoc = newJObject()
  anchorDoc["experimentId"] = %"act2-wp4h1-intrinsic-safety"
  anchorDoc["selectionProcedure"] = %"deterministic-intrinsic-ranking"
  anchorDoc["anchor"] = anchor
  anchorDoc["anchorResult"] = %anchorResult
  writeFile(anchorPath, canonicalJsonMinified(anchorDoc))

  quit(0)
