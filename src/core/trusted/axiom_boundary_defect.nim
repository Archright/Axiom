import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## AxiomBoundaryDefect — Fail-Fast defect for I/O boundary violations.
## Converts CatchableError at I/O boundaries into immediate panics
## to prevent error masking and ensure deterministic failure paths.

type AxiomBoundaryDefect* = object of Defect
  ## Raised when an I/O boundary catches an unexpected CatchableError
  ## that cannot be safely propagated through the effect system.
  ## This guarantees that boundary violations are always visible
  ## and never silently swallowed.

func raiseBoundaryDefect*(msg: string) {.noreturn, raises: [].} =
  ## Raise an AxiomBoundaryDefect with the given message.
  ## Uses rawRaise to bypass effect system constraints.
  raise (ref AxiomBoundaryDefect)(msg: msg)
