import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, strutils]
import safe_move

proc mergeShadowIntoOriginal(origPath, shadowPath: string): bool =
  ## Git 3-way merge: base=original, ours=original, theirs=shadow
  ## Shadow was derived from original, so base==ours → shadow changes apply cleanly
  let tmpPath = origPath & ".merge_tmp"
  copyFile(origPath, tmpPath)
  let cmd = "git merge-file " & quoteShell(tmpPath) & " " &
            quoteShell(origPath) & " " & quoteShell(shadowPath)
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode == 0:
    safeMoveFile(tmpPath, origPath)
    return true
  # Conflict — restore original, clean up tmp
  removeFile(tmpPath)
  return false

proc main() =
  var dryRun = false
  var limit = int.high
  for i in 1..paramCount():
    if paramStr(i) == "--dry-run": dryRun = true
    elif paramStr(i) == "--limit" and i < paramCount():
      limit = parseInt(paramStr(i + 1))

  var merged = 0
  var failed = 0
  var processed = 0

  for shadowPath in walkDirRec("src"):
    if not shadowPath.endsWith("_shadow.nim"): continue
    let origPath = shadowPath.replace("_shadow.nim", ".nim")
    if not fileExists(origPath): continue
    if processed >= limit: break

    if dryRun:
      echo "[DRY] Would merge: " & shadowPath & " -> " & origPath
      inc processed
      continue

    if mergeShadowIntoOriginal(origPath, shadowPath):
      removeFile(shadowPath)
      echo "[OK] Merged: " & origPath
      inc merged
    else:
      echo "[FAIL] Conflict: " & origPath
      inc failed
    inc processed

  echo "Done: " & $merged & " merged, " & $failed & " failed, " & $processed & " processed"

main()
