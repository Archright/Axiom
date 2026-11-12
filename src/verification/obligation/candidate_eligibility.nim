import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Candidate Eligibility — classification of whether a RuntimeAxiomEntry
## + IRFuncDef pair is a proof candidate, has no obligations, is unsupported,
## or is malformed.
##
## This module composes the static admissibility decision, the obligation
## generation result, and the VerifiedFragmentV1 boundary to produce a
## four-class eligibility classification used by frontier selection and
## proof budgeting.
##
## Design decisions:
## - `elProofCandidate` is the ONLY class that proceeds to proof attempt.
##   All other classes are filtered out before proof execution.
## - Generated results whose obligation kinds fall outside the fragment
##   allowlist map to elUnsupported (static boundary — not a product scope
##   obligation). This is NOT elMalformed (the IR is well-formed) and NOT
##   elNoObligation (obligations exist, they are just out of scope).
## - `isFrontierSelectionEligible` mirrors `isFunctionTextuallyIneligible`
##   in admissibility.nim (lines 108-130): linear scan of runtimeAxiomRegistry,
##   strip trailing `*`, deserializeIRFuncDef, classify.
## - `CandidateRejectionReason` is the WHY behind the class. It is a separate
##   field, not a fifth class, so frontier selection keeps consuming the 4-way
##   enum unchanged while the census can report an aggregated reason histogram.

import core/trusted/axiom_pragmas
import core/trusted/axiom_ir
import core/trusted/private/obligation_smt_lowering
import std/[algorithm, json, options, sets, strutils, sequtils]
import verification/admissibility
import verification/obligation/obligation_types
import verification/obligation/obligation_ir
import verification/obligation/canonical_obligation_generator
import verification/obligation/verified_fragment

# ---------------------------------------------------------------------------
# EligibilityClass — four-class classification
# ---------------------------------------------------------------------------

type
  EligibilityClass* = enum
    elProofCandidate  ## Admissible, generated, and all obligations within
                      ## the VerifiedFragmentV1 allowlist — proceeds to proof.
    elNoObligation    ## No applicable obligations (ogrNoApplicableObligation).
    elUnsupported     ## INELIGIBLE static admissibility, ogrUnsupported,
                      ## or ogrGenerated with obligations outside the
                      ## VerifiedFragmentV1 allowlist (static boundary).
    elMalformed       ## ogrIllFormed — IR well-formedness check failed.

# ---------------------------------------------------------------------------
# CandidateRejectionReason — why a candidate is not a proof candidate
# ---------------------------------------------------------------------------
## Closed vocabulary. The four-way `EligibilityClass` answers *which bucket* a
## candidate falls into and is consumed by frontier selection; this enum
## answers *why*, and is carried as a separate field so that neither answer
## has to be re-derived from the other. `none` means "not rejected".

type
  CandidateRejectionReason* = enum
    crrStaticAdmissibility    ## ineligible.static-admissibility
    crrObligationUnsupported  ## ogr.unsupported
    crrObligationIllFormed    ## ogr.ill-formed
    crrNoApplicableObligation ## ogr.no-applicable
    crrFragmentBoundary       ## fragment.not-allowed
    crrConstantDivisor        ## divisor.constant — produced by the census
    crrVacuousTautology       ## vacuous.tautology — produced by the census
    crrSemanticUnresolvedFact ## semantic.unresolved-fact — produced by the census

  ## The first five are produced here, from the base eligibility decision
  ## alone. The last three are census-layer outcomes: a candidate the base
  ## classifier accepts can still be rejected by the census when every
  ## obligation it generated is decided at compile time and therefore proves
  ## nothing (see the Candidacy Census section below), or when the meaning of
  ## its obligations is not fully determined at census time.

const
  RejectionReasonToken*: array[CandidateRejectionReason, string] = [
    "ineligible.static-admissibility",
    "ogr.unsupported",
    "ogr.ill-formed",
    "ogr.no-applicable",
    "fragment.not-allowed",
    "divisor.constant",
    "vacuous.tautology",
    "semantic.unresolved-fact"
  ]
  ## The reason vocabulary is closed and each token is part of the census
  ## contract, so the mapping is a total table rather than a dispatch.

