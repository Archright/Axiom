import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

## Exemption Registry Cleaner
##
## After porting a Python/Shell file to Nim, run this tool to remove the
## corresponding entry from src/policy/python_shell_exemptions.nim.
##
## Usage:
##   nim c -r tools/update_exemption_registry.nim

import std/[os, strutils]

const RegistryPath = "src/policy/python_shell_exemptions.nim"

proc extractPath(entry: string): string =
  ## Extract the path value from an ExemptionEntry block.
  let marker = "path: FilePath(\""
  let startIdx = entry.find(marker)
  if startIdx < 0:
    return ""
  let pathStart = startIdx + marker.len
  let pathEnd = entry.find("\")", pathStart)
  if pathEnd < 0:
    return ""
  result = entry[pathStart ..< pathEnd]

proc main() =
  if not fileExists(RegistryPath):
    stderr.writeLine("Registry not found: " & RegistryPath)
    quit(1)

  let content = readFile(RegistryPath)
  var output = ""
  var i = 0
  var removed = 0
  var kept = 0

  while i < content.len:
    let entryStart = content.find("ExemptionEntry(", i)
    if entryStart < 0:
      output.add(content[i .. ^1])
      break

    # Add everything before this entry.
    output.add(content[i ..< entryStart])

    # Find the matching closing ")," considering nested parens.
    var depth = 1
    var j = entryStart + "ExemptionEntry(".len
    while j < content.len and depth > 0:
      if content[j] == '(':
        inc depth
      elif content[j] == ')':
        dec depth
      inc j

    # Include the trailing comma if present.
    if j < content.len and content[j] == ',':
      inc j

    let entry = content[entryStart ..< j]
    let relPath = extractPath(entry)
    let fullPath = getCurrentDir() / relPath

    if relPath.len > 0 and not fileExists(fullPath):
      inc removed
      stderr.writeLine("[update-exemption-registry] Removing: " & relPath)
    else:
      inc kept
      output.add(entry)

    i = j

  writeFile(RegistryPath, output)
  stderr.writeLine("[update-exemption-registry] Kept: " & $kept &
                   ", Removed: " & $removed)

when isMainModule:
  main()

{.pop.}
