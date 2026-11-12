import core/trusted/layer_declaration
axiomLayer "domain"


{.push raises: [].}

## Verified Frontier — topology queue masking with transitive dependency padding.

import std/options
import std/tables
import core/sorter/sorter_core
import core/topology/symbol_interning
import core/topology/topology_engine
import core/topology/verified_set
import core/proof/proof_integrity

func isInKernelScope(key: string; scope: KernelScopeInfo): bool {.inline.} =
  key in scope.kernelSymbols

func isKernelExempt(key: string; scope: KernelScopeInfo): bool {.inline.} =
  key in scope.kernelExemptSymbols

func buildNodeIndex(analysis: TopologyAnalysis): Table[string, int] {.inline.} =
  for idx, node in analysis.state.nodes:
    result[sorterNodeIdString(node.id)] = idx

func allDependenciesVerified(
  node: SorterNode;
  verified: VerifiedSet;
  internPool: InternPoolSnapshot
): bool {.inline.} =
  for dep in node.dependencyIds:
    let depOpt = nodeIdForSorter(internPool, dep)
    if depOpt.isNone:
      return false
    if not verified.contains(depOpt.get()):
      return false
  true

func computeVerifiedFrontier*(
  analysis: TopologyAnalysis;
  verified: VerifiedSet;
  internPool: InternPoolSnapshot;
  limit: int;
  scope: KernelScopeInfo;
  subjectMode: bool = false
): seq[SorterNodeId] =
  ## Return up to `limit` unverified nodes whose direct dependencies are already
  ## verified. This is a push-based topological generation-wave slice:
  ## padding size is always zero because prerequisites are satisfied before a
  ## node is selected.
  ##
  ## Kernel-scope aware: when a kernel scope is provided (non-empty kernelSymbols),
  ## only symbols that are members of the kernel scope are eligible as candidates.
  ## This prevents VKD-non-contributing symbols (e.g. shell symbols like parseJson)
  ## from consuming prove budget, so `ax prove --limit N` selects admissible VKD
  ## candidates only.
  ##
  ## `limit <= 0` means unlimited.
  let scopeAware = scope.kernelSymbols.len > 0
  result = @[]
  var selected = initVerifiedSet(analysis.verificationQueue.len)
  let nodeIndex = buildNodeIndex(analysis)

  for rootSorterId in analysis.verificationQueue:
    let rootOpt = nodeIdForSorter(internPool, rootSorterId)
    if rootOpt.isNone:
      continue
    let rootNodeId = rootOpt.get()
    if verified.contains(rootNodeId) or selected.contains(rootNodeId):
      continue

    # WP2-a: in external-subject mode (subjectMode=true) the SubjectUniverse
    # (runtime-derived from VerificationSubject) is the admission authority, so
    # Axiom-self kernel-scope/exempt membership gates do not apply here.
    # SupportUniverse semantics (verification_scope.lock) stay untouched —
    # self-runs pass subjectMode=false and keep the original path verbatim.
    if not subjectMode:
      if scopeAware and not isInKernelScope(sorterNodeIdString(rootSorterId), scope):
        continue
      if scopeAware and isKernelExempt(sorterNodeIdString(rootSorterId), scope):
        continue

    let rootIdx = nodeIndex.getOrDefault(sorterNodeIdString(rootSorterId), -1)
    if rootIdx < 0:
      continue

    if not allDependenciesVerified(analysis.state.nodes[rootIdx], verified, internPool):
      continue

    selected.incl(rootNodeId)
    result.add(rootSorterId)

    if limit > 0 and result.len >= limit:
      break

{.pop.}
