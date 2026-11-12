import core/trusted/layer_declaration
axiomLayer "trusted.core.ir"

{.push raises: [].}
## Axiom Core IR — base type definitions (leaf module).
##
## Leaf module: defines `IRType` and its constructors only. It must not
## import `axiom_ir` (or anything that imports it) — this is what breaks
## the `axiom_ir` ↔ `symbol_table_types` import cycle (Nim forbids circular
## module dependencies). `axiom_ir` imports and re-exports this module, so
## downstream consumers of `axiom_ir` still see `IRType` unchanged.

import std/strutils

type
  IRTypeKind* = enum
    irtBitVec64    ## Machine integer (64-bit, NOT mathematical Int)
    irtBool        ## Boolean
    irtList        ## List with element type
    irtString      ## String
    irtEnum        ## Finite enumeration (mapped to BV64 ordinals in SMT)
    irtVariant     ## Tagged union (case object): tag in high bits, payload in low bits

  IRType* {.acyclic.} = ref object
    case kind*: IRTypeKind
    of irtBitVec64:
      discard
    of irtBool:
      discard
    of irtList:
      elemType*: IRType
    of irtString:
      discard
    of irtEnum:
      enumName*: string      ## enumeration type name
      enumValues*: seq[string]  ## variant names
      enumOrdinals*: seq[int64] ## ordinal values (parallel to enumValues)
    of irtVariant:
      variantName*: string            ## variant type name
      variantTags*: seq[string]       ## tag names
      variantOrdinals*: seq[int64]    ## tag ordinal values
      variantPayloadTypes*: seq[IRType] ## payload type per tag
      tagBitWidth*: int               ## bits for tag extraction (computed from max ordinal)

func computeTagBitWidth*(maxOrdinal: int64): int {.inline.} =
  ## Compute minimum bit width needed to represent the maximum ordinal.
  if maxOrdinal <= 0'i64: 8
  elif maxOrdinal <= 0xFF'i64: 8
  elif maxOrdinal <= 0xFFFF'i64: 16
  elif maxOrdinal <= 0xFFFFFFFF'i64: 32
  else: 64

func irTypeBitVec64*: IRType {.inline.} =
  IRType(kind: irtBitVec64)

func irTypeBool*: IRType {.inline.} =
  IRType(kind: irtBool)

func irTypeList*(elem: IRType): IRType {.inline.} =
  IRType(kind: irtList, elemType: elem)

func irTypeString*: IRType {.inline.} =
  IRType(kind: irtString)

func irTypeEnum*(name: string; values: seq[string]; ordinals: seq[int64]): IRType {.inline.} =
  IRType(kind: irtEnum, enumName: name, enumValues: values, enumOrdinals: ordinals)

func irTypeVariant*(name: string; tags: seq[string]; ordinals: seq[int64]; payloadTypes: seq[IRType]): IRType {.inline.} =
  var maxOrd = 0'i64
  for o in ordinals:
    if o > maxOrd: maxOrd = o
  let tagBitWidth = computeTagBitWidth(maxOrd)
  IRType(kind: irtVariant, variantName: name, variantTags: tags, variantOrdinals: ordinals, variantPayloadTypes: payloadTypes, tagBitWidth: tagBitWidth)

func irTypeFromKind*(kind: IRTypeKind): IRType {.inline.} =
  ## Create a minimal IRType from just the kind.
  ## Used by type manifest registry when only the kind is known.
  case kind
  of irtBitVec64: irTypeBitVec64()
  of irtBool: irTypeBool()
  of irtList: irTypeList(irTypeBitVec64())
  of irtString: irTypeString()
  of irtEnum: irTypeEnum("", @[], @[])
  of irtVariant: irTypeVariant("", @[], @[], @[])

func serializeIRType*(t: IRType): string {.raises: [].} =
  ## Deterministic canonical serialization of an IRType.
  case t.kind
  of irtBitVec64: "BV64"
  of irtBool: "BOOL"
  of irtList: "LIST(" & serializeIRType(t.elemType) & ")"
  of irtString: "STR"
  of irtEnum:
    var ordStrs: seq[string]
    for o in t.enumOrdinals: ordStrs.add($o)
    "ENUM(" & t.enumName & ",[" & t.enumValues.join(",") & "],[" &
      ordStrs.join(",") & "])"
  of irtVariant:
    var ordStrs: seq[string]
    for o in t.variantOrdinals: ordStrs.add($o)
    var payloadStrs: seq[string]
    for pt in t.variantPayloadTypes: payloadStrs.add(serializeIRType(pt))
    "VARIANT(" & t.variantName & ",[" & t.variantTags.join(",") & "],[" &
      ordStrs.join(",") & "],[" & payloadStrs.join(",") & "])"

{.pop.}
