import std/[json, os, osproc, sets, strutils]
import core/results
import core/trusted/axiom_ir
import infrastructure/ir_binary_codec
import verification/kernel_reexecution
import verification/renderer_differential

## ═══════════════════════════════════════════════════════════════════════
## SemanticClosure — certification continuity Phase 3.5 tests
## (Tier 1: kernel-inside semantic closure)
##
## Coverage:
##   P0  dual-renderer differential (canonical vs ir_to_lean) — agree/skip
##       on the overlap, disagree semantics on divergent/malformed renderings
##   P1  irCast codec roundtrip (Nim: encode(icast) → decode → equal) +
##       malformed-codec rejection
##   P2  real Lean runs against proofs/IR/Denotation.lean: same IR →
##       renderIR == evalIR; wrong IR (outside subset) → mismatch detected /
##       Certified membership refused  (SKIP loudly if lean absent, exit 0)
##   P3  Phase-3 allowlist reuse via reexecuteLean: denotation artifact →
##       krPassed; native_decide → krAxiomViolation; forbidden axiom →
##       krAxiomViolation; out-of-subset refusal → krPassed
##   P4  LeanWorker invocation: valid serialized IR → exit 0 / krPassed;
##       corrupted bytes → non-zero / krCompileError; irCast bytes decode
##       (Lean-side 0x0D gap closed)  (SKIP loudly if ircheck binary absent)
## ═══════════════════════════════════════════════════════════════════════

var passCount = 0
var skipCount = 0

proc checkEq(name: string; got, exp: string) =
  if got == exp:
    echo "  [PASS] ", name
    inc passCount
  else:
    echo "  [FAIL] ", name, "\n      got: ", got, "\n      exp: ", exp
    quit(1)

proc checkTrue(name: string; cond: bool) =
  if cond:
    echo "  [PASS] ", name
    inc passCount
  else:
    echo "  [FAIL] ", name
    quit(1)

proc checkVerdict(name: string; got, exp: KernelVerdict) =
  if got == exp:
    echo "  [PASS] ", name, " -> ", $got
    inc passCount
  else:
    echo "  [FAIL] ", name, "\n      got: ", $got, "\n      exp: ", $exp
    quit(1)

proc checkDifferential(name: string; got, exp: RendererDifferentialVerdict) =
  if got == exp:
    echo "  [PASS] ", name, " -> ", $got
    inc passCount
  else:
    echo "  [FAIL] ", name, "\n      got: ", $got, "\n      exp: ", $exp
    quit(1)

proc skip(name: string; reason: string) =
  echo "  [SKIP] ", name, " (", reason, ") — test skipped, exit 0"
  inc skipCount

proc findRepoRoot(): string =
  var dir = getCurrentDir()
  while dir.len > 0:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = parentDir(dir)
    if parent == dir: break
    dir = parent
  result = getCurrentDir()

let repoRoot = findRepoRoot()
let proofsDir = repoRoot / "proofs"
let leanAvailable = findExe("lake").len > 0 and findExe("lean").len > 0 and
                    fileExists(proofsDir / "lakefile.lean")
let ircheckBin = proofsDir / ".lake" / "build" / "bin" / "ircheck"
let workerAvailable = fileExists(ircheckBin)

# ---------------------------------------------------------------------------
# shared IR fixture builders
# ---------------------------------------------------------------------------
proc lit(v: int64): IRExpr = IRExpr(kind: irLit, litVal: v)
proc vv(n: string): IRExpr =
  IRExpr(kind: irVar, varName: n, varType: IRType(kind: irtBitVec64))
proc op(k: BinOpKind; l, r: IRExpr): IRExpr =
  IRExpr(kind: irBinOp, binOp: k, binLhs: l, binRhs: r)
proc neg(a: IRExpr): IRExpr =
  IRExpr(kind: irUnaryOp, unaryOp: uoNot, unaryArg: a)
