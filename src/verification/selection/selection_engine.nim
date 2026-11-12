import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Selection Engine — deterministic, pure symbol-level selection subsystem.
##
## Computes Selected ⊆ Universe from a change Δ via upward BFS propagation
## through symbolDependents. Fail-closed triggers force FALLBACK_REQUIRED;
## malformed inputs force ERROR. The derivation is a certificate of *how*
## the selection was derived, not a proof of affectedness (see contract
## sentence 3 of canonical_execution_semantics.md §4.2).
##
## Contract sentence 2: any unresolved edge in the graph forces FALLBACK
## because reachability through an unresolved target is unknowable.
## This is the conservative reading mandated by the spec.

import std/[algorithm, json, sequtils, strutils, sets, tables]
import infrastructure/cas_index
import verification/selection/selection_digests
import core/types/canonical_change_set
import core/types/graph_artifact
import core/types/selection_derivation
import core/types/execution_plan
import core/types/request_derivation_types
import verification/selection/request_derivation
import verification/selection/request_oracle

# ---------------------------------------------------------------------------
# SelectorInputs — full semantic input to the selector
# (named SelectorInputs to avoid collision with selection_derivation.SelectionInputs)
# ---------------------------------------------------------------------------

type
  SelectorInputs* = object
    changeSet*: CanonicalChangeSet
    graph*: GraphArtifact
    symbolDeps*: Table[string, seq[string]]     ## symbol → symbols it depends on
    symbolDependents*: Table[string, seq[string]] ## reverse: symbol → symbols that depend on it
    universe*: seq[string]                       ## VKS symbol ids
    policyDigest*: string
    changedSymbolSeeds*: seq[string]             ## symbols directly changed by Δ

# ---------------------------------------------------------------------------
# SelectionOutcome — result of computeSelection
# ---------------------------------------------------------------------------

type
  SelectionOutcome* = object
    derivation*: SelectionDerivation
    plan*: ExecutionPlan

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func computeUniverseDigest*(universe: seq[string]): string {.raises: [].} =
  combineHashes([universe.sorted(cmp).join("|")])

func computePolicyDigest*(policyDigest: string): string {.raises: [].} =
  ## Identity for a plain digest; used to canonicalise the policy input.
  policyDigest

func buildDerivationInputs*(inputs: SelectorInputs): selection_derivation.SelectionInputs =
  ## Extract the digest-only SelectionInputs for the derivation certificate.
  selection_derivation.SelectionInputs(
    changeSetDigest: computeChangeSetDigest(inputs.changeSet),
    graphDigest: computeGraphDigest(inputs.graph),
    universeDigest: computeUniverseDigest(inputs.universe),
    policyDigest: computePolicyDigest(inputs.policyDigest))

# ---------------------------------------------------------------------------
# BFS closure: seeds → upward propagation via symbolDependents
# ---------------------------------------------------------------------------

func computeClosure*(
    seeds: seq[string];
    symbolDependents: Table[string, seq[string]];
    universe: HashSet[string]): tuple[selected: seq[string]; excluded: seq[string]; predecessorMap: Table[string, string]] =
  ## BFS upward through symbolDependents from seeds.
  ## Returns selected (intersected with universe), excluded (universe \ selected),
  ## and a predecessor map for replaying derivation chains.
  ## Deterministic: all sets are sorted; BFS uses sorted queues.

  var visited = initHashSet[string]()
  var queue: seq[string] = @[]
  var predecessorMap: Table[string, string] = initTable[string, string]()

  # Enqueue seeds in sorted order for determinism
  let sortedSeeds = seeds.sorted(cmp)
  for seed in sortedSeeds:
    if seed notin visited:
      visited.incl(seed)
      queue.add(seed)
      # Seeds have no predecessor in the chain
      predecessorMap[seed] = ""

  # BFS
  var head = 0
  while head < queue.len:
    let current = queue[head]
    head += 1
    let dependents = symbolDependents.getOrDefault(current, @[])
    let sortedDeps = dependents.sorted(cmp)
    for dep in sortedDeps:
      if dep notin visited:
        visited.incl(dep)
        predecessorMap[dep] = current
        queue.add(dep)

  # Intersect with universe
  var selected: seq[string] = @[]
  var excluded: seq[string] = @[]
  for sym in universe.toSeq.sorted(cmp):
    if sym in visited:
      selected.add(sym)
    else:
      excluded.add(sym)

  (selected: selected, excluded: excluded, predecessorMap: predecessorMap)

# ---------------------------------------------------------------------------
# Predecessor chain reconstruction
# ---------------------------------------------------------------------------

func reconstructChain*(predecessorMap: Table[string, string]; target: string): seq[string] =
  ## Replay the BFS path from a seed to `target` using the predecessor map.
  ## Returns the chain [seed, ..., target] in forward order.
  var chain: seq[string] = @[]
  var current = target
  while current != "":
    chain.add(current)
    current = predecessorMap.getOrDefault(current, "")
  chain.reverse()
  chain

# ---------------------------------------------------------------------------
# Fail-closed trigger detection
# ---------------------------------------------------------------------------

