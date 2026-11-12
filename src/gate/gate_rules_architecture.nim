import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import std/algorithm
import std/sequtils
import std/sets
import std/strutils
import std/tables

import core/domain_types
import core/domain_utils
import core/utils/text_utils
import gate/gate_rules_module_classifier
import gate/gate_rules_normalization
import ../core/trusted/axiom_pragmas

const
  maxUniqueResourceFanout = 3
  maxCallDepthThreshold = 5
  lowCohesionDomainThreshold = 3
  lowInterfaceUsageThreshold = 0.2
  maxArchitecturePenalty* = 0.95
  maxDependencyBudget = 5
  maxDryCheckGroupSize = 15
  maxDryCheckModuleSpan = 3
  lspViolationSignals = ["precondition_strengthened", "postcondition_weakened", "lsp_violation"]

proc hasCurrentVerifiedFingerprint(cert: FunctionCertificate): bool =
  isCertificateVerified(cert.status) and
    cert.fingerprint.len > 0 and
    cert.currentFingerprint.len > 0 and
    cert.fingerprint == cert.currentFingerprint

proc addArchitectureViolation*(
  gate: var ArchitecturePrinciplesGate;
  checkName: string;
  ruleId: string;
  severity: ArchitectureGateSeverity;
  message: string;
  affectedFunctions: seq[string];
  penalty: float
) {.raises: [], axiom: ["(assert (and ast_parse_failed_isolated (>= (str.len checkName) 0) (>= (str.len ruleId) 0) (>= (str.len message) 0) (>= (seq.len affectedFunctions) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len affectedFunctions))) (>= (str.len (seq.nth affectedFunctions i)) 0))) (>= (str.len checkName) 0) (>= (str.len ruleId) 0) (>= (str.len message) 0) (>= (seq.len affectedFunctions) 0) (forall ((affectedFunctionsIdx Int)) (=> (and (>= affectedFunctionsIdx 0) (< affectedFunctionsIdx (seq.len affectedFunctions))) (>= (str.len (seq.nth affectedFunctions affectedFunctionsIdx)) 0)))))", "ast_parse_failed_isolated ∧ checkName.length ≥ 0 ∧ ruleId.length ≥ 0 ∧ message.length ≥ 0 ∧ affectedFunctions.size ≥ 0 ∧ ∀ (i : Fin affectedFunctions.size), (affectedFunctions.get i).length ≥ 0 ∧ checkName.length ≥ 0 ∧ ruleId.length ≥ 0 ∧ message.length ≥ 0 ∧ affectedFunctions.size ≥ 0 ∧ (∀ (affectedFunctionsIdx : Fin affectedFunctions.size), (affectedFunctions.get affectedFunctionsIdx).length ≥ 0)"].} =
  let cleanAffected = affectedFunctions.filterIt(it.len > 0).deduplicate().sorted()
  case severity
  of agWarning:
    gate.violations.add(ArchitectureViolation(
      checkName: checkName,
      ruleId: ruleId,
      severity: severity,
      message: message,
      affectedFunctions: cleanAffected
    ))
    inc gate.warnings
  of agBlocking:
    gate.violations.add(ArchitectureViolation(
      checkName: checkName,
      ruleId: ruleId,
      severity: severity,
      message: message,
      affectedFunctions: cleanAffected
    ))
    gate.totalPenalty += max(0.0, penalty)
    inc gate.blockingFailures

proc mergeArchitecturePrinciplesGate*(
  left: ArchitecturePrinciplesGate;
  right: ArchitecturePrinciplesGate
): ArchitecturePrinciplesGate =
  result = ArchitecturePrinciplesGate(
    warnings: left.warnings + right.warnings,
    blockingFailures: left.blockingFailures + right.blockingFailures,
    totalPenalty: min(left.totalPenalty + right.totalPenalty, maxArchitecturePenalty),
    violations: left.violations & right.violations
  )

  ## axiom-smt: (assert (and (>= (seq.len certificates) 0)))
  ## axiom-lean: certificates.size ≥ 0
