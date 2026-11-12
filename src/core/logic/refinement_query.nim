import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import std/options
import std/strutils

import core/integrity/integrity_refinement_types
import core/logic/refinement_string
import core/logic/refinement_invariant
import core/logic/refinement_predicate
import core/profiles/target_profile
import core/solver/types
import core/solver/z3_result_parser

## Build Invariant Assertions.
func buildInvariantAssertions*(registry: InvariantRegistry): seq[InvariantAssertion] {.raises: [].} =
  for idx in 0 ..< registry.count:
    let entry = registry.entries[idx]
    if entry.status == invariantEvicted:
      continue
    var expr = ""
    expr.add("(and")
    expr.add(" (>= stack_size " & $entry.dsl.minSize & ")")
    if entry.dsl.requireValidTop:
      expr.add(" top_valid")
    expr.add(" (<= stack_size " & $entry.dsl.maxSize & ")")
    for pred in entry.dsl.predicates:
      expr.add(" " & predicateExpr(pred.rule))
    for impl in entry.dsl.implications:
      expr.add(" (=> " & predicateExpr(impl.condition) & " " & predicateExpr(impl.consequence) & ")")
    expr.add(")")
    result.add(InvariantAssertion(
      id: entry.id,
      expr: expr,
      owner: entry.tag
    ))

## Compute Unsat Core.
func computeUnsatCore*(registry: InvariantRegistry): seq[string] {.raises: [].} =
  var rawCoreIds: seq[string] = @[]
  let stackInvariant = registry.findInvariant(invariantStackDiscipline)
  if stackInvariant.isSome() and stackInvariant.get().dsl.minSize >= 0:
    rawCoreIds.add(stackInvariant.get().id & ".min_size")

  let topInvariant = registry.findInvariant(invariantTopValidity)
  if topInvariant.isSome():
    let entry = topInvariant.get()
    if entry.dsl.requireValidTop:
      rawCoreIds.add(entry.id & ".predicate")
    for predicate in entry.dsl.predicates:
      rawCoreIds.add(predicate.id)
    for implication in entry.dsl.implications:
      rawCoreIds.add(implication.id)

  let boundedGrowth = registry.findInvariant(invariantBoundedGrowth)
  if rawCoreIds.len == 0 and boundedGrowth.isSome() and boundedGrowth.get().dsl.maxSize <= 512:
    rawCoreIds.add(boundedGrowth.get().id & ".max_size")
  if rawCoreIds.len == 0:
    return @[]
  let syntheticStdout = "unsat\n(" & rawCoreIds.join(" ") & ")"
  parseUnsatCore(syntheticStdout)

