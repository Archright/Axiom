import core/trusted/layer_declaration
axiomLayer "tools"

## Selection Harness — bounded runner mirroring impact_closure_selector's
## shadow-report style for the symbol-level selector.
##
## Builds SelectionInputs from a minimal fixture (file→symbol table +
## symbol dependency graph), runs computeSelection + oracle containment,
## prints planStatus/certainty/selected/containment + witnessDigest
## verification, exits 0/2/1 under --require-certain.
##
## Usage:
##   nim c -r --hints:off tools/selection_harness.nim
##   nim c -r --hints:off tools/selection_harness.nim --require-certain

import std/[os, strutils, sequtils, tables, json, algorithm, options, parseopt, sets]
import core/types/canonical_change_set
import core/types/graph_artifact
import core/types/selection_derivation
import core/types/execution_plan
import core/topology/topology_types
import verification/selection/selection_engine
import verification/selection/soundness_oracle
import verification/selection/selection_digests

# ---------------------------------------------------------------------------
# Fixture data
# ---------------------------------------------------------------------------

proc makeFixtureChangeSet*(): CanonicalChangeSet =
  CanonicalChangeSet(
    baseCommit: "base_sha_000",
    headCommit: "head_sha_111",
    mergeBase: @["merge_sha_222"],
    canonicalDiffDigest: "diff_hash_fixture_001",
    diffInterpretationPolicy: DiffInterpretationPolicy(flags: {}))

proc makeFixtureGraph*(): GraphArtifact =
  GraphArtifact(
    structureDigest: "struct_fixture_001",
    constructionInputsDigest: "inputs_fixture_001",
    interpretationPolicyDigest: "policy_fixture_001",
    unresolvedEdges: @[],
    builderVersion: "2")

proc makeFixtureInputs*(): selection_engine.SelectorInputs =
  ## Minimal fixture: 5 symbols in universe, 2 changed seeds,
  ## BFS propagation through symbolDependents.
  ##
  ## Universe:  A, B, C, D, E
  ## Changed:   A (seed, rkDeltaChanged)
  ## Deps:      A → B depends on A, C depends on A, D depends on B
  ##            E has no deps (unreachable from A)
  ## Expected:  A, B, C, D selected; E excluded
  ##
  ## This fixture exercises: BFS propagation, predecessor chains,
  ## excluded units, and containment with the oracle.

  let changeSet = makeFixtureChangeSet()
  let graph = makeFixtureGraph()

  # symbolDeps: symbol → symbols it depends on (forward edges)
  var symbolDeps: Table[string, seq[string]]
  symbolDeps["A"] = @[]           # A has no deps
  symbolDeps["B"] = @["A"]        # B depends on A
  symbolDeps["C"] = @["A"]        # C depends on A
  symbolDeps["D"] = @["B"]        # D depends on B
  symbolDeps["E"] = @[]           # E has no deps (unreachable)

  # symbolDependents: reverse edges (for upward propagation)
  var symbolDependents: Table[string, seq[string]]
  symbolDependents["A"] = @["B", "C"]   # B and C depend on A
  symbolDependents["B"] = @["D"]        # D depends on B
  symbolDependents["C"] = @[]
  symbolDependents["D"] = @[]
  symbolDependents["E"] = @[]

  selection_engine.SelectorInputs(
    changeSet: changeSet,
    graph: graph,
    symbolDeps: symbolDeps,
    symbolDependents: symbolDependents,
    universe: @["A", "B", "C", "D", "E"],
    policyDigest: "policy_fixture_001",
    changedSymbolSeeds: @["A"])

# ---------------------------------------------------------------------------
# Oracle fixture
# ---------------------------------------------------------------------------

proc makeFixtureOracleChangedFiles*(): seq[string] =
  ## Changed files that map to the fixture symbols.
  @["src/core/vault/vault_manager_spec.nim"]

proc makeFixtureUniverse*(): seq[string] =
  @["src/core/vault/vault_manager_spec.nim::axiomSpecToJsonNode",
    "src/core/vault/vault_manager_spec.nim::hasVaultEntry",
    "src/core/sorter/sorter_core_index_table.nim::hasVaultEntry",
    "src/core/topology/topology_dependency.nim::proximityScore",
    "src/core/topology/topology_engine.nim::findTopologyMetricIndex"]

