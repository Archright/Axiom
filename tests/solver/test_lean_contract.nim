## Lean REPL 계약 테스트 (Contract-First TDD)
## docs/spec/lean_repl_protocol.md §1-§7 각 시나리오 검증

import std/[unittest, streams, json, os, osproc, strutils, times]

const MockBin = "tests/solver/mock_lean_repl"

proc startMock(): Process =
  startProcess(MockBin, options = {poStdErrToStdOut})

proc sendCmd(p: Process, cmd: string, env: int = -1): JsonNode =
  var request = %*{"cmd": cmd}
  if env >= 0:
    request["env"] = %*env
  p.inputStream.write($request & "\n\n")
  p.inputStream.flush()

  var responseStr = ""
  let deadline = getTime() + initDuration(seconds = 5)
  while getTime() < deadline:
    if not p.outputStream.atEnd:
      let line = p.outputStream.readLine()
      responseStr.add(line)
      try:
        return parseJson(responseStr)
      except JsonParsingError:
        continue
    else:
      sleep(10)
  doAssert false, "Timeout waiting for mock response"

suite "Lean REPL Protocol Contract (spec: lean_repl_protocol.md)":

  test "§1 basic command → env response":
    let p = startMock()
    defer:
      p.inputStream.close()
      discard p.waitForExit(2000)
      p.close()

    let r = sendCmd(p, "def f := 2")
    check r.hasKey("env")
    check r["env"].getInt() == 1
    check r.hasKey("messages")

  test "§2 explicit env tracking":
    let p = startMock()
    defer:
      p.inputStream.close()
      discard p.waitForExit(2000)
      p.close()

    let r1 = sendCmd(p, "def f := 2")
    check r1["env"].getInt() == 1

    let r2 = sendCmd(p, "example : f = 2 := rfl", env = 1)
    check r2["env"].getInt() == 2

  test "§3 tactic mode → proofStates + goals":
    let p = startMock()
    defer:
      p.inputStream.close()
      discard p.waitForExit(2000)
      p.close()

    let r = sendCmd(p, "example : True := by")
    check r.hasKey("proofStates")
    check r["proofStates"].len > 0
    check r.hasKey("goals")
    check r["goals"].len > 0

  test "§5 sorry detection":
    let p = startMock()
    defer:
      p.inputStream.close()
      discard p.waitForExit(2000)
      p.close()

    let r = sendCmd(p, "example : False := sorry")
    check r.hasKey("sorries")
    check r["sorries"].len > 0
    check r["sorries"][0].hasKey("goal")

  test "§7 EOF → clean exit":
    let p = startMock()
    # Send one command first
    discard sendCmd(p, "def x := 1")
    # Close stdin to trigger EOF
    p.inputStream.close()
    let exitCode = p.waitForExit(2000)
    check exitCode == 0
    p.close()

  test "sequential commands with env increment":
    let p = startMock()
    defer:
      p.inputStream.close()
      discard p.waitForExit(2000)
      p.close()

    let r1 = sendCmd(p, "def a := 1")
    let r2 = sendCmd(p, "def b := 2")
    let r3 = sendCmd(p, "def c := 3")
    check r1["env"].getInt() == 1
    check r2["env"].getInt() == 2
    check r3["env"].getInt() == 3
