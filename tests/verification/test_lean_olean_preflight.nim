## Issue #221 regression: the Rust reference-extractor SOURCE path must fail
## with an actionable "run `lake build` in proofs/" reason when the Lean
## project oleans are unbuilt — a DISTINCT environment classification, never
## "reference extractor rejected the wire".
##
## Deterministic: the third block reaches the real call site
## (runRustExtractionAgreement) but the preflight returns before any
## lake/Lean process is spawned, so no toolchain is required.

import std/[os, strutils]
import core/trusted/rust_canonical
import verification/extraction_agreement
import verification/rust_extraction_agreement

proc fixtureCanonical(): RustCanonical =
  ## Minimal in-grammar straight-line canonical (`_0 = a; return`).
  RustCanonical(
    modulePath: "axiom_issue221::probe",
    sourceIdentity: "issue221-preflight-fixture",
    funcName: "identity",
    returnPlace: "_0",
    failureMode: rfmNoneObserved,
    params: @[RustParam(name: "a", ty: rustU8Type())],
    retType: rustU8Type(),
    body: @[
      RustStmt(kind: rskAssign, dest: "_0",
               rvalue: RustRvalue(kind: rrvUse,
                 operand: RustOperand(kind: ropCopy, place: "a"))),
      RustStmt(kind: rskReturn)
    ])

proc main() =
  echo "=== Lean olean preflight (issue #221) ==="
  let tmp = getTempDir() / ("axiom_olean_preflight_" & $getCurrentProcessId())
  removeDir(tmp)
  let proofs = tmp / "proofs"
  createDir(proofs / "IR")
  writeFile(proofs / "IR" / "RustReferenceExtractor.lean", "-- fixture\n")
  defer:
    removeDir(tmp)

  # 1. Missing .lake/build → actionable reason naming artifact + command.
  block:
    let reason = leanOleanPreflightReason(proofs)
    doAssert reason.len > 0, "missing olean must produce a reason"
    doAssert "lake build" in reason, "reason must name `lake build`: " & reason
    doAssert "IR/AxiomIRExpr.olean" in reason,
      "reason must name the missing artifact: " & reason
    echo "  PASS: missing olean -> " & reason

  # 2. Present IR/AxiomIRExpr.olean → empty reason (preflight passes).
  block:
    let oleanDir = proofs / ".lake" / "build" / "lib" / "lean" / "IR"
    createDir(oleanDir)
    writeFile(oleanDir / "AxiomIRExpr.olean", "fixture")
    doAssert leanOleanPreflightReason(proofs).len == 0,
      "present olean must pass the preflight"
    echo "  PASS: present olean -> empty reason"

  # 3. Real call site: the differential maps the preflight to a DISTINCT
  #    classification, never the "rejected the wire" reason class. The
  #    prebuilt-worker override is cleared so the source-run path is taken.
  block:
    removeDir(proofs / ".lake")
    let hadOverride = existsEnv("AXIOM_RUSTCHECK_CMD")
    let prior = getEnv("AXIOM_RUSTCHECK_CMD", "")
    delEnv("AXIOM_RUSTCHECK_CMD")
    defer:
      if hadOverride:
        putEnv("AXIOM_RUSTCHECK_CMD", prior)
    let r = runRustExtractionAgreement(fixtureCanonical(), rcheckExe = "",
                                       projectRoot = tmp)
    doAssert r.verdict == eaReferenceError,
      "expected eaReferenceError, got " & $r.verdict & ": " & r.reason
    doAssert "leanOleanMissing" in r.reason,
      "reason must carry the distinct classification: " & r.reason
    doAssert "lake build" in r.reason,
      "reason must be actionable: " & r.reason
    doAssert "rejected the wire" notin r.reason,
      "environment deficiency must not look like an extractor rejection: " & r.reason
    echo "  PASS: call site -> " & r.reason

  echo "=== ALL PASS ==="

main()