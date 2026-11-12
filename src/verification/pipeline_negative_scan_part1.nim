import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/json
import std/strutils

import core/solver/types
import core/effect_shim
import core/axiom_pragmas
import core/utils/text_utils
import core/logic/universal_translation_types
# axiomIoBoundary

# @axiom-hint: lean="bindings.size ≥ 0" smt="(assert (and (>= (seq.len bindings) 0)))"
# @axiom-hint: lean="(bindings ≥ 0) ∧ (result ≥ 0)" smt="(assert (and (>= bindings 0) (>= result 0)))"
func buildBindingJson*(bindings: seq[SolverBinding]): JsonNode =
  result = newJObject()
  for binding in bindings:
    result[binding.name] = newJString(binding.value)

## Binding Value.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
# @axiom-hint: lean=".() ∧ JString ∧ JInt ∧ JFloat ∧ JBool ∧ key.length ≥ 0 ∧ defaultValue.length ≥ 0" smt="(assert (and (. ) JString JInt JFloat JBool (>= (str.len key) 0) (>= (str.len defaultValue) 0)))"
func bindingValue*(bindings: JsonNode; key: string; defaultValue: string): string =
  if bindings.kind != JObject or not bindings.hasKey(key):
    return defaultValue
  let value = bindings[key]
  case value.kind
  of JString:
    value.getStr()
  of JInt:
    $value.getInt()
  of JFloat:
    $value.getFloat()
  of JBool:
    if value.getBool(): "true" else: "false"
  else:
    defaultValue

# @axiom-hint: lean="trimmed.length = 0 ∧ JString ∧ JInt ∧ JFloat ∧ JBool ∧ result ∧ trimmed.length = 0 → result = result ∧ (result ≥ 0) ∧ (parsed ≥ 0)" smt="(assert (and (= (str.len trimmed) 0) JString JInt JFloat JBool result (=> (= (str.len trimmed) 0) (= result result)) (>= result 0) (>= parsed 0)))"
proc extractBindingsFromFallback*(fallbackJson: string): JsonNode {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = newJObject()
  let trimmed = fallbackJson.strip()
  if trimmed.len == 0:
    return result
  try:
    let parsed = effect_shim.safeParseJson(trimmed)
    if parsed.kind == JObject:
      for key, value in parsed:
        case value.kind
        of JString:
          result[key] = newJString(value.getStr())
        of JInt:
          result[key] = newJString($value.getInt())
        of JFloat:
          result[key] = newJString($value.getFloat())
        of JBool:
          result[key] = newJString(if value.getBool(): "true" else: "false")
        else:
          result[key] = newJString($value)
      return result
  except CatchableError:
    discard  # best-effort  # axiom:best-effort(ioboundary catch)

# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func hasVersionTransition*(translation: UniversalTranslation): bool =
  for entry in translation.ilEntries:
    let tokens = tokenizeLowered(entry.il)
    if "version" in tokens:
      return true
  false
{.pop.}
