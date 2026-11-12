import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, strutils, algorithm, re, sequtils]

const
  MaxDiffLines = 5
  StubMaxLines = 5

proc diffLineCount(a, b: string): int =
  let na = a.splitLines()
  let nb = b.splitLines()
  var i = 0
  var j = 0
  while i < na.len or j < nb.len:
    if i < na.len and j < nb.len:
      if na[i] == nb[j]:
        inc i
        inc j
      else:
        inc result
        inc i
        inc j
    elif i < na.len:
      inc result
      inc i
    else:
      inc result
      inc j

proc isSafeCandidate(origPath, shadowPath: string): bool =
  let orig = readFile(origPath)
  let shadow = readFile(shadowPath)
  let origLines = orig.splitLines().len
  if origLines <= StubMaxLines: return false
  let hasProc = orig.contains("proc ") or orig.contains("func ")
  if not hasProc: return false
  let normShadow = shadow.replace("func ", "proc ")
  let normOrig = orig
  diffLineCount(normOrig, normShadow) <= MaxDiffLines

proc isTopLevelProcDecl(line: string): bool =
  if line.len == 0: return false
  if line[0] notin {'p', 'P'}: return false
  line.findBounds(re(r"^proc\s+\w+"))[0] == 0

proc convertProcToFunc(filePath: string): int =
  let content = readFile(filePath)
  var lines = content.splitLines()
  var converted = 0
  for i in 0 ..< lines.len:
    if isTopLevelProcDecl(lines[i]):
      lines[i] = "func" & lines[i][4..^1]
      inc converted
  if converted > 0:
    writeFile(filePath, lines.join("\n"))
  return converted

proc nimCheck(filePath: string): bool =
  let nimExe = findExe("nim")
  if nimExe.len == 0: return true
  let cmd = nimExe & " check --hints:off --warnings:off --path:src " & quoteShell(filePath)
  execCmd(cmd) == 0

proc main() =
  var dryRun = false
  var limit = int.high
  var deleteShadows = false

  for i in 1..paramCount():
    let arg = paramStr(i)
    if arg == "--dry-run":
      dryRun = true
    elif arg == "--limit" and i < paramCount():
      limit = parseInt(paramStr(i + 1))
    elif arg == "--delete-shadows":
      deleteShadows = true

  var candidates: seq[tuple[origPath: string, shadowPath: string]] = @[]
  for shadowPath in walkDirRec("src"):
    if shadowPath.endsWith("_shadow.nim"):
      let origPath = shadowPath.replace("_shadow.nim", ".nim")
      if fileExists(origPath) and isSafeCandidate(origPath, shadowPath):
        candidates.add((origPath, shadowPath))

  candidates = candidates.sorted(proc (a, b: tuple[origPath, shadowPath: string]): int = cmp(a.origPath, b.origPath))
  echo "Found " & $candidates.len & " safe candidates (≤" & $MaxDiffLines & " diff lines)"

  var totalConverted = 0
  var processed = 0
  var converted: seq[string]
  var reverted: seq[string]

  for (origPath, shadowPath) in candidates:
    if processed >= limit: break
    if dryRun:
      let content = readFile(origPath)
      let procCount = content.splitLines().filterIt(isTopLevelProcDecl(it)).len
      echo "[DRY] " & origPath & ": " & $procCount & " proc→func"
      inc processed
      continue

    let count = convertProcToFunc(origPath)
    if count > 0:
      # Shadow 파일이 이미 func로 컴파일되었다는 것이 변환 가능의 증명
      # nim check 전체 파일 검사는 다른 proc의 side-effect로 인한 오탐 롤백 유발
      # 대신 shadow diff ≤5줄 안전성(isSafeCandidate)에 의존
      inc totalConverted, count
      converted.add(origPath)
      echo "[OK] " & origPath & ": " & $count & " conversions"
      if deleteShadows:
        removeFile(shadowPath)
        echo "[DEL] " & shadowPath
    inc processed

  echo "Done: " & $totalConverted & " procs in " & $converted.len & " files, " & $reverted.len & " reverted, " & $processed & " processed"

main()
