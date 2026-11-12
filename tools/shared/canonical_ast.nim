## tools/shared/canonical_ast.nim
## Version-independent AST adapter — wraps std/macros.NimNode behind a stable
## canonical model so that downstream tools never depend on Nim-version-specific
## literals (nnkIdent, nnkProcDef…), index-based child access, or magic procs
## (strVal, intVal).  All conversions happen at this single boundary.
##
## SSOT for AST shape in tools/discover_test_debt.nim and future consumers.
##
## Quirk reference: docs/spec/pnode_nimnode_type_separation_quirk.md
## Nim 2.2.10 API verified via core/macros.nim inspection (proc len, kind, strVal,
## intVal, floatVal, repr; no safeLen; no parseFile — use readFile+parseStmt).

import std/strutils
import std/macros

# ---------------------------------------------------------------------------
## §1. Canonical node-kind enum (version-independent surface)
# ---------------------------------------------------------------------------

type
  CanonKind* = enum
    ckNone, ckEmpty, ckIdent, ckSym,
    ckCharLit, ckIntLit, ckInt8Lit, ckInt16Lit, ckInt32Lit, ckInt64Lit,
    ckUIntLit, ckUInt8Lit, ckUInt16Lit, ckUInt32Lit, ckUInt64Lit,
    ckFloatLit, ckFloat32Lit, ckFloat64Lit, ckFloat128Lit,
    ckStrLit, ckRStrLit, ckTripleStrLit, ckNilLit,
    ckCommand, ckCall, ckInfix, ckPrefix, ckPostfix,
    ckExprEqExpr, ckExprColonExpr, ckIdentDefs, ckVarTuple,
    ckPar, ckObjConstr, ckCurly, ckCurlyExpr,
    ckBracket, ckBracketExpr, ckPragmaExpr, ckRange,
    ckDotExpr, ckIfExpr, ckElifExpr, ckElseExpr, ckLambda, ckDo,
    ckTableConstr, ckBind,
    ckClosedSymChoice, ckOpenSymChoice,
    ckHiddenStdConv, ckHiddenSubConv, ckConv, ckCast, ckStaticExpr,
    ckAddr, ckProcDef, ckFuncDef, ckMethodDef, ckConverterDef,
    ckMacroDef, ckTemplateDef, ckIteratorDef, ckOfBranch,
    ckElifBranch, ckExceptBranch, ckElse,
    ckAsmStmt, ckPragma, ckPragmaBlock,
    ckIfStmt, ckWhenStmt, ckForStmt, ckParForStmt, ckWhileStmt,
    ckCaseStmt,
    ckTypeSection, ckVarSection, ckLetSection, ckConstSection,
    ckConstDef, ckTypeDef,
    ckYieldStmt, ckDefer, ckTryStmt, ckFinally, ckRaiseStmt,
    ckReturnStmt, ckBreakStmt, ckContinueStmt, ckBlockStmt,
    ckStaticStmt, ckDiscardStmt, ckStmtList,
    ckImportStmt, ckImportExceptStmt,
    ckExportStmt, ckExportExceptStmt,
    ckFromStmt, ckIncludeStmt,
    ckBindStmt, ckMixinStmt, ckUsingStmt,
    ckCommentStmt, ckStmtListExpr, ckBlockExpr,
    ckStmtListType, ckBlockType,
    ckObjectTy, ckTupleTy, ckRefTy, ckPtrTy, ckVarTy,
    ckEnumTy, ckEnumFieldDef,
    ckArgList, ckPattern,
    ckTupleConstr, ckError,
    ckRecCase, ckDistinctTy,
    ckAsgn, ckFormalParams, ckGenericParams,
    ckUnknown ## sentinel for unmapped / future kinds

# ---------------------------------------------------------------------------
## §2. Canonical node type
# ---------------------------------------------------------------------------

