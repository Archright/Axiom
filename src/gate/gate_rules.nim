## Gate Rules — Read-Only Analysis Layer (Phase 2 Purified)
import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}
#
# All procs in this file take seq[FunctionCertificate] (read-only) and return
# GateDirectiveBundle[T] containing:
#   1. gateResult: the analysis result object
#   2. directives: seq[CertificateDirective] describing mutations to apply
#
# Actual mutation is performed by certificate_applier.nim (Infra layer).
# See: docs/history/phase2-gate-purity.md

import core/symbolic_types_expr
import std/os
import std/strutils
import std/tables
import core/parsers/safe_parsers
import core/results
import core/domain_types
import core/domain_utils
import core/symbolic/global_symbol_graph_types
import core/symbol_graph/global_symbol_graph_query
import gate/gate_rules_architecture
export gate_rules_architecture
import gate/gate_rules_normalization
export gate_rules_normalization
# import verification/proof_linkage — REMOVED: AxiomLinkageResult in core/types/domain_types
import core/gate/gate_evaluators

{.push raises: [].}

# ============================================================================
# Audit Trail Gate
# ============================================================================

func applyAuditTrailGate*(certificates: seq[FunctionCertificate]): GateDirectiveBundle[AuditTrailGate] =
  ## Audit Trail Gate: Verified certificates MUST record the winning strategy
  ## and retry count that led to their certification.
  result.gateResult = AuditTrailGate(violations: @[], blockingFailures: 0)
  for cert in certificates:
    if cert.status == certGreen:
      if cert.winningStrategy.len == 0:
        let qn = qualifiedName(cert)
        let violation = AuditTrailViolation(
          functionName: qn,
          ruleId: "audit-trail-missing",
          severity: agBlocking,
          message: "Verified certificate lacks winningStrategy audit trail"
        )
        result.gateResult.violations.add(violation)
        result.gateResult.blockingFailures += 1
        result.directives.add(CertificateDirective(
          functionName: qn,
          kind: cdkSetStatus,
          status: certRed,
          reason: "missing-audit-trail"
        ))

# ============================================================================
# Global Influence Gate Helpers
# ============================================================================

func applyStaleFingerprintCheck(
  gate: var GlobalInfluenceGate;
  cert: FunctionCertificate;
  currentHash: string;
  directives: var seq[CertificateDirective]
): bool =
  ## Rule 1: stale global graph fingerprint. Returns true if demoted.
  if cert.status != certGreen:
    return false
  let qn = qualifiedName(cert)
  if cert.globalGraphFingerprint.len > 0 and cert.globalGraphFingerprint != currentHash:
    let violation = GlobalInfluenceViolation(
      functionName: qn,
      ruleId: "global-graph-stale",
      severity: agBlocking,
      message: "Certificate global graph fingerprint does not match current graph",
      influencer: "",
      affectedNodes: @[qn],
      reason: "global-graph-stale"
    )
    gate.violations.add(violation)
    gate.blockingFailures += 1
    directives.add(CertificateDirective(
      functionName: qn,
      kind: cdkSetStatus,
      status: certRed,
      reason: "global-graph-stale"
    ))
    return true
  false

func applyRedDependencyCheck(
  gate: var GlobalInfluenceGate;
  cert: FunctionCertificate;
  certificates: seq[FunctionCertificate];
  directives: var seq[CertificateDirective]
): bool =
  ## Rule 2: dependency on certRed via call graph. Returns true if demoted.
  if cert.status != certGreen:
    return false
  let qn = qualifiedName(cert)
  for dep in cert.calls:
    for other in certificates:
      let otherQn = qualifiedName(other)
      if otherQn == dep or other.functionName == dep:
        if other.status == certRed:
          let violation = GlobalInfluenceViolation(
            functionName: qn,
            ruleId: "pending-by-dependency",
            severity: agBlocking,
            message: "Certificate depends on red node: " & dep,
            influencer: dep,
            affectedNodes: @[qn],
            reason: "pending-by-dependency:" & dep
          )
          gate.violations.add(violation)
          gate.blockingFailures += 1
          directives.add(CertificateDirective(
            functionName: qn,
            kind: cdkSetStatus,
            status: certRed,
            reason: "pending-by-dependency:" & dep
          ))
          return true
  false

func applyMissingGraphEntryCheck(
  gate: var GlobalInfluenceGate;
  cert: FunctionCertificate;
  graph: GlobalSymbolGraph;
  directives: var seq[CertificateDirective]
): bool =
  ## Rule 3: missing graph entry for a green cert. Returns true if demoted.
  if cert.status != certGreen:
    return false
  let qn = qualifiedName(cert)
  let inSourceTree = string(cert.modulePath).startsWith("src/") or
                     isAbsolute(string(cert.modulePath)) and string(cert.modulePath).contains("/src/")
  if inSourceTree and qn.len > 0 and not graph.symbols.hasKey(qn):
    let violation = GlobalInfluenceViolation(
      functionName: qn,
      ruleId: "isolated-unknown-scope",
      severity: agBlocking,
      message: "Verified certificate has no entry in global symbol graph",
      influencer: "",
      affectedNodes: @[qn],
      reason: "isolated-unknown-scope"
    )
    gate.violations.add(violation)
    gate.blockingFailures += 1
    directives.add(CertificateDirective(
      functionName: qn,
      kind: cdkSetStatus,
      status: certRed,
      reason: "isolated-unknown-scope"
    ))
    return true
  false

# ============================================================================
# Global Influence Gate
# ============================================================================

