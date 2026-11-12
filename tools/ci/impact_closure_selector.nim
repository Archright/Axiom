## impact_closure_selector.nim — P3 Shadow Mode
##
## Deterministically computes which CI work units are affected by a git diff,
## without wiring into CI. Outputs a machine-readable JSON shadow report.
##
## Usage:
##   impact-closure --base <ref> --head <ref> [options]
##   impact-closure --base main --head HEAD
##
## Design invariants (from docs/spec/incremental_ci_contract.md §4):
##   1. affected(U, Δ) ≡ closure(Δ) ∩ inputClosure(U) ≠ ∅
##   2. Skip allowed ONLY when affected(U, Δ) is provably false.
##   Conservative over-approximation: unknown → broader unit affected.
##
## Limitations (documented):
##   - import_graph.nim cannot be imported due to checksums/sha2 dependency gap
##     in this Nim 2.2.10 environment; core transitive-dependency resolution is
##     reimplemented inline (same algorithm: buildImportGraph → buildReverseGraph →
##     transitiveDependents BFS). Gate-target closure beyond core is a known gap.
##   - ci-lake-build (W9) has UNKNOWN duration; excluded from cost sums.
##   - Normative doc → cache-key invalidation (G4) is not yet wired.
##   - Makefile pervasive-invocation over-approximation may over-claim W1–W9.

import core/trusted/layer_declaration
import core/trusted/axiom_pragmas_lite
axiomLayer "tools"

# W-axis single editing authority: id/name/pathPatterns/duration/tier + the
# repo-level certified no-effect declarations all live in the catalog module.
import gate/proof_unit_catalog

import std/[os, osproc, strutils, strformat, sequtils, sets, tables, json, algorithm,
            options, parseopt, times, math, xmltree, xmlparser]

# ═══════════════════════════════════════════════════════════════════════════
# §0: Compile-time guard
# ═══════════════════════════════════════════════════════════════════════════

static:
  when NimMajor != 2 or NimMinor != 2:
    {.error: "Impact Closure Selector requires Nim v2.2.x".}

# ═══════════════════════════════════════════════════════════════════════════
# §1: Types
# ═══════════════════════════════════════════════════════════════════════════

type
  WorkUnitId* = string

  WorkUnit* = object
    id*: string                     # e.g. "W1", "W4/G1"
    name*: string                   # human-readable name
    pathPatterns*: seq[string]      # glob patterns for direct file matching
    semanticRules*: seq[string]     # special rules (see §3)
    duration*: string               # measured duration or "UNKNOWN"
    provenance*: string             # source of duration data
    isContainer*: bool              # true if this unit contains sub-steps

  ChangedFile* = object
    path*: string
    status*: string                 # A/M/D/C/R from git diff --name-status
    blobHash*: string               # git blob hash at HEAD

  AffectedUnit* = object
    unit*: WorkUnit
    reason*: string                 # which changed file(s) triggered it, via which rule

  ShadowReport* = object
    base*: string
    head*: string
    changeFingerprint*: string
    changedFiles*: seq[ChangedFile]
    selectedUnits*: seq[AffectedUnit]
    estimatedCostMinutes*: float
    fullPipelineCostMinutes*: float
    costSavingsMinutes*: float
    savingsPercent*: float
    limitations*: seq[string]
    planStatus*: string            # "VALID" | "FALLBACK_REQUIRED" | "ERROR" (§12)
    certainty*: string             # "CERTAIN" | "UNCERTAIN" (§12)
    uncertaintyReasons*: seq[string]  # non-empty iff certainty == "UNCERTAIN"

# ═══════════════════════════════════════════════════════════════════════════
# §2: Work Unit construction — from the single editing authority
# ═══════════════════════════════════════════════════════════════════════════
#
# W-axis facts (id, name, pathPatterns, durationMin, tier) come exclusively
# from src/gate/proof_unit_catalog.nim (ProofUnitCatalog, cutover 2026-09-23).
# The selector-side decoration below (provenance, isContainer, semanticRules
# labels) is runtime-behavior data that the catalog schema deliberately does
# not own; the semantic rule ALGORITHMS live in mapToWorkUnits §7.

func durationToText(durationMin: float): string {.raises: [].} =
  ## Render catalog durationMin to the legacy textual form ("UNKNOWN" for NaN).
  if isNaN(durationMin):
    result = "UNKNOWN"
  else:
    result = formatFloat(durationMin, ffDecimal, 2)

func semanticRulesFor(id: string): seq[string] {.raises: [].} =
  ## Informational rule labels per unit (consumed by nothing but preserved for
  ## WorkUnit parity; the rule logic itself is §7's hardcoded steps).
  case id
  of "W1": result = @["scans_all_source"]
  of "W2": result = @["compiles_release_bin"]
  of "W3": result = @["depends_on_W2_output"]
  of "W4": result = @["contract_tests_exercise_core", "depends_on_W2_output"]
  of "W5": result = @["nimble_install_rebuilds_all"]
  of "W7": result = @["scans_all_source_via_topology"]
  of "W8": result = @["gateway_binaries_compile_src"]
  of "W11": result = @["engine_imports_core_transitively", "generated_build_env"]
  else: discard

func provenanceFor(id: string): string {.raises: [].} =
  ## Source of the duration measurement (report provenance field).
  case id
  of "W1", "W10", "W11": result = "[gh-run]"
  of "W9": result = "[gh-run] ran; timing not exposed"
  of "W3": result = "[critical-path-report]"
  else: result = "[migration-doc]"

func isContainerFor(id: string): bool {.raises: [].} =
  ## True if the unit contains sub-steps (mirrors the pre-catalog table).
  result = id in ["W1", "W2", "W4", "W5", "W6", "W7", "W8"]

const
  ## Every W id referenced by the §7 semantic-rule / over-approximation steps,
  ## validated against the catalog at compile time (fail closed on drift).
  SemanticRuleStepIds = [
    "W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8", "W9", "W10", "W11"
  ]
  CatalogIds = block:
    var ids: seq[string]
    for u in ProofUnitCatalog:
      ids.add(u.id)
    ids

static:
  # Fail-closed: rule steps may only reference units that exist in the catalog.
  for rid in SemanticRuleStepIds:
    doAssert rid in CatalogIds,
      "semantic rule references work unit not in ProofUnitCatalog: " & rid
  # Catalog-internal hygiene: unique ids.
  var seenIds: seq[string]
  for u in ProofUnitCatalog:
    doAssert u.id notin seenIds, "duplicate unit id in ProofUnitCatalog: " & u.id
    seenIds.add(u.id)

proc makeWorkUnits*(): seq[WorkUnit] {.raises: [].} =
  ## Return the W1–W11 work unit catalog with their input closure patterns.
  ## W-axis facts are sourced from ProofUnitCatalog (single editing authority);
  ## this proc adds only the selector-side decoration defined above.
  ## Conservative over-approximation: patterns are intentionally broad where
  ## the contract §3.2 requires it (unknown → broader unit).
  result = @[]
  for u in ProofUnitCatalog:
    result.add WorkUnit(
      id: u.id,
      name: u.name,
      pathPatterns: u.pathPatterns,
      semanticRules: semanticRulesFor(u.id),
      duration: durationToText(u.durationMin),
      provenance: provenanceFor(u.id),
      isContainer: isContainerFor(u.id)
    )

# ═══════════════════════════════════════════════════════════════════════════
# §3: Pattern matching helpers (pure, func)
# ═══════════════════════════════════════════════════════════════════════════

func matchPattern*(filePath, pattern: string): bool {.raises: [].} =
  ## Match a file path against a pattern.
  ## Patterns ending in '/' are directory prefixes.
  ## Patterns containing '*' are glob-like (simple prefix/suffix match).
  ## Patterns without special chars are exact or prefix matches.
  if pattern.endsWith("/"):
    result = filePath.startsWith(pattern) or filePath.startsWith("./" & pattern)
  elif "*" in pattern:
    let parts = pattern.split("*")
    if parts.len == 2:
      result = filePath.startsWith(parts[0]) and filePath.endsWith(parts[1])
    else:
      result = pattern in filePath
  else:
    result = filePath == pattern or filePath.endsWith("/" & pattern)

func matchesAnyPattern*(filePath: string, patterns: seq[string]): bool {.raises: [].} =
  for pattern in patterns:
    if matchPattern(filePath, pattern):
      return true
  result = false

# ═══════════════════════════════════════════════════════════════════════════
# §4: Core import graph (reimplementation of import_graph.nim algorithms)
##  import_graph.nim cannot be imported due to checksums/sha2 dependency gap
##  in this environment. The algorithms below are direct reimplementations of
##  buildImportGraph, buildReverseGraph, and transitiveDependents.
# ═══════════════════════════════════════════════════════════════════════════

