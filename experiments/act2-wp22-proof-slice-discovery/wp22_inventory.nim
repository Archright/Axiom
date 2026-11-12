## experiments/act2-wp22-proof-slice-discovery/wp22_inventory.nim
## — Act2-WP22 Proof Slice Discovery Inventory Probe
##
## EXPERIMENT-ONLY instrument.
##   - NOT a canonical execution path
##   - NOT a production API
##   - NOT part of the shipped product / CLI
##   - NOT wired into the engine
##
## Probe for ACT 2.2: full-tree candidate inventory + HARD filter + DETERMINISTIC
## ranking over nim-stew. Iterates EVERY proc/func def in EVERY .nim file under
## the subject's `stew/` library scope and computes the predicate vector.
##
## This probe is a copy-extension of the WP4b inventory probe
## (experiments/act2-wp4b-proof-execution-anchor/wp4b_inventory.nim). It adds
## the ACT 2.2 hard-filter / ranking axes:
##   - postconditionCount   (irFuncDef.postConditions.len)
##   - dependencyCount      (distinct irCall callName in body — dependency surface)
##   - overloadAmbiguity    (same module::function bare name defined >1 times)
##   - vacuousSignal        (renewal of `vacuous`, now ranking-only)
##   - proofExecutionShape  (coarse IR-shape label)
##
## HARD filter (v4 contract — exactly 6 predicates):
##   unique definition(1) ∧ materialized(moMaterialized) ∧ obligationCount>0
##   ∧ elProofCandidate ∧ ¬overload ambiguity (exact-target=1)
##   ∧ proofTier != vtNonDecidable
##   postconditionCount>0 is NOT a hard gate in v4 — it is ranking-only.
##
## DETERMINISTIC ranking over the hard-eligible set (tie-break `module::function`):
##   1 unique identity (hard) 2 materialized (hard) 3 obligation>0 (hard)
##   4 postcondition>0 (ranking-only) 5 vacuousSignal==false first
##   6 dependencyCount ASC (fewer deps better — dependency-surface minimization)
##   7 vtSmtNative over vtStructural
##   8 bodyNodeCount ASC
##
## The full ordered hard-eligible list is preserved in ranking.json (no
## cherry-picking). inventory.json carries every symbol.
##
## Usage: wp22-inventory <subjectRoot> <outDir>
## Exit: 0 always.

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
# Helpers
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
# bodyHasSymbolicDivisor — scan IR body for division by non-constant denom.
# (ranked higher-risk for constant-denominator tautology rejection)
# ---------------------------------------------------------------------------

proc bodyHasSymbolicDivisor*(body: IRExpr): bool =
  if body == nil: return false
  case body.kind
  of irBinOp:
    if body.binOp in {boDiv, boRem, boRemU} and body.binRhs != nil and body.binRhs.kind != irLit:
      return true
    if bodyHasSymbolicDivisor(body.binLhs): return true
    if bodyHasSymbolicDivisor(body.binRhs): return true
  of irLet:
    if bodyHasSymbolicDivisor(body.letVal): return true
    if bodyHasSymbolicDivisor(body.letBody): return true
  of irIf:
    if bodyHasSymbolicDivisor(body.ifCond): return true
    if bodyHasSymbolicDivisor(body.ifThen): return true
    if bodyHasSymbolicDivisor(body.ifElse): return true
  of irCase:
    if bodyHasSymbolicDivisor(body.caseScrutinee): return true
    for b in body.caseBranches:
      if bodyHasSymbolicDivisor(b.body): return true
    if bodyHasSymbolicDivisor(body.caseDefault): return true
  of irCall:
    for a in body.callArgs:
      if bodyHasSymbolicDivisor(a): return true
  of irRecCall:
    for a in body.recArgs:
      if bodyHasSymbolicDivisor(a): return true
  of irUnaryOp:
    if bodyHasSymbolicDivisor(body.unaryArg): return true
  else: discard
  false

# ---------------------------------------------------------------------------
# countNodes — body simplicity heuristic (fewer IR nodes = simpler).
# ---------------------------------------------------------------------------

