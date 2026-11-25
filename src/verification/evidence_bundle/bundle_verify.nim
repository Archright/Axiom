import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

## `ax evidence bundle verify` — verify an Evidence Bundle v2 WITHOUT the
## subject checkout, the Axiom journal, the certificate vault, or `./bin/ax`.
##
## Every input is the bundle directory itself plus optional external
## observations (GitHub attestation / check-runs / ruleset). The verifier
## never resolves a path outside the bundle, never follows a symlink, and
## never accepts an unlisted member.
##
## Legs and what they actually prove:
##
##   bundleContent   — strict JSON, closed key sets, closed file set, path
##                     safety, sizes/counts, and all three digests recomputed.
##   certEvidence    — each cert file hashes to its manifest entry and its
##                     identity fields recompute (evidenceId, propositionHash,
##                     KAA digest/artifact identity, axiom set).
##   subjectBinding  — `sources/` bytes hash to `source-index.json`, the tree
##                     digest matches, and each cert's `sourceHash` is the
##                     fingerprint of the shipped blob. This binds BYTES, not
##                     a Git commit (commit↔tree is the provenance axis).
##   kernel          — optional (`--kernel`): re-execute leanSource + smtlib2
##                     against the pinned toolchain. Exit 3 (not 0) when the
##                     re-execution could not happen at all.
##   provenance      — optional (`--attestation`): a normalized GitHub
##                     attestation record must bind the same evidence digest
##                     and run envelope. Sigstore is NOT re-verified here.
##   mergeAuthority  — optional (`--check-runs` / `--ruleset`): external
##                     GitHub observations of the admission App 5795152 and
##                     ruleset 27097366. Absent input is NOT_CHECKED, never a
##                     silent SUCCESS.
##
## Exit codes: 0 = every requested leg PASS; 1 = FAIL; 2 = usage/IO;
## 3 = KERNEL_SKIPPED (requested kernel re-execution could not run).

import std/json
import std/os
import std/algorithm
import std/sets
import std/strutils
import std/tables
import core/crypto/hash_kernel
import core/proof/source_fingerprint
import core/results
import core/types/verification_tier
import core/types/z3_solver_config
import core/utils/repo_root
import verification/evidence_bundle/bundle_paths
import verification/evidence_bundle/bundle_schema
import verification/evidence_bundle/bundle_toolchain
import verification/evidence_bundle/lean_replay
import verification/evidence_bundle/strict_json
import verification/evidence_cas
import verification/kernel_reexecution

when fileExists("src/generated/build_env.nim"):
  import generated/build_env
else:
  const BuildEnvZ3Version = ""

const
  BundleManifestName = "manifest.json"
  BundleSourceIndexName = "source-index.json"
  BundleCertDir = "certs"
  BundleSourceDir = "sources"
  MaxManifestBytes = 4 * 1024 * 1024
  MaxSourceIndexBytes = 32 * 1024 * 1024
  MaxBundleFiles = MaxSourceFiles + MaxCerts + 8
  KernelLegTimeoutMs = 180_000
  Z3ReexecTimeoutMs = 120_000
  AdmissionAppId = 5795152
  AdmissionRulesetId = 27097366
  AttestationSchema = "axiom.evidence-bundle.attestation.v1"
  AttestationKeys = ["schema", "signerRepository", "verified",
                     "subjectDigestSha256", "run"]

type
  BundleVerifyOptions* = object
    bundleDir*: string
    expectCommit*: string
    attestationPath*: string
    checkRunsPath*: string
    rulesetPath*: string
    runKernel*: bool

  BundleLegStatus* = enum
    blsPass, blsFail, blsNotChecked, blsSkipped

  BundleLeg* = object
    name*: string
    status*: BundleLegStatus
    detail*: string

  BundleVerifyOutcome* = object
    exitCode*: int
    legs*: seq[BundleLeg]
    evidenceDigest*: string
    provenanceDigest*: string
    bundleDigest*: string
    certCount*: int

  BundleContents = object
    manifest: JsonNode
    index: JsonNode
    certDocs: seq[JsonNode]
    sourceBytes: Table[string, string]

func legStatusText*(status: BundleLegStatus): string {.raises: [].} =
  case status
  of blsPass: "PASS"
  of blsFail: "FAIL"
  of blsNotChecked: "NOT_CHECKED"
  of blsSkipped: "SKIPPED"

func addLeg(legs: var seq[BundleLeg]; name: string; status: BundleLegStatus;
            detail: string) {.raises: [].} =
  legs.add(BundleLeg(name: name, status: status, detail: detail))

proc loadStrictPath(path: string; maxBytes: int64): Result[JsonNode, string] {.raises: [CatchableError].} =
  var root = parentDir(path)
  if root.len == 0: root = "."
  let rel = extractFilename(path)
  let resolved = resolveRegularFileUnder(root, rel, maxBytes)
  if resolved.isErr:
    return err(resolved.error)
  let text =
    try: readFile(resolved.get)
    except CatchableError as e: return err(path & ": " & e.msg)
  parseStrictJson(text)

proc readBytesUnder(bundleDir, rel: string; maxBytes: int64): Result[string, string] {.raises: [CatchableError].} =
  let resolved = resolveRegularFileUnder(bundleDir, rel, maxBytes)
  if resolved.isErr:
    return err(resolved.error)
  try:
    ok(readFile(resolved.get))
  except CatchableError as e:
    err(rel & ": " & e.msg)

# ─── shape validation (pure) ────────────────────────────────────────────────