type
  CanonNode* = object
    kind*:   CanonKind
    name*:   string      ## identifier / symbol name (for ckIdent, ckSym, ckProcDef…)
    strVal*: string      ## string literal value (for ckStrLit, ckIdent.strVal…)
    intVal*: BiggestInt   ## integer literal value (for ckIntLit, ckCharLit…)
    floatVal*: BiggestFloat ## floating-point literal value
    sourceSpanRef*: string ## derived provenance: "file:line:col:kind" (empty when no location info).
                           ## Semantic comparison MUST NOT read this field — it is provenance only,
                           ## never part of identity (see docs/spec/canonical_ast_identity.md).
    children*: seq[CanonNode]

# ---------------------------------------------------------------------------
## §3. Raw-NimNode → CanonNode converter
# ---------------------------------------------------------------------------

func nimKindToCanon*(nk: NimNodeKind): CanonKind {.noSideEffect.} =
  ## Map a raw NimNodeKind to the canonical enum.
  case nk
  of nnkNone:          ckNone
  of nnkEmpty:         ckEmpty
  of nnkIdent:         ckIdent
  of nnkSym:           ckSym
  of nnkType:          ckUnknown
  of nnkCharLit:       ckCharLit
  of nnkIntLit:        ckIntLit
  of nnkInt8Lit:       ckInt8Lit
  of nnkInt16Lit:      ckInt16Lit
  of nnkInt32Lit:      ckInt32Lit
  of nnkInt64Lit:      ckInt64Lit
  of nnkUIntLit:       ckUIntLit
  of nnkUInt8Lit:      ckUInt8Lit
  of nnkUInt16Lit:     ckUInt16Lit
  of nnkUInt32Lit:     ckUInt32Lit
  of nnkUInt64Lit:     ckUInt64Lit
  of nnkFloatLit:      ckFloatLit
  of nnkFloat32Lit:    ckFloat32Lit
  of nnkFloat64Lit:    ckFloat64Lit
  of nnkFloat128Lit:   ckFloat128Lit
  of nnkStrLit:        ckStrLit
  of nnkRStrLit:       ckRStrLit
  of nnkTripleStrLit:  ckTripleStrLit
  of nnkNilLit:        ckNilLit
  of nnkComesFrom:     ckUnknown
  of nnkDotCall:       ckUnknown
  of nnkCommand:       ckCommand
  of nnkCall:          ckCall
  of nnkCallStrLit:    ckUnknown
  of nnkInfix:         ckInfix
  of nnkPrefix:        ckPrefix
  of nnkPostfix:       ckPostfix
  of nnkHiddenCallConv:ckUnknown
  of nnkExprEqExpr:    ckExprEqExpr
  of nnkExprColonExpr: ckExprColonExpr
  of nnkIdentDefs:     ckIdentDefs
  of nnkVarTuple:      ckVarTuple
  of nnkPar:           ckPar
  of nnkObjConstr:     ckObjConstr
  of nnkCurly:         ckCurly
  of nnkCurlyExpr:     ckCurlyExpr
  of nnkBracket:       ckBracket
  of nnkBracketExpr:   ckBracketExpr
  of nnkPragmaExpr:    ckPragmaExpr
  of nnkRange:         ckRange
  of nnkDotExpr:       ckDotExpr
  of nnkCheckedFieldExpr: ckUnknown
  of nnkDerefExpr:     ckUnknown
  of nnkIfExpr:        ckIfExpr
  of nnkElifExpr:      ckElifExpr
  of nnkElseExpr:      ckElseExpr
  of nnkLambda:        ckLambda
  of nnkDo:            ckDo
  of nnkTableConstr:   ckTableConstr
  of nnkBind:          ckBind
  of nnkClosedSymChoice: ckClosedSymChoice
  of nnkOpenSymChoice: ckOpenSymChoice
  of nnkHiddenStdConv: ckHiddenStdConv
  of nnkHiddenSubConv: ckHiddenSubConv
  of nnkConv:          ckConv
  of nnkCast:          ckCast
  of nnkStaticExpr:    ckStaticExpr
  of nnkAddr:          ckAddr
  of nnkHiddenAddr:    ckUnknown
  of nnkHiddenDeref:   ckUnknown
  of nnkObjDownConv:   ckUnknown
  of nnkObjUpConv:     ckUnknown
  of nnkChckRangeF:    ckUnknown
  of nnkChckRange64:   ckUnknown
  of nnkChckRange:     ckUnknown
  of nnkStringToCString: ckUnknown
  of nnkCStringToString: ckUnknown
  of nnkAsgn:          ckAsgn
  of nnkFastAsgn:      ckUnknown
  of nnkGenericParams: ckGenericParams
  of nnkFormalParams:  ckFormalParams
  of nnkOfInherit:     ckUnknown
  of nnkImportAs:      ckUnknown
  of nnkProcDef:       ckProcDef
  of nnkMethodDef:     ckMethodDef
  of nnkConverterDef:  ckConverterDef
  of nnkMacroDef:      ckMacroDef
  of nnkTemplateDef:   ckTemplateDef
  of nnkIteratorDef:   ckIteratorDef
  of nnkOfBranch:      ckOfBranch
  of nnkElifBranch:    ckElifBranch
  of nnkExceptBranch:  ckExceptBranch
  of nnkElse:          ckElse
  of nnkEnumTy:        ckEnumTy
  of nnkDistinctTy:    ckDistinctTy
  of nnkAsmStmt:       ckAsmStmt
  of nnkPragma:        ckPragma
  of nnkPragmaBlock:   ckPragmaBlock
  of nnkIfStmt:        ckIfStmt
  of nnkWhenStmt:      ckWhenStmt
  of nnkForStmt:       ckForStmt
  of nnkParForStmt:    ckParForStmt
  of nnkWhileStmt:     ckWhileStmt
  of nnkCaseStmt:      ckCaseStmt
  of nnkTypeSection:   ckTypeSection
  of nnkVarSection:    ckVarSection
  of nnkLetSection:    ckLetSection
  of nnkConstSection:  ckConstSection
  of nnkConstDef:      ckConstDef
  of nnkTypeDef:       ckTypeDef
  of nnkYieldStmt:     ckYieldStmt
  of nnkDefer:         ckDefer
  of nnkTryStmt:       ckTryStmt
  of nnkFinally:       ckFinally
  of nnkRaiseStmt:     ckRaiseStmt
  of nnkReturnStmt:    ckReturnStmt
  of nnkBreakStmt:     ckBreakStmt
  of nnkContinueStmt:  ckContinueStmt
  of nnkBlockStmt:     ckBlockStmt
  of nnkStaticStmt:    ckStaticStmt
  of nnkDiscardStmt:   ckDiscardStmt
  of nnkStmtList:      ckStmtList
  of nnkImportStmt:    ckImportStmt
  of nnkImportExceptStmt: ckImportExceptStmt
  of nnkExportStmt:    ckExportStmt
  of nnkExportExceptStmt: ckExportExceptStmt
  of nnkFromStmt:      ckFromStmt
  of nnkIncludeStmt:   ckIncludeStmt
  of nnkBindStmt:      ckBindStmt
  of nnkMixinStmt:     ckMixinStmt
  of nnkUsingStmt:     ckUsingStmt
  of nnkCommentStmt:   ckCommentStmt
  of nnkStmtListExpr:  ckStmtListExpr
  of nnkBlockExpr:     ckBlockExpr
  of nnkStmtListType:  ckStmtListType
  of nnkBlockType:     ckBlockType
  of nnkWith:          ckUnknown
  of nnkWithout:       ckUnknown
  of nnkTypeOfExpr:    ckUnknown
  of nnkObjectTy:      ckObjectTy
  of nnkTupleTy:       ckTupleTy
  of nnkTupleClassTy:  ckUnknown
  of nnkTypeClassTy:   ckUnknown
  of nnkStaticTy:      ckUnknown
  of nnkRecList:       ckUnknown
  of nnkRecCase:       ckRecCase
  of nnkRecWhen:       ckUnknown
  of nnkSinkAsgn:      ckUnknown
  of nnkArgList:       ckArgList
  of nnkPattern:       ckPattern
  of nnkHiddenTryStmt: ckUnknown
  of nnkClosure:       ckUnknown
  of nnkGotoState:     ckUnknown
  of nnkState:         ckUnknown
  of nnkBreakState:    ckUnknown
  of nnkFuncDef:       ckFuncDef
  of nnkTupleConstr:   ckTupleConstr
  of nnkError:         ckError
  else:                ckUnknown

