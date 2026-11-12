import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## Abstract Provider
## Phase 5: Layer 1 — Lightweight interval analysis for context-aware invariant synthesis.
## Derives variable bounds and obvious invariant candidates from CFG structure.

import std/options
import std/tables
import std/strutils
import compiler/ast
import core/results
import core/symbolic_types_expr
import core/symbolic/symbolic_types_parse
import core/parsers/pnode_nav
import core/orchestrator/cfg_builder
import core/parsers/safe_parsers
import verification/abstract_provider_types
# axiomIoBoundary

export abstract_provider_types

## Interval From Const.
# @axiom-hint: lean="value ≥ -9223372036854775808 ∧ value ≤ 9223372036854775807" smt="(assert (and (and (>= value -9223372036854775808) (<= value 9223372036854775807))))"
func intervalFromConst*(value: int): Interval {.inline, noSideEffect.} =
  Interval(lo: some(value), hi: some(value))

## Interval Non Negative.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
func intervalNonNegative*(): Interval {.inline, noSideEffect.} =
  Interval(lo: some(0), hi: none(int))

## Interval Unknown.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
func intervalUnknown*(): Interval {.inline, noSideEffect.} =
  Interval(lo: none(int), hi: none(int))

## Interval To String.
func intervalToString*(iv: Interval): string {.raises: [].} =
  let loStr = if iv.lo.isSome: $iv.lo.get else: "-inf"
  let hiStr = if iv.hi.isSome: $iv.hi.get else: "+inf"
  "[" & loStr & ", " & hiStr & "]"

# ---------------------------------------------------------------------------
# Interval Analysis from CFG
# ---------------------------------------------------------------------------

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="(node ≥ 0)" smt="(assert (and (>= node 0)))"
func extractIntegerValue(node: PNode): Option[int] {.raises: [].} =
  ## Extracts an integer constant from an AST node (PNode version).
  ## Total over every `TNodeKind`: each discriminant range is handled by the
  ## branch that owns it, so no variant field is ever read outside its own arm.
  ##
  ## Field ownership (Nim 2.2.10 `compiler/ast.nim:600-612`, discriminant order
  ## in `compiler/nodekinds.nim:13`):
  ##   `nkCharLit..nkUInt64Lit` → `intVal`
  ##   `nkFloatLit..nkFloat128Lit` → `floatVal`
  ##   `nkStrLit..nkTripleStrLit` → `strVal`
  ##   `nkSym` → `sym`, `nkIdent` → `ident`, every other kind → `sons`
  ## Reading a field outside its discriminant range raises `FieldDefect`, which
  ## is not a `CatchableError` and therefore escapes `except CatchableError`.
  ##
  ## What the compiler does and does not enforce here: `case` exhaustiveness is
  ## checked at compile time (dropping a branch without an `else` is an error), so
  ## the `else` below guarantees every kind lands on an explicit branch or on the
  ## `sons` fall-through. Field/kind pairing is *not* checked — Nim lowers a
  ## mismatched variant read to a runtime `FieldDefect` even with no `case` at
  ## all — so the branch mapping above must be kept in sync with the pinned
  ## `compiler/ast.nim`. Reference implementation of the same discipline:
  ## `pNodeText` in `src/core/parsers/pnode_nav.nim`.
  if node.isNil:
    return none(int)
  case node.kind
  of nkIntLit..nkUInt64Lit:
    let parsed = safeParseInt($node.intVal)
    if parsed.isOk:
      return some(parsed.get)
    return none(int)
  of nkCharLit:
    # Carries `intVal` too, but holds a char codepoint, not an integer literal.
    return none(int)
  of nkFloatLit..nkFloat128Lit:
    # Carries `floatVal`; a floating literal is not an integer constant.
    return none(int)
  of nkStrLit..nkTripleStrLit:
    # Carries `strVal`; a string literal is not an integer constant.
    return none(int)
  of nkIdent:
    # Carries `ident`; an identifier name is not an integer constant.
    return none(int)
  of nkSym:
    # Carries `sym`; a symbol reference is not an integer constant.
    return none(int)
  else:
    # Only `sons`-carrying kinds remain (nkNone, nkEmpty, nkType, nkNilLit,
    # nkCommentStmt and every composite node): fall through to the child scan.
    discard
  # `items`/`pairs` on PNode walk `safeLen` (`compiler/ast.nim:1011-1014` and
  # `:1947-1948`), which is 0 for every non-`sons` kind, so this loop is total.
  for child in node:
    if child.isNil: continue
    case child.kind
    of nkIntLit..nkUInt64Lit:
      let parsed = safeParseInt($child.intVal)
      if parsed.isOk:
        return some(parsed.get)
      return none(int)
    else:
      discard
  none(int)

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0) (> (str.len t) 0) t (=> (> (str.len t) 0) (= result t)) (>= node 0)))"
func extractVariableName(node: PNode): string {.raises: [].} =
  ## Extracts a simple variable name from an AST node (PNode version).
  if node.isNil:
    return ""
  if node.kind == nkIdent:
    return node.ident.s
  # Leaf/literal nodes have no children — iterating sons raises Defect.
  if node.kind in {nkIntLit, nkInt8Lit, nkInt16Lit, nkInt32Lit, nkInt64Lit,
                   nkUIntLit, nkUInt8Lit, nkUInt16Lit, nkUInt32Lit, nkUInt64Lit,
                   nkFloatLit, nkFloat32Lit, nkFloat64Lit, nkFloat128Lit,
                   nkStrLit, nkTripleStrLit, nkCharLit, nkNilLit, nkCommentStmt,
                   nkNone}:
    return ""
  for child in node:
    if child.isNil: continue
    if child.kind == nkIdent:
      let t = child.ident.s
      if t.len > 0:
        return t
  ""

