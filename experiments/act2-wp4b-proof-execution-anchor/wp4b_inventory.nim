## experiments/act2-wp4b-proof-execution-anchor/wp4b-inventory.nim
## — Act2-WP4b Full-Tree Candidate Inventory Probe
##
## EXPERIMENT-ONLY instrument.
##   - NOT a canonical execution path
##   - NOT a production API
##   - NOT part of the shipped product / CLI
##   - NOT wired into the engine
##
## Probe for WP4-b Phase 1: full-tree candidate inventory over nim-stew.
## Iterates EVERY proc/func def in EVERY .nim file under the subject
## and computes the 9+ field predicate vector per symbol.
##
## Computes per symbol:
##   - module, function, definitionCount
##   - irDigest (sha256 of serializeIRFuncDef)
##   - obligationCount / obligationKinds
##   - vacuous (assessAdmissibility INELIGIBLE = no meaningful postcondition)
##   - admissibility (assessAdmissibility decision)
##   - eligibility (classifyCandidateEligibility)
##   - proofTier (classifyFunction tier)
##   - materialized (moMaterialized | moNotFound | moAmbiguousOverload | moParseFailure)
##   - mkExcluded (hard exclusion reason or null)
##   - symbolicDivisor (body contains div/mod by non-constant denom)
##   - inVerifiedFragmentV1
##   - bodyNodeCount (body simplicity heuristic)
##
## Usage: wp4b-inventory <subjectRoot> <outJsonPath>
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
# findAllFuncDefsP — reimplemented from infrastructure/external_ir_materializer
# (avoids pulling in ModuleContentResolver / IOEffect chain in a standalone
#  inventory probe while keeping identical lookup semantics).
# ---------------------------------------------------------------------------

func findAllFuncDefsP*(root: PNode; procName: string): seq[PNode] =
  var stack: seq[PNode] = @[root]
  while stack.len > 0:
    let n = stack.pop()
    if n.isNil: continue
    if n.kind in {nkEmpty, nkIdent, nkSym, nkCharLit,
                  nkIntLit..nkInt64Lit, nkUIntLit..nkUInt64Lit,
                  nkFloatLit..nkFloat128Lit, nkStrLit, nkRStrLit,
                  nkTripleStrLit, nkNilLit}:
      continue
    if n.kind in {nkFuncDef, nkProcDef} and n.len > 0:
      var nameText = ""
      let head = n[0]
      if not head.isNil:
        case head.kind
        of nkIdent: nameText = head.ident.s
        of nkSym: nameText = head.sym.name.s
        of nkPostfix:
          if head.len > 1 and not head[1].isNil and head[1].kind == nkIdent:
            nameText = head[1].ident.s
        else: discard
      if nameText == procName:
        result.add(n)
    for i in 0 ..< n.len:
      if not n[i].isNil and n.kind notin {nkEmpty, nkIdent, nkSym, nkCharLit,
          nkIntLit..nkInt64Lit, nkUIntLit..nkUInt64Lit,
          nkFloatLit..nkFloat128Lit, nkStrLit, nkRStrLit, nkTripleStrLit, nkNilLit}:
        stack.add(n[i])

# ---------------------------------------------------------------------------
# bodyHasSymbolicDivisor — scan IR body for division by non-constant denom.
#
# A function whose body divides by a non-literal (param/variable) denominator
# is ranked higher because a constant-denominator div synthesizes a `const != 0`
# precondition that the Z3 gate rejects as tautology (decodedLength case).
# Scans irBinOp nodes: boDiv (signed div), boRem (signed mod %), boRemU (unsigned %%).
# Source-of-truth: instruction specifies nkDiv/nkDivI/nkModI at the Nim-AST
# level; at the IR level the equivalent nodes are irBinOp with the OpKind set
# above and a non-lit RHS.
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
# computeSymbolVector — full 9+ predicate vector for one symbol
# ---------------------------------------------------------------------------

