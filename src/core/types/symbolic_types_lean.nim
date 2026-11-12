import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import core/trusted/axiom_pragmas
import core/symbolic/symbolic_types_expr
## S Expr To Lean.
func sExprToLean*(e: SymSExpr): string {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  ## Recursively converts an SymSExpr to Lean 4 infix syntax.
  if e.isNil:
    return "nil"
  case e.kind
  of seVar: e.name
  of seConst: $e.intValue
  of seTrue: "True"
  of seFalse: "False"
  of seAdd: "(" & sExprToLean(e.lhs) & " + " & sExprToLean(e.rhs) & ")"
  of seSub: "(" & sExprToLean(e.lhs) & " - " & sExprToLean(e.rhs) & ")"
  of seMul: "(" & sExprToLean(e.lhs) & " * " & sExprToLean(e.rhs) & ")"
  of seDiv: "(" & sExprToLean(e.lhs) & " / " & sExprToLean(e.rhs) & ")"
  of seMod: "(" & sExprToLean(e.lhs) & " % " & sExprToLean(e.rhs) & ")"
  of seEq: "(" & sExprToLean(e.lhs) & " = " & sExprToLean(e.rhs) & ")"
  of seNe: "(" & sExprToLean(e.lhs) & " ≠ " & sExprToLean(e.rhs) & ")"
  of seLt: "(" & sExprToLean(e.lhs) & " < " & sExprToLean(e.rhs) & ")"
  of seLe: "(" & sExprToLean(e.lhs) & " ≤ " & sExprToLean(e.rhs) & ")"
  of seGt: "(" & sExprToLean(e.lhs) & " > " & sExprToLean(e.rhs) & ")"
  of seGe: "(" & sExprToLean(e.lhs) & " ≥ " & sExprToLean(e.rhs) & ")"
  of seAnd: "(" & sExprToLean(e.lhs) & " ∧ " & sExprToLean(e.rhs) & ")"
  of seOr: "(" & sExprToLean(e.lhs) & " ∨ " & sExprToLean(e.rhs) & ")"
  of seNot: "(¬" & sExprToLean(e.lhs) & ")"
  of seNone: "Option.none"
  of seSome: "(some " & sExprToLean(e.lhs) & ")"
  of seIsSome: "(" & sExprToLean(e.lhs) & ".isSome)"
  of seVal: "(" & sExprToLean(e.lhs) & ".get!)"
  of seOk: "(ok " & sExprToLean(e.lhs) & ")"
  of seErr: "(err " & sExprToLean(e.lhs) & ")"
  of seIsOk: "(" & sExprToLean(e.lhs) & ".isOk)"
  of seErrMsg: "(" & sExprToLean(e.lhs) & ".errMsg)"
  of seUninterpretedApp: e.name & " " & sExprToLean(e.lhs)
  of seAxiomRef: e.name
  of seNil: "[]"
  of seCons: "(" & sExprToLean(e.lhs) & " :: " & sExprToLean(e.rhs) & ")"
  of seHead: "(" & sExprToLean(e.lhs) & ".head!)"
  of seTail: "(" & sExprToLean(e.lhs) & ".tail!)"
  of seLength: "(" & sExprToLean(e.lhs) & ".length)"

{.pop.}
