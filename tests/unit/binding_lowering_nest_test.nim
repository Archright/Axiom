## tests/unit/binding_lowering_nest_test.nim
## Obligation SMT lowering — recorded source bindings → nested single-binding
## `let`s, the name subtraction that follows, and the fail-closed orders.
##
## The subject is the obligation nim-stew's `bitsLen` actually produced:
##
##     let bytesCount = bytes.len
##     (bytesCount - 1 >= 0) /\ (bytesCount - 1 < len bytes)
##
## `bytesCount` arrives in the proposition as a plain free variable while the
## expression that defines it lives in IRFuncDef.recordedBindings, outside the
## proposition. Without the binding the script proves a statement about an
## unconstrained constant. With it, the script states what the subject said.
##
## Every Z3 interaction runs the real binary and asserts the EXIT CODE as well
## as stdout: Z3 prints an answer even when it has already rejected the script,
## so "sat" on stdout proves nothing on its own.

import std/[os, osproc, sequtils, strutils, unittest]
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/private/obligation_smt_lowering
import core/trusted/semantic_fact_types
import core/logic/smt_logic

const targetSlice = "binding_lowering_nest_test"

func countOccurrences(haystack, needle: string): int =
  var n = 0
  var pos = haystack.find(needle)
  while pos >= 0:
    inc n
    pos = haystack.find(needle, pos + 1)
  n

# ---------------------------------------------------------------------------
# The measured subject, rebuilt from the IR the census produced.
# ---------------------------------------------------------------------------

func bytesVar(): IRExpr = irVar("bytes", irTypeList(irTypeBitVec64()))
func lenOfBytes(): IRExpr = irCall("len", @[bytesVar()])
func bvVar(name: string): IRExpr = irVar(name, irTypeBitVec64())
func countVar(): IRExpr = bvVar("bytesCount")
func minusOne(): IRExpr = irBinOp(boSub, countVar(), irLit(1))

func targetProposition(): IRExpr =
  irBinOp(boAnd,
          irBinOp(boGe, minusOne(), irLit(0)),
          irBinOp(boLt, minusOne(), lenOfBytes()))

func bytesCountBinding(): IRBinding =
  IRBinding(name: "bytesCount", value: lenOfBytes(),
            anchor: "stmt[1]/let", isCompileTime: false, lossFree: true)

func aufContext(bindings: seq[IRBinding]): SmtLoweringContext =
  SmtLoweringContext(logic: slQfAufbv, rlimit: 10000,
                     obligationKind: targetSlice, sourceBindings: bindings)

proc resolveZ3(): string =
  let fromEnv = getEnv("AXIOM_Z3", "")
  if fromEnv.len > 0 and fileExists(fromEnv):
    return fromEnv
  let home = getHomeDir() / ".local" / "bin" / "z3"
  if fileExists(home):
    return home
  "z3"

proc runZ3(z3Bin: string; script, tag: string): tuple[outText: string, exitCode: int] =
  let path = getTempDir() / (targetSlice & "_" & tag & ".smt2")
  writeFile(path, script)
  defer: removeFile(path)
  try:
    let res = execCmdEx(z3Bin & " " & quoteShell(path))
    (res.output, res.exitCode)
  except OSError:
    ("Z3_UNAVAILABLE", -1)

# ---------------------------------------------------------------------------

