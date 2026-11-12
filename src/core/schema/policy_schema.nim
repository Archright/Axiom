import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/[tables]
# ---------------------------------------------------------------------------
# Distinct types — semantic safety
# ---------------------------------------------------------------------------

type
  PolicyVersion* = distinct string
    ## Semantic version of a PolicySpec (e.g. "1.0.0").
func `$`*(v: PolicyVersion): string {.inline.} =
  string(v)
func `==`*(a, b: PolicyVersion): bool {.inline.} =
  string(a) == string(b)
func initPolicyVersion*(raw: string): PolicyVersion =
  PolicyVersion(raw)

# ---------------------------------------------------------------------------
# Gate enforcement mode
# ---------------------------------------------------------------------------
proc `$`*(v: PolicyVersion): string {.inline.} =
  string(v)
func parseGateMode*(s: string): GateMode {.raises: [].} =
  ## Parse a string into GateMode. Returns gmShadow on unknown input.
  case s
  of "shadow": gmShadow
  of "advisory": gmAdvisory
  of "enforce": gmEnforce
  else: gmShadow

# ---------------------------------------------------------------------------
# Policy enforcement level
# ---------------------------------------------------------------------------
func parsePolicyEnforcement*(s: string): PolicyEnforcement {.raises: [].} =
  ## Parse a string into PolicyEnforcement. Returns peWarn on unknown input.
  case s
  of "warn": peWarn
  of "error": peError
  of "halt": peHalt
  else: peWarn

# ---------------------------------------------------------------------------
# PolicyRule — single policy rule with selector and constraints
# ---------------------------------------------------------------------------
proc `==`*(a, b: PolicyVersion): bool {.inline.} =
  string(a) == string(b)
# ---------------------------------------------------------------------------
# Gate enforcement mode
# ---------------------------------------------------------------------------
type
  GateMode* = enum
    gmShadow      ## Log violations only; never block.
    gmAdvisory    ## Report violations; allow override.
    gmEnforce     ## Block on violation; no override.
type
  PolicyEnforcement* = enum
    peWarn     ## Emit warnings; never block.
    peError    ## Emit errors; gate may block.
    peHalt     ## Halt the pipeline on violation.
type
  PolicyRule* = object
    id*: string                          ## Unique rule identifier.
    description*: string                 ## Human-readable description.
    selector*: Table[string, string]     ## Key-value matching criteria.
    deny*: seq[string]                   ## Denied resources / actions.
    require*: seq[string]                ## Required resources / actions.
    priority*: int                       ## Higher = evaluated first.
# ---------------------------------------------------------------------------
# PolicySpec — collection of rules with enforcement config
# ---------------------------------------------------------------------------

type
  PolicySpec* = object
    version*: PolicyVersion              ## Schema version.
    rules*: seq[PolicyRule]              ## Ordered rule set.
    exemptions*: Table[string, seq[string]] ## gate ID -> exempt rule IDs.
    enforcement*: PolicyEnforcement      ## Global enforcement level.
# ---------------------------------------------------------------------------
# PolicyConfig — loaded policy bundle
# ---------------------------------------------------------------------------

type
  PolicyConfig* = object
    version*: PolicyVersion              ## Config schema version.
    spec*: PolicySpec                    ## The embedded policy spec.
    loadedAt*: string                    ## ISO-8601 timestamp of load.
    loadedFrom*: string                  ## File path the config was loaded from.
# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

func validatePolicyRule*(rule: PolicyRule): seq[string] =
  ## Validate a single PolicyRule. Returns empty seq on success.
  result = @[]
  if rule.id.len == 0:
    result.add("PolicyRule: id must not be empty")
  if rule.description.len == 0:
    result.add("PolicyRule '" & rule.id & "': description must not be empty")
  if rule.deny.len == 0 and rule.require.len == 0:
    result.add("PolicyRule '" & rule.id & "': must have at least one deny or require entry")
func validatePolicySpec*(spec: PolicySpec): seq[string] =
  ## Validate a PolicySpec. Returns seq[string] of error messages.
  ## Empty seq means valid.
  result = @[]

  if string(spec.version).len == 0:
    result.add("PolicySpec: version must not be empty")

  if spec.rules.len == 0:
    result.add("PolicySpec: must contain at least one rule")

  var seenIds: seq[string]
  for rule in spec.rules:
    # Validate individual rule
    let ruleErrors = validatePolicyRule(rule)
    for err in ruleErrors:
      result.add(err)

    # Check for duplicate rule IDs
    if rule.id in seenIds:
      result.add("PolicySpec: duplicate rule id '" & rule.id & "'")
    seenIds.add(rule.id)

  # Validate exemptions reference existing rule IDs
  for gateId, exemptIds in spec.exemptions:
    for eid in exemptIds:
      var found = false
      for rule in spec.rules:
        if rule.id == eid:
          found = true
          break
      if not found:
        result.add("PolicySpec: exemption rule '" & eid & "' in gate '" & gateId & "' does not match any rule")
func validatePolicyConfig*(config: PolicyConfig): seq[string] =
  ## Validate a PolicyConfig. Returns seq[string] of error messages.
  result = @[]

  if string(config.version).len == 0:
    result.add("PolicyConfig: version must not be empty")
  if config.loadedAt.len == 0:
    result.add("PolicyConfig: loadedAt must not be empty")
  if config.loadedFrom.len == 0:
    result.add("PolicyConfig: loadedFrom must not be empty")

  # Delegate to spec validation
  let specErrors = validatePolicySpec(config.spec)
  for err in specErrors:
    result.add("PolicyConfig.spec: " & err)
{.pop.}