func checkClosed(node: JsonNode; keys: openArray[string]; label: string;
                 problems: var seq[string]) {.raises: [].} =
  if node.isNil or node.kind != JObject:
    problems.add(label & " must be an object")
    return
  for k in unknownKeys(node, keys):
    problems.add(label & ": unknown key '" & k & "'")
  for k in missingKeys(node, keys):
    problems.add(label & ": missing key '" & k & "'")

func requireSha(node: JsonNode; key, label: string; problems: var seq[string]) {.raises: [].} =
  if not isSha256Hex(strOf(node, key)):
    problems.add(label & "." & key & " must be 64 lowercase hex")

func requireGitOid(node: JsonNode; key, label: string; problems: var seq[string]) {.raises: [].} =
  if not isGitOid(strOf(node, key)):
    problems.add(label & "." & key & " must be a 40-hex git OID")

func requireNonEmpty(node: JsonNode; key, label: string; problems: var seq[string]) {.raises: [].} =
  if strOf(node, key).len == 0:
    problems.add(label & "." & key & " must be a non-empty string")

func requireNumeric(node: JsonNode; key, label: string; problems: var seq[string]) {.raises: [].} =
  let value = strOf(node, key)
  if value.len == 0 or not value.allCharsInSet({'0'..'9'}):
    problems.add(label & "." & key & " must be numeric")

func checkedSection(parent: JsonNode; key: string; keys: openArray[string];
                    label: string; problems: var seq[string]): JsonNode {.raises: [].} =
  result = objOf(parent, key)
  checkClosed(result, keys, label, problems)

func validateCertEntry(cert: JsonNode; subjectId: string; entryIndex: int;
                       problems: var seq[string]) {.raises: [].} =
  let label = "manifest.certs[" & $entryIndex & "]"
  checkClosed(cert, CertKeys, label, problems)
  if cert.isNil or cert.kind != JObject: return
  for key in ["irHash", "propositionHash", "evidenceId", "sha256",
              "leanSourceDigest", "artifactIdentity"]:
    requireSha(cert, key, label, problems)
  if strOf(cert, "subjectId") != subjectId:
    problems.add(label & ".subjectId does not equal manifest.subject.subjectId")
  let irHash = strOf(cert, "irHash")
  let expectedPath = BundleCertDir & "/" & irHash & ".json"
  if strOf(cert, "path") != expectedPath:
    problems.add(label & ".path must be " & expectedPath)
  if not isSafeRelativePath(strOf(cert, "path")):
    problems.add(label & ".path is not a safe bundle path")
  if strOf(cert, "status") notin VerifiedStatuses:
    problems.add(label & ".status is not a verified status: " & strOf(cert, "status"))
  requireNonEmpty(cert, "backend", label, problems)
  let axioms = sortedAxioms(cert{"axiomsUsed"})
  if axioms.isErr:
    problems.add(label & ".axiomsUsed: " & axioms.error)
  elif not axiomsAllowlisted(axioms.get):
    problems.add(label & ".axiomsUsed contains an axiom outside the allowlist")

func validateManifest(manifest: JsonNode; problems: var seq[string]) {.raises: [].} =
  checkClosed(manifest, ManifestKeys, "manifest", problems)
  if manifest.isNil or manifest.kind != JObject:
    return
  if strOf(manifest, "schema") != BundleSchema:
    problems.add("manifest.schema must be " & BundleSchema)

  let subject = checkedSection(manifest, "subject", SubjectKeys, "manifest.subject", problems)
  if not subject.isNil and subject.kind == JObject:
    requireNonEmpty(subject, "repository", "manifest.subject", problems)
    if '/' notin strOf(subject, "repository"):
      problems.add("manifest.subject.repository must be <owner>/<name>")
    requireGitOid(subject, "commit", "manifest.subject", problems)
    requireSha(subject, "treeDigest", "manifest.subject", problems)
    requireGitOid(subject, "baseSha", "manifest.subject", problems)
    requireSha(subject, "subjectId", "manifest.subject", problems)

  let run = checkedSection(manifest, "run", RunKeys, "manifest.run", problems)
  if not run.isNil and run.kind == JObject:
    requireNumeric(run, "runId", "manifest.run", problems)
    requireNumeric(run, "runAttempt", "manifest.run", problems)
    for key in ["workflowPath", "workflowRef", "event"]:
      requireNonEmpty(run, key, "manifest.run", problems)
    requireGitOid(run, "headSha", "manifest.run", problems)
    if isGitOid(strOf(subject, "commit")) and
        strOf(run, "headSha") != strOf(subject, "commit"):
      problems.add("manifest.run.headSha must equal manifest.subject.commit")

  let toolchain = checkedSection(manifest, "toolchain", ToolchainKeys,
    "manifest.toolchain", problems)
  if not toolchain.isNil and toolchain.kind == JObject:
    for key in ["verifierBuildId", "verifierBundleSha256", "z3BinarySha256"]:
      requireSha(toolchain, key, "manifest.toolchain", problems)
    for key in ["nimVersion", "leanToolchainFile", "leanVersion", "z3Version"]:
      requireNonEmpty(toolchain, key, "manifest.toolchain", problems)
    let checker = strOf(toolchain, "leancheckerSha256")
    if checker.len != 0 and not isSha256Hex(checker):
      problems.add("manifest.toolchain.leancheckerSha256 must be empty or 64 lowercase hex")

  let policy = checkedSection(manifest, "policy", PolicyKeys, "manifest.policy", problems)
  if not policy.isNil and policy.kind == JObject:
    requireSha(policy, "policyDigest", "manifest.policy", problems)
    requireSha(policy, "scopeDigest", "manifest.policy", problems)

  let counts = checkedSection(manifest, "counts", CountsKeys, "manifest.counts", problems)
  if not counts.isNil and counts.kind == JObject:
    if intOf(counts, "certs") < 0:
      problems.add("manifest.counts.certs must be a non-negative integer")
    if intOf(counts, "kernelSymbols") < 0:
      problems.add("manifest.counts.kernelSymbols must be a non-negative integer")

  requireNonEmpty(manifest, "sourceVault", "manifest", problems)

  let certs = arrayOf(manifest, "certs")
  if certs.isNil:
    problems.add("manifest.certs must be an array")
  else:
    if certs.len == 0:
      problems.add("manifest.certs must not be empty (empty bundles are refused)")
    if certs.len > MaxCerts:
      problems.add("manifest.certs exceeds MaxCerts")
    var seenIr = initTable[string, bool]()
    var seenPath = initTable[string, bool]()
    for i in 0 ..< certs.len:
      let cert = certs[i]
      validateCertEntry(cert, strOf(subject, "subjectId"), i, problems)
      if cert.isNil or cert.kind != JObject: continue
      let irHash = strOf(cert, "irHash")
      if seenIr.hasKey(irHash):
        problems.add("manifest.certs contains a duplicate irHash: " & irHash)
      seenIr[irHash] = true
      let path = strOf(cert, "path")
      if seenPath.hasKey(path):
        problems.add("manifest.certs contains a duplicate path: " & path)
      seenPath[path] = true
    if not counts.isNil and intOf(counts, "certs") != certs.len:
      problems.add("manifest.counts.certs does not equal the cert array length")

