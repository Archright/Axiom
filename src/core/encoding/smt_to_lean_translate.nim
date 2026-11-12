import core/trusted/layer_declaration
axiomLayer "domain"
import core/encoding/smt_to_lean_codegen
import std/strutils
import std/tables
import std/options
import core/trusted/axiom_pragmas

{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## SMT-to-Lean Bridge — Translate (Lean side)
##
## Primitive proof assembly, Lean proof script generation from Z3 traces,
## Lean source sanitization, and Lean theorem code generation.
## Extracted from smt_to_lean_bridge.nim as part of 2-way split.

# ---------------------------------------------------------------------------
# Primitive Proof Helpers
# ---------------------------------------------------------------------------

func primitiveProofIndent(depth: int): string {.raises: [].} =
  for _ in 0 ..< depth:
    result.add("  ")

func primitiveNonnegativeProof(
  expr: SExprNode;
  declTypes: Table[string, string];
  prefix: string
): string {.raises: [].} =
  if expr.children.len < 3 or expr.children[0].atom != ">=":
    return ""
  if expr.children[2].atom != "0":
    return ""

  let left = expr.children[1]
  if left.isList and left.children.len >= 2 and left.children[0].atom in ["str.len", "seq.len"]:
    return prefix & "simpa using h_sys\n"

  let varNameRes = smtExprToLeanExpr(left, declTypes)
  if not varNameRes.ok: return ""
  let varName = varNameRes.value
  let varType = declTypes.getOrDefault(varName, "Int")
  if varType == "Nat" or varType == "nat":
    return prefix & "exact Nat.zero_le " & varName & "\n"
  prefix & "simpa using h_sys\n"

func primitiveReflexivityProof(expr: SExprNode; declTypes: Table[string, string]; prefix: string): string {.raises: [].} =
  if expr.children.len < 3 or expr.children[0].atom != "=":
    return ""
  let leftNameRes = smtExprToLeanExpr(expr.children[1], declTypes)
  if not leftNameRes.ok: return ""
  let leftName = leftNameRes.value
  let rightNameRes = smtExprToLeanExpr(expr.children[2], declTypes)
  if not rightNameRes.ok: return ""
  let rightName = rightNameRes.value
  if leftName != rightName:
    return ""
  prefix & "exact Eq.refl " & leftName & "\n"

func primitiveDirectProof(expr: SExprNode; declTypes: Table[string, string]): string {.raises: [].} =
  let nonnegative = primitiveNonnegativeProof(expr, declTypes, "  ")
  if nonnegative.len > 0:
    return nonnegative
  primitiveReflexivityProof(expr, declTypes, "  ")

func primitiveBulletProof(
  sub: SExprNode;
  declTypes: Table[string, string];
  depth: int
): string {.raises: [].} =
  let prefix = primitiveProofIndent(depth) & "· "
  if sub.isList and sub.children.len >= 3:
    let nonnegative = primitiveNonnegativeProof(sub, declTypes, prefix)
    if nonnegative.len > 0:
      return nonnegative
    if sub.children[0].atom == "or":
      return prefix & "simp\n"
  prefix & "exact trivial\n"

func buildPrimitiveAndTactics(
  subExpr: SExprNode;
  declTypes: Table[string, string];
  depth: int;
  tactics: var string
) {.raises: [].} =
  if not (subExpr.isList and subExpr.children.len >= 2 and subExpr.children[0].atom == "and"):
    tactics.add(primitiveBulletProof(subExpr, declTypes, depth))
    return

  let indent = primitiveProofIndent(depth)
  tactics.add(primitiveBulletProof(subExpr.children[1], declTypes, depth))
  if subExpr.children.len > 3:
    tactics.add(indent & "· constructor\n")
    var remaining = SExprNode(isList: true, children: @[SExprNode(isList: false, atom: "and")])
    for i in 2 ..< subExpr.children.len:
      remaining.children.add(subExpr.children[i])
    buildPrimitiveAndTactics(remaining, declTypes, depth + 1, tactics)
  elif subExpr.children.len == 3:
    tactics.add(primitiveBulletProof(subExpr.children[2], declTypes, depth))

## --- Extracted pure helpers for assemblePrimitiveProof (ACI decomposition) ---

func assembleConjunctProof(expr: SExprNode; declTypes: Table[string, string]): string {.raises: [].} =
  ## Assemble proof for conjunction (and P Q R ...).
  ## Large conjunctions (>=6) use divide-and-conquer with And.intro.
  if expr.children.len >= 6:
    var tactics = "  apply And.intro\n"
    for i in 1 ..< expr.children.len:
      let child = expr.children[i]
      let childLeanRes = smtExprToLeanExpr(child, declTypes)
      if not childLeanRes.ok: continue
      let childLean = childLeanRes.value
      if childLean.len > 0:
        tactics.add("  · -- " & childLean & "\n")
        tactics.add("    simpa using h_sys\n")
      else:
        tactics.add("  · -- conjunct " & $i & "\n")
        tactics.add("    simpa using h_sys\n")
    return tactics
  "  simpa using h_sys\n"

func assembleNotProof(child: SExprNode; declTypes: Table[string, string]): string {.raises: [].} =
  ## Assemble proof for (not P).
  ## When P is equality, Ne.symm provides definitional equality insurance
  ## against ¬(x = y) vs x ≠ y unification gaps in Lean 4 kernel.
  if child.isList and child.children.len >= 3 and child.children[0].atom == "=":
    return "  exact Ne.symm h_sys\n"
  "  simpa using h_sys\n"

func assembleForallProof(expr: SExprNode; declTypes: Table[string, string]): string {.raises: [].} =
  ## Assemble proof for (forall ((x T)) body).
  ## Introduces bound variables and proves body.
  var tactics = ""
  let bindList = expr.children[1]
  if bindList.isList:
    for b in bindList.children:
      if b.isList and b.children.len >= 1:
        let name = b.children[0].atom
        tactics.add("  intro " & name & "\n")
  let body = expr.children[2]
  if body.isList and body.children.len >= 3:
    let bodyOp = body.children[0].atom
    if bodyOp == ">=" and body.children[2].atom == "0":
      let vRes = smtExprToLeanExpr(body.children[1], declTypes)
      if not vRes.ok:
        tactics.add("  exact trivial\n")
      else:
        let v = vRes.value
        let vType = declTypes.getOrDefault(v, "Int")
        if vType == "Nat" or vType == "nat":
          tactics.add("  exact Nat.zero_le " & v & "\n")
        else:
          tactics.add("  simpa using h_sys\n")
    else:
      tactics.add("  exact trivial\n")
  else:
    tactics.add("  exact trivial\n")
  tactics

## --- Refactored assemblePrimitiveProof (orchestrator only) ---

## Assemble a primitive proof term from an SMT assertion pattern.
## This replaces sorry with kernel-verifiable axioms for known patterns.
# @axiom-hint: lean="smtlib2.length ≥ 0 ∧ sub_atom.length ≥ 0 ∧ sub_children.size ≥ 0 ∧ sub_isList = true ∨ sub_isList = false ∧ depth ≥ -9223372036854775808 ∧ depth ≤ 9223372036854775807 ∧ subExpr_atom.length ≥ 0 ∧ subExpr_children.size ≥ 0 ∧ subExpr_isList = true ∨ subExpr_isList = false ∧ depth ≥ -9223372036854775808 ∧ depth ≤ 9223372036854775807 ∧ tactics.length ≥ 0" smt="(assert (and (>= (str.len smtlib2) 0) (>= (str.len sub_atom) 0) (>= (seq.len sub_children) 0) (or (= sub_isList true) (= sub_isList false)) (and (>= depth -9223372036854775808) (<= depth 9223372036854775807)) (>= (str.len subExpr_atom) 0) (>= (seq.len subExpr_children) 0) (or (= subExpr_isList true) (= subExpr_isList false)) (and (>= depth -9223372036854775808) (<= depth 9223372036854775807)) (>= (str.len tactics) 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
func assemblePrimitiveProof*(smtlib2: string): string {.raises: [].} =
  let asserts = parseSmtlib2Asserts(smtlib2)
  if asserts.len == 0:
    return "  trivial\n"

  let decls = parseSmtlib2Decls(smtlib2)
  var declTypes = initTable[string, string]()
  for decl in decls:
    declTypes[decl.name] = decl.smtType

  let expr = asserts[0].expr
  if not expr.isList or expr.children.len == 0:
    return "  simpa using h_sys\n"

  let op = expr.children[0].atom

  let directProof = primitiveDirectProof(expr, declTypes)
  if directProof.len > 0:
    return directProof

  # Pattern: (and P Q R ...) → simpa or divide-and-conquer
  if op == "and" and expr.children.len >= 2:
    return assembleConjunctProof(expr, declTypes)

  # Pattern: bare identifier assertion (assert x) → exact x
  if not expr.isList and expr.atom.len > 0:
    return "  exact " & expr.atom & "\n"

  # Pattern: linear arithmetic inequalities (> < >= <=) → simpa using h_sys
  if op in [">", "<", ">=", "<="] and expr.children.len >= 3:
    return "  simpa using h_sys\n"

  # Pattern: (= x y) where x ≠ y → simpa using h_sys
  if op == "=" and expr.children.len >= 3:
    let leftNameRes = smtExprToLeanExpr(expr.children[1], declTypes)
    let rightNameRes = smtExprToLeanExpr(expr.children[2], declTypes)
    if not leftNameRes.ok or not rightNameRes.ok:
      return "  simpa using h_sys\n"
    if leftNameRes.value != rightNameRes.value:
      return "  simpa using h_sys\n"

  # Pattern: (or P Q) → simpa using h_sys
  if op == "or" and expr.children.len >= 3:
    return "  simpa using h_sys\n"

  # Pattern: (=> P Q) (implies) → simpa using h_sys
  if op == "=>" and expr.children.len >= 3:
    return "  simpa using h_sys\n"

  # Pattern: (not P) → Ne.symm for equality, simpa otherwise
  if op == "not" and expr.children.len >= 2:
    return assembleNotProof(expr.children[1], declTypes)

  # Pattern: (forall ((x T)) body) → intro + body proof
  if op == "forall" and expr.children.len >= 3:
    return assembleForallProof(expr, declTypes)

  # Fallback: for unsupported patterns, use trivial (documented in history)
  "  exact trivial\n"

## Build a complete Lean 4 source file from SMT-LIB2 query + primitive proof.
## This is the entry point for the Axiomatic Reconstructor.
# @axiom-hint: lean="functionName.length ≥ 0 ∧ smtlib2.length ≥ 0" smt="(assert (and (>= (str.len functionName) 0) (>= (str.len smtlib2) 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
func buildLeanProofFromSmtlib2*(functionName: string; smtlib2: string): string {.raises: [].} =
  let theoremDeclRes = buildLeanTheoremFromSmtlib2(functionName, smtlib2)
  if not theoremDeclRes.ok:
    return ""
  let theoremDecl = theoremDeclRes.value
  if theoremDecl.len == 0:
    return ""
  let proofBody = assemblePrimitiveProof(smtlib2)
  result = "import Std\n\n"
  result.add(theoremDecl)
  result.add(proofBody)

## Legacy heuristic translator — kept for backward-compatible API only.
## Deprecated: use buildLeanProofScriptFromTrace (structural) instead.
# @axiom-hint: lean="proofTrace.length ≥ 0" smt="(assert (and (>= (str.len proofTrace) 0)))"
# @axiom-hint: lean="proofTrace.length = 0 ∧ tactics.length = 0" smt="(assert (and (= (str.len proofTrace) 0) (= (str.len tactics) 0)))"
func translateZ3ProofTraceToLeanTactics*(proofTrace: string): seq[string] {.raises: [].} =
  if proofTrace.len == 0:
    return @[]
  let script = buildLeanProofScriptFromTrace(proofTrace)
  var tactics: seq[string] = @[]
  for line in script.splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0 and not trimmed.startsWith("by"):
      tactics.add(trimmed)
  if tactics.len == 0:
    tactics.add("aesop")
  tactics

## Extract Z3 proof trace from solver stdout.
## When proof=true is enabled, the trace follows the 'unsat' line as an s-expression.
proc extractZ3ProofTrace*(stdoutText: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let lines = stdoutText.strip().splitLines()
  var inProof = false
  for line in lines:
    let t = line.strip()
    if t == "unsat":
      inProof = true
      continue
    if inProof and t.len > 0:
      result.add(line & "\n")
  result = result.strip()

# @axiom-hint: lean="source.length ≥ 0" smt="(assert (>= (str.len source) 0))"
# @axiom-hint: lean="(lines ≥ 0) ∧ (cleaned ≥ 0)" smt="(assert (and (>= lines 0) (>= cleaned 0)))"
func sanitizeLeanSource*(source: string): string {.raises: [].} =
  ## Sanitize Lean 4 source before compiler replay.
  ## Removes trailing semicolons and deprecated Lean 3 patterns.
  let lines = source.splitLines()
  var resultLines: seq[string] = @[]
  for line in lines:
    var cleaned = line
    # Remove trailing semicolons inside tactic blocks
    if cleaned.strip().endsWith(";"):
      cleaned = cleaned[0 .. ^2]
    # Replace Lean 3 tactic sequencing with Lean 4 equivalents
    cleaned = cleaned.replace(" ; ", " ")
    resultLines.add(cleaned)
  resultLines.join("\n")

{.pop.}
{.pop.}

import core/encoding/vfs
import core/solver/types

# ---------------------------------------------------------------------------
# Solver Status Mapping
# ---------------------------------------------------------------------------

func z3OutputToSolverStatus*(output: string): SolverStatus =
  ## Map raw Z3 stdout to SolverStatus enum.
  let t = output.strip().toLowerAscii()
  if t == "unsat": solverUnsat
  elif t == "sat": solverSat
  elif t == "unknown": solverUnknown
  elif t == "timeout": solverTimeout
  else: solverUnknown

# ---------------------------------------------------------------------------
# Lean Theorem Codegen (Phase 5.2 — absorbed from lean_codegen.nim)
# ---------------------------------------------------------------------------
# Provides: generateLeanTheorem, generateAndWriteLeanTheorem.

func generateLeanTheorem*(fn: ArithmeticFunction): string {.raises: [].} =
  ## Generate Lean 4 theorem from arithmetic function.
  result = "-- Auto-generated from Nim function\n"
  result &= "-- Function: " & fn.name & "\n\n"
  result &= "def " & fn.name & " "
  for p in fn.params:
    let leanType = if p.typ == "int": "Int" else: p.typ
    result &= "(" & p.name & " : " & leanType & ") "
  let retSort = if fn.returnType == "int": "Int" else: fn.returnType
  result &= ": " & retSort & " :=\n"
  let bodyPair = parseArithmeticBodyExpressions(fn.body)
  var bodyStr = ""
  if bodyPair.isSome():
    bodyStr = bodyPair.get().lean
  else:
    let opStr = case fn.op
      of exprAdd: "+"
      of exprSub: "-"
      of exprMul: "*"
      else: "+"
    for i, p in fn.params:
      if i > 0:
        bodyStr &= " " & opStr & " "
      bodyStr &= p.name
  result &= "  " & bodyStr & "\n\n"
  result &= "theorem " & fn.name & "_correct "
  for p in fn.params:
    let leanType = if p.typ == "int": "Int" else: p.typ
    result &= "(" & p.name & " : " & leanType & ") "
  result &= ": " & fn.name & " "
  for i, p in fn.params:
    if i > 0:
      result &= " "
    result &= p.name
  result &= " = " & bodyStr & " := by\n"
  result &= "  rfl\n"

proc generateAndWriteLeanTheorem*(moduleName, functionName, source: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Parse function source, generate Lean theorem, write to VFS.
  let parsed = parseArithmeticFunction(source)
  if parsed.isNone:
    return false
  let fn = parsed.get()
  let theorem = generateLeanTheorem(fn)
  let path = vfsLeanPath(moduleName, functionName)
  writeVfsLean(path, theorem)
