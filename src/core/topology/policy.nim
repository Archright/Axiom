## Topology Policy Parser
## AGENTS.md Topology Contract §Phase A
## Parses topology_policy.json into a typed structure.

import core/trusted/layer_declaration
axiomLayer "domain"
import core/results
import std/[json, strutils, tables]
{.push raises: [].}
# axiomIoBoundary

type
  TransitionalDetection* = object
    patterns*: seq[string]
    generalizedRule*: string

  PolicyDefaults* = object
    maxDirectoryFiles*: int
    allowTransitionalModules*: bool
    transitionalMaxAgeDays*: int
    collapseSingletons*: bool
    forbidEmptyDirectories*: bool
    transitionalDetection*: TransitionalDetection

  PolicyException* = object
    path*: string
    reason*: string
    collapseSingletons*: bool
    suppressAudit*: seq[string]
    suppressUntil*: string

  SeverityRules* = Table[string, string]

  TopologyPolicy* = object
    schema*: string
    namespaceUuid*: string
    defaults*: PolicyDefaults
    severityRules*: SeverityRules
    exceptions*: seq[PolicyException]

func parseSeverityRules*(j: JsonNode): SeverityRules =
  result = initTable[string, string]()
  if j.kind != JObject:
    return
  for key, val in j.pairs:
    result[key] = val.getStr("warning")

proc parseTopologyPolicy*(path: string): Result[TopologyPolicy, string] =
  let j =
    try: parseFile(path)
    except CatchableError as e:
      return err("topology policy unreadable: " & e.msg & " — failing closed per §0.9")
  try:
    if not j.hasKey("_schema") or j{"_schema"}.getStr("").len == 0:
      return err("topology policy corrupt: missing _schema — failing closed per §0.9")
    if not j.hasKey("defaults") or j{"defaults"}.kind != JObject:
      return err("topology policy corrupt: missing defaults — failing closed per §0.9")
  except CatchableError as e:
    return err("topology policy parse error: " & e.msg & " — failing closed per §0.9")
  var policy = TopologyPolicy(
    schema: j{"_schema"}.getStr,
    namespaceUuid: j{"namespace_uuid"}.getStr
  )
  policy.defaults.maxDirectoryFiles = j{"defaults"}{"max_directory_files"}.getInt
  policy.defaults.allowTransitionalModules = j{"defaults"}{"allow_transitional_modules"}.getBool
  policy.defaults.transitionalMaxAgeDays = j{"defaults"}{"transitional_max_age_days"}.getInt
  policy.defaults.collapseSingletons = j{"defaults"}{"collapse_singletons"}.getBool
  policy.defaults.forbidEmptyDirectories = j{"defaults"}{"forbid_empty_directories"}.getBool
  policy.defaults.transitionalDetection.patterns = @[]
  for p in j{"defaults"}{"transitional_detection"}{"patterns"}:
    policy.defaults.transitionalDetection.patterns.add(p.getStr)
  policy.defaults.transitionalDetection.generalizedRule =
    j{"defaults"}{"transitional_detection"}{"generalized_rule"}.getStr

  policy.severityRules = initTable[string, string]()
  if j.hasKey("severity_rules"):
    policy.severityRules = parseSeverityRules(j{"severity_rules"})

  policy.exceptions = @[]
  if j.hasKey("exceptions") and j{"exceptions"}.kind == JArray:
    for e in j{"exceptions"}:
      var suppressAudit: seq[string] = @[]
      if e.hasKey("suppress_audit"):
        for s in e{"suppress_audit"}:
          suppressAudit.add(s.getStr)
      var suppressUntil = ""
      if e.hasKey("suppress_until"):
        suppressUntil = e{"suppress_until"}.getStr
      policy.exceptions.add(PolicyException(
        path: e{"path"}.getStr,
        reason: e{"reason"}.getStr,
        collapseSingletons: e{"collapse_singletons"}.getBool,
        suppressAudit: suppressAudit,
        suppressUntil: suppressUntil
      ))
  ok(policy)

func findException*(policy: TopologyPolicy, dirPath: string): PolicyException =
  for ex in policy.exceptions:
    if dirPath.startsWith(ex.path):
      return ex
  result = PolicyException(path: "")

func isException*(policy: TopologyPolicy, dirPath: string): bool =
  for ex in policy.exceptions:
    if dirPath.startsWith(ex.path):
      return true
  return false

func getMaxDirectoryFiles*(policy: TopologyPolicy, dirPath: string): int =
  for ex in policy.exceptions:
    if dirPath.startsWith(ex.path):
      return -1  # unlimited
  return policy.defaults.maxDirectoryFiles

func getSeverity*(policy: TopologyPolicy, kind: string): string =
  policy.severityRules.getOrDefault(kind, "warning")

{.pop}
