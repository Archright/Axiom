import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, strutils, sequtils, times]

const
  # NOTE: tests/auto_generated/ directory was removed from the project.
  # This tool's functionality depends on that directory.
  AutoGenDir = "tests/auto_generated"  # DEPRECATED — directory no longer exists
  FeaturesDir = "tests/features"
  LogFile = "tools/logs/stub_conversion.log"

type
  RunnerClass = enum
    rcStub, rcReal, rcPartial, rcEmpty, rcError

proc classifyRunner(filepath: string): RunnerClass =
  try:
    let content = readFile(filepath)
    let discardCount = content.count("discard")
    let hasCheck = "check" in content or "doAssert" in content or "assert" in content
    let hasSuite = "suite " in content
    let hasTest = "test " in content or "test\"" in content
    if not hasCheck and discardCount > 0:
      return rcStub
    if hasCheck and hasSuite and hasTest:
      return rcReal
    if hasCheck:
      return rcPartial
    return rcEmpty
  except CatchableError:
    return rcError

proc findFeatureScenarios(featureName: string): seq[string] =
  let featureFile = FeaturesDir / (featureName & ".feature")
  if not fileExists(featureFile):
    return @[]
  try:
    let content = readFile(featureFile)
    for line in content.splitLines:
      let stripped = line.strip
      if stripped.startsWith("Scenario:"):
        result.add(stripped[9..^1].strip)
  except CatchableError:
    discard  # axiom:best-effort(feature file read failure — returns empty scenario list)

proc convertStubToAssertion(filepath: string; dryRun: bool): tuple[ok: bool; msg: string] =
  try:
    let original = readFile(filepath)
    var lines = original.splitLines
    var newLines: seq[string] = @[]
    var changed = false
    for line in lines:
      let stripped = line.strip
      if stripped == "discard":
        # axiom:theater-fix — replaced broken `fail()` call with doAssert that compiles and gives actionable error
        var indentEnd = 0
        for i in 0 ..< line.len:
          if line[i] in {' ', '\t'}:
            inc indentEnd
          else:
            break
        let indentStr = if indentEnd > 0: line[0 ..< indentEnd] else: ""
        newLines.add(indentStr & "doAssert false, \"TODO: Replace discard with real assertion for this test case\"")
        changed = true
      else:
        newLines.add(line)
    let newContent = newLines.join("\n")
    if newContent == original:
      return (false, "no changes")
    if dryRun:
      return (true, "would convert")
    writeFile(filepath, newContent)
    let (compileOut, compileCode) = execCmdEx("nim c --hints:off " & filepath)
    if compileCode != 0 or "Error:" in compileOut:
      writeFile(filepath, original)
      let errorMsg = compileOut.split("Error:")[^1].strip[0..99]
      return (false, "compile error — rolled back: " & errorMsg)
    return (true, "converted + verified")
  except CatchableError as e:
    return (false, "read error: " & e.msg)

proc main() =
  let args = commandLineParams()
  let dryRun = args.contains("--dry-run") or not args.contains("--execute")
  let execute = args.contains("--execute")
  let reportOnly = args.contains("--report")

  if not dirExists(AutoGenDir):
    echo "Directory not found: " & AutoGenDir
    quit(1)

  var runners: seq[string] = @[]
  for path in walkDirRec(AutoGenDir):
    if path.endsWith(".nim"):
      runners.add(path)

  var stubs: seq[string] = @[]
  var reals: seq[string] = @[]
  var partials: seq[string] = @[]
  var empties: seq[string] = @[]

  for r in runners:
    case classifyRunner(r)
    of rcStub: stubs.add(r)
    of rcReal: reals.add(r)
    of rcPartial: partials.add(r)
    else: empties.add(r)

  echo "=== Auto-Generated Runner Report ==="
  echo "Total: " & $runners.len
  let realPct = if runners.len > 0: reals.len * 100 div runners.len else: 0
  let stubPct = if runners.len > 0: stubs.len * 100 div runners.len else: 0
  echo "  REAL (has assertions):  " & $reals.len & " (" & $realPct & "%)"
  echo "  STUB (discard only):    " & $stubs.len & " (" & $stubPct & "%)"
  echo "  PARTIAL:                " & $partials.len
  echo "  EMPTY/ERROR:            " & $empties.len
  echo ""

  if reportOnly:
    if stubs.len > 0:
      echo "Stub files:"
      for s in stubs:
        echo "  " & s
    return

  echo "Mode: " & (if execute: "EXECUTE" else: "DRY-RUN")
  var converted = 0
  var failed = 0

  for stub in stubs:
    let (ok, msg) = convertStubToAssertion(stub, dryRun)
    let status = if ok: "✅" else: "❌"
    echo "  " & status & " " & stub & ": " & msg
    if ok:
      inc converted
    else:
      inc failed

  echo "\n" & (if dryRun: "Would convert" else: "Converted") & ": " & $converted & ", Failed: " & $failed

  createDir(LogFile.parentDir)
  let logEntry = (if dryRun: "DRY-RUN" else: "EXECUTE") & ": converted=" & $converted & ", failed=" & $failed & "\n"
  try:
    var f = open(LogFile, fmAppend)
    f.write(logEntry)
    close(f)
  except CatchableError:
    discard  # axiom:best-effort(log write failure — non-fatal)

when isMainModule:
  main()
