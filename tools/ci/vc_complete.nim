import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import api/tools_facade
import std/[os, options, strutils]
import verification/lean_repl_bridge
import personas/legislator
import check_lean_vacuity_v2
import src/engine/profiler

type
  VCPipelineResult* = object
    success*: bool
    roundsUsed*: int
    finalOutput*: string
    vacuityPass*: bool
    z3BmcResult*: Z3BmcResult
    z3BmcOutput*: string

  HybridVerificationResult* = object
    leanProven*: bool
    z3Proven*: bool
    hybridProven*: bool
    leanOutput*: string
    z3Output*: string
    leanRounds*: int

proc solveTheoremVC*(leanFilePath, theoremName: string): VCPipelineResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var content = readFile(leanFilePath)
  var currentError: Option[string] = none(string)

  echo "[VC-PIPE] Starting Tactic Search for: ", theoremName

  for round in 1 .. MaxFeedbackRounds:
    echo "  -> Round ", round, "/", MaxFeedbackRounds

    if round > 1 or content.contains("sorry"):
      let tactic = solveGoal(theoremName, "", round, currentError)
      echo "  [VC-PIPE] Leanstral returned tactic: '", tactic, "'"
      content = injectTactic(content, tactic)
      writeFile(leanFilePath, content)

    let vcResult = profileBlock("Lean 4 Kernel Verification", 2000):
      runLeanKernel(leanFilePath)

    case vcResult.status
    of psVerified:
      echo "[VC-PIPE] Kernel verification passed!"
      echo "[VC-PIPE] Running vacuity check..."
      let vacuityResults = runVacuityCheck(@[leanFilePath.expandFilename])
      var vacuityOk = vacuityResults.len > 0
      for vr in vacuityResults:
        if not vr.pass:
          vacuityOk = false
          break
      if not vacuityOk:
        echo "[VC-PIPE] Vacuity check FAILED"
        return VCPipelineResult(success: false, roundsUsed: round, finalOutput: vcResult.rawOutput, vacuityPass: false)
      echo "[VC-PIPE] Vacuity check passed"
      return VCPipelineResult(success: true, roundsUsed: round, finalOutput: vcResult.rawOutput, vacuityPass: true)

    of psUnsolvedGoals:
      let goal = vcResult.extractedGoal.get("")
      currentError = some(vcResult.rawOutput)

    of psSyntaxError:
      currentError = some(vcResult.rawOutput)
      echo "  [VC-PIPE] Syntax error, retrying..."

    of psTimeout, psVacuousProof:
      echo "  [VC-PIPE] Failed: ", vcResult.status
      return VCPipelineResult(success: false, roundsUsed: round, finalOutput: vcResult.rawOutput, vacuityPass: false)

  echo "[VC-PIPE] Exceeded MaxFeedbackRounds"
  return VCPipelineResult(success: false, roundsUsed: MaxFeedbackRounds, finalOutput: "Max rounds exceeded", vacuityPass: false)

proc runHybridVerification*(leanFilePath, theoremName: string): HybridVerificationResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  echo ""
  echo "=== Hybrid Verification: Lean 4 + Z3 BMC ==="
  echo "Theorem: ", theoremName
  echo "File: ", leanFilePath
  echo ""

  echo "[HYBRID] Phase 1: Lean 4 Kernel Verification..."
  var leanOutput = ""
  var leanProven = false
  var leanRounds = 0
  var content = readFile(leanFilePath)
  var currentError: Option[string] = none(string)
  for round in 1 .. MaxFeedbackRounds:
    leanRounds = round
    if round > 1 or content.contains("sorry"):
      let tactic = solveGoal(theoremName, "", round, currentError)
      content = injectTactic(content, tactic)
      writeFile(leanFilePath, content)
    let lr = runLeanKernel(leanFilePath)
    leanOutput = lr.rawOutput
    if lr.status == psVerified:
      leanProven = true
      break
    elif lr.status == psUnsolvedGoals:
      currentError = some(lr.rawOutput)
    else:
      currentError = some(lr.rawOutput)

  echo "[HYBRID]   Lean result: ", (if leanProven: "PROVEN" else: "FAILED")

  echo "[HYBRID] Phase 2: Z3 BMC Verification..."
  let (_, thmStmt) = extractTheoremNameAndStatement(leanFilePath)
  var z3Proven = false
  var z3Output = ""
  if thmStmt.len > 0:
    let smtQuery = encodeLeanTheoremToSmt(thmStmt)
    let z3Res = runZ3Bmc(smtQuery, 10000)
    z3Output = $z3Res
    z3Proven = (z3Res == zbrProven)
    echo "[HYBRID]   Z3 BMC result: ", z3Output
  else:
    echo "[HYBRID]   Z3 BMC: could not extract theorem statement"

  let hybridProven = leanProven or z3Proven
  echo "[HYBRID] Overall: ", (if hybridProven: "PROVEN" else: "FAILED")
  echo "[HYBRID]   Lean proven: ", leanProven, " (", leanRounds, " rounds)"
  echo "[HYBRID]   Z3 BMC proven: ", z3Proven
  echo ""

  return HybridVerificationResult(
    leanProven: leanProven, z3Proven: z3Proven, hybridProven: hybridProven,
    leanOutput: leanOutput, z3Output: z3Output, leanRounds: leanRounds
  )

