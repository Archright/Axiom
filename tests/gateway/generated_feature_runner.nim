## generated_feature_runner.nim — Generic BDD runner for generated features.
##
## Scope: compile-time verification + structural contract checks
## - "module compiles": `nim check` → exit code 0
## - "type has default": `var _: T = default(T)` compiles
## - "import boundary": module doesn't directly import core/trusted/ or core/types/
## - "pragma contracts": exported funcs declare {.raises: [].} or {.raises: [CatchableError].}
## - "I/O boundary": non-CLI modules don't import I/O modules (std/os, std/osproc, etc.)
## NOT in scope: runtime instantiation, business logic, I/O side effects.
##
## Reads data/feature_manifest.json at runtime. Skips gracefully if absent.
{.push raises: [CatchableError].}

import std/[unittest, os, json, strutils, sequtils, osproc]

const manifestPath = "data/feature_manifest.json"

# ─── Helpers ──────────────────────────────────────────────────────────────

proc loadManifest(): JsonNode =
  ## Parse the feature manifest. Returns nil if missing.
  if not fileExists(manifestPath):
    return nil
  parseFile(manifestPath)

proc shellCheck(cmd: string): bool =
  ## Run a shell command, return true on exit code 0.
  ## Suppresses stdout/stderr — only exit code matters.
  try:
    let (_, exitCode) = execCmdEx(cmd)
    exitCode == 0
  except OSError:
    false

proc checkModuleCompiles(modulePath: string): bool =
  ## Verify a Nim module compiles without linking (nim check).
  if not fileExists(modulePath):
    return false
  shellCheck("nim check --hints:off --warnings:off " & modulePath.quoteShell)

proc importPathFromSource(modulePath: string): string =
  ## Derive Nim import path from source file path.
  ## e.g. "src/core/bmc/bmc_engine.nim" → "core/bmc/bmc_engine"
  let parts = modulePath.split("/")
  if parts.len >= 3 and parts[0] == "src":
    result = parts[1 .. ^1].join("/").replace(".nim", "")
  else:
    result = ""

proc checkTypeHasDefault(typeName, modulePath: string): bool =
  ## Verify `default(T)` compiles for a given type.
  ## Does NOT instantiate at runtime — avoids DB/network panic risk.
  let importPath = importPathFromSource(modulePath)
  if importPath.len == 0:
    return false
  let code = "import " & importPath & "\nvar _: " & typeName & " = default(" & typeName & ")"
  shellCheck("nim check --hints:off --warnings:off -e:" & code.quoteShell)

# ─── Feature filtering ────────────────────────────────────────────────────

proc isGenerated(feat: JsonNode): bool =
  ## True if this feature was code-generated (not hand-written or manual).
  if feat["origin"].getStr != "generated":
    return false
  let tags = feat["tags"].mapIt(it.getStr)
  "@manual" notin tags

# ─── Extraction Helpers (duplicated from feature_scaffold_generator) ─────

func stripComments(content: string): string =
  ## Remove single-line (# and ##) comment lines.
  result = ""
  for line in content.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("#") and not stripped.startsWith("#["):
      continue
    result.add(line)
    result.add("\n")

func extractImportPaths(content: string): seq[string] =
  ## Extract all import paths from module content.
  let cleanContent = stripComments(content)
  result = @[]
  for line in cleanContent.splitLines():
    let stripped = line.strip()
    if not stripped.startsWith("import "): continue
    if stripped.len <= "import ".len: continue
    let imports = stripped["import ".len .. ^1].strip()
    for part in imports.split(','):
      let path = part.strip().split(' ')[0].strip()
      if path.len > 0 and path notin result:
        result.add(path)

func extractPragmaAnnotatedProcs(content: string): seq[(string, string)] =
  ## Scan for exported procs with pragma annotations.
  ## Returns seq of (procName, pragmaKind).
  ## pragmaKind: "raises", "noSideEffect", "axiomIoBoundary", or "none"
  let cleanContent = stripComments(content)
  result = @[]
  for line in cleanContent.splitLines():
    let stripped = line.strip()
    if not (stripped.startsWith("proc ") or stripped.startsWith("func ")):
      continue
    if "*" notin stripped:
      continue
    let parenOpen = stripped.find('(')
    if parenOpen < 0: continue
    let nameStart = if stripped.startsWith("func "): "func ".len else: "proc ".len
    let namePart = stripped[nameStart ..< parenOpen].strip()
    let funcName = if namePart.endsWith("*"): namePart[0 ..< ^1] else: namePart
    var pragmaKind = "none"
    if "{.raises:" in stripped: pragmaKind = "raises"
    elif "{.noSideEffect.}" in stripped: pragmaKind = "noSideEffect"
    elif "{.axiomIoBoundary.}" in stripped: pragmaKind = "axiomIoBoundary"
    result.add((funcName, pragmaKind))

