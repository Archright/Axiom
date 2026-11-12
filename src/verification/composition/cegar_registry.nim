import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/options
import std/tables

import core/application/persona_context
import core/symbolic_types_expr
import core/orchestrator/cfg_builder
import core/orchestrator/cegar_types
from verification/cegar_engine import nil
import verification/solver/fixedpoint_engine
import verification/abstract_provider
# axiomIoBoundary

func registerCegar*(ctx: var PersonaContext) {.raises: [].} =
  ctx.z3CheckViaProcess = proc(solverCmd: string; solverArgs: seq[string]): PersonaZ3CheckFn {.closure, raises: [].} =
    cegar_engine.z3CheckViaProcess(solverCmd, solverArgs)

  ctx.runCegarLoop = proc(cfg: ControlFlowGraph; headerId: int; z3Check: PersonaZ3CheckFn; maxIterations: int; budgetMs: int64): CegarEngineResult {.closure, raises: [CatchableError].} =
    cegar_engine.runCegarLoop(cfg, headerId, z3Check, maxIterations, budgetMs)

  ctx.proveWithFixedpoint = proc(cfg: ControlFlowGraph; headerId: int; variables: seq[string]): FixedpointResult {.closure, raises: [].} =
    fixedpoint_engine.proveWithFixedpoint(cfg, headerId, variables)

  ctx.encodeProvedInvariantsSmtlib2 = proc(invariants: seq[SymSExpr]): string {.closure, raises: [].} =
    cegar_engine.encodeProvedInvariantsSmtlib2(invariants)

  ctx.analyzeVariableIntervalsAtLoopHeader = proc(cfg: ControlFlowGraph; headerId: int): Table[string, Interval] {.closure, raises: [].} =
    abstract_provider.analyzeVariableIntervalsAtLoopHeader(cfg, headerId)

  ctx.detectInductionVariables = proc(cfg: ControlFlowGraph; headerId: int): seq[string] {.closure, raises: [].} =
    abstract_provider.detectInductionVariables(cfg, headerId)

  ctx.deriveInvariantCandidates = proc(ctxAbs: AbstractContext): seq[SymSExpr] {.closure, raises: [].} =
    abstract_provider.deriveInvariantCandidates(ctxAbs)

  ctx.extractLoopConditionFromHeader = proc(cfg: ControlFlowGraph; headerId: int): Option[SymSExpr] {.closure, raises: [].} =
    abstract_provider.extractLoopConditionFromHeader(cfg, headerId)

{.pop.}
