import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Feature Universe — Manifest-Backed Feature Discovery
##
## SSOT for feature discovery across the Axiom test suite.
## Replaces filesystem walkDir with ``data/feature_manifest.json`` (641 features).
##
## Architecture:
##   1. Primary: parseFile(manifest.json) — covers all 641 features
##   2. Fallback: walkDir(tests/features/) — backward compat if manifest absent
##
## Public API (preserved from original interface):
##   - ``getFeatures*()``  — all FeatureEntry values
##   - ``getFeature*(name)`` — lookup by feature name
##   - ``refreshUniverse*()`` — re-parse manifest (hot-reload)
##
## See also: docs/agents/architecture.md § feature universe

import std/os
import std/json
import std/tables
import std/strutils
import gate/tag_parser

type
  FeaturePriority* = enum
    fpLow
    fpMedium
    fpHigh

  FeatureDependency* = enum
    fdNone
    fdBlocking

  FeatureEntry* = object
    name*: string
    fullPath*: string
    relativePath*: string
    tags*: seq[string]
    scenarioCount*: int
    isExecutable*: bool
    priority*: FeaturePriority
    isWaived*: bool
    waiverReason*: string
    dependency*: FeatureDependency
    origin*: string        ## "hand-written" or "generated"
    domain*: string        ## feature domain (architecture, gate, etc.)
    runner*: string        ## associated runner binary, if any

# ── Singleton State ───────────────────────────────────────────────────────────

var
  universeCache: Table[string, FeatureEntry]
  universeLoaded = false

# ── Root Resolution ───────────────────────────────────────────────────────────

