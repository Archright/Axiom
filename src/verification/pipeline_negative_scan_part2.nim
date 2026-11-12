import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/json
import std/options
import std/os
import std/strutils
import std/tempfiles
import compiler/ast
import core/axiom_pragmas

import core/utils/io_utils
import core/json/json_utils
import core/utils/file_utils
import core/utils/text_utils
import core/domain_types
import core/results
import core/solver/solver_bridge
import core/pipeline_core_types
import core/logic/universal_translation_types
import core/utils/constants
import infrastructure/process_utils
# axiomIoBoundary
import core/parsers/pnode_nav

import verification/pipeline_negative_scan_part1 as part1

func hasVersionPayloadState*(sourceCode: string; ast: Option[PNode] = none(PNode)): bool =
  if ast.isSome:
    return hasTypeWithFieldsP(ast.get, ["version", "payload"])
  false

# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
func hasVersioningGuard*(sourceCode: string; ast: Option[PNode] = none(PNode)): bool =
  if ast.isSome:
    let astNode = ast.get
    for cond in collectAssertConditionsP(astNode):
      for ident in findNodesP(cond, {nkIdent}):
        if pNodeText(ident) == "version":
          for infix in findNodesP(cond, {nkInfix}):
            for op in findNodesP(infix, {nkIdent}):
              if pNodeText(op) in [">=", "==", ">", "<"]:
                return true
    for cond in collectIfConditionsP(astNode):
      for ident in findNodesP(cond, {nkIdent}):
        if pNodeText(ident) == "version":
          for infix in findNodesP(cond, {nkInfix}):
            for op in findNodesP(infix, {nkIdent}):
              if pNodeText(op) in ["<=", "<", ">=", ">", "=="]:
                return true
  false

# @axiom-hint: lean="tokens.length = 0 ∧ hasVersion = true ∧ hasPayload = true ∧ hasIdx = true ∧ hasLength = true ∧ hasPtr = true ∧ hasNotNil = true ∧ hasAmount = true ∧ hasBalance = true ∧ hasLe = true ∧ hasGe = true ∧ hasZeroLe = true ∧ false ∧ tokens.length = 0 → result = false ∧ (hasPayload ≥ 0) ∧ (hasIdx ≥ 0) ∧ (hasGe ≥ 0) ∧ (hasAmount ≥ 0) ∧ (hasBalance ≥ 0) ∧ (hasLength ≥ 0) ∧ (hasLe ≥ 0) ∧ (hasVersion ≥ 0) ∧ (tokens ≥ 0) ∧ (hasNotNil ≥ 0) ∧ (hasPtr ≥ 0) ∧ (hasZeroLe ≥ 0)" smt="(assert (and (= (str.len tokens) 0) (= hasVersion true) (= hasPayload true) (= hasIdx true) (= hasLength true) (= hasPtr true) (= hasNotNil true) (= hasAmount true) (= hasBalance true) (= hasLe true) (= hasGe true) (= hasZeroLe true) false (=> (= (str.len tokens) 0) (= result false)) (>= hasPayload 0) (>= hasIdx 0) (>= hasGe 0) (>= hasAmount 0) (>= hasBalance 0) (>= hasLength 0) (>= hasLe 0) (>= hasVersion 0) (>= tokens 0) (>= hasNotNil 0) (>= hasPtr 0) (>= hasZeroLe 0)))"
func coversPromotedInvariant*(kind: VulnerabilityKind; activeInvariant: string): bool =
  let tokens = tokenizeLowered(activeInvariant)
  if tokens.len == 0:
    return false
  case kind
  of vkGhostUpdate:
    var hasVersion = false
    var hasPayload = false
    for tok in tokens:
      if tok == "version": hasVersion = true
      if tok == "payload": hasPayload = true
    hasVersion and hasPayload
  of vkBufferOverflow:
    var hasIdx = false
    var hasLength = false
    for tok in tokens:
      if tok == "idx": hasIdx = true
      if tok == "length": hasLength = true
    hasIdx and hasLength
  of vkNullPointerDereference:
    var hasPtr = false
    var hasNotNil = false
    for tok in tokens:
      if tok == "ptr": hasPtr = true
    let invLower = activeInvariant.toLowerAscii()
    if invLower.find("!= nil") >= 0 or invLower.find("!= null") >= 0:
      hasNotNil = true
    hasPtr and hasNotNil
  of vkIntegerOverflowUnderflow:
    var hasAmount = false
    var hasBalance = false
    var hasLe = false
    var hasGe = false
    var hasZeroLe = false
    for tok in tokens:
      case tok
      of "amount": hasAmount = true
      of "balance": hasBalance = true
      of "<=": hasLe = true
      of ">=": hasGe = true
      of "zero_le": hasZeroLe = true
      else: discard
    (hasAmount and hasBalance and hasLe) or (hasAmount and hasGe) or hasZeroLe
  of vkDeadlockRaceCondition:
    "lock" in tokens

