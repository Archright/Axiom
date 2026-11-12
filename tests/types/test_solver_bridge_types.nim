## test_solver_bridge_types.nim — Unit tests for VerificationResult/VerificationReport.
##
## Run: nim c --hints:off -d:skipImportLint -r tests/types/test_solver_bridge_types.nim

import std/[options, strutils, strformat]
import core/solver/solver_bridge

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string; cond: bool) =
    if cond:
      inc passed
      echo "  PASS: " & name
    else:
      inc failed
      echo "  FAIL: " & name

  # --- VerificationResult (Z3 BMC) ---
  block:
    let z3Res = VerificationResult(
      targetProc: "myFunc",
      success: false,
      durationMs: 123.4,
      message: "counterexample found",
      kind: vkZ3BMC,
      counterexample: some("x = 5, y = 0"),
      depthK: 10
    )
    check "Z3 BMC kind is vkZ3BMC", z3Res.kind == vkZ3BMC
    check "Z3 BMC success is false", not z3Res.success
    check "Z3 BMC counterexample present", z3Res.counterexample.isSome
    check "Z3 BMC depthK == 10", z3Res.depthK == 10
    check "Z3 BMC targetProc", z3Res.targetProc == "myFunc"

  # --- VerificationResult (Lean 4) ---
  block:
    let leanRes = VerificationResult(
      targetProc: "verifyAdd",
      success: true,
      durationMs: 45.0,
      message: "kernel verified",
      kind: vkLean4,
      proofTerm: some("rfl"),
      isKernelVerified: true
    )
    check "Lean4 kind is vkLean4", leanRes.kind == vkLean4
    check "Lean4 success", leanRes.success
    check "Lean4 proofTerm present", leanRes.proofTerm.isSome
    check "Lean4 isKernelVerified", leanRes.isKernelVerified
    check "Lean4 targetProc", leanRes.targetProc == "verifyAdd"

  # --- VerificationReport ---
  block:
    let z3Res = VerificationResult(
      targetProc: "myFunc",
      success: false,
      durationMs: 123.4,
      message: "counterexample found",
      kind: vkZ3BMC,
      counterexample: some("x = 5"),
      depthK: 10
    )
    let leanRes = VerificationResult(
      targetProc: "verifyAdd",
      success: true,
      durationMs: 45.0,
      message: "kernel verified",
      kind: vkLean4,
      proofTerm: some("rfl"),
      isKernelVerified: true
    )
    let report = VerificationReport(
      results: @[z3Res, leanRes],
      totalDurationMs: 168.4
    )
    let summary = generateReport(report)
    check "report summary includes passed count", summary.contains("1 passed")
    check "report summary includes failed count", summary.contains("1 failed")
    check "report summary includes total duration", summary.contains("168.4ms")

  echo &"\n{passed} passed, {failed} failed"
  if failed > 0:
    quit(1)

main()
