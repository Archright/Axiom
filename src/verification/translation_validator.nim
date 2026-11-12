import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
import std/strutils
import std/tables
import core/domain_types
import core/symbolic_types_expr
import core/symbolic_types_lean
import core/symbolic/symbolic_types_exec

# axiomIoBoundary
import ../core/trusted/axiom_pragmas
# import ../gate/gate_rules — REMOVED: all types in core/types/domain_types

## Translation Validator
## Phase 4: Semantic Equivalence Validation between Nim Symbolic State and Lean 4 Propositions
## Proves AI proof synthesis is mathematically equivalent to original logic via SMT-LIB2.
## Wave Y: Self-Proving Refactor — Translation Validation for code refactoring equivalence.

# ---------------------------------------------------------------------------
# Types (SemanticIntegrityViolation, SemanticIntegrityGate defined in domain_types)
# ---------------------------------------------------------------------------

# TranslationValidationResult — SSOT in core/types/domain_types.nim
# (moved to break circular dependency with gate_registry)

# ---------------------------------------------------------------------------
# Lean 4 Proposition → SMT-LIB2 Converter
# ---------------------------------------------------------------------------

proc normalizeLeanProp(prop: string): string {.raises: [], axiom: ["(assert (and (> colonIdx 0) (< i (str.len result)) (= i (+ i (str.len name))) (>= result 0) (and (>= i 0) (< i result))))", "colonIdx > 0 ∧ i < result.length ∧ i = i + name.length ∧ (result ≥ 0) ∧ ((i ≥ 0) ∧ (i < result))"].} =
  ## Strips decorative Unicode and normalizes Lean syntax for SMT conversion.
  result = prop.strip()
  result = result.replace("∀", "forall")
  result = result.replace("∃", "exists")
  result = result.replace("→", "=>")
  result = result.replace("∧", "and")
  result = result.replace("∨", "or")
  result = result.replace("¬", "not")
  result = result.replace("≤", "<=")
  result = result.replace("≥", ">=")
  result = result.replace("≠", "distinct")
  result = result.replace("ℕ", "Nat")
  result = result.replace("ℤ", "Int")
  # Remove Lean type ascriptions like `(x : Nat)` → `x`
  var i = 0
  while i < result.len:
    if result[i] == '(' and i + 1 < result.len and result[i+1] != '(':
      let closeIdx = result.find(')', i)
      if closeIdx > i and ':' in result[i .. closeIdx]:
        let inner = result[i+1 ..< closeIdx].strip()
        let colonIdx = inner.find(':')
        if colonIdx > 0:
          let name = inner[0 ..< colonIdx].strip()
          result = result[0 ..< i] & name & result[closeIdx+1 .. ^1]
          i = i + name.len
          continue
    inc i

