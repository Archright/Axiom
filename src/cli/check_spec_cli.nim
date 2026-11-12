import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}

import std/[algorithm, os, sets, strutils]
from std/re import findAll, re

proc extractSpecTags(mdPath: string): seq[string] =
  let content = readFile(mdPath)
  let pattern = re"<!--\s*@spec\s+GATE-\w+\s*-->"
  for fullMatch in findAll(content, pattern):
    let tagStart = strutils.find(fullMatch, "@spec") + 6
    let tagEnd = strutils.find(fullMatch, "-->")
    let tag = fullMatch[tagStart ..< tagEnd].strip
    if tag.len > 0:
      result.add(tag)

proc extractGatePragmas(srcDir: string): seq[string] =
  let pattern = re"""\{\.gate:\s*"GATE-\w+"\.\}"""
  for path in walkDirRec(srcDir):
    if path.endsWith(".nim"):
      let content = try: readFile(path) except CatchableError: ""
      if content.len == 0:
        continue
      for fullMatch in findAll(content, pattern):
        let tagStart = strutils.find(fullMatch, '"') + 1
        let tagEnd = strutils.rfind(fullMatch, '"')
        let tag = fullMatch[tagStart .. tagEnd]
        if tag.len > 0:
          result.add(tag)
  result.sort()

proc runCheckSpec*(args: seq[string]) =
  let rootDir = getCurrentDir()
  let agentsMd = rootDir / "AGENTS.md"
  let srcDir = rootDir / "src"

  if not fileExists(agentsMd):
    stderr.writeLine("error: AGENTS.md not found")
    quit(1)
  if not dirExists(srcDir):
    stderr.writeLine("error: src/ directory not found")
    quit(1)

  var fix = false
  for a in args:
    if a == "--fix":
      fix = true

  let specTags = extractSpecTags(agentsMd)
  let codeTags = extractGatePragmas(srcDir)

  let specSet = specTags.toHashSet
  let codeSet = codeTags.toHashSet

  let specOnly = specSet - codeSet
  let codeOnly = codeSet - specSet

  if specOnly.len == 0 and codeOnly.len == 0:
    echo "check-spec: OK"
    quit(0)

  if specOnly.len > 0:
    echo "=== In AGENTS.md only (not in code) ==="
    for tag in specOnly:
      echo "  " & tag
    echo ""

  if codeOnly.len > 0:
    echo "=== In code only (not in AGENTS.md) ==="
    for tag in codeOnly:
      echo "  " & tag
    echo ""

  if fix and codeOnly.len > 0:
    let backupPath = agentsMd & ".bak"
    try:
      copyFile(agentsMd, backupPath)
    except CatchableError as e:
      stderr.writeLine("error: backup failed: " & e.msg)
      quit(1)
    echo "Backup: " & backupPath
    var mdContent = readFile(agentsMd)
    if mdContent.len > 0 and mdContent[^1] != '\n':
      mdContent.add("\n")
    mdContent.add("\n")
    for tag in codeOnly:
      mdContent.add("<!-- @spec " & tag & " -->\n")
    writeFile(agentsMd, mdContent)
    echo "Fixed: " & $codeOnly.len & " tag(s) added"

  quit(if specOnly.len + codeOnly.len > 0: 1 else: 0)
{.pop.}