func `$`*(reason: CandidateRejectionReason): string {.raises: [].} =
  ## Stable wire token. These strings are emitted into report JSON and are
  ## part of the census contract; changing one is a schema change.
  RejectionReasonToken[reason]

func rejectionToken*(reason: Option[CandidateRejectionReason]): string {.raises: [].} =
  ## The wire token, or "" when the candidate was not rejected.
  if reason.isNone: "" else: $(reason.get())

# ---------------------------------------------------------------------------
# classifyAndGenerate — one pass, class + reason + obligations
# ---------------------------------------------------------------------------

const
  BaseVerdictByGenerationKind: array[ObligationGenerationResultKind,
      (EligibilityClass, Option[CandidateRejectionReason])] = [
    (elProofCandidate, none(CandidateRejectionReason)),
    (elNoObligation, some(crrNoApplicableObligation)),
    (elUnsupported, some(crrObligationUnsupported)),
    (elMalformed, some(crrObligationIllFormed))
  ]
  ## The generation terminal alone fixes the class and reason for three of the
  ## four outcomes. `ogrGenerated` is the one that is only a *candidate* verdict
  ## — it says obligations exist, not that they are admissible — so it carries
  ## the optimistic pair and is refined by the fragment decision below.

func classifyAndGenerate*(entry: RuntimeAxiomEntry; funcDef: IRFuncDef):
    (EligibilityClass, Option[CandidateRejectionReason], ObligationGenerationResult) {.raises: [].} =
  ## Classify a candidate and hand back the generation result the decision was
  ## taken from, so a caller that needs the obligations (the census, to apply
  ## the constant-divisor rule) does not have to generate them a second time.
  ##
  ## Mapping (class, reason):
  ##   ogrIllFormed                              → (elMalformed,   ogr.ill-formed)
  ##   ogrNoApplicableObligation                 → (elNoObligation,ogr.no-applicable)
  ##   ogrUnsupported                            → (elUnsupported, ogr.unsupported)
  ##   ogrGenerated, INELIGIBLE admissibility    → (elUnsupported, ineligible.static-admissibility)
  ##   ogrGenerated, kind outside the allowlist  → (elUnsupported, fragment.not-allowed)
  ##   ogrGenerated, all conditions hold         → (elProofCandidate, none)
  let genResult = generateCanonicalObligations(funcDef, defaultScopePolicy())
  var (verdict, reason) = BaseVerdictByGenerationKind[genResult.kind]

  if genResult.kind == ogrGenerated:
    case verifiedFragmentExclusion(entry, funcDef, genResult)
    of feInFragment: discard
    of feStaticAdmissibility:
      (verdict, reason) = (elUnsupported, some(crrStaticAdmissibility))
    of feObligationBoundary:
      (verdict, reason) = (elUnsupported, some(crrFragmentBoundary))

  (verdict, reason, genResult)

# ---------------------------------------------------------------------------
# classifyCandidateEligibility
# ---------------------------------------------------------------------------

func classifyCandidateEligibility*(entry: RuntimeAxiomEntry;
                                   funcDef: IRFuncDef): EligibilityClass {.raises: [].} =
  ## Classify a candidate by composing static admissibility, obligation
  ## generation, and fragment boundary checks.
  ##
  ## Mapping:
  ##   INELIGIBLE admissibility            → elUnsupported
  ##   ogrUnsupported                       → elUnsupported
  ##   ogrGenerated AND NOT inVerifiedFragmentV1 → elUnsupported
  ##   ogrIllFormed                         → elMalformed
  ##   ogrNoApplicableObligation            → elNoObligation
  ##   ogrGenerated AND inVerifiedFragmentV1  → elProofCandidate
  classifyAndGenerate(entry, funcDef)[0]

func classifyCandidateEligibilityDetailed*(entry: RuntimeAxiomEntry; funcDef: IRFuncDef):
    (EligibilityClass, Option[CandidateRejectionReason]) {.raises: [].} =
  ## `classifyCandidateEligibility` plus the machine-readable reason. Same
  ## decision, same inputs — the 4-way class is unchanged.
  let classified = classifyAndGenerate(entry, funcDef)
  (classified[0], classified[1])

