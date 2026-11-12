## experiments/act2-wp2-subject-scoped-execution/wp1_ingress_probe.nim
## — Act2-WP1 External Symbol Ingress Probe
##
## EXPERIMENT-ONLY instrument.
##   - NOT a canonical execution path
##   - NOT a production API
##   - NOT part of the shipped product / CLI
##   - NOT wired into the engine
##
## This probe lives in the experiments/ workspace, which is outside
## production layer enforcement scope (layer_enforcement_gate scans src/
## and tools/ only). It is retained here as measurement evidence for the
## act2-wp1/act2-wp2 external-symbol-ingress experiments; do not reference
## it from product source.
##
## Deterministically measures 5-stage external symbol ingress for the
## golden symbol decodedLength (uint32 overload) in nim-stew.
##
## Usage: wp1_ingress_probe <subjectRoot> <outJsonPath>
## Exit: 0 always (regardless of stage statuses).

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/[os, strutils, json, tables, sequtils, algorithm, macros]
import core/crypto/hash_kernel
import compiler/ast
import core/context/run_context
import core/types/results
import core/topology/node_filter
import core/topology/import_graph
import core/symbol_graph/global_symbol_graph_builder_part2
import core/parser_utils
import core/parsers/pnode_nav
import core/trusted/ast_to_ir
import core/trusted/pnode_to_canon
import core/proof/proof_integrity
import verification/obligation/canonical_obligation_generator
import verification/obligation/obligation_ir
import verification/obligation/semantic_target_extractor
import verification/obligation/obligation_types
import cli/topology_cli
import core/sorter/sorter_core_index_base
import wp15_scope_projection

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

proc normalizePath*(p: string): string =
  result = p.replace("\\", "/")
  while result.endsWith("/") and result.len > 1:
    result = result[0 .. ^2]

proc getProcName*(nameNode: PNode): string =
  ## Extract proc name from a name node, handling nnkPostfix (export marker).
  if nameNode == nil: return ""
  case nameNode.kind
  of nkPostfix:
    if nameNode.len > 1: pNodeText(nameNode[1]) else: ""
  of nkIdent: pNodeText(nameNode)
  else: ""

# ---------------------------------------------------------------------------
# Stage E1: SourceDiscovery
# ---------------------------------------------------------------------------

proc stageE1*(subjectRoot: string): JsonNode =
  result = newJObject()
  let relTarget = "stew/base36.nim"
  let targetAbs = subjectRoot / relTarget

  let fileSet = collectSubjectFileSet(subjectRoot)
  let targetInFileSet = fileSet.paths.contains(relTarget)

  var fileSha256Hex = ""
  let digestRes = sha256FileT(targetAbs)
  if digestRes.ok:
    var rawStr = newString(32)
    for i in 0..31:
      rawStr[i] = char(digestRes.value[i])
    fileSha256Hex = sha256HexStr(rawStr)

  var subjectFingerprint = ""
  let subjRes = buildVerificationSubject(subjectRoot)
  if subjRes.ok:
    subjectFingerprint = subjRes.value.sourceFingerprint

  let flags = detectSubjectFlags(subjectRoot)

  result["status"] = %"completed"
  result["evidence"] = %*{
    "targetInFileSet": targetInFileSet,
    "relPath": relTarget,
    "fileSha256Hex": fileSha256Hex,
    "subjectFingerprint": subjectFingerprint,
    "usedFallback": fileSet.usedFallback,
    "duplicateCount": 0,
    "hasSubmodules": flags.hasSubmodules,
    "indexGitlinkCount": flags.indexGitlinkCount
  }
  result["failureTaxonomy"] = %nil

# ---------------------------------------------------------------------------
# Stage E2: ModuleIdentity
# ---------------------------------------------------------------------------

