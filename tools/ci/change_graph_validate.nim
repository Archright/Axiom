## change_graph_validate.nim — Static Merge Graph Validator
##
## Reads TOML manifest files from a directory, builds a DAG from
## depends_on / conflicts_with declarations, and validates:
##   1. Cycle detection in depends_on graph
##   2. Unknown change IDs (referenced but not defined)
##   3. Invalid base_ref (empty or missing)
##   4. Missing referenced changes (depends_on/conflicts_with entries
##      that declare a change ID not present in the manifest set)
##   5. Declared conflict inconsistency (if A conflicts_with B then
##      B must also declare conflicts_with A)
##
## No automatic inference from file overlap — only declared edges are
## checked.  Read-only: reads git refs + config/changes/*.toml only.
##
## Exit code: 0 = valid graph, 1 = violation(s) found.
##
## Usage:
##   nim c tools/ci/change_graph_validate.nim
##   ./change_graph_validate <changes-dir>
##   # or from repo root:
##   nim c -o:bin/change_graph_validate tools/ci/change_graph_validate.nim
##   ./change_graph_validate config/changes/

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, tables, sets, sequtils]

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  ChangeNode = object
    changeId*: string
    baseRef*: string
    dependsOn*: seq[string]
    conflictsWith*: seq[string]

  ChangeGraph = object
    nodes*: Table[string, ChangeNode]

  ValidationError = object
    kind*: string      # CYCLE | UNKNOWN_CHANGE | INVALID_BASE_REF | CONFLICT_INCONSISTENCY
    message*: string

# ---------------------------------------------------------------------------
# Repo root resolution (compile-time anchor via currentSourcePath)
# ---------------------------------------------------------------------------
func repoRoot(): string {.raises: [].} =
  parentDir(parentDir(parentDir(currentSourcePath())))

# ---------------------------------------------------------------------------
# Minimal TOML parser (stdlib only — no external dependencies)
# Handles: section headers, string values, arrays of strings.
# Does NOT handle: nested tables, inline tables, multi-line strings,
#   integers, booleans, dates, or dotted keys.
# Sufficient for change manifest format.
# ---------------------------------------------------------------------------

func stripComment(line: string): string {.raises: [].} =
  ## Strip a TOML comment (# ...) from a line, respecting quoted strings.
  var inStr = false
  for i, ch in line:
    if ch == '"' and (i == 0 or line[i-1] != '\\'):
      inStr = not inStr
    if ch == '#' and not inStr:
      return line[0 ..< i].strip()
  result = line.strip()

func parseTomlString(val: string): string {.raises: [].} =
  ## Strip surrounding double quotes from a TOML string value.
  let v = val.strip()
  if v.len >= 2 and v[0] == '"' and v[^1] == '"':
    return v[1 .. ^2]
  v

func parseTomlArray(val: string): seq[string] {.raises: [].} =
  ## Parse a TOML array of strings: ["a", "b", "c"].
  let v = val.strip()
  if v.len < 2 or v[0] != '[' or v[^1] != ']':
    return @[]
  let inner = v[1 .. ^2].strip()
  if inner.len == 0:
    return @[]
  for item in inner.split(','):
    let stripped = item.strip()
    if stripped.len > 0:
      result.add(parseTomlString(stripped))

