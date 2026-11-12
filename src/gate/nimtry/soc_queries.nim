import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## SoC (Separation of Concerns) queries — layer import violations and surface area limits.

import std/os
import std/strutils
import std/tables
import gate/architecture_ast_facts
import core/gate/architecture_policy
import gate/rule_patterns
import gate/nimtry/nimtry_registry
import gate/nimtry/call_graph
import core/utils/repo_root
from core/trusted/axiom_pragmas_lite import axiomEffect, AxiomEffectKind, IOEffect, Pure
from core/trusted/effect_bridge import AxiomIOEffect

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc importTargetPath(policy: ArchitecturePolicy; importExpr: string; currentFile: string): string {.raises: [].} =
  var expr = importExpr.strip()
  if expr.len == 0: return ""
  for prefix in policy.externalPackagePrefixes:
    if expr.startsWith(prefix):
      return ""
  if " as " in expr:
    expr = expr.split(" as ")[0].strip()
  if expr.startsWith("../") or expr.startsWith("./"):
    var parts = parentDir(currentFile).split('/')
    for part in expr.split('/'):
      if part == "..":
        if parts.len > 0: discard parts.pop()
      elif part == "." or part.len == 0:
        discard
      else:
        parts.add(part)
    return parts.join("/") & ".nim"
  if '/' in expr:
    return "src/" & expr & ".nim"
  "src/" & expr.replace(".", "/") & ".nim"

# ---------------------------------------------------------------------------
# Query: Surface Area / Layer Limits
# ---------------------------------------------------------------------------

proc checkSurfaceArea(
  policy: ArchitecturePolicy;
  facts: ModuleFacts
): seq[ArchitectureViolationArtifact] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let layer = policy.layerForPath(facts.path)
  let moduleOverride = policy.surfaceArea.moduleOverrides.getOrDefault(facts.path, LayerLimit(
    maxImports: -1, maxExportedFunctions: -1))
  var effectiveMaxExported = policy.surfaceArea.defaultMaxExportedFunctions
  var effectiveMaxImports = policy.surfaceArea.defaultMaxImports
  try:
    let ll = policy.surfaceArea.layerLimits.getOrDefault(layer, LayerLimit(
      maxImports: policy.surfaceArea.defaultMaxImports,
      maxExportedFunctions: policy.surfaceArea.defaultMaxExportedFunctions))
    effectiveMaxExported = ll.maxExportedFunctions
    effectiveMaxImports = ll.maxImports
  except KeyError:
    discard
  if moduleOverride.maxExportedFunctions > 0:
    effectiveMaxExported = moduleOverride.maxExportedFunctions
  if facts.imports.len > effectiveMaxImports:
    result.add(ArchitectureViolationArtifact(
      rule: "SoC",
      detail: facts.path & " has " & $facts.imports.len & " imports (layer " & layer & " max " & $effectiveMaxImports & ")",
      files: @[facts.path],
      severity: "warning"))
  var exportedCount = 0
  for fn in facts.functions:
    if fn.exported:
      inc exportedCount
  if exportedCount > effectiveMaxExported:
    result.add(ArchitectureViolationArtifact(
      rule: "SOLID",
      detail: facts.path & " has " & $exportedCount & " exported functions (layer " & layer & " max " & $effectiveMaxExported & ")",
      files: @[facts.path],
      severity: "warning"))
  # maxFunctionLines check
  let maxFnLines = policy.surfaceArea.maxFunctionLines
  if maxFnLines > 0:
    for fn in facts.functions:
      if fn.effectiveSLOC > maxFnLines:
        result.add(ArchitectureViolationArtifact(
          rule: "SOLID",
          detail: facts.path & ":" & $fn.location.line & " function " & fn.name &
            " spans " & $fn.effectiveSLOC & " effective SLOC (max " & $maxFnLines & ")",
          files: @[facts.path],
          severity: "warning"))

# ---------------------------------------------------------------------------
# Query checkers
# ---------------------------------------------------------------------------

proc checkLayerImportViolations*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for facts in allFacts:
    checkLayerEdges(result, policy, facts, importTargetPath)

  # Filter: allow APPROVED core→verification|gate boundary crossings, scoped per
  # (source file, normalized import target) — NOT per file. A whitelisted file that
  # gains a NEW forbidden-layer import must still be reported (DEBT#495 design-defect
  # clause; decision record docs/history/debt/rl14-4-crossing-decision-2026-10-11.md §3.1).
  # The single authoritative pair list is `core_to_verification_pairs` in
  # src/gate/architecture_policy.lock, encoded as "source.nim|target|reason|expires".
  let pairEntries = policy.layerEdges.getOrDefault("core_to_verification_pairs", @[])
  if pairEntries.len > 0:
    var approvedPairs: seq[(string, string)] = @[]
    for entry in pairEntries:
      let parts = entry.split('|')
      if parts.len < 2: continue
      let src = if parts[0].startsWith("src/"): parts[0] else: "src/" & parts[0]
      approvedPairs.add((src, parts[1]))
    var filtered: seq[ArchitectureViolationArtifact] = @[]
    for violation in result:
      if violation.rule == "SoC" and "forbidden layer" in violation.detail:
        let sourcePath = violation.files[0]
        # detail ends with ": <normalized target>" — recover the target for pair match.
        let sep = violation.detail.rfind(": ")
        let target = if sep >= 0: violation.detail[sep + 2 .. ^1].strip() else: ""
        var isApproved = false
        for (src, tgt) in approvedPairs:
          if src == sourcePath and (target == tgt or target.startsWith(tgt & "/")):
            isApproved = true
            break
        if isApproved:
          continue
      filtered.add(violation)
    result = filtered

