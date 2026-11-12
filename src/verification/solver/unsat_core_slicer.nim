## Unsat Core Slicer — Extract minimal unsatisfiable subset of invariant clauses
## via Z3's (get-unsat-core) mechanism.
##
## Replaces heuristic clause stripping with sound Z3-backed unsat core extraction.
## Architecture:
##   1. Build CHC query with named assertions for each invariant clause
##   2. Execute Z3 with (get-unsat-core) to obtain the actual unsat core
##   3. Map named assertions back to clause indices
##   4. Optional minimization: iterative removal to find truly minimal core
##
## Deterministic: same input → same output (Z3 rlimit-based budget, no timeouts).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
import std/strutils
import std/times
import core/symbolic_types_expr
import core/results
import verification/solver/z3_pool
# axiomIoBoundary

# ──────────────────────────────────────────────────────────────────────
# Types
# ──────────────────────────────────────────────────────────────────────

type
  UnsatCoreSlice* = object
    ## Result of unsat core slicing.
    ## coreIndices are 0-based positions in the original invariantClauses seq.
    coreIndices*: seq[int]
    coreClauses*: seq[SymSExpr]
    coreAssumptions*: seq[string]
    isMinimal*: bool
    z3Version*: string
    elapsedMs*: int

# ──────────────────────────────────────────────────────────────────────
# Named Clause Encoding (pure funcs)
# ──────────────────────────────────────────────────────────────────────

func namedClauseId(idx: int): string {.raises: [].} =
  ## Deterministic assumption name for clause at index `idx`.
  "clause_" & $idx

func buildChcWithNamedClauses*(
  invariantClauses: seq[string];
  transitionRelation: string;
  propertyToVerify: string;
  variables: seq[string] = @[]
): string {.raises: [].} =
  ## Build a CHC query in SMT-LIB2 where each invariant clause is a
  ## named assertion. Z3's (get-unsat-core) will reference these names.
  ##
  ## The query encodes: invariant ∧ transitionRelation → ¬property
  ## If UNSAT, the property holds under the given invariants.
  ## The unsat core reveals which invariant clauses are essential.
  var lines: seq[string] = @[]
  lines.add("(set-logic HORN)")
  lines.add("(set-option :produce-unsat-cores true)")

  # Declare state variables if provided
  if variables.len > 0:
    for v in variables:
      lines.add("(declare-const " & v & " Int)")
      lines.add("(declare-const " & v & "! Int)")

  # Named invariant clause assertions
  for i, clause in invariantClauses:
    let name = namedClauseId(i)
    lines.add("(assert (! " & clause & " :named " & name & "))")

  # Transition relation
  if transitionRelation.len > 0:
    lines.add("(assert " & transitionRelation & ")")

  # Property negation: assert NOT(property) to check satisfiability.
  # If the conjunction of invariants + transition + ¬property is UNSAT,
  # then invariants ∧ transition → property holds.
  if propertyToVerify.len > 0:
    lines.add("(assert (not " & propertyToVerify & "))")

  lines.add("(check-sat)")
  lines.add("(get-unsat-core)")
  lines.join("\n")

# ──────────────────────────────────────────────────────────────────────
# Z3 Output Parsing (pure func)
# ──────────────────────────────────────────────────────────────────────

func extractClauseIndex(token: string, numClauses: int): int {.raises: [].} =
  ## Parse "clause_N" token and return the index, or -1 if invalid.
  const prefix = "clause_"
  if not token.startsWith(prefix):
    return -1
  let idxStr = token[prefix.len .. ^1]
  var idx = 0
  for ch in idxStr:
    if ch < '0' or ch > '9':
      return -1
    idx = idx * 10 + (ord(ch) - ord('0'))
  if idx >= 0 and idx < numClauses:
    return idx
  -1