# ---------------------------------------------------------------------------
# isFrontierSelectionEligible — mirrors isFunctionTextuallyIneligible
# ---------------------------------------------------------------------------

proc isFrontierSelectionEligible*(funcName: string): bool {.raises: [].} =
  ## Frontier-level cheap gate: given a bare function name (with any `*`
  ## export marker), look it up in the compile-time registry and return
  ## true iff classifyCandidateEligibility == elProofCandidate.
  ##
  ## Mirrors isFunctionTextuallyIneligible in admissibility.nim (lines
  ## 108-130): linear scan of runtimeAxiomRegistry, strip trailing `*`,
  ## deserializeIRFuncDef, classify. Unknown names (no registry entry)
  ## return false (not eligible).
  var bare = funcName
  if bare.endsWith("*"):
    bare = bare[0..^2]
  for entry in runtimeAxiomRegistry:
    if entry.name != bare or entry.irSerialized.len == 0:
      continue
    let funcDef = deserializeIRFuncDef(entry.irSerialized)
    if funcDef.name.len > 0:
      return classifyCandidateEligibility(entry, funcDef) == elProofCandidate
  false

# ===========================================================================
# Candidacy Census — the measurement surface for "does the canonical obligation
# authority derive a NON-TRIVIAL proof obligation from this subject?"
# ===========================================================================
## The census is a pure, deterministic function of the candidate set: no I/O,
## no environment reads, no clock, and no map-iteration order — every emitted
## list is sorted before it is returned.
##
## Two layers of decision, kept visibly separate:
##
## 1. Base eligibility (`classifyAndGenerate` above) — the pre-existing 4-way
##    classification, unchanged, with a reason token attached.
## 2. The constant-divisor rule (F) — a candidate the base classifier accepts
##    can still be excluded here, because every obligation it generated may be
##    decided at compile time. `¬(k == 0)` with `k` a nonzero literal is true
##    under EVERY assignment, so proving it says nothing about the subject;
##    `¬(0 == 0)` is false under every assignment and carries nothing either. A
##    candidate whose obligations are all of that shape is marked
##    `divisor.constant` / `vacuous.tautology` and never reaches proof.
##
## The divisor is read from the obligation's `proposition: IRExpr` — the typed
## expression `makeDivCandidate` preserved — never from the canonical predicate
## string. Rule F is decidable by IR shape alone; no solver runs.
##
## The same ordering holds for rule S (the semantic-universe rule, below): a
## candidate the rule F probe already classified as `divisor.constant` or
## `vacuous.tautology` keeps that token verbatim. Rule S can only remove a
## candidate that rule F would have counted as census-eligible, so the two
## existing census buckets stay byte-identical when rule S is introduced.
##
## Scope: the census covers external-subject candidates only. Kernel-registry
## candidates are classified by the same base rule but are NOT part of this
## measurement, so `scope` is emitted alongside every census and an empty census
## reports NO_EXTERNAL_CANDIDATE rather than claiming that no eligible
## obligation exists.

const
  CensusTerminalNoExternalCandidate* = "NO_EXTERNAL_CANDIDATE"
    ## No external-subject candidate reached the eligibility gate at all. The
    ## measurement is empty, so no claim about eligible obligations is made —
    ## an empty census is not evidence of anything.
  CensusTerminalNoEligibleObligation* = "NO_ELIGIBLE_OBLIGATION"
    ## Candidates were examined and none produced a non-tautological obligation.
    ## This is a publishable, positive finding: the obligation authority derives
    ## no non-trivial proof obligation from this subject. A run that lands here
    ## may legitimately report solverInvocationCount == 0; that is the measured
    ## outcome, not a verification failure.
  CensusTerminalCandidateSelected* = "CANDIDATE_SELECTED_FOR_PROOF"
    ## Candidacy resolved and at least one candidate reached proof attempt. The
    ## proof terminal itself lives elsewhere in the same document
    ## (`runOutcome` / `executionStats`); the census does not restate it.
  CensusScopeExternalSubject* = "external-subject"

  CensusUnclassifiedRejection* = "unclassified.rejection"
    ## A candidate the census rejected without a stated reason. That is a
    ## census defect, not a measurement, so it is surfaced under its own token
    ## instead of being folded into a real reason bucket.

