import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import ../../core/trusted/axiom_pragmas
import core/gateway/gateway_json
import core/json/std_redirect
import core/logic/smt_logic
import core/logic/universal_translation_types
import core/translator/universal_mapper_part1
import core/types/domain_types
import core/types/results
import std/json
import std/sequtils
import std/strutils
func mapLoopNode*(node: JsonNode; idx: int): AstMapEntry {.raises: [], axiom: ["(assert (>= depth 0))", "depth >= 0"].} =
  let guard = sanitizeSymbol(jsonString(node, "condition", "loop_guard"))
  AstMapEntry(
    nodeId: "n" & $idx,
    kind: "loop",
    il: "loop while " & guard,
    smt: "(assert (>= " & guard & " 0))"
  )
func mapMemoryNode*(node: JsonNode; idx: int; writeMode: bool; logic: SmtLogic = slQfLia): AstMapEntry {.raises: [], axiom: ["(assert (and writeMode (or (= writeMode true) (= writeMode false))))", "writeMode ∧ writeMode = true ∨ writeMode = false"].} =
  let base = sanitizeSymbol(jsonString(node, "base", "mem"))
  let index = sanitizeSymbol(jsonString(node, "index", "idx"))
  let lenSymbol = semanticLengthSymbol(jsonString(node, "length", base & "_len"))
  let width = parseIndexWidth(node)
  let il = (if writeMode: "store " else: "load ") & base & "[" & index & "]"
  let smtExpr =
    if logic in {slQfLia, slHorn}:
      "(assert (and " &
      "(>= " & index & " 0) " &
      "(< " & index & " " & lenSymbol & ") " &
      "(>= (+ " & base & " " & index & ") " & base & ") " &
      "(< (+ " & base & " " & index & ") (+ " & base & " " & lenSymbol & "))))"
    else:
      "(assert (and " &
      "(bvuge " & index & " (_ bv0 " & $width & ")) " &
      "(bvult " & index & " " & lenSymbol & ") " &
      "(bvuge (bvadd " & base & " " & index & ") " & base & ") " &
      "(bvult (bvadd " & base & " " & index & ") (bvadd " & base & " " & lenSymbol & "))))"
  AstMapEntry(
    nodeId: "n" & $idx,
    kind: (if writeMode: "memory_write" else: "memory_read"),
    il: il,
    smt: smtExpr
  )
func mapGenericNode*(node: JsonNode; idx: int): AstMapEntry {.raises: [], axiom: ["(assert (and (and (>= idx -9223372036854775808) (<= idx 9223372036854775807))))", "idx ≥ -9223372036854775808 ∧ idx ≤ 9223372036854775807"].} =
  let rawKind = jsonString(node, "kind", "unknown")
  AstMapEntry(
    nodeId: "n" & $idx,
    kind: rawKind,
    il: "noop " & rawKind,
    smt: ""
  )

