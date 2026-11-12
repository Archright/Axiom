import std/sequtils
import std/strutils
import core/trusted/layer_declaration
import core/trusted/axiom_ir_helpers
import core/trusted/specification_artifact
import core/trusted/evidence_capture
import core/trusted/dependency_snapshot

proc makeFuncDef(name: string, post: IRExpr): IRFuncDef =
  let bv64 = irTypeBitVec64()
  let x = irVar("x", bv64)
  result = irFuncDef(
    name = name,
    params = @[("x", bv64)],
    ret = bv64,
    body = x
  )
  result.postConditions = @[post]

proc main() =
  echo "=== Phase-2 Evidence Capture — Negative Trust ==="

  # 1. specId is NOT preserved when postConditions differ (same funcName, diff post)
  block:
    let bv64 = irTypeBitVec64()
    let x = irVar("x", bv64)
    let result = irVar("result", bv64)

    let postA = irBinOp(boGe, result, x)
    let postB = irBinOp(boGe, result, irLit(0))

    let f1 = makeFuncDef("f", postA)
    let f2 = makeFuncDef("f", postB)

    let s1 = captureSpecification(f1, soCanonicalDerived, "v1")
    let s2 = captureSpecification(f2, soCanonicalDerived, "v1")

    doAssert s1.specIdentity != s2.specIdentity,
      "specId must differ when postConditions differ"
    doAssert s1.canonicalSpecIR != s2.canonicalSpecIR,
      "canonicalSpecIR must differ when postConditions differ"
    echo "  OK: diff postConditions -> diff specIdentity"

  # 2. specId changes when ruleVersion or origin changes
  block:
    let f = makeFuncDef("g", irBinOp(boGe, irVar("result", irTypeBitVec64()), irVar("x", irTypeBitVec64())))

    let sCanonical = captureSpecification(f, soCanonicalDerived, "v1")
    let sMined = captureSpecification(f, soMined, "v1")
    let sV2 = captureSpecification(f, soCanonicalDerived, "v2")

    doAssert sCanonical.specIdentity != sMined.specIdentity,
      "specId must differ: soMined vs soCanonicalDerived"
    doAssert sCanonical.specIdentity != sV2.specIdentity,
      "specId must differ: ruleVersion v1 vs v2"
    doAssert sMined.specIdentity != sV2.specIdentity,
      "specId must differ: soMined+v1 vs soCanonicalDerived+v2"
    echo "  OK: origin/ruleVersion change -> specId changes"

  # 3. DependencySnapshot.snapshotHash sensitivity and order-insensitivity
  block:
    # (a) dependency list change -> hash differs
    let d1 = captureDependencySnapshot(@["a", "b"], "src")
    let d2 = captureDependencySnapshot(@["a", "c"], "src")
    doAssert d1.snapshotHash != d2.snapshotHash,
      "diff deps must yield diff snapshotHash"

    # (b) sourceScope change -> hash differs
    let d3 = captureDependencySnapshot(@["a", "b"], "src")
    let d4 = captureDependencySnapshot(@["a", "b"], "lib")
    doAssert d3.snapshotHash != d4.snapshotHash,
      "diff sourceScope must yield diff snapshotHash"

    # (c) same deps in different order -> identical hash (order-insensitive)
    let d5 = captureDependencySnapshot(@["b", "a"], "src")
    let d6 = captureDependencySnapshot(@["a", "b"], "src")
    doAssert d5.snapshotHash == d6.snapshotHash,
      "same deps in diff order must yield identical snapshotHash"
    echo "  OK: snapshotHash sensitive to deps/scope, order-insensitive"

  # 4. Same funcDef twice -> identical canonicalSpecIR + specIdentity (idempotent)
  block:
    let f = makeFuncDef("h", irBinOp(boGe, irVar("result", irTypeBitVec64()), irVar("x", irTypeBitVec64())))

    let s1 = captureSpecification(f, soCanonicalDerived, "v1")
    let s2 = captureSpecification(f, soCanonicalDerived, "v1")

    doAssert s1.specIdentity == s2.specIdentity,
      "specIdentity must be identical for same funcDef"
    doAssert s1.canonicalSpecIR == s2.canonicalSpecIR,
      "canonicalSpecIR must be identical for same funcDef"
    doAssert s1.rawPostConditions.len == s2.rawPostConditions.len,
      "raw postConditions count must match"
    echo "  OK: same funcDef -> identical canonicalSpecIR + specIdentity"

  # 5. Grep check: Phase2a/2c encodings are NOT reverted
  block:
    doAssert binOpSymbol(boRemU) == "bvurem",
      "boRemU must encode as bvurem (not reverted)"
    doAssert binOpSymbol(boUnsupported) == "UNSUPPORTED",
      "boUnsupported must encode as UNSUPPORTED"
    echo "  OK: Phase2a/2c encodings preserved (boRemU->bvurem, boUnsupported->UNSUPPORTED)"

  echo "=== Phase-2 Evidence Capture Negative Trust OK ==="

main()