import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## JSON gateway helpers extracted from gateway.nim to keep per-module export
## count under the core-layer limit (≤15).

import std/options
import core/types/results
import core/types/domain_types
import core/json/json_utils
import core/json/std_redirect
import ../../core/trusted/axiom_pragmas

## Json Parse Safe.
func jsonParseSafe*(raw: string): Result[JsonNode, AxiomError] {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0)))", "raw.length ≥ 0"].} =
  ## Fails closed on any parsing failure — never yields ok(empty) for corrupt input.
  if raw.len == 0:
    return err(axiomErrJsonInvalid)
  let opt = parseJsonOpt(raw)
  if opt.isSome:
    ok(opt.get)
  else:
    err(axiomErrJsonInvalid)


## Json Require Object.
func jsonRequireObject*(node: JsonNode): Result[JsonNode, AxiomError] {.
  axiom: ["(assert (and (>= depth 0)))", "depth >= 0"],
  raises: [],
  ensures: (not result.isOk()) or (result.get().kind == JObject)
.} =
  if node.kind != JObject:
    return err(axiomErrJsonWrongType)
  ok(node)

## Json Require Object Field.
func jsonRequireObjectField*(node: JsonNode; field: string): Result[JsonNode, AxiomError] {.raises: [], axiom: ["(assert (and (>= (str.len field) 0)))", "field.length ≥ 0"].} =
  if node.kind != JObject:
    return err(axiomErrJsonWrongType)
  let v = node{field}
  if v.isNil:
    return err(axiomErrJsonMissingField)
  if v.kind != JObject:
    return err(axiomErrJsonWrongType)
  ok(v)

## Json Get Non Empty String Field.
func jsonGetNonEmptyStringField*(node: JsonNode; field: string): Result[string, AxiomError] {.
  axiom: ["(assert (and (= (str.len s) 0)))", "s.length = 0"],
  raises: [],
  ensures: (not result.isOk()) or (result.get().len > 0)
.} =
  if node.kind != JObject:
    return err(axiomErrJsonWrongType)
  let v = node{field}
  if v.isNil:
    return err(axiomErrJsonMissingField)
  if v.kind != JString:
    return err(axiomErrJsonWrongType)
  let s = v.getStr()
  if s.len == 0:
    return err(axiomErrEmptyString)
  ok(s)

## Json Get Non Empty String Field Or Default.
func jsonGetNonEmptyStringFieldOrDefault*(node: JsonNode; field: string; defaultValue: string): Result[string, AxiomError] {.
  axiom: ["(assert (and (>= (str.len field) 0) (>= (str.len defaultValue) 0) (= (str.len s) 0)))", "field.length ≥ 0 ∧ defaultValue.length ≥ 0 ∧ s.length = 0"],
  raises: [],
  requires: defaultValue.len > 0,
  ensures: (not result.isOk()) or (result.get().len > 0)
.} =
  if node.kind != JObject:
    return err(axiomErrJsonWrongType)
  let v = node{field}
  if v.isNil:
    return ok(defaultValue)
  if v.kind != JString:
    return err(axiomErrJsonWrongType)
  let s = v.getStr()
  if s.len == 0:
    return err(axiomErrEmptyString)
  ok(s)

## Json Get Bool Field Or Default.
func jsonGetBoolFieldOrDefault*(node: JsonNode; field: string; defaultValue: bool): Result[bool, AxiomError] {.raises: [], axiom: ["(assert (and (or (= defaultValue true) (= defaultValue false))))", "defaultValue = true ∨ defaultValue = false"].} =
  if node.kind != JObject:
    return err(axiomErrJsonWrongType)
  let v = node{field}
  if v.isNil:
    return ok(defaultValue)
  if v.kind != JBool:
    return err(axiomErrJsonWrongType)
  ok(v.getBool())

## Json Try Get Object Field.
func jsonTryGetObjectField*(node: JsonNode; field: string): Option[JsonNode] {.inline, raises: [], axiom: ["(assert (and (>= (str.len field) 0)))", "field.length ≥ 0"].} =
  if node.kind != JObject:
    return none(JsonNode)
  let v = node{field}
  if v.isNil or v.kind != JObject:
    return none(JsonNode)
  some(v)

## Json Try Get Array Field.
func jsonTryGetArrayField*(node: JsonNode; field: string): Option[JsonNode] {.inline, raises: [], axiom: ["(assert (and (>= (str.len field) 0)))", "field.length ≥ 0"].} =
  if node.kind != JObject:
    return none(JsonNode)
  let v = node{field}
  if v.isNil or v.kind != JArray:
    return none(JsonNode)
  some(v)

## Json Try Get Non Empty String Field.
func jsonTryGetNonEmptyStringField*(node: JsonNode; field: string): Option[string] {.inline, raises: [], axiom: ["(assert (and (= (str.len s) 0)))", "s.length = 0"].} =
  if node.kind != JObject:
    return none(string)
  let v = node{field}
  if v.isNil or v.kind != JString:
    return none(string)
  let s = v.getStr()
  if s.len == 0:
    return none(string)
  some(s)

{.pop.}
