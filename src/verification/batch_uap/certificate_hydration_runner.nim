## Certificate Hydration Runner — Topological certificate hydration pre-pass.
##
## Extracted from loop_driver.nim to keep the main orchestration loop under
## the 500-line module limit. This module performs a single pass over the
## work plan and marks nodes as verified when a matching, valid certificate
## exists and all their dependencies are already verified.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError], tags: [TimeEffect, RootEffect].}

import std/os
import std/options
import std/tables
import core/sorter/sorter_core
import core/orchestrator/orchestrator_types
import core/orchestrator/orchestrator_request_types
import core/results
import core/trusted/trust_commit
import verification/certificate_hydration
import verification/unified_trajectory
import verification/batch_uap/private/types
import core/proof/source_fingerprint
import core/axiom_pragmas

proc runCertificateHydrationPrePass*(
  state: SorterState;
  plan: SorterPlan;
  requests: seq[OrchestrationProofRequest];
  report: var OrchestrationReport;
  progressSink: BatchUapProgressSink = nil
) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Scans existing certificates and hydrates verified nodes in topological
  ## order. Mutates ``report`` with hydrated node reports and updates the
  ## cache-hit counter. Skips nodes already verified by earlier phases.
  let certDir = joinPath(getCurrentDir(), "src", "verification", "certificates")
  let certs = scanCertificateDir(certDir)
  if certs.len == 0:
    return
  # The reference vault is a derived projection; the active TrustCommit journal
  # is the authority. A certificate may hydrate only when its own commit is
  # present in the journal that this run reads — otherwise a cert copied from
  # another state (or a fresh state) would be silently treated as current
  # evidence and never re-verified or journaled.
  let journalBase = activeJournalRoot(getCurrentDir())

  # Only nodes that actually have a certificate can be hydrated; build a
  # fast-membership set so the main loop skips the rest in O(1).
  var certNodeIds = initTable[string, bool]()
  for key in certs.keys:
    certNodeIds[key] = true

  # Build O(1) lookup tables to avoid O(n^2) scans in the main loop.
  var requestByNodeId = initTable[string, OrchestrationProofRequest]()
  for r in requests:
    requestByNodeId[sorterNodeIdString(r.nodeId)] = r
  var depsByNodeId = initTable[string, seq[SorterNodeId]]()
  for node in state.nodes:
    depsByNodeId[sorterNodeIdString(node.id)] = node.dependencyIds

  # Transitive-fingerprint cache: seed with request source codes, then reuse
  # across all hydration candidates to avoid repeated file reads.
  var sourceCache = initTable[string, string]()
  for r in requests:
    sourceCache[sorterNodeIdString(r.nodeId)] = computeStableSourceFingerprint(r.sourceCode)
  var transitiveMemo = initTable[string, string]()

  # Build initial verified-node set from vault hydration results
  var hydratedVerifiedNodes = initTable[string, bool]()
  for nr in report.nodeReports:
    if nr.status == orchestrationVerified:
      hydratedVerifiedNodes[sorterNodeIdString(nr.nodeId)] = true

  # Process work items in topological order (sorted by dependencyDepth).
  # Skip any node that has no certificate: it cannot be hydrated here.
  for item in plan.workItems:
    let nodeIdStr = sorterNodeIdString(item.nodeId)

    if not certNodeIds.hasKey(nodeIdStr):
      continue

    # Skip nodes already verified (by vault hydration or earlier certificate hydration)
    if hydratedVerifiedNodes.hasKey(nodeIdStr):
      continue

    # Find matching request for this node
    if not requestByNodeId.hasKey(nodeIdStr):
      continue
    let matchingReq = requestByNodeId[nodeIdStr]

    # Dependency gate: all dependencies must already be verified
    let nodeDeps = depsByNodeId.getOrDefault(nodeIdStr, @[])
    if not allDependenciesInVerifiedSet(nodeDeps, hydratedVerifiedNodes):
      continue

    # Attempt certificate hydration using transitive-closure fingerprint.
    let currentTf = computeTransitiveFingerprintWithCaches(
      state, nodeIdStr, sourceCache, transitiveMemo)
    let certOpt = findHydratableCertificate(certs, nodeIdStr, matchingReq, currentTf)
    if certOpt.isSome():
      let cert = certOpt.get()
      if cert.trustCommitId.len == 0 or
          readCommit(journalBase, cert.trustCommitId).isErr():
        logStage(skCertificate, nodeIdStr,
          "certificate-hydration skipped: journal commit absent", status=ssSkipped)
        continue
      report.nodeReports.add(OrchestrationNodeReport(
        nodeId: item.nodeId,
        status: orchestrationVerified,
        cacheHit: true,
        vaultPath: cert.certificatePath,
        evidenceLogJson: "CERTIFICATE-HYDRATION: " & cert.winningStrategy
      ))
      inc report.executionStats.cacheHitCount
      hydratedVerifiedNodes[nodeIdStr] = true
      logStage(skCertificate, nodeIdStr, "certificate-hydrated: " & cert.winningStrategy, status=ssSucceeded)
      if progressSink != nil:
        try:
          progressSink(nodeIdStr, "CERTIFICATE-HYDRATED")
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)

{.pop.}