func validateSourceIndex(index, manifest: JsonNode; problems: var seq[string]) {.raises: [].} =
  checkClosed(index, SourceIndexKeys, "source-index", problems)
  if index.isNil or index.kind != JObject: return
  if strOf(index, "schema") != SourceIndexSchema:
    problems.add("source-index.schema must be " & SourceIndexSchema)
  let subject = objOf(manifest, "subject")
  if strOf(index, "repository") != strOf(subject, "repository"):
    problems.add("source-index.repository does not equal manifest.subject.repository")
  if strOf(index, "commit") != strOf(subject, "commit"):
    problems.add("source-index.commit does not equal manifest.subject.commit")
  requireGitOid(index, "treeOid", "source-index", problems)
  let entries = arrayOf(index, "entries")
  if entries.isNil:
    problems.add("source-index.entries must be an array")
    return
  if entries.len > MaxSourceFiles:
    problems.add("source-index.entries exceeds MaxSourceFiles")
  var seen = initTable[string, bool]()
  var previous = ""
  var entryOrd = 0
  for entry in entries:
    let label = "source-index.entries[" & $entryOrd & "]"
    inc entryOrd
    checkClosed(entry, SourceEntryKeys, label, problems)
    if entry.isNil or entry.kind != JObject: continue
    let path = strOf(entry, "path")
    if not isSafeRelativePath(path):
      problems.add(label & ".path is not a safe bundle path: " & path)
    if strOf(entry, "mode") notin ["100644", "100755", "120000", "160000"]:
      problems.add(label & ".mode is unsupported: " & strOf(entry, "mode"))
    requireSha(entry, "sha256", label, problems)
    if seen.hasKey(path):
      problems.add("source-index contains a duplicate path: " & path)
    seen[path] = true
    if previous.len > 0:
      if cmp(previous, path) >= 0:
        problems.add("source-index entries are not strictly sorted by path")
      if path.startsWith(previous & "/"):
        problems.add("source-index path is both a file and a directory: " & previous)
    previous = path
  if treeDigestFor(entries) != strOf(subject, "treeDigest"):
    problems.add("manifest.subject.treeDigest does not hash the source-index entries")

# ─── bundle loading ─────────────────────────────────────────────────────────

proc scanBundleFiles(root: string): Result[seq[string], string] {.raises: [CatchableError].} =
  ## Every regular file under `root`, relative and sorted. Symlinks and
  ## special files are refused; an unexpected top-level directory is refused.
  ## Problems are collected and sorted so the failure text is deterministic.
  var files: seq[string] = @[]
  if not dirExists(root):
    return err("bundle directory is missing: " & root)
  var problems: seq[string] = @[]
  var stack: seq[tuple[absDir, relDir: string]] = @[(absolutePath(root), "")]
  while stack.len > 0:
    let item = stack.pop()
    for kind, path in walkDir(item.absDir):
      let name = extractFilename(path)
      let rel = if item.relDir.len == 0: name else: item.relDir & "/" & name
      case kind
      of pcFile:
        if files.len >= MaxBundleFiles:
          return err("bundle contains too many files")
        files.add(rel)
      of pcDir:
        let allowed = rel == BundleCertDir or rel == BundleSourceDir or
          rel.startsWith(BundleCertDir & "/") or rel.startsWith(BundleSourceDir & "/")
        if not allowed:
          problems.add("bundle contains an unexpected directory: " & rel)
        else:
          stack.add((path, rel))
      of pcLinkToFile, pcLinkToDir:
        problems.add("bundle contains a symlink (refused): " & rel)
  if problems.len > 0:
    problems.sort()
    return err(problems.join("; "))
  files.sort()
  ok(files)