proc resolveCoreModule*(currentDir, importExpr: string): string {.raises: [].} =
  ## Resolve a Nim import expression to a core/ module path.
  ## Returns empty string if not a core/ module.
  ## NOTE: fileExists is allowed here (no effect-tag enforcement on this
  ## reimplementation); returns "" when unresolvable.
  var expr = importExpr.strip()
  if " as " in expr:
    expr = expr.split(" as ")[0].strip()
  if " except " in expr:
    expr = expr.split(" except ")[0].strip()

  if expr.startsWith("std/") or expr.startsWith("vendor/"):
    return ""

  if expr.startsWith("core/"):
    result = expr[5..^1]
  elif expr.startsWith("./") or expr.startsWith("../"):
    var base = currentDir
    var remaining = expr
    while remaining.startsWith("../"):
      base = parentDir(base)
      remaining = remaining[3..^1]
    if remaining.startsWith("./"):
      remaining = remaining[2..^1]
    result = base / remaining
    result = result.replace("\\", "/")
    if result.startsWith("src/core/"):
      result = result[9..^1]
    elif result.startsWith("core/"):
      result = result[5..^1]
  else:
    let localPath = currentDir / expr
    if fileExists(localPath & ".nim"):
      result = localPath.replace("\\", "/")
      if result.startsWith("src/core/"):
        result = result[9..^1]
      elif result.startsWith("core/"):
        result = result[5..^1]
    else:
      let corePath = "src/core" / expr
      if fileExists(corePath & ".nim"):
        result = expr
      else:
        result = ""

proc extractCoreImports*(filePath: string): seq[string] {.raises: [], axiomEffect: IoEffect.} =
  ## Extract all imports that resolve to core/ modules from a file.
  result = @[]
  let content = try: readFile(filePath) except CatchableError: ""
  if content.len == 0:
    return

  var currentDir = ""
  try:
    currentDir = parentDir(absolutePath(filePath))
  except CatchableError:
    currentDir = parentDir(filePath)
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if not (line.startsWith("import ") or line.startsWith("from ")):
      continue
    let prefix = if line.startsWith("import "): "import " else: "from "
    let after = line[prefix.len..^1]
    for part in after.split(','):
      let modName = resolveCoreModule(currentDir, part)
      if modName.len > 0 and modName notin result:
        result.add(modName)

proc buildCoreImportGraph*(): Table[string, seq[string]] =
  ## Build a dependency graph of all modules under src/core/.
  ## Returns empty table if src/core/ not found.
  ## NOTE: This is a reimplementation of import_graph.buildImportGraph
  ## because checksums/sha2 is unavailable in this environment.
  ## walkDirRec can raise OSError, so wrap in try/except (see
  ## annotation_hygiene_gate.nim — must NOT carry raises/axiomEffect).
  let coreDir = "src/core"
  if not dirExists(coreDir):
    return initTable[string, seq[string]]()

  result = initTable[string, seq[string]]()
  try:
    for path in walkDirRec(coreDir, {pcFile}):
      if not path.endsWith(".nim"):
        continue
      let relPath = path[coreDir.len+1..^5]  # strip "src/core/" and ".nim"
      let imports = extractCoreImports(path)
      if imports.len > 0:
        result[relPath] = imports
  except OSError:
    discard

func buildReverseGraph*(graph: Table[string, seq[string]]): Table[string, seq[string]] {.raises: [].} =
  ## Build reverse dependency graph: if A imports B, reverseGraph[B] contains A.
  ## Reimplementation of import_graph.buildReverseGraph.
  result = initTable[string, seq[string]]()
  for src, deps in graph:
    for dep in deps:
      result.mgetOrPut(dep, @[]).add(src)
  for src in graph.keys:
    if src notin result:
      result[src] = @[]

func transitiveDependents*(
    reverseGraph: Table[string, seq[string]],
    changedModules: HashSet[string]): HashSet[string] {.raises: [].} =
  ## BFS through reverse edges from changedModules to find all transitively
  ## affected modules. Reimplementation of import_graph.transitiveDependents.
  result = changedModules
  var queue: seq[string]
  for m in changedModules:
    queue.add(m)
  while queue.len > 0:
    let current = queue[^1]
    queue.setLen(queue.len - 1)
    for dependent in reverseGraph.getOrDefault(current):
      if dependent notin result:
        result.incl(dependent)
        queue.add(dependent)

# ═══════════════════════════════════════════════════════════════════════════
# §5: Git helpers (I/O boundary, proc)
# ═══════════════════════════════════════════════════════════════════════════

proc runGit*(args: string): string {.axiomEffect: IoEffect.} =
  ## Run a git command and return trimmed stdout. Raises on failure.
  let cmd = "git " & args
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    raise newException(OSError, &"git {args} failed (exit {exitCode}): {output.strip()}")
  result = output.strip()

proc getChangedFiles*(base, head: string): seq[ChangedFile] {.axiomEffect: IoEffect.} =
  ## Get the set of changed files between base and head using git diff.
  let diffOutput = runGit(&"diff --name-status {base}..{head}")
  if diffOutput.len == 0:
    return @[]

  for line in diffOutput.splitLines():
    let parts = line.split('\t')
    if parts.len < 2:
      continue
    let status = parts[0].strip()
    let filePath = parts[1].strip()
    if filePath.len == 0:
      continue

    # Get blob hash at HEAD for this file
    var blobHash = ""
    try:
      let treeOutput = runGit(&"ls-tree HEAD -- {filePath}")
      let treeParts = treeOutput.split('\t')
      if treeParts.len >= 1:
        let headerParts = treeParts[0].split(' ')
        if headerParts.len >= 3:
          blobHash = headerParts[2]
    except CatchableError:
      blobHash = "00000000000000000000000000000000000000"

    result.add ChangedFile(path: filePath, status: status, blobHash: blobHash)

  result.sort(proc(a, b: ChangedFile): int = cmp(a.path, b.path))

# ═══════════════════════════════════════════════════════════════════════════
# §6: Change fingerprint (deterministic hash of the change set)
# ═══════════════════════════════════════════════════════════════════════════

proc computeFingerprint*(changedFiles: seq[ChangedFile]): string {.axiomEffect: IoEffect.} =
  ## Compute a deterministic SHA256 fingerprint of the change set.
  ## Canonical form: sorted "filepath blobhash" lines, piped through sha256sum.
  var canonical = ""
  for cf in changedFiles:
    canonical &= cf.path & " " & cf.blobHash & "\n"

  let tmpFile = getTempDir() / "axiom_impact_fingerprint_input"
  writeFile(tmpFile, canonical)
  defer: removeFile(tmpFile)

  let (output, exitCode) = execCmdEx(&"sha256sum {tmpFile}")
  if exitCode != 0:
    # Fallback (deterministic, no shell escaping): hash the temp file via git.
    let (fallbackOutput, _) = execCmdEx(&"git hash-object {tmpFile}")
    result = "sha256:" & fallbackOutput.strip()
  else:
    result = "sha256:" & output.strip().split(' ')[0]

# ═══════════════════════════════════════════════════════════════════════════
# §7: Closure mapping — changed files → affected work units
# ═══════════════════════════════════════════════════════════════════════════

