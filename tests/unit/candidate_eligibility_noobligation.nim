## Unit tests for Phase A — body-aware post-satisfaction-by-construction.
##
## Oracle design (design-change-sensitive — update header when spec changes):
## When a function's body + postcondition structurally establish the
## postcondition BY CONSTRUCTION within the VerifiedFragment boundary, the
## obligation generator must classify it ogrNoApplicableObligation (reason
## obs:postSatisfiedByConstruction) → candidate eligibility elNoObligation.
##
## Controls:
##   POSITIVE: firstBoolCore — real product symbol whose deserialized IR is
##             body=IF(gt(len(candidates),0) ? 0 : defaultValue) with post
##             (len==0 ∧ result==defaultValue) ∨ (len>0 ∧ result==0).
##             → ogrNoApplicableObligation → elNoObligation.
##   NEGATIVE: normalizeMaxWorkers — post is (result >= 1) [boGe, NOT result==X
##             leaf]; body leaf-only but post leaf pattern unmatched.
##             → ogrGenerated → elProofCandidate (static boundary).
##   FRAGMENT-EXCLUSION: a loop-bearing body (irLoop) never matches → ogrGenerated.
##
## Failure mode: any mismatch → test FAIL. Faithful IR: every fixture is
## serialized and deserialized exactly as the runtime registry pipeline does,
## so the matcher observes the same canonicalized structure as production.

import std/[unittest, strutils, options, sequtils]
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/axiom_pragmas
import verification/obligation/canonical_obligation_generator
import verification/obligation/obligation_types
import verification/obligation/obligation_ir
import verification/obligation/candidate_eligibility
import verification/obligation/post_satisfaction

