import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

import std/options
import std/strutils

import core/parsers/safe_parsers
import core/gateway/gateway
import core/types/results
import core/json/std_redirect

## Default Proof Vault Dir.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
func defaultProofVaultDir*(): string {.raises: [], noSideEffect.} =
  ".axiom/vault"

## Default Bdd Dir.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
func defaultBddDir*(): string {.raises: [], noSideEffect.} =
  "tests/features"

## Lookup Field.
# @axiom-hint: lean="key = fieldName ∧ fieldName.length ≥ 0" smt="(assert (and (= key fieldName) (>= (str.len fieldName) 0)))"
func lookupField*(
  node: JsonNode;
  fieldName: string
): Option[JsonNode] {.raises: [], noSideEffect.} =
  if node.kind != JObject:
    return none(JsonNode)
  for key, value in node.pairs:
    if key == fieldName:
      return some(value)
  none(JsonNode)

## String Field.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
# @axiom-hint: lean="value.length = 0 ∧ fieldName.length ≥ 0" smt="(assert (and (= (str.len value) 0) (>= (str.len fieldName) 0)))"
func stringField*(
  node: JsonNode;
  fieldName: string
): Result[string, AxiomError] {.raises: [].} =
  let fieldOpt = lookupField(node, fieldName)
  if fieldOpt.isNone():
    return err(axiomErrJsonMissingField)
  let field = fieldOpt.get()
  if field.kind != JString:
    return err(axiomErrJsonWrongType)
  let value = field.getStr().strip()
  if value.len == 0:
    return err(axiomErrEmptyString)
  ok(value)

## Optional String Field.
# @axiom-hint: lean="fieldName.length ≥ 0 ∧ defaultValue.length ≥ 0" smt="(assert (and (>= (str.len fieldName) 0) (>= (str.len defaultValue) 0)))"
func optionalStringField*(
  node: JsonNode;
  fieldName: string;
  defaultValue: string = ""
): Result[string, AxiomError] {.raises: [].} =
  let fieldOpt = lookupField(node, fieldName)
  if fieldOpt.isNone():
    return ok(defaultValue)
  let field = fieldOpt.get()
  if field.kind != JString:
    return err(axiomErrJsonWrongType)
  ok(field.getStr())

## Optional Int Field.
# @axiom-hint: lean="fieldName.length ≥ 0 ∧ defaultValue ≥ -9223372036854775808 ∧ defaultValue ≤ 9223372036854775807" smt="(assert (and (>= (str.len fieldName) 0) (and (>= defaultValue -9223372036854775808) (<= defaultValue 9223372036854775807))))"
# @axiom-hint: lean="JInt ∧ JString" smt="(assert (and JInt JString))"
func optionalIntField*(
  node: JsonNode;
  fieldName: string;
  defaultValue: int
): Result[int, AxiomError] {.raises: [].} =
  let fieldOpt = lookupField(node, fieldName)
  if fieldOpt.isNone():
    return ok(defaultValue)
  let field = fieldOpt.get()
  case field.kind
  of JInt:
    ok(field.getInt())
  of JString:
    let parsed = safeParseInt(field.getStr().strip())
    if parsed.isOk:
      ok(parsed.get)
    else:
      err(axiomErrInvalidValue)
  else:
    err(axiomErrJsonWrongType)

## Object Field.
func objectField*(
  node: JsonNode;
  fieldName: string
): Result[JsonNode, AxiomError] {.raises: [].} =
  let fieldOpt = lookupField(node, fieldName)
  if fieldOpt.isNone():
    return err(axiomErrJsonMissingField)
  let field = fieldOpt.get()
  if field.kind != JObject:
    return err(axiomErrJsonWrongType)
  ok(field)
{.pop.}