proc mapToWorkUnits*(changedFiles: seq[ChangedFile]): seq[AffectedUnit] =
  ## Map each changed file to affected work units using the matrix rules.
  ## Implements the conservative over-approximation from contract §3.2:
  ##   - Unknown dependency → broader unit affected
  ##   - Never under-approximate
  let units = makeWorkUnits()
  var affected: Table[string, AffectedUnit]

  # Collect changed file paths and identify which are in src/core/
  var changedPaths: HashSet[string]
  var changedCoreFiles: seq[string]
  var changedSrcFiles: seq[string]
  for cf in changedFiles:
    changedPaths.incl(cf.path)
    if cf.path.startsWith("src/core/"):
      changedCoreFiles.add(cf.path)
    if cf.path.startsWith("src/"):
      changedSrcFiles.add(cf.path)

  # Step 1: Direct path-pattern matching for each work unit
  for unit in units:
    var matchedFiles: seq[string] = @[]
    for cf in changedFiles:
      if matchesAnyPattern(cf.path, unit.pathPatterns):
        matchedFiles.add(cf.path)

    if matchedFiles.len > 0:
      let joinedFiles = matchedFiles.join(", ")
      let reason = &"direct path match: {joinedFiles}"
      if unit.id notin affected:
        affected[unit.id] = AffectedUnit(unit: unit, reason: reason)
      else:
        affected[unit.id].reason &= &"; {reason}"

  # Step 2: Semantic dependency rules
  # W3 depends on W2 output (bin/ax)
  if "W2" in affected and "W3" notin affected:
    let w3Idx = units.findIt(it.id == "W3")
    if w3Idx >= 0:
      affected["W3"] = AffectedUnit(
        unit: units[w3Idx],
        reason: "depends_on_W2_output: ci-bootstrap (W2) produces bin/ax which W3 tests"
      )

  # W4 contract tests exercise core invariants — if any src/core/ changed, W4 affected
  if changedCoreFiles.len > 0 and "W4" notin affected:
    let w4Idx = units.findIt(it.id == "W4")
    if w4Idx >= 0:
      affected["W4"] = AffectedUnit(
        unit: units[w4Idx],
        reason: "semantic: src/core/ change exercises core invariants tested by verify-contract (W4)"
      )

  # W5: nimble install rebuilds all source — any src/ change affects W5
  if changedSrcFiles.len > 0 and "W5" notin affected:
    let w5Idx = units.findIt(it.id == "W5")
    if w5Idx >= 0:
      let joinedSrc = changedSrcFiles.join(", ")
      affected["W5"] = AffectedUnit(
        unit: units[w5Idx],
        reason: &"semantic: nimble install rebuilds all source; changed src/ files: {joinedSrc}"
      )

  # W8: gateway binaries compile from src/ — if any src/ change, W8 affected
  if changedSrcFiles.len > 0 and "W8" notin affected:
    let w8Idx = units.findIt(it.id == "W8")
    if w8Idx >= 0:
      let joinedSrc2 = changedSrcFiles.join(", ")
      affected["W8"] = AffectedUnit(
        unit: units[w8Idx],
        reason: &"semantic: gateway binaries compile from src/; changed src/ files: {joinedSrc2}"
      )

  # W10: coverage guard — conservative over-approximation for src/ changes
  if changedSrcFiles.len > 0 and "W10" notin affected:
    let w10Idx = units.findIt(it.id == "W10")
    if w10Idx >= 0:
      affected["W10"] = AffectedUnit(
        unit: units[w10Idx],
        reason: "conservative over-approximation (§3.2): src/ changes may affect coverage instrumentation"
      )

  # W11: generate-docs — src/engine.nim imports core/** transitively
  if changedCoreFiles.len > 0 and "W11" notin affected:
    let w11Idx = units.findIt(it.id == "W11")
    if w11Idx >= 0:
      let joinedCore = changedCoreFiles.join(", ")
      affected["W11"] = AffectedUnit(
        unit: units[w11Idx],
        reason: &"semantic: src/engine.nim → engine/engine.nim → core/** transitively; core modules changed: {joinedCore}"
      )

  # Step 3: Conservative over-approximation for Makefile changes
  # Makefile is the CI's pervasive invocation mechanism (contract §3.2)
  for cf in changedFiles:
    if cf.path == "Makefile" or cf.path.endsWith("/Makefile"):
      for unit in units:
        if unit.id in @["W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8", "W9"]:
          if unit.id notin affected:
            affected[unit.id] = AffectedUnit(
              unit: unit,
              reason: &"conservative over-approximation (§3.2): Makefile is the CI's pervasive invocation mechanism; recipe change affects all make-invoked units"
            )
          else:
            affected[unit.id].reason &= "; Makefile: pervasive invocation mechanism (§3.2)"

  # Step 4: src/generated/ changes affect W1, W2, W3, W4, W5, W6, W7, W8, W10
  for cf in changedFiles:
    if cf.path.startsWith("src/generated/"):
      for unit in units:
        if unit.id in @["W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8", "W10"]:
          if unit.id notin affected:
            affected[unit.id] = AffectedUnit(
              unit: unit,
              reason: "conservative over-approximation: generated code changes propagate to all compilation-dependent units"
            )
          else:
            affected[unit.id].reason &= "; generated code change propagates"

  # Step 5: data/debt_registry.json changes affect W1 (check-debt reads it)
  for cf in changedFiles:
    if cf.path == "data/debt_registry.json":
      if "W1" notin affected:
        let w1Idx = units.findIt(it.id == "W1")
        if w1Idx >= 0:
          affected["W1"] = AffectedUnit(
            unit: units[w1Idx],
            reason: "semantic: tools/debt_engine.nim reads data/debt_registry.json at runtime (line 94)"
          )

  # Step 5b: docs/DEBT_REGISTRY.md changes affect W1 (check-debt reads the
  # markdown too — tools/debt_engine.nim MarkdownPath; docs classification fix 2026-09-23).
  for cf in changedFiles:
    if cf.path == "docs/DEBT_REGISTRY.md":
      if "W1" notin affected:
        let w1Idx = units.findIt(it.id == "W1")
        if w1Idx >= 0:
          affected["W1"] = AffectedUnit(
            unit: units[w1Idx],
            reason: "semantic: make check-debt → bin/debt_engine --validate reads docs/DEBT_REGISTRY.md (tools/debt_engine.nim MarkdownPath)"
          )

  # Step 6: config/readiness_policy.json changes affect W7
  for cf in changedFiles:
    if cf.path == "config/readiness_policy.json":
      if "W7" notin affected:
        let w7Idx = units.findIt(it.id == "W7")
        if w7Idx >= 0:
          affected["W7"] = AffectedUnit(
            unit: units[w7Idx],
            reason: "semantic: readiness_start_gate reads config/readiness_policy.json"
          )

  # Step 7: docs/spec/ normative doc changes — conservative: affect W4 and W7
  # (contract §6.3 gap G4: cache-key not wired, but semantically affected)
  for cf in changedFiles:
    if cf.path.startsWith("docs/spec/"):
      for unitId in @["W4", "W7"]:
        if unitId notin affected:
          let uIdx = units.findIt(it.id == unitId)
          if uIdx >= 0:
            affected[unitId] = AffectedUnit(
              unit: units[uIdx],
              reason: &"conservative over-approximation (§3.2, gap G4): normative spec change semantically affects {unitId} but cache-key is not yet wired"
            )

  # Also apply src/core/ transitive dependency resolution via the core import graph
  if changedCoreFiles.len > 0:
    let coreGraph = buildCoreImportGraph()
    if coreGraph.len > 0:
      let revGraph = buildReverseGraph(coreGraph)
      var changedModules = initHashSet[string]()
      for f in changedCoreFiles:
        let modLine = f
        var modName = ""
        let prefix = "src/core/"
        if modLine.len > prefix.len and modLine.startsWith(prefix):
          let rest = modLine[prefix.len..^1]
          if rest.endsWith(".nim"):
            modName = rest[0..^5]
        if modName.len > 0:
          changedModules.incl(modName)
      let transitivelyAffected = transitiveDependents(revGraph, changedModules)

      # Any work unit that matches a transitively affected core module is affected
      for modName in transitivelyAffected:
        let modulePattern = "src/core/" & modName & ".nim"
        for unit in units:
          if matchesAnyPattern(modulePattern, unit.pathPatterns) and unit.id notin affected:
            affected[unit.id] = AffectedUnit(
              unit: unit,
              reason: &"semantic: core module '{modName}' is transitively dependent on changed core module; import graph closure"
            )

  # Convert to sorted seq
  result = affected.values.toSeq()
  result.sort(proc(a, b: AffectedUnit): int = cmp(a.unit.id, b.unit.id))

# ═══════════════════════════════════════════════════════════════════════════
# §8: Cost estimation
# ═══════════════════════════════════════════════════════════════════════════

proc estimateCost*(selected: seq[AffectedUnit]): tuple[total: float, unknown: bool] =
  ## Sum durations of selected work units. Returns (totalMinutes, hasUnknown).
  var total = 0.0
  var hasUnknown = false
  for au in selected:
    if au.unit.duration == "UNKNOWN":
      hasUnknown = true
      continue
    try:
      total += parseFloat(au.unit.duration)
    except ValueError:
      hasUnknown = true
  result = (total, hasUnknown)

# ═══════════════════════════════════════════════════════════════════════════
# §8a: Selection certainty — fail-closed plan gating (P8.2)
#
# Determines whether the selection plan is CERTAIN or UNCERTAIN.  Per the
# contract §4.5 and §12, uncertainty is NEVER converted to "run a bit less" —
# it MUST convert to broader selection or V2 full certification
# (FALLBACK_REQUIRED).  The two conditions below are the ONLY situations
# under which the selector cannot prove its own containment, so it fails
# closed rather than risk an under-approximation.
#
# The certified no-effect declarations (CertifiedNoEffectPrefixes,
# CertifiedNoEffectExtensions, CertifiedNoEffectRootNames) are owned by
# src/gate/proof_unit_catalog.nim (single editing authority, 2026-09-23).
# ═══════════════════════════════════════════════════════════════════════════