proc checkSurfaceAreaWrapper*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for facts in allFacts:
    result.add(checkSurfaceArea(policy, facts))

# ---------------------------------------------------------------------------
# Domain-Level Import Violations (v4.0.0)
# ---------------------------------------------------------------------------
# Checks that imports between core/ subdomains respect [domain_edges] rules.
# Each core/ subdirectory is treated as a domain. Cross-domain imports must
# be declared in the [domain_edges] section of architecture_policy.lock.

import std/json as stdjson

type
  DomainLayout* = object
    domains*: Table[string, seq[string]]  # domain_name -> [allowed_target_domains]
    domainPaths*: Table[string, string]   # domain_name -> import_path

proc loadDomainLayout*(): DomainLayout {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Loads domain_layout.json v4.0.0 and extracts domain edges.
  let layoutPath = findRepoRoot() / "src" / "core" / "domain_layout.json"
  if not fileExists(layoutPath):
    return
  try:
    let content = readFile(layoutPath)
    let root = stdjson.parseJson(content)
    result.domains = initTable[string, seq[string]]()
    result.domainPaths = initTable[string, string]()
    
    let domainsNode = root["domains"]
    for name, info in domainsNode:
      var allowed: seq[string] = @[]
      if info.hasKey("allowed_layers"):
        for layer in info["allowed_layers"]:
          allowed.add(layer.getStr())
      result.domains[name] = allowed
      
      if info.hasKey("import_path"):
        result.domainPaths[name] = info["import_path"].getStr()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc domainForPath*(layout: DomainLayout; path: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Determines which domain a file belongs to based on its path.
  ## e.g., "src/core/bmc/bmc_engine.nim" → "bmc"
  let normalizedPath = path.replace("\\", "/")
  for domainName, importPath in layout.domainPaths:
    if normalizedPath.contains("/" & importPath & "/") or 
       normalizedPath.endsWith("/" & importPath & ".nim"):
      return domainName
  
  # Check if it's a root primitive
  if normalizedPath.contains("/src/core/") and "/" notin normalizedPath.split("/src/core/")[^1]:
    return "root"

proc checkDomainImportViolations*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Checks that imports between core/ subdomains respect [domain_edges] rules.
  let layout = loadDomainLayout()
  if layout.domains.len == 0:
    return  # No layout loaded, skip check

  for facts in allFacts:
    let sourceDomain = domainForPath(layout, facts.path)
    if sourceDomain.len == 0 or sourceDomain == "root":
      continue  # Not in a tracked domain

    let allowedTargets = layout.domains.getOrDefault(sourceDomain, @[])
    # Root primitives are always allowed (types, results, etc.)
    let alwaysAllowed = @["root", sourceDomain]

    for imp in facts.imports:
      let rawModule = imp.modulePath
      let ln = imp.location.line
      let col = imp.location.column
      let targetPath = importTargetPath(policy, rawModule, facts.path)
      if targetPath.len == 0:
        continue
      
      # Only check core/ internal imports
      if not targetPath.contains("/src/core/"):
        continue
      
      let targetDomain = domainForPath(layout, targetPath)
      if targetDomain.len == 0 or targetDomain in alwaysAllowed:
        continue
      
      if targetDomain notin allowedTargets and targetDomain != "root":
        # Check if it's a facade/SSOT pattern (always allowed)
        if targetDomain in layout.domains:
          result.add(ArchitectureViolationArtifact(
            rule: "SoC",
            detail: facts.path & ":" & $ln & ":" & $col &
              " domain '" & sourceDomain & "' imports from '" & targetDomain & 
              "' (not in [domain_edges])",
            files: @[facts.path],
            severity: "warning"))

proc registerSocQueries*(queries: var seq[NimtryQuery]) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # ── SoC queries ──────────────────────────────────────────────────────
  # SoC: Transitive layer violations (from query_engine)
  queries.add(NimtryQuery(
    name: "soc-transitive",
    rule: "SoC",
    severity: "warning",
    taxonomy: structural,
    checker: proc(allFacts: seq[ModuleFacts]; policy: ArchitecturePolicy): seq[ArchitectureViolationArtifact] {.raises: [].} =
      buildCallGraphAndCheck(allFacts, policy, maxDepth = 2)
  ))

  # SoC: Layer import violations (from core_rules)
  queries.add(NimtryQuery(
    name: "soc-layer-imports",
    rule: "SoC",
    severity: "error",
    taxonomy: structural,
    checker: checkLayerImportViolations
  ))

  # SoC/SOLID: Surface area limits (from core_rules)
  queries.add(NimtryQuery(
    name: "soc-surface-area",
    rule: "SoC",
    severity: "warning",
    taxonomy: structural,
    checker: checkSurfaceAreaWrapper
  ))

  # SoC: Domain-level import violations (v4.0.0)
  # Checks that imports between core/ subdomains respect [domain_edges]
  queries.add(NimtryQuery(
    name: "soc-domain-imports",
    rule: "SoC",
    severity: "warning",
    taxonomy: structural,
    checker: proc(allFacts: seq[ModuleFacts]; policy: ArchitecturePolicy): seq[ArchitectureViolationArtifact] {.raises: [].} =
      checkDomainImportViolations(allFacts, policy)
  ))

{.pop.}


