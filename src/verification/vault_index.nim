import core/trusted/layer_declaration
axiomLayer "infrastructure"
import std/[json, os, options, sequtils, sets, strutils, tables, times]
import core/crypto/hash_kernel
import core/utils/io_utils
import core/results
import core/vault/vault_index
import core/axiom_pragmas
export vault_index
import core/trusted/trust_commit
import core/trusted/scope_identity
import core/json/json_utils
# axiomIoBoundary

{.push raises: [].}

proc stableHash64*(s: string): uint64 {.inline, raises: [].} =
  ## SHA-256-derived uint64 for HashSet dedup. First 8 bytes of SHA-256 digest.
  let h = sha256Hex(s)
  # Parse first 16 hex chars as uint64
  result = 0'u64
  for i in 0..<16:
    if i < h.len:
      let c = h[i]
      let v = case c
        of '0'..'9': uint64(ord(c) - ord('0'))
        of 'a'..'f': uint64(ord(c) - ord('a') + 10)
        else: 0'u64
      result = result * 16 + v

## Canonicalize a module path to a system-independent relative form.
## Steps: 1) normalize, 2) drop "src/" prefix if present, 3) unify separators to "/".
## Note: buildGlobalSymbolGraph already produces repoRoot-relative paths,
## so we only need to strip the optional "src/" prefix and normalize.
# @axiom-hint: lean="path.length ≥ 0 ∧ projectRoot.length ≥ 0" smt="(assert (and (>= (str.len path) 0) (>= (str.len projectRoot) 0)))"
proc canonicalizeModulePath*(path, projectRoot: string): string {.raises: [].} =
  result = path
  normalizePath(result)
  if projectRoot.len > 0:
    try:
      var absProjectRoot = absolutePath(projectRoot)
      var absPath = absolutePath(result)
      normalizePath(absPath)
      normalizePath(absProjectRoot)
      let prefix = absProjectRoot & DirSep
      if absPath.startsWith(prefix):
        result = absPath.substr(prefix.len)
    except CatchableError:
      discard  # best-effort  # axiom:best-effort(ioboundary catch)
  let srcPrefix = "src" & DirSep
  if result.startsWith(srcPrefix):
    result = result.substr(srcPrefix.len)
  result = result.replace($DirSep, "/")

# @axiom-hint: lean="modulePath.length ≥ 0 ∧ functionName.length ≥ 0" smt="(assert (and (>= (str.len modulePath) 0) (>= (str.len functionName) 0)))"
proc makeVaultKey*(modulePath, functionName: string; projectRoot: string = ""): string {.raises: [].} =
  canonicalizeModulePath(modulePath, projectRoot) & "::" & functionName

# @axiom-hint: lean="path.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (>= (str.len path) 0) external_io_isolated))"
# @axiom-hint: lean="(result ≥ 0) ∧ external_io_isolated" smt="(assert (and (>= result 0) external_io_isolated))"
proc loadVirtualVaultIndex*(path: string): VaultIndex =
  result = VaultIndex(version: 1, lastVerifiedAt: 0, entries: initTable[string, VaultIndexEntry](), byFileName: initTable[string, string]())
  if not fileExists(path):
    return
  try:
    let readRes = readFileOpt(path)
    if readRes.isErr: return
    let data = readRes.get
    let node = json.parseJson(data)
    if node.hasKey("version"):
      result.version = node["version"].getInt()
    if node.hasKey("lastVerifiedAt"):
      result.lastVerifiedAt = node["lastVerifiedAt"].getBiggestInt()
    if node.hasKey("entries") and node["entries"].kind == JArray:
      for entryNode in node["entries"]:
        if entryNode.kind != JObject:
          continue
        let e = VaultIndexEntry(
          fileName: entryNode.getOrDefault("fileName").getStr(""),
          modulePath: entryNode.getOrDefault("modulePath").getStr(""),
          functionName: entryNode.getOrDefault("functionName").getStr(""),
          fingerprint: entryNode.getOrDefault("fingerprint").getStr(""),
          status: entryNode.getOrDefault("status").getStr(""),
          trusted: entryNode.getOrDefault("trusted").getBool(true),
          sourceMtime: entryNode.getOrDefault("sourceMtime").getBiggestInt(0),
          certMtime: entryNode.getOrDefault("certMtime").getBiggestInt(0),
          proofTimeMs: entryNode.getOrDefault("proofTimeMs").getBiggestInt(0),
          axiomCount: entryNode.getOrDefault("axiomCount").getInt(0),
          solverEngine: entryNode.getOrDefault("solverEngine").getStr("")
        )
        if e.modulePath.len > 0 and e.functionName.len > 0:
          let key = makeVaultKey(e.modulePath, e.functionName)
          result.entries[key] = e
          result.byFileName[e.fileName] = key
  except CatchableError:
    discard  # best-effort  # axiom:best-effort(ioboundary catch)

