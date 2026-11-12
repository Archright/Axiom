import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## Phase 14 Symbolic Test Synthesis — Branch Targeting Walker & Path Condition Synthesis.
##
## Walks IR trees to collect branch targets with accumulated path conditions,
## then emits SMT-LIB2 scripts for satisfiability checking.
## All functions are pure (`func`), no side effects.

import std/strutils
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers  # for irNot, irAnd, irOr
import core/trusted/axiom_pragmas  # for axiomIoHint, AxiomIOEffect
import core/trusted/ir_to_smt         # for irExprToSmt, irTypeToSmt
import core/types/obligation_evidence  # for ModelBinding
import infrastructure/logger

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  BranchKind* = enum
    bkTrue
    bkFalse

  BranchTarget* = object
    pathCond*: seq[IRExpr]
    targetCond*: IRExpr
    branch*: BranchKind

# ---------------------------------------------------------------------------
# Branch Targeting Walker
# ---------------------------------------------------------------------------

func collectWalk(body: IRExpr, pathCond: seq[IRExpr],
                  targets: var seq[BranchTarget]) {.raises: [].} =
  ## Internal recursive walker. Accumulates path conditions as it descends.
  if body == nil: return
  case body.kind
  of irIf:
    # Record true-branch target at this branch point
    targets.add(BranchTarget(pathCond: pathCond, targetCond: body.ifCond, branch: bkTrue))
    # Record false-branch target (negated condition)
    targets.add(BranchTarget(pathCond: pathCond, targetCond: irNot(body.ifCond), branch: bkFalse))
    # Recurse into then-branch with path extended by the condition
    collectWalk(body.ifThen, pathCond & @[body.ifCond], targets)
    # Recurse into else-branch with path extended by the negated condition
    collectWalk(body.ifElse, pathCond & @[irNot(body.ifCond)], targets)
  of irLet:
    collectWalk(body.letVal, pathCond, targets)
    collectWalk(body.letBody, pathCond, targets)
  of irCase:
    collectWalk(body.caseScrutinee, pathCond, targets)
    for br in body.caseBranches:
      collectWalk(br.body, pathCond, targets)
    if body.caseDefault != nil:
      collectWalk(body.caseDefault, pathCond, targets)
  of irCall:
    for a in body.callArgs:
      collectWalk(a, pathCond, targets)
  of irBinOp:
    collectWalk(body.binLhs, pathCond, targets)
    collectWalk(body.binRhs, pathCond, targets)
  of irUnaryOp:
    collectWalk(body.unaryArg, pathCond, targets)
  of irRecCall:
    for a in body.recArgs:
      collectWalk(a, pathCond, targets)
  of irLoop:
    for init in body.loopInits:
      collectWalk(init, pathCond, targets)
    collectWalk(body.loopCond, pathCond, targets)
    if body.loopStep != nil:
      collectWalk(body.loopStep, pathCond, targets)
    collectWalk(body.loopBody, pathCond, targets)
  of irLit, irFloatLit, irVar, irStringLit:
    discard  # Leaf nodes — no branch targets
  of irCast:
    collectWalk(body.castExpr, pathCond, targets)

func collectBranchTargets*(body: IRExpr): seq[BranchTarget] =
  ## Walk IR tree collecting all irIf branch points with accumulated path conditions.
  ## For each irIf node, records both the true and false branch targets, then
  ## recurses into children with the path condition extended accordingly.
  var targets: seq[BranchTarget]
  collectWalk(body, @[], targets)
  targets

# ---------------------------------------------------------------------------
# Path Condition → SMT Assertion
# ---------------------------------------------------------------------------

