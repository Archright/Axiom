import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Axiom Verification Context — Constraint Accumulation + Unsat-Core Diagnostics
##
## Unifies Boundary Extractor static bounds with AST Mapper dynamic steps
## into a single SMT-LIB2 script. Supports named assertions for unsat-core
## extraction when constraints conflict (Gemini Patch #3: set-option must be
## at global header, so this module emits only declare-fun / assert / check-sat).

import std/strutils
import std/sequtils
import core/logic/smt_logic
import core/parsers/safe_parsers
import core/types/results
import core/types/domain_types
export domain_types.ConstraintKind
export domain_types.VerificationConstraint
export domain_types.AxiomVerificationContext

func addConstraint*(ctx: var AxiomVerificationContext; kind: ConstraintKind;
                    expression, source: string) {.raises: [].} =
  ctx.constraints.add(VerificationConstraint(
    kind: kind,
    expression: expression,
    source: source
  ))

func conjoinConstraints*(ctx: AxiomVerificationContext): string {.raises: [].} =
  ## Generate the assertion body of an SMT-LIB2 script.
  ##
  ## NOTE: `(set-logic ...)` and `(set-option :produce-unsat-cores true)`
  ## MUST be emitted by the orchestrator at the GLOBAL HEADER level,
  ## before any declare-fun (Gemini Patch #3).
  ##
  ## Each assertion is named (`:named cN`) so `(get-unsat-core)` can map
  ## conflicting constraints back to their sources.
  for i, c in ctx.constraints:
    result.add("(assert (! " & c.expression & " :named c" & $i & "))\n")
  result.add("(check-sat)\n")
  if ctx.constraints.len > 0:
    result.add("(get-unsat-core)\n")

func emitAssertionLines*(ctx: AxiomVerificationContext): string {.raises: [].} =
  ## Emit only the named assertion lines (without check-sat / get-unsat-core)
  ## for merging into an existing SMT-LIB2 script.
  for i, c in ctx.constraints:
    result.add("(assert (! " & c.expression & " :named c" & $i & "))\n")

func extractConflictSources*(ctx: AxiomVerificationContext;
                             unsatCoreLine: string): seq[string] {.raises: [].} =
  ## Map a `(get-unsat-core)` result like `(c0 c3 c7)` back to human-readable
  ## source strings from the VerificationConstraint records.
  let stripped = unsatCoreLine.strip()
  if stripped.len < 2: return @[]
  let inner = stripped[1 ..< stripped.high]  ## drop surrounding parens
  for token in inner.splitWhitespace():
    if token.len < 2 or token[0] != 'c': continue
    let idxStr = token[1 ..< token.len]
    let idx = safeParseInt(idxStr).getOrDefault(-1)
    if idx >= 0 and idx < ctx.constraints.len:
      result.add(ctx.constraints[idx].source)

func addHornRelation*(ctx: var AxiomVerificationContext;
                        decl: string) {.raises: [].} =
  ctx.hornRelations.add(decl)

func addHornRule*(ctx: var AxiomVerificationContext;
                  rule: string) {.raises: [].} =
  ctx.hornRules.add(rule)

func addHornQuery*(ctx: var AxiomVerificationContext;
                   query: string) {.raises: [].} =
  ctx.hornQueries.add(query)

func emitHornScript*(ctx: AxiomVerificationContext): string {.raises: [].} =
  ## Emit a complete HORN/SPACER SMT-LIB2 script.
  ##
  ## Includes: set-logic, relation declarations, rules, queries.
  ## Does NOT include standard (assert) constraints — HORN uses rules.
  result.add(emitLogicHeader(ctx.logic) & "\n")
  for decl in ctx.hornRelations:
    result.add(decl & "\n")
  for rule in ctx.hornRules:
    result.add(rule & "\n")
  for query in ctx.hornQueries:
    result.add(query & "\n")

func emitDeclarations*(ctx: AxiomVerificationContext;
                       stateSpace: seq[string]): string {.raises: [].} =
  ## Emit variable declarations for all symbols in the state space.
  for symbol in stateSpace.deduplicate():
    if symbol.len > 0 and symbol[0] notin {'0'..'9'}:
      result.add(emitVariableDeclaration(symbol, ctx.logic) & "\n")

func buildSmtScript*(ctx: var AxiomVerificationContext;
                      stateSpace: seq[string];
                      transitionAssertions: seq[string] = @[]): string {.raises: [].} =
  ## Convenience: declarations + accumulated constraints + optional
  ## transition assertions (from AST mapper) in one script body.
  ## Uses `var` because transition assertions are appended to the context.
  result.add(emitDeclarations(ctx, stateSpace))
  for assertion in transitionAssertions:
    if assertion.len > 0:
      addConstraint(ctx, ckDynamicStep, assertion, "ast-mapper")
  result.add(conjoinConstraints(ctx))

{.pop.}
