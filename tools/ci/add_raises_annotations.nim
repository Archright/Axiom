import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, strutils, sequtils, re, tables]

const
  Base = "."
  TargetProcs = {
    "gate_registry.nim": {
      "semanticViolationToJson": "skip",
      "semanticIntegrityGateToJson": "skip",
      "translationValidationResultToJson": "skip",
      "semanticResultsContext": "skip",
      "registerGate": "io",
      "findGate": "io",
      "unregisterGate": "io",
      "initDefaultGates": "io",
      "runSemanticIntegrityGate": "io",
    }.toTable,
    "gate_rules_architecture.nim": {
      "applyDirectConcreteDependencyCheck": "io",
      "applyArchitecturePrinciplesGate": "io",
    }.toTable,
    "gate_rules_module_classifier.nim": {
      "isConcreteModule": "skip",
      "isAbstractModule": "skip",
      "isLikelyConcreteName": "skip",
      "isLikelyAbstractionName": "skip",
    }.toTable,
    "orchestrator.nim": {
      "groupByPriority": "pure",
    }.toTable,
    "git.nim": {
      "gitDiffCachedNames": "skip",
      "gitDiffCachedPatch": "skip",
      "gitUnstagedNames": "skip",
      "hasUnstagedChanges": "skip",
      "gitStage": "skip",
    }.toTable,
    "logic_binding_gate.nim": {
      "hasLogicBinding": "skip",
      "containsBannedAtom": "skip",
      "runLogicBindingGate": "io",
    }.toTable,
    "gate_utils.nim": {
      "shouldRun": "skip",
    }.toTable,
    "context_size_guard.nim": {
      "checkAgmdSize": "skip",
      "main": "skip",
    }.toTable,
  }.toTable

  PostProcess = default(Table[string, Table[string, string]])

  Files = @[
    "src/gate/gate_registry.nim",
    "src/gate/gate_rules_architecture.nim",
    "src/gate/gate_rules_module_classifier.nim",
    "src/gate/git.nim",
    "src/gate/logic_binding_gate.nim",
    "src/gate/gate_utils.nim",
    "src/gate/runners/context_size_guard.nim",
  ]

proc findProcLines(lines: seq[string]; procName: string): tuple[start, ending: int] =
  result = (-1, -1)
  for i, line in lines:
    let stripped = line.strip
    if not (stripped.startsWith("proc ") or stripped.startsWith("func ")):
      continue
    if procName notin stripped:
      continue
    var parenDepth = 0
    var bracketDepth = 0
    var started = false
    var j = i
    while j < lines.len:
      for ch in lines[j]:
        if ch == '(':
          inc parenDepth
          started = true
        elif ch == ')':
          dec parenDepth
        elif ch == '[':
          inc bracketDepth
        elif ch == ']':
          dec bracketDepth
      if started and parenDepth <= 0 and bracketDepth <= 0:
        return (i, j)
      inc j
    return (i, i)

proc hasRaisesInRange(lines: seq[string]; start, ending: int): bool =
  for i in start .. min(ending, lines.len - 1):
    if "raises" in lines[i]:
      return true
  result = false

