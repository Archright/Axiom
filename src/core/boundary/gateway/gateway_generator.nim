import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Gateway Generator — Pure AST interpreter macro.
## Receives static GatewayEndpoint / GatewayEnumSpec values and emits
## distinct string types with validation constructors.
##
## Dependency boundary: imports only gateway_spec, std/macros, std/strutils.
## All generated code references (Result, AxiomError, err/ok) are injected
## via fully-qualified identifiers to avoid coupling to core/types/domain_types
## at the macro-definition layer.

import std/macros
import std/strutils
import gateway_spec

func lowerFirstAscii*(s: string): string {.raises: [].} =
  if s.len == 0:
    return s
  result = s
  result[0] = result[0].toLowerAscii

macro generateGateway*(spec: static GatewayEndpoint): untyped =
  ## Generate distinct type + validation constructor from a static spec.
  ## The spec fields are primitive strings so newLit never fails.
  let typeName = ident(spec.typeName)
  let stringProcName = ident(lowerFirstAscii(spec.typeName) & "String")
  let toProcName = ident("to" & spec.typeName)
  let rawIdent = ident("raw")
  let predicate = ident(spec.predicate)
  let errValue = ident(spec.errValue)
  let extraReqNode =
    if spec.requires.len == 0:
      newLit(true)
    else:
      parseExpr(spec.requires)
  let reqNode = quote do:
    (`rawIdent`.len > 0) and `extraReqNode`

  result = quote do:
    type `typeName`* = distinct string

    func `stringProcName`*(id: `typeName`): string {.inline, raises: [].} =
      string(id)

    func `toProcName`*(`rawIdent`: string): Result[`typeName`, AxiomError] {.
      raises: [],
      requires: `reqNode`,
      ensures:
        (not result.isOk()) or
        (`extraReqNode` and `predicate`(`rawIdent`) and (`stringProcName`(result.get()) == `rawIdent`))
    .} =
      if `rawIdent`.len == 0:
        return err(axiomErrEmptyString)
      if not `extraReqNode`:
        return err(`errValue`)
      if not `predicate`(`rawIdent`):
        return err(`errValue`)
      ok(`typeName`(`rawIdent`))

proc genEnumIsValidBody(pairs: seq[EnumMapping]): NimNode =
  result = newStmtList()
  var c = newTree(nnkCaseStmt, ident("raw"))
  for p in pairs:
    c.add newTree(nnkOfBranch, newLit(p.raw), newStmtList(newLit(true)))
  c.add newTree(nnkElse, newStmtList(newLit(false)))
  result.add c

proc genEnumStringBody(pairs: seq[EnumMapping]): NimNode =
  result = newStmtList()
  var c = newTree(nnkCaseStmt, ident("v"))
  for p in pairs:
    c.add newTree(nnkOfBranch, ident(p.enumVal), newStmtList(newLit(p.raw)))
  result.add c

proc genEnumToBody(pairs: seq[EnumMapping]): NimNode =
  result = newStmtList()
  var c = newTree(nnkCaseStmt, ident("raw"))
  for p in pairs:
    c.add newTree(nnkOfBranch, newLit(p.raw),
      newStmtList(newCall("ok", ident(p.enumVal))))
  c.add newTree(nnkElse,
    newStmtList(newCall("err", ident("axiomErrEnumValueUnknown"))))
  result.add c

macro generateEnumGateway*(spec: static GatewayEnumSpec): untyped =
  ## Generate enum validation + string mapping from a static spec.
  ## AST-based via genAst — no string parsing.
  let typeStr = spec.typeName
  let stringProcName = lowerFirstAscii(typeStr) & "String"
  let isValidProcName = "isValid" & typeStr
  let toProcName = "to" & typeStr
  let pairs = spec.mappings

  if pairs.len == 0:
    error("At least one mapping pair is required")

  let isValidBody = genEnumIsValidBody(pairs)
  let stringBody = genEnumStringBody(pairs)
  let toBody = genEnumToBody(pairs)

  let typeNameIdent = ident(typeStr)
  let isValidIdent = ident(isValidProcName)
  let stringProcIdent = ident(stringProcName)
  let toProcIdent = ident(toProcName)
  let rawIdent = ident("raw")
  let vIdent = ident("v")

  # Use quote do with explicit bind of `result` to avoid macro-scope capture
  result = quote do:
    bind result
    proc `isValidIdent`*(`rawIdent`: string): bool {.inline, raises: [].} =
      `isValidBody`

    proc `stringProcIdent`*(`vIdent`: `typeNameIdent`): string {.inline, raises: [].} =
      `stringBody`

    proc `toProcIdent`*(`rawIdent`: string): Result[`typeNameIdent`, AxiomError] {.
      raises: [],
      ensures: (not result.isOk()) or (`stringProcIdent`(result.get()) == `rawIdent`)
    .} =
      `toBody`

{.pop.}
