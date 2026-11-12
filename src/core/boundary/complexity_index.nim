import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
from std/tables import Table, `[]=`, `[]`, getOrDefault, initTable
import ../../core/trusted/axiom_pragmas
import core/parsers/pnode_nav
import core/types/results
import core/utils/io_utils
import std/[os]
import std/options
import std/sets
import std/strutils
import compiler/ast
# ---------------------------------------------------------------------------
# TypeRegistry (inlined from type_registry.nim)
# ---------------------------------------------------------------------------

type
  TypeRegistry* = object
    table: Table[string, int]  ## typeName → fieldCount
## Create an empty TypeRegistry.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func initTypeRegistry*(): TypeRegistry {.raises: [].} =
  result.table = initTable[string, int]()

## Lookup a key in the registry. Returns `default` if not found.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func get*(registry: TypeRegistry; key: string; default: int): int {.raises: [].} =
  registry.table.getOrDefault(key, default)

## Set a key in the registry (mutable, only used internally).
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func setFieldCount*(registry: var TypeRegistry; typeName: string; count: int) {.raises: [].} =
  registry.table[typeName] = count

# ---------------------------------------------------------------------------
# Canonicalization: strip generics, modifiers, pointer prefixes
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func canonicalizeTypeName*(typ: string): string {.raises: [].} =
  ## Strip `var`, `ref`, `ptr`, `sink`, `out`, `lent` modifiers and
  ## generic parameters (`[...]`) to extract the base type name.
  var t = typ.strip()
  while true:
    if t.startsWith("var "): t = t[4..^1].strip()
    elif t.startsWith("ref "): t = t[4..^1].strip()
    elif t.startsWith("ptr "): t = t[4..^1].strip()
    elif t.startsWith("out "): t = t[4..^1].strip()
    elif t.startsWith("lent "): t = t[5..^1].strip()
    elif t.startsWith("sink "): t = t[5..^1].strip()
    else: break
  let bracketIdx = t.find('[')
  if bracketIdx > 0:
    t = t[0 ..< bracketIdx].strip()
  result = t

# ---------------------------------------------------------------------------
# Heuristic Field Weight (Expansion Prediction)
# Phase 0 data: 934 attempted functions, 717 with params, 155 unique types.
# ---------------------------------------------------------------------------

## Known Nim stdlib types with conservative field-count estimates.
const KnownStdlibTypes: array[0..10, (string, int)] = [
  ("table", 2),
  ("orderedtable", 2),
  ("hashset", 2),
  ("orderedset", 2),
  ("option", 1),
  ("result", 2),
  ("seq", 1),
  ("array", 1),
  ("openarray", 1),
  ("string", 1),
  ("bool", 1),
]

## Data-derived weights from Phase 0 analysis (high-frequency custom types).
## Types appearing 10+ times in attempted functions, all with 0% verification rate.
## Weights reflect structural complexity inferred from type semantics.
const DataDerivedWeights: array[0..3, (string, int)] = [
  ("jsonnode", 4),     ## 85 uses — variant type (JNull, JBool, JInt, JFloat, JString, JArray, JObject)
  ("xmlnode", 3),       ## 21 uses — tree node with children and attributes
  ("sorterstate", 4),   ## 13 uses — complex state object
  ("symsexpr", 3),      ## 11 uses — symbolic expression with operator + operands
]

## Name-suffix heuristics for types not in registry or known tables.
## Weights derived from structural complexity patterns in Axiom codebase.
## Tier 5 (large state objects, UI containers, dense contexts):
##   state, context, display — 10+ fields typical, guaranteed isComplexType hit.
## Tier 4 (moderate complexity, domain aggregates, I/O wrappers):
##   config, manager, registry, payload, event, view, store, handler
const SuffixHeuristics: array[0..10, (string, int)] = [
  ("state", 5),
  ("context", 5),
  ("display", 5),
  ("config", 4),
  ("manager", 4),
  ("registry", 4),
  ("payload", 4),
  ("event", 4),
  ("view", 4),
  ("store", 4),
  ("handler", 4),
]

