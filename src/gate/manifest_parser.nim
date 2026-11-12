import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## manifest_parser.nim — SSOT for gate manifest parsing and validation.
## Used by both compile-time (gate_registry.nim) and runtime consumers.
## Per AGENTS.md §0.2: First-Principles Elegance.
##
## Section parsers are pure `func` with `{.raises: [].}` — no exceptions escape.
## They operate on JSON nodes pre-validated by the outer `parseGateConfig` proc.

import core/types/results
import core/utils/axiom_error
import gate/gate_types
import std/[enumutils, json, sets, strutils]

const requiredFields = ["id", "name", "layer", "entry", "stages", "passFilenames", "weight"]

# ---------------------------------------------------------------------------
# Section parsers — pure func, no exceptions escape {.raises: []}.
# ---------------------------------------------------------------------------

func parseStages(node: JsonNode): Result[set[GateStage], AxiomError] {.raises: [].} =
  ## Parse stages set from validated JSON node.
  var stages: set[GateStage]
  try:
    let arr = node{"stages"}
    if arr != nil and arr.kind == JArray:
      for s in arr:
        case s.getStr()
        of "pre-commit": stages.incl(gsPreCommit)
        of "pre-push": stages.incl(gsPrePush)
        of "manual": stages.incl(gsManual)
        of "ci": stages.incl(gsCI)
    ok(stages)
  except CatchableError as e:
    err(parseError("parseStages: " & e.msg))

func parseLayer(node: JsonNode): Result[GateLayer, AxiomError] {.raises: [].} =
  ## Parse layer enum (default glFunctional).
  try:
    let n = node{"layer"}
    if n != nil and n.getStr() == "meta": ok(glMeta)
    else: ok(glFunctional)
  except CatchableError as e:
    err(parseError("parseLayer: " & e.msg))

func parseWeight(node: JsonNode): Result[GateWeight, AxiomError] {.raises: [].} =
  ## Parse weight enum (default gwLight).
  try:
    let n = node{"weight"}
    if n != nil:
      case n.getStr()
      of "medium": ok(gwMedium)
      of "heavy": ok(gwHeavy)
      else: ok(gwLight)
    else: ok(gwLight)
  except CatchableError as e:
    err(parseError("parseWeight: " & e.msg))

func parseOptionalStrSeq(node: JsonNode, key: string): Result[seq[string], AxiomError] {.raises: [].} =
  ## Parse optional string array by key (argsTemplate, depsDirs, after, etc.).
  var res: seq[string]
  try:
    let arr = node{key}
    if arr != nil and arr.kind == JArray:
      for item in arr:
        res.add(item.getStr())
    ok(res)
  except CatchableError as e:
    err(parseError("parseOptionalStrSeq(" & key & "): " & e.msg))

func parseEnvVars(node: JsonNode): Result[seq[(string, string)], AxiomError] {.raises: [].} =
  ## Parse optional envVars array.
  var res: seq[(string, string)]
  try:
    let arr = node{"envVars"}
    if arr != nil and arr.kind == JArray:
      for ev in arr:
        let nameNode = ev{"name"}
        let valueNode = ev{"value"}
        if nameNode != nil and valueNode != nil:
          res.add((nameNode.getStr(), valueNode.getStr()))
    ok(res)
  except CatchableError as e:
    err(parseError("parseEnvVars: " & e.msg))

func parseEnvDependencies(node: JsonNode): Result[seq[EnvDependency], AxiomError] {.raises: [].} =
  ## Parse optional envDependencies array.
  var res: seq[EnvDependency]
  try:
    let arr = node{"envDependencies"}
    if arr != nil and arr.kind == JArray:
      for d in arr:
        let kindNode = d{"kind"}
        let keyNode = d{"key"}
        if kindNode != nil and keyNode != nil:
          let kind = case kindNode.getStr()
            of "gitConfig": dkGitConfig
            else: dkEnvVar
          res.add(EnvDependency(kind: kind, key: keyNode.getStr()))
    ok(res)
  except CatchableError as e:
    err(parseError("parseEnvDependencies: " & e.msg))

func parseSeverity(node: JsonNode): Result[GateSeverity, AxiomError] {.raises: [].} =
  ## Parse optional severity (default gsError = blocking).
  try:
    let n = node{"severity"}
    if n != nil:
      case n.getStr()
      of "warn": ok(gsWarn)
      else: ok(gsError)
    else: ok(gsError)
  except CatchableError as e:
    err(parseError("parseSeverity: " & e.msg))

func parseHermeticity(node: JsonNode): Result[GateHermeticity, AxiomError] {.raises: [].} =
  ## Parse optional hermeticity (default ghHermetic = fully deterministic).
  try:
    let n = node{"hermeticity"}
    if n != nil:
      case n.getStr()
      of "transient": ok(ghTransient)
      else: ok(ghHermetic)
    else: ok(ghHermetic)
  except CatchableError as e:
    err(parseError("parseHermeticity: " & e.msg))

func parseInputSlice(node: JsonNode): Result[tuple[kind: InputSliceKind,
    paths: seq[string], exclude: seq[string]], AxiomError] {.raises: [].} =
  ## Parse optional inputSlice fields (Phase 1-C: Fine-Grained Input Slicing).
  var kind = skFilesPattern
  try:
    let kindNode = node{"inputSliceKind"}
    if kindNode != nil and kindNode.kind == JString:
      let s = kindNode.getStr()
      if s.len > 0:
        kind = parseEnum[InputSliceKind](s)
  except CatchableError as e:
    return err(parseError("parseInputSlice: " & e.msg))
  let pathsRes = parseOptionalStrSeq(node, "inputSlicePaths")
  if pathsRes.isErr:
    return err(pathsRes.error)
  let excludeRes = parseOptionalStrSeq(node, "inputSliceExclude")
  if excludeRes.isErr:
    return err(excludeRes.error)
  ok((kind: kind, paths: pathsRes.get(), exclude: excludeRes.get()))

