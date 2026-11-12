## Sweep-line Disjoint Interval Verification for CST token edits.
##
## Provides O(N log N) overlap detection for non-overlapping edit sequences
## used in CST (Concrete Syntax Tree) token manipulation pipelines.
##
## Core invariant: all edits must target disjoint source regions so they
## can be applied in any order without interference.

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/algorithm

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  TokenEdit* = object
    ## A single text replacement spanning a source region.
    startLine*, startCol*: int
    endLine*, endCol*: int
    original*: string
    replacement*: string

# ---------------------------------------------------------------------------
# Helpers (private)
# ---------------------------------------------------------------------------

func startPos(e: TokenEdit): (int, int) =
  ## 2-D start key.
  (e.startLine, e.startCol)

func endPos(e: TokenEdit): (int, int) =
  ## 2-D end key.
  (e.endLine, e.endCol)

func lessPos(x, y: (int, int)): bool =
  ## Strict total order on (line, col) pairs.
  x[0] < y[0] or (x[0] == y[0] and x[1] < y[1])

# ---------------------------------------------------------------------------
# Strict Total Order comparator (4-key)
# ---------------------------------------------------------------------------

func cmpEdit*(a, b: TokenEdit): int =
  ## Compare two edits by (startLine, startCol, endLine, endCol) ascending.
  ##
  ## Returns -1, 0, or 1.  A return of 0 means the two edits target the
  ## **identical** region and are therefore duplicates.
  if a.startLine < b.startLine: return -1
  if a.startLine > b.startLine: return 1
  if a.startCol < b.startCol: return -1
  if a.startCol > b.startCol: return 1
  if a.endLine < b.endLine: return -1
  if a.endLine > b.endLine: return 1
  if a.endCol < b.endCol: return -1
  if a.endCol > b.endCol: return 1
  0

# ---------------------------------------------------------------------------
# Duplicate detection
# ---------------------------------------------------------------------------

func deduplicateEdits*(edits: seq[TokenEdit]): tuple[ok: bool, msg: string] =
  ## Check that no two edits in the sorted sequence are identical (cmp=0).
  ##
  ## `edits` **must** already be sorted by `cmpEdit`.  Returns
  ## `(true, "")` when no duplicates exist, or `(false, msg)` with a
  ## diagnostic message locating the first duplicate pair.
  for i in 0 ..< edits.len - 1:
    if cmpEdit(edits[i], edits[i + 1]) == 0:
      let emsg = "duplicate edit detected at (" & $edits[i].startLine &
                "," & $edits[i].startCol & ")-(" & $edits[i].endLine &
                "," & $edits[i].endCol & ")"
      return (false, emsg)
  (true, "")

# ---------------------------------------------------------------------------
# Overlap detection
# ---------------------------------------------------------------------------

func overlaps*(a, b: TokenEdit): bool =
  ## Determine whether two edits overlap in source text.
  ##
  ## Two edits overlap iff ``a.end > b.start AND b.end > a.start`` using
  ## the 2-D (line, col) coordinate system.
  let aStart = a.startPos()
  let aEnd = a.endPos()
  let bStart = b.startPos()
  let bEnd = b.endPos()
  lessPos(bStart, aEnd) and lessPos(aStart, bEnd)

# ---------------------------------------------------------------------------
# Sweep-line verification
# ---------------------------------------------------------------------------

proc verifyDisjointSweep*(edits: var seq[TokenEdit]): tuple[ok: bool, msg: string] =
  ## Verify that all edits target pairwise-disjoint source regions.
  ##
  ## Algorithm (O(N log N)):
  ##   1. Sort edits by the 4-key comparator.
  ##   2. Check for duplicates via `deduplicateEdits`.
  ##   3. Sweep-line: after sorting by start, any overlap must involve
  ##      adjacent pairs — compare only neighbours.
  ##
  ## Mutates `edits` in place (sorted on return).
  ## Returns `(true, "")` when all edits are disjoint, or
  ## `(false, detail)` on the first detected overlap.

  # Step 1 — sort
  edits.sort(proc (x, y: TokenEdit): int = cmpEdit(x, y))

  # Step 2 — duplicates
  let dedup = deduplicateEdits(edits)
  if not dedup.ok:
    return (false, dedup.msg)

  # Step 3 — sweep-line overlap check on adjacent pairs
  for i in 0 ..< edits.len - 1:
    if overlaps(edits[i], edits[i + 1]):
      let emsg = "overlapping edits at (" & $edits[i].startLine &
                "," & $edits[i].startCol & ")-(" & $edits[i].endLine &
                "," & $edits[i].endCol & ") and (" &
                $edits[i + 1].startLine & "," & $edits[i + 1].startCol &
                ")-(" & $edits[i + 1].endLine & "," &
                $edits[i + 1].endCol & ")"
      return (false, emsg)

  (true, "")

# ---------------------------------------------------------------------------
# Idempotency check
# ---------------------------------------------------------------------------

func editsAreIdempotent*(edits: seq[TokenEdit]): bool =
  ## Verify that applying the edit list twice yields the same result as
  ## applying it once.
  ##
  ## Sufficient condition: no edit's replacement text length causes the
  ## shifted target range of a subsequent edit to collide with another
  ## edit's target range.  In the simple case where all edits have
  ## identical original and replacement lengths, idempotency holds
  ## trivially.  For the general case we check that replacement spans
  ## never overlap any target span.
  for i in 0 ..< edits.len:
    let replEndCol = edits[i].startCol + edits[i].replacement.len
    let replEnd = (edits[i].startLine, replEndCol)
    let iStart = edits[i].startPos()
    for j in 0 ..< edits.len:
      if i == j:
        continue
      let jStart = edits[j].startPos()
      let jEnd = edits[j].endPos()
      # If edit i's replacement "covers" edit j's start, idempotency fails.
      if lessPos(jStart, replEnd) and lessPos(iStart, jEnd):
        return false
  true
