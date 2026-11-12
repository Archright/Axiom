{.push raises: [].}

## axiom_codec_test — Prototype Validation for deriveJsonCodec
##
## Tests enum, simple object, and complex nested object derivation.
## Validates round-trip, strict validation (missing/wrong type → err),
## JArray guard, and edge cases.

import std/unittest
import core/codec/axiom_codec
import core/types/domain_types
import core/types/universe_types
import core/types/workflow_state
import core/json/std_redirect

# Apply deriveJsonCodec to prototype types
# (In production, deriveJsonCodec goes in the type file itself)
deriveJsonCodec(AxiomError)
deriveJsonCodec(ProofUniverseLock)
deriveJsonCodec(ProofReplayTactic)
deriveJsonCodec(ProofReplayResult)

# Variant object types at module level (deriveJsonCodec requires top-level context)
type
  ShapeKind = enum
    skCircle, skRect, skTriangle
  Shape = object
    name: string
    case kind: ShapeKind
    of skCircle:
      radius: float
    of skRect:
      width, height: float
    of skTriangle:
      base: float
      triHeight: float

deriveJsonCodec(Shape)

suite "deriveJsonCodec enum":
  test "AxiomError round-trip all 23 variants":
    for v in AxiomError:
      let j = toJson(v)
      check j.kind == JString
      check j.getStr() == $v
      let back = fromJson(j, AxiomError)
      check back.ok
      check back.value == v

  test "AxiomError fromJson invalid string":
    let r = fromJson(newJString("nonexistent_variant"), AxiomError)
    check not r.ok

  test "AxiomError fromJson wrong JSON kind":
    let r = fromJson(newJInt(42), AxiomError)
    check not r.ok

suite "deriveJsonCodec simple object":
  test "ProofUniverseLock round-trip":
    let lock = ProofUniverseLock(
      merkleRoot: "abc123",
      timestamp: "2026-06-13T09:00:00Z",
      fileCount: 42,
      vkdFixed4: "deadbeef"
    )
    let back = fromJson(toJson(lock), ProofUniverseLock)
    check back.ok
    check back.value.merkleRoot == "abc123"
    check back.value.timestamp == "2026-06-13T09:00:00Z"
    check back.value.fileCount == 42
    check back.value.vkdFixed4 == "deadbeef"

  test "ProofUniverseLock missing field → err":
    let j = %*{"merkleRoot": "abc"}
    let r = fromJson(j, ProofUniverseLock)
    check not r.ok

  test "ProofUniverseLock wrong type for int field → err":
    let j = %*{"merkleRoot": "abc", "timestamp": "t", "fileCount": "not_int", "vkdFixed4": "f"}
    let r = fromJson(j, ProofUniverseLock)
    check not r.ok

  test "ProofUniverseLock empty values":
    let lock = ProofUniverseLock(merkleRoot: "", timestamp: "", fileCount: 0, vkdFixed4: "")
    let back = fromJson(toJson(lock), ProofUniverseLock)
    check back.ok
    check back.value.merkleRoot == ""
    check back.value.fileCount == 0

suite "deriveJsonCodec nested object":
  test "ProofReplayTactic round-trip":
    let t = ProofReplayTactic(name: "intro", step: 1, verified: true)
    let back = fromJson(toJson(t), ProofReplayTactic)
    check back.ok
    check back.value.name == "intro"
    check back.value.step == 1
    check back.value.verified == true

  test "ProofReplayResult round-trip with nested objects":
    let r = ProofReplayResult(
      replayMethod: "lean",
      tactics: @[
        ProofReplayTactic(name: "intro", step: 1, verified: true),
        ProofReplayTactic(name: "apply", step: 2, verified: false)
      ],
      verified: true,
      leanKernelVerified: true,
      minimalProofPath: @["a.lean", "b.lean"],
      soundnessNote: "ok",
      strictSpecWarnings: @["warning1"]
    )
    let back = fromJson(toJson(r), ProofReplayResult)
    check back.ok
    let got = back.value
    check got.replayMethod == "lean"
    check got.tactics.len == 2
    check got.tactics[0].name == "intro"
    check got.tactics[1].verified == false
    check got.minimalProofPath == @["a.lean", "b.lean"]
    check got.strictSpecWarnings == @["warning1"]

  test "ProofReplayResult empty seqs":
    let r = ProofReplayResult(
      replayMethod: "",
      tactics: @[],
      verified: false,
      leanKernelVerified: false,
      minimalProofPath: @[],
      soundnessNote: "",
      strictSpecWarnings: @[]
    )
    let back = fromJson(toJson(r), ProofReplayResult)
    check back.ok

  test "ProofReplayResult non-array seq field → err":
    let j = %*{
      "replayMethod": "",
      "tactics": "not_an_array",
      "verified": false,
      "leanKernelVerified": false,
      "minimalProofPath": [],
      "soundnessNote": "",
      "strictSpecWarnings": []
    }
    let r = fromJson(j, ProofReplayResult)
    check not r.ok

  test "ProofReplayResult missing field → err":
    let j = %*{"replayMethod": "lean"}
    let r = fromJson(j, ProofReplayResult)
    check not r.ok

suite "deriveJsonCodec toJson structure":
  test "ProofUniverseLock JSON keys match expected names":
    let lock = ProofUniverseLock(merkleRoot: "x", timestamp: "y", fileCount: 1, vkdFixed4: "z")
    let j = toJson(lock)
    check j.hasKey("merkleRoot")
    check j.hasKey("timestamp")
    check j.hasKey("fileCount")
    check j.hasKey("vkdFixed4")
    check not j.hasKey("nonexistent")

  test "AxiomError toJson is JString":
    let j = toJson(axiomErrSolverTimeout)
    check j.kind == JString
    check j.getStr() == "axiomErrSolverTimeout"

suite "deriveJsonCodec variant object":
  test "variant object round-trip — circle":
    let s = Shape(name: "c", kind: skCircle, radius: 3.14)
    let j = toJson(s)
    check j["kind"].getStr() == "skCircle"
    check j["radius"].getFloat() == 3.14
    check j["name"].getStr() == "c"
    let back = fromJson(j, Shape)
    check back.ok
    check back.value.kind == skCircle
    check back.value.radius == 3.14

  test "variant object round-trip — rect":
    let s = Shape(name: "r", kind: skRect, width: 10.0, height: 5.0)
    let j = toJson(s)
    check j["kind"].getStr() == "skRect"
    check j["width"].getFloat() == 10.0
    let back = fromJson(j, Shape)
    check back.ok
    check back.value.width == 10.0
    check back.value.height == 5.0

  test "variant object fromJson missing discriminator → err":
    let j = %*{"name": "bad"}
    let r = fromJson(j, Shape)
    check not r.ok

  test "variant object fromJson unknown discriminator → err":
    let j = %*{"kind": "skHexagon", "name": "bad"}
    let r = fromJson(j, Shape)
    check not r.ok

{.pop.}