# @axiom-hint: lean="(node ≥ 0) ∧ (root ≥ 0) ∧ external_io_isolated" smt="(assert (and (>= node 0) (>= root 0) external_io_isolated))"
proc saveVirtualVaultIndex*(path: string; idx: VaultIndex) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var arr = newJArray()
  for key, entry in idx.entries:
    var node = newJObject()
    node["fileName"] = newJString(entry.fileName)
    node["modulePath"] = newJString(entry.modulePath)
    node["functionName"] = newJString(entry.functionName)
    node["fingerprint"] = newJString(entry.fingerprint)
    node["status"] = newJString(entry.status)
    node["trusted"] = newJBool(entry.trusted)
    node["sourceMtime"] = newJInt(entry.sourceMtime)
    node["certMtime"] = newJInt(entry.certMtime)
    node["proofTimeMs"] = newJInt(entry.proofTimeMs)
    node["axiomCount"] = newJInt(entry.axiomCount)
    node["solverEngine"] = newJString(entry.solverEngine)
    arr.add(node)
  var root = newJObject()
  root["version"] = newJInt(idx.version)
  root["lastVerifiedAt"] = newJInt(idx.lastVerifiedAt)
  root["entries"] = arr
  try:
    let dir = parentDir(path)
    if dir.len > 0 and not dirExists(dir):
      discard existsOrCreateDirOpt(dir)
    ## intentional-discard: legacy-approved (spec §4.1)
    discard writeFileOpt(path, pretty(root))  # axiom:best-effort(vault index is derived cache; authoritative state is TrustCommit journal)
  except CatchableError:
    discard  # best-effort  # axiom:best-effort(ioboundary catch)
  # Non-authoritative cache: the raw index file is a derived cache artifact.
  # The authoritative state is the TrustCommit journal record written below.
  try:
    var entriesArr = newJArray()
    for key, entry in idx.entries:
      entriesArr.add %*{
        "fileName": entry.fileName,
        "modulePath": entry.modulePath,
        "functionName": entry.functionName,
        "fingerprint": entry.fingerprint,
        "status": entry.status,
        "trusted": entry.trusted,
        "sourceMtime": entry.sourceMtime,
        "certMtime": entry.certMtime,
        "proofTimeMs": entry.proofTimeMs,
        "axiomCount": entry.axiomCount,
        "solverEngine": entry.solverEngine
      }
    let claim = renderJsonMultiline(%*{
      "version": idx.version,
      "lastVerifiedAt": idx.lastVerifiedAt,
      "entries": entriesArr
    })
    let certificateDigest = sha256Hex(claim)
    let solverInvocation = "vault-index"
    let evidenceId = computeEvidenceId(claim, solverInvocation, certificateDigest)
    let scopeDigest = certificateScopeDigestForPair("src/verification/vault_index.nim", "saveVirtualVaultIndex")
    let configDigest = certificateConfigDigestForPair("src/verification/vault_index.nim", "saveVirtualVaultIndex", "index-save", "", "", "SPV1")
    let c = TrustCommit(
      kind: tcVerifiedProof,
      evidenceId: evidenceId,
      claim: claim,
      solverInvocation: solverInvocation,
      attestation: "Vault index state captured in TrustCommit journal",
      certificateDigest: certificateDigest,
      scopeDigest: scopeDigest,
      configDigest: configDigest,
      parentCommit: none(string)
    )
    let journalBase = repoRootForPath(path)
    let baseDir = if journalBase.len > 0: journalBase else: path.parentDir()
    discard commitVerification(baseDir, c)  # axiom:best-effort(TrustCommit journal is advisory; failures re-checked by reconcilePass)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch) — TrustCommit failure must not block index save