func isCertifiedNoEffect*(path: string): bool {.raises: [].} =
  ## True if `path` is a certified provably-non-affecting file (metadata/
  ## images/lockfiles).  These never force UNCERTAIN — per contract §6 they are
  ## semantically non-verification-relevant.
  ##
  ## Docs classification (fix 2026-09-23): the former blanket "docs/" prefix
  ## is gone. Known-impact docs paths are carved out below so they can never be
  ## certified no-effect — their impact is carried by explicit edges (or, for
  ## build inputs, by conservative UNCERTAIN), not by class.
  if path == "docs/DEBT_REGISTRY.md":
    # Explicit W1 edge in §7 Step 5b: make check-debt reads this file
    # (tools/debt_engine.nim MarkdownPath). Must not be classifiable no-effect.
    return false
  if path.startsWith("docs/agents/"):
    # Build input: src/policy/embedded_agents_docs.nim staticReads these at
    # compile time. No-effect assertion would permit a silent under-approximation.
    # (정정 2026-09-30, plan Phase 2d — 사실 정정, 분류·UNCERTAIN 집합·패턴 불변):
    # the embedded set is exactly 3 files — AGENTS.md, docs/agents/architecture.md,
    # docs/agents/rules_workflow.md (tools/generate_embedded_docs.nim:13-17).
    # The non-embedded docs/agents files are NOT build inputs; they are
    # normative docs on the gate-scan axis (proof_unit_consistency_gate
    # (g) scan roots: docs/agents + docs/spec + config/policy), so their
    # impact is non-zero on that axis too — "0 아님". Either way the class
    # stays non-certifiable: the carve-out below is unconditional.
    return false
  for prefix in CertifiedNoEffectPrefixes:
    if path.startsWith(prefix):
      return true
  let lower = path.toLowerAscii()
  for ext in CertifiedNoEffectExtensions:
    if lower.endsWith(ext):
      return true
  # LICENSE-like root files are also non-affecting
  if lower in CertifiedNoEffectRootNames:
    return true
  result = false

func fileCoveredByWorkUnits*(path: string): bool {.raises: [].} =
  ## True if `path` matches any W1–W11 pathPattern (direct coverage).
  for unit in makeWorkUnits():
    if matchesAnyPattern(path, unit.pathPatterns):
      return true
  result = false

proc determineUncertainty*(
    changedFiles: seq[ChangedFile]): tuple[certain: bool, reasons: seq[string]] {.raises: [].} =
  ## Fail-closed certainty analysis.  Returns (certain, uncertaintyReasons).
  ## `certain == true` only when the selector can prove containment for every
  ## changed file; otherwise it returns UNCERTAIN with concrete reasons so the
  ## caller MUST fall back to V2 full certification.
  var reasons: seq[string] = @[]
  var hasCoreChange = false
  for cf in changedFiles:
    if cf.path.startsWith("src/core/"):
      hasCoreChange = true
      break

  # U1 — broken/unavailable core import graph with a src/core/ change:
  # transitive dependency closure is unknowable → potential under-approximation.
  if hasCoreChange:
    let coreGraph = buildCoreImportGraph()
    if coreGraph.len == 0:
      reasons.add("core import graph is empty/unavailable despite src/core/ change; " &
                  "transitive dependency closure cannot be determined — potential under-approximation")

  # U2 — unclassified source: a changed file is not covered by any work-unit
  # pattern and is not a certified no-effect file → cannot reason about impact.
  for cf in changedFiles:
    let p = cf.path
    let covered = fileCoveredByWorkUnits(p) or
                  p == "Makefile" or p.endsWith("/Makefile") or
                  p == "data/debt_registry.json" or
                  p == "docs/DEBT_REGISTRY.md" or
                  p == "config/readiness_policy.json" or
                  p == "config/gates.manifest.toml" or
                  p.startsWith("docs/spec/") or
                  p.startsWith("src/generated/") or
                  p.startsWith("config/")
    if not covered and not isCertifiedNoEffect(p):
      reasons.add(&"UNCLASSIFIED source file '{p}' matches no work-unit pattern and is not " &
                   "a certified no-effect file — impact unknowable (UNCLASSIFIED → P4 FAIL)")

  result = (certain: reasons.len == 0, reasons: reasons)

# ═══════════════════════════════════════════════════════════════════════════
# §9: Report generation
# ═══════════════════════════════════════════════════════════════════════════

proc selectedUnitsToJson*(units: seq[AffectedUnit]): JsonNode =
  let arr = newJArray()
  for au in units:
    var obj = newJObject()
    obj["id"] = newJString(au.unit.id)
    obj["name"] = newJString(au.unit.name)
    obj["reason"] = newJString(au.reason)
    obj["duration_minutes"] = newJString(au.unit.duration)
    obj["provenance"] = newJString(au.unit.provenance)
    obj["isContainer"] = newJBool(au.unit.isContainer)
    arr.add(obj)
  result = arr

proc generateReport*(
    base, head, fingerprint: string,
    changedFiles: seq[ChangedFile],
    selectedUnits: seq[AffectedUnit],
    limitations: seq[string]): ShadowReport =
  let (cost, _) = estimateCost(selectedUnits)
  let fullCost = 73.7
  result.base = base
  result.head = head
  result.changeFingerprint = fingerprint
  result.changedFiles = changedFiles
  result.selectedUnits = selectedUnits
  result.estimatedCostMinutes = cost
  result.fullPipelineCostMinutes = fullCost
  result.costSavingsMinutes = fullCost - cost
  result.savingsPercent = if fullCost > 0: ((fullCost - cost) / fullCost) * 100.0 else: 0.0
  result.limitations = limitations

proc reportToJson*(report: ShadowReport): JsonNode =
  var obj = newJObject()
  obj["base"] = newJString(report.base)
  obj["head"] = newJString(report.head)
  obj["changeFingerprint"] = newJString(report.changeFingerprint)

  let filesArr = newJArray()
  for cf in report.changedFiles:
    var fObj = newJObject()
    fObj["path"] = newJString(cf.path)
    fObj["status"] = newJString(cf.status)
    fObj["blobHash"] = newJString(cf.blobHash)
    filesArr.add(fObj)
  obj["changedFiles"] = filesArr

  obj["selectedWorkUnits"] = selectedUnitsToJson(report.selectedUnits)

  var costObj = newJObject()
  costObj["estimatedAffectedClosure_minutes"] = newJFloat(report.estimatedCostMinutes)
  costObj["fullPipeline_baseline_minutes"] = newJFloat(report.fullPipelineCostMinutes)
  costObj["savings_minutes"] = newJFloat(report.costSavingsMinutes)
  costObj["savings_percent"] = newJFloat(report.savingsPercent)
  obj["costComparison"] = costObj

  let limArr = newJArray()
  for lim in report.limitations:
    limArr.add(newJString(lim))
  obj["limitations"] = limArr

  obj["planStatus"] = newJString(report.planStatus)
  obj["certainty"] = newJString(report.certainty)
  let uncArr = newJArray()
  for reason in report.uncertaintyReasons:
    uncArr.add(newJString(reason))
  obj["uncertaintyReasons"] = uncArr

  obj["determinism"] = newJString("identical (base, head, repo state) inputs produce byte-identical output; all sets sorted, no timestamps in body")

  result = obj

# ═══════════════════════════════════════════════════════════════════════════
# §9b: A2 decision envelope (select-job consumer)
# ═══════════════════════════════════════════════════════════════════════════
#
# Deterministic projection of the selector verdict onto the
# runner-pool-acceptance 9-job execution surface (ADR-0017 Amendment A1.3
# operational redefinition): W2 ↔ ci-bootstrap, W8 ↔ gateway-shard×K.
# All other W-units (W1, W3–W7, W9–W11) are NOT represented by that workflow
# (their grid execution is DEBT#466 — the A1.3 redefinition, not a grid run).
# The projection is a pure function of the verdict: sorted ids, no timestamps,
# no I/O — byte-identical for identical inputs (determinism §0.2/§0.5).
# Decision logic (which W-units are affected) lives HERE (M7) — the workflow
# YAML only schedules based on this envelope; it never re-judges affectedness.

const
  DecisionEnvelopeSchema = "axiom/ci-select-decision/v1"
  # K=8 fixed partition (ADR-0023 Amendment A1.8); the workflow matrix is
  # static [0..7] and must stay in lockstep with this constant — POLICY 다이얼 금지.
  CIJobShardCount = 8

  # Oracle evidence contract (plan Phase 4 — independent-oracle consumption;
  # ADR-0017 개정 동반(PR-B)): the select job's independent oracle writes this
  # file; the selector CONSUMES and verifies it only — it never derives the
  # verdict itself (self-reference prohibition, §0.9 / Completion Evidence #10).
  OracleEvidenceSchema = "axiom/oracle-evidence/v1"
  # The five axes whose Δ-exclusion the oracle must evidence before a zero
  # derivation (plan Phase 2b, 5-axis schema): execution-code closure
  # (B-compiled derive_checker_closure), gate-scan roots, envHash inputs,
  # identity, and the 3-file embed set. A derivedEmpty=true verdict without
  # all five axes present is NOT accepted. (product_surface_closure is NOT an
  # axis — plan round-4: unwired, out of scope.)
  OracleEvidenceAxes = [
    "executionClosure", "gateScanRoots", "envHashInputs", "identity", "embedSet"
  ]
  # §0.10 decision-text binding (proof_unit_consistency_gate.nim:76-81
  # pattern): the literal token this decision and the ADR amendment (PR-B)
  # share. The amendment records the oracleEvidence field on decision.json
  # (axiom/ci-select-decision/v1) as the carrier of the independent-oracle
  # verdict (derivedEmpty) — the reconcile gate binds to the same literal.
  OracleEvidenceBindingToken = "oracleEvidence"
  # Landing policy (CONTROLLED, H-tree input): the committed landing-required
  # gateway test set. Read at the I/O boundary in main() and passed into the
  # pure decisionEnvelope as a parameter (:802-809 pattern — no I/O here).
  LandingPolicyRelPath = "config/policy/landing_required_gateway_tests.json"

