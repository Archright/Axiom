import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## DRY (Don't Repeat Yourself) queries — exact and alpha-equivalent duplicate detection.

import std/tables
import std/sets
import std/sequtils
import std/algorithm
import std/strutils
import gate/architecture_ast_facts
import core/gate/architecture_policy
import gate/rule_patterns
import gate/nimtry/nimtry_registry

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func isBoilerplateFunction(policy: ArchitecturePolicy; fact: FunctionFact): bool {.raises: [].} =
  if not fact.exported: return true
  if fact.nodeCount < policy.dry.boilerplateNodeCountThreshold: return true
  false

func collectDryFacts(
  exactFingerprints: var Table[string, seq[tuple[path: string; fnName: string]]];
  alphaFingerprints: var Table[string, seq[tuple[path: string; fnName: string]]];
  policy: ArchitecturePolicy;
  facts: ModuleFacts
) {.raises: [].} =
  for fn in facts.functions:
    if isBoilerplateFunction(policy, fn): continue
    if fn.nodeCount < policy.dry.functionCloneMinAstNodes: continue
    exactFingerprints.mgetOrPut(fn.normalizedAstFingerprint, @[]).add((path: facts.path, fnName: fn.name))
    if policy.dry.alphaEquivalence:
      alphaFingerprints.mgetOrPut(fn.alphaFingerprint, @[]).add((path: facts.path, fnName: fn.name))

func addDuplicateViolations(
  result: var seq[ArchitectureViolationArtifact];
  exactFingerprints: Table[string, seq[tuple[path: string; fnName: string]]];
  alphaFingerprints: Table[string, seq[tuple[path: string; fnName: string]]]
) {.raises: [].} =
  var exactDuplicateLabels = initHashSet[string]()
  for fp, entries in exactFingerprints:
    if entries.len < 2: continue
    var files = initHashSet[string]()
    for entry in entries: files.incl(entry.path)
    if files.len < 2: continue
    var labels: seq[string] = @[]
    for entry in entries:
      labels.add(entry.path & "::" & entry.fnName)
    labels.sort(system.cmp[string])
    for label in labels: exactDuplicateLabels.incl(label)
    result.add(ArchitectureViolationArtifact(
      rule: "DRY",
      detail: "exact AST fingerprint duplicate: " & labels.join("; "),
      files: files.toSeq().sorted(system.cmp[string]),
      severity: "error"))
  for fp, entries in alphaFingerprints:
    if entries.len < 2: continue
    var files = initHashSet[string]()
    for entry in entries: files.incl(entry.path)
    if files.len < 2: continue
    var labels: seq[string] = @[]
    for entry in entries:
      labels.add(entry.path & "::" & entry.fnName)
    labels.sort(system.cmp[string])
    var allExact = true
    for label in labels:
      if label notin exactDuplicateLabels:
        allExact = false
    if allExact:
      continue
    result.add(ArchitectureViolationArtifact(
      rule: "DRY",
      detail: "alpha-equivalent AST fingerprint duplicate: " & labels.join("; "),
      files: files.toSeq().sorted(system.cmp[string]),
      severity: "error"))

func addDuplicateStringViolations(
  result: var seq[ArchitectureViolationArtifact];
  constStrings: Table[string, seq[string]]
) {.raises: [].} =
  for literal, files in constStrings:
    let uniqueFiles = files.deduplicate().sorted(system.cmp[string])
    if uniqueFiles.len > 1:
      result.add(ArchitectureViolationArtifact(
        rule: "SSOT",
        detail: "duplicate string constant in " & uniqueFiles.join(", "),
        files: uniqueFiles,
        severity: "error"))

# ---------------------------------------------------------------------------
# Query checkers
# ---------------------------------------------------------------------------

func checkDryDuplicates*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  var exactFingerprints = initTable[string, seq[tuple[path: string; fnName: string]]]()
  var alphaFingerprints = initTable[string, seq[tuple[path: string; fnName: string]]]()
  var constStrings = initTable[string, seq[string]]()
  for facts in allFacts:
    collectDryFacts(exactFingerprints, alphaFingerprints, policy, facts)
    for literal in facts.constStrings:
      constStrings.mgetOrPut(literal.value, @[]).add(facts.path)
  addDuplicateStringViolations(result, constStrings)
  addDuplicateViolations(result, exactFingerprints, alphaFingerprints)

func registerDryQueries*(queries: var seq[NimtryQuery]) {.raises: [].} =
  # ── DRY queries ──────────────────────────────────────────────────────
  # DRY: Exact and alpha-equivalent duplicate detection (from core_rules)
  queries.add(NimtryQuery(
    name: "dry-duplicates",
    rule: "DRY",
    severity: "error",
    taxonomy: structural,
    checker: checkDryDuplicates
  ))


{.pop.}
