## tools/facade_eliminator.nim — Mechanical facade→direct import replacement engine.
##
## Replaces facade module imports with direct module imports across the codebase.
## Self-contained: no imports from src/ (build boundary compliance).
## Follows ax_hygiene_fix.nim structural patterns.
##
## Usage:
##   nim c tools/facade_eliminator.nim
##   ./tools/facade_eliminator --facade <path> --real <path> [--dry-run]
##   ./tools/facade_eliminator --list
##   ./tools/facade_eliminator --delete-unused [--dry-run]
##   ./tools/facade_eliminator --auto [--dry-run]

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, algorithm, sets]

# ═══════════════════════════════════════════════════════════════════════════════
# §1. Configuration
# ═══════════════════════════════════════════════════════════════════════════════

const
  toolDir = currentSourcePath().parentDir()
  projectRoot = toolDir.parentDir()
  srcDir = projectRoot / "src"

## Top-level dir names to skip under scan path.
const skipDirNames = [
  "tools", "tests", "vendor", "build", "bin",
  ".lake", "nimcache", "node_modules",
]

## Known facade → real module mappings.
## Empty real path = auto-discover from the facade's import/export statements.
const knownFacades: seq[(string, string)] = @[
  ("gate/gate_list", "gate/gate_registry"),
  ("gate/runners", ""),   # multi-target: re-exports 3 sub-modules
  ("gate/nimtry", "gate/nimtry/nimtry_cli"),
  ("core/types/domain_types", ""),  # hub — 37 importers, architectural KEEP
]

## Architecturally justified facades — must never be deleted.
const protectedFacades: seq[string] = @[
  "core/types/domain_types",
  "core/results",
  "core/axiom_pragmas",
]

# ═══════════════════════════════════════════════════════════════════════════════
# §2. Types
# ═══════════════════════════════════════════════════════════════════════════════

type
  FacadeStats = object
    filesScanned: int
    filesModified: int
    importsReplaced: int
    qualifiedRefsReplaced: int
    filesDeleted: int
    warnings: seq[string]

# ═══════════════════════════════════════════════════════════════════════════════
# §3. Facade parsing
# ═══════════════════════════════════════════════════════════════════════════════

proc parseFacadeExports(filePath: string): seq[string] =
  ## Parse a facade module and return the list of re-exported module paths.
  ## Only returns non-std imports that have a corresponding export.
  result = @[]
  if not fileExists(filePath):
    return
  let content = readFile(filePath)
  # Collect all import paths
  var importPaths: seq[string]
  for line in content.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("#") or stripped.startsWith("{.") or stripped.len == 0:
      continue
    if stripped.startsWith("import ") and not stripped.startsWith("import std/"):
      let body = stripped["import ".len .. ^1].strip()
      for part in body.split(","):
        let p = part.strip()
        if p.len > 0 and not p.startsWith("std/"):
          importPaths.add(p)
    elif stripped.startsWith("from "):
      if " import " in stripped:
        let beforeImport = stripped["from ".len .. stripped.find(" import ") - 1]
        let modPath = beforeImport.strip()
        if modPath.len > 0 and not modPath.startsWith("std/"):
          importPaths.add(modPath)
  # Collect all export paths
  var exportPaths: seq[string]
  for line in content.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("export "):
      let body = stripped["export ".len .. ^1].strip()
      for part in body.split(","):
        let p = part.strip()
        if p.len > 0 and not p.startsWith("std/"):
          exportPaths.add(p)
  # Return intersection — modules that are both imported and exported
  for imp in importPaths:
    if imp in exportPaths:
      result.add(imp)

proc facadeModulePath(importPath: string): string =
  ## Resolve a Nim import path to an actual file path.
  result = srcDir / (importPath & ".nim")
  if not fileExists(result):
    result = ""

# ═══════════════════════════════════════════════════════════════════════════════
# §4. File collection
# ═══════════════════════════════════════════════════════════════════════════════

proc collectNimFiles(scanPath: string): seq[string] =
  result = @[]
  if not dirExists(scanPath):
    return
  for kind, path in walkDir(scanPath):
    case kind
    of pcFile:
      if path.endsWith(".nim"):
        result.add(path)
    of pcDir:
      let dirName = path.extractFilename()
      if dirName.startsWith(".") or dirName in skipDirNames:
        continue
      for f in collectNimFiles(path):
        result.add(f)
    else: discard
  result.sort()

