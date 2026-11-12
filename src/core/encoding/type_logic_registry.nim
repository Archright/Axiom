## type_logic_registry.nim — Type-to-Logic Registry (Runtime)
##
## Loads type mapping metadata from src/generated/type_registry_metadata.json
## (generated at build time by bin/hermetic_build).
## Provides SSOT for Nim type → SMT sort / Lean type / result constraint mapping.
##
## Replaces ad-hoc mappings in:
##   - smart_search.nim:elemBoundaryConstraints
##   - smt_hint_validation.nim:nimTypeToSmtType
##   - contract_ast_extractor.nim:rule7_resultAssignment
##
## NOTE: This module uses regular `var` (not threadvar) because the Axiom CLI
## is single-threaded. The registry is write-once-read-many — loaded once at
## startup, then read-only for all subsequent lookups.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/json
import std/tables
import std/strutils
{.push raises: [].}

type
  TypeLogicEntry* = object
    nimType*: string            ## Canonical Nim type pattern (e.g., "Option[T]", "void")
    category*: string           ## "numeric", "string", "bool", "option", "result", "seq", "void", "object", "float"
    smtSort*: string            ## SMT-LIB2 sort (e.g., "Int", "String", "(Option T_sort)")
    leanType*: string           ## Lean 4 type expression
    resultConstraintTemplate*: string  ## SMT constraint template for result ("" = no constraint)
    ignorable*: bool            ## void: @axiom-hint itself should be ignored
    negativeConstraints*: seq[string]  ## Explicitly forbidden patterns for LLM prompts

  TypeCheckResult* = object
    valid*: bool
    error*: string
    allowedConstraints*: string

var
  registry: Table[string, TypeLogicEntry]
  typeMapping: Table[string, TypeLogicEntry]
  registryLoaded: bool = false

const DefaultTypeLogicEntry* = TypeLogicEntry(
  nimType: "unknown",
  category: "unknown",
  smtSort: "Int",
  leanType: "Int",
  resultConstraintTemplate: "",
  ignorable: false,
  negativeConstraints: @[]
)

proc loadFromMetadata*(path: string) {.raises: [CatchableError].} =
  ## Load type registry from build-time generated JSON.
  ## Called once at startup.
  if registryLoaded: return
  let jsonNode = parseFile(path)

  # Load per-function entries (keyed by returnType for type-logic lookup)
  if jsonNode.hasKey("entries"):
    for entry in jsonNode["entries"]:
      let returnType = entry{"returnType"}.getStr("")
      if returnType.len == 0: continue
      registry[returnType] = TypeLogicEntry(
        nimType: returnType,
        category: entry{"typeCategory"}.getStr("unknown"),
        smtSort: entry{"smtSort"}.getStr("Int"),
        leanType: entry{"leanType"}.getStr("Int"),
        resultConstraintTemplate: entry{"resultConstraintTemplate"}.getStr(""),
        ignorable: entry{"ignorable"}.getBool(false),
        negativeConstraints: block:
          var nc: seq[string] = @[]
          if entry.hasKey("negativeConstraints"):
            for item in entry["negativeConstraints"]:
              nc.add(item.getStr())
          nc
      )

  # Load type mapping table
  if jsonNode.hasKey("typeMapping"):
    for typeName, mapping in jsonNode["typeMapping"]:
      typeMapping[typeName] = TypeLogicEntry(
        nimType: typeName,
        category: mapping{"category"}.getStr("unknown"),
        smtSort: mapping{"smtSort"}.getStr("Int"),
        leanType: mapping{"leanType"}.getStr("Int"),
        resultConstraintTemplate: mapping{"resultConstraintTemplate"}.getStr(""),
        ignorable: mapping{"ignorable"}.getBool(false),
        negativeConstraints: block:
          var nc: seq[string] = @[]
          if mapping.hasKey("negativeConstraints"):
            for item in mapping["negativeConstraints"]:
              nc.add(item.getStr())
          nc
      )

  registryLoaded = true

