import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/policy/architecture_policy_types
import std/algorithm
import std/strutils
import std/tables
func sortedStrings*(values: seq[string]): seq[string] {.raises: [].} =
  result = values
  result.sort(system.cmp[string])
func quoteTrim*(value: string): string {.raises: [].} =
  let trimmed = value.strip()
  if trimmed.len >= 2 and trimmed[0] == '"' and trimmed[^1] == '"':
    trimmed[1 .. ^2]
  else:
    trimmed
func parseStringArray*(value: string): tuple[ok: bool; values: seq[string]] {.raises: [].} =
  let trimmed = value.strip()
  if trimmed.len < 2 or trimmed[0] != '[' or trimmed[^1] != ']':
    return (false, @[])
  var inString = false
  var current = ""
  var values: seq[string] = @[]
  var i = 1
  while i < trimmed.len - 1:
    let ch = trimmed[i]
    if inString:
      if ch == '"' and (i == 0 or trimmed[i - 1] != '\\'):
        values.add(current)
        current = ""
        inString = false
      else:
        current.add(ch)
    else:
      case ch
      of ' ', '\t', ',': discard
      of '"': inString = true
      else: return (false, @[])
    inc i
  if inString:
    return (false, @[])
  (true, values)
func parseBoolValue*(value: string): tuple[ok: bool; value: bool] {.raises: [].} =
  let normalized = value.strip().toLowerAscii()
  if normalized == "true": return (true, true)
  if normalized == "false": return (true, false)
  (false, false)
func parseNatural*(value: string): tuple[ok: bool; value: int] {.raises: [].} =
  let trimmed = value.strip()
  if trimmed.len == 0:
    return (false, 0)
  var number = 0
  for ch in trimmed:
    if ch < '0' or ch > '9':
      return (false, 0)
    number = number * 10 + (ord(ch) - ord('0'))
  (true, number)
func isKnownSection*(section: string): bool {.raises: [].} =
  section in [
    "meta", "layer", "layer_edges", "module_roles", "ssot_types",
    "forbidden_calls", "forbidden_assignments", "allowed_assignment_owners",
    "dry", "surface_area", "canonical_computations", "interfaces", "opaque_types", "cohesion",
    "layer_limits", "external_packages", "forbidden_call_policies", "generated_modules", "module_overrides",
    "lcom_overrides",
    "tcc_overrides",
    "forbidden_call_patterns",
    "ocp_registries",
    "ocp_overrides",
    "forbidden_pragmas",
    "legacy_violations",
    "effect_hints",
    "effect_hints.functions",
    "debt_ceiling",
    "debt_metrics",
    "impure_procedures_whitelist",
    "gcsafe_approvals",
    "dag_enforcement",
    "facade_ratchet",
    "time_bounded_debt_500line",
    "memory_policy_markers"
  ]
func requiresArray*(section: string): bool {.raises: [].} =
  section in [
    "layer_edges", "module_roles",
    "forbidden_assignments", "allowed_assignment_owners"
  ]
func isValidLayerGlob*(value: string): bool {.raises: [].} =
  if value.len == 0: return false
  if ".." in value: return false
  if value.startsWith("src/") or value.startsWith("scripts/") or value.startsWith("tests/"):
    return true
  false
func addDiagnostic*(result: var ArchitecturePolicyParseResult; lineNo: int; message: string) {.raises: [].} =
  result.diagnostics.add("line " & $lineNo & ": " & message)
  result.ok = false
func putArray*(
  result: var ArchitecturePolicyParseResult;
  section: string;
  key: string;
  values: seq[string]
) {.raises: [].} =
  let canonicalValues = sortedStrings(values)
  case section
  of "layer": result.policy.layers[key] = canonicalValues
  of "layer_edges": result.policy.layerEdges[key] = canonicalValues
  of "module_roles": result.policy.moduleRoles[key] = canonicalValues
  of "forbidden_calls": result.policy.forbiddenCalls[key] = canonicalValues
  of "forbidden_assignments": result.policy.forbiddenAssignments[key] = canonicalValues
  of "allowed_assignment_owners": result.policy.allowedAssignmentOwners[key] = canonicalValues
  of "impure_procedures_whitelist":
    if key == "whitelist":
      result.policy.impureProceduresWhitelist = canonicalValues
  else: discard
{.pop.}
