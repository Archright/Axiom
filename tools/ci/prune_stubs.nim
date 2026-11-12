import core/trusted/layer_declaration
axiomLayer "tools"
import api/tools_facade
import shared_types/shared_types
import std/[os, osproc, strutils]
proc countImporters(repoRoot, moduleName: string): int {.axiomEffect: IoEffect.} =
  ## Count how many .nim files under src/ import this module.
  result = 0
  let srcDir = repoRoot / "src"
  if not dirExists(srcDir):
    return
  let searchPattern = "import core/" & moduleName
  for kind, path in walkDir(srcDir):
    if kind == pcFile and path.endsWith(".nim"):
      try:
        let content = readFile(path)
        for line in content.splitLines():
          if searchPattern in line:
            inc result
            break
      except CatchableError:
        discard  # axiom:best-effort(readFile failure during import scan — non-fatal)
proc main() {.axiomEffect: IoEffect.} =
  let params = commandLineParams()
  let deleteMode = params.contains("--delete")

  if params.contains("--help") or params.contains("-h"):
    echo "Usage: prune_stubs.nim [--delete]"
    echo "  (default)  Dry-run: report deprecated stubs with 0 importers"
    echo "  --delete   Actually remove the files via git rm"
    quit(0)

  let repoRoot = findRepoRoot()

  if deleteMode:
    echo "[prune] DELETE MODE \u2014 files will be removed"
  else:
    echo "[prune] DRY RUN \u2014 no files will be deleted"

  let coreDir = repoRoot / "src" / "core"
  if not dirExists(coreDir):
    echo "[prune] src/core/ not found"
    quit(1)

  var count = 0

  for kind, stub in walkDir(coreDir):
    if kind != pcFile:
      continue
    if not stub.endsWith(".nim"):
      continue

    try:
      let content = readFile(stub)
      if "{.deprecated.}" notin content:
        continue
    except CatchableError:
      continue

    let (_, name, _) = stub.splitFile()
    let importers = countImporters(repoRoot, name)

    if importers == 0:
      echo "[prune] " & stub & " \u2014 0 importers"
      if deleteMode:
        let gitCmd = "git -C \"" & repoRoot & "\" rm \"" & stub & "\""
        try:
          let (output, exitCode) = execCmdEx(gitCmd)
          if exitCode == 0:
            echo "[prune]   DELETED"
          else:
            echo "[prune]   git rm failed: " & output.strip()
        except CatchableError:
          echo "[prune]   git rm failed"
      inc count

  echo "[prune] Found " & $count & " deprecated stubs with 0 importers"
  if count > 0 and not deleteMode:
    echo "[prune] Run with --delete to remove them"

when isMainModule:
  main()
