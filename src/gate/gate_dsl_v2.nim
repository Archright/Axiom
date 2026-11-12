## Gate DSL v2 — Nim-Native Gate Definition DSL
##
## Replaces ``gate_manifest.json`` with compile-time Nim const definitions.
## Each gate is defined using the ``gate`` template which produces a ``GateDef``.
## Compile-time validation ensures:
##   - No duplicate gate IDs
##   - Critical gates are marked ``gcHigh``
##   - DAG dependencies reference existing gate IDs
##   - Tier values are in valid range
##
## Usage:
##   import gate_dsl_v2
##   const MyGates = @[gate("my-gate", "My Gate", glFunctional, 1, gwMedium,
##                         {gsPreCommit}, "bin/my_gate", false, @[], gcMedium)]

import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

import std/[macros, tables, strutils]
import gate_types

type
  GateCriticality* = enum
    gcHigh = "high"      ## Never auto-disable (gate-self-check, sentinel, etc.)
    gcMedium = "medium"  ## Conditional auto-disable
    gcLow = "low"        ## Auto-disable eligible

  GateDef* = object
    id*: string
    name*: string
    layer*: GateLayer
    tier*: range[1..2]
    weight*: GateWeight
    stages*: set[GateStage]
    entry*: string           ## Runner path or bin path
    filesPattern*: string    ## File pattern for incremental mode
    passFilenames*: bool
    after*: seq[string]      ## DAG dependencies (other gate IDs)
    depsDirs*: seq[string]
    argsTemplate*: seq[string]
    envVars*: seq[(string, string)]
    criticality*: GateCriticality
    inputs*: seq[string]       ## Declared input paths (for compile-time collision detection)
    outputs*: seq[string]      ## Declared output paths (for compile-time collision detection)
    envDependencies*: seq[EnvDependency]  ## External state dependencies for context-aware cache keys
    hermeticity*: GateHermeticity          ## Cache policy: ghHermetic or ghTransient

# ─── Gate Definition Template ────────────────────────────────────────────────

template gate*(id: string, name: string, layer: GateLayer, tier: static[int],
               weight: GateWeight, stages: set[GateStage], entry: string,
               passFilenames: bool, after: seq[string], criticality: GateCriticality,
               filesPattern: string = "",
               depsDirs: seq[string] = @[],
               argsTemplate: seq[string] = @[],
               envVars: seq[(string, string)] = @[],
               inputs: seq[string] = @[],
               outputs: seq[string] = @[],
               envDependencies: seq[EnvDependency] = @[],
               hermeticity: GateHermeticity = ghHermetic): GateDef =
  ## Construct a GateDef with compile-time tier validation.
  GateDef(id: id, name: name, layer: layer, tier: tier, weight: weight,
          stages: stages, entry: entry, filesPattern: filesPattern,
          passFilenames: passFilenames, after: after, depsDirs: depsDirs,
          argsTemplate: argsTemplate, envVars: envVars, criticality: criticality,
          inputs: inputs, outputs: outputs, envDependencies: envDependencies,
          hermeticity: hermeticity)

# ─── Critical Gate Registry ──────────────────────────────────────────────────
# Critical gate IDs — hardcoded at compile time, agent cannot override.
# These gates MUST always run and cannot be auto-disabled.

const CriticalGateIds*: seq[string] = @[
  "gate-self-check",
  "unstaged-guard",
  "integrity-workflow",
]

# ─── Compile-Time Validation Macro ───────────────────────────────────────────

macro validateGateDefs*(gates: static[seq[GateDef]]) =
  ## Runs at compile time: validates no duplicate IDs, DAG acyclicity,
  ## critical gate marking, and tier range.
  var ids: seq[string]
  for g in gates:
    # Duplicate ID check
    if g.id in ids:
      error("Duplicate gate ID: " & g.id)
    ids.add(g.id)

    # Critical gates must be gcHigh
    if g.id in CriticalGateIds and g.criticality != gcHigh:
      error("Critical gate " & g.id & " must be gcHigh, got " & $g.criticality)

    # Tier range check (range[1..2] handles this at type level, but
    # validate explicitly for clarity)
    if g.tier < 1 or g.tier > 2:
      error("Gate " & g.id & " has invalid tier=" & $g.tier)

  # DAG dependency validation: all 'after' references must exist
  for g in gates:
    for depId in g.after:
      if depId notin ids:
        error("Gate " & g.id & " depends on non-existent gate: " & depId)

  # DAG acyclicity check (topological sort)
  # Two-pass: first initialize all gate IDs, then count dependencies.
  # Single-pass is order-dependent: if gate B depends on gate A but A
  # appears later in the sequence, the dependency is missed.
  var inDegree: Table[string, int]
  for g in gates:
    inDegree[g.id] = 0
  for g in gates:
    for depId in g.after:
      inDegree[g.id] += 1

  # Kahn's algorithm for cycle detection
  var queue: seq[string]
  var visited = 0
  for g in gates:
    if inDegree[g.id] == 0:
      queue.add(g.id)

  while queue.len > 0:
    let current = queue[0]
    queue.delete(0)
    inc visited
    for g in gates:
      if current in g.after:
        dec inDegree[g.id]
        if inDegree[g.id] == 0:
          queue.add(g.id)

  if visited != gates.len:
    error("DAG cycle detected in gate dependencies")

  # Output collision detection (Wave 7C-2)
  # If two gates declare the same output, they must have an ordering edge
  var outputOwners: Table[string, seq[string]]  # output path → gate IDs
  for g in gates:
    for outPath in g.outputs:
      if outPath notin outputOwners:
        outputOwners[outPath] = @[]
      outputOwners[outPath].add(g.id)

  for outPath, owners in outputOwners:
    if owners.len > 1:
      # Verify ordering: each pair must have an after edge
      for i in 0..<owners.len:
        for j in (i+1)..<owners.len:
          let a = owners[i]
          let b = owners[j]
          # Check if a -> b or b -> a edge exists
          var hasEdge = false
          for g in gates:
            if g.id == b and a in g.after:
              hasEdge = true
            if g.id == a and b in g.after:
              hasEdge = true
          if not hasEdge:
            error("Output collision: gates '" & a & "' and '" & b &
                  "' both declare output '" & outPath &
                  "' with no ordering edge. Add an 'after' dependency.")

macro validateEntryPointUniqueness*(gates: static[seq[GateDef]]) =
  ## Compile-time check: no two gates in the same layer share an entry point.
  var entryLayers: Table[string, set[GateLayer]]
  var entryOwners: Table[string, seq[string]]
  var entryStageSets: Table[string, seq[set[GateStage]]]
  for g in gates:
    if g.entry.len > 0:
      if g.entry notin entryLayers:
        entryLayers[g.entry] = {}
        entryOwners[g.entry] = @[]
        entryStageSets[g.entry] = @[]
      entryLayers[g.entry].incl(g.layer)
      entryOwners[g.entry].add(g.id)
      entryStageSets[g.entry].add(g.stages)
  for entry, layers in entryLayers:
    if layers.card == 1 and entryOwners[entry].len > 1:
      # Allow: different stages = intentional variant configs (e.g. external-cli-smoke vs -hard)
      var allSameStages = true
      let stageSeq = entryStageSets[entry]
      for i in 1..<stageSeq.len:
        if stageSeq[i] != stageSeq[0]:
          allSameStages = false
          break
      if allSameStages:
        error("Semantic duplicate: gates '" & entryOwners[entry].join("', '") &
              "' share entry '" & entry & "' in the same layer with same stages")

{.pop.}
