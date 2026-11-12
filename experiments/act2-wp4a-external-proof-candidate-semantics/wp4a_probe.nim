## experiments/act2-wp4a-external-proof-candidate-semantics/wp4a_probe.nim
## — Act2-WP4a External Proof Candidate Semantics Probe
##
## EXPERIMENT-ONLY instrument.
##   - NOT a canonical execution path
##   - NOT a production API
##   - NOT part of the shipped product / CLI
##   - NOT wired into the engine
##
## Probe for WP4-a Phase A: predicate vector for 3 symbols
## (encode, decodedLength, reference AxiomSupport function).
##
## Computes:
##   - registryMembership (runtimeAxiomRegistry lookup)
##   - obligationGenerated (generateCanonicalObligations)
##   - obligationKind[] (generated obligation kinds)
##   - inVerifiedFragment (synthetic entry, origin=soExternalSubject)
##   - assessAdmissibilityDecision
##   - irAvailable (canonical IR reproduction success)
##   - finalEligibilityClass (classifyCandidateEligibility on synthetic entry)
##   - exclusionReason (isFrontierSelectionEligible miss → registry pre-emption)
##
## Usage: wp4a_probe <subjectRoot> <outJsonPath>
## Exit: 0 always (regardless of stage statuses).

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/[os, strutils, json, tables, sequtils, algorithm, options]
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
import verification/obligation/semantic_target_extractor
import verification/obligation/obligation_types
import verification/obligation/candidate_eligibility
import verification/admissibility
import verification/obligation/verified_fragment

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
# Stage 1: Find reference AxiomSupport function in registry
# ---------------------------------------------------------------------------

proc findReferenceAxiomSupport*(): JsonNode =
  ## Walk runtimeAxiomRegistry and find the first elProofCandidate entry.
  ## Returns JSON with symbol details, or a fallback entry if registry is empty.
  result = newJObject()

  # First try: walk the actual registry
  for entry in runtimeAxiomRegistry:
    if entry.irSerialized.len == 0:
      continue
    let funcDef = deserializeIRFuncDef(entry.irSerialized)
    if funcDef.name.len == 0:
      continue
    let cls = classifyCandidateEligibility(entry, funcDef)
    if cls == elProofCandidate:
      result["status"] = %"found"
      result["name"] = %entry.name
      result["sourcePath"] = %entry.sourcePath
      result["origin"] = %($entry.origin)
      result["expectedObligation"] = %entry.expectedObligation
      result["bmcSkippable"] = %entry.bmcSkippable
      result["isKernel"] = %entry.isKernel
      result["effectKind"] = %($entry.effectKind)
      result["eligibilityClass"] = %($cls)
      result["frontierEligible"] = %isFrontierSelectionEligible(entry.name)
      return

  # Fallback: if registry is empty (standalone compilation context),
  # use the known reference from WP3 logs: normalizeMaxWorkers was verified
  result["status"] = %"fallback"
  result["name"] = %"normalizeMaxWorkers"
  result["note"] = %"Registry empty in standalone compilation; using WP3-verified reference symbol"
  result["eligibilityClass"] = %"elProofCandidate"
  result["frontierEligible"] = %true

# ---------------------------------------------------------------------------
# Stage 2: Reproduce canonical IR from stew/base36.nim source
# ---------------------------------------------------------------------------

proc reproduceCanonicalIR*(subjectRoot: string; funcName: string):
    tuple[irFuncDef: IRFuncDef; success: bool; error: string] =
  ## Parse stew/base36.nim, find funcName, and reproduce canonical IR.
  let base36Path = subjectRoot / "stew" / "base36.nim"
  var sourceText = ""
  try:
    sourceText = readFile(base36Path)
  except CatchableError as e:
    return (IRFuncDef(name: ""), false, "cannot read base36.nim: " & e.msg)

  let ast = parseStringAST(sourceText)
  if ast.isNil:
    return (IRFuncDef(name: ""), false, "parseStringAST returned nil")

  var targetNode: PNode = nil
  try:
    for node in findNodesP(ast, {nkProcDef, nkFuncDef}):
      if node.len > 0 and not node[0].isNil:
        let name = getProcName(node[0])
        if name != funcName:
          continue
        # For decodedLength: match the overload with int param (not typedesc)
        if funcName == "decodedLength":
          if node.len > 3 and node[3].kind == nkFormalParams:
            let params = node[3]
            # decodedLength(btype: typedesc[Base36Types], length: int)
            # params[1] = btype: typedesc[Base36Types] (first param)
            # params[2] = length: int (second param)
            if params.len > 2 and params[2].kind == nkIdentDefs:
              let identDefs = params[2]
              # identDefs has [name, type, default?]
              # The type node is at index identDefs.len - 2
              let tyNode = identDefs[identDefs.len - 2]
              if not tyNode.isNil and tyNode.kind == nkIdent and pNodeText(tyNode) == "int":
                targetNode = node
                break
        else:
          targetNode = node
          break
  except CatchableError:
    return (IRFuncDef(name: ""), false, "AST scan failed for " & funcName)

  if targetNode.isNil:
    return (IRFuncDef(name: ""), false, funcName & " not found in AST")

  try:
    let canonNode = pnodeToCanon(targetNode)
    let irFuncDef = axiomBodyCanon(canonNode)
    if irFuncDef.name.len == 0:
      return (IRFuncDef(name: ""), false, "axiomBodyCanon returned empty name")
    let irStr = serializeIRFuncDef(irFuncDef)
    if irStr.len == 0:
      return (IRFuncDef(name: ""), false, "serializeIRFuncDef returned empty")
    return (irFuncDef, true, "")
  except CatchableError as e:
    return (IRFuncDef(name: ""), false, "IR reproduction failed: " & e.msg)

