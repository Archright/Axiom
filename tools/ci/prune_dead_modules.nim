## prune_dead_modules.nim — Dead Module Pruner (Nim port)
## 3-layer dead module detection:
##   1) ref count via readFile+regex in src/ and tests/
##   2) forwarding stub detection in src/core/ imports
##   3) export symbol check
##
## Modes: --dry-run (default, report only), --enforce (move to quarantine)
## Exit code: 0 on success

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, re, algorithm, tables, times]
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
    quarantined: bool

  PruneReport = object
    mode: string
    candidates: int
    skipped: int
    modules: seq[ModuleInfo]
    reportPath: string

const dtFmt = initTimeFormat("yyyy'-'MM'-'dd HH:mm:ss")
const dtFmtFile = initTimeFormat("yyyy'_'MM'_'dd")

proc findRepoRoot(): string =
  var dir = getAppDir()
  while dir.len > 0:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = parentDir(dir)
    if parent == dir:
      break
    dir = parent
  result = getAppDir() / ".." / ".."
  normalizePath(result)

proc collectStubImports(repoRoot: string): Table[string, bool] =
  result = initTable[string, bool]()
  let coreDir = repoRoot / "src" / "core"
  if not dirExists(coreDir):
    return
  for kind, path in walkDir(coreDir):
    if kind == pcFile and path.endsWith(".nim"):
      try:
        let content = readFile(path)
        let importPat = re"(?m)^import\s+(\S+)"
        for m in content.findAll(importPat):
          let moduleName = m.replace(re"(?m)^import\s+", "")
          result[moduleName] = true
      except IOError:
        discard

proc countRefs(moduleFile: string, repoRoot: string): int =
  let basename = extractFilename(moduleFile)
  var count = 0
  let srcDir = repoRoot / "src"
  let testsDir = repoRoot / "tests"
  for searchDir in [srcDir, testsDir]:
    if not dirExists(searchDir):
      continue
    for path in walkDirRec(searchDir, yieldFilter = {pcFile}):
      if path == moduleFile:
        continue
      if path.endsWith(".nim"):
        try:
          let content = readFile(path)
          if content.contains(basename):
            inc count
        except IOError:
          discard
  result = count

proc countExports(filePath: string): int =
  try:
    let content = readFile(filePath)
    let exportPat = re"(?m)^proc\s+\w+\*|^\s+proc\s+\w+\*|(?m)func\s+\w+\*|(?m)type\s+\w+\*|(?m)const\s+\w+\*|^\*\w+|\w+\*\s*[=(]"
    result = content.findAll(exportPat).len
  except IOError:
    result = 0

proc isMainModuleFile(filePath: string): bool =
  try:
    let content = readFile(filePath)
    result = content.contains("when isMainModule")
  except IOError:
    result = false

proc shouldSkip(filePath: string): bool =
  let basename = extractFilename(filePath)
  if basename.startsWith("_") and basename.len > 1:
    return true
  if basename.contains("_part") and basename.endsWith(".nim"):
    return true
  result = false

proc buildReport(report: PruneReport): string =
  var lines: seq[string] = @[]
  lines.add("# Prune Audit — " & now().format(dtFmt))
  lines.add("")
  lines.add("| Module | Ref Count | Exported Symbols | Forwarding Stub? | Action |")
  lines.add("|--------|-----------|-----------------|------------------|--------|")
  for m in report.modules:
    let stubStr = if m.hasStub: "YES" else: "no"
    var action: string
    if m.isCandidate and m.quarantined:
      action = "✅ QUARANTINED"
    elif m.isCandidate:
      action = "🔴 CANDIDATE"
    elif m.refCount == 0:
      action = "⚠️ SKIP"
    else:
      continue
    lines.add("| " & m.basenameNoExt & " | " & $m.refCount & " | " &
              $m.exportCount & " | " & stubStr & " | " & action & " |")
  lines.add("")
  lines.add("## Summary")
  lines.add("- Mode: " & report.mode)
  lines.add("- Candidates: " & $report.candidates)
  lines.add("- Skipped (has exports/stub): " & $report.skipped)
  lines.add("- Date: " & now().format(dtFmt))
  result = lines.join("\n")

proc main() =
  let args = commandLineParams()
  var dryRun = true
  if args.len > 0 and args[0] == "--enforce":
    dryRun = false

  let repoRoot = findRepoRoot()
  let today = now().format(dtFmtFile)
  let quarantineDir = repoRoot / "experimental" / "pending_deprecation" / today
  let reportDir = repoRoot / "docs" / "reports"
  let reportPath = reportDir / "prune_audit_" & today & ".md"

  try:
    createDir(reportDir)
  except OSError:
    discard

  var report = PruneReport(
    mode: if dryRun: "--dry-run" else: "--enforce",
    candidates: 0,
    skipped: 0,
    reportPath: reportPath,
    modules: @[]
  )

  let stubImports = collectStubImports(repoRoot)
  let srcDir = repoRoot / "src"
  if not dirExists(srcDir):
    echo "❌ src/ directory not found at " & srcDir
    quit(1)

  for filePath in walkDirRec(srcDir, yieldFilter = {pcFile}):
    if not filePath.endsWith(".nim"):
      continue
    if shouldSkip(filePath):
      continue
    if isMainModuleFile(filePath):
      continue

    let baseName = extractFilename(filePath)
    let baseNameNoExt = baseName.splitFile().name
    let refCount = countRefs(filePath, repoRoot)
    let hasStub = stubImports.hasKey(baseNameNoExt)
    let exportCount = countExports(filePath)

    var info = ModuleInfo(
      path: filePath,
      basenameNoExt: baseNameNoExt,
      basenameFile: baseName,
      refCount: refCount,
      hasStub: hasStub,
      exportCount: exportCount
    )

    if refCount == 0 and not hasStub and exportCount == 0:
      info.isCandidate = true
      inc report.candidates
      if not dryRun:
        try:
          createDir(quarantineDir)
          safeMoveFile(filePath, quarantineDir / baseName)
          info.quarantined = true
        except FileMoveError as e:
          echo "⚠️  Failed to quarantine " & filePath & ": " & e.msg
    elif refCount == 0:
      inc report.skipped

    report.modules.add(info)

  let reportContent = buildReport(report)
  try:
    writeFile(reportPath, reportContent)
  except IOError as e:
    echo "⚠️  Failed to write report: " & e.msg
    quit(1)

  echo "=== Prune Audit Complete ==="
  echo "Candidates: " & $report.candidates & " | Skipped: " & $report.skipped &
       " | Mode: " & report.mode
  echo "Report: " & reportPath
  echo ""
  echo reportContent

when isMainModule:
  main()
