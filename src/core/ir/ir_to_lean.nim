{.push raises: [].}
import std/[options, sequtils, strutils, strformat, streams]
import osproc
import core/trusted/effect_bridge
import ir_types

proc escapeLeanKeyword*(identifier: string): string =
  const leanKeywords = ["result", "type", "def", "theorem", "fun", "match", "prop"]
  if identifier in leanKeywords:
    "«" & identifier & "»"
  else:
    identifier

proc renderIRExpr*(expr: IRExpr): string =
  case expr.kind
  of ieVar: escapeLeanKeyword(expr.varName)
  of ieConst: expr.val
  of ieBinaryOp: &"({renderIRExpr(expr.left)} {expr.op} {renderIRExpr(expr.right)})"
  of ieApp: &"{expr.fnName} " & expr.args.map(renderIRExpr).join(" ")
  of ieRefinement: &"{{{escapeLeanKeyword(expr.refVarName)} : {expr.refBaseType} // {renderIRExpr(expr.predicate)}}}"

proc selectFastTactic*(ir: AxiomIRNode): string =
  ## Tier 1: Fast Path
  if ir.preConditions.len == 0 and ir.postCondition.isNone():
    return "by rfl"
  else:
    return "by simp [*]"

proc verifyInLeanRepl*(leanCode: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Communicate with Lean through stdin and return true only when Lean accepts the tactic block.
  var process: Process
  try:
    process = startProcess("lean", args = ["--stdin"], options = {poUsePath, poStdErrToStdOut})
    defer: process.close()

    process.inputStream.write(leanCode)
    process.inputStream.close()

    let exitCode = process.waitForExit(5000)
    if exitCode == -1:
      return false

    let output = process.outputStream.readAll()
    let lowered = output.toLowerAscii()
    if "error:" in lowered or "sorry" in lowered:
      return false
    return exitCode == 0
  except CatchableError:
    return false

proc irToLeanRefinedDefinition*(ir: AxiomIRNode): Option[string]

proc generateOptimalTactic*(ir: AxiomIRNode): Option[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let leanCodeOpt = irToLeanRefinedDefinition(ir)
  if leanCodeOpt.isNone:
    return none(string)
  let leanCode = leanCodeOpt.get
  let fastTactic = selectFastTactic(ir)
  # irToLeanRefinedDefinition emits a full theorem with a default tactic body
  # ("by intros simp [*]"). Strip that body so the fast tactic becomes the
  # theorem body — appending a second tactic block is invalid Lean.
  let statement = leanCode.split(":=\n", 1)[0].strip & " :="
  let testCode = statement & "\n  " & fastTactic
  if verifyInLeanRepl(testCode):
    echo "[Tier 1] Fast Path succeeded: ", fastTactic
    return some(fastTactic)
  none(string)

proc irToLeanRefinedDefinition*(ir: AxiomIRNode): Option[string] =
  var paramStrs: seq[string] = @[]

  for p in ir.params:
    let escapedName = escapeLeanKeyword(p.name)
    if p.refinement.isSome:
      let pred = renderIRExpr(p.refinement.get)
      paramStrs.add(&"({escapedName} : {{{escapedName} : {p.typeStr} // {pred}}})")
    else:
      paramStrs.add(&"({escapedName} : {p.typeStr})")

  for idx, pre in ir.preConditions:
    paramStrs.add(&"(h_pre{idx} : {renderIRExpr(pre)})")

  let sig = paramStrs.join(" ")
  let paramNames = ir.params.mapIt(escapeLeanKeyword(it.name)).join(" ")

  let targetProp = if ir.postCondition.isSome:
                     renderIRExpr(ir.postCondition.get)
                   else:
                     &"{ir.name} {paramNames} = {ir.name} {paramNames}"

  let tactic = "by\n  intros\n  simp [*]"

  some(&"theorem {ir.name}_spec {sig} : {targetProp} :=\n  {tactic}\n")

proc encodeLeanTheoremFromIr*(ir: AxiomIRNode; depth: int = 10; timeoutMs: int = 10000): Option[string] =
  let theoremStmtOpt = irToLeanRefinedDefinition(ir)
  if theoremStmtOpt.isNone:
    return none(string)
  let theoremStmt = theoremStmtOpt.get.replace("==", "=")
  some("(set-option :timeout " & $timeoutMs & ")\n" &
    "(assert (not " & theoremStmt & "))\n" &
    "(check-sat)\n" &
    "; Axiom Z3 BMC depth: " & $depth & "\n")

proc irToLeanDefinition*(ir: AxiomIRNode): string =
  var paramStrs: seq[string] = @[]
  for p in ir.params:
    let escapedName = escapeLeanKeyword(p.name)
    if p.refinement.isSome:
      let refStr = renderIRExpr(p.refinement.get)
      paramStrs.add(&"({escapedName} : {refStr})")
    else:
      paramStrs.add(&"({escapedName} : {p.typeStr})")

  let sig = paramStrs.join(" ")
  let paramNames = ir.params.mapIt(escapeLeanKeyword(it.name)).join(" ")
  var proofStrategy = "by simp"

  for p in ir.params:
    if "List" in p.typeStr or "MyList" in p.typeStr:
      let escapedName = escapeLeanKeyword(p.name)
      proofStrategy = &"by\n  induction {escapedName} with\n  | nil => rfl\n  | cons head tail ih => simp [ih]"
      break

  let targetProp = if ir.postCondition.isSome:
                     renderIRExpr(ir.postCondition.get)
                   else:
                     &"{ir.name} {paramNames} = {ir.name} {paramNames}"

  result = &"theorem {ir.name}_auto {sig} : {targetProp} :=\n  {proofStrategy}\n"
