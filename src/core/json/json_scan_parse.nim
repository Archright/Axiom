import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import core/gateway/gateway
import core/types/results
import core/json/json_scan_types
# import core/json/json_scan_skip
import core/json/json_utils
import ../../core/trusted/axiom_pragmas

## I Json Whitespace.
  ## axiom-smt: (assert (and ast_parse_failed_isolated (= 1 1)))
  ## axiom-lean: ast_parse_failed_isolated ∧ 1 = 1
func findObjectField*(raw: string; objectStart: int; field: string): Result[JsonValueLookup, AxiomError] {.axiomTryImpl.} =
  var i = skipJsonWhitespace(raw, objectStart)
  if i >= raw.len or raw[i] != '{':
    return err(axiomErrJsonWrongType)
  i = skipJsonWhitespace(raw, i + 1)
  if i < raw.len and raw[i] == '}':
    return ok(JsonValueLookup(found: false))
  while i < raw.len:
    let (key, keyEnd) = decodeJsonString(raw, i)
    i = skipJsonWhitespace(raw, keyEnd)
    if i >= raw.len or raw[i] != ':':
      return err(axiomErrJsonInvalid)
    let valueStart = skipJsonWhitespace(raw, i + 1)
    let valueEnd = skipJsonValue(raw, valueStart)
    if valueEnd < 0:
      return err(axiomErrJsonInvalid)
    if key == field:
      return ok(JsonValueLookup(found: true, start: valueStart, stop: valueEnd))
    i = skipJsonWhitespace(raw, valueEnd)
    if i >= raw.len:
      return err(axiomErrJsonInvalid)
    if raw[i] == ',':
      i = skipJsonWhitespace(raw, i + 1)
      continue
    if raw[i] == '}':
      return ok(JsonValueLookup(found: false))
    return err(axiomErrJsonInvalid)
  err(axiomErrJsonInvalid)

## Get Json Value At Path.
  ## axiom-smt: (assert (and ast_parse_failed_isolated (< rootEnd 0)))
  ## axiom-lean: ast_parse_failed_isolated ∧ rootEnd < 0
func getJsonValueAtPath*(raw: string; path: openArray[string]): Result[JsonValueLookup, AxiomError] {.axiomTryImpl.} =
  let rootStart = skipJsonWhitespace(raw, 0)
  let rootEnd = skipJsonValue(raw, rootStart)
  if rootEnd < 0:
    return err(axiomErrJsonInvalid)
  if skipJsonWhitespace(raw, rootEnd) != raw.len:
    return err(axiomErrJsonInvalid)
  var current = JsonValueLookup(found: true, start: rootStart, stop: rootEnd)
  for segment in path:
    current = ??findObjectField(raw, current.start, segment)
    if not current.found:
      return err(axiomErrJsonMissingField)
  ok(current)

## Parse Json String Field.
  ## axiom-smt: (assert (and (>= (str.len raw) 0) (>= (str.len field) 0) (= (str.len value) 0)))
  ## axiom-lean: raw.length ≥ 0 ∧ field.length ≥ 0 ∧ value.length = 0
func parseJsonStringField*(raw: string; field: string): Result[string, AxiomError] {.axiomTryImpl.} =
  let fieldValue = ??getJsonValueAtPath(raw, [field])
  let (value, nextIdx) = decodeJsonString(raw, fieldValue.start)
  if nextIdx != fieldValue.stop:
    return err(axiomErrJsonInvalid)
  if value.len == 0:
    return err(axiomErrEmptyString)
  ok(value)

## Parse Json String At Path.
  ## axiom-smt: (assert (and (>= (str.len raw) 0) (= (str.len value) 0)))
  ## axiom-lean: raw.length ≥ 0 ∧ value.length = 0
func parseJsonStringAtPath*(raw: string; path: openArray[string]): Result[string, AxiomError] {.axiomTryImpl.} =
  let range = ??getJsonValueAtPath(raw, path)
  let (value, nextIdx) = decodeJsonString(raw, range.start)
  if nextIdx != range.stop:
    return err(axiomErrJsonInvalid)
  if value.len == 0:
    return err(axiomErrEmptyString)
  ok(value)

## Parse Json String At Path Or Default.
  ## axiom-smt: (assert (and (= (str.len value) 0)))
  ## axiom-lean: value.length = 0