## Promotion Snapshot Path.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func promotionSnapshotPath*(req: UniversalPipelineRequest): string {.raises: [].} =
  joinPath(req.proofVaultDir, text_utils.sanitizeToken(req.functionName) & "_uap_promoted_invariant.json")

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
proc loadPromotionSnapshot(req: UniversalPipelineRequest): tuple[invariant: string; snapshotPath: string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let snapshotPath = try:
    promotionSnapshotPath(req)
  except CatchableError:
    return ("", "")
  if not fileExists(snapshotPath):
    return ("", "")
  try:
    let node = readJsonFile(snapshotPath).get()
    if node.kind != JObject:
      return ("", "")
    if node.hasKey("modulePath") and node["modulePath"].kind == JString and
        node["modulePath"].getStr() != req.modulePath:
      return ("", "")
    if node.hasKey("functionName") and node["functionName"].kind == JString and
        node["functionName"].getStr() != req.functionName:
      return ("", "")
    if node.hasKey("activeInvariant") and node["activeInvariant"].kind == JString:
      return (node["activeInvariant"].getStr(), normalizePath(snapshotPath))
    if node.hasKey("refinedInvariant") and node["refinedInvariant"].kind == JString:
      return (node["refinedInvariant"].getStr(), normalizePath(snapshotPath))
  except CatchableError:
    discard  # best-effort  # axiom:best-effort(ioboundary catch)
  ("", "")

## Load Promotion From Proof Vault.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="kind ≠ pcFile ∧ candidate.length = 0 ∧ fileName > newestFile ∧ newestInvariant.length = 0 ∧ newestFile = fileName ∧ newestInvariant = candidate ∧ snapshot ∧ (newestInvariant ≥ 0) ∧ (candidate ≥ 0) ∧ (newestFile ≥ 0)" smt="(assert (and (not (= kind pcFile)) (= (str.len candidate) 0) (> fileName newestFile) (= (str.len newestInvariant) 0) (= newestFile fileName) (= newestInvariant candidate) snapshot (>= newestInvariant 0) (>= candidate 0) (>= newestFile 0)))"
proc loadPromotionFromProofVault*(req: UniversalPipelineRequest): tuple[invariant: string; snapshotPath: string]  =
  let snapshot = loadPromotionSnapshot(req)
  if snapshot.invariant.len > 0:
    return snapshot
  if not dirExists(req.proofVaultDir):
    return ("", "")
  let expectedPrefix = text_utils.sanitizeToken(req.functionName) & "_universal_pipeline_"
  var newestFile = ""
  var newestInvariant = ""
  for kind, path in walkDir(req.proofVaultDir):
    if kind != pcFile:
      continue
    let fileName = extractFilename(path)
    if not fileName.startsWith(expectedPrefix) or not fileName.endsWith(".json"):
      continue
    try:
      let node = readJsonFile(path).get()
      if node.kind != JObject:
        continue
      if node.hasKey("modulePath") and node["modulePath"].kind == JString and
          node["modulePath"].getStr() != req.modulePath:
        continue
      if node.hasKey("functionName") and node["functionName"].kind == JString and
          node["functionName"].getStr() != req.functionName:
        continue
      var candidate = ""
      if node.hasKey("activeInvariant") and node["activeInvariant"].kind == JString:
        candidate = node["activeInvariant"].getStr()
      elif node.hasKey("refinedInvariant") and node["refinedInvariant"].kind == JString:
        candidate = node["refinedInvariant"].getStr()
      elif node.hasKey("evolution") and node["evolution"].kind == JObject and
          node["evolution"].hasKey("refinedInvariant") and
          node["evolution"]["refinedInvariant"].kind == JString:
        candidate = node["evolution"]["refinedInvariant"].getStr()
      if candidate.len == 0:
        continue
      if fileName > newestFile:
        newestFile = fileName
        newestInvariant = candidate
    except CatchableError:
      discard  # best-effort  # axiom:best-effort(ioboundary catch)
  if newestInvariant.len == 0:
    return ("", "")
  try:
    (newestInvariant, normalizePath(promotionSnapshotPath(req)))
  except CatchableError:
    return ("", "")

# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
func hasArithmeticRiskSignal*(translation: UniversalTranslation; sourceCode: string; ast: Option[PNode] = none(PNode)): bool =
  if ast.isSome:
    let astNode = ast.get
    for infix in findNodesP(astNode, {nkInfix}):
      for op in findNodesP(infix, {nkIdent}):
        let opText = pNodeText(op)
        if opText in ["+", "-", "*", "div", "mod"]:
          return true
  for entry in translation.ilEntries:
    let kind = entry.kind.toLowerAscii()
    if kind in ["arithmetic", "add", "sub", "mul", "div", "mod"]:
      return true
  false

# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
func hasConcurrencySignal*(translation: UniversalTranslation; sourceCode: string; ast: Option[PNode] = none(PNode)): bool =
  if ast.isSome:
    let astNode = ast.get
    for callNode in findNodesP(astNode, {nkCall}):
      for ident in findNodesP(callNode, {nkIdent}):
        let name = pNodeText(ident)
        if name in ["thread", "spawn", "atomic", "lock", "acquire", "release"]:
          return true
    for pragmaNode in findNodesP(astNode, {nkPragma}):
      for ident in findNodesP(pragmaNode, {nkIdent}):
        let name = pNodeText(ident)
        if name in ["gcsafe", "threadvar"]:
          return true
  return false

# @axiom-hint: lean="sourceCode.length > 0 ∧ ast.isSome = true ∧ hasStale ∧ result.length = 0 ∧ (hasStale ≥ 0)" smt="(assert (and (> (str.len sourceCode) 0) (= (option.isSome ast) true) hasStale (= (str.len result) 0) (>= hasStale 0)))"
func inferTraceBranchPoints(
  translation: UniversalTranslation;
  kind: string;
  sourceCode: string;
  bindings: JsonNode;
  ast: Option[PNode] = none(PNode)
): seq[string] =
  if kind == "ghost_update":
    var hasStale = false
    if ast.isSome:
      hasStale = hasIdentifierNamedP(ast.get, "stale")
    elif sourceCode.len > 0:
      let tokens = tokenizeLowered(sourceCode)
      hasStale = "stale" in tokens
    if hasStale:
      result.add("branch: stale path accepted")
    else:
      result.add("branch: stale write path accepted")
  for entry in translation.ilEntries:
    if result.len >= 4:
      break
    let tokens = tokenizeLowered(entry.il)
    if entry.kind == "if" or entry.kind == "branch":
      result.add("branch: " & entry.il)
    elif kind == "ghost_update" and ("version" in tokens or "payload" in tokens):
      result.add("write: " & entry.il)
    elif kind == "buffer_overflow" and "store" in tokens:
      result.add("memory: " & entry.il)
    elif kind == "integer_overflow_underflow" and ("add" in tokens or "sub" in tokens):
      result.add("arithmetic: " & entry.il)
  if kind == "ghost_update":
    let staleVersion = part1.bindingValue(bindings, "stale_version", "1")
    let nextVersion = part1.bindingValue(bindings, "version", "2")
    result.add("binding: stale_version=" & staleVersion & ", next_version=" & nextVersion)
  elif kind == "buffer_overflow":
    result.add("binding: idx=" & part1.bindingValue(bindings, "idx", "-1"))
  elif kind == "null_pointer_dereference":
    result.add("binding: ptr=" & part1.bindingValue(bindings, "ptr", "nil"))
  elif kind == "integer_overflow_underflow":
    result.add("binding: amount=" & part1.bindingValue(bindings, "amount", "2147483647"))
  elif kind == "deadlock_race_condition":
    result.add("binding: t1=" & part1.bindingValue(bindings, "t1", "enter"))
  if result.len == 0:
    result.add("path: no explicit branch extracted")

# @axiom-hint: lean="kind.length ≥ 0 ∧ sourceCode.length ≥ 0" smt="(assert (and (>= (str.len kind) 0) (>= (str.len sourceCode) 0)))"
func buildTraceJson(
  translation: UniversalTranslation;
  kind: string;
  sourceCode: string;
  bindings: JsonNode
): JsonNode =
  try:
    let branchPoints = inferTraceBranchPoints(translation, kind, sourceCode, bindings)
    %*{
      "branchPoints": branchPoints,
      "pathSignature": branchPoints.join(" -> ")
    }
  except CatchableError:
    %*{"branchPoints": [], "pathSignature": ""}

# @axiom-hint: lean="kind.length ≥ 0 ∧ status.length ≥ 0 ∧ violatedProperty.length ≥ 0 ∧ sourceCode.length ≥ 0" smt="(assert (and (>= (str.len kind) 0) (>= (str.len status) 0) (>= (str.len violatedProperty) 0) (>= (str.len sourceCode) 0)))"
func buildCounterExampleJson(
  translation: UniversalTranslation;
  kind: string;
  status: string;
  violatedProperty: string;
  sourceCode: string;
  bindings: JsonNode
): string =
  try:
    $(%*{
      "solver": DefaultSolverCommand,
      "status": status,
      "vulnerabilityKind": kind,
      "violatedProperty": violatedProperty,
      "bindings": bindings,
      "trace": buildTraceJson(translation, kind, sourceCode, bindings)
    })
  except CatchableError:
    """{"solver":"z3","status":"error","vulnerabilityKind":"unknown","violatedProperty":"unknown","bindings":{},"trace":{"branchPoints":[],"pathSignature":""}}"""

## Build Counter Example Input.
# @axiom-hint: lean="exitCode ≠ 0 ∧ external_io_isolated" smt="(assert (and (not (= exitCode 0)) external_io_isolated))"
proc buildCounterExampleInput*(
  translation: UniversalTranslation;
  kind: string;
  violatedProperty: string;
  fallbackJson: string
): Option[string] =
  # axiom:theater-fix(DEBT#376) — return none() on Z3 failure instead of fabricating fake counterexamples
  let smtPath = genTempPath("axiom_uap_", ".smt2")
  try:
    ## intentional-discard: temp SMT file for solver invocation; cleaned up by OS
    discard writeFileOpt(smtPath, translation.smt2)
    let (solverStdout, exitCode) = execCmdWithTimeout("z3 -smt2 \"" & smtPath & "\"", timeoutMs = 30_000)
    if exitCode != 0:
      # axiom:theater-fix(DEBT#376) — Z3 returned non-zero; do not synthesize fake counterexample
      return none[string]()
    let parsed = parseZ3StdoutAsResult(solverStdout, translation.smt2, violatedProperty)
    if parsed.isErr():
      let failure = parsed.error
      if failure.code == axiomErrVacuousContradiction:
        return some(buildCounterExampleJson(
          translation,
          kind,
          "vacuous",
          violatedProperty,
          "",
          part1.extractBindingsFromFallback(fallbackJson)
        ))
      if failure.code == axiomErrSolverSatCounterExample and failure.counterExample.isSome():
        let satBindings =
          if failure.counterExample.get().bindings.len > 0:
            part1.buildBindingJson(failure.counterExample.get().bindings)
          else:
            part1.extractBindingsFromFallback(fallbackJson)
        return some(buildCounterExampleJson(
          translation,
          kind,
          "sat",
          failure.counterExample.get().violatedProperty,
          "",
          satBindings
        ))
      # axiom:theater-fix(DEBT#376) — parse error without solvable counterexample; no fake fallback
      return none[string]()
    let fallbackBindings = part1.extractBindingsFromFallback(fallbackJson)
    return some(buildCounterExampleJson(translation, kind, "unsat", violatedProperty, "", fallbackBindings))
  except CatchableError:
    # axiom:theater-fix(DEBT#376) — Z3 unavailable/crashed; do not synthesize fake counterexample
    return none[string]()
  finally:
    try:
      if fileExists(smtPath):
        discard removeFileOpt(smtPath)
    except CatchableError:
      discard  # best-effort  # axiom:best-effort(ioboundary catch)

# @axiom-hint: lean="(isSat ≥ 0) ∧ (isVacuous ≥ 0)" smt="(assert (and (>= isSat 0) (>= isVacuous 0)))"
proc buildAnnotatedHit*(
  kind: VulnerabilityKind;
  payload: VulnerabilityHit;
  violatedProperty: string;
  counterExampleInput: string;
  remediation: string
): AnnotatedHit =
  var isSat = false
  var isVacuous = false
  try:
    let json = json.parseJson(counterExampleInput)
    if json.hasKey("status"):
      let status = json["status"].getStr()
      isSat = status == "sat"
      isVacuous = status == "vacuous"
  except CatchableError:
    discard  # best-effort  # axiom:best-effort(ioboundary catch)
  AnnotatedHit(
    hit: payload,
    sat: isSat,
    violatedProperty: violatedProperty,
    counterExampleInput: counterExampleInput,
    remediation: remediation
  )
{.pop.}
