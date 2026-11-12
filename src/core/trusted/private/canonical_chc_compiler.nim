## Canonical CHC Compiler — official deterministic CHC representation projected from the Semantic Kernel.
## This is NOT the semantic reference (normative truth lives in the Semantic Contract / Semantic Kernel).
## Two distinct VerificationModels must never produce colliding artifacts; the artifact carries identity metadata.
##
## Deterministic guarantees:
##   - Rules are sorted by canonical key (C14).
##   - `serialize` produces byte-identical output for identical inputs.
##   - `semanticFingerprint` and `encodingConfigFingerprint` provide identity metadata.

import checksums/sha2
import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/[options, sets, tables, sequtils, strutils, algorithm]
import core/trusted/axiom_ir
import core/trusted/ir_to_smt
import core/trusted/symbol_table_types
import core/trusted/verification_model_types
import core/trusted/private/identity_core
import core/trusted/private/identity_mapping
import core/trusted/private/semantic_identity
import core/trusted/solver_invocation
import core/trusted/private/transition_formula_builder
import core/trusted/private/verification_obligations
import verification/obligation/obligation_ir

type
  CanonicalSymbol* = object
    originalName*: string
    canonicalName*: string
    scopePath*: seq[string]
    declarationOrdinal*: uint32

  CanonicalRelation* = object
    ## C14: identity is structural and explicit — never recovered by parsing
    ## a relation-name string. relationId is the canonical identity; sourceNode
    ##/targetNode/stateSignature carry the provenance back to the VM.
    relationId*: string
    relationName*: string
    sourceNode*: NodeId
    targetNode*: NodeId
    stateSignature*: seq[CanonicalSymbol]
    parameters*: seq[CanonicalSymbol]
    formula*: string

  EncodingConfig* = object
    ## C15: artifact identities are versioned. Changing `compilerSchemaVersion`
    ## invalidates all cached/matched fingerprints (no silent collision).
    compilerSchemaVersion*: uint32
    loopStrategy*: string
    arithmeticDomain*: string
    memoryModel*: string
    printCertificate*: bool

  CanonicalModel* = object
    symbols*: seq[CanonicalSymbol]
    relations*: seq[CanonicalRelation]
    encodingConfig*: EncodingConfig
    initExprs*: seq[IRExpr]
    transitions*: seq[Transition]
    obligations*: seq[Obligation]
    property*: Option[IRExpr]
    states*: seq[StateVar]
    ## Derived exit safety — the backend-agnostic obligation model carries a
    ## safety property (from `property` or semantic obligations); emitted as an
    ## `error` rule gated on `^exitGuard` exactly like the legacy encoder, so
    ## this path is NON-VACUOUS for property-carrying models (§0.9 Anti-Theater).
    exitGuardSmt*: string
    derivedSafetySmt*: Option[string]
    ## C14: deterministic, explicit, immutable mapping Semantic ↔ Canonical.
    identityMap*: SemanticToCanonicalMap
    ## Identity metadata — deterministic digests over the canonical projection and encoding config.
    semanticFingerprint*: string
    encodingConfigFingerprint*: string

  CHCAst* = object
    prelude*: string
    declarations*: seq[string]
    rules*: seq[string]
    query*: string
    checkSat*: string
    getModel*: string

const hornPrelude* = "(set-logic HORN)\n" &
    "(set-option :fp.engine spacer)\n" &
    "(set-option :fp.spacer.ground_pobs false)\n" &
    solverOptionsPayload(pinnedDeterminismOptions())

func defaultEncodingConfig*(printCertificate: bool = true): EncodingConfig {.raises: [].} =
  ## Raises-free default with a pinned schema version (C15).
  EncodingConfig(compilerSchemaVersion: 1, loopStrategy: "spacer", arithmeticDomain: "bitvec",
                 memoryModel: "bitvec", printCertificate: printCertificate)

func unsignedProjection(smt: string): string {.raises: [].} =
  result = smt
    .replace("bvslt", "bvult")
    .replace("bvsle", "bvule")
    .replace("bvsge", "bvuge")
    .replace("bvsgt", "bvugt")

