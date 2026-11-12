import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}
## Tier Classifier — Automatically classifies all procs/funcs into Tier 1 (SSOT),
## Tier 2 (Pure), or Tier 3 (IO/Glue). Generates JSON report to logs/audit/.

import std/[json, os, strutils, sequtils]

type
  Tier* = enum
    t1SSOT
    t2Pure
    t3IO

  ProcClassification* = object
    name*: string
    modulePath*: string
    tier*: Tier
    reason*: string
    manualOverride*: bool

func extractProcName(line: string): string =
  let trimmed = line.strip()
  let startPos = if trimmed.startsWith("func "): 5 elif trimmed.startsWith("proc "): 5 else: return ""
  var endPos = startPos
  var parenDepth = 0
  var captured = false
  for ch in trimmed[startPos .. ^1]:
    if ch == '(':
      parenDepth += 1
      captured = true
    elif ch == ')':
      parenDepth -= 1
      if captured and parenDepth == 0:
        endPos += 1
        break
    elif ch == '{' and parenDepth == 0:
      break
    elif ch == '*' and parenDepth == 0:
      break
    if not captured:
      endPos += 1
  result = trimmed[startPos .. endPos - 1].strip()
  result = result.split('[')[0].strip()
  result = result.split('(')[0].strip()

func classifyProc(line: string; modulePath: string): tuple[tier: Tier, reason: string] =
  let stripped = line.strip()

  if "{.tier1.}" in stripped:
    return (t1SSOT, "Manual override: {.tier1.}")
  if "{.tier2.}" in stripped:
    return (t2Pure, "Manual override: {.tier2.}")
  if "{.tier3.}" in stripped:
    return (t3IO, "Manual override: {.tier3.}")

  if stripped.startsWith("func "):
    return (t2Pure, "func keyword (pure function)")

  if stripped.startsWith("proc ") and "noSideEffect" in stripped:
    return (t2Pure, "noSideEffect pragma")

  let ssotModules = ["metrics.nim", "certificate_types.nim", "proof_hydration.nim", "verification_tier.nim"]
  for m in ssotModules:
    if m in modulePath:
      if stripped.startsWith("func ") or stripped.startsWith("proc "):
        return (t1SSOT, "SSOT module: " & m)

  if stripped.startsWith("proc "):
    return (t3IO, "Default: I/O or glue proc")

  (t3IO, "Not a proc/func")

proc classifyProject(projectRoot: string): seq[ProcClassification] =
  var results: seq[ProcClassification] = @[]
  let srcDir = projectRoot / "src"

  var nimFiles: seq[string] = @[]
  try:
    for filePath in walkDirRec(srcDir, yieldFilter = {pcFile}):
      if filePath.endsWith(".nim"):
        nimFiles.add(filePath)
  except OSError:
    discard

  for filePath in nimFiles:
    var content: string
    try:
      content = readFile(filePath)
    except IOError:
      continue
    let lines = content.splitLines()
    for line in lines:
      let stripped = line.strip()
      if stripped.startsWith("func ") or stripped.startsWith("proc "):
        let (tier, reason) = classifyProc(stripped, filePath)
        let name = extractProcName(stripped)
        results.add(ProcClassification(
          name: name,
          modulePath: filePath,
          tier: tier,
          reason: reason,
          manualOverride: "{.tier" in stripped
        ))

  results

proc reportToJson(classifications: seq[ProcClassification]): JsonNode =
  var t1, t2, t3: seq[JsonNode] = @[]
  for c in classifications:
    let node = %*{"name": c.name, "module": c.modulePath, "reason": c.reason}
    case c.tier
    of t1SSOT: t1.add(node)
    of t2Pure: t2.add(node)
    of t3IO: t3.add(node)

  %*{
    "summary": %*{
      "total": classifications.len,
      "tier1": t1.len,
      "tier2": t2.len,
      "tier3": t3.len
    },
    "classifications": %*{
      "tier1_ssot": t1,
      "tier2_pure": t2,
      "tier3_io": t3
    }
  }

when isMainModule:
  let projectRoot = if paramCount() > 0: paramStr(1) else: getCurrentDir()
  let classifications = classifyProject(projectRoot)
  let report = reportToJson(classifications)

  let outDir = projectRoot / "logs" / "audit"
  if not dirExists(outDir):
    createDir(outDir)
  let outPath = outDir / "tier_classification.json"
  writeFile(outPath, pretty(report))

  let t1Count = classifications.countIt(it.tier == t1SSOT)
  let t2Count = classifications.countIt(it.tier == t2Pure)
  let t3Count = classifications.countIt(it.tier == t3IO)

  echo "=== Tier Classification Report ==="
  echo "Total procs: " & $classifications.len
  echo "Tier 1 (SSOT): " & $t1Count
  echo "Tier 2 (Pure): " & $t2Count
  echo "Tier 3 (IO): " & $t3Count
  echo "Report: " & outPath
