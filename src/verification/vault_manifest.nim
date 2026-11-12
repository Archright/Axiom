import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}
## Content-Addressable Proof Vault Manifest
##
## Provides atomic manifest management for proof verification results.
## Key = irHash (SHA-256 of IR serialization + env constraints)
## Value = ManifestEntry with verification status, solver metadata, timestamps.
##
## Embedded in the prove engine teardown pipeline (Phase 13 Wave 2).
## Atomic write pattern: createDir → tmp + writeFile + moveFile.
## Manifest lives alongside certificates in src/verification/certificates/.
## NOTE: atomicWriteManifest writes manifest.json (the promotion index) inside
## the cert dir. This is the canonical manifest that tracks promotion state,
## so it MUST NOT be blocked by the canonical-write guard even when the
## cert dir resolves to the canonical path. The guard in certificate_manager,
## cert_builder, and cert_writer applies to individual certificate files only.

import std/[json, os, options, sequtils, times]
import core/trusted/stdlib_shield
import core/axiom_pragmas
import infrastructure/logging_facade
import core/trusted/trust_commit
import core/crypto/hash_kernel
import core/trusted/scope_identity
import core/json/json_utils

type
  ManifestEntry* = object
    modulePath*: string
    functionName*: string
    status*: string           ## certGreen, certRed, certYellow
    solverMethod*: string     ## smFFI, smCLI, smLean, etc.
    lastVerifiedAt*: string   ## ISO timestamp
    irHash*: string           ## sha-256 CAS key

  VaultManifest* = object
    version*: int             ## = 2
    entries*: seq[ManifestEntry]

proc loadManifest*(path: string): VaultManifest {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load existing manifest from disk, or return empty if not found.
  result = VaultManifest(version: 2, entries: @[])
  if not fileExists(path): return
  try:
    let j = parseFile(path)
    result.version = j["version"].getInt(2)
    for e in j["entries"]:
      result.entries.add ManifestEntry(
        modulePath: e["modulePath"].getStr(""),
        functionName: e["functionName"].getStr(""),
        status: e["status"].getStr("certRed"),
        solverMethod: e["solverMethod"].getStr("smNone"),
        lastVerifiedAt: e["lastVerifiedAt"].getStr(""),
        irHash: e["irHash"].getStr(""))
  except CatchableError as e:
    logError("vault_manifest", "loadManifest failed for " & path & ": " & e.msg)

proc mergeResult*(m: var VaultManifest, functionName: string,
                  modulePath: string, irHash: string,
                  status: string, solverMethod: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Merge a verification result into the manifest.
  ## Uses irHash as content-addressable key — same IR → same key → update in place.
  let ts = now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  var found = false
  for i in 0 ..< m.entries.len:
    if m.entries[i].irHash == irHash:
      m.entries[i].status = status
      m.entries[i].solverMethod = solverMethod
      m.entries[i].lastVerifiedAt = ts
      found = true
      break
  if not found:
    m.entries.add ManifestEntry(
      modulePath: modulePath, functionName: functionName,
      status: status, solverMethod: solverMethod,
      lastVerifiedAt: ts, irHash: irHash)

proc atomicWriteManifest*(m: VaultManifest, path: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Atomic write: createDir → tmp + writeFile + moveFile.
  ## Follows state_ledger.nim tmp+fsync+rename pattern.
  let tmpPath = path & ".tmp"
  try:
    createDir(path.parentDir)
    var j = newJObject()
    j["version"] = newJInt(m.version)
    j["entries"] = newJArray()
    for e in m.entries:
      var entryNode = newJObject()
      entryNode["modulePath"] = newJString(e.modulePath)
      entryNode["functionName"] = newJString(e.functionName)
      entryNode["status"] = newJString(e.status)
      entryNode["solverMethod"] = newJString(e.solverMethod)
      entryNode["lastVerifiedAt"] = newJString(e.lastVerifiedAt)
      entryNode["irHash"] = newJString(e.irHash)
      j["entries"].add(entryNode)
    writeFile(tmpPath, pretty(j) & "\n")
    safeMoveFile(tmpPath, path)
  except CatchableError, FileMoveError:
    try: removeFile(tmpPath)
    except CatchableError as e:
      logError("vault_manifest", "cleanup tmp after atomicWriteManifest failure: " & e.msg)
  # Non-authoritative cache: the raw manifest file is a derived cache artifact.
  # The authoritative state is the TrustCommit journal record written below.
  try:
    let claim = renderJsonMultiline(%*{
      "version": m.version,
      "entries": m.entries.mapIt(%*{
        "modulePath": it.modulePath,
        "functionName": it.functionName,
        "status": it.status,
        "solverMethod": it.solverMethod,
        "lastVerifiedAt": it.lastVerifiedAt,
        "irHash": it.irHash
      })
    })
    let certificateDigest = sha256Hex(claim)
    let solverInvocation = "vault-manifest"
    let evidenceId = computeEvidenceId(claim, solverInvocation, certificateDigest)
    let scopeDigest = certificateScopeDigestForPair("src/verification/vault_manifest.nim", "atomicWriteManifest")
    let configDigest = certificateConfigDigestForPair("src/verification/vault_manifest.nim", "atomicWriteManifest", "manifest-write", "", "", "SPV1")
    let c = TrustCommit(
      kind: tcVerifiedProof,
      evidenceId: evidenceId,
      claim: claim,
      solverInvocation: solverInvocation,
      attestation: "Vault manifest state captured in TrustCommit journal",
      certificateDigest: certificateDigest,
      scopeDigest: scopeDigest,
      configDigest: configDigest,
      parentCommit: none(string)
    )
    let journalBase = repoRootForPath(path)
    let baseDir = if journalBase.len > 0: journalBase else: path.parentDir()
    discard commitVerification(baseDir, c)  # axiom:best-effort(TrustCommit journal is advisory; failures re-checked by reconcilePass)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch) — TrustCommit failure must not block manifest write

{.pop.}