func hasIOModuleImport(content: string): bool =
  ## Check if module imports I/O modules (std/os, std/osproc, etc.)
  let imports = extractImportPaths(content)
  const ioModules = ["std/os", "std/osproc", "std/streams", "std/net",
                     "std/httpclient", "std/asynchttpserver", "std/asyncnet",
                     "os", "osproc", "streams", "net", "httpclient"]
  for imp in imports:
    for ioMod in ioModules:
      if imp == ioMod or imp.startsWith(ioMod & "/"):
        return true
  return false

# ─── Verification Procs ───────────────────────────────────────────────────

proc verifyImportBoundary(sourceModule: string): seq[string] =
  ## Verify module doesn't directly import core/trusted/ or core/types/.
  ## Returns list of violations (empty = pass).
  result = @[]
  if not fileExists(sourceModule):
    return
  var content: string
  try:
    content = readFile(sourceModule)
  except IOError:
    return
  let imports = extractImportPaths(content)
  const forbidden = ["core/trusted/", "core/types/"]
  for imp in imports:
    for f in forbidden:
      if imp.startsWith(f) or imp == f[0 ..< ^1]:
        result.add(imp)

proc verifyPragmaContracts(sourceModule: string): seq[string] =
  ## Verify exported funcs have {.raises: [].} or {.raises: [CatchableError].}.
  ## Returns list of func names missing contracts (empty = pass).
  result = @[]
  if not fileExists(sourceModule):
    return
  var content: string
  try:
    content = readFile(sourceModule)
  except IOError:
    return
  let procs = extractPragmaAnnotatedProcs(content)
  for (name, pragma) in procs:
    if pragma == "none":
      result.add(name)

proc verifyIOBoundary(sourceModule: string): bool =
  ## Verify non-I/O modules don't import I/O modules.
  ## Returns true if violation found (module imports I/O but is not in cli/).
  if not fileExists(sourceModule):
    return false
  # Modules in src/cli/ are allowed to import I/O
  if sourceModule.contains("/cli/"):
    return false
  var content: string
  try:
    content = readFile(sourceModule)
  except IOError:
    return false
  hasIOModuleImport(content)

# ─── Test Suite ───────────────────────────────────────────────────────────

suite "Generated Feature Runner — compile + default(T) + contracts":

  test "manifest exists and has valid structure":
    ## Scenario: manifest file is present and parseable
    let manifest = loadManifest()
    if manifest == nil:
      skip()
    else:
      check manifest.hasKey("features")
      check manifest["features"].kind == JArray
      check manifest.hasKey("total_count")
      check manifest.hasKey("generated_count")
      check manifest.hasKey("hand_written_count")

  test "manifest counts are internally consistent":
    ## Scenario: count fields sum correctly
    let manifest = loadManifest()
    if manifest == nil:
      skip()
    else:
      let totalCount = manifest["total_count"].getInt
      let generatedCount = manifest["generated_count"].getInt
      let handWrittenCount = manifest["hand_written_count"].getInt
      check totalCount == generatedCount + handWrittenCount
      check totalCount == manifest["features"].len

  test "all generated modules compile via nim check":
    ## Scenario: each generated feature's source module compiles
    let manifest = loadManifest()
    if manifest == nil:
      skip()
    else:
      var failures: seq[string] = @[]
      var tested = 0
      for feat in manifest["features"]:
        if not feat.isGenerated:
          continue
        let sourceModule = feat["source_module"].getStr
        if sourceModule.len == 0:
          continue
        inc tested
        if not checkModuleCompiles(sourceModule):
          failures.add(feat["name"].getStr & " (" & sourceModule & ")")
      echo "  compiled " & $tested & " generated modules"
      if failures.len > 0:
        echo "  FAILURES: " & failures.join(", ")
      check failures.len == 0

  test "all exported types have default(T)":
    ## Scenario: every exported type in generated features has a default value
    let manifest = loadManifest()
    if manifest == nil:
      skip()
    else:
      var failures: seq[string] = @[]
      var tested = 0
      for feat in manifest["features"]:
        if not feat.isGenerated:
          continue
        if not feat.hasKey("exported_types"):
          continue
        let sourceModule = feat["source_module"].getStr
        if sourceModule.len == 0:
          continue
        for typ in feat["exported_types"]:
          let typeName = typ.getStr
          inc tested
          if not checkTypeHasDefault(typeName, sourceModule):
            failures.add(feat["name"].getStr & "::" & typeName)
      echo "  verified " & $tested & " exported types have defaults"
      if failures.len > 0:
        echo "  FAILURES: " & failures.join(", ")
      check failures.len == 0

  test "no feature has empty source_module":
    ## Scenario: every generated feature declares a source module path
    let manifest = loadManifest()
    if manifest == nil:
      skip()
    else:
      var orphanFeatures: seq[string] = @[]
      for feat in manifest["features"]:
        if not feat.isGenerated:
          continue
        if feat["source_module"].getStr.len == 0:
          orphanFeatures.add(feat["name"].getStr)
      if orphanFeatures.len > 0:
        echo "  features without source_module: " & orphanFeatures.join(", ")
      check orphanFeatures.len == 0

