import core/trusted/layer_declaration
axiomLayer "domain"
## Probe program for WP4-h-3 Areas 3 and 4: obligation SMT lowering.
##
## Constructs the exact expression ¬(resultBits == 0) with resultBits : BitVec64,
## calls lowerObligationToSmt, prints the result, writes the SMT-LIB2 script
## to a file, and runs z3 on it.  Verifies determinism by running twice and
## comparing byte-identical output.

import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/private/obligation_smt_lowering
import core/logic/smt_logic
import std/strutils
import std/os

const Z3Path = "<user-home>/.local/bin/z3"
const ProbeOutDir = "./experiments/act2-wp4h3-proofir/probe"
const SmtScriptFile = ProbeOutDir & "/wp4h3_lowered.smt2"
const Run1File = ProbeOutDir & "/run1.smt2"
const Run2File = ProbeOutDir & "/run2.smt2"
const Z3OutputFile = ProbeOutDir & "/z3_output.txt"

# ---------------------------------------------------------------------------
# Build the target expression: ¬(resultBits == 0)
# resultBits is a BitVec64 variable.
# ---------------------------------------------------------------------------

func buildTargetExpr(): IRExpr =
  let resultBits = irVar("resultBits", irTypeBitVec64())
  let zero = irLit(0)
  let eq = irEq(resultBits, zero)          # boEq → resultBits == 0
  irNot(eq)                                       # uoNot → ¬(resultBits == 0)

# ---------------------------------------------------------------------------
# Run z3 on a script file and capture output to a file.
# ---------------------------------------------------------------------------

proc runZ3(scriptPath: string): string =
  let cmd = Z3Path & " -smt2 " & scriptPath & " > " & Z3OutputFile & " 2>&1"
  let exitCode = execShellCmd(cmd)
  if fileExists(Z3OutputFile):
    readFile(Z3OutputFile)
  else:
    "z3 execution failed (exit code: " & $exitCode & ")"

# ---------------------------------------------------------------------------
# Main probe logic.
# ---------------------------------------------------------------------------

let proposition = buildTargetExpr()

let ctx = SmtLoweringContext(
  logic: slQfBv,
  rlimit: 30_000_000,
  obligationKind: "okSafetyDiv"
)

let result = lowerObligationToSmt(proposition, ctx)

echo "=== SmtLoweringResult ==="
echo "obligationKind: ", result.obligationKind
echo "symbolicOperands: ", result.symbolicOperands
echo "referencedIrNodes: ", result.referencedIrNodes
echo "smtTerm: ", result.smtTerm
echo "empty: ", result.empty
echo "lostInformation: ", result.lostInformation
echo "errorMsg: ", result.errorMsg
echo ""

# Write the SMT script to a file.
writeFile(SmtScriptFile, result.smtScript)
echo "Wrote SMT script to: ", SmtScriptFile

# Write run-specific copies for determinism comparison.
writeFile(Run1File, result.smtScript)

# Run z3 on the script.
let z3Output1 = runZ3(SmtScriptFile)
echo "=== Z3 output (run 1) ==="
echo z3Output1
echo ""

# Second run: recompute and compare.
let result2 = lowerObligationToSmt(proposition, ctx)
writeFile(Run2File, result2.smtScript)
let z3Output2 = runZ3(SmtScriptFile)
echo "=== Z3 output (run 2) ==="
echo z3Output2
echo ""

# Determinism check: compare the two SMT scripts byte-identically.
let script1 = readFile(Run1File)
let script2 = readFile(Run2File)
if script1 == script2:
  echo "DETERMINISM CHECK: PASS — byte-identical scripts across two runs."
else:
  echo "DETERMINISM CHECK: FAIL — scripts differ!"
  echo "Run1 length: ", script1.len
  echo "Run2 length: ", script2.len

# Z3 output check: both runs should produce the same sat/unsat/unknown.
let z3status1 = z3Output1.strip().splitWhitespace()
let z3status2 = z3Output2.strip().splitWhitespace()
if z3status1.len > 0 and z3status2.len > 0:
  if z3status1[0] == z3status2[0]:
    echo "Z3 CONSISTENCY CHECK: PASS — both runs returned: ", z3status1[0]
  else:
    echo "Z3 CONSISTENCY CHECK: FAIL — run1=", z3status1[0], " run2=", z3status2[0]

# Verify the script contains declare-fun for resultBits.
if result.smtScript.contains("declare-fun resultBits"):
  echo "DECLARE-FUN CHECK: PASS — script contains declare-fun for resultBits."
else:
  echo "DECLARE-FUN CHECK: FAIL — missing declare-fun for resultBits."

# Verify the script is non-empty.
if result.smtScript.len > 0:
  echo "NON-EMPTY CHECK: PASS — script is non-empty."
else:
  echo "NON-EMPTY CHECK: FAIL — script is empty."

# Verify fail-closed: test with an unsupported construct.
# We use an irLoop which is not supported by this slice.
let loopExpr = irLoop(
  lkFor,
  @["i"],
  @[irLit(0)],
  irLt(irVar("i", irTypeBitVec64()), irLit(10)),
  loopBody = irLit(1)
)
let loopResult = lowerObligationToSmt(loopExpr, ctx)
if loopResult.empty and loopResult.lostInformation and loopResult.errorMsg.len > 0:
  echo "FAIL-CLOSED CHECK: PASS — unsupported construct (irLoop) → empty + lostInformation + errorMsg."
else:
  echo "FAIL-CLOSED CHECK: FAIL — unsupported construct did not produce expected error state."
  echo "  empty=", loopResult.empty, " lostInformation=", loopResult.lostInformation, " errorMsg=", loopResult.errorMsg

echo ""
echo "=== Full SMT Script ==="
echo result.smtScript
