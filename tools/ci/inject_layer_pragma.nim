## inject_layer_pragma.nim — Inject `axiomLayer` pragma (statement form) into Nim source files
##
## Uses template-call form `axiomLayer "domain"` instead of bracket form `{.axiomLayer: "domain".}`
## because Nim 2.2.x rejects custom module-level bracket pragmas.
## Each file also gets `import core/trusted/layer_declaration` for the template declaration.
##
## Usage:
##   inject_layer_pragma <directory>   # scan directory recursively
##   inject_layer_pragma <file>        # process single file
##   inject_layer_pragma --dry-run ... # preview changes without writing
##
## Exit codes:
##   0 - all files processed successfully
##   1 - error during processing

import std/[os, strutils]

type
  CliConfig = object
    dryRun: bool
    target: string

const
  ImportLine = "import core/trusted/layer_declaration"

proc detectLayer(filePath: string): string =
  let normalized = "/" & filePath.replace("\\", "/")
  if normalized.endsWith("/src/api.nim"): result = "presentation"
  elif normalized.endsWith("/src/engine.nim"): result = "infrastructure"
  elif "/src/core/" in normalized: result = "domain"
  elif "/src/verification/" in normalized or "/src/engine/" in normalized or
       "/src/frontend/" in normalized or "/src/infrastructure/" in normalized or
       "/src/personas/" in normalized or "/src/generated/" in normalized: result = "infrastructure"
  elif "/src/cli/" in normalized or "/src/mcp/" in normalized or
       "/src/ui/" in normalized or "/src/api/" in normalized: result = "presentation"
  elif "/src/gate/" in normalized or "/src/policy/" in normalized: result = "gate"
  elif "/src/sieve/" in normalized: result = "infrastructure"
  elif "/src/shared_types/" in normalized: result = "infrastructure"
  elif normalized.startsWith("/tools/") or "/tools/" in normalized: result = "tools"
  else: result = "unknown"

proc hasAxiomLayerImportAndCall(lines: seq[string]): bool =
  for i in 0 ..< lines.len:
    if lines[i].strip() == ImportLine:
      if i + 1 < lines.len and lines[i + 1].strip().startsWith("axiomLayer "):
        return true
  false

proc isLayerDeclarationFile(lines: seq[string]): bool =
  for line in lines:
    if "template axiomLayer*" in line:
      return true
  false

proc findInsertionPoint(lines: seq[string]): int =
  if lines.len == 0: return 0
  let startIdx = if lines[0].strip().startsWith("#!"): 1 else: 0
  for i in startIdx ..< lines.len:
    let stripped = lines[i].strip()
    if stripped.len == 0 or stripped.startsWith("##"):
      continue
    return i
  lines.len

proc processFile(filePath: string; config: CliConfig): bool =
  if not fileExists(filePath):
    stderr.writeLine("ERROR: file not found: " & filePath)
    return false
  let content = readFile(filePath)
  let lines = content.splitLines()
  if isLayerDeclarationFile(lines):
    echo "  SKIP (layer_declaration itself): " & filePath
    return false
  if hasAxiomLayerImportAndCall(lines):
    echo "  SKIP (already has pragma): " & filePath
    return false
  let layer = detectLayer(filePath)
  if layer == "unknown":
    stderr.writeLine("  SKIP (unknown layer): " & filePath)
    return false
  let insertAt = findInsertionPoint(lines)
  let pragmaLine = "axiomLayer \"" & layer & "\""
  var newLines: seq[string] = @[]
  for i, line in lines:
    if i == insertAt:
      newLines.add(ImportLine)
      newLines.add(pragmaLine)
    newLines.add(line)
  if insertAt >= lines.len:
    newLines.add(ImportLine)
    newLines.add(pragmaLine)
  let newContent = newLines.join("\n")
  if config.dryRun:
    echo "  WOULD MODIFY: " & filePath & " (layer: " & layer & ", insert at line " & $insertAt & ")"
  else:
    writeFile(filePath, newContent)
    echo "  MODIFIED: " & filePath & " (layer: " & layer & ", insert at line " & $insertAt & ")"
  true

proc processDir(dirPath: string; config: CliConfig): int =
  var count = 0
  for kind, path in walkDir(dirPath):
    if kind == pcFile and path.endsWith(".nim"):
      if processFile(path, config):
        inc count
    elif kind == pcDir:
      count += processDir(path, config)
  count

proc parseCli(): CliConfig =
  result.dryRun = false
  result.target = ""
  var args = commandLineParams()
  var i = 0
  while i < args.len:
    if args[i] == "--dry-run":
      result.dryRun = true
    elif result.target.len == 0:
      result.target = args[i]
    inc i
  if result.target.len == 0:
    stderr.writeLine("Usage: inject_layer_pragma [--dry-run] <file.nim | directory>")
    quit(1)

proc main() =
  let config = parseCli()
  let target = config.target
  if dirExists(target):
    echo "Scanning directory: " & target
    let modCount = processDir(target, config)
    if config.dryRun:
      echo "Dry-run complete. " & $modCount & " file(s) would be modified."
    else:
      echo "Done. " & $modCount & " file(s) modified."
  elif fileExists(target):
    if processFile(target, config):
      echo "Done. 1 file modified."
    else:
      echo "No changes made."
  else:
    stderr.writeLine("ERROR: target not found: " & target)
    quit(1)

when isMainModule:
  main()
