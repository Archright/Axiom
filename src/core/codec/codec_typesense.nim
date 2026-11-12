import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Codec Typesense — Compile-Time Type Introspection Engine
##
## Pure compile-time module for classifying Nim AST type nodes
## and extracting field metadata for code generation.
##
## Used by codec_codegen.nim to drive toJson/fromJson derivation.
## Reuses patterns from macro_helpers.nim and export_injector.nim.

import std/macros

type
  TypeKind* = enum
    tkString, tkInt, tkFloat, tkBool,
    tkEnum, tkDistinct,
    tkSeq, tkOption, tkTable,
    tkObject, tkRefObject, tkVariantObject,
    tkJsonNode, tkUnknown

  FieldInfo* = object
    name*: string           ## field name (stripped of *)
    nameNode*: NimNode      ## identifier node for codegen
    typeNode*: NimNode      ## raw type node for recursive dispatch
    typeKind*: TypeKind     ## pre-classified type kind
    isOptional*: bool       ## true only for Option[T] fields
    baseTypeNode*: NimNode  ## for distinct: the base type node
    baseTypeKind*: TypeKind ## for distinct: resolved base kind

  VariantBranch* = object
    discValues*: seq[NimNode]  ## nnkOfBranch value nodes
    discValueNames*: seq[string]  ## enum value names (from nnkSym.strVal or $intVal)
    branchFields*: seq[FieldInfo]

  TypeInfo* = object
    kind*: TypeKind
    typeName*: string
    baseTypeNode*: NimNode       ## for distinct: the base type
    baseTypeKind*: TypeKind      ## for distinct: resolved base kind
    memberFields*: seq[FieldInfo]
    enumValues*: seq[string]
    hasDiscriminator*: bool
    discFieldName*: string
    discNameNode*: NimNode
    branches*: seq[VariantBranch]
    elseFields*: seq[FieldInfo]

  ObjectFieldResult* = object
    ## Result of extractObjectFields — avoids named tuple + noSideEffect clash.
    memberFields*: seq[FieldInfo]
    hasDisc*: bool
    discName*: string
    discNameNode*: NimNode
    branches*: seq[VariantBranch]
    elseFields*: seq[FieldInfo]

# ── Symbol Classification ────────────────────────────────────────────────────

func classifySymbol*(symName: string): TypeKind =
  ## Map a type symbol name to its TypeKind classification.
  case symName
  of "string": tkString
  of "int", "int8", "int16", "int32", "int64",
     "uint", "uint8", "uint16", "uint32", "uint64": tkInt
  of "float", "float32", "float64": tkFloat
  of "bool": tkBool
  of "JsonNode": tkJsonNode
  else: tkUnknown

# ── AST Name Extraction ─────────────────────────────────────────────────────

func getNameStr*(node: NimNode): string =
  ## Extract the identifier string from a node, handling nnkPostfix (*).
  case node.kind
  of nnkPostfix: node[1].strVal
  of nnkIdent, nnkSym: node.strVal
  else: $node

func getNameNode*(node: NimNode): NimNode =
  ## Get the raw identifier node, stripping nnkPostfix wrapper.
  case node.kind
  of nnkPostfix: node[1]
  of nnkIdent, nnkSym: node
  else: node

# ── Type Classification ─────────────────────────────────────────────────────

func classifyType*(node: NimNode): TypeKind =
  ## Classify a type AST node into its TypeKind.
  ## Handles nnkSym, nnkBracketExpr, nnkRefTy, nnkDistinctTy,
  ## nnkObjectTy, nnkEnumTy.
  case node.kind
  of nnkSym:
    let basic = classifySymbol($node)
    if basic != tkUnknown: return basic
    # Non-primitive symbol — resolve via getTypeImpl
    let impl = node.getTypeImpl()
    if impl.kind != node.kind:
      return classifyType(impl)
    tkUnknown
  of nnkBracketExpr:
    let head = $node[0]
    if head == "seq": tkSeq
    elif head == "Option": tkOption
    elif head in ["Table", "OrderedTable"]: tkTable
    else: tkUnknown
  of nnkRefTy:
    tkRefObject
  of nnkDistinctTy:
    tkDistinct
  of nnkObjectTy:
    for child in node:
      if child.kind == nnkRecList:
        for childNode in child:
          if childNode.kind == nnkRecCase:
            return tkVariantObject
    tkObject
  of nnkEnumTy:
    tkEnum
  of nnkPtrTy:
    tkRefObject  # treat ptr same as ref for serialization
  else:
    tkUnknown

# ── Enum Value Extraction ────────────────────────────────────────────────────

func extractEnumValues*(node: NimNode): seq[string] =
  ## Extract enum variant names from nnkEnumTy.
  ## First child is nnkEmpty (placeholder), rest are nnkIdent, nnkSym,
  ## or nnkEnumFieldDef (for enums with explicit values).
  assert node.kind == nnkEnumTy
  for i in 1 ..< node.len:
    case node[i].kind
    of nnkIdent, nnkSym: result.add($node[i])
    of nnkEnumFieldDef: result.add($node[i][0])
    else: discard

# ── Distinct Base Type Resolution ────────────────────────────────────────────

func resolveDistinctBase*(node: NimNode): (NimNode, TypeKind) =
  ## Extract base type from nnkDistinctTy and classify it.
  ## nnkDistinctTy has one child: the base type identifier.
  assert node.kind == nnkDistinctTy
  let baseNode = node[0]
  (baseNode, classifyType(baseNode))

# ── Object Field Extraction ─────────────────────────────────────────────────

