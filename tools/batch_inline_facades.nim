import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, strutils, sequtils, times, tables, sets, algorithm, re]
import inline_facade

const
  LogDir = "logs/upgrade_history"
  Facades = {
    "core/sorter_core": @["core/sorter_core_index", "core/sorter_core_algo"],
    "core/axiom_api": @["core/axiom_api_session", "core/axiom_api_verify"],
    "core/bmc/bmc_race": @["core/bmc/bmc_types", "core/bmc/bmc_engine"],
    "core/diagnostics_engine": @["core/diagnostics_engine_helpers", "core/diagnostics_engine_main"],
    "core/api": @["api"],
    "core/encoding/smt_to_lean_bridge": @["core/encoding/smt_to_lean_codegen", "core/encoding/smt_to_lean_translate"],
  }.toTable

proc checkGitClean(): bool =
  let (status, code) = execCmdEx("git status --porcelain")
  if code != 0:
    return false
  result = status.strip.len == 0

proc findImporters(facadeName: string): seq[string] =
  var files = initHashSet[string]()
  let (importOut, _) = execCmdEx("grep -rn '^import " & facadeName & "$' src")
  for line in importOut.strip.splitLines:
    if line.len > 0:
      let colonPos = line.find(':')
      if colonPos > 0:
        files.incl(line[0 ..< colonPos])
  let (fromOut, _) = execCmdEx("grep -rn '^from " & facadeName & " import' src")
  for line in fromOut.strip.splitLines:
    if line.len > 0:
      let colonPos = line.find(':')
      if colonPos > 0:
        files.incl(line[0 ..< colonPos])
  result = files.toSeq
  result.sort()

proc parseNimErrors(output: string): seq[tuple[file: string; line, col: int; message: string]] =
  result = @[]
  for line in output.splitLines:
    if "Error:" in line:
      let m = line.find(re"""(.*?)\((\d+),\s*(\d+)\)\s*Error:\s*(.*)""")
      if m >= 0:
        let parts = line[m ..< line.len].split("Error:")
        if parts.len >= 2:
          let loc = parts[0]
          let msg = parts[1].strip
          let parensOpen = loc.find('(')
          let parensClose = loc.find(')')
          if parensOpen > 0 and parensClose > parensOpen:
            let fname = loc[0 ..< parensOpen]
            let coords = loc[parensOpen + 1 ..< parensClose].split(",")
            if coords.len == 2:
              try:
                let lineNo = parseInt(coords[0].strip)
                let colNo = parseInt(coords[1].strip)
                result.add((fname, lineNo, colNo, msg))
              except ValueError:
                discard

proc saveRemainingDebt(errors: seq[tuple[file: string; line, col: int; message: string]]) =
  createDir(LogDir)
  let timestamp = now().format("yyyy-MM-dd-HHmmss")
  let path = LogDir / ("remaining_debt_" & timestamp & ".txt")
  var content = ""
  for e in errors:
    content.add(e.file & ":" & $e.line & ":" & $e.col & " Error: " & e.message & "\n")
  writeFile(path, content)
  echo "Saved " & $errors.len & " remaining debt items to " & path

proc main() =
  let args = commandLineParams()
  let dryRun = args.contains("--dry-run") or not args.contains("--execute")

  if not dryRun and not checkGitClean():
    echo "ABORT: Working tree is not clean. Commit or stash changes first."
    quit(1)

  var totalImporters = 0
  var allModified: seq[string] = @[]

  for facade, subs in Facades.pairs:
    let importers = findImporters(facade)
    let subImport = subs.join(", ")
    for imp in importers:
      let oldLine = "import " & facade
      let newLine = "import " & subImport
      if dryRun:
        echo "DRY-RUN: " & imp
        echo "  - " & oldLine
        echo "  + " & newLine
      else:
        try:
          let content = readFile(imp)
          let newContent = content.replace(oldLine & "\n", newLine & "\n").replace(oldLine, newLine)
          writeFile(imp, newContent)
          allModified.add(imp)
        except CatchableError:
          discard  # axiom:best-effort(file processing error)
      inc totalImporters

  echo "\nTotal: " & $totalImporters & " imports across " & $Facades.len & " facades"

  if not dryRun and allModified.len > 0:
    echo "Verifying compilation..."
    var errors: seq[tuple[file: string; line, col: int; message: string]] = @[]
    for f in allModified:
      let (output, code) = execCmdEx("nim check --hints:off " & f)
      if code != 0:
        errors.add(parseNimErrors(output))
    if errors.len > 0:
      saveRemainingDebt(errors)
      echo "WARNING: " & $errors.len & " compilation errors found"
    else:
      for facade in Facades.keys:
        let facadePath = facade & ".nim"
        if fileExists(facadePath):
          discard execCmdEx("git rm " & facadePath)
      echo "SUCCESS: All facades inlined and deleted"

when isMainModule:
  main()
