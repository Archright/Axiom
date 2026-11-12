import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## AST-Based Axiom Signature — deterministic structure-level matching.
##
## Replaces string-based axiom matching with canonical IR-structure hashing.
## Two functions with identical IR structure produce the same signature,
## regardless of variable names or formatting.
##
## Design: all functions are `func` (no side effects), SHA-256 for hashing.

import core/crypto/hash_kernel
import core/trusted/axiom_ir
import std/strutils

# ---------------------------------------------------------------------------
# IRType → canonical short name
# ---------------------------------------------------------------------------

func irTypeShortName*(t: IRType): string {.raises: [].} =
  ## Canonical short name for an IR type.
  ##   irtBitVec64 → "bv64"
  ##   irtBool     → "bool"
  ##   irtList(T)  → "list(<T>)"
  case t.kind
  of irtBitVec64: "bv64"
  of irtBool: "bool"
  of irtString: "str"
  of irtEnum: "enum(" & t.enumName & ")"
  of irtVariant: "variant(" & t.variantName & ")"
  of irtList: "list(" & irTypeShortName(t.elemType) & ")"

# ---------------------------------------------------------------------------
# Parameter signature (canonical string from IR param types)
# ---------------------------------------------------------------------------

func computeIrTypeSignature*(params: seq[IRFuncParam]): string {.raises: [].} =
  ## Canonical string from IR parameter types.
  ##   @[bv64, bv64] → "(bv64,bv64)"
  ##   @[bool]        → "(bool)"
  ##   @[]            → "()"
  result = "("
  for i, p in params:
    if i > 0: result.add(",")
    result.add(irTypeShortName(p.ty))
  result.add(")")

# ---------------------------------------------------------------------------
# Full function signature hash
# ---------------------------------------------------------------------------

func computeIrSignatureHash*(params: seq[IRFuncParam],
                              retType: IRType): string {.raises: [].} =
  ## SHA-256 of the canonical signature string.
  ##   (bv64,bv64) → bv64  →  hash("(bv64,bv64)->bv64")
  let paramSig = computeIrTypeSignature(params)
  let fullSig = paramSig & "->" & irTypeShortName(retType)
  result = hash_kernel.sha256Hex(fullSig)

# ---------------------------------------------------------------------------
# Expression structure hash (deterministic tree traversal)
# ---------------------------------------------------------------------------

func irExprStructure*(e: IRExpr): string {.raises: [].} =
  ## Deterministic canonical string from expression tree structure.
  ## Captures node kinds and literal values, but NOT variable names —
  ## making the hash insensitive to renaming.
  case e.kind
  of irLit:
    result = "lit(" & $e.litVal & ")"
  of irFloatLit:
    result = "flit(" & $e.floatVal & ")"
  of irVar:
    result = "var(" & irTypeShortName(e.varType) & ")"
  of irLet:
    result = "let(" & irExprStructure(e.letVal) & "," & irExprStructure(e.letBody) & ")"
  of irIf:
    result = "if(" & irExprStructure(e.ifCond) & "," &
            irExprStructure(e.ifThen) & "," &
            irExprStructure(e.ifElse) & ")"
  of irCase:
    result = "case(" & irExprStructure(e.caseScrutinee)
    for br in e.caseBranches:
      result.add("," & $br.pattern & "=>" & irExprStructure(br.body))
    if e.caseDefault != nil:
      result.add(",default=>" & irExprStructure(e.caseDefault))
    result.add(")")
  of irCall:
    result = "call(" & e.callName
    for a in e.callArgs:
      result.add("," & irExprStructure(a))
    result.add(")")
  of irBinOp:
    result = "binop(" & $e.binOp & "," &
              irExprStructure(e.binLhs) & "," &
              irExprStructure(e.binRhs) & ")"
  of irUnaryOp:
    result = "unaryop(" & $e.unaryOp & "," & irExprStructure(e.unaryArg) & ")"
  of irRecCall:
    result = "rec("
    for i, a in e.recArgs:
      if i > 0: result.add(",")
      result.add(irExprStructure(a))
    result.add(")")
  of irStringLit:
    result = "strlit(" & $e.stringVal & ")"
  of irLoop:
    result = "loop(" & $e.loopKind & ",["
    for i, v in e.loopVars:
      if i > 0: result.add(",")
      result.add(v)
    result.add("],[")
    for i, init in e.loopInits:
      if i > 0: result.add(",")
      result.add(irExprStructure(init))
    result.add("],")
    result.add(irExprStructure(e.loopCond))
    result.add(",")
    if e.loopStep != nil:
      result.add(irExprStructure(e.loopStep))
    else:
      result.add("nil")
    result.add(",")
    result.add(irExprStructure(e.loopBody))
    if e.loopInvariants.len > 0:
      result.add(",[")
      for i, inv in e.loopInvariants:
        if i > 0: result.add(",")
        result.add(irExprStructure(inv))
      result.add("]")
    if e.loopVariant != nil:
      result.add(",variant=")
      result.add(irExprStructure(e.loopVariant))
    result.add(")")
  of irCast:
    result = "cast(" & irTypeShortName(e.castFrom) & "," &
             irTypeShortName(e.castTo) & "," &
             irExprStructure(e.castExpr) & ")"

func computeNimAstHash*(f: IRFuncDef): string {.raises: [].} =
  ## Deterministic hash of the full IR function definition.
  ## Covers: name + param types + return type + body structure.
  result = hash_kernel.sha256Hex("func:" & f.name & "|params:" & computeIrTypeSignature(f.params) & "|ret:" & irTypeShortName(f.retType) & "|recursive:" & $f.isRecursive & "|body:" & irExprStructure(f.body))

# ---------------------------------------------------------------------------
# Lean signature hash
# ---------------------------------------------------------------------------

func computeLeanSignatureHash*(leanOutput: string): string {.raises: [].} =
  ## Hash of Lean #print output.
  ## Normalizes whitespace before hashing for determinism.
  var normalized = ""
  for ch in leanOutput:
    if ch notin {' ', '\t', '\r', '\n'}:
      normalized.add(ch)
  result = hash_kernel.sha256Hex(normalized)

# ---------------------------------------------------------------------------
# AxiomSignature aggregate
# ---------------------------------------------------------------------------

type
  AxiomSignature* = object
    nimHash*: string          ## SHA-256 of full IR function definition
    leanHash*: string         ## SHA-256 of normalized Lean output
    paramSignature*: string   ## Canonical param signature, e.g. "(bv64,bv64)->bv64"

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

func axiomSignature*(f: IRFuncDef, leanOutput: string = ""): AxiomSignature {.raises: [].} =
  ## Compute the full AST-based axiom signature for an IR function.
  let paramSig = computeIrTypeSignature(f.params) & "->" & irTypeShortName(f.retType)
  AxiomSignature(
    nimHash: computeNimAstHash(f),
    leanHash: if leanOutput.len > 0: computeLeanSignatureHash(leanOutput) else: "",
    paramSignature: paramSig
  )

{.pop.}