# ---------------------------------------------------------------------------
# DivisorTautology — the rule F probe
# ---------------------------------------------------------------------------

type
  DivisorTautology* = enum
    dtNone             ## not a division obligation with a constant divisor
    dtConstantNonZero  ## ¬(k == 0), k a nonzero integer literal
    dtConstantZero     ## ¬(0 == 0)

func divisorOperandOf(prop: IRExpr): IRExpr {.raises: [].} =
  ## The divisor sub-expression of a `¬(d == 0)` proposition, read off the IR.
  ## Either side of the equality may carry the literal zero, so both are
  ## accepted; nil when `prop` has that shape with neither side being zero.
  if prop == nil or prop.kind != irUnaryOp or prop.unaryOp != uoNot:
    return nil
  let inner = prop.unaryArg
  if inner == nil or inner.kind != irBinOp or inner.binOp != boEq:
    return nil
  let lhs = inner.binLhs
  let rhs = inner.binRhs
  let lhsIsZero = lhs != nil and lhs.kind == irLit and lhs.litVal == 0
  let rhsIsZero = rhs != nil and rhs.kind == irLit and rhs.litVal == 0
  if rhsIsZero: return lhs
  if lhsIsZero: return rhs
  nil

func divisorTautologyOf(obl: VerificationObligation): DivisorTautology {.raises: [].} =
  ## Classify one obligation under rule F.
  ##
  ## Only `okSafetyDiv` obligations whose divisor operand is an `irLit` are in
  ## scope. An `irFloatLit` divisor is deliberately NOT matched: the IR encodes
  ## floats as fixed-point scaled to int64, and nothing established says the
  ## Lean rendering of such a comparison preserves the compile-time decision.
  ## Leaving it `dtNone` keeps the candidate in the proof set (fail-closed
  ## toward proving, never toward dropping).
  if obl.kind != okSafetyDiv:
    return dtNone
  let divisor = divisorOperandOf(obl.proposition)
  if divisor == nil or divisor.kind != irLit:
    return dtNone
  if divisor.litVal == 0: dtConstantZero else: dtConstantNonZero

# ---------------------------------------------------------------------------
# Census records
# ---------------------------------------------------------------------------

type
  CandidateCensusRecord* = object
    modulePath*: string
    functionName*: string
    eligibility*: EligibilityClass
      ## The base 4-way class, verbatim from `classifyAndGenerate`. It is NOT
      ## rewritten by rule F — a rule F exclusion stays visible in `rejection`,
      ## so the base verdict stays auditable.
    censusEligible*: bool
      ## eligibility == elProofCandidate AND at least one generated obligation
      ## is not a compile-time tautology AND the semantic universe is resolved
      ## (rule S).
    obligationSetComplete*: bool
      ## False when the translator lost something outside every region rule S
      ## certified, so a guard the subject contains may have produced an
      ## obligation that was never generated. This is a coverage statement, not a
      ## rejection: the obligations that WERE generated are proved on faithful
      ## regions. Reported separately because the census otherwise reports only
      ## rejections, and a candidate with incomplete coverage would be
      ## indistinguishable from one whose obligation set is the subject's whole
      ## set.
    rejection*: Option[CandidateRejectionReason]
    generatedObligationCount*: int
    nonTrivialObligationCount*: int

  RejectionReasonCount* = object
    reason*: string
    count*: int

  CandidacyCensus* = object
    scope*: string
    candidateCount*: int
    rejectedCount*: int
    proofCandidateCount*: int
    coverageLimitedCount*: int
      ## Census-eligible candidates whose obligation set may be incomplete because
      ## the translator lost something outside the regions rule S certified.
    rejectionReasons*: seq[RejectionReasonCount]
    obligationCount*: int
    generatedObligationCount*: int
    selected*: string
    proofCandidates*: seq[string]
    terminal*: string
    candidates*: seq[CandidateCensusRecord]
  ## `obligationCount` counts the obligations of the census-eligible set — the
  ## ones that actually carry proof content. `generatedObligationCount` counts
  ## every obligation the authority produced, including the ones rule F
  ## discarded. Both are reported so neither can be mistaken for the other.