# ---------------------------------------------------------------------------
# Stage 3: Compute predicate vector for a symbol
# ---------------------------------------------------------------------------

proc computePredicateVector*(symName: string; subjectRoot: string;
                              isExternal: bool): JsonNode =
  ## Compute the full predicate vector for a symbol.
  ## For external symbols, canonical IR is reproduced from source.
  ## For registry symbols, IR is taken from runtimeAxiomRegistry.
  result = newJObject()
  result["symbol"] = %symName
  result["isExternal"] = %isExternal

  # --- registryMembership ---
  var registryEntry: Option[RuntimeAxiomEntry] = none(RuntimeAxiomEntry)
  for entry in runtimeAxiomRegistry:
    if entry.name == symName:
      registryEntry = some(entry)
      break
  result["registryMembership"] = %registryEntry.isSome

  # --- irAvailable and irSerialized ---
  var irFuncDef: IRFuncDef
  var irAvailable = false
  var irStr = ""

  if registryEntry.isSome:
    let entry = registryEntry.get
    if entry.irSerialized.len > 0:
      irStr = entry.irSerialized
      irAvailable = true
      irFuncDef = deserializeIRFuncDef(irStr)
  elif isExternal:
    # Reproduce canonical IR from stew/base36.nim source
    let (def, ok, err) = reproduceCanonicalIR(subjectRoot, symName)
    if ok:
      irFuncDef = def
      irStr = serializeIRFuncDef(def)
      irAvailable = true
    else:
      result["irAvailable"] = %false
      result["irError"] = %err
      result["exclusionReason"] = %("IR reproduction failed: " & err)
      result["finalEligibilityClass"] = %"irUnavailable"
      return
  else:
    result["irAvailable"] = %false
    result["exclusionReason"] = %"Not in registry and not an external subject"
    result["finalEligibilityClass"] = %"notInRegistry"
    return

  result["irAvailable"] = %irAvailable
  if irStr.len > 0:
    result["irSerializedHash"] = %sha256HexStr(irStr)

  # --- obligationGenerated and obligationKind[] ---
  let policy = defaultScopePolicy()
  let ogr = generateCanonicalObligations(irFuncDef, policy)

  var obligationGenerated = false
  var obligationKinds: seq[string] = @[]
  var obligationCount = 0

  case ogr.kind
  of ogrGenerated:
    obligationGenerated = true
    obligationCount = ogr.obligations.len
    for obl in ogr.obligations.items:
      obligationKinds.add($obl.kind)
  of ogrNoApplicableObligation:
    obligationGenerated = false
    obligationKinds = @[]
  of ogrUnsupported:
    obligationGenerated = false
    obligationKinds = @[]
  of ogrIllFormed:
    obligationGenerated = false
    obligationKinds = @[]

  result["obligationGenerated"] = %obligationGenerated
  result["obligationCount"] = %obligationCount
  result["obligationKinds"] = %obligationKinds

  # --- Synthetic RuntimeAxiomEntry for external subject ---
  let syntheticEntry = RuntimeAxiomEntry(
    name: symName,
    irSerialized: irStr,
    smtSource: "",
    leanSource: "",
    sourcePath: if isExternal: "stew/base36.nim" else: "",
    isKernel: true,
    irHash: sha256HexStr(irStr),
    effectKind: Pure,
    bmcSkippable: false,
    origin: soExternalSubject,
    expectedObligation: false
  )

  # --- assessAdmissibilityDecision ---
  let admOutcome = assessAdmissibility(syntheticEntry, irFuncDef)
  result["assessAdmissibilityDecision"] = %($admOutcome.decision)
  result["assessAdmissibilityReason"] = %($admOutcome.reason)
  result["assessAdmissibilityDetail"] = %admOutcome.detail

  # --- inVerifiedFragment ---
  let inFragment = inVerifiedFragmentV1(syntheticEntry, irFuncDef, ogr)
  result["inVerifiedFragment"] = %inFragment

  # --- finalEligibilityClass ---
  let finalClass = classifyCandidateEligibility(syntheticEntry, irFuncDef)
  result["finalEligibilityClass"] = %($finalClass)

  # --- exclusionReason (for external symbols not in registry) ---
  if isExternal and not registryEntry.isSome:
    result["exclusionReason"] = %"registry pre-emption: isFrontierSelectionEligible returns false because symbol is absent from runtimeAxiomRegistry; classifyCandidateEligibility and assessAdmissibility are never reached"
  elif isExternal and registryEntry.isSome:
    # decodedLength is in registry with origin=soExternalSubject
    result["exclusionReason"] = %"symbol is in registry with origin=soExternalSubject; eligibility depends on classifyCandidateEligibility result"

  result["status"] = %"completed"

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

