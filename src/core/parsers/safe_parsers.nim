import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import std/parseutils
import std/strutils
import core/types/results

func safeParseInt*(s: string): Result[int, string] {.raises: [].} =
  var val: int
  try:
    if parseInt(s, val) > 0: ## nimtry-disable safety-unsafe-parse: canonical wrapper implementation
      ok(val)
    else:
      err("failed to parse integer")
  except ValueError:
    err("failed to parse integer")

func strictParseInt*(s: string): Result[int, string] {.raises: [].} =
  ## Whole-string integer parse — the `strutils.parseInt` consumption
  ## contract as a Result: succeeds only when the ENTIRE string is a decimal
  ## integer. `safeParseInt` keeps std/parseutils prefix semantics
  ## (consumed-length: "1abc" -> ok(1)) for its broad consumers; use this
  ## where trailing garbage must be rejected (e.g. linear RHS constants).
  var val: int
  try:
    let consumed = parseInt(s, val) ## nimtry-disable safety-unsafe-parse: canonical wrapper implementation
    if consumed == s.len and consumed > 0:
      ok(val)
    else:
      err("invalid integer: " & s)
  except ValueError:
    err("invalid integer: " & s)

func safeParseFloat*(s: string): Result[float, string] {.raises: [].} =
  var val: float
  try:
    if parseFloat(s, val) > 0: ## nimtry-disable safety-unsafe-parse: canonical wrapper implementation
      ok(val)
    else:
      err("failed to parse float")
  except ValueError:
    err("failed to parse float")

func safeParseBool*(s: string): Result[bool, string] {.raises: [].} =
  ## Parse "true"/"false" (case-insensitive). Returns Err for any other input.
  let lower = s.toLowerAscii()
  if lower == "true": ok(true)
  elif lower == "false": ok(false)
  else: err("failed to parse bool: " & s)

func safeParseNatural*(s: string): Result[int, string] {.raises: [].} =
  ## Parse a non-negative integer. Returns Err for negative values or invalid input.
  let r = safeParseInt(s)
  if r.isErr(): err(r.error)
  elif r.get() < 0: err("expected non-negative integer, got: " & s)
  else: r

{.pop.}
{.pop.}
