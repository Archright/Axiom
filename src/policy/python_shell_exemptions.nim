## Python/Shell Exemptions (Policy-as-Code)
##
## Every entry MUST have expiryDate, issueId, approvedBy.
## Expired entries cause a compile-time error.
## This file is the SSOT for pre-existing Python/Shell files awaiting Nim port.
##
## CLOSED 2026-07-06: All 35 entries removed — every exempted file has been
## deleted and replaced by its Nim equivalent. See DEBT#242 closure.

import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

import macros/policy_schema_macros
import policy/types

const PythonShellExemptions*: seq[ExemptionEntry] = checkExemptionSchema(@[
  # All previous entries (35) removed on DEBT#242 closure.
  # Re-add here only when a genuinely new Python/Shell file is approved.
])

static:
  validateExemptions(PythonShellExemptions)

{.pop.}
