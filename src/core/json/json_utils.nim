import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/json/json_utils_scan
import core/json/std_redirect
import core/parsers/safe_parsers
import core/pure/json_parse
import core/trusted/axiom_pragmas
import core/types/results
import core/utils/io_utils
import std/json except parseJson
import std/options
import std/sequtils
import std/strutils
export json_utils_scan

## Render Json Multiline.
func renderJsonMultiline*(node: JsonNode): string {.noSideEffect.} =
  pretty(node, 2)

## Json Node String Array.
# @axiom-hint: lean="values.size ≥ 0 ∧ (∀ (valuesIdx : Fin values.size), (values.get valuesIdx).length ≥ 0)" smt="(assert (and (>= (seq.len values) 0) (forall ((valuesIdx Int)) (=> (and (>= valuesIdx 0) (< valuesIdx (seq.len values))) (>= (str.len (seq.nth values valuesIdx)) 0)))))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
func jsonNodeStringArray*(values: seq[string]): JsonNode {.noSideEffect.} =
  result = newJArray()
  for item in values:
    result.add(newJString(item))

## Normalized String Seq.
# @axiom-hint: lean="(∀ (valuesIdx : Fin values.size), (values.get valuesIdx).length ≥ 0)" smt="(assert (and (forall ((valuesIdx Int)) (=> (and (>= valuesIdx 0) (< valuesIdx (seq.len values))) (>= (str.len (seq.nth values valuesIdx)) 0)))))"
func normalizedStringSeq*(values: seq[string]): seq[string] {.noSideEffect.} =
  values
    .mapIt(it.strip())
    .filterIt(it.len > 0)
    .deduplicate()

## Json Array To String Seq.
# @axiom-hint: lean="value.length > 0 ∧ (result ≥ 0)" smt="(assert (and (> (str.len value) 0) (>= result 0)))"
func jsonArrayToStringSeq*(node: JsonNode): seq[string] {.noSideEffect.} =
  if node.kind != JArray:
    return @[]
  for item in node.elems:
    if item.kind == JString:
      let value = item.getStr().strip()
      if value.len > 0:
        result.add(value)
  result = result.deduplicate()

## Sync String Array Field.
# @axiom-hint: lean="fieldName.length ≥ 0 ∧ values.size ≥ 0 ∧ (∀ (valuesIdx : Fin values.size), (values.get valuesIdx).length ≥ 0)" smt="(assert (and (>= (str.len fieldName) 0) (>= (seq.len values) 0) (forall ((valuesIdx Int)) (=> (and (>= valuesIdx 0) (< valuesIdx (seq.len values))) (>= (str.len (seq.nth values valuesIdx)) 0)))))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
func syncStringArrayField*(node: var JsonNode; fieldName: string; values: seq[string]): bool =
  let expected = normalizedStringSeq(values)
  if expected.len == 0:
    if node.hasKey(fieldName):
      try:
        node.delete(fieldName)
      except KeyError:
        discard  # guarded by hasKey
      return true
    return false
  if node.hasKey(fieldName):
    let current = jsonArrayToStringSeq(node{fieldName})
    if current == expected:
      return false
  node[fieldName] = jsonNodeStringArray(expected)
  true

## Write Pretty Json File.
# @axiom-hint: lean="result = true ∧ (result ≥ 0) ∧ external_io_isolated" smt="(assert (and (= result true) (>= result 0) external_io_isolated))"
export json_utils_scan

## Write Pretty Json File.
# @axiom-hint: lean="result = true ∧ (result ≥ 0) ∧ external_io_isolated" smt="(assert (and (= result true) (>= result 0) external_io_isolated))"
# CONFLICT_UNRESOLVED: syncStringArrayField (both sides modified)
proc writePrettyJsonFile*(path: string; node: JsonNode): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Atomic write: delegates to writeFileOpt which writes to .tmp then renames.
  writeFileOpt(path, pretty(node, 2)).isOk

## Parse Json Optional.
# @axiom-hint: lean="raw.length ≥ 0 ∧ (result ≥ 0)" smt="(assert (and (>= (str.len raw) 0) (>= result 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
func parseJsonOpt*(raw: string): Option[JsonNode] {.raises: [].} =
  try:
    result = some(pureParseJson(raw))
  except CatchableError:
    result = none(JsonNode)

## Read Json File.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
# @axiom-hint: lean="path.length ≥ 0" smt="(assert (and (>= (str.len path) 0)))"
proc readJsonFile*(path: string): Option[JsonNode] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let contentRes = readFileOpt(path)
  if contentRes.isErr:
    return none(JsonNode)
  parseJsonOpt(contentRes.get())
