## tests/unit/obligation_lowering_smt_let_test.nim
## Obligation SMT lowering — irLet slice: nested SMT `let`, signed BV
## operators, uninterpreted `len`, and the let-bound name subtraction.
##
## Every Z3 interaction runs the real binary at $AXIOM_Z3 (default
## ~/.local/bin/z3) and asserts the exit code, because Z3 prints its answer
## on stdout even when it has already rejected the script.

import std/[os, osproc, sequtils, strutils]
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/private/obligation_smt_lowering
import core/logic/smt_logic

const targetSlice = "obligation_lowering_smt_let_test"

func countOccurrences(haystack, needle: string): int =
  var n = 0
  var pos = haystack.find(needle)
  while pos >= 0:
    inc n
    pos = haystack.find(needle, pos + 1)
  n

# ---------------------------------------------------------------------------
# The measured target obligation, rebuilt verbatim:
#   let bytesCount = len bytes in
#     (bytesCount - 1 >= 0) /\ (bytesCount - 1 < len bytes)
# ---------------------------------------------------------------------------

func bytesVar(): IRExpr = irVar("bytes", irTypeList(irTypeBitVec64()))
func lenOfBytes(): IRExpr = irCall("len", @[bytesVar()])
func bvVar(name: string): IRExpr = irVar(name, irTypeBitVec64())
func countVar(): IRExpr = bvVar("bytesCount")
func minusOne(): IRExpr = irBinOp(boSub, countVar(), irLit(1))

func targetProposition(): IRExpr =
  let gePart = irBinOp(boGe, minusOne(), irLit(0))
  let ltPart = irBinOp(boLt, minusOne(), lenOfBytes())
  irLet("bytesCount", lenOfBytes(), irBinOp(boAnd, gePart, ltPart))

func aufContext(): SmtLoweringContext =
  SmtLoweringContext(logic: slQfAufbv, rlimit: 10000, obligationKind: targetSlice)

proc runZ3(z3Bin: string; script, tag: string): tuple[outText: string, exitCode: int] =
  let path = getTempDir() / (targetSlice & "_" & tag & ".smt2")
  writeFile(path, script)
  defer: removeFile(path)
  try:
    let res = execCmdEx(z3Bin & " " & quoteShell(path))
    (res.output, res.exitCode)
  except OSError:
    ("Z3_UNAVAILABLE", -1)

