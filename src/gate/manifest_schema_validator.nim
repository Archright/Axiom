import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## manifest_schema_validator.nim — JSON-Schema-subset validator for gate manifests.
## Pure, effect-free module. All procs are `func` with `{.raises: [].}`.
## No I/O, no regex, no stdlib beyond json/sets/strutils.

import std/[json, sets, strutils]

const knownFieldNames* = [
  "id", "name", "layer", "entry", "stages",
  "filesPattern", "passFilenames", "priority",
  "weight", "severity", "always_run", "tier",
  "hermeticity", "after", "depsDirs", "argsTemplate",
  "envVars", "envDependencies", "execution_mode",
  "category", "description", "checks", "timeout_seconds",
]

const validLayers = ["meta", "functional"]
const validWeights = ["light", "medium", "heavy"]
const validSeverities = ["warn", "error"]
const validTiers = [1, 2]
const validHermeticities = ["hermetic", "transient"]
const validStages = ["pre-commit", "pre-push", "manual", "ci"]
const validCategories = ["theorem", "rule", "policy"]
const validExecutionModes = ["aot", "interpreted"]

template enumErr(node: JsonNode, field, valid: string): string =
  "Gate '" & getId(node) & "': field '" & field & "' has invalid value '" &
  node{field}.getStr() & "'; valid: " & valid

template missingErr(node: JsonNode, field: string): string =
  "Gate '" & getId(node) & "': missing required field '" & field & "'"

template typeErr(node: JsonNode, field, expected: string): string =
  "Gate '" & getId(node) & "': field '" & field & "' must be " & expected

func getId(node: JsonNode): string =
  try:
    if node{"id"} != nil: node["id"].getStr() else: "<unknown>"
  except CatchableError as e:
    "<unknown (error: " & e.msg & ")>"

func validateRequiredField(node: JsonNode; field: string): seq[string] =
  if node{field} == nil or node{field}.kind == JNull:
    result.add missingErr(node, field)

func validateEnumField(node: JsonNode; field: string; validValues: openArray[string]): seq[string] =
  try:
    let val = node{field}
    if val != nil and val.kind == JString:
      let s = val.getStr()
      var found = false
      for v in validValues:
        if s == v:
          found = true
          break
      if not found:
        result.add enumErr(node, field, validValues.join(", "))
  except CatchableError as e:
    result.add("internal error validating '" & field & "': " & e.msg)

func validateEnumField(node: JsonNode; field: string; validValues: openArray[int]): seq[string] =
  try:
    let val = node{field}
    if val != nil and val.kind == JInt:
      let n = val.getInt()
      var found = false
      for v in validValues:
        if n == v:
          found = true
          break
      if not found:
        var validStrs: seq[string]
        for v in validValues:
          validStrs.add($v)
        result.add "Gate '" & getId(node) & "': field '" & field &
          "' has invalid value " & $n & "; valid: " & validStrs.join(", ")
  except CatchableError as e:
    result.add("internal error validating '" & field & "': " & e.msg)

func validateType(node: JsonNode; field: string; expectedKind: JsonNodeKind): seq[string] =
  try:
    let val = node{field}
    if val != nil and val.kind != JNull and val.kind != expectedKind:
      result.add typeErr(node, field, $expectedKind)
  except CatchableError as e:
    result.add("internal error in validateType for '" & field & "': " & e.msg)

func validateArrayStrings(node: JsonNode; field: string): seq[string] =
  try:
    let arr = node{field}
    if arr != nil and arr.kind == JArray:
      for idx in 0 ..< arr.len:
        let item = arr[idx]
        if item.kind != JString:
          result.add "Gate '" & getId(node) & "': field '" & field &
            "' item " & $idx & " must be a string"
  except CatchableError as e:
    result.add("internal error validating array field '" & field & "': " & e.msg)

func validateStagesArray(node: JsonNode): seq[string] =
  try:
    let arr = node{"stages"}
    if arr != nil and arr.kind == JArray:
      for item in arr:
        if item.kind == JString:
          let s = item.getStr()
          var found = false
          for v in validStages:
            if s == v:
              found = true
              break
          if not found:
            result.add "Gate '" & getId(node) & "': stages item '" & s &
              "' invalid; valid: " & validStages.join(", ")
  except CatchableError as e:
    result.add("internal error validating stages: " & e.msg)

func validateEnvVars(node: JsonNode): seq[string] =
  try:
    let arr = node{"envVars"}
    if arr != nil and arr.kind == JArray:
      for idx in 0 ..< arr.len:
        let ev = arr[idx]
        if ev.kind != JObject:
          result.add "Gate '" & getId(node) & "': envVars[" & $idx & "] must be an object"
        else:
          if ev{"name"} == nil or ev{"name"}.kind != JString:
            result.add "Gate '" & getId(node) & "': envVars[" & $idx & "] missing 'name'"
          if ev{"value"} == nil or ev{"value"}.kind != JString:
            result.add "Gate '" & getId(node) & "': envVars[" & $idx & "] missing 'value'"
          var envKeys: seq[string]
          for k in ev.keys: envKeys.add(k)
          for key in envKeys:
            if key != "name" and key != "value":
              result.add "Gate '" & getId(node) & "': envVars[" & $idx &
                "] has unknown key '" & key & "'"
  except CatchableError as e:
    result.add("internal error validating envVars: " & e.msg)

