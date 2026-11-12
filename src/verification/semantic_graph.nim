import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/axiom_pragmas
import core/utils/constants
import core/global_symbol_graph_types
import core/json/json_utils
import core/json/std_redirect
import core/results
import core/semantic_types
import core/symbol_graph/global_symbol_graph_query
import core/symbolic/global_symbol_graph_types
import core/utils/io_utils
import core/utils/text_utils
import std/algorithm
import std/options
import std/os
import std/sets
import std/strutils
import std/tables
import std/times
import verification/global_symbol_graph
# ---------------------------------------------------------------------------
# Certificate status mapping
# ---------------------------------------------------------------------------

# @axiom-hint: lean="qualifiedName.length ≥ 0 ∧ certDir.length ≥ 0" smt="(assert (and (>= (str.len qualifiedName) 0) (>= (str.len certDir) 0)))"
# @axiom-hint: lean="nodeOpt.isNone = true ∧ snsUnknown ∧ snsVerified ∧ snsInvalid ∧ snsPending ∧ nodeOpt.isNone = true → result = snsUnknown" smt="(assert (and (= (option.isNone nodeOpt) true) snsUnknown snsVerified snsInvalid snsPending (=> (= (option.isNone nodeOpt) true) (= result snsUnknown))))"
proc loadCertificateStatus(qualifiedName: string; certDir: string): SemanticNodeStatus {.raises: [].} =
  let safeName = sanitizeAxiomToken(qualifiedName).replace("/", "_")
  let path = certDir & "/" & safeName & ".json"
  if not fileExists(path):
    return snsUnknown
  let nodeOpt = readJsonFile(path)
  if nodeOpt.isNone:
    return snsUnknown
  let node = nodeOpt.get()
  if node.hasKey(statusKey):
    let s = node.getOrDefault(statusKey).getStr()
    case s
    of "verified", "green", "certGreen": return snsVerified
    of "invalid", "red", "certRed": return snsInvalid
    of "pending", "yellow", "certPending": return snsPending
    of "certyellow", "bounded": return snsPending
    else: return snsUnknown
  return snsUnknown

# ---------------------------------------------------------------------------
# Tarjan SCC (cycle detection)
# ---------------------------------------------------------------------------

# @axiom-hint: lean="stack.length = 0 ∧ w = v ∧ scc.length > 1 ∧ true ∧ result = sccs ∧ (result ≥ 0)" smt="(assert (and (= (str.len stack) 0) (= w v) (> (str.len scc) 1) true (= result sccs) (>= result 0)))"
proc tarjanScc(adj: Table[string, seq[string]]): seq[seq[string]] {.raises: [].} =
  var index = 0
  var stack: seq[string] = @[]
  var onStack = initHashSet[string]()
  var indices = initTable[string, int]()
  var lowlinks = initTable[string, int]()
  var sccs: seq[seq[string]] = @[]

# @axiom-hint: lean="v.length ≥ 0" smt="(assert (and (>= (str.len v) 0)))"
# @axiom-hint: lean="stack.length = 0 ∧ w = v ∧ scc.length > 1 ∧ true" smt="(assert (and (= (str.len stack) 0) (= w v) (> (str.len scc) 1) true))"
  func strongConnect(v: string) {.raises: [].} =
    discard indices.mgetOrPut(v, index)
    discard lowlinks.mgetOrPut(v, index)
    inc index
    stack.add(v)
    onStack.incl(v)
    for w in adj.getOrDefault(v, @[]):
      if not indices.hasKey(w):
        strongConnect(w)
        if lowlinks.getOrDefault(w) < lowlinks.getOrDefault(v):
          discard lowlinks.mgetOrPut(v, lowlinks.getOrDefault(w))
      elif w in onStack:
        if indices.getOrDefault(w) < lowlinks.getOrDefault(v):
          discard lowlinks.mgetOrPut(v, indices.getOrDefault(w))
    if lowlinks.getOrDefault(v) == indices.getOrDefault(v):
      var scc: seq[string] = @[]
      while true:
        if stack.len == 0:
          break
        let w = stack[^1]
        stack.setLen(stack.len - 1)
        onStack.excl(w)
        scc.add(w)
        if w == v:
          break
      if scc.len > 1:
        sccs.add(scc)

  for v in adj.keys:
    if not indices.hasKey(v):
      strongConnect(v)
  result = sccs