func canonicalize*(model: VerificationModel; config: EncodingConfig): CanonicalModel {.raises: [].} =
  var symbols: seq[CanonicalSymbol] = @[]
  for i, sv in model.semantic.states:
    symbols.add(CanonicalSymbol(
      originalName: sv.name,
      canonicalName: "s" & $i,
      scopePath: @[],
      declarationOrdinal: uint32(i)
    ))
  let stateNames = model.semantic.states.mapIt(it.name).toHashSet()
  for entry in model.metadata.symbolMap.allSymbols():
    if entry.name notin stateNames:
      symbols.add(CanonicalSymbol(
        originalName: entry.name,
        canonicalName: entry.name,
        scopePath: @[],
        declarationOrdinal: uint32(symbols.len)
      ))
  let stateParams = (0..<model.semantic.states.len).mapIt(
    CanonicalSymbol(
      originalName: model.semantic.states[it].name,
      canonicalName: "s" & $it,
      scopePath: @[],
      declarationOrdinal: uint32(it)
    )
  )
  var relations: seq[CanonicalRelation] = @[]
  var identityMap: SemanticToCanonicalMap
  # C14: each CFG node (and its outgoing transitions) maps to a relation identity.
  # The state relation ranges over the function's states; per-node relation ids
  # are derived deterministically from NodeId so identity never relies on names.
  relations.add(CanonicalRelation(
    relationId: "rel_state",
    relationName: "state",
    sourceNode: NodeId(0),
    targetNode: NodeId(0),
    stateSignature: stateParams,
    parameters: stateParams,
    formula: ""
  ))
  for tr in model.semantic.transitions:
    identityMap.setNodeMapping(tr.source, RelationId("rel_state"))
    identityMap.setNodeMapping(tr.target, RelationId("rel_state"))
  # Compute semanticFingerprint over the canonical identity projection:
  # state canonical-symbol ordering + relation identity + transition identity.
  var semanticParts: seq[string] = @[]
  for sym in symbols:
    semanticParts.add(sym.canonicalName & ":" & sym.originalName)
  for rel in relations:
    semanticParts.add(rel.relationId & "|" & rel.relationName & "|" & $rel.sourceNode & "|" & $rel.targetNode)
    for ss in rel.stateSignature:
      semanticParts.add("ss:" & ss.canonicalName)
    for p in rel.parameters:
      semanticParts.add("p:" & p.canonicalName)
  let stateParamNames = stateParams.mapIt(it.canonicalName)
  var builder = newTransitionFormulaBuilder(stateParamNames)
  for tr in model.semantic.transitions:
    var freshBase = 0
    let guardSmtVal = guardSmt(tr)
    let formula = buildTransitionFormula(builder, tr, freshBase)
    let guardKey = guardSmtVal
    let updateKey = formula.postArgs.mapIt(it.stateVar & "=" & it.nextSmt).join(";")
    let id = transitionIdentityOf(tr, guardKey, updateKey)
    semanticParts.add(canonicalKey(id))

  # Compute encodingConfigFingerprint over serialized EncodingConfig fields.
  let configStr = $config.compilerSchemaVersion & ":" & config.loopStrategy & ":" & config.arithmeticDomain & ":" & config.memoryModel & ":" & $config.printCertificate

  # Derived exit-safety for NON-VACUOUS error rule: from the safety obligation
  # family. Reuse the same derived obligation model as the legacy encoder so both
  # CHC projections share one semantics (the architecture requires both to be
  # encodings of the SAME obligation model — divergence here is a soundness bug).
  var exitGuardSmt = ""
  if model.semantic.exitGuard.isSome and model.semantic.exitGuard.get != nil:
    exitGuardSmt = irExprToSmt(model.semantic.exitGuard.get)
  var derivedSafety: Option[string]
  let derived = buildObligations(model)
  if derived.safeties.len > 0 and derived.safeties[0].propertySmt.len > 0:
    derivedSafety = some(derived.safeties[0].propertySmt)

  CanonicalModel(
    symbols: symbols,
    relations: relations,
    encodingConfig: config,
    semanticFingerprint: $secureHash(Sha_256, semanticParts.join("||")),
    encodingConfigFingerprint: $secureHash(Sha_256, configStr),
    initExprs: model.semantic.initExprs,
    transitions: model.semantic.transitions,
    obligations: model.semantic.obligations,
    property: model.semantic.property,
    states: model.semantic.states,
    exitGuardSmt: exitGuardSmt,
    derivedSafetySmt: derivedSafety,
    identityMap: identityMap
  )

