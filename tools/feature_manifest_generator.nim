import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}
## Feature Manifest Generator — SSOT for feature discovery.
## Usage: nim c -r tools/feature_manifest_generator.nim
## Output: data/feature_manifest.json (replaces walkDir at runtime).
##
## Walks tests/features/ recursively, parses tags, checks for gateway runners,
## and enriches entries with hotspot_burn_down_queue.json metadata.

import std/[os, json, strutils, sequtils, algorithm, tables]
import checksums/sha2
import shared_types/shared_types
import safe_move


# ─── Parsing Helpers ─────────────────────────────────────────────────

func parseFeatureTags(content: string): seq[string] =
  ## Extract @tags from the first 10 lines of a .feature file.
  result = @[]
  let lines = content.splitLines()
  for i in 0 ..< min(10, lines.len):
    let line = lines[i].strip()
    if line.startsWith("@"):
      for tag in line.splitWhitespace():
        if tag.startsWith("@") and tag notin result:
          result.add(tag)

func extractExportedTypes(content: string): seq[string] =
  ## Extract exported type names from Given/Then step text.
  result = @[]
  for line in content.splitLines():
    let stripped = line.strip()
    if "exported type" in stripped.toLower or "exported_types" in stripped.toLower:
      let parts = stripped.split("\"")
      if parts.len >= 2:
        let typeName = parts[1]
        if typeName.len > 0 and typeName notin result:
          result.add(typeName)

func extractScaffoldMetadata(content: string): tuple[sourceModule, domain, priority: string] =
  ## Parse scaffold comment: "# pending | src/module.nim | domain | priority"
  result = ("", "", "")
  for line in content.splitLines():
    if line.contains("# pending |"):
      let parts = line.split("|").mapIt(it.strip)
      if parts.len >= 4:
        result = (parts[1], parts[2], parts[3])
      break

proc findRunner(featureName: string, gatewayDir: string): string =
  ## Check if a matching _feature_test.nim exists in tests/gateway/.
  ## Returns a RELATIVE path so the manifest is checkout-location independent
  ## (absolute paths would make source_hash/content differ between local and CI,
  ## breaking the deterministic freshness gate, §0.2).
  let candidate = gatewayDir / featureName & "_feature_test.nim"
  if fileExists(candidate):
    return relativePath(candidate, gatewayDir)
  let candidate2 = gatewayDir / featureName.replace("-", "_") & "_feature_test.nim"
  if fileExists(candidate2):
    return relativePath(candidate2, gatewayDir)
  ""

# ─── Hotspot Queue Loading ──────────────────────────────────────────

type
  HotspotMeta = tuple[sourceModule, domain, priority: string]

proc loadHotspotQueue(path: string): Table[string, HotspotMeta] =
  ## Load hotspot_burn_down_queue.json for module metadata.
  result = initTable[string, HotspotMeta]()
  if not fileExists(path): return
  let data = parseFile(path)
  if "queue" notin data: return
  for entry in data["queue"]:
    let module = entry["module"].getStr()
    let domain = entry["domain"].getStr()
    let priority = entry["priority"].getStr()
    let base = module.extractFilename()
    let name = if base.endsWith(".nim"): base[0 ..< ^4] else: base
    result[name] = (module, domain, priority)

# ─── Source Hash ──────────────────────────────────────────────────────

proc computeSourceHash(featureDir: string): string =
  ## Deterministic hash of all .feature files for staleness detection.
  ## Path-independent: hashes RELATIVE paths (relativePath) so the checkout
  ## location (local vs CI) never changes the hash — identical feature content
  ## always yields an identical source_hash (§0.2 Determinism).
  var files: seq[string] = @[]
  for entry in walkDirRec(featureDir):
    if entry.endsWith(".feature"):
      files.add(relativePath(entry, featureDir))
  files.sort()
  var hasher = initSha_256()
  for f in files:
    let content = readFile(featureDir / f)
    hasher.update(f & ":")
    hasher.update(content)
    hasher.update("\n")
  result = $hasher.digest()

# ─── Root Discovery ──────────────────────────────────────────────────

proc findRoot(): string =
  var dir = getCurrentDir()
  while dir.len > 1:
    if fileExists(dir / ".axiom_root"): return dir
    dir = parentDir(dir)
  ""

# ─── Public API ──────────────────────────────────────────────────────