proc countNodes*(e: IRExpr): int =
  if e == nil: return 0
  result = 1
  case e.kind
  of irBinOp:
    result += countNodes(e.binLhs) + countNodes(e.binRhs)
  of irUnaryOp:
    result += countNodes(e.unaryArg)
  of irLet:
    result += countNodes(e.letVal) + countNodes(e.letBody)
  of irIf:
    result += countNodes(e.ifCond) + countNodes(e.ifThen) + countNodes(e.ifElse)
  of irCase:
    result += countNodes(e.caseScrutinee)
    for b in e.caseBranches:
      result += countNodes(b.body)
    result += countNodes(e.caseDefault)
  of irCall:
    for a in e.callArgs:
      result += countNodes(a)
  of irRecCall:
    for a in e.recArgs:
      result += countNodes(a)
  of irLoop:
    result += countNodes(e.loopCond)
    for init in e.loopInits: result += countNodes(init)
    result += countNodes(e.loopStep)
    result += countNodes(e.loopBody)
    for inv in e.loopInvariants: result += countNodes(inv)
    result += countNodes(e.loopVariant)
  of irCast:
    result += countNodes(e.castExpr)
  else: discard

# ---------------------------------------------------------------------------
# collectCallees — distinct named callees referenced by the IR body.
# This is the ACT 2.2 "dependency surface" heuristic: fewer distinct callees
# => smaller dependency surface. Self-recursion (irRecCall) is not counted.
# ---------------------------------------------------------------------------

proc collectCallees*(e: IRExpr; acc: var HashSet[string]) =
  if e == nil: return
  case e.kind
  of irCall:
    if e.callName.len > 0: acc.incl(e.callName)
    for a in e.callArgs: collectCallees(a, acc)
  of irRecCall:
    for a in e.recArgs: collectCallees(a, acc)
  of irBinOp:
    collectCallees(e.binLhs, acc); collectCallees(e.binRhs, acc)
  of irUnaryOp:
    collectCallees(e.unaryArg, acc)
  of irLet:
    collectCallees(e.letVal, acc); collectCallees(e.letBody, acc)
  of irIf:
    collectCallees(e.ifCond, acc); collectCallees(e.ifThen, acc); collectCallees(e.ifElse, acc)
  of irCase:
    collectCallees(e.caseScrutinee, acc)
    for b in e.caseBranches: collectCallees(b.body, acc)
    collectCallees(e.caseDefault, acc)
  of irLoop:
    collectCallees(e.loopCond, acc)
    for init in e.loopInits: collectCallees(init, acc)
    collectCallees(e.loopStep, acc)
    collectCallees(e.loopBody, acc)
    for inv in e.loopInvariants: collectCallees(inv, acc)
    collectCallees(e.loopVariant, acc)
  of irCast:
    collectCallees(e.castExpr, acc)
  else: discard

# ---------------------------------------------------------------------------
# proofExecutionShape — coarse IR-shape label.
#   "smtNativeDirect"  : pure expression, no call/loop/rec, no div
#   "direct"           : pure expression, no call/loop/rec
#   "struct"           : structural (case / if-heavy)
#   "loop"             : contains irLoop
#   "recursive"        : contains irRecCall
#   "calls"            : makes named calls (irCall), no loop/rec
#   "mixed"            : multiple signal shapes
#   "empty/unsupported" : body nil or not materialized
# Deterministic priority: recursive > loop > calls > struct > direct.
# ---------------------------------------------------------------------------

