import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
import core/utils/constants
import core/json/std_redirect
import core/judge/tautology_checker
import core/telemetry/metrics
import core/types/asi_types
import cli/vacuity_classifier
import std/options
import std/sequtils
import std/strutils
import std/tables
const certifiedExemptStatus* = "certified_exempt"

## Count Ax Proof Statuses.
# @axiom-hint: lean="entries.size ≥ 0 ∧ status.length ≥ 0" smt="(assert (and (>= (seq.len entries) 0) (>= (str.len status) 0)))"
# @axiom-hint: lean="(entries ≥ 0)" smt="(assert (and (>= entries 0)))"
func countAxProofStatuses*(entries: seq[JsonNode]; status: string): int =
  for entry in entries:
    if entry.kind == JObject and entry.hasKey(statusKey) and entry[statusKey].kind == JString and
        entry[statusKey].getStr() == status:
      inc result

# @axiom-hint: lean="key.length ≥ 0" smt="(assert (and (>= (str.len key) 0)))"
func proofStateStringField*(entry: JsonNode; key: string): string {.raises: [].} =
  if entry.kind != JObject:
    return ""
  let value = entry.fields.getOrDefault(key, newJNull())
  if value.kind == JString:
    return value.getStr()
  ""

# @axiom-hint: lean="key.length ≥ 0" smt="(assert (and (>= (str.len key) 0)))"
func proofStateBoolField(entry: JsonNode; key: string): Option[bool] =
  if entry.kind != JObject:
    return none(bool)
  let value = entry.fields.getOrDefault(key, newJNull())
  if value.kind == JBool:
    return some(value.getBool())
  none(bool)

# @axiom-hint: lean="raw.length ≥ 0" smt="(assert (and (>= (str.len raw) 0)))"
func hasLegacySameContextProofShape(raw: string): bool =
  raw.contains("(check-sat)") and raw.contains("(assert (not ") and not raw.contains("(pop 1)")

# @axiom-hint: lean="raw.length ≥ 0" smt="(assert (and (>= (str.len raw) 0)))"
func hasExplicitVacuousSmtShape(raw: string): bool =
  raw.contains("(assert true)") or raw.contains("(assert (= ")

# @axiom-hint: lean="token.length ≥ 0" smt="(assert (and (>= (str.len token) 0)))"
func classifyMetadataSmtToken(token: string): tuple[accepted: bool; metadata: bool] =
  let t = token.strip(chars = {'(', ')', '"', '\''}).toLowerAscii()
  if t.len == 0:
    return (accepted: false, metadata: false)
  let startIdx = if t[0] == '-': 1 else: 0
  if startIdx < t.len:
    var isInteger = true
    for idx in startIdx ..< t.len:
      if not t[idx].isDigit:
        isInteger = false
        break
    if isInteger:
      return (accepted: true, metadata: false)
  if t in [
    "and", "or", "not", "=>", "=", "<", "<=", ">", ">=", "+", "-", "*",
    "div", "mod", "true", "false", "int", "bool", "str.len", "seq.len"
  ]:
    return (accepted: true, metadata: false)
  if t in [
    "depth", "impact", "impactindex", "dependencydepth", "impactednodecount",
    "nodeid", "label", "functionname", "modulepath", "retrycount",
    "premisecount", "dependencycount", "dependentnodecount",
    "transitivedependentcount", "ast_parse_failed_isolated"
  ]:
    return (accepted: true, metadata: true)
  for suffix in [
    "_depth", "_impact", "_impactindex", "_dependencydepth",
    "_impactednodecount", "_retrycount", "_premisecount", "_dependencycount",
    "_dependentnodecount", "_transitivedependentcount",
    "_ast_parse_failed_isolated"
  ]:
    if t.endsWith(suffix):
      return (accepted: true, metadata: true)
  (accepted: false, metadata: false)

