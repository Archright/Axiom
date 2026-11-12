import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

## PNode → CanonNode bridge (WP1.5-a).
##
## Purpose: let headless-parsed EXTERNAL subject sources flow into the existing
## CanonNode→IRFuncDef production path (ast_to_ir.convertFuncDefCanon) without
## any PNode→NimNode casting, which is forbidden by
## docs/spec/pnode_nimnode_type_separation_quirk.md (ptr vs ref type separation).
##
## Mapping contract: mirrors tools/shared/canonical_ast.nim::toCanon(NimNode)
## field-for-field — kind via nimKindToCanon, name for ident/sym, strVal for
## string literals (+ident), intVal/floatVal for literal families, then
## recursive children. Structural identity between the two frontends is the
## WP1.5 acceptance anchor (serializeIRFuncDef byte-equality test).

import core/parser_utils                 # PNode + compiler ast re-exports
import std/strutils                      # contains(s, sub)
import shared/canonical_ast              # CanonNode / CanonKind / nimKindToCanon
import compiler/[ast, idents]            # TNodeKind nk* constants, ident access

func pnodeKindName*(n: PNode): string =
  ## Diagnostics helper: raw nk name for unsupported-kind reporting.
  $(n.kind)

func toCanonKind(nk: TNodeKind): CanonKind =
  ## PNode (TNodeKind) → CanonKind. Deliberately parallel to
  ## canonical_ast.nim::nimKindToCanon so both frontends converge on the same
  ## discriminators. Unmapped kinds land on ckUnknown, mirroring toCanon.
  case nk
  of nkEmpty:            ckEmpty
  of nkIdent:            ckIdent
  of nkSym:              ckSym
  of nkCharLit:          ckCharLit
  of nkIntLit..nkInt64Lit: CanonKind(ord(ckIntLit) + ord(nk) - ord(nkIntLit))
  of nkUIntLit..nkUInt64Lit: CanonKind(ord(ckUIntLit) + ord(nk) - ord(nkUIntLit))
  of nkFloatLit..nkFloat128Lit: CanonKind(ord(ckFloatLit) + ord(nk) - ord(nkFloatLit))
  of nkStrLit:           ckStrLit
  of nkRStrLit:          ckRStrLit
  of nkTripleStrLit:     ckTripleStrLit
  of nkNilLit:           ckNilLit
  of nkCommand:          ckCommand
  of nkCall:             ckCall
  of nkInfix:            ckInfix
  of nkPrefix:           ckPrefix
  of nkPostfix:          ckPostfix
  of nkExprEqExpr:       ckExprEqExpr
  of nkExprColonExpr:    ckExprColonExpr
  of nkIdentDefs:        ckIdentDefs
  of nkVarTuple:         ckVarTuple
  of nkPar:              ckPar
  of nkObjConstr:        ckObjConstr
  of nkCurly:            ckCurly
  of nkCurlyExpr:        ckCurlyExpr
  of nkBracket:          ckBracket
  of nkBracketExpr:      ckBracketExpr
  of nkPragmaExpr:       ckPragmaExpr
  of nkRange:            ckRange
  of nkDotExpr:          ckDotExpr
  of nkIfExpr:           ckIfExpr
  of nkElifBranch:       ckElifBranch
  of nkElse:             ckElse
  of nkElifExpr:         ckElifExpr
  of nkElseExpr:         ckElseExpr
  of nkLambda:           ckLambda
  of nkDo:               ckDo
  of nkClosedSymChoice:  ckClosedSymChoice
  of nkOpenSymChoice:    ckOpenSymChoice
  of nkHiddenStdConv:    ckHiddenStdConv
  of nkHiddenSubConv:    ckHiddenSubConv
  of nkConv:             ckConv
  of nkCast:             ckCast
  of nkStaticStmt:       ckStaticStmt
  of nkProcDef:          ckProcDef
  of nkFuncDef:          ckFuncDef
  of nkMethodDef:        ckMethodDef
  of nkConverterDef:     ckConverterDef
  of nkMacroDef:         ckMacroDef
  of nkTemplateDef:      ckTemplateDef
  of nkIteratorDef:      ckIteratorDef
  of nkOfBranch:         ckOfBranch
  of nkExceptBranch:     ckExceptBranch
  of nkIfStmt:           ckIfStmt
  of nkWhenStmt:         ckWhenStmt
  of nkForStmt:          ckForStmt
  of nkParForStmt:       ckParForStmt
  of nkWhileStmt:        ckWhileStmt
  of nkCaseStmt:         ckCaseStmt
  of nkVarSection:       ckVarSection
  of nkLetSection:       ckLetSection
  of nkConstSection:     ckConstSection
  of nkConstDef:         ckConstDef
  of nkTypeDef:          ckTypeDef
  of nkYieldStmt:        ckYieldStmt
  of nkDefer:            ckDefer
  of nkTryStmt:          ckTryStmt
  of nkFinally:          ckFinally
  of nkRaiseStmt:        ckRaiseStmt
  of nkReturnStmt:       ckReturnStmt
  of nkBreakStmt:        ckBreakStmt
  of nkContinueStmt:     ckContinueStmt
  of nkBlockStmt:        ckBlockStmt
  of nkDiscardStmt:      ckDiscardStmt
  of nkStmtList:         ckStmtList
  of nkStmtListExpr:     ckStmtListExpr
  of nkBlockExpr:        ckBlockExpr
  of nkObjectTy:         ckObjectTy
  of nkTupleTy:          ckTupleTy
  of nkRefTy:            ckRefTy
  of nkPtrTy:            ckPtrTy
  of nkVarTy:            ckVarTy
  of nkEnumTy:           ckEnumTy
  of nkEnumFieldDef:     ckEnumFieldDef
  of nkFormalParams:     ckFormalParams
  of nkGenericParams:    ckGenericParams
  of nkAsgn:             ckAsgn
  of nkRecCase:          ckRecCase
  of nkDistinctTy:       ckDistinctTy
  of nkCommentStmt:      ckCommentStmt
  else:                  ckUnknown

