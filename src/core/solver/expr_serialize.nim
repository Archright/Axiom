import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/types/solver_types  # SmtSExpr (moved from solver/types by parallel refactor)
import std/strutils

func needsBvCoercion*(s: string): bool {.inline.} =
  ## Heuristic: returns true if an SMT-LIB2 term is likely BitVec64 sort
  ## rather than Bool. Used to coerce operands for boolean operators.
  let t = s.strip()
  if t.len == 0: return false
  # Hex literal: #x...
  if t[0] == '#': return true
  # Bitvector numeral: (_ bv...)
  if t.startsWith("(_ bv"): return true
  # Bitvector arithmetic always returns BitVec64 (NOT comparisons like bvslt)
  if t.startsWith("(bvadd ") or t.startsWith("(bvsub ") or
     t.startsWith("(bvmul ") or t.startsWith("(bvsdiv ") or
     t.startsWith("(bvsrem ") or t.startsWith("(bvshl ") or
     t.startsWith("(bvlshr ") or t.startsWith("(bvashr ") or
     t.startsWith("(bvneg ") or t.startsWith("(bvnot ") or
     t.startsWith("(bvand ") or t.startsWith("(bvor ") or
     t.startsWith("(bvxor "): return true
  false

func coerceToBoolStr*(smtExpr: string): string {.inline, raises: [].} =
  ## Coerce a BV64 SMT expression to Bool sort.
  ## BV64 value is nonzero → true, zero → false.
  ## This is the string-based bridge; prefer smt_sort.coerceToBool() for new code.
  "(not (= " & smtExpr & " #x0000000000000000))"

func coerceToBool*(s: string): string {.inline, raises: [].} =
  ## Coerce a BitVec64 SMT term to Bool via canonical coerceToBoolStr.
  ## Preserves Bool expressions unchanged (heuristic check).
  if needsBvCoercion(s):
    coerceToBoolStr(s)
  else:
    s

func toSmt*(e: SmtSExpr): string {.raises: [].} =
  case e.kind
  of exprIntLit, exprBoolLit, exprSymbol:
    e.text
  of exprIte:
    "(ite " & toSmt(e.args[0]) & " " & toSmt(e.args[1]) & " " & toSmt(e.args[2]) & ")"
  of exprAdd:
    "(+ " & toSmt(e.args[0]) & " " & toSmt(e.args[1]) & ")"
  of exprSub:
    "(- " & toSmt(e.args[0]) & " " & toSmt(e.args[1]) & ")"
  of exprMul:
    "(* " & toSmt(e.args[0]) & " " & toSmt(e.args[1]) & ")"
  of exprEq:
    "(= " & toSmt(e.args[0]) & " " & toSmt(e.args[1]) & ")"
  of exprLt:
    "(< " & toSmt(e.args[0]) & " " & toSmt(e.args[1]) & ")"
  of exprLe:
    "(<= " & toSmt(e.args[0]) & " " & toSmt(e.args[1]) & ")"
  of exprGt:
    "(> " & toSmt(e.args[0]) & " " & toSmt(e.args[1]) & ")"
  of exprGe:
    "(>= " & toSmt(e.args[0]) & " " & toSmt(e.args[1]) & ")"
  of exprAnd:
    "(and " & coerceToBool(toSmt(e.args[0])) & " " & coerceToBool(toSmt(e.args[1])) & ")"
  of exprOr:
    "(or " & coerceToBool(toSmt(e.args[0])) & " " & coerceToBool(toSmt(e.args[1])) & ")"
  of exprNot:
    "(not " & toSmt(e.args[0]) & ")"
  of exprImplies:
    "(=> " & toSmt(e.args[0]) & " " & toSmt(e.args[1]) & ")"
func namedAssert*(label: string, expr: SmtSExpr): string {.raises: [].} =
  "(assert (! " & toSmt(expr) & " :named " & label & "))"