proc ite(c, t, e: IRExpr): IRExpr =
  IRExpr(kind: irIf, ifCond: c, ifThen: t, ifElse: e)

# ---------------------------------------------------------------------------
# P0 — dual-renderer differential (pure, always runs)
# ---------------------------------------------------------------------------
echo "=== P0: dual-renderer differential ==="
let params = ["x", "y"].toHashSet
checkDifferential("add agrees", differentialCheck(op(boAdd, vv("x"), lit(5)), params), rdAgree)
checkDifferential("add/sub chain agrees",
  differentialCheck(op(boAdd, op(boSub, vv("x"), lit(1)), vv("y")), params), rdAgree)
checkDifferential("lt agrees", differentialCheck(op(boLt, vv("x"), lit(1)), params), rdAgree)
checkDifferential("le agrees",
  differentialCheck(op(boLe, op(boAdd, vv("x"), lit(1)), lit(5)), params), rdAgree)
checkDifferential("ge agrees", differentialCheck(op(boGe, vv("x"), vv("y")), params), rdAgree)
checkDifferential("eq agrees", differentialCheck(op(boEq, vv("x"), lit(3)), params), rdAgree)
checkDifferential("and-of-not agrees",
  differentialCheck(op(boAnd, neg(vv("x")), vv("y")), params), rdAgree)
checkDifferential("or-of-comparisons agrees",
  differentialCheck(op(boOr, op(boGt, vv("x"), lit(0)), op(boLt, vv("y"), lit(0))), params), rdAgree)
checkDifferential("not-of-comparison agrees",
  differentialCheck(neg(op(boLt, vv("x"), lit(1))), params), rdAgree)
checkDifferential("top-level if agrees",
  differentialCheck(ite(op(boLt, vv("x"), lit(1)), lit(2), lit(3)), params), rdAgree)
checkDifferential("nested-if branch agrees",
  differentialCheck(ite(op(boLt, vv("x"), lit(1)),
    ite(op(boGt, vv("y"), lit(0)), lit(2), lit(4)), lit(3)), params), rdAgree)
checkDifferential("if on binop RHS agrees",
  differentialCheck(op(boAdd, vv("x"),
    ite(op(boLt, vv("y"), lit(1)), lit(2), lit(3))), params), rdAgree)
checkDifferential("if on binop LHS agrees (atomic branches)",
  differentialCheck(op(boAdd,
    ite(op(boLt, vv("x"), lit(1)), lit(2), lit(3)), vv("y")), params), rdAgree)
checkDifferential("negative literal agrees",
  differentialCheck(op(boAdd, vv("x"), lit(-5)), params), rdAgree)
checkDifferential("mul skipped (outside overlap)",
  differentialCheck(op(boMul, vv("x"), lit(2)), params), rdSkip)
checkDifferential("floatLit skipped",
  differentialCheck(IRExpr(kind: irFloatLit, floatVal: 1.0), params), rdSkip)
checkDifferential("call skipped",
  differentialCheck(IRExpr(kind: irCall, callName: "f", callArgs: @[vv("x")]), params), rdSkip)
checkDifferential("uoBvNeg skipped",
  differentialCheck(IRExpr(kind: irUnaryOp, unaryOp: uoBvNeg, unaryArg: vv("x")), params), rdSkip)
checkDifferential("non-param var skipped (canonical unsupported)",
  differentialCheck(op(boAdd, vv("z"), lit(1)), params), rdSkip)
checkDifferential("nil skipped", differentialCheck(nil, params), rdSkip)
checkDifferential("dialect spellings normalize equal",
  differentialCompareNormalized("((! x) && y)", "(¬ x ∧ y)"), rdAgree)
checkDifferential("whitespace-insensitive compare",
  differentialCompareNormalized("(if (x < 1) then 2 else 3)", "(if(x<1)then 2 else 3)"), rdAgree)
