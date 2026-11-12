## ============================================================
## Raises Coverage Tracker (Nim port)
## ============================================================
## {.raises: [].} 어노테이션 커버리지를 측정합니다.
## 목표: 17% → 50% → 80% → 100%
## ============================================================

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils]

{.push raises: [].}

const
  Layers = [
    "core", "verification", "gate", "cli", "mcp", "personas",
    "sieve", "ui", "api", "engine", "frontend", "semantic_proofs",
  ]

func isProcLine(line: string): bool =
  ## Matches lines the shell script counts: `^proc ` or `^  proc ` (0 or 2 leading spaces).
  line.startsWith("proc ") or line.startsWith("  proc ")

func countProcLines(lines: seq[string]): int {.raises: [].} =
  for line in lines:
    if isProcLine(line):
      inc result

func countRaisesEmpty(lines: seq[string]): int {.raises: [].} =
  for line in lines:
    if "{.raises: [].}" in line:
      inc result

func countRaisesSpecific(lines: seq[string]): int {.raises: [].} =
  for line in lines:
    if "{.raises: [" in line and "{.raises: [].}" notin line:
      inc result

proc collectNimFiles(root: string): seq[string] {.raises: [OSError].} =
  result = @[]
  for kind, path in walkDir(root, relative = false):
    if kind == pcFile and path.endsWith(".nim"):
      result.add(path)
    elif kind == pcDir:
      result.add(collectNimFiles(path))

proc readFileLines(path: string): seq[string] {.raises: [].} =
  try:
    readFile(path).splitLines()
  except IOError:
    @[]

proc printReport(totalProcs, raisesEmpty, raisesSpecific: int) {.raises: [].} =
  let totalRaises = raisesEmpty + raisesSpecific
  echo "=== Raises Coverage Report ==="
  echo "Total procs in src/:      " & $totalProcs
  echo "With {.raises: [].}:      " & $raisesEmpty
  echo "With {.raises: [Type]}:   " & $raisesSpecific
  echo "Total with raises:        " & $totalRaises
  if totalProcs > 0:
    let coverage = totalRaises * 100 div totalProcs
    echo "Coverage:                 " & $coverage & "%"
    echo ""
    if coverage < 50:
      echo "🔴 CRITICAL: Coverage below 50%"
    elif coverage < 80:
      echo "🟡 WARNING: Coverage below 80%"
    else:
      echo "✅ GOOD: Coverage above 80%"
  else:
    echo "Coverage:                 N/A"

proc printLayerBreakdown(repoRoot: string) {.raises: [IOError].} =
  echo ""
  echo "=== Per-Layer Breakdown ==="
  for layer in Layers:
    let layerDir = repoRoot / "src" / layer
    if not dirExists(layerDir):
      continue
    var layerTotal = 0
    var layerRaises = 0
    let nimFiles = try: collectNimFiles(layerDir)
                  except OSError: @[]
    for nimFile in nimFiles:
      let lines = readFileLines(nimFile)
      layerTotal += countProcLines(lines)
      # Any {.raises: pattern counts for layer-level raises
      for line in lines:
        if "{.raises:" in line:
          inc layerRaises
    if layerTotal > 0:
      let layerPct = layerRaises * 100 div layerTotal
      stdout.write "  "
      stdout.write layer.alignLeft(20)
      stdout.write align($layerPct, 3) & "%  ("
      stdout.write $layerRaises & "/" & $layerTotal & ")"
      stdout.write "\n"

proc main() {.raises: [IOError].} =
  # Resolve repo root: script is at tools/ci/track_raises_coverage.nim → repo root is 2 levels up
  let scriptDir = parentDir(currentSourcePath())
  let repoRoot = parentDir(parentDir(scriptDir))
  let srcDir = repoRoot / "src"

  if not dirExists(srcDir):
    echo "No src/ directory found at " & srcDir
    quit(0)

  var totalProcs = 0
  var raisesEmpty = 0
  var raisesSpecific = 0

  let srcFiles = try: collectNimFiles(srcDir)
                 except OSError: @[]
  for nimFile in srcFiles:
    let lines = readFileLines(nimFile)
    totalProcs += countProcLines(lines)
    raisesEmpty += countRaisesEmpty(lines)
    raisesSpecific += countRaisesSpecific(lines)

  if totalProcs == 0:
    echo "No procs found in src/"
    quit(0)

  printReport(totalProcs, raisesEmpty, raisesSpecific)
  printLayerBreakdown(repoRoot)

when isMainModule:
  main()
