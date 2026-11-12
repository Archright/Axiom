import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Change-graph admission facts — pure predicates over TOML manifest content.
##
## SSOT for the semantic rules shared by the merge-admission controller
## (`ax merge`) and the static validator (`tools/ci/change_graph_validate.nim`):
## the change DAG is built from `depends_on` / `conflicts_with` declarations and
## must be acyclic with all referenced change ids defined. The validator owns
## the CLI surface + fixtures; this module owns the pure admission predicate
## consumed by `MergeAdmissible` (see docs/spec/merge_admission_controller.md,
## docs/spec/change_manifest_contract.md).
##
## `config/changes/` is a FLAT directory contract: only top-level `*.toml`
## files are manifests; subdirectories are test fixtures (validator's walkDir
## is non-recursive by design).

import std/[strutils, tables, sets, sequtils]

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  ## One change manifest node parsed from a `config/changes/*.toml` file.
  ChangeManifestNode* = object
    changeId*: string
    baseRef*: string
    dependsOn*: seq[string]
    conflictsWith*: seq[string]

  ## Kinds of graph violations detectable from manifest content alone.
  ChangeGraphViolationKind* = enum
    cgvUnknownChange          ## referenced change id is not defined
    cgvCycle                  ## cycle in the depends_on graph
    cgvInvalidBaseRef         ## empty or missing base_ref
    cgvConflictInconsistency  ## conflicts_with not symmetric
    cgvEmptyGraph             ## no manifests collected (vacuous truth)

  ChangeGraphViolation* = object
    kind*: ChangeGraphViolationKind
    message*: string

  ChangeGraphStatus* = object
    valid*: bool
    nodeCount*: int
    violations*: seq[ChangeGraphViolation]

# ---------------------------------------------------------------------------
# Minimal TOML parsing (flat manifests only — mirrors the validator's grammar:
## section headers, string values, arrays of strings; no nested tables).
# ---------------------------------------------------------------------------

func stripTomlComment*(line: string): string {.raises: [].} =
  ## Strip a TOML comment (# ...) respecting double-quoted strings.
  var inStr = false
  for i, ch in line:
    if ch == '"' and (i == 0 or line[i-1] != '\\'):
      inStr = not inStr
    if ch == '#' and not inStr:
      return line[0 ..< i].strip()
  result = line.strip()

func parseTomlString*(v: string): string {.raises: [].} =
  let s = v.strip()
  if s.len >= 2 and s[0] == '"' and s[^1] == '"':
    s[1 .. ^2]
  else:
    s

func parseTomlStringArray*(v: string): seq[string] {.raises: [].} =
  ## Parse `["a", "b"]` into @["a", "b"]; anything malformed → empty.
  let s = v.strip()
  if s.len < 2 or s[0] != '[' or s[^1] != ']':
    return @[]
  let inner = s[1 .. ^2].strip()
  if inner.len == 0:
    return @[]
  for item in inner.split(','):
    let t = item.strip()
    if t.len > 0:
      result.add(parseTomlString(t))

func parseChangeManifestContent*(content: string): seq[ChangeManifestNode] {.raises: [].} =
  ## Parse manifest TOML content into nodes. Supports the two on-disk shapes:
  ## (a) root key/value manifests — `id = "..."` at the top level (the shape
  ##     used by real `config/changes/*.toml` files); the whole file is ONE
  ##     node whose id comes from the root `id` key.
  ## (b) section-per-change fixtures — `[change-a]` headers (the shape used by
  ##     validator fixtures under config/changes/valid|invalid_*/); each
  ##     section is one node keyed by the section name.
  ## Malformed lines are skipped; structural problems surface as graph
  ## violations rather than crashes.
  var
    section = ""
    sections = initTable[string, seq[(string, string)]]()

  for rawLine in content.splitLines():
    let line = stripTomlComment(rawLine)
    if line.len == 0:
      continue
    if line[0] == '[' and line[^1] == ']':
      section = line[1 .. ^2].strip()
      if section.len > 0 and section notin sections:
        sections[section] = @[]
      continue
    let eq = line.find('=')
    if eq < 0:
      continue
    let key = line[0 ..< eq].strip()
    let value = line[eq + 1 .. ^1].strip()
    if section.len == 0:
      section = "__root__"
      if section notin sections:
        sections[section] = @[]
    sections.mgetOrPut(section, @[]).add((key, value))

  # Shape (a): a single root-level manifest with an `id` key.
  if sections.len == 1 and "__root__" in sections:
    var node = ChangeManifestNode()
    for (k, v) in sections.getOrDefault("__root__", @[]):
      case k
      of "id":
        node.changeId = parseTomlString(v)
      of "base_ref":
        node.baseRef = parseTomlString(v)
      of "depends_on":
        node.dependsOn = parseTomlStringArray(v)
      of "conflicts_with":
        node.conflictsWith = parseTomlStringArray(v)
      else:
        discard
    if node.changeId.len > 0:
      result.add(node)
    return

  # Shape (b): section-per-change.
  for name, kvs in sections.pairs():
    if name == "__root__":
      continue
    var node = ChangeManifestNode(changeId: name)
    for (k, v) in kvs:
      case k
      of "base_ref":
        node.baseRef = parseTomlString(v)
      of "depends_on":
        node.dependsOn = parseTomlStringArray(v)
      of "conflicts_with":
        node.conflictsWith = parseTomlStringArray(v)
      else:
        discard
    if node.changeId.len > 0:
      result.add(node)