# ---------------------------------------------------------------------------
# Semantic universe — the rule S gate
# ---------------------------------------------------------------------------
## The census runs before any SemanticEnvironment exists: no semantic fact has
## been derived, no evidence artifact has been consulted. A candidate may
## therefore be counted only when nothing about the meaning of its obligations
## is still open at that point. Concretely a free variable that is neither a
## declared parameter of the subject nor a binding the translator read out of the
## source is, at census time, an unknown piece of Nim meaning — the solver would
## read it as a free constant and prove something about the wrong program. Rule S
## is decidable from the IR alone.

type
  BindingUniverseVerdict* = enum
    buvResolved               ## every gate below holds
    buvLossyPropositionRegion ## (a) a guard/loop condition was translated lossily,
                              ##     or a statement form was dropped whole
    buvLossyBindingRegion     ## (b) some binding's defining expression lost something
    buvUnresolvedName         ## (c) an obligation names something the subject never bound
    buvAmbiguousBindingName   ## (d) a name is bound twice, so it is not an identity

func freeVarsResolvable(funcDef: IRFuncDef;
                        obligations: seq[VerificationObligation]): bool {.raises: [].} =
  ## Transitive closure of `params ∪ bindings`: every name the subject binds is
  ## resolvable, and a binding is only usable when its own defining expression
  ## names nothing outside that set. A binding that reads an undeclared name is
  ## unresolved no matter how many obligations name the binding itself.
  ## The closure is built in insertion order and the sets are only ever asked
  ## membership questions, so the verdict never depends on hash iteration order.
  var closure: HashSet[string]
  for p in funcDef.params:
    closure.incl p.name
  for b in funcDef.recordedBindings:
    if b.lossFree: closure.incl b.name

  for b in funcDef.recordedBindings:
    if not b.lossFree: continue
    for v in collectFreeVars(b.value):
      if v notin closure: return false

  for obl in obligations:
    # A contract postcondition naming `result` names the subject's declared
    # result slot, not a free constant: lowerPostconditionToLean substitutes
    # the applied body for `result` when the obligation reaches the solver
    # (canonical_verification.nim), so the census-time reading of `result` as
    # an unknown Nim meaning does not apply to this kind. Preconditions and
    # safety obligations keep rule S strict — `result` has no defined value in
    # their pre-state — so the widening is per-obligation, never accumulated
    # into the shared closure (an early post must not launder a later pre),
    # and a post naming any other undeclared identifier is still rejected.
    var effClosure = closure
    if obl.kind == okContractPost:
      effClosure.incl "result"
    for v in collectFreeVars(obl.proposition):
      if v notin effClosure: return false
  true

func bindingNameUnique(funcDef: IRFuncDef): bool {.raises: [].} =
  ## A name bound twice is not a binding identity: the obligation's reference to
  ## it does not select one meaning. Only translator-read source bindings are
  ## considered — a synthesized loop-result name is an artifact of one construct,
  ## not two competing declarations.
  var seen: HashSet[string]
  for b in funcDef.recordedBindings:
    if b.name in seen: return false
    seen.incl b.name
  true

func bindingUniverseVerdict*(funcDef: IRFuncDef;
                            obligations: seq[VerificationObligation]):
    BindingUniverseVerdict {.raises: [].} =
  ## The four gates, in the only order that cannot admit an unsound candidate.
  ##
  ## (a) before (d) is load-bearing. Name uniqueness alone is not a shadowing
  ## check: `ckBlockStmt` has no arm in the CanonNode body converter, so
  ## `let x = 1; block: let x = 2` reaches the IR with the inner binding deleted
  ## and the surviving name looking unique. (a) rejects that source, because the
  ## dropped statement is what made the name unique.
  if not funcDef.propositionRegionLossFree:
    return buvLossyPropositionRegion
  for b in funcDef.recordedBindings:
    if not b.lossFree: return buvLossyBindingRegion
  if not freeVarsResolvable(funcDef, obligations):
    return buvUnresolvedName
  if not bindingNameUnique(funcDef):
    return buvAmbiguousBindingName
  buvResolved

