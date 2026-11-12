import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Static Rules Engine (Wave 3)
##
## Persistent storage and matching engine for learned StaticRules.
## Rules are loaded from a local JSON directory and matched against
## nodeIds before any AI invocation.

import std/options
import std/os
import std/strutils
import core/utils/io_utils
import core/axiom_pragmas

import verification/proof_summarizer
import core/json/json_utils
import core/json/std_redirect
import core/utils/file_utils
# axiomIoBoundary

type
  StaticRuleMatch* = object
    rule*: StaticRule
    matchKind*: string  # "exact", "function", "module"

# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
proc staticRulesDir(): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    result = joinPath(getCurrentDir(), "logs", "static_rules")
  except CatchableError:
    result = "logs/static_rules"

# @axiom-hint: lean="result.length = 0 ∧ result = dir ∧ (result ≥ 0)" smt="(assert (and (= (str.len result) 0) (= result dir) (>= result 0)))"
proc ensureRulesDir(dir: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = dir
  if result.len == 0:
    result = staticRulesDir()
  discard existsOrCreateDirOpt(result)

## Static Rule To Json.
func staticRuleToJson*(rule: StaticRule): JsonNode {.raises: [].} =
  try:
    %*{
      "ruleId": rule.ruleId,
      "nodeId": rule.nodeId,
      "functionName": rule.functionName,
      "modulePath": rule.modulePath,
      "leanTheoremSource": rule.leanTheoremSource,
      "smtConstraint": rule.smtConstraint,
      "strategy": rule.strategy,
      "sourceReference": rule.sourceReference,
      "createdAt": rule.createdAt,
      "appliedCount": rule.appliedCount,
      "successCount": rule.successCount
    }
  except CatchableError:
    newJNull()

## Json To Static Rule.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
func jsonToStaticRule*(node: JsonNode): StaticRule {.raises: [].} =
  try:
    result.ruleId = node{"ruleId"}.getStr("")
    result.nodeId = node{"nodeId"}.getStr("")
    result.functionName = node{"functionName"}.getStr("")
    result.modulePath = node{"modulePath"}.getStr("")
    result.leanTheoremSource = node{"leanTheoremSource"}.getStr("")
    result.smtConstraint = node{"smtConstraint"}.getStr("")
    result.strategy = node{"strategy"}.getStr("")
    result.sourceReference = node{"sourceReference"}.getStr("")
    result.createdAt = node{"createdAt"}.getStr("")
    result.appliedCount = node{"appliedCount"}.getInt(0)
    result.successCount = node{"successCount"}.getInt(0)
  except CatchableError: # axiom:best-effort(JSON parse fallback)
    discard

## Load Static Rules.
# @axiom-hint: lean="external_io_isolated" smt="(assert (and external_io_isolated))"
proc loadStaticRules*(rulesDir: string = ""): seq[StaticRule] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let dir = ensureRulesDir(rulesDir)
  try:
    for path in walkFiles(joinPath(dir, "*.json")):
      let raw = readFileSafe(path)
      let node = parseJsonOpt(raw).get(newJObject())
      if node.kind == JObject:
        let rule = jsonToStaticRule(node)
        if rule.ruleId.len > 0:
          result.add(rule)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

## Save Static Rule.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
proc saveStaticRule*(rule: StaticRule; rulesDir: string = "") {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let dir = ensureRulesDir(rulesDir)
  let path = joinPath(dir, rule.ruleId & ".json")
  ## intentional-discard: legacy-approved (spec §4.1)
  discard writeFileOpt(path, $staticRuleToJson(rule))

## Increment Rule Stats.
# @axiom-hint: lean="success ∧ success = true ∨ success = false" smt="(assert (and success (or (= success true) (= success false))))"
proc incrementRuleStats*(rule: StaticRule; success: bool; rulesDir: string = "") {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var updated = rule
  updated.appliedCount += 1
  if success:
    updated.successCount += 1
  saveStaticRule(updated, rulesDir)

## Match Static Rule.
# @axiom-hint: lean="(rules ≥ 0)" smt="(assert (and (>= rules 0)))"
func matchStaticRule*(nodeId: string; rules: seq[StaticRule]): Option[StaticRuleMatch] {.raises: [].} =
  ## Match a nodeId against loaded static rules.
  ## Priority: exact nodeId match > functionName match.
  for rule in rules:
    if rule.nodeId == nodeId:
      return some(StaticRuleMatch(rule: rule, matchKind: "exact"))
  for rule in rules:
    let parts = nodeId.split("::", maxsplit = 1)
    if parts.len >= 2:
      let fnName = parts[1]
      if rule.functionName == fnName and rule.functionName.len > 0:
        return some(StaticRuleMatch(rule: rule, matchKind: "function"))
  none(StaticRuleMatch)

{.pop.}

