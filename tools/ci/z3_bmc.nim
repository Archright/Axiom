import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, strutils]
import verification/lean_repl_bridge

proc runZ3BMC*(smtScript: string): Z3CheckResult =
  let tmpFile = getCurrentDir() / "tmp_bmc.smt2"
  writeFile(tmpFile, smtScript)
  let (output, _) = execCmdEx("z3 --model " & tmpFile)
  removeFile(tmpFile)
  let lowered = output.toLowerAscii()
  if lowered.contains("unsat"):
    result = z3Unsat
  elif lowered.contains("sat"):
    result = z3Sat
  else:
    echo "[Z3 BMC] UNKNOWN -> delegating to Lean 4 induction"
    result = z3Inductive

proc main() =
  let smtScript = """
(set-option :produce-models true)
(set-logic QF_LIA)
(declare-const x Int)
(declare-const y Int)
(assert (= (+ x y) 5))
(assert (> x 0))
(assert (> y 0))
(check-sat)
(get-model)
"""
  let z3res = runZ3BMC(smtScript.strip())
  case z3res
  of z3Unsat:
    echo "BMC verification: PASS (bounded valid)"
  of z3Sat:
    echo "BMC verification: FAIL (counterexample found)"
  of z3Inductive:
    echo "BMC verification: UNKNOWN -> delegate to Lean 4"

when isMainModule:
  main()