func formatSourceSpan*(n: NimNode): string {.noSideEffect.} =
  ## Derive a stable provenance string "file:line:col:kind".
  ## Empty string when no location info is available (synthetic nodes).
  ## Nim 2.2.10 quirk: newNimNode() in the VM assigns creation-site line info,
  ## so "no location" is detected via zero line OR empty filename, not via
  ## constructor identity.  (parseStmt("") yields filename=='' — synthetic.)
  let li = n.lineInfoObj
  if li.line == 0 or li.filename.len == 0: return ""
  li.filename & ":" & $li.line & ":" & $li.column & ":" & $n.kind

func toCanon*(n: NimNode): CanonNode {.noSideEffect.} =
  ## Convert a single NimNode into a canonical tree node.
  result.kind   = nimKindToCanon(n.kind)
  result.name   = if n.kind in {nnkIdent, nnkSym}: n.strVal else: ""
  result.strVal = if n.kind in {nnkStrLit, nnkRStrLit, nnkTripleStrLit}: n.strVal
                  elif n.kind == nnkIdent: n.strVal
                  else: ""
  result.intVal = if n.kind in {nnkIntLit..nnkUInt64Lit, nnkCharLit}: n.intVal
                  else: 0.BiggestInt
  result.floatVal = if n.kind in {nnkFloatLit..nnkFloat128Lit}: n.floatVal
                    else: cast[BiggestFloat](0)
  result.sourceSpanRef = formatSourceSpan(n)
  # Recursively convert children (len() is the standard accessor)
  var kids: seq[CanonNode] = @[]
  for i in 0 ..< n.len:
    kids.add(toCanon(n[i]))
  result.children = kids

