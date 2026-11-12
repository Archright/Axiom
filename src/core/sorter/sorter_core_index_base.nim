import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import std/strutils
import std/sets
import core/vault/vault_manager_spec
import core/types/hubs/sorter_node_id
import ../../core/trusted/axiom_pragmas
export sorter_node_id

type
  AxiomFormula* = distinct string

  AstResidency* = enum
    astResident,
    astReleased

  AnalysisSourceKind* = enum
    sourceDetailedAst,
    sourceVaultAxiom

  SorterNode* = object
    modulePath*: string
    functionName*: string
    nodeType*: string
    id*: SorterNodeId
    dependencyIds*: seq[SorterNodeId]
    astResidency*: AstResidency
    isStale*: bool
    refactoredSource*: string
    definitionFingerprint*: string

  VaultEntry* = object
    nodeId*: SorterNodeId
    axiom*: AxiomFormula

  VaultIntegrityBlock* = object
    nodeId*: SorterNodeId
    error*: AxiomInvalidError
    vaultPath*: string

  SorterState* = object
    nodes*: seq[SorterNode]
    vaultEntries*: seq[VaultEntry]
    vaultIntegrityBlocks*: seq[VaultIntegrityBlock]

  SorterWorkItem* = object
    nodeId*: SorterNodeId
    dependencyDepth*: int
    ownSourceKind*: AnalysisSourceKind
    usesDependencyVault*: bool
    readsDependencySource*: bool
    dependencyAxioms*: seq[AxiomFormula]

  SorterPlan* = object
    workItems*: seq[SorterWorkItem]
    blockedNodes*: seq[SorterNodeId]
    releasedAstNodes*: seq[SorterNodeId]
    staleDependencyNodes*: seq[SorterNodeId]

## Sorter Node Id.
func sorterNodeId*(raw: string): SorterNodeId {.inline, axiom: ["(assert (and ast_parse_failed_isolated (>= (str.len raw) 0)))", "ast_parse_failed_isolated ∧ raw.length ≥ 0"].} =
  SorterNodeId(raw.strip())

## Sorter Node Id String.
func sorterNodeIdString*(nodeId: SorterNodeId): string {.inline.} =
  string(nodeId)

## Node Id Equals.
func nodeIdEquals*(left: SorterNodeId; right: SorterNodeId): bool {.inline, axiom: ["(assert (and (>= depth 0) ast_parse_failed_isolated (= 1 1)))", "depth >= 0 ∧ ast_parse_failed_isolated ∧ 1 = 1"].} =
  sorterNodeIdString(left) == sorterNodeIdString(right)

func `==`*(left: SorterNodeId; right: SorterNodeId): bool {.inline.} =
  sorterNodeIdString(left) == sorterNodeIdString(right)

func `$`*(nodeId: SorterNodeId): string {.inline.} =
  sorterNodeIdString(nodeId)

## Axiom Formula.
func axiomFormula*(raw: string): AxiomFormula {.inline, axiom: ["(assert (and ast_parse_failed_isolated))", "ast_parse_failed_isolated"].} =
  AxiomFormula(raw.strip())

## Axiom Formula String.
func axiomFormulaString*(formula: AxiomFormula): string {.inline.} =
  string(formula)

## Make Vault Entry.
func makeVaultEntry*(nodeId: SorterNodeId; axiom: AxiomFormula): VaultEntry {.inline.} =
  VaultEntry(nodeId: nodeId, axiom: axiom)

## Make Sorter Node.
func makeSorterNode*(
  modulePath: string;
  functionName: string;
  nodeId: SorterNodeId;
  dependencyIds: seq[SorterNodeId];
  nodeType: string = "";
  definitionFingerprint: string = ""
): SorterNode {.inline, axiom: ["(assert (and (>= (str.len modulePath) 0) (>= (str.len functionName) 0) (>= (seq.len dependencyIds) 0) (>= (str.len nodeType) 0)))", "modulePath.length ≥ 0 ∧ functionName.length ≥ 0 ∧ dependencyIds.size ≥ 0 ∧ nodeType.length ≥ 0"].} =
  SorterNode(
    modulePath: modulePath.strip(),
    functionName: functionName.strip(),
    nodeType: nodeType,
    id: nodeId,
    dependencyIds: dependencyIds,
    astResidency: astResident,
    isStale: true,
    definitionFingerprint: definitionFingerprint
  )