proc applyDryCheck(gate: var ArchitecturePrinciplesGate; certificates: seq[FunctionCertificate]) {.axiom, axiomImpl.} =
  var byFingerprint = initTable[string, seq[string]]()
  for cert in certificates:
    if not hasCurrentVerifiedFingerprint(cert) or cert.functionName.len == 0:
      continue
    byFingerprint.mgetOrPut(cert.fingerprint, @[]).add(qualifiedName(cert))
  for fingerprintGroup in byFingerprint.values:
    let deduped = fingerprintGroup.deduplicate().sorted()
    if deduped.len < 2:
      continue
    var modules = initHashSet[string]()
    for qn in deduped:
      let dotIdx = qn.find('.')
      if dotIdx >= 0:
        modules.incl(qn[0 ..< dotIdx])
      else:
        modules.incl(qn)
    if deduped.len > maxDryCheckGroupSize and modules.len > maxDryCheckModuleSpan:
      continue
    var pairLabels: seq[string] = @[]
    for i in 0 ..< deduped.len:
      for j in i + 1 ..< deduped.len:
        pairLabels.add(deduped[i] & " <-> " & deduped[j])
    gate.addArchitectureViolation(
      "DRY Check",
      "logic-duplication",
      agBlocking,
      "Duplicate fingerprint function pairs detected; logic duplication rate is high.",
      pairLabels,
      0.06
    )

  ## axiom-smt: (assert (and (>= (seq.len certificates) 0) (>= certificates 0)))
  ## axiom-lean: certificates.size ≥ 0 ∧ (certificates ≥ 0)
proc applyResourceFanoutCheck(gate: var ArchitecturePrinciplesGate; certificates: seq[FunctionCertificate]) {.axiom, axiomImpl.} =
  for cert in certificates:
    if cert.reason != "source-not-found" and normalizedResources(cert).len > maxUniqueResourceFanout:
      gate.addArchitectureViolation(
        "SoC Check",
        "resource-fanout",
        agBlocking,
        "A function's unique accessedResources exceeds " & $maxUniqueResourceFanout & ".",
        @[qualifiedName(cert)],
        0.04
      )

  ## axiom-smt: (assert (and (>= (seq.len certificates) 0) (> maxDepth maxCallDepthThreshold)))
  ## axiom-lean: certificates.size ≥ 0 ∧ maxDepth > maxCallDepthThreshold
proc applyCallDepthCheck(gate: var ArchitecturePrinciplesGate; certificates: seq[FunctionCertificate]) {.axiom, axiomImpl.} =
  let callGraph = buildQualifiedCallGraph(certificates)
  let maxDepth = computeMaxCallDepth(callGraph)
  if maxDepth > maxCallDepthThreshold:
    gate.addArchitectureViolation(
      "SoC Check",
      "call-depth",
      agBlocking,
      "Module call depth exceeds " & $maxCallDepthThreshold & " levels. maxDepth=" & $maxDepth,
      callGraph.keys.toSeq().sorted(),
      0.05
    )

  ## axiom-smt: (assert (and (>= (seq.len certificates) 0) (> (str.len prefix) 0) (>= certificates 0)))
  ## axiom-lean: certificates.size ≥ 0 ∧ prefix.length > 0 ∧ (certificates ≥ 0)
proc applyLowCohesionCheck(gate: var ArchitecturePrinciplesGate; certificates: seq[FunctionCertificate]) {.axiom, axiomImpl.} =
  for cert in certificates:
    var domains = initHashSet[string]()
    for resource in normalizedResources(cert):
      let prefix = parseDomainPrefix(resource)
      if prefix.len > 0:
        domains.incl(prefix)
    if domains.len >= lowCohesionDomainThreshold:
      gate.addArchitectureViolation(
        "CohesionAnalyzer",
        "srp-low-cohesion",
        agBlocking,
        "Violation: Low Cohesion / SRP - Function references " & $lowCohesionDomainThreshold & " or more domain prefixes.",
        @[qualifiedName(cert)],
        0.05
      )

  ## axiom-smt: (assert (and (< dotIdx 0) (not (= (str.len parts) 2)) (<= total 0) (and (> (str.len usedMethods) 0) (< usageRatio lowInterfaceUsageThreshold)) (= dotIdx i) (>= certificates 0) (>= dotIdx 0) (>= usedMethodsByClientProvider 0) (>= methodsByModule 0)))
  ## axiom-lean: dotIdx < 0 ∧ parts.length ≠ 2 ∧ total ≤ 0 ∧ usedMethods.length > 0 ∧ usageRatio < lowInterfaceUsageThreshold ∧ dotIdx = i ∧ (certificates ≥ 0) ∧ (dotIdx ≥ 0) ∧ (usedMethodsByClientProvider ≥ 0) ∧ (methodsByModule ≥ 0)