# ---------------------------------------------------------------------------
# Statement Handlers (extracted from analyzeVariableIntervalsAtLoopHeader)
# ---------------------------------------------------------------------------

func handleVarSection(stmt: PNode, intervals: var Table[string, Interval]) {.raises: [].} =
  ## Processes a var_section / let_section statement (PNode version).
  ## nkIdentDefs structure: [identifiers..., type?, expr?]
  if stmt.isNil: return
  for child in stmt:
    if child.isNil or child.kind != nkIdentDefs: continue
    var nameNode: PNode = nil
    var valueNode: PNode = nil
    # In nkIdentDefs: identifiers come first, then optional type (nkSym), then expression
    var seenIdents = false
    var afterIdents = false
    for c in child:
      if c.isNil: continue
      if c.kind == nkIdent:
        if not afterIdents:
          nameNode = c
          seenIdents = true
      elif c.kind == nkSym:
        # Type symbol - skip
        if seenIdents: afterIdents = true
      else:
        # After idents and type, this is the expression/value
        if seenIdents:
          valueNode = c
    if nameNode.isNil:
      continue
    let name = extractVariableName(nameNode)
    if name.len == 0:
      continue
    if valueNode.isNil:
      intervals[name] = intervalFromConst(0)
    else:
      let valOpt = extractIntegerValue(valueNode)
      if valOpt.isSome:
        intervals[name] = intervalFromConst(valOpt.get)
      else:
        intervals[name] = intervalFromConst(0)

func handleAssignment(stmt: PNode, intervals: var Table[string, Interval]) {.raises: [].} =
  ## Processes an assignment statement (PNode version).
  ## nkAsgn structure: [lhs, rhs]
  if stmt.isNil or stmt.kind != nkAsgn: return
  var leftNode: PNode = nil
  var rightNode: PNode = nil
  if stmt.len > 0 and not stmt[0].isNil: leftNode = stmt[0]
  if stmt.len > 1 and not stmt[1].isNil: rightNode = stmt[1]
  if leftNode.isNil or rightNode.isNil:
    return
  let name = extractVariableName(leftNode)
  if name.len == 0:
    return
  let valOpt = extractIntegerValue(rightNode)
  if valOpt.isSome:
    intervals[name] = intervalFromConst(valOpt.get)

func handleForLoop(stmt: PNode, intervals: var Table[string, Interval]) {.raises: [].} =
  ## Processes a for loop statement (PNode version).
  ## nkForStmt structure: [varNames..., expr, body]
  if stmt.isNil or stmt.kind != nkForStmt: return
  var iterName = ""
  var rangeNode: PNode = nil
  # Find identifier (iterator var) and the expression before body
  var foundExpr = false
  for c in stmt:
    if c.isNil: continue
    if c.kind == nkIdent and iterName.len == 0:
      iterName = c.ident.s
    elif not foundExpr and c.kind != nkStmtList and c.kind != nkBlockStmt and c.kind != nkBlockExpr:
      rangeNode = c
      foundExpr = true
  if iterName.len > 0:
    if not intervals.hasKey(iterName):
      intervals[iterName] = intervalFromConst(0)
    # Try to extract range bounds from infix_expression like "0 ..< n"
    if not rangeNode.isNil and rangeNode.kind == nkInfix:
      var leftBound: PNode = nil
      var rightBound: PNode = nil
      if rangeNode.len > 0 and not rangeNode[0].isNil: leftBound = rangeNode[0]
      if rangeNode.len > 2 and not rangeNode[2].isNil: rightBound = rangeNode[2]
      let loOpt = extractIntegerValue(leftBound)
      if loOpt.isSome:
        var iv = intervals.getOrDefault(iterName)
        iv.lo = loOpt
        intervals[iterName] = iv

