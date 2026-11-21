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
## No z3/lean binaries are required for (a)-(f): those assertions only touch
## obligation verdicts. Test (g) exercises the real canonical-success return
## and skips when the pinned Lean toolchain or the built ircheck extractor is
## absent.

import std/[unittest, options, os]
import core/trusted/axiom_ir
import core/trusted/contract_synthesis
import core/trusted/verification_result_types
import core/trusted/semantic_fact_types
import core/axiom_pragmas
import core/deterministic_cas_key
import infrastructure/evidence_artifact_io
import infrastructure/external_ir_materializer
import verification/obligation/obligation_ir
import verification/obligation/canonical_obligation_generator
import verification/obligation/canonical_verification
import verification/obligation/golden_fixture_ir
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

proc materializeCanonicalCompleteness(fd: IRFuncDef; sourcePath: string): bool =
  ## Test-boundary producer role for the §2.1a artifacts the canonical chain
  ## requires (same materialization as tests/unit/test_s1a_lean_golden.nim).
  let key = computeDeterministicCasKey(serializeIRFuncDef(fd))
  let evidence = CompletenessEvidence(
    translationLossFree: true,
    bindingUniverseComplete: true,
    opaqueExpansionStatus: "none",
    sourceBindingCount: 1,
    irBindingCount: 1)
  saveEvidenceArtifact(key, evidence)
  let capture = measureCompletenessSourceCapture("", sourcePath,
    readFile(sourcePath), contentCarried = false)
  saveCompletenessEvidenceDual(key, fd, capture, evidence)

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

  test "(g) canonical-success early return preserves the generated obligation count":
    # DEBT#423 pre-fix behavior: the canonical-success return sits inside the
    # ogrGenerated dispatch, BEFORE the old count assignment, so it reported
    # obligationCount=0 although obligations were generated. This drives the
    # real Lean kernel lane (the same golden subject as S1-A) and asserts the
    # canonical return itself carries the generation-boundary count.
    let sourcePath = "tests/golden/sub_postcondition.nim"
    let toolchainReady = findExe("lean").len > 0 and findExe("lake").len > 0 and
      fileExists("proofs/.lake/build/bin/ircheck")
    if not toolchainReady:
      skip()
    else:
      let funcDef = gfSubPostcondition()
      let expected = expectedGeneratedCount(funcDef)
      check expected == 1
      check materializeCanonicalCompleteness(funcDef, sourcePath) == true
      let bound = measureParseBoundComponents(readFile(sourcePath), funcDef.name)
      var entry = makeEntry(funcDef.name, bmcSkippable = false)
      entry.sourcePath = sourcePath
      entry.isKernel = true
      let ve = ValidatedIrEntry(entry: entry, funcDef: funcDef,
                                parseBound: bound)
      let result = runIrPipeline(ve)

      # Reason pins the canonical-success return, not a fall-through path.
      check result.obligationVerdict.reason == "canonicalVerified"
      check result.obligationVerdict.obligationCount == expected
      check result.obligationVerdict.obligationCount > 0