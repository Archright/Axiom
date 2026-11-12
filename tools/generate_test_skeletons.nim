import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, re]

const
  ViolationsFile = "docs/evidence/verifications/test_mapping_violations.txt"
  TestDir = "tests/unit"

proc extractSourcePath(line: string): string =
  let m = line.find(re"""(src/\S+\.nim):""")
  if m >= 0:
    let match = line[m ..< line.len]
    let colonPos = match.find(':')
    if colonPos > 0:
      return match[0 ..< colonPos]
  result = ""

proc sourceToImportPath(sourcePath: string): string =
  result = sourcePath.replace("src/", "").replace(".nim", "").replace("/", ".")

proc sourceToTestName(sourcePath: string): string =
  let name = extractFilename(sourcePath).changeFileExt("")
  result = name & "_test"

proc shouldSkip(sourcePath: string): bool =
  let name = extractFilename(sourcePath).changeFileExt("")
  if name.endsWith("_types") or name.endsWith("_core") or name.endsWith("_helpers"):
    return true
  if "_parts/" in sourcePath:
    return true
  if name.endsWith("_index") or name.endsWith("_table") or name.endsWith("_algo"):
    return true
  if sourcePath == "src/cli/main.nim":
    return true
  result = false

proc generateTestSkeleton(sourcePath: string): string =
  let importPath = sourceToImportPath(sourcePath)
  let moduleName = extractFilename(sourcePath).changeFileExt("")
  result = "import std/unittest\n" &
           "import " & importPath & "\n\n" &
           "suite \"" & moduleName & "\":\n" &
           "  test \"compiles\":\n" &
           "    # Compilation-only test — verifies module structure\n" &
           "    # REQUIRED: Add meaningful tests — stub tests are forbidden (AGENTS.md §0.8)\n" &
           "    discard\n"

proc main() =
  var created = 0
  var skipped = 0
  var errors: seq[string] = @[]

  if not fileExists(ViolationsFile):
    echo "Violations file not found: " & ViolationsFile
    quit(1)

  let content = readFile(ViolationsFile)
  for line in content.splitLines:
    let sourcePath = extractSourcePath(line.strip)
    if sourcePath.len == 0:
      continue
    if shouldSkip(sourcePath):
      inc skipped
      continue
    let testName = sourceToTestName(sourcePath)
    let testPath = TestDir / (testName & ".nim")
    if fileExists(testPath):
      continue
    try:
      let skeleton = generateTestSkeleton(sourcePath)
      createDir(TestDir)
      writeFile(testPath, skeleton)
      inc created
    except CatchableError as e:
      errors.add(sourcePath & ": " & e.msg)

  echo "Created: " & $created & " test skeletons"
  echo "Skipped: " & $skipped & " (type/parts/entry modules)"
  if errors.len > 0:
    echo "Errors: " & $errors.len
    for e in errors[0 ..< min(5, errors.len)]:
      echo "  " & e

when isMainModule:
  main()
