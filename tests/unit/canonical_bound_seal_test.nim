import std/[unittest, strutils, sequtils, options]
import ../../src/core/results
import ../../src/core/trusted/axiom_ir
import ../../src/core/trusted/axiom_ir_helpers
import ../../src/verification/obligation/canonical_verification
import ../../src/verification/obligation/verification_decision_authority

## Canonical bound-seal gates (I6 takeover of agent-9's wiring).
##
## The §2.1a subject binding gates the canonical kernel run (Step 3b BEFORE
## Step 5): an unmeasurable or non-corresponding binding component yields NO
## bound obligation identity, so no verified certificate is possible. These
## tests drive the fail-closed gates through the public
## executeCanonicalVerification entry against a REAL in-repo subject module
## (git ref + tree merkle measure against the CWD repo) — all refusals happen
## before the kernel, so no Lean run is needed here.

proc mkVar(name: string; ty: IRType): IRExpr =
  IRExpr(kind: irVar, varName: name, varType: ty, typ: ty)

proc mkEq(l, r: IRExpr): IRExpr =
  IRExpr(kind: irBinOp, binOp: boEq, binLhs: l, binRhs: r, typ: irTypeBool())

proc identityLikeFd(name: string): IRFuncDef =
  let x = mkVar("x", irTypeBitVec64())
  IRFuncDef(
    name: name,
    params: @[IRFuncParam(name: "x", ty: irTypeBitVec64())],
    retType: irTypeBitVec64(),
    body: x,
    isRecursive: false,
    preConditions: @[],
    postConditions: @[mkEq(mkVar("result", irTypeBitVec64()), x)]
  )

func fabricatedParseBound(forName: string; agreed: bool): SubjectParseBoundComponents =
  ## Structurally valid components (64-hex digests) with a controlled agreed
  ## flag — the gate under test is the binding logic, not the measurers.
  SubjectParseBoundComponents(
    pnodeCanonicalV2Digest: "a".repeat(64),
    eaNimDigest: "b".repeat(64),
    eaLeanDigest: "c".repeat(64),
    eaIrcheckBinaryDigest: "d".repeat(64),
    eaAgreed: agreed,
    measuredForFuncName: forName)

suite "Canonical bound seal — §2.1a gates refuse before the kernel":

  test "default parse-bound components are unmeasured (parseComponentsMeasured=false)":
    check parseComponentsMeasured(SubjectParseBoundComponents()) == false

  test "unmeasured parse-bound → fail-closed with the reason carried (DEBT#490)":
    let r = executeCanonicalVerification(
      identityLikeFd("identityPostcondition"),
      "tests/golden/identity_postcondition.nim",
      "identityPostcondition")
    check r.success == false
    check r.verdict != vdVerified
    check r.canonicalEvidence.isNone
    check r.sealError.contains("unmeasured")

  test "correspondence gate — components measured for ANOTHER funcDef are refused":
    let r = executeCanonicalVerification(
      identityLikeFd("boundOtherName"),
      "tests/golden/identity_postcondition.nim",
      "boundOtherName",
      parseBound = fabricatedParseBound(forName = "identityPostcondition", agreed = true))
    check r.success == false
    check r.verdict != vdVerified
    check r.canonicalEvidence.isNone
    check r.sealError.contains("not this funcDef")

  test "EA disagreement is measurable but never verifiable":
    let r = executeCanonicalVerification(
      identityLikeFd("identityPostcondition"),
      "tests/golden/identity_postcondition.nim",
      "identityPostcondition",
      parseBound = fabricatedParseBound(forName = "identityPostcondition", agreed = false))
    check r.success == false
    check r.verdict != vdVerified
    check r.canonicalEvidence.isNone
    check r.sealError.contains("extraction agreement mismatch")
