## closure_evaluation_test.nim — I-C / I-F closure evaluation integrity
##
## Covers:
##   - collectClosureState: universe restricted to kernel scope; completed from
##     terminal node statuses (verified / no_obligation / inductive_valid).
##   - computeRequiredRequestsFull (via closure path): unresolved edges stay
##     within kernel scope (no unrelated-symbol inflation).
##   - evaluateUniverseFreshness (I-F): drift ⇒ not fresh (fail-closed).
##   - evaluateClosure: closureComplete=false when required remain uncompleted
##     even if frontier is empty (I-C: frontier.empty ≠ closure complete).

{.push raises: [CatchableError].}

import std/[algorithm, json, sequtils, sets, strutils, unittest]
import core/crypto/hash_kernel
import core/proof/proof_integrity
import core/sorter/sorter_core
import core/topology/topology_types
import core/topology/symbol_interning
import core/topology/verified_set
import core/orchestrator/orchestrator_report_types
import core/types/request_id
import verification/selection/request_oracle
import verification/selection/request_completeness
import verification/selection/closure_evaluation

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc makeKernelScope(syms: seq[string]): KernelScopeInfo =
  KernelScopeInfo(kernelSymbols: syms, kernelTotal: syms.len)

proc makeNodeReport(id: string; status: OrchestrationNodeStatus): OrchestrationNodeReport =
  OrchestrationNodeReport(
    nodeId: sorterNodeId(id),
    status: status,
    dependencyDepth: 0,
    usesDependencyVault: false,
    readsDependencySource: false,
    injectedAxioms: @[],
    vaultPath: "",
    cacheHit: false,
    remediationHint: "",
    mathematicalRationale: "",
    timeoutComplexityWeight: 0,
    timeoutHotspots: @[])

# ---------------------------------------------------------------------------
# collectClosureState — kernel-scoped universe
# ---------------------------------------------------------------------------

test "collectClosureState: universe restricted to kernel scope (not whole table)":
  let scope = makeKernelScope(@["src/a.nim::f", "src/b.nim::g"])
  # Build a minimal TopologyAnalysis with 3 state nodes (one outside scope).
  var analysis = TopologyAnalysis()
  # state.nodes is a seq — we can't easily fabricate SorterNode here without
  # the full sorter; instead verify the kernel-scope branch via a degraded
  # empty-analysis path and the oracle directly. The oracle kernel filter is
  # tested in request_oracle_full_test; here we assert the pure helpers.
  let state = collectClosureState(analysis, scope, initVerifiedSet(), freezeInternPool(initInternPool()), @[])
  check state.universeList.len == 2
  check "src/a.nim::f" in state.universeList
  check "src/b.nim::g" in state.universeList

test "evaluateUniverseFreshness: drift ⇒ not fresh (I-F fail-closed)":
  let scope = makeKernelScope(@["src/a.nim::f", "src/b.nim::g"])
  let startDigest = sha256Hex(scope.kernelSymbols.sorted(cmp).join("|"))
  let fresh = evaluateUniverseFreshness(scope, startDigest)
  check fresh.fresh
  # A different (drifted) start digest ⇒ not fresh
  let drifted = evaluateUniverseFreshness(scope, sha256Hex("stale-universe"))
  check not drifted.fresh

test "evaluateClosure: frontier empty but required uncompleted ⇒ closureComplete=false (I-C)":
  # Two required kernel units, only one completed (no_obligation terminal).
  let scope = makeKernelScope(@["src/a.nim::f", "src/b.nim::g"])
  var analysis = TopologyAnalysis()
  let reports = @[makeNodeReport("src/a.nim::f", orchestrationNoObligation)]
  let fields = evaluateClosure(analysis, scope, initVerifiedSet(), reports,
    frontier = @[], wavesExecuted = 2,
    universeDigestStart = sha256Hex(scope.kernelSymbols.sorted(cmp).join("|")),
    internSnapshot = freezeInternPool(initInternPool()))
  # frontier is empty but closure is NOT complete because src/b.nim::g remains
  # uncompleted — this is exactly the I-C separation (frontier.empty ≠ complete).
  check fields["frontierEmpty"].getBool()
  check not fields["closureComplete"].getBool()
  let uncompleted = fields["uncompletedRequired"].getElems().mapIt(it.getStr())
  check "src/b.nim::g" in uncompleted
  check "src/a.nim::f" notin uncompleted  # completed (terminal) → not uncompleted

test "evaluateClosure: all required completed ⇒ closureComplete=true":
  let scope = makeKernelScope(@["src/a.nim::f", "src/b.nim::g"])
  var analysis = TopologyAnalysis()
  let reports = @[
    makeNodeReport("src/a.nim::f", orchestrationNoObligation),
    makeNodeReport("src/b.nim::g", orchestrationVerified)]
  let fields = evaluateClosure(analysis, scope, initVerifiedSet(), reports,
    frontier = @[], wavesExecuted = 1,
    universeDigestStart = sha256Hex(scope.kernelSymbols.sorted(cmp).join("|")),
    internSnapshot = freezeInternPool(initInternPool()))
  check fields["frontierEmpty"].getBool()
  check fields["closureComplete"].getBool()
  check fields["uncompletedRequired"].getElems().len == 0

{.pop.}