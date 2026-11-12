
import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push, raises: [CatchableError].}
# axiomIoBoundary
## Stage 07: Certificate Vault
## Virtual DB load/sync, certificate loading, and vault enrichment.
import infrastructure/logging_facade

import
  std / options

import
  std / os

import
  std / tables

import
  std / times

import
  std / sets

import
  core / types / domain_types

import
  core / json / json_utils

import
  core / utils / constants

import
  verification / vault_index

import
  verification / analyzer / stage_02_fingerprint

import
  core / json / std_redirect

proc loadVaultIndex*(vaultDir: string): Table[string,
    tuple[winningStrategy: string, retryCount: int]] =
  ## Scans axiom_vault/*.json to build a lookup table of winning strategies.
  result = initTable[string, tuple[winningStrategy: string, retryCount: int]]()
  if not dirExists(vaultDir):
    return
  for path in walkPattern(joinPath(vaultDir, "*.json")):
    let nodeOpt = readJsonFile(path)
    if nodeOpt.isNone:
      continue
    let node = nodeOpt.get()
    if node.hasKey(functionNameKey) and
        node.getOrDefault(functionNameKey).kind == JString and
        node.hasKey(modulePathKey) and
        node.getOrDefault(modulePathKey).kind == JString:
      let fn = node.getOrDefault(functionNameKey).getStr()
      let modPath = node.getOrDefault(modulePathKey).getStr()
      let key = splitFile(modPath).name & "::" & fn
      let ws = if node.hasKey("winningStrategy") and
          node.getOrDefault("winningStrategy").kind == JString:
        node.getOrDefault("winningStrategy").getStr()
      else:
        ""
      let rc = if node.hasKey(retryCountKey) and
          node.getOrDefault(retryCountKey).kind == JInt:
        node.getOrDefault(retryCountKey).getInt()
      else:
        0
      result[key] = (winningStrategy: ws, retryCount: rc)

## Verify Certificates.
proc runVaultSync*(idx: var VaultIndex; certDir: string; idxPath: string) =
  ## [WAVE_Z:vaultSync] 1/14 Virtual DB Load & Sync
  let t0 = epochTime()
  idx = loadVirtualVaultIndex(idxPath)
  syncVaultIndexWithCertificates(idx, certDir)
  let t1 = epochTime()
  logDebug("stage_07_certificate", "[TIMING] Virtual DB load/sync: " & $(t1 - t0) & "s")

proc runCertLoad*(result: var VerificationReportSummary; idx: VaultIndex;
                  certDir: string) =
  ## [WAVE_Z:certLoad] 3/14 Load trusted certificates
  ## [AXIOM AMU] Anti-vacuity isolation: filter out nodes marked as
  ## vacuous_contradiction or unverifiable in ax_proof_state.json.
  ## These nodes must NOT contribute to verifiedWeight even if their
  ## certificate files still claim certGreen.
  let repoRoot = parentDir(parentDir(parentDir(absolutePath(certDir))))
  let statePath = joinPath(repoRoot, "logs", "ax_proof_state.json")
  var isolatedNodes: HashSet[string]
  try:
    if fileExists(statePath):
      let state = parseFile(statePath)
      if state.hasKey("entries") and state["entries"].kind == JArray:
        for entry in state["entries"].elems:
          if entry.kind == JObject and entry.hasKey("status"):
            let status = entry["status"].getStr("")
            if status in ["vacuous_contradiction", "unverifiable"]:
              let nodeId = entry.getOrDefault("nodeId").getStr("")
              if nodeId.len > 0:
                isolatedNodes.incl(nodeId)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  for key, entry in idx.entries:
    if not entry.trusted:
      continue
    let path = joinPath(certDir, entry.fileName)
    if not fileExists(path):
      continue
    if key in isolatedNodes:
      continue
    let cert = loadCertificateFromFile(path)
    if cert.trusted:
      result.certificates.add(cert)

proc runVaultEnrich*(result: var VerificationReportSummary; certDir: string) =
  let certBaseDir = absolutePath(certDir)
  let vaultDir = joinPath(certBaseDir, "..", "axiom_vault")
  let vaultIndex = loadVaultIndex(vaultDir)
  for i in 0 ..< result.certificates.len:
    let cert = result.certificates[i]
    let key = splitFile(string(cert.modulePath)).name & "::" &
        cert.functionName
    if vaultIndex.hasKey(key):
      result.certificates[i].winningStrategy = vaultIndex[key].winningStrategy
      result.certificates[i].retryCount = vaultIndex[key].retryCount

{.pop.}
