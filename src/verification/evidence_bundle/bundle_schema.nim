import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Evidence Bundle v2 — schema constants and digest definitions.
##
## The manifest is the bundle's identity surface. Three digests are kept
## separate on purpose (D6 separation — provenance never enters a semantic
## digest):
##
##   evidenceDigest   = H(schema | subject | toolchain pin | policy | certs)
##   provenanceDigest = H(run | evidenceDigest)
##   bundleDigest     = H(entire manifest minus bundleDigest)
##
## `evidenceDigest` is run-independent: the same subject, cert set, toolchain
## pin, and policy produce the same value in every run. `provenanceDigest`
## adds the run envelope (runId/attempt/workflow/event/headSha) and therefore
## MUST NOT be used as a semantic identity across runs.
##
## `treeDigest` is the sha256 of the canonical source index
## `{path, mode, sha256}` over every entry of the subject commit's git tree.
## It binds the bytes shipped in `sources/`; it does NOT prove that a Git
## commit with that tree exists. That claim belongs to the provenance axis
## (GitHub attestation / commit API), never to this digest.

import std/json
import std/algorithm
import std/strutils
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results
import verification/canonical_json
import verification/evidence_bundle/strict_json

const
  BundleSchema* = "axiom.evidence-bundle.v2"
  SourceIndexSchema* = "axiom.evidence-bundle.sources.v1"
  TreeDigestScheme* = "axiom.evidence-bundle.tree.v1"
  SubjectIdScheme* = "axiom.evidence-bundle.subject.v1"
  EvidenceIdSeparator* = "|"

  ManifestKeys* = ["schema", "subject", "run", "toolchain", "policy",
                   "certs", "counts", "sourceVault", "evidenceDigest",
                   "provenanceDigest", "bundleDigest"]
  SubjectKeys* = ["repository", "commit", "treeDigest", "baseSha", "subjectId"]
  RunKeys* = ["runId", "runAttempt", "workflowPath", "workflowRef", "event", "headSha"]
  ToolchainKeys* = ["verifierBuildId", "verifierBundleSha256", "nimVersion",
                    "leanToolchainFile", "leanVersion", "leancheckerSha256",
                    "z3Version", "z3BinarySha256"]
  PolicyKeys* = ["policyDigest", "scopeDigest"]
  CertKeys* = ["irHash", "propositionHash", "canonicalProposition",
               "evidenceId", "subjectId", "path", "sha256", "status",
               "axiomsUsed", "backend", "leanSourceDigest", "artifactIdentity"]
  CountsKeys* = ["certs", "kernelSymbols"]
  SourceIndexKeys* = ["schema", "repository", "commit", "treeOid", "entries"]
  SourceEntryKeys* = ["path", "mode", "sha256"]

  VerifiedStatuses* = ["certGreen", "certLeanVerified", "certDualVerified",
                       "certVerifiedAxiom"]
  AxiomAllowlist* = ["propext", "Classical.choice", "Quot.sound", "funext"]

  MaxCerts* = 4096
  MaxSourceFiles* = 20000
  MaxCertBytes* = 8 * 1024 * 1024
  MaxSourceFileBytes* = 8 * 1024 * 1024
  MaxTotalSourceBytes* = 64 * 1024 * 1024

func isHexOfLen*(s: string; n: int): bool {.raises: [].} =
  if s.len != n: return false
  for ch in s:
    if ch notin {'0'..'9', 'a'..'f'}: return false
  true

func isSha256Hex*(s: string): bool {.raises: [].} =
  isHexOfLen(s, 64)

func isGitOid*(s: string): bool {.raises: [].} =
  isHexOfLen(s, 40)

func hasKeys*(node: JsonNode; keys: openArray[string]): bool {.raises: [].} =
  ## Closed-object membership test (extra keys are NOT allowed).
  if node.isNil or node.kind != JObject: return false
  if node.len != keys.len: return false
  for k in keys:
    if not node.hasKey(k): return false
  true

func unknownKeys*(node: JsonNode; keys: openArray[string]): seq[string] {.raises: [].} =
  ## Keys present on `node` but absent from the closed set, sorted.
  result = @[]
  if node.isNil or node.kind != JObject: return
  for k in node.keys:
    var known = false
    for allowed in keys:
      if k == allowed:
        known = true
        break
    if not known: result.add(k)
  result.sort()

