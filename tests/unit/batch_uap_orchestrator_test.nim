## Integration test for batch_uap_orchestrator.nim — batch UAP pipeline.

import std/[unittest, tables, os, algorithm, json]
import cli/selection_state
import cli/wf_render
import core/crypto/hash_kernel
import core/orchestrator/orchestrator_types
import core/sorter/sorter_core
import core/topology/topology_engine
import core/proof/proof_budget
import core/trusted/verification_result_types
import verification/obligation/obligation_ir
import verification/batch_uap/ir_pipeline_runner
import verification/batch_uap/loop_depth_scheduler
import verification/batch_uap/loop_driver
import verification/batch_uap/stages

suite "BatchUapOrchestrator":
  test "runBatchUapOrchestration with empty requests returns empty report":
    let state = initSorterState(@[])
    let result = runBatchUapOrchestration(state, @[], "proof_vault")
    check result.orchestrationReport.nodeReports.len == 0
    check result.budget.gasUsed() == 0

  test "BatchUapReport contains budget info":
    let state = initSorterState(@[])
    let result = runBatchUapOrchestration(state, @[], "proof_vault")
    check result.budget.gasTotal == maxTotalSolverInvocations
    check result.budget.gasRemaining == maxTotalSolverInvocations

  test "runBatchUapOrchestration handles unmatched requests gracefully":
    let node = makeSorterNode("src/test.nim", "testFunc", sorterNodeId("src/test.nim::testFunc"), @[])
    let state = initSorterState(@[node])
    # Request with different nodeId — should be skipped
    let req = initOrchestrationProofRequest(
      nodeId = sorterNodeId("other::func"),
      sourceCode = "func func(): int = 1",
      stateValue = 100,
      inputDelta = 70
    )
    let result = runBatchUapOrchestration(state, @[req], "proof_vault")
    check result.budget.gasUsed() == 0

  test "BatchUapReport uapResults table is initially empty":
    let state = initSorterState(@[])
    let result = runBatchUapOrchestration(state, @[], "proof_vault")
    check result.uapResults.len == 0

suite "BatchUapOrchestrator — P4 disproof carve-out":
  ## A fatal pre-sieve block (the governed symbol is a template, so the
  ## pre-sieve verdict is `blocked_non_routine`) is a STRUCTURAL verdict, not
  ## a refutation: it must not swallow a P4-promoted, replay-confirmed
  ## disproof of an adopted claim. The vsDisproved terminal is the only path
  ## that marks a node failed, so a PRE-SIEVED report there would make a
  ## confirmed disproof structurally invisible to the exit rule.

  const blockedModule = "src/axiom_test_blocked_template.nim"
  const blockedFn = "axiomTestBlockedTemplate"

  proc blockedNodeIdStr(): string =
    blockedModule & "::" & blockedFn

  proc blockedState(): SorterState =
    let node = makeSorterNode(blockedModule, blockedFn,
      sorterNodeId(blockedNodeIdStr()), @[])
    initSorterState(@[node])

  proc blockedRequest(): OrchestrationProofRequest =
    initOrchestrationProofRequest(
      nodeId = sorterNodeId(blockedNodeIdStr()),
      sourceCode = "template " & blockedFn & "*(x: int): int =\n  x\n",
      stateValue = 100,
      inputDelta = 70
    )

  proc nodeStatus(report: OrchestrationReport): OrchestrationNodeStatus =
    ## The node's own terminal status. An absent report is a test failure,
    ## never a silent pass.
    for nr in report.nodeReports:
      if sorterNodeIdString(nr.nodeId) == blockedNodeIdStr():
        return nr.status
    raise newException(ValueError, "no node report for " & blockedNodeIdStr())

  test "fatally blocked node without a scoped disproof reports pre-sieved":
    let vault = getTempDir() / ("axiom_bvu_blocked_" & $getCurrentProcessId())
    let result = runBatchUapOrchestration(blockedState(), @[blockedRequest()], vault)
    check nodeStatus(result.orchestrationReport) == orchestrationPreSievedUnverifiable
    # A blocked node that never reaches a terminal attempts no obligations.
    check result.orchestrationReport.executionStats.obligationAttemptedCount == 0

  test "fatally blocked node with a scoped vsDisproved result reports failed":
    let vault = getTempDir() / ("axiom_bvu_disproof_" & $getCurrentProcessId())
    let disproof = IrPipelineResult(
      funcName: blockedFn,
      modulePath: blockedModule,
      verification: makeDisproved(smBMC, pkZ3Bmc, psBounded),
      obligationVerdict: ObligationVerdictInfo(kind: ogrGenerated, obligationCount: 1))
    let result = runBatchUapOrchestration(blockedState(), @[blockedRequest()], vault,
      preComputedIrResults = @[disproof])
    check nodeStatus(result.orchestrationReport) == orchestrationProofFailed
    # A carved-out node reaches the disproof terminal, so its generated
    # obligations ARE attempted: the P6 accounting must count them (the
    # pre-carve-out guard dropped them silently).
    check result.orchestrationReport.executionStats.obligationAttemptedCount == 1