proc readJsonFileNode*(path: string): JsonNode {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Same as readJsonFile but returns nil on failure instead of Option.
  ## Use this when the JsonNode must outlive a temporary Option wrapper
  ## (ARC/ORC safety: avoids early-destruction dangling ref).
  let opt = readJsonFile(path)
  if opt.isNone: return nil
  result = opt.unsafeGet
# ── JsonNode field extractors (promoted from verify_workflow_cli) ───────────
# These operate on already-parsed JsonNode objects. For raw-string scanning
# (without full parse), use json_scan.nim instead.

# @axiom-hint: lean="fieldName.length ≥ 0" smt="(assert (and (>= (str.len fieldName) 0)))"
# @axiom-hint: lean="value.length = 0" smt="(assert (and (= (str.len value) 0)))"
func readRequiredJsonString*(node: JsonNode; fieldName: string): Result[string, string] =
  if node.kind != JObject:
    return err("JSON payload entries must be objects")
  let field = node{fieldName}
  if field.isNil or field.kind != JString:
    return err("JSON payload requires string field: " & fieldName)
  let value = field.getStr().strip()
  if value.len == 0:
    return err("JSON payload requires non-empty string field: " & fieldName)
  ok(value)

# @axiom-hint: lean="fieldName.length ≥ 0" smt="(assert (and (>= (str.len fieldName) 0)))"
func readOptionalJsonString*(node: JsonNode; fieldName: string): string =
  if node.kind == JObject and node.hasKey(fieldName) and node{fieldName}.kind == JString:
    return node{fieldName}.getStr().strip()
  ""

# @axiom-hint: lean="fieldName.length ≥ 0" smt="(assert (and (>= (str.len fieldName) 0)))"
# @axiom-hint: lean="JInt ∧ JString" smt="(assert (and JInt JString))"
func readRequiredJsonInt*(node: JsonNode; fieldName: string): Result[int, string] =
  if node.kind != JObject or not node.hasKey(fieldName):
    return err("JSON payload requires integer field: " & fieldName)
  let field = node{fieldName}
  case field.kind
  of JInt:
    ok(field.getInt())
  of JString:
    let parsed = safeParseInt(field.getStr())
    if parsed.isOk: ok(parsed.get())
    else: err("JSON payload requires integer field: " & fieldName)
  else:
    err("JSON payload requires integer field: " & fieldName)

# @axiom-hint: lean="fieldName.length ≥ 0 ∧ defaultValue = true ∨ defaultValue = false" smt="(assert (and (>= (str.len fieldName) 0) (or (= defaultValue true) (= defaultValue false))))"
# @axiom-hint: lean="JBool ∧ JString ∧ JInt ∧ defaultValue = true ∨ defaultValue = false" smt="(assert (and JBool JString JInt (or (= defaultValue true) (= defaultValue false))))"
func readOptionalJsonBool*(node: JsonNode; fieldName: string; defaultValue: bool): Result[bool, string] =
  if node.kind != JObject or not node.hasKey(fieldName):
    return ok(defaultValue)
  let field = node{fieldName}
  case field.kind
  of JBool:
    ok(field.getBool())
  of JString:
    let s = field.getStr().toLowerAscii()
    if s == "true" or s == "1": ok(true)
    elif s == "false" or s == "0": ok(false)
    else: err("JSON payload requires boolean field: " & fieldName)
  of JInt:
    if field.getInt() == 1: ok(true)
    elif field.getInt() == 0: ok(false)
    else: err("JSON payload requires boolean field: " & fieldName)
  else:
    err("JSON payload requires boolean field: " & fieldName)

# @axiom-hint: lean="fieldName.length ≥ 0 ∧ defaultValue ≥ -9223372036854775808 ∧ defaultValue ≤ 9223372036854775807" smt="(assert (and (>= (str.len fieldName) 0) (and (>= defaultValue -9223372036854775808) (<= defaultValue 9223372036854775807))))"
# @axiom-hint: lean="JInt ∧ JString" smt="(assert (and JInt JString))"
func readOptionalJsonInt*(node: JsonNode; fieldName: string; defaultValue: int): Result[int, string] =
  if node.kind != JObject or not node.hasKey(fieldName):
    return ok(defaultValue)
  let field = node{fieldName}
  case field.kind
  of JInt:
    ok(field.getInt())
  of JString:
    let parsed = safeParseInt(field.getStr())
    if parsed.isOk: ok(parsed.get())
    else: err("JSON payload requires integer field: " & fieldName)
  else:
    err("JSON payload requires integer field: " & fieldName)

# @axiom-hint: lean="fieldName.length ≥ 0" smt="(assert (and (>= (str.len fieldName) 0)))"
func readJsonStringSeq*(node: JsonNode; fieldName: string): Result[seq[string], string] =
  if node.kind != JObject or not node.hasKey(fieldName):
    return ok(newSeq[string]())
  if node{fieldName}.kind != JArray:
    return err("JSON payload requires array field: " & fieldName)
  var values: seq[string] = @[]
  for child in node{fieldName}:
    if child.kind != JString:
      return err("JSON payload array must contain strings: " & fieldName)
    values.add(child.getStr().strip())
  ok(values)
# These operate on already-parsed JsonNode objects. For raw-string scanning
# (without full parse), use json_scan.nim instead.
# CONFLICT_UNRESOLVED: readJsonStringSeq (both sides modified)
{.pop.}
