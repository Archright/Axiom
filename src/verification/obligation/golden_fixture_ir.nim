import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Golden fixture IRFuncDefs — the single shared construction of the four
## canonical S1-A golden subjects.
##
## The s1a golden test (tests/unit/test_s1a_lean_golden.nim) and the Judgment
## CAS closure (verification/judgment_cas.nim) must construct the EXACT same
## IR subjects: the test verifies them through the canonical chain, and the
## CAS re-derives their CompletenessEvidence keys (component ⑧ of the judgment
## closure) without re-running any kernel. A second, drifting construction
## would let the recorded keys diverge from the verified subjects, so both
## consumers import these constructors — one definition, one hash space.
##
## CompletenessEvidence key = computeDeterministicCasKey(serializeIRFuncDef(fd))
## — the same scheme the runner cache and the test boundary materializer
## (saveEvidenceArtifact) use.

import core/trusted/axiom_ir
import core/deterministic_cas_key

func gfVar(name: string; ty: IRType): IRExpr {.inline, raises: [].} =
  IRExpr(kind: irVar, varName: name, varType: ty, typ: ty)

func gfLit(v: int64): IRExpr {.inline, raises: [].} =
  IRExpr(kind: irLit, litVal: v, typ: irTypeBitVec64())

func gfBin(op: BinOpKind; l, r: IRExpr): IRExpr {.inline, raises: [].} =
  IRExpr(kind: irBinOp, binOp: op, binLhs: l, binRhs: r, typ: irTypeBool())

func gfIf(c, t, e: IRExpr): IRExpr {.inline, raises: [].} =
  IRExpr(kind: irIf, ifCond: c, ifThen: t, ifElse: e, typ: irTypeBitVec64())

## Mirrors the real production function (normalizeMaxWorkers,
## src/core/orchestrator/orchestrator_api.nim:34):
##   func normalizeMaxWorkers(maxWorkers: int): int {.axiom, axiom:[post:(result >= 1)].} =
##     if maxWorkers > 0: maxWorkers else: 1
func gfNormalizeMaxWorkers*(): IRFuncDef {.raises: [].} =
  let maxW = gfVar("maxWorkers", irTypeBitVec64())
  let body = gfIf(gfBin(boGt, maxW, gfLit(0)), maxW, gfLit(1))
  let post = gfBin(boGe, gfVar("result", irTypeBitVec64()), gfLit(1))
  IRFuncDef(
    name: "normalizeMaxWorkers",
    params: @[IRFuncParam(name: "maxWorkers", ty: irTypeBitVec64())],
    retType: irTypeBitVec64(),
    body: body,
    isRecursive: false,
    preConditions: @[],
    postConditions: @[post])

## Mirrors tests/golden/identity_postcondition.nim:
##   func identityPostcondition(x: int): int {.axiom.[post:(result == x)].} = x
func gfIdentityPostcondition*(): IRFuncDef {.raises: [].} =
  let x = gfVar("x", irTypeBitVec64())
  let post = gfBin(boEq, gfVar("result", irTypeBitVec64()), x)
  IRFuncDef(
    name: "identityPostcondition",
    params: @[IRFuncParam(name: "x", ty: irTypeBitVec64())],
    retType: irTypeBitVec64(),
    body: x,
    isRecursive: false,
    preConditions: @[],
    postConditions: @[post])

## Mirrors tests/golden/sub_postcondition.nim:
##   func subPostcondition(x: int): int {.axiom.[post:(result == x - 1)].} = x - 1
func gfSubPostcondition*(): IRFuncDef {.raises: [].} =
  let x = gfVar("x", irTypeBitVec64())
  let post = gfBin(boEq, gfVar("result", irTypeBitVec64()),
    gfBin(boSub, x, gfLit(1)))
  IRFuncDef(
    name: "subPostcondition",
    params: @[IRFuncParam(name: "x", ty: irTypeBitVec64())],
    retType: irTypeBitVec64(),
    body: gfBin(boSub, x, gfLit(1)),
    isRecursive: false,
    preConditions: @[],
    postConditions: @[post])

## Mirrors tests/golden/mul_div_body.nim:
##   func mulDivRoundtrip(x: int): int {.axiom.[post:(result == (x * 6) div 2)].} =
##     (x * 6) div 2
func gfMulDivRoundtrip*(): IRFuncDef {.raises: [].} =
  let x = gfVar("x", irTypeBitVec64())
  let body = gfBin(boDiv, gfBin(boMul, x, gfLit(6)), gfLit(2))
  let postRhs = gfBin(boDiv, gfBin(boMul, gfVar("x", irTypeBitVec64()), gfLit(6)),
    gfLit(2))
  let post = gfBin(boEq, gfVar("result", irTypeBitVec64()), postRhs)
  IRFuncDef(
    name: "mulDivRoundtrip",
    params: @[IRFuncParam(name: "x", ty: irTypeBitVec64())],
    retType: irTypeBitVec64(),
    body: body,
    isRecursive: false,
    preConditions: @[],
    postConditions: @[post])

func goldenCompletenessKey*(fd: IRFuncDef): string {.raises: [].} =
  ## The runner-cache CAS key of one golden subject — the value the test
  ## boundary materializes (saveEvidenceArtifact) and judgment closure
  ## component ⑧ binds.
  computeDeterministicCasKey(serializeIRFuncDef(fd))

func goldenCompletenessKeys*(): array[4, string] {.raises: [].} =
  ## The four CompletenessEvidence keys in the canonical subject order
  ## (normalizeMaxWorkers, identity, sub, mulDiv) — the closed set judgment
  ## closure component ⑧ re-derives.
  [goldenCompletenessKey(gfNormalizeMaxWorkers()),
   goldenCompletenessKey(gfIdentityPostcondition()),
   goldenCompletenessKey(gfSubPostcondition()),
   goldenCompletenessKey(gfMulDivRoundtrip())]

{.pop.}
