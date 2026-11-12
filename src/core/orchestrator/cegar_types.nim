import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## CEGAR Types — Pure data types for Counterexample-Guided Abstraction Refinement.
## Extracted from verification/cegar_engine.nim to enable Domain-layer protocols.
## All types are pure data (no I/O, no side effects).
##
## AGENTS.md §1.2: Domain never imports Infrastructure.
## These types allow Domain to define CEGAR concepts without importing verification/.

import core/symbolic/symbolic_types_expr

type
  CegarEngineVerdict* = enum
    cegarProven          ## Fixed-point reached, all invariants verified
    cegarCounterexample  ## Real counterexample found (delegate to BMC)
    cegarMaxIterations   ## Max iterations exhausted
    cegarBudgetExceeded  ## Time budget exceeded

  CegarIteration* = object
    iteration*: int
    candidatesBefore*: int
    candidatesAfter*: int
    operatorUsed*: string    ## name of the refinement operator applied
    z3Accepted*: bool        ## did Z3 accept this iteration's invariants?
    fixedPointReached*: bool

  CegarEngineResult* = object
    verdict*: CegarEngineVerdict
    provedInvariants*: seq[SymSExpr]
    iterations*: int
    elapsedMs*: int64
    refinementHistory*: seq[CegarIteration]
    unsatCoreVars*: seq[string]

{.pop.}