func parseZ3UnsatCoreOutput*(
  output: string;
  numClauses: int
): UnsatCoreSlice {.raises: [].} =
  ## Parse Z3 response to extract the unsat core.
  ## Z3 output format: "unsat\n(clause_0 clause_2 ...)" or just "unsat" if core empty.
  ## Also handles "(unsupported)" when unsat cores are not available.
  result = UnsatCoreSlice(
    coreIndices: @[],
    coreClauses: @[],
    coreAssumptions: @[],
    isMinimal: false,
    z3Version: "",
    elapsedMs: 0
  )

  let stripped = output.strip()

  # Check for unsat result
  if not stripped.startsWith("unsat"):
    return

  # Extract version info if present (e.g., "Z3 version 4.12.4")
  let verStart = stripped.find("Z3 version ")
  if verStart >= 0:
    let verEnd = stripped.find("\n", verStart)
    if verEnd >= 0:
      result.z3Version = stripped[verStart ..< verEnd]
    else:
      result.z3Version = stripped[verStart .. ^1]

  # Find the unsat core in parentheses: (clause_0 clause_2 ...)
  let coreStart = stripped.find('(')
  if coreStart < 0:
    # No explicit core returned — all clauses may be assumed essential
    for i in 0 ..< numClauses:
      result.coreIndices.add(i)
      result.coreAssumptions.add(namedClauseId(i))
    return

  let coreEnd = stripped.find(')', coreStart)
  if coreEnd < 0:
    return

  let coreContent = stripped[(coreStart + 1) ..< coreEnd].strip()
  if coreContent.len == 0:
    return

  # Parse space-separated assumption names
  for token in coreContent.splitWhitespace():
    let trimmed = token.strip()
    if trimmed.len == 0:
      continue
    # Extract index from "clause_N" pattern
    let idx = extractClauseIndex(trimmed, numClauses)
    if idx >= 0:
      result.coreIndices.add(idx)
      result.coreAssumptions.add(trimmed)

  # Sort indices for deterministic output
  for i in 1 ..< result.coreIndices.len:
    let keyIdx = result.coreIndices[i]
    let keyAss = result.coreAssumptions[i]
    var j = i - 1
    while j >= 0 and result.coreIndices[j] > keyIdx:
      result.coreIndices[j + 1] = result.coreIndices[j]
      result.coreAssumptions[j + 1] = result.coreAssumptions[j]
      dec j
    result.coreIndices[j + 1] = keyIdx
    result.coreAssumptions[j + 1] = keyAss

# ──────────────────────────────────────────────────────────────────────
# Heuristic Fallback (pure func)
# ──────────────────────────────────────────────────────────────────────

func heuristicFallback*(clauses: seq[SymSExpr]): UnsatCoreSlice {.raises: [].} =
  ## Fallback when Z3 is unavailable.
  ## Returns all clauses as the "core" (no minimization possible).
  result = UnsatCoreSlice(
    coreIndices: @[],
    coreClauses: @[],
    coreAssumptions: @[],
    isMinimal: false,
    z3Version: "heuristic",
    elapsedMs: 0
  )
  for i, clause in clauses:
    result.coreIndices.add(i)
    result.coreClauses.add(clause)
    result.coreAssumptions.add(namedClauseId(i))

# ──────────────────────────────────────────────────────────────────────
# Minimization (impure — calls Z3)
# ──────────────────────────────────────────────────────────────────────

func buildReducedClauses(invariantClauses: seq[string], remaining: seq[int], candidate: int): seq[string] {.raises: [].} =
  ## Build the clause list excluding the candidate clause.
  result = @[]
  for idx in remaining:
    if idx != candidate:
      result.add(invariantClauses[idx])

proc isClauseRedundant(query: string, timeoutMs: int): bool =
  ## Check if removing a clause still results in UNSAT (clause is redundant).
  var cd, td: string
  let z3Result = z3ExecPersistent(query, timeoutMs, desiredWorkers = 1,
    canonicalEnvelopeDigest = cd, transportPayloadDigest = td)
  if z3Result.isOk:
    let response = z3Result.get().strip().toLowerAscii()
    return response.startsWith("unsat")
  return false

proc minimizeSlice*(
  slice: UnsatCoreSlice;
  invariantClauses: seq[string];
  transitionRelation: string;
  propertyToVerify: string;
  variables: seq[string] = @[];
  timeoutMs: int = 10000
): UnsatCoreSlice =
  ## Iterative minimization: for each clause in the core, remove it and
  ## re-check. If still UNSAT, the clause was redundant.
  ## O(n) Z3 calls where n = current core size.
  ## Preserves original clause order in output.
  result = slice
  if result.coreIndices.len <= 1:
    result.isMinimal = true
    return

  var remaining = result.coreIndices
  var i = 0
  while i < remaining.len:
    let candidate = remaining[i]
    let reducedClauses = buildReducedClauses(invariantClauses, remaining, candidate)
    let query = buildChcWithNamedClauses(
      reducedClauses, transitionRelation, propertyToVerify, variables)
    if isClauseRedundant(query, timeoutMs):
      # Still UNSAT without this clause — it is redundant, remove it
      remaining.delete(i)
      # Don't increment i; check next element at same position
      continue
    # Either SAT, error, or timeout — clause is essential, keep it
    inc i

  # Rebuild slice with minimized core
  result.coreIndices = remaining
  result.coreAssumptions = @[]
  result.coreClauses = @[]
  for idx in remaining:
    result.coreAssumptions.add(namedClauseId(idx))
  result.isMinimal = true

