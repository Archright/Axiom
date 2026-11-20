import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

## `ax evidence bundle export` — build an Evidence Bundle v2 from a
## run-scoped proof state.
##
## Selection is driven by the proof state, never by a blind vault walk:
##
##   1. `unitEvidenceRefs[<module>::<function>]` is the run's
##      VDA-decided canonical-evidence set (propositionHash, evidenceId,
##      leanSourceHash, kaaDigest, toolchainFingerprint, obligationId).
##   2. `runAccounting.units[<module>::<function>]` must say SATISFIED with
##      satisfactionSource=FRESH. REUSED rows are refused unless the caller
##      passes `allowReused` explicitly; a row that is present but not
##      FRESH is a contradiction and fails closed.
##   3. The vault is consulted only to find the ONE certificate whose
##      identity fields equal the run-state row. Zero or multiple matches
##      fail closed.
##
## The subject bytes come from the subject commit (`git cat-file`), never the
## working tree. Every ship-able source entry of the commit's tree is copied
## into `sources/` and bound by `treeDigest`.
##
## The manifest deliberately does not carry `canonicalProposition` implicitly:
## the certificate body does not persist the canonical proposition text, so the
## caller must supply it (`--propositions`, propositionHash → text). A missing
## proposition is a hard failure — a bundle that cannot re-derive
## `propositionHash` is not evidence.

import std/json
import std/os
import std/osproc
import std/algorithm
import std/strutils
import std/tables
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/proof/source_fingerprint
import core/results
import core/types/verification_tier
import core/utils/repo_root
import infrastructure/process_utils
import verification/canonical_json
import verification/cert_vault_role
import verification/evidence_bundle/bundle_paths
import verification/evidence_bundle/bundle_schema
import verification/evidence_bundle/bundle_toolchain
import verification/evidence_bundle/strict_json

const
  GitTimeoutMs = 300_000
  BundleCertDir = "certs"
  BundleSourceDir = "sources"
  SourceIndexName = "source-index.json"

type
  BundleExportOptions* = object
    proofStatePath*: string
    subjectRepo*: string
    subjectCommit*: string
    baseSha*: string
    subjectRoot*: string
    outDir*: string
    vaultDir*: string          ## "" → resolveCertificate(cvRuntimeCanonical)
    propositionsPath*: string
    runId*: string
    runAttempt*: string
    workflowPath*: string
    workflowRef*: string
    event*: string
    headSha*: string
    allowReused*: bool

  BundleExportOutcome* = object
    outDir*: string
    evidenceDigest*: string
    provenanceDigest*: string
    bundleDigest*: string
    certCount*: int
    sourceCount*: int

  SourceBlob = object
    mode: string
    gitOid: string
    content: string
    sha256: string

  VaultCert = object
    path: string
    bytes: string
    irHash: string
    modulePath: string
    functionName: string
    propositionHash: string
    evidenceId: string
    leanSourceHash: string
    kaaDigest: string
    toolchainFingerprint: string
    node: JsonNode

func splitUnitKey(key: string): tuple[modulePath, functionName: string] {.raises: [].} =
  let idx = key.rfind("::")
  if idx <= 0 or idx + 2 >= key.len:
    return ("", "")
  (key[0 ..< idx], key[idx + 2 .. ^1])

proc runGit(subjectRoot: string; args: seq[string]): tuple[ok: bool; output: string] {.raises: [].} =
  var quoted: seq[string] = @[]
  for a in args: quoted.add(quoteShell(a))
  let cmd = "git -C " & quoteShell(subjectRoot) & " " & quoted.join(" ")
  let (output, code) = execCmdWithTimeout(cmd, timeoutMs = GitTimeoutMs)
  (ok: code == 0, output: output)

proc loadStrictFile(path: string; maxBytes: int64): Result[JsonNode, string] {.raises: [CatchableError].} =
  if not fileExists(path):
    return err("file not found: " & path)
  let root = parentDir(path)
  let rel = extractFilename(path)
  let resolved = resolveRegularFileUnder(root, rel, maxBytes)
  if resolved.isErr:
    return err(resolved.error)
  let text = readFile(resolved.get)
  parseStrictJson(text)

