import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

import std/[os, strutils, algorithm, sequtils]
import core/axiom_pragmas

func extractAndNormalizeImports*(lines: seq[string]): tuple[imports: seq[string], codeLines: seq[string], changed: bool] =
  var imports: seq[string] = @[]
  var codeLines: seq[string] = @[]
  var originalImports: seq[string] = @[]

  for line in lines:
    let stripped = line.strip()
    if stripped.startsWith("import ") or stripped.startsWith("from "):
      originalImports.add(stripped)
      imports.add(stripped)
    else:
      codeLines.add(line)

  let sortedImports = imports.deduplicate().sorted()
  let changed = sortedImports != originalImports

  (imports: sortedImports, codeLines: codeLines, changed: changed)

proc normalizeImportsInFile*(filePath: string): bool {.raises: [Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not fileExists(filePath):
    return false

  let content = readFile(filePath)
  let lines = content.splitLines()
  let (normalizedImports, codeLines, changed) = extractAndNormalizeImports(lines)

  if not changed:
    return false

  var output = ""
  for imp in normalizedImports:
    output.add(imp & "\n")
  if normalizedImports.len > 0 and codeLines.len > 0:
    output.add("\n")
  for i, line in codeLines:
    if i > 0:
      output.add("\n")
    output.add(line)

  let tmpPath = filePath & ".tmp"
  writeFile(tmpPath, output)
  moveFile(tmpPath, filePath)
  true

proc normalizeImportsInDirectory*(dir: string, extensions: seq[string] = @[".nim"]): int {.raises: [Exception].} =
  result = 0
  for path in walkDirRec(dir):
    let ext = path.splitFile().ext
    if ext in extensions:
      if normalizeImportsInFile(path):
        inc result

proc normalizeImportsForFiles*(files: seq[string]): int {.raises: [Exception].} =
  ## Normalize imports only for the specified files (no directory scan).
  ## Returns count of modified files.
  result = 0
  for f in files:
    if f.endsWith(".nim") and fileExists(f):
      if normalizeImportsInFile(f):
        inc result

{.pop.}