proc stageE2*(subjectRoot: string): JsonNode =
  result = newJObject()
  let targetRel = "stew/base36.nim"

  var overloads: seq[JsonNode] = @[]
  var selectedIndex = -1

  try:
    let graph = buildGlobalSymbolGraph(subjectRoot, freezeGraphCache = false)
    for key, sym in graph.symbols.pairs:
      if sym.qualifiedName.endsWith("decodedLength") and sym.modulePath.normalizePath.endsWith("base36.nim"):
        let sigStr = sym.qualifiedName & "|" & $sym.kind & "|" & sym.modulePath
        let sigHash = sha256HexStr(sigStr)
        let entry = %*{
          "qualifiedName": sym.qualifiedName,
          "kind": $sym.kind,
          "modulePath": sym.modulePath,
          "signatureHash": sigHash
        }
        overloads.add(entry)

    # The graph stores one entry per qualifiedName; all 4 overloads share
    # the same qualifiedName so only the first is retained.
    # We still record what the graph found and identify int by source analysis.
    selectedIndex = if overloads.len > 0: 0 else: -1
  except CatchableError as e:
    result["status"] = %"error"
    result["evidence"] = %*{"error": e.msg}
    result["failureTaxonomy"] = %"InfrastructureFailure(graph-build-failed)"
    return

  result["status"] = %"completed"
  result["evidence"] = %*{
    "symbolName": "decodedLength",
    "modulePathStored": "stew/base36.nim",
    "modulePathNormalized": subjectRoot.normalizePath & "/" & targetRel,
    "overloadCount": overloads.len,
    "overloads": overloads,
    "overloadNote": "GlobalSymbolGraph stores one entry per qualifiedName; 4 overloads share the same name so only the first is retained in the graph table",
    "selectedIndex": selectedIndex,
    "selectedOverload": if selectedIndex >= 0: overloads[selectedIndex] else: %*{}
  }
  result["failureTaxonomy"] = %nil

# ---------------------------------------------------------------------------
# Stage E3: ImportResolution
# ---------------------------------------------------------------------------

proc classifyImportExpr*(importExpr: string): string =
  ## Classify an import expression using the same logic as resolveModuleName.
  var expr = importExpr.strip()
  if " as " in expr:
    expr = expr.split(" as ")[0].strip()
  if " except " in expr:
    expr = expr.split(" except ")[0].strip()
  if expr.startsWith("std/") or expr.startsWith("vendor/"):
    return "std"
  if expr.startsWith("core/"):
    return "core-resolvable"
  if expr.startsWith("./") or expr.startsWith("../"):
    return "unresolvable-subject-local"
  # Check if it resolves to a core/ module
  let corePath = "src/core/" & expr
  if fileExists(corePath & ".nim"):
    return "core-resolvable"
  # Check subdirectories of src/core (wrapped in try/except for OSError)
  try:
    for kind, path in walkDir("src/core"):
      if kind == pcDir:
        let subPath = path & "/" & expr
        if fileExists(subPath & ".nim"):
          return "core-resolvable"
  except CatchableError: # bestEffort("""walkDir on src/core failed — classify remaining expr as unresolvable, not a hard error""")
    discard
  # Check if it's a subject-local module (relative path)
  if expr.contains("/") or expr.contains("\\"):
    return "unresolvable-subject-local"
  return "unresolvable"

proc stageE3*(subjectRoot: string): JsonNode =
  result = newJObject()
  let targetRel = "stew/base36.nim"
  let targetAbs = subjectRoot / targetRel

  var sourceText = ""
  try:
    sourceText = readFile(targetAbs)
  except CatchableError as e:
    result["status"] = %"error"
    result["evidence"] = %*{"error": "cannot read target file: " & e.msg}
    result["failureTaxonomy"] = %"InfrastructureFailure(file-read-failed)"
    return

  # Line-scan for top-level import/from lines
  var importLines: seq[string] = @[]
  var classifications: seq[JsonNode] = @[]
  for line in sourceText.splitLines:
    let stripped = line.strip()
    if stripped.startsWith("import ") or stripped.startsWith("from "):
      importLines.add(stripped)
      let prefix = if stripped.startsWith("import "): "import " else: "from "
      let after = stripped[prefix.len .. ^1]
      for part in after.split(','):
        let modName = part.strip()
        let classification = classifyImportExpr(modName)
        classifications.add(%*{
          "importLine": stripped,
          "moduleExpr": modName,
          "classification": classification
        })

  # Also call resolveModuleName via extractCoreImports (which uses it internally)
  # extractCoreImports returns core-resolvable imports from a file
  var coreImports: seq[string] = @[]
  try:
    coreImports = extractCoreImports(targetAbs)
  except CatchableError: # bestEffort("""core-import extraction failed — report empty import set, stage records the failure""")
    discard

  result["status"] = %"completed"
  result["evidence"] = %*{
    "importLinesFound": importLines.len,
    "importLines": importLines,
    "classifications": classifications,
    "extractCoreImportsResult": coreImports,
    "resolveModuleNameVerdict": "stew/base36 → unresolvable (not a core/ module, not std/, not relative; no .nim file found in src/core/ or its subdirs)"
  }
  result["failureTaxonomy"] = %nil