# @axiom-hint: lean="idx_version ≥ -9223372036854775808 ∧ idx_version ≤ 9223372036854775807 ∧ idx_lastVerifiedAt ≥ -9223372036854775808 ∧ idx_lastVerifiedAt ≤ 9223372036854775807 ∧ certDir.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (and (>= idx_version -9223372036854775808) (<= idx_version 9223372036854775807)) (and (>= idx_lastVerifiedAt -9223372036854775808) (<= idx_lastVerifiedAt 9223372036854775807)) (>= (str.len certDir) 0) external_io_isolated))"
# @axiom-hint: lean="modulePath.length = 0 ∨ functionName.length = 0 ∧ (sourceMtime ≥ 0) ∧ (toRemove ≥ 0) ∧ external_io_isolated" smt="(assert (and (or (= (str.len modulePath) 0) (= (str.len functionName) 0)) (>= sourceMtime 0) (>= toRemove 0) external_io_isolated))"
proc removeUnseenVaultEntries*(idx: var VaultIndex; seenKeys: HashSet[uint64]) {.noinline.} =
  ## Isomorphic clean-up: rebuild tables from scratch instead of in-place del().
  ## Eliminates iterator invalidation / tombstone accumulation risks.
  var newEntries = initTable[string, VaultIndexEntry]()
  var newByFileName = initTable[string, string]()
  for key, entry in idx.entries:
    if stableHash64(key) in seenKeys:
      newEntries[key] = entry
      if entry.fileName.len > 0:
        newByFileName[entry.fileName] = key
  idx.entries = newEntries
  idx.byFileName = newByFileName

proc syncVaultIndexWithCertificates*(idx: var VaultIndex; certDir: string) =
  ## Incrementally rebuild index from certificate files.
  ## Only reads certificates that are new or changed since last sync.
  var certBaseDir: string
  var certPattern: string
  try:
    certBaseDir = absolutePath(certDir)
    certPattern = joinPath(certBaseDir, "*.json")
  except OSError, ValueError:
    return
  let repoRoot = parentDir(parentDir(parentDir(certBaseDir)))
  var seenKeys = initHashSet[uint64]()
  var walkCount = 0
  for path in walkPattern(certPattern):
    try:
      let fileName = splitFile(path).name & ".json"
      let certMtime = getLastModificationTime(path).toUnix()
      # Fast-path: if filename and mtime match existing entry, skip readFile
      if idx.byFileName.hasKey(fileName):
        let existingKey = idx.byFileName[fileName]
        if idx.entries.hasKey(existingKey):
          let existing = idx.entries[existingKey]
          if existing.certMtime == certMtime and existing.fileName == fileName:
            seenKeys.incl(stableHash64(existingKey))
            continue
      let node = readJsonFileNode(path)
      if node.isNil or node.kind != JObject:
        continue
      let modulePath = node.getOrDefault("modulePath").getStr("")
      let functionName = node.getOrDefault("functionName").getStr("")
      if modulePath.len == 0 or functionName.len == 0:
        continue
      let key = makeVaultKey(modulePath, functionName)
      seenKeys.incl(stableHash64(key))
      if idx.entries.hasKey(key):
        let existing = idx.entries[key]
        if existing.certMtime == certMtime and existing.fileName == fileName:
          continue
      let fingerprint = node.getOrDefault("fingerprint").getStr("")
      let status = node.getOrDefault("status").getStr("")
      let trusted = node.getOrDefault("trusted").getBool(true)
      let sourcePath = joinPath(repoRoot, "src", modulePath)
      var sourceMtime: int64 = 0
      if fileExists(sourcePath):
        sourceMtime = getLastModificationTime(sourcePath).toUnix()
      idx.entries[key] = VaultIndexEntry(
        fileName: fileName,
        modulePath: modulePath,
        functionName: functionName,
        fingerprint: fingerprint,
        status: status,
        trusted: trusted,
        sourceMtime: sourceMtime,
        certMtime: certMtime
      )
      idx.byFileName[fileName] = key
      inc walkCount
    except CatchableError:
      discard  # best-effort  # axiom:best-effort(ioboundary catch)
  removeUnseenVaultEntries(idx, seenKeys)

# @axiom-hint: lean="result = toRemove ∧ (result ≥ 0)" smt="(assert (and (= result toRemove) (>= result 0)))"
proc runSymbolicGc*(idx: var VaultIndex; currentSymbols: HashSet[string]): seq[string] =
  ## Returns keys of entries that should be removed. Does NOT modify idx.
  var toRemove: seq[string] = @[]
  for key in idx.entries.keys:
    if key notin currentSymbols:
      toRemove.add(key)
  result = toRemove
{.pop.}