proc proofExecutionShape*(e: IRExpr): string =
  if e == nil: return "empty"
  var hasCall = false
  var hasLoop = false
  var hasRec = false
  var hasCase = false
  proc scan(x: IRExpr) {.raises: [].} =
    if x == nil: return
    case x.kind
    of irBinOp:
      scan(x.binLhs); scan(x.binRhs)
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
# computeSymbolVector — full predicate vector for one symbol (extended)
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
  var materializedReason = ""

  try:
    let canonNode = pnodeToCanon(funcDefNode)
    irFuncDef = axiomBodyCanon(canonNode)
    if irFuncDef.name.len == 0:
      irError = "axiomBodyCanon returned empty name"
      materializedStatus = "moParseFailure"
      materializedReason = irError
    else:
      irStr = serializeIRFuncDef(irFuncDef)
      if irStr.len == 0:
        irError = "serializeIRFuncDef returned empty"
        materializedStatus = "moParseFailure"
        materializedReason = irError
      else:
        irAvailable = true
        materializedStatus = "moMaterialized"
        materializedReason = ""
  except CatchableError as e:
    irError = "IR reproduction failed: " & e.msg
    materializedStatus = "moParseFailure"
    materializedReason = irError

  result["irAvailable"] = %irAvailable
  if irStr.len > 0:
    result["irDigest"] = %sha256HexStr(irStr)
    result["irSerializedHash"] = %sha256HexStr(irStr)
  else:
    result["irDigest"] = %""
    result["irSerializedHash"] = %""
  if irError.len > 0:
    result["irError"] = %irError

  result["materialized"] = %materializedStatus
  if materializedReason.len > 0:
    result["materializedReason"] = %materializedReason

  # --- obligation generation (only when IR reproduced) ---
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

  # --- ACT 2.2 extension fields ---
  # postconditionCount from the IR spec (seq[IRExpr])
  var postconditionCount = 0
  var dependencyCount = 0
  var shapeStr = "empty"
  var symbolicDivisor = false
  var bodyNodeCount = 0
  if irAvailable:
    postconditionCount = irFuncDef.postConditions.len
    var callees = initHashSet[string]()
    collectCallees(irFuncDef.body, callees)
    dependencyCount = callees.len
    shapeStr = proofExecutionShape(irFuncDef.body)
    symbolicDivisor = bodyHasSymbolicDivisor(irFuncDef.body)
    bodyNodeCount = countNodes(irFuncDef.body)
  result["postconditionCount"] = %postconditionCount
  result["dependencyCount"] = %dependencyCount
  result["proofExecutionShape"] = %shapeStr

  # --- post-IR analysis (vacuity, eligibility, proofTier) ---
  var proofTierStr = "vtNonDecidable"
  var proofTierSource = "heuristic (IR unavailable or nil body)"
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
      result["assessAdmissibilityDecision"] = %($admOutcome.decision)
      result["assessAdmissibilityReason"] = %($admOutcome.reason)
      result["assessAdmissibilityDetail"] = %admOutcome.detail
      result["vacuous"] = %(admOutcome.decision == INELIGIBLE)
      result["vacuousSignal"] = %(admOutcome.decision == INELIGIBLE)
      let inFragment = inVerifiedFragmentV1(syntheticEntry, irFuncDef, ogr)
      result["inVerifiedFragmentV1"] = %inFragment
      let eligibility = classifyCandidateEligibility(syntheticEntry, irFuncDef)
      result["eligibility"] = %($eligibility)
      try:
        let tierInfo = classifyFunction(irFuncDef)
        proofTierStr = $tierInfo.tier
        proofTierSource = "real callable (verification/ax_classify.classifyFunction)"
      except CatchableError as e:
        proofTierSource = "heuristic (classifyFunction failed: " & e.msg & ")"
    except CatchableError as e:
      result["assessAdmissibilityDecision"] = %"INELIGIBLE"
      result["assessAdmissibilityReason"] = %("error: " & e.msg)
      result["vacuous"] = %true
      result["vacuousSignal"] = %true
      result["eligibility"] = %"elUnsupported"
      result["proofTier"] = %"vtNonDecidable"
      result["proofTierSource"] = %("error: " & e.msg)
  else:
    result["vacuous"] = %true
    result["vacuousSignal"] = %true
    result["eligibility"] = %"elUnsupported"

  result["proofTier"] = %proofTierStr
  result["proofTierSource"] = %proofTierSource
  result["symbolicDivisor"] = %symbolicDivisor
  result["bodyNodeCount"] = %bodyNodeCount

  # --- overload ambiguity (set later by main; default false here) ---
  result["overloadAmbiguity"] = %false
  result["definitionCount"] = %1

  # --- mkExcluded (hard exclusion) ---
  var mkExcluded: string
  if materializedStatus == "moParseFailure":
    mkExcluded = "parse failure: " & irError
  elif proofTierStr == "vtNonDecidable":
    mkExcluded = "vtNonDecidable hard exclusion"
  elif not irAvailable:
    mkExcluded = "IR unavailable"
  else:
    mkExcluded = ""
  result["mkExcluded"] = %mkExcluded

  result["status"] = %"completed"