## Map Ast Json To Universal Translation.
func mapAstJsonToUniversalTranslation*(
  language: string;
  astJson: string;
  logic: SmtLogic = slQfLia
): Result[UniversalTranslation, AxiomError] {.raises: [], axiom: ["(assert (and (>= (str.len language) 0) (>= (str.len astJson) 0) (> (str.len guardInvariant) 0) (> (str.len loopControl) 0) (= (str.len rankVariables) 0) (and (= (str.len rankVariables) 0) (> (str.len stateSpace) 0)) (>= entry 0) (>= mapped 0)))", "language.length ≥ 0 ∧ astJson.length ≥ 0 ∧ guardInvariant.length > 0 ∧ loopControl.length > 0 ∧ rankVariables.length = 0 ∧ rankVariables.length = 0 ∧ stateSpace.length > 0 ∧ (entry ≥ 0) ∧ (mapped ≥ 0)"].} =
  let parsed = ??jsonParseSafe(astJson)
  let root = parsed
  if root.kind != JObject:
    return err(axiomErrJsonWrongType)
  let functionName = sanitizeSymbol(jsonString(root, "functionName", "anonymous"))
  let nodes = root{"nodes"}
  if nodes.isNil or nodes.kind != JArray:
    return err(axiomErrJsonMissingField)

  var mapped: seq[AstMapEntry] = @[]
  var controlFlowCount = 0
  var memoryAccessCount = 0
  var stateSpace: seq[string] = @[]
  var stateInvariants: seq[string] = @[]
  var transitionRelation: seq[string] = @[]
  var transitionInvariants: seq[string] = @[]
  var operationalSemantics: seq[string] = @[]
  var environmentInputs: seq[string] = @[]
  var envInputConstructors: seq[string] = @[]
  var stepFunctionCases: seq[string] = @[]
  var loopControlVariables: seq[string] = @[]
  var rankVariables: seq[string] = @[]

  for idx, item in nodes.elems:
    if item.kind != JObject:
      continue
    let kind = jsonString(item, "kind", "").toLowerAscii()
    var entry: AstMapEntry
    case kind
    of "assign":
      entry = mapAssignNode(item, idx, logic)
      let target = sanitizeSymbol(jsonString(item, "target", "x"))
      let left = sanitizeSymbol(jsonString(item, "left", target))
      let rightRaw = jsonString(item, "right", "0")
      stateSpace.addUniqueSymbol(target)
      stateSpace.addUniqueSymbol(left)
      stateSpace.addUniqueSymbol(rightRaw)
      stateSpace.addUniqueSymbol(target & "_next")
      let relation = prettyAssignRelation(target, left, jsonString(item, "op", "assign"), rightRaw)
      transitionRelation.addUniqueLine(relation)
      stateInvariants.addStateInvariantFromRelation(relation)
      transitionInvariants.addTransitionInvariant(relation)
      operationalSemantics.addUniqueLine("internal " & relation)
    of "if", "branch":
      inc controlFlowCount
      entry = mapIfNode(item, idx, logic)
      let condition = sanitizeSymbol(jsonString(item, "condition", "cond"))
      stateSpace.addUniqueSymbol(condition)
      transitionRelation.addUniqueLine("guard " & condition)
      operationalSemantics.addUniqueLine("branch " & condition)
      let guardInvariant = inferGuardStateInvariant(condition)
      if guardInvariant.len > 0:
        stateInvariants.addUniqueLine(guardInvariant)
    of "loop", "while", "for":
      inc controlFlowCount
      entry = mapLoopNode(item, idx)
      let guard = sanitizeSymbol(jsonString(item, "condition", "loop_guard"))
      stateSpace.addUniqueSymbol(guard)
      transitionRelation.addUniqueLine("loop_guard " & guard)
      operationalSemantics.addUniqueLine("loop " & guard)
      let guardInvariant = inferGuardStateInvariant(guard)
      if guardInvariant.len > 0:
        stateInvariants.addUniqueLine(guardInvariant)
      let loopControl = inferLoopControlVariable(guard)
      if loopControl.len > 0:
        loopControlVariables.addUniqueLine(loopControl)
        rankVariables.addUniqueLine(loopControl)
    of "memory_read", "load", "read":
      inc memoryAccessCount
      entry = mapMemoryNode(item, idx, false, logic)
      let base = sanitizeSymbol(jsonString(item, "base", "mem"))
      let index = sanitizeSymbol(jsonString(item, "index", "idx"))
      let lenSymbol = semanticLengthSymbol(jsonString(item, "length", base & "_len"))
      stateSpace.addUniqueSymbol(base)
      stateSpace.addUniqueSymbol(index)
      stateSpace.addUniqueSymbol(lenSymbol)
      transitionRelation.addUniqueLine("load " & base & "[" & index & "]")
      let memoryInvariant = buildMemoryStateInvariant(base, index, lenSymbol)
      stateInvariants.addUniqueLine(memoryInvariant)
      transitionInvariants.addUniqueLine(memoryInvariant)
      operationalSemantics.addUniqueLine("memory load " & base & "[" & index & "]")
    of "memory_write", "store", "write":
      inc memoryAccessCount
      entry = mapMemoryNode(item, idx, true, logic)
      let base = sanitizeSymbol(jsonString(item, "base", "mem"))
      let index = sanitizeSymbol(jsonString(item, "index", "idx"))
      let lenSymbol = semanticLengthSymbol(jsonString(item, "length", base & "_len"))
      stateSpace.addUniqueSymbol(base)
      stateSpace.addUniqueSymbol(index)
      stateSpace.addUniqueSymbol(lenSymbol)
      transitionRelation.addUniqueLine("store " & base & "[" & index & "]")
      let memoryInvariant = buildMemoryStateInvariant(base, index, lenSymbol)
      stateInvariants.addUniqueLine(memoryInvariant)
      transitionInvariants.addUniqueLine(memoryInvariant)
      operationalSemantics.addUniqueLine("memory store " & base & "[" & index & "]")
    of "network_read", "network_write", "io_read", "stdin_read", "external_input", "nondet":
      entry = mapExternalInputNode(item, idx, kind)
      let target = sanitizeSymbol(jsonString(item, "target", "env_value"))
      let source = envSourceName(item, kind)
      stateSpace.addUniqueSymbol(target)
      transitionRelation.addUniqueLine("env " & source & " -> " & target)
      environmentInputs.addUniqueLine(source)
      envInputConstructors.addUniqueLine(buildEnvConstructorName(source) & " (value : Int)")
      operationalSemantics.addUniqueLine("env " & source & " -> " & target)
      stepFunctionCases.addUniqueLine(buildEnvStepCase(stateSpace, source, target, rankVariables))
    else:
      entry = mapGenericNode(item, idx)
      operationalSemantics.addUniqueLine("generic " & entry.kind)
    mapped.add(entry)

  if rankVariables.len == 0:
    for candidate in ["idx", "index", "i", "j", "k", "count", "counter", "n"]:
      if stateSpace.contains(candidate):
        rankVariables.add(candidate)
        break
  if rankVariables.len == 0 and stateSpace.len > 0:
    rankVariables.add(stateSpace[0])

  stepFunctionCases.insert(buildInternalStepCase(stateSpace, transitionRelation, rankVariables), 0)

  var smtLines: seq[string] = @[emitLogicHeader(logic)]
  for symbol in stateSpace.deduplicate():
    if symbol.len > 0 and symbol[0] notin {'0'..'9'}:
      smtLines.add(emitVariableDeclaration(symbol, logic))
  for entry in mapped:
    if entry.smt.len > 0:
      smtLines.add(entry.smt)
  smtLines.add("(check-sat)")
  smtLines.add("(get-model)")

  ok(UniversalTranslation(
    language: normalizeLanguage(language),
    functionName: functionName,
    logic: logic,
    ilEntries: mapped,
    smt2: smtLines.join("\n"),
    controlFlowCount: controlFlowCount,
    memoryAccessCount: memoryAccessCount,
    stateSpace: stateSpace,
    stateInvariants: stateInvariants,
    transitionRelation: transitionRelation,
    transitionInvariants: transitionInvariants,
    operationalSemantics: operationalSemantics,
    environmentInputs: environmentInputs,
    envInputConstructors: envInputConstructors,
    stepFunctionCases: stepFunctionCases,
    loopControlVariables: loopControlVariables,
    rankVariables: rankVariables
  ))