# ---------------------------------------------------------------------------
# Graph builders
# ---------------------------------------------------------------------------

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
proc buildAdjacency(graph: GlobalSymbolGraph): Table[string, seq[string]] {.raises: [].} =
  for edge in graph.edges:
    result.mgetOrPut(edge.source, @[]).add(edge.target)

# @axiom-hint: lean="nodeName.length ≥ 0 ∧ graph_sccGroups.size ≥ 0 ∧ graph_rootDir.length ≥ 0 ∧ graph_graphGeneratedAt ≥ -9223372036854775808 ∧ graph_graphGeneratedAt ≤ 9223372036854775807 ∧ graph_sourceLastModifiedAt ≥ -9223372036854775808 ∧ graph_sourceLastModifiedAt ≤ 9223372036854775807 ∧ graph_totalNodes ≥ -9223372036854775808 ∧ graph_totalNodes ≤ 9223372036854775807 ∧ graph_verifiedNodes ≥ -9223372036854775808 ∧ graph_verifiedNodes ≤ 9223372036854775807 ∧ graph_pendingNodes ≥ -9223372036854775808 ∧ graph_pendingNodes ≤ 9223372036854775807 ∧ graph_invalidNodes ≥ -9223372036854775808 ∧ graph_invalidNodes ≤ 9223372036854775807 ∧ graph_riskNodes ≥ -9223372036854775808 ∧ graph_riskNodes ≤ 9223372036854775807 ∧ graph_externalNodes ≥ -9223372036854775808 ∧ graph_externalNodes ≤ 9223372036854775807" smt="(assert (and (>= (str.len nodeName) 0) (>= (seq.len graph_sccGroups) 0) (>= (str.len graph_rootDir) 0) (and (>= graph_graphGeneratedAt -9223372036854775808) (<= graph_graphGeneratedAt 9223372036854775807)) (and (>= graph_sourceLastModifiedAt -9223372036854775808) (<= graph_sourceLastModifiedAt 9223372036854775807)) (and (>= graph_totalNodes -9223372036854775808) (<= graph_totalNodes 9223372036854775807)) (and (>= graph_verifiedNodes -9223372036854775808) (<= graph_verifiedNodes 9223372036854775807)) (and (>= graph_pendingNodes -9223372036854775808) (<= graph_pendingNodes 9223372036854775807)) (and (>= graph_invalidNodes -9223372036854775808) (<= graph_invalidNodes 9223372036854775807)) (and (>= graph_riskNodes -9223372036854775808) (<= graph_riskNodes 9223372036854775807)) (and (>= graph_externalNodes -9223372036854775808) (<= graph_externalNodes 9223372036854775807))))"
# @axiom-hint: lean="0 ∧ (updatedNode ≥ 0)" smt="(assert (and 0 (>= updatedNode 0)))"
proc countForInvalidDescendants(
  nodeName: string;
  graph: var SemanticGraph;
  computed, visiting: var HashSet[string]
): int {.raises: [].} =
  if nodeName in computed:
    return graph.nodes.getOrDefault(nodeName).invalidDescendantsCount
  if nodeName in visiting:
    return 0
  visiting.incl(nodeName)
  var count = 0
  if graph.nodes.hasKey(nodeName):
    let node = graph.nodes.getOrDefault(nodeName)
    if node.status in {snsInvalid, snsRisk}:
      count += 1
    for desc in node.descendants:
      count += countForInvalidDescendants(desc, graph, computed, visiting)
    var updatedNode = graph.nodes.getOrDefault(nodeName)
    updatedNode.invalidDescendantsCount = count
    graph.nodes[nodeName] = updatedNode
    computed.incl(nodeName)
  visiting.excl(nodeName)
  count