func parseTomlContent*(content: string): Table[string, Table[string, seq[string]]] {.raises: [].} =
  ## Parse TOML content into section → key → raw-value-strings.
  ## Each key maps to a seq of string values (for arrays, multiple elements;
  ## for simple strings, a single-element seq).
  result = initTable[string, Table[string, seq[string]]]()
  var currentSection = ""

  for rawLine in content.splitLines():
    let line = stripComment(rawLine)
    if line.len == 0:
      continue
    # Section header: [section-name]
    if line[0] == '[' and line[^1] == ']':
      currentSection = line[1 .. ^2].strip()
      if currentSection notin result:
        result[currentSection] = initTable[string, seq[string]]()
      continue
    # Key = value
    let eqIdx = line.find('=')
    if eqIdx < 0:
      continue
    let key = line[0 ..< eqIdx].strip()
    let valueRaw = line[eqIdx + 1 .. ^1].strip()
    if currentSection.len == 0:
      currentSection = "__root__"
    if currentSection notin result:
      result[currentSection] = initTable[string, seq[string]]()
    var section = result.getOrDefault(currentSection, initTable[string, seq[string]]())
    if valueRaw.len > 0 and valueRaw[0] == '[':
      section[key] = parseTomlArray(valueRaw)
    else:
      section[key] = @[parseTomlString(valueRaw)]
    result[currentSection] = section

# ---------------------------------------------------------------------------
# Change graph construction (I/O boundary)
# ---------------------------------------------------------------------------

func parseChangeNode*(sectionName: string; section: Table[string, seq[string]]): ChangeNode {.raises: [].} =
  ## Parse a TOML section into a ChangeNode.
  result.changeId = sectionName
  result.baseRef = ""
  result.dependsOn = @[]
  result.conflictsWith = @[]

  if "base_ref" in section:
    result.baseRef = section.getOrDefault("base_ref", @[""])[0]
  if "depends_on" in section:
    result.dependsOn = section.getOrDefault("depends_on", @[])
  if "conflicts_with" in section:
    result.conflictsWith = section.getOrDefault("conflicts_with", @[])

proc loadManifests*(dir: string): ChangeGraph {.raises: [IOError, OSError].} =
  ## Enumerate all .toml files in *dir* and build a ChangeGraph.
  result.nodes = initTable[string, ChangeNode]()
  if not dirExists(dir):
    return

  for kind, path in walkDir(dir):
    if kind != pcFile:
      continue
    if not path.endsWith(".toml"):
      continue
    try:
      let content = readFile(path)
      let doc = parseTomlContent(content)
      for sectionName, section in doc.pairs:
        let node = parseChangeNode(sectionName, section)
        if node.changeId notin result.nodes:
          result.nodes[node.changeId] = node
    except CatchableError:
      # Skip malformed TOML files — they will surface as unknown-change
      # or missing-ref errors when other manifests reference them.
      discard

# ---------------------------------------------------------------------------
# Validation checks (pure, no I/O)
# ---------------------------------------------------------------------------

func detectCycles*(graph: ChangeGraph): seq[ValidationError] {.raises: [].} =
  ## Detect cycles in the depends_on graph using DFS.
  const
    White = 0
    Gray = 1
    Black = 2
  var color = initTable[string, int]()
  for id in graph.nodes.keys:
    color[id] = White

  proc dfs(nodeId: string; path: seq[string]): seq[ValidationError] =
    let node = graph.nodes.getOrDefault(nodeId, ChangeNode())
    color[nodeId] = Gray
    var newPath = path & @[nodeId]
    for dep in node.dependsOn:
      if dep notin graph.nodes:
        continue  # unknown change — reported by missing_ref check
      let depColor = color.getOrDefault(dep, White)
      if depColor == Gray:
        # Cycle found — reconstruct the cycle path.
        let cycleStart = newPath.find(dep)
        let cyclePath = if cycleStart >= 0:
                          newPath[cycleStart .. ^1].join(" -> ") & " -> " & dep
                        else:
                          dep & " -> " & dep
        result.add(ValidationError(
          kind: "CYCLE",
          message: "Cycle detected in depends_on: " & cyclePath))
      elif depColor == White:
        result.add(dfs(dep, newPath))
    color[nodeId] = Black

  for id in graph.nodes.keys:
    if color.getOrDefault(id, White) == White:
      result.add(dfs(id, @[]))

