
import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push, raises: [CatchableError].}
import core/axiom_pragmas
import infrastructure/logging_facade
# axiomIoBoundary
## Stage 06: Proof Synthesis / Hydration Extract
## Incremental hydration: re-verify certificates whose source changed.
import
  std / os

import
  std / tables

import
  std / sets

import
  std / times

import
  core / types / domain_types

import
  verification / vault_index

import
  core / symbolic / global_symbol_graph_types

import
  core / symbol_graph / global_symbol_graph_query

import
  verification / analyzer / analyzer_shared_cert

import
  verification / analyzer / stage_02_fingerprint

proc runHydrationExtract*(result: var VerificationReportSummary;
                          idx: var VaultIndex; certDir: string;
                          graph: GlobalSymbolGraph; normalizedCertDir: string;
                          knownFunctions: HashSet[string];
                          globalsByModule: var Table[string, HashSet[string]];
    moduleFunctionsByPath: var Table[string, HashSet[string]]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  let certBaseDir = absolutePath(certDir)
  let currentGraphHash = graphHash(graph)
  let t4 = epochTime()
  var hydratedCount = 0
  var skippedCount = 0
  for i in 0 ..< result.certificates.len:
    var cert = result.certificates[i]
    let key = makeVaultKey(string(cert.modulePath),
                           cert.functionName)
    var needsHydration = true
    if idx.entries.hasKey(key):
      let entry = idx.entries[key]
      let sourcePath = resolveSourcePath(certBaseDir, string(cert.modulePath))
      var currentSourceMtime: int64 = 0
      if fileExists(sourcePath):
        currentSourceMtime = getLastModificationTime(sourcePath).toUnix()
      if currentSourceMtime == entry.sourceMtime:
        needsHydration = false
        inc skippedCount
        if cert.status == certGreen and
            cert.fingerprint != entry.fingerprint:
          needsHydration = true
    if needsHydration:
      inc hydratedCount
      hydrateCertificate(cert, certBaseDir, knownFunctions, globalsByModule,
                         moduleFunctionsByPath, result.missingCertificates,
                         result.mismatchedFingerprints, currentGraphHash)
      if idx.entries.hasKey(key):
        let sourcePath = resolveSourcePath(certBaseDir, string(cert.modulePath))
        var currentSourceMtime: int64 = 0
        if fileExists(sourcePath):
          currentSourceMtime = getLastModificationTime(sourcePath).toUnix()
        idx.entries[key].sourceMtime = currentSourceMtime
        idx.entries[key].fingerprint = cert.fingerprint
        idx.entries[key].status = $cert.status
    result.certificates[i] = cert
  let t5 = epochTime()
  logDebug("stage_06_proof_synth", "[TIMING] Hydration: " & $(t5 - t4) & "s (hydrated=" & $(hydratedCount) & ", skipped=" & $(skippedCount) & ")")

{.pop.}