# ---------------------------------------------------------------------------
## §4. Public adapter surface (~15 functions)
# ---------------------------------------------------------------------------

func getNodeKind*(n: CanonNode): CanonKind {.inline, noSideEffect.} = n.kind
func getNodeName*(n: CanonNode): string {.inline, noSideEffect.} = n.name
func getStringValue*(n: CanonNode): string {.inline, noSideEffect.} = n.strVal
func getIntValue*(n: CanonNode): BiggestInt {.inline, noSideEffect.} = n.intVal
func getFloatValue*(n: CanonNode): BiggestFloat {.inline, noSideEffect.} = n.floatVal

func getChildCount*(n: CanonNode): int {.inline, noSideEffect.} = n.children.len

func getChild*(n: CanonNode, idx: int): CanonNode =
  ## Safe indexed child access — returns ckUnknown sentinel on OOB.
  if idx < 0 or idx >= n.children.len: return CanonNode(kind: ckUnknown)
  n.children[idx]

func getChildren*(n: CanonNode): seq[CanonNode] {.inline, noSideEffect.} = n.children

func extractProcName*(n: CanonNode): string =
  ## Extract the procedure name from a proc/func definition node.
  if n.kind notin {ckProcDef, ckFuncDef}: return ""
  # First child of ProcDef is the ident/sym holding the name
  if n.children.len > 0: n.children[0].name else: ""

