import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## semantic_environment.nim — WP4-j.2 Phase C+D + WP4-j.4 Evidence Ladder.
##
## Functions only (no side effects). Provides:
##   - deriveSemanticFactsFromIR: projection from IR to SemanticEnvironment
##   - deriveInstantiationFacts: witness → ladder SemanticFact (WP4-j.4)
##   - filterResolvableFacts: completeness + collision gate
##   - saveEvidenceArtifact / loadEvidenceArtifact: evidence IO
##
## v1 rule: name ambiguity only — relevance filtering is FURTHER EXTENDED
## to a scope-aware resolver in the next WP. P is accepted but unused.

import core/trusted/semantic_fact_types
import infrastructure/evidence_artifact_io
import core/trusted/axiom_ir_helpers
import core/trusted/axiom_ir
import core/trusted/binding_inventory
import std/algorithm
import std/strutils
import std/sets
import std/tables
import std/sequtils

# collectLetNames / collectLoopVarNames are provided by axiom_ir_helpers
# (shared with external_ir_materializer — infrastructure layer).

# ---------------------------------------------------------------------------
# deriveSemanticFactsFromIR — projection from IR to SemanticEnvironment
# ---------------------------------------------------------------------------

func deriveFacts(e: IRExpr; path: string; env: var SemanticEnvironment) =
  ## Recursive walk: find isCompileTime=true irLet with irLit value.
  ## Non-literal compile-time bindings become boundary records.
  if e == nil: return
  case e.kind
  of irLet:
    if e.isCompileTime and e.letVal != nil and e.letVal.kind == irLit:
      let varType = if e.letVal.typ != nil: e.letVal.typ else: irTypeBitVec64()
      let proposition = IRExpr(
        kind: irBinOp, binOp: boEq,
        binLhs: IRExpr(kind: irVar, varName: e.letName, varType: varType, typ: varType),
        binRhs: IRExpr(kind: irLit, litVal: e.letVal.litVal,
                       litU64: e.letVal.litU64, typ: irTypeBitVec64()),
        typ: irTypeBool())
      env.facts.add(SemanticFact(
        id: e.letName & "@" & path,
        proposition: proposition,
        provenance: FactProvenance(
          origin: foCompileTimeBinding,
          occurrenceRef: path,
          sourceRef: "")))
    elif e.isCompileTime:
      env.boundaryRecords.add(BoundaryRecord(
        symbol: e.letName, reason: "value-not-literal"))
    deriveFacts(e.letVal, path & "/letVal", env)
    deriveFacts(e.letBody, path & "/letBody", env)
  of irBinOp:
    deriveFacts(e.binLhs, path & "/binLhs", env)
    deriveFacts(e.binRhs, path & "/binRhs", env)
  of irUnaryOp:
    deriveFacts(e.unaryArg, path & "/unaryArg", env)
  of irIf:
    deriveFacts(e.ifCond, path & "/ifCond", env)
    deriveFacts(e.ifThen, path & "/ifThen", env)
    deriveFacts(e.ifElse, path & "/ifElse", env)
  of irCase:
    deriveFacts(e.caseScrutinee, path & "/caseScrutinee", env)
    for i, br in e.caseBranches:
      deriveFacts(br.body, path & "/caseBranch[" & $i & "]", env)
    if e.caseDefault != nil:
      deriveFacts(e.caseDefault, path & "/caseDefault", env)
  of irCall:
    for i, a in e.callArgs:
      deriveFacts(a, path & "/callArg[" & $i & "]", env)
  of irRecCall:
    for i, a in e.recArgs:
      deriveFacts(a, path & "/recArg[" & $i & "]", env)
  of irLoop:
    for i, init in e.loopInits:
      deriveFacts(init, path & "/loopInit[" & $i & "]", env)
    deriveFacts(e.loopCond, path & "/loopCond", env)
    if e.loopStep != nil:
      deriveFacts(e.loopStep, path & "/loopStep", env)
    deriveFacts(e.loopBody, path & "/loopBody", env)
    for i, inv in e.loopInvariants:
      deriveFacts(inv, path & "/loopInvariant[" & $i & "]", env)
    if e.loopVariant != nil:
      deriveFacts(e.loopVariant, path & "/loopVariant", env)
  of irCast:
    deriveFacts(e.castExpr, path & "/castExpr", env)
  of irLit, irFloatLit, irVar, irStringLit:
    discard

