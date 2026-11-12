import std/[os, osproc, tables, json, strutils, sequtils]
import core/results
import core/trusted/trust_commit
import core/proof/source_fingerprint

proc findRepoRoot(): string =
  var dir = getCurrentDir()
  while dir.len > 0:
    if fileExists(dir / ".axiom_root") or fileExists(dir / "axiom.toml"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  getCurrentDir()

when isMainModule:
  let repoRoot = findRepoRoot()
  setCurrentDir(repoRoot)
  let journalBaseDir = repoRoot
  let cid = "4b0301c13a35517c5fb95a069c1040e458a4856159129687b609b521b86fddab"
  let rc = readCommit(journalBaseDir, cid)
  echo "readCommit ok: ", rc.ok
  if rc.ok:
    let claim = parseJson(rc.value.claim)
    echo "claim kind: ", claim.kind
    echo "top-level keys: ", toSeq(claim.fields.keys)
    echo "modulePath: ", claim{"modulePath"}.getStr("")
    echo "functionName: ", claim{"functionName"}.getStr("")
    echo "sourceHash: ", claim.getOrDefault("sourceHash").getStr("")
    echo "irHash: ", claim.getOrDefault("irHash").getStr("")
    echo "trustCommitId: ", claim.getOrDefault("trustCommitId").getStr("")
    echo "has entries[]: ", claim{"entries"} != nil
