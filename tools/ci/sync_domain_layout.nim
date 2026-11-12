## sync_domain_layout.nim — Syncs domain_layout.json (SSOT) to architecture_policy.lock.
##
## Reads the declarative DAG matrix from domain_layout.json,
## validates topological ordering, and auto-generates the [layer_edges]
## section in architecture_policy.lock.
##
## Exit codes:
##   0 — success
##   1 — validation failed or file not found
##
## Usage:
##   nim c -d:release -o:bin/sync_domain_layout tools/ci/sync_domain_layout.nim
##   bin/sync_domain_layout [--check]

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/[os, json, strutils, sequtils, sets, algorithm, tables, re]

const
  layoutRelPath = "data/domain_layout.json"
  lockRelPath = "src/gate/architecture_policy.lock"
  layerEdgesHeader = "[layer_edges]"

# ---------------------------------------------------------------------------
# Pure helpers (func)
# ---------------------------------------------------------------------------

func validateTopologicalOrder(layout: JsonNode): seq[string] {.raises: [CatchableError].} =
  ## Validate that layer priorities form a valid DAG (no cycles).
  ## Returns seq of error messages (empty = valid).
  let layers = layout["layers"]
  for name in layers.keys:
    let priority = layers[name]["priority"].getInt()
    let allowedDeps = layers[name].getOrDefault("allowed_deps")
    if allowedDeps.kind == JArray:
      for depNode in allowedDeps:
        let dep = depNode.getStr()
        if dep notin layers:
          result.add("Layer '" & name & "' depends on unknown layer '" & dep & "'")
        elif layers[dep]["priority"].getInt() >= priority:
          result.add("Layer '" & name & "' (priority=" & $priority &
                     ") depends on '" & dep & "' (priority=" &
                     $layers[dep]["priority"].getInt() &
                     ") \u2014 violates DAG ordering")

func validateDomainRefs(layout: JsonNode): seq[string] {.raises: [CatchableError].} =
  ## Validate that all domain layer references exist in the layers map.
  let layers = layout["layers"]
  for d in layout["domains"]:
    let layerName = d["layer"].getStr()
    if layerName notin layers:
      result.add("Domain '" & d["name"].getStr() & "' references unknown layer '" & layerName & "'")

func computeEdgeMatrix(layout: JsonNode): Table[string, seq[string]] {.raises: [CatchableError].} =
  ## Compute allowed import edges per domain based on layer dependencies.
  let layers = layout["layers"]
  let domains = layout["domains"]

  # Build layer -> domain names mapping
  var layerDomains: Table[string, seq[string]]
  for d in domains:
    let layerName = d["layer"].getStr()
    layerDomains.mgetOrPut(layerName, @[]).add(d["name"].getStr())

  for d in domains:
    let domainName = d["name"].getStr()
    let domainLayerName = d["layer"].getStr()
    let domainLayer = layers[domainLayerName]
    var canImportFrom: seq[string] = @[domainLayerName]
    let allowedDeps = domainLayer.getOrDefault("allowed_deps")
    if allowedDeps.kind == JArray:
      for depNode in allowedDeps:
        canImportFrom.add(depNode.getStr())

    var allowedDomainImports: seq[string]
    for ln in canImportFrom:
      if ln in layerDomains:
        allowedDomainImports.add(layerDomains[ln])

    # Always allow self-import; deduplicate and sort
    allowedDomainImports.add(domainName)
    allowedDomainImports = allowedDomainImports.deduplicate(isSorted = false)
    allowedDomainImports.sort()
    result[domainName] = allowedDomainImports

func buildEdgeLine(domain: string, deps: seq[string]): string =
  ## Format a single edge line for the lock file.
  if deps.len > 0:
    let quoted = deps.mapIt("\"" & it & "\"").join(", ")
    domain & " = [" & quoted & "]"
  else:
    domain & " = []"

# ---------------------------------------------------------------------------
# I/O procs
# ---------------------------------------------------------------------------

proc findProjectRoot(): string {.raises: [CatchableError].} =
  ## Walk upward from the binary's directory to find .axiom_root.
  result = getAppDir()
  for _ in 0..10:
    if fileExists(result / ".axiom_root"):
      return result
    let parent = parentDir(result)
    if parent == result:
      break
    result = parent

proc loadLayout(path: string): JsonNode {.raises: [CatchableError].} =
  parseJson(readFile(path))

