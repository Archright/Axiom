import std/[strutils, sequtils]

proc extractCleanError*(rawError: string): string =
  let lines = rawError.splitLines()
  var cleanLines: seq[string] = @[]
  var captureBlock = false

  for line in lines:
    let trimmed = line.strip()

    if "tactic" in trimmed.toLowerAscii() or
       "unsolved" in trimmed.toLowerAscii() or
       "error:" in trimmed.toLowerAscii():
      captureBlock = true
      cleanLines.add(trimmed)
      continue

    if "⊢" in trimmed or captureBlock:
      captureBlock = true
      if not trimmed.startsWith("at ") and not trimmed.startsWith("File:"):
        cleanLines.add(line)

  if cleanLines.len == 0:
    return rawError.strip()

  return cleanLines.join("\n").strip()

proc replaceFirst*(s, sub, by: string): string =
  let idx = s.find(sub)
  if idx < 0: return s
  return s[0 .. idx-1] & by & s[idx + sub.len .. ^1]

proc canonicalizeTactic*(rawTactic: string): string =
  var t = rawTactic.strip()
  if t.startsWith("```lean"): t = t[7..^1].strip()
  elif t.startsWith("```"): t = t[3..^1].strip()
  if t.endsWith("```"): t = t[0..^4].strip()
  while t.startsWith("by "):
    t = t[3..^1].strip()
  if t.len == 0:
    return "by simp"
  return "by " & t

proc injectTactic*(sourceCode: string, newTactic: string): string =
  let startMarker = "/- AXIOM_PROOF_BEGIN -/"
  let endMarker = "/- AXIOM_PROOF_END -/"

  let startIdx = sourceCode.find(startMarker)
  let endIdx = sourceCode.find(endMarker)

  if startIdx == -1 or endIdx == -1:
    raise newException(ValueError, "Proof anchor markers not found in Lean file.")

  let prefix = sourceCode[0 ..< startIdx + startMarker.len]
  let suffix = sourceCode[endIdx .. ^1]

  let indentedTactic = newTactic.strip().splitLines()
    .mapIt("  " & it.strip())
    .join("\n")

  return prefix & "\n" & indentedTactic & "\n  " & suffix
