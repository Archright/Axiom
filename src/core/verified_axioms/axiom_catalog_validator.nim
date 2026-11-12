import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Axiom Catalog Schema Validator
##
## Compile-time macro that loads and validates the externalized
## axiom catalog JSON file. Enforces the Data-Schema-Validation pattern.

import std/json except parseJson
import core/pure/json_parse
import std/macros

const requiredFields = @[
  "axiomId", "nimSymbol", "leanTheorem", "leanType",
  "nimSignature", "leanSignature", "axiomVersion",
  "proofObligation", "verified", "sourceHash",
  "leanTheoremSource", "category"
]

macro loadAndValidateAxiomCatalog*(path: static string): untyped =
  ## Compile-time entry point. Reads JSON at `path`, validates every
  ## entry against AxiomMapping schema, returns seq[AxiomMapping] literal.
  ## Compilation aborts on any validation violation.
  let raw = staticRead(path)
  var node: JsonNode
  try:
    node = pureParseJson(raw)
  except JsonParsingError as e:
    error("axiom_catalog_validator: JSON parse error: " & e.msg)

  if node.kind != JArray:
    error("axiom_catalog_validator: Expected JSON array, got " & $node.kind)

  if node.len == 0:
    error("axiom_catalog_validator: axiom catalog JSON is empty")

  # Validate and extract
  var elems = newSeq[NimNode](node.len)
  for i in 0 ..< node.len:
    let entry = node[i]
    if entry.kind != JObject:
      error("axiom_catalog_validator: Entry " & $i & " is not a JSON object")

    let axiomId = if entry.hasKey("axiomId"): entry["axiomId"].getStr() else: "<missing>"

    # Validate required fields
    for field in requiredFields:
      if not entry.hasKey(field):
        error("axiom_catalog_validator: Entry " & $i & " (" & axiomId &
              ") missing required field: " & field)

    # Validate types
    for strField in ["axiomId", "nimSymbol", "leanTheorem", "leanType",
                     "nimSignature", "leanSignature", "axiomVersion",
                     "proofObligation", "sourceHash",
                     "leanTheoremSource", "category"]:
      if entry[strField].kind != JString:
        error("axiom_catalog_validator: Entry " & $i & " (" & axiomId &
              "): field '" & strField & "' must be a string")

    if entry["verified"].kind != JBool:
      error("axiom_catalog_validator: Entry " & $i & " (" & axiomId &
            "): field 'verified' must be a boolean")

    # Validate category value
    let catStr = entry["category"].getStr()
    if catStr notin ["acLengthNonNeg", "acTypeCoercion", "acArithmetic",
                     "acMemory", "acEffectIsolation", "acLogicOperator",
                     "acContainerOps"]:
      error("axiom_catalog_validator: Entry " & $i & " (" & axiomId &
            "): invalid category '" & catStr & "'")

    # Build NimNode literal
    elems[i] = nnkObjConstr.newTree(
      ident("AxiomMapping"),
      newColonExpr(ident("axiomId"), newStrLitNode(entry["axiomId"].getStr())),
      newColonExpr(ident("nimSymbol"), newStrLitNode(entry["nimSymbol"].getStr())),
      newColonExpr(ident("leanTheorem"), newStrLitNode(entry["leanTheorem"].getStr())),
      newColonExpr(ident("leanType"), newStrLitNode(entry["leanType"].getStr())),
      newColonExpr(ident("nimSignature"), newStrLitNode(entry["nimSignature"].getStr())),
      newColonExpr(ident("leanSignature"), newStrLitNode(entry["leanSignature"].getStr())),
      newColonExpr(ident("axiomVersion"), newStrLitNode(entry["axiomVersion"].getStr())),
      newColonExpr(ident("proofObligation"), newStrLitNode(entry["proofObligation"].getStr())),
      newColonExpr(ident("verified"), newLit(entry["verified"].getBool())),
      newColonExpr(ident("sourceHash"), newStrLitNode(entry["sourceHash"].getStr())),
      newColonExpr(ident("leanTheoremSource"), newStrLitNode(entry["leanTheoremSource"].getStr())),
      newColonExpr(ident("category"), ident(catStr))
    )

  result = nnkPrefix.newTree(ident("@"), nnkBracket.newTree(elems))

{.pop.}
