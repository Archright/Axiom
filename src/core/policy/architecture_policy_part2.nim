import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Main parsing entry points and query functions for architecture policy.
##
## Extracted from architecture_policy_parts/architecture_policy_part2.nim
## as a standalone importable module.

import std/os
import std/strutils
import std/sets
import std/tables
import std/sequtils
import core/utils/file_utils
import core/trusted/axiom_pragmas
import core/policy/architecture_policy_types
import core/policy/architecture_policy_part1

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func validateMandatorySections*(result: var ArchitecturePolicyParseResult; seenSections: HashSet[string]) {.raises: [].} =
  for section in [
    "meta", "layer", "layer_edges", "module_roles", "ssot_types",
    "forbidden_calls", "forbidden_assignments", "allowed_assignment_owners",
    "dry"
  ]:
    if section notin seenSections:
      result.diagnostics.add("missing mandatory section " & section)
      result.ok = false
  if result.policy.version != expectedPolicyVersion:
    result.diagnostics.add("unsupported policy version " & result.policy.version)
    result.ok = false
  if result.policy.dry.functionCloneMinAstNodes <= 0:
    result.diagnostics.add("dry.function_clone_min_ast_nodes must be positive")
    result.ok = false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc parseArchitecturePolicy*(content: string): ArchitecturePolicyParseResult {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result.ok = true
  result.policy.dry.functionCloneMinAstNodes = 20
  result.policy.dry.alphaEquivalence = false
  result.policy.dry.boilerplateNodeCountThreshold = 2
  result.policy.surfaceArea.defaultMaxImports = 20
  result.policy.surfaceArea.defaultMaxExportedFunctions = 15
  result.policy.surfaceArea.maxFunctionLines = 50
  var section = ""
  var seenSections = initHashSet[string]()
  var seenKeys = initHashSet[string]()
  var lineNo = 0
  for rawLine in content.splitLines():
    inc lineNo
    let trimmed = rawLine.strip()
    if trimmed.len == 0 or trimmed.startsWith("#"):
      continue
    if trimmed.startsWith("[") and trimmed.endsWith("]"):
      section = trimmed[1 .. ^2].strip()
      if not isKnownSection(section):
        result.addDiagnostic(lineNo, "unknown section " & section)
      else:
        seenSections.incl(section)
      continue
    if section.len == 0:
      result.addDiagnostic(lineNo, "assignment before any section")
      continue
    if not isKnownSection(section):
      continue
    result.parseAssignmentLine(seenKeys, section, trimmed, lineNo)
  result.validateMandatorySections(seenSections)
  if result.diagnostics.len > 0:
    result.diagnostics = sortedStrings(result.diagnostics)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadArchitecturePolicy*(path: string = architecturePolicyPath): ArchitecturePolicyParseResult {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not fileExists(path):
    result.ok = false
    result.diagnostics = @["policy file not found: " & path]
    return
  let content = try: readFileSafe(path) except CatchableError:
    result.ok = false
    result.diagnostics = @["policy file unreadable: " & path]
    return
  parseArchitecturePolicy(content)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func pathMatchesGlob*(path: string; pattern: string): bool {.raises: [].} =
  let normalizedPath = path.replace("\\", "/")
  let normalizedPattern = pattern.replace("\\", "/")
  if normalizedPattern == "**/*.nim":
    return normalizedPath.endsWith(".nim")
  if normalizedPattern.endsWith("/**"):
    let prefix = normalizedPattern[0 .. ^4]
    return normalizedPath == prefix or normalizedPath.startsWith(prefix & "/")
  if normalizedPattern.contains("*"):
    let star = normalizedPattern.find('*')
    let prefix = normalizedPattern[0 ..< star]
    let suffix = normalizedPattern[star + 1 .. ^1]
    return normalizedPath.startsWith(prefix) and normalizedPath.endsWith(suffix)
  # Directory prefix match: "src/core" matches "src/core/gateway.nim"
  if normalizedPath == normalizedPattern:
    return true
  if normalizedPath.startsWith(normalizedPattern & "/"):
    return true
  false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func layerForPath*(policy: ArchitecturePolicy; path: string): string {.raises: [].} =
  var bestLen = -1
  for layerName, patterns in policy.layers:
    for pattern in patterns:
      if pathMatchesGlob(path, pattern) and pattern.len > bestLen:
        bestLen = pattern.len
        result = layerName

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func allowedLayersFor*(policy: ArchitecturePolicy; sourceLayer: string): seq[string] {.raises: [].} =
  policy.layerEdges.getOrDefault(sourceLayer, @[])

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func hasModuleRole*(policy: ArchitecturePolicy; path: string; role: string): bool {.raises: [].} =
  let normalizedRole = role.toLowerAscii()
  for pattern, roles in policy.moduleRoles:
    if pathMatchesGlob(path, pattern) or path == pattern:
      for candidate in roles:
        if candidate.toLowerAscii() == normalizedRole:
          return true
  false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isAssignmentOwner*(policy: ArchitecturePolicy; targetPath: string; path: string): bool {.raises: [].} =
  let owners = policy.allowedAssignmentOwners.getOrDefault(targetPath, @[])
  for owner in owners:
    if pathMatchesGlob(path, owner) or path == owner:
      return true
  false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func forbiddenAssignmentsFor*(policy: ArchitecturePolicy; path: string): seq[string] {.raises: [].} =
  for pattern, targets in policy.forbiddenAssignments:
    if pathMatchesGlob(path, pattern):
      result.add(targets)
  result = result.deduplicate()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func forbiddenCallsFor*(policy: ArchitecturePolicy; path: string): seq[string] {.raises: [].} =
  for pattern, callees in policy.forbiddenCalls:
    if pathMatchesGlob(path, pattern):
      result.add(callees)
  result = result.deduplicate()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isGeneratedModuleWhitelisted*(policy: ArchitecturePolicy; path: string): tuple[whitelisted: bool; fingerprint: string] {.raises: [].} =
  ## Check if a module is in the generated_modules whitelist.
  ## Returns (true, fingerprint) if whitelisted, (false, "") otherwise.
  for modulePath, fp in policy.generatedModules:
    if pathMatchesGlob(path, modulePath) or path == modulePath:
      return (true, fp)
  (false, "")

{.pop.}