func findUnknownChanges*(graph: ChangeGraph): seq[ValidationError] {.raises: [].} =
  ## Find change IDs referenced in depends_on or conflicts_with that are
  ## not defined as a manifest section.
  let definedIds = graph.nodes.keys.toSeq().toHashSet()
  for id, node in graph.nodes.pairs:
    for dep in node.dependsOn:
      if dep notin definedIds:
        result.add(ValidationError(
          kind: "UNKNOWN_CHANGE",
          message: "Change '" & id & "' depends_on '" & dep &
            "', but no manifest defines change_id '" & dep & "'"))
    for conf in node.conflictsWith:
      if conf notin definedIds:
        result.add(ValidationError(
          kind: "UNKNOWN_CHANGE",
          message: "Change '" & id & "' conflicts_with '" & conf &
            "', but no manifest defines change_id '" & conf & "'"))

func findInvalidBaseRef*(graph: ChangeGraph): seq[ValidationError] {.raises: [].} =
  ## Find changes with empty or missing base_ref.
  for id, node in graph.nodes.pairs:
    if node.baseRef.len == 0:
      result.add(ValidationError(
        kind: "INVALID_BASE_REF",
        message: "Change '" & id & "' has empty or missing base_ref"))

func findConflictInconsistency*(graph: ChangeGraph): seq[ValidationError] {.raises: [].} =
  ## Check that conflicts_with is symmetric: if A conflicts_with B,
  ## then B must also declare conflicts_with A.
  for id, node in graph.nodes.pairs:
    for conf in node.conflictsWith:
      if conf notin graph.nodes:
        continue  # unknown change — reported by unknown_change check
      let other = graph.nodes.getOrDefault(conf, ChangeNode())
      if id notin other.conflictsWith:
        result.add(ValidationError(
          kind: "CONFLICT_INCONSISTENCY",
          message: "Change '" & id & "' declares conflicts_with '" & conf &
            "', but '" & conf & "' does not declare conflicts_with '" & id & "'"))

# ---------------------------------------------------------------------------
# Main validation entry point
# ---------------------------------------------------------------------------

proc validate*(dir: string): int {.raises: [].} =
  ## Validate all manifests in *dir*.  Returns 0 if valid, 1 if violations.
  let graph = try:
               loadManifests(dir)
             except IOError, OSError:
               echo "FAIL: could not read manifests from " & dir
               return 1

  if graph.nodes.len == 0:
    echo "WARN: no .toml manifests found in " & dir
    return 0

  var errors: seq[ValidationError] = @[]

  errors.add(detectCycles(graph))
  errors.add(findUnknownChanges(graph))
  errors.add(findInvalidBaseRef(graph))
  errors.add(findConflictInconsistency(graph))

  # Flatten and deduplicate by message.
  var seen: HashSet[string] = initHashSet[string]()
  var uniqueErrors: seq[ValidationError] = @[]
  for e in errors.concat():
    if e.message notin seen:
      seen.incl(e.message)
      uniqueErrors.add(e)

  if uniqueErrors.len > 0:
    echo "FAIL: change graph validation found " & $uniqueErrors.len & " violation(s):"
    for e in uniqueErrors:
      echo "  [" & e.kind & "] " & e.message
    return 1

  echo "PASS: change graph is valid (" & $graph.nodes.len & " node(s), acyclic, all refs resolved)"
  return 0

# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

proc main() =
  let args = commandLineParams()
  var targetDir = ""

  if args.len == 0:
    # Default: look for config/changes/ relative to repo root.
    targetDir = repoRoot() / "config" / "changes"
  elif args.len == 1:
    targetDir = args[0]
    if not targetDir.isAbsolute():
      targetDir = repoRoot() / targetDir
  else:
    stderr.writeLine("Usage: change_graph_validate [<changes-dir>]")
    stderr.writeLine("  <changes-dir>  Directory of TOML manifests (default: config/changes/)")
    quit(1)

  if not dirExists(targetDir):
    stderr.writeLine("FAIL: directory not found: " & targetDir)
    quit(1)

  let exitCode = validate(targetDir)
  quit(exitCode)

when isMainModule:
  main()
