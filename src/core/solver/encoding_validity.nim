import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Direct Validity Query Encoder
##
## For DAG (acyclic) functions, instead of k-induction,
## directly encode the VC as a validity query:
##   (assert (not property)) → unsat = proved
##
## This is faster and more precise than k-induction for pure functions.
## The VC is built from the function's precondition → postcondition implication.
##
## User refinement (Plan v5): "DAG → Direct Validity Query —
## DAG 함수는 k-induction 없이 직접 VC 인코딩 후 unsat 확인"

import core/bmc/bmc_types

type
  ValidityQueryKind* = enum
    vqPreconditionViolation   ## Precondition can be violated
    vqPostconditionViolation  ## Postcondition can be violated
    vqInvariantViolation      ## Loop invariant can be violated (for reducible)

  ValidityPayload* = object
    ## A direct validity query payload.
    declarations*: seq[string]
    assertions*: seq[string]      ## Positive assertions (preconditions, invariants)
    negatedGoal*: string          ## (not property) — what we want to prove unsat
    smt2*: string                 ## Complete SMT-LIB2 string
    kind*: ValidityQueryKind
    functionName*: string

func buildValidityPayload*(
    declarations: seq[string];
    preconditions: seq[string];
    postcondition: string;
    functionName: string = "";
    kind: ValidityQueryKind = vqPostconditionViolation
): ValidityPayload {.noSideEffect.} =
  ## Build a direct validity query.
  ##
  ## The query asks: "given the preconditions, can the postcondition be violated?"
  ## If Z3 returns UNSAT, the postcondition holds.
  ##
  ## SMT-LIB2 structure:
  ##   (set-logic QF_LIA)
  ##   (declare-const x Int)
  ##   ... declarations ...
  ##   (assert precondition1)
  ##   (assert precondition2)
  ##   ... preconditions ...
  ##   (assert (not postcondition))  ← negated goal
  ##   (check-sat)

  var smt = "(set-logic QF_LIA)\n"

  # Declarations
  for decl in declarations:
    smt.add("(declare-const " & decl & " Int)\n")

  # Preconditions (positive assertions)
  var assertions: seq[string] = @[]
  for pre in preconditions:
    smt.add("(assert " & pre & ")\n")
    assertions.add(pre)

  # Negated goal
  let negGoal = "(not " & postcondition & ")"
  smt.add("(assert " & negGoal & ")\n")
  smt.add("(check-sat)\n")

  return ValidityPayload(
    declarations: declarations,
    assertions: assertions,
    negatedGoal: negGoal,
    smt2: smt,
    kind: kind,
    functionName: functionName
  )

func buildValidityFromInvariant*(
    declarations: seq[string];
    invariantRule: InvariantRule;
    variableSymbol: string = "x";
    functionName: string = ""
): ValidityPayload {.noSideEffect.} =
  ## Build a validity query from an InvariantRule.
  ##
  ## For invariantMinValue: prove (x >= minValue)
  ## For invariantMaxValue: prove (x <= maxValue)
  ##
  ## This produces a trivial SMT query that Z3 can solve instantly.
  let symbol = variableSymbol

  case invariantRule.kind
  of invariantMinValue:
    let postcondition = "(>= " & symbol & " " & $invariantRule.minValue & ")"
    return buildValidityPayload(
      declarations = declarations,
      preconditions = @[],
      postcondition = postcondition,
      functionName = functionName,
      kind = vqPostconditionViolation
    )
  of invariantMaxValue:
    let postcondition = "(<= " & symbol & " " & $invariantRule.maxValue & ")"
    return buildValidityPayload(
      declarations = declarations,
      preconditions = @[],
      postcondition = postcondition,
      functionName = functionName,
      kind = vqPostconditionViolation
    )

func buildValidityFromTransition*(
    declarations: seq[string];
    transitionRule: TransitionRule;
    initialValue: int;
    variableSymbol: string = "x";
    functionName: string = ""
): ValidityPayload {.noSideEffect.} =
  ## Build a validity query encoding the transition relation.
  ##
  ## For transitionAdd with delta=5, initialValue=10:
  ##   declare x0, x1
  ##   assert x0 = 10
  ##   assert x1 = x0 + 5
  ##   assert (not (x1 >= 0))  ← can result go negative?
  ##
  ## This is a 1-step reachability query — much simpler than k-induction.
  let x0 = variableSymbol & "_0"
  let x1 = variableSymbol & "_1"

  var decls = declarations
  if x0 notin decls: decls.add(x0)
  if x1 notin decls: decls.add(x1)

  var preconditions: seq[string] = @[
    "(= " & x0 & " " & $initialValue & ")"
  ]

  case transitionRule.op
  of transitionAdd:
    preconditions.add("(= " & x1 & " (+ " & x0 & " " & $transitionRule.delta & "))")
  of transitionSub:
    preconditions.add("(= " & x1 & " (- " & x0 & " " & $transitionRule.delta & "))")

  # Default postcondition: result >= 0 (no underflow)
  let postcondition = "(>= " & x1 & " 0)"

  return buildValidityPayload(
    declarations = decls,
    preconditions = preconditions,
    postcondition = postcondition,
    functionName = functionName,
    kind = vqPostconditionViolation
  )

{.pop.}