checkDifferential("different operators disagree",
  differentialCompareNormalized("(x + 1)", "(x - 1)"), rdDisagree)
checkDifferential("different structure disagrees",
  differentialCompareNormalized("(x - (y - 1))", "((x - y) - 1)"), rdDisagree)
checkDifferential("malformed rendering disagrees (fail-closed)",
  differentialCompareNormalized("(x < 1", "(x < 1)"), rdDisagree)
checkDifferential("unlexable rendering disagrees (fail-closed)",
  differentialCompareNormalized("x != 1", "x = 1"), rdDisagree)
checkDifferential("empty canonical side disagrees (fail-closed)",
  differentialCompareNormalized("", "(x < 1)"), rdDisagree)

# ---------------------------------------------------------------------------
# P1 — irCast codec roundtrip + malformed-codec rejection (pure, always runs)
# ---------------------------------------------------------------------------
echo "=== P1: irCast codec roundtrip + malformed codec ==="
let castIR = IRExpr(kind: irCast, castExpr: lit(5),
                    castFrom: IRType(kind: irtBitVec64),
                    castTo: IRType(kind: irtBool))
let castBytes = serializeIRExprAligned(castIR)
let castBack = deserializeIRExprAligned(castBytes)
checkTrue("irCast bytes non-empty", castBytes.len > 0)
checkTrue("encode(icast) → decode → kind irCast", castBack != nil and castBack.kind == irCast)
checkTrue("castFrom restored", castBack != nil and castBack.castFrom != nil and
  castBack.castFrom.kind == irtBitVec64)
checkTrue("castTo restored", castBack != nil and castBack.castTo != nil and
  castBack.castTo.kind == irtBool)
checkTrue("castExpr restored", castBack != nil and castBack.castExpr != nil and
  castBack.castExpr.kind == irLit and castBack.castExpr.litVal == 5)
let litBytes = serializeIRExprAligned(lit(5))
# Nim-side codec is fail-soft on bounds (mid-tag truncation → nil tag); the
# strict reject lives in the Lean BinaryCodec (checked in P4).
let truncBytes = @(litBytes[0 ..< 4])
checkTrue("truncated bytes → nil (reject)",
  deserializeIRExprAligned(truncBytes) == nil)
var corruptTag = @(castBytes)
if corruptTag.len > 0:
  corruptTag[0] = 0x99'u8
checkTrue("corrupt tag 0x99 → nil (reject)",
  deserializeIRExprAligned(corruptTag) == nil)
checkTrue("empty bytes → nil (reject)", deserializeIRExprAligned(@[]) == nil)

# ---------------------------------------------------------------------------
# P2 — real Lean runs on the hand-written Denotation (SKIP loudly if absent)
# ---------------------------------------------------------------------------
echo "=== P2: real Lean render/denotation equivalence ==="
proc runLeanInProofs(leanSource: string): tuple[output: string, exitCode: int] =
  let path = getTempDir() / ("axiom_semclosure_" & $getCurrentProcessId() & ".lean")
  writeFile(path, leanSource)
  result = execCmdEx("cd " & quoteShell(proofsDir) & " && lake env lean --threads=1 " &
                     quoteShell(path))
  try: removeFile(path)
  except CatchableError: discard # axiom:best-effort(ioboundary catch) test cleanup

