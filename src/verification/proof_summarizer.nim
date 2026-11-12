import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/crypto/hash_kernel
import std/options
import std/strutils
import std/times
import ../core/trusted/axiom_pragmas_lite
# axiomIoBoundary

type
  StaticRule* = object
    ruleId*: string
    nodeId*: string
    functionName*: string
    modulePath*: string
    leanTheoremSource*: string
    smtConstraint*: string
    strategy*: string
    sourceReference*: string
    createdAt*: string
    appliedCount*: int
    successCount*: int
proc hashNodeId(nodeId: string): string {.raises: [], axiom: ["(assert (and (>= (str.len nodeId) 0) (>= result 0) (>= h 0) (>= nodeId 0)))", "nodeId.length ≥ 0 ∧ (result ≥ 0) ∧ (h ≥ 0) ∧ (nodeId ≥ 0)"].} =
  ## Create a short deterministic hash for a nodeId to use as ruleId.
  result = "rule_" & sha256Hex(nodeId)
proc parseNodeId(nodeId: string): tuple[modulePath: string, functionName: string] {.raises: [], axiom: ["(assert (and (>= (str.len nodeId) 0) (>= result 0)))", "nodeId.length ≥ 0 ∧ (result ≥ 0)"].} =
  let parts = nodeId.split("::", maxsplit = 1)
  if parts.len >= 2:
    result = (modulePath: parts[0], functionName: parts[1])
  else:
    result = (modulePath: "", functionName: nodeId)

## I Smt Assert Line.
proc isSmtAssertLine*(line: string): bool {.raises: [].} =
  let normalized = line.strip()
  normalized.startsWith("(assert ") and normalized.endsWith(")")

## Normalize Smt Constraint.
proc normalizeSmtConstraint*(constraint: string): string {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  ## Vacuity ban: never normalize to (assert true).
  ## Returns empty string if no valid assertions are found.
  var assertionLines: seq[string] = @[]
  for line in constraint.splitLines():
    let normalized = line.strip()
    if normalized.len == 0:
      continue
    if not isSmtAssertLine(normalized):
      return ""
    assertionLines.add(normalized)
  if assertionLines.len == 0:
    ""
  else:
    assertionLines.join("\n")

## Smt Constraint From Assertion Lines.
proc smtConstraintFromAssertionLines*(source: string): string {.raises: [], axiom: ["(assert (and (>= (str.len source) 0)))", "source.length ≥ 0"].} =
  var assertionLines: seq[string] = @[]
  for line in source.splitLines():
    let normalized = line.strip()
    if isSmtAssertLine(normalized):
      assertionLines.add(normalized)
  normalizeSmtConstraint(assertionLines.join("\n"))
## Summarize Successful Proof.
# @axiom-hint: lean="leanSource.length = 0 ∨ nodeId.length = 0 ∧ normalizedSmtConstraint.length = 0 ∧ tacticTrace.length > 0 ∧ tacticSummary.length > 0 ∧ (tacticSummary ≥ 0) ∧ (∀ (tacticTraceIdx : Fin tacticTrace.size), (tacticTrace.get tacticTraceIdx).length ≥ 0)" smt="(assert (and (or (= (str.len leanSource) 0) (= (str.len nodeId) 0)) (= (str.len normalizedSmtConstraint) 0) (> (str.len tacticTrace) 0) (> (str.len tacticSummary) 0) (>= tacticSummary 0) (forall ((tacticTraceIdx Int)) (=> (and (>= tacticTraceIdx 0) (< tacticTraceIdx (seq.len tacticTrace))) (>= (str.len (seq.nth tacticTrace tacticTraceIdx)) 0)))))"
proc summarizeSuccessfulProof*(
  nodeId: string;
  leanSource: string;
  smtConstraint: string;
  tacticTrace: seq[string]
): Option[StaticRule] {.raises: [], axiom: ["(assert (and (or (= (str.len leanSource) 0) (= (str.len nodeId) 0)) (= (str.len normalizedSmtConstraint) 0) (> (str.len tacticTrace) 0) (> (str.len tacticSummary) 0) (>= tacticSummary 0) (forall ((tacticTraceIdx Int)) (=> (and (>= tacticTraceIdx 0) (< tacticTraceIdx (seq.len tacticTrace))) (>= (str.len (seq.nth tacticTrace tacticTraceIdx)) 0)))))", "leanSource.length = 0 ∨ nodeId.length = 0 ∧ normalizedSmtConstraint.length = 0 ∧ tacticTrace.length > 0 ∧ tacticSummary.length > 0 ∧ (tacticSummary ≥ 0) ∧ (∀ (tacticTraceIdx : Fin tacticTrace.size), (tacticTrace.get tacticTraceIdx).length ≥ 0)"].} =
  ## Convert a verified Lean 4 proof into a reusable StaticRule.
  if leanSource.len == 0 or nodeId.len == 0:
    return none(StaticRule)

  let (modulePath, functionName) = parseNodeId(nodeId)
  let ruleId = hashNodeId(nodeId & leanSource)
  let normalizedSmtConstraint = normalizeSmtConstraint(smtConstraint)
  # Vacuity ban: reject static rules with no valid SMT constraint
  if normalizedSmtConstraint.len == 0:
    return none(StaticRule)

  var tacticSummary = ""
  if tacticTrace.len > 0:
    tacticSummary = tacticTrace.join(", ")

  let sourceRef = if tacticSummary.len > 0:
    "Verified proof for " & nodeId & " [tactics: " & tacticSummary & "]"
  else:
    "Verified proof for " & nodeId

  let rule = StaticRule(
    ruleId: ruleId,
    nodeId: nodeId,
    functionName: functionName,
    modulePath: modulePath,
    leanTheoremSource: leanSource,
    smtConstraint: normalizedSmtConstraint,
    strategy: "staticRule",
    sourceReference: sourceRef,
    createdAt: now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
    appliedCount: 0,
    successCount: 1
  )
  some(rule)

{.pop.}

