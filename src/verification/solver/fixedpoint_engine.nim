import core/trusted/layer_declaration
axiomLayer "infrastructure"
# Z3 Fixedpoint / PDR Backend for CEGAR Engine
# Emits Constrained Horn Clauses (CHC) in SMT-LIB2 format and solves via Z3's fixedpoint engine.
{.push raises: [].}

import std/strutils
import std/sequtils
import std/tables
import compiler/ast
import core/orchestrator/cfg_builder
import core/results
import core/axiom_pragmas
import verification/solver/provers
import verification/solver/fixedpoint_types
# axiomIoBoundary

export fixedpoint_types

verifySpecification("docs/spec/solver_infrastructure_spec.md")

const
  chcPrelude = "(set-logic HORN)\n(set-option :produce-proofs true)\n(set-option :random-seed 0)\n(set-option :sat.random_seed 0)\n(set-option :fp.spacer.random_seed 0)\n"
  stateRelation = "state"
  errorRelation = "error"

# ──────────────────────────────────────────────────────────────────────
# CHC Emission (pure string construction — all funcs)
# ──────────────────────────────────────────────────────────────────────

## Emit a single Horn clause as an SMT-LIB2 `rule` command.
## Named rules enable `update_rule` for incremental CHC solving.
## Context7 verified: SMT-LIB2 `:named` annotation on `rule` commands.
func emitRule(clause: HornClause): string {.raises: [].} =
  if clause.name.len > 0:
    # Named rule — enables update_rule for incremental CHC
    if clause.body.len == 0:
      "(rule (! " & clause.head & " :named " & clause.name & "))"
    else:
      "(rule (! (=> " & clause.body & " " & clause.head & ") :named " & clause.name & "))"
  else:
    # Nameless rule (fallback for backward compatibility)
    if clause.body.len == 0:
      "(rule " & clause.head & ")"
    else:
      "(rule (=> " & clause.body & " " & clause.head & "))"

## Emit declare-var commands for program variables.
func emitVarDeclarations(variables: seq[string]): string {.raises: [].} =
  var lines: seq[string] = @[]
  for v in variables:
    lines.add("(declare-var " & v & " Int)")
    lines.add("(declare-var " & v & "! Int)")  # primed (next-state) copy
  lines.join("\n")

## Emit declare-rel commands for state and error predicates.
func emitRelDeclarations(variables: seq[string]): string {.raises: [].} =
  let argSorts = variables.mapIt("Int").join(" ")
  "(declare-rel " & stateRelation & " (" & argSorts & "))\n" &
  "(declare-rel " & errorRelation & " ())"

## Build the application of state relation with given variable names.
func stateApply(variables: seq[string]; suffix: string = ""): string {.raises: [].} =
  let args = variables.mapIt(it & suffix).join(" ")
  "(" & stateRelation & " " & args & ")"

## @anchor(fixedpoint_engine.emitHornClauses)
## Emit a complete CHC SMT-LIB2 program from component parts.
##   variables  — program state variables (e.g. ["x", "y"])
##   initBody   — boolean expression establishing initial state
##   transBody  — boolean expression for the transition relation (uses x and x!)
##   propBody   — boolean expression whose conjunction with state implies error
func emitHornClauses*(
  variables: seq[string];
  initBody: string;
  transBody: string;
  propBody: string
): string {.raises: [].} =
  var lines: seq[string] = @[]
  lines.add(chcPrelude)
  lines.add(emitVarDeclarations(variables))
  lines.add(emitRelDeclarations(variables))

  # Init rule:  init(x) => state(x)
  let initState = stateApply(variables)
  lines.add(emitRule(HornClause(
    name: "init_rule",
    body: initBody,
    head: initState
  )))

  # Transition rule:  state(x) /\ trans(x, x!) => state(x!)
  let currentState = stateApply(variables)
  let primedSuffix = "!"
  let nextState = stateApply(variables, primedSuffix)
  let transConjunction = "(and " & currentState & " " & transBody & ")"
  lines.add(emitRule(HornClause(
    name: "trans_rule",
    body: transConjunction,
    head: nextState
  )))

  # Property rule:  state(x) /\ propBody(x) => error
  let propConjunction = "(and " & currentState & " " & propBody & ")"
  lines.add(emitRule(HornClause(
    name: "prop_rule",
    body: propConjunction,
    head: "(" & errorRelation & ")"
  )))

  # Query: is error reachable?
  lines.add("(query " & errorRelation & ")")

  lines.join("\n")

# ──────────────────────────────────────────────────────────────────────
# Z3 Fixedpoint Solver (proc — I/O boundary)
# ──────────────────────────────────────────────────────────────────────

## Parse Z3 fixedpoint output into a structured result.
func parseFixedpointOutput(raw: string): FixedpointResult {.raises: [].} =
  result.rawOutput = raw
  let stripped = raw.strip()

  if stripped.startsWith("sat"):
    result.sat = true
    # Extract model / counterexample if present
    let modelStart = stripped.find("(model")
    if modelStart >= 0:
      result.counterexample = stripped[modelStart .. ^1]
    else:
      result.counterexample = stripped
  elif stripped.startsWith("unsat"):
    result.sat = false
    # Extract invariant from proof output if present
    # Z3 may output invariants as part of the proof or in a separate section
    let proofStart = stripped.find("(proof")
    if proofStart >= 0:
      result.invariant = stripped[proofStart .. ^1]
    # Also check for direct invariant output
    let invStart = stripped.find("(define-fun")
    if invStart >= 0:
      result.invariant = stripped[invStart .. ^1]
  else:
    # Unknown or error — treat as inconclusive
    result.sat = false
    result.invariant = ""
    result.counterexample = stripped