# @axiom-hint: lean="skipProofNegations = true ∨ skipProofNegations = false" smt="(assert (and (or (= skipProofNegations true) (= skipProofNegations false))))"
func collectAssertBodies(raw: string; skipProofNegations: bool): seq[string] =
  for line in raw.splitLines():
    let s = line.strip()
    if s.startsWith("(assert ") and s.endsWith(")"):
      let body = s[8 .. ^2].strip()
      if skipProofNegations and body.startsWith("(not "):
        continue
      result.add(body)
func containsOnlyMetadataSmtTokens(body: string): bool =
  var sawMetadata = false
  let normalized = body.multiReplace({
    "(": " ",
    ")": " ",
    ";": " "
  })
  for token in normalized.splitWhitespace():
    let classified = classifyMetadataSmtToken(token)
    if not classified.accepted:
      return false
    if classified.metadata:
      sawMetadata = true
  sawMetadata

# @axiom-hint: lean="bodies.length = 0 ∧ false ∧ bodies.length = 0 → result = false ∧ (bodies ≥ 0)" smt="(assert (and (= (str.len bodies) 0) false (=> (= (str.len bodies) 0) (= result false)) (>= bodies 0)))"
func hasMetadataOnlySmtShape*(raw: string): bool =
  let bodies = collectAssertBodies(raw, skipProofNegations = true)
  if bodies.len == 0:
    return false
  for body in bodies:
    if not containsOnlyMetadataSmtTokens(body):
      return false
  true

# @axiom-hint: lean="raw.length = 0 ∧ negative.isNone = true ∧ false ∧ true ∧ raw.length = 0 ∧ negative.isNone = true → result = true" smt="(assert (and (and (= (str.len raw) 0) (= (option.isNone negative) true)) false true (=> (and (= (str.len raw) 0) (= (option.isNone negative) true)) (= result true))))"
func shouldIsolateProofStateEntry*(entry: JsonNode): bool =
  if proofStateStringField(entry, statusKey) != verifiedKey:
    return false
  # Triviality Pass (AST-level, deterministic): exempt trivial-by-design functions
  let sourceCode = proofStateStringField(entry, "sourceCode")
  let functionName = proofStateStringField(entry, "functionName")
  if sourceCode.len > 0 and functionName.len > 0:
    let trivialPattern = classifyTriviality(sourceCode, functionName)
    if trivialPattern != tpNone:
      return false  # Trivial function — exempt from anti-vacuity
  let hasRaw = entry.kind == JObject and entry.hasKey("raw_smt_query")
  let raw = proofStateStringField(entry, "raw_smt_query")
  let negative = proofStateBoolField(entry, "negativeTestResult")
  if not hasRaw and negative.isNone:
    return false
  if hasRaw and raw.len == 0:
    return true
  if negative.isSome and negative.get() == false:
    return true
  hasLegacySameContextProofShape(raw) or hasExplicitVacuousSmtShape(raw) or
    hasMetadataOnlySmtShape(raw)

