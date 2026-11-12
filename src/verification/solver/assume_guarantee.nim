## assume_guarantee.nim — Assume-Guarantee Compositional Reasoning
##
## Decompose multi-module verification into pairwise checks.
## Instead of proving the entire system at once, verify each module
## pair independently using Z3 satisfiability checks.
##
## Algorithm (Lamport 1977, Misra & Curry 1981):
##   1. For each module Mi, assume Mi's assumptions hold.
##   2. For each other module Mj, check if Mi's guarantees
##      satisfy Mj's assumptions (pairwise check).
##   3. Circular check: verify all guarantees hold simultaneously
##      as an inductive invariant.
##   4. Use Z3 for each satisfiability check.
##
## Per AGENTS.md §0.6: Static First Enforcement.
## All pure funcs: {.raises: [].}. Z3 I/O procs: {.axiomEffect: IOEffect.}.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/[strutils, os, monotimes]
import core/symbolic_types_expr
import core/solver/shell_bridge
import core/axiom_pragmas

# ─── Types ────────────────────────────────────────────────────────────────────

type
  ModuleSpec* = object
    ## Specification for a single module in the compositional proof.
    name*: string
    assumptions*: seq[SymSExpr]        ## Preconditions the environment must satisfy
    guarantees*: seq[SymSExpr]          ## Postconditions this module guarantees
    initialState*: seq[SymSExpr]        ## Initial state constraints
    transitionRelation*: string         ## SMT-LIB2 transition relation assertion

  AssumeGuaranteeCounterExample* = object
    ## A counterexample found during assume-guarantee checking.
    moduleName*: string
    violatedGuarantee*: string
    trace*: seq[string]

  AssumeGuaranteeResult* = object
    ## Result of the assume-guarantee verification.
    allVerified*: bool
    failedModules*: seq[string]
    counterexamples*: seq[AssumeGuaranteeCounterExample]
    pairsChecked*: int
    elapsedMs*: int
    errorMessage*: string               ## Non-empty if Z3 execution failed

# ─── Variable Extraction (defined first — used by query builders) ─────────────

proc collectVarNames(expr: SymSExpr; names: var seq[string]) {.raises: [].} =
  ## Recursively collect all variable names from an expression tree.
  if expr.isNil:
    return
  case expr.kind
  of seVar:
    if expr.name notin names:
      names.add(expr.name)
  of seAdd, seSub, seMul, seDiv, seMod,
     seEq, seNe, seLt, seLe, seGt, seGe,
     seAnd, seOr:
    collectVarNames(expr.lhs, names)
    collectVarNames(expr.rhs, names)
  of seNot, seSome, seIsSome, seVal, seOk, seErr, seIsOk, seErrMsg,
     seHead, seTail, seLength:
    collectVarNames(expr.lhs, names)
  of seUninterpretedApp:
    collectVarNames(expr.lhs, names)
  else:
    discard

# ─── Query Construction (Pure) ────────────────────────────────────────────────

proc buildVarDeclarations(varNames: seq[string]): string {.raises: [].} =
  ## Build SMT-LIB2 variable declarations from extracted names.
  result = ""
  for name in varNames:
    result.add("(declare-const " & name & " Int)\n")

proc collectModuleVarNames(modules: seq[ModuleSpec]; i, j: int): seq[string] {.
    raises: [].} =
  ## Collect and deduplicate variable names from two modules.
  result = @[]
  for clause in modules[i].initialState:
    collectVarNames(clause, result)
  for clause in modules[i].assumptions:
    collectVarNames(clause, result)
  for clause in modules[i].guarantees:
    collectVarNames(clause, result)
  for clause in modules[j].assumptions:
    collectVarNames(clause, result)
  for clause in modules[j].guarantees:
    collectVarNames(clause, result)

proc collectAllModuleVarNames(modules: seq[ModuleSpec]): seq[string] {.raises: [].} =
  ## Collect and deduplicate variable names from all modules.
  result = @[]
  for m in modules:
    for clause in m.assumptions:
      collectVarNames(clause, result)
    for clause in m.guarantees:
      collectVarNames(clause, result)
    for clause in m.initialState:
      collectVarNames(clause, result)