func deriveSemanticFactsFromIR*(funcDef: IRFuncDef): SemanticEnvironment =
  ## Walk funcDef.body and extract compile-time literal bindings
  ## as SemanticFact entries. Facts with non-literal values are
  ## recorded as boundary records. Returns empty environment if
  ## no compile-time bindings exist.
  deriveFacts(funcDef.body, "body", result)

# ---------------------------------------------------------------------------
# WP4-j.4 — deriveInstantiationFacts: witness → ladder SemanticFact
# ---------------------------------------------------------------------------
# Projection rule: witness consumes the InstantiationWitness (not the AST).
# Emission rule: a SemanticFact is emitted only when its VALUE was observed.
# Neither the witness nor the IR carries the target's type widths — `IRType`'s
# `irtBitVec64` is a fixed 64-bit machine integer with no width field — so a
# `sizeof(T) * 8` binding yields the shape and nothing else.

func observedCompileTimeLiteral(e: IRExpr): (string, int64, uint64) =
  ## Walk funcDef.body for the first compile-time `irLet` bound to an `irLit`,
  ## returning that binding's name and the literal it holds — the literal in
  ## its two-part form (nonzero third element ⟺ u64-domain representation).
  ##
  ## Fail-closed: a binding whose value is a `sizeof(...) * 8` expression, or
  ## any other non-literal, returns ("", 0, 0). Writing a number against it
  ## would be an assumption about the target, not evidence observed from it.
  if e == nil: return ("", 0, 0)
  case e.kind
  of irLet:
    if e.isCompileTime and e.letVal != nil and e.letVal.kind == irLit:
      return (e.letName, e.letVal.litVal, e.letVal.litU64)
    let fromVal = observedCompileTimeLiteral(e.letVal)
    if fromVal[0].len > 0: return fromVal
    observedCompileTimeLiteral(e.letBody)
  of irBinOp:
    let fromLhs = observedCompileTimeLiteral(e.binLhs)
    if fromLhs[0].len > 0: return fromLhs
    observedCompileTimeLiteral(e.binRhs)
  of irUnaryOp:
    observedCompileTimeLiteral(e.unaryArg)
  of irIf:
    let fromCond = observedCompileTimeLiteral(e.ifCond)
    if fromCond[0].len > 0: return fromCond
    let fromThen = observedCompileTimeLiteral(e.ifThen)
    if fromThen[0].len > 0: return fromThen
    observedCompileTimeLiteral(e.ifElse)
  of irCase:
    let fromScrut = observedCompileTimeLiteral(e.caseScrutinee)
    if fromScrut[0].len > 0: return fromScrut
    for br in e.caseBranches:
      let fromBranch = observedCompileTimeLiteral(br.body)
      if fromBranch[0].len > 0: return fromBranch
    observedCompileTimeLiteral(e.caseDefault)
  of irCall:
    for a in e.callArgs:
      let fromArg = observedCompileTimeLiteral(a)
      if fromArg[0].len > 0: return fromArg
    ("", 0, 0)
  of irRecCall:
    for a in e.recArgs:
      let fromArg = observedCompileTimeLiteral(a)
      if fromArg[0].len > 0: return fromArg
    ("", 0, 0)
  of irLoop:
    for init in e.loopInits:
      let fromInit = observedCompileTimeLiteral(init)
      if fromInit[0].len > 0: return fromInit
    let fromCond = observedCompileTimeLiteral(e.loopCond)
    if fromCond[0].len > 0: return fromCond
    let fromStep = observedCompileTimeLiteral(e.loopStep)
    if fromStep[0].len > 0: return fromStep
    let fromBody = observedCompileTimeLiteral(e.loopBody)
    if fromBody[0].len > 0: return fromBody
    for inv in e.loopInvariants:
      let fromInv = observedCompileTimeLiteral(inv)
      if fromInv[0].len > 0: return fromInv
    observedCompileTimeLiteral(e.loopVariant)
  of irCast:
    observedCompileTimeLiteral(e.castExpr)
  of irLit, irFloatLit, irVar, irStringLit:
    ("", 0, 0)