proc loadPropositions(path: string): Result[Table[string, string], string] {.raises: [CatchableError].} =
  ## Accepted shapes:
  ##   { "<64-hex propositionHash>": "<canonical proposition>", ... }
  ##   { "schema": "...", "propositions": [{propositionHash, proposition}, ...] }
  let parsed = loadStrictFile(path, 16 * 1024 * 1024)
  if parsed.isErr: return err("propositions: " & parsed.error)
  let node = parsed.get
  if node.kind != JObject:
    return err("propositions: top-level must be an object")
  var props = initTable[string, string]()
  if node.hasKey("propositions"):
    let rows = node{"propositions"}
    if rows.isNil or rows.kind != JArray:
      return err("propositions.propositions must be an array")
    for row in rows:
      if row.isNil or row.kind != JObject:
        return err("propositions entry is not an object")
      let hash = strOf(row, "propositionHash")
      let text = strOf(row, "proposition")
      if not isSha256Hex(hash):
        return err("propositions entry has a malformed propositionHash: " & hash)
      if text.len == 0:
        return err("propositions entry has an empty proposition for " & hash)
      if props.hasKey(hash):
        return err("duplicate propositionHash in propositions: " & hash)
      props[hash] = text
  else:
    for hash, value in node.pairs:
      if not isSha256Hex(hash):
        return err("propositions key is not a 64-hex digest: " & hash)
      if value.kind != JString or value.getStr().len == 0:
        return err("propositions value is not a non-empty string: " & hash)
      props[hash] = value.getStr()
  ok(props)

proc loadProofState(path: string): Result[JsonNode, string] {.raises: [CatchableError].} =
  loadStrictFile(path, 256 * 1024 * 1024)

proc parseTreeEntries(subjectRoot, commit: string): Result[tuple[treeOid: string,
    blobs: OrderedTable[string, SourceBlob], totalBytes: int64], string] {.raises: [CatchableError].} =
  let rev = runGit(subjectRoot, @["rev-parse", "--verify", commit & "^{commit}"])
  if not rev.ok:
    return err("subject commit is not resolvable: " & commit)
  if rev.output.strip() != commit:
    return err("subject commit resolved to a different object: " & rev.output.strip())
  let tree = runGit(subjectRoot, @["rev-parse", commit & "^{tree}"])
  if not tree.ok or not isGitOid(tree.output.strip()):
    return err("subject tree OID is not resolvable: " & commit)
  let treeOid = tree.output.strip()
  let listing = runGit(subjectRoot, @["ls-tree", "-r", "-z", "--full-tree", commit])
  if not listing.ok:
    return err("git ls-tree failed for " & commit)
  var blobs = initOrderedTable[string, SourceBlob]()
  var totalBytes = 0'i64
  var records = listing.output.split('\0')
  for record in records:
    if record.len == 0: continue
    let tab = record.find('\t')
    if tab <= 0:
      return err("malformed git ls-tree record")
    let meta = record[0 ..< tab].split(' ')
    if meta.len != 3:
      return err("malformed git ls-tree metadata")
    let mode = meta[0]
    let kind = meta[1]
    let oid = meta[2]
    let path = record[tab + 1 .. ^1]
    if not isSafeRelativePath(path):
      return err("subject tree contains an unsafe path: " & path)
    if blobs.hasKey(path):
      return err("subject tree contains a duplicate path: " & path)
    if mode notin ["100644", "100755", "120000", "160000"]:
      return err("subject tree contains an unsupported mode " & mode & ": " & path)
    var content = ""
    if kind == "blob":
      let blob = runGit(subjectRoot, @["cat-file", "blob", oid])
      if not blob.ok:
        return err("git cat-file failed for " & path)
      content = blob.output
    elif kind == "commit" and mode == "160000":
      content = oid & "\n"
    else:
      return err("subject tree entry is not a regular file: " & path)
    let size = int64(content.len)
    if size > MaxSourceFileBytes:
      return err("subject file exceeds the size limit: " & path)
    totalBytes += size
    if totalBytes > MaxTotalSourceBytes:
      return err("subject tree exceeds the total source size limit")
    if blobs.len >= MaxSourceFiles:
      return err("subject tree exceeds the file count limit")
    blobs[path] = SourceBlob(mode: mode, gitOid: oid, content: content,
      sha256: sha256Hex(content))
  ok((treeOid: treeOid, blobs: blobs, totalBytes: totalBytes))

