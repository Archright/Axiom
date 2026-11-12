import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
import std/[options, sequtils, strutils, tables]
import core/trusted/axiom_pragmas
import verification/solver_adapter

type
  ObligationResult* = object
    passed*: bool
    obligationName*: string
    smtQuery*: string
    solverStatus*: string
    errorMessage*: string

  ObligationDischarger* = object
    adapter*: SolverAdapter

proc newObligationDischarger*(z3Path: string = "z3"; timeoutMs: int = 5000): ObligationDischarger {.axiomDecision(
  id = "DECISION-0306",
  reason = "Constructor for ObligationDischarger providing Z3-backed obligation discharge (C17)",
  adr = "docs/spec/cfg_contract_specification.md",
  introduced = "v32").} =
  ObligationDischarger(adapter: newSolverAdapter(z3Path, timeoutMs, printCertificate = true))

proc discharge*(discharger: ObligationDischarger; script: string): ObligationResult {.axiomDecision(
  id = "DECISION-0307",
  reason = "Backend-neutral obligation discharge: runs SMT script and returns whether unsat (discharged)",
  adr = "docs/spec/cfg_contract_specification.md",
  introduced = "v32"), raises: [].} =
  let outcome = discharger.adapter.solve(script)
  ObligationResult(
    passed: outcome.status == sosUnsat,
    smtQuery: script,
    solverStatus: $outcome.status,
    errorMessage: if outcome.status == sosUnsat: "" else: outcome.diagnostics
  )

{.pop.}