func detectFailClosedTriggers*(inputs: SelectorInputs): tuple[triggered: bool; reasons: seq[string]; status: SelectionStatus] =
  ## Check all fail-closed triggers. Returns (triggered, reasons, status).
  ## Trigger 1: any unresolved edge in graph forces FALLBACK (conservative reading
  ## of contract sentence 2 — reachability through unresolved targets is unknowable).
  ## Trigger 2: builderVersion empty or stale.
  ## Trigger 3: a changedSymbolSeed not in universe and not in the graph.
  ## Trigger 4: policyDigest empty (toolchain/policy digest mismatch signal).
  ## Input malformation → ssError.

  var reasons: seq[string] = @[]

  # Input malformation checks → ssError
  if inputs.universe.len > 0 and inputs.graph.unresolvedEdges.len == 0 and inputs.symbolDeps.len == 0:
    # Empty graph (no edges) with non-empty universe is malformed — we cannot reason
    # about symbol reachability.
    return (triggered: true, reasons: @["malformed input: non-empty universe with empty dependency graph"], status: ssError)

  if inputs.universe.len == 0:
    # Empty universe is malformed — nothing to select.
    return (triggered: true, reasons: @["malformed input: empty universe"], status: ssError)

  if inputs.changeSet.baseCommit.len == 0 or inputs.changeSet.headCommit.len == 0:
    return (triggered: true, reasons: @["malformed input: missing baseCommit or headCommit in CanonicalChangeSet"], status: ssError)

  # Trigger 1: unresolved edges
  if inputs.graph.unresolvedEdges.len > 0:
    reasons.add("unresolved edges present in graph: reachability through unresolved targets is unknowable; conservative FALLBACK (contract sentence 2)")

  # Trigger 2: builderVersion empty or stale
  if inputs.graph.builderVersion.len == 0:
    reasons.add("graph builderVersion is empty: construction metadata missing or stale")

  # Trigger 3: changedSymbolSeed not in universe and not in the graph
  var universeSet = initHashSet[string]()
  for sym in inputs.universe:
    universeSet.incl(sym)

  var graphNodeSet = initHashSet[string]()
  # Build graph node set from symbolDeps keys and values
  for sym in inputs.symbolDeps.keys:
    graphNodeSet.incl(sym)
  for deps in inputs.symbolDeps.values:
    for dep in deps:
      graphNodeSet.incl(dep)

  for seed in inputs.changedSymbolSeeds:
    if seed notin universeSet and seed notin graphNodeSet:
      let msg = "changedSymbolSeed '" & seed & "' is not in universe and not in graph: unknown symbol"
      reasons.add(msg)

  # Trigger 4: policy digest mismatch signal (empty policyDigest)
  if inputs.policyDigest.len == 0:
    reasons.add("policyDigest is empty: toolchain/policy digest mismatch signal")

  if reasons.len > 0:
    return (triggered: true, reasons: reasons, status: ssFallbackRequired)

  return (triggered: false, reasons: @[], status: ssValid)

# ---------------------------------------------------------------------------
# computeSelection — main entry point
# ---------------------------------------------------------------------------

func computeSelection*(inputs: SelectorInputs): SelectionOutcome {.raises: [].} =
  ## Deterministic selection: seeds → upward BFS → intersect with universe.
  ## Produces a SelectionDerivation (derivation certificate) and ExecutionPlan.
  ## Fail-closed: any trigger forces FALLBACK_REQUIRED or ERROR.

  # Step 1: Detect fail-closed triggers
  let (triggered, triggerReasons, triggerStatus) = detectFailClosedTriggers(inputs)

  # Step 2: Build derivation inputs (digest-only)
  let derivationInputs = buildDerivationInputs(inputs)

  # Step 3: Compute BFS closure
  var universeSet = initHashSet[string]()
  for sym in inputs.universe:
    universeSet.incl(sym)
  let closureResult = computeClosure(inputs.changedSymbolSeeds, inputs.symbolDependents, universeSet)

  # Step 4: Build ProofOfSelection entries
  var selectedProofs: seq[ProofOfSelection] = @[]
  for sym in closureResult.selected:
    let reasonKind = if sym in inputs.changedSymbolSeeds: rkDeltaChanged
                     else: rkDependencyChanged
    let chain = reconstructChain(closureResult.predecessorMap, sym)
    selectedProofs.add(ProofOfSelection(
      unitId: sym,
      reasonKind: reasonKind,
      predecessorChain: chain))

  # Sort selected proofs deterministically
  selectedProofs.sort(proc(a, b: ProofOfSelection): int = cmp(a.unitId, b.unitId))

  # Step 5: Build excluded entries
  var excludedEntries: seq[(string, string)] = @[]
  for sym in closureResult.excluded:
    excludedEntries.add((sym, "not reachable from changed seeds via symbolDependents"))
  excludedEntries.sort(proc(a, b: (string, string)): int =
    let c = cmp(a[0], b[0])
    if c != 0: return c
    cmp(a[1], b[1]))

  # Step 6: Determine status and fallback reason
  var status = triggerStatus
  var fallbackReason = ""
  if triggered:
    fallbackReason = triggerReasons.join("; ")

  # Step 7: Build SelectionDerivation (without witnessDigest first)
  var derivation = SelectionDerivation(
    inputDigests: derivationInputs,
    status: status,
    selected: selectedProofs,
    excluded: excludedEntries,
    fallbackReason: fallbackReason,
    witnessDigest: "")

  # Step 8: Compute witnessDigest (self-referential: digest excludes witnessDigest field)
  let witnessDigest = computeSelectionDerivationDigest(derivation)
  derivation.witnessDigest = witnessDigest

  # Step 9: Build ExecutionPlan
  let mode = if status == ssValid: umSelected
             else: umFull
  let policy = RequestPolicy(budgetCap: 0, fallbackOn: {})
  let derived = deriveRequests(closureResult.selected, policy)
  let plan = makeExecutionPlan(derivation, mode, closureResult.selected, derived.requests)

  SelectionOutcome(derivation: derivation, plan: plan)

{.pop.}