proc loadVaultCerts(vaultDir: string): Result[seq[VaultCert], string] {.raises: [CatchableError].} =
  var certs: seq[VaultCert] = @[]
  if not dirExists(vaultDir):
    return err("certificate vault not found: " & vaultDir)
  var names = listRegularFiles(vaultDir)
  if names.isErr:
    return err("certificate vault: " & names.error)
  for name in names.get:
    if not name.endsWith(".json") or name == "manifest.json":
      continue
    let path = vaultDir / name
    let parsed = loadStrictFile(path, MaxCertBytes)
    if parsed.isErr:
      return err("vault certificate " & name & ": " & parsed.error)
    let node = parsed.get
    if node.kind != JObject:
      return err("vault certificate is not an object: " & name)
    let modulePath = strOf(node, "modulePath")
    let functionName = strOf(node, "functionName")
    if modulePath.len == 0 or functionName.len == 0:
      continue  # not a tracked per-symbol certificate
    let irHash = strOf(node, "irHash")
    if not isSha256Hex(irHash):
      return err("vault certificate has a malformed irHash: " & name)
    if splitFile(name).name != irHash:
      return err("vault certificate filename does not equal its irHash: " & name)
    let bytes = readFile(path)
    certs.add(VaultCert(
      path: path, bytes: bytes, irHash: irHash, modulePath: modulePath,
      functionName: functionName,
      propositionHash: strOf(node, "propositionHash"),
      evidenceId: strOf(node, "evidenceId"),
      leanSourceHash: strOf(node, "leanSourceHash"),
      kaaDigest: strOf(node, "kaaDigest"),
      toolchainFingerprint: strOf(node, "toolchainFingerprint"),
      node: node))
  ok(certs)

func findVaultCert(certs: seq[VaultCert]; modulePath, functionName, propositionHash,
                   evidenceId, leanSourceHash, kaaDigest,
                   toolchainFingerprint: string): seq[VaultCert] {.raises: [].} =
  result = @[]
  for c in certs:
    if c.modulePath == modulePath and c.functionName == functionName and
        c.propositionHash == propositionHash and c.evidenceId == evidenceId and
        c.leanSourceHash == leanSourceHash and c.kaaDigest == kaaDigest and
        c.toolchainFingerprint == toolchainFingerprint:
      result.add(c)

func certEntryFor(cert: VaultCert; subjectId, canonicalProposition: string): JsonNode {.raises: [].} =
  var axioms = newJArray()
  let ax = cert.node{"axiomsUsed"}
  if not ax.isNil and ax.kind == JArray:
    for item in ax:
      if item.kind == JString: axioms.add(%item.getStr())
  result = newJObject()
  result["irHash"] = %cert.irHash
  result["propositionHash"] = %cert.propositionHash
  result["canonicalProposition"] = %canonicalProposition
  result["evidenceId"] = %cert.evidenceId
  result["subjectId"] = %subjectId
  result["path"] = %(BundleCertDir & "/" & cert.irHash & ".json")
  result["sha256"] = %sha256Hex(cert.bytes)
  result["status"] = %strOf(cert.node, "status")
  result["axiomsUsed"] = axioms
  result["backend"] = %strOf(cert.node, "backend")
  result["leanSourceDigest"] = %cert.leanSourceHash
  result["artifactIdentity"] = %canonicalKaaArtifactIdentity(strOf(cert.node, "canonicalKaa"))

proc validateSelectedCert(cert: VaultCert; canonicalProposition: string): Result[void, string] {.raises: [].} =
  let node = cert.node
  let status = strOf(node, "status")
  if status notin VerifiedStatuses:
    return err("certificate status is not verified: " & status)
  if not statusConsistentWithEvidence(node):
    return err("certificate status is stronger than its stored evidence (P0)")
  let leanSource = strOf(node, "leanSource")
  if leanSource.len == 0:
    return err("certificate carries no leanSource")
  if cert.leanSourceHash.len != 64 or sha256Hex(leanSource) != cert.leanSourceHash:
    return err("certificate leanSourceHash does not hash its leanSource")
  if cert.propositionHash.len != 64:
    return err("certificate propositionHash is malformed")
  if sha256Hex(canonicalProposition) != cert.propositionHash:
    return err("canonicalProposition does not hash to the certificate propositionHash")
  if cert.kaaDigest != sha256Hex(strOf(node, "canonicalKaa")):
    return err("certificate kaaDigest does not hash its canonicalKaa")
  if cert.evidenceId != evidenceIdFromCert(node):
    return err("certificate evidenceId does not recompute from its identity fields")
  let artifact = canonicalKaaArtifactIdentity(strOf(node, "canonicalKaa"))
  if artifact.len != 64:
    return err("certificate canonicalKaa carries no receiptArtifactIdentity")
  if artifact != cert.leanSourceHash:
    return err("certificate artifactIdentity does not equal leanSourceHash")
  let ax = sortedAxioms(node{"axiomsUsed"})
  if ax.isErr: return err(ax.error)
  if not axiomsAllowlisted(ax.get):
    return err("certificate axiomsUsed is outside the allowlist")
  let kaaAx = canonicalKaaObservedAxioms(strOf(node, "canonicalKaa"))
  if kaaAx.isErr: return err(kaaAx.error)
  if kaaAx.get != ax.get:
    return err("certificate axiomsUsed does not equal the KAA-observed axiom set")
  Result[void, string](ok: true)

