import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Canonical Obligation Generator — total, pure, deterministic decision engine.
##
## Produces `ObligationGenerationResult` from an IRFuncDef + ScopePolicy.
## Implements the 4-way classification (§4 of obligation_semantics.md):
##   - IllFormed: IR well-formedness check fails
##   - Unsupported: semantic scope out of model (closed list of 3 reasons)
##   - Generated: ≥1 obligation candidate detected
##   - NoApplicable: 0 candidates, proven absence
##
## C4 determinism: obligations sorted by kind ordinal → subject string → id.
## C6 closure: each obligation carries subject·assumptions·predicate·derivationRule.
## C5: postcondition absence is NEVER Unsupported.

import std/[sequtils, strutils, algorithm, options]
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/axiom_pragmas_lite
import verification/obligation/obligation_types
import verification/obligation/obligation_ir
import verification/obligation/no_obligation_provenance
import verification/obligation/semantic_target_extractor
import verification/obligation/post_satisfaction

# ---------------------------------------------------------------------------
# ScopePolicy — controls how the generator classifies zero-obligation cases
# ---------------------------------------------------------------------------

type
  ScopePolicy* = object
    admissible*: bool
      ## Whether this function is within the kernel scope under analysis.
      ## False → treat as exempt; produce NoApplicable with excludedClasses.
    exemptReason*: Option[string]
      ## If set, explains why this function is exempt from obligation generation.
    expectedObligation*: bool
      ## Whether the scope contract expects obligations for this symbol.
      ## True + zero obligations → scope inconsistency (NoObligationScopeMismatch).
      ## False + zero obligations → legitimate no-op (noObligationLegitimate).
      ## Mirrors proof_integrity.nim classifyNoObligation semantics.

func defaultScopePolicy*: ScopePolicy {.inline.} =
  ## Default policy: admissible, no exemption, no explicit expectation.
  ScopePolicy(admissible: true, exemptReason: none(string), expectedObligation: false)

# ---------------------------------------------------------------------------
# Well-formedness check — minimal local sanity
# ---------------------------------------------------------------------------

func isWellFormed*(funcDef: IRFuncDef): bool {.raises: [].} =
  ## Minimal well-formedness check: body must be non-nil and retType must be set.
  if funcDef.body == nil: return false
  if funcDef.retType == nil: return false
  for p in funcDef.params:
    if p.ty == nil: return false
  true

# ---------------------------------------------------------------------------
# Unsupported detection — closed list of 3 reasons only
# ---------------------------------------------------------------------------

func detectUnsupported*(funcDef: IRFuncDef): Option[UnsupportedReason] {.raises: [], axiomDecision(
  id = "DECISION-0819",
  reason = "Unsupported-feature detection returning Option — closed list of 3 reasons; postcondition absence is NEVER Unsupported (C5)",
  adr = "docs/spec/obligation_semantics.md",
  introduced = "v39").} =
  ## Detect unsupported semantic features. Returns some(reason) if found,
  ## none() otherwise. Closed list: only these 3 reasons are valid.
  ##
  ## Rules:
  ## - Recursive functions → scopedRecursiveHeapNotModeled
  ## - Higher-order effect → scopedHigherOrderEffectNotModeled
  ## - Unsupported language construct → scopedLanguageConstructNotModeled
  ## - Postcondition absence is NEVER Unsupported (C5)

  # Check for recursive functions (potential heap interaction)
  if funcDef.isRecursive:
    return some(usScopedRecursiveHeapNotModeled)

  # Walk IR tree to detect known unsafe constructs
  func walk(e: IRExpr): bool {.raises: [].} =
    if e == nil: return false
    case e.kind
    of irCall:
      if e.callName in ["unsafeCast", "ffiCall"]:
        return true
      for a in e.callArgs:
        if walk(a): return true
      false
    of irBinOp:
      walk(e.binLhs) or walk(e.binRhs)
    of irLet:
      walk(e.letVal) or walk(e.letBody)
    of irIf:
      walk(e.ifCond) or walk(e.ifThen) or walk(e.ifElse)
    of irCase:
      if walk(e.caseScrutinee): return true
      for b in e.caseBranches:
        if walk(b.body): return true
      if e.caseDefault != nil:
        if walk(e.caseDefault): return true
      false
    of irUnaryOp:
      walk(e.unaryArg)
    of irRecCall:
      for a in e.recArgs:
        if walk(a): return true
      false
    of irLoop:
      for init in e.loopInits:
        if walk(init): return true
      if walk(e.loopCond): return true
      if walk(e.loopStep): return true
      if walk(e.loopBody): return true
      for inv in e.loopInvariants:
        if walk(inv): return true
      if e.loopVariant != nil:
        if walk(e.loopVariant): return true
      false
    of irCast:
      walk(e.castExpr)
    else: false

  for param in funcDef.params:
    if param.constraint.isSome:
      let c = param.constraint.get
      if c != nil and walk(c):
        return some(usScopedLanguageConstructNotModeled)

  for pre in funcDef.preConditions:
    if pre != nil and walk(pre):
      return some(usScopedLanguageConstructNotModeled)

  for post in funcDef.postConditions:
    if post != nil and walk(post):
      return some(usScopedLanguageConstructNotModeled)

  none(UnsupportedReason)