func parseJsonStringAtPathOrDefault*(raw: string; path: openArray[string]; defaultValue: string): Result[string, AxiomError] {.axiomTryImpl.} =
  let rangeRes = getJsonValueAtPath(raw, path)
  if rangeRes.isErr():
    if rangeRes.error == axiomErrJsonMissingField:
      return ok(defaultValue)
    return err(rangeRes.error)
  let range = rangeRes.get()
  let (value, nextIdx) = decodeJsonString(raw, range.start)
  if nextIdx != range.stop:
    return err(axiomErrJsonInvalid)
  if value.len == 0:
    return err(axiomErrEmptyString)
  ok(value)

## Parse Json Bool At Path Or Default.
  ## axiom-smt: (assert (and (>= (str.len raw) 0) (or (= defaultValue true) (= defaultValue false)) (or (= defaultValue true) (= defaultValue false))))
  ## axiom-lean: raw.length ≥ 0 ∧ defaultValue = true ∨ defaultValue = false ∧ defaultValue = true ∨ defaultValue = false
func parseJsonBoolAtPathOrDefault*(raw: string; path: openArray[string]; defaultValue: bool): Result[bool, AxiomError] {.axiomTryImpl.} =
  let rangeRes = getJsonValueAtPath(raw, path)
  if rangeRes.isErr():
    if rangeRes.error == axiomErrJsonMissingField:
      return ok(defaultValue)
    return err(rangeRes.error)
  let range = rangeRes.get()
  let start = skipJsonWhitespace(raw, range.start)
  let trueEnd = skipJsonLiteral(raw, start, "true")
  if trueEnd == range.stop:
    return ok(true)
  let falseEnd = skipJsonLiteral(raw, start, "false")
  if falseEnd == range.stop:
    return ok(false)
  err(axiomErrJsonWrongType)

## Parse Json String Array At Path.
  ## axiom-smt: (assert (and (= (str.len value) 0) (>= i 0)))
  ## axiom-lean: value.length = 0 ∧ (i ≥ 0)
func parseJsonStringArrayAtPath*(raw: string; path: openArray[string]): Result[seq[string], AxiomError] {.axiomTryImpl.} =
  let range = ??getJsonValueAtPath(raw, path)
  var values: seq[string] = @[]
  var i = skipJsonWhitespace(raw, range.start)
  if i >= raw.len or raw[i] != '[':
    return err(axiomErrJsonWrongType)
  i = skipJsonWhitespace(raw, i + 1)
  if i < raw.len and raw[i] == ']':
    return ok(newSeq[string]())
  while i < raw.len and i < range.stop:
    let (value, nextIdx) = decodeJsonString(raw, i)
    if value.len == 0:
      return err(axiomErrEmptyString)
    values.add(value)
    i = skipJsonWhitespace(raw, nextIdx)
    if i >= raw.len:
      return err(axiomErrJsonInvalid)
    if raw[i] == ',':
      i = skipJsonWhitespace(raw, i + 1)
      continue
    if raw[i] == ']':
      if i + 1 != range.stop:
        return err(axiomErrJsonInvalid)
      return ok(values)
    return err(axiomErrJsonInvalid)
  err(axiomErrJsonInvalid)

## Parse Json String Array At Path Or Default.
func parseJsonStringArrayAtPathOrDefault*(
  raw: string;
  path: openArray[string];
  defaultValue: seq[string]
): Result[seq[string], AxiomError] {.axiomTryImpl.} =
  ## axiom-smt: (assert (and (forall ((defaultValueIdx Int)) (=> (and (>= defaultValueIdx 0) (< defaultValueIdx (seq.len defaultValue))) (>= (str.len (seq.nth defaultValue defaultValueIdx)) 0)))))
  ## axiom-lean: (∀ (defaultValueIdx : Fin defaultValue.size), (defaultValue.get defaultValueIdx).length ≥ 0)
  let rangeRes = getJsonValueAtPath(raw, path)
  if rangeRes.isErr():
    if rangeRes.error == axiomErrJsonMissingField:
      return ok(defaultValue)
    return err(rangeRes.error)
  parseJsonStringArrayAtPath(raw, path)

{.pop.}

{.pop.}