proc resolveZ3(): string =
  let fromEnv = getEnv("AXIOM_Z3", "")
  if fromEnv.len > 0 and fileExists(fromEnv):
    return fromEnv
  let home = getHomeDir() / ".local" / "bin" / "z3"
  if fileExists(home):
    return home
  "z3"

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()
      except Defect:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  let lowered = lowerObligationToSmt(targetProposition(), aufContext())
  let script = lowered.smtScript

  echo "=== Generated SMT-LIB2 ==="
  echo script
  echo "============================"

  # =========================================================================
  # 1. Emitted shape
  # =========================================================================
  echo "=== emitted shape ==="

  check "lowering is not empty":
    doAssert not lowered.empty, lowered.errorMsg
    doAssert not lowered.lostInformation

  check "exactly one let binding, and it is bytesCount":
    doAssert countOccurrences(script, "(let ((") == 1, script
    doAssert script.contains("(let ((bytesCount (len bytes)))"), script

  check "five new operators are emitted":
    for op in ["(and ", "(bvsge ", "(bvslt ", "(bvsub ", "(len "]:
      doAssert script.contains(op), op & " missing from: " & script

  check "signed semantics, not unsigned":
    doAssert not script.contains("bvult") and not script.contains("bvuge")

  check "len is declared as a 1-ary uninterpreted function":
    doAssert script.contains(
      "(declare-fun len ((Array (_ BitVec 64) (_ BitVec 64))) (_ BitVec 64))"), script

  check "declaration ordering does not depend on collection order":
    let sigs: seq[SmtFuncSig] = @[
      SmtFuncSig(funcName: "gamma", argSorts: @["Bool"], retSort: "Bool"),
      SmtFuncSig(funcName: "alpha", argSorts: @["Bool"], retSort: "Bool"),
      SmtFuncSig(funcName: "beta", argSorts: @[], retSort: "(_ BitVec 64)")]
    let names = sortFuncSigs(sigs).mapIt(it.funcName)
    doAssert names == @["alpha", "beta", "gamma"], $names
    let shuffled: seq[SmtFuncSig] = @[sigs[1], sigs[0], sigs[2]]
    doAssert names == sortFuncSigs(shuffled).mapIt(it.funcName),
      "sort must not depend on input order"
    doAssert sortFuncSigs(@[]).len == 0
    doAssert sortFuncSigs(@[sigs[0]]).mapIt(it.funcName) == @["gamma"]
    doAssert smtDeclareFuns(@[], @[], sigs).splitLines == [
      "(declare-fun alpha (Bool) Bool)",
      "(declare-fun beta () (_ BitVec 64))",
      "(declare-fun gamma (Bool) Bool)"], smtDeclareFuns(@[], @[], sigs)

  check "let-bound bytesCount is NOT declared":
    doAssert not script.contains("(declare-fun bytesCount"), script
    doAssert lowered.symbolicOperands == @["bytes"], $lowered.symbolicOperands

  check "declared free var universe is exactly {bytes}":
    let decls = script.splitLines.filterIt(it.startsWith("(declare-fun"))
    doAssert decls.len == 2, "expected 2 declare-fun, got " & $decls.len
    doAssert decls[0].startsWith("(declare-fun bytes () "), decls[0]
    doAssert decls[1].startsWith("(declare-fun len ("), decls[1]

  # =========================================================================
  # 2. Determinism of the script text
  # =========================================================================
  echo "=== script determinism ==="

  check "identical IR yields identical script bytes":
    let again = lowerObligationToSmt(targetProposition(), aufContext())
    doAssert again.smtScript == script

  # =========================================================================
  # 3. Real Z3
  # =========================================================================
  echo "=== real Z3 ==="
  let z3Bin = resolveZ3()

  check "z3 binary is reachable":
    doAssert fileExists(z3Bin) or findExe(z3Bin).len > 0, "no z3 at " & z3Bin

  check "script as emitted answers sat with exit 0":
    let r0 = runZ3(z3Bin, script, "plain")
    doAssert r0.exitCode == 0, "exit=" & $r0.exitCode & " out=" & r0.outText
    doAssert not r0.outText.contains("(error"), r0.outText
    doAssert r0.outText.strip() == "sat", r0.outText

  # SMT-LIB2 4.2.1 makes (set-logic ...) the first command of a script, so the
  # pin goes on the line after it; Z3 rejects the option when it leads.
  let firstNl = script.find('\n')
  let seeded = script[0 ..< firstNl] & "\n(set-option :random-seed 4242)" &
               script[firstNl .. ^1]
  check "seed option lands after set-logic, which SMT-LIB2 4.2.1 requires first":
    doAssert seeded.contains("(set-option :random-seed 4242)")
    doAssert seeded.splitLines[0].startsWith("(set-logic "), seeded
    doAssert seeded.splitLines[1] == "(set-option :random-seed 4242)", seeded

  check "3 runs of the emitted script are byte-identical and sat":
    var outputs: seq[string]
    for i in 0 ..< 3:
      let r = runZ3(z3Bin, script, "plain" & $i)
      doAssert r.exitCode == 0, "run " & $i & " exit=" & $r.exitCode &
                                 " out=" & r.outText
      doAssert not r.outText.contains("(error"), r.outText
      outputs.add r.outText
    doAssert outputs[0] == outputs[1] and outputs[1] == outputs[2], $outputs

  check "3 runs with :random-seed 4242 are byte-identical and sat":
    var outputs: seq[string]
    for i in 0 ..< 3:
      let r = runZ3(z3Bin, seeded, "seed" & $i)
      doAssert r.exitCode == 0, "run " & $i & " exit=" & $r.exitCode &
                                 " out=" & r.outText
      doAssert not r.outText.contains("(error"), r.outText
      outputs.add r.outText
    doAssert outputs[0] == outputs[1] and outputs[1] == outputs[2], $outputs

  # Why nesting is mandatory: SMT-LIB2 3.6.1 binds `let` simultaneously, and Z3
  # rejects a parallel form while still printing an answer on stdout.
  check "a parallel let with a sibling-dependent RHS is rejected by Z3":
    let parallel = """
(set-logic QF_AUFBV)
(declare-fun bytes () (Array (_ BitVec 64) (_ BitVec 64)))
(declare-fun len ((Array (_ BitVec 64) (_ BitVec 64))) (_ BitVec 64))
(assert (not (let ((bytesCount (len bytes)) (other (bvsub bytesCount #x0000000000000001))) (bvslt other #x0000000000000000))))
(check-sat)
"""
    let r = runZ3(z3Bin, parallel, "parallel")
    doAssert r.exitCode != 0, "parallel let must not succeed"
    doAssert r.outText.contains("(error"), r.outText
    doAssert r.outText.contains("unknown constant bytesCount"), r.outText

  # =========================================================================
  # 4. Negative tests — everything outside the closure fails closed
  # =========================================================================
  echo "=== negative tests ==="

  check "irCall(\"[]\") fails closed":
    let expr = irLet("bytesCount", lenOfBytes(),
      irBinOp(boLt, minusOne(), irCall("[]", @[bytesVar(), irLit(0)])))
    let res = lowerObligationToSmt(expr, aufContext())
    doAssert res.empty, res.smtScript
    doAssert res.lostInformation

  check "log2trunc fails closed":
    let expr = irLet("bytesCount", lenOfBytes(),
      irBinOp(boLt, minusOne(), irCall("log2trunc", @[bytesVar()])))
    let res = lowerObligationToSmt(expr, aufContext())
    doAssert res.empty, res.smtScript

  check "len at the wrong arity fails closed":
    let expr = irLet("bytesCount", irCall("len", @[bytesVar(), bytesVar()]),
                     irBinOp(boLt, countVar(), irLit(0)))
    let res = lowerObligationToSmt(expr, aufContext())
    doAssert res.empty, res.smtScript

  check "unsupported binop (boDiv) fails closed":
    let expr = irLet("bytesCount", lenOfBytes(),
      irBinOp(boDiv, minusOne(), irLit(0)))
    let res = lowerObligationToSmt(expr, aufContext())
    doAssert res.empty, res.smtScript

  check "unsupported binop (boOr) fails closed":
    let expr = irLet("bytesCount", lenOfBytes(),
      irBinOp(boOr, irBinOp(boEq, countVar(), irLit(1)),
                     irBinOp(boEq, countVar(), irLit(2))))
    let res = lowerObligationToSmt(expr, aufContext())
    doAssert res.empty, res.smtScript

  check "QF_BV cannot carry the Array sort — fails closed, not mislabelled":
    let ctx = SmtLoweringContext(logic: slQfBv, rlimit: 10000,
                                 obligationKind: targetSlice)
    let res = lowerObligationToSmt(targetProposition(), ctx)
    doAssert res.empty, res.smtScript
    doAssert res.errorMsg.contains("QF_AUFBV"), res.errorMsg

  # =========================================================================
  # 5. Nested-let shape
  # =========================================================================
  echo "=== nested let ==="

  check "chained lets nest one binding per node":
    let expr = irLet("a", lenOfBytes(),
      irLet("b", irBinOp(boSub, bvVar("a"), irLit(1)),
            irBinOp(boLt, bvVar("b"), irLit(0))))
    let res = lowerObligationToSmt(expr, aufContext())
    doAssert not res.empty, res.errorMsg
    doAssert countOccurrences(res.smtScript, "(let ((") == 2, res.smtScript
    let nestedPrefix = "(let ((a (len bytes))) (let ((b (bvsub a "
    doAssert res.smtScript.contains(nestedPrefix), res.smtScript
    doAssert not res.smtScript.contains("(let ((a (len bytes)) (b "),
      "no sibling bindings: " & res.smtScript
    doAssert res.smtScript.contains("))) (let (("), res.smtScript

  check "a let whose RHS is itself a let still nests":
    let expr = irLet("outer",
      irLet("inner", irLit(5), bvVar("inner")),
      bvVar("outer"))
    let res = lowerObligationToSmt(expr, aufContext())
    doAssert not res.empty, res.errorMsg
    let rhsIsLet = "(let ((outer (let ((inner "
    doAssert res.smtScript.contains(rhsIsLet), res.smtScript
    doAssert countOccurrences(res.smtScript, "(let ((") == 2, res.smtScript

  check "nested-let script is sat under Z3":
    let expr = irLet("a", lenOfBytes(),
      irLet("b", irBinOp(boSub, bvVar("a"), irLit(1)),
            irBinOp(boLt, bvVar("b"), irLit(0))))
    let res = lowerObligationToSmt(expr, aufContext())
    doAssert res.symbolicOperands == @["bytes"], $res.symbolicOperands
    let r = runZ3(z3Bin, res.smtScript, "nested")
    doAssert r.exitCode == 0, "exit=" & $r.exitCode & " out=" & r.outText
    doAssert r.outText.strip() == "sat", r.outText

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

when isMainModule:
  main()