# ---------------------------------------------------------------------------
# Interval-Bounded Invariant Derivation (extracted from deriveInvariantCandidates)
# ---------------------------------------------------------------------------

func deriveIntervalBounds(ctx: AbstractContext): seq[SymSExpr] {.raises: [].} =
  ## Derives invariant candidates from interval analysis of variables.
  result = @[]
  for varName, iv in ctx.intervals:
    # Non-negative from initialization: if starts at [0, 0] or [0, +inf]
    if iv.lo.isSome and iv.lo.get >= 0:
      try:
        result.add(sGe(sVar(varName), sConst(0)))
      except CatchableError:
        discard  # computation fallback

    # Upper bound from interval hi
    if iv.hi.isSome:
      try:
        result.add(sLe(sVar(varName), sConst(iv.hi.get)))
      except CatchableError:
        discard  # computation fallback  # axiom:best-effort(ioboundary catch)

    # Induction variable with non-negative start
    if varName in ctx.inductionVars:
      if iv.lo.isSome and iv.lo.get >= 0:
        try:
          let candidate = sGe(sVar(varName), sConst(0))
          if candidate notin result:
            result.add(candidate)
        except CatchableError:
          discard  # computation fallback  # axiom:best-effort(ioboundary catch)

func extractBoundsFromLoopCondition(ctx: AbstractContext): seq[SymSExpr] {.raises: [].} =
  ## Derives invariant candidates from loop condition structure.
  result = @[]
  if ctx.loopCondition.isSome:
    let cond = ctx.loopCondition.get()
    # Extract bound from condition: e.g., (< i n) → i <= n
    if not cond.isNil and cond.kind in {seLt, seLe, seGt, seGe}:
      if cond.lhs != nil and cond.rhs != nil:
        if cond.lhs.kind == seVar:
          let varName = cond.lhs.name
          case cond.kind
          of seLt:
            # i < n → i <= n (n might be symbolic, so we keep it as var)
            if cond.rhs.kind == seVar:
              try:
                result.add(sLe(sVar(varName), cond.rhs))
              except CatchableError:
                discard  # computation fallback
          of seLe:
            if cond.rhs.kind == seVar:
              try:
                result.add(sLe(sVar(varName), cond.rhs))
              except CatchableError:
                discard  # computation fallback
          of seGt:
            if cond.rhs.kind == seVar:
              try:
                result.add(sGe(sVar(varName), cond.rhs))
              except CatchableError:
                discard  # computation fallback
          of seGe:
            if cond.rhs.kind == seVar:
              try:
                result.add(sGe(sVar(varName), cond.rhs))
              except CatchableError:
                discard  # computation fallback
          else:
            discard

# ---------------------------------------------------------------------------
# Analyze Variable Intervals At Loop Header
# ---------------------------------------------------------------------------

## Analyze Variable Intervals At Loop Header.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
func analyzeVariableIntervalsAtLoopHeader*(
  cfg: ControlFlowGraph;
  headerId: int
): Table[string, Interval] {.raises: [].} =
  ## Scans predecessor blocks of the loop header to determine variable intervals.
  ## Nim implicitly initializes integers to 0, so default is [0, 0].
  result = initTable[string, Interval]()

  # Default: all integer variables are implicitly [0, 0] in Nim
  # We will refine this by scanning declarations and assignments

  let headerBlock = cfg.blockById.getOrDefault(headerId)

  # Scan all predecessor blocks for variable declarations and assignments
  var blocksToScan: seq[int] = @[]
  for predId in headerBlock.predecessors:
    if predId >= 0 and predId < cfg.blocks.len:
      blocksToScan.add(predId)

  # Also scan the header block itself for declarations
  blocksToScan.add(headerId)

  for blockId in blocksToScan:
    for stmt in cfg.blocks[blockId].statements:
      if stmt.isNil:
        continue

      case stmt.kind
      of nkVarSection, nkLetSection:
        handleVarSection(stmt, result)
      of nkAsgn:
        handleAssignment(stmt, result)
      of nkForStmt:
        handleForLoop(stmt, result)
      else:
        discard

  # Ensure all variables mentioned in the header have at least [0, 0]
  for stmt in headerBlock.statements:
    let name = extractIdentifierNameP(stmt)
    if name.len > 0 and not result.hasKey(name):
      result[name] = intervalFromConst(0)

# ---------------------------------------------------------------------------
# Loop Condition Extraction
# ---------------------------------------------------------------------------