# @axiom-hint: lean="graph_sccGroups.size ≥ 0 ∧ graph_rootDir.length ≥ 0 ∧ graph_graphGeneratedAt ≥ -9223372036854775808 ∧ graph_graphGeneratedAt ≤ 9223372036854775807 ∧ graph_sourceLastModifiedAt ≥ -9223372036854775808 ∧ graph_sourceLastModifiedAt ≤ 9223372036854775807 ∧ graph_totalNodes ≥ -9223372036854775808 ∧ graph_totalNodes ≤ 9223372036854775807 ∧ graph_verifiedNodes ≥ -9223372036854775808 ∧ graph_verifiedNodes ≤ 9223372036854775807 ∧ graph_pendingNodes ≥ -9223372036854775808 ∧ graph_pendingNodes ≤ 9223372036854775807 ∧ graph_invalidNodes ≥ -9223372036854775808 ∧ graph_invalidNodes ≤ 9223372036854775807 ∧ graph_riskNodes ≥ -9223372036854775808 ∧ graph_riskNodes ≤ 9223372036854775807 ∧ graph_externalNodes ≥ -9223372036854775808 ∧ graph_externalNodes ≤ 9223372036854775807" smt="(assert (and (>= (seq.len graph_sccGroups) 0) (>= (str.len graph_rootDir) 0) (and (>= graph_graphGeneratedAt -9223372036854775808) (<= graph_graphGeneratedAt 9223372036854775807)) (and (>= graph_sourceLastModifiedAt -9223372036854775808) (<= graph_sourceLastModifiedAt 9223372036854775807)) (and (>= graph_totalNodes -9223372036854775808) (<= graph_totalNodes 9223372036854775807)) (and (>= graph_verifiedNodes -9223372036854775808) (<= graph_verifiedNodes 9223372036854775807)) (and (>= graph_pendingNodes -9223372036854775808) (<= graph_pendingNodes 9223372036854775807)) (and (>= graph_invalidNodes -9223372036854775808) (<= graph_invalidNodes 9223372036854775807)) (and (>= graph_riskNodes -9223372036854775808) (<= graph_riskNodes 9223372036854775807)) (and (>= graph_externalNodes -9223372036854775808) (<= graph_externalNodes 9223372036854775807))))"
proc computeInvalidDescendants(graph: var SemanticGraph) {.raises: [].} =
  var computed = initHashSet[string]()
  var visiting = initHashSet[string]()
  for name in graph.nodes.keys:
    discard countForInvalidDescendants(name, graph, computed, visiting)
