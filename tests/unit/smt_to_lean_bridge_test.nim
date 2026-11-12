import std/unittest
import std/strutils
import core/encoding/smt_to_lean_translate
import core/encoding/smt_to_lean_codegen

suite "Grammar Invariant sanitization":
  test "removes trailing semicolons":
    let raw = "theorem foo : True := by\n  simp;\n"
    let cleaned = sanitizeLeanSource(raw)
    check not contains(cleaned, "simp;")

  test "replaces Lean 3 sequencing":
    let raw = "by simp ; trivial"
    let cleaned = sanitizeLeanSource(raw)
    check not contains(cleaned, " ; ")

  test "assemblePrimitiveProof for linear arithmetic inequality":
    let smt = "(assert (> x 5))"
    let proof = assemblePrimitiveProof(smt)
    check contains(proof, "linarith")

  test "assemblePrimitiveProof for string length":
    let smt = "(assert (>= (str.len s) 0))"
    let proof = assemblePrimitiveProof(smt)
    check contains(proof, "exact")

  test "assemblePrimitiveProof for conjunction":
    let smt = "(assert (and (> x 5) (< x 10)))"
    let proof = assemblePrimitiveProof(smt)
    check contains(proof, "constructor")

  test "buildLeanProofFromSmtlib2 produces valid skeleton":
    let smt = "(declare-const x Int)\n(assert (> x 5))\n"
    let lean = buildLeanProofFromSmtlib2("test_theorem", smt)
    check contains(lean, "theorem test_theorem")
    check contains(lean, "import Std")

  test "assemblePrimitiveProof for single-conjunct and":
    let smt = "(assert (and (>= (str.len raw) 0)))"
    let proof = assemblePrimitiveProof(smt)
    check not contains(proof, "constructor")
    check contains(proof, "exact")

  test "assemblePrimitiveProof for disjunction emits aesop":
    let smt = "(assert (or (> x 5) (< x 0)))"
    let proof = assemblePrimitiveProof(smt)
    check contains(proof, "aesop")

  test "assemblePrimitiveProof for implication emits intro":
    let smt = "(assert (=> (> x 0) (> x -1)))"
    let proof = assemblePrimitiveProof(smt)
    check contains(proof, "intro")
    check contains(proof, "linarith")

  test "assemblePrimitiveProof for negation emits contradiction":
    let smt = "(assert (not (> x x)))"
    let proof = assemblePrimitiveProof(smt)
    check contains(proof, "intro")
    check contains(proof, "contradiction")

  test "assemblePrimitiveProof for arithmetic equality emits linarith":
    let smt = "(declare-const x Int)\n(declare-const y Int)\n(assert (= x y))"
    let proof = assemblePrimitiveProof(smt)
    check contains(proof, "linarith")

  test "extractZ3ProofTrace extracts trace after unsat":
    let stdout = "sat\nunknown\nunsat\n(proof (rewrite (= x x)))"
    let trace = extractZ3ProofTrace(stdout)
    check trace.len > 0
    check contains(trace, "proof")

  test "buildLeanProofScriptFromTrace produces tactic script":
    let trace = "(proof (rewrite (= x x)) (mp (asserted (> x 0)) (asserted (=> (> x 0) (> x -1)))))"
    let script = buildLeanProofScriptFromTrace(trace)
    check contains(script, "by")
    check script.splitLines().len >= 2

  test "z3ProofNodeToLeanTactic maps rewrite to rw":
    let node = Z3ProofNode(kind: zpnkRewrite, rawText: "rewrite", children: @[
      Z3ProofNode(kind: zpnkUnknown, rawText: "add_comm"),
      Z3ProofNode(kind: zpnkUnknown, rawText: "")
    ])
    let tactic = z3ProofNodeToLeanTactic(node)
    check contains(tactic, "rw")

  test "z3ProofNodeToLeanTactic maps quant-inst to specialize":
    let node = Z3ProofNode(kind: zpnkQuantInst, rawText: "quant-inst", children: @[
      Z3ProofNode(kind: zpnkUnknown, rawText: "n")
    ])
    let tactic = z3ProofNodeToLeanTactic(node)
    check contains(tactic, "specialize")

  test "z3ProofNodeToLeanTactic maps unit-resolution to cases":
    let node = Z3ProofNode(kind: zpnkUnitResolution, rawText: "unit-resolution", children: @[
      Z3ProofNode(kind: zpnkUnknown, rawText: "")
    ])
    let tactic = z3ProofNodeToLeanTactic(node)
    check contains(tactic, "cases")