## Known Nim stdlib types with conservative field-count estimates.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func heuristicFieldWeight*(typeName: string): int {.raises: [], axiom: ["(assert (and (= (str.len canon) 0) (= name canon) 0 weight 1 (=> (= (str.len canon) 0) (= result 0)) (=> (= name canon) (= result weight))))", "canon.length = 0 ∧ name = canon ∧ 0 ∧ weight ∧ 1 ∧ canon.length = 0 → result = 0 ∧ name = canon → result weight"].} =
  ## Return an estimated field count for a type based on name heuristics.
  ## Used as fallback when the type is not found in the TypeRegistry.
  ##
  ## Weights derived from Phase 0 data analysis:
  ##   - Primitives (int, string, bool, float, char): weight 1
  ##   - Collections (seq, array, openarray): weight 1
  ##   - Containers (Table, Option, Result, HashSet): weight 2
  ##   - Known complex types (JsonNode, PNode, SorterState): weight 3-4
  ##   - Name-suffix heuristics: weight 4-5 (tier 5: state/context/display, tier 4: config/manager/registry/payload/event/view/store/handler)
  let canon = canonicalizeTypeName(typeName).toLowerAscii()
  if canon.len == 0:
    return 0

  # 1. Check known stdlib types
  for (name, weight) in KnownStdlibTypes:
    if name == canon:
      return weight

  # 2. Check data-derived weights (high-frequency custom types)
  for (name, weight) in DataDerivedWeights:
    if name == canon:
      return weight

  # 3. Primitives — return 1 (token-level, no internal structure)
  if canon in ["int", "integer", "float", "float64", "float32",
               "char", "byte", "cint", "cstring", "csize",
               "pointer", "void", "natural", "positive",
               "uint", "uint8", "uint16", "uint32", "uint64",
               "int8", "int16", "int32", "int64"]:
    return 1

  # 4. Enum types — return 1 (discrete, no fields)
  if canon in ["bool", "complexitycategory", "inferencestrategy",
               "nodekind", "boundarykind", "gateaction"]:
    return 1

  # 5. Name-suffix heuristics
  for (suffix, weight) in SuffixHeuristics:
    if canon.endsWith(suffix):
      return weight

  # 6. Fallback: generic object → conservative estimate
  3

# ---------------------------------------------------------------------------
# Lookup Type Fields (registry → heuristic fallback)
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func lookupTypeFields*(registry: TypeRegistry; typeName: string): int {.raises: [].} =
  ## Return the number of fields for a given type name.
  ## Priority: 1) TypeRegistry  2) heuristicFieldWeight.
  let canon = canonicalizeTypeName(typeName)
  let registryResult = registry.table.getOrDefault(canon, -1)
  if registryResult >= 0:
    return registryResult
  # Fallback to heuristic for types not in registry
  result = heuristicFieldWeight(typeName)

# ---------------------------------------------------------------------------
# Complexity Gate
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isComplexType*(registry: TypeRegistry; typeName: string; threshold: int = 4): bool {.raises: [].} =
  ## Return true if the type has field count >= threshold.
  ## Used by the Final Guard: if any parameter type is complex AND ACI < 30
  ## AND no @axiom-hint exists, trigger Conservative Mode.
  lookupTypeFields(registry, typeName) >= threshold

# ---------------------------------------------------------------------------
# Build Type Registry (file I/O)
# ---------------------------------------------------------------------------

{.pop.}  # pop noSideEffect — buildTypeRegistry is physically impure

## Build Type Registry.
## Physically impure (file I/O) — must be `proc` per GUARDIAN §0.146.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc buildTypeRegistry*(sourceRoot: string): TypeRegistry {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Scan all .nim files in the source tree and build a registry
  ## mapping each `type Xxx = ref object` definition to its field count.
  result = initTypeRegistry()
  try:
    for file in walkDirRec(sourceRoot, yieldFilter = {pcFile}):
      if not file.endsWith(".nim"):
        continue
      let readRes = readFileOpt(file)
      if readRes.isErr: continue
      let content = readRes.get
      var inObjectType = false
      var typeName = ""
      var fieldCount = 0
      for line in content.splitLines():
        let stripped = line.strip()
        # Detect type definition start
        if "= ref object" in stripped or "= object" in stripped:
          let parts = stripped.split({' ', '='}, maxsplit = 2)
          if parts.len >= 1:
            typeName = parts[0].strip().replace("*", "")
            inObjectType = true
            fieldCount = 0
          continue
        # Count fields (lines with `name: type` pattern)
        if inObjectType and stripped.len > 0:
          if ":" in stripped and not stripped.startsWith("#") and
             not stripped.startsWith("type ") and not stripped.startsWith("func ") and
             not stripped.startsWith("proc ") and not stripped.startsWith("let ") and
             not stripped.startsWith("var ") and not stripped.startsWith("const "):
            # Check if this is a field declaration (has colon, not a keyword)
            let colonIdx = stripped.find(':')
            if colonIdx > 0:
              let beforeColon = stripped[0..<colonIdx].strip()
              if beforeColon.len > 0 and not beforeColon.contains(" "):
                inc fieldCount
          else:
            # End of object definition
            if stripped.startsWith("func ") or stripped.startsWith("proc ") or
               stripped.startsWith("type ") or stripped == "" or
               stripped.startsWith("let ") or stripped.startsWith("var ") or
               stripped.startsWith("const "):
              if inObjectType and typeName.len > 0:
                setFieldCount(result, typeName, fieldCount)
              inObjectType = false
  except CatchableError:
    discard # axiom:best-effort(partial registry; types missing use heuristic fallback)