proc makeFixtureExpectedAffected*(): seq[string] =
  ## Oracle expected affected from the symbol catalog.
  ## For the changed file src/core/vault/vault_manager_spec.nim,
  ## the catalog says axiomSpecToJsonNode and hasVaultEntry are affected.
  @["src/core/vault/vault_manager_spec.nim::axiomSpecToJsonNode",
    "src/core/vault/vault_manager_spec.nim::hasVaultEntry",
    "src/core/sorter/sorter_core_index_table.nim::hasVaultEntry"]

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc main() =
  var requireCertain = false
  var showHelp = false

  var p = initOptParser(commandLineParams(),
                        shortNoVal = {'h'},
                        longNoVal = @["help", "require-certain"])
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "help", "h":
        showHelp = true
      of "require-certain":
        requireCertain = true
      else:
        echo "[selection-harness] Unknown option: " & p.key
        showHelp = true
    of cmdArgument:
      discard

  if showHelp:
    echo "Selection Harness — symbol-level selector shadow report"
    echo ""
    echo "Usage:"
    echo "  selection-harness [options]"
    echo ""
    echo "Options:"
    echo "  --require-certain   Gate on CERTAIN only (exit 0/2/1)"
    echo "  --help, -h          Show this help"
    return

  # Build inputs from fixture
  let inputs = makeFixtureInputs()

  # Run selector
  let outcome = computeSelection(inputs)
  let deriv = outcome.derivation
  let plan = outcome.plan

  # Build oracle expected affected
  let changedFiles = makeFixtureOracleChangedFiles()
  let universe = makeFixtureUniverse()
  let expectedAffected = independentReferenceAffected(changedFiles, universe)

  # Containment check
  let selectedIds = deriv.selected.mapIt(it.unitId)
  let containment = checkContainment(expectedAffected, selectedIds)

  # Witness verification
  let witnessOk = verifySelectionWitness(deriv)

  # Certainty determination (mirrors impact_closure_selector §8a)
  let certain = deriv.status == ssValid
  let certainty = if certain: "CERTAIN" else: "UNCERTAIN"
  let planStatus = $deriv.status

  # Print report
  echo ""
  echo "======================================================="
  echo "  AXIOM SELECTION HARNESS — SHADOW MODE"
  echo "======================================================="
  echo ""
  echo "  planStatus: " & planStatus & "    certainty: " & certainty
  echo "  selected: " & $deriv.selected.len & " unit(s)"
  echo "  excluded: " & $deriv.excluded.len & " unit(s)"
  echo "  fallbackReason: " & deriv.fallbackReason
  echo ""
  echo "  Selected units:"
  for ps in deriv.selected:
    let chainStr = ps.predecessorChain.join(" -> ")
    echo "    " & ps.unitId & "  reason=" & $ps.reasonKind & "  chain=[" & chainStr & "]"
  echo ""
  echo "  Excluded units:"
  for (uid, reason) in deriv.excluded:
    echo "    " & uid & "  reason=" & reason
  echo ""
  echo "  Oracle expectedAffected: " & $expectedAffected.len & " symbol(s)"
  echo "  Containment (ExpectedAffected <= Selected):"
  if containment.ok:
    echo "    OK - selector is sound for this fixture"
  else:
    echo "    MISSING - " & $containment.missing.len & " symbol(s) not selected: " & containment.missing.join(", ")
  echo ""
  echo "  Witness digest verification: " & (if witnessOk: "PASS" else: "FAIL")
  echo "  Witness digest: " & deriv.witnessDigest
  echo ""
  echo "  Plan mode: " & $plan.mode & "    selectedUnitIds: " & $plan.selectedUnitIds.len
  echo "======================================================="
  echo ""

  # Exit contract (mirrors impact_closure_selector §12)
  if not requireCertain:
    quit(0)
  if certain and containment.ok and witnessOk:
    quit(0)
  elif not certain:
    quit(2)
  else:
    quit(1)

when isMainModule:
  main()