proc verifyMyConcatAssoc*(): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  echo "==========================================="
  echo "  Hybrid Verification: my_concat_assoc"
  echo "==========================================="
  let fixturePath = "tests/fixtures/test_custom_reverse_sorry.lean"
  let tempPath = "tests/fixtures/temp_vc_hybrid_test.lean"
  copyFile(fixturePath, tempPath)
  defer: removeFile(tempPath)

  echo "[TEST] Phase 1: Lean 4 proof via tactic injection..."
  let inductionTactic = """
by
  induction xs with
  | nil => rfl
  | cons h t ih => simp [my_concat, ih]
"""
  let r1Code = readFile(tempPath)
  let r2Code = injectTactic(r1Code, inductionTactic)
  writeFile(tempPath, r2Code)
  let leanResult = runLeanKernel(tempPath)
  echo "[TEST]   Lean 4 Kernel: ", leanResult.status
  let leanOk = leanResult.status == psVerified

  echo "[TEST] Phase 2: Z3 BMC verification..."
  let (_, thmStmt) = extractTheoremNameAndStatement(tempPath)
  echo "[TEST]   Theorem: ", thmStmt
  let smtQuery = encodeLeanTheoremToSmt(thmStmt)
  echo "[TEST]   SMT Query:"
  for line in smtQuery.splitLines():
    echo "      ", line
  let z3Res = runZ3Bmc(smtQuery, 10000)
  echo "[TEST]   Z3 BMC result: ", z3Res

  echo ""
  echo "==========================================="
  echo "  Test 2: Z3 BMC on simple arithmetic"
  echo "==========================================="
  let arithQuery = createSimpleArithQuery()
  echo "[TEST]   SMT Query:"
  for line in arithQuery.splitLines():
    echo "      ", line
  let arithRes = runZ3Bmc(arithQuery, 5000)
  echo "[TEST]   Z3 BMC on 5+3=8: ", arithRes
  let arithOk = (arithRes == zbrProven)

  echo ""
  echo "==========================================="
  echo "  Hybrid Verification Results"
  echo "==========================================="
  echo "  Lean 4 (my_concat_assoc): ", (if leanOk: "PASS" else: "FAIL")
  echo "  Z3 BMC (my_concat_assoc): ", (if z3Res == zbrProven: "PASS" else: "UNKNOWN (inductive)")
  echo "  Z3 BMC (5+3=8):           ", (if arithOk: "PASS" else: "FAIL")
  echo "  Hybrid:                   ", (if leanOk: "PASS" else: "FAIL")
  echo "==========================================="
  return leanOk

when isMainModule:
  if paramCount() >= 1 and paramStr(1) == "--hybrid":
    if paramCount() >= 3:
      let hResult = runHybridVerification(paramStr(2), paramStr(3))
      if not hResult.hybridProven:
        quit(1)
    else:
      let success = verifyMyConcatAssoc()
      if not success:
        quit(1)
  elif paramCount() < 2:
    echo "Usage:"
    echo "  vc_complete <lean_file> <theorem_name>           # Classic VC pipeline"
    echo "  vc_complete --hybrid [<lean_file> <theorem_name>] # Hybrid Lean+Z3 BMC"
    quit(1)
  else:
    let vcResult = solveTheoremVC(paramStr(1), paramStr(2))
    if vcResult.success:
      echo "SUCCESS after ", vcResult.roundsUsed, " rounds"
    else:
      echo "FAILED after ", vcResult.roundsUsed, " rounds"
      quit(1)

{.pop.}
