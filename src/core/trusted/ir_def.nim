import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Axiom IR Definition Macro — compile-time bridge between Nim IR and Lean 4 inductives.
##
## Provides a single `defineIR` macro that parses an IR definition body,
## generates Nim type definitions (enums + variant objects), and writes
## a corresponding Lean 4 file with inductive types.
##
## Standalone procs (`generateLeanEnum`, `generateLeanInductive`, `generateLeanFile`)
## are also available for manual use outside the macro.

import std/macros
import std/strutils
import std/os
import core/axiom_pragmas
import core/parsers/safe_parsers
import core/types/results

# ---------------------------------------------------------------------------
# Lean type mapping
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func nodeToTypeText*(n: NimNode): string =
  ## Render a type AST node back to its source text, e.g.
  ## `BracketExpr(Ident "array", IntLit 16, Ident "byte")` → "array[16, byte]".
  case n.kind
  of nnkBracketExpr:
    result = nodeToTypeText(n[0]) & "["
    for i in 1 ..< n.len:
      if i > 1: result.add(", ")
      result.add(nodeToTypeText(n[i]))
    result.add("]")
  of nnkIdent, nnkSym:
    result = n.strVal
  of nnkIntLit, nnkInt8Lit, nnkInt16Lit, nnkInt32Lit, nnkInt64Lit:
    result = $n.intVal
  of nnkUIntLit, nnkUInt8Lit, nnkUInt16Lit, nnkUInt32Lit, nnkUInt64Lit:
    result = $n.intVal
  of nnkFloatLit, nnkFloat32Lit, nnkFloat64Lit:
    result = $n.floatVal
  of nnkDotExpr:
    result = nodeToTypeText(n[0]) & "." & nodeToTypeText(n[1])
  of nnkTupleTy, nnkPar, nnkTupleConstr:
    var parts: seq[string] = @[]
    for child in n:
      parts.add(nodeToTypeText(child))
    result = "(" & parts.join(", ") & ")"
  else:
    result = n.repr.strip()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func typeTextToNode*(t: string): NimNode =
  ## Convert a type text (e.g. "array[16, byte]") back to a Nim type AST node.
  ## Plain identifiers use `ident`; bracket expressions are rebuilt structurally
  ## so that `array[N, T]` fields compile in packed objects.
  let openIdx = t.find("[")
  if openIdx > 0 and t.endsWith("]"):
    let base = t[0 ..< openIdx].strip()
    let inner = t[openIdx + 1 .. ^2]
    var args = newTree(nnkBracketExpr)
    args.add(ident(base))
    for part in inner.split(","):
      let p = part.strip()
      if p.len > 0 and p[0] in {'0' .. '9'}:
        let parsed = safeParseInt(p)
        if parsed.isOk:
          args.add(newIntLitNode(parsed.get))
        else:
          args.add(ident(p))
      else:
        args.add(typeTextToNode(p))
    return args
  result = ident(t.strip())

func nimToLeanType*(nimType: string): string =
  ## Map Nim primitive types to their Lean 4 equivalents.
  ## Recursive/custom types pass through unchanged.
  ## `array[N, T]` → `Array (Fin N) T` (Lean 4 fixed-size array).
  let arrayIdx = nimType.find("array[")
  if arrayIdx >= 0:
    let rest = nimType[arrayIdx + "array[".len .. ^1]
    let commaIdx = rest.find(",")
    if commaIdx >= 0:
      let n = rest[0 ..< commaIdx].strip()
      let elem = rest[commaIdx + 1 .. ^1].strip().strip(chars = {']', ';', '}'})
      # Lean 4 fixed-size array: `Fin N → T` (function type). Note: `Array α n`
      # is not valid Lean; `Array` in Lean 4 has no length parameter.
      return "Fin " & n & " → " & nimToLeanType(elem)
  case nimType
  of "int64", "int": "Int"
  of "float64", "float": "Float"
  of "string": "String"
  of "bool": "Bool"
  of "uint32": "UInt32"
  of "int32": "Int32"
  of "uint64": "UInt64"
  of "byte": "UInt8"
  else: nimType

