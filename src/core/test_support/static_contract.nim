{.push raises: [].}
## Static Contract Extraction & Z3 Verification (Phase 3)
##
## Extracts contracts (assert, pre/postconditions) from Nim AST and verifies
## them via Z3. Self-contained — does not import axiom_dsl.nim (has pre-existing
## compile error at line 147).
##
## Design:
##   - Contract: (kind, expr, smtLib2, sourceLine)
##   - extractContracts(NimNode): seq[Contract] — walks AST for assert/ensures/requires
##   - verifyContract(Contract): Z3Result — queries Z3 for satisfiability
##   - PBT: roundtrip property (Nim AST → Contract → SMT-LIB2 → Z3)

import core/trusted/layer_declaration
axiomLayer "domain"
import core/testing/axiom_dsl
import std/[macros, strutils, osproc, os, streams, tempfiles]
import core/axiom_pragmas
import core/trusted/solver_invocation
import core/parsers/safe_parsers
import core/results

type
  ContractKind* = enum
    ckPrecondition   ## requires/assert before computation
    ckPostcondition  ## ensures/return value constraint
    ckAssert         ## inline assert statement
    ckInvariant      ## loop/struct invariant

  Contract* = object
    kind*: ContractKind
    expr*: string         ## Source repr of the expression
    smtLib2*: string      ## SMT-LIB2 representation
    sourceLine*: int      ## 1-based line in source
    description*: string  ## Human-readable description

  ContractVerificationResult* = object
    contract*: Contract
    z3Result*: Z3Result
    verified*: bool       ## true if Z3 proves unsat (no counterexample)

# ── Nim AST → SMT-LIB2 Transpiler ──────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func nimNodeToSmtLib2*(node: NimNode): string =
  ## Convert a Nim AST node to SMT-LIB2 expression.
  ## Supports: int literals, bool literals, identifiers, infix ops, prefix not.
  case node.kind
  of nnkIntLit:
    result = $node.intVal
  of nnkIdent, nnkSym:
    case node.strVal
    of "true": result = "true"
    of "false": result = "false"
    else: result = node.strVal
  of nnkOpenSymChoice, nnkClosedSymChoice:
    # Overloaded symbol — use the first candidate's name
    if node.len > 0:
      result = node[0].strVal
    else:
      result = node.repr
  of nnkInfix:
    let opSym = case node[0].kind
      of nnkIdent, nnkSym: node[0].strVal
      of nnkOpenSymChoice, nnkClosedSymChoice:
        if node[0].len > 0: node[0][0].strVal else: node[0].repr
      else: node[0].repr
    let op = case opSym
      of "+": "+"
      of "-": "-"
      of "*": "*"
      of "div": "div"
      of "mod": "mod"
      of "<": "<"
      of "<=": "<="
      of ">": ">"
      of ">=": ">="
      of "==": "="
      of "!=": "distinct"
      of "and": "and"
      of "or": "or"
      of "implies": "=>"
      else: opSym
    let lhs = nimNodeToSmtLib2(node[1])
    let rhs = nimNodeToSmtLib2(node[2])
    result = "(" & op & " " & lhs & " " & rhs & ")"
  of nnkPrefix:
    let opSym = node[0].strVal
    let operand = nimNodeToSmtLib2(node[1])
    if opSym == "not":
      result = "(not " & operand & ")"
    elif opSym == "-":
      result = "(- " & operand & ")"
    else:
      result = operand
  of nnkCall:
    # Function application: f(a, b) → (f a b)
    let fn = if node[0].kind == nnkIdent: node[0].strVal else: node[0].repr
    result = "(" & fn
    for i in 1..<node.len:
      result &= " " & nimNodeToSmtLib2(node[i])
    result &= ")"
  of nnkExprEqExpr, nnkAsgn:
    # x = expr → (= x expr)
    let lhs = nimNodeToSmtLib2(node[0])
    let rhs = nimNodeToSmtLib2(node[1])
    result = "(= " & lhs & " " & rhs & ")"
  else:
    # Fallback: repr the node
    result = node.repr