proc validateRunEnvelope(opts: BundleExportOptions): seq[string] {.raises: [].} =
  result = @[]
  if opts.runId.len == 0: result.add("runId is required (--run-id or GITHUB_RUN_ID)")
  elif not opts.runId.allCharsInSet({'0'..'9'}): result.add("runId must be numeric")
  if opts.runAttempt.len == 0: result.add("runAttempt is required (--run-attempt or GITHUB_RUN_ATTEMPT)")
  elif not opts.runAttempt.allCharsInSet({'0'..'9'}): result.add("runAttempt must be numeric")
  if opts.workflowPath.len == 0: result.add("workflowPath is required")
  if opts.workflowRef.len == 0: result.add("workflowRef is required")
  if opts.event.len == 0: result.add("event is required (--event or GITHUB_EVENT_NAME)")
  if not isGitOid(opts.headSha): result.add("headSha must be a 40-hex git OID")
  elif opts.headSha != opts.subjectCommit: result.add("headSha must equal the subject commit")
  if opts.subjectRepo.len == 0 or '/' notin opts.subjectRepo:
    result.add("subjectRepo must be <owner>/<name>")
  if not isGitOid(opts.subjectCommit): result.add("subjectCommit must be a 40-hex git OID")
  if not isGitOid(opts.baseSha): result.add("baseSha must be a 40-hex git OID")
  if opts.subjectRoot.len == 0 or not dirExists(opts.subjectRoot):
    result.add("subjectRoot must be an existing directory")
  if opts.outDir.len == 0: result.add("outDir is required")
  if opts.proofStatePath.len == 0: result.add("proofStatePath is required")
  if opts.propositionsPath.len == 0: result.add("propositionsPath is required")