suite "obligation lowering: source bindings → nested SMT let":

  test "the binding becomes a let and disappears from the declared universe":
    let lowered = lowerObligationToSmt(targetProposition(),
                                       aufContext(@[bytesCountBinding()]))
    check not lowered.empty
    check lowered.errorMsg == ""
    check lowered.smtScript.contains("(let ((bytesCount (len bytes)))")
    check lowered.smtScript.contains("(assert (not (let ((bytesCount")
    check not lowered.smtScript.contains("(declare-fun bytesCount")
    check lowered.symbolicOperands == @["bytes"]

  test "the script declares the binding's own right-hand side operands":
    # `bytes` is read by `len bytes` inside the let, not by the proposition.
    # collectFreeVars reads through the nest, so it lands in the universe
    # without a second pass over the bindings.
    let lowered = lowerObligationToSmt(targetProposition(),
                                       aufContext(@[bytesCountBinding()]))
    let decls = lowered.smtScript.splitLines.filterIt(it.startsWith("(declare-fun"))
    check decls.len == 2
    check decls[0].startsWith("(declare-fun bytes () (Array")
    check decls[1].startsWith("(declare-fun len (")

  test "exactly one binding per let, never a parallel group":
    # SMT-LIB 2.7 §3.6.1: `let` is simultaneous. Two siblings would not see each
    # other, and Z3 answers "(error … unknown constant …)" while still printing
    # a result.
    let lowered = lowerObligationToSmt(targetProposition(),
                                       aufContext(@[bytesCountBinding()]))
    check countOccurrences(lowered.smtScript, "(let ((") == 1
    check not lowered.smtScript.contains("(let ((bytesCount (len bytes)) (")

  test "a loss-free binding referencing another binding nests outside it":
    let bindings = @[
      bytesCountBinding(),
      IRBinding(name: "limit", value: irBinOp(boSub, countVar(), irLit(1)),
                anchor: "stmt[2]/let", isCompileTime: false, lossFree: true)]
    let prop = irBinOp(boAnd,
                       irBinOp(boLt, bvVar("limit"), irLit(0)),
                       irBinOp(boGe, countVar(), irLit(0)))
    let lowered = lowerObligationToSmt(prop, aufContext(bindings))
    check not lowered.empty
    check lowered.errorMsg == ""
    check countOccurrences(lowered.smtScript, "(let ((") == 2
    # `limit`'s RHS reads `bytesCount`, so `bytesCount` must be the OUTER let.
    check lowered.smtScript.contains(
      "(let ((bytesCount (len bytes))) (let ((limit (bvsub bytesCount ")
    check not lowered.smtScript.contains("(assert (not (let ((limit ")
    check lowered.symbolicOperands == @["bytes"]

  test "a source-order forward reference is still placed correctly":
    # `recordBinding` appends in translation order, so a binding that reads a
    # LATER binding is a forward reference. A topological sort places the
    # referenced binding outside, which is the only order that makes the name
    # visible to the RHS.
    let bindings = @[
      IRBinding(name: "limit", value: irBinOp(boSub, countVar(), irLit(1)),
                anchor: "stmt[0]/let", isCompileTime: false, lossFree: true),
      bytesCountBinding()]
    let prop = irBinOp(boAnd,
                       irBinOp(boLt, bvVar("limit"), irLit(0)),
                       irBinOp(boGe, countVar(), irLit(0)))
    let nest = planBindingNest(bindings, @["limit", "bytesCount"])
    check nest.verdict == bnvPlaced
    check nest.order.mapIt(it.name) == @["bytesCount", "limit"]
    let lowered = lowerObligationToSmt(prop, aufContext(bindings))
    check not lowered.empty
    check lowered.smtScript.contains(
      "(let ((bytesCount (len bytes))) (let ((limit (bvsub bytesCount ")

  test "nesting order is a deterministic function of the bindings":
    let bindings = @[
      bytesCountBinding(),
      IRBinding(name: "limit", value: irBinOp(boSub, countVar(), irLit(1)),
                anchor: "stmt[2]/let", isCompileTime: false, lossFree: true)]
    let prop = irBinOp(boLt, bvVar("limit"), irLit(0))
    let a = planBindingNest(bindings, @["limit", "bytesCount"])
    let b = planBindingNest(bindings, @["bytesCount", "limit"])
    check a.order.mapIt(it.name) == b.order.mapIt(it.name)
    check lowerObligationToSmt(prop, aufContext(bindings)).smtScript ==
          lowerObligationToSmt(prop, aufContext(bindings)).smtScript

  test "a binding nobody mentions is not admitted":
    # `markerPos` in bitsLen is loss-free but absent from the proposition.
    # Carrying it would put a term on the solver's plate that the obligation
    # never needed.
    let bindings = @[
      bytesCountBinding(),
      IRBinding(name: "markerPos", value: irCall("log2trunc", @[bvVar("bytesCount")]),
                anchor: "stmt[3]/let", isCompileTime: false, lossFree: true)]
    let nest = planBindingNest(bindings, @["bytesCount"])
    check nest.verdict == bnvPlaced
    check nest.order.len == 1
    check nest.order[0].name == "bytesCount"

  test "a lossy binding is not admitted":
    # `lossFree` is the statement that nothing inside the defining expression
    # was replaced by a placeholder. A binding that lost something is a fact
    # about the translation, not about the program.
    let lossy = IRBinding(name: "bytesCount", value: lenOfBytes(),
                          anchor: "stmt[1]/let", isCompileTime: false, lossFree: false)
    check admitBindings(@[lossy], @["bytesCount"]).len == 0
    let nest = planBindingNest(@[lossy], @["bytesCount"])
    check nest.verdict == bnvPlaced
    check nest.order.len == 0

  # -------------------------------------------------------------------------
  # Fail-closed orders
  # -------------------------------------------------------------------------

  test "a binding cycle fails closed":
    let bindings = @[
      IRBinding(name: "a", value: bvVar("b"), anchor: "stmt[0]/let",
                isCompileTime: false, lossFree: true),
      IRBinding(name: "b", value: bvVar("a"), anchor: "stmt[1]/let",
                isCompileTime: false, lossFree: true)]
    let nest = planBindingNest(bindings, @["a", "b"])
    check nest.verdict == bnvCycle
    check nest.order.len == 0
    check nest.detail.len > 0

  test "a binding that reads its own name fails closed":
    let bindings = @[
      IRBinding(name: "a", value: irBinOp(boAdd, bvVar("a"), irLit(1)),
                anchor: "stmt[0]/let", isCompileTime: false, lossFree: true)]
    let nest = planBindingNest(bindings, @["a"])
    check nest.verdict == bnvCycle
    check nest.detail.contains("a")

  test "a name recorded twice fails closed":
    # A name bound twice is not an identity: a reference to it selects no
    # single meaning. This is the same ambiguity rule S rejects.
    let bindings = @[
      bytesCountBinding(),
      IRBinding(name: "bytesCount", value: irLit(7), anchor: "stmt[2]/let",
                isCompileTime: false, lossFree: true)]
    let nest = planBindingNest(bindings, @["bytesCount"])
    check nest.verdict == bnvRepeatedName
    check nest.detail.contains("bytesCount")

  test "an unorderable cycle refuses the whole lowering, not just the nest":
    let bindings = @[
      IRBinding(name: "a", value: bvVar("b"), anchor: "stmt[0]/let",
                isCompileTime: false, lossFree: true),
      IRBinding(name: "b", value: bvVar("a"), anchor: "stmt[1]/let",
                isCompileTime: false, lossFree: true)]
    let prop = irBinOp(boAnd, irBinOp(boGe, bvVar("a"), irLit(0)),
                       irBinOp(boGe, bvVar("b"), irLit(0)))
    let lowered = lowerObligationToSmt(prop, aufContext(bindings))
    check lowered.empty
    check lowered.lostInformation
    check lowered.smtScript == ""
    check lowered.errorMsg.contains("cannot order source bindings")

  test "a binding whose value cannot be lowered refuses the script":
    # Emitting the proposition with the binding silently dropped would turn
    # `bytesCount` back into an unconstrained constant and prove a statement
    # the subject never made. `boDiv` is the case that reaches this check: an
    # unlowerable call is already refused by the signature gate.
    let bindings = @[
      IRBinding(name: "bytesCount",
                value: irBinOp(boDiv, bvVar("bytes"), irLit(0)),
                anchor: "stmt[1]/let", isCompileTime: false, lossFree: true)]
    let prop = irBinOp(boGe, countVar(), irLit(0))
    let lowered = lowerObligationToSmt(prop, aufContext(bindings))
    check lowered.empty
    check lowered.lostInformation
    check lowered.errorMsg.contains("bytesCount")

  test "an unadmitted callee inside a binding fails closed":
    let bindings = @[
      IRBinding(name: "bytesCount", value: irCall("log2trunc", @[bytesVar()]),
                anchor: "stmt[1]/let", isCompileTime: false, lossFree: true)]
    let lowered = lowerObligationToSmt(targetProposition(), aufContext(bindings))
    check lowered.empty
    check lowered.lostInformation
    check lowered.errorMsg.contains("log2trunc")

  test "a fact about a let-bound name refuses rather than asserts the wrong thing":
    # Facts are asserted at script scope, OUTSIDE the let. Asserting `x == k`
    # about a top-level free constant when the subject says `x` is let-bound
    # constrains a symbol the subject never quantified — a proof about the
    # wrong program, in the direction that manufactures `unsat`.
    let fact = SemanticFact(
      id: "bytesCount@body",
      proposition: irBinOp(boEq, bvVar("bytesCount"), irLit(4)),
      provenance: FactProvenance(origin: foCompileTimeBinding,
                                 occurrenceRef: "body", sourceRef: ""))
    var ctx = aufContext(@[bytesCountBinding()])
    ctx.semanticFacts = @[fact]
    let lowered = lowerObligationToSmt(targetProposition(), ctx)
    check lowered.empty
    check lowered.lostInformation
    check lowered.errorMsg.contains("bytesCount")

  # -------------------------------------------------------------------------
  # Real Z3
  # -------------------------------------------------------------------------

  test "the emitted script parses and runs on the real z3":
    let z3Bin = resolveZ3()
    check fileExists(z3Bin) or findExe(z3Bin).len > 0
    let lowered = lowerObligationToSmt(targetProposition(),
                                       aufContext(@[bytesCountBinding()]))
    let r = runZ3(z3Bin, lowered.smtScript, "target")
    check r.exitCode == 0
    check not r.outText.contains("(error")
    # The proposition is `bytesCount >= 1`, and `bytesCount` is `len bytes`.
    # Z3 therefore answers sat by choosing `len bytes = 0` — a counterexample,
    # which is the honest machine decision for an openArray index guard.
    check r.outText.strip() == "sat"

  test "the nested two-binding script also runs on the real z3":
    let z3Bin = resolveZ3()
    let bindings = @[
      bytesCountBinding(),
      IRBinding(name: "limit", value: irBinOp(boSub, countVar(), irLit(1)),
                anchor: "stmt[2]/let", isCompileTime: false, lossFree: true)]
    let prop = irBinOp(boLt, bvVar("limit"), irLit(0))
    let lowered = lowerObligationToSmt(prop, aufContext(bindings))
    let r = runZ3(z3Bin, lowered.smtScript, "nested")
    check r.exitCode == 0
    check not r.outText.contains("(error")
    check r.outText.strip() == "sat"

  test "a parallel let with a sibling-dependent RHS is rejected by the real z3":
    # The shape the emitter must never produce, measured rather than assumed.
    let z3Bin = resolveZ3()
    let parallel = """
(set-logic QF_AUFBV)
(declare-fun bytes () (Array (_ BitVec 64) (_ BitVec 64)))
(declare-fun len ((Array (_ BitVec 64) (_ BitVec 64))) (_ BitVec 64))
(assert (not (let ((bytesCount (len bytes)) (limit (bvsub bytesCount #x0000000000000001))) (bvslt limit #x0000000000000000))))
(check-sat)
"""
    let r = runZ3(z3Bin, parallel, "parallel")
    check r.exitCode != 0
    check r.outText.contains("(error")
    check r.outText.contains("unknown constant bytesCount")

  # -------------------------------------------------------------------------
  # The declared logic is the caller's decision
  # -------------------------------------------------------------------------

  test "selectLoweringLogic widens only what the declared logic cannot carry":
    # `bytes` is a list and `len` is uninterpreted: QF_BV cannot carry either.
    check selectLoweringLogic(slQfBv, targetProposition()) == slQfAufbv
    # Already-wide is returned untouched.
    check selectLoweringLogic(slQfAufbv, targetProposition()) == slQfAufbv
    # A pure bit-vector proposition needs nothing QF_BV lacks.
    let pureBv = irBinOp(boGe, bvVar("x"), irLit(0))
    check selectLoweringLogic(slQfBv, pureBv) == slQfBv

  test "the lowerer still refuses a script its declared logic cannot carry":
    # The widening decision lives at the call site; the refusal lives here, so a
    # caller that gets it wrong fails closed instead of shipping an ill-sorted
    # script that Z3 answers on stdout anyway.
    var ctx = aufContext(@[bytesCountBinding()])
    ctx.logic = slQfBv
    let lowered = lowerObligationToSmt(targetProposition(), ctx)
    check lowered.empty
    check lowered.errorMsg.contains("QF_AUFBV")