## Lean Prop To Smt2.
proc leanPropToSmt2*(leanProp: string): string {.raises: [], axiom: ["(assert (and (>= (str.len leanProp) 0) (= (str.len norm) 0) (> bodyStart 0) (> (str.len v) 0) (> (str.len arg) 0) (< dotIdx 0) (> (str.len name) 0) (< i (str.len smt)) (= i (+ i (str.len replacement))) (= i 0) (= i (+ startName (str.len replacement))) (= i (+ dotIdx 1)) (= result smt) (>= vars 0) (>= smt 0) (>= result 0) (and (and (>= i 0) (< i smt)) (< i smt))))", "leanProp.length ≥ 0 ∧ norm.length = 0 ∧ bodyStart > 0 ∧ v.length > 0 ∧ arg.length > 0 ∧ dotIdx < 0 ∧ name.length > 0 ∧ i < smt.length ∧ i = i + replacement.length ∧ i = 0 ∧ i = startName + replacement.length ∧ i = dotIdx + 1 ∧ result = smt ∧ (vars ≥ 0) ∧ (smt ≥ 0) ∧ (result ≥ 0) ∧ (((i ≥ 0) ∧ (i < smt)) ∧ (i < smt))"].} =
  ## Lightweight converter from Lean proposition syntax to SMT-LIB2.
  ## Handles common patterns: forall, arithmetic, comparisons, logical connectives.
  let norm = normalizeLeanProp(leanProp)
  if norm.len == 0:
    return ""

  var smt = norm
  # Convert forall blocks: "forall x y, P" → "(forall ((x Int) (y Int)) P)"
  if smt.startsWith("forall "):
    let bodyStart = smt.find(",")
    if bodyStart > 0:
      let varsPart = smt["forall ".len ..< bodyStart].strip()
      let body = smt[bodyStart+1 .. ^1].strip()
      let vars = varsPart.splitWhitespace()
      var decls: seq[string] = @[]
      for v in vars:
        if v.len > 0:
          decls.add("(" & v & " Int)")
      smt = "(forall (" & decls.join(" ") & ") " & body & ")"

  # Convert exists blocks similarly
  if smt.startsWith("exists "):
    let bodyStart = smt.find(",")
    if bodyStart > 0:
      let varsPart = smt["exists ".len ..< bodyStart].strip()
      let body = smt[bodyStart+1 .. ^1].strip()
      let vars = varsPart.splitWhitespace()
      var decls: seq[string] = @[]
      for v in vars:
        if v.len > 0:
          decls.add("(" & v & " Int)")
      smt = "(exists (" & decls.join(" ") & ") " & body & ")"

  # Replace Nat.zero_le x with (>= x 0)
  var i = 0
  while i < smt.len:
    let pat = "Nat.zero_le "
    if smt.continuesWith(pat, i):
      let startArg = i + pat.len
      var argEnd = startArg
      while argEnd < smt.len and smt[argEnd] notin Whitespace + {')', '('}:
        inc argEnd
      let arg = smt[startArg ..< argEnd]
      if arg.len > 0:
        let replacement = "(>= " & arg & " 0)"
        smt = smt[0 ..< i] & replacement & smt[argEnd .. ^1]
        i = i + replacement.len
        continue
    inc i

  # Replace n.succ with (+ n 1)
  i = 0
  while i < smt.len:
    let dotSucc = ".succ"
    let dotIdx = smt.find(dotSucc, i)
    if dotIdx < 0:
      break
    var startName = dotIdx - 1
    while startName >= 0 and smt[startName] notin Whitespace + {'(', ')'}:
      dec startName
    inc startName
    let name = smt[startName ..< dotIdx]
    if name.len > 0:
      let replacement = "(+ " & name & " 1)"
      smt = smt[0 ..< startName] & replacement & smt[dotIdx + dotSucc.len .. ^1]
      i = startName + replacement.len
      continue
    i = dotIdx + 1

  # Ensure prefix notation for basic operators by simple parenthesization passes
  # This is a best-effort converter; complex nested expressions may need manual handling.
  result = smt

# ---------------------------------------------------------------------------
# Equivalence Query Builder
# ---------------------------------------------------------------------------

proc declareSmtVarsFromExpr(e: SymSExpr): string {.raises: [], axiom: ["(assert (and (>= depth 0) (>= vars 0) (>= result 0) (>= seen 0)))", "depth >= 0 ∧ (vars ≥ 0) ∧ (result ≥ 0) ∧ (seen ≥ 0)"].} =
  var seen = initTable[string, bool]()
  let vars = sExprVariables(e)
  var lines: seq[string] = @[]
  for v in vars:
    if not seen.hasKey(v):
      seen[v] = true
      lines.add("(declare-const " & v & " Int)")
  result = lines.join("\n")

proc buildImplicationQuery(antecedent, consequent: string; smtVars: string): string {.raises: [], axiom: ["(assert (and (>= (str.len antecedent) 0) (>= (str.len consequent) 0) (>= (str.len smtVars) 0) (> (str.len smtVars) 0) (>= result 0)))", "antecedent.length ≥ 0 ∧ consequent.length ≥ 0 ∧ smtVars.length ≥ 0 ∧ smtVars.length > 0 ∧ (result ≥ 0)"].} =
  ## Builds SMT-LIB2 query to check if antecedent → consequent is valid.
  ## Query asserts (antecedent ∧ ¬consequent); unsat means implication holds.
  var parts: seq[string] = @[]
  parts.add("(set-option :print-success false)")
  parts.add("(set-logic ALL)")
  if smtVars.len > 0:
    parts.add(smtVars)
  parts.add("(assert " & antecedent & ")")
  parts.add("(assert (not " & consequent & "))")
  parts.add("(check-sat)")
  result = parts.join("\n")

