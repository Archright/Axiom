import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

## Stage 03: Dependency & Influence Gate
## Global influence analysis and audit trail for influence violations.
# @module-role import-facade

import std/os
import std/tables
import core/domain_types
import core/symbolic/global_symbol_graph_types
import core/symbol_graph/global_symbol_graph_query
import verification/gate_rule_adapter
import verification/certificate_applier
import verification/state_manager
import core/trusted/axiom_pragmas
# axiomIoBoundary

func runInfluenceGate*(result: var VerificationReportSummary;
    graph: GlobalSymbolGraph) =
  result.currentGraphHash = graphHash(graph)
  result.symbolCount = len(graph.symbols)
  result.edgeCount = graph.edges.len
  let bundle = applyGlobalInfluenceGate(result.certificates, graph)
  result.globalInfluenceGate = bundle.gateResult
  applyDirectives(result.certificates, bundle.directives)
  result.totalTrustedFunctions = countSourceFunctions(graph)
  result.missingCertificates = max(0, result.totalTrustedFunctions -
      result.certificates.len)



proc runAuditInfluence*(result: var VerificationReportSummary;
    repoRoot: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## [WAVE_Z:auditInfluence] 8/14 Audit: global_influence events
  let auditPath = joinPath(repoRoot, "logs", "audit", "stream.jsonl")
  for violation in result.globalInfluenceGate.violations:
    discard appendGlobalInfluenceEvent(auditPath,
      influencer = violation.influencer,
      affectedNodes = violation.affectedNodes, demotionKind = "certRed",
      reason = violation.reason, astDiffCount = 0)



{.pop.}