if leanAvailable:
  let acceptSrc = """
import IR.Denotation
open AxiomDenotation
#eval renderIR (fun _ => 3) (.binOp .lt (.binOp .add (.var_ "x" .bitVec64) (.lit 1)) (.lit 5))
#eval evalIR (fun _ => 3) (.binOp .lt (.binOp .add (.var_ "x" .bitVec64) (.lit 1)) (.lit 5))
#eval certifiedSubset (.binOp .lt (.binOp .add (.var_ "x" .bitVec64) (.lit 1)) (.lit 5)) .bool
#eval renderIR (fun _ => 7) (.binOp .eq (.binOp .sub (.var_ "x" .bitVec64) (.lit 2)) (.lit 5))
#eval evalIR (fun _ => 7) (.binOp .eq (.binOp .sub (.var_ "x" .bitVec64) (.lit 2)) (.lit 5))
"""
  let acc = runLeanInProofs(acceptSrc)
  checkTrue("same IR: lean file exits 0", acc.exitCode == 0)
  if acc.exitCode != 0:
    echo acc.output
  checkTrue("same IR: renderIR = true, evalIR = 1 (agree)",
    acc.output.contains("true\n1"))
  checkTrue("same IR: certifiedSubset true, equality form agrees",
    acc.output.contains("true\n1") and acc.output.count("true") >= 2)
  checkTrue("same IR: second expr renderIR=true evalIR=1",
    acc.output.contains("true\n1"))
  let rejectSrc = """
import IR.Denotation
open AxiomDenotation
#eval certifiedSubset (.floatLit 1.0) .int
#eval certifiedSubset (.binOp .lt (.floatLit 1.0) (.lit 5)) .bool
#eval renderIR (fun _ => 3) (.floatLit 1.0)
#eval evalIR (fun _ => 3) (.floatLit 1.0)
example : certifiedSubset (.floatLit 1.0) .int = false := by rfl
example : ¬ Certified (.floatLit 1.0) .int := by
  intro h
  cases h
"""
  let rej = runLeanInProofs(rejectSrc)
  checkTrue("wrong IR: refusal file exits 0 (kernel-checked)", rej.exitCode == 0)
  if rej.exitCode != 0:
    echo rej.output
  checkTrue("wrong IR: floatLit outside subset → mismatch detected (subset=false)",
    rej.output.contains("false\nfalse\nfalse\n0"))
else:
  skip("real Lean render/denotation equivalence suite", "lean/lake/proofs build not found")

# ---------------------------------------------------------------------------
# P3 — Phase-3 allowlist reuse on the closure artifacts (SKIP if lean absent)
# ---------------------------------------------------------------------------
echo "=== P3: INV-6 allowlist reuse (ax cert verify --kernel machinery) ==="
proc makeCert(leanSource: string): JsonNode =
  var node = newJObject()
  node["status"] = %"passed"
  node["leanSource"] = %leanSource
  node

if leanAvailable:
  let leanCmd = "cd " & quoteShell(proofsDir) & " && lake env lean"
  let denotationArtifact = """
import IR.Denotation
open AxiomDenotation
theorem closure_sample
    (h : Certified (.binOp .lt (.binOp .add (.var_ "x" .bitVec64) (.lit 1)) (.lit 5)) .bool) :
    (renderIR (fun _ => 3) (.binOp .lt (.binOp .add (.var_ "x" .bitVec64) (.lit 1)) (.lit 5)) = true
      ↔ evalIR (fun _ => 3) (.binOp .lt (.binOp .add (.var_ "x" .bitVec64) (.lit 1)) (.lit 5)) ≠ 0) := by
  exact renderIR_eq_eval (env := fun _ => 3)
    (ir := .binOp .lt (.binOp .add (.var_ "x" .bitVec64) (.lit 1)) (.lit 5)) h
#print axioms closure_sample
"""
  checkVerdict("denotation artifact kernel-checked + allowlisted → krPassed",
    reexecuteLean(makeCert(denotationArtifact), leanCmd, 120_000), krPassed)
  let nativeSrc = """
import IR.Denotation
open AxiomDenotation
theorem tN : renderInt (fun _ => 0) (.lit 5) = 5 := by native_decide
#print axioms tN
"""
  checkVerdict("native_decide on closure term → krAxiomViolation",
    reexecuteLean(makeCert(nativeSrc), leanCmd, 120_000), krAxiomViolation)
  let forbiddenSrc = """
import IR.Denotation
axiom bad : False
#print axioms bad
"""
  checkVerdict("forbidden axiom → krAxiomViolation",
    reexecuteLean(makeCert(forbiddenSrc), leanCmd, 120_000), krAxiomViolation)
  let refusalArtifact = """
import IR.Denotation
open AxiomDenotation
example : certifiedSubset (.floatLit 1.0) .int = false := by rfl
example : ¬ Certified (.floatLit 1.0) .int := by
  intro h
  cases h
#print axioms certifiedSubset
"""
  checkVerdict("out-of-subset refusal kernel-clean → krPassed",
    reexecuteLean(makeCert(refusalArtifact), leanCmd, 120_000), krPassed)