## Build Equivalence Query.
proc buildEquivalenceQuery*(nimSmt2, leanSmt2: string; smtVars: string): tuple[fwd: string; bwd: string] {.raises: [], axiom: ["(assert (and (>= result 0)))", "(result ≥ 0)"].} =
  ## Builds bidirectional implication queries for semantic equivalence.
  result.fwd = buildImplicationQuery(nimSmt2, leanSmt2, smtVars)
  result.bwd = buildImplicationQuery(leanSmt2, nimSmt2, smtVars)

# ---------------------------------------------------------------------------
# Semantic Equivalence Validation
# ---------------------------------------------------------------------------

## Validate Semantic Equivalence.
proc validateSemanticEquivalence*(
  nimExpr: SymSExpr;
  leanProp: string;
  z3Check: proc(query: string): bool {.closure, gcsafe, raises: [].}
): TranslationValidationResult {.raises: [], axiom: ["(assert (and fwdOk bwdOk result (>= bwdOk 0) (>= result 0) (>= fwdOk 0)))", "fwdOk ∧ bwdOk ∧ result ∧ (bwdOk ≥ 0) ∧ (result ≥ 0) ∧ (fwdOk ≥ 0)"].} =
  ## Validates that Nim symbolic expression and Lean proposition are logically equivalent.
  ## Uses bidirectional implication checking via Z3.
  result = TranslationValidationResult(
    equivalent: false,
    nimSmt2: "",
    leanSmt2: "",
    z3OutputFwd: "",
    z3OutputBwd: "",
    message: "",
    verifiedByZ3: false,
    verifiedByLean: false
  )

  if nimExpr.isNil or leanProp.len == 0:
    result.message = "empty input: nimExpr or leanProp missing"
    return result

  result.nimSmt2 = sExprToString(nimExpr)
  result.leanSmt2 = leanPropToSmt2(leanProp)

  if result.leanSmt2.len == 0:
    result.message = "lean proposition conversion failed"
    return result

  let smtVars = declareSmtVarsFromExpr(nimExpr)
  let queries = buildEquivalenceQuery(result.nimSmt2, result.leanSmt2, smtVars)

  var fwdOk = false
  var bwdOk = false
  try:
    fwdOk = z3Check(queries.fwd)
    result.z3OutputFwd = if fwdOk: "unsat" else: "sat/unknown"
  except CatchableError:
    result.message = "Z3 forward implication check failed"
    return result

  try:
    bwdOk = z3Check(queries.bwd)
    result.z3OutputBwd = if bwdOk: "unsat" else: "sat/unknown"
  except CatchableError:
    result.message = "Z3 backward implication check failed"
    return result

  result.verifiedByZ3 = fwdOk and bwdOk
  result.equivalent = result.verifiedByZ3

  if result.equivalent:
    result.message = "semantic equivalence confirmed: Nim SymSExpr ⟺ Lean proposition"
  else:
    if not fwdOk and not bwdOk:
      result.message = "semantic divergence: neither direction holds"
    elif not fwdOk:
      result.message = "semantic incompleteness: Lean proposition stronger than Nim invariant"
    else:
      result.message = "semantic hallucination: Nim invariant stronger than Lean proposition"

# ---------------------------------------------------------------------------
# Lean Theorem Generation from Invariant
# ---------------------------------------------------------------------------

proc collectSExprVars(e: SymSExpr): seq[string] {.raises: [], axiom: ["(assert (and (>= depth 0) seVar seConst seTrue seFalse (>= rhsVars 0) (>= lhsVars 0)))", "depth >= 0 ∧ seVar ∧ seConst ∧ seTrue ∧ seFalse ∧ (rhsVars ≥ 0) ∧ (lhsVars ≥ 0)"].} =
  ## Collect all variable names from an SymSExpr (duplicate-free).
  if e.isNil:
    return
  case e.kind
  of seVar:
    if e.name notin result:
      result.add(e.name)
  of seConst, seTrue, seFalse:
    discard
  else:
    if e.lhs != nil:
      let lhsVars = collectSExprVars(e.lhs)
      for v in lhsVars:
        if v notin result:
          result.add(v)
    if e.rhs != nil:
      let rhsVars = collectSExprVars(e.rhs)
      for v in rhsVars:
        if v notin result:
          result.add(v)