# ---------------------------------------------------------------------------
# Lean code generation
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func sanitizeLeanName(name: string): string =
  ## Lean constructors must start with lowercase. Append `_` to reserved words.
  let reserved = ["where", "match", "case", "fun", "do", "let", "if", "then", "else"]
  result = name
  if result.len > 0 and result[0].isUpperAscii:
    result = result.toLowerAscii()
  if result in reserved:
    result = result & "_"

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func generateLeanEnum*(name: string, variants: seq[string]): string =
  ## Generate a Lean 4 `inductive` from enum variants.
  ## Output: `inductive Name where | v1 | v2 ... deriving ...`
  result = "inductive " & name & " where\n"
  for i, v in variants:
    result.add("  | " & sanitizeLeanName(v))
    if i < variants.len - 1:
      result.add("\n")
  result.add("\n  deriving BEq, Repr, Inhabited\n")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func generateLeanInductive*(name: string, fields: seq[(string, string)]): string =
  ## Generate a Lean 4 `inductive` with constructors.
  ## fields: seq of (ctorName, fieldTypeDescription).
  result = "inductive " & name & " where\n"
  for i, (ctor, ftype) in fields:
    let leanCtor = sanitizeLeanName(ctor)
    if ftype.len > 0:
      result.add("  | " & leanCtor & " (" & ftype & ") : " & name & "\n")
    else:
      result.add("  | " & leanCtor & " : " & name & "\n")
  result.add("  deriving BEq, Repr, Inhabited\n")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func generateLeanStruct*(name: string, fields: seq[(string, string)]): string =
  ## Generate a Lean 4 `structure Name where ... deriving Repr, BEq`.
  ## Used for packed structs that share a binary layout between Nim and C.
  ## Structs with `Fin N → T` array fields skip `deriving Repr, BEq` because
  ## function types lack those instances in Lean 4.
  result = "structure " & name & " where\n"
  var hasArrayField = false
  for (fname, ftype) in fields:
    result.add("  " & fname & " : " & nimToLeanType(ftype) & "\n")
    if ftype.startsWith("array["):
      hasArrayField = true
  if not hasArrayField:
    result.add("  deriving Repr, BEq\n")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc generateLeanFile*(outputPath: string,
                       enums: seq[(string, seq[string])],
                       inductives: seq[(string, seq[(string, string)])],
 structs: seq[(string, seq[(string, string)], bool)] = @[]): void {.raises: [IOError, OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Generate a complete Lean 4 file with namespace, enums, inductives, and structs.
  var content = "-- Auto-generated by ir_def.nim — DO NOT EDIT\n"
  content.add("namespace AxiomIR\n\n")

  for (name, variants) in enums:
    content.add(generateLeanEnum(name, variants))
    content.add("\n")

  for (name, fields) in inductives:
    content.add(generateLeanInductive(name, fields))
    content.add("\n")

  for (name, fields, _) in structs:
    content.add(generateLeanStruct(name, fields))
    content.add("\n")

  content.add("end AxiomIR\n")

  let dir = parentDir(outputPath)
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)
  writeFile(outputPath, content)

# ---------------------------------------------------------------------------
# Macro helpers — compile-time AST parsing
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func extractIdents(n: NimNode, acc: var seq[string]) =
  ## Recursively extract all identifier names from a node.
  case n.kind
  of nnkIdent:
    acc.add(n.strVal)
  of nnkCommand:
    extractIdents(n[0], acc)
    if n.len > 1: extractIdents(n[1], acc)
  of nnkStmtList:
    for child in n:
      extractIdents(child, acc)
  else: discard

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func extractFieldsFromCmd(node: NimNode): seq[(string, string)] =
  ## Extract (fieldName, fieldType) pairs from a nested command tree.
  ## Pattern: field1: type1, field2: type2 →
  ##   nnkCommand(field1, nnkCommand(type1, nnkCommand(field2, type2)))
  result = @[]
  var cur = node
  while cur.kind == nnkCommand:
    let name = cur[0].strVal
    let rest = cur[1]
    case rest.kind
    of nnkIdent:
      # Last field: name: type
      result.add((name, rest.strVal))
      break
    of nnkCommand:
      # More fields: name: type, ...
      let typ = rest[0].strVal
      result.add((name, typ))
      cur = rest[1]
    else:
      break

# ---------------------------------------------------------------------------
# Nim type generation
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildNimEnumDef(name: string, variants: seq[string]): NimNode =
  ## Build `type Name* = enum variant1, variant2, ...`
  let enumBody = nnkEnumTy.newTree(newEmptyNode())
  for v in variants:
    enumBody.add(nnkEnumFieldDef.newTree(ident(v), newEmptyNode()))
  result = nnkTypeDef.newTree(
    nnkPostfix.newTree(ident("*"), ident(name)),
    newEmptyNode(),
    enumBody
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildNimVariantDef(typeName: string, caseKindName: string,
                        branches: seq[(string, seq[(string, string)])]): NimNode =
  ## Build a ref object with case-of variant branches.
  let ofBranches = nnkRecCase.newTree(
    nnkIdentDefs.newTree(
      nnkPostfix.newTree(ident("kind"), ident("*")),
      ident(caseKindName),
      newEmptyNode()
    )
  )

  for (variantName, fields) in branches:
    var branch = nnkOfBranch.newTree(ident(variantName))
    for (fieldName, fieldType) in fields:
      branch.add(nnkIdentDefs.newTree(
        nnkPostfix.newTree(ident(fieldName), ident("*")),
        ident(fieldType),
        newEmptyNode()
      ))
    ofBranches.add(branch)

  let objBody = nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), ofBranches)
  result = nnkTypeDef.newTree(
    nnkPostfix.newTree(ident("*"), ident(typeName)),
    newEmptyNode(),
    nnkRefTy.newTree(objBody)
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildNimPackedObject*(typeName: string, fields: seq[(string, string)]): NimNode =
  ## Build `type Name {.packed, codegenDecl: "struct axiom_$# $# $#".} = object ...`
  ## Generates a packed object with explicit C struct naming for offsetof guards.
  ## AST shape (verified): TypeDef(PragmaExpr(Postfix name, Pragma), Empty, ObjectTy(Empty, Empty, RecList)).
  var recList = nnkRecList.newTree()
  for (fname, ftype) in fields:
    recList.add(nnkIdentDefs.newTree(
      nnkPostfix.newTree(ident("*"), ident(fname)),
      typeTextToNode(ftype),
      newEmptyNode()
    ))

  let objBody = nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), recList)
  let pragma = nnkPragma.newTree(
    ident("packed"),
    newTree(nnkExprColonExpr,
      ident("codegenDecl"),
      newStrLitNode("struct axiom_$# $# $#")
    )
  )
  let nameWithPragma = newTree(nnkPragmaExpr,
    nnkPostfix.newTree(ident("*"), ident(typeName)),
    pragma
  )

  result = nnkTypeSection.newTree(
    nnkTypeDef.newTree(
      nameWithPragma,
      newEmptyNode(),
      objBody
    )
  )