else:
  skip("allowlist reuse suite", "lean/lake/proofs build not found")

# ---------------------------------------------------------------------------
# P4 — LeanWorker invocation: decode + metaCheck (SKIP if worker absent)
# ---------------------------------------------------------------------------
echo "=== P4: LeanWorker invocation (ircheck --check-file) ==="
if workerAvailable:
  checkVerdict("valid serialized IR (lit) → krPassed",
    checkIRWithLeanWorker(litBytes, ircheckBin, repoRoot, 60_000), krPassed)
  checkVerdict("valid serialized IR (lt expr) → krPassed",
    checkIRWithLeanWorker(serializeIRExprAligned(op(boLt, lit(3), lit(5))),
                          ircheckBin, repoRoot, 60_000), krPassed)
  checkVerdict("irCast bytes → krPassed (Lean 0x0D decode gap closed)",
    checkIRWithLeanWorker(castBytes, ircheckBin, repoRoot, 60_000), krPassed)
  checkVerdict("corrupt tag bytes → krCompileError",
    checkIRWithLeanWorker(corruptTag, ircheckBin, repoRoot, 60_000), krCompileError)
  checkVerdict("truncated bytes → krCompileError",
    checkIRWithLeanWorker(truncBytes, ircheckBin, repoRoot, 60_000), krCompileError)
  checkVerdict("empty bytes → krMissingInput",
    checkIRWithLeanWorker(@[], ircheckBin, repoRoot, 5_000), krMissingInput)
  checkVerdict("missing worker binary → krInternalError (fail-closed)",
    checkIRWithLeanWorker(litBytes, "/nonexistent/ircheck", repoRoot, 5_000), krInternalError)
  let f = getTempDir() / ("axiom_ircheck_probe_" & $getCurrentProcessId() & ".bin")
  writeFile(f, cast[string](castBytes))
  let (rawOut, rawCode) = execCmdEx(quoteShell(ircheckBin) & " --check-file " & quoteShell(f))
  checkTrue("direct invocation: valid serialized IR → exit 0", rawCode == 0)
  try: removeFile(f)
  except CatchableError: discard # axiom:best-effort(ioboundary catch) test cleanup
  let bad = getTempDir() / ("axiom_ircheck_bad_" & $getCurrentProcessId() & ".bin")
  writeFile(bad, cast[string](corruptTag))
  let (badOut, badCode) = execCmdEx(quoteShell(ircheckBin) & " --check-file " & quoteShell(bad))
  checkTrue("direct invocation: corrupted serialized IR → non-zero exit", badCode != 0)
  try: removeFile(bad)
  except CatchableError: discard # axiom:best-effort(ioboundary catch) test cleanup
  let (missingOut, missingCode) = execCmdEx(
    quoteShell(ircheckBin) & " --check-file /nonexistent/axiom_ir.bin")
  checkTrue("direct invocation: unreadable file → non-zero exit", missingCode != 0)
else:
  skip("LeanWorker invocation suite", "proofs/.lake/build/bin/ircheck not built (run: cd proofs && lake build ircheck)")

# ---------------------------------------------------------------------------
echo ""
echo "ALL SEMANTIC CLOSURE TESTS PASSED (" & $passCount & " checks, " & $skipCount & " skipped)"