func canonEscape(s: string): string {.raises: [].} =
  ## Minimal JSON string escaping, jq-compatible — byte-identical twin of
  ## proof_reconcile_gate.nim canonEscape (divergence would break the
  ## derivationDigest binding): `"` `\` and C controls are escaped; everything
  ## else — including raw UTF-8 bytes ≥ 0x80 — passes through verbatim.
  result = newStringOfCap(s.len + 2)
  for c in s:
    case c
    of '"': result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\b': result.add("\\b")
    of '\f': result.add("\\f")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else:
      if ord(c) <= 0x1F:  # remaining C controls → \uXXXX (jq-compatible hex)
        result.add("\\u" & toHex(ord(c), 4))
      else:               # printable + raw UTF-8 bytes pass through verbatim
        result.add(c)

func canonicalJson(node: JsonNode): string {.raises: [].} =
  ## Compact JSON with object keys sorted lexicographically at EVERY depth and
  ## array order preserved — byte-identical twin of proof_reconcile_gate.nim
  ## canonicalJson; this is the byte form the oracle runner must have hashed
  ## for derivationDigest (equivalent to jq -S -c modulo the escaping above).
  case node.kind
  of JObject:
    result.add("{")
    var entries: seq[(string, JsonNode)]
    for k, v in node.pairs:
      entries.add((k, v))
    for i, e in entries.sortedByIt(it[0]):
      if i > 0:
        result.add(",")
      result.add("\"")
      result.add(canonEscape(e[0]))
      result.add("\":")
      result.add(canonicalJson(e[1]))
    result.add("}")
  of JArray:
    result.add("[")
    for i in 0 ..< node.len:
      if i > 0:
        result.add(",")
      result.add(canonicalJson(node[i]))
    result.add("]")
  of JString:
    result.add("\"")
    result.add(canonEscape(node.str))
    result.add("\"")
  of JInt:
    result.add($node.num)
  of JFloat:
    result.add($node.fnum)
  of JBool:
    result.add($node.bval)
  of JNull:
    result.add("null")

proc loadOracleEvidence(path: string): tuple[valid: bool; derivedEmpty: bool;
    digest: string; axes: JsonNode; reason: string] {.
  axiomEffect: IoEffect,
  axiomDecision(
    id = "DECISION-CPV-02",
    reason = "Independent-oracle evidence consumption for mode=none admission: the selector verifies JSON parse, schema axiom/oracle-evidence/v1, presence of the 5 axes, derivedEmpty boolean, and derivationDigest == sha256 of the canonical document minus the derivationDigest field (proof_reconcile_gate twin convention) — it never derives the verdict itself; invalid evidence forces full fallback via exit 2",
    adr = "docs/adr/0017-incremental-verification-engine.md",
    introduced = "v34-cpv").} =
  ## Read and verify the independent oracle's evidence file (plan Phase 4).
  ## The selector verifies ONLY: JSON parses, schema matches
  ## axiom/oracle-evidence/v1, all 5 axes are present as objects,
  ## derivedEmpty is a boolean, and derivationDigest equals a sha256
  ## recomputation over the canonical document minus the derivationDigest
  ## field (byte-identical to proof_reconcile_gate.nim's canonicalJson — the
  ## two consumers must agree on the byte form). A failed check returns
  ## valid=false with the reason — the caller must fail closed (exit 2 → full
  ## fallback; the selector must not emit mode=none without this file).
  result = (valid: false, derivedEmpty: false, digest: "", axes: nil, reason: "")
  if not fileExists(path):
    result.reason = "oracle evidence missing: " & path
    return
  var raw = ""
  try:
    raw = readFile(path)
  except CatchableError as e:
    result.reason = "oracle evidence unreadable: " & path & " (" & e.msg & ")"
    return
  var data: JsonNode
  try:
    data = parseJson(raw)
  except CatchableError as e:
    result.reason = "oracle evidence invalid JSON: " & path & " (" & e.msg & ")"
    return
  if data.kind != JObject:
    result.reason = "oracle evidence root is not an object"
    return
  let schemaNode = data{"schema"}
  if schemaNode == nil or schemaNode.kind != JString or
     schemaNode.getStr() != OracleEvidenceSchema:
    result.reason = "oracle evidence schema mismatch (expected " &
                    OracleEvidenceSchema & ")"
    return
  let axesNode = data{"axes"}
  if axesNode == nil or axesNode.kind != JObject:
    result.reason = "oracle evidence axes missing or not an object"
    return
  for axis in OracleEvidenceAxes:
    if axesNode{axis} == nil or axesNode{axis}.kind != JObject:
      result.reason = "oracle evidence axis missing: " & axis
      return
  let deNode = data{"derivedEmpty"}
  if deNode == nil or deNode.kind != JBool:
    result.reason = "oracle evidence derivedEmpty missing or not a boolean"
    return
  # derivationDigest must equal sha256 over the CANONICAL document minus the
  # derivationDigest field itself — the contract pinned by the B-trusted
  # consumer proof_reconcile_gate.nim (:598-607, "sha256 of the canonical
  # document minus itself"): canonical = compact JSON with object keys sorted
  # lexicographically at every depth, array order preserved. The canonical
  # bytes here MUST stay byte-identical with proof_reconcile_gate.nim's
  # canonicalJson — a divergence would break the digest binding between the
  # selector and the gate (both consume the same oracle file).
  let ddNode = data{"derivationDigest"}
  if ddNode == nil or ddNode.kind != JString:
    result.reason = "oracle evidence derivationDigest missing or not a string"
    return
  let stated = ddNode.getStr()
  if stated.len != 64:
    result.reason = "oracle evidence derivationDigest malformed (not 64 hex chars)"
    return
  var canon = newJObject()
  for k, v in data.pairs:
    if k != "derivationDigest":
      canon[k] = v
  let canonBytes = canonicalJson(canon)
  let tmpDigest = getTempDir() / "axiom_oe_digest_input"
  var recomputed = ""
  try:
    writeFile(tmpDigest, canonBytes)
    let (dOut, dCode) = execCmdEx("sha256sum " & quoteShell(tmpDigest))
    if dCode == 0:
      let dParts = dOut.strip().splitWhitespace()
      if dParts.len > 0:
        recomputed = dParts[0]
  except CatchableError: # axiom:best-effort(temp digest input write failure: recomputed stays empty → fail-closed 'digest unavailable')
    discard # axiom:best-effort(sha256sum invocation failure: fail-closed via empty recomputed, no silent pass)
  finally:
    if fileExists(tmpDigest):
      removeFile(tmpDigest)
  if recomputed.len == 0:
    result.reason = "oracle evidence digest unavailable (sha256sum failed)"
    return
  if recomputed != stated:
    result.reason = "oracle evidence derivationDigest mismatch: claimed '" &
                    stated & "' != recomputed '" & recomputed &
                    "' (sha256 of canonical document minus derivationDigest)"
    return
  result.valid = true
  result.derivedEmpty = deNode.getBool()
  result.digest = stated
  result.axes = axesNode