suite "BatchUapOrchestrator — VS-1 parallel parity (disproof carve-out)":
  ## The SAME two-node input must produce identical node decisions, OGR
  ## attempt accounting, and status aggregation on the sequential path
  ## (workers=1) and on the threaded parallel path (workers=2, run twice —
  ## the taskIndex-reordered merge makes arrival order unobservable).
  ##
  ## Node A: fatally blocked template (blocked_non_routine) carrying a
  ## claim-scoped vsDisproved — the P4 disproof carve-out. The shared rule
  ## (stages.decidePreSieveNode) must route it to the FAILED terminal on
  ## BOTH lanes; a PRE-SIEVED report would make the confirmed disproof
  ## structurally invisible to the exit rule.
  ## Node B: a second fatally blocked template with NO scoped IR evidence —
  ## pinned to the shared rule's PRE-SIEVED branch. (A pipeline-reaching
  ## node is deliberately avoided: the per-unit budget/spacer/UAP region it
  ## enters is not lane-deterministic — a pre-existing gap outside VS-1's
  ## pre-sieve/blocked-decision scope.)
  ## Both nodes terminate at shared-rule terminals, so the fixture invokes
  ## no solver and stores no summary — fully deterministic, no cross-run
  ## contamination through the process-global summary cache.

  const vs1CarveModule = "src/axiom_test_blocked_template.nim"
  const vs1CarveFn = "axiomTestBlockedTemplate"
  const vs1PreModule = "src/axiom_test_parity_blocked.nim"
  const vs1PreFn = "axiomTestParityBlocked"

  proc vs1CarveNodeIdStr(): string =
    vs1CarveModule & "::" & vs1CarveFn

  proc vs1PreNodeIdStr(): string =
    vs1PreModule & "::" & vs1PreFn

  proc vs1State(): SorterState =
    ## Two independent nodes at the same dependency depth (no dependencies),
    ## so depthItems.len > 1 and the threaded parallel branch actually runs.
    initSorterState(@[
      makeSorterNode(vs1CarveModule, vs1CarveFn,
        sorterNodeId(vs1CarveNodeIdStr()), @[]),
      makeSorterNode(vs1PreModule, vs1PreFn,
        sorterNodeId(vs1PreNodeIdStr()), @[])])

  proc vs1Requests(): seq[OrchestrationProofRequest] =
    proc tplSrc(fnName: string): string =
      "template " & fnName & "*(x: int): int =\n  x\n"
    @[initOrchestrationProofRequest(
        nodeId = sorterNodeId(vs1CarveNodeIdStr()),
        sourceCode = tplSrc(vs1CarveFn),
        stateValue = 100, inputDelta = 70),
      initOrchestrationProofRequest(
        nodeId = sorterNodeId(vs1PreNodeIdStr()),
        sourceCode = tplSrc(vs1PreFn),
        stateValue = 100, inputDelta = 70)]

  proc vs1IrResults(): seq[IrPipelineResult] =
    ## ONLY the carve-out node carries scoped IR evidence: a P4-confirmed,
    ## replay-confirmed disproof with one generated obligation. The second
    ## node has none — fail-closed direction: demotions keep the pre-sieve
    ## verdict, and IR-less nodes are never carved out.
    @[IrPipelineResult(
      funcName: vs1CarveFn,
      modulePath: vs1CarveModule,
      verification: makeDisproved(smBMC, pkZ3Bmc, psBounded),
      obligationVerdict: ObligationVerdictInfo(kind: ogrGenerated, obligationCount: 1))]

  proc vs1Run(workers: int): BatchUapReport =
    ## One full batch run under a fixed AXIOM_PROVE_WORKERS value (restored
    ## on exit) with a per-run vault. Asserts the branch-entry contract:
    ## the threaded parallel branch counter moves only on workers > 1.
    let prevWorkers = getEnv("AXIOM_PROVE_WORKERS")
    let prevSkip = getEnv("AXIOM_SKIP_SOLVER_CHECK")
    putEnv("AXIOM_SKIP_SOLVER_CHECK", "1")
    if workers > 1:
      putEnv("AXIOM_PROVE_WORKERS", $workers)
    else:
      putEnv("AXIOM_PROVE_WORKERS", "1")
    parallelDepthBatchRuns = 0
    let vault = getTempDir() / ("axiom_vs1_parity_" & $workers & "_" & $getCurrentProcessId())
    defer:
      if prevWorkers.len == 0: delEnv("AXIOM_PROVE_WORKERS")
      else: putEnv("AXIOM_PROVE_WORKERS", prevWorkers)
      if prevSkip.len == 0: delEnv("AXIOM_SKIP_SOLVER_CHECK")
      else: putEnv("AXIOM_SKIP_SOLVER_CHECK", prevSkip)
    result = runBatchUapOrchestration(
      vs1State(), vs1Requests(), vault,
      preComputedIrResults = vs1IrResults())
    check parallelDepthBatchRuns == (if workers > 1: 1 else: 0)

  proc vs1StatusFor(report: OrchestrationReport; nodeIdStr: string): OrchestrationNodeStatus =
    ## The node's own terminal status. An absent report is a test failure,
    ## never a silent pass.
    for nr in report.nodeReports:
      if sorterNodeIdString(nr.nodeId) == nodeIdStr:
        return nr.status
    raise newException(ValueError, "no node report for " & nodeIdStr)

  proc vs1StatusProjection(rep: BatchUapReport): seq[(string, OrchestrationNodeStatus)] =
    ## nodeId-sorted (nodeId, status) projection — order-independent by
    ## construction, matching the parallel merge's taskIndex reorder.
    for nr in rep.orchestrationReport.nodeReports:
      result.add((sorterNodeIdString(nr.nodeId), nr.status))
    result.sort(proc(a, b: (string, OrchestrationNodeStatus)): int =
      cmp(a[0], b[0]))

  test "carve-out and pre-sieve decisions are identical on sequential and parallel paths":
    let seqRep = vs1Run(1)
    let parRep = vs1Run(2)
    let parRep2 = vs1Run(2)

    # Node statuses identical across all three runs: the carved-out node is
    # orchestrationProofFailed on BOTH lanes (never pre-sieved), the
    # disproof-less node stays PRE-SIEVED on both.
    for rep in [seqRep, parRep, parRep2]:
      check vs1StatusFor(rep.orchestrationReport, vs1CarveNodeIdStr()) ==
        orchestrationProofFailed
      check vs1StatusFor(rep.orchestrationReport, vs1PreNodeIdStr()) ==
        orchestrationPreSievedUnverifiable

    # Order-independent aggregation: identical (nodeId, status) projections.
    check vs1StatusProjection(seqRep) == vs1StatusProjection(parRep)
    check vs1StatusProjection(parRep) == vs1StatusProjection(parRep2)

    # OGR attempt accounting identical: the carved-out node's single
    # generated obligation counts on BOTH lanes (the parallel merge mirrors
    # the sequential P6 accounting through preSieveAttemptsObligations).
    for rep in [seqRep, parRep, parRep2]:
      check rep.orchestrationReport.executionStats.obligationAttemptedCount == 1
      check rep.orchestrationReport.executionStats.obligationGeneratedCount == 1
      check rep.orchestrationReport.executionStats.targetsWithObligations == 1

    # Aggregation equivalence: no uap results (both nodes failed/terminal),
    # exactly one S3 refactor trigger — from the PRE-SIEVED node only; the
    # carved-out disproof node must not contribute one on either lane.
    for rep in [seqRep, parRep, parRep2]:
      check rep.uapResults.len == 0
      check rep.refactorTasks.len == 1
      check rep.orchestrationReport.nodeReports.len == 2

    # Documented statistic: the parallel runs executed the single depth
    # level with two workers (branch entry itself is proven by the
    # parallelDepthBatchRuns check inside vs1Run).
    for rep in [parRep, parRep2]:
      check rep.orchestrationReport.executionStats.depthStats.len == 1
      check rep.orchestrationReport.executionStats.depthStats[0].workerCount == 2