proc buildManifestJson*(projectRoot: string): Result[JsonNode, string] {.axiomEffect: IOEffect.} =
  ## Build feature manifest in memory. No file system mutations.
  try:
    let featuresDir = projectRoot / "tests/features"
    let gatewayDir = projectRoot / "tests/gateway"
    let hotspotPath = projectRoot / "data/hotspot_burn_down_queue.json"

    if not dirExists(featuresDir):
      return err(featuresDir & " does not exist")

    let hotspotQueue = loadHotspotQueue(hotspotPath)

    var featureFiles: seq[string] = @[]
    for path in walkDirRec(featuresDir, relative = true):
      if path.endsWith(".feature"):
        featureFiles.add(path)
    featureFiles.sort()

    var features = newJArray()
    var generatedCount = 0
    var handWrittenCount = 0

    for relPath in featureFiles:
      let fullPath = featuresDir / relPath
      let content = readFile(fullPath)
      let tags = parseFeatureTags(content)
      let exportedTypes = extractExportedTypes(content)

      let name = relPath.extractFilename().changeFileExt("")
      let origin = if "/generated/" in relPath or relPath.startsWith("generated/"):
                     "generated"
                   else:
                     "hand-written"
      let runner = findRunner(name, gatewayDir)

      var domain = ""
      var sourceModule = ""
      var priority = ""
      if hotspotQueue.hasKey(name):
        let meta = hotspotQueue[name]
        sourceModule = meta.sourceModule
        domain = meta.domain
        priority = meta.priority
      else:
        let meta = extractScaffoldMetadata(content)
        sourceModule = meta.sourceModule
        domain = meta.domain
        priority = meta.priority

      if origin == "generated":
        inc generatedCount
      else:
        inc handWrittenCount

      var entry = %*{
        "name": name,
        "path": relPath,
        "tags": tags,
        "domain": domain,
        "source_module": sourceModule,
        "priority": priority,
        "runner": runner,
        "origin": origin
      }
      if exportedTypes.len > 0:
        entry["exported_types"] = %exportedTypes

      features.add(entry)

    let manifest = %*{
      "version": 1,
      "total_count": features.len,
      "generated_count": generatedCount,
      "hand_written_count": handWrittenCount,
      "source_hash": computeSourceHash(featuresDir),
      "features": features
    }
    return ok(manifest)
  except CatchableError as e:
    return err("buildManifest exception: " & e.msg)

proc verifyFeatureManifest*(projectRoot: string): Result[void, string] {.axiomEffect: IOEffect.} =
  ## Pure Verification Gate — no file system mutations.
  ## Deterministic content-hash comparison of the on-disk manifest against the
  ## freshly built manifest. No mtime snapshot dependency — a .feature content
  ## change always yields STALE regardless of timestamps.
  try:
    let outputPath = projectRoot / "data" / "feature_manifest.json"
    if not fileExists(outputPath):
      return err("feature_manifest.json not found. Run: nim r tools/feature_manifest_generator")

    let built = buildManifestJson(projectRoot)
    if built.isErr:
      return err("manifest build failed: " & built.error)

    let onDisk = parseFile(outputPath)
    if onDisk != built.value:
      return err("feature_manifest.json is stale. Run: nim r tools/feature_manifest_generator")

    return Result[void, string](ok: true)
  except CatchableError as e:
    return err("verifyFeatureManifest exception: " & e.msg)

proc generateFeatureManifest*(projectRoot: string): Result[void, string] {.axiomEffect: IOEffect.} =
  ## Standalone CLI path — builds manifest and writes atomically.
  ## Idempotent: if the on-disk manifest already matches the built content,
  ## the write is skipped entirely (mtime preserved → deterministic rebuilds).
  try:
    let built = buildManifestJson(projectRoot)
    if built.isErr: return err(built.error)

    let outputPath = projectRoot / "data" / "feature_manifest.json"
    let outputDir = outputPath.parentDir()

    if fileExists(outputPath):
      let onDisk = try: parseFile(outputPath)
                   except CatchableError: nil
      if onDisk != nil and onDisk == built.value:
        return Result[void, string](ok: true)

    if not dirExists(outputDir): createDir(outputDir)

    let tmpPath = outputPath & ".tmp"
    try:
      writeFile(tmpPath, built.value.pretty())
    except CatchableError as e:
      if fileExists(tmpPath): removeFile(tmpPath)
      return err("write failed: " & e.msg)
    try:
      safeMoveFile(tmpPath, outputPath)
    except FileMoveError as e:
      if fileExists(tmpPath): removeFile(tmpPath)
      return err("atomic replace failed: " & e.msg)

    return Result[void, string](ok: true)
  except CatchableError as e:
    return err("generateFeatureManifest exception: " & e.msg)

# ─── Main (thin wrapper) ─────────────────────────────────────────────

proc main() =
  let root = findRoot()
  if root.len == 0:
    echo "ERROR: .axiom_root not found"
    quit(1)
  let cmd = if paramCount() >= 1: paramStr(1) else: ""
  if cmd == "verify":
    let res = verifyFeatureManifest(root)
    if res.isErr:
      echo "FEATURE MANIFEST STALE: " & res.error
      quit(1)
    echo "feature_manifest.json verified OK"
    return
  if cmd == "ensure":
    # Self-deciding bootstrap: regenerate only when stale; otherwise no-op.
    # Always exits 0 on success so NimScript `exec` can invoke it standalone.
    let res = verifyFeatureManifest(root)
    if res.isErr:
      echo "[Axiom] .feature changed. Regenerating manifest..."
      let gen = generateFeatureManifest(root)
      if gen.isErr:
        echo "ERROR: " & gen.error
        quit(1)
    echo "feature_manifest.json ensured fresh"
    return
  let res = generateFeatureManifest(root)
  if res.isErr:
    echo "ERROR: " & res.error
    quit(1)
  echo "feature_manifest.json generated successfully"

when isMainModule:
  main()
{.pop.}
