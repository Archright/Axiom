## tools/shared/layer_dag.nim
## Lightweight layer DAG parser for architecture_policy.lock.
## Parses [layer_edges] section and provides DAG validation.
##
## Dependencies: std/[strutils, tables, sets, sequtils] only. No src/ imports.
## Used by: tools/hermetic_build, tools/axiom_validator, config.nims

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/[strutils, tables, sets, sequtils]

type
  LayerDag* = object
    ## Directed acyclic graph of allowed layer imports.
    edges*: Table[string, seq[string]]  ## layer → allowed target layers
    layerPaths*: Table[string, string]  ## layer → src/ path (e.g., "core" → "src/core")

func parseLayerEdges*(lockContent: string): LayerDag =
  ## Parse architecture_policy.lock content into a LayerDag.
  ## Handles [layer], [layer_edges] sections.
  ## Lightweight parser — no TOML dependency required.
  result = LayerDag(
    edges: initTable[string, seq[string]](),
    layerPaths: initTable[string, string]()
  )

  var section = ""
  var inMultilineArray = false
  var arrayKey = ""
  var arrayAccum = ""

  for line in lockContent.splitLines():
    let stripped = line.strip()

    # Skip empty lines and comments
    if stripped.len == 0 or stripped.startsWith("#"):
      continue

    # Section header
    if stripped.startsWith("[") and stripped.endsWith("]"):
      section = stripped[1 ..< ^1].strip()
      continue

    # Key = value line
    if "=" in stripped:
      let eqIdx = stripped.find('=')
      let key = stripped[0 ..< eqIdx].strip()
      let value = stripped[eqIdx + 1 .. ^1].strip()

      case section
      of "layer":
        # core = "src/core"
        let cleanValue = value.strip(chars = {'"', '\''})
        result.layerPaths[key] = cleanValue

      of "layer_edges":
        # core = [] or core = ["a", "b"]
        if value == "[]":
          result.edges[key] = @[]
        elif value.startsWith("[") and value.endsWith("]"):
          let content = value[1 ..< ^1]
          var targets: seq[string]
          for item in content.split(','):
            let clean = item.strip().strip(chars = {'"', ' '})
            if clean.len > 0:
              targets.add(clean)
          result.edges[key] = targets
        elif value == "[":
          # Multi-line array start
          inMultilineArray = true
          arrayKey = key
          arrayAccum = ""

      else:
        discard

    # Multi-line array continuation
    elif inMultilineArray:
      arrayAccum &= " " & stripped
      if "]" in stripped:
        inMultilineArray = false
        let openIdx = arrayAccum.find('[')
        let closeIdx = arrayAccum.rfind(']')
        if openIdx >= 0 and closeIdx > openIdx:
          let content = arrayAccum[openIdx + 1 ..< closeIdx]
          var targets: seq[string]
          for item in content.split(','):
            let clean = item.strip().strip(chars = {'"', ' '})
            if clean.len > 0:
              targets.add(clean)
          result.edges[arrayKey] = targets

func isAllowed*(dag: LayerDag, sourceLayer, targetLayer: string): bool =
  ## Check if source layer is allowed to import from target layer.
  ## Returns false if source layer not in DAG (unknown layers are forbidden).
  if sourceLayer notin dag.edges:
    return false
  let allowed = dag.edges.getOrDefault(sourceLayer, @[])
  targetLayer in allowed

func getLayer*(filePath: string, dag: LayerDag): string =
  ## Determine which layer a file belongs to based on its path.
  ## Returns "" if the file doesn't belong to any known layer.
  ## Checks longest prefix first (e.g., "verification" before "core").
  let normalizedPath = filePath.replace("\\", "/")
  var bestMatch = ""
  var bestLen = 0
  for layer, layerPath in dag.layerPaths:
    let normalizedLayerPath = layerPath.replace("\\", "/")
    if normalizedPath.startsWith(normalizedLayerPath & "/") or
       normalizedPath == normalizedLayerPath:
      if normalizedLayerPath.len > bestLen:
        bestMatch = layer
        bestLen = normalizedLayerPath.len
  bestMatch

func getSubDomain*(filePath: string, layer: string, dag: LayerDag): string =
  ## For core/ files, extract the sub-domain (e.g., "trusted", "bmc").
  ## Returns "" if not a core/ file or sub-domain not recognized.
  if layer != "core":
    return ""
  let layerPath = dag.layerPaths.getOrDefault("core", "src/core")
  let normalizedPath = filePath.replace("\\", "/")
  let normalizedLayerPath = layerPath.replace("\\", "/")
  if not normalizedPath.startsWith(normalizedLayerPath & "/"):
    return ""
  let relative = normalizedPath[normalizedLayerPath.len + 1 .. ^1]
  let firstDir = relative.split("/")[0]
  firstDir

func fileEdges*(dag: LayerDag, filePath: string,
                imports: HashSet[string]): seq[(string, string)] =
  ## For a given file and its imports, return all (source, target) layer edges.
  let sourceLayer = getLayer(filePath, dag)
  if sourceLayer.len == 0:
    return @[]
  for imp in imports:
    # Resolve import path to a layer
    for layer, layerPath in dag.layerPaths:
      let normalizedImp = imp.replace("\\", "/")
      let normalizedLayerPath = layerPath.replace("\\", "/")
      if normalizedImp.startsWith(layer & "/") or
         normalizedImp.startsWith(normalizedLayerPath & "/"):
        result.add((sourceLayer, layer))
        break
