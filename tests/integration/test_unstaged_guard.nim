when defined(axiomIntegration) or defined(leanIntegration):
  import std/[osproc, unittest]

  proc runUnstagedGuard(): tuple[exitCode: int; output: string] =
    let (output, exitCode) = execCmdEx("nim c --nimcache:nimcache -r src/gate/runners/unstaged_guard.nim")
    result = (exitCode, output)

  suite "unstaged guard":
    test "unstaged guard binary compiles":
      let (output, exitCode) = execCmdEx("nim c --nimcache:nimcache -o:bin/unstaged_guard_test_bin src/gate/runners/unstaged_guard.nim")
      check exitCode == 0
