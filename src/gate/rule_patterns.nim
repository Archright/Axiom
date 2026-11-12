import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Declarative architecture rule patterns using fusion/matching.
##
## Replaces imperative for-loops in ast_architecture_gate.nim with
## pattern-matched rule definitions. Each rule is a single `case`
## expression that matches facts against violation patterns.

import fusion/matching, tables
{.pop.}
import std/strutils
import gate/architecture_ast_facts
import core/gate/architecture_policy
import core/trusted/axiom_pragmas_lite

type
  ArchitectureViolationArtifact* = object
    rule*: string
    detail*: string
    files*: seq[string]
    severity*: string

# ---------------------------------------------------------------------------
# Rule: SoC — Layer Edge Violations
# ---------------------------------------------------------------------------

proc checkLayerEdges*(
  result: var seq[ArchitectureViolationArtifact];
  policy: ArchitecturePolicy;
  facts: ModuleFacts;
  importTargetPath: proc(policy: ArchitecturePolicy; importExpr: string; currentFile: string): string {.raises: [].}
) {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  let sourceLayer = policy.layerForPath(facts.path)
  if sourceLayer.len == 0:
    return

  for importFact in facts.imports:
    case importFact:
    of ImportFact(modulePath: @rawModule, location: SourceLocation(line: @ln, column: @col)):
      let targetPath = importTargetPath(policy, rawModule, facts.path)
      if targetPath.len == 0:
        continue
      let targetLayer = policy.layerForPath(targetPath)
      if targetLayer.len == 0:
        continue
      if sourceLayer != targetLayer and targetLayer notin policy.allowedLayersFor(sourceLayer):
        result.add(ArchitectureViolationArtifact(
          rule: "SoC",
          detail: facts.path & ":" & $ln & ":" & $col &
            " imports from forbidden layer " & targetLayer & ": " & rawModule,
          files: @[facts.path],
          severity: "error"))

# ---------------------------------------------------------------------------
# Rule: SSOT — Forbidden Field Assignments
# ---------------------------------------------------------------------------

proc checkForbiddenAssignments*(
  result: var seq[ArchitectureViolationArtifact];
  policy: ArchitecturePolicy;
  facts: ModuleFacts
) {.raises: [].} =
  let forbiddenTargets = policy.forbiddenAssignmentsFor(facts.path)
  if forbiddenTargets.len == 0:
    return

  for assignment in facts.assignments:
    case assignment:
    of AssignmentFact(targetPath: @target, location: SourceLocation(line: @ln, column: @col)):
      if target in forbiddenTargets:
        if not policy.isAssignmentOwner(target, facts.path):
          result.add(ArchitectureViolationArtifact(
            rule: "SSOT",
            detail: facts.path & ":" & $ln & ":" & $col &
              " assigns policy-owned field " & target,
            files: @[facts.path],
            severity: "error"))

# ---------------------------------------------------------------------------
# Rule: SSOT — Type Placement Ownership
# ---------------------------------------------------------------------------

proc checkSsotTypePlacement*(
  result: var seq[ArchitectureViolationArtifact];
  policy: ArchitecturePolicy;
  facts: ModuleFacts
) {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  if policy.layerForPath(facts.path) == "Test":
    return

  for typeDef in facts.typeDefs:
    case typeDef:
    of TypeDefFact(name: @typeName, location: SourceLocation(line: @ln, column: @col)):
      if policy.ssotTypes.hasKey(typeName):
        let owner = policy.ssotTypes.getOrDefault(typeName, "")
        if owner.len > 0 and facts.path != owner:
          result.add(ArchitectureViolationArtifact(
            rule: "SSOT",
            detail: facts.path & ":" & $ln & ":" & $col &
              " defines SSOT type " & typeName & "; canonical owner is " & owner,
            files: @[facts.path, owner],
            severity: "error"))

# ---------------------------------------------------------------------------
# Rule: SSOT — Ratio Construction Ownership (no ad-hoc ratio math in CLI)
# ---------------------------------------------------------------------------

proc checkRatioOwnerViolations*(
  result: var seq[ArchitectureViolationArtifact];
  policy: ArchitecturePolicy;
  facts: ModuleFacts
) {.raises: [].} =
  ## CLI presentation layer must not construct verified/total ratios with
  ## ad-hoc division; every ratio assignment must flow through the SSOT
  ## factories (initKernelRatio / initAsiRatio). Enforces the metrics.nim
  ## contract "No ad-hoc ASI math in CLI, TUI, or API layers".
  if not facts.path.startsWith("src/cli"):
    return

  const ratioMarks = ["verified", "netVerified", "cumulativeVerified",
                      "verifiedCount", "passCount", "kernelVerified",
                      "netVerifiedFunctions", "total", "totalSrcFuncs",
                      "totalProcessed", "attempted", "kernelTotal"]

  for division in facts.divisions:
    if division.insideFactory:
      continue
    var hasRatioMark = false
    for m in ratioMarks:
      if m in division.text:
        hasRatioMark = true
        break
    if not hasRatioMark:
      continue
    result.add(ArchitectureViolationArtifact(
      rule: "SSOT",
      detail: facts.path & ":" & $division.location.line & ":" &
        $division.location.column &
        " performs ad-hoc ratio division in CLI layer; route through initKernelRatio/initAsiRatio",
      files: @[facts.path],
      severity: "error"))

# ---------------------------------------------------------------------------
# Rule: SOLID — Forbidden Concrete Calls (DIP)
# ---------------------------------------------------------------------------

proc checkForbiddenCalls*(
  result: var seq[ArchitectureViolationArtifact];
  policy: ArchitecturePolicy;
  facts: ModuleFacts
) {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  let forbidden = policy.forbiddenCallsFor(facts.path)
  if forbidden.len == 0:
    return

  for call in facts.calls:
    case call:
    of CallFact(callee: @callee, qualifiedCallee: @qualified, location: SourceLocation(line: @ln, column: @col)):
      let matched = if callee in forbidden: callee elif qualified in forbidden: qualified else: ""
      if matched.len > 0:
        if not policy.hasModuleRole(facts.path, "solver-backend-owner") and
           not policy.hasModuleRole(facts.path, "solver-composition-owner"):
          result.add(ArchitectureViolationArtifact(
            rule: "SOLID",
            detail: facts.path & ":" & $ln & ":" & $col &
              " calls concrete backend " & matched & "; use abstraction boundary",
            files: @[facts.path],
            severity: "error"))