proc loadBundle(bundleDir: string): Result[BundleContents, string] {.raises: [CatchableError].} =
  let manifestRes = loadStrictPath(bundleDir / BundleManifestName, MaxManifestBytes)
  if manifestRes.isErr:
    return err("manifest: " & manifestRes.error)
  let manifest = manifestRes.get
  var problems: seq[string] = @[]
  validateManifest(manifest, problems)
  if problems.len > 0:
    return err("manifest: " & problems.join("; "))

  let indexRes = loadStrictPath(bundleDir / BundleSourceDir / BundleSourceIndexName,
    MaxSourceIndexBytes)
  if indexRes.isErr:
    return err("source-index: " & indexRes.error)
  let index = indexRes.get
  problems = @[]
  validateSourceIndex(index, manifest, problems)
  if problems.len > 0:
    return err("source-index: " & problems.join("; "))

  # Closed file set: exactly manifest.json + certs/<irHash>.json +
  # sources/source-index.json + sources/<path>.
  var expected = initHashSet[string]()
  expected.incl(BundleManifestName)
  expected.incl(BundleSourceDir & "/" & BundleSourceIndexName)
  let certs = arrayOf(manifest, "certs")
  for cert in certs:
    expected.incl(strOf(cert, "path"))
  let entries = arrayOf(index, "entries")
  for entry in entries:
    expected.incl(BundleSourceDir & "/" & strOf(entry, "path"))
  let filesRes = scanBundleFiles(bundleDir)
  if filesRes.isErr:
    return err("bundle files: " & filesRes.error)
  let files = filesRes.get
  var fileSet = initHashSet[string]()
  var unlisted: seq[string] = @[]
  for file in files:
    fileSet.incl(file)
    if file notin expected:
      unlisted.add(file)
  var missing: seq[string] = @[]
  for file in expected:
    if file notin fileSet:
      missing.add(file)
  unlisted.sort()
  missing.sort()
  for file in unlisted:
    problems.add("bundle contains an unlisted file: " & file)
  for file in missing:
    problems.add("bundle is missing a listed file: " & file)
  if problems.len > 0:
    return err("bundle files: " & problems.join("; "))

  # Load and hash every certificate.
  var certDocs: seq[JsonNode] = @[]
  for cert in certs:
    let rel = strOf(cert, "path")
    let bytesRes = readBytesUnder(bundleDir, rel, MaxCertBytes)
    if bytesRes.isErr:
      return err("certificate " & rel & ": " & bytesRes.error)
    let bytes = bytesRes.get
    if sha256Hex(bytes) != strOf(cert, "sha256"):
      return err("certificate " & rel & " does not hash to manifest.certs[].sha256")
    let docRes = parseStrictJson(bytes)
    if docRes.isErr:
      return err("certificate " & rel & ": " & docRes.error)
    if docRes.get.kind != JObject:
      return err("certificate " & rel & " is not a JSON object")
    certDocs.add(docRes.get)

  # Load and hash every shipped source blob.
  var sourceBytes = initTable[string, string]()
  var totalBytes = 0'i64
  for entry in entries:
    let path = strOf(entry, "path")
    let bytesRes = readBytesUnder(bundleDir, BundleSourceDir & "/" & path,
      MaxSourceFileBytes)
    if bytesRes.isErr:
      return err("source " & path & ": " & bytesRes.error)
    let bytes = bytesRes.get
    totalBytes += int64(bytes.len)
    if totalBytes > MaxTotalSourceBytes:
      return err("sources exceed MaxTotalSourceBytes")
    if sha256Hex(bytes) != strOf(entry, "sha256"):
      return err("source " & path & " does not hash to its source-index entry")
    sourceBytes[path] = bytes

  # Recompute the identity surface.
  if evidenceDigestFor(manifest) != strOf(manifest, "evidenceDigest"):
    problems.add("manifest.evidenceDigest does not recompute")
  if provenanceDigestFor(manifest) != strOf(manifest, "provenanceDigest"):
    problems.add("manifest.provenanceDigest does not recompute")
  if bundleDigestFor(manifest) != strOf(manifest, "bundleDigest"):
    problems.add("manifest.bundleDigest does not recompute")
  let subject = objOf(manifest, "subject")
  if subjectIdFor(strOf(subject, "repository"), strOf(subject, "commit"),
      strOf(subject, "treeDigest"), strOf(subject, "baseSha")) !=
      strOf(subject, "subjectId"):
    problems.add("manifest.subject.subjectId does not recompute")
  if problems.len > 0:
    return err("bundle content: " & problems.join("; "))

  ok(BundleContents(manifest: manifest, index: index, certDocs: certDocs,
    sourceBytes: sourceBytes))

# ─── cert evidence ──────────────────────────────────────────────────────────