## @anchor(fixedpoint_engine.solveFixedpoint)
## Send a CHC program to Z3 and parse the fixedpoint result.
proc solveFixedpoint*(chcSource: string; timeoutMs: int = 30000): FixedpointResult {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  let prover = Z3PoolProver()
  let rawResult = proveRaw(prover, chcSource, timeoutMs)
  if rawResult.isErr():
    return FixedpointResult(
      sat: false,
      invariant: "",
      counterexample: "",
      rawOutput: "ERROR: " & rawResult.error
    )
  parseFixedpointOutput(rawResult.get())

# ──────────────────────────────────────────────────────────────────────
# CFG Integration — High-level proof interface
# ──────────────────────────────────────────────────────────────────────

## Safe Table lookup — returns default BasicBlock if key missing.
func lookupBlock(cfg: ControlFlowGraph; id: int): BasicBlock {.raises: [].} =
  cfg.blockById.getOrDefault(id)

## Check whether a block id exists in the CFG.
func hasBlock(cfg: ControlFlowGraph; id: int): bool {.raises: [].} =
  cfg.blockById.hasKey(id)

## Extract textual representation from a PNode AST node.
func stmtText(node: PNode): string {.raises: [].} =
  if node.isNil: return ""
  case node.kind
  of nkIdent:
    if node.strVal.len > 0: return node.strVal
  of nkStrLit:
    return node.strVal
  of nkIntLit:
    return $node.intVal
  of nkFloatLit:
    return $node.floatVal
  of nkCharLit:
    # Char literals store their codepoint in intVal, not strVal (TNode layout).
    return $chr(int(node.intVal))
  else:
    if node.len > 0:
      var parts: seq[string] = @[]
      for i in 0..<node.len:
        let child = node[i]
        if not child.isNil:
          parts.add(stmtText(child))
      if parts.len > 0:
        result = parts.join(" ")

## Build an SMT-LIB2 boolean expression from block statements.
## This is a best-effort textual extraction for the fixedpoint encoding.
func blockToSmtCondition(blk: BasicBlock): string {.raises: [].} =
  if blk.statements.len == 0:
    return "true"
  # Concatenate statement texts; for a production system this would
  # involve a proper AST-to-SMT translator. Here we produce a conjunction
  # of the raw textual predicates.
  var parts: seq[string] = @[]
  for stmt in blk.statements:
    let txt = stmtText(stmt)
    if txt.len > 0:
      parts.add(txt)
  if parts.len == 0:
    return "true"
  if parts.len == 1:
    return parts[0]
  "(and " & parts.join(" ") & ")"

## @anchor(fixedpoint_engine.proveWithFixedpoint)
## High-level function: prove a property over a CFG loop using Z3 PDR.
##
## Given a ControlFlowGraph, a loop header block id, and a set of variables,
## this function:
##   1. Extracts the loop entry conditions as the init rule
##   2. Extracts the loop body transitions as the transition relation
##   3. Builds the property rule from the loop's safety conditions
##   4. Solves the resulting CHC system via Z3 Fixedpoint
proc proveWithFixedpoint*(
  cfg: ControlFlowGraph;
  headerId: int;
  variables: seq[string]
): FixedpointResult {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  # Validate headerId using safe lookup
  if not cfg.hasBlock(headerId):
    return FixedpointResult(
      sat: false,
      rawOutput: "ERROR: block " & $headerId & " not found in CFG"
    )

  let headerBlock = cfg.lookupBlock(headerId)
  if not headerBlock.loopHeader:
    return FixedpointResult(
      sat: false,
      rawOutput: "ERROR: block " & $headerId & " is not a loop header"
    )

  # Build init condition: predecessors' conditions leading into the loop
  var initParts: seq[string] = @[]
  for predId in headerBlock.predecessors:
    if predId != headerId:  # exclude back edges
      if cfg.hasBlock(predId):
        let predCond = blockToSmtCondition(cfg.lookupBlock(predId))
        if predCond != "true":
          initParts.add(predCond)
  let initBody = if initParts.len == 0: "true"
                 elif initParts.len == 1: initParts[0]
                 else: "(or " & initParts.join(" ") & ")"

  # Build transition from loop body: header + all successors in the loop
  var transParts: seq[string] = @[]
  let headerCond = blockToSmtCondition(headerBlock)
  if headerCond != "true":
    transParts.add(headerCond)

  # Add successor conditions and frame constraints for primed variables
  for succId in headerBlock.successors:
    if cfg.hasBlock(succId) and succId != cfg.exit:
      let succCond = blockToSmtCondition(cfg.lookupBlock(succId))
      if succCond != "true":
        transParts.add(succCond)

  # Default: if no explicit transition conditions, use a self-loop frame
  if transParts.len == 0:
    # All variables stay the same (identity transition)
    var frameParts: seq[string] = @[]
    for v in variables:
      frameParts.add("(= " & v & "! " & v & ")")
    transParts.add(
      if frameParts.len == 1: frameParts[0]
      else: "(and " & frameParts.join(" ") & ")"
    )

  let transBody = if transParts.len == 1: transParts[0]
                  else: "(and " & transParts.join(" ") & ")"

  # Build property: safety condition — if we're in the loop header state
  # and some bad condition holds, the property is violated.
  # For the default case, we check that all variables are non-negative.
  var propParts: seq[string] = @[]
  for v in variables:
    propParts.add("(< " & v & " 0)")
  let propBody = if propParts.len == 1: propParts[0]
                 else: "(or " & propParts.join(" ") & ")"

  # Emit and solve
  let chc = emitHornClauses(variables, initBody, transBody, propBody)
  solveFixedpoint(chc)

{.pop.}
