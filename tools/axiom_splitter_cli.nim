import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, parseopt]

proc writeIfChanged(path: string, content: string) =
  if fileExists(path):
    let existing = readFile(path)
    if existing == content:
      return
  writeFile(path, content)

proc splitModule(inputPath: string) =
  let content = readFile(inputPath)
  let baseName = inputPath.changeFileExt("")

  var typesSection = "## Auto-generated types section\n"
  var implSection = "## Auto-generated impl section\n"
  var gateSection = "## Auto-generated gate section\n"

  for line in content.splitLines():
    if "{.types.}" in line:
      typesSection.add(line & "\n")
    elif "{.gate.}" in line:
      gateSection.add(line & "\n")
    else:
      implSection.add(line & "\n")

  writeIfChanged(baseName & "_types.nim", typesSection)
  writeIfChanged(baseName & "_gate.nim", gateSection)
  writeIfChanged(baseName & "_impl.nim", implSection)

  let facade = "include " & baseName & "_types\ninclude " & baseName & "_gate\ninclude " & baseName & "_impl\n"
  writeIfChanged(inputPath, facade)

proc main() =
  var p = initOptParser()
  while true:
    p.next()
    if p.kind == cmdEnd: break
    if p.kind == cmdArgument:
      splitModule(p.key)

when isMainModule:
  main()