func validateCertDoc(manifestCert, doc: JsonNode; problems: var seq[string]) {.raises: [].} =
  let irHash = strOf(manifestCert, "irHash")
  if doc.isNil or doc.kind != JObject:
    problems.add("certificate " & irHash & " is not an object")
    return
  if strOf(doc, "irHash") != irHash:
    problems.add("certificate " & irHash & ": irHash field disagrees with its manifest entry")
  let modulePath = strOf(doc, "modulePath")
  let functionName = strOf(doc, "functionName")
  if not isSafeRelativePath(modulePath):
    problems.add("certificate " & irHash & ": modulePath is not a safe relative path")
  if functionName.len == 0:
    problems.add("certificate " & irHash & ": functionName is empty")
  let status = strOf(doc, "status")
  if status != strOf(manifestCert, "status"):
    problems.add("certificate " & irHash & ": status disagrees with its manifest entry")
  if status notin VerifiedStatuses:
    problems.add("certificate " & irHash & ": status is not verified: " & status)
  if not statusConsistentWithEvidence(doc):
    problems.add("certificate " & irHash & ": status is stronger than its stored evidence")

  let leanSource = strOf(doc, "leanSource")
  if leanSource.len == 0:
    problems.add("certificate " & irHash & ": leanSource is empty")
  let leanSourceHash = strOf(doc, "leanSourceHash")
  if not isSha256Hex(leanSourceHash) or sha256Hex(leanSource) != leanSourceHash:
    problems.add("certificate " & irHash & ": leanSourceHash does not hash leanSource")
  if leanSourceHash != strOf(manifestCert, "leanSourceDigest"):
    problems.add("certificate " & irHash & ": leanSourceHash disagrees with the manifest")

  let propositionHash = strOf(doc, "propositionHash")
  if propositionHash != strOf(manifestCert, "propositionHash"):
    problems.add("certificate " & irHash & ": propositionHash disagrees with the manifest")
  let canonicalProposition = strOf(manifestCert, "canonicalProposition")
  if canonicalProposition.len == 0:
    problems.add("certificate " & irHash & ": manifest canonicalProposition is empty")
  elif sha256Hex(canonicalProposition) != propositionHash:
    problems.add("certificate " & irHash & ": canonicalProposition does not hash to propositionHash")

  let evidenceId = strOf(doc, "evidenceId")
  if evidenceId != strOf(manifestCert, "evidenceId"):
    problems.add("certificate " & irHash & ": evidenceId disagrees with the manifest")
  if evidenceId != evidenceIdFromCert(doc):
    problems.add("certificate " & irHash & ": evidenceId does not recompute from its fields")

  let canonicalKaa = strOf(doc, "canonicalKaa")
  if canonicalKaa.len == 0:
    problems.add("certificate " & irHash & ": canonicalKaa is empty")
  if sha256Hex(canonicalKaa) != strOf(doc, "kaaDigest"):
    problems.add("certificate " & irHash & ": kaaDigest does not hash canonicalKaa")
  let artifact = canonicalKaaArtifactIdentity(canonicalKaa)
  if artifact.len != 64:
    problems.add("certificate " & irHash & ": canonicalKaa carries no receiptArtifactIdentity")
  elif artifact != leanSourceHash:
    problems.add("certificate " & irHash & ": artifactIdentity does not equal leanSourceHash")
  if strOf(manifestCert, "artifactIdentity") != artifact:
    problems.add("certificate " & irHash & ": artifactIdentity disagrees with the manifest")

  let certAxioms = sortedAxioms(doc{"axiomsUsed"})
  if certAxioms.isErr:
    problems.add("certificate " & irHash & ": axiomsUsed: " & certAxioms.error)
  else:
    if not axiomsAllowlisted(certAxioms.get):
      problems.add("certificate " & irHash & ": axiomsUsed is outside the allowlist")
    let kaaAxioms = canonicalKaaObservedAxioms(canonicalKaa)
    if kaaAxioms.isErr:
      problems.add("certificate " & irHash & ": " & kaaAxioms.error)
    elif kaaAxioms.get != certAxioms.get:
      problems.add("certificate " & irHash & ": axiomsUsed does not equal the KAA-observed set")
    let manifestAxioms = sortedAxioms(manifestCert{"axiomsUsed"})
    if manifestAxioms.isErr or manifestAxioms.get != certAxioms.get:
      problems.add("certificate " & irHash & ": axiomsUsed disagrees with the manifest")

  if strOf(doc, "backend") != strOf(manifestCert, "backend"):
    problems.add("certificate " & irHash & ": backend disagrees with the manifest")

func validateCertEvidence(contents: BundleContents): seq[string] {.raises: [].} =
  result = @[]
  let certs = arrayOf(contents.manifest, "certs")
  for i in 0 ..< certs.len:
    validateCertDoc(certs[i], contents.certDocs[i], result)

# ─── subject binding ────────────────────────────────────────────────────────

func validateSubjectBinding(contents: BundleContents;
                            expectCommit: string): seq[string] {.raises: [].} =
  result = @[]
  let manifest = contents.manifest
  let subject = objOf(manifest, "subject")
  if expectCommit.len > 0 and strOf(subject, "commit") != expectCommit:
    result.add("manifest.subject.commit does not equal the expected commit")
  let entries = arrayOf(contents.index, "entries")
  var byPath = initTable[string, JsonNode]()
  for entry in entries:
    byPath[strOf(entry, "path")] = entry
  let certs = arrayOf(manifest, "certs")
  for i in 0 ..< certs.len:
    let doc = contents.certDocs[i]
    let irHash = strOf(certs[i], "irHash")
    let modulePath = strOf(doc, "modulePath")
    if not byPath.hasKey(modulePath):
      result.add("certificate " & irHash & ": modulePath is not in the source index: " & modulePath)
      continue
    let entry = byPath.getOrDefault(modulePath)
    let bytes = contents.sourceBytes.getOrDefault(modulePath)
    if sha256Hex(bytes) != strOf(entry, "sha256"):
      result.add("certificate " & irHash & ": source bytes do not match the index")
    let recorded = strOf(doc, "sourceHash")
    if recorded.len == 0:
      result.add("certificate " & irHash & ": sourceHash is empty")
    elif computeStableSourceFingerprint(bytes) != recorded:
      result.add("certificate " & irHash & ": sourceHash is not the shipped subject blob")

# ─── kernel re-execution ────────────────────────────────────────────────────

