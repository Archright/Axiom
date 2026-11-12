## tests/integration/test_pipeline_stage1_5.nim
## IR Pipeline Stage 1.5 Integration Test — Mock LSP (nil-path)
##
## Exercises the full runIrPipeline → Stage 1.5 → fallback wiring
## WITHOUT a real Lean LSP server. Verifies:
##   1. lspClient=nil + type-level-eligible → vpTypeLevelEncoding (fail-open fallback)
##   2. lspClient=nil + type-level-ineligible → vpNone (falls through to Stage 2-4)
##   3. classifyTypeLevel accepts string/list types with simple bodies (Subtype encoding)
##      and rejects string/list types with complex bodies (irCall, irBinOp, etc.)
##   4. Pipeline completes and populates IrPipelineResult fields
##   5. runAllIrPipelines processes the full registry
##   6. Edge cases: invalid IR, empty registry
##
## This test does NOT require z3 or lean binaries — Z3 absent → z3Sat=false
## (fail-safe), LSP absent → classifyTypeLevel fallback provides fast-path.

import std/[unittest, options, strutils, tables]
import core/trusted/axiom_ir
import core/trusted/ir_to_lean
import core/axiom_pragmas          # RuntimeAxiomEntry, registerAxiom, runtimeAxiomRegistry
import core/sorter/sorter_core_index_base  # sorterNodeId, sorterNodeIdString
import core/orchestrator/orchestrator_request_types  # OrchestrationProofRequest, initOrchestrationProofRequest
import verification/batch_uap/ir_pipeline_runner
import verification/cross_validation  # CrossValidationResult field access
import sieve/trivial_lean_router   # classifyTypeLevel (for eligibility assertions)

# ── Helper constructors (mirrors tests/trusted/test_trivial_lean_router.nim) ──

func makeParam(name: string, ty: IRTypeKind = irtBitVec64): IRFuncParam =
  IRFuncParam(name: name, ty: IRType(kind: ty), constraint: none(IRExpr))

func makeConstrainedParam(name: string, constraint: IRExpr): IRFuncParam =
  IRFuncParam(name: name, ty: IRType(kind: irtBitVec64), constraint: some(constraint))

func makeLit(val: int64): IRExpr =
  IRExpr(kind: irLit, litVal: val)

func makeVar(name: string): IRExpr =
  IRExpr(kind: irVar, varName: name, varType: IRType(kind: irtBitVec64))

func makeBinOp(op: BinOpKind, lhs, rhs: IRExpr): IRExpr =
  IRExpr(kind: irBinOp, binOp: op, binLhs: lhs, binRhs: rhs)

func makeFuncDef(name: string, params: seq[IRFuncParam], body: IRExpr,
                 preConditions: seq[IRExpr] = @[],
                 isRecursive: bool = false,
                 retType: IRType = IRType(kind: irtBitVec64)): IRFuncDef =
  IRFuncDef(name: name, params: params,
            retType: retType, body: body,
            isRecursive: isRecursive, preConditions: preConditions)

# ── Entry constructors ──

func makeEntry(name: string, irSerialized: string): RuntimeAxiomEntry =
  RuntimeAxiomEntry(name: name, irSerialized: irSerialized,
                    smtSource: "", leanSource: "")

func makeEntryFromFuncDef(f: IRFuncDef): RuntimeAxiomEntry =
  makeEntry(f.name, serializeIRFuncDef(f))

func makeValidatedEntry(f: IRFuncDef): ValidatedIrEntry =
  ValidatedIrEntry(entry: makeEntryFromFuncDef(f), funcDef: f)

# ── Test fixtures ──

# Scenario A: Type-level-eligible (constrained, non-recursive, simple body)
let eligibleFuncDef = makeFuncDef(
  "clamp",
  @[makeConstrainedParam("x", makeBinOp(boLt, makeVar("x"), makeLit(100)))],
  makeVar("x"))

# Scenario B: Type-level-ineligible (no constraints → classifyTypeLevel=false)
let ineligibleNoConstraint = makeFuncDef(
  "plain_add",
  @[makeParam("x"), makeParam("y")],
  makeBinOp(boAdd, makeVar("x"), makeVar("y")))

