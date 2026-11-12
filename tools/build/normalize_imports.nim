import core/trusted/layer_declaration
axiomLayer "tools"
import std/[json, os, strutils, re, sequtils, algorithm]

const
  RegistryFile = "src/core/domain_layout.json"

type
  ImportInfo = object
    lineNo: int
    fullLine: string
    impType: string
    importPath: string

proc loadRegistry(): JsonNode =
  let content = readFile(RegistryFile)
  result = parseJson(content)

proc resolveAbsolutePath(importPath, sourceFile: string): string =
  let sourceDir = sourceFile.parentDir
  var candidate = sourceDir / (importPath.replace('/', DirSep) & ".nim")
  if fileExists(candidate):
    return candidate.absolutePath
  candidate = "src" / (importPath.replace('/', DirSep) & ".nim")
  if fileExists(candidate):
    return candidate.absolutePath
  candidate = (importPath.replace('/', DirSep) & ".nim")
  if fileExists(candidate):
    return candidate.absolutePath
  result = ""

proc computeOptimalPath(targetFile: string; registry: JsonNode): string =
  let srcRoot = absolutePath("src")
  var rel = ""
  try:
    rel = targetFile.relativePath(srcRoot)
  except ValueError:
    return ""
  let parts = rel.split(DirSep)
  if parts.len < 2:
    return ""
  var moduleName = parts[^1]
  if moduleName.endsWith(".nim"):
    moduleName = moduleName[0..^5]
  let rootPrimitives = registry{"root_primitives"}
  if not rootPrimitives.isNil and parts.len == 2 and parts[0] == "core":
    for rp in rootPrimitives:
      if rp.getStr("") == moduleName:
        return "core/" & moduleName
  let domains = registry{"domains"}
  if not domains.isNil:
    for name, info in domains.pairs:
      let isFacade = info{"is_facade"}.getBool(false)
      let facadePath = info{"facade_path"}.getStr("")
      let importPath = info{"import_path"}.getStr("")
      if isFacade and facadePath.len > 0 and importPath.len > 0:
        if rel.startsWith(importPath):
          return facadePath
  result = rel.replace(DirSep, '/')
  if result.endsWith(".nim"):
    result = result[0..^5]

proc scanImports(filepath: string): seq[ImportInfo] =
  result = @[]
  try:
    let content = readFile(filepath)
    var lineNo = 0
    for line in content.splitLines:
      inc lineNo
      let stripped = line.strip
      if stripped.startsWith("#"):
        continue
      var m: array[1, string]
      let importPattern = re"""^import\s+([.A-Za-z_][.A-Za-z0-9_/]*)"""
      let fromPattern = re"""^from\s+([.A-Za-z_][.A-Za-z0-9_/]*)\s+import"""
      if line.find(importPattern, m) >= 0:
        let path = m[0]
        if path.startsWith("std/") or path.startsWith("compiler/") or path.startsWith("fusion/") or path.startsWith("checksums/"):
          continue
        var impType = if '/' notin path: "bare" else: "absolute"
        if path.startsWith("./"): impType = "relative_dot"
        elif path.startsWith("../"): impType = "relative_parent"
        result.add(ImportInfo(lineNo: lineNo, fullLine: stripped, impType: impType, importPath: path))
        continue
      if line.find(fromPattern, m) >= 0:
        let path = m[0]
        if path.startsWith("std/") or path.startsWith("compiler/") or path.startsWith("fusion/") or path.startsWith("checksums/"):
          continue
        var impType = if '/' notin path: "bare" else: "absolute"
        if path.startsWith("./"): impType = "relative_dot"
        elif path.startsWith("../"): impType = "relative_parent"
        result.add(ImportInfo(lineNo: lineNo, fullLine: stripped, impType: impType, importPath: path))
  except CatchableError:
    discard  # axiom:best-effort(import scan failure)

proc normalizeFile(filepath: string; registry: JsonNode; dryRun: bool): seq[string] =
  result = @[]
  try:
    let content = readFile(filepath)
    var lines = content.splitLines
    var modified = false
    let imports = scanImports(filepath)
    if imports.len == 0:
      return result
    for imp in imports:
      if imp.impType == "absolute":
        continue
      var resolved = ""
      if imp.impType == "relative_parent":
        resolved = resolveAbsolutePath(imp.importPath, filepath)
      elif imp.impType == "relative_dot":
        resolved = resolveAbsolutePath(imp.importPath[2..^1], filepath)
      elif imp.impType == "bare":
        resolved = resolveAbsolutePath(imp.importPath, filepath)
        if resolved.len == 0:
          resolved = resolveAbsolutePath("core/" & imp.importPath, filepath)
      if resolved.len == 0:
        result.add("  SKIP " & extractFilename(filepath) & ":" & $imp.lineNo & " — cannot resolve '" & imp.importPath & "'")
        continue
      let optimal = computeOptimalPath(resolved, registry)
      if optimal.len == 0:
        result.add("  SKIP " & extractFilename(filepath) & ":" & $imp.lineNo & " — cannot compute optimal path for '" & imp.importPath & "'")
        continue
      if imp.importPath == optimal:
        continue
      let oldLine = lines[imp.lineNo - 1]
      var newLine = oldLine
      if imp.impType == "relative_parent":
        newLine = oldLine.replace(imp.importPath, optimal)
      elif imp.impType == "relative_dot":
        newLine = oldLine.replace(imp.importPath, optimal)
      elif imp.impType == "bare":
        newLine = oldLine.replace(" " & imp.importPath, " " & optimal)
      if oldLine != newLine:
        lines[imp.lineNo - 1] = newLine
        modified = true
        result.add("  " & extractFilename(filepath) & ":" & $imp.lineNo & "  " & imp.importPath & " → " & optimal)
    if modified and not dryRun:
      writeFile(filepath, lines.join("\n"))
  except CatchableError:
    discard  # axiom:best-effort(import normalization write failure for one file must not halt batch processing)

proc main() =
  let args = commandLineParams()
  let dryRun = args.contains("--dry-run") or not args.contains("--execute")
  let mode = if dryRun: "DRY RUN" else: "EXECUTE"
  echo "=== Import Normalization — " & mode & " ===\n"

  let registry = loadRegistry()
  var nimFiles: seq[string] = @[]
  for path in walkDirRec("src"):
    if path.endsWith(".nim") and ".nimcache" notin path:
      nimFiles.add(path)
  nimFiles.sort()

  var totalChanges = 0
  var filesChanged = 0

  for filepath in nimFiles:
    let changes = normalizeFile(filepath, registry, dryRun)
    if changes.len > 0:
      inc filesChanged
      for c in changes:
        echo c
      totalChanges += changes.len

  echo "\n=== Summary (" & mode & ") ==="
  echo "  Files scanned: " & $nimFiles.len
  echo "  Files changed: " & $filesChanged
  echo "  Imports normalized: " & $totalChanges

  if dryRun:
    echo "\n  Run with --execute to apply changes."

when isMainModule:
  main()