func validateEnvDependencies(node: JsonNode): seq[string] =
  try:
    let arr = node{"envDependencies"}
    if arr != nil and arr.kind == JArray:
      for idx in 0 ..< arr.len:
        let dep = arr[idx]
        if dep.kind != JObject:
          result.add "Gate '" & getId(node) & "': envDependencies[" & $idx & "] must be an object"
        else:
          if dep{"kind"} == nil or dep{"kind"}.kind != JString:
            result.add "Gate '" & getId(node) & "': envDependencies[" & $idx & "] missing 'kind'"
          else:
            let k = dep{"kind"}.getStr()
            if k != "gitConfig" and k != "envVar":
              result.add "Gate '" & getId(node) & "': envDependencies[" & $idx &
                "] kind '" & k & "' invalid; valid: gitConfig, envVar"
          if dep{"key"} == nil or dep{"key"}.kind != JString:
            result.add "Gate '" & getId(node) & "': envDependencies[" & $idx & "] missing 'key'"
          var depKeys: seq[string]
          for k in dep.keys: depKeys.add(k)
          for key in depKeys:
            if key != "kind" and key != "key":
              result.add "Gate '" & getId(node) & "': envDependencies[" & $idx &
                "] has unknown key '" & key & "'"
  except CatchableError as e:
    result.add("internal error validating envDependencies: " & e.msg)

func validateAdditionalProperties(node: JsonNode): seq[string] =
  try:
    for key in node.keys:
      var known = false
      for k in knownFieldNames:
        if key == k:
          known = true
          break
      if not known:
        result.add "Gate '" & getId(node) & "': unknown field '" & key & "'"
  except CatchableError as e:
    result.add("internal error validating additional properties: " & e.msg)

func validateGateNode*(node: JsonNode): seq[string] =
  if node == nil or node.kind != JObject:
    return @["Gate node must be a JSON object"]

  for field in ["id", "name", "layer", "entry", "stages", "weight"]:
    result.add validateRequiredField(node, field)

  if result.len > 0:
    return

  result.add validateEnumField(node, "layer", validLayers)
  result.add validateEnumField(node, "weight", validWeights)
  result.add validateEnumField(node, "severity", validSeverities)
  result.add validateEnumField(node, "hermeticity", validHermeticities)
  result.add validateEnumField(node, "tier", validTiers)
  result.add validateEnumField(node, "execution_mode", validExecutionModes)
  result.add validateEnumField(node, "category", validCategories)

  result.add validateStagesArray(node)

  result.add validateType(node, "layer", JString)
  result.add validateType(node, "weight", JString)
  result.add validateType(node, "severity", JString)
  result.add validateType(node, "hermeticity", JString)
  result.add validateType(node, "execution_mode", JString)
  result.add validateType(node, "category", JString)
  result.add validateType(node, "tier", JInt)

  result.add validateType(node, "passFilenames", JBool)
  result.add validateType(node, "priority", JInt)
  result.add validateType(node, "always_run", JBool)
  result.add validateType(node, "filesPattern", JString)
  result.add validateType(node, "entry", JString)
  result.add validateType(node, "id", JString)
  result.add validateType(node, "name", JString)

  result.add validateArrayStrings(node, "after")
  result.add validateArrayStrings(node, "depsDirs")
  result.add validateArrayStrings(node, "argsTemplate")

  result.add validateEnvVars(node)
  result.add validateEnvDependencies(node)

  result.add validateAdditionalProperties(node)

func validateAllGateNodes*(nodes: seq[JsonNode]): seq[string] =
  var idSet: HashSet[string]
  for i, node in nodes:
    let gateErrors = validateGateNode(node)
    for e in gateErrors:
      result.add e

    if result.len > 100:
      result.add "[Truncated: too many errors]"
      return

    let id = getId(node)
    if id.len > 0 and id in idSet:
      result.add "Duplicate gate id: '" & id & "'"
    if id.len > 0:
      idSet.incl(id)

func knownGateIds*(nodes: seq[JsonNode]): HashSet[string] =
  for node in nodes:
    try:
      let id = getId(node)
      if id.len > 0:
        result.incl(id)
    except CatchableError: # axiom:best-effort(JSON traversal skip malformed node)
      discard

func checkAfterClosure*(nodes: seq[JsonNode]): seq[string] =
  let ids = knownGateIds(nodes)
  for node in nodes:
    try:
      let arr = node{"after"}
      if arr != nil and arr.kind == JArray:
        let gateId = getId(node)
        for item in arr:
          if item.kind == JString:
            let dep = item.getStr()
            if dep.len > 0 and dep notin ids:
              result.add "Gate '" & gateId & "': 'after' references unknown gate id '" & dep & "'"
    except CatchableError as e:
      result.add("internal error in checkAfterClosure: " & e.msg)

{.pop.}