suite "BatchUapOrchestrator — VS-1 non-blocked IR disproof terminal":
  ## An ADMITTED (non-blocked) node whose claim-scoped IR evidence is a
  ## P4-confirmed disproof is REFUTED: both lanes must terminate it at the
  ## IR disproof terminal BEFORE budget/spacer/UAP — sequential at its
  ## stage-2 vsDisproved check (loop_driver), parallel at the psndProceed
  ## terminal (loop_depth_scheduler). Before the parallel terminal existed,
  ## the refuted claim fell through to the solver region on the threaded
  ## lane and could be reported orchestrationVerified WITH a certificate
  ## (failedCount 0 → exit 0) while the sequential lane failed the same
  ## node (exit 1) — lane-dependent verdicts for an IR-adjudicated claim.
  ##
  ## Z3 independence — BY CONSTRUCTION, plus process observation:
  ## (a) the fixture sources carry a `var` in the body, so
  ##     isArithmeticFunction rejects them and the type-directed stage
  ##     (runArithmeticTypeDirectedProof) returns before its solver leg on
  ##     BOTH lanes;
  ## (b) the shared admission rule ADMITS both nodes (sieve verdict not
  ##     blocked — asserted below), so the parallel worker reaches the
  ##     psndProceed terminal and returns BEFORE stages 6-9
  ##     (budget/spacer/UAP), which are the only stages that spawn Z3;
  ## (c) the certNoObligation label-mirror helper is exercised directly
  ##     against crafted cert files — the full cert-write path (which the
  ##     verified label requires) is never entered.
  ## The execve audit of the test binary (strace -f) records zero z3
  ## executions; see the VS-1 parity evidence for the observation.
  ##
  ## Node A and Node B are two independent non-blocked functions at the
  ## same dependency depth (no dependencies), so depthItems.len > 1 and
  ## the threaded parallel branch actually runs; both carry a claim-scoped
  ## vsDisproved with one generated obligation, so the run under test has
  ## TWO IR-terminal nodes and arrival order between them is unobservable
  ## in the outcome.

  const vs1TermAModule = "src/axiom_test_irterm_a.nim"
  const vs1TermAFn = "axiomTestIrTermA"
  const vs1TermBModule = "src/axiom_test_irterm_b.nim"
  const vs1TermBFn = "axiomTestIrTermB"

  proc vs1TermNodeIdStr(modulePath, fnName: string): string =
    modulePath & "::" & fnName

  proc vs1TermASrc(): string =
    "func " & vs1TermAFn & "*(x: int): int =\n  var y = x\n  y\n"

  proc vs1TermBSrc(): string =
    "func " & vs1TermBFn & "*(x: int): int =\n  var y = x\n  y\n"

  proc vs1TermAIdStr(): string = vs1TermNodeIdStr(vs1TermAModule, vs1TermAFn)
  proc vs1TermBIdStr(): string = vs1TermNodeIdStr(vs1TermBModule, vs1TermBFn)

  proc vs1TermState(): SorterState =
    initSorterState(@[
      makeSorterNode(vs1TermAModule, vs1TermAFn,
        sorterNodeId(vs1TermAIdStr()), @[]),
      makeSorterNode(vs1TermBModule, vs1TermBFn,
        sorterNodeId(vs1TermBIdStr()), @[])])

  proc vs1TermRequests(): seq[OrchestrationProofRequest] =
    @[initOrchestrationProofRequest(
        nodeId = sorterNodeId(vs1TermAIdStr()),
        sourceCode = vs1TermASrc(),
        stateValue = 100, inputDelta = 70),
      initOrchestrationProofRequest(
        nodeId = sorterNodeId(vs1TermBIdStr()),
        sourceCode = vs1TermBSrc(),
        stateValue = 100, inputDelta = 70)]

  proc vs1TermDisproof(fnName, modulePath: string): IrPipelineResult =
    ## P4-confirmed, replay-confirmed disproof of an adopted claim with one
    ## generated obligation (the same shape the P4 finalizer promotes to
    ## vsDisproved). obligationCount=1 pins the P6 attempt accounting.
    IrPipelineResult(
      funcName: fnName,
      modulePath: modulePath,
      verification: makeDisproved(smBMC, pkZ3Bmc, psBounded),
      obligationVerdict: ObligationVerdictInfo(kind: ogrGenerated, obligationCount: 1))

  proc vs1TermIrResults(): seq[IrPipelineResult] =
    @[vs1TermDisproof(vs1TermAFn, vs1TermAModule),
      vs1TermDisproof(vs1TermBFn, vs1TermBModule)]

  test "fixture precondition: both nodes are ADMITTED by the shared rule":
    ## Pins the route under test: with the relaxed threshold the driver uses
    ## (stallCount=0), the sieve verdict is NOT blocked, so the shared
    ## admission rule returns psndProceed for these nodes — the terminal
    ## exercised by the runs below is the psndProceed IR terminal, not the
    ## blocked-node carve-out (psndDisproofTerminal).
    let blockThreshold = computeRelaxedThreshold(0)
    for checkIdx in 0..<2:
      let (modulePath, fnName, idStr) =
        if checkIdx == 0: (vs1TermAModule, vs1TermAFn, vs1TermAIdStr())
        else: (vs1TermBModule, vs1TermBFn, vs1TermBIdStr())
      let item = SorterWorkItem(nodeId: sorterNodeId(idStr))
      let matchingReq = vs1TermRequests()[checkIdx]
      let sieveResult = runPreSieveStage(
        item, matchingReq, TopologyAnalysis(), modulePath, fnName,
        blockThreshold = blockThreshold)
      check sieveResult.sieveVerdict.blocked == false
      check decidePreSieveNode(
        sieveResult.sieveVerdict, blockThreshold,
        hasScopedIrResult = true, irDisproved = true) == psndProceed

  proc vs1TermRun(workers: int): tuple[rep: BatchUapReport, vault: string] =
    ## One full batch run under a fixed AXIOM_PROVE_WORKERS value (restored
    ## on exit) with a per-run vault. Asserts the branch-entry contract: the
    ## threaded parallel branch counter moves only on workers > 1.
    let prevWorkers = getEnv("AXIOM_PROVE_WORKERS")
    let prevSkip = getEnv("AXIOM_SKIP_SOLVER_CHECK")
    putEnv("AXIOM_SKIP_SOLVER_CHECK", "1")
    putEnv("AXIOM_PROVE_WORKERS", $workers)
    parallelDepthBatchRuns = 0
    let vault = getTempDir() / ("axiom_vs1_irterm_" & $workers & "_" &
      $getCurrentProcessId())
    defer:
      if prevWorkers.len == 0: delEnv("AXIOM_PROVE_WORKERS")
      else: putEnv("AXIOM_PROVE_WORKERS", prevWorkers)
      if prevSkip.len == 0: delEnv("AXIOM_SKIP_SOLVER_CHECK")
      else: putEnv("AXIOM_SKIP_SOLVER_CHECK", prevSkip)
    result.rep = runBatchUapOrchestration(
      vs1TermState(), vs1TermRequests(), vault,
      preComputedIrResults = vs1TermIrResults())
    result.vault = vault
    check parallelDepthBatchRuns == (if workers > 1: 1 else: 0)

  proc vs1TermNode(rep: OrchestrationReport;
      idStr: string): OrchestrationNodeReport =
    ## The node's own terminal report. An absent report is a test failure,
    ## never a silent pass.
    for nr in rep.nodeReports:
      if sorterNodeIdString(nr.nodeId) == idStr:
        return nr
    raise newException(ValueError, "no node report for " & idStr)

  proc vs1TermProjection(rep: BatchUapReport):
      seq[(string, OrchestrationNodeStatus, string)] =
    ## (nodeId, status, evidence label) projection, nodeId-sorted —
    ## order-independent by construction, matching the parallel merge's
    ## taskIndex reorder.
    for nr in rep.orchestrationReport.nodeReports:
      result.add((sorterNodeIdString(nr.nodeId), nr.status, nr.evidenceLogJson))
    result.sort(proc(a, b: (string, OrchestrationNodeStatus, string)): int =
      cmp(a[0], b[0]))

  proc vs1TermCertPath(vault, modulePath, fnName, source: string): string =
    vault / (sha256Hex(modulePath & fnName & source) & ".json")

  test "non-blocked vsDisproved nodes terminate at the IR terminal identically on sequential and parallel lanes":
    let (seqRep, seqVault) = vs1TermRun(1)
    let (parRep, parVault) = vs1TermRun(2)
    let (parRep2, parVault2) = vs1TermRun(2)

    # Per-node terminal verdicts: orchestrationProofFailed with the
    # sequential stage-2 mapping's evidence label ("UAP failed") on ALL
    # runs — lane-independent node verdicts for IR-adjudicated claims.
    for (rep, _) in [(seqRep, seqVault), (parRep, parVault), (parRep2, parVault2)]:
      for idStr in [vs1TermAIdStr(), vs1TermBIdStr()]:
        let nr = vs1TermNode(rep.orchestrationReport, idStr)
        check nr.status == orchestrationProofFailed
        check nr.evidenceLogJson == "UAP failed"

    # Order-independent aggregation: identical sorted projections.
    check vs1TermProjection(seqRep) == vs1TermProjection(parRep)
    check vs1TermProjection(parRep) == vs1TermProjection(parRep2)

    # failedCount parity through the CANONICAL report projection: both
    # refuted nodes count as failed on every lane (before the parallel
    # terminal, the threaded lane reported them verified → failedCount 0).
    for (rep, _) in [(seqRep, seqVault), (parRep, parVault), (parRep2, parVault2)]:
      let projection = jsonFromOrchestrationReport(rep.orchestrationReport)
      check projection{"summary"}{"failedCount"}.getInt() == 2
      for row in projection{"nodeReports"}.items():
        check row{"status"}.getStr() == "failed"

    # P6 attempt-accounting parity: each refuted node's single generated
    # obligation counts as attempted on BOTH lanes (the parallel merge
    # mirrors the sequential P6 accounting through
    # preSieveAttemptsObligations — a psndProceed node reaches the
    # terminal, so its obligations ARE attempted).
    for (rep, _) in [(seqRep, seqVault), (parRep, parVault), (parRep2, parVault2)]:
      check rep.orchestrationReport.executionStats.obligationAttemptedCount == 2
      check rep.orchestrationReport.executionStats.obligationGeneratedCount == 2
      check rep.orchestrationReport.executionStats.targetsWithObligations == 2

    # Counterexample semantics: the refuted claims produce NO uap output,
    # NO summary, NO certificate, and NO verified row on any lane — the
    # disproof surfaces ONLY through the failed terminal, never through a
    # certificate that would claim a refuted contract.
    for (rep, vault) in [(seqRep, seqVault), (parRep, parVault), (parRep2, parVault2)]:
      check rep.uapResults.len == 0
      check rep.refactorTasks.len == 0
      check rep.orchestrationReport.nodeReports.len == 2
      check not fileExists(vs1TermCertPath(vault, vs1TermAModule, vs1TermAFn, vs1TermASrc()))
      check not fileExists(vs1TermCertPath(vault, vs1TermBModule, vs1TermBFn, vs1TermBSrc()))

    # Documented statistic: the parallel runs executed the single depth
    # level with two workers (branch entry itself is proven by the
    # parallelDepthBatchRuns check inside vs1TermRun).
    for (rep, _) in [(parRep, parVault), (parRep2, parVault2)]:
      check rep.orchestrationReport.executionStats.depthStats.len == 1
      check rep.orchestrationReport.executionStats.depthStats[0].workerCount == 2

  test "certNoObligation label mirror: observed cert status reclassifies the node label":
    ## The parallel merge mirrors the sequential promotion classification's
    ## certNoObligation branch: a verified-labeled node whose persisted
    ## certificate carries certNoObligation (no verification obligation —
    ## not a failure, nothing promoted) is relabeled
    ## orchestrationNoObligation. Fail-closed: any other observed status —
    ## or an unreadable/missing certificate — keeps the incoming label.
    let vault = getTempDir() / ("axiom_vs1_irterm_mirror_" & $getCurrentProcessId())
    createDir(vault)
    let irHash = sha256Hex("mod" & "fn" & "src")
    let certPath = vault / (irHash & ".json")

    writeFile(certPath, """{"status": "certNoObligation"}""")
    var relabeled = OrchestrationNodeReport(
      nodeId: sorterNodeId("mod::fn"), status: orchestrationVerified)
    reclassifyCertNoObligation(relabeled, vault, irHash)
    check relabeled.status == orchestrationNoObligation

    writeFile(certPath, """{"status": "certZ3Verified"}""")
    var keptVerified = OrchestrationNodeReport(
      nodeId: sorterNodeId("mod::fn"), status: orchestrationVerified)
    reclassifyCertNoObligation(keptVerified, vault, irHash)
    check keptVerified.status == orchestrationVerified

    removeFile(certPath)
    var keptMissing = OrchestrationNodeReport(
      nodeId: sorterNodeId("mod::fn"), status: orchestrationVerified)
    reclassifyCertNoObligation(keptMissing, vault, irHash)
    check keptMissing.status == orchestrationVerified

    var keptEmptyHash = OrchestrationNodeReport(
      nodeId: sorterNodeId("mod::fn"), status: orchestrationVerified)
    reclassifyCertNoObligation(keptEmptyHash, vault, "")
    check keptEmptyHash.status == orchestrationVerified