func extractParams*(n: CanonNode): seq[CanonNode] =
  ## Extract parameter list nodes from a proc/func definition.
  if n.kind notin {ckProcDef, ckFuncDef}: return @[]
  # Second child (index 1) is typically the formal params section
  if n.children.len > 1: n.children[1].children else: @[]

func extractBody*(n: CanonNode): CanonNode =
  ## Extract the body statement list from a proc/func definition.
  if n.kind notin {ckProcDef, ckFuncDef}: return CanonNode(kind: ckUnknown)
  # Body is usually the last significant child
  if n.children.len > 2: n.children[^1] else: CanonNode(kind: ckUnknown)

proc walkDescendants*(n: CanonNode, visit: proc (node: CanonNode): bool {.closure.}): bool =
  ## Depth-first walk; visit(node) returning false aborts traversal.
  if not visit(n): return false
  for child in n.children:
    if not walkDescendants(child, visit): return false
  true

func isOfType*(n: CanonNode, expected: set[CanonKind]): bool {.inline, noSideEffect.} =
  n.kind in expected

func isIdentOrSym*(n: CanonNode): bool {.inline, noSideEffect.} =
  n.kind in {ckIdent, ckSym}

func newNode*(kind: CanonKind): CanonNode =
  CanonNode(kind: kind, children: @[])

func newProc*(name: string): CanonNode =
  CanonNode(
    kind: ckProcDef,
    name: name,
    children: @[CanonNode(kind: ckIdent, name: name),
                CanonNode(kind: ckStmtList)]
  )

func extractCondition*(n: CanonNode): string =
  ## Convert an expression node to its source representation string.
  case n.kind
  of ckIdent, ckSym:
    n.name.strip()
  of ckIntLit, ckInt8Lit, ckInt16Lit, ckInt32Lit, ckInt64Lit,
     ckUIntLit, ckUInt8Lit, ckUInt16Lit, ckUInt32Lit, ckUInt64Lit:
    $n.intVal
  of ckFloatLit, ckFloat32Lit, ckFloat64Lit, ckFloat128Lit:
    $n.floatVal
  of ckStrLit, ckTripleStrLit, ckRStrLit:
    n.strVal
  of ckNilLit:
    "nil"
  else:
    ""

func getRepr*(n: CanonNode): string {.noSideEffect.} =
  ## Return a string representation of the canonical node, approximating
  ## the original NimNode.repr behavior for diagnostic purposes.
  case n.kind
  of ckIdent, ckSym:
    n.name
  of ckStrLit, ckRStrLit, ckTripleStrLit:
    "\"" & n.strVal & "\""
  of ckIntLit, ckInt8Lit, ckInt16Lit, ckInt32Lit, ckInt64Lit,
     ckUIntLit, ckUInt8Lit, ckUInt16Lit, ckUInt32Lit, ckUInt64Lit:
    $n.intVal
  of ckFloatLit, ckFloat32Lit, ckFloat64Lit, ckFloat128Lit:
    $n.floatVal
  of ckCharLit:
    $n.intVal
  of ckNilLit:
    "nil"
  of ckProcDef, ckFuncDef, ckMethodDef, ckConverterDef,
     ckMacroDef, ckTemplateDef, ckIteratorDef:
    "proc " & n.name & "(...)"
  of ckIfStmt, ckIfExpr:
    "if ..."
  of ckCaseStmt:
    "case ..."
  of ckWhenStmt:
    "when ..."
  else:
    ""

# ---------------------------------------------------------------------------
## §5. NOTE: Runtime file-level parsing is NOT supported
# ---------------------------------------------------------------------------
## std/macros.parseStmt is {.compileTime.} in Nim 2.2.10 — it cannot be called
## at runtime in a compiled binary.  Therefore parseSourceFile is intentionally
## omitted from this module.  Tools that need runtime AST-free analysis should
## use text-based scanning (see tools/discover_test_debt.nim extractIfBranches).
## The canonical model (CanonNode + CanonKind) remains useful for compile-time
## macro contexts where NimNode IS available.