func findProjectRoot*(): string =
  ## Walk upward from CWD looking for ``.axiom_root`` (SSOT anchor).
  ## Falls back to ``axiom.toml`` for backward compatibility.
  ## See AGENTS.md § Deterministic Root Resolution.
  var dir = getCurrentDir()
  while true:
    if fileExists(dir / ".axiom_root"):
      return dir
    if fileExists(dir / "axiom.toml"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  # Last resort: current directory
  return getCurrentDir()

# ── Scenario Counter ──────────────────────────────────────────────────────────

func countScenarios(content: string): int =
  ## Count Scenario/Scenario Outline keywords in feature content.
  for line in content.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("Scenario: ") or stripped.startsWith("Scenario Outline: "):
      inc result

# ── Metadata Parser ───────────────────────────────────────────────────────────

func parseFeatureMetadata(content: string; entry: var FeatureEntry) =
  ## Parse header tags from feature file to enrich entry with runtime metadata.
  ## Tags like @executable, @waived, @priority-high drive gate behavior.
  let parsed = parseFeatureTags(content)
  # Merge file-level tags into entry
  for tag in parsed.tags:
    if tag notin entry.tags:
      entry.tags.add(tag)

  # Derived flags from tags
  entry.isExecutable = isExecutable(parsed)

  # Priority from tags
  for tag in parsed.tags:
    if tag == "priority-high":
      entry.priority = fpHigh
    elif tag == "priority-low":
      entry.priority = fpLow

  # Waiver from tags
  for tag in parsed.tags:
    if tag.startsWith("waived"):
      entry.isWaived = true
      entry.waiverReason = "tagged @waived"

  # Dependency from tags
  for tag in parsed.tags:
    if tag == "blocking":
      entry.dependency = fdBlocking

# ── Manifest Loader (Primary Path) ───────────────────────────────────────────

func loadFromManifest(rootDir: string): Table[string, FeatureEntry] =
  ## Read ``data/feature_manifest.json`` and build the feature table.
  ## This is the primary discovery path — covers all 641 features.
  result = initTable[string, FeatureEntry]()
  let manifestPath = rootDir / "data" / "feature_manifest.json"
  if not fileExists(manifestPath):
    return  # caller will fall back to walkDir

  let manifest = parseFile(manifestPath)
  let features = manifest["features"]
  for feat in features:
    let name = feat["name"].getStr()
    let relPath = feat["path"].getStr()
    let fullPath = rootDir / "tests" / "features" / relPath

    var entry = FeatureEntry(
      name: name,
      fullPath: fullPath,
      relativePath: relPath,
      tags: @[],
      scenarioCount: 0,
      isExecutable: false,
      priority: fpMedium,
      isWaived: false,
      waiverReason: "",
      dependency: fdNone,
      origin: feat["origin"].getStr("unknown"),
      domain: feat["domain"].getStr(""),
      runner: feat["runner"].getStr("")
    )

    # Enrich tags from manifest
    let tagsNode = feat["tags"]
    if tagsNode.kind == JArray:
      for tagNode in tagsNode:
        let tag = tagNode.getStr()
        if tag.len > 0 and tag notin entry.tags:
          entry.tags.add(tag)
    # Strip @ prefix from manifest tags for consistency with tag_parser
    var cleanTags: seq[string] = @[]
    for tag in entry.tags:
      if tag.startsWith("@"):
        cleanTags.add(tag[1..^1])
      else:
        cleanTags.add(tag)
    entry.tags = cleanTags

    # Parse feature file if it exists on disk
    if fileExists(fullPath):
      try:
        let content = readFile(fullPath)
        entry.scenarioCount = countScenarios(content)
        parseFeatureMetadata(content, entry)
      except CatchableError:
        discard  # file read failure: use manifest data only  # axiom:best-effort(ioboundary catch)
    else:
      # Generated feature not yet on disk — derive executable from tags
      entry.isExecutable = "executable" in entry.tags

    result[name] = entry

# ── walkDir Fallback (Backward Compatibility) ────────────────────────────────

func loadFromWalkDir(rootDir: string): Table[string, FeatureEntry] =
  ## Fallback: walk ``tests/features/`` when manifest is absent.
  ## Only finds hand-written features (192 of 641).
  result = initTable[string, FeatureEntry]()
  let featuresDir = rootDir / "tests" / "features"
  if not dirExists(featuresDir):
    return

  for kind, path in walkDir(featuresDir, relative = false):
    if kind != pcFile:
      continue
    if not path.endsWith(".feature"):
      continue

    let fileName = lastPathPart(path)
    let name = fileName.replace(".feature", "")
    let relPath = extractFilename(path)

    var entry = FeatureEntry(
      name: name,
      fullPath: path,
      relativePath: relPath,
      tags: @[],
      scenarioCount: 0,
      isExecutable: false,
      priority: fpMedium,
      isWaived: false,
      waiverReason: "",
      dependency: fdNone,
      origin: "hand-written",
      domain: "",
      runner: ""
    )

    try:
      let content = readFile(path)
      entry.scenarioCount = countScenarios(content)
      parseFeatureMetadata(content, entry)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

    result[name] = entry

# ── Public API ────────────────────────────────────────────────────────────────

func loadUniverse*() =
  ## Load/reload the feature universe. Called on first access or explicit refresh.
  let rootDir = findProjectRoot()

  # Primary: manifest
  universeCache = loadFromManifest(rootDir)

  # Fallback: walkDir if manifest returned empty
  if universeCache.len == 0:
    universeCache = loadFromWalkDir(rootDir)

  universeLoaded = true

func getFeatures*(): seq[FeatureEntry] =
  ## Return all features in the universe.
  if not universeLoaded:
    loadUniverse()
  result = @[]
  for entry in universeCache.values():
    result.add(entry)

func getFeature*(name: string): FeatureEntry =
  ## Lookup a single feature by name.
  ## Raises KeyError if not found.
  if not universeLoaded:
    loadUniverse()
  result = universeCache[name]

func getFeatureOrNull*(name: string): FeatureEntry =
  ## Lookup a single feature by name, returning default if not found.
  if not universeLoaded:
    loadUniverse()
  if universeCache.hasKey(name):
    result = universeCache[name]
  else:
    result = FeatureEntry()

func hasFeature*(name: string): bool =
  ## Check if a feature exists in the universe.
  if not universeLoaded:
    loadUniverse()
  result = universeCache.hasKey(name)

func featureCount*(): int =
  ## Return the total number of features in the universe.
  if not universeLoaded:
    loadUniverse()
  result = universeCache.len

func refreshUniverse*() =
  ## Re-parse the manifest file (hot-reload).
  ## Call after manifest regeneration (Phase 1-S2).
  universeLoaded = false
  loadUniverse()

{.pop.}
