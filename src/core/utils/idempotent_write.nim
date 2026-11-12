import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/[os]
import core/axiom_pragmas

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc writeFileIdempotent*(path: string, content: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Deterministic write guard: only writes if content actually changed.
  ## Returns true if file was written (content changed).
  ## Returns false if existing content was identical (no-op) or on IO failure.
  ## Preserves mtime when content unchanged → prevents spurious git diffs.
  try:
    if fileExists(path) and readFile(path) == content:
      return false
    writeFile(path, content)
    return true
  except IOError:
    return false
