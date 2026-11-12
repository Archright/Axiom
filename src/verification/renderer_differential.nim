import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Dual-renderer differential (certification-continuity Phase 3.5).
##
## Compares the canonical obligation renderer
## (`verification/obligation/canonical_verification.lowerIRExprToLean` —
## Int-typed, Prop comparisons) against the BitVec renderer
## (`core/trusted/ir_to_lean.irExprToLean` — BitVec-typed, let-binding form)
## at the expression level, restricted to their OVERLAPPING bounded subset:
## Int literals, variables, `+`, `-`, `<`, `≤`, `>`, `≥`, `=`, `∧`, `∨`, `¬`,
## if-then-else.
##
## Format differences are normalized before comparison (documented dialect
## mapping): whitespace/indentation, if-then-else layout, and the operator
## spellings `==`→`=`, `&&`→`∧`, `||`→`∨`, `!`→`¬`. Normalization lexes the
## rendered Lean text into a shared token dialect, parses it, and re-emits
## the canonical fully-parenthesized form. In the shared dialect every
## binary operator node is parenthesized and nested if-then-else binds by
## the dangling-else rule — exactly the shapes both renderers emit on the
## overlap — so the normalized text depends only on the parse tree.
## Text that does not parse in the shared dialect (structurally ambiguous
## or malformed) is rdDisagree — fail-closed, never a silent pass.
##
## Verdicts:
##   rdAgree    — both renderers produced the same normalized form
##   rdDisagree — rendered forms differ after normalization, or one side is
##                empty/unparseable in the shared dialect (fail-closed)
##   rdSkip     — outside the overlapping subset (documented; not evidence)
##
## INV-4 note: this module is a same-language differential, NOT independent
## verification evidence by itself (two renderers, one codebase). Its
## purpose is catching accidental divergence between the two renderers on
## the certified overlap.

import std/sets
import core/trusted/axiom_ir
import core/trusted/ir_to_lean
import verification/obligation/canonical_verification

type RendererDifferentialVerdict* = enum
  rdAgree
  rdDisagree
  rdSkip

# ---------------------------------------------------------------------------
# Structural overlap check — the forms BOTH renderers certify
# ---------------------------------------------------------------------------

func inDifferentialSubset*(e: IRExpr): bool {.raises: [].} =
  ## True when `e` is structurally inside the overlapping bounded subset:
  ## the forms lowerIRExprToLean supports (bounded Int subset) AND
  ## irExprToLean renders with non-`UNSUPPORTED` operators. Everything
  ## else is skipped, never compared.
  if e == nil:
    return false
  case e.kind
  of irLit, irVar:
    result = true
  of irBinOp:
    case e.binOp
    of boAdd, boSub, boLt, boLe, boGt, boGe, boEq, boAnd, boOr:
      result = inDifferentialSubset(e.binLhs) and inDifferentialSubset(e.binRhs)
    else:
      result = false
  of irUnaryOp:
    result = e.unaryOp == uoNot and inDifferentialSubset(e.unaryArg)
  of irIf:
    result = inDifferentialSubset(e.ifCond) and
             inDifferentialSubset(e.ifThen) and
             inDifferentialSubset(e.ifElse)
  else:
    result = false

# ---------------------------------------------------------------------------
# Shared-dialect lexer — tokens of the rendered Lean text
# ---------------------------------------------------------------------------
## Words ([A-Za-z0-9_]+, keywords if/then/else), operator symbols and
## parentheses. ir_to_lean spellings `==` `&&` `||` `!` are normalized to
## the shared dialect `=` `∧` `∨` `¬` at lex time. Whitespace is
## insignificant. Unlexable bytes → empty seq (outside the dialect).

const
  tokAnd = "∧"
  tokOr = "∨"
  tokLe = "≤"
  tokGe = "≥"
  tokNot = "¬"