func semanticUniverseResolved(funcDef: IRFuncDef;
                               obligations: seq[VerificationObligation]): bool {.raises: [].} =
  ## The semantic preconditions of proof eligibility, as one conjunction: the
  ## regions an obligation and its bindings are derived from translated without
  ## loss, and no obligation names something the subject did not bind.
  ##
  ## This no longer consults `translationLossFree` or `bindingUniverseComplete`.
  ## Both are one bit for a whole function, which is the granularity this gate
  ## exists to stop using; and `bindingUniverseComplete` is itself a conjunction
  ## (loss ∧ raw-AST correspondence ∧ opacity) that this census cannot decompose —
  ## it has neither the loss term the scoped evidence now supersedes nor any
  ## authority over the other two. What those other two protect is preserved by
  ## construction: a name the subject never bound cannot appear in
  ## `recordedBindings`, so it cannot resolve through the closure, and a binding
  ## the translator dropped cannot appear in an obligation at all. Fact injection
  ## is unchanged and still fail-closes on both flags
  ## (semantic_environment.nim), so the completeness gate they carry is untouched.
  bindingUniverseVerdict(funcDef, obligations) == buvResolved

# ---------------------------------------------------------------------------
# classifyCandidateForCensus — base eligibility + rule F + rule S
# ---------------------------------------------------------------------------

func classifyCandidateForCensus*(entry: RuntimeAxiomEntry;
                                 funcDef: IRFuncDef): CandidateCensusRecord {.raises: [].} =
  ## One candidate, one record. Pure and deterministic.
  let (kls, rejection, genResult) = classifyAndGenerate(entry, funcDef)
  result = CandidateCensusRecord(
    modulePath: entry.sourcePath,
    functionName: entry.name,
    eligibility: kls,
    censusEligible: false,
    obligationSetComplete: true,
    rejection: rejection,
    generatedObligationCount: 0,
    nonTrivialObligationCount: 0)

  if kls != elProofCandidate:
    return

  # Coverage is a property of the translation, not of the eligibility verdict:
  # it is recorded even for candidates rule F or S go on to reject, so the census
  # never has to re-derive it and never silently reports a lossy subject as whole.
  result.obligationSetComplete = not funcDef.lossOutsideBindingRegions

  var nonTrivial = 0
  var unsatisfiable = false
  for obl in genResult.obligations.items:
    let tautology = divisorTautologyOf(obl)
    # if/elif rather than `case` on a three-valued local enum: this module's
    # runtime case-branch surface is held at the fragment-boundary decision
    # alone (solid-ocp), and a two-sided decision reads the same either way.
    if tautology == dtNone:
      inc nonTrivial
    elif tautology == dtConstantZero:
      unsatisfiable = true

  result.generatedObligationCount = genResult.obligations.len
  result.nonTrivialObligationCount = nonTrivial
  if nonTrivial > 0:
    # Rule S runs only on candidates rule F already found provable-in-principle,
    # so it can subtract from the eligible set but never relabel an existing
    # reason bucket.
    if semanticUniverseResolved(funcDef, genResult.obligations.items):
      result.censusEligible = true
      result.rejection = none(CandidateRejectionReason)
    else:
      result.rejection = some(crrSemanticUnresolvedFact)
  elif unsatisfiable:
    # ¬(0 == 0) is false under every assignment — no proof content either.
    result.rejection = some(crrVacuousTautology)
  else:
    result.rejection = some(crrConstantDivisor)

# ---------------------------------------------------------------------------
# buildCandidacyCensus — deterministic aggregation
# ---------------------------------------------------------------------------

func candidateIdentity(rec: CandidateCensusRecord): string {.raises: [].} =
  rec.modulePath & "::" & rec.functionName

func compareCandidates(a, b: CandidateCensusRecord): int {.raises: [].} =
  var c = cmp(a.modulePath, b.modulePath)
  if c != 0: return c
  cmp(a.functionName, b.functionName)

func compareReasonCounts(a, b: RejectionReasonCount): int {.raises: [].} =
  if a.reason != b.reason: cmp(a.reason, b.reason)
  else: cmp(a.count, b.count)

