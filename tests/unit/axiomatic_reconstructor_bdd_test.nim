## BDD test runner for tests/features/axiomatic_reconstructor.feature
import std/unittest
import std/strutils
import core/encoding/smt_to_lean_translate

type
  BddCtx = object
    smtlib: string
    theoremOutput: string

proc givenTheAxiomaticReconstructorIsInitialized*(ctx: var BddCtx) =
  ctx.smtlib = ""
  ctx.theoremOutput = ""

proc givenAnSmtAssertion(ctx: var BddCtx; assertion: string) =
  ctx.smtlib = assertion

proc whenTheReconstructorGeneratesALeanTheorem*(ctx: var BddCtx) =
  ctx.theoremOutput = buildLeanProofFromSmtlib2("test_theorem", ctx.smtlib)

proc thenTheTheoremContains*(ctx: var BddCtx; expected: string) =
  check ctx.theoremOutput.contains(expected)

proc thenTheTheoremDoesNotContain*(ctx: var BddCtx; expected: string) =
  check not ctx.theoremOutput.contains(expected)

suite "bdd: axiomatic_reconstructor.feature":
  test "depth bound assertion produces Nat.zero_le without sorry":
    var ctx: BddCtx
    givenTheAxiomaticReconstructorIsInitialized(ctx)
    givenAnSmtAssertion(ctx, "(assert (>= depth 0))")
    whenTheReconstructorGeneratesALeanTheorem(ctx)
    thenTheTheoremContains(ctx, "Nat.zero_le depth")
    thenTheTheoremDoesNotContain(ctx, "sorry")

  test "string length assertion produces Nat.zero_le without sorry":
    var ctx: BddCtx
    givenTheAxiomaticReconstructorIsInitialized(ctx)
    givenAnSmtAssertion(ctx, "(assert (>= (str.len s) 0))")
    whenTheReconstructorGeneratesALeanTheorem(ctx)
    thenTheTheoremContains(ctx, "Nat.zero_le s.length")
    thenTheTheoremDoesNotContain(ctx, "sorry")

  test "and assertion with two bounds produces constructor with subproofs":
    var ctx: BddCtx
    givenTheAxiomaticReconstructorIsInitialized(ctx)
    givenAnSmtAssertion(ctx, "(assert (and (>= (str.len raw) 0) (>= startIdx 0)))")
    whenTheReconstructorGeneratesALeanTheorem(ctx)
    thenTheTheoremContains(ctx, "constructor")
    thenTheTheoremContains(ctx, "Nat.zero_le")
    thenTheTheoremDoesNotContain(ctx, "sorry")

  test "self-equality assertion produces Eq.refl without sorry":
    var ctx: BddCtx
    givenTheAxiomaticReconstructorIsInitialized(ctx)
    givenAnSmtAssertion(ctx, "(assert (= x x))")
    whenTheReconstructorGeneratesALeanTheorem(ctx)
    thenTheTheoremContains(ctx, "Eq.refl")
    thenTheTheoremDoesNotContain(ctx, "sorry")