# ---------------------------------------------------------------------------
# Main macro
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro defineIR*(name, body: untyped): untyped =
  ## Main macro — parses body to extract enum variants and inductive constructors.
  ## Generates Nim types and Lean 4 file. Returns the Nim type AST.
  ##
  ## DSL:
  ##   defineIR "AxiomIR":
  ##     enum BinOpKind:
  ##       boAdd, boSub, boMul
  ##     inductive IRExpr:
  ##       irLit: litVal: int64
  ##       irVar: varName: string, varType: IRType

  expectKind(body, nnkStmtList)

  var enums: seq[(string, seq[string])] = @[]
  var inductives: seq[(string, seq[(string, string)])] = @[]
  var structs: seq[(string, seq[(string, string)], bool)] = @[]
  var resultTypes = newStmtList()

  for stmt in body:
    if stmt.kind != nnkCommand: continue
    let keyword = stmt[0].strVal

    if keyword == "enum":
      # enum Name: variant1, variant2, ...
      expectKind(stmt[1], nnkIdent)
      let enumName = stmt[1].strVal
      expectKind(stmt[2], nnkStmtList)

      var variants: seq[string] = @[]
      extractIdents(stmt[2], variants)

      enums.add((enumName, variants))
      resultTypes.add(buildNimEnumDef(enumName, variants))

    elif keyword == "inductive":
      # inductive Name: ctor: field1: type1, field2: type2
      expectKind(stmt[1], nnkIdent)
      let typeName = stmt[1].strVal
      expectKind(stmt[2], nnkStmtList)

      var constructors: seq[(string, seq[(string, string)])] = @[]
      var leanFields: seq[(string, string)] = @[]
      var variantNames: seq[string] = @[]

      for ctorDef in stmt[2]:
        case ctorDef.kind
        of nnkCommand:
          let ctorName = ctorDef[0].strVal
          var fields: seq[(string, string)] = @[]
          var leanParts: seq[string] = @[]

          if ctorDef.len > 1 and ctorDef[1].kind == nnkCommand:
            fields = extractFieldsFromCmd(ctorDef[1])
            for (fname, ftype) in fields:
              leanParts.add("(" & fname & " : " & nimToLeanType(ftype) & ")")

          constructors.add((ctorName, fields))
          leanFields.add((ctorName, leanParts.join(" ")))
          variantNames.add(ctorName)

        of nnkIdent:
          # Constructor without fields
          let ctorName = ctorDef.strVal
          constructors.add((ctorName, @[]))
          leanFields.add((ctorName, ""))
          variantNames.add(ctorName)

        else: discard

      # Generate Nim enum for the case-kind discriminator
      resultTypes.add(buildNimEnumDef(typeName & "Kind", variantNames))
      # Generate Nim variant object
      resultTypes.add(buildNimVariantDef(typeName, typeName & "Kind", constructors))
      # Store for Lean generation
      inductives.add((typeName, leanFields))

    elif keyword == "struct":
      # struct Name {.packed.}: field1: type1, field2: type2
      var structName: string
      var isPacked = false

      if stmt[1].kind == nnkPragmaExpr:
        # struct Name {.packed.}: ...
        structName = stmt[1][0].strVal
        for pragma in stmt[1][1]:
          if pragma.kind == nnkIdent and pragma.strVal == "packed":
            isPacked = true
      else:
        # struct Name: ...
        structName = stmt[1].strVal

      expectKind(stmt[2], nnkStmtList)

      var fields: seq[(string, string)] = @[]
      for fieldDef in stmt[2]:
        # Nim parses `name: type` inside a macro body as nnkCall whose second
        # child is an nnkStmtList containing the type expression (e.g.
        # `array[16, byte]` → BracketExpr). Handle both nnkCommand and nnkCall.
        if fieldDef.kind == nnkCommand and fieldDef.len >= 2:
          let fname = fieldDef[0].strVal
          let ftype = fieldDef[1].strVal
          fields.add((fname, ftype))
        elif fieldDef.kind == nnkCall and fieldDef.len >= 2:
          let fname = fieldDef[0].strVal
          var ftype = ""
          if fieldDef[1].kind == nnkStmtList and fieldDef[1].len > 0:
            ftype = nodeToTypeText(fieldDef[1][0])
          if ftype.len == 0:
            ftype = fieldDef[1].repr.strip()
          fields.add((fname, ftype))

      # Generate Nim packed object with codegenDecl
      resultTypes.add(buildNimPackedObject(structName, fields))
      # Store for Lean generation
      structs.add((structName, fields, isPacked))

    else: discard

  # Generate Lean file — output to proofs/Generated/ so Lean imports
  # (e.g. ShmFFI.lean → import Generated.SharedIRHeader) resolve correctly.
  let outputPath = "proofs/Generated/" & name.strVal & ".lean"
  generateLeanFile(outputPath, enums, inductives, structs)

  result = resultTypes
  when defined(axiomDebug):
    echo "ir_def: Lean file → ", outputPath
    echo "ir_def: generated ", $enums.len, " enums, ", $inductives.len, " inductives, ", $structs.len, " structs"

{.pop.}