{.push noSideEffect.}  # resume noSideEffect for pure functions

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------
type
  ComplexityCategory* = enum
    ccSimple    ## ACI < 10: fast-track
    ccMedium    ## ACI 10-30: standard
    ccComplex   ## ACI 30-70: extended timeout
    ccCritical  ## ACI > 70: block pipeline, require refactoring

  ConservativeTrigger* = enum
    ctNone              ## No conservative trigger
    ctComplexTypeNoHint ## Complex type detected, ACI < 30, no @axiom-hint
    ctCriticalACI        ## ACI >= 70 (ccCritical) — existing hard gate

  AxiomComplexity* = object
    cyclomatic*: int   ## Cyclomatic complexity (control-flow branches)
    cognitive*: int     ## Cognitive complexity (nesting-weighted)
    coupling*: int      ## SRP coupling (unique external symbols)
    dataDimension*: int ## Wave V (D-Factor): sum of parameter fields
    total*: int         ## ACI = cyclo + cog + coupling(cap10) + dataDim
    category*: ComplexityCategory
    conservativeTrigger*: ConservativeTrigger  ## Wave X: Final Guard
# ---------------------------------------------------------------------------
# Cyclomatic Complexity (M)
# ---------------------------------------------------------------------------

const controlFlowKinds: set[TNodeKind] = {nkElifBranch, nkOfBranch, nkExceptBranch,
  nkWhileStmt, nkForStmt}
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func computeCyclomaticComplexity*(fnNode: PNode): int {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Count control-flow branch points (McCabe metric).
  ## Base is 1 (single execution path); each branch point adds 1.
  if fnNode.isNil or not isPNodeElement(fnNode):
    return 1
  result = 1
  for k in controlFlowKinds:
    let nodes = findNodesP(fnNode, {k})
    result += nodes.len

# ---------------------------------------------------------------------------
# Cognitive Complexity (C)
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func computeCognitiveComplexity*(fnNode: PNode): int {.raises: [].} =
  ## Nesting-weighted complexity. Each nesting level multiplies the
  ## branch weight, modelling the mental load of deep control-flow.
  if fnNode.isNil or not isPNodeElement(fnNode):
    return 0

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
  func scan(node: PNode; depth: int; counter: var int) {.raises: [].} =
    if node.isNil or not isPNodeElement(node):
      return
    case node.kind
    of nkIfStmt, nkElifBranch, nkOfBranch, nkExceptBranch, nkWhileStmt, nkForStmt, nkCaseStmt, nkTryStmt:
      counter += 1 + depth
    else:
      discard  # axiom:best-effort(switch else: unhandled AST tag, intentional no-op)
    for child in node:
      const nestingKinds: set[TNodeKind] = {nkIfStmt, nkForStmt, nkWhileStmt, nkCaseStmt, nkTryStmt}
      let nextDepth = if node.kind in nestingKinds: depth + 1 else: depth
      scan(child, nextDepth, counter)

  scan(fnNode, 0, result)

# ---------------------------------------------------------------------------
# SRP Coupling Index (S)
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func computeCouplingIndex*(fnNode: PNode): int {.raises: [], axiom: ["(assert (and (= (option.isSome funcOpt) true) (> (str.len idents) 0) (= (option.isSome rightOpt) true) (= (str.len field) 0) (> (str.len field) 0) (= result (str.len symbols)) 0))", "funcOpt.isSome = true ∧ idents.length > 0 ∧ rightOpt.isSome = true ∧ field.length = 0 ∧ field.length > 0 ∧ result = symbols.length ∧ 0"].} =
  ## Count unique external symbols accessed via call/dot_expression.
  ## High coupling indicates multiple responsibilities.
  if fnNode.isNil or not isPNodeElement(fnNode):
    return 0
  var symbols: HashSet[string]
  const builtinNames = ["assert", "doAssert", "discard", "return",
      "len", "high", "low", "abs", "min", "max", "ord", "chr",
      "inc", "dec", "add", "new", "init"]
  # Count call targets
  for callNode in findNodesP(fnNode, {nkCall}):
    var name = ""
    let funcOpt = nodeFieldP(callNode, "function")
    if funcOpt.isSome:
      name = nodeText(funcOpt.get())
    else:
      # Fallback: find first identifier child (works with flat XML)
      let idents = findNodesP(callNode, {nkIdent, nkSym})
      if idents.len > 0:
        name = nodeText(idents[0])
    if name.len > 0 and name notin builtinNames:
      symbols.incl(name)
  # Count dot_expression targets (field access)
  for dotNode in findNodesP(fnNode, {nkDotExpr}):
    var field = ""
    let rightOpt = nodeFieldP(dotNode, "right")
    if rightOpt.isSome:
      let rightNode = rightOpt.get()
      # Get the identifier text from the right node
      let idents = findNodesP(rightNode, {nkIdent, nkSym})
      if idents.len > 0:
        field = nodeText(idents[0])
      if field.len == 0:
        field = nodeText(rightNode)
    if field.len > 0:
      symbols.incl(field)
  result = symbols.len

# ---------------------------------------------------------------------------
# ACI Assembly
# ---------------------------------------------------------------------------

## Wave X Final Guard: check if any parameter type is complex.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func hasComplexParamType*(fnNode: PNode; registry: TypeRegistry; threshold: int = 4): bool {.raises: [].} =
  ## Scan parameter types and return true if any is structurally complex
  ## (field count >= threshold). Used by Final Guard.
  for paramList in findNodesP(fnNode, {nkIdentDefs}):
    for paramDecl in findNodesP(paramList, {nkIdentDefs}):
      let typeNode = findFirstNodeP(paramDecl, {nkExprColonExpr})
      if typeNode.isSome:
        let typeName = nodeText(typeNode.get()).strip()
        if isComplexType(registry, typeName, threshold):
          return true
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func computeAxiomComplexityIndex*(fnNode: PNode; registry: TypeRegistry = initTypeRegistry();
    fileContext: string = ""): AxiomComplexity {.raises: [].} =
  ## Compute the full ACI from a function AST node.
  ##
  ## **Wave X Final Guard**: if ACI < 30 AND a parameter type is complex
  ## (>= 4 fields) AND no @axiom-hint exists in fileContext, sets
  ## `conservativeTrigger = ctComplexTypeNoHint`. Callers should respond
  ## by increasing proof timeout, enforcing hint requirement, or blocking.
  if fnNode.isNil or not isPNodeElement(fnNode):
    return AxiomComplexity(total: 0, category: ccSimple, conservativeTrigger: ctNone)
  result.cyclomatic = computeCyclomaticComplexity(fnNode)
  result.cognitive = computeCognitiveComplexity(fnNode)
  result.coupling = computeCouplingIndex(fnNode)
  ## Wave W (Deep D-Factor): count ALL parameter declarations recursively.
  ## Wave X (SAC): lookup type field counts from registry (with heuristic fallback).
  var fieldCount = 0
  for paramList in findNodesP(fnNode, {nkIdentDefs}):
    for paramDecl in findNodesP(paramList, {nkIdentDefs}):
      inc fieldCount
      ## Lookup type name in registry for deep field count
      let typeNode = findFirstNodeP(paramDecl, {nkExprColonExpr})
      if typeNode.isSome:
        let typeName = nodeText(typeNode.get()).strip()
        let deepFields = lookupTypeFields(registry, typeName)
        if deepFields > 0:
          fieldCount += deepFields
  result.dataDimension = fieldCount
  # Cap coupling contribution at 10
  let cappedCoupling = min(result.coupling, 10)
  result.total = result.cyclomatic + result.cognitive + cappedCoupling + result.dataDimension
  result.category = case result.total
    of 0..9: ccSimple
    of 10..29: ccMedium
    of 30..69: ccComplex
    else: ccCritical
  ## Wave X Final Guard: Conservative Mode trigger
  result.conservativeTrigger = ctNone
  if result.category == ccCritical:
    result.conservativeTrigger = ctCriticalACI
  elif result.total < 30 and hasComplexParamType(fnNode, registry):
    if fileContext.len > 0 and "@axiom-hint:" notin fileContext:
      result.conservativeTrigger = ctComplexTypeNoHint
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isConservativeTriggered*(aci: AxiomComplexity): bool {.raises: [].} =
  ## Convenience: true if any conservative trigger is active.
  aci.conservativeTrigger != ctNone
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func aciToString*(aci: AxiomComplexity): string {.raises: [].} =
  let catStr = case aci.category
    of ccSimple: "Simple"
    of ccMedium: "Medium"
    of ccComplex: "Complex"
    of ccCritical: "Critical"
  let trigStr = case aci.conservativeTrigger
    of ctNone: ""
    of ctComplexTypeNoHint: " [!complex-no-hint]"
    of ctCriticalACI: " [CRITICAL]"
  "ACI=" & $aci.total & "(" & catStr & ")" & trigStr &
    " M=" & $aci.cyclomatic & " C=" & $aci.cognitive &
    " S=" & $aci.coupling & " D=" & $aci.dataDimension
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func aciCategoryToTimeoutMs*(category: ComplexityCategory): int {.raises: [].} =
  ## Map ACI category to adaptive Leanstral timeout in milliseconds.
  case category
  of ccSimple: 25_000  ## Wave J: 10s→25s for API RTT + model loading
  of ccMedium: 30_000
  of ccComplex: 60_000
  of ccCritical: 120_000

{.pop.}