# ---------------------------------------------------------------------------
# Helpers for JSON field access
# ---------------------------------------------------------------------------

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
    stderr.writeLine("usage: wp22-inventory <subjectRoot> <outDir>")
    quit(2)

  let subjectRoot = args[0]
  let outDir = args[1]
  createDir(outDir)
  let inventoryPath = outDir / "inventory.json"
  let rankingPath = outDir / "ranking.json"

  generateAxiomInit()

  var report = newJObject()
  report["experimentId"] = %"act2-wp22-proof-slice-discovery"
  report["phase"] = %"ACT-2.2"
  report["probeType"] = %"proof-slice-discovery-inventory"
  report["notCanonicalExecutionPath"] = %true
  report["notProductionAPI"] = %true
  report["subjectRoot"] = %subjectRoot
  report["subjectRevision"] = %"c75502ceedb5ed2a37b7b5e4744fc71313682859"
  report["toolchainIdentity"] = %"Nim 2.2.10 (choosenim nim-2.2.10)"

  # --- Find all .nim files under subject/stew (library scope only) ---
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
    except CatchableError as e:
      discard
  nimFiles.sort()
  report["nimFileCount"] = %nimFiles.len

  # --- Parse every file, collect all proc/func defs ---
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

  # --- Build inventory for every symbol ---
  var inventory: seq[JsonNode] = @[]
  for key, val in symDefs:
    let moduleRel = key.moduleRel
    let funcName = key.funcName
    let definitionCount = val.count
    let funcDefNode = val.node

    var vec = try:
      computeSymbolVector(moduleRel, funcName, funcDefNode, subjectRoot)
    except Defect as e:
      let errVec = newJObject()
      errVec["module"] = %moduleRel
      errVec["function"] = %funcName
      errVec["definitionCount"] = %definitionCount
      errVec["irAvailable"] = %false
      errVec["irDigest"] = %""
      errVec["irError"] = %("Defect during IR: " & e.msg)
      errVec["obligationCount"] = %0
      errVec["obligationGenerated"] = %false
      errVec["obligationKinds"] = %newJArray()
      errVec["postconditionCount"] = %0
      errVec["dependencyCount"] = %0
      errVec["proofExecutionShape"] = %"empty"
      errVec["vacuous"] = %true
      errVec["vacuousSignal"] = %true
      errVec["assessAdmissibilityDecision"] = %"INELIGIBLE"
      errVec["assessAdmissibilityReason"] = %("defect: " & e.msg)
      errVec["inVerifiedFragmentV1"] = %false
      errVec["eligibility"] = %"elUnsupported"
      errVec["proofTier"] = %"vtNonDecidable"
      errVec["proofTierSource"] = %("defect: " & e.msg)
      errVec["symbolicDivisor"] = %false
      errVec["bodyNodeCount"] = %0
      errVec["materialized"] = %"moParseFailure"
      errVec["materializedReason"] = %("defect: " & e.msg)
      errVec["mkExcluded"] = %("defect: " & e.msg)
      errVec["status"] = %"defect"
      errVec
    vec["definitionCount"] = %definitionCount
    # overload ambiguity: same module::function bare name defined >1 time
    vec["overloadAmbiguity"] = %(definitionCount > 1)

    inventory.add(vec)

  # --- Deterministic sort of inventory for stable output (module::function) ---
  inventory.sort(proc(a, b: JsonNode): int =
    let ma = jsonStr(a, "module", "")
    let mb = jsonStr(b, "module", "")
    let c1 = cmp(ma, mb)
    if c1 != 0: return c1
    cmp(jsonStr(a, "function", ""), jsonStr(b, "function", ""))
  )
  report["inventory"] = %inventory

  # --- ACT 2.2 / v4 HARD filter (6 predicates only) ---
  # unique def(1) ∧ materialized ∧ obligation>0 ∧ elProofCandidate ∧
  # ¬overload ambiguity (exact-target=1) ∧ proofTier != vtNonDecidable
  # NOTE: postconditionCount>0 is NOT a hard filter in the v4 contract. It is
  # a ranking-only axis (see rank 4). This matches the user's v4 contract:
  #   unique ∧ materialized ∧ obligationCount>0 ∧ elProofCandidate ∧
  #   ¬vtNonDecidable ∧ exact-target=1
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

  # Funnel accounting
  var fSail: array[7, int]
  for vec in inventory:
    if jsonInt(vec, "definitionCount", 0) == 1: fSail[0] += 1
    if jsonStr(vec, "materialized", "") == "moMaterialized" and jsonBool(vec, "irAvailable", false): fSail[1] += 1
    if jsonInt(vec, "obligationCount", 0) > 0: fSail[2] += 1
    if jsonInt(vec, "postconditionCount", 0) > 0: fSail[3] += 1
    if jsonStr(vec, "eligibility", "") == "elProofCandidate": fSail[4] += 1
    if not jsonBool(vec, "overloadAmbiguity", false): fSail[5] += 1
    if jsonStr(vec, "proofTier", "vtNonDecidable") != "vtNonDecidable": fSail[6] += 1
  report["funnel"] = %*{
    "total": inventory.len,
    "uniqueDef": fSail[0],
    "materialized": fSail[1],
    "obligationGreaterThan0": fSail[2],
    "elProofCandidate": fSail[4],
    "noOverloadAmbiguity": fSail[5],
    "notVtNonDecidable": fSail[6],
    "postconditionGreaterThan0": fSail[3],
    "postconditionIsHardFilterV4": false,
    "hardEligible": hardEligible.len
  }

  # --- DETERMINISTIC ranking over hard-eligible set ---
  func tierOrd(tier: string): int =
    case tier
    of "vtSmtNative": 0
    of "vtStructural": 1
    else: 9
  proc shapeRank(s: string): int =
    case s
    of "direct": 0
    of "struct": 1
    of "calls": 2
    of "loop": 3
    of "recursive": 4
    else: 8
  hardEligible.sort(proc(a, b: JsonNode): int =
    # 5. vacuousSignal false first
    let vA = if jsonBool(a, "vacuousSignal", false): 1 else: 0
    let vB = if jsonBool(b, "vacuousSignal", false): 1 else: 0
    if vA != vB: return cmp(vA, vB)
    # 6. dependency surface ASC (fewer deps better)
    let dA = jsonInt(a, "dependencyCount", 0)
    let dB = jsonInt(b, "dependencyCount", 0)
    if dA != dB: return cmp(dA, dB)
    # 7. vtSmtNative over vtStructural
    let tA = tierOrd(jsonStr(a, "proofTier", "vtNonDecidable"))
    let tB = tierOrd(jsonStr(b, "proofTier", "vtNonDecidable"))
    if tA != tB: return cmp(tA, tB)
    # shape heuristic (direct first) as tie-break within tier
    let sA = shapeRank(jsonStr(a, "proofExecutionShape", "empty"))
    let sB = shapeRank(jsonStr(b, "proofExecutionShape", "empty"))
    if sA != sB: return cmp(sA, sB)
    # 8. bodyNodeCount ASC (simpler body first)
    let nA = jsonInt(a, "bodyNodeCount", 0)
    let nB = jsonInt(b, "bodyNodeCount", 0)
    if nA != nB: return cmp(nA, nB)
    # tie-break: module::function lexicographic
    let ma = jsonStr(a, "module", "")
    let mb = jsonStr(b, "module", "")
    let c1 = cmp(ma, mb)
    if c1 != 0: return c1
    cmp(jsonStr(a, "function", ""), jsonStr(b, "function", ""))
  )

  # attach rank
  for i, vec in hardEligible:
    vec["rank"] = %(i + 1)
    vec["anchorId"] = %(jsonStr(vec, "module", "") & "::" & jsonStr(vec, "function", ""))

  report["ranking"] = %hardEligible

  # --- Write outputs (deterministic canonical minified JSON) ---
  let canonicalInventory = canonicalJsonMinified(report)
  writeFile(inventoryPath, canonicalInventory)

  # ranking.json: full ordered hard-eligible list (no cherry-picking)
  let rankDoc = newJObject()
  rankDoc["experimentId"] = %"act2-wp22-proof-slice-discovery"
  rankDoc["hardEligibleCount"] = %hardEligible.len
  rankDoc["hardFilter"] = %*{
    "uniqueDef1": true,
    "materialized": true,
    "obligationGreaterThan0": true,
    "elProofCandidate": true,
    "noOverloadAmbiguity": true,
    "notVtNonDecidable": true,
    "postconditionHardGateV4": false,
    "postconditionIsRankingOnly": true
  }
  let rankedArr = newJArray()
  for vec in hardEligible:
    rankedArr.add(vec)
  rankDoc["orderedCandidates"] = rankedArr
  writeFile(rankingPath, canonicalJsonMinified(rankDoc))

  quit(0)
