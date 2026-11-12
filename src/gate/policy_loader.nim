import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Policy Loader — Load and validate policy_schema.json (SSOT).
##
## Provides API to query rules for a gate ID and validate policy structure.
## Pure query functions use ``func``; file I/O uses ``proc``.
##
## Usage:
##   import gate/policy_loader
##   let policy = loadPolicy()
##   let rules = policy.getRulesForGate("intent-gate")

import std/json
import std/os
import core/utils/repo_root
import core/trusted/axiom_pragmas

type
  LogRotation* = object
    maxSizeMB*: int
    maxFiles*: int

  GateConfig* = object
    bypassTokenEnv*: string
    logPath*: string
    rotation*: LogRotation

  PolicyRule* = object
    id*: string
    description*: string
    severity*: string          ## "error" | "warning" | "info"
    filesPattern*: string
    gateIds*: seq[string]      ## gates that enforce this rule

  GatePolicy* = object
    gateConfig*: GateConfig
    rules*: seq[PolicyRule]

# ---------------------------------------------------------------------------
# Pure query functions (func) — no I/O, no exceptions
# ---------------------------------------------------------------------------

func getRulesForGate*(policy: GatePolicy, gateId: string): seq[PolicyRule] =
  ## Returns all rules whose gateIds contain ``gateId``.
  result = @[]
  for rule in policy.rules:
    if gateId in rule.gateIds:
      result.add(rule)

func getAllRuleIds*(policy: GatePolicy): seq[string] =
  ## Returns every rule id in the policy.
  result = @[]
  for rule in policy.rules:
    result.add(rule.id)

func hasRule*(policy: GatePolicy, ruleId: string): bool =
  ## Checks if a rule with the given id exists.
  for rule in policy.rules:
    if rule.id == ruleId:
      return true
  false

func getSeverity*(policy: GatePolicy, ruleId: string): string =
  ## Returns the severity of a rule, or "" if not found.
  for rule in policy.rules:
    if rule.id == ruleId:
      return rule.severity
  ""

func ruleCount*(policy: GatePolicy): int =
  ## Number of rules in the policy.
  policy.rules.len

# ---------------------------------------------------------------------------
# I/O boundary — file reads only
# ---------------------------------------------------------------------------

proc parseGateConfig(node: JsonNode): GateConfig  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Parse gateConfig section from JSON node.
  result.bypassTokenEnv = node["bypassTokenEnv"].getStr()
  result.logPath = node["logPath"].getStr()
  let rot = node["rotation"]
  result.rotation.maxSizeMB = rot["maxSizeMB"].getInt()
  result.rotation.maxFiles = rot["maxFiles"].getInt()

proc parsePolicyRule(node: JsonNode): PolicyRule  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Parse a single rule from JSON node.
  result.id = node["id"].getStr()
  result.description = node["description"].getStr()
  result.severity = node["severity"].getStr()
  result.filesPattern = node["filesPattern"].getStr()
  if node.hasKey("gateIds"):
    for gid in node["gateIds"]:
      result.gateIds.add(gid.getStr())

proc loadPolicyFromJson*(root: string): GatePolicy {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load and validate policy_schema.json from the given project root.
  ## Raises IOError if file is missing, ValueError if structure is invalid.
  let policyPath = root / "src" / "gate" / "policy_schema.json"
  if not fileExists(policyPath):
    raise newException(IOError, "Policy schema not found: " & policyPath)

  let content = readFile(policyPath)
  let node = parseJson(content)

  if not node.hasKey("gateConfig"):
    raise newException(ValueError, "policy_schema.json missing 'gateConfig'")
  if not node.hasKey("rules"):
    raise newException(ValueError, "policy_schema.json missing 'rules'")

  result.gateConfig = parseGateConfig(node["gateConfig"])

  for ruleNode in node["rules"]:
    result.rules.add(parsePolicyRule(ruleNode))

proc loadPolicy*(): GatePolicy =
  ## Load policy_schema.json using auto-detected project root.
  let root = findRepoRoot()
  result = loadPolicyFromJson(root)

when isMainModule:
  ## Excluded from aggregated nim check to avoid UnusedImport warnings.
  let p {.used.} = loadPolicy()

{.pop.}
