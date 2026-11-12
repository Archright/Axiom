## Verified Frontier Tests — Topological generation-wave slicing.
##
## Verifies that the frontier contains only unverified nodes whose direct
## dependencies are already verified (push-based wave slicing), and that no
## dependency padding is added.

import std/options
import std/unittest
import core/sorter/sorter_core
import core/topology/topology_engine
import core/topology/topology_types
import core/topology/symbol_interning
import core/topology/verified_set
import core/topology/verified_frontier
import core/proof/proof_integrity

func makeFrontierTestSymbol(
  modulePath, functionName: string;
  targets: seq[string] = @[]
): TopologySymbol =
  TopologySymbol(
    modulePath: modulePath,
    functionName: functionName,
    nodeType: "func",
    nodeId: sorterNodeId(modulePath & "::" & functionName),
    declarationLine: 1,
    bodyStartLine: 1,
    bodyEndLine: 2,
    exported: false,
    boundaryKind: topologyBoundaryNone,
    rawCallTargets: targets,
    branchCount: 0,
    nestingDepth: 0,
    lineSpan: 2
  )

func idFor(modulePath, functionName: string): SorterNodeId =
  sorterNodeId(modulePath & "::" & functionName)

func buildSnapshot(analysis: TopologyAnalysis): InternPoolSnapshot =
  var pool = initInternPool(analysis.state.nodes.len)
  for node in analysis.state.nodes:
    discard nodeIdForSorter(pool, node.id)
  freezeInternPool(pool)

func markVerified(
  snapshot: InternPoolSnapshot;
  verified: var VerifiedSet;
  nodeId: SorterNodeId
) =
  let opt = nodeIdForSorter(snapshot, nodeId)
  if opt.isSome:
    verified.incl(opt.get())

func frontierSet(
  snapshot: InternPoolSnapshot;
  frontier: seq[SorterNodeId]
): VerifiedSet =
  result = initVerifiedSet(frontier.len)
  for nodeId in frontier:
    let opt = nodeIdForSorter(snapshot, nodeId)
    if opt.isSome:
      result.incl(opt.get())

func hasMissingDependency(
  node: SorterNode;
  selected, verified: VerifiedSet;
  snapshot: InternPoolSnapshot
): bool =
  for depId in node.dependencyIds:
    let depOpt = nodeIdForSorter(snapshot, depId)
    if depOpt.isNone:
      return true
    let depHandle = depOpt.get()
    if not verified.contains(depHandle) and not selected.contains(depHandle):
      return true
  false

func dependenciesSatisfied(
  analysis: TopologyAnalysis;
  frontier: seq[SorterNodeId];
  verified: VerifiedSet;
  snapshot: InternPoolSnapshot
): bool =
  let selected = frontierSet(snapshot, frontier)
  for node in analysis.state.nodes:
    if not selected.contains(nodeIdForSorter(snapshot, node.id).get()):
      continue
    if hasMissingDependency(node, selected, verified, snapshot):
      return false
  true

suite "VerifiedFrontier":

  let analysis = buildTopologyAnalysis(@[
    makeFrontierTestSymbol("src/a.nim", "A"),
    makeFrontierTestSymbol("src/b.nim", "B", @["A"]),
    makeFrontierTestSymbol("src/c.nim", "C", @["A"]),
    makeFrontierTestSymbol("src/d.nim", "D", @["B"])
  ])
  let snapshot = buildSnapshot(analysis)

  test "leaf node is the only ready node when nothing is verified":
    let empty = initVerifiedSet(analysis.verificationQueue.len)
    let frontier = computeVerifiedFrontier(analysis, empty, snapshot, 0, KernelScopeInfo())
    check frontier.len == 1
    check frontier[0] == idFor("src/a.nim", "A")
    check dependenciesSatisfied(analysis, frontier, empty, snapshot)

  test "verified node is excluded from frontier":
    var verified = initVerifiedSet(analysis.verificationQueue.len)
    markVerified(snapshot, verified, idFor("src/a.nim", "A"))
    let frontier = computeVerifiedFrontier(analysis, verified, snapshot, 0, KernelScopeInfo())
    check not frontierSet(snapshot, frontier).contains(
      nodeIdForSorter(snapshot, idFor("src/a.nim", "A")).get())
    check dependenciesSatisfied(analysis, frontier, verified, snapshot)

  test "frontier selects dependents only after their dependencies are verified":
    var verified = initVerifiedSet(analysis.verificationQueue.len)
    markVerified(snapshot, verified, idFor("src/a.nim", "A"))
    let frontier = computeVerifiedFrontier(analysis, verified, snapshot, 0, KernelScopeInfo())
    let selected = frontierSet(snapshot, frontier)
    check selected.contains(nodeIdForSorter(snapshot, idFor("src/b.nim", "B")).get())
    check selected.contains(nodeIdForSorter(snapshot, idFor("src/c.nim", "C")).get())
    check not selected.contains(nodeIdForSorter(snapshot, idFor("src/d.nim", "D")).get())
    check dependenciesSatisfied(analysis, frontier, verified, snapshot)

  test "frontier respects the limit":
    var verified = initVerifiedSet(analysis.verificationQueue.len)
    markVerified(snapshot, verified, idFor("src/a.nim", "A"))
    let frontier = computeVerifiedFrontier(analysis, verified, snapshot, 1, KernelScopeInfo())
    check frontier.len == 1
    check dependenciesSatisfied(analysis, frontier, verified, snapshot)

  test "kernel-scope gate excludes non-kernel symbols from the frontier":
    # Symbols A and C are kernel-scope members; B and D are shell (excluded).
    let kernelScope = KernelScopeInfo(
      kernelSymbols: @["src/a.nim::A", "src/c.nim::C"],
      kernelTotal: 2
    )
    let frontier = computeVerifiedFrontier(analysis, initVerifiedSet(analysis.verificationQueue.len), snapshot, 0, kernelScope)
    let selected = frontierSet(snapshot, frontier)
    # A is the only ready leaf in kernel scope; B/D are shell and must not appear.
    check selected.contains(nodeIdForSorter(snapshot, idFor("src/a.nim", "A")).get())
    check not selected.contains(nodeIdForSorter(snapshot, idFor("src/b.nim", "B")).get())
    check not selected.contains(nodeIdForSorter(snapshot, idFor("src/d.nim", "D")).get())

  test "kernel-exempt symbols are excluded from the frontier":
    let localAnalysis = buildTopologyAnalysis(@[
      makeFrontierTestSymbol("src/a.nim", "A"),
      makeFrontierTestSymbol("src/exempt.nim", "Exempt", @[])
    ])
    let localSnapshot = buildSnapshot(localAnalysis)
    let kernelScope = KernelScopeInfo(
      kernelSymbols: @["src/a.nim::A", "src/exempt.nim::Exempt"],
      kernelTotal: 2,
      vksTotal: 1,
      kernelExemptSymbols: @["src/exempt.nim::Exempt"]
    )
    let frontier = computeVerifiedFrontier(localAnalysis, initVerifiedSet(localAnalysis.verificationQueue.len), localSnapshot, 0, kernelScope)
    let selected = frontierSet(localSnapshot, frontier)
    # A is the only ready eligible leaf; Exempt excluded by the kernel-exempt gate.
    check selected.contains(nodeIdForSorter(localSnapshot, idFor("src/a.nim", "A")).get())
    check not selected.contains(nodeIdForSorter(localSnapshot, idFor("src/exempt.nim", "Exempt")).get())
    check dependenciesSatisfied(localAnalysis, frontier, initVerifiedSet(localAnalysis.verificationQueue.len), localSnapshot)


