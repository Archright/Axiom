import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
## Pipeline Trace Artifacts
## Builds trace reports and PoC snippets from counter-example data.

import std/options
import std/strutils

import core/json/json_scan_skip
import core/json/json_utils
import core/types/pipeline_core_types
import core/json/std_redirect

## Parse Counter Example Input Node.
# @axiom-hint: lean="counterExampleInput.length >= 0" smt="(assert (and (>= (str.len counterExampleInput) 0)))"
func parseCounterExampleInputNode*(counterExampleInput: string): JsonNode {.raises: [].} =
  let parsedOpt = parseJsonOpt(counterExampleInput)
  if parsedOpt.isSome and parsedOpt.get().kind == JObject:
    return parsedOpt.get()
  newJObject()

## Trace Node From Counter Example.
# @axiom-hint: lean="traceNode" smt="(assert (and traceNode))"
func traceNodeFromCounterExample*(counterExample: JsonNode): JsonNode {.raises: [], noSideEffect.} =
  let traceNode = counterExample{"trace"}
  if counterExample.kind == JObject and not traceNode.isNil and traceNode.kind == JObject:
    return traceNode
  newJObject()

# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
# @axiom-hint: lean="keyIndex < 0 and colonIndex < 0" smt="(assert (and (< keyIndex 0) (< colonIndex 0)))"
func findJsonFieldValueStart(input: string; fieldName: string): int {.raises: [], noSideEffect.} =
  let key = "\"" & fieldName & "\""
  let keyIndex = input.find(key)
  if keyIndex < 0:
    return -1
  let colonIndex = input.find(':', keyIndex + key.len)
  if colonIndex < 0:
    return -1
  json_scan_skip.skipJsonWhitespace(input, colonIndex + 1)

# @axiom-hint: lean="startIndex >= -1" smt="(assert (and (>= startIndex -1)))"
func readJsonStringLiteral(input: string; startIndex: int): string {.raises: [], noSideEffect.} =
  if startIndex < 0 or startIndex >= input.len or input[startIndex] != '"':
    return ""
  var index = startIndex + 1
  while index < input.len:
    let current = input[index]
    if current == '\\' and index + 1 < input.len:
      result.add(input[index + 1])
      inc index, 2
      continue
    if current == '"':
      return result
    result.add(current)
    inc index
  ""

# @axiom-hint: lean="startIndex >= -1" smt="(assert (and (>= startIndex -1)))"
func readJsonStringArray(input: string; startIndex: int): seq[string] {.raises: [], noSideEffect.} =
  if startIndex < 0 or startIndex >= input.len or input[startIndex] != '[':
    return @[]
  var index = startIndex + 1
  while index < input.len:
    let current = input[index]
    if current == ']':
      return result
    if current == '"':
      result.add(readJsonStringLiteral(input, index))
      inc index
      while index < input.len:
        if input[index] == '\\' and index + 1 < input.len:
          inc index, 2
          continue
        if input[index] == '"':
          inc index
          break
        inc index
      continue
    inc index

## Trace Signature From Counter Example.
# @axiom-hint: lean="counterExampleInput.length >= 0" smt="(assert (and (>= (str.len counterExampleInput) 0)))"
func traceSignatureFromCounterExample*(counterExampleInput: string): string {.raises: [], noSideEffect.} =
  let valueStart = findJsonFieldValueStart(counterExampleInput, "pathSignature")
  if valueStart >= 0:
    return readJsonStringLiteral(counterExampleInput, valueStart)
  ""

## Binding From Counter Example.
# @axiom-hint: lean="counterExampleInput.length >= 0" smt="(assert (and (>= (str.len counterExampleInput) 0)))"
func bindingsFromCounterExample*(counterExampleInput: string): JsonNode {.raises: [].} =
  let node = parseCounterExampleInputNode(counterExampleInput)
  if node.kind == JObject:
    let bindingsNode = node{"bindings"}
    if bindingsNode.kind == JObject:
      return bindingsNode
  newJObject()

