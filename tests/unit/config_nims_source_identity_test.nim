## Single-Authority guard for source identity (VS-SOURCE-IDENTITY-1 PR-B).
##
## `config.nims` is an execution ADAPTER. The vs1-tree-hash/1 kernel lives in
## `tools/hermetic_build.nim`; a second NimScript implementation would drift
## silently (DEBT#532). These assertions are source-level invariants: the
## adapter must (a) contain no kernel walk, (b) route through
## `bin/hermetic_build --src-tree-hash`, (c) gate on `getCommand() == "check"`
## because `exec`/`staticExec` are silent no-ops there, and (d) bind the
## toolchain + helper payload into envHash instead of trusting size/mtime.

import std/[unittest, os, strutils]

proc findRepoRoot(): string =
  var dir = getCurrentDir()
  while true:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  raise newException(IOError, ".axiom_root not found from " & getCurrentDir())

suite "config.nims source identity — single authority":

  let root = findRepoRoot()
  let cfg = readFile(root / "config.nims")

  test "no duplicate hash kernel in the adapter":
    check not cfg.contains("proc computeSourceTreeHash")
    check not cfg.contains("walkDirRec(srcDir)")
    check not cfg.contains("stream.add(rel)")

  test "native authority route is wired":
    check cfg.contains("proc nativeSourceTreeHash")
    check cfg.contains("bin/hermetic_build")
    check cfg.contains("--src-tree-hash")

  test "check mode is detected and cannot spawn children":
    check cfg.contains("getCommand() != \"check\"")
    check cfg.contains("cache decision deferred")

  test "temp output is PID-unique, validated, and always removed":
    check cfg.contains("src_tree_hash.")
    check cfg.contains("vs1-tree-hash/1")
    check cfg.contains("parseInt")
    check cfg.contains("finally:")
    check cfg.contains("rmFile(outTmp)")

  test "envHash binds toolchain and helper payload":
    check cfg.contains("NimVersion")
    check cfg.contains("sizeof(int)")
    check cfg.contains("sha256sum")
    check cfg.contains("|hb:")

  test "cold bootstrap defers instead of recursing":
    check cfg.contains("cold bootstrap")