## Build Lean Theorem From Invariant.
proc buildLeanTheoremFromInvariant*(fnName: string; inv: SymSExpr): string {.raises: [], axiom: ["(assert (and (>= (str.len fnName) 0) (> (str.len vars) 0) (>= result 0) (>= varDecl 0)))", "fnName.length ≥ 0 ∧ vars.length > 0 ∧ (result ≥ 0) ∧ (varDecl ≥ 0)"].} =
  ## Generates a Lean 4 theorem statement from a Nim loop invariant SymSExpr.
  ## The theorem asserts the invariant holds for all loop iterations.
  let invLean = sExprToLean(inv)
  let vars = collectSExprVars(inv)
  var varDecl = ""
  if vars.len > 0:
    varDecl = "∀ (" & vars.join(" ") & " : Nat), "
  result = "theorem " & fnName & "_loop_invariant : " & varDecl & invLean & " := by\n"
  result &= "  simp\n"
  result &= "  <;> try { omega }\n"

## Build Lean Negative Test.
proc buildLeanNegativeTest*(fnName: string; inv: SymSExpr): string {.raises: [], axiom: ["(assert (and (>= (str.len fnName) 0) (>= result 0)))", "fnName.length ≥ 0 ∧ (result ≥ 0)"].} =
  ## Generates a Lean negative test by negating the invariant.
  ## If this compiles, the original proof is vacuous.
  let invLean = sExprToLean(inv)
  result = "theorem " & fnName & "_loop_invariant_neg : ¬(" & invLean & ") := by\n"
  result &= "  simp\n"

# ---------------------------------------------------------------------------
# Semantic Integrity Gate
# ---------------------------------------------------------------------------

## Apply Semantic Integrity Gate.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
# applySemanticIntegrityGate — SSOT in core/gate_evaluators.nim
import core/gate/gate_evaluators
export gate_evaluators.applySemanticIntegrityGate

# ---------------------------------------------------------------------------
# Wave Y: Refactoring Equivalence Validation (Nim↔Nim mode)
# ---------------------------------------------------------------------------

type
  TransformationKind* = enum
    tkExtractMethod      ## Extract inline closure → standalone proc/func
    tkTableDriven        ## Replace case branches → const table + loop
    tkInlineExpansion    ## Replace proc call → inline body
    tkRename             ## Symbol rename (no logic change)
    tkStructuralDecomp   ## Extract helper functions from god function

  RefactoringCertificate* = object
    ## Certificate proving semantic equivalence between original and refactored code.
    originalFunction*: string     ## Qualified name: "module.nim::originalFn"
    refactoredFunction*: string   ## Qualified name: "module.nim::newFn" (or same if inline)
    transformationKind*: TransformationKind
    equivalent*: bool
    verifiedByZ3*: bool
    verifiedByLean*: bool
    proofStrategy*: string        ## "mechanical-equivalence", "operator-enumeration", etc.
    operatorCount*: int           ## For tkTableDriven: number of operators verified
    z3CounterExample*: string
    leanArtifactPath*: string
    issuedAt*: string

