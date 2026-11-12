import core/trusted/layer_declaration
axiomLayer "trusted.core.io-boundary"

## IO Boundary — Centralized I/O effect declarations
## AGENTS.md §0.6: proc only at I/O boundary, func everywhere else
##
## This module defines the canonical I/O effect interface for the project.
## All I/O operations MUST go through these procs to maintain effect purity
## in the rest of the codebase.
{.push raises: [].}

import std/os

import core/types/results
import core/trusted/axiom_pragmas

type
  IoErrorKind* = enum
    ioFileNotFound
    ioPermissionDenied
    ioReadFailed
    ioWriteFailed
    ioDeleteFailed
    ioCreateDirFailed

  IoResult*[T] = Result[T, IoErrorKind]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc safeReadFile*(path: string): IoResult[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read file contents, returning Result instead of raising
  try:
    result = ok(readFile(path))
  except CatchableError:
    result = err(ioReadFailed)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc safeWriteFile*(path: string, content: string): IoResult[void] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Write file contents, returning Result instead of raising
  try:
    writeFile(path, content)
    result = IoResult[void](ok: true)
  except CatchableError:
    result = err(ioWriteFailed)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc safeDeleteFile*(path: string): IoResult[void] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Delete file, returning Result instead of raising
  try:
    removeFile(path)
    result = IoResult[void](ok: true)
  except CatchableError:
    result = err(ioDeleteFailed)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc safeCreateDir*(path: string): IoResult[void] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Create directory, returning Result instead of raising
  try:
    createDir(path)
    result = IoResult[void](ok: true)
  except CatchableError:
    result = err(ioCreateDirFailed)

{.pop.}
