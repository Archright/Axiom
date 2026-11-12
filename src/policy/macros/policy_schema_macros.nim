## Policy Schema Macros
## Compile-time validators for policy data structures.
## These turn schema violations into compiler errors.

import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

import std/[strutils, sets]
import std/macros
import policy/types

macro checkExemptionSchema*(entriesExpr: untyped): untyped =
  ## Macro that returns the input seq literal unchanged after validating it
  ## at compile time. Validation is performed in a static block after the
  ## const is declared, because macros cannot easily evaluate distinct-type
  ## literals; the static block can.
  ##
  ## Usage:
  ##   const PythonShellExemptions* = checkExemptionSchema(@[...])
  result = entriesExpr

macro checkAllowedLibSchema*(entriesExpr: untyped): untyped =
  ## Same as checkExemptionSchema, for AllowedLibEntry.
  result = entriesExpr

func validateExemptions*(entries: seq[ExemptionEntry]) {.compileTime.} =
  ## Compile-time validation of exemption entries.
  ## - issueId MUST match AX-<digits>
  ## - reason and approved_by MUST be non-empty
  ## - expiry_date MUST parse as YYYY-MM-DD (expiry check is runtime)
  ## - paths MUST be unique
  var seenPaths: HashSet[string]
  for e in entries:
    let path = $e.path
    let issueId = $e.issueId
    let reason = $e.reason
    let approvedBy = $e.approvedBy

    if reason.len == 0:
          macros.error("EXEMPTION SCHEMA VIOLATION: reason is required for " & path)

    if approvedBy.len == 0:
          macros.error("EXEMPTION SCHEMA VIOLATION: approved_by is required for " & path)

    if not (issueId.len > 3 and issueId.startsWith("AX-") and
            issueId[3..^1].allCharsInSet(Digits)):
        macros.error("EXEMPTION SCHEMA VIOLATION: issueId '" & issueId &
        "' must match AX-<digits> in " & path)
    if path in seenPaths:
          macros.error("EXEMPTION SCHEMA VIOLATION: duplicate path " & path)

    seenPaths.incl(path)

    let expiry = $e.expiryDate
    if expiry.len != 10 or expiry[4] != '-' or expiry[7] != '-':
          macros.error("EXEMPTION SCHEMA VIOLATION: expiry_date '" & expiry &

            "' must be YYYY-MM-DD in " & path)

func validateAllowedLibs*(entries: seq[AllowedLibEntry]) {.compileTime.} =
  ## Compile-time validation of allowed library entries.
  ## - id MUST be non-empty
  ## - names MUST be non-empty and contain no empty entries
  ## - reason MUST be non-empty
  ## - ids MUST be unique
  var seenIds: HashSet[string]
  for e in entries:
    let id = $e.id
    let reason = $e.reason

    if id.len == 0:
          macros.error("ALLOWED LIB SCHEMA VIOLATION: id is required")

    if reason.len == 0:
          macros.error("ALLOWED LIB SCHEMA VIOLATION: reason is required for " & id)

    if e.names.len == 0:
          macros.error("ALLOWED LIB SCHEMA VIOLATION: names must not be empty for " & id)

    for n in e.names:
      if ($n).len == 0:
        error("ALLOWED LIB SCHEMA VIOLATION: empty name in " & id)
    if id in seenIds:
          macros.error("ALLOWED LIB SCHEMA VIOLATION: duplicate id " & id)

    seenIds.incl(id)

{.pop.}