func toCHCAst*(canonical: CanonicalModel): CHCAst {.raises: [].} =
  var declarations: seq[string] = @[]
  for rel in canonical.relations:
    let sorts = rel.parameters.mapIt("(_ BitVec 64)").join(" ")
    declarations.add("(declare-rel " & rel.relationName & " (" & sorts & "))")
  declarations.add("(declare-rel error ())")
  var rules: seq[string] = @[]
  let stateRelIdx = canonical.relations.findIt(it.relationName == "state")
  let stateRel = canonical.relations[stateRelIdx]
  # Non-vacuous when a derived exit safety exists (property or semantic
  # obligation) — otherwise no `error` reachability rule would make the query
  # trivially `unsat` and prove nothing (§0.9 Anti-Theater).
  let hasSafety = canonical.derivedSafetySmt.isSome or canonical.obligations.len > 0
  if hasSafety and canonical.states.len > 0:
    let initSmts = canonical.initExprs.mapIt(irExprToSmt(it)).join(" ")
    rules.add("(rule (state " & initSmts & "))")
    var transitionRules: seq[tuple[key: string, rule: string]] = @[]
    var builder = newTransitionFormulaBuilder(stateRel.parameters.mapIt(it.canonicalName))
    for tr in canonical.transitions:
      var freshBase = 0
      let guardSmtVal = guardSmt(tr)
      let formula = buildTransitionFormula(builder, tr, freshBase)
      let preArgs = stateRel.parameters.mapIt(it.canonicalName)
      let postArgs = formula.postArgs.mapIt(it.nextSmt)
      let guardKey = guardSmtVal
      let updateKey = formula.postArgs.mapIt(it.stateVar & "=" & it.nextSmt).join(";")
      let id = transitionIdentityOf(tr, guardKey, updateKey)
      let key = canonicalKey(id)
      transitionRules.add((key, "(rule (=> (and (state " & preArgs.join(" ") & ") " & guardSmtVal & ") (state " & postArgs.join(" ") & ")))"))
    transitionRules.sort(proc(a, b: tuple[key: string, rule: string]): int = cmp(a.key, b.key))
    for tr in transitionRules:
      rules.add(tr.rule)
    var obligationRules: seq[tuple[key: string, rule: string]] = @[]
    let stateArgs = stateRel.parameters.mapIt(it.canonicalName).join(" ")
    # Derived exit-safety: error when the safety property is VIOLATED at the
    # exit boundary — `(state) ∧ ¬exitGuard ∧ ¬safety → error`. This matches the
    # legacy encoder's obligation semantics and is non-vacuous.
    if canonical.derivedSafetySmt.isSome:
      var cond = @["(state " & stateArgs & ")"]
      if canonical.exitGuardSmt.len > 0:
        cond.add("(not " & canonical.exitGuardSmt & ")")
      cond.add("(not " & canonical.derivedSafetySmt.get & ")")
      obligationRules.add(("safety", "(rule (=> (and " & cond.join(" ") & ") error))"))
    # Semantic obligations: error when a required safety predicate is VIOLATED.
    for obl in canonical.obligations:
      let predSmt = irExprToSmt(obl.predicate)
      var cond = @["(state " & stateArgs & ")"]
      cond.add("(not " & predSmt & ")")
      let sortKey = "sem:" & $(obl.kind) & ":" & obl.source
      obligationRules.add((sortKey, "(rule (=> (and " & cond.join(" ") & ") error))"))
    obligationRules.sort(proc(a, b: tuple[key: string, rule: string]): int = cmp(a.key, b.key))
    for obl in obligationRules:
      rules.add(obl.rule)
  let query = "(query error)"
  let checkSat = "(check-sat)"
  let getModel = ""
  CHCAst(
    prelude: hornPrelude,
    declarations: declarations,
    rules: rules,
    query: query,
    checkSat: checkSat,
    getModel: getModel
  )

func serialize*(ast: CHCAst): string {.raises: [].} =
  var parts: seq[string] = @[]
  parts.add(ast.prelude)
  for d in ast.declarations:
    parts.add(d)
  for r in ast.rules:
    parts.add(r)
  parts.add(ast.query)
  parts.add(ast.checkSat)
  if ast.getModel.len > 0:
    parts.add(ast.getModel)
  parts.join("\n")

# ---------------------------------------------------------------------------
# P4: Obligation-IR consumer overload — explicit obligations → CanonicalModel
# ---------------------------------------------------------------------------

func canonicalizeWithObligations*(
  model: VerificationModel;
  obligations: seq[VerificationObligation];
  config: EncodingConfig = defaultEncodingConfig()
): CanonicalModel {.raises: [].} =
  ## Canonicalize a VerificationModel with an explicit obligation list.
  ## Each obligation is projected into the canonical model's obligations
  ## and derived safety SMT (1:1 mapping).  An empty obligation list
  ## produces a model with no safety rules — downstream CHC emission
  ## classifies this as `cbNotApplicable(cnaNoObligations)` (the caller
  ## already decided this from the generator result).
  let base = canonicalize(model, config)
  var predSmts: seq[string] = @[]
  var oblObjs: seq[Obligation] = @[]
  for obl in obligations:
    let predSmt = unsignedProjection(obl.predicate)
    predSmts.add(predSmt)
    oblObjs.add(Obligation(
      origin: SymbolOrigin(kind: sokImplicit),
      predicate: nil,
      kind: okDerivedSafety,
      source: obl.id
    ))
  CanonicalModel(
    symbols: base.symbols,
    relations: base.relations,
    encodingConfig: base.encodingConfig,
    semanticFingerprint: base.semanticFingerprint,
    encodingConfigFingerprint: base.encodingConfigFingerprint,
    initExprs: base.initExprs,
    transitions: base.transitions,
    obligations: oblObjs,
    property: base.property,
    states: base.states,
    exitGuardSmt: base.exitGuardSmt,
    derivedSafetySmt: if predSmts.len > 0: some(predSmts.join(" ")) else: none(string),
    identityMap: base.identityMap
  )