func isWordByte(c: char): bool {.raises: [].} =
  (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
  (c >= '0' and c <= '9') or c == '_'

func isDigitByte(c: char): bool {.raises: [].} =
  c >= '0' and c <= '9'

func startsAt(s: string; i: int; tok: string): bool {.raises: [].} =
  ## True when the multi-byte UTF-8 token `tok` starts at byte offset `i`.
  if i + tok.len > s.len:
    return false
  for k in 0 ..< tok.len:
    if s[i + k] != tok[k]:
      return false
  true

func lexSymbol*(rendered: string; i: int): tuple[token: string, next: int] {.raises: [].} =
  ## Lex ONE non-word token at byte offset `i` (parens, operators,
  ## multi-byte Unicode, or the ir_to_lean ASCII spellings).
  ## token = "" means `i` is not the start of any symbol — caller fails
  ## closed (outside the shared dialect).
  result = ("", i)
  if i >= rendered.len:
    return
  let c = rendered[i]
  if c == '(' or c == ')':
    return ($c, i + 1)
  if startsAt(rendered, i, tokAnd): return (tokAnd, i + tokAnd.len)
  if startsAt(rendered, i, tokOr): return (tokOr, i + tokOr.len)
  if startsAt(rendered, i, tokLe): return (tokLe, i + tokLe.len)
  if startsAt(rendered, i, tokGe): return (tokGe, i + tokGe.len)
  if startsAt(rendered, i, tokNot): return (tokNot, i + tokNot.len)
  if c == '&':
    if i + 1 < rendered.len and rendered[i + 1] == '&':
      return (tokAnd, i + 2)
    return
  if c == '|':
    if i + 1 < rendered.len and rendered[i + 1] == '|':
      return (tokOr, i + 2)
    return
  if c == '=':
    if i + 1 < rendered.len and rendered[i + 1] == '=':
      return ("=", i + 2)
    return ("=", i + 1)
  if c == '!': return (tokNot, i + 1)
  if c == '<': return ("<", i + 1)
  if c == '>': return (">", i + 1)
  if c == '+': return ("+", i + 1)
  if c == '-': return ("-", i + 1)
  return

func tokenizeLean*(rendered: string): seq[string] {.raises: [].} =
  ## Lex rendered Lean text into shared-dialect tokens.
  ## Empty result means the text is outside the shared dialect.
  result = @[]
  var i = 0
  while i < rendered.len:
    let c = rendered[i]
    if c == ' ' or c == '\n' or c == '\t' or c == '\r':
      inc i
    elif isWordByte(c):
      var j = i
      while j < rendered.len and isWordByte(rendered[j]):
        inc j
      result.add(rendered[i ..< j])
      i = j
    else:
      let (tok, next) = lexSymbol(rendered, i)
      if tok.len == 0:
        return @[]
      result.add(tok)
      i = next

func isBinOpTok(t: string): bool {.raises: [].} =
  t == "+" or t == "-" or t == "<" or t == ">" or t == "=" or
  t == tokLe or t == tokGe or t == tokAnd or t == tokOr

# ---------------------------------------------------------------------------
# Shared-dialect parser → canonical re-emission
# ---------------------------------------------------------------------------
## Grammar (identical for both renderer dialects after tokenization):
##   expr := atom | "-" number | ¬ expr
##         | ( expr )                 -- transparent grouping
##         | ( expr op expr )         -- operator node
##         | if expr then expr else expr
## Re-emission produces ONE canonical fully-parenthesized form, so the
## normalized text depends only on the parse tree — never on layout,
## whitespace, or where the original parens sat.

type DialectParser = object
  toks: seq[string]
  pos: int
  ok: bool

func parseDialectExpr(p: var DialectParser): string {.raises: [].}

func parseDialectGroup(p: var DialectParser): string {.raises: [].} =
  ## Parse a parenthesized expression: transparent single-expr grouping or
  ## a binary operator node; return the canonical re-emission.
  inc p.pos
  let inner = parseDialectExpr(p)
  if not p.ok:
    return ""
  if p.pos >= p.toks.len:
    p.ok = false
    return ""
  let nxt = p.toks[p.pos]
  if nxt == ")":
    inc p.pos
    return inner
  if isBinOpTok(nxt):
    inc p.pos
    let rhs = parseDialectExpr(p)
    if not p.ok:
      return ""
    if p.pos >= p.toks.len or p.toks[p.pos] != ")":
      p.ok = false
      return ""
    inc p.pos
    return "(" & inner & " " & nxt & " " & rhs & ")"
  p.ok = false
  ""

func parseDialectIf(p: var DialectParser): string {.raises: [].} =
  ## Parse `if expr then expr else expr` — nested if-forms bind by the
  ## dangling-else rule, exactly as in both renderer dialects and Lean.
  inc p.pos
  let cond = parseDialectExpr(p)
  if not p.ok:
    return ""
  if p.pos >= p.toks.len or p.toks[p.pos] != "then":
    p.ok = false
    return ""
  inc p.pos
  let thenE = parseDialectExpr(p)
  if not p.ok:
    return ""
  if p.pos >= p.toks.len or p.toks[p.pos] != "else":
    p.ok = false
    return ""
  inc p.pos
  let elseE = parseDialectExpr(p)
  if not p.ok:
    return ""
  "if " & cond & " then " & thenE & " else " & elseE

func parseDialectExpr(p: var DialectParser): string {.raises: [].} =
  ## Parse one expression; return its canonical form ("" = failure,
  ## p.ok = false).
  result = ""
  if not p.ok:
    return
  if p.pos >= p.toks.len:
    p.ok = false
    return
  let t = p.toks[p.pos]
  if t == "(":
    result = parseDialectGroup(p)
  elif t == "if":
    result = parseDialectIf(p)
  elif t == tokNot:
    inc p.pos
    let arg = parseDialectExpr(p)
    if not p.ok:
      return
    result = tokNot & " " & arg
  elif t == "-":
    # negative literal only at expression head (unary minus is outside both
    # renderers' certified forms)
    if p.pos + 1 >= p.toks.len or not isDigitByte(p.toks[p.pos + 1][0]):
      p.ok = false
      return
    inc p.pos
    result = "-" & p.toks[p.pos]
    inc p.pos
  elif isWordByte(t[0]) and not isDigitByte(t[0]):
    if t == "if" or t == "then" or t == "else":
      p.ok = false
      return
    result = t
    inc p.pos
  elif isDigitByte(t[0]):
    result = t
    inc p.pos
  else:
    p.ok = false

func normalizeLeanForDifferential*(rendered: string): tuple[ok: bool, normalized: string] {.raises: [].} =
  ## Parse `rendered` in the shared dialect and re-emit its canonical form.
  ## ok = false when the text is empty, unlexable, or structurally
  ## ambiguous in the shared dialect.
  if rendered.len == 0:
    return (false, "")
  let toks = tokenizeLean(rendered)
  if toks.len == 0:
    return (false, "")
  var p = DialectParser(toks: toks, pos: 0, ok: true)
  let tree = parseDialectExpr(p)
  if not p.ok or p.pos != toks.len:
    return (false, "")
  (true, tree)

# ---------------------------------------------------------------------------
# Differential entry points
# ---------------------------------------------------------------------------

func differentialCompareNormalized*(
  canonicalRendered, irRendered: string
): RendererDifferentialVerdict {.raises: [].} =
  ## Compare two ALREADY-RENDERED expressions (canonical renderer output vs
  ## ir_to_lean renderer output) after shared-dialect normalization.
  ## Either side empty, unlexable, or structurally ambiguous → rdDisagree
  ## (fail-closed — the text is outside the comparable dialect).
  if canonicalRendered.len == 0 or irRendered.len == 0:
    return rdDisagree
  let a = normalizeLeanForDifferential(canonicalRendered)
  let b = normalizeLeanForDifferential(irRendered)
  if not a.ok or not b.ok:
    return rdDisagree
  if a.normalized == b.normalized:
    return rdAgree
  rdDisagree

func differentialCheck*(
  e: IRExpr;
  paramNames: HashSet[string]
): RendererDifferentialVerdict {.raises: [].} =
  ## Compare the canonical renderer output vs the ir_to_lean renderer output
  ## for one IR expression on the overlapping subset.
  ##   - outside the structural overlap        → rdSkip (documented)
  ##   - canonical renderer unsupported ("")   → rdSkip (bounded-subset rule)
  ##   - normalized forms equal                → rdAgree
  ##   - normalized forms differ / unparseable → rdDisagree (fail-closed)
  if not inDifferentialSubset(e):
    return rdSkip
  let canonical = lowerIRExprToLean(e, paramNames)
  if canonical.len == 0:
    return rdSkip
  let irSide = irExprToLean(e, 0)
  if irSide.len == 0:
    return rdSkip
  differentialCompareNormalized(canonical, irSide)