## Build Semantic Graph.
# @axiom-hint: lean="rootDir.length ≥ 0 ∧ certDir.length ≥ 0 ∧ graphPath.length ≥ 0" smt="(assert (and (>= (str.len rootDir) 0) (>= (str.len certDir) 0) (>= (str.len graphPath) 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
proc buildSemanticGraph*(rootDir: string; certDir: string = defaultCertDir; graphPath: string; freezeGraphCache: bool = false): SemanticGraph {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = SemanticGraph()
  result.rootDir = rootDir
  result.graphGeneratedAt = 0
  result.sourceLastModifiedAt = 0
  var gsg: GlobalSymbolGraph
  if fileExists(graphPath):
    let infoRes = getFileInfoOpt(graphPath)
    if infoRes.isOk:
      result.graphGeneratedAt = infoRes.get().lastWriteTime.toUnix()
  try:
    gsg = buildGlobalSymbolGraph(rootDir, freezeGraphCache)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  let walkRes = walkDirRecOpt(rootDir)
  if walkRes.isOk:
    for path in walkRes.get():
      if path.endsWith(".nim"):
        let infoRes = getFileInfoOpt(path)
        if infoRes.isOk:
          let t = infoRes.get().lastWriteTime.toUnix()
          if t > result.sourceLastModifiedAt:
            result.sourceLastModifiedAt = t

  let adj = buildAdjacency(gsg)
  let sccs = tarjanScc(adj)
  for i, scc in sccs:
    result.sccGroups.add(SccGroup(id: i, members: scc, status: snsUnknown))

  for qn, sym in gsg.symbols:
    if sym.kind notin {skProc, skFunc}:
      continue
    var status = loadCertificateStatus(qn, certDir)
    if status == snsUnknown:
      status = snsPending

    let deps = findDependents(gsg, qn)
    var ancestors: seq[string] = @[]
    for d in deps:
      ancestors.add(d)
    var descendants = adj.getOrDefault(qn, @[])

    result.nodes[qn] = SemanticGraphNode(
      name: sym.qualifiedName.split(".")[^1],
      modulePath: sym.modulePath,
      qualifiedName: qn,
      status: status,
      certificateHash: "",
      irFingerprint: "",
      ancestors: ancestors,
      descendants: descendants,
      depth: 0,
      impactIndex: 0.0,
      invalidDescendantsCount: 0
    )
    inc result.totalNodes
    case status
    of snsVerified: inc result.verifiedNodes
    of snsPending, snsPendingByDependency: inc result.pendingNodes
    of snsInvalid: inc result.invalidNodes
    of snsRisk, snsExternalRisk: inc result.riskNodes
    of snsUnknown: discard

  computeInvalidDescendants(result)

# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

## Impact Analysis.
# @axiom-hint: lean="v ≠ changedNode ∧ (visited ≥ 0)" smt="(assert (and (not (= v changedNode)) (>= visited 0)))"
proc impactAnalysis*(graph: SemanticGraph; changedNode: string): seq[string] {.raises: [].} =
  if not graph.nodes.hasKey(changedNode):
    return
  var visited = initHashSet[string]()
# @axiom-hint: lean="node.length ≥ 0" smt="(assert (and (>= (str.len node) 0)))"
# @axiom-hint: lean="node ∈ visited ∧ node.length ≥ 0" smt="(assert (and (member node visited) (>= (str.len node) 0)))"
  func dfs(node: string) {.raises: [].} =
    if node in visited:
      return
    visited.incl(node)
    if graph.nodes.hasKey(node):
      for ancestor in graph.nodes.getOrDefault(node).ancestors:
        dfs(ancestor)
  dfs(changedNode)
  for v in visited:
    if v != changedNode:
      result.add(v)

## Set Semantic Node Status.
# @axiom-hint: lean="current = status ∧ snsVerified ∧ snsPending ∧ snsPendingByDependency ∧ snsInvalid ∧ snsRisk ∧ snsExternalRisk ∧ snsUnknown ∧ (node ≥ 0)" smt="(assert (and (= current status) snsVerified snsPending snsPendingByDependency snsInvalid snsRisk snsExternalRisk snsUnknown (>= node 0)))"
proc setSemanticNodeStatus*(
  graph: var SemanticGraph;
  nodeName: string;
  status: SemanticNodeStatus
) {.raises: [].} =
  if not graph.nodes.hasKey(nodeName):
    return
  var node = graph.nodes.getOrDefault(nodeName)
  let current = node.status
  if current == status:
    return
  case current
  of snsVerified: dec graph.verifiedNodes
  of snsPending, snsPendingByDependency: dec graph.pendingNodes
  of snsInvalid: dec graph.invalidNodes
  of snsRisk, snsExternalRisk: dec graph.riskNodes
  of snsUnknown: discard
  node.status = status
  graph.nodes[nodeName] = node
  case status
  of snsVerified: inc graph.verifiedNodes
  of snsPending, snsPendingByDependency: inc graph.pendingNodes
  of snsInvalid: inc graph.invalidNodes
  of snsRisk, snsExternalRisk: inc graph.riskNodes
  of snsUnknown: discard

## Mark Affected Nodes Pending By Dependency.
# @axiom-hint: lean="(affected ≥ 0)" smt="(assert (and (>= affected 0)))"
proc markAffectedNodesPendingByDependency*(
  graph: var SemanticGraph;
  changedNode: string
) {.raises: [].} =
  let affected = impactAnalysis(graph, changedNode)
  for nodeName in affected:
    setSemanticNodeStatus(graph, nodeName, snsPendingByDependency)

## Invalidate Affected Subgraph.
# @axiom-hint: lean="graph_sccGroups.size ≥ 0 ∧ graph_rootDir.length ≥ 0 ∧ graph_graphGeneratedAt ≥ -9223372036854775808 ∧ graph_graphGeneratedAt ≤ 9223372036854775807 ∧ graph_sourceLastModifiedAt ≥ -9223372036854775808 ∧ graph_sourceLastModifiedAt ≤ 9223372036854775807 ∧ graph_totalNodes ≥ -9223372036854775808 ∧ graph_totalNodes ≤ 9223372036854775807 ∧ graph_verifiedNodes ≥ -9223372036854775808 ∧ graph_verifiedNodes ≤ 9223372036854775807 ∧ graph_pendingNodes ≥ -9223372036854775808 ∧ graph_pendingNodes ≤ 9223372036854775807 ∧ graph_invalidNodes ≥ -9223372036854775808 ∧ graph_invalidNodes ≤ 9223372036854775807 ∧ graph_riskNodes ≥ -9223372036854775808 ∧ graph_riskNodes ≤ 9223372036854775807 ∧ graph_externalNodes ≥ -9223372036854775808 ∧ graph_externalNodes ≤ 9223372036854775807 ∧ changedNode.length ≥ 0 ∧ certDir.length ≥ 0" smt="(assert (and (>= (seq.len graph_sccGroups) 0) (>= (str.len graph_rootDir) 0) (and (>= graph_graphGeneratedAt -9223372036854775808) (<= graph_graphGeneratedAt 9223372036854775807)) (and (>= graph_sourceLastModifiedAt -9223372036854775808) (<= graph_sourceLastModifiedAt 9223372036854775807)) (and (>= graph_totalNodes -9223372036854775808) (<= graph_totalNodes 9223372036854775807)) (and (>= graph_verifiedNodes -9223372036854775808) (<= graph_verifiedNodes 9223372036854775807)) (and (>= graph_pendingNodes -9223372036854775808) (<= graph_pendingNodes 9223372036854775807)) (and (>= graph_invalidNodes -9223372036854775808) (<= graph_invalidNodes 9223372036854775807)) (and (>= graph_riskNodes -9223372036854775808) (<= graph_riskNodes 9223372036854775807)) (and (>= graph_externalNodes -9223372036854775808) (<= graph_externalNodes 9223372036854775807)) (>= (str.len changedNode) 0) (>= (str.len certDir) 0)))"
proc invalidateAffectedSubgraph*(graph: var SemanticGraph; changedNode: string; certDir: string = defaultCertDir) {.raises: [].} =
  discard certDir
  markAffectedNodesPendingByDependency(graph, changedNode)

## Invalidate Scc Group.
# @axiom-hint: lean="(group ≥ 0)" smt="(assert (and (>= group 0)))"
proc invalidateSccGroup*(graph: var SemanticGraph; sccId: int) {.raises: [].} =
  if sccId < 0 or sccId >= graph.sccGroups.len:
    return
  var group = graph.sccGroups[sccId]
  group.status = snsInvalid
  graph.sccGroups[sccId] = group
  for member in group.members:
    setSemanticNodeStatus(graph, member, snsInvalid)

## I Graph Stale.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
proc isGraphStale*(graph: SemanticGraph): bool {.raises: [].} =
  result = graph.graphGeneratedAt > 0 and graph.sourceLastModifiedAt > 0 and
           graph.graphGeneratedAt < graph.sourceLastModifiedAt

## Compute Global Asi.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
proc computeGlobalAsi*(graph: SemanticGraph): float {.raises: [].} =
  if graph.totalNodes == 0:
    return 1.0
  let verifiedRatio = float(graph.verifiedNodes) / float(graph.totalNodes)
  let cyclePenalty = min(float(graph.sccGroups.len) * 0.01, 0.2)
  let staleRatio = if graph.totalNodes > 0:
    float(graph.pendingNodes) / float(graph.totalNodes) else: 0.0
  let riskRatio = if graph.totalNodes > 0:
    float(graph.invalidNodes + graph.riskNodes) / float(graph.totalNodes) else: 0.0
  let externalRiskRatio = if graph.totalNodes > 0:
    float(graph.externalNodes) / float(graph.totalNodes) else: 0.0
  result = verifiedRatio * (1.0 - cyclePenalty) * (1.0 - staleRatio) * (1.0 - riskRatio) * (1.0 - externalRiskRatio)
  if result < 0.0: result = 0.0
  if result > 1.0: result = 1.0

## Find Risk Nodes.
# @axiom-hint: lean="limit > 0 ∧ (result ≥ 0) ∧ a_isExternal = true ∨ a_isExternal = false ∧ b_isExternal = true ∨ b_isExternal = false" smt="(assert (and (> limit 0) (>= result 0) (or (= a_isExternal true) (= a_isExternal false)) (or (= b_isExternal true) (= b_isExternal false))))"
proc findRiskNodes*(graph: SemanticGraph; topN: int = 20): seq[SemanticGraphNode] {.raises: [].} =
  var nodes: seq[SemanticGraphNode] = @[]
  for n in graph.nodes.values:
    if n.status in {snsInvalid, snsRisk, snsPendingByDependency, snsExternalRisk} or
       (n.depth > 5 and n.impactIndex > 0.8):
      nodes.add(n)
  nodes.sort(proc (a, b: SemanticGraphNode): int {.raises: [].} =
    if a.invalidDescendantsCount != b.invalidDescendantsCount:
      return b.invalidDescendantsCount - a.invalidDescendantsCount
    if a.impactIndex != b.impactIndex:
      return int((b.impactIndex - a.impactIndex) * 1000.0)
    return b.depth - a.depth
  )
  let limit = min(topN, nodes.len)
  if limit > 0:
    result = nodes[0 ..< limit]
{.pop.}

