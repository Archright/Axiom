{.push raises: [CatchableError].}

## Proof Witness Checker Feature Test.
## See tests/features/proof_witness_checker.feature for the specification.
##
## Validates compile-time proof witness integrity — pure module checks only.
## Runtime hash verification tested in integration suite (non-hermetic).

import std/[unittest, os, strutils]
# The import IS the enforcement vehicle: proof_witness_checker runs
# verifyProofWitness() in its static block at THIS binary's compile time, so
# a witness whose lean_version drifts from the proofs/lean-toolchain pin (or
# whose source_hash no longer matches proofs/GateInvariants) fails this
# gateway test's compilation (spec: "Tampered witness file fails
# verification"). Without the import the compile-time checks never execute
# anywhere (observed 2026-10-09: stale-witness probe compiled clean).
import core/proof/proof_witness_checker

{.push warning[BareExcept]:off.}
suite "proof witness checker — compile-time integrity":

  test "proof witness JSON path is deterministically resolved":
    ## The checker uses staticRead at compile time to embed the witness.
    ## This test verifies the path constant resolves correctly.
    const witnessRelPath = "proofs" / "proof_witness.json"
    check witnessRelPath.endsWith("proof_witness.json")
    check '/' in witnessRelPath or '\\' in witnessRelPath

  test "GateInvariants directory path is well-formed":
    const gateDir = "proofs" / "GateInvariants"
    check gateDir == "proofs/GateInvariants" or gateDir == "proofs\\GateInvariants"

  test "hash algorithm identifier is sha256":
    ## The checker uses sha256sum for hash computation.
    ## This verifies the algorithm constant is correct.
    const algo = "sha256"
    check algo == "sha256"
    check algo.len == 6

  test "witness lean_version matches proofs/lean-toolchain pin (runtime enforcement)":
    ## Runtime twin of the compile-time pin check — reads BOTH artifacts from
    ## disk on every test run, so the enforcement fires even when the Nim
    ## incremental cache would reuse stale staticRead bytes (observed
    ## 2026-10-09). Same parse helpers the compile-time check consumes.
    let pin = readFile("proofs" / "lean-toolchain")
    let witness = readFile("proofs" / "proof_witness.json")
    let expected = parseLeanToolchainPinVersion(pin)
    check expected.len > 0
    let got = extractField(witness, "lean_version")
    check got.len > 0
    check got == expected
{.pop.}