# ---------------------------------------------------------------------------
# Main generator function
# ---------------------------------------------------------------------------

func generateCanonicalObligations*(
  funcDef: IRFuncDef,
  policy: ScopePolicy
): ObligationGenerationResult {.raises: [].} =
  ## Total, pure, deterministic obligation generation.
  ##
  ## Decision flow:
  ## 1. Well-formedness → IllFormed if fails
  ## 2. Unsupported detection → Unsupported if closed-list reason found
  ## 3. Admissibility check → NoApplicable if not admissible
  ## 4. Candidate extraction → Generated if ≥1, NoApplicable if 0

  # Step 1: Well-formedness
  if not isWellFormed(funcDef):
    let reason = if funcDef.body == nil: ifUnknownSymbol
                 elif funcDef.retType == nil: ifTypeMismatch
                 else: ifScopeViolation
    return makeIllFormed(reason)

  # Step 2: Unsupported detection (closed list)
  let unsupOpt = detectUnsupported(funcDef)
  if unsupOpt.isSome:
    return makeUnsupported(unsupOpt.get)

  # Step 3: Admissibility check
  if not policy.admissible:
    var facts = newSeq[string]()
    if policy.exemptReason.isSome:
      facts.add("exempt_reason=" & policy.exemptReason.get)
    facts.add("admissible=false")
    facts.add("candidates_found=0")
    let excludedClasses: seq[ObligationKind] =
      @[okSafetyDiv, okSafetyIndex, okContractPost, okContractPre]
    let naProv: NoObligationProvenance = NoObligationProvenance(
      applicableClasses: @[],
      excludedClasses: excludedClasses,
      derivationRule: "policy:scopeExempt",
      semanticFacts: facts
    )
    return makeNoApplicable(naProv)

  # Step 4: Extract candidates
  let candidates = extractObligationCandidates(funcDef)

  # Step 4a: Post-satisfaction by construction (Phase A).
  # When the body+post structurally establish the postcondition by construction
  # (analyzePostByConstruction) AND every candidate is a post-obligation (i.e.,
  # the whole obligation set reduces to zero — no divis/index/loop/pre remain),
  # classify ogrNoApplicableObligation with reason obs:postSatisfiedByConstruction.
  # Fragile/fail-closed: any other obligation kind present (real safety/contract
  # target) keeps the Generated path — we never drop an obligation that still
  # needs evidence. Matcher never asserts a false no-violation.
  if candidates.len > 0:
    var allPost = true
    for cand in candidates:
      if cand.kind != okContractPost:
        allPost = false
        break
    if allPost:
      let postProvOpt = analyzePostByConstruction(funcDef)
      if postProvOpt.isSome:
        let ps = postProvOpt.get
        let excludedPostOnly: seq[ObligationKind] = @[okContractPost]
        let naProvPost: NoObligationProvenance = NoObligationProvenance(
          applicableClasses: @[],
          excludedClasses: excludedPostOnly,
          derivationRule: ps.derivationRule,
          semanticFacts: ps.semanticFacts
        )
        return makeNoApplicable(naProvPost)

  if candidates.len == 0:
    # Zero obligations — determine NoApplicable vs Unsupported
    # Per spec §4.3: pure func with no safety/contract targets → NoApplicable
    # String identity is NOT Unsupported (it's in scope, just trivially safe)
    var facts = newSeq[string]()
    facts.add("body_type=simple")
    facts.add("no_division_operators")
    facts.add("no_index_access")
    facts.add("no_loops")
    facts.add("no_postconditions")
    facts.add("no_preconditions")
    facts.add("expectedObligation=" & $policy.expectedObligation)

    let noAppFacts = facts
    let excludedNoApp: seq[ObligationKind] =
      @[okSafetyDiv, okSafetyIndex, okSafetyLoopBound,
          okContractPost, okContractPre, okInvariant]
    let naProv2: NoObligationProvenance = NoObligationProvenance(
      applicableClasses: @[],
      excludedClasses: excludedNoApp,
      derivationRule: "obs:noObligations",
      semanticFacts: noAppFacts
    )
    return makeNoApplicable(naProv2)

  # Step 5: Build obligations from candidates (≥1 found)
  var obligations: seq[VerificationObligation] = @[]
  for cand in candidates:
    let canonAssumptions = cand.assumptions.sorted.join("|")
    let provenance = "generated:" & funcDef.name & ":" & cand.derivationRule
    let obl = makeVerificationObligation(cand.kind, cand.subject,
      canonAssumptions, cand.derivationRule, provenance, cand.proposition)
    obligations.add obl

  # C4 determinism: sort by kind ordinal → subject string → id
  obligations.sort(proc(a, b: VerificationObligation): int =
    if a.kind.ord != b.kind.ord: cmp(a.kind.ord, b.kind.ord)
    elif a.subject != b.subject: cmp(a.subject, b.subject)
    else: cmp(a.id, b.id))

  doAssert obligations.len >= 1, "generateCanonicalObligations requires ≥1 candidate"
  return makeGenerated(makeLightNonEmpty(obligations))

{.pop.}