# ═══════════════════════════════════════════════════════════════════════════════
# §5. Importer discovery
# ═══════════════════════════════════════════════════════════════════════════════

func fileImportsModule(content: string, importPath: string): bool =
  ## Check if a file imports the given module path.
  for line in content.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("#") or stripped.len == 0:
      continue
    # "import path/to/module" — exact match with boundary check
    if ("import " & importPath) in stripped:
      let idx = stripped.find("import " & importPath)
      let afterIdx = idx + ("import " & importPath).len
      if afterIdx >= stripped.len or stripped[afterIdx] in {',', ' ', '\t', '#'}:
        return true
    # "from path/to/module import ..."
    elif ("from " & importPath & " ") in stripped:
      return true
  return false

proc findImporters(importPath: string): seq[string] =
  ## Find all .nim files under src/ that import the given module.
  result = @[]
  for f in collectNimFiles(srcDir):
    let content = readFile(f)
    if fileImportsModule(content, importPath):
      result.add(f)

# ═══════════════════════════════════════════════════════════════════════════════
# §6. Import line transformation
# ═══════════════════════════════════════════════════════════════════════════════

func transformImportLine(line: string, facadePath: string,
                         realPaths: seq[string]): (string, bool) =
  ## Transform a single import line, replacing facadePath with realPaths.
  ## Returns (transformedLine, wasChanged).
  let stripped = line.strip()

  # Skip non-import lines
  if not stripped.startsWith("import ") and not stripped.startsWith("from "):
    return (line, false)

  # ── "from facade import X" ──
  if stripped.startsWith("from ") and ("from " & facadePath & " ") in stripped:
    if realPaths.len == 1:
      return (line.replace("from " & facadePath & " ",
                           "from " & realPaths[0] & " "), true)
    # Multi-target: use first sub-module (best-effort; user should verify)
    return (line.replace("from " & facadePath & " ",
                         "from " & realPaths[0] & " "), true)

  # ── "import ..." lines ──
  if ("import " & facadePath) notin stripped:
    return (line, false)

  let indent = line[0 ..< line.len - stripped.len]
  let importBody = stripped["import ".len .. ^1]

  # Single import (no commas)
  if "," notin importBody:
    if realPaths.len == 1:
      return (indent & "import " & realPaths[0], true)
    # Expand into multiple import lines
    var expanded: seq[string]
    for rp in realPaths:
      expanded.add(indent & "import " & rp)
    return (expanded.join("\n"), true)

  # Comma-separated import — find and replace the matching entry
  var parts: seq[string]
  var replaced = false
  for part in importBody.split(","):
    let p = part.strip()
    if p == facadePath:
      for rp in realPaths:
        parts.add(rp)
      replaced = true
    else:
      parts.add(p)

  if replaced:
    return (indent & "import " & parts.join(", "), true)
  return (line, false)

# ═══════════════════════════════════════════════════════════════════════════════
# §7. Qualified reference replacement
# ═══════════════════════════════════════════════════════════════════════════════

func replaceQualifiedRefs(content: string, facadeBase: string,
                          realBase: string): (string, int) =
  ## Replace "facadeBase." with "realBase." in non-import, non-comment lines.
  if facadeBase == realBase:
    return (content, 0)
  let needle = facadeBase & "."
  let replacement = realBase & "."
  var count = 0
  var newLines: seq[string]
  for line in content.splitLines():
    var newLine = line
    let stripped = line.strip()
    # Skip comments
    if not stripped.startsWith("#") and needle in newLine:
      # Count occurrences properly, skip import/from lines
      var cnt = 0
      var searchPos = 0
      while true:
        let idx = newLine.find(needle, searchPos)
        if idx < 0: break
        inc cnt
        searchPos = idx + needle.len
      if cnt > 0:
        # Check line isn't an import/from line
        if not stripped.startsWith("import ") and not stripped.startsWith("from "):
          newLine = newLine.replace(needle, replacement)
          count += cnt
    newLines.add(newLine)
  return (newLines.join("\n"), count)

# ═══════════════════════════════════════════════════════════════════════════════
# §8. File-level transformation
# ═══════════════════════════════════════════════════════════════════════════════

