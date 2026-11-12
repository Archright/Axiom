import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import ../../core/trusted/axiom_pragmas
import std/macros
import std/strutils
type
  FfiParamInfo* = tuple[name: string; nimType: string; cType: string]
  FfiExtractionResult* = object
    params*: seq[FfiParamInfo]
    returnType*: string  ## Nim return type string
    importcName*: string ## C symbol name from {.importc.} pragma
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
func extractFfiParamsFromAst(stmt: NimNode): FfiExtractionResult {.axiomTryImpl.} =
  ## Walks a Nim procedure AST node (from macros) and extracts
  ## parameter names, Nim types, and C type pragma info.
  result = FfiExtractionResult()
  if stmt.kind != nnkProcDef and stmt.kind != nnkFuncDef:
    return
  # Extract params from FormalParams
  let paramsNode = stmt[3]
  for i in 1 ..< paramsNode.len:
    let paramGroup = paramsNode[i]
    var names: seq[string] = @[]
    var nimType = ""
    for j in 0 ..< paramGroup.len - 1:
      names.add(paramGroup[j].strVal)
    let typeNode = paramGroup[paramGroup.len - 1]
    nimType = typeNode.repr.strip()
    var cType = nimType  # fallback
    # Check for {.importc.} pragma on the proc
    if stmt.len > 4:
      let pragmaNode = stmt[4]
      if pragmaNode.kind == nnkPragma:
        for p in pragmaNode:
          if p.kind == nnkExprColonExpr and p[0].strVal == "importc":
            if p[1].kind == nnkStrLit:
              result.importcName = p[1].strVal
    for name in names:
      result.params.add((name: name, nimType: nimType, cType: cType))
  # Return type
  if paramsNode[0].kind != nnkEmpty:
    result.returnType = paramsNode[0].repr.strip()

  ## axiom-smt: (assert ast_parse_failed_isolated)
  ## axiom-lean: ast_parse_failed_isolated
macro extractFfiBoundaries*(fnDef: untyped): untyped {.axiom.} =
  ## Compile-time macro: extracts C FFI parameter info from a proc declaration.
  ## Usage: const ffiInfo = extractFfiBoundaries: proc foo(x: int) {.importc.}
  result = newLit(extractFfiParamsFromAst(fnDef))
func detectFfiInSource*(sourceText: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len sourceText) 0)))", "sourceText.length ≥ 0"].} =
  ## Lightweight import-pragma detector: detects {.importc.} or {.cdecl.} or {.stdcall.}
  ## in source text without requiring a full compile.
  ".importc." in sourceText or
  ".cdecl." in sourceText or
  ".stdcall." in sourceText or
  ".exportc." in sourceText

{.pop.}
