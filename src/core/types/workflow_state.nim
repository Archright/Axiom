import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/trusted/axiom_pragmas
import std/json
import std/sequtils
type
  ProofReplayTactic* = object
    name*: string
    step*: int
    verified*: bool

  ProofReplayResult* = object
    replayMethod*: string
    tactics*: seq[ProofReplayTactic]
    verified*: bool
    leanKernelVerified*: bool
    minimalProofPath*: seq[string]
    soundnessNote*: string
    strictSpecWarnings*: seq[string]
func proofReplayTacticNames*(replay: ProofReplayResult): seq[string] {.noSideEffect, axiom: ["(assert (and (>= (str.len replay_replayMethod) 0) (>= (seq.len replay_tactics) 0) (or (= replay_verified true) (= replay_verified false)) (or (= replay_leanKernelVerified true) (= replay_leanKernelVerified false)) (>= (seq.len replay_minimalProofPath) 0) (>= (str.len replay_soundnessNote) 0) (>= (seq.len replay_strictSpecWarnings) 0) (or (= replay_verified true) (= replay_verified false)) (or (= replay_leanKernelVerified true) (= replay_leanKernelVerified false))))", "replay_replayMethod.length ≥ 0 ∧ replay_tactics.size ≥ 0 ∧ replay_verified = true ∨ replay_verified = false ∧ replay_leanKernelVerified = true ∨ replay_leanKernelVerified = false ∧ replay_minimalProofPath.size ≥ 0 ∧ replay_soundnessNote.length ≥ 0 ∧ replay_strictSpecWarnings.size ≥ 0 ∧ replay_verified = true ∨ replay_verified = false ∧ replay_leanKernelVerified = true ∨ replay_leanKernelVerified = false"].} =
  replay.tactics.mapIt(it.name)
func `%`*(tactic: ProofReplayTactic): JsonNode {.noSideEffect.} =
  %*{
    "name": tactic.name,
    "step": tactic.step,
    "verified": tactic.verified
  }
func toJson*(replay: ProofReplayResult): JsonNode {.noSideEffect, raises: [].} =
  ## Serializes ProofReplayResult to JSON without using % operator.
  ## Avoids {.raises: [Exception].} from std/json's generic %.
  result = newJObject()
  result["method"] = newJString(replay.replayMethod)
  var tacticsArr = newJArray()
  for t in replay.tactics:
    var tNode = newJObject()
    tNode["name"] = newJString(t.name)
    tNode["step"] = newJInt(t.step)
    tNode["verified"] = newJBool(t.verified)
    tacticsArr.add(tNode)
  result["tactics"] = tacticsArr
  result["verified"] = newJBool(replay.verified)
  result["leanKernelVerified"] = newJBool(replay.leanKernelVerified)
  var mpArr = newJArray()
  for p in replay.minimalProofPath:
    mpArr.add(newJString(p))
  result["minimalProofPath"] = mpArr
  result["soundnessNote"] = newJString(replay.soundnessNote)
  var sswArr = newJArray()
  for w in replay.strictSpecWarnings:
    sswArr.add(newJString(w))
  result["strictSpecWarnings"] = sswArr
{.pop.}