proc isLoaded*: bool {.raises: [].} =
  registryLoaded

proc lookupTypeLogic*(nimType: string): TypeLogicEntry {.raises: [].} =
  ## Look up type logic entry. Tries:
  ## 1. Exact match in per-function registry
  ## 2. Exact match in type mapping table
  ## 3. Generic unwrapping (Option[JsonNode] → Option[T])
  ## 4. Default (unknown)
  let canonical = strip(nimType)
  result = registry.getOrDefault(canonical, DefaultTypeLogicEntry)
  if result.nimType != "unknown": return

  result = typeMapping.getOrDefault(canonical, DefaultTypeLogicEntry)
  if result.nimType != "unknown": return

  # Try generic unwrapping: "Option[JsonNode]" → "Option[T]"
  let bracketPos = canonical.find('[')
  if bracketPos > 0:
    let baseType = canonical[0..<bracketPos]
    let genericKey = baseType & "[T]"
    result = typeMapping.getOrDefault(genericKey, DefaultTypeLogicEntry)
    if result.nimType != "unknown": return
    # Also try just the base type
    result = typeMapping.getOrDefault(baseType, DefaultTypeLogicEntry)
    if result.nimType != "unknown": return

  result = DefaultTypeLogicEntry

func canonicalizeType*(nimType: string): string {.raises: [].} =
  ## Normalize Nim type for registry lookup.
  ## Strips var/ref/ptr/sink/out/lent prefixes.
  result = nimType.strip()
  for prefix in ["var ", "ref ", "ptr ", "sink ", "out ", "lent "]:
    if result.startsWith(prefix):
      result = result[prefix.len..^1]
  result = result.strip()

proc isNumericType*(nimType: string): bool {.raises: [].} =
  lookupTypeLogic(nimType).category == "numeric"

proc isVoidType*(nimType: string): bool {.raises: [].} =
  let cat = lookupTypeLogic(nimType).category
  cat == "void" or nimType.strip() in ["", "void"]

proc isIgnorable*(nimType: string): bool {.raises: [].} =
  lookupTypeLogic(nimType).ignorable or isVoidType(nimType)

func hasNumericResultConstraint*(smtConstraint: string): bool {.raises: [].} =
  ## Check if SMT constraint contains numeric comparison on result.
  let s = smtConstraint.strip()
  "(>= result 0)" in s or
  "(<= result 0)" in s or
  "(> result 0)" in s or
  "(< result 0)" in s or
  "(>= (str.len result) 0)" in s  # This is valid for string, not for others

proc validateHintTypeConsistency*(hintLean, hintSmt: string, returnType: string): TypeCheckResult {.raises: [].} =
  ## Validate that a hint is type-consistent with the function's return type.
  ## Used in the Closed-Loop Feedback cycle.
  let logic = lookupTypeLogic(returnType)

  if logic.ignorable and "result" in hintSmt:
    return TypeCheckResult(
      valid: false,
      error: "void function should not have result constraints; result does not exist in scope",
      allowedConstraints: "(none — result is not in scope for void functions)"
    )

  if logic.category != "numeric" and logic.category != "string" and
     hasNumericResultConstraint(hintSmt):
    # Disallow numeric constraints on non-numeric types
    # Exception: (>= (str.len result) 0) is valid for string
    if not (logic.category == "string" and "(str.len result)" in hintSmt):
      return TypeCheckResult(
        valid: false,
        error: "Numeric constraint '(>= result 0)' on non-numeric type: " & returnType &
               " (category: " & logic.category & ")",
        allowedConstraints: logic.resultConstraintTemplate
      )

  TypeCheckResult(valid: true, error: "", allowedConstraints: logic.resultConstraintTemplate)

proc getNegativeConstraints*(nimType: string): seq[string] {.raises: [].} =
  ## Get negative constraints for LLM prompt injection.
  lookupTypeLogic(nimType).negativeConstraints

proc getTypeCategory*(nimType: string): string {.raises: [].} =
  lookupTypeLogic(nimType).category

{.pop}
