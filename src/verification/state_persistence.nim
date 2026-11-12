import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
# axiomIoBoundary

import std/os
import std/options
import std/json
import std/strutils
import core/types/asi_types
import core/utils/io_utils
import core/json/json_utils
import core/results
import core/telemetry/metrics
import verification/state_manager
import verification/proof_state_projection
import core/axiom_pragmas

## Atomic Write Proof State.
## Convenience wrapper: serialises a JsonNode and writes it atomically to path.
proc atomicWriteProofState*(path: string; content: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Atomically writes proof-state JSON to disk. Returns true on success.
  ## Creates parent directory if it does not exist.
  let dir = parentDir(path)
  if dir.len > 0 and not dirExists(dir):
    try:
      discard existsOrCreateDir(dir)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
  let res = atomicWriteText(path, content)
  res.isOk()

## Reconstruct Proof State From Certificates.
## Self-healing fallback: when ax_proof_state.json is missing or corrupt,
## scan the certificate directory and build a minimal valid state object.
## DEBT#429: Verified-count projection fragmented across 5 independent counting paths; single canonical invariant absent.
proc reconstructProofStateFromCertificates*(certDir: string; totalSourceFunctions: int): JsonNode {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], axiomDebt: "DEBT#429".} =
  ## Scans ``certDir/*.json`` and counts certificates with:
  ##   - status in ["certGreen", "certVerifiedAxiom"]
  ##   - solverMeta.leanCompilerVerified == true
  ## Builds a minimal proof-state JsonNode the pipeline can consume.
  var verifiedCount = 0
  var pseudoVerifiedCount = 0
  var vacuousCount = 0
  var timeoutCount = 0
  var counterExampleCount = 0
  var entries = newJArray()
  let pattern = joinPath(certDir, "*.json")
  try:
    for path in walkPattern(pattern):
      let contentRes = readFileOpt(path)
      if contentRes.isErr: continue
      let parsedOpt = parseJsonOpt(contentRes.get())
      if parsedOpt.isNone: continue
      let node = parsedOpt.get()
      if node.kind != JObject: continue
      let modulePath = node.getOrDefault("modulePath").getStr("")
      let functionName = node.getOrDefault("functionName").getStr("")
      if modulePath.len == 0 or functionName.len == 0: continue
      let status = node.getOrDefault("status").getStr("")
      let reason = node.getOrDefault("reason").getStr("").toLowerAscii()
      # Pseudo-verified
      if status == "certPseudoVerified":
        inc pseudoVerifiedCount
        entries.add(%*{
          "nodeId": modulePath & "::" & functionName,
          "modulePath": modulePath,
          "functionName": functionName,
          "status": "pseudo_verified",
          "attempted": true,
          "attemptCount": 0
        })
        continue
      if status == "certRed" or status == "red" or status == "failed":
        if reason.contains("counter"):
          inc counterExampleCount
          entries.add(%*{
            "nodeId": modulePath & "::" & functionName,
            "modulePath": modulePath,
            "functionName": functionName,
            "status": "counter_example_found",
            "attempted": true,
            "attemptCount": 0
          })
          continue
        if reason.contains("vacuous"):
          inc vacuousCount
          entries.add(%*{
            "nodeId": modulePath & "::" & functionName,
            "modulePath": modulePath,
            "functionName": functionName,
            "status": "vacuous_contradiction",
            "attempted": true,
            "attemptCount": 0
          })
          continue
        if reason.contains("timeout"):
          inc timeoutCount
          entries.add(%*{
            "nodeId": modulePath & "::" & functionName,
            "modulePath": modulePath,
            "functionName": functionName,
            "status": "timed_out",
            "attempted": true,
            "attemptCount": 0
          })
          continue
      # Standard verified — all genuine lean-verified evidence classes
      # (certGreen, certVerifiedAxiom, certLeanVerified, certDualVerified)
      # that passed the leanCompilerVerified gate below are counted.
      if status != "certGreen" and status != "certVerifiedAxiom" and
         status != "certLeanVerified" and status != "certDualVerified": continue
      let solverMeta = node.getOrDefault("solverMeta")
      let leanVerified = (not solverMeta.isNil and solverMeta.kind == JObject and
                          solverMeta.getOrDefault("leanCompilerVerified").getBool(false))
      if not leanVerified: continue
      inc verifiedCount
      entries.add(%*{
        "nodeId": modulePath & "::" & functionName,
        "modulePath": modulePath,
        "functionName": functionName,
        "status": certificateStatusToProofStateStatus(status),
        "attempted": true,
        "attemptCount": 0
      })
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  let effectiveTotal = max(totalSourceFunctions, 1)
  let asiRatio = initAsiRatio(verifiedCount.float / effectiveTotal.float).get(defaultAsiRatio())
  let asiVal = asString(metrics.exportAsiFixed4(asiRatio))
  let explicitCertCount = verifiedCount + pseudoVerifiedCount + vacuousCount + timeoutCount
  result = %*{
    "summary": {
      "totalNodes": entries.len,
      "attemptedNodes": verifiedCount + pseudoVerifiedCount + vacuousCount + timeoutCount,
      "verified": verifiedCount,
      "counterExamples": counterExampleCount,
      "vacuousContradictions": vacuousCount,
      "timedOut": timeoutCount,
      "failedCount": 0,
      "unverifiable": 0,
      "pseudoVerified": pseudoVerifiedCount,
      "certifiedExempt": 0,
      "unattempted": entries.len - explicitCertCount,
      "engineAsiFixed4": asiVal,
      "totalSourceFunctions": totalSourceFunctions
    },
    "entries": entries,
    "reconstructedFromCertificates": true
  }

{.pop.}
