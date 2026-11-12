# nim-check: skip (shadow fragment — pragma context resolved by parent module)
import core/trusted/layer_declaration
axiomLayer "infrastructure"
func runHealingPipeline*(repoRoot: string; selfTest: bool = false): int
    {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect],
     axiomDecision.} =
  ## Main pipeline entry point. Returns 0 on success, 1 on failure.
  ##
  ## In self-test mode, uses synthetic inputs to validate pipeline logic.

  if selfTest:
    return runSelfTest()

  let proofState = loadProofState(repoRoot)
  let vaultState = loadVaultState(repoRoot)

  # Merge vault diagnostics if available
  var mergedQueue: seq[JsonNode] = @[]
  if proofState.hasKey("verificationQueue"):
    for node in proofState{"verificationQueue"}:
      mergedQueue.add(node)
  if vaultState.kind == JObject and vaultState.hasKey("verificationQueue"):
    for node in vaultState{"verificationQueue"}:
      mergedQueue.add(node)

  let failingNodes = extractFailingNodes(proofState)
  if failingNodes.len == 0:
    writeStatus("pass")
    return 0

  var anyFailed = false
  for node in failingNodes:
    let hint = buildHintFromNode(node)
    let report = validateHint(hint, hint.symbols)
    if not report.passed:
      anyFailed = true
      for r in report.results:
        if r.verdict == gvFail:
          let entry = buildFailureEntry(r.gate, hint.nodeId, r.message)
          writeFailure(entry)

  if anyFailed:
    writeStatus("fail")
    return 1
  else:
    writeStatus("pass")
    return 0

# ─── CLI Entry Point ────────────────────────────────────────────────────────
