import std/unittest
import std/strutils
import core/judge/tautology_prover

suite "Tautology Prover (Wave D)":
  test "buildTautologyProof returns simpa script":
    let proof = buildTautologyProof(@[], @[])
    check proof.len > 0
    check "simpa" in proof

  test "buildTautologyProofWithHint handles int range bounds":
    let proof = buildTautologyProofWithHint(
      "x >= -9223372036854775808 and x <= 9223372036854775807",
      "(assert (and (>= x -9223372036854775808) (<= x 9223372036854775807)))"
    )
    check proof.len > 0
    check "simpa" in proof or "h_range" in proof

  test "buildTautologyProofWithHint handles str.len >= 0":
    let proof = buildTautologyProofWithHint(
      "s.length >= 0",
      "(assert (>= (str.len s) 0))"
    )
    check proof.len > 0
    check "simpa" in proof

  test "isTautologyConstraint detects str.len >= 0":
    check isTautologyConstraint("(>= (str.len s) 0)", "s.length >= 0")

  test "isTautologyConstraint detects int range bounds":
    check isTautologyConstraint(
      "(>= x -9223372036854775808)",
      "x >= -9223372036854775808"
    )

  test "isTautologyConstraint does not flag str.len > 5 as tautology":
    check not isTautologyConstraint("(> (str.len s) 5)", "s.length > 5")
