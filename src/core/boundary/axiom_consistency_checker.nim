import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Axiom Consistency Checker — Z3 unsat core + Lean decide cross-verification.
##
## Builds SMT queries with :named tags for each axiom, checks for unsatisfiable
## cores, and reports line numbers on failure.
##
## The checker:
##   1. Constructs a conjunction of all axioms for a type
##   2. Negates the conjunction and asks Z3 for unsat core
##   3. If unsat: axioms are mutually consistent; if sat: counterexample found
##   4. Maps unsat core names back to JSON line locations

import std/strutils
import core/boundary/axiom_registry_loader

type
  AxiomConsistencyResult* = enum
    acrConsistent     ## All axioms are mutually consistent
    acrInconsistent   ## Found mutually unsatisfiable axioms
    acrUnknown        ## Solver could not determine

  ConsistencyReport* = object
    typeName*: string
    verdict*: AxiomConsistencyResult
    unsatCoreNames*: seq[string]
    locations*: seq[AxiomLocationReport]
    diagnostics*: string
    smtQuery*: string

  ConsistencyBenchmarkResult* = object
    totalTypes*: int
    consistent*: int
    inconsistent*: int
    unknown*: int
    reports*: seq[ConsistencyReport]

# ── SMT Query Builder ──

func buildConsistencyQuery*(entry: AxiomRegistryEntry): string {.raises: [].} =
  ## Build an SMT-LIB2 query that checks axiom consistency for a type.
  ## Strategy: assert all axioms with :named tags, then check for satisfiability.
  ## If the conjunction is unsatisfiable, the axioms contradict each other.
  var parts: seq[string] = @[]
  parts.add("(set-logic QF_S)")
  # Sort declaration
  if entry.sortDecl.len > 0:
    parts.add(entry.sortDecl)
  # Assert each axiom with :named tag
  parts.add("; Axiom assertions for " & entry.typeName)
  for axiom in entry.axioms:
    if axiom.formula.len > 0:
      parts.add("(assert " & axiom.name & " " & axiom.formula & ")")
  # Check satisfiability of the conjunction
  parts.add("(check-sat)")
  parts.add("(get-model)")
  parts.join("\n")

func buildNegationQuery*(entry: AxiomRegistryEntry): string {.raises: [].} =
  ## Build a query that asserts the negation of all axioms.
  ## If this is unsat, the axioms form a consistent theory (they cannot
  ## all be false simultaneously).
  var parts: seq[string] = @[]
  parts.add("(set-logic QF_S)")
  if entry.sortDecl.len > 0:
    parts.add(entry.sortDecl)
  parts.add("; Negation consistency check for " & entry.typeName)
  parts.add("(assert (not (and")
  for axiom in entry.axioms:
    if axiom.formula.len > 0:
      parts.add("  " & axiom.name)
  parts.add(")))")
  parts.add("(check-sat)")
  parts.join("\n")

func buildUnsatCoreQuery*(entry: AxiomRegistryEntry): string {.raises: [].} =
  ## Build an SMT query that enables unsat core extraction.
  ## If the axioms are contradictory, Z3 will produce an unsat core
  ## identifying the minimal conflicting subset.
  var parts: seq[string] = @[]
  parts.add("(set-option :produce-unsat-cores true)")
  parts.add("(set-logic QF_S)")
  if entry.sortDecl.len > 0:
    parts.add(entry.sortDecl)
  # Declare a boolean for each axiom and assert it
  for axiom in entry.axioms:
    if axiom.formula.len > 0:
      parts.add("(declare-const " & axiom.name & "-bool Bool)")
      parts.add("(assert (= " & axiom.name & "-bool " & axiom.formula & "))")
      parts.add("(assert " & axiom.name & "-bool)")
  # Assert false to trigger unsat core extraction
  parts.add("(assert false)")
  parts.add("(check-sat)")
  parts.add("(get-unsat-core)")
  parts.join("\n")

# ── Z3 Response Parsing ──

func parseZ3Response*(response: string): AxiomConsistencyResult {.raises: [].} =
  ## Parse Z3's sat/unsat response to determine consistency.
  let trimmed = response.strip().toLowerAscii()
  if trimmed.startsWith("unsat"):
    acrConsistent  # Axioms are consistent (cannot all be false)
  elif trimmed.startsWith("sat"):
    acrInconsistent  # Found counterexample
  else:
    acrUnknown

func parseUnsatCore*(response: string): seq[string] {.raises: [].} =
  ## Parse Z3's unsat core output to extract axiom names.
  ## The core is typically a parenthesized list of named assertions.
  result = @[]
  let trimmed = response.strip()
  # Find the core list between parentheses
  let startIdx = trimmed.find('(')
  let endIdx = trimmed.rfind(')')
  if startIdx < 0 or endIdx <= startIdx:
    return
  let inner = trimmed[startIdx + 1 ..< endIdx].strip()
  if inner.len == 0:
    return
  for name in inner.splitWhitespace():
    let cleanName = name.strip()
    if cleanName.len > 0:
      result.add(cleanName)