func parseArtifactSubscriptions(node: JsonNode): Result[tuple[produces: seq[string],
    subscribes: seq[string]], AxiomError] {.raises: [].} =
  ## Parse optional produces/subscribes (Phase H: DAG Artifact Subscriptions).
  let producesRes = parseOptionalStrSeq(node, "produces")
  if producesRes.isErr:
    return err(producesRes.error)
  let subscribesRes = parseOptionalStrSeq(node, "subscribes")
  if subscribesRes.isErr:
    return err(subscribesRes.error)
  ok((produces: producesRes.get(), subscribes: subscribesRes.get()))

# ---------------------------------------------------------------------------
# Main parser — proc (I/O boundary), validates required fields then delegates.
# ---------------------------------------------------------------------------

proc parseGateConfig*(node: JsonNode): GateConfig =
  ## Parse a single gate JSON object into GateConfig.
  ## Validates required fields exist (catches typos like "wieght").
  ## In compile-time context: doAssert (always active).
  ## In runtime context: raise ValueError.

  # Required field presence validation
  for field in requiredFields:
    when nimvm:
      doAssert node.hasKey(field),
        "Missing required field '" & field & "' in gate '" &
        (if node.hasKey("id"): node["id"].getStr() else: "<unknown>") & "'"
    else:
      if not node.hasKey(field):
        raise newException(ValueError,
          "Missing required field '" & field & "' in gate '" &
          (if node.hasKey("id"): node["id"].getStr() else: "<unknown>") & "'")

  # Delegate to pure section parsers (unwrap Result, propagate via exception)
  let inputSliceRes = parseInputSlice(node)
  if inputSliceRes.isErr:
    raise newException(ValueError, inputSliceRes.error.message)
  let inputSlice = inputSliceRes.get()

  let artifactsRes = parseArtifactSubscriptions(node)
  if artifactsRes.isErr:
    raise newException(ValueError, artifactsRes.error.message)
  let artifacts = artifactsRes.get()

  let executionMode = if node.hasKey("execution_mode"): node["execution_mode"].getStr("aot")
                      else: "aot"

  let stagesRes = parseStages(node)
  if stagesRes.isErr:
    raise newException(ValueError, stagesRes.error.message)

  let layerRes = parseLayer(node)
  if layerRes.isErr:
    raise newException(ValueError, layerRes.error.message)

  let weightRes = parseWeight(node)
  if weightRes.isErr:
    raise newException(ValueError, weightRes.error.message)

  let severityRes = parseSeverity(node)
  if severityRes.isErr:
    raise newException(ValueError, severityRes.error.message)

  let hermeticityRes = parseHermeticity(node)
  if hermeticityRes.isErr:
    raise newException(ValueError, hermeticityRes.error.message)

  let envVarsRes = parseEnvVars(node)
  if envVarsRes.isErr:
    raise newException(ValueError, envVarsRes.error.message)

  let envDepsRes = parseEnvDependencies(node)
  if envDepsRes.isErr:
    raise newException(ValueError, envDepsRes.error.message)

  template unwrapSeq(key: string): seq[string] =
    let r = parseOptionalStrSeq(node, key)
    if r.isErr:
      raise newException(ValueError, r.error.message)
    r.get()

  result = GateConfig(
    id: node["id"].getStr(),
    name: node["name"].getStr(),
    layer: layerRes.get(),
    entry: node["entry"].getStr(),
    executionMode: executionMode,
    stages: stagesRes.get(),
    filesPattern: if node.hasKey("filesPattern"): node["filesPattern"].getStr()
                  else: "",
    scope: unwrapSeq("scope"),
    passFilenames: node["passFilenames"].getBool(),
    priority: node.getOrDefault("priority").getInt(0),
    envVars: envVarsRes.get(),
    weight: weightRes.get(),
    depsDirs: unwrapSeq("depsDirs"),
    argsTemplate: unwrapSeq("argsTemplate"),
    after: unwrapSeq("after"),
    alwaysRun: if node.hasKey("always_run"): node["always_run"].getBool() else: false,
    tier: if node.hasKey("tier"): node["tier"].getInt()
          else: 1,
    envDependencies: envDepsRes.get(),
    severity: severityRes.get(),
    hermeticity: hermeticityRes.get(),
    inputSliceKind: inputSlice.kind,
    inputSlicePaths: inputSlice.paths,
    inputSliceExclude: inputSlice.exclude,
    produces: artifacts.produces,
    subscribes: artifacts.subscribes,
  )

proc validateGateManifest*(gates: seq[GateConfig]) =
  ## Validate gate manifest for duplicate IDs.
  ## In compile-time context: doAssert (always active).
  ## In runtime context: raise ValueError.
  var idSet: HashSet[string]
  for g in gates:
    when nimvm:
      doAssert g.id notin idSet,
        "CRITICAL: Duplicate Gate ID detected -> " & g.id
    else:
      if g.id in idSet:
        raise newException(ValueError,
          "CRITICAL: Duplicate Gate ID detected -> " & g.id)
    idSet.incl(g.id)

{.pop.}