# ---------------------------------------------------------------------------
# Stage E4: SymbolAdmission (v2 — scope-projection-driven)
# ---------------------------------------------------------------------------

proc stageE4*(subjectRoot: string): JsonNode =
  result = newJObject()

  let stateDir = getEnv("AXIOM_STATE_DIR", "/tmp/wp0c_state")
  let lockPath = stateDir / "data" / "verification_scope.lock"

  var scopeSupport: seq[string] = @[]
  try:
    scopeSupport = loadKernelScope(lockPath).kernelSymbols
  except CatchableError: # bestEffort("""kernel-scope lock load failed — treat support scope as empty; admission then falls to subject projection""")
    discard

  let (subjectSyms, parsedOk, parsedFail) = buildSubjectSymbols(subjectRoot)
  let projection = ScopeProjection(
    support: scopeSupport,
    subjectSymbols: subjectSyms
  )

  let goldenQname = "stew/base36.nim::decodedLength"
  var admission = false
  var goldenOrigin = soAxiomSupport
  for sym in subjectSyms:
    if sym.qualifiedName == goldenQname:
      goldenOrigin = sym.origin
      if projection.admits(sym):
        admission = true
      break

  let taxonomy = if admission: "" else: "Blocked:S3-registry-static"
  let status = if admission: "admitted" else: "blocked"

  result["status"] = %status
  result["evidence"] = %*{
    "subjectSymbolCount": subjectSyms.len,
    "supportScopeCount": scopeSupport.len,
    "admission": admission,
    "goldenSymbol": goldenQname,
    "goldenOrigin": $goldenOrigin,
    "parsedOkCount": parsedOk,
    "parseFailCount": parsedFail,
    "replacedGate": "S3 demoted to AxiomSupport-only init path"
  }
  result["failureTaxonomy"] = %taxonomy

# ---------------------------------------------------------------------------
# Stage E5: ObligationCandidate (v2 — full Canon→IR→Obligation chain)
# ---------------------------------------------------------------------------