func tallyRejections(sorted: seq[CandidateCensusRecord]): seq[RejectionReasonCount] {.raises: [].} =
  ## Rejection histogram by reason, tallying by enum ordinal and then ordering by
  ## token — the tally never depends on a hash table's iteration order.
  var tally: array[CandidateRejectionReason, int]
  var unclassified = 0
  for rec in sorted:
    if rec.rejection.isSome:
      inc tally[rec.rejection.get]
    elif not rec.censusEligible:
      # A census-eligible record carries no token because it was not rejected;
      # counting it here would file every passing candidate under the token that
      # means "a census rejected this without a reason".
      inc unclassified
  for reason in CandidateRejectionReason:
    if tally[reason] > 0:
      result.add(RejectionReasonCount(reason: $reason, count: tally[reason]))
  if unclassified > 0:
    result.add(RejectionReasonCount(reason: CensusUnclassifiedRejection,
                                     count: unclassified))
  result.sort(compareReasonCounts)

func buildCandidacyCensus*(records: seq[CandidateCensusRecord]): CandidacyCensus {.raises: [].} =
  ## Aggregate per-candidate records into the census. Sorting happens here and
  ## only here, so the result depends on the multiset of records alone — not on
  ## the order they were produced, and not on any hash-table layout.
  var sorted = records
  sorted.sort(compareCandidates)

  var proofCandidates: seq[string] = @[]
  for rec in sorted:
    inc result.candidateCount
    result.generatedObligationCount += rec.generatedObligationCount
    if rec.censusEligible:
      inc result.proofCandidateCount
      result.obligationCount += rec.nonTrivialObligationCount
      proofCandidates.add(candidateIdentity(rec))
      if not rec.obligationSetComplete: inc result.coverageLimitedCount
    else:
      inc result.rejectedCount

  result.rejectionReasons = tallyRejections(sorted)
  result.candidates = sorted
  result.proofCandidates = proofCandidates
  result.scope = CensusScopeExternalSubject
  if result.candidateCount == 0:
    result.selected = ""
    result.terminal = CensusTerminalNoExternalCandidate
  elif result.proofCandidateCount == 0:
    result.selected = ""
    result.terminal = CensusTerminalNoEligibleObligation
  else:
    result.selected = proofCandidates[0]
    result.terminal = CensusTerminalCandidateSelected

# ---------------------------------------------------------------------------
# censusToJson — the report projection
# ---------------------------------------------------------------------------

func rejectionTokenOrNull(reason: Option[CandidateRejectionReason]): JsonNode {.raises: [].} =
  let token = rejectionToken(reason)
  if token.len > 0: %token else: newJNull()

func censusToJson*(c: CandidacyCensus): JsonNode {.raises: [].} =
  result = newJObject()
  result["scope"] = %c.scope
  result["terminal"] = %c.terminal
  result["candidateCount"] = %c.candidateCount
  result["rejectedCount"] = %c.rejectedCount
  result["proofCandidateCount"] = %c.proofCandidateCount
  result["coverageLimitedCount"] = %c.coverageLimitedCount
  result["obligationCount"] = %c.obligationCount
  result["generatedObligationCount"] = %c.generatedObligationCount

  var reasons = newJObject()
  for r in c.rejectionReasons:
    reasons[r.reason] = %r.count
  result["rejectionReasons"] = reasons

  if c.selected.len > 0: result["selected"] = %c.selected
  else: result["selected"] = newJNull()
  result["proofCandidates"] = %c.proofCandidates

  var candidates = newJArray()
  for rec in c.candidates:
    var node = newJObject()
    node["modulePath"] = %rec.modulePath
    node["functionName"] = %rec.functionName
    node["eligibility"] = %($rec.eligibility)
    node["censusEligible"] = %rec.censusEligible
    node["obligationSetComplete"] = %rec.obligationSetComplete
    node["rejection"] = rejectionTokenOrNull(rec.rejection)
    node["generatedObligationCount"] = %rec.generatedObligationCount
    node["nonTrivialObligationCount"] = %rec.nonTrivialObligationCount
    candidates.add(node)
  result["candidates"] = candidates

{.pop.}
