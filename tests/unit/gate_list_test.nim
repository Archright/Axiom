import std/[unittest, sequtils, strutils]
import gate/[types, gate_contract]

suite "gate registry configuration":
  test "all gates have unique ids":
    let gates = allGates()
    var ids: seq[string] = @[]
    for g in gates:
      check g.id notin ids
      ids.add(g.id)

  test "meta gates do not reference gate_hook":
    let gates = allGates()
    for g in gates:
      if g.layer == glMeta:
        check not g.entry.contains("gate_hook")

  test "meta gates do not reference pre-commit":
    let gates = allGates()
    for g in gates:
      if g.layer == glMeta:
        check not g.entry.contains("pre-commit")

  test "cli-build is restricted to pre-push":
    let gates = allGates()
    let cliBuild = gates.filterIt(it.id == "cli-build")
    check cliBuild.len == 1
    check gsPrePush in cliBuild[0].stages
    check gsPreCommit notin cliBuild[0].stages

  test "unstaged-guard is in pre-commit stage":
    let gates = allGates()
    let guard = gates.filterIt(it.id == "unstaged-guard")
    check guard.len == 1
    check gsPreCommit in guard[0].stages

  test "heavy gates are blocked from pre-commit":
    let gates = allGates()
    let heavy = ["cli-build", "proof-universe-lock-gate"]
    for g in gates:
      if g.id in heavy:
        check gsPreCommit notin g.stages
