import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import core/types/results



## Error Bridge — Monadic Adapter for Incremental Refactoring
##
## Provides gripIO/gripVoid templates to convert exception-based code
## into Result-based code without breaking existing callers.
##
## Strategy: "Air-pocket refactoring" — each file is refactored
## independently using these adapters, compiled in isolation,
## and committed one-by-one.

template gripIO*[T](body: T): Result[T, string] =
  ## Convert an expression that may raise into Result[T, string].
  ## Usage: `let r = gripIO(readFileSafe("path"))`
  block:
    var res: Result[T, string]
    try:
      res = ok(body)
    except CatchableError as e:
      res = err(e.msg)
    res

template gripVoid*(body: untyped): Result[void, string] =
  ## Convert a void statement that may raise into Result[void, string].
  ## Usage: `let r = gripVoid(discard writeFileSafe("path", data))`
  block:
    var res: Result[void, string]
    try:
      body
      res = ok()
    except CatchableError as e:
      res = err(e.msg)
    res

template gripOr*[T](body: T, default: T): T =
  ## Execute body, return default on exception.
  ## For cases where caller wants a simple fallback, not Result.
  try:
    body
  except CatchableError:
    default

template gripLog*(body: untyped, logger: untyped): Result[void, string] =
  ## Execute body, log on error, return Result.
  block:
    var res: Result[void, string]
    try:
      body
      res = ok()
    except CatchableError as e:
      logger(e.msg)
      res = err(e.msg)
    res

{.pop.}