func kernelLegSkipped(reason: string): BundleLeg {.raises: [].} =
  BundleLeg(name: "kernel", status: blsSkipped, detail: reason)

proc verifyKernel(contents: BundleContents;
                  repoRoot: string): BundleLeg {.raises: [CatchableError].} =
  ## Re-execute the recorded kernels and compare the freshly observed axiom
  ## set with BOTH the certificate and the KAA projection. Prerequisites
  ## missing on this machine → SKIPPED (exit 3), never a pass.
  let toolchain = objOf(contents.manifest, "toolchain")
  let pinnedBuild = strOf(toolchain, "verifierBuildId")
  let liveBuild = measuredVerifierBuildId()
  if liveBuild == "unmeasured" or liveBuild.len != 64:
    return kernelLegSkipped("this verifier's build identity is unmeasured")
  if liveBuild != pinnedBuild:
    return BundleLeg(name: "kernel", status: blsFail,
      detail: "verifier build id " & liveBuild & " != pinned " & pinnedBuild)
  let liveApp = readAppSha256()
  if liveApp.isErr:
    return kernelLegSkipped(liveApp.error)
  if liveApp.get != strOf(toolchain, "verifierBundleSha256"):
    return BundleLeg(name: "kernel", status: blsFail,
      detail: "this verifier executable does not match verifierBundleSha256")
  if $NimVersion != strOf(toolchain, "nimVersion"):
    return BundleLeg(name: "kernel", status: blsFail,
      detail: "Nim " & $NimVersion & " != pinned " & strOf(toolchain, "nimVersion"))
  let toolchainFile = repoRoot / LeanToolchainPinPath
  let pinnedLeanFile =
    if fileExists(toolchainFile): readFile(toolchainFile).strip() else: ""
  if pinnedLeanFile != strOf(toolchain, "leanToolchainFile"):
    return BundleLeg(name: "kernel", status: blsFail,
      detail: "proofs/lean-toolchain does not match the pinned leanToolchainFile")
  let leanVersion = probeLeanVersion()
  if leanVersion.len == 0:
    return kernelLegSkipped("lean --version failed — the pinned Lean kernel is unavailable")
  if leanVersion != strOf(toolchain, "leanVersion"):
    return BundleLeg(name: "kernel", status: blsFail,
      detail: "Lean " & leanVersion & " != pinned " & strOf(toolchain, "leanVersion"))
  let z3Bin = resolveZ3Path()
  if z3Bin.len == 0 or not fileExists(z3Bin):
    return kernelLegSkipped("the pinned z3 binary is unavailable")
  let z3Sha = sha256Hex(readFile(z3Bin))
  if z3Sha != strOf(toolchain, "z3BinarySha256"):
    return BundleLeg(name: "kernel", status: blsFail,
      detail: "z3 binary sha256 != pinned z3BinarySha256")
  if not z3BinaryChecksumAccepted(z3Bin, repoRoot):
    return BundleLeg(name: "kernel", status: blsFail,
      detail: "z3 binary does not match data/policy/z3_binary_checksums.json")
  if BuildEnvZ3Version != strOf(toolchain, "z3Version"):
    return BundleLeg(name: "kernel", status: blsFail,
      detail: "z3 version " & BuildEnvZ3Version & " != pinned " & strOf(toolchain, "z3Version"))

  let checkerPin = strOf(toolchain, "leancheckerSha256")
  let checker = leanCheckerPath()
  var checkerRuns = false
  if checkerPin.len == 0:
    discard
  elif checker.len == 0:
    discard
  else:
    if sha256Hex(readFile(checker)) != checkerPin:
      return BundleLeg(name: "kernel", status: blsFail,
        detail: "leanchecker sha256 != pinned leancheckerSha256")
    checkerRuns = true

  let certs = arrayOf(contents.manifest, "certs")
  var failures: seq[string] = @[]
  var checkerSkipped = false
  for i in 0 ..< certs.len:
    let doc = contents.certDocs[i]
    let irHash = strOf(certs[i], "irHash")
    let lean = reexecuteLeanObserved(doc, "", KernelLegTimeoutMs)
    if lean.verdict != krPassed:
      failures.add(irHash & ": lean " & kernelVerdictReason(lean.verdict))
    else:
      var observed = lean.axes
      observed.sort()
      let recorded = sortedAxioms(certs[i]{"axiomsUsed"})
      if recorded.isErr or recorded.get != observed:
        failures.add(irHash & ": fresh lean axiom set (" & observed.join(",") &
          ") != recorded set")
      # Theorem identity: the axiom set above can agree while the source proves
      # a DIFFERENT declaration than the certificate names. A bundle that
      # records a claim must have it reproduced by the fresh run (DEBT#572).
      let recordedTheorem = strOf(doc, "theoremName")
      if recordedTheorem.len > 0 and lean.theoremName != recordedTheorem:
        failures.add(irHash & ": fresh run observed theorem '" & lean.theoremName &
          "' but the certificate claims '" & recordedTheorem & "'")
    let z3 = reexecuteZ3(doc, z3Bin, Z3ReexecTimeoutMs)
    if z3 != krPassed:
      failures.add(irHash & ": z3 " & kernelVerdictReason(z3))
    if checkerRuns:
      let deep = checkLeanWithLeanChecker(doc, checkerExe = checker,
        projectRoot = repoRoot, timeoutMs = KernelLegTimeoutMs)
      case deep
      of lcPassed: discard
      of lcMismatch: failures.add(irHash & ": " & leanCheckerVerdictReason(deep))
      of lcSkipped: checkerSkipped = true
    else:
      checkerSkipped = true

  if failures.len > 0:
    return BundleLeg(name: "kernel", status: blsFail,
      detail: failures.join("; "))
  result = BundleLeg(name: "kernel", status: blsPass,
    detail: $certs.len & " certificate(s) re-executed (lean + z3)" &
      (if checkerSkipped: "; leanchecker SKIPPED (no pinned checker on this machine)"
       else: "; leanchecker passed"))

