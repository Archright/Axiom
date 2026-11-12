import core/trusted/layer_declaration
axiomLayer "verification"
{.push raises: [].}

## computeVerificationPlan — pure, deterministic verification plan computation.
##
## Produces a VerificationPlan from (universe, analysis, kernelScope, seedSet, policy).
##
## Required predicate: Required(u,P) ⟺ ScopeEligible(u) ∧ HasObligation(u) ∧ PolicyAllows(u,P)
## — NO dependency-satisfiability in the predicate (dependency status is a SEPARATE execution dimension).
##
## seedSet is used ONLY for affectedUnitIds (SeedReachable closure). requiredUnitIds is seed-INDEPENDENT.
##
## INV-3: if any unit is UNRESOLVED → planState = UNRESOLVED (fail-closed, NOT COMPLETE).
## COMPLETE ⇒ every unit REQUIRED or NOT_REQUIRED.
##
## Reuses computeRequiredRequestsWithProvenance for the required-set + reason,
## and implements a SeedReachable BFS for affectedUnitIds.
## Do NOT modify existing functions — wrap them.

import std/[algorithm, sequtils, sets, strutils, tables]
import core/crypto/hash_kernel
import core/sorter/sorter_core
import core/types/request_id
import core/types/request_derivation_types
import core/topology/topology_types
import core/proof/proof_integrity
import verification/selection/request_oracle
import core/types/verification_plan

# ---------------------------------------------------------------------------
# SeedReachable BFS — upward propagation from seeds through dependents
# ---------------------------------------------------------------------------

func seedReachableClosure*(
  seeds: HashSet[string]
; symbolDependents: Table[string, seq[string]]
; universe: HashSet[string]
): seq[string] {.raises: [].} =
  var visited = initHashSet[string]()
  var queue: seq[string] = @[]
  for seed in seeds.toSeq.sorted(cmp):
    if seed notin visited:
      visited.incl(seed)
      queue.add(seed)
  var head = 0
  while head < queue.len:
    let current = queue[head]
    head += 1
    for dep in symbolDependents.getOrDefault(current, @[]).sorted(cmp):
      if dep notin visited:
        visited.incl(dep)
        queue.add(dep)
  result = visited.intersection(universe).toSeq.sorted(cmp)

# ---------------------------------------------------------------------------
# Build symbolDependents from TopologyAnalysis
# ---------------------------------------------------------------------------

func buildSymbolDependents*(analysis: TopologyAnalysis): Table[string, seq[string]] {.raises: [].} =
  var dependents: Table[string, seq[string]] = initTable[string, seq[string]]()
  for node in analysis.state.nodes:
    let nodeStr = sorterNodeIdString(node.id)
    for depId in node.dependencyIds:
      dependents.mgetOrPut(sorterNodeIdString(depId), @[]).add(nodeStr)
  dependents

# ---------------------------------------------------------------------------
# Policy application
# ---------------------------------------------------------------------------

func applyBudgetPolicy*(requiredSet: HashSet[string]; policy: RequestPolicy): HashSet[string] {.raises: [].} =
  if policy.budgetCap <= 0: return requiredSet
  var allowed: HashSet[string] = initHashSet[string]()
  let sortedRequired = requiredSet.toSeq.sorted(cmp)
  for i in 0 ..< min(policy.budgetCap, sortedRequired.len):
    allowed.incl(sortedRequired[i])
  allowed

# ---------------------------------------------------------------------------
# Per-unit requirement building
# ---------------------------------------------------------------------------

func buildPerUnitRequirement*(
  universe: seq[string]
; requiredSet: HashSet[string]
; allowedSet: HashSet[string]
; requiredReasons: Table[string, string]
): seq[RequirementDecision] {.raises: [].} =
  var perUnit: seq[RequirementDecision] = @[]
  for unitId in universe.sorted(cmp):
    if unitId in allowedSet and unitId in requiredSet:
      perUnit.add(RequirementDecision(unitId: unitId, decision: rdRequired,
        reason: requiredReasons.getOrDefault(unitId, "scope-eligible, has obligation, policy allows")))
    elif unitId in requiredSet and unitId notin allowedSet:
      perUnit.add(RequirementDecision(unitId: unitId, decision: rdNotRequired,
        reason: "policy budget cap exceeded"))
    elif unitId in requiredReasons and requiredReasons.getOrDefault(unitId, "") == "verified-excluded":
      perUnit.add(RequirementDecision(unitId: unitId, decision: rdNotRequired,
        reason: "verified-excluded"))
    else:
      perUnit.add(RequirementDecision(unitId: unitId, decision: rdNotRequired,
        reason: "outside kernel scope or no obligation"))
  perUnit

# ---------------------------------------------------------------------------
# Digest computation
# ---------------------------------------------------------------------------

func computePlanDigests*(
  universe: seq[string]
; policy: RequestPolicy
): tuple[subjectDigest, semanticPolicyDigest, universeDigest: string] {.raises: [].} =
  let subjectDigest = sha256Hex(universe.sorted(cmp).join("|"))
  let semanticPolicyDigest = sha256Hex($policy.budgetCap & $policy.fallbackOn)
  let universeDigest = sha256Hex(universe.sorted(cmp).join("|"))
  (subjectDigest: subjectDigest, semanticPolicyDigest: semanticPolicyDigest, universeDigest: universeDigest)

# ---------------------------------------------------------------------------
# computeVerificationPlan — main entry point (pure func)
# ---------------------------------------------------------------------------

func computeVerificationPlan*(
  universe: seq[string]
; analysis: TopologyAnalysis
; kernelScope: KernelScopeInfo
; seedSet: HashSet[string]
; policy: RequestPolicy
): VerificationPlan {.raises: [].} =
  ## Pure function: computes a VerificationPlan from (universe, analysis, kernelScope, seedSet, policy).
  ## Reads NOTHING external — no cache, no solver, no execution, no scheduler, no wave, no vault.

  var universeSet = initHashSet[string]()
  for u in universe: universeSet.incl(u)

  let emptyVerifiedSet: HashSet[string] = initHashSet[string]()
  let provenance = computeRequiredRequestsWithProvenance(universe, analysis, kernelScope, emptyVerifiedSet)

  var requiredSet: HashSet[string] = initHashSet[string]()
  var requiredReasons: Table[string, string] = initTable[string, string]()
  for entry in provenance:
    let uid = string(entry.requestId)
    if entry.reason == "verified-excluded":
      requiredReasons[uid] = "verified-excluded"
    else:
      requiredSet.incl(uid)
      requiredReasons[uid] = entry.reason

  let allowedSet = applyBudgetPolicy(requiredSet, policy)
  let perUnit = buildPerUnitRequirement(universe, requiredSet, allowedSet, requiredReasons)
  let symbolDependents = buildSymbolDependents(analysis)
  let affectedUnitIds = seedReachableClosure(seedSet, symbolDependents, universeSet)

  let hasUnresolved = perUnit.anyIt(it.decision == rdUnresolved)
  let planState = if hasUnresolved: psUnresolved else: psComplete

  let digests = computePlanDigests(universe, policy)

  VerificationPlan(
    subjectDigest: digests.subjectDigest,
    semanticPolicyDigest: digests.semanticPolicyDigest,
    universeDigest: digests.universeDigest,
    affectedUnitIds: affectedUnitIds,
    requiredUnitIds: allowedSet.toSeq.sorted(cmp),
    perUnitRequirement: perUnit,
    planState: planState,
    semanticModelVersion: "")

{.pop.}