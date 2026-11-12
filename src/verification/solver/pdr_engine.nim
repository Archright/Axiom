import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
# axiomIoBoundary
# verification/solver/pdr_engine.nim — PDR/IC3 Engine via Z3 Spacer
# Property Directed Reachability (PDR/IC3) solver interface.
# Z3's Spacer engine implements PDR internally; this module delegates to it.

import std/strutils
import core/proof/proof_budget
import verification/solver/fixedpoint_engine

const
  DefaultMaxFrames* = 20            ## Default max PDR frames (IC3 depth)
  DefaultMaxGeneralizeDepth* = 3    ## Default max clause generalization depth

type
  PdrConfig* = object
    maxFrames*: int
    z3TimeoutMs*: int
    maxGeneralizeDepth*: int

  PdrResult* = object
    converged*: bool
    inductiveInvariant*: seq[string]
    iterations*: int
    elapsedMs*: int
    error*: string

func extractSmtVariables*(exprs: varargs[string]): seq[string] {.raises: [].} =
  ## Extract unique variable names from SMT-LIB2 expressions.
  ## Filters out SMT keywords, operators, literals, and known function names.
  const keywords = [
    "and", "or", "not", "true", "false", "forall", "exists",
    "declare-var", "declare-rel", "assert", "rule", "query",
    "check-sat", "set-logic", "Int", "Bool", "=>", "ite",
    "state", "init", "trans", "error"
  ]
  var seen: seq[string]
  for expr in exprs:
    var i = 0
    while i < expr.len:
      # Skip whitespace and parens
      if expr[i] in {' ', '(', ')', '\n', '\r', '\t'}:
        inc i
        continue
      # Read a token
      var token = ""
      while i < expr.len and expr[i] notin {' ', '(', ')', '\n', '\r', '\t'}:
        token.add(expr[i])
        inc i
      # Skip empty, keywords, numeric literals, and operators
      if token.len == 0: continue
      if token in keywords: continue
      if token[0] in {'0'..'9', '-'} and token.len > 1 and token[1] in {'0'..'9'}: continue
      if token in ["+", "-", "*", "/", "<", "<=", ">", ">=", "="]: continue
      # Skip _next suffixed (post-state) to avoid duplicates
      if token.endsWith("_next"):
        let base = token[0 ..< token.len - 5]
        if base notin seen:
          seen.add(base)
        continue
      if token notin seen:
        seen.add(token)
  result = seen

proc runPdrEngine*(
  property: string;
  initialState: string;
  transitionRelation: string;
  config: PdrConfig = PdrConfig(maxFrames: 20, z3TimeoutMs: z3SafetyNetMs, maxGeneralizeDepth: 3)
): PdrResult {.raises: [].} =
  ## PDR via Z3 Spacer — delegates to CHC solver.
  ## Z3's Spacer engine uses IC3/PDR internally.
  ## This avoids reimplementing PDR from scratch.
  try:
    let vars = extractSmtVariables(initialState, transitionRelation, property)

    # Build CHC program from init/trans/property
    let chcSource = emitHornClauses(vars, initialState, transitionRelation, property)

    # Solve via Z3 fixedpoint (Spacer uses PDR internally)
    let fpResult = solveFixedpoint(chcSource, timeoutMs = config.z3TimeoutMs)

    if not fpResult.sat and fpResult.invariant.len > 0:
      # UNSAT = property holds, invariant found
      PdrResult(
        converged: true,
        inductiveInvariant: @[fpResult.invariant],
        iterations: 1,
        elapsedMs: 0,
        error: ""
      )
    elif fpResult.sat:
      # SAT = property violated
      PdrResult(
        converged: false,
        inductiveInvariant: @[],
        iterations: 1,
        elapsedMs: 0,
        error: "Counterexample found: " & fpResult.counterexample
      )
    else:
      # Unknown/timeout
      PdrResult(
        converged: false,
        inductiveInvariant: @[],
        iterations: 0,
        elapsedMs: 0,
        error: "PDR solver returned unknown: " & fpResult.rawOutput
      )
  except CatchableError as e:
    PdrResult(
      converged: false,
      inductiveInvariant: @[],
      iterations: 0,
      elapsedMs: 0,
      error: "PDR engine exception: " & e.msg
    )

{.pop.}