proc decisionEnvelope(base, head, fingerprint, certainty, planStatus: string;
                      selected: seq[AffectedUnit];
                      landingPolicyFloor = false;
                      oracleDerivedEmpty = false;
                      oracleDigest = "";
                      oracleAxes: JsonNode = nil): JsonNode {.
  axiomDecision(
    id = "DECISION-CPV-01",
    reason = "A2 select-job decision envelope: the landing floor is policy-derived (lgPolicyNonEmpty ∧ ¬oracleDerivedEmpty — no literals) and a verified independent-oracle verdict (oracleEvidence.derivedEmpty=true) is the only condition that admits mode=none on an empty selection",
    adr = "docs/adr/0017-incremental-verification-engine.md",
    introduced = "v34-cpv").} =
  ## Build the A2 select-job decision envelope.
  ##   mode:   "none"     selectable, empty selection → nothing to run
  ##           "selected" selectable, non-empty selection → run the projection
  ##           "full"     UNCERTAIN (or non-VALID) → full L2 (M6 fail-closed)
  ##   executableWorkUnits: projection of the selected set onto {W2, W8};
  ##                         ci-bootstrap also runs when an W8 leg runs (the
  ##                         legs consume ci-bootstrap artifacts as infra).
  ##   shards: gateway-shard matrix indices to run ("all 8" iff W8 selected).
  ##   landingPolicyFloor: when the committed LANDING_REQUIRED_GATEWAY_TESTS
  ##                         policy is non-empty, W8 is forced into the
  ##                         projection so the landing test set executes on
  ##                         EVERY candidate regardless of the diff (plan
  ##                         Phase 2: "landing set은 selector 무관 전량 발화").
  ##                         The policy file is part of the H tree (input
  ##                         identity) → deterministic; purity preserved by
  ##                         passing it in as a parameter instead of reading I/O here.
  ##                         Phase 3 (ADR-0017/0025 개정 동반(PR-B)): the value
  ##                         is computed at the call site as
  ##                         lgPolicyNonEmpty ∧ ¬oracleDerivedEmpty — a
  ##                         provably-empty derivation (valid oracle evidence,
  ##                         derivedEmpty=true) is the ONLY condition that
  ##                         lifts the floor; the selector never derives that
  ##                         fact itself (§0.9).
  ##   oracleEvidence: when a verified evidence file exists, the envelope
  ##                         mirrors oracleId/derivedEmpty/derivationDigest/
  ##                         axes so downstream gates and tests can consume
  ##                         the independent verdict (additive field — the
  ##                         decisionHash binding is over the emitted bytes,
  ##                         so the record stays self-consistent).
  var ids: seq[string]
  for au in selected:
    ids.add(au.unit.id)
  if landingPolicyFloor and "W8" notin ids:
    ids.add("W8")
  ids.sort()

  let mode =
    if certainty != "CERTAIN": "full"
    elif ids.len == 0: "none"
    else: "selected"
  let w8 = "W8" in ids
  let shards =
    if mode == "full" or w8:
      (0 ..< CIJobShardCount).toSeq
    else:
      newSeq[int]()
  let ciBootstrap = mode == "full" or "W2" in ids or w8
  var executable: seq[string]
  if ciBootstrap:
    executable.add("W2")
  if shards.len > 0:
    executable.add("W8")
  let gatewayTestScope = if mode == "full" or w8: "ALL" else: "EMPTY"

  result = %*{
    "schema": DecisionEnvelopeSchema,
    "base": base,
    "head": head,
    "changeFingerprint": fingerprint,
    "certainty": certainty,
    "planStatus": planStatus,
    "mode": mode,
    "selectedWorkUnits": ids,
    "executableWorkUnits": executable,
    "shards": shards,
    "ciBootstrap": ciBootstrap,
    "gatewayTestScope": gatewayTestScope,
    "landingPolicyFloor": landingPolicyFloor
  }
  if oracleDigest.len > 0 and oracleAxes != nil:
    var oev = newJObject()
    oev["oracleId"] = newJString(OracleEvidenceSchema)
    oev["derivedEmpty"] = newJBool(oracleDerivedEmpty)
    oev["derivationDigest"] = newJString(oracleDigest)
    oev["axes"] = oracleAxes
    result[OracleEvidenceBindingToken] = oev
    # Top-level mirror of the verdict — the A2 consumers (regression fixtures,
    # reconcile binding) read decision.json["derivedEmpty"] directly.
    result["derivedEmpty"] = newJBool(oracleDerivedEmpty)

# ═══════════════════════════════════════════════════════════════════════════
# §10: Human-readable stdout summary
# ═══════════════════════════════════════════════════════════════════════════

proc printSummary*(report: ShadowReport) =
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "  AXIOM IMPACT CLOSURE SELECTOR — SHADOW MODE"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  echo &"  Range: {report.base}..{report.head}"
  echo &"  Change fingerprint: {report.changeFingerprint}"
  echo &"  Changed files: {report.changedFiles.len}"
  echo &"  Plan status: {report.planStatus}  (certainty: {report.certainty})"
  if report.uncertaintyReasons.len > 0:
    echo "  Uncertainty reasons:"
    for reason in report.uncertaintyReasons:
      echo &"    - {reason}"
  echo ""

  if report.selectedUnits.len == 0:
    echo "  ✅ No affected work units — all reusable (0 m affected closure)."
    echo "     Savings: 100 % of pipeline baseline (73.7 m)."
  else:
    echo &"  Affected work units: {report.selectedUnits.len}"
    echo ""
    for au in report.selectedUnits:
      echo &"    {au.unit.id}  {au.unit.name}"
      echo &"           reason: {au.reason}"
      echo &"           duration: {au.unit.duration} min ({au.unit.provenance})"
      echo ""

  let (cost, hasUnknown) = estimateCost(report.selectedUnits)
  echo &"  Affected-closure cost (conservative): {cost:.1f} min"
  if hasUnknown:
    echo "    ⚠ Some durations are UNKNOWN — cost estimate is conservative (low)."
  echo &"  Full pipeline baseline: {report.fullPipelineCostMinutes} min"
  echo &"  Estimated savings: {report.costSavingsMinutes:.1f} min ({report.savingsPercent:.1f} %)"
  echo ""

  if report.limitations.len > 0:
    echo "  Limitations:"
    for lim in report.limitations:
      echo &"    - {lim}"
    echo ""

  echo "═══════════════════════════════════════════════════════════════"
  echo ""

# ═══════════════════════════════════════════════════════════════════════════
# §11: CLI entry point
# ═══════════════════════════════════════════════════════════════════════════

proc printHelp() =
  echo "Impact Closure Selector — P3 Shadow Mode"
  echo ""
  echo "Deterministically computes which CI work units are affected by a git diff."
  echo "Does NOT wire into CI. Outputs a shadow report only."
  echo ""
  echo "Usage:"
  echo "  impact-closure --base <ref> --head <ref> [options]"
  echo "  impact-closure --policy-files <policy.json>"
  echo "  impact-closure --policy-gate <policy.json> <junit-dir>"
  echo ""
  echo "Policy subcommands (checker.mk static-derivability helpers — see §9c):"
  echo "  --policy-files  Print the sorted testPath list from the landing policy."
  echo "  --policy-gate   Post-execution landing-required set membership gate."
  echo ""
  echo "Options (selector mode):"
  echo "  --base <ref>        Base ref for diff (required)"
  echo "  --head <ref>        Head ref for diff (default: HEAD)"
  echo "  --output <path>     Output JSON report path"
  echo "                       (default: docs/reports/impact_closure_shadow_<date>.json)"
  echo "  --decision-out <path>"
  echo "                       Write the A2 select-job decision envelope (JSON)."
  echo "                       Deterministic projection onto the runner-pool-acceptance"
  echo "                       9-job surface: mode/executableWorkUnits/shards/ciBootstrap/"
  echo "                       gatewayTestScope (W2↔ci-bootstrap, W8↔gateway-shard)."
  echo "  --require-certain   Gate authoritative selection on CERTAIN only (§12)."
  echo "                       Exit: 0=CERTAIN/VALID, 2=UNCERTAIN/FALLBACK_REQUIRED,"
  echo "                       1=ERROR.  Without this flag exit is always 0 (shadow)."
  echo "  --oracle-evidence <path>"
  echo "                       Independent-oracle evidence file (plan Phase 4,"
  echo "                       schema axiom/oracle-evidence/v1). Verified — never"
  echo "                       derived — by the selector: JSON parse, schema, the"
  echo "                       5 axes (executionClosure/gateScanRoots/envHashInputs/"
  echo "                       identity/embedSet), derivedEmpty boolean, and"
  echo "                       derivationDigest == sha256 of the canonical document"
  echo "                       (keys sorted at every depth, compact) minus the"
  echo "                       derivationDigest field (proof_reconcile_gate twin)."
  echo "                       Missing/invalid evidence → exit 2 (full fallback)."
  echo "                       Valid ∧ derivedEmpty=true admits mode=none (lifts the"
  echo "                       landing floor); derivedEmpty=false keeps the floor on"
  echo "                       while the normal selection path continues (no exit 2)."
  echo "  --help, -h          Show this help"
  echo ""
  echo "Examples:"
  echo "  impact-closure --base main --head HEAD"
  echo "  impact-closure --base HEAD~1 --head HEAD --output docs/reports/impact.json"
  echo "  impact-closure --base HEAD~1 --head HEAD --require-certain"
  echo ""
  echo "Output:"
  echo "  JSON report with: base, head, change fingerprint, changed files,"
  echo "  selected work units with reasons, cost comparison, limitations,"
  echo "  planStatus, certainty, uncertaintyReasons."
  echo ""
  echo "Invariants implemented:"
  echo "  1. affected(U, Δ) ≡ closure(Δ) ∩ inputClosure(U) ≠ ∅"
  echo "  2. Skip allowed ONLY when affected(U, Δ) is provably false"
  echo "  Conservative over-approximation: unknown → broader unit affected."

# ═══════════════════════════════════════════════════════════════════════════
# §9c: Policy subcommands (checker.mk static-derivability ports)
# ═══════════════════════════════════════════════════════════════════════════
#
# --policy-files / --policy-gate: exact behavioral ports of the python that
# used to live inline in ci/checker.mk (GATEWAY_POLICY_PARSE and the
# test-gateway-policy-gate recipe). checker.mk now calls these via path
# commands (bin/impact_closure_selector ...), which the closure deriver
# resolves through the file-target product rule. Both subcommands operate on
# the current working tree only (no git), stay deterministic (sorted sets,
# fixed iteration order, no timestamps in output), and fail closed: any
# violation → exit 1 with the reason on stderr, no partial stdout that a
# recipe consumer could mistake for a valid policy list.

