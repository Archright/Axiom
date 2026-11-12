## Feature Spec definitions for BDD feature generation.
## Defines the types and descriptions for auto-generated BDD feature files.
## No disk I/O — pure data definitions only.
##
## To add new features, append a FeatureSpec entry and add the type name
## to the collectFeatureSpecs macro call in feature_writer.nim.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/macros

type
  FeatureSpec* = object
    typeName*: string
    description*: string
    kind*: string  # "object" or "enum"

macro collectFeatureSpecs*(types: typed, descs: static seq[string]): seq[FeatureSpec] =
  ## Reads type definitions at compile time using getImpl.
  ## Pair each type with its description from the parallel `descs` sequence.
  ## The `typed` parameter ensures symbols are resolved before the macro runs.
  result = newNimNode(nnkPrefix)
  result.add(ident"@")
  let bracket = newNimNode(nnkBracket)
  let descList = descs
  for i in 0 ..< types.len:
    let typeSym = types[i]
    let impl = getImpl(typeSym)
    if impl.kind != nnkTypeDef:
      continue
    let nameNode = impl[0]
    # Strip export marker: nnkPostfix(*, Name) -> Name, nnkIdent(Name) -> Name
    let rawName = if nameNode.kind == nnkPragmaExpr: nameNode[0] else: nameNode
    let cleanName = if rawName.kind == nnkPostfix: $rawName[1] else: $rawName
    let bodyNode = impl[2]
    let typeKind = if bodyNode.kind == nnkObjectTy: "object" else: "enum"
    let desc = if i < descList.len: descList[i] else: cleanName & " type"
    let descLit = newStrLitNode(desc)
    let kindLit = newStrLitNode(typeKind)
    bracket.add quote do:
      FeatureSpec(typeName: `cleanName`, description: `descLit`, kind: `kindLit`)

  if bracket.len == 0:
    result = quote do: newSeq[FeatureSpec]()
  else:
    result.add(bracket)