## Validate Refactoring Equivalence (Nim↔Nim).
## Generalization of validateSemanticEquivalence for two Nim symbolic expressions.
proc validateRefactoringEquivalence*(
  originalExpr: SymSExpr;
  refactoredExpr: SymSExpr;
  z3Check: proc(query: string): bool {.closure, gcsafe, raises: [].}
): TranslationValidationResult {.raises: [], axiom: ["(assert (and (>= (seq.len originalExpr) 0) (>= (seq.len refactoredExpr) 0)))", "originalExpr.size ≥ 0 ∧ refactoredExpr.size ≥ 0"].} =
  ## Validates that original and refactored Nim expressions are logically equivalent.
  ## Uses bidirectional implication checking via Z3.
  result = TranslationValidationResult(
    equivalent: false,
    nimSmt2: "",
    leanSmt2: "",
    z3OutputFwd: "",
    z3OutputBwd: "",
    message: "",
    verifiedByZ3: false,
    verifiedByLean: false
  )

  if originalExpr.isNil or refactoredExpr.isNil:
    result.message = "empty input: one or both expressions missing"
    return result

  result.nimSmt2 = sExprToString(originalExpr)
  result.leanSmt2 = sExprToString(refactoredExpr)

  if result.nimSmt2.len == 0 or result.leanSmt2.len == 0:
    result.message = "SMT conversion failed"
    return result

  let smtVars = declareSmtVarsFromExpr(originalExpr)
  let queries = buildEquivalenceQuery(result.nimSmt2, result.leanSmt2, smtVars)

  var fwdOk = false
  var bwdOk = false
  try:
    fwdOk = z3Check(queries.fwd)
    result.z3OutputFwd = if fwdOk: "unsat" else: "sat/unknown"
  except CatchableError:
    result.message = "Z3 forward implication check failed"
    return result

  try:
    bwdOk = z3Check(queries.bwd)
    result.z3OutputBwd = if bwdOk: "unsat" else: "sat/unknown"
  except CatchableError:
    result.message = "Z3 backward implication check failed"
    return result

  result.verifiedByZ3 = fwdOk and bwdOk
  result.equivalent = result.verifiedByZ3

  if result.equivalent:
    result.message = "semantic equivalence confirmed: original ⟺ refactored"
  else:
    result.message = "semantic divergence detected"

## Issue a refactoring equivalence certificate.
proc issueRefactoringCertificate*(
  originalFn, refactoredFn: string;
  kind: TransformationKind;
  validationResult: TranslationValidationResult;
  proofStrategy: string = "z3-bidirectional";
  operatorCount: int = 0
): RefactoringCertificate {.raises: [].} =
  ## Create a refactoring equivalence certificate from validation results.
  RefactoringCertificate(
    originalFunction: originalFn,
    refactoredFunction: refactoredFn,
    transformationKind: kind,
    equivalent: validationResult.equivalent,
    verifiedByZ3: validationResult.verifiedByZ3,
    verifiedByLean: validationResult.verifiedByLean,
    proofStrategy: proofStrategy,
    operatorCount: operatorCount,
    z3CounterExample: if not validationResult.equivalent: validationResult.message else: "",
    leanArtifactPath: "",
    issuedAt: ""
  )

## Validate table-driven refactoring: verify all operator mappings.
## Used for InfixOps → case-branch equivalence in boundary_extractor.nim.
proc validateTableDrivenEquivalence*(
  operatorTable: openArray[(string, string, string)];  ## (nimOp, smtOp, leanOp)
  buildOriginal: proc(op: string): (string, string) {.closure, gcsafe, raises: [].};
  buildRefactored: proc(op: string; smtOp, leanOp: string): (string, string) {.closure, gcsafe, raises: [].}
): (bool, int, string) {.raises: [], axiom: ["(assert (and (>= (seq.len originalExpr) 0) (>= (seq.len tableExpr) 0)))", "originalExpr.size ≥ 0 ∧ tableExpr.size ≥ 0"].} =
  ## Validates that a table-driven implementation produces identical output
  ## to the original case-branch implementation for all table entries.
  ## Returns: (allMatch, mismatchCount, firstMismatchDetail)
  var mismatchCount = 0
  var firstMismatch = ""
  for (nimOp, smtOp, leanOp) in operatorTable:
    let orig = buildOriginal(nimOp)
    let refac = buildRefactored(nimOp, smtOp, leanOp)
    if orig != refac:
      inc mismatchCount
      if firstMismatch.len == 0:
        firstMismatch = "op='" & nimOp & "' orig='" & orig[0] & ";" & orig[1] &
                        "' refac='" & refac[0] & ";" & refac[1] & "'"
  return (mismatchCount == 0, mismatchCount, firstMismatch)
{.pop.}


