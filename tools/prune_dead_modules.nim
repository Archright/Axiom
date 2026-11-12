import core/trusted/layer_declaration
axiomLayer "tools"
import api/tools_facade
import shared_types/shared_types
import std/[os, strutils, algorithm, tables, times]
import safe_move
type
  ModuleInfo = object
    path: string
    basenameNoExt: string
    basenameFile: string
    refCount: int
    hasStub: bool
    exportCount: int
    isCandidate: bool
proc isMainModuleFile(path: string): bool {.axiomEffect: IoEffect.} =
  ## Check if a .nim file contains 'when isMainModule'.
  try:
    let content = readFile(path)
    result = "when isMainModule" in content
  except CatchableError:
    result = false
proc countRefs(filePath, repoRoot: string): int {.axiomEffect: IoEffect.} =
  ## Count references to this file in src/ and tests/.
  result = 0
  let basename = extractFilename(filePath)
  for pattern in ["src/", "tests/"]:
    let searchDir = repoRoot / pattern
    if not dirExists(searchDir):
      continue
    for kind, path in walkDir(searchDir):
      if kind == pcFile and path.endsWith(".nim") and path != filePath:
        try:
          let content = readFile(path)
          if basename in content:
            inc result
        except CatchableError: # axiom:best-effort(unreadable ref target — skip for reference count)
          discard
proc hasExportSymbols(filePath: string): bool {.axiomEffect: IoEffect.} =
  ## Check if a .nim file has exported symbols (proc*, func*, type*, const*).
  try:
    let content = readFile(filePath)
    for line in content.splitLines():
      let s = line.strip()
      if s.startsWith("proc ") and "*" in s:
        return true
      if s.startsWith("func ") and "*" in s:
        return true
      if s.startsWith("type") and "*" in s:
        return true
      if s.startsWith("const ") and "*" in s:
        return true
      if s.startsWith("var ") and "*" in s:
        return true
      if s.startsWith("export ") and s.len > 7:
        return true
    result = false
  except CatchableError:
    result = false
proc collectStubImports(repoRoot: string): seq[string] {.axiomEffect: IoEffect.} =
  ## Collect module names imported by forwarding stubs in src/core/.
  result = @[]
  let coreDir = repoRoot / "src" / "core"
  if not dirExists(coreDir):
    return
  var seen = initTable[string, bool]()
  for kind, path in walkDir(coreDir):
    if kind == pcFile and path.endsWith(".nim"):
      try:
        let content = readFile(path)
        for line in content.splitLines():
          let s = line.strip()
          if s.startsWith("import "):
            let imported = s[7..^1].strip().split(",")[0].strip()
            let moduleName = imported.split("/")[^1].split(".")[0]
            if moduleName notin seen:
              seen[moduleName] = true
              result.add(moduleName)
      except CatchableError: # axiom:best-effort(unreadable stub import file — skip for collection)
        discard
  result.sort()
func isStubImport(moduleName: string, stubs: seq[string]): bool {.raises: [].} =
  result = false
  for s in stubs:
    if s == moduleName:
      return true
proc main() {.axiomEffect: IoEffect.} =
  let params = commandLineParams()
  var dryRun = true

  if params.len > 0:
    case params[0]
    of "--dry-run":
      dryRun = true
    of "--enforce":
      dryRun = false
    of "--help", "-h":
      echo "Usage: prune_dead_modules.nim [--dry-run|--enforce]"
      echo "  --dry-run  (default) Report only, no file moves"
      echo "  --enforce  Move dead modules to quarantine directory"
      quit(0)
    else:
      stderr.writeLine("Unknown option: ", params[0])
      quit(1)

  let repoRoot = findRepoRoot()
  let today = now().format("yyyy'_'MM'_'dd")
  let quarantineDir = repoRoot / "experimental" / "pending_deprecation" / today
  let auditLogDir = repoRoot / "docs" / "reports"
  let auditLog = auditLogDir / ("prune_audit_" & today & ".md")

  # Ensure output dirs exist
  if not dirExists(auditLogDir):
    createDir(auditLogDir)

  # Collect forwarding stub imports
  let stubImports = collectStubImports(repoRoot)

  # Scan all .nim files in src/
  var pruned = 0
  var skipped = 0
  var lines: seq[string] = @[]

  lines.add("# Prune Audit — " & now().format("yyyy-MM-dd HH:mm:ss"))
  lines.add("")
  lines.add("| Module | Ref Count | Exported Symbols | Forwarding Stub? | Action |")
  lines.add("|--------|-----------|-----------------|------------------|--------|")

  let srcDir = repoRoot / "src"
  if not dirExists(srcDir):
    stderr.writeLine("ERROR: src/ directory not found")
    quit(1)

  # Collect all .nim files, sorted deterministically
  var nimFiles: seq[string] = @[]
  for path in walkDirRec(srcDir, yieldFilter = {pcFile}):
    if path.endsWith(".nim") and
       not path.contains("/_") and
       not path.contains("_part") and
       not path.extractFilename().startsWith("_"):
      nimFiles.add(path)
  nimFiles.sort()

  for f in nimFiles:
    let basenameNoExt = f.extractFilename().splitFile().name
    let basenameFile = f.extractFilename()

    # Skip isMainModule files (CLI entry points)
    if isMainModuleFile(f):
      continue

    # Check 1: reference count
    let refCount = countRefs(f, repoRoot)

    # Check 2: forwarding stub
    let hasStub = isStubImport(basenameNoExt, stubImports)

    # Check 3: exported symbols
    let exportCount = if hasExportSymbols(f): 1 else: 0

    # Decision
    if refCount == 0 and not hasStub and exportCount == 0:
      if dryRun:
        lines.add("| " & basenameNoExt & " | 0 | 0 | no | 🔴 CANDIDATE |")
      else:
        if not dirExists(quarantineDir):
          createDir(quarantineDir)
        safeMoveFile(f, quarantineDir / basenameFile)
        lines.add("| " & basenameNoExt & " | 0 | 0 | no | ✅ QUARANTINED |")
      inc pruned
    elif refCount == 0:
      let stubStr = if hasStub: "YES" else: "no"
      lines.add("| " & basenameNoExt & " | 0 | " & $exportCount & " | " & stubStr & " | ⚠️ SKIP |")
      inc skipped

  # Write audit log
  lines.add("")
  lines.add("## Summary")
  let modeStr = if dryRun: "--dry-run" else: "--enforce"
  lines.add("- Mode: " & modeStr)
  lines.add("- Candidates: " & $pruned)
  lines.add("- Skipped (has exports/stub): " & $skipped)
  lines.add("- Date: " & now().format("yyyy-MM-dd HH:mm:ss"))

  writeFile(auditLog, lines.join("\n"))

  # Print summary
  echo "=== Prune Audit Complete ==="
  echo "Candidates: ", pruned, " | Skipped: ", skipped, " | Mode: ", modeStr
  echo "Report: ", auditLog

  # Print full report
  for line in lines:
    echo line

when isMainModule:
  main()