func deriveInstantiationFacts*(witness: InstantiationWitness;
    funcDef: IRFuncDef): seq[SemanticFact] =
  ## Ladder projection: witness → SemanticFact(s) injected into E_safe.
  ##
  ## Empty result when positional correspondence is unknown, or when no value
  ## was observed. The concrete type argument is a NAME (`BiggestUInt`,
  ## `uint32`, …); nothing in the IR fixes its width, so no width is asserted
  ## here. A `sizeof(T) * 8` binding therefore produces no fact at all — its
  ## value is absent from every artifact Axiom holds, and the boundary it
  ## represents is already reported as `value-not-literal` by
  ## `deriveSemanticFactsFromIR` on the same body.
  if witness.positionalRelation.len == 0:
    return @[]

  let observed = observedCompileTimeLiteral(funcDef.body)
  if observed[0].len == 0:
    return @[]

  let letName = observed[0]
  let path = "instantiation/" & witness.calleeSymbol
  let boundLit = if observed[2] != 0'u64: irLitU64(observed[2])
                 else: IRExpr(kind: irLit, litVal: observed[1],
                              typ: irTypeBitVec64())
  @[SemanticFact(
    id: letName & "@" & path,
    proposition: IRExpr(
      kind: irBinOp, binOp: boEq,
      binLhs: IRExpr(kind: irVar, varName: letName,
                     varType: irTypeBitVec64(), typ: irTypeBitVec64()),
      binRhs: boundLit,
      typ: irTypeBool()),
    provenance: FactProvenance(
      origin: foTemplateInstantiation,
      occurrenceRef: witness.occurrenceRef,
      sourceRef: witness.callSite))]

# ---------------------------------------------------------------------------
# filterResolvableFacts — completeness + collision gate
# ---------------------------------------------------------------------------

func filterResolvableFacts*(completeness: CompletenessEvidence, funcDef: IRFuncDef,
                             P: IRExpr, E_all: SemanticEnvironment): SemanticEnvironment =
  ## Gate (v1): name-mismatch only — relevance filtering is deferred.
  ## P is accepted as a parameter for future scope-aware resolver use;
  ## v1 does not reference P in any filtering logic.

  # ── Gate 1: completeness evidence ──────────────────────────
  if not (completeness.translationLossFree and completeness.bindingUniverseComplete):
    result.boundaryRecords.add(BoundaryRecord(
      symbol: "", reason: "completeness unproven"))
    return result  # reject ALL facts — empty environment

  # ── Gate 2: collision universe — per-name ambiguity ────────
  let letNames = collectLetNames(funcDef.body)
  let paramNames = funcDef.params.mapIt(it.name)
  let loopVarNames = collectLoopVarNames(funcDef)

  var nameCount: Table[string, int]
  for n in letNames:       nameCount[n] = nameCount.getOrDefault(n) + 1
  for n in paramNames:     nameCount[n] = nameCount.getOrDefault(n) + 1
  for n in loopVarNames:   nameCount[n] = nameCount.getOrDefault(n) + 1

  # Track which names have already been flagged as ambiguous.
  var ambiguousFlagged: HashSet[string]

  # Filter: keep facts whose name has count < 2 in the collision universe.
  for fact in E_all.facts:
    # Extract variable name from proposition: irBinOp(boEq, irVar(name,_), irLit(_))
    if fact.proposition.kind == irBinOp and fact.proposition.binOp == boEq:
      let lhs = fact.proposition.binLhs
      if lhs.kind == irVar:
        let name = lhs.varName
        let cnt = nameCount.getOrDefault(name)
        if cnt < 2:
          result.facts.add(fact)
        elif cnt >= 2 and not ambiguousFlagged.contains(name):
          ambiguousFlagged.incl(name)
          result.boundaryRecords.add(BoundaryRecord(
            symbol: name, reason: "ambiguous-name"))

  # ── (3) Sort by name ───────────────────────────────────────
  result.facts.sort(proc(a, b: SemanticFact): int =
    cmp(a.proposition.binLhs.varName, b.proposition.binLhs.varName))

  # Preserve original boundary records from E_all
  for br in E_all.boundaryRecords:
    result.boundaryRecords.add(br)

# ---------------------------------------------------------------------------
# Re-export evidence artifact IO (convenience — same module surface)
# ---------------------------------------------------------------------------

export evidence_artifact_io

{.pop.}