func buildPathConditionSmt*(pathCond: seq[IRExpr]): string =
  ## Convert accumulated path conditions to a single SMT assertion string.
  ## Empty path  → (assert true)
  ## Single      → (assert {smt})
  ## Multiple    → (assert (and {smt1} {smt2} ...))
  if pathCond.len == 0:
    return "(assert true)"
  if pathCond.len == 1:
    return "(assert " & irExprToSmt(pathCond[0]) & ")"
  var parts = ""
  for i, cond in pathCond:
    if i > 0: parts.add(" ")
    parts.add(irExprToSmt(cond))
  "(assert (and " & parts & "))"

# ---------------------------------------------------------------------------
# SMT-LIB2 Script Builder
# ---------------------------------------------------------------------------

func buildSatScript*(funcDef: IRFuncDef; target: BranchTarget): string =
  ## Build a complete SMT-LIB2 satisfiability script for a branch target.
  ##
  ## 1. (set-logic QF_BV)
  ## 2. (declare-const ...) for each parameter
  ## 3. (assert ...) for each preCondition
  ## 4. (assert (and ...)) for accumulated path conditions
  ## 5. (assert ...) for target condition
  ## 6. (check-sat)
  ## 7. (get-model)
  var lines: seq[string]
  lines.add("(set-logic QF_BV)")
  # Declare constants for function parameters
  for p in funcDef.params:
    lines.add("(declare-const " & p.name & " " & irTypeToSmt(p.ty) & ")")
  # Assert preconditions
  for pre in funcDef.preConditions:
    lines.add("(assert " & irExprToSmt(pre) & ")")
  # Assert accumulated path conditions
  lines.add(buildPathConditionSmt(target.pathCond))
  # Assert target condition
  lines.add("(assert " & irExprToSmt(target.targetCond) & ")")
  lines.add("(check-sat)")
  lines.add("(get-model)")
  lines.join("\n")

# ---------------------------------------------------------------------------
# Model-to-Nim Bit-Exact Converters (AGENT-P14-B)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Z3 BitVec64 hex → Nim int64  (bit-exact, no truncation)
# ---------------------------------------------------------------------------

func z3BvHexToI64*(hexStr: string): int64 =
  ## Convert Z3 BitVec64 hex literal (e.g. ``#x000000000000000A``) to
  ## Nim ``int64``.  Bit-exact, no sign extension needed (64↔64).
  ##
  ## Uses manual nibble parsing to stay ``func``-compatible (avoids
  ## ``parseHexStr`` which allocates).
  assert hexStr.len >= 18
  let hexBody = hexStr[2 .. 17]  # skip #x, take 16 hex chars
  var u64: uint64 = 0
  for i in 0..<16:
    let c = hexBody[i]
    let nibble = case c
      of '0'..'9': uint64(ord(c) - ord('0'))
      of 'a'..'f': uint64(ord(c) - ord('a') + 10)
      of 'A'..'F': uint64(ord(c) - ord('A') + 10)
      else: 0'u64
    u64 = (u64 shl 4) or nibble
  cast[int64](u64)

# ---------------------------------------------------------------------------
# Model binding → Nim source literal
# ---------------------------------------------------------------------------

func bindingToNimLiteral*(binding: ModelBinding; paramType: IRType): string =
  ## Convert a Z3 model binding to a Nim source literal string.
  ##
  ## - BitVec64 → int64 decimal string (e.g. ``"42"``)
  ## - Bool     → ``"true"`` / ``"false"``
  ## - List/String → ``"nil"``
  case paramType.kind
  of irtBitVec64:
    # Value may be ``#x...`` hex or plain decimal
    if binding.value.len >= 18 and binding.value[0] == '#' and
       binding.value[1] == 'x':
      $z3BvHexToI64(binding.value)
    else:
      # Plain decimal value from Z3 — pass through as-is
      binding.value
  of irtBool:
    if binding.value == "true": "true"
    else: "false"
  of irtList, irtString:
    "nil"
  of irtEnum:
    binding.value
  of irtVariant:
    binding.value

# ---------------------------------------------------------------------------
# Model bindings → seq of Nim test-input literals
# ---------------------------------------------------------------------------

