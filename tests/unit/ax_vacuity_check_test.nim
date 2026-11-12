import std/unittest
import std/sequtils
import std/strutils
import verification/lean_vacuity_test_runner

## Adversarial validation tests for the ax_vacuity_check anti-vacuity linter.
## These tests exercise the compiler wrapper, not just the tactic in isolation,
## to guarantee the end-to-end contract: a certificate is "vacuity proven" only
## when the generated Lean source (a) compiles and (b) contains a successful
## ax_vacuity_check theorem for the main safety theorem.

suite "ax_vacuity_check adversarial validation":
  setup:
    cleanTestArtifacts()

  teardown:
    cleanTestArtifacts()

  test "clean proof with vacuity theorem is verified and vacuity proven":
    let res = runVacuityCompilerCase(tckCleanWithVacuity)
    check res.verified == true
    check res.vacuityProven == true
    check res.negativeTestVerified == false

  test "sorry in main proof fails compilation and vacuity":
    let res = runVacuityCompilerCase(tckSorryInProof)
    check res.verified == false
    check res.vacuityProven == false

  test "unauthorized axiom is rejected by vacuity linter":
    let res = runVacuityCompilerCase(tckUnauthorizedAxiom)
    check res.verified == false
    check res.vacuityProven == false
    check res.diagnostics.anyIt(it.message.contains("prohibited constant"))

  test "clean proof without vacuity theorem is not vacuity proven":
    let res = runVacuityCompilerCase(tckCleanWithoutVacuity)
    check res.verified == true
    check res.vacuityProven == false