func applyGlobalInfluenceGate*(
  certificates: seq[FunctionCertificate];
  graph: GlobalSymbolGraph
): GateDirectiveBundle[GlobalInfluenceGate] =
  ## Global Influence Gate: Verified certificates must align with the current
  ## global symbol graph.
  result.gateResult = GlobalInfluenceGate(violations: @[], blockingFailures: 0)
  let currentHash = graphHash(graph)

  for cert in certificates:
    if applyStaleFingerprintCheck(result.gateResult, cert, currentHash, result.directives):
      continue
    if applyRedDependencyCheck(result.gateResult, cert, certificates, result.directives):
      continue
    discard applyMissingGraphEntryCheck(result.gateResult, cert, graph, result.directives)

# ============================================================================
# Type Integrity Gate
# ============================================================================

func applyTypeIntegrityGate*(certificates: seq[FunctionCertificate]): GateDirectiveBundle[TypeIntegrityGate] =
  ## Type Integrity Gate: Validates type constraints recorded on certificates.
  result.gateResult = TypeIntegrityGate(violations: @[], blockingFailures: 0)
  for cert in certificates:
    if cert.status != certGreen:
      continue
    let qn = qualifiedName(cert)
    for constraint in cert.constraints:
      if constraint.startsWith("range:"):
        let boundsStr = constraint[6..^1].strip
        let parts = boundsStr.split("..")
        if parts.len == 2:
          let loRes = safeParseInt(parts[0].strip)
          let hiRes = safeParseInt(parts[1].strip)
          if loRes.isErr or hiRes.isErr:
            continue
          let lo = loRes.get
          let hi = hiRes.get
          if lo > hi:
            let violation = TypeIntegrityViolation(
              functionName: qn,
              ruleId: "invalid-range",
              severity: agBlocking,
              message: "Invalid range bounds: " & boundsStr,
              affectedNodes: @[qn]
            )
            result.gateResult.violations.add(violation)
            result.gateResult.blockingFailures += 1
            result.directives.add(CertificateDirective(
              functionName: qn,
              kind: cdkSetStatus,
              status: certRed,
              reason: "invalid-range"
            ))
            break
      elif constraint.startsWith("type-mismatch:"):
        let detail = constraint[14..^1].strip
        let violation = TypeIntegrityViolation(
          functionName: qn,
          ruleId: "type-mismatch",
          severity: agBlocking,
          message: "Type mismatch: " & detail,
          affectedNodes: @[qn]
        )
        result.gateResult.violations.add(violation)
        result.gateResult.blockingFailures += 1
        result.directives.add(CertificateDirective(
          functionName: qn,
          kind: cdkSetStatus,
          status: certRed,
          reason: "type-mismatch:" & detail
        ))
        break

# ============================================================================
# Symbolic Invariant Gate
# ============================================================================

func applySymbolicInvariantGate*(
  certificates: seq[FunctionCertificate];
  cfgResults: Table[string, CfgAnalysisResult]
): GateDirectiveBundle[SymbolicInvariantGate] =
  ## Symbolic Invariant Gate: Any certGreen function with loops but no verified
  ## invariant is demoted to certRed.
  result.gateResult = SymbolicInvariantGate(violations: @[], blockingFailures: 0)
  for cert in certificates:
    if cert.status != certGreen:
      continue
    let qn = qualifiedName(cert)
    if not cfgResults.hasKey(qn):
      continue
    let cfgRes = cfgResults.getOrDefault(qn)
    if cfgRes.hasUnsupported:
      let violation = SymbolicInvariantViolation(
        functionName: qn,
        ruleId: "symbolic-unsupported",
        severity: agWarning,
        message: "Symbolic execution unsupported: " & cfgRes.unsupportedReason,
        affectedNodes: @[qn]
      )
      result.gateResult.violations.add(violation)
      continue
    if cfgRes.hasLoops:
      var hasInvariant = false
      for _ in cfgRes.loopInvariants.values:
        hasInvariant = true
        break
      if not hasInvariant:
        let violation = SymbolicInvariantViolation(
          functionName: qn,
          ruleId: "missing-loop-invariant",
          severity: agBlocking,
          message: "Function contains loops but no verified invariant",
          affectedNodes: @[qn]
        )
        result.gateResult.violations.add(violation)
        result.gateResult.blockingFailures += 1
        result.directives.add(CertificateDirective(
          functionName: qn,
          kind: cdkSetStatus,
          status: certRed,
          reason: "missing-loop-invariant"
        ))

# ============================================================================
# Axiom Linkage Gate
# ============================================================================

proc applyAxiomLinkageGate*(
  certificates: seq[FunctionCertificate];
  verifyLinkage: ProofLinkageCallback
): GateDirectiveBundle[ArchitecturePrinciplesGate] =
  ## Enforces hash-based linkage integrity for all certVerifiedAxiom certificates.
  result.gateResult = ArchitecturePrinciplesGate()

  for i in 0 ..< certificates.len:
    if certificates[i].status != certVerifiedAxiom:
      continue

    let cert = certificates[i]
    let linkage = verifyLinkage(cert)

    if not linkage.verified:
      let qn = qualifiedName(cert)
      result.directives.add(CertificateDirective(
        functionName: qn,
        kind: cdkSetStatus,
        status: certStale,
        reason: "Rule 10 (Axiom Linkage): " & linkage.reason
      ))
      result.directives.add(CertificateDirective(
        functionName: qn,
        kind: cdkSetLinkage,
        linkageVerified: false
      ))

      addArchitectureViolation(
        result.gateResult,
        "Axiom Linkage Integrity",
        "axiom-linkage-mismatch",
        agBlocking,
        qualifiedName(cert) & ": " & linkage.reason,
        @[qualifiedName(cert)],
        0.15
      )
    else:
      let qn = qualifiedName(cert)
      result.directives.add(CertificateDirective(
        functionName: qn,
        kind: cdkSetLinkage,
        linkageVerified: true
      ))
{.pop.}
{.pop.}
