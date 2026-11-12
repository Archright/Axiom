## tests/unit/test_ir_pipeline_theaterguard.nim
## DEBT#423 — TheaterGuard / early-return obligation-count preservation.
##
## Verifies:
##   1. Post-generation verdict constructors never zero the obligation count
##      (generatedObligationVerdict / theaterDetectedVerdict).
##   2. runIrPipeline preserves the generated obligation count on early-return
##      paths taken AFTER obligation generation (BMC-skip pre-check).
##   3. The standard completion path keeps kind=ogrGenerated with the count.
##   4. Pre-generation exits (ogrNoApplicableObligation) still report count 0 —
##      the "0 for non-generated" invariant is not broken by the fix.
##
## No z3/lean binaries are required: assertions only touch obligation verdicts.

import std/[unittest, options]
import core/trusted/axiom_ir
import core/trusted/contract_synthesis
import core/trusted/verification_result_types
import core/axiom_pragmas
import verification/obligation/obligation_ir
import verification/obligation/canonical_obligation_generator
import verification/batch_uap/ir_pipeline_runner

# ---------------------------------------------------------------------------
# Fixture helpers (mirror tests/integration/test_pipeline_stage1_5.nim)
# ---------------------------------------------------------------------------

func makeParam(name: string; ty: IRTypeKind = irtBitVec64): IRFuncParam =
  IRFuncParam(name: name, ty: IRType(kind: ty), constraint: none(IRExpr))

func makeLit(val: int64): IRExpr =
  IRExpr(kind: irLit, litVal: val)

func makeVar(name: string): IRExpr =
  IRExpr(kind: irVar, varName: name, varType: IRType(kind: irtBitVec64))

func makeBinOp(op: BinOpKind; lhs, rhs: IRExpr): IRExpr =
  IRExpr(kind: irBinOp, binOp: op, binLhs: lhs, binRhs: rhs)

func makeDivFuncDef(name: string): IRFuncDef =
  ## x / y — division safety obligation + synthesized division-guard
  ## precondition obligation (>= 1 obligation, unmistakeably generated).
  IRFuncDef(name: name,
            params: @[makeParam("x"), makeParam("y")],
            retType: IRType(kind: irtBitVec64),
            body: makeBinOp(boDiv, makeVar("x"), makeVar("y")))

proc makeEntry(name: string; bmcSkippable: bool): RuntimeAxiomEntry =
  RuntimeAxiomEntry(name: name, irSerialized: "test_ir_serialized",
                    smtSource: "", leanSource: "",
                    sourcePath: "test/module.nim", isKernel: true,
                    irHash: "test_ir_hash_" & name, effectKind: Pure,
                    bmcSkippable: bmcSkippable)

# Mirror the pipeline's generation sequence: synthesizeContracts runs first,
# then generateCanonicalObligations — the count the pipeline must preserve.
func expectedGeneratedCount(f: IRFuncDef): int =
  var fd = f
  synthesizeContracts(fd)
  let ogr = generateCanonicalObligations(fd, defaultScopePolicy())
  doAssert ogr.kind == ogrGenerated, "fixture must generate obligations"
  len(ogr.obligations.value)

# ---------------------------------------------------------------------------
# Suite
# ---------------------------------------------------------------------------

suite "DEBT#423: TheaterGuard / Early-Return Obligation Count Preservation":

  test "(a) generatedObligationVerdict preserves the count with kind ogrGenerated":
    let v = generatedObligationVerdict(3)
    check v.kind == ogrGenerated
    check v.reason == ""
    check v.obligationCount == 3

  test "(b) theaterDetectedVerdict records 'theater_detected' AND preserves the count":
    let v = theaterDetectedVerdict(2)
    check v.kind == ogrIllFormed
    check v.reason == "theater_detected"
    check v.obligationCount == 2
    # Fail-closed terminal: downstream maps ogrIllFormed to not_verifiable.
    check v.obligationCount > 0

  test "(c) BMC-skip early return preserves the generated obligation count":
    let funcDef = makeDivFuncDef("theater_bmcskip")
    doAssert expectedGeneratedCount(funcDef) >= 1,
      "fixture must produce generated obligations"
    let ve = ValidatedIrEntry(entry: makeEntry("theater_bmcskip", bmcSkippable = true),
                              funcDef: funcDef)
    let result = runIrPipeline(ve)

    # BMC pre-check fires AFTER obligation generation — the count must not
    # be zeroed on this early-return path.
    check result.provenance == vpBmcSkipped
    check result.obligationVerdict.kind == ogrGenerated
    check result.obligationVerdict.obligationCount == expectedGeneratedCount(funcDef)
    check result.obligationVerdict.obligationCount > 0

  test "(d) Typed lowering succeeds for obligations-without-postconditions — TheaterGuard does not fire":
    # x / y has NO postcondition (division-only, no clamp pattern).
    # The classic irToSmtScript would emit an empty script, but the
    # typed ProofIR → SMT lowering now produces a valid script from
    # the obligation's typed proposition. The TheaterGuard must NOT
    # fire when typed lowering succeeds — the pipeline proceeds to Z3.
    let funcDef = makeDivFuncDef("theater_target")
    let expected = expectedGeneratedCount(funcDef)
    doAssert expected >= 1, "fixture must generate obligations"
    let ve = ValidatedIrEntry(entry: makeEntry("theater_target", bmcSkippable = false),
                              funcDef: funcDef)
    let result = runIrPipeline(ve)

    # Typed lowering succeeded — TheaterGuard did NOT fire.
    # The pipeline proceeds past the TheaterGuard to the BMC path.
    check result.obligationVerdict.kind == ogrGenerated
    check result.obligationVerdict.obligationCount == expected
    check result.obligationVerdict.obligationCount > 0

  test "(e) standard completion path keeps kind=ogrGenerated with the count":
    # A postcondition makes the SMT script non-empty, so the pipeline completes;
    # the final verdict still carries the generated obligation count.
    var funcDef = makeDivFuncDef("theater_std")
    funcDef.postConditions.add(makeBinOp(boGe, makeVar("x"), makeLit(0)))
    let ve = ValidatedIrEntry(entry: makeEntry("theater_std", bmcSkippable = false),
                              funcDef: funcDef)
    let result = runIrPipeline(ve)

    check result.obligationVerdict.kind == ogrGenerated
    check result.obligationVerdict.reason == ""
    check result.obligationVerdict.obligationCount == expectedGeneratedCount(funcDef)

  test "(f) pre-generation NoApplicable path still reports count 0":
    # No candidates -> ogrNoApplicableObligation (proven absence) — 0 is correct
    # because generation never produced obligations.
    let funcDef = IRFuncDef(name: "plain_add",
                            params: @[makeParam("x"), makeParam("y")],
                            retType: IRType(kind: irtBitVec64),
                            body: makeBinOp(boAdd, makeVar("x"), makeVar("y")))
    let ve = ValidatedIrEntry(entry: makeEntry("plain_add", bmcSkippable = false),
                              funcDef: funcDef)
    let result = runIrPipeline(ve)

    check result.obligationVerdict.kind == ogrNoApplicableObligation
    check result.obligationVerdict.obligationCount == 0