## Universal Translation To Json.
func universalTranslationToJson*(translation: UniversalTranslation): JsonNode {.raises: [], axiom: ["(assert (and (>= (str.len translation_language) 0) (>= (str.len translation_functionName) 0) (>= (seq.len translation_ilEntries) 0) (>= (str.len translation_smt2) 0) (and (>= translation_controlFlowCount -9223372036854775808) (<= translation_controlFlowCount 9223372036854775807)) (and (>= translation_memoryAccessCount -9223372036854775808) (<= translation_memoryAccessCount 9223372036854775807)) (>= (seq.len translation_stateSpace) 0) (>= (seq.len translation_stateInvariants) 0) (>= (seq.len translation_transitionRelation) 0) (>= (seq.len translation_transitionInvariants) 0) (>= (seq.len translation_operationalSemantics) 0) (>= (seq.len translation_environmentInputs) 0) (>= (seq.len translation_envInputConstructors) 0) (>= (seq.len translation_stepFunctionCases) 0) (>= (seq.len translation_loopControlVariables) 0) (>= (seq.len translation_rankVariables) 0) (>= node 0) (>= result 0)))", "translation_language.length ≥ 0 ∧ translation_functionName.length ≥ 0 ∧ translation_ilEntries.size ≥ 0 ∧ translation_smt2.length ≥ 0 ∧ translation_controlFlowCount ≥ -9223372036854775808 ∧ translation_controlFlowCount ≤ 9223372036854775807 ∧ translation_memoryAccessCount ≥ -9223372036854775808 ∧ translation_memoryAccessCount ≤ 9223372036854775807 ∧ translation_stateSpace.size ≥ 0 ∧ translation_stateInvariants.size ≥ 0 ∧ translation_transitionRelation.size ≥ 0 ∧ translation_transitionInvariants.size ≥ 0 ∧ translation_operationalSemantics.size ≥ 0 ∧ translation_environmentInputs.size ≥ 0 ∧ translation_envInputConstructors.size ≥ 0 ∧ translation_stepFunctionCases.size ≥ 0 ∧ translation_loopControlVariables.size ≥ 0 ∧ translation_rankVariables.size ≥ 0 ∧ (node ≥ 0) ∧ (result ≥ 0)"].} =
  result = newJObject()
  result["language"] = newJString(translation.language)
  result["functionName"] = newJString(translation.functionName)
  result["controlFlowCount"] = newJInt(translation.controlFlowCount)
  result["memoryAccessCount"] = newJInt(translation.memoryAccessCount)
  result["smt2"] = newJString(translation.smt2)
  let entries = newJArray()
  for entry in translation.ilEntries:
    let node = newJObject()
    node["nodeId"] = newJString(entry.nodeId)
    node["kind"] = newJString(entry.kind)
    node["il"] = newJString(entry.il)
    node["smt"] = newJString(entry.smt)
    entries.add(node)
  result["ilEntries"] = entries
  let stateSpace = newJArray()
  for symbol in translation.stateSpace:
    stateSpace.add(newJString(symbol))
  result["stateSpace"] = stateSpace
  let stateInvariants = newJArray()
  for invariant in translation.stateInvariants:
    stateInvariants.add(newJString(invariant))
  result["stateInvariants"] = stateInvariants
  let transitionRelation = newJArray()
  for relation in translation.transitionRelation:
    transitionRelation.add(newJString(relation))
  result["transitionRelation"] = transitionRelation
  let transitionInvariants = newJArray()
  for invariant in translation.transitionInvariants:
    transitionInvariants.add(newJString(invariant))
  result["transitionInvariants"] = transitionInvariants
  let operationalSemantics = newJArray()
  for item in translation.operationalSemantics:
    operationalSemantics.add(newJString(item))
  result["operationalSemantics"] = operationalSemantics
  let environmentInputs = newJArray()
  for item in translation.environmentInputs:
    environmentInputs.add(newJString(item))
  result["environmentInputs"] = environmentInputs
  let envInputConstructors = newJArray()
  for item in translation.envInputConstructors:
    envInputConstructors.add(newJString(item))
  result["envInputConstructors"] = envInputConstructors
  let stepFunctionCases = newJArray()
  for item in translation.stepFunctionCases:
    stepFunctionCases.add(newJString(item))
  result["stepFunctionCases"] = stepFunctionCases
  let loopControlVariables = newJArray()
  for item in translation.loopControlVariables:
    loopControlVariables.add(newJString(item))
  result["loopControlVariables"] = loopControlVariables
  let rankVariables = newJArray()
  for item in translation.rankVariables:
    rankVariables.add(newJString(item))
  result["rankVariables"] = rankVariables
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