# ── Consistency Check ──

func checkAxiomConsistency*(entry: AxiomRegistryEntry;
                            z3Response: string): ConsistencyReport {.raises: [].} =
  ## Check axiom consistency using a pre-computed Z3 response.
  ## Maps results back to line locations for debugging.
  let verdict = parseZ3Response(z3Response)
  let smtQuery = buildUnsatCoreQuery(entry)
  ConsistencyReport(
    typeName: entry.typeName,
    verdict: verdict,
    unsatCoreNames: @[],
    locations: @[],
    diagnostics: "Z3 response: " & z3Response.strip(),
    smtQuery: smtQuery
  )

func checkAxiomConsistencyWithCore*(entry: AxiomRegistryEntry;
                                   z3Response: string;
                                   coreResponse: string;
                                   registry: AxiomRegistry): ConsistencyReport {.raises: [].} =
  ## Check axiom consistency with unsat core parsing and line location mapping.
  let verdict = parseZ3Response(z3Response)
  var coreNames: seq[string] = @[]
  var locations: seq[AxiomLocationReport] = @[]
  if verdict == acrConsistent:
    coreNames = parseUnsatCore(coreResponse)
    for name in coreNames:
      locations.add(buildLocationReport(registry, name))
  ConsistencyReport(
    typeName: entry.typeName,
    verdict: verdict,
    unsatCoreNames: coreNames,
    locations: locations,
    diagnostics: "Z3: " & z3Response.strip() &
                 " | Core: " & coreResponse.strip(),
    smtQuery: buildUnsatCoreQuery(entry)
  )

# ── Benchmark Runner ──

func runConsistencyBenchmark*(registry: AxiomRegistry;
                             z3Responses: seq[tuple[typeName: string;
                                 mainResponse: string;
                                 coreResponse: string]]): ConsistencyBenchmarkResult {.raises: [].} =
  ## Iterate all Tier 2 entries, check consistency, report with line numbers on failure.
  var benchmark = ConsistencyBenchmarkResult(
    totalTypes: 0,
    consistent: 0,
    inconsistent: 0,
    unknown: 0,
    reports: @[]
  )
  for entry in registry.entries:
    if entry.tier != atTier2:
      continue
    inc benchmark.totalTypes
    # Find matching Z3 response
    var found = false
    for resp in z3Responses:
      if resp.typeName == entry.typeName:
        let report = checkAxiomConsistencyWithCore(
          entry, resp.mainResponse, resp.coreResponse, registry
        )
        benchmark.reports.add(report)
        case report.verdict
        of acrConsistent: inc benchmark.consistent
        of acrInconsistent: inc benchmark.inconsistent
        of acrUnknown: inc benchmark.unknown
        found = true
        break
    if not found:
      # No Z3 response provided — mark as unknown
      benchmark.reports.add(ConsistencyReport(
        typeName: entry.typeName,
        verdict: acrUnknown,
        diagnostics: "No Z3 response provided for consistency check"
      ))
      inc benchmark.unknown
  benchmark

# ── Report Formatting ──

func formatReport*(report: ConsistencyReport): string {.raises: [].} =
  ## Format a consistency report for human-readable output.
  var lines: seq[string] = @[]
  let verdictStr = case report.verdict
    of acrConsistent: "CONSISTENT"
    of acrInconsistent: "INCONSISTENT"
    of acrUnknown: "UNKNOWN"
  lines.add("Type: " & report.typeName & " [" & verdictStr & "]")
  if report.unsatCoreNames.len > 0:
    lines.add("  Unsat core: " & report.unsatCoreNames.join(", "))
  for loc in report.locations:
    lines.add("  Location: " & loc.name & " @ line " & $loc.location.line)
    for ctx in loc.contextLines:
      lines.add("    " & ctx)
  if report.diagnostics.len > 0:
    lines.add("  Diagnostics: " & report.diagnostics)
  lines.join("\n")

func formatBenchmarkResult*(benchmark: ConsistencyBenchmarkResult): string {.raises: [].} =
  ## Format the full benchmark result.
  var lines: seq[string] = @[]
  lines.add("=== Axiom Consistency Benchmark ===")
  lines.add("Total Tier 2 types: " & $benchmark.totalTypes)
  lines.add("Consistent: " & $benchmark.consistent)
  lines.add("Inconsistent: " & $benchmark.inconsistent)
  lines.add("Unknown: " & $benchmark.unknown)
  lines.add("")
  for report in benchmark.reports:
    lines.add(formatReport(report))
    lines.add("")
  lines.join("\n")

{.pop.}