func pnodeToCanon*(n: PNode): CanonNode {.raises: [].} =
  ## Convert a single PNode into a CanonNode, mirroring toCanon(NimNode):
  ##   kind   = canonical enum via the parallel table above,
  ##   name   = identifier/symbol text (nkIdent uses ident.s, nkSym sym.name.s),
  ##   strVal = string-literal payload (plus ident text, mirroring toCanon),
  ##   intVal = integer/char literal payloads, floatVal = float families,
  ##   children = recursive conversion in source order.
  ## sourceSpanRef stays empty on this path; it is provenance-only by contract
  ## (docs/spec/canonical_ast_identity.md) and never part of identity.
  result.kind = toCanonKind(n.kind)
  case n.kind
  of nkIdent:
    result.name = n.ident.s
    result.strVal = n.ident.s
  of nkSym:
    result.name = n.sym.name.s
    result.strVal = n.sym.name.s
  of nkStrLit, nkRStrLit, nkTripleStrLit:
    result.strVal = n.strVal
  of nkCharLit:
    result.intVal = n.intVal
  of nkIntLit..nkInt64Lit, nkUIntLit..nkUInt64Lit:
    result.intVal = n.intVal
  of nkFloatLit..nkFloat128Lit:
    result.floatVal = n.floatVal
  else:
    discard
  var kids: seq[CanonNode] = @[]
  # Atom kinds (ident/sym/literals) have no `sons` — accessing n.len raises
  # FieldDefect on them (compiler/ast.nim len() contract). Guard by kind.
  if n.kind notin {nkEmpty, nkIdent, nkSym, nkCharLit,
                   nkIntLit..nkInt64Lit, nkUIntLit..nkUInt64Lit,
                   nkFloatLit..nkFloat128Lit,
                   nkStrLit, nkRStrLit, nkTripleStrLit, nkNilLit}:
    for i in 0 ..< n.len:
      if not n[i].isNil:
        kids.add(pnodeToCanon(n[i]))
  result.children = kids

func findFuncDefP*(root: PNode; procName, paramTypeHint: string): PNode =
  ## Locate a func/proc definition by name and an optional param-type substring
  ## in its formal params. Explicit-stack traversal (no nested proc), so the
  ## whole helper counts as ONE func against the src/core proc budget.
  ## Overload disambiguation is textual and deterministic (first match wins).
  var stack: seq[PNode] = @[root]
  while stack.len > 0:
    let n = stack.pop()
    if n.isNil: continue
    # Atom kinds have no `sons`; touching n.len/n[i] raises FieldDefect.
    if n.kind in {nkEmpty, nkIdent, nkSym, nkCharLit,
                  nkIntLit..nkInt64Lit, nkUIntLit..nkUInt64Lit,
                  nkFloatLit..nkFloat128Lit, nkStrLit, nkRStrLit,
                  nkTripleStrLit, nkNilLit}:
      continue
    if n.kind in {nkFuncDef, nkProcDef} and n.len > 0:
      var nameText = ""
      let head = n[0]
      if not head.isNil:
        case head.kind
        of nkIdent: nameText = head.ident.s
        of nkSym: nameText = head.sym.name.s
        of nkPostfix:
          if head.len > 1 and not head[1].isNil and head[1].kind == nkIdent:
            nameText = head[1].ident.s
        else: discard
      if nameText == procName:
        if paramTypeHint.len == 0:
          return n
        if n.len > 3 and not n[3].isNil:
          var hintHit = false
          for i in 1 ..< n[3].len:
            let idn = n[3][i]
            if not idn.isNil and idn.kind == nkIdentDefs and idn.len >= 3:
              let tyNode = idn[idn.len - 2]
              if not tyNode.isNil:
                var tyText = ""
                if tyNode.kind == nkIdent and tyNode.ident != nil:
                  tyText = tyNode.ident.s
                elif tyNode.kind == nkSym and tyNode.sym != nil:
                  tyText = tyNode.sym.name.s
                if tyText.contains(paramTypeHint):
                  hintHit = true
          if hintHit:
            return n
    for i in 0 ..< n.len:
      # Atom kinds have no `sons` — n.len raises FieldDefect on them
      # (compiler/ast.nim len() contract). Guard pushes like pnodeToCanon does.
      if not n[i].isNil and n.kind notin {nkEmpty, nkIdent, nkSym, nkCharLit,
          nkIntLit..nkInt64Lit, nkUIntLit..nkUInt64Lit,
          nkFloatLit..nkFloat128Lit, nkStrLit, nkRStrLit, nkTripleStrLit, nkNilLit}:
        stack.add(n[i])
  nil

{.pop.}