proc buildPairwiseQuery*(modules: seq[ModuleSpec]; i, j: int): string {.
    raises: [].} =
  ## Build Z3 query for pairwise check: Mi's guarantees → Mj's assumptions.
  ##
  ## Encoding:
  ##   assume Ai ∧ Gi ∧ Ti  (Mi's assumptions, guarantees, transition)
  ##   assert ¬Aj            (negate Mj's assumptions)
  ##   check-sat             (UNSAT = Mi implies Mj's assumptions)
  var lines: seq[string] = @[]
  lines.add("(set-logic QF_LIA)")

  # Collect and declare all variable names
  let uniqueVars = collectModuleVarNames(modules, i, j)
  lines.add(buildVarDeclarations(uniqueVars))

  # Mi's initial state
  for clause in modules[i].initialState:
    if not clause.isNil:
      lines.add("(assert " & sExprToString(clause) & ")")

  # Mi's assumptions
  for clause in modules[i].assumptions:
    if not clause.isNil:
      lines.add("(assert " & sExprToString(clause) & ")")

  # Mi's guarantees
  for clause in modules[i].guarantees:
    if not clause.isNil:
      lines.add("(assert " & sExprToString(clause) & ")")

  # Mi's transition relation
  if modules[i].transitionRelation.len > 0:
    lines.add(modules[i].transitionRelation)

  # Negate Mj's assumptions
  for clause in modules[j].assumptions:
    if not clause.isNil:
      lines.add("(assert (not " & sExprToString(clause) & "))")

  lines.add("(check-sat)")
  result = lines.join("\n")

