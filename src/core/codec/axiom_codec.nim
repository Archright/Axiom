import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Axiom Codec — Compile-Time Type-Driven JSON Codec Derivation
##
## Entry point macro: deriveJsonCodec(T)
##
## Generates:
##   func toJson*(x: T): JsonNode {.noSideEffect, raises: [].}
##   func fromJson*(node: JsonNode, _: typedesc[T]): Result[T, string]
##     {.noSideEffect, raises: [].}
##
## Supported types:
##   int, float, string, bool, enum, object, ref object, distinct,
##   seq[T], Option[T], Table[string, T], variant objects (case)
##
## Convention:
## - Generated code uses ONLY newJObject/newJString/newJInt/etc.
##   NEVER % or %*{} (avoids {.raises: [Exception].})
## - Uses noSideEffect cast for std/json mutation safety
##   [SEE: nim_effect_system_quirks.md]
## - Strict validation: hasKey + kind checks for required fields
## - Only Option[T] fields allow missing/JNull
##
## Usage:
##   from core/axiom_codec import deriveJsonCodec
##   type MyType = object
##     name*: string
##     count*: int
##   deriveJsonCodec(MyType)

import std/macros
import codec_typesense
import codec_codegen_funcs

macro deriveJsonCodec*(T: typedesc): untyped =
  ## Compile-time type-driven JSON codec derivation.
  ##
  ## Dispatches on the type's AST kind BEFORE calling getActualObjectImpl:
  ## - Enum (nnkEnumTy): direct enum path, bypass object unwrapping
  ## - Object/Ref/Variant: unwrap via getActualObjectImpl, then classify
  ##
  ## Concern #1 fix: rawImpl.kind dispatch BEFORE getActualObjectImpl
  ## prevents nnkRecList traversal on enum types.

  var impl = T.getTypeImpl

  # Unwrap typedesc wrapper FIRST — nnkBracketExpr(typedesc, ConcreteType)
  # This must happen before any kind check, including enum
  if impl.kind == nnkBracketExpr and impl[0].eqIdent("typedesc"):
    impl = impl[1].getTypeImpl

  # Path 1: Enum — direct nnkEnumTy, no object unwrapping needed
  if impl.kind == nnkEnumTy:
    let enumVals = extractEnumValues(impl)
    result = newStmtList()
    result.add(emitEnumToJson(T, enumVals))
    result.add(emitEnumFromJson(T, enumVals))
    return

  # Path 2: Object/Ref/Variant — unwrap ref, then classify
  let normalized = unwrapRef(impl)
  var info = classifyFull(normalized, $T)

  # Resolve tkUnknown fields that are actually enums (getTypeImpl resolves nnkSym → nnkEnumTy)
  for field in info.memberFields.mitems:
    if field.typeKind == tkUnknown:
      let resolved = field.typeNode.getTypeImpl
      if resolved.kind == nnkEnumTy:
        field.typeKind = tkEnum
        # Keep field.typeNode as nnkSym — it's used in typedesc[T] which needs the symbol, not the full enum AST

  case info.kind
  of tkObject, tkVariantObject:
    result = newStmtList()
    result.add(emitObjectToJson(T, info))
    result.add(emitObjectFromJson(T, info))
  of tkDistinct:
    # Distinct types: derive codec for the base type, then wrap
    # This generates toJson/fromJson that cast to/from the base
    let baseImpl = info.baseTypeNode
    let baseInfo = classifyFull(baseImpl, $T)
    result = newStmtList()
    if baseInfo.kind in {tkObject, tkVariantObject}:
      result.add(emitObjectToJson(T, baseInfo))
      result.add(emitObjectFromJson(T, baseInfo))
    else:
      error("deriveJsonCodec: unsupported distinct base type for '" &
          $T & "'. Use manual codec.", baseImpl)
  else:
    error("deriveJsonCodec: unsupported type kind for '" & $T &
        "'. Supported: enum, object, ref object, distinct.", impl)

{.pop.}