const
  PolicyInvMustRefs = [
    "INV-1", "INV-2", "INV-3", "INV-4", "INV-5", "INV-6", "INV-7",
    "INV-8", "INV-9", "INV-10", "INV-11", "INV-12", "INV-13"
  ]
  PolicyRMustRefs = ["R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8"]
  UnresolvedMustRef = "UNRESOLVED"
  UnresolvedJustification = "candidate pending Phase-3 semantic proof"

func jstr(n: JsonNode, key: string): string {.raises: [].} =
  ## String attribute access with python's `t.get(key, "")` semantics
  ## (missing or non-string → empty string).
  let v = n{key}
  if v == nil or v.kind != JString:
    result = ""
  else:
    result = v.getStr()

func junitBaseName(testPath: string): string {.raises: [].} =
  ## os.path.splitext(os.path.basename(tp))[0] — testcase name as recorded in
  ## junit (basename without extension).
  result = testPath.splitFile.name

proc policyFilesList(policyPath: string): int {.axiomEffect: IoEffect.} =
  ## --policy-files <policy.json>: read tests[] from the committed landing
  ## policy and print the sorted testPath list (newline-separated) to stdout.
  ## Fail-closed → exit 1 + stderr reason, no stdout (port of GATEWAY_POLICY_PARSE).
  if not fileExists(policyPath):
    stderr.writeLine("[policy] FAIL - landing policy missing: " & policyPath)
    return 1
  let parsed = try: parseFile(policyPath) except CatchableError:
    stderr.writeLine("[policy] FAIL - landing policy invalid JSON: " & policyPath)
    return 1
  let tests = parsed{"tests"}
  if tests == nil or tests.kind != JArray or tests.len == 0:
    stderr.writeLine("[policy] FAIL - tests[] missing or empty")
    return 1
  var paths: seq[string]
  for t in tests:
    if t.kind != JObject:
      stderr.writeLine("[policy] FAIL - testPath missing")
      return 1
    let tp = jstr(t, "testPath")
    if tp.len == 0:
      stderr.writeLine("[policy] FAIL - testPath missing")
      return 1
    if not fileExists(tp):
      stderr.writeLine("[policy] FAIL - testPath does not resolve: " & tp)
      return 1
    paths.add(tp)
  paths.sort()
  for p in paths:
    stdout.writeLine(p)
  result = 0

proc collectJunitRunCases(junitDir: string): tuple[files: seq[string],
    executed, failed: HashSet[string]] {.axiomEffect: IoEffect.} =
  ## Recursive gateway-junit.xml glob (sorted) + run-testcase collection —
  ## port of `glob.glob(join(junit_dir, "**", "gateway-junit.xml"), recursive=True)`
  ## and the two executed/failed set comprehensions. Malformed junit → fail
  ## closed via raised IOError.
  result.executed = initHashSet[string]()
  result.failed = initHashSet[string]()
  if not dirExists(junitDir):
    return
  try:
    for path in walkDirRec(junitDir, {pcFile}):
      if path.endsWith("gateway-junit.xml"):
        result.files.add(path)
  except OSError:
    return
  result.files.sort()
  for jf in result.files:
    let root = try: loadXml(jf) except CatchableError as e:
      raise newException(IOError, "junit parse error: " & jf & " (" & e.msg & ")")
    for tc in root.findAll("testcase"):
      if tc.attr("classname") == "run":
        let name = tc.attr("name")
        if name.len > 0:
          result.executed.incl(name)
          var hasFailure = false
          for child in tc:
            if child.kind == xnElement and child.tag == "failure":
              hasFailure = true
              break
          if hasFailure:
            result.failed.incl(name)

proc policyGate(policyPath, junitDir: string): int {.axiomEffect: IoEffect.} =
  ## --policy-gate <policy.json> <junit-dir>: exact behavioral port of the
  ## test-gateway-policy-gate recipe python. Prints the same [policy-gate]
  ## log lines to stdout; any violation → exit 1 (fail-closed).
  let parsed = try: parseFile(policyPath) except CatchableError:
    stderr.writeLine("[policy-gate] FAIL - landing policy unreadable: " & policyPath)
    return 1
  let tests = parsed{"tests"}
  if tests == nil or tests.kind != JArray:
    stdout.writeLine("[policy-gate] FAIL — tests[] missing or not a list")
    return 1
  if tests.len == 0:
    stdout.writeLine("[policy-gate] FAIL — tests[] empty (landing-required set cannot be empty)")
    return 1

  let junit = try: collectJunitRunCases(junitDir) except CatchableError as e:
    stderr.writeLine("[policy-gate] FAIL - " & e.msg)
    return 1
  stdout.writeLine("[policy-gate] junit_files=" & $junit.files.len &
                   " executed(run)=" & $junit.executed.len &
                   " failed=" & $junit.failed.len)

  var ids: seq[string]
  var paths: seq[string]
  var items: seq[tuple[pid, must, tp, just: string]]
  for t in tests:
    if t.kind != JObject:
      stdout.writeLine("[policy-gate] FAIL — malformed test entry (not an object)")
      return 1
    let pid = jstr(t, "policyId")
    let must = jstr(t, "mustRef")
    let tp = jstr(t, "testPath")
    let just = jstr(t, "justification")
    ids.add(pid)
    paths.add(tp)
    items.add((pid, must, tp, just))

  var dups: seq[string]
  for x in ids.toHashSet.toSeq.sorted():
    if ids.count(x) > 1:
      dups.add(x)
  for x in paths.toHashSet.toSeq.sorted():
    if paths.count(x) > 1:
      dups.add(x)
  if dups.len > 0:
    stdout.writeLine("[policy-gate] FAIL — duplicate policy identity: " & dups.join(", "))

  var probs: seq[tuple[pid, reason: string]]
  for (pid, must, tp, just) in items:
    if not (pid.len > 0 and must.len > 0 and tp.len > 0 and just.len > 0):
      probs.add((pid, "incomplete entry (policyId/mustRef/testPath/justification required)"))
    if must != UnresolvedMustRef and must notin PolicyInvMustRefs and
       must notin PolicyRMustRefs:
      probs.add((pid, "mustRef not in INV-1..13 / R1..R8: " & must))
    if must == UnresolvedMustRef and just != UnresolvedJustification:
      probs.add((pid, "UNRESOLVED must carry the exact Phase-3-pending justification"))
    if not fileExists(tp):
      probs.add((pid, "testPath does not resolve: " & tp))
    if fileExists(tp) and junitBaseName(tp) notin junit.executed:
      probs.add((pid, "not executed (junit run-suite missing): " & junitBaseName(tp)))
    if fileExists(tp) and junitBaseName(tp) in junit.executed and
       junitBaseName(tp) in junit.failed:
      probs.add((pid, "executed but failing: " & junitBaseName(tp)))

  let probPids = probs.mapIt(it.pid)
  for (pid, must, tp, just) in items:
    if pid notin probPids:
      stdout.writeLine("[policy-gate] " & pid & " " & junitBaseName(tp) &
                       " mustRef=" & must & " — OK")
  for (pid, reason) in probs:
    stdout.writeLine("[policy-gate] FAIL — " & pid & ": " & reason)

  let rc = (if dups.len > 0: 1 else: 0) or (if probs.len > 0: 1 else: 0)
  if rc != 0:
    stdout.writeLine("[policy-gate] FAIL — landing-required set violated (fail-closed)")
    return 1
  stdout.writeLine("[policy-gate] OK — every landing-required test resolved and executed without failure (" & $tests.len & " items)")
  result = 0