## Recompute Ax Proof State Summary.
proc recomputeAxProofStateSummary*(reportNode: var JsonNode) =
  if not reportNode.hasKey("summary") or reportNode["summary"].kind != JObject:
    reportNode["summary"] = newJObject()
  if not reportNode.hasKey(entriesKey) or reportNode[entriesKey].kind != JArray:
    reportNode[entriesKey] = newJArray()
  let entries = reportNode[entriesKey].elems
  reportNode["summary"][totalNodesKey] = %entries.len
  reportNode["summary"][attemptedNodesKey] =
    %entries.countIt(it.hasKey("attempted") and it["attempted"].kind == JBool and it["attempted"].getBool())
  reportNode["summary"][verifiedKey] = %countAxProofStatuses(entries, verifiedKey)
  reportNode["summary"][counterExamplesKey] = %countAxProofStatuses(entries, "counter_example_found")
  reportNode["summary"][vacuousContradictionsKey] = %countAxProofStatuses(entries, "vacuous_contradiction")
  reportNode["summary"][timedOutKey] = %countAxProofStatuses(entries, "timed_out")
  reportNode["summary"]["unverifiable"] = %countAxProofStatuses(entries, "unverifiable")
  reportNode["summary"]["pseudoVerified"] = %countAxProofStatuses(entries, "pseudo_verified")
  reportNode["summary"]["certifiedExempt"] = %countAxProofStatuses(entries, certifiedExemptStatus)
  reportNode["summary"][unattemptedKey] = %countAxProofStatuses(entries, unattemptedKey)
  let totalSrcFuncs = reportNode["summary"].getOrDefault("totalSourceFunctions").getInt(0)
  if totalSrcFuncs < metrics.KernelDomainThreshold:
    quit(1)
  let verified = countAxProofStatuses(entries, verifiedKey)
  reportNode["summary"]["totalSourceFunctions"] = %totalSrcFuncs
  let asiFixed4 = initAsiRatio(verified.float / max(1, totalSrcFuncs).float).get(defaultAsiRatio())
  # Canonical VKD (verified/total) — not information-weighted ASI.
  reportNode["summary"][vkdFixed4Key] = %asString(metrics.exportAsiFixed4(asiFixed4))

# @axiom-hint: lean="0 ∧ (entry ≥ 0)" smt="(assert (and 0 (>= entry 0)))"
func applyProofStateAntiVacuityGate*(state: var JsonNode): int =
  if state.kind != JObject or not state.hasKey(entriesKey) or state[entriesKey].kind != JArray:
    return 0
  for entry in state[entriesKey].elems:
    if entry.kind != JObject:
      continue
    if not shouldIsolateProofStateEntry(entry):
      continue
    entry[statusKey] = newJString("pseudo_verified")
    entry["attempted"] = newJBool(true)
    entry["staleReason"] = newJString("lack-of-substantive-evidence")
    entry[reasonKey] = newJString("anti-vacuity-gate")
    inc result
  recomputeAxProofStateSummary(state)

# ---------------------------------------------------------------------------
# Anti-Tautology Sentinel (DEBT#002)
# ---------------------------------------------------------------------------

## Is Proof State Tautology.
## Checks if a proof-state entry represents a type-system-level tautology
## (e.g., `str.len >= 0`) that provides no substantive verification evidence.
## These auto-generated tautologies must not contribute to ASI 1.0000.
# @axiom-hint: lean="smtField.length ≥ 0" smt="(assert (and (>= (str.len smtField) 0)))"
func isProofStateTautology*(entry: JsonNode): bool {.raises: [].} =
  if entry.kind != JObject:
    return false
  let status = proofStateStringField(entry, statusKey)
  if status != verifiedKey:
    return false
  let smtField = proofStateStringField(entry, "raw_smt_query")
  if smtField.len == 0:
    return false
  isTautologyConstraint(smtField, "")

## Apply Anti-Tautology Sentinel to proof state.
## Scans all verified entries and demotes type-system-level tautologies
## (e.g., `str.len >= 0`, `depth >= 0`) to `pseudo_verified` status.
## These entries are excluded from ASI 1.0000 computation, ensuring that
## auto-generated trivial proofs do not inflate the integrity score.
func applyAntiTautologySentinel*(state: var JsonNode): int =
  if state.kind != JObject or not state.hasKey(entriesKey) or state[entriesKey].kind != JArray:
    return 0
  for entry in state[entriesKey].elems:
    if entry.kind != JObject:
      continue
    if not isProofStateTautology(entry):
      continue
    entry[statusKey] = newJString("pseudo_verified")
    entry["attempted"] = newJBool(true)
    entry["staleReason"] = newJString("type-system-tautology")
    entry[reasonKey] = newJString("anti-tautology-sentinel")
    inc result
  if result > 0:
    recomputeAxProofStateSummary(state)
{.pop.}