# Scenario C: Type-level-ineligible (recursive → classifyTypeLevel=false)
let ineligibleRecursive = makeFuncDef(
  "factorial",
  @[makeConstrainedParam("n", makeBinOp(boLt, makeVar("n"), makeLit(64)))],
  IRExpr(kind: irRecCall, recArgs: @[makeVar("n")]),
  isRecursive = true)

# Scenario D: Type-level-ineligible (irCall in body → classifyTypeLevel=false)
let ineligibleCall = makeFuncDef(
  "delegating",
  @[makeConstrainedParam("x", makeBinOp(boLt, makeVar("x"), makeLit(100)))],
  IRExpr(kind: irCall, callName: "external_fn",
         callArgs: @[makeVar("x")]))

# ── Save/restore global registry state ──
var savedRegistry: seq[RuntimeAxiomEntry]

proc saveRegistry() =
  savedRegistry = runtimeAxiomRegistry

proc restoreRegistry() =
  runtimeAxiomRegistry = savedRegistry

# ── Test Suite ──

suite "IR Pipeline Stage 1.5 Integration":

  setup:
    saveRegistry()
    runtimeAxiomRegistry = @[]

  teardown:
    restoreRegistry()

  # ── 1. Nil lspClient + type-level-eligible → fallback provenance ──────────

  test "nil lspClient with type-level-eligible IR → provenance vpBmcSkipped (fallback: no postconditions)":
    # classifyTypeLevel(eligibleFuncDef) == true, lspClient is nil
    # Without postconditions, irToSmtScript returns empty → vpBmcSkipped.
    doAssert classifyTypeLevel(eligibleFuncDef) == true,
      "Sanity: fixture must be type-level-eligible"

    let entry = makeValidatedEntry(eligibleFuncDef)
    let result = runIrPipeline(entry, lspClient = nil)

    check result.funcName == "clamp"
    check result.provenance == vpBmcSkipped  # no postconditions → empty SMT
    check result.success == true             # skip is not a failure
    check result.crossValidation.consistent == false

  test "nil lspClient with type-level-ineligible IR (no constraints) → provenance vpBmcSkipped":
    doAssert classifyTypeLevel(ineligibleNoConstraint) == false,
      "Sanity: fixture must NOT be type-level-eligible"

    let entry = makeValidatedEntry(ineligibleNoConstraint)
    let result = runIrPipeline(entry, lspClient = nil)

    check result.funcName == "plain_add"
    check result.provenance == vpBmcSkipped  # no postconditions → empty SMT

  test "nil lspClient with recursive IR → provenance vpNone":
    doAssert classifyTypeLevel(ineligibleRecursive) == false,
      "Sanity: recursive fixture must NOT be type-level-eligible"

    let entry = makeValidatedEntry(ineligibleRecursive)
    let result = runIrPipeline(entry, lspClient = nil)

    check result.funcName == "factorial"
    check result.provenance == vpNone  # no LSP, falls through → irToSmtScript succeeds for recursive

  test "nil lspClient with irCall body → provenance vpBmcSkipped":
    doAssert classifyTypeLevel(ineligibleCall) == false,
      "Sanity: irCall fixture must NOT be type-level-eligible"

    let entry = makeValidatedEntry(ineligibleCall)
    let result = runIrPipeline(entry, lspClient = nil)

    check result.funcName == "delegating"
    check result.provenance == vpBmcSkipped  # no postconditions → empty SMT

  # ── 2. Pipeline completes and populates all IrPipelineResult fields ────────

  test "pipeline returns result for simple function (no postconditions → vpBmcSkipped)":
    let entry = makeValidatedEntry(ineligibleNoConstraint)
    let result = runIrPipeline(entry, lspClient = nil)

    check result.funcName == "plain_add"
    check result.irDigest.len > 0
    check result.provenance == vpBmcSkipped   # no postconditions → empty SMT
    check result.success == true

  # ── 3. Edge case: invalid/empty serialized IR → sentinel failure ───────────

  test "invalid serialized IR → success=false, provenance=vpNone":
    let rawEntry = makeEntry("garbage_func", "NOT_VALID_IR")
    let def = deserializeIRFuncDef("NOT_VALID_IR")
    let entry = ValidatedIrEntry(entry: rawEntry, funcDef: def)
    let result = runIrPipeline(entry, lspClient = nil)

    check result.funcName == "garbage_func"
    check result.success == false
    check result.provenance == vpNone

  test "empty serialized IR → success=false, provenance=vpNone":
    let rawEntry = makeEntry("empty_func", "")
    let def = deserializeIRFuncDef("")
    let entry = ValidatedIrEntry(entry: rawEntry, funcDef: def)
    let result = runIrPipeline(entry, lspClient = nil)

    check result.funcName == "empty_func"
    check result.success == false
    check result.provenance == vpNone

  # ── 4. runAllIrPipelines integration ───────────────────────────────────────

  {.push warning[Deprecated]: off.}

  test "runAllIrPipelines with empty registry → empty result":
    let results = runAllIrPipelines(lspClient = nil)
    check results.len == 0

  test "runAllIrPipelines processes all registered entries":
    registerAxiom("func_a", serializeIRFuncDef(ineligibleNoConstraint), "", "", "")
    registerAxiom("func_b", serializeIRFuncDef(eligibleFuncDef), "", "", "")
    registerAxiom("func_c", serializeIRFuncDef(ineligibleRecursive), "", "", "")

    let results = runAllIrPipelines(lspClient = nil)
    check results.len == 3

    # Verify all entries were processed (each has a funcName)
    var names: seq[string]
    for r in results:
      names.add(r.funcName)
    check "func_a" in names
    check "func_b" in names
    check "func_c" in names

    # Without LSP, entries without postConditions go through → vpBmcSkipped
    # (func_a has no postConditions, func_c is recursive with no postConditions)
    for r in results:
      check r.provenance in {vpBmcSkipped, vpNone}

  {.pop.}

  # ── 5. String/list type acceptance (Subtype encoding) ────────────────────

  test "string parameter with simple body → classifyTypeLevel accepts":
    let stringParam = IRFuncParam(
      name: "s", ty: IRType(kind: irtString), constraint: none(IRExpr))
    let stringFunc = makeFuncDef(
      "process_str",
      @[stringParam],
      makeVar("s"),
      preConditions = @[makeLit(1)])
    doAssert classifyTypeLevel(stringFunc) == true,
      "string param with simple body must be accepted by classifyTypeLevel"

    let entry = makeValidatedEntry(stringFunc)
    let result = runIrPipeline(entry, lspClient = nil)
    check result.funcName == "process_str"
    check result.provenance == vpBmcSkipped  # string param → isBmcSkippable

  test "list parameter with simple body → classifyTypeLevel accepts":
    let listParam = IRFuncParam(
      name: "xs", ty: IRType(kind: irtList, elemType: irTypeBitVec64()),
      constraint: none(IRExpr))
    let listFunc = makeFuncDef(
      "process_list",
      @[listParam],
      makeVar("xs"),
      preConditions = @[makeLit(1)])
    doAssert classifyTypeLevel(listFunc) == true,
      "list param with simple body must be accepted by classifyTypeLevel"

    let entry = makeValidatedEntry(listFunc)
    let result = runIrPipeline(entry, lspClient = nil)
    check result.funcName == "process_list"
    check result.provenance == vpBmcSkipped  # no postconditions → empty SMT

  test "string return type with simple body → classifyTypeLevel accepts":
    let stringRetFunc = makeFuncDef(
      "get_name",
      @[IRFuncParam(name: "x", ty: irTypeBitVec64(),
                    constraint: some(makeLit(1)))],
      makeVar("x"),
      retType = IRType(kind: irtString))
    doAssert classifyTypeLevel(stringRetFunc) == true,
      "string return type with simple body must be accepted"

  test "string parameter with complex body (irCall) → classifyTypeLevel rejects":
    let stringParam = IRFuncParam(
      name: "s", ty: IRType(kind: irtString), constraint: none(IRExpr))
    let callBody = IRExpr(kind: irCall, callName: "external",
                          callArgs: @[makeVar("s")])
    let stringFunc = makeFuncDef(
      "complex_str",
      @[stringParam],
      callBody,
      preConditions = @[makeLit(1)])
    doAssert classifyTypeLevel(stringFunc) == false,
      "string param with irCall body must be rejected"

  test "string parameter with complex body (irBinOp) → classifyTypeLevel rejects":
    let stringParam = IRFuncParam(
      name: "s", ty: IRType(kind: irtString), constraint: none(IRExpr))
    let binopBody = makeBinOp(boAdd, makeVar("s"), makeLit(0))
    let stringFunc = makeFuncDef(
      "binop_str",
      @[stringParam],
      binopBody,
      preConditions = @[makeLit(1)])
    doAssert classifyTypeLevel(stringFunc) == false,
      "string param with irBinOp body must be rejected (stricter check)"

  # ── 6. verify IrPipelineResult type completeness ───────────────────────────

  test "IrPipelineResult has expected enum variants":
    # Compile-time verification that all provenance variants are accessible
    let v1: VerificationProvenance = vpNone
    let v2: VerificationProvenance = vpZ3Bmc
    let v3: VerificationProvenance = vpTypeLevelEncoding
    let v4: VerificationProvenance = vpDual
    check v1 == vpNone
    check v2 == vpZ3Bmc
    check v3 == vpTypeLevelEncoding
    check v4 == vpDual

  # ── 7. classifyTypeLevel + pipeline wiring consistency ─────────────────────

  test "classifyTypeLevel eligibility vs pipeline behavior with nil LSP":
    # Without LSP, both eligible and ineligible functions go through
    # the standard Stage 2-4 pipeline (no fast-path early return).
    let eligible = makeValidatedEntry(eligibleFuncDef)
    let ineligible = makeValidatedEntry(ineligibleNoConstraint)

    let rEligible = runIrPipeline(eligible, lspClient = nil)
    let rIneligible = runIrPipeline(ineligible, lspClient = nil)

    # Both go through Stage 2-4 — without postConditions both get vpBmcSkipped
    check rEligible.provenance == vpBmcSkipped  # no postconditions → empty SMT
    check rEligible.success == true

    check rIneligible.provenance == vpBmcSkipped  # no postconditions → empty SMT
    check rIneligible.success == true

  # ── 7. Task-Injected Pipeline: runIrPipelinesFor ─────────────────────────

  test "runIrPipelinesFor empty seq → empty result":
    var memoCache: Table[string, IrPipelineResult]
    let results = runIrPipelinesFor(@[], memoCache, lspClient = nil)
    check results.len == 0

  test "runIrPipelinesFor bounded — 5 entries registered, pass 3 → get 3 results":
    # Register 5 entries in the global registry
    registerAxiom("bounded_a", serializeIRFuncDef(ineligibleNoConstraint), "", "", "")
    registerAxiom("bounded_b", serializeIRFuncDef(eligibleFuncDef), "", "", "")
    registerAxiom("bounded_c", serializeIRFuncDef(ineligibleRecursive), "", "", "")
    registerAxiom("bounded_d", serializeIRFuncDef(ineligibleCall), "", "", "")
    registerAxiom("bounded_e", serializeIRFuncDef(ineligibleNoConstraint), "", "", "")

    # Only pass 3 entries (bounded collection verification) as ValidatedIrEntry
    let subset = @[
      ValidatedIrEntry(entry: runtimeAxiomRegistry[0], funcDef: deserializeIRFuncDef(runtimeAxiomRegistry[0].irSerialized)),
      ValidatedIrEntry(entry: runtimeAxiomRegistry[2], funcDef: deserializeIRFuncDef(runtimeAxiomRegistry[2].irSerialized)),
      ValidatedIrEntry(entry: runtimeAxiomRegistry[4], funcDef: deserializeIRFuncDef(runtimeAxiomRegistry[4].irSerialized)),
    ]
    var memoCache: Table[string, IrPipelineResult]
    let results = runIrPipelinesFor(subset, memoCache, lspClient = nil)

    check results.len == 3
    check results[0].funcName == "bounded_a"
    check results[1].funcName == "bounded_c"
    # bounded_e has the same funcDef as bounded_a — CAS cache returns bounded_a result
    check results[2].funcName == "bounded_a"

  # ── 8. Task-Injected Pipeline: selectEntriesFor ──────────────────────────

  test "selectEntriesFor topology order preservation":
    # Set up registry and lookup
    runtimeAxiomRegistry = @[]
    registerAxiom("node_alpha", serializeIRFuncDef(ineligibleNoConstraint), "", "", "")
    registerAxiom("node_beta", serializeIRFuncDef(eligibleFuncDef), "", "", "")
    registerAxiom("node_gamma", serializeIRFuncDef(ineligibleRecursive), "", "", "")
    initRegistryLookup()

    # Create requests in a specific topology order: beta, gamma, alpha
    var requests: seq[OrchestrationProofRequest]
    requests.add(initOrchestrationProofRequest(
      SorterNodeId("node_beta"), "", 0, 0))
    requests.add(initOrchestrationProofRequest(
      SorterNodeId("node_gamma"), "", 0, 0))
    requests.add(initOrchestrationProofRequest(
      SorterNodeId("node_alpha"), "", 0, 0))

    let report = selectEntriesFor(requests)

    # All 3 found — no skips
    check report.selected.len == 3
    check report.skippedCount == 0

    # Order must match input: beta, gamma, alpha
    check report.selected[0].entry.name == "node_beta"
    check report.selected[1].entry.name == "node_gamma"
    check report.selected[2].entry.name == "node_alpha"

  test "selectEntriesFor structural anomaly — missing nodeId":
    # Set up registry with only 2 entries
    runtimeAxiomRegistry = @[]
    registerAxiom("present_a", serializeIRFuncDef(ineligibleNoConstraint), "", "", "")
    registerAxiom("present_b", serializeIRFuncDef(eligibleFuncDef), "", "", "")
    initRegistryLookup()

    # Create requests: one existing, one missing, one existing
    var requests: seq[OrchestrationProofRequest]
    requests.add(initOrchestrationProofRequest(
      SorterNodeId("present_a"), "", 0, 0))
    requests.add(initOrchestrationProofRequest(
      SorterNodeId("DOES_NOT_EXIST"), "", 0, 0))
    requests.add(initOrchestrationProofRequest(
      SorterNodeId("present_b"), "", 0, 0))

    let report = selectEntriesFor(requests)

    # Only 2 selected, 1 skipped
    check report.selected.len == 2
    check report.skippedCount == 1
    check report.skippedNodes.len == 1
    check "DOES_NOT_EXIST" in report.skippedNodes

    # Selected entries are the two that exist
    check report.selected[0].entry.name == "present_a"
    check report.selected[1].entry.name == "present_b"

  # ── 9. Regression: crossValidation not claiming consistent on BMC-skip ────

  test "BMC-skip result has crossValidation.consistent == false":
    # A string-returning function triggers BMC-skip. That path must NOT
    # fabricate crossValidation(consistent: true).
    let skipFunc = makeFuncDef(
      "string_ret",
      @[makeParam("x")],
      makeVar("x"),
      preConditions = @[makeLit(0)],
      retType = IRType(kind: irtString))
    let entry = makeValidatedEntry(skipFunc)
    let result = runIrPipeline(entry, lspClient = nil)
    check result.provenance == vpBmcSkipped
    check result.crossValidation.consistent == false
    check result.crossValidation.z3Result.len == 0
    check result.crossValidation.leanResult.len == 0

  test "tautology result has crossValidation.consistent == false":
    # A trivially-true precondition triggers tautology rejection.
    # Must NOT claim consistent cross-validation.
    let tautFunc = makeFuncDef(
      "trivially_true",
      @[makeConstrainedParam("x", makeLit(1))],
      makeVar("x"))
    let entry = makeValidatedEntry(tautFunc)
    let result = runIrPipeline(entry, lspClient = nil)
    check result.provenance == vpBmcSkipped
    check result.crossValidation.consistent == false

  # ── 10. Regression: routeToTypeLevel propagates LSP errors ────────────────
  # Tests through the pipeline: when LSP returns err, the pipeline must
  # fall back to Stage 2-4 (vpNone) rather than fabricating success.
  # This is exercised by runIrPipeline with a nil lspClient (no LSP available).

  test "no-LSP fallback does NOT fabricate vpTypeLevelEncoding success":
    # Without LSP, a classifyTypeLevel-eligible function must fall through
    # to the standard pipeline rather than fabricating a vpTypeLevelEncoding result.
    let eligible = makeValidatedEntry(eligibleFuncDef)
    let result = runIrPipeline(eligible, lspClient = nil)

    check result.provenance != vpTypeLevelEncoding
    # Without postConditions, empty-SMT path → vpBmcSkipped
    check result.provenance == vpBmcSkipped
    check result.success == true  # skip = not a failure