# ─── external observations ──────────────────────────────────────────────────

proc checkAttestation(path: string; manifest: JsonNode): Result[seq[string], string] {.raises: [CatchableError].} =
  let parsed = loadStrictPath(path, MaxManifestBytes)
  if parsed.isErr:
    return err("attestation: " & parsed.error)
  var problems: seq[string] = @[]
  let doc = parsed.get
  checkClosed(doc, AttestationKeys, "attestation", problems)
  if doc.isNil or doc.kind != JObject:
    return err(problems.join("; "))
  if strOf(doc, "schema") != AttestationSchema:
    problems.add("attestation.schema must be " & AttestationSchema)
  if strOf(doc, "signerRepository") != "Archright/Axiom":
    problems.add("attestation.signerRepository must be Archright/Axiom")
  let verified = doc{"verified"}
  if verified.isNil or verified.kind != JBool or not verified.getBool:
    problems.add("attestation.verified must be true")
  if strOf(doc, "subjectDigestSha256") != strOf(manifest, "evidenceDigest"):
    problems.add("attestation.subjectDigestSha256 does not equal manifest.evidenceDigest")
  let run = objOf(doc, "run")
  checkClosed(run, RunKeys, "attestation.run", problems)
  if not run.isNil and run.kind == JObject:
    let manifestRun = objOf(manifest, "run")
    for key in RunKeys:
      if strOf(run, key) != strOf(manifestRun, key):
        problems.add("attestation.run." & key & " does not equal the manifest run")
  if problems.len > 0: err(problems.join("; ")) else: ok(problems)

proc checkCheckRuns(path: string; manifest: JsonNode): Result[seq[string], string] {.raises: [CatchableError].} =
  let parsed = loadStrictPath(path, MaxManifestBytes)
  if parsed.isErr:
    return err("check-runs: " & parsed.error)
  var problems: seq[string] = @[]
  let doc = parsed.get
  if doc.isNil or doc.kind != JObject:
    return err("check-runs: top-level must be an object")
  let arr = arrayOf(doc, "check_runs")
  if arr.isNil:
    return err("check-runs: check_runs must be an array")
  let total = intOf(doc, "total_count", arr.len)
  if total < 0:
    return err("check-runs: total_count must be a non-negative integer")
  if total > arr.len:
    return err("check-runs: truncated read (total_count=" & $total &
      " > fetched=" & $arr.len & ") — fail-closed")
  let headSha = strOf(objOf(manifest, "run"), "headSha")
  var matching = 0
  var succeeded = 0
  for run in arr:
    if run.isNil or run.kind != JObject: continue
    if strOf(run, "name") != "admission-check": continue
    if strOf(run, "head_sha") != headSha: continue
    let app = objOf(run, "app")
    if intOf(app, "id") != AdmissionAppId: continue
    inc matching
    let status = strOf(run, "status")
    let conclusion = strOf(run, "conclusion")
    if status == "completed" and conclusion == "success":
      inc succeeded
    else:
      problems.add("admission-check run " & strOf(run, "id") & " is status=" &
        status & " conclusion=" & conclusion)
  if matching == 0:
    problems.add("no admission-check check-run from app " & $AdmissionAppId &
      " for head " & headSha)
  elif succeeded == 0 and problems.len == 0:
    problems.add("no successful admission-check run for head " & headSha)
  if problems.len > 0: err(problems.join("; ")) else: ok(problems)

proc checkRuleset(path: string): Result[seq[string], string] {.raises: [CatchableError].} =
  let parsed = loadStrictPath(path, MaxManifestBytes)
  if parsed.isErr:
    return err("ruleset: " & parsed.error)
  var problems: seq[string] = @[]
  let doc = parsed.get
  if doc.isNil or doc.kind != JObject:
    return err("ruleset: top-level must be an object")
  if intOf(doc, "id") != AdmissionRulesetId:
    problems.add("ruleset.id must be " & $AdmissionRulesetId)
  if strOf(doc, "enforcement") != "active":
    problems.add("ruleset.enforcement must be active")
  let bypass = doc{"bypass_actors"}
  if bypass.isNil or bypass.kind != JArray or bypass.len != 0:
    problems.add("ruleset.bypass_actors must be an empty array")
  var found = false
  let rules = arrayOf(doc, "rules")
  if rules.isNil:
    problems.add("ruleset.rules must be an array")
  else:
    for rule in rules:
      if rule.isNil or rule.kind != JObject: continue
      if strOf(rule, "type") != "required_status_checks": continue
      let params = objOf(rule, "parameters")
      let checks = arrayOf(params, "required_status_checks")
      if checks.isNil: continue
      for entry in checks:
        if entry.isNil or entry.kind != JObject: continue
        if strOf(entry, "context") == "admission-check" and
            intOf(entry, "integration_id") == AdmissionAppId:
          found = true
  if not found:
    problems.add("ruleset has no required admission-check context from app " &
      $AdmissionAppId)
  if problems.len > 0: err(problems.join("; ")) else: ok(problems)

# ─── orchestration ──────────────────────────────────────────────────────────