## Init Sorter State.
func initSorterState*(
  nodes: seq[SorterNode];
  vaultEntries: seq[VaultEntry] = @[];
  vaultIntegrityBlocks: seq[VaultIntegrityBlock] = @[]
): SorterState {.inline.} =
  SorterState(
    nodes: nodes,
    vaultEntries: vaultEntries,
    vaultIntegrityBlocks: vaultIntegrityBlocks
  )

## Deduplicate Strings.
  ## axiom-smt: (assert (and (>= (seq.len values) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len values))) (>= (str.len (seq.nth values i)) 0))) (and (= existing value) (= seen true) (>= values 0) (>= result 0) (>= seen 0) (forall ((valuesIdx Int)) (=> (and (>= valuesIdx 0) (< valuesIdx (seq.len values))) (>= (str.len (seq.nth values valuesIdx)) 0)))))))
  ## axiom-lean: values.size ≥ 0 ∧ ∀ (i : Fin values.size), (values.get i).length ≥ 0 ∧ existing = value ∧ seen = true ∧ (values ≥ 0) ∧ (result ≥ 0) ∧ (seen ≥ 0) ∧ (∀ (valuesIdx : Fin values.size), (values.get valuesIdx).length ≥ 0)
func deduplicateStrings*(values: seq[string]): seq[string] {.axiomTryImpl.} =
  for value in values:
    var seen = false
    for existing in result:
      if existing == value:
        seen = true
        break
    if not seen:
      result.add(value)

## Contain Node Id.
  ## axiom-smt: (assert (and (>= (seq.len nodes) 0) ast_parse_failed_isolated true (>= nodes 0) true true (>= nodes 0) (>= (seq.len nodes) 0)))
  ## axiom-lean: nodes.size ≥ 0 ∧ ast_parse_failed_isolated ∧ true ∧ (nodes ≥ 0) ∧ true ∧ true ∧ (nodes ≥ 0) ∧ nodes.size ≥ 0
func containsNodeId*(nodes: seq[SorterNodeId]; nodeId: SorterNodeId): bool {.axiomTryImpl.} =
  for existing in nodes:
    if nodeIdEquals(existing, nodeId):
      return true
  false

## Deduplicate Node Ids.
  ## axiom-smt: (assert (and (>= (seq.len values) 0) (>= values 0)))
  ## axiom-lean: values.size ≥ 0 ∧ (values ≥ 0)
func deduplicateNodeIds*(values: seq[SorterNodeId]): seq[SorterNodeId] {.axiomTryImpl.} =
  var seen: HashSet[string]
  for value in values:
    let key = sorterNodeIdString(value)
    if key notin seen:
      seen.incl(key)
      result.add(value)

## Find Node Index.
  ## axiom-smt: (assert (and (>= (seq.len state_nodes) 0) (>= (seq.len state_vaultEntries) 0) (>= (seq.len state_vaultIntegrityBlocks) 0) ast_parse_failed_isolated idx))
  ## axiom-lean: state_nodes.size ≥ 0 ∧ state_vaultEntries.size ≥ 0 ∧ state_vaultIntegrityBlocks.size ≥ 0 ∧ ast_parse_failed_isolated ∧ idx
func findNodeIndex*(state: SorterState; nodeId: SorterNodeId): int {.axiomTryImpl.} =
  for idx, node in state.nodes:
    if nodeIdEquals(node.id, nodeId):
      return idx
  result = -1

  ## axiom-smt: (assert (and ast_parse_failed_isolated idx))
  ## axiom-lean: ast_parse_failed_isolated ∧ idx
func findVaultEntryIndex*(state: SorterState; nodeId: SorterNodeId): int {.axiomTryImpl.} =
  for idx, entry in state.vaultEntries:
    if nodeIdEquals(entry.nodeId, nodeId):
      return idx
  result = -1

{.pop.}
{.pop.}