proc syncToLock(edges: Table[string, seq[string]],
                lockPath: string) {.raises: [CatchableError].} =
  ## Add fine-grained domain edges to [layer_edges], preserving existing entries.
  var lockContent = readFile(lockPath)

  if layerEdgesHeader notin lockContent:
    # No section exists — create one with all edges
    var lines: seq[string] = @[layerEdgesHeader]
    var sortedKeys: seq[string]
    for k in edges.keys:
      sortedKeys.add(k)
    sortedKeys.sort()
    for domain in sortedKeys:
      lines.add(buildEdgeLine(domain, edges[domain]))
    lockContent.add("\n" & lines.join("\n") & "\n")
    writeFile(lockPath, lockContent)
    return

  # Parse existing keys in [layer_edges] section
  let sectionPat = re(r"\[layer_edges\](.*?)(?=\n\[|\z)", {reDotAll})
  var captures: seq[string]
  let match = findBounds(lockContent, sectionPat, captures)
  let existingSection = if captures.len > 0: captures[0] else: ""

  var existingKeys: HashSet[string]
  for line in existingSection.splitLines():
    let stripped = line.strip()
    if stripped.len > 0 and not stripped.startsWith("#") and "=" in stripped:
      let key = stripped.split("=", 1)[0].strip()
      existingKeys.incl(key)

  # Generate lines only for NEW domains not already in the section
  var newLines: seq[string]
  var sortedKeys: seq[string]
  for k in edges.keys:
    sortedKeys.add(k)
  sortedKeys.sort()
  for domain in sortedKeys:
    if domain in existingKeys:
      continue # preserve existing entry
    newLines.add(buildEdgeLine(domain, edges[domain]))

  if newLines.len == 0:
    echo "  (no new domain edges to add)"
    return

  let insertBlock = newLines.join("\n") & "\n"

  # Find the end of [layer_edges] section
  let nextSectionPat = re(r"\n(\[)")
  var nextCaptures: seq[string]
  let nextMatch = findBounds(existingSection, nextSectionPat, nextCaptures)

  if nextMatch.first >= 0:
    # Insert before the next section header within the match
    let pos = match.first + len(layerEdgesHeader) + nextMatch.first
    lockContent = lockContent[0 ..< pos] & "\n" & insertBlock & lockContent[pos .. ^1]
  else:
    # [layer_edges] is the last section — append at end of section
    let pos = match.last
    lockContent = lockContent[0 ..< pos] & insertBlock & lockContent[pos .. ^1]

  writeFile(lockPath, lockContent)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc main() {.raises: [].} =
  var checkOnly = false
  for i in 1..paramCount():
    if paramStr(i) == "--check":
      checkOnly = true

  var root: string
  try:
    root = findProjectRoot()
  except CatchableError:
    echo "\u274c Could not resolve project root"
    quit(1)

  let layoutPath = root / layoutRelPath
  let lockPath = root / lockRelPath

  if not fileExists(layoutPath):
    echo "\u274c domain_layout.json not found at " & layoutPath
    quit(1)

  var layout: JsonNode
  try:
    layout = loadLayout(layoutPath)
  except CatchableError:
    echo "\u274c Failed to parse domain_layout.json"
    quit(1)

  # Validate
  var errors: seq[string]
  var edges: Table[string, seq[string]]
  try:
    errors = validateTopologicalOrder(layout)
    errors.add(validateDomainRefs(layout))
  except CatchableError:
    echo "\u274c Validation raised unexpected error"
    quit(1)

  if errors.len > 0:
    echo "\u274c Validation FAILED:"
    for e in errors:
      echo "  - " & e
    quit(1)

  try:
    edges = computeEdgeMatrix(layout)
  except CatchableError:
    echo "\u274c Failed to compute edge matrix"
    quit(1)

  if checkOnly:
    try:
      let domainCount = layout["domains"].len
      let layerCount = layout["layers"].len
      echo "\u2705 domain_layout.json valid"
      echo "   " & $domainCount & " domains, " & $layerCount & " layers"
      echo "   " & $edges.len & " edge entries computed"
    except CatchableError:
      echo "\u2705 domain_layout.json valid"
      echo "   " & $edges.len & " edge entries computed"
    quit(0)

  try:
    syncToLock(edges, lockPath)
    let relLockPath = lockPath.relativePath(root)
    echo "\u2705 Synced " & $edges.len & " domain edges to " & relLockPath
  except CatchableError:
    echo "\u274c Failed to sync to architecture_policy.lock"
    quit(1)

when isMainModule:
  main()