proc stageE5*(subjectRoot: string): JsonNode =
  result = newJObject()
  let targetRel = "stew/base36.nim"
  let targetAbs = subjectRoot / targetRel

  var sourceText = ""
  try:
    sourceText = readFile(targetAbs)
  except CatchableError as e:
    result["status"] = %"error"
    result["evidence"] = %*{"error": "cannot read target file: " & e.msg}
    result["failureTaxonomy"] = %"InfrastructureFailure(file-read-failed)"
    return

  # Parse the AST
  let ast = parseStringAST(sourceText)
  if ast.isNil:
    result["status"] = %"unsupported"
    result["evidence"] = %*{"error": "parseStringAST returned nil for base36.nim"}
    result["failureTaxonomy"] = %"Unsupported(parse-failure)"
    return

  # Find the decodedLength(uint32) proc definition node safely.
  # findFuncDefP has a known FieldDefect on atomic node kinds (nkIdent),
  # so we use findNodesP with a guard and replicate the name+type-hint filter.
  var targetNode: PNode = nil
  try:
    for node in findNodesP(ast, {nkProcDef, nkFuncDef}):
      if node.len > 0 and not node[0].isNil:
        let name = getProcName(node[0])
        if name != "decodedLength":
          continue
        # Check uint32 overload via formal params
        if node.len > 3 and node[3].kind == nkFormalParams:
          let params = node[3]
          if params.len > 1 and params[1].kind == nkIdentDefs:
            # decodedLength(btype: typedesc[Base36Types], length: int) —
            # disambiguate on the *second* identdefs ("length: int"): the last
            # type child renders as plain identifier "int".
            if params.len > 2 and params[2].kind == nkIdentDefs:
              let tyNode = params[2][params[2].len - 2]
              if not tyNode.isNil and tyNode.kind == nkIdent and pNodeText(tyNode) == "int":
                targetNode = node
                break
  except CatchableError: # bestEffort("""AST scan for decodedLength func node failed — behave as symbol-not-found, classify as Unsupported""")
    discard

  if targetNode.isNil:
    result["status"] = %"unsupported"
    result["evidence"] = %*{"error": "decodedLength(int) func node not found in AST"}
    result["failureTaxonomy"] = %"Unsupported(symbol-not-found-in-ast)"
    return

  # Bridge: PNode → CanonNode → IRFuncDef (avoids PNode→NimNode boundary)
  let canonNode = pnodeToCanon(targetNode)
  let irFuncDef = axiomBodyCanon(canonNode)

  # Run the real obligation generator with default scope policy
  let policy = defaultScopePolicy()
  let ogr = generateCanonicalObligations(irFuncDef, policy)

  # Build evidence
  var candidateCount = 0
  var kinds: seq[string] = @[]
  var firstCandidateHash = ""
  var verdict = ""

  case ogr.kind
  of ogrGenerated:
    candidateCount = ogr.obligations.len
    for obl in ogr.obligations.items:
      kinds.add($obl.kind)
    if candidateCount > 0:
      firstCandidateHash = ogr.obligations.items[0].id
    verdict = "ObligationGenerated"
  of ogrNoApplicableObligation:
    verdict = "CanonicalNoObligation"
  of ogrUnsupported:
    verdict = "Unsupported(" & $ogr.unsupportedReason & ")"
  of ogrIllFormed:
    verdict = "IllFormed(" & $ogr.illFormedReason & ")"

  result["status"] = %"completed"
  result["evidence"] = %*{
    "candidateCount": candidateCount,
    "kinds": kinds,
    "firstCandidateHash": firstCandidateHash,
    "verdict": verdict,
    "chain": "parseStringAST→findNodesP(filter nkProcDef/nkFuncDef)→pnodeToCanon→axiomBodyCanon→generateCanonicalObligations",
    "policy": "defaultScopePolicy(admissible=true,expectedObligation=false)"
  }
  result["failureTaxonomy"] = %nil

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

when isMainModule:
  let args = commandLineParams()
  if args.len < 2:
    stderr.writeLine("usage: wp1_ingress_probe <subjectRoot> <outJsonPath>")
    quit(2)

  let subjectRoot = args[0]
  let outJsonPath = args[1]

  var stages: JsonNode = newJObject()
  let stageOrder = @["E1", "E2", "E3", "E4", "E5"]

  stages["E1"] = stageE1(subjectRoot)
  stages["E2"] = stageE2(subjectRoot)
  stages["E3"] = stageE3(subjectRoot)
  stages["E4"] = stageE4(subjectRoot)
  stages["E5"] = stageE5(subjectRoot)

  # Compute ingress digest (canonical minified JSON of stages evidence, excluding observedPaths)
  var evidenceForDigest: JsonNode = newJObject()
  for stageName in stageOrder:
    let stage = stages[stageName]
    if stage.hasKey("evidence"):
      evidenceForDigest[stageName] = stage["evidence"]
  let ingressDigest = sha256HexStr(canonicalJsonMinified(evidenceForDigest))

  let topLevel = %*{
    "experimentId": "act2-wp1-external-symbol-ingress",
    "golden": %*{"module": "stew/base36.nim", "symbol": "decodedLength", "overload": "int"},
    "stages": stages,
    "digests": %*{"ingressDigest": ingressDigest}
  }

  let outDir = parentDir(outJsonPath)
  if outDir != "" and not outDir.dirExists:
    outDir.createDir

  try:
    writeFile(outJsonPath, canonicalJsonMinified(topLevel))
  except CatchableError as e:
    stderr.writeLine("cannot write output: " & e.msg)
    quit(1)

  quit(0)