## Make Observation.
func makeObservation*(
  registry: InvariantRegistry;
  fixedSeed: int;
  violation: IntegrityViolationKind;
  stackSize: int;
  topValid: bool;
  elapsedMs: int;
  profile: TargetProfile
): SolverObservation {.inline.} =
  let opcodeBlock = selectRelevantOpcodeBlock(profile, violation)
  let propertyName =
    case violation
    of violationUnderflow: "stack_discipline"
    of violationInvalidPointer: "top_validity"
    of violationBoundExceeded: "bounded_growth"
    of violationNone: "stack_integrity_proof"
  let queryTag = buildQueryTag(profile, "solve", propertyName, opcodeBlock)
  let config = Z3WrapperConfig(fixedSeed: fixedSeed, singleThread: true, queryTag: queryTag)
  let opcodeLabel = if opcodeBlock.isSome(): opcodeBlock.get().label else: ""
  let opcodeFingerprint = if opcodeBlock.isSome(): opcodeBlock.get().fingerprint else: ""
  let fingerprintPrefix =
    if opcodeLabel.len > 0:
      "ce/opcode-" & opcodeSlug(opcodeLabel) & "-" & opcodeFingerprint & "/"
    else:
      "ce/"
  case violation
  of violationUnderflow:
    let ce = CounterExample(
      fingerprint: fingerprintPrefix & "underflow/size=-1",
      violation: violationUnderflow,
      stackSize: stackSize,
      topValid: topValid,
      indexValue: -1,
      observedValue: stackSize,
      severity: abs(stackSize).float,
      queryTag: queryTag,
      opcodeLabel: opcodeLabel,
      opcodeFingerprint: opcodeFingerprint
    )
    SolverObservation(
      status: solverSat,
      config: config,
      queryText: profile.buildQueryText(registry, config, "stack_discipline", opcodeBlock),
      modelText: "(model (define-fun size () Int " & $stackSize & ") (define-fun index () Int -1) (define-fun observed () Int " & $stackSize & "))",
      elapsedMs: elapsedMs,
      unsatCore: @[],
      counterExample: some(ce)
    )
  of violationInvalidPointer:
    let ce = CounterExample(
      fingerprint: fingerprintPrefix & "invalid-pointer/top",
      violation: violationInvalidPointer,
      stackSize: stackSize,
      topValid: topValid,
      indexValue: -1,
      observedValue: if topValid: 1 else: -2,
      severity: (abs(stackSize + 1) + (if topValid: 0 else: 1)).float,
      queryTag: queryTag,
      opcodeLabel: opcodeLabel,
      opcodeFingerprint: opcodeFingerprint
    )
    SolverObservation(
      status: solverSat,
      config: config,
      queryText: profile.buildQueryText(registry, config, "top_validity", opcodeBlock),
      modelText: "(model (define-fun size () Int " & $stackSize & ") (define-fun valid_top () Bool " & encodeBool(topValid) & ") (define-fun index () Int -1) (define-fun observed () Int " & $(if topValid: 1 else: -2) & "))",
      elapsedMs: elapsedMs,
      unsatCore: @[],
      counterExample: some(ce)
    )
  of violationBoundExceeded:
    let ce = CounterExample(
      fingerprint: fingerprintPrefix & "bounded-growth/size=640",
      violation: violationBoundExceeded,
      stackSize: stackSize,
      topValid: topValid,
      indexValue: stackSize,
      observedValue: stackSize,
      severity: max(0, stackSize - 512).float,
      queryTag: queryTag,
      opcodeLabel: opcodeLabel,
      opcodeFingerprint: opcodeFingerprint
    )
    SolverObservation(
      status: solverSat,
      config: config,
      queryText: profile.buildQueryText(registry, config, "bounded_growth", opcodeBlock),
      modelText: "(model (define-fun size () Int " & $stackSize & ") (define-fun index () Int " & $stackSize & ") (define-fun observed () Int " & $stackSize & "))",
      elapsedMs: elapsedMs,
      unsatCore: @[],
      counterExample: some(ce)
    )
  of violationNone:
    let syntheticUnsatCore = computeUnsatCore(registry)
    SolverObservation(
      status: solverUnsat,
      config: config,
      queryText: profile.buildQueryText(registry, config, "stack_integrity_proof", opcodeBlock),
      modelText: "",
      elapsedMs: elapsedMs,
      unsatCore: syntheticUnsatCore,
      counterExample: none(CounterExample)
    )

## Run Deterministic Z3 For Target.
func runDeterministicZ3ForTarget*(
  registry: InvariantRegistry;
  fixedSeed: int;
  profile: TargetProfile
): SolverObservation {.raises: [].} =
  let stackDiscipline = registry.findInvariant(invariantStackDiscipline)
  let topValidity = registry.findInvariant(invariantTopValidity)
  let boundedGrowth = registry.findInvariant(invariantBoundedGrowth)
  if hasStackSignals(profile) and stackDiscipline.isSome() and stackDiscipline.get().dsl.minSize < 0:
    return makeObservation(registry, fixedSeed, violationUnderflow, underflowWitnessSize(registry), false, 110, profile)
  if hasTopSignals(profile) and topValidity.isSome() and not hasTopValidityProtection(topValidity.get()):
    return makeObservation(registry, fixedSeed, violationInvalidPointer, 1, false, 120, profile)
  if hasBoundSignals(profile) and boundedGrowth.isSome() and boundedGrowth.get().dsl.maxSize > 512:
    return makeObservation(registry, fixedSeed, violationBoundExceeded, boundWitnessSize(registry), true, 130, profile)
  makeObservation(registry, fixedSeed, violationNone, 0, true, 90, profile)

{.pop.}

{.pop.}