# ---------------------------------------------------------------------------
# Pure graph predicate
# ---------------------------------------------------------------------------

func collectCycleViolations*(graph: Table[string, ChangeManifestNode]): seq[ChangeGraphViolation] {.raises: [].} =
  ## Iterative DFS cycle detection over the depends_on edges.
  const
    white = 0
    gray = 1
    black = 2
  var color = initTable[string, int]()
  for id in graph.keys:
    color[id] = white

  for root in graph.keys:
    if color.getOrDefault(root, white) != white:
      continue
    var
      stack: seq[tuple[node: string, idx: int]] = @[(root, 0)]
      path: seq[string] = @[]
    color[root] = gray
    path.add(root)
    while stack.len > 0:
      var (cur, idx) = stack[^1]
      let deps = graph.getOrDefault(cur, ChangeManifestNode()).dependsOn
      if idx < deps.len:
        stack[^1].idx = idx + 1
        let dep = deps[idx]
        if dep notin graph:
          continue
        let c = color.getOrDefault(dep, white)
        if c == gray:
          let cycleStart = path.find(dep)
          let cycle = if cycleStart >= 0:
                        path[cycleStart .. ^1].join(" -> ") & " -> " & dep
                      else:
                        dep & " -> " & dep
          result.add(ChangeGraphViolation(
            kind: cgvCycle,
            message: "cycle in depends_on: " & cycle))
        elif c == white:
          color[dep] = gray
          path.add(dep)
          stack.add((dep, 0))
      else:
        color[cur] = black
        discard stack.pop()
        discard path.pop()

func evaluateChangeGraph*(nodes: seq[ChangeManifestNode]): ChangeGraphStatus {.raises: [].} =
  ## Evaluate the change DAG: acyclic, all references defined, base_ref
  ## non-empty, conflicts symmetric. Empty graph = violation (fail-closed —
  ## an uncollected manifest set must never read as "valid").
  if nodes.len == 0:
    result.violations.add(ChangeGraphViolation(
      kind: cgvEmptyGraph,
      message: "no change manifests collected — vacuous truth blocked"))
    result.valid = false
    return

  result.nodeCount = nodes.len

  var byId = initTable[string, ChangeManifestNode]()
  for n in nodes:
    byId[n.changeId] = n

  let defined = toHashSet(toSeq(byId.keys))

  # Unknown references (depends_on / conflicts_with).
  for n in nodes:
    for dep in n.dependsOn:
      if dep notin defined:
        result.violations.add(ChangeGraphViolation(
          kind: cgvUnknownChange,
          message: "change '" & n.changeId & "' depends_on unknown change '" & dep & "'"))
    for c in n.conflictsWith:
      if c notin defined:
        result.violations.add(ChangeGraphViolation(
          kind: cgvUnknownChange,
          message: "change '" & n.changeId & "' conflicts_with unknown change '" & c & "'"))

  # Empty base_ref.
  for n in nodes:
    if n.baseRef.len == 0:
      result.violations.add(ChangeGraphViolation(
        kind: cgvInvalidBaseRef,
        message: "change '" & n.changeId & "' has empty or missing base_ref"))

  # Conflict symmetry: A conflicts_with B ⇒ B conflicts_with A.
  for n in nodes:
    for c in n.conflictsWith:
      if c in byId and n.changeId notin byId.getOrDefault(c, ChangeManifestNode()).conflictsWith:
        result.violations.add(ChangeGraphViolation(
          kind: cgvConflictInconsistency,
          message: "change '" & n.changeId & "' declares conflicts_with '" & c &
            "' but '" & c & "' does not declare it back"))

  # Cycle detection (DFS, iterative coloring) — fully flat loop, no nested
  # closures (Nim forbids capturing `result` in nested procs).
  result.violations.add(collectCycleViolations(byId))

  result.valid = result.violations.len == 0

{.pop.}
