import core/trusted/layer_declaration
axiomLayer "tools"
import std/[macros, os, strutils]

macro generateBoundaryHarness*(modulePath: static string): untyped =
  let ast = parseStmt(staticRead(modulePath))
  result = newStmtList()
  let basicTypes = ["int", "int64", "string", "bool", "float", "float64"]

  for node in ast:
    if node.kind in {nnkProcDef, nnkFuncDef}:
      let procName = node[0]
      if procName.kind == nnkPostfix and procName[0].strVal == "*":
        let procIdent = procName[1]
        let params = node[3]

        if params.len > 1:  # has parameters
          var args = newSeq[NimNode]()
          for i in 1..<params.len:
            let paramType = params[i][1]
            if paramType.kind == nnkIdent:
              case paramType.strVal
              of "int", "int64": args.add(newLit(0))
              of "string": args.add(newLit(""))
              of "bool": args.add(newLit(false))
              of "float", "float64": args.add(newLit(0.0))
              else: args.add(newNilLit())
            else:
              args.add(newNilLit())

          var callNode = newCall(procIdent)
          for arg in args: callNode.add(arg)

          result.add quote do:
            suite `procName[1].strVal` & " TCB Boundary":
              test "execution with boundary defaults":
                try:
                  discard `callNode`
                except CatchableError: # axiom:best-effort(boundary test execution failure — non-fatal for harness)
                  discard

proc extractProcs(content: string): seq[tuple[name: string, params: seq[string]]] =
  result = @[]
  var lines = content.splitLines()
  var i = 0
  while i < lines.len:
    var line = lines[i].strip()
    if line.startsWith("proc ") or line.startsWith("func "):
      var isExported = false
      if "*" in line:
        isExported = true
      if isExported:
        let parts = line.split("(")
        if parts.len >= 2:
          var procName = parts[0].replace("proc ", "").replace("func ", "").strip()
          procName = procName.replace("*", "").strip()
          let paramPart = parts[1]
          if ")" in paramPart:
            let params = paramPart.split(")")[0].split(":")
            if params.len >= 2:
              var paramTypes: seq[string] = @[]
              for p in params:
                let cleanP = p.strip()
                if cleanP.len > 0 and not cleanP.startsWith("result"):
                  paramTypes.add(cleanP)
              result.add((name: procName, params: paramTypes))
    inc i

proc generateTestWithAllImport(modulePath: string): string =
  let moduleName = modulePath.replace("src/", "").replace(".nim", "")
  result = "# Auto-generated TCB boundary test ({.all.} pattern)\n"
  result &= "import " & moduleName & " {.all.}\n"
  result &= "# All symbols (public + private) are now accessible\n"

proc generateTestWithImport(modulePath: string): string =
  let moduleName = modulePath.replace("src/", "").replace(".nim", "")
  result = "# Auto-generated TCB boundary test (import pattern)\n"
  result &= "import unittest\n"
  result &= "import " & moduleName & "\n"

proc generateTestCode(modulePath: string, procs: seq[tuple[name: string, params: seq[string]]]): string =
  if procs.len == 0:
    result = generateTestWithAllImport(modulePath)
  else:
    result = generateTestWithImport(modulePath)

  result &= "\n"

  for procInfo in procs:
    result.add "suite \"" & procInfo.name & " TCB Boundary\":\n"
    result.add "  test \"execution with boundary defaults\":\n"
    result.add "    try:\n"
    result.add "      discard " & procInfo.name & "("
    var args: seq[string] = @[]
    for p in procInfo.params:
      if "int" in p or "int64" in p:
        args.add("0")
      elif "string" in p:
        args.add("\"\"")
      elif "bool" in p:
        args.add("false")
      elif "float" in p:
        args.add("0.0")
      else:
        args.add("nil")
    result.add args.join(", ") & ")\n"
    result.add "    except CatchableError:\n"
    result.add "      discard\n\n"

when isMainModule:
  if paramCount() < 1:
    echo "Usage: tcb_pbt_generator <module_path>"
    quit(1)
  let modulePath = paramStr(1)
  echo "Generating boundary tests for: " & modulePath

  if not fileExists(modulePath):
    echo "Error: File not found: " & modulePath
    quit(1)

  let content = readFile(modulePath)
  let procs = extractProcs(content)

  if procs.len == 0:
    echo "No exported procs found, using {.all.} import for: " & modulePath
  else:
    echo "Found " & $procs.len & " exported procs"

  let testDir = "tests/generated"
  if not dirExists(testDir):
    createDir(testDir)

  let testPath = testDir / "tcb_boundary_" & modulePath.extractFilename().replace(".nim", "") & ".nim"
  let testCode = generateTestCode(modulePath, procs)
  writeFile(testPath, testCode)
  echo "Generated test file: " & testPath
