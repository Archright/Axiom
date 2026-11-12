import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/types/domain_types
import std/strutils
export domain_types.SmtLogic

type
  SmtSort* = enum
    smBv64, smBool, smArray, smInt

## SMT-LIB2 Logic Selection and Operator Emission
##
## Defines the SmtLogic enum (QF_BV, QF_LIA, HORN) and helpers to emit
## SMT-LIB2 declarations/operators according to the selected logic.
##
## Gemini Patch #1: Nim `int` is signed → QF_BV comparisons use signed
## bit-vector operators (bvslt/bvsle/bvsgt/bvsge), NOT unsigned (bvult/bvule).

## SMT-LIB2 logic enum is now defined in core/types/domain_types.
## All behavior funcs below operate on the re-exported SmtLogic type.

func smtLogicName*(logic: SmtLogic): string {.raises: [].} =
  ## Return the SMT-LIB2 logic name for a SmtLogic value.
  ## Used by irToSmtScript to parameterize the `(set-logic ...)` command.
  case logic
  of slQfBv:  "QF_BV"
  of slQfLia: "QF_LIA"
  of slHorn:  "HORN"
  of slQfSlia: "QF_SLIA"
  of slQfAufbv: "QF_AUFBV"

func emitLogicHeader*(logic: SmtLogic): string {.raises: [].} =
  ## Emit the `(set-logic ...)` command.
  "(set-logic " & smtLogicName(logic) & ")"
func emitVariableDeclaration*(name: string; logic: SmtLogic): string {.raises: [].} =
  ## Emit a variable declaration appropriate for the logic.
  case logic
  of slQfBv, slQfAufbv:
    "(declare-fun " & name & " () (_ BitVec 64))"
  of slQfLia, slHorn, slQfSlia:
    "(declare-fun " & name & " () Int)"
func emitOp*(op: string; logic: SmtLogic): string {.raises: [].} =
  ## Emit an arithmetic/comparison operator in SMT-LIB2 syntax.
  ##
  ## For QF_LIA/HORN: native Int operators (+, -, <, <=, etc.)
  ## For QF_BV: signed 64-bit bit-vector operators (Gemini Patch #1)
  let lowered = op.toLowerAscii()
  if logic in {slQfLia, slHorn}:
    case lowered
    of "add", "+": "+"
    of "sub", "-": "-"
    of "mul", "*": "*"
    of "lt",  "<": "<"
    of "le",  "<=": "<="
    of "gt",  ">": ">"
    of "ge",  ">=": ">="
    of "div", "/": "div"
    of "mod", "%": "mod"
    else: op
  else:
    case lowered
    of "add", "+": "bvadd"
    of "sub", "-": "bvsub"
    of "mul", "*": "bvmul"
    of "div", "/": "bvsdiv"
    of "mod", "%": "bvsmod"
    of "lt",  "<": "bvslt"
    of "le",  "<=": "bvsle"
    of "gt",  ">": "bvsgt"
    of "ge",  ">=": "bvsge"
    of "and", "&": "bvand"
    of "or",  "|": "bvor"
    of "xor", "^": "bvxor"
    of "not", "~": "bvnot"
    of "shl", "<<": "bvshl"
    of "shr", ">>": "bvashr"
    else: "bv" & op
func emitNumericLiteral*(value: string; logic: SmtLogic): string {.raises: [].} =
  ## Emit a numeric literal appropriate for the logic.
  ##
  ## QF_BV: `(_ bv<value> 64)`
  ## QF_LIA/HORN: plain integer string
  if logic in {slQfBv, slQfAufbv}:
    "(_ bv" & value & " 64)"
  else:
    value
func emitBoundsCheck*(varName: string; logic: SmtLogic;
                      minVal, maxVal: string): string {.raises: [].} =
  ## Emit a bounds-check assertion: minVal <= varName <= maxVal.
  if logic in {slQfLia, slHorn}:
    "(and (>= " & varName & " " & minVal & ") (<= " & varName & " " & maxVal & "))"
  else:
    ## For QF_BV/QF_AUFBV we already declare 64-bit vectors; unsigned range
    ## check is equivalent to the declared width.
    "(and (bvuge " & varName & " " & emitNumericLiteral(minVal, logic) & ") " &
    "(bvule " & varName & " " & emitNumericLiteral(maxVal, logic) & "))"
func emitHornRelationDecl*(name: string; argTypes: seq[string]): string {.raises: [].} =
  ## Emit a HORN relation declaration.
  ##
  ## Example: `emitHornRelationDecl("mc", @["Int", "Int"])` →
  ##   (declare-rel mc (Int Int))
  var typeList = ""
  for i, t in argTypes:
    if i > 0: typeList.add(" ")
    typeList.add(t)
  "(declare-rel " & name & " (" & typeList & "))"
func emitHornRule*(head: string; body: seq[string]): string {.raises: [].} =
  ## Emit a HORN clause rule: (rule (=> (and body...) head)).
  ##
  ## If `body` is empty, emits a fact: (rule head).
  ## If `body` has one element, emits: (rule (=> body0 head)).
  ## Otherwise: (rule (=> (and body0 body1 ...) head)).
  if body.len == 0:
    "(rule " & head & ")"
  elif body.len == 1:
    "(rule (=> " & body[0] & " " & head & "))"
  else:
    var bodyExpr = "(and"
    for b in body:
      bodyExpr.add(" " & b)
    bodyExpr.add(")")
    "(rule (=> " & bodyExpr & " " & head & "))"
func emitHornQuery*(name: string; printCertificate: bool = false): string {.raises: [].} =
  ## Emit a HORN query with optional certificate production.
  ##
  ## Example: `emitHornQuery("inv", printCertificate=true)` →
  ##   (query inv :print-certificate true)
  if printCertificate:
    "(query " & name & " :print-certificate true)"
  else:
    "(query " & name & ")"
func selectLogicFromAst*(hasBitwiseOps, hasNonLinear, hasLoops: bool): SmtLogic {.raises: [].} =
  ## Heuristic: choose the most appropriate logic for a given function.
  ##
  ## - Bitwise ops (and, or, xor, shifts) → QF_BV (native support)
  ## - Non-linear arithmetic → QF_BV (LIA only handles linear)
  ## - Loops + inductive invariants → HORN (SPACER engine)
  ## - Otherwise → QF_LIA (default, overflow VC friendly)
  if hasLoops:
    slHorn
  elif hasBitwiseOps or hasNonLinear:
    slQfBv
  else:
    slQfLia

{.pop.}
