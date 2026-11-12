{.push raises: [].}
## PBT: ProofReplayResult Data Properties
## Exercises: src/core/types/workflow_state.nim (ProofReplayResult, ProofReplayTactic)
## Properties:
##   - toJson always produces JObject with expected fields
##   - proofReplayTacticNames preserves tactic names (roundtrip)
##   - ProofReplayTactic toJson contains all fields
##   - Empty tactics list yields empty names
## @basic tier — runs in every CI push.

import std/[json, sequtils, unittest]
import core/testing/pbt_engine
import core/types/workflow_state

suite "PBT: ProofReplayResult toJson":
  test "toJson always produces JObject (200 iterations)":
    # Property: toJson on any ProofReplayResult always returns JObject.
    let gen = genString(1, 32)
    let prop = proc(methodName: string): bool =
      let replay = ProofReplayResult(
        replayMethod: methodName,
        verified: true,
        leanKernelVerified: false
      )
      let json = replay.toJson()
      json.kind == JObject
    let pbtResult = checkProperty(gen, prop, iterations = 200,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

  test "toJson has expected top-level fields (200 iterations)":
    # Property: toJson output always contains method, verified, tactics fields.
    let gen = genString(1, 32)
    let prop = proc(methodName: string): bool =
      let replay = ProofReplayResult(replayMethod: methodName)
      let json = replay.toJson()
      json.hasKey("method") and json.hasKey("verified") and json.hasKey("tactics")
    let pbtResult = checkProperty(gen, prop, iterations = 200,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

  test "toJson method field matches replayMethod (200 iterations)":
    # Property: json["method"] == replay.replayMethod.
    let gen = genString(1, 32)
    let prop = proc(methodName: string): bool =
      let replay = ProofReplayResult(replayMethod: methodName)
      let json = replay.toJson()
      json{"method"}.getStr("") == methodName
    let pbtResult = checkProperty(gen, prop, iterations = 200,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

suite "PBT: proofReplayTacticNames":
  test "proofReplayTacticNames preserves names (200 iterations)":
    # Property: proofReplayTacticNames(toJson-like) roundtrips tactic names.
    let gen = genString(1, 20)
    let prop = proc(name: string): bool =
      let tactic = ProofReplayTactic(name: name, step: 1, verified: true)
      let replay = ProofReplayResult(
        replayMethod: "test",
        tactics: @[tactic]
      )
      let names = replay.proofReplayTacticNames()
      names.len == 1 and names[0] == name
    let pbtResult = checkProperty(gen, prop, iterations = 200,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

  test "Empty tactics yields empty names (100 iterations)":
    # Property: proofReplayTacticNames on empty tactics returns empty seq.
    let gen = genString(1, 32)
    let prop = proc(methodName: string): bool =
      let replay = ProofReplayResult(replayMethod: methodName)
      let names = replay.proofReplayTacticNames()
      names.len == 0
    let pbtResult = checkProperty(gen, prop, iterations = 100,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

  test "Multiple tactics preserve all names (100 iterations)":
    # Property: names length matches tactics length, each name preserved.
    let gen = genString(1, 16)
    let prop = proc(baseName: string): bool =
      var tactics: seq[ProofReplayTactic] = @[]
      for i in 0..4:
        tactics.add(ProofReplayTactic(name: baseName & $i, step: i, verified: true))
      let replay = ProofReplayResult(
        replayMethod: "test",
        tactics: tactics
      )
      let names = replay.proofReplayTacticNames()
      if names.len != 5: return false
      for i in 0..4:
        if names[i] != baseName & $i: return false
      true
    let pbtResult = checkProperty(gen, prop, iterations = 100,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

suite "PBT: ProofReplayTactic toJson":
  test "ProofReplayTactic toJson has all fields (200 iterations)":
    # Property: tactic toJson always contains name, step, verified.
    let gen = genString(1, 20)
    let prop = proc(name: string): bool =
      let tactic = ProofReplayTactic(name: name, step: 42, verified: false)
      let json = %tactic
      json.kind == JObject and
      json.hasKey("name") and
      json.hasKey("step") and
      json.hasKey("verified")
    let pbtResult = checkProperty(gen, prop, iterations = 200,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

  test "ProofReplayTactic toJson name matches (200 iterations)":
    # Property: json["name"] == tactic.name.
    let gen = genString(1, 20)
    let prop = proc(name: string): bool =
      let tactic = ProofReplayTactic(name: name, step: 0, verified: true)
      let json = %tactic
      json{"name"}.getStr("") == name
    let pbtResult = checkProperty(gen, prop, iterations = 200,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

{.pop.}