proc transformFile(filePath: string, facadePath: string,
                   realPaths: seq[string], dryRun: bool,
                   stats: var FacadeStats): bool =
  ## Replace all facade imports in a single file. Returns true if modified.
  let content = readFile(filePath)
  let facadeBase = facadePath.splitFile().name

  # Phase 1: Transform import/from lines
  let lines = content.splitLines()
  var newLines: seq[string]
  var importChanges = 0
  for line in lines:
    let (transformed, changed) = transformImportLine(line, facadePath, realPaths)
    newLines.add(transformed)
    if changed:
      inc importChanges

  var finalContent = newLines.join("\n")

  # Phase 2: Replace qualified references (facadeModule.symbol → realModule.symbol)
  var qualChanges = 0
  if realPaths.len == 1:
    let realBase = realPaths[0].splitFile().name
    (finalContent, qualChanges) = replaceQualifiedRefs(
      finalContent, facadeBase, realBase)

  if finalContent != content:
    stats.importsReplaced += importChanges
    stats.qualifiedRefsReplaced += qualChanges
    if not dryRun:
      writeFile(filePath, finalContent)
    return true

  return false

# ═══════════════════════════════════════════════════════════════════════════════
# §9. Deletion
# ═══════════════════════════════════════════════════════════════════════════════

proc deleteFacadeFile(importPath: string, isProtected: bool,
                      dryRun: bool, stats: var FacadeStats): bool =
  if isProtected:
    stats.warnings.add(
      "  ⚠ " & importPath & " — PROTECTED (architectural boundary), skipping")
    return false
  let filePath = facadeModulePath(importPath)
  if filePath.len == 0:
    stats.warnings.add("  ⚠ " & importPath & " — file not found on disk")
    return false
  if not dryRun:
    removeFile(filePath)
    echo "  🗑  " & importPath & ".nim — deleted"
  else:
    echo "  🗑  " & importPath & ".nim — would delete (dry run)"
  inc stats.filesDeleted
  return true

# ═══════════════════════════════════════════════════════════════════════════════
# §10. Report generation
# ═══════════════════════════════════════════════════════════════════════════════

proc reportFacades() =
  echo "Known facades — importer inventory"
  echo "═".repeat(60)
  echo ""

  for (facadePath, realPath) in knownFacades:
    let importers = findImporters(facadePath)
    let isProtected = facadePath in protectedFacades
    let filePath = facadeModulePath(facadePath)
    let lineCount = if fileExists(filePath):
                      readFile(filePath).splitLines().len
                    else: 0

    let status = if isProtected: "🛡  PROTECTED"
                 elif importers.len == 0: "🗑  0 importers — delete safe"
                 else: "⚠  " & $importers.len & " importers"

    echo "  " & facadePath
    echo "    Status:  " & status
    echo "    Lines:   " & $lineCount
    if realPath.len > 0:
      echo "    Target:  " & realPath
    else:
      let subs = if fileExists(filePath): parseFacadeExports(filePath)
                 else: @[]
      if subs.len > 0:
        echo "    Exports: " & subs.join(", ")
    if importers.len > 0 and importers.len <= 5:
      echo "    Importers:"
      for imp in importers:
        echo "      - " & imp.relativePath(projectRoot)
    elif importers.len > 5:
      echo "    Importers: " & $importers.len & " files"
    echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# §11. CLI entry point
# ═══════════════════════════════════════════════════════════════════════════════

