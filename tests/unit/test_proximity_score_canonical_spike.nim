import std/[os, options, strutils]
import ../../src/core/trusted/axiom_ir
import ../../src/core/trusted/axiom_ir_helpers
import ../../src/core/deterministic_cas_key
import ../../src/core/trusted/semantic_fact_types
import ../../src/infrastructure/evidence_artifact_io
import ../../src/infrastructure/external_ir_materializer
import ../../src/verification/obligation/canonical_verification
import ../../src/verification/obligation/kernel_acceptance_authority
import ../../src/verification/obligation/verification_decision_authority

## Phase 0 spike: can proximityScore reach the canonical Lean kernel once a
## measured CompletenessEvidence artifact is present? This is a diagnostic,
## not a product assertion. It prints the exact verdict/sealError.

proc mkVar(name: string; ty: IRType): IRExpr =
  IRExpr(kind: irVar, varName: name, varType: ty, typ: ty)

proc mkLit(v: int64): IRExpr =
  IRExpr(kind: irLit, litVal: v, typ: irTypeBitVec64())

proc mkBin(op: BinOpKind; l, r: IRExpr): IRExpr =
  IRExpr(kind: irBinOp, binOp: op, binLhs: l, binRhs: r, typ: irTypeBool())

proc mkArith(op: BinOpKind; l, r: IRExpr): IRExpr =
  IRExpr(kind: irBinOp, binOp: op, binLhs: l, binRhs: r, typ: irTypeBitVec64())

let bv64 = irTypeBitVec64()

proc proximityFuncDef(): IRFuncDef =
  let i = mkVar("interfaceDistance", bv64)
  let n = mkVar("nodeCount", bv64)
  let body = IRExpr(
    kind: irIf,
    ifCond: mkBin(boGt, i, n),
    ifThen: mkLit(0),
    ifElse: mkArith(boDiv, mkLit(60), mkArith(boAdd, i, mkLit(1))),
    typ: bv64)
  let post = mkBin(boAnd,
    mkBin(boGe, mkVar("result", bv64), mkLit(0)),
    mkBin(boLe, mkVar("result", bv64), mkLit(60)))
  IRFuncDef(
    name: "proximityScore",
    params: @[IRFuncParam(name: "interfaceDistance", ty: bv64),
              IRFuncParam(name: "nodeCount", ty: bv64)],
    retType: bv64,
    body: body,
    isRecursive: false,
    preConditions: @[mkBin(boGe, i, mkLit(0)), mkBin(boGe, n, mkLit(0))],
    postConditions: @[post])

proc materializeCompletenessFor(fd: IRFuncDef; sourcePath: string) =
  ## Test-boundary dual-write (Phase 1A): the legacy 5-field artifact plus the
  ## authenticated strict CompletenessBinding sibling, both at the runner-cache
  ## anchor. The capture measures the CWD repo as subject root
  ## (contentCarried=false — the same resolution rule executeCanonicalVerification
  ## applies to these path-resolved fixtures), so the strict-first reader
  ## recomputes the recorded sourceIdentity exactly.
  let key = computeDeterministicCasKey(serializeIRFuncDef(fd))
  let evidence = CompletenessEvidence(
    translationLossFree: true,
    bindingUniverseComplete: true,
    opaqueExpansionStatus: "none",
    sourceBindingCount: 2,
    irBindingCount: 2)
  saveEvidenceArtifact(key, evidence)
  let capture = measureCompletenessSourceCapture("", sourcePath,
    readFile(sourcePath), contentCarried = false)
  discard saveCompletenessEvidenceDual(key, fd, capture, evidence)

when isMainModule:
  let fd = proximityFuncDef()
  let rendered = renderLeanForFuncDef(fd)
  doAssert rendered.len > 0
  doAssert "by_cases" in rendered
  doAssert "Int.ediv_le_self" in rendered
  let sourcePath = "src/core/topology/topology_dependency.nim"
  materializeCompletenessFor(fd, sourcePath)
  let bound = measureParseBoundComponents(readFile(sourcePath), "proximityScore")
  doAssert bound.eaAgreed, bound.eaDetail
  let r = executeCanonicalVerification(fd, sourcePath, "proximityScore",
    parseBound = bound)
  doAssert r.success
  doAssert r.verdict == vdVerified
  doAssert r.evidence == "lean_kernel_accepted"
  doAssert r.canonicalEvidence.isSome
  let e = r.canonicalEvidence.get()
  ## Phase 1A: the sealed evidence carries the authenticated strict binding
  ## identity (the dual-write above landed a measurable capture).
  doAssert cleCompletenessEvidenceKey(e).len > 0
  doAssert cleCompletenessBindingDigest(e).len == 64
  doAssert cleCompletenessPayloadDigest(e).len == 64
  echo "proximityScore canonical division proof: PASS"