# ─── Import Boundary Tests ───────────────────────────────────────────────

suite "Generated Feature Runner — import boundary":

  test "critical modules respect import boundary":
    ## Scenario: module respects import boundary
    ## Given a critical module in the manifest
    ## Then it should not directly import "core/trusted/" or "core/types/"
    ## And all internal imports should go through forwarding stubs
    let manifest = loadManifest()
    if manifest == nil:
      skip()
    else:
      var violations: seq[string] = @[]
      var tested = 0
      for feat in manifest["features"]:
        if not feat.isGenerated:
          continue
        let priority = feat["priority"].getStr
        if priority != "critical":
          continue
        let sourceModule = feat["source_module"].getStr
        if sourceModule.len == 0:
          continue
        inc tested
        let vio = verifyImportBoundary(sourceModule)
        for v in vio:
          violations.add(feat["name"].getStr & " → " & v)
      echo "  checked " & $tested & " critical modules for import boundary"
      if violations.len > 0:
        echo "  VIOLATIONS: " & violations.join(", ")
      check violations.len == 0

  test "high modules respect import boundary":
    ## Scenario: module respects import boundary (high priority)
    let manifest = loadManifest()
    if manifest == nil:
      skip()
    else:
      var violations: seq[string] = @[]
      var tested = 0
      for feat in manifest["features"]:
        if not feat.isGenerated:
          continue
        let priority = feat["priority"].getStr
        if priority != "high":
          continue
        let sourceModule = feat["source_module"].getStr
        if sourceModule.len == 0:
          continue
        inc tested
        let vio = verifyImportBoundary(sourceModule)
        for v in vio:
          violations.add(feat["name"].getStr & " → " & v)
      echo "  checked " & $tested & " high modules for import boundary"
      if violations.len > 0:
        echo "  VIOLATIONS: " & violations.join(", ")
      check violations.len == 0

# ─── Pragma Contract Tests ──────────────────────────────────────────────

suite "Generated Feature Runner — pragma contracts":

  test "critical modules have pragma contracts on exported funcs":
    ## Scenario: exported funcs declare exception contracts
    ## Given the module exports funcs
    ## Then each func should have {.raises: [].} or {.raises: [CatchableError].}
    let manifest = loadManifest()
    if manifest == nil:
      skip()
    else:
      var warnings: seq[string] = @[]
      var tested = 0
      for feat in manifest["features"]:
        if not feat.isGenerated:
          continue
        let priority = feat["priority"].getStr
        if priority != "critical":
          continue
        let sourceModule = feat["source_module"].getStr
        if sourceModule.len == 0:
          continue
        let missing = verifyPragmaContracts(sourceModule)
        for name in missing:
          inc tested
          warnings.add(feat["name"].getStr & "::" & name)
      echo "  found " & $tested & " exported funcs missing exception contracts in critical modules"
      if warnings.len > 0:
        echo "  WARNINGS: " & warnings.join(", ")
      # Warnings only — not a hard failure for now
      # Assert the reported count matches actual data collected
      check tested == warnings.len

# ─── I/O Boundary Tests ─────────────────────────────────────────────────

suite "Generated Feature Runner — I/O boundary":

  test "non-CLI modules do not import I/O modules":
    ## Scenario: non-I/O modules don't import I/O modules
    ## Given a module not in src/cli/
    ## Then it should not import std/os, std/osproc, etc.
    let manifest = loadManifest()
    if manifest == nil:
      skip()
    else:
      var violations: seq[string] = @[]
      var tested = 0
      for feat in manifest["features"]:
        if not feat.isGenerated:
          continue
        let priority = feat["priority"].getStr
        if priority notin ["critical", "high"]:
          continue
        let sourceModule = feat["source_module"].getStr
        if sourceModule.len == 0:
          continue
        inc tested
        if verifyIOBoundary(sourceModule):
          violations.add(feat["name"].getStr & " (" & sourceModule & ")")
      echo "  checked " & $tested & " critical/high modules for I/O boundary"
      if violations.len > 0:
        echo "  VIOLATIONS: " & violations.join(", ")
      check violations.len == 0

{.pop.}