proc applyInterfaceUsageCheck(gate: var ArchitecturePrinciplesGate; certificates: seq[FunctionCertificate]) {.axiom, axiomImpl.} =
  var methodsByModule = initTable[string, HashSet[string]]()
  var usedMethodsByClientProvider = initTable[string, HashSet[string]]()
  for cert in certificates:
    if cert.functionName.len == 0 or string(cert.modulePath).len == 0:
      continue
    let provider = moduleStem(cert)
    if not methodsByModule.hasKey(provider):
      methodsByModule[provider] = initHashSet[string]()
    methodsByModule[provider].incl(cert.functionName)
  for cert in certificates:
    if isCliCompositionRoot(cert):
      continue
    let client = moduleStem(cert)
    for dep in cert.calls:
      var dotIdx = -1
      for i in 0 ..< dep.len:
        if dep[i] == '.':
          dotIdx = i
          break
      if dotIdx < 0:
        continue
      let provider = dep[0 ..< dotIdx]
      let methodName = dep[dotIdx + 1 .. ^1]
      let key = client & "->" & provider
      if not usedMethodsByClientProvider.hasKey(key):
        usedMethodsByClientProvider[key] = initHashSet[string]()
      usedMethodsByClientProvider[key].incl(methodName)
  for key, usedMethods in usedMethodsByClientProvider.pairs:
    let parts = key.split("->", maxsplit = 1)
    if parts.len != 2:
      continue
    let client = parts[0]
    let provider = parts[1]
    if not methodsByModule.hasKey(provider):
      continue
    let total = methodsByModule[provider].len
    if total <= 0:
      continue
    let usageRatio = usedMethods.len.float / total.float
    if usedMethods.len > 0 and usageRatio < lowInterfaceUsageThreshold:
      gate.addArchitectureViolation(
        "CohesionAnalyzer",
        "isp-low-usage",
        agBlocking,
        "Violation: Low Cohesion / ISP - Client interface usage rate is below " &
          $(lowInterfaceUsageThreshold * 100.0) & "%.",
        @[client & "->" & provider],
        0.04
      )

  ## axiom-smt: (assert (and (>= (seq.len certificates) 0)))
  ## axiom-lean: certificates.size ≥ 0
proc applyWriteOwnershipCheck(gate: var ArchitecturePrinciplesGate; certificates: seq[FunctionCertificate]) {.axiom, axiomImpl.} =
  var writerModulesByResource = initTable[string, HashSet[string]]()
  var writerFunctionsByResource = initTable[string, seq[string]]()
  for cert in certificates:
    if not isWriteFunction(cert):
      continue
    let moduleName = moduleStem(cert)
    for resource in normalizedMutations(cert):
      if not writerModulesByResource.hasKey(resource):
        writerModulesByResource[resource] = initHashSet[string]()
        writerFunctionsByResource[resource] = @[]
      writerModulesByResource[resource].incl(moduleName)
      writerFunctionsByResource[resource].add(qualifiedName(cert))
  for resource, modules in writerModulesByResource.pairs:
    if modules.len <= 1:
      continue
    gate.addArchitectureViolation(
      "SSOT Check",
      "write-resource-owner",
      agBlocking,
      "Write functions for a resource cross single module boundary: " & resource,
      writerFunctionsByResource[resource].deduplicate().sorted(),
      0.2
    )

proc applyDirectConcreteDependencyCheck(
  gate: var ArchitecturePrinciplesGate;
  certificates: seq[FunctionCertificate]
) {.raises: [CatchableError], axiom: ["(assert (and (>= (seq.len certificates) 0) (= abstractionSeen true) (>= certificates 0) (>= abstractionSeen 0)))", "certificates.size ≥ 0 ∧ abstractionSeen = true ∧ (certificates ≥ 0) ∧ (abstractionSeen ≥ 0)"].} =
  let modulePaths = buildModulePathMap(certificates)
  for cert in certificates:
    var concreteHits: seq[string] = @[]
    var abstractionSeen = false
    for dep in normalizedEntries(cert.calls):
      if isLikelyConcreteName(dep, modulePaths):
        concreteHits.add(dep)
      if isLikelyAbstractionName(dep, modulePaths):
        abstractionSeen = true
    for dep in normalizedEntries(cert.imports):
      if isLikelyConcreteName(dep, modulePaths):
        concreteHits.add(dep)
      if isLikelyAbstractionName(dep, modulePaths):
        abstractionSeen = true
    if concreteHits.len > 0 and not abstractionSeen:
      gate.addArchitectureViolation(
        "AbstractionGate",
        "dip-direct-concrete-dependency",
        agBlocking,
        "Violation: DIP - High-level module directly depends on concrete implementation without abstraction layer.",
        @[qualifiedName(cert)] & concreteHits.deduplicate(),
        0.05
      )

  ## axiom-smt: (assert (and (>= (str.len raw) 0)))
  ## axiom-lean: raw.length ≥ 0