proc computeSymbolVector*(module: string; funcName: string;
    funcDefNode: PNode; subjectRoot: string): JsonNode =
  result = newJObject()
  result["module"] = %module
  result["function"] = %funcName

  # --- IR reproduction ---
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

  # --- materialized field ---
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

  # --- post-IR analysis (vacuity, eligibility, proofTier) ---
  var proofTierStr = "vtNonDecidable"
  var proofTierSource = "heuristic (IR unavailable or nil body)"
  var symbolicDivisor = false
  var bodyNodeCount = 0
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
      symbolicDivisor = bodyHasSymbolicDivisor(irFuncDef.body)
      bodyNodeCount = countNodes(irFuncDef.body)
    except CatchableError as e:
      result["assessAdmissibilityDecision"] = %"INELIGIBLE"
      result["assessAdmissibilityReason"] = %("error: " & e.msg)
      result["vacuous"] = %true
      result["eligibility"] = %"elUnsupported"
      result["proofTier"] = %"vtNonDecidable"
      result["proofTierSource"] = %("error: " & e.msg)
  else:
    result["vacuous"] = %true
    result["eligibility"] = %"elUnsupported"

  result["proofTier"] = %proofTierStr
  result["proofTierSource"] = %proofTierSource
  result["symbolicDivisor"] = %symbolicDivisor
  result["bodyNodeCount"] = %bodyNodeCount

  # --- mkExcluded (hard exclusion) ---
  # Three hard exclusions per plan:
  #   (a) function name appears only in a .nim that fails to parse (materialized == moParseFailure)
  #   (b) template/macro keyword (elUnsupported) — handled by only scanning nkProcDef/nkFuncDef
  #   (c) vtNonDecidable (the only HARD exclusion per the plan)
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

  # --- status ---
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
    stderr.writeLine("usage: wp4b-inventory <subjectRoot> <outJsonPath>")
    quit(2)

  let subjectRoot = args[0]
  let outJsonPath = args[1]

  # Initialize the compile-time registry
  let debugLog = "/tmp/wp4b_debug.txt"
  writeFile(debugLog, "start\n")
  generateAxiomInit()
  writeFile(debugLog, readFile(debugLog) & "init_done\n")

  var report = newJObject()
  report["experimentId"] = %"act2-wp4b-proof-execution-anchor"
  report["phase"] = %"Phase-1"
  report["probeType"] = %"full-tree-candidate-inventory"
  report["notCanonicalExecutionPath"] = %true
  report["notProductionAPI"] = %true
  report["subjectRoot"] = %subjectRoot

  # --- Find all .nim files under the subject ---
  proc collectNimFiles(dir: string; result: var seq[string]) {.raises: [OSError].} =
    for kind, path in walkDir(dir):
      if kind == pcFile and path.endsWith(".nim"):
        result.add(path)
      elif kind == pcDir and path notin [".", ".."]:
        collectNimFiles(path, result)
  var nimFiles: seq[string] = @[]
  # Library scope only: walk subjectRoot/stew recursively (covers stew/ranges, stew/shims,
  # stew/windows etc). Do NOT walk subjectRoot (would pull in tests/ and double-walk stew/).
  let libRoot = subjectRoot / "stew"
  if dirExists(libRoot):
    try:
      collectNimFiles(libRoot, nimFiles)
    except CatchableError as e:
      discard
  nimFiles.sort()
  report["nimFileCount"] = %nimFiles.len
  writeFile(debugLog, readFile(debugLog) & "files=" & $nimFiles.len & "\n")

  # --- Parse every file, collect all proc/func defs ---
  # Map: (moduleRel, functionName) -> (defCount, node, fileFullPath)
  type SymKey = tuple[moduleRel, funcName: string]
  var symDefs = initTable[SymKey, tuple[count: int, node: PNode, fullPath: string]]()
  var fileProcCount = initTable[string, int]()   # module -> number of func defs found
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
    var found = 0
    for node in findNodesP(ast, {nkProcDef, nkFuncDef}):
      let name = getProcName(node[0])
      if name.len == 0: continue
      # Exclude templates/macros explicitly (they are elUnsupported)
      # node.kind is nkProcDef or nkFuncDef here (from findNodesP filter),
      # so templates/macros (nkMacroDef/nkTemplateDef) are already excluded.
      let key: SymKey = (moduleRel, name)
      if symDefs.hasKey(key):
        symDefs[key].count += 1
      else:
        symDefs[key] = (count: 1, node: node, fullPath: fullPath)
      found += 1
    if found > 0:
      fileProcCount[moduleRel] = found

  report["fileProcCount"] = newJObject()
  for k, v in fileProcCount:
    report["fileProcCount"][k] = %v
  report["fileParseFailures"] = %fileParseFailures
  report["uniqueSymbols"] = %symDefs.len
  writeFile(debugLog, readFile(debugLog) & "syms=" & $symDefs.len & "\n")

  # --- Build inventory for every symbol ---
  var inventory: seq[JsonNode] = @[]
  var invCount = 0
  for key, val in symDefs:
    invCount += 1
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
      errVec["vacuous"] = %true
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

    # Shortlist pre-compute flags
    let isMaterialized = vec["materialized"].getStr == "moMaterialized"
    let isEligible = vec["eligibility"].getStr == "elProofCandidate"
    let isObligation = vec["obligationCount"].getInt > 0
    let isUniqueDef = definitionCount == 1
    let isVacuous = vec["vacuous"].getBool
    let isMkExcluded = vec["mkExcluded"].getStr.len > 0
    let proofTier = vec["proofTier"].getStr
    let isNonDecidable = proofTier == "vtNonDecidable"

    vec["shortlistEligible"] = %isMaterialized
    # (full shortlist logic applied in post-filter)

    inventory.add(vec)
  writeFile(debugLog, readFile(debugLog) & "inv=" & $inventory.len & "\n")

  # --- Sort inventory: vtSmtNative first, then vtStructural; non-vacuous first; symbolicDivisor ---
  func tierOrd(tier: string): int =
    case tier
    of "vtSmtNative": 0
    of "vtStructural": 1
    of "vtNonDecidable": 2
    else: 9
  inventory.sort(proc(a, b: JsonNode): int =
    let oA = tierOrd(jsonStr(a, "proofTier", "vtNonDecidable"))
    let oB = tierOrd(jsonStr(b, "proofTier", "vtNonDecidable"))
    if oA != oB: return cmp(oA, oB)
    let vA = if jsonBool(a, "vacuous", false): 1 else: 0
    let vB = if jsonBool(b, "vacuous", false): 1 else: 0
    if vA != vB: return cmp(vA, vB)
    let sA = if jsonBool(a, "symbolicDivisor", false): 1 else: 0
    let sB = if jsonBool(b, "symbolicDivisor", false): 1 else: 0
    if sA != sB: return cmp(sA, sB)
    let nA = jsonInt(a, "bodyNodeCount", 0)
    let nB = jsonInt(b, "bodyNodeCount", 0)
    return cmp(nA, nB)
  )

  report["inventory"] = %inventory

  # --- Shortlist funnel ---
  var total = inventory.len
  var fObligation = 0
  var fEligibility = 0
  var fUniqueDef = 0
  var fMaterialized = 0
  var shortlist: seq[JsonNode] = @[]

  for vec in inventory:
    let isObligation = jsonInt(vec, "obligationCount", 0) > 0
    let isEligible = jsonStr(vec, "eligibility", "") == "elProofCandidate"
    let isUniqueDef = jsonInt(vec, "definitionCount", 0) == 1
    let isMaterialized = jsonStr(vec, "materialized", "") == "moMaterialized"
    let isMkExcluded = jsonStr(vec, "mkExcluded", "").len > 0
    let proofTier = jsonStr(vec, "proofTier", "vtNonDecidable")

    if isObligation: fObligation += 1
    if isEligible: fEligibility += 1
    if isUniqueDef: fUniqueDef += 1
    if isMaterialized and not isMkExcluded: fMaterialized += 1

    if isObligation and isEligible and isUniqueDef and isMaterialized and not isMkExcluded and proofTier != "vtNonDecidable":
      shortlist.add(vec)

  report["shortlist"] = %shortlist
  writeFile(debugLog, readFile(debugLog) & "shortlist=" & $shortlist.len & "\n")
  report["funnel"] = %*{
    "total": total,
    "obligationGreaterThan0": fObligation,
    "eligibilityElProofCandidate": fEligibility,
    "uniqueDefinitionCount1": fUniqueDef,
    "materializedMoMaterialized": fMaterialized,
    "shortlistFinal": shortlist.len
  }

  # --- Commands used ---
  report["commands"] = %*[
    {"cmd": "nim c -d:release --hints:off -o:/tmp/wp4b_inventory_bin experiments/act2-wp4b-proof-execution-anchor/wp4b-inventory.nim", "desc": "build probe"},
    {"cmd": "/tmp/wp4b_inventory_bin <workspace>/nim-stew-clean-c75502c /tmp/wp4b-inventory.json", "desc": "run probe over nim-stew"}
  ]

  # --- proofTier source ---
  var realCallableCount = 0
  var heuristicCount = 0
  for vec in inventory:
    if jsonStr(vec, "proofTierSource", "").contains("real callable"): realCallableCount += 1
    else: heuristicCount += 1
  report["proofTierSourceCounts"] = %*{
    "realCallable": realCallableCount,
    "heuristicFallback": heuristicCount
  }

  writeFile(debugLog, readFile(debugLog) & "before_write\n")
  let canonicalJsonOut = canonicalJsonMinified(report)
  writeFile(debugLog, readFile(debugLog) & "json_len=" & $canonicalJsonOut.len & "\n")
  try:
    writeFile(outJsonPath, canonicalJsonOut)
    writeFile(debugLog, readFile(debugLog) & "wrote\n")
  except CatchableError:
    quit(1)

  quit(0)