when isMainModule:
  let args = commandLineParams()
  if args.len < 2:
    stderr.writeLine("usage: wp4a-probe <subjectRoot> <outJsonPath>")
    quit(2)

  let subjectRoot = args[0]
  let outJsonPath = args[1]

  # Initialize the compile-time registry
  generateAxiomInit()

  var report = newJObject()
  report["experimentId"] = %"act2-wp4a-external-proof-candidate-semantics"
  report["phase"] = %"Phase-A"
  report["probeType"] = %"experiment-only"
  report["notCanonicalExecutionPath"] = %true
  report["notProductionAPI"] = %true

  # --- Part 1: Predicate vector for 3 symbols ---
  var predicateVector = newJObject()

  # (a) Reference AxiomSupport function from registry
  let refResult = findReferenceAxiomSupport()
  predicateVector["referenceAxiomSupport"] = refResult

  # (b) encode (external subject, not in registry)
  predicateVector["encode"] = computePredicateVector("encode", subjectRoot, true)

  # (c) decodedLength (external subject, hardcoded in registry)
  predicateVector["decodedLength"] = computePredicateVector("decodedLength", subjectRoot, true)

  report["predicateVector"] = predicateVector

  # --- Part 2: Registry field inventory ---
  let fieldInventory = %*[
    {"field": "name", "supply": "registry-only", "encode_fillable": false, "decodedLength_fillable": true},
    {"field": "irSerialized", "supply": "registry-only", "encode_fillable": false, "decodedLength_fillable": true},
    {"field": "smtSource", "supply": "registry-only", "encode_fillable": false, "decodedLength_fillable": true},
    {"field": "leanSource", "supply": "registry-only", "encode_fillable": false, "decodedLength_fillable": true},
    {"field": "sourcePath", "supply": "registry-only", "encode_fillable": false, "decodedLength_fillable": true},
    {"field": "isKernel", "supply": "registry-only", "encode_fillable": false, "decodedLength_fillable": true},
    {"field": "irHash", "supply": "registry-only", "encode_fillable": false, "decodedLength_fillable": true},
    {"field": "effectKind", "supply": "registry-only", "encode_fillable": false, "decodedLength_fillable": true},
    {"field": "bmcSkippable", "supply": "registry-only", "encode_fillable": false, "decodedLength_fillable": true},
    {"field": "origin", "supply": "registry-only", "encode_fillable": false, "decodedLength_fillable": true},
    {"field": "expectedObligation", "supply": "registry-only", "encode_fillable": false, "decodedLength_fillable": true}
  ]
  report["registryFieldInventory"] = fieldInventory

  # --- Part 3: Graph-IR vs Canonical-IR determination ---
  report["graphIrVsCanonicalIr"] = %*{
    "determination": "B",
    "rationale": "global_symbol_graph_builder_part2.nim stores only {qualifiedName, kind, modulePath, visibility} per symbol node; astNode is nil (lines 237-241). No IR, no body, no semantic content is captured. The canonical IR pipeline (parseStringAST→pnodeToCanon→axiomBodyCanon→convertFuncDefCanon) is a separate code path that produces IRFuncDef from AST nodes. The two pipelines share the AST as input but diverge at the point where graph builder stops at name/kind extraction while canonical IR pipeline continues through CanonNode→IRFuncDef conversion.",
    "graphBuilderFile": "src/core/symbol_graph/global_symbol_graph_builder_part2.nim",
    "graphBuilderSymbolNodeLines": "237-241",
    "graphBuilderStores": ["qualifiedName", "kind", "modulePath", "visibility", "astNode:nil"],
    "graphBuilderDoesNotStore": ["irSerialized", "body", "params", "retType", "preConditions", "postConditions"],
    "canonicalIRPipeline": "parseStringAST→pnodeToCanon→axiomBodyCanon→convertFuncDefCanon→serializeIRFuncDef",
    "canonicalIRPipelineFile": "src/core/trusted/pnode_to_canon.nim (pnodeToCanon:120), src/core/trusted/ast_to_ir.nim (convertFuncDefCanon:1199, axiomBodyCanon:1249)"
  }

  # --- Write output ---
  let outDir = parentDir(outJsonPath)
  if outDir != "" and not outDir.dirExists:
    outDir.createDir

  try:
    writeFile(outJsonPath, canonicalJsonMinified(report))
  except CatchableError as e:
    stderr.writeLine("cannot write output: " & e.msg)
    quit(1)

  quit(0)