func missingKeys*(node: JsonNode; keys: openArray[string]): seq[string] {.raises: [].} =
  result = @[]
  if node.isNil or node.kind != JObject:
    for k in keys: result.add(k)
    return
  for k in keys:
    if not node.hasKey(k): result.add(k)

func strOf*(node: JsonNode; key: string; default = ""): string {.raises: [].} =
  if node.isNil or node.kind != JObject: return default
  let v = node{key}
  if v.isNil or v.kind != JString: default else: v.getStr()

func intOf*(node: JsonNode; key: string; default = -1): int {.raises: [].} =
  if node.isNil or node.kind != JObject: return default
  let v = node{key}
  if v.isNil or v.kind != JInt: default else: v.getInt()

func arrayOf*(node: JsonNode; key: string): JsonNode {.raises: [].} =
  if node.isNil or node.kind != JObject: return nil
  let v = node{key}
  if v.isNil or v.kind != JArray: nil else: v

func objOf*(node: JsonNode; key: string): JsonNode {.raises: [].} =
  if node.isNil or node.kind != JObject: return nil
  let v = node{key}
  if v.isNil or v.kind != JObject: nil else: v

func subjectIdFor*(repository, commit, treeDigest, baseSha: string): string {.raises: [].} =
  ## Run-independent subject identity. The commit is a label here; binding a
  ## commit OID to a real Git object is the provenance axis' job.
  sha256Hex(SubjectIdScheme & "|" & repository & "|" & commit & "|" &
    treeDigest & "|" & baseSha)

func treeDigestFor*(entries: JsonNode): string {.raises: [].} =
  ## Canonical source-index digest. Entry order in the input is irrelevant:
  ## the projection sorts by path.
  var sorted = newJArray()
  if not entries.isNil and entries.kind == JArray:
    var rows: seq[JsonNode] = @[]
    for e in entries:
      if not e.isNil and e.kind == JObject:
        rows.add(e)
    rows.sort(proc(a, b: JsonNode): int = cmp(strOf(a, "path"), strOf(b, "path")))
    for e in rows:
      var row = newJObject()
      row["path"] = %strOf(e, "path")
      row["mode"] = %strOf(e, "mode")
      row["sha256"] = %strOf(e, "sha256")
      sorted.add(row)
  var projection = newJObject()
  projection["schema"] = %TreeDigestScheme
  projection["entries"] = sorted
  sha256Hex(canonicalJsonString(projection))

func evidenceIdFromFields*(obligationId, propositionHash, leanSourceHash,
                           kaaDigest, toolchainFingerprint,
                           executionContractDigest,
                           completenessBindingDigest: string): string {.raises: [].} =
  ## Mirror of `kernel_acceptance_authority.evidenceId` over certificate
  ## fields. The strict-completeness extension appends the binding digest as
  ## the seventh component; a legacy certificate is byte-for-byte unchanged.
  var legacy = obligationId & EvidenceIdSeparator &
    propositionHash & EvidenceIdSeparator &
    leanSourceHash & EvidenceIdSeparator &
    kaaDigest & EvidenceIdSeparator &
    toolchainFingerprint & EvidenceIdSeparator &
    executionContractDigest
  if completenessBindingDigest.len > 0:
    legacy = legacy & EvidenceIdSeparator & completenessBindingDigest
  sha256Hex(legacy)

func evidenceIdFromCert*(cert: JsonNode): string {.raises: [].} =
  evidenceIdFromFields(
    strOf(cert, "obligationId"),
    strOf(cert, "propositionHash"),
    strOf(cert, "leanSourceHash"),
    strOf(cert, "kaaDigest"),
    strOf(cert, "toolchainFingerprint"),
    strOf(cert, "executionContractDigest"),
    strOf(cert, "completenessBindingDigest"))

