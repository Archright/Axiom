import std/unittest
import cli/ax_workflow_shortcuts
import core/results

suite "parseAxTopologyShortcutArgs contract":
  test "defaults when no args":
    let res = parseAxTopologyShortcutArgs(@[])
    check res.isOk()
    let args = res.get()
    check args.targetDirectory == "src"
    check args.limit == axShortcutDefaultLimit
    check args.diagnosisDepth == 0
    check args.emitJson == false

  test "parses --limit":
    let res = parseAxTopologyShortcutArgs(@["--limit", "10"])
    check res.isOk()
    check res.get().limit == 10

  test "--limit clamps to minimum of 1":
    let res = parseAxTopologyShortcutArgs(@["--limit", "0"])
    check res.isOk()
    check res.get().limit == 1

  test "--limit requires a value":
    let res = parseAxTopologyShortcutArgs(@["--limit"])
    check res.isErr()

  test "parses --diagnostic-depth":
    let res = parseAxTopologyShortcutArgs(@["--diagnostic-depth", "3"])
    check res.isOk()
    check res.get().diagnosisDepth == 3

  test "parses --json flag":
    let res = parseAxTopologyShortcutArgs(@["--json"])
    check res.isOk()
    check res.get().emitJson == true

  test "accepts positional target directory":
    let res = parseAxTopologyShortcutArgs(@["src/core"])
    check res.isOk()
    check res.get().targetDirectory == "src/core"

  test "unknown option is rejected":
    let res = parseAxTopologyShortcutArgs(@["--strict"])
    check res.isErr()