proc verifyEvidenceBundle*(opts: BundleVerifyOptions): BundleVerifyOutcome {.raises: [CatchableError].} =
  var legs: seq[BundleLeg] = @[]
  if opts.bundleDir.len == 0 or not dirExists(opts.bundleDir):
    legs.addLeg("bundleContent", blsFail, "bundle directory does not exist")
    legs.addLeg("certEvidence", blsSkipped, "bundle content unavailable")
    legs.addLeg("subjectBinding", blsSkipped, "bundle content unavailable")
    legs.addLeg("kernel", (if opts.runKernel: blsSkipped else: blsNotChecked),
      "bundle content unavailable")
    legs.addLeg("provenance", blsNotChecked, "not requested")
    legs.addLeg("mergeAuthority", blsNotChecked, "not requested")
    return BundleVerifyOutcome(exitCode: 1, legs: legs)

  let loaded = loadBundle(opts.bundleDir)
  if loaded.isErr:
    legs.addLeg("bundleContent", blsFail, loaded.error)
    legs.addLeg("certEvidence", blsSkipped, "bundle content unavailable")
    legs.addLeg("subjectBinding", blsSkipped, "bundle content unavailable")
    legs.addLeg("kernel", (if opts.runKernel: blsSkipped else: blsNotChecked),
      "bundle content unavailable")
    legs.addLeg("provenance", blsNotChecked, "bundle content unavailable")
    legs.addLeg("mergeAuthority", blsNotChecked, "bundle content unavailable")
    return BundleVerifyOutcome(exitCode: 1, legs: legs)

  let contents = loaded.get
  let manifest = contents.manifest
  legs.addLeg("bundleContent", blsPass,
    $arrayOf(manifest, "certs").len & " cert(s), " &
      $arrayOf(contents.index, "entries").len & " source file(s); digests recomputed")

  let certProblems = validateCertEvidence(contents)
  if certProblems.len > 0:
    legs.addLeg("certEvidence", blsFail, certProblems.join("; "))
  else:
    legs.addLeg("certEvidence", blsPass, "certificate identity fields recompute")

  let subjectProblems = validateSubjectBinding(contents, opts.expectCommit)
  if subjectProblems.len > 0:
    legs.addLeg("subjectBinding", blsFail, subjectProblems.join("; "))
  else:
    legs.addLeg("subjectBinding", blsPass,
      "sources/ bytes, treeDigest, subjectId and cert sourceHash agree")

  if opts.runKernel:
    try:
      legs.add(verifyKernel(contents, resolveRepoRoot()))
    except CatchableError as e:
      legs.addLeg("kernel", blsFail, "kernel re-execution raised: " & e.msg)
  else:
    legs.addLeg("kernel", blsNotChecked, "not requested (--kernel)")

  if opts.attestationPath.len == 0:
    legs.addLeg("provenance", blsNotChecked, "no --attestation input")
  else:
    let att = checkAttestation(opts.attestationPath, manifest)
    if att.isErr:
      legs.addLeg("provenance", blsFail, att.error)
    else:
      legs.addLeg("provenance", blsPass,
        "normalized attestation binds evidenceDigest and run envelope (Sigstore NOT re-verified)")

  if opts.checkRunsPath.len == 0 and opts.rulesetPath.len == 0:
    legs.addLeg("mergeAuthority", blsNotChecked, "no --check-runs / --ruleset input")
  else:
    var authorityProblems: seq[string] = @[]
    var checked = 0
    if opts.checkRunsPath.len > 0:
      inc checked
      let runs = checkCheckRuns(opts.checkRunsPath, manifest)
      if runs.isErr: authorityProblems.add(runs.error)
    if opts.rulesetPath.len > 0:
      inc checked
      let ruleset = checkRuleset(opts.rulesetPath)
      if ruleset.isErr: authorityProblems.add(ruleset.error)
    if authorityProblems.len > 0:
      legs.addLeg("mergeAuthority", blsFail, authorityProblems.join("; "))
    elif checked == 2:
      legs.addLeg("mergeAuthority", blsPass,
        "admission-check run + ruleset 27097366 observed")
    else:
      legs.addLeg("mergeAuthority", blsNotChecked,
        "one observation supplied; the other is NOT_CHECKED")

  var hasFail = false
  var kernelSkipped = false
  for leg in legs:
    if leg.status == blsFail: hasFail = true
    if leg.name == "kernel" and leg.status == blsSkipped: kernelSkipped = true
  let exitCode = if hasFail: 1 elif kernelSkipped: 3 else: 0

  result = BundleVerifyOutcome(
    exitCode: exitCode,
    legs: legs,
    evidenceDigest: strOf(manifest, "evidenceDigest"),
    provenanceDigest: strOf(manifest, "provenanceDigest"),
    bundleDigest: strOf(manifest, "bundleDigest"),
    certCount: arrayOf(manifest, "certs").len)

func verifyOutcomeJson*(outcome: BundleVerifyOutcome): JsonNode {.raises: [].} =
  var legs = newJArray()
  for leg in outcome.legs:
    legs.add(%*{"name": leg.name, "status": legStatusText(leg.status),
                "detail": leg.detail})
  result = newJObject()
  result["schema"] = %"axiom.evidence-bundle.verify.v1"
  result["exitCode"] = %outcome.exitCode
  result["legs"] = legs
  result["evidenceDigest"] = %outcome.evidenceDigest
  result["provenanceDigest"] = %outcome.provenanceDigest
  result["bundleDigest"] = %outcome.bundleDigest
  result["certCount"] = %outcome.certCount

{.pop.}