suite "Post-Satisfaction-by-Construction — Phase A":

  func makeEntry(name: string): RuntimeAxiomEntry =
    RuntimeAxiomEntry(
      name: name,
      irSerialized: "",
      isKernel: true,
      effectKind: Pure,
      bmcSkippable: false,
      expectedObligation: false
    )

  # Faithful IR: serialize → deserialize (mirrors registry pipeline).
  func rt(fd: IRFuncDef): IRFuncDef =
    deserializeIRFuncDef(serializeIRFuncDef(fd))

  # -------------------------------------------------------------------------
  # Positive control: firstBoolCore
  # -------------------------------------------------------------------------

  test "firstBoolCore → ogrNoApplicableObligation(obs:postSatisfiedByConstruction) → elNoObligation":
    let candidates = irVar("candidates", irTypeList(irTypeBool()))
    let lenCandidates = irCall("len", @[candidates])
    let gtZero = irBinOp(boGt, lenCandidates, irLit(0))
    # body = if gt(len(candidates),0) ? 0 : defaultValue
    let body = irIf(gtZero, irLit(0), irVar("defaultValue", irTypeBool()))
    # post = (len==0 ∧ result==defaultValue) ∨ (len>0 ∧ result==0)
    let resultVar = irVar("result", irTypeBitVec64())
    let clause1 = irBinOp(boAnd,
      irBinOp(boEq, lenCandidates, irLit(0)),
      irBinOp(boEq, resultVar, irVar("defaultValue", irTypeBool())))
    let clause2 = irBinOp(boAnd,
      irBinOp(boGt, lenCandidates, irLit(0)),
      irBinOp(boEq, resultVar, irLit(0)))
    let post = irBinOp(boOr, clause1, clause2)
    var fd = irFuncDef("firstBoolCore",
      @[("candidates", irTypeList(irTypeBool())), ("defaultValue", irTypeBool())],
      irTypeBool(), body, false)
    fd.postConditions = @[post]
    let fdt = rt(fd)

    # Direct matcher check.
    let prov = analyzePostByConstruction(fdt)
    check prov.isSome
    check prov.get.derivationRule == "obs:postSatisfiedByConstruction"

    # Generator classification.
    let gen = generateCanonicalObligations(fdt, defaultScopePolicy())
    check gen.kind == ogrNoApplicableObligation
    check gen.provenance.derivationRule == "obs:postSatisfiedByConstruction"

    # Eligibility classification.
    let cls = classifyCandidateEligibility(makeEntry("firstBoolCore"), fdt)
    check cls == elNoObligation

  # -------------------------------------------------------------------------
  # Negative control: normalizeMaxWorkers (post is boGe, not result==X leaf)
  # -------------------------------------------------------------------------

  test "normalizeMaxWorkers → ogrGenerated → elProofCandidate (negative control)":
    let resultVar = irVar("result", irTypeBitVec64())
    let postCond = irBinOp(boGe, resultVar, irLit(1))
    var fd = irFuncDef("normalizeMaxWorkers",
      @[("maxWorkers", irTypeBitVec64())], irTypeBitVec64(),
      irIf(irBinOp(boGt, irVar("maxWorkers", irTypeBitVec64()), irLit(0)),
           irVar("maxWorkers", irTypeBitVec64()), irLit(1)), false)
    fd.postConditions = @[postCond]
    let fdt = rt(fd)

    let prov = analyzePostByConstruction(fdt)
    check prov.isNone     # boGe is not a result==X leaf clause → no match

    let gen = generateCanonicalObligations(fdt, defaultScopePolicy())
    check gen.kind == ogrGenerated

    let cls = classifyCandidateEligibility(makeEntry("normalizeMaxWorkers"), fdt)
    check cls == elProofCandidate

  # -------------------------------------------------------------------------
  # Negative control: body with a loop (irLoop) → never matches
  # -------------------------------------------------------------------------

  test "loop-bearing body → ogrGenerated (never post-satisfaction)":
    # Post that IS by-construction-shaped, but body contains an irLoop, which
    # must suppress the matcher (loop body violates the leaf-only gate).
    let x = irVar("x", irTypeBitVec64())
    let resultVar = irVar("result", irTypeBitVec64())
    let loopBody = irLoop(loopKind = lkWhile, loopVars = @["i"],
      loopInits = @[], loopCond = irBinOp(boLt, irVar("i", irTypeBitVec64()), irLit(10)),
      loopBody = irVar("i", irTypeBitVec64()), loopInvariants = @[])
    # body = if x>0 ? loop : 0  (then-branch not a leaf)
    let body = irIf(irBinOp(boGt, x, irLit(0)), loopBody, irLit(0))
    var fd = irFuncDef("loop_fn", @[("x", irTypeBitVec64())], irTypeBitVec64(), body, false)
    # post = (x>0 ∧ result==loop? ) — any post; matcher must return none due to body.
    fd.postConditions = @[irBinOp(boEq, resultVar, loopBody)]
    let fdt = rt(fd)

    let prov = analyzePostByConstruction(fdt)
    check prov.isNone

    let gen = generateCanonicalObligations(fdt, defaultScopePolicy())
    check gen.kind == ogrGenerated

  # -------------------------------------------------------------------------
  # Negative control: single postcondition without disjunction, leaf mismatch
  # -------------------------------------------------------------------------

  test "post with unmatched leaf (then≠any clause leaf) → ogrGenerated":
    let x = irVar("x", irTypeBitVec64())
    let resultVar = irVar("result", irTypeBitVec64())
    # body = if x>0 ? 5 : 0   (then leaf 5)
    let body = irIf(irBinOp(boGt, x, irLit(0)), irLit(5), irLit(0))
    var fd = irFuncDef("mismatch_fn", @[("x", irTypeBitVec64())], irTypeBitVec64(), body, false)
    # post = (x>0 ∧ result==7) ∨ (x<=0? ...) — leaf 7 does not match then leaf 5
    let post = irBinOp(boOr,
      irBinOp(boAnd, irBinOp(boGt, x, irLit(0)), irBinOp(boEq, resultVar, irLit(7))),
      irBinOp(boAnd, irBinOp(boLe, x, irLit(0)), irBinOp(boEq, resultVar, irLit(0))))
    fd.postConditions = @[post]
    let fdt = rt(fd)

    # x is a VAR subject, not len — gt(x,0) normalizes fine, but the else-branch
    # guard ¬(x>0) requires arithmetic negation on a var subject → none.
    let prov = analyzePostByConstruction(fdt)
    check prov.isNone

    let gen = generateCanonicalObligations(fdt, defaultScopePolicy())
    check gen.kind == ogrGenerated