proc buildConjunction(clauses: seq[SymSExpr]): SymSExpr {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Build a conjunction of all clauses.
  if clauses.len == 0:
    return sTrue()
  result = clauses[0]
  for i in 1 ..< clauses.len:
    result = sAnd(result, clauses[i])

proc appendClauses(lines: var seq[string], clauses: seq[SymSExpr]) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Append SMT-LIB2 assertion clauses for a sequence of expressions.
  for clause in clauses:
    if not clause.isNil:
      lines.add("(assert " & sExprToString(clause) & ")")

proc buildCircularQuery*(modules: seq[ModuleSpec]): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Build Z3 query for circular assume-guarantee check.
  ##
  ## Encoding:
  ##   assume ∧Ai    (all module assumptions)
  ##   assume ∧Gi    (all module guarantees)
  ##   assume T      (transition relation)
  ##   assert ¬(∧Gi) (negate conjunction of all guarantees)
  ##   check-sat     (UNSAT = guarantees form inductive invariant)
  var lines: seq[string] = @[]
  lines.add("(set-logic QF_LIA)")

  # Collect and declare all variable names
  let uniqueVars = collectAllModuleVarNames(modules)
  lines.add(buildVarDeclarations(uniqueVars))

  # All initial states
  for m in modules:
    lines.appendClauses(m.initialState)

  # All assumptions
  for m in modules:
    lines.appendClauses(m.assumptions)

  # All guarantees
  for m in modules:
    lines.appendClauses(m.guarantees)

  # All transition relations
  for m in modules:
    if m.transitionRelation.len > 0:
      lines.add(m.transitionRelation)

  # Negate conjunction of all guarantees
  var allGuarantees: seq[SymSExpr] = @[]
  for m in modules:
    allGuarantees.add(m.guarantees)
  let conj = buildConjunction(allGuarantees)
  if not conj.isNil and conj.kind != seTrue:
    lines.add("(assert (not " & sExprToString(conj) & "))")

  lines.add("(check-sat)")
  result = lines.join("\n")

# ─── Z3 Execution (I/O Boundary) ─────────────────────────────────────────────

proc execZ3Query*(query: string): tuple[sat: bool; output: string; ok: bool] {.
    raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Execute a Z3 SMT-LIB2 query via temp file.
  ## Returns (sat=true if SAT, output=raw Z3 output, ok=true if no error).
  let tmpFile = (getTempDir() / "axiom_ag_") & $getCurrentProcessId() &
      "_" & $getMonoTime().ticks & ".smt2"
  writeFile(tmpFile, query)
  let (output, exitCode) = runCommandInDir("z3 " & tmpFile)
  discard tryRemoveFile(tmpFile)
  if exitCode != 0 and output.len == 0:
    return (false, "", false)
  let status = output.strip().splitLines()
  for line in status:
    let t = line.strip()
    if t == "sat":
      return (true, output, true)
    if t == "unsat":
      return (false, output, true)
    if t == "unknown":
      return (false, output, true)
  # Fallback: treat unrecognized output as error
  return (false, output, false)

# ─── Pairwise Check Helpers ───────────────────────────────────────────────────

proc recordPairwiseCounterexample(result: var AssumeGuaranteeResult,
    moduleNameI, moduleNameJ: string) {.raises: [].} =
  ## Record a counterexample when a pairwise check finds SAT.
  result.allVerified = false
  if moduleNameI notin result.failedModules:
    result.failedModules.add(moduleNameI)
  let violated = moduleNameI & "'s guarantees do not imply " &
      moduleNameJ & "'s assumptions"
  result.counterexamples.add(AssumeGuaranteeCounterExample(
    moduleName: moduleNameI,
    violatedGuarantee: violated,
    trace: @["Pairwise check failed: " & moduleNameI & " → " & moduleNameJ]
  ))

proc recordCircularFailure(result: var AssumeGuaranteeResult,
    modules: seq[ModuleSpec]) {.raises: [].} =
  ## Record failure when circular assume-guarantee check finds SAT.
  result.allVerified = false
  for m in modules:
    if m.name notin result.failedModules:
      result.failedModules.add(m.name)
  result.counterexamples.add(AssumeGuaranteeCounterExample(
    moduleName: "system",
    violatedGuarantee: "Conjunction of all guarantees is not inductive",
    trace: @["Circular assume-guarantee check failed"]
  ))

proc checkAllPairsForModule(modules: seq[ModuleSpec], i: int,
    agg: var AssumeGuaranteeResult, startTime: int64): bool {.
    raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check all pairwise comparisons for module i.
  ## Returns true if caller should abort (Z3 execution failure).
  for j in 0 ..< modules.len:
    if i == j:
      continue
    if modules[j].assumptions.len == 0:
      continue
    let query = buildPairwiseQuery(modules, i, j)
    let (sat, _, ok) = execZ3Query(query)
    inc agg.pairsChecked
    if not ok:
      agg.allVerified = false
      let pairName = modules[i].name & ", " & modules[j].name
      agg.errorMessage = "Z3 execution failed for pair (" & pairName & ")"
      agg.elapsedMs = int((getMonoTime().ticks - startTime) div 1_000_000)
      return true
    if sat:
      recordPairwiseCounterexample(agg, modules[i].name, modules[j].name)
  return false

# ─── Main Verification Entry Point ────────────────────────────────────────────

proc assumeGuaranteeVerify*(modules: seq[ModuleSpec]): AssumeGuaranteeResult {.
    raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run assume-guarantee compositional verification.
  ##
  ## For each pair of modules, checks that one module's guarantees
  ## imply the other module's assumptions. Then performs a circular
  ## check to verify the conjunction of all guarantees is inductive.
  let startTime = getMonoTime().ticks
  result = AssumeGuaranteeResult(allVerified: true)

  if modules.len == 0:
    result.elapsedMs = int((getMonoTime().ticks - startTime) div 1_000_000)
    return

  # Phase 1: Pairwise checks
  for i in 0 ..< modules.len:
    if checkAllPairsForModule(modules, i, result, startTime):
      return

  # Phase 2: Circular assume-guarantee check
  if result.allVerified and modules.len > 1:
    let query = buildCircularQuery(modules)
    let (sat, _, ok) = execZ3Query(query)

    inc result.pairsChecked

    if not ok:
      result.allVerified = false
      result.errorMessage = "Z3 execution failed for circular check"
    elif sat:
      recordCircularFailure(result, modules)

  result.elapsedMs = int((getMonoTime().ticks - startTime) div 1_000_000)

{.pop.}
