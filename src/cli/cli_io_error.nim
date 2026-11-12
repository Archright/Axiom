import core/trusted/layer_declaration
axiomLayer "presentation"
import ../core/trusted/axiom_pragmas
import infrastructure/logging_facade
{.push raises: [CatchableError].}
# axiomIoBoundary

## Die.
  ## axiom-smt: (assert (and ast_parse_failed_isolated (>= (str.len msg) 0) (and (>= code -9223372036854775808) (<= code 9223372036854775807))))
  ## axiom-lean: ast_parse_failed_isolated ∧ msg.length ≥ 0 ∧ code ≥ -9223372036854775808 ∧ code ≤ 9223372036854775807
proc die*(msg: string; code: int = 1) {.axiomTryImpl.} =
  logInfo("cli_io_error", msg)
  quit(code)
{.pop.}