func canonicalKaaArtifactIdentity*(canonicalKaa: string): string {.raises: [].} =
  ## `artifactIdentity` is carried inside the canonical KAA projection as
  ## `receiptArtifactIdentity`. A malformed projection yields "" (fail-closed
  ## at the caller).
  if canonicalKaa.len == 0: return ""
  let parsed = parseStrictJson(canonicalKaa)
  if parsed.isErr: return ""
  let node = parsed.get
  if node.kind != JObject: return ""
  strOf(node, "receiptArtifactIdentity")

func canonicalKaaObservedAxioms*(canonicalKaa: string): Result[seq[string], string] {.
  raises: [], axiomDecision(id = "DECISION-0834",
    reason = "KAA axiom observation is fail-closed: malformed projections yield an err, never an empty trusted set",
    adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "VS-2a").} =
  ## The KAA-observed axiom set, in canonical (sorted, deduped) form. Used to
  ## cross-check the certificate's serialized `axiomsUsed` field.
  if canonicalKaa.len == 0: return err("canonicalKaa is empty")
  let parsed = parseStrictJson(canonicalKaa)
  if parsed.isErr: return err("canonicalKaa is not strict JSON: " & parsed.error)
  let node = parsed.get
  if node.kind != JObject: return err("canonicalKaa is not an object")
  let ax = node{"observedAxiomSet"}
  if ax.isNil or ax.kind != JArray:
    return err("canonicalKaa.observedAxiomSet is not an array")
  var names: seq[string] = @[]
  for item in ax:
    if item.kind != JString:
      return err("canonicalKaa.observedAxiomSet contains a non-string")
    let name = item.getStr()
    if name.len == 0:
      return err("canonicalKaa.observedAxiomSet contains an empty name")
    if name notin names: names.add(name)
  names.sort()
  ok(names)

func sortedAxioms*(node: JsonNode): Result[seq[string], string] {.
  raises: [], axiomDecision(id = "DECISION-0835",
    reason = "Axiom-set parsing is fail-closed: duplicates, non-strings and empty names are errs",
    adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "VS-2a").} =
  if node.isNil or node.kind != JArray:
    return err("axiomsUsed is not an array")
  var names: seq[string] = @[]
  for item in node:
    if item.kind != JString:
      return err("axiomsUsed contains a non-string")
    let name = item.getStr()
    if name.len == 0:
      return err("axiomsUsed contains an empty name")
    if name in names:
      return err("axiomsUsed contains a duplicate name: " & name)
    names.add(name)
  names.sort()
  ok(names)

func axiomAllowed*(name: string): bool {.raises: [].} =
  if name.len == 0: return false
  let lower = name.toLowerAscii()
  if "sorry" in lower or "trustcompiler" in lower or "native_decide" in lower:
    return false
  name in AxiomAllowlist

func axiomsAllowlisted*(names: openArray[string]): bool {.raises: [].} =
  for name in names:
    if not axiomAllowed(name): return false
  true

func evidenceDigestFor*(manifest: JsonNode): string {.raises: [].} =
  var projection = newJObject()
  projection["schema"] = manifest{"schema"}
  projection["subject"] = manifest{"subject"}
  projection["toolchain"] = manifest{"toolchain"}
  projection["policy"] = manifest{"policy"}
  projection["certs"] = manifest{"certs"}
  sha256Hex(canonicalJsonString(projection))

func provenanceDigestFor*(manifest: JsonNode): string {.raises: [].} =
  var projection = newJObject()
  projection["run"] = manifest{"run"}
  projection["evidenceDigest"] = manifest{"evidenceDigest"}
  sha256Hex(canonicalJsonString(projection))

func bundleDigestFor*(manifest: JsonNode): string {.raises: [].} =
  if manifest.isNil or manifest.kind != JObject: return ""
  var projection = newJObject()
  for k, v in manifest.pairs:
    if k != "bundleDigest":
      projection[k] = v
  sha256Hex(canonicalJsonString(projection))

func sourceIndexProjectionDigest*(index: JsonNode): string {.raises: [].} =
  ## Digest over the entries of a `sources/source-index.json` document.
  treeDigestFor(arrayOf(index, "entries"))

func canonicalManifestText*(manifest: JsonNode): string {.raises: [].} =
  canonicalJsonString(manifest) & "\n"

{.pop.}