proc exportEvidenceBundle*(opts: BundleExportOptions): Result[BundleExportOutcome, string] {.
  raises: [CatchableError], axiomDecision(id = "DECISION-0830",
    reason = "Bundle export is run-scoped and fail-closed: no vault walk, no missing proposition, no empty bundle",
    adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "VS-2a").} =
  let envelopeProblems = validateRunEnvelope(opts)
  if envelopeProblems.len > 0:
    return err("export refused: " & envelopeProblems.join("; "))

  let proofParsed = loadProofState(opts.proofStatePath)
  if proofParsed.isErr: return err("proof state: " & proofParsed.error)
  let proofState = proofParsed.get
  if proofState.kind != JObject:
    return err("proof state: top-level must be an object")
  let executionIdentity = objOf(proofState, "executionIdentity")
  if executionIdentity.isNil:
    return err("proof state: executionIdentity is missing")
  let recordedBuildId = strOf(executionIdentity, "verifierBuildId")
  let liveBuildId = measuredVerifierBuildId()
  if recordedBuildId.len == 0 or recordedBuildId == "unmeasured":
    return err("proof state: verifierBuildId is unmeasured (fail-closed)")
  if recordedBuildId != liveBuildId:
    return err("proof state: verifierBuildId does not match this verifier")
  let unitEvidence = objOf(proofState, "unitEvidenceRefs")
  if unitEvidence.isNil or unitEvidence.len == 0:
    return err("proof state: unitEvidenceRefs is missing or empty (empty bundles are refused)")
  let runAccounting = objOf(proofState, "runAccounting")
  if runAccounting.isNil:
    return err("proof state: runAccounting is missing — export requires run-scoped accounting")
  let units = arrayOf(runAccounting, "units")
  if units.isNil:
    return err("proof state: runAccounting.units is missing")
  var unitRows = initTable[string, JsonNode]()
  for row in units:
    if row.isNil or row.kind != JObject: continue
    let uid = strOf(row, "unitId")
    if uid.len > 0: unitRows[uid] = row

  let props = loadPropositions(opts.propositionsPath)
  if props.isErr: return err(props.error)

  let treeEntries = parseTreeEntries(absolutePath(opts.subjectRoot), opts.subjectCommit)
  if treeEntries.isErr: return err(treeEntries.error)
  let treeOid = treeEntries.get.treeOid
  let blobs = treeEntries.get.blobs

  let vaultDir = if opts.vaultDir.len > 0: opts.vaultDir else: resolveCertificate(cvRuntimeCanonical)
  let vault = loadVaultCerts(vaultDir)
  if vault.isErr: return err(vault.error)
  let vaultCerts = vault.get

  var keys: seq[string] = @[]
  for k in unitEvidence.keys: keys.add(k)
  keys.sort()

  var selected: seq[VaultCert] = @[]
  var selectedProps: Table[string, string] = initTable[string, string]()
  var seenIrHashes = initTable[string, string]()
  for key in keys:
    let parts = splitUnitKey(key)
    if parts.modulePath.len == 0:
      return err("unitEvidenceRefs key is not <module>::<function>: " & key)
    let evidence = objOf(unitEvidence, key)
    if evidence.isNil:
      return err("unitEvidenceRefs entry is not an object: " & key)
    let ce = objOf(evidence, "canonicalEvidence")
    if ce.isNil:
      return err("unitEvidenceRefs entry has no canonicalEvidence: " & key)
    let propositionHash = strOf(ce, "propositionHash")
    let evidenceId = strOf(ce, "evidenceId")
    let leanSourceHash = strOf(ce, "leanSourceHash")
    let kaaDigest = strOf(ce, "kaaDigest")
    let toolchainFingerprint = strOf(ce, "toolchainFingerprint")
    for (name, value) in [("propositionHash", propositionHash),
                          ("evidenceId", evidenceId),
                          ("leanSourceHash", leanSourceHash),
                          ("kaaDigest", kaaDigest),
                          ("toolchainFingerprint", toolchainFingerprint)]:
      if not isSha256Hex(value):
        return err("canonicalEvidence." & name & " is malformed for " & key)
    let row = unitRows.getOrDefault(key)
    if row.isNil:
      return err("runAccounting has no unit row for " & key)
    if strOf(row, "verificationOutcome") != "SATISFIED":
      return err("run unit is not SATISFIED: " & key)
    let source = strOf(row, "satisfactionSource")
    if source == "REUSED" and not opts.allowReused:
      return err("run unit is REUSED, not FRESH (explicit --allow-reused required): " & key)
    if source notin ["FRESH", "REUSED"]:
      return err("run unit has no established satisfaction source: " & key)

    var canonicalProposition = ""
    if props.get.hasKey(propositionHash):
      canonicalProposition = props.get[propositionHash]
    let fromState = strOf(ce, "canonicalProposition")
    if canonicalProposition.len == 0:
      canonicalProposition = fromState
    elif fromState.len > 0 and fromState != canonicalProposition:
      return err("canonicalProposition disagrees with the proof state for " & key)
    if canonicalProposition.len == 0:
      return err("canonicalProposition is missing for propositionHash " & propositionHash &
        " (supply --propositions; the certificate body does not persist it)")
    if sha256Hex(canonicalProposition) != propositionHash:
      return err("canonicalProposition does not hash to propositionHash for " & key)

    let matches = findVaultCert(vaultCerts, parts.modulePath, parts.functionName,
      propositionHash, evidenceId, leanSourceHash, kaaDigest, toolchainFingerprint)
    if matches.len == 0:
      return err("no vault certificate matches the run evidence for " & key)
    if matches.len > 1:
      return err("multiple vault certificates match the run evidence for " & key)
    let cert = matches[0]
    let certCheck = validateSelectedCert(cert, canonicalProposition)
    if certCheck.isErr:
      return err("certificate " & cert.irHash & ": " & certCheck.error)
    if not blobs.hasKey(cert.modulePath):
      return err("subject commit contains no source blob for " & cert.modulePath)
    let sourceBytes = blobs[cert.modulePath].content
    if computeStableSourceFingerprint(sourceBytes) != strOf(cert.node, "sourceHash"):
      return err("certificate sourceHash is not the subject commit blob: " & cert.modulePath)
    if seenIrHashes.hasKey(cert.irHash) and seenIrHashes[cert.irHash] != key:
      return err("one certificate is claimed by multiple units: " & cert.irHash)
    if not seenIrHashes.hasKey(cert.irHash):
      seenIrHashes[cert.irHash] = key
      selected.add(cert)
      selectedProps[cert.irHash] = canonicalProposition

  if selected.len == 0:
    return err("no run-scoped certificates were selected (empty bundles are refused)")

  let toolchain = buildToolchain(resolveRepoRoot())
  if toolchain.isErr: return err("toolchain: " & toolchain.error)
  let policy = buildPolicy(resolveRepoRoot())
  if policy.isErr: return err("policy: " & policy.error)

  var entries = newJArray()
  var sourceIndex = newJArray()
  for path, blob in blobs:
    sourceIndex.add(%*{"path": path, "mode": blob.mode, "sha256": blob.sha256})
    entries.add(%*{"path": path, "mode": blob.mode})
  let treeDigest = treeDigestFor(sourceIndex)
  let subjectId = subjectIdFor(opts.subjectRepo, opts.subjectCommit, treeDigest, opts.baseSha)

  var certEntries = newJArray()
  var kernelSymbols = 0
  for cert in selected:
    certEntries.add(certEntryFor(cert, subjectId, selectedProps[cert.irHash]))
    if cert.node{"kernel"}.getBool(false):
      inc kernelSymbols

  var manifest = newJObject()
  manifest["schema"] = %BundleSchema
  var subject = newJObject()
  subject["repository"] = %opts.subjectRepo
  subject["commit"] = %opts.subjectCommit
  subject["treeDigest"] = %treeDigest
  subject["baseSha"] = %opts.baseSha
  subject["subjectId"] = %subjectId
  manifest["subject"] = subject
  var run = newJObject()
  run["runId"] = %opts.runId
  run["runAttempt"] = %opts.runAttempt
  run["workflowPath"] = %opts.workflowPath
  run["workflowRef"] = %opts.workflowRef
  run["event"] = %opts.event
  run["headSha"] = %opts.headSha
  manifest["run"] = run
  manifest["toolchain"] = toolchain.get
  manifest["policy"] = policy.get
  manifest["certs"] = certEntries
  var counts = newJObject()
  counts["certs"] = %selected.len
  counts["kernelSymbols"] = %kernelSymbols
  manifest["counts"] = counts
  manifest["sourceVault"] = %vaultDir
  manifest["evidenceDigest"] = %evidenceDigestFor(manifest)
  manifest["provenanceDigest"] = %provenanceDigestFor(manifest)
  manifest["bundleDigest"] = %bundleDigestFor(manifest)

  if dirExists(opts.outDir):
    var existing: seq[string] = @[]
    for kind, path in walkDir(opts.outDir):
      discard kind
      existing.add(path)
    if existing.len > 0:
      return err("output directory is not empty: " & opts.outDir)
  else:
    createDir(opts.outDir)
  let certDir = ensureDirectoryUnder(opts.outDir, BundleCertDir)
  if certDir.isErr: return err(certDir.error)
  let sourceDir = ensureDirectoryUnder(opts.outDir, BundleSourceDir)
  if sourceDir.isErr: return err(sourceDir.error)

  for cert in selected:
    writeFile(certDir.get / (cert.irHash & ".json"), cert.bytes)
  for path, blob in blobs:
    let target = sourceDir.get / path
    let parent = parentDir(target)
    if parent.len > 0 and not dirExists(parent):
      createDir(parent)
    writeFile(target, blob.content)
  var indexDoc = newJObject()
  indexDoc["schema"] = %SourceIndexSchema
  indexDoc["repository"] = %opts.subjectRepo
  indexDoc["commit"] = %opts.subjectCommit
  indexDoc["treeOid"] = %treeOid
  indexDoc["entries"] = sourceIndex
  writeFile(sourceDir.get / SourceIndexName, canonicalJsonString(indexDoc) & "\n")
  writeFile(opts.outDir / "manifest.json", canonicalManifestText(manifest))

  ok(BundleExportOutcome(
    outDir: opts.outDir,
    evidenceDigest: strOf(manifest, "evidenceDigest"),
    provenanceDigest: strOf(manifest, "provenanceDigest"),
    bundleDigest: strOf(manifest, "bundleDigest"),
    certCount: selected.len,
    sourceCount: blobs.len))

{.pop.}