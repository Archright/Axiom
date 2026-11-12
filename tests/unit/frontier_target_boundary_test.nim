## Verified-Frontier target boundary test (F1 fail-first contract).
##
## F1 reproduces the engine-level blocker that `selectFrontierNodes` alone
## cannot cover: the --target symbol is lost BEFORE selectFrontierNodes runs,
## because `computeVerifiedFrontier` truncates to `--limit` in its internal
## wave loop (verified_frontier.nim:94 `if limit>0 and result.len>=limit:
## break`).
##
## Scenario nailed by WP2 follow-up ordering fix + F1:
##   frontier queue = [nodeA (ready, first), nodeB (ready, --target)]
##   --limit 1:
##     * pre-fix axiom_engine passed frontierLimit=1 into
##       computeVerifiedFrontier -> only [nodeA] survives the internal break.
##       nodeB (the target) never reaches selectFrontierNodes -> planned=0.
##     * F1 fix: axiom_engine passes computeLimit=0 (unrestricted) when a
##       --target is present, because selectFrontierNodes re-applies the real
##       frontierLimit in its Step 3. => both nodes reach selectFrontierNodes,
##       which returns exactly the targeted, eligible node.
##
## This test composes computeVerifiedFrontier + selectFrontierNodes exactly as
## axiom_engine does, so it reproduces the boundary condition and proves that
## an UNRESTRICTED frontier (the fix) admits the target while a bounded one
## (the regression) drops it.

import std/[unittest, tables, strutils]
import core/sorter/sorter_core
import core/topology/topology_engine
import core/topology/symbol_interning
import core/topology/verified_set
import core/topology/verified_frontier
import core/proof/proof_integrity
import cli/frontier_selection

# ---- helpers (mirror verified_frontier_test.nim) -------------------------

func makeSymbol(
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

func buildSnapshot(analysis: TopologyAnalysis): InternPoolSnapshot =
  var pool = initInternPool(analysis.state.nodes.len)
  for node in analysis.state.nodes:
    discard nodeIdForSorter(pool, node.id)
  freezeInternPool(pool)

func nodeFnIdxFor(analysis: TopologyAnalysis): Table[string, string] =
  for node in analysis.state.nodes:
    result[sorterNodeIdString(node.id)] = node.functionName

suite "F1 --target beyond --limit boundary (unrestricted frontier)":
  # Queue order is the insertion order: [A, B]. A is a ready leaf that sorts
  # first; B is the --target ready leaf that sorts second. With --limit 1,
  # the internal wave break keeps only A.
  let analysis = buildTopologyAnalysis(@[
    makeSymbol("src/a.nim", "nodeA"),           # ready, sorts first
    makeSymbol("src/b.nim", "nodeB")            # ready, sorts second (=decodedLength-like)
  ])
  let snapshot = buildSnapshot(analysis)
  let nodeIdx = nodeFnIdxFor(analysis)
  let emptyVerified = initVerifiedSet(analysis.verificationQueue.len)

  # Mock eligibility: decodedLength-like fn is eligible, nodeA is not.
  let isEligible = proc(fnName: string): bool {.raises: [].} =
    fnName == "nodeB"

  test "regression: bounded (limit=1) frontier drops the --target before selection":
    # This is the PRE-FIX condition. computeVerifiedFrontier(limit=1) applies
    # the internal break and returns only nodeA; nodeB (the target) never
    # reaches selectFrontierNodes, so --target cannot be planned.
    let bounded = computeVerifiedFrontier(analysis, emptyVerified, snapshot, 1, KernelScopeInfo())
    check sorterNodeIdString(bounded[0]) == "src/a.nim::nodeA"
    check bounded.len == 1
    # nodeB is NOT in the bounded frontier:
    var hasTarget = false
    for nid in bounded:
      if sorterNodeIdString(nid).contains("nodeB"):
        hasTarget = true
    check hasTarget == false

  test "fix: unrestricted (limit=0) frontier admits the --target for selection":
    # This is the F1 post-fix condition: axiom_engine passes computeLimit=0
    # into computeVerifiedFrontier whenever --target is present.
    let frontier = computeVerifiedFrontier(analysis, emptyVerified, snapshot, 0, KernelScopeInfo())
    check frontier.len == 2
    # selectFrontierNodes re-applies the real frontierLimit (1) in Step 3 and
    # the eligibility gate, returning exactly the targeted nodeB.
    let selected = selectFrontierNodes(frontier, "nodeB", nodeIdx, 1, isEligible)
    check selected.len == 1
    check sorterNodeIdString(selected[0]) == "src/b.nim::nodeB"

  test "no-target run keeps the original bounded behavior (zero-drift)":
    # No --target: engine uses frontierLimit as-is (not unlimited), so the
    # internal wave break truncates to 1 just as before F1.
    let frontier = computeVerifiedFrontier(analysis, emptyVerified, snapshot, 1, KernelScopeInfo())
    let selected = selectFrontierNodes(frontier, "", nodeIdx, 1, isEligible)
    # nodeA is not eligible, nodeB not in bounded frontier -> nothing selected.
    check selected.len == 0
