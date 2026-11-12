## Unit tests for tools/setup_hooks.nim (bin/setup-hooks replacement)
## Runs the compiled binary in isolated temp git repos, and scans the tracked
## sources for competing writers of the hooksPath key.
## Authority: docs/adr/0028-hook-installation-authority.md

import std/[unittest, os, osproc, strutils, times]

const
  RepoRoot = currentSourcePath().parentDir().parentDir().parentDir()
  SetupHooksBin = RepoRoot / "bin" / "setup-hooks"
  CanonicalHooksPath = ".githooks"
  SoleWriter = "tools/setup_hooks.nim"
  ReadFlags = ["--get", "--unset", "--list", "--replace-all", "-l"]
  ScannedExts = [".nim", ".nimble", ".nims", ".mk", ".sh", ".py"]

proc writesHooksPath(line: string): bool =
  ## True when the line assigns a value to the hooksPath key. Bare `--get` is a
  ## read, and a redirection (`2>/dev/null`) is a read plus a value for the shell.
  let key = "core" & "." & "hooksPath"
  let keyPos = line.find(key)
  if keyPos < 0 or "git config" notin line:
    return false
  for readFlag in ReadFlags:
    if readFlag in line:
      return false
  let value = line[keyPos + key.len .. ^1].strip()
  if value.len == 0 or value[0] == '-':
    return false
  let firstChar = value[0]
  firstChar in {'A'..'Z', 'a'..'z', '.', '/', '_'}

suite "setup_hooks":

  test "success: configures git hooksPath to .githooks":
    let tmpDir = getTempDir() / "axiom_setup_hooks_test_" & $toUnix(getTime())
    try:
      createDir(tmpDir)
      discard execCmdEx("git init", workingDir = tmpDir)
      discard execCmdEx("git config user.email \"test@test.com\"", workingDir = tmpDir)
      discard execCmdEx("git config user.name \"Test\"", workingDir = tmpDir)

      createDir(tmpDir / ".githooks")
      copyFile(RepoRoot / ".githooks" / "pre-commit", tmpDir / ".githooks" / "pre-commit")
      copyFile(RepoRoot / ".githooks" / "pre-push", tmpDir / ".githooks" / "pre-push")

      let (output, exitCode) = execCmdEx(SetupHooksBin.quoteShell, workingDir = tmpDir)

      check exitCode == 0
      check "[OK]" in output

      let (hooksVal, rc) = execCmdEx("git config --local --get core.hooksPath",
                                    workingDir = tmpDir)
      check rc == 0
      check hooksVal.strip() == CanonicalHooksPath
      check not dirExists(tmpDir / "hooks")
    finally:
      removeDir(tmpDir)

  test "fail-closed: errors when .githooks directory not found":
    let tmpDir = getTempDir() / "axiom_setup_hooks_test_no_githooks_" & $toUnix(getTime())
    try:
      createDir(tmpDir)
      discard execCmdEx("git init", workingDir = tmpDir)
      discard execCmdEx("git config user.email \"test@test.com\"", workingDir = tmpDir)
      discard execCmdEx("git config user.name \"Test\"", workingDir = tmpDir)

      # Do NOT copy .githooks/ — the tool should fail with a clear error
      let (output, exitCode) = execCmdEx(SetupHooksBin.quoteShell, workingDir = tmpDir)

      check exitCode != 0
      check "not found" in output
    finally:
      removeDir(tmpDir)

  test "authority: tools/setup_hooks.nim is the only tracked writer of the hooksPath key":
    let (tracked, rc) = execCmdEx("git ls-files -z", workingDir = RepoRoot)
    check rc == 0

    var writers: seq[string] = @[]
    for rel in tracked.split('\0'):
      if rel.len == 0 or splitFile(rel).ext notin ScannedExts:
        continue
      let full = RepoRoot / rel
      if not fileExists(full):
        continue
      for line in readFile(full).splitLines():
        if writesHooksPath(line) and rel notin writers:
          writers.add(rel)

    check writers == @[SoleWriter]