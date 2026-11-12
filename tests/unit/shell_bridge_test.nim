import std/[os, strutils, unittest]
import core/solver/shell_bridge

suite "shell_bridge":
  test "runCommandInDir returns exit code 0 for echo":
    let res = runCommandInDir("echo hello")
    check res.exitCode == 0
    check "hello" in res.output

  test "runCommandInDir respects workingDir":
    let tmpDir = getTempDir()
    let res = runCommandInDir("pwd", tmpDir)
    when defined(windows):
      check tmpDir.replace('/', '\\') in res.output
    else:
      check tmpDir.strip(chars = {'/'}) == res.output.strip().strip(chars = {'/'})

  test "checkToolAvailable finds nim":
    check checkToolAvailable("nim") == true

  test "checkToolAvailable returns false for nonexistent tool":
    check checkToolAvailable("nonexistent_tool_xyz") == false

  test "runCommandSeqInDir runs multiple commands":
    let res = runCommandSeqInDir(@["echo first", "echo second"])
    check res.exitCode == 0
    check "first" in res.output
    check "second" in res.output

  test "runCommandSeqInDir stops at first failure":
    let res = runCommandSeqInDir(@["echo ok", "nonexistent_tool_xyz"])
    check res.exitCode != 0
