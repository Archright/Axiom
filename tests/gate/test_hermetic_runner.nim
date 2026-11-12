import std/unittest
import gate/framework/hermetic_runner

suite "HermeticRunner":
  test "compile and run pass gate returns gskPass":
    let runner = initHermeticRunner()
    let result = runner.runGateIsolated("tests/fixtures/hermetic_pass_gate.nim", @[])
    check result.status == gskPass

  test "compile and run fail gate returns gskFail":
    let runner = initHermeticRunner()
    let result = runner.runGateIsolated("tests/fixtures/hermetic_fail_gate.nim", @[])
    check result.status == gskFail

  test "compile and run crash gate returns gskError":
    let runner = initHermeticRunner()
    let result = runner.runGateIsolated("tests/fixtures/hermetic_crash_gate.nim", @[])
    check result.status == gskError