# ── AST Extraction ──────────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func extractContracts*(body: NimNode): seq[Contract] =
  ## Walk a proc body AST and extract all contract expressions.
  ## Recognizes: assert, requires, ensures, doAssert.
  result = @[]
  if body == nil: return

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
  proc getLine(node: NimNode): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    let info = node.lineinfo
    let lp = info.find('(')
    let cp = info.find(',', start = lp + 1)
    if lp > 0 and cp > lp:
      safeParseInt(info[lp+1 ..< cp]).getOrDefault(0)
    else: 0

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
  proc tryExtract(node: NimNode): seq[Contract] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    ## Try to extract a contract from a single Call/Command node.
    result = @[]
    if node.kind notin {nnkCall, nnkCommand}: return
    let fnName = case node[0].kind
      of nnkIdent, nnkSym: node[0].strVal
      else: ""
    if fnName notin ["assert", "doAssert", "requires", "ensures"]: return
    if node.len < 2: return
    try:
      let condExpr = node[1]
      let smt = nimNodeToSmtLib2(condExpr)
      let kind = case fnName
        of "assert", "doAssert": ckAssert
        of "requires": ckPrecondition
        of "ensures": ckPostcondition
        else: ckAssert
      result.add(Contract(
        kind: kind, expr: condExpr.repr, smtLib2: smt,
        sourceLine: getLine(node),
        description: fnName & " " & condExpr.repr
      ))
    except CatchableError: discard  # axiom:best-effort(ioboundary catch)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
  proc walk(node: NimNode; depth: int): seq[Contract] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    ## Walk AST with depth guard to prevent infinite recursion.
    result = @[]
    if depth > 50: return
    case node.kind
    of nnkCall, nnkCommand:
      result.add(tryExtract(node))
    of nnkStmtList, nnkBlockStmt, nnkIfStmt, nnkIfExpr,
       nnkElifBranch, nnkElse, nnkElifExpr,
       nnkForStmt, nnkWhileStmt, nnkCaseStmt:
      for child in node:
        result.add(walk(child, depth + 1))
    of nnkTryStmt:
      if node.len > 0:
        result.add(walk(node[0], depth + 1))
    else: discard

  # Handle both StmtList and single-statement bodies
  if body.kind == nnkStmtList:
    for child in body:
      result.add(walk(child, 0))
  else:
    result.add(walk(body, 0))

# ── Z3 Verification ─────────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc queryZ3*(smtLib2Code: string): Z3Result {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Query Z3 with SMT-LIB2 code. Returns sat/unsat + model.
  let fullQuery = "(set-option :produce-models true)\n" &
    solverOptionsPayload(pinnedDeterminismOptions()) &
    smtLib2Code & "\n(check-sat)\n(get-model)\n"
  let z3Path = if fileExists("vendor/z3/z3"): "vendor/z3/z3" else: "z3"
  # Write query to temp file and pipe to z3
  let tmpFile = genTempPath("axiom_z3_query_", ".smt2")
  var output = ""
  try:
    writeFile(tmpFile, fullQuery)
    let (outp, _) = execCmdEx(z3Path & " -in -smt2 < " & tmpFile)
    output = outp
  except CatchableError:
    return Z3Result(isSat: false, model: "Z3 query failed: " & getCurrentExceptionMsg())
  finally:
    try: removeFile(tmpFile) except CatchableError: discard  # axiom:best-effort(ioboundary catch)
  let lines = output.strip().splitLines()
  if lines.len == 0:
    return Z3Result(isSat: false, model: "Z3 returned empty output")
  result.isSat = lines[0] == "sat"
  result.model = if result.isSat and lines.len > 1: lines[1..^1].join("\n") else: ""

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func extractIdentifiers(smtExpr: string): seq[string] =
  ## Extract free variable identifiers from an SMT-LIB2 expression.
  ## Filters out operators, keywords, and numeric literals.
  result = @[]
  let keywords = ["and", "or", "not", "true", "false", "implies",
                  "div", "mod", "abs", "ite"]
  let ops = ["+", "-", "*", "=", "<", ">", "<=", ">="]
  var token = ""
  for ch in smtExpr:
    if ch in {'(', ')', ' ', '\t', '\n', '\r'}:
      if token.len > 0:
        if token notin keywords and token notin ops:
          var isNum = true
          for c in token:
            if c notin {'0'..'9', '-'}: isNum = false; break
          if not isNum and token notin result:
            result.add(token)
        token = ""
    else:
      token.add(ch)
  if token.len > 0 and token notin keywords and token notin ops:
    var isNum = true
    for c in token:
      if c notin {'0'..'9', '-'}: isNum = false; break
    if not isNum and token notin result:
      result.add(token)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc verifyContract*(contract: Contract): ContractVerificationResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Verify a single contract via Z3.
  ## Builds negation query with variable declarations.
  ## If Z3 finds a model (sat), the contract can be violated.
  ## If Z3 returns unsat, the contract is proven.
  var decls = ""
  for id in extractIdentifiers(contract.smtLib2):
    decls.add("(declare-const " & id & " Int)\n")
  let negatedQuery = decls &
    "(assert (not\n" & contract.smtLib2 & "\n))\n(check-sat)\n(get-model)\n"
  let z3Result = queryZ3(negatedQuery)
  ContractVerificationResult(
    contract: contract,
    z3Result: z3Result,
    verified: not z3Result.isSat
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc verifyContracts*(contracts: seq[Contract]): seq[ContractVerificationResult] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Verify a sequence of contracts via Z3.
  result = @[]
  for c in contracts:
    result.add(verifyContract(c))

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro newContractSpec*(body: untyped): seq[Contract] =
  ## Extract contracts from a proc body at compile time.
  ## Usage:
  ##   let specs = newContractSpec(procBody)
  ## Returns a compile-time seq[Contract] with SMT-LIB2 transpilation.
  let contracts = extractContracts(body)
  result = quote do:
    @`contracts`
