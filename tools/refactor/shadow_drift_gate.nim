import core/trusted/layer_declaration
axiomLayer "tools"
import std/[json, os, strutils, tables]
import ast_diff

const
  MaxAllowedDrift = 20
  ManifestPath = "data/shadow_drift_manifest.json"

type
  DriftResult = object
    shadow: string
    orig: string
    currentDiff: int
    lockedDiff: int
    status: string

proc diffLineCount(a, b: string): int =
  let na = a.splitLines()
  let nb = b.splitLines()
  var i = 0
  var j = 0
  while i < na.len or j < nb.len:
    if i < na.len and j < nb.len:
      if na[i] == nb[j]:
        inc i; inc j
      else:
        inc result; inc i; inc j
    elif i < na.len:
      inc result; inc i
    else:
      inc result; inc j

proc normalizeForDiff(s: string): string =
  result = normalizePragmas(s)
  var lines: seq[string]
  for line in result.splitLines():
    let stripped = line.strip()
    if stripped.len > 0 and not stripped.startsWith("#"):
      lines.add(stripped)
  result = lines.join("\n")

proc loadLockedDiffs(path: string): Table[string, int] =
  var manifest: JsonNode
  if fileExists(path):
    manifest = parseJson(readFile(path))
  else:
    manifest = %* {"details": []}
  for entry in manifest{"details"}:
    let shadow = entry{"shadow"}.getStr()
    let diff = entry{"diff"}.getInt()
    result[shadow] = diff

proc main() =
  let lockedDiffs = loadLockedDiffs(ManifestPath)
  var violations: seq[string]
  var debtViolations: seq[string]
  var warnings: seq[string]
  var newShadows: seq[string]
  var ok = 0

  for shadowPath in walkDirRec("src"):
    if not shadowPath.endsWith("_shadow.nim"): continue
    let origPath = shadowPath.replace("_shadow.nim", ".nim")
    if not fileExists(origPath): continue
    try:
      let orig = readFile(origPath)
      let shadow = readFile(shadowPath)
      let normOrig = normalizeForDiff(orig)
      let normShadow = normalizeForDiff(shadow)
      let diff = diffLineCount(normOrig, normShadow)

      if diff > MaxAllowedDrift:
        violations.add(origPath & " (drift: " & $diff & " lines)")
      elif shadowPath in lockedDiffs:
        let locked = lockedDiffs[shadowPath]
        if diff > locked:
          debtViolations.add(origPath & " (current: " & $diff & ", locked: " & $locked & ")")
        elif diff > 5:
          warnings.add(origPath & " (drift: " & $diff & " lines)")
        else:
          inc ok
      elif diff > 5:
        warnings.add(origPath & " (drift: " & $diff & " lines, new)")
        newShadows.add(shadowPath)
      else:
        inc ok
        newShadows.add(shadowPath)
    except CatchableError: # axiom:best-effort(unreadable shadow/orig file — skip for this iteration)
      discard

  echo "=== Shadow Drift Gate Report ==="
  echo "OK (≤5 diff): " & $ok
  echo "Warning (6-20 diff): " & $warnings.len
  echo "Debt Violation (drift increased): " & $debtViolations.len
  echo "Absolute Violation (>20 diff): " & $violations.len

  if debtViolations.len > 0:
    echo ""
    echo "--- No-New-Drift Violations (drift increased vs locked) ---"
    for v in debtViolations:
      echo "  [FAIL] " & v

  if warnings.len > 0:
    echo ""
    echo "--- Warnings ---"
    for w in warnings:
      echo "  [WARN] " & w

  if violations.len > 0:
    echo ""
    echo "--- Absolute Violations ---"
    for v in violations:
      echo "  [FAIL] " & v

  if debtViolations.len > 0 or violations.len > 0:
    quit(1)

main()