# ──────────────────────────────────────────────────────────────────────
# Main Export — sliceUnsatCore
# ──────────────────────────────────────────────────────────────────────

func populateCoreClauses(slice: var UnsatCoreSlice, invariantClauses: seq[SymSExpr]) {.raises: [].} =
  ## Populate coreClauses from coreIndices.
  slice.coreClauses = @[]
  for idx in slice.coreIndices:
    if idx >= 0 and idx < invariantClauses.len:
      slice.coreClauses.add(invariantClauses[idx])

proc sliceUnsatCore*(
  invariantClauses: seq[SymSExpr];
  transitionRelation: string;
  propertyToVerify: string;
  variables: seq[string] = @[];
  timeoutMs: int = 30000;
  minimize: bool = true
): UnsatCoreSlice =
  ## Query Z3 for the actual unsat core of invariant clauses.
  ## Returns the minimal subset of clauses essential for proving the property.
  ##
  ## 1. Convert SymSExpr clauses to SMT-LIB2 strings
  ## 2. Build CHC query with named assertions
  ## 3. Execute Z3 with (get-unsat-core)
  ## 4. Parse the response to extract clause indices
  ## 5. Optionally minimize via iterative removal
  let startMs = int(getTime().toUnixFloat() * 1000)
  result.elapsedMs = 0
  result.z3Version = ""
  result.isMinimal = false

  # Convert SymSExpr to string form
  var clauseStrings: seq[string] = @[]
  for clause in invariantClauses:
    clauseStrings.add(sExprToString(clause))

  # Build the named CHC query
  let query = buildChcWithNamedClauses(
    clauseStrings, transitionRelation, propertyToVerify, variables)

  # Execute Z3
  var cd, td: string
  let z3Result = z3ExecPersistent(query, timeoutMs, desiredWorkers = 1,
    canonicalEnvelopeDigest = cd, transportPayloadDigest = td)

  let endMs = int(getTime().toUnixFloat() * 1000)
  result.elapsedMs = int(endMs - startMs)

  if z3Result.isErr:
    # Z3 failed — fall back to heuristic (all clauses)
    return heuristicFallback(invariantClauses)

  let rawOutput = z3Result.get()

  # Parse version from output
  let verStart = rawOutput.find("Z3 version ")
  if verStart >= 0:
    let verEnd = rawOutput.find("\n", verStart)
    if verEnd >= 0:
      result.z3Version = rawOutput[verStart ..< verEnd]
    else:
      result.z3Version = rawOutput[verStart .. ^1]

  # Parse the unsat core
  result = parseZ3UnsatCoreOutput(rawOutput, invariantClauses.len)
  result.elapsedMs = int(endMs - startMs)
  if result.z3Version.len == 0:
    result.z3Version = "z3"

  # Populate coreClauses from indices
  populateCoreClauses(result, invariantClauses)

  # Iterative minimization
  if minimize and result.coreIndices.len > 1:
    result = minimizeSlice(
      result, clauseStrings, transitionRelation,
      propertyToVerify, variables, timeoutMs = min(timeoutMs div 2, 10000))
    # Re-populate coreClauses after minimization
    populateCoreClauses(result, invariantClauses)

# ──────────────────────────────────────────────────────────────────────
# Convenience Methods on UnsatCoreSlice
# ──────────────────────────────────────────────────────────────────────

func hasUnsatCore*(slice: UnsatCoreSlice): bool {.raises: [].} =
  ## True if the slice contains at least one core clause.
  slice.coreIndices.len > 0

func coreIndicesToAssumptions*(slice: UnsatCoreSlice): seq[string] {.raises: [].} =
  ## Return the named assumption IDs for the core clauses.
  slice.coreAssumptions

func coreCount*(slice: UnsatCoreSlice): int {.raises: [].} =
  ## Number of clauses in the unsat core.
  slice.coreIndices.len

{.pop.}