proc main() =
  let params = commandLineParams()
  var mode = ""   # "replace" | "list" | "delete-unused" | "auto"
  var facadePath = ""
  var realPath = ""
  var dryRun = false

  # ── Argument parsing ──
  var i = 0
  while i < params.len:
    case params[i]
    of "--facade":
      if i + 1 < params.len:
        facadePath = params[i + 1]
        inc i
    of "--real":
      if i + 1 < params.len:
        realPath = params[i + 1]
        inc i
    of "--list":
      mode = "list"
    of "--delete-unused":
      mode = "delete-unused"
    of "--auto":
      mode = "auto"
    of "--dry-run":
      dryRun = true
    of "--help", "-h":
      echo "facade_eliminator — Mechanical facade→direct import replacement"
      echo ""
      echo "Usage:"
      echo "  facade_eliminator --facade <path> --real <path> [--dry-run]"
      echo "  facade_eliminator --list"
      echo "  facade_eliminator --delete-unused [--dry-run]"
      echo "  facade_eliminator --auto [--dry-run]"
      echo ""
      echo "Modes:"
      echo "  --facade/--real   Replace one facade with a real module"
      echo "  --list            List known facades and their importer counts"
      echo "  --delete-unused   Delete facades with 0 importers"
      echo "  --auto            Process all known facades automatically"
      echo ""
      echo "Options:"
      echo "  --dry-run         Show what would change without writing"
      echo "  --help, -h        Show this help"
      quit(0)
    else:
      stderr.writeLine("Unknown option: " & params[i] & " (use --help)")
      quit(1)
    inc i

  # Infer mode from arguments
  if mode.len == 0 and facadePath.len > 0:
    mode = "replace"

  # ── Dispatch ──
  case mode

  of "list":
    reportFacades()

  of "delete-unused":
    echo "Delete unused facades"
    echo "═".repeat(60)
    echo "Dry run: " & $dryRun
    echo ""

    var stats = FacadeStats()
    for (fp, _) in knownFacades:
      let importers = findImporters(fp)
      let isProt = fp in protectedFacades
      if importers.len == 0:
        discard deleteFacadeFile(fp, isProt, dryRun, stats)
      else:
        echo "  ⏭  " & fp & " — " & $importers.len & " importers (skipping)"

    for w in stats.warnings:
      echo w

    echo ""
    echo "═".repeat(60)
    echo "Files deleted: " & $stats.filesDeleted

  of "auto":
    echo "Auto-process all known facades"
    echo "═".repeat(60)
    echo "Dry run: " & $dryRun
    echo ""

    for (fp, rp) in knownFacades:
      if fp in protectedFacades:
        echo "  🛡  " & fp & " — PROTECTED, skipping"
        continue

      let importers = findImporters(fp)

      # Zero importers → delete
      if importers.len == 0:
        echo "  🗑  " & fp & " — 0 importers"
        var stats = FacadeStats()
        discard deleteFacadeFile(fp, false, dryRun, stats)
        echo ""
        continue

      echo "  🔄 " & fp & " — " & $importers.len & " importers"

      # Resolve real module paths
      var targets: seq[string]
      if rp.len > 0:
        targets = @[rp]
      else:
        let filePath = facadeModulePath(fp)
        if filePath.len == 0:
          echo "    ⚠ Facade file not found on disk"
          continue
        targets = parseFacadeExports(filePath)
        if targets.len == 0:
          echo "    ⚠ No exports detected in facade"
          continue
      echo "    Targets: " & targets.join(", ")

      var stats = FacadeStats()
      for imp in importers:
        let relPath = imp.relativePath(projectRoot)
        var fileStats = FacadeStats()
        let modified = transformFile(imp, fp, targets, dryRun, fileStats)
        if modified:
          inc stats.filesModified
          stats.importsReplaced += fileStats.importsReplaced
          stats.qualifiedRefsReplaced += fileStats.qualifiedRefsReplaced
          echo "    ✓ " & relPath & " — " & $fileStats.importsReplaced &
               " imports, " & $fileStats.qualifiedRefsReplaced & " qual refs"
        else:
          echo "    · " & relPath & " — no change"

      echo ""

    echo "═".repeat(60)
    echo "Done."

  of "replace":
    if facadePath.len == 0:
      stderr.writeLine("Error: --facade is required")
      quit(1)
    if realPath.len == 0:
      stderr.writeLine("Error: --real is required (or use --auto)")
      quit(1)

    echo "Replace: " & facadePath & " → " & realPath
    echo "═".repeat(60)
    echo "Dry run: " & $dryRun
    echo ""

    let importers = findImporters(facadePath)
    if importers.len == 0:
      echo "No importers found for " & facadePath
      quit(0)

    echo "Found " & $importers.len & " importers"
    echo ""

    var stats = FacadeStats()
    for imp in importers:
      let relPath = imp.relativePath(projectRoot)
      var fileStats = FacadeStats()
      let modified = transformFile(imp, facadePath, @[realPath],
                                   dryRun, fileStats)
      if modified:
        inc stats.filesModified
        stats.importsReplaced += fileStats.importsReplaced
        stats.qualifiedRefsReplaced += fileStats.qualifiedRefsReplaced
        echo "  ✓ " & relPath & " — " & $fileStats.importsReplaced &
             " imports, " & $fileStats.qualifiedRefsReplaced & " qual refs"

    echo ""
    echo "═".repeat(60)
    echo "Summary:"
    echo "  Files modified:       " & $stats.filesModified
    echo "  Imports replaced:     " & $stats.importsReplaced
    echo "  Qualified refs:       " & $stats.qualifiedRefsReplaced
    if dryRun:
      echo ""
      echo "  (dry run — no files were written)"

  else:
    stderr.writeLine("No mode specified. Use --help for usage.")
    quit(1)

when isMainModule:
  main()