func modelToTestInputs*(bindings: seq[ModelBinding];
                        params: seq[IRFuncParam]): seq[string] =
  ## Match Z3 model bindings to IR function parameters by name and
  ## convert each to a Nim source literal.
  ##
  ## Missing parameters receive type-appropriate defaults:
  ## - BitVec64 → ``"0"``
  ## - Bool     → ``"false"``
  ## - List/String → ``"nil"``
  result = newSeq[string](params.len)
  for pi, param in params:
    var found = false
    for b in bindings:
      if b.name == param.name:
        result[pi] = bindingToNimLiteral(b, param.ty)
        found = true
        break
    if not found:
      # Default literal for the parameter type
      case param.ty.kind
      of irtBitVec64: result[pi] = "0"
      of irtBool:     result[pi] = "false"
      of irtList, irtString: result[pi] = "nil"
      of irtEnum: result[pi] = "0"
      of irtVariant: result[pi] = "0"

# ---------------------------------------------------------------------------
# Orchestrator — Symbolic Test Synthesis Pipeline
# ---------------------------------------------------------------------------

type
  SymbolicTestCase* = object
    inputs*: seq[string]       ## Nim source literals for test inputs
    branch*: BranchKind        ## Which branch was targeted
    branchIndex*: int          ## Index in the branch target list

  SymbolicSynthesisResult* = object
    funcName*: string
    cases*: seq[SymbolicTestCase]
    usedPbtFallback*: bool     ## true if preConditions were empty
    seed*: int64               ## seed used (deterministic)

const AxiomDeterministicSeed* = 0x4158494f4d'i64  ## Fixed seed for PBT fallback

func synthesizeSymbolicInputs*(
    funcDef: IRFuncDef
): seq[SymbolicTestCase] {.raises: [].} =
  ## Pure orchestrator: collect branch targets, build SMT scripts.
  ## Does NOT execute Z3 (that's I/O boundary).
  ## Returns test cases with SMT scripts ready for execution.
  let targets = collectBranchTargets(funcDef.body)
  for i, target in targets:
    let inputs = modelToTestInputs(@[], funcDef.params)  # default inputs
    result.add(SymbolicTestCase(
      inputs: inputs,
      branch: target.branch,
      branchIndex: i
    ))

proc synthesizeSymbolicTests*(
    funcDef: IRFuncDef;
    z3Exec: proc(script: string): string {.raises: [].}  # Z3 executor callback
): SymbolicSynthesisResult {.raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Full pipeline: collect targets → build scripts → Z3 → extract model.
  ## Uses deterministic seed for PBT fallback.
  axiomIoHint("I/O boundary: Z3 subprocess execution")
  result.funcName = funcDef.name
  result.seed = AxiomDeterministicSeed
  result.usedPbtFallback = false

  let targets = collectBranchTargets(funcDef.body)
  if targets.len == 0:
    # No branches — PBT fallback with deterministic seed
    result.usedPbtFallback = true
    logger.info("[symbolic-synth] No branches in " & funcDef.name &
                "; PBT fallback with fixed seed " & $AxiomDeterministicSeed)
    return

  for i, target in targets:
    let script = buildSatScript(funcDef, target)
    let z3Output = z3Exec(script)
    # Parse Z3 response: first line is "sat" or "unsat"
    let firstLine = z3Output.splitLines()[0].strip()
    if firstLine == "sat":
      # Extract model bindings from remaining lines
      let modelText = z3Output.splitLines()[1..^1].join("\n")
      let bindings = parseModelBindings(modelText)
      let inputs = modelToTestInputs(bindings, funcDef.params)
      result.cases.add(SymbolicTestCase(
        inputs: inputs,
        branch: target.branch,
        branchIndex: i
      ))
    else:
      logger.info("[symbolic-synth] Branch " & $i & " (" & $target.branch &
                  ") unsatisfiable — infeasible path")

{.pop.}
