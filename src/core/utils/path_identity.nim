# Path Identity — PhysicalPath / LogicalPath Distinct Types
#
# PhysicalPath — absolute, environment-dependent filesystem path.
#   Used for runtime file access (read/write/stat/walk).
#
# LogicalPath — repo-relative, relocation-invariant path.
#   Used for identity/contract computations that must be
#   independent of the physical checkout location.
#
# Conversion boundary: toLogical(PhysicalPath, root): LogicalPath
#   This is the single conversion boundary.
#   The repo root must be passed in (resolved at callsite) so that
#   toLogical itself remains a pure func — no runtime I/O.
#
# Const-context sites (currentSourcePath() / instantiationInfo)
# cannot be wrapped in LogicalPath without breaking const evaluation
# and macro expansion. See docs/spec/artifact_determinism.md §2.4
# for the full deferral registry.

import std/[os, strutils]

type
  PhysicalPath* = distinct string
    ## Absolute filesystem path, environment-dependent.
    ## Used for runtime file access.

  LogicalPath* = distinct string
    ## Repo-relative, relocation-invariant path.
    ## Used for identity/contract computations.

func toLogical*(pp: PhysicalPath; root: string): LogicalPath {.raises: []} =
  ## Convert PhysicalPath → LogicalPath using the provided repo root.
  ## This is the single conversion boundary.
  ## Strips the project root prefix to produce a repo-relative path.
  ## Pure func — root is resolved at the callsite to keep this
  ## function free of runtime I/O.
  let s = string(pp)
  if root.len > 0 and s.startsWith(root):
    let relative = s.substr(root.len)
    LogicalPath(relative.strip(chars = {'/'}))
  else:
    LogicalPath(s)