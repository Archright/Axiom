import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils]

proc stripComments(content: string): string =
  result = content
  var startIdx = result.find("##[")
  while startIdx >= 0:
    let endIdx = result.find("]##", startIdx + 3)
    if endIdx >= 0:
      result = result[0..<startIdx] & result[endIdx+3..^1]
    else:
      result = result[0..<startIdx]
    startIdx = result.find("##[")
  var lines = result.splitLines()
  for i in 0..<lines.len:
    let hashPos = lines[i].find('#')
    if hashPos >= 0:
      lines[i] = lines[i][0..<hashPos]
  result = lines.join("\n")

proc normalizeWhitespace(content: string): string =
  result = content
  while "\n\n" in result:
    result = result.replace("\n\n", "\n")
  result = result.strip()

proc normalizePragmas(content: string): string =
  result = content.replace("axiomTryImpl", "axiomImpl")
  result = result.replace("{.axiom, axiomImpl.}", "{.axiomImpl.}")

proc classifyPair(originalPath, shadowPath: string): string =
  try:
    let origContent = readFile(originalPath)
    let shadowContent = readFile(shadowPath)

    let origNorm = origContent.stripComments().normalizeWhitespace().normalizePragmas()
    let shadowNorm = shadowContent.stripComments().normalizeWhitespace().normalizePragmas()

    if origNorm == shadowNorm:
      return "mergeable"
    else:
      let origLines = origNorm.splitLines()
      let shadowLines = shadowNorm.splitLines()
      var diffCount = 0
      let maxLen = max(origLines.len, shadowLines.len)
      for i in 0..<maxLen:
        let o = if i < origLines.len: origLines[i] else: ""
        let s = if i < shadowLines.len: shadowLines[i] else: ""
        if o != s:
          inc diffCount
      if diffCount <= 5:
        return "mergeable"
      else:
        return "drift"
  except CatchableError:
    return "error"

proc main() =
  var mergeable: seq[string] = @[]
  var drift: seq[string] = @[]
  var errors: seq[string] = @[]

  for shadowPath in walkDirRec("src"):
    if not shadowPath.endsWith("_shadow.nim"): continue
    let originalPath = shadowPath.replace("_shadow.nim", ".nim")
    if not fileExists(originalPath): continue

    let classification = classifyPair(originalPath, shadowPath)
    case classification
    of "mergeable": mergeable.add(originalPath)
    of "drift": drift.add(originalPath)
    of "error": errors.add(originalPath)
    else: discard

  echo "=== AST-Diff Classification Report ==="
  echo "Mergeable (safe to auto-merge): " & $mergeable.len
  echo "True Drift (needs manual review): " & $drift.len
  echo "Parse Errors: " & $errors.len
  echo ""

  if mergeable.len > 0:
    echo "--- Mergeable Files ---"
    for f in mergeable:
      echo "  " & f

  if drift.len > 0:
    echo "--- True Drift Files ---"
    for f in drift:
      echo "  " & f

  if errors.len > 0:
    echo "--- Parse Error Files ---"
    for f in errors:
      echo "  " & f

main()