proc containsAnySignal(raw: string; signals: openArray[string]): bool {.axiom, axiomImpl.} =
  ## Diagnostic pattern matching: checks if a diagnostic string contains
  ## known LSP violation signals using token-based matching.
  let tokens = tokenizeLowered(raw)
  for signal in signals:
    if signal in tokens:
      return true
  result = false

proc applyLspInvariantCheck(
  gate: var ArchitecturePrinciplesGate;
  certificates: seq[FunctionCertificate];
  directives: var seq[CertificateDirective]
  # axiom-smt: (assert (and (>= (seq.len certificates) 0) (> (str.len lspViolationFunctions) 0)))
  # axiom-lean: certificates.size ≥ 0 ∧ lspViolationFunctions.length > 0
) {.axiom, axiomImpl.} =
  var lspViolationFunctions: seq[string] = @[]
  for i in 0 ..< certificates.len:
    let cert = certificates[i]
    let signals = cert.constraints.join(" ").toLowerAscii() & " " &
      cert.reason.toLowerAscii() & " " &
      cert.selfHealingAsserts.join(" ").toLowerAscii()
    if containsAnySignal(signals, lspViolationSignals):
      directives.add(CertificateDirective(
        functionName: qualifiedName(certificates[i]),
        kind: cdkSetStatus,
        status: certRed,
        reason: "lsp-invariant-violation"
      ))
      lspViolationFunctions.add(qualifiedName(certificates[i]))
  if lspViolationFunctions.len > 0:
    gate.addArchitectureViolation(
      "RefinementInvariantCheck",
      "lsp-invariant-break",
      agBlocking,
      "Violation: LSP - Implementation violating parent invariant detected and locked as certRed.",
      lspViolationFunctions.deduplicate().sorted(),
      0.18
    )

## Apply Architecture Principles Gate.
  ## axiom-smt: (assert (and (>= (seq.len certificates) 0) (> budget maxDependencyBudget) (>= certificates 0)))
  ## axiom-lean: certificates.size ≥ 0 ∧ budget > maxDependencyBudget ∧ (certificates ≥ 0)
proc applyDependencyBudgetCheck(gate: var ArchitecturePrinciplesGate; certificates: seq[FunctionCertificate]) {.axiom, axiomImpl.} =
  for cert in certificates:
    if isDependencyBudgetBoundary(cert):
      continue
    let budget = normalizedEntries(cert.calls).len +
                 normalizedEntries(cert.imports).len +
                 normalizedResources(cert).len +
                 normalizedMutations(cert).len
    if budget > maxDependencyBudget:
      gate.addArchitectureViolation(
        "Coupling Check",
        "coupling-dependency-budget-exceeded",
        agBlocking,
        "Function references " & $budget & " external symbols (budget = " & $maxDependencyBudget & ").",
        @[qualifiedName(cert)],
        0.15
      )

proc applyArchitecturePrinciplesGate*(certificates: seq[FunctionCertificate]): GateDirectiveBundle[ArchitecturePrinciplesGate] {.raises: [CatchableError], axiom: ["(assert (and (>= result 0)))", "(result ≥ 0)"].} =
  result.gateResult = ArchitecturePrinciplesGate(
    warnings: 0,
    blockingFailures: 0,
    totalPenalty: 0.0,
    violations: @[]
  )
  applyDryCheck(result.gateResult, certificates)
  applyResourceFanoutCheck(result.gateResult, certificates)
  applyCallDepthCheck(result.gateResult, certificates)
  applyLowCohesionCheck(result.gateResult, certificates)
  applyInterfaceUsageCheck(result.gateResult, certificates)
  applyWriteOwnershipCheck(result.gateResult, certificates)
  applyDirectConcreteDependencyCheck(result.gateResult, certificates)
  applyLspInvariantCheck(result.gateResult, certificates, result.directives)
  applyDependencyBudgetCheck(result.gateResult, certificates)
  result.gateResult.totalPenalty = min(result.gateResult.totalPenalty, maxArchitecturePenalty)
{.pop.}

