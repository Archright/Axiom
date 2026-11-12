import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## solver_types.nim — SSOT for solver-related domain types.
## Extracted from domain_types.nim (Phase B-4).

import std/options
import core/types/error_types

type
  SolverStatus* = enum
    solverSat
    solverUnsat
    solverUnknown
    solverTimeout
    solverVacuousContradiction

  LogicKind* = enum
    logicQfLia

  SmtExprKind* = enum
    exprIntLit
    exprBoolLit
    exprSymbol
    exprIte
    exprAdd
    exprSub
    exprMul
    exprEq
    exprLt
    exprLe
    exprGt
    exprGe
    exprAnd
    exprOr
    exprNot
    exprImplies

  SmtSExpr* = object
    kind*: SmtExprKind
    text*: string
    args*: seq[SmtSExpr]

  SolverBinding* = object
    name*: string
    value*: string

  SolverCounterExample* = object
    violatedProperty*: string
    trace*: seq[string]
    bindings*: seq[SolverBinding]

  SymbolicFailure* = object
    code*: AxiomError
    message*: string
    solverStatus*: Option[SolverStatus]
    counterExample*: Option[SolverCounterExample]
    smt2*: Option[string]

  SolverEvidence* = object
    solverName*: string
    logic*: LogicKind
    status*: SolverStatus
    queryHash*: string
    smt2*: string
    modelText*: string
    unsatCoreText*: string
    unsatCoreLabels*: seq[string] = @[]  ## parsed label names from unsat core (populated when status == solverUnsat)
    proofTrace*: string
    counterExample*: Option[SolverCounterExample]

  SolverRequest* = object
    logic*: LogicKind
    declarations*: seq[string]
    preconditions*: seq[SmtSExpr]
    assertions*: seq[SmtSExpr]
    labeledPreconditions*: seq[tuple[label: string, expr: SmtSExpr]] = @[]
    labeledAssertions*: seq[tuple[label: string, expr: SmtSExpr]] = @[]
    finalStateSymbol*: string
    checkSat*: bool
    getModel*: bool
    getUnsatCore*: bool

  SolverBridgeResult* = object
    evidence*: SolverEvidence

  KInductionRequest* = object
    k*: int
    baseCase*: SolverRequest
    stepCase*: SolverRequest
    uniquenessConstraints*: seq[SmtSExpr]

{.pop.}