func extractFieldsFromIdentDefs(node: NimNode): seq[FieldInfo] =
  ## Extract field info from nnkIdentDefs.
  ## Structure: [Ident1, Ident2, ..., Type, Default]
  ## Last 2 children are type and default; rest are field names.
  assert node.kind == nnkIdentDefs
  let typeNode = node[node.len - 2]
  let typeKind = classifyType(typeNode)
  let isOpt = (typeKind == tkOption)

  var baseNode: NimNode = newEmptyNode()
  var baseKind: TypeKind = tkUnknown
  if typeKind == tkDistinct:
    let resolved = resolveDistinctBase(typeNode)
    baseNode = resolved[0]
    baseKind = resolved[1]

  for i in 0 ..< node.len - 2:
    let nameNode = node[i]
    if nameNode.kind in {nnkIdent, nnkSym, nnkPostfix}:
      result.add(FieldInfo(
        name: getNameStr(nameNode),
        nameNode: getNameNode(nameNode),
        typeNode: typeNode,
        typeKind: typeKind,
        isOptional: isOpt,
        baseTypeNode: baseNode,
        baseTypeKind: baseKind,
      ))

func extractObjectFields*(recList: NimNode): ObjectFieldResult =
  ## Walk nnkRecList to extract all fields, detecting nnkRecCase for variants.
  for child in recList:
    case child.kind
    of nnkIdentDefs:
      for f in extractFieldsFromIdentDefs(child):
        result.memberFields.add(f)
    of nnkRecCase:
      result.hasDisc = true
      # First child is the discriminator nnkIdentDefs
      let discDef = child[0]
      result.discName = getNameStr(discDef[0])
      result.discNameNode = getNameNode(discDef[0])
      # Resolve enum value names from discriminator type for ordinal→name mapping
      var enumNames: seq[string]
      if discDef.len > 1:
        let discTypeImpl = getTypeImpl(discDef[1])
        if discTypeImpl.kind == nnkEnumTy:
          for i in 1 ..< discTypeImpl.len:
            enumNames.add($discTypeImpl[i])
      # Also add discriminator as a regular field
      for f in extractFieldsFromIdentDefs(discDef):
        result.memberFields.add(f)
      # Remaining children are nnkOfBranch or nnkElse
      for j in 1 ..< child.len:
        if child[j].kind == nnkOfBranch:
          var branch = VariantBranch()
          # nnkOfBranch children: [value1, value2, ..., nnkRecList]
          for k in 0 ..< child[j].len - 1:
            let dv = child[j][k]
            branch.discValues.add(dv)
            # Store enum value name for fromJson string mapping
            if dv.kind == nnkSym:
              branch.discValueNames.add(dv.strVal)
            elif dv.kind == nnkIntLit and dv.intVal.int < enumNames.len:
              branch.discValueNames.add(enumNames[dv.intVal.int])
            elif dv.kind == nnkIntLit:
              branch.discValueNames.add($dv.intVal)
            else:
              branch.discValueNames.add($dv)
          let branchRecList = child[j][child[j].len - 1]
          for bf in branchRecList:
            if bf.kind == nnkIdentDefs:
              for f in extractFieldsFromIdentDefs(bf):
                branch.branchFields.add(f)
          result.branches.add(branch)
        elif child[j].kind == nnkElse:
          let elseRecList = child[j][0]
          for ef in elseRecList:
            if ef.kind == nnkIdentDefs:
              for f in extractFieldsFromIdentDefs(ef):
                result.elseFields.add(f)
    of nnkOfInherit:
      # Inheritance: resolve parent type fields
      # child[0] is the parent type symbol
      # We handle this by erroring — manual codec needed for inheritance
      discard
    of nnkRecWhen:
      error("deriveJsonCodec: conditional compilation fields (nnkRecWhen) not supported. Use manual codec.")
    else:
      discard

# ── Unwrap Helpers ───────────────────────────────────────────────────────────

func unwrapRef*(node: NimNode): NimNode =
  ## Unwrap nnkRefTy to get the inner nnkObjectTy.
  if node.kind == nnkRefTy:
    if node.len > 0:
      return node[0]
  node

func unwrapDistinct*(node: NimNode): NimNode =
  ## Unwrap nnkDistinctTy to get the base type.
  if node.kind == nnkDistinctTy:
    if node.len > 0:
      return node[0]
  node

# ── Full Type Classification ────────────────────────────────────────────────

func classifyFull*(node: NimNode; typeName: string): TypeInfo =
  ## Perform full type classification and field extraction.
  ## Input must be the unwrapped type node (after unwrapRef).
  result.typeName = typeName
  result.kind = classifyType(node)

  case result.kind
  of tkEnum:
    result.enumValues = extractEnumValues(node)
  of tkObject, tkVariantObject, tkRefObject:
    # nnkObjectTy structure: [pragmas, inheritance, nnkRecList]
    # extractObjectFields expects the nnkRecList child, not the full nnkObjectTy
    let recListNode = if node.kind == nnkObjectTy and node.len > 2: node[2]
                       else: node
    let objResult = extractObjectFields(recListNode)
    result.memberFields = objResult.memberFields
    result.hasDiscriminator = objResult.hasDisc
    result.discFieldName = objResult.discName
    result.discNameNode = objResult.discNameNode
    result.branches = objResult.branches
    result.elseFields = objResult.elseFields
    if objResult.hasDisc:
      result.kind = tkVariantObject
  of tkDistinct:
    let (baseNode, baseKind) = resolveDistinctBase(node)
    result.baseTypeNode = baseNode
    result.baseTypeKind = baseKind
  else:
    discard

{.pop.}