proc main() =
  let argv = commandLineParams()
  if argv.len > 0:
    case argv[0]
    of "--policy-files":
      if argv.len != 2:
        stderr.writeLine("[policy-files] usage: impact-closure --policy-files <policy.json>")
        quit(1)
      quit(policyFilesList(argv[1]))
    of "--policy-gate":
      if argv.len != 3:
        stderr.writeLine("[policy-gate] usage: impact-closure --policy-gate <policy.json> <junit-dir>")
        quit(1)
      quit(policyGate(argv[1], argv[2]))
    else:
      discard
  var baseRef = ""
  var headRef = "HEAD"
  var outputPath = ""
  var decisionOutPath = ""
  var oracleEvidencePath = ""
  var requireCertain = false
  var showHelp = false

  var p = initOptParser(commandLineParams(),
                        shortNoVal = {'h'},
                        longNoVal = @["help", "require-certain"])
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "base", "b":
        baseRef = p.val
      of "head", "H":
        headRef = p.val
      of "output", "o":
        outputPath = p.val
      of "decision-out":
        decisionOutPath = p.val
      of "oracle-evidence":
        oracleEvidencePath = p.val
      of "require-certain":
        requireCertain = true
      of "help", "h":
        showHelp = true
      else:
        echo &"[impact-closure] Unknown option: {p.key}"
        showHelp = true
    of cmdArgument:
      if baseRef.len == 0:
        baseRef = p.key
      elif headRef == "HEAD":
        headRef = p.key

  if showHelp or baseRef.len == 0:
    printHelp()
    if baseRef.len == 0 and not showHelp:
      quit(1)
    return

  # Determine repo root (walk up looking for .axiom_root)
  var repoRoot = getCurrentDir()
  for _ in 0 ..< 10:
    if dirExists(repoRoot / ".axiom_root"):
      break
    let parent = repoRoot.parentDir()
    if parent == repoRoot:
      break
    repoRoot = parent

  # Default output path
  if outputPath.len == 0:
    let dateStr = now().utc().format("yyyy-MM-dd")
    outputPath = repoRoot / "docs/reports" / &"impact_closure_shadow_{dateStr}.json"

  # Ensure output directory exists
  let outDir = outputPath.parentDir()
  if not dirExists(outDir):
    createDir(outDir)

  # Oracle evidence (plan Phase 4 — independent-oracle consumption; ADR-0017
  # 개정 동반(PR-B)): verify the oracle's verdict file. The selector consumes
  # and verifies it only — it never derives the verdict itself (§0.9
  # self-reference prohibition; Completion Evidence #9). An invalid evidence
  # forces fail-closed full fallback via UNCERTAIN + exit 2; a VALID
  # derivedEmpty=true is the only condition that lifts the landing floor.
  var oracleDerivedEmpty = false
  var oracleDigest = ""
  var oracleAxes: JsonNode = nil
  var oracleInvalid = ""
  if oracleEvidencePath.len > 0:
    let ov = loadOracleEvidence(oracleEvidencePath)
    if ov.valid:
      oracleDerivedEmpty = ov.derivedEmpty
      oracleDigest = ov.digest
      oracleAxes = ov.axes
      echo "[impact-closure] Oracle evidence verified: derivedEmpty=" & $ov.derivedEmpty &
           " derivationDigest=" & ov.digest
    else:
      oracleInvalid = ov.reason
      stderr.writeLine("[impact-closure] " & ov.reason & " — exit 2 (full fallback)")

  # Step 1: Get changed files
  echo &"[impact-closure] Computing diff {baseRef}..{headRef} ..."
  let changedFiles = getChangedFiles(baseRef, headRef)
  echo &"[impact-closure] Found {changedFiles.len} changed file(s)."

  # Step 2: Compute change fingerprint
  echo "[impact-closure] Computing change fingerprint ..."
  let fingerprint = computeFingerprint(changedFiles)
  echo &"[impact-closure] Fingerprint: {fingerprint}"

  # Step 3: Map to work units
  echo "[impact-closure] Computing affected dependency closure ..."
  let selectedUnits = mapToWorkUnits(changedFiles)

  # Step 4: Build limitations list
  var limitations: seq[string] = @[
    "import_graph.nim cannot be imported (checksums/sha2 dependency gap in Nim 2.2.10); core transitive-dependency resolution is reimplemented inline (same BFS algorithm)",
    "ci-lake-build (W9) duration is UNKNOWN; excluded from cost sums",
    "Normative doc → cache-key invalidation (G4) is not yet wired; conservative over-approximation applied",
    "Makefile pervasive-invocation over-approximation may over-claim W1–W9 for recipe-level changes",
    "Gate-target closure beyond src/core/ is a known gap (import_graph.nim is core-only per handoff note)"
  ]

  # Step 5: Generate report
  let report = generateReport(baseRef, headRef, fingerprint, changedFiles, selectedUnits, limitations)

  # Step 5b: Determine selection certainty (P8.2 §8a/§12) — fail-closed plan gate.
  # planStatus assignment:
  #   CERTAIN  → "VALID"
  #   UNCERTAIN → "FALLBACK_REQUIRED"   (caller MUST fall back to V2 full certification)
  #   argument/main error → "ERROR"
  # NOTE: planStatus/certainty/uncertaintyReasons are var because ShadowReport is
  # an object value; generateReport returns a fresh value we own.
  var reportV = report
  var (certain, reasons) = determineUncertainty(changedFiles)
  if oracleInvalid.len > 0:
    # P4 fail-closed: oracle evidence failure is independently UNCERTAIN —
    # mode=none must not be emitted without a verified independent verdict
    # (the reasons below propagate into planStatus/certainty, so the envelope
    # mode becomes "full" and the exit contract returns 2).
    certain = false
    reasons.add(oracleInvalid & " — mode=none 불발행, full 폴백 (plan Phase 4 fail-closed)")
  if certain:
    reportV.planStatus = "VALID"
    reportV.certainty = "CERTAIN"
  else:
    reportV.planStatus = "FALLBACK_REQUIRED"
    reportV.certainty = "UNCERTAIN"
  reportV.uncertaintyReasons = reasons
  let finalReport = reportV

  # Step 6: Write JSON report
  let jsonNode = reportToJson(finalReport)
  let prettyJson = pretty(jsonNode, 2)
  writeFile(outputPath, prettyJson)

  # Step 6b (A2): Write the decision envelope when requested (--decision-out).
  # Deterministic projection (sorted ids, no timestamps) — identical inputs →
  # byte-identical decision.json, so decisionHash = sha256(decision.json) is a
  # reproducible binding between the decision record and the CI execution.
  if decisionOutPath.len > 0:
    # Landing floor (plan Phase 2/3 — ADR-0017/0025 개정 동반(PR-B)): the
    # gateway lane must execute on EVERY candidate so the landing set runs
    # regardless of the diff (mint-publish [B2](c) still needs a certificate
    # for that head). The committed policy file decides WHICH tests the lane
    # runs (checker.mk), not WHETHER it runs. The former hardcoded
    # `let landingFloor = true` is REMOVED (no ratified decision backed it —
    # ADR·waiver grep 0 hits): the floor is now derived from committed
    # inputs, floor = lgPolicyNonEmpty ∧ ¬oracleDerivedEmpty —
    #   lgPolicyNonEmpty   from config/policy/landing_required_gateway_tests.json
    #                      (CONTROLLED, H-tree input; read here at the I/O
    #                      boundary, passed into the pure envelope as a
    #                      parameter — :802-809 pattern)
    #   ¬oracleDerivedEmpty from the verified independent-oracle verdict above
    #                       (only a provably-empty derivation lifts the floor;
    #                       valid ∧ derivedEmpty=false keeps the floor ON and
    #                       the normal selection path continues — no exit 2).
    var lgPolicyNonEmpty = false
    let lgPolicyPath = repoRoot / LandingPolicyRelPath
    if fileExists(lgPolicyPath):
      let lgParsed = try: parseFile(lgPolicyPath) except CatchableError: nil
      if lgParsed != nil:
        let tests = lgParsed{"tests"}
        lgPolicyNonEmpty = tests != nil and tests.kind == JArray and tests.len > 0
    if not lgPolicyNonEmpty:
      stderr.writeLine("[impact-closure] WARNING: landing policy empty/unreadable: " &
                       lgPolicyPath & " — floor term off (mode=none still needs a " &
                       "verified oracle-derivedEmpty=true)")
    let landingFloor = lgPolicyNonEmpty and not oracleDerivedEmpty
    let envelope = decisionEnvelope(
      baseRef, headRef, fingerprint,
      finalReport.certainty, finalReport.planStatus,
      selectedUnits,
      landingPolicyFloor = landingFloor,
      oracleDerivedEmpty = oracleDerivedEmpty,
      oracleDigest = oracleDigest,
      oracleAxes = oracleAxes)
    writeFile(decisionOutPath, pretty(envelope, 2))
    echo "[impact-closure] Decision envelope written to: " & decisionOutPath

  # Step 7: Print human-readable summary
  printSummary(finalReport)

  echo &"[impact-closure] Shadow report written to: {outputPath}"

  # Step 8: Exit contract (P8.2 §12).
  # Without --require-certain we stay in shadow mode → always exit 0 (back-compat).
  # With --require-certain, the selector is authoritative-eligible:
  #   0 = CERTAIN / VALID      → approved to run V1 (affected-only certification)
  #   2 = UNCERTAIN / FALLBACK_REQUIRED → V2 full certification MUST be used
  #   1 = ERROR (only reached via an explicit early quit above)
  # Oracle evidence failure (plan Phase 4) is fail-closed REGARDLESS of
  # --require-certain: the select job passes the flag, but a missing/invalid
  # verdict must force full fallback (exit 2) even in shadow mode — the
  # selector must never emit mode=none without a verified independent verdict.
  if oracleInvalid.len > 0:
    quit(2)
  if not requireCertain:
    quit(0)
  if certain:
    quit(0)
  else:
    quit(2)

when isMainModule:
  main()
