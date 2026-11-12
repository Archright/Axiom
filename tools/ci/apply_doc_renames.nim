import core/trusted/layer_declaration
axiomLayer "tools"
import std/[json, os, strutils]

proc applyRenames(repoRoot: string) =
  let renames = parseJson(readFile(repoRoot / "tools/ci/doc_renames.json"))
  var patched = 0
  for entry in renames["renames"]:
    let oldPath = entry["old"].getStr()
    let newPath = entry["new"].getStr()
    for mdFile in walkFiles(repoRoot / "docs/**/*.md"):
      let content = readFile(mdFile)
      if oldPath in content:
        let newContent = content.replace(oldPath, newPath)
        if newContent != content:
          writeFile(mdFile, newContent)
          echo "[PATCHED] " & mdFile & ": " & oldPath & " → " & newPath
          inc patched
  echo "Total patched: " & $patched

when isMainModule:
  applyRenames(getCurrentDir())