## Build Trace Report.
func buildTraceReport*(
  hit: Option[AnnotatedHit]
): TraceReport {.raises: [], noSideEffect.} =
  if hit.isNone():
    return TraceReport()
  let selected = hit.get()
  result.vulnerabilityKind = $selected.hit.kind
  result.violatedProperty = selected.violatedProperty
  result.branchPoints = readJsonStringArray(
    selected.counterExampleInput,
    findJsonFieldValueStart(selected.counterExampleInput, "branchPoints")
  )
  result.pathSignature = traceSignatureFromCounterExample(selected.counterExampleInput)
  result.counterExampleSummary =
    if result.pathSignature.len > 0:
      result.pathSignature
    else:
      selected.counterExampleInput

# @axiom-hint: lean="functionName.length >= 0" smt="(assert (and (>= (str.len functionName) 0)))"
# @axiom-hint: lean="params.length >= 0" smt="(assert (and (>= (str.len params) 0)))"
func buildGenericNimPoc(functionName: string; hit: AnnotatedHit; bindings: JsonNode): string =
  let traceSignature = traceSignatureFromCounterExample(hit.counterExampleInput)
  var params = ""
  var args = ""
  if bindings.kind == JObject:
    for key, value in bindings:
      if params.len > 0:
        params.add(", ")
        args.add(", ")
      params.add(key & ": " & $value.kind)
      let valueStr =
        case value.kind
        of JString: value.getStr()
        of JInt: $value.getInt()
        of JFloat: $value.getFloat()
        of JBool: $value.getBool()
        else: $value
      args.add(key & " = " & valueStr)
  var body = ""
  case hit.hit.kind
  of vkGhostUpdate:
    body = "doAssert committed.version >= newest.version"
  of vkBufferOverflow:
    body = "assert idx >= 0 and idx < length"
  of vkNullPointerDereference:
    body = "assert ptr != nil"
  of vkIntegerOverflowUnderflow:
    body = "assert value >= MIN and value <= MAX"
  of vkDeadlockRaceCondition:
    body = "assert lockHeld == true"
  "proc " & functionName & "*(" & params & "): void =\n" &
    "  " & body & "\n" &
    "\n" &
    "# Counter-example: " & traceSignature & "\n" &
    "# Bindings: {" & args & "}"

func buildGhostUpdateNimPoc(bindings: JsonNode): string =
  result = "proc reproduceGhostUpdate*(): RecordState =\n"
  result.add("  let newest = RecordState(version: 2, payload: 200)\n")
  result.add("  let stale = RecordState(version: 1, payload: 100)\n")
  result.add("  var committed = newest\n")
  result.add("  committed.version = stale.version\n")
  result.add("  committed.payload = stale.payload\n")
  result.add("  doAssert committed.version >= newest.version\n")
  result.add("  return committed\n")

# @axiom-hint: lean="language.length >= 0 and functionName.length >= 0" smt="(assert (and (>= (str.len language) 0) (>= (str.len functionName) 0)))"
func buildPocSnippet*(
  language: string;
  functionName: string;
  hit: AnnotatedHit
): string =
  let bindings = bindingsFromCounterExample(hit.counterExampleInput)
  let normalized = language.toLowerAscii()
  if hit.hit.kind == vkGhostUpdate and normalized == "nim":
    return buildGhostUpdateNimPoc(bindings)
  if normalized == "nim":
    return buildGenericNimPoc(functionName, hit, bindings)
  if hit.hit.kind == vkGhostUpdate:
    return "typedef struct { int version; int payload; } RecordState;\n\n" &
      "RecordState commitRecord(RecordState state, int delta) {\n" &
      "  RecordState result = state;\n" &
      "  if (delta > 0) {\n" &
      "    result.version = state.version + delta;\n" &
      "  }\n" &
      "  return result;\n" &
      "}\n\n" &
      "int main(void) {\n" &
      "  RecordState newest = {2, 200};\n" &
      "  RecordState stale = {1, 100};\n" &
      "  RecordState committed = commitRecord(newest, 1);\n" &
      "  committed.version = stale.version;\n" &
      "  committed.payload = stale.payload;\n" &
      "  return committed.version >= newest.version ? 0 : 1;\n" &
      "}"
  "int main(void) {  return 0; }"

{.pop.}