## Extract Loop Condition From Header.
# @axiom-hint: lean="(stmt ≥ 0)" smt="(assert (and (>= stmt 0)))"
func extractLoopConditionFromHeader*(
  cfg: ControlFlowGraph;
  headerId: int
): Option[SymSExpr] {.raises: [].} =
  ## Extracts the loop condition expression from the header block as an SymSExpr.
  let headerBlock = cfg.blockById.getOrDefault(headerId)
  for stmt in headerBlock.statements:
    if stmt.isNil:
      continue
    case stmt.kind
    of nkInfix, nkIdent:
      let condRes = nimExprToSymSExprP(stmt)
      if condRes.isOk():
        return some(condRes.get())
    of nkWhileStmt:
      # The while node's condition child (first child)
      if stmt.len > 0 and not stmt[0].isNil:
        let condRes = nimExprToSymSExprP(stmt[0])
        if condRes.isOk():
          return some(condRes.get())
    of nkForStmt:
      # For loop: extract range expression as condition approximation
      # nkForStmt: [varNames..., expr, body] — find the expr before body
      for c in stmt:
        if c.isNil: continue
        if c.kind != nkStmtList and c.kind != nkBlockStmt and c.kind != nkBlockExpr:
          let rangeRes = nimExprToSymSExprP(c)
          if rangeRes.isOk():
            return some(rangeRes.get())
    else:
      discard
  none(SymSExpr)

# ---------------------------------------------------------------------------
# Induction Variable Detection
# ---------------------------------------------------------------------------

## Detect Induction Variables.
# @axiom-hint: lean="leftName.length = 0 ∧ leftNode = c ∧ rightNode = c ∧ (bodyBlocks ≥ 0) ∧ (rightNode ≥ 0) ∧ (stmt ≥ 0) ∧ (leftNode ≥ 0) ∧ (result ≥ 0)" smt="(assert (and (= (str.len leftName) 0) (= leftNode c) (= rightNode c) (>= bodyBlocks 0) (>= rightNode 0) (>= stmt 0) (>= leftNode 0) (>= result 0)))"
func detectInductionVariables*(
  cfg: ControlFlowGraph;
  headerId: int
): seq[string] {.raises: [].} =
  ## Detects variables that are incremented/decremented in the loop body.
  ## Scans successor blocks of the header for assignments like i = i + 1.
  result = @[]
  let headerBlock = cfg.blockById.getOrDefault(headerId)
  var bodyBlocks: seq[int] = @[]
  for succId in headerBlock.successors:
    if succId >= 0 and succId < cfg.blocks.len and succId != headerId:
      bodyBlocks.add(succId)

  for blockId in bodyBlocks:
    for stmt in cfg.blocks[blockId].statements:
      if stmt.isNil or stmt.kind != nkAsgn:
        continue
      var leftNode: PNode = nil
      var rightNode: PNode = nil
      if stmt.len > 0 and not stmt[0].isNil: leftNode = stmt[0]
      if stmt.len > 1 and not stmt[1].isNil: rightNode = stmt[1]
      if leftNode.isNil or rightNode.isNil:
        continue
      let leftName = extractVariableName(leftNode)
      if leftName.len == 0:
        continue
      # Check if right side references the same variable (e.g., i = i + 1)
      let rightText = pNodeText(rightNode)
      if leftName in rightText:
        if leftName notin result:
          result.add(leftName)

# ---------------------------------------------------------------------------
# Candidate Invariant Derivation
# ---------------------------------------------------------------------------

## Derive Invariant Candidates.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
func deriveInvariantCandidates*(ctx: AbstractContext): seq[SymSExpr] {.raises: [].} =
  ## Derives obvious invariant candidates from interval analysis and loop structure.
  ## Layer 1: Abstract invariants derived before solver-backed validation.
  result = @[]

  # Interval-based bounds: non-negative, upper bound, induction variables
  result.add deriveIntervalBounds(ctx)

  # Loop condition-derived bounds: (< i n) → i <= n
  result.add extractBoundsFromLoopCondition(ctx)

  # Deduplicate
  var seen = initTable[string, bool]()
  var deduped: seq[SymSExpr] = @[]
  for c in result:
    let key = sExprToString(c)
    if not seen.hasKey(key):
      seen[key] = true
      deduped.add(c)
  result = deduped

# ---------------------------------------------------------------------------
# Initiation Assertion Generation
# ---------------------------------------------------------------------------

## Build Initiation Asserts.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
func buildInitiationAsserts*(ctx: AbstractContext): seq[string] {.raises: [].} =
  ## Builds SMT-LIB2 assertions from the abstract context for initiation check.
  ## These assertions represent what we know about variables at loop entry.
  result = @[]
  for varName, iv in ctx.intervals:
    if iv.lo.isSome and iv.hi.isSome and iv.lo.get == iv.hi.get:
      # Exact constant: (assert (= var value))
      result.add("(assert (= " & varName & " " & $iv.lo.get & "))")
    else:
      if iv.lo.isSome:
        result.add("(assert (>= " & varName & " " & $iv.lo.get & "))")
      if iv.hi.isSome:
        result.add("(assert (<= " & varName & " " & $iv.hi.get & "))")
{.pop.}