proc addRaisesToProc(lines: var seq[string]; procName: string; ioType: string): tuple[ok: bool; desc: string] =
  let (start, ending) = findProcLines(lines, procName)
  if start < 0:
    return (false, "NOT FOUND")
  if hasRaisesInRange(lines, start, ending):
    return (false, "already has raises")
  let annotationRaises = if ioType == "io": "[CatchableError]" else: "[]"
  var endLine = lines[ending]
  # Case 1: existing pragma block
  let pragmaMatch = endLine.find(re"""\{\.([^\}]*?)\.\}""")
  if pragmaMatch >= 0:
    let pragmaContent = endLine[pragmaMatch ..< endLine.len]
    let closeIdx = pragmaContent.find(".}")
    let content = if closeIdx > 0: pragmaContent[2 ..< closeIdx] else: ""
    let newPragma = if content.strip.len > 0:
      "{." & content.strip & ", raises: " & annotationRaises & ".}"
    else:
      "{.raises: " & annotationRaises & ".}"
    let newLine = endLine[0 ..< pragmaMatch] & newPragma & endLine[pragmaMatch + closeIdx + 2 ..< endLine.len]
    lines[ending] = newLine
    return (true, "merged into existing pragma")
  # Case 2: line ends with `) =`
  let eqAfterParen = endLine.find(re"""(\))(\s*=\s*$)""")
  if eqAfterParen >= 0:
    let pos = eqAfterParen + 1
    let annotation = " {.raises: " & annotationRaises & ".}"
    let newLine = endLine[0 ..< pos] & annotation & endLine[pos ..< endLine.len]
    lines[ending] = newLine
    return (true, "inserted before =")
  # Case 3: line ends with `)`
  if endLine.strip.endsWith(")"):
    let annotation = " {.raises: " & annotationRaises & ".}"
    lines[ending] = endLine.strip & annotation
    return (true, "appended after )")
  # Case 4: `=` without `)`
  let eqPos = endLine.find('=')
  if eqPos >= 0 and "{." notin endLine[0 ..< eqPos]:
    let annotation = " {.raises: " & annotationRaises & ".} "
    let newLine = endLine[0 ..< eqPos].strip & annotation & endLine[eqPos ..< endLine.len]
    lines[ending] = newLine
    return (true, "inserted before =")
  return (false, "could not find insertion point")

proc main() =
  var totalChanges = 0
  var modifiedFiles: seq[string] = @[]
  var totalSkipped = 0

  for relPath in Files:
    let fpath = Base / relPath
    if not fileExists(fpath):
      echo "⚠️  " & relPath & " not found, skipping"
      continue
    let content = readFile(fpath)
    let fname = extractFilename(relPath)
    let targets = TargetProcs.getOrDefault(fname)
    if targets.len == 0:
      continue
    let pushMatch = content.find(re"""\{\.\s*push\s+raises\s*:\s*\[([^\]]*)\]\s*\.\}""")
    var filePush = "none"
    if pushMatch >= 0:
      let m = content[pushMatch ..< content.len]
      let bracketOpen = m.find('[')
      let bracketClose = m.find(']')
      if bracketOpen > 0 and bracketClose > bracketOpen:
        filePush = m[bracketOpen + 1 ..< bracketClose].strip
    var lines = content.splitLines
    var changes: seq[string] = @[]
    var fileChanged = false
    for procName, ioType in targets.pairs:
      if ioType == "skip":
        changes.add("  ⏭️  " & procName & " — covered by push raises: [" & filePush & "]")
        inc totalSkipped
        continue
      let (ok, desc) = addRaisesToProc(lines, procName, ioType)
      if ok:
        let annotation = if ioType == "io": "{.raises: [CatchableError].}" else: "{.raises: [].}"
        changes.add("  ✅ " & procName & " — " & desc & ": " & annotation)
        inc totalChanges
        fileChanged = true
      else:
        changes.add("  ⚠️  " & procName & " — " & desc)
    var newContent = lines.join("\n")
    let postReplacements = PostProcess.getOrDefault(fname)
    for (oldText, newText) in postReplacements.pairs:
      if oldText in newContent:
        newContent = newContent.replace(oldText, newText)
        changes.add("  ✅ (post-process) fixed lambda annotation")
        inc totalChanges
        fileChanged = true
    if fileChanged and newContent != content:
      writeFile(fpath, newContent)
      modifiedFiles.add(relPath)
    echo "\n📄 " & relPath & " (push raises: [" & filePush & "]):"
    for c in changes:
      echo c

  echo "\n" & repeat('=', 60)
  echo "Total: " & $totalChanges & " annotations added, " & $totalSkipped & " skipped (covered by push)"
  echo "Modified files: " & $modifiedFiles.len

  if modifiedFiles.len > 0:
    echo "\n🔍 Running nim check on modified files..."
    var allOk = true
    for relPath in modifiedFiles:
      let fpath = Base / relPath
      let (_, code) = execCmdEx("nim check --hints:off " & fpath)
      if code == 0:
        echo "  ✅ " & relPath & " compiles"
      else:
        echo "  ❌ " & relPath & " — COMPILATION ERROR"
        allOk = false
    if not allOk:
      echo "\n⚠️  Some files have compilation errors. Run nim check manually for details."
    else:
      echo "\n✅ All modified files compile successfully."
  else:
    echo "\n✅ No files modified — all procs already annotated."

when isMainModule:
  main()
