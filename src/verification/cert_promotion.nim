import core/trusted/layer_declaration
axiomLayer "infrastructure"
import std/[os, json, strutils, tables, sequtils, options]
import checksums/sha2
import core/axiom_pragmas
import core/types/results
import core/json/json_utils
import core/utils/io_utils
import core/crypto/hash_kernel
import core/trusted/stdlib_shield
import core/trusted/provenance_guard
import core/trusted/trust_commit
import core/trusted/evidence_calculus
import core/types/verification_tier
import core/types/certificate_types
import verification/cert_vault_role
import verification/certificate_manager
import verification/cert_writer
import verification/certificate_eligibility
import verification/canonical_certificate_payload
import verification/cert_reconcile

## ─── Promotion Gate ───────────────────────────────────────
## Validates candidate certificates in build/certificates/ before allowing
## promotion to the runtime canonical vault (data/trusted/certificates/).
## All gate functions are pure (no I/O, no raises).

type
  PromotionStatus* = enum
    psAllowed
    psRejected
    psError

  PromotionGate* = object
    verdict*: PromotionStatus
    reason*: string

  CandidateEvidence* = object
    modulePath*: string
    functionName*: string
    irHash*: string
    fingerprint*: string
    contentHash*: string
    status*: string
    lifecycleStage*: string
    backend*: string

func isHex*(s: string): bool {.axiomDecision(id = "DECISION-0635", reason = "Pure hex validation helper for fingerprint contentHash checks in promotion gate", adr = "docs/spec/verification_result_types.md", introduced = "v32"), raises: [].} =
  if s.len == 0:
    return false
  for ch in s:
    if ch notin {'0'..'9', 'a'..'f', 'A'..'F'}:
      return false
  true

func validateFingerprint*(fingerprint: string): bool {.raises: [].} =
  fingerprint.len > 0 and isHex(fingerprint)

func validateContentHash*(contentHash: string): bool {.raises: [].} =
  contentHash.startsWith("sha256:") and contentHash.len > 7

func isPromotionAllowedStatus*(status: string): bool {.raises: [].} =
  ## v3 canonical promotion-allowed terminal statuses. certZ3Candidate
  ## (Z3-only evidence) is candidate-only — never promoted to
  ## certGreen or verified status. certNoObligation is excluded:
  ## no-obligation nodes have no semantic evidence to promote and
  ## are explicitly classified at the loop_driver entry.
  case status
  of "certGreen", "certLeanVerified", "certYellow":
    true
  else:
    false

func promotionAllowsNegativeFixture*(status: string): bool {.raises: [].} =
  status == "certRed"

func checkCandidateIdentity*(candidate: CandidateEvidence): PromotionGate {.raises: [].} =
  if candidate.modulePath.len == 0:
    PromotionGate(verdict: psRejected, reason: "identity check failed: empty modulePath")
  elif candidate.functionName.len == 0:
    PromotionGate(verdict: psRejected, reason: "identity check failed: empty functionName")
  else:
    PromotionGate(verdict: psAllowed, reason: "")

func checkCandidateFingerprint*(candidate: CandidateEvidence): PromotionGate {.raises: [].} =
  ## v3 canonical semantics: identity is content-addressed by irHash and bound by
  ## identityDigest (enforced via verifyIdentityBinding in the R4 aggregate). The
  ## legacy self-referential `contentHash` field is NOT part of the v3 schema, so
  ## it is not required here; fingerprint (a hex digest) remains a well-formedness
  ## gate. This is the single PROMOTE(c) fingerprint contract.
  if not validateFingerprint(candidate.fingerprint):
    PromotionGate(verdict: psRejected, reason: "fingerprint check failed: not well-formed hex")
  else:
    PromotionGate(verdict: psAllowed, reason: "")

func checkCandidatePolicy*(candidate: CandidateEvidence; allowNegativeFixture: bool): PromotionGate {.raises: [].} =
  if isPromotionAllowedStatus(candidate.status):
    PromotionGate(verdict: psAllowed, reason: "")
  elif candidate.status == "certRed" and allowNegativeFixture:
    PromotionGate(verdict: psAllowed, reason: "certRed allowed with allowNegativeFixture=true")
  elif candidate.status == "certRed":
    PromotionGate(verdict: psRejected, reason: "certRed requires allowNegativeFixture=true for promotion")
  else:
    PromotionGate(verdict: psRejected, reason: "status not promotion-allowed: " & candidate.status)

func checkBaselineEligibility*(candidate: CandidateEvidence; canonicalCount: int): PromotionGate {.raises: [].} =
  if canonicalCount == 0 and candidate.modulePath.len == 0:
    PromotionGate(verdict: psRejected, reason: "baseline eligibility failed: empty candidate in empty canonical set")
  else:
    PromotionGate(verdict: psAllowed, reason: "")

func promoteVerdict*(candidate: CandidateEvidence; existingModulePath, existingFunctionName: string; canonicalCount: int; allowNegativeFixture: bool): PromotionGate {.raises: [].} =
  let idGate = checkCandidateIdentity(candidate)
  if idGate.verdict != psAllowed:
    return idGate
  let fpGate = checkCandidateFingerprint(candidate)
  if fpGate.verdict != psAllowed:
    return fpGate
  let policyGate = checkCandidatePolicy(candidate, allowNegativeFixture)
  if policyGate.verdict != psAllowed:
    return policyGate
  let baseGate = checkBaselineEligibility(candidate, canonicalCount)
  if baseGate.verdict != psAllowed:
    return baseGate
  PromotionGate(verdict: psAllowed, reason: "all checks passed")

func promote*(candidate: CandidateEvidence; existingModulePath, existingFunctionName: string; canonicalCount: int; allowNegativeFixture: bool): PromotionGate {.raises: [].} =
  promoteVerdict(candidate, existingModulePath, existingFunctionName, canonicalCount, allowNegativeFixture)

## ─── Promotion Active Control ─────────────────────────────

proc setPromotionActive*() {.axiomDecision(id = "DECISION-0631", reason = "Enables the canonical write chokepoint so promotion context allows direct cert write to data/trusted/certificates (runtime canonical store)", adr = "docs/spec/hermetic_gate_framework.md", introduced = "v32").} =
  promotionActive = true

proc clearPromotionActive*() {.axiomDecision(id = "DECISION-0632", reason = "Disables the canonical write chokepoint after promotion completes; restores fail-closed guard", adr = "docs/spec/hermetic_gate_framework.md", introduced = "v32").} =
  promotionActive = false

## ─── Promotion Result ─────────────────────────────────────

type
  PromotionResult* = Result[string, string]

## ─── TrustCommit Journal Base ──────────────────────────────

proc journalBaseFor*(dir: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Promotion and reclassification TrustCommits land in the SAME journal root
  ## the verification commit used: AXIOM_STATE_DIR when set, else the repo
  ## anchor, else `dir`. A promotion written to a different root than the
  ## certificate's trustCommitId makes the promoted claim unreadable.
  activeJournalRoot(dir)

## ─── Promote to Canonical (I/O boundary) ─────────────────────────

proc updateManifestForPromotion*(canonicalDir, candidatePath, irHash: string; candidate: CandidateEvidence): bool {.axiomDecision(id = "DECISION-0634", reason = "Updates manifest.json after a successful promotion to include the new canonical entry with lifecycleStage=canonical", adr = "docs/spec/hermetic_gate_framework.md", introduced = "v32"), axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let manifestPath = joinPath(canonicalDir, "manifest.json")
  var manifest: JsonNode
  if fileExists(manifestPath):
    let manifestOpt = readJsonFile(manifestPath)
    if manifestOpt.isSome:
      manifest = manifestOpt.get()
    else:
      manifest = newJObject()
  else:
    manifest = newJObject()
  if manifest.kind != JObject:
    manifest = newJObject()
  if not manifest.hasKey("entries"):
    manifest["entries"] = newJArray()
  if not manifest.hasKey("version"):
    manifest["version"] = newJInt(2)
  if not manifest.hasKey("fingerprint"):
    manifest["fingerprint"] = newJString("")
  var newEntries = newJArray()
  var found = false
  let entries = manifest["entries"]
  for i in 0 ..< entries.len:
    let e = entries[i]
    if e.kind == JObject and e{"irHash"}.getStr("") == irHash:
      newEntries.add %*{
        "modulePath": candidate.modulePath,
        "functionName": candidate.functionName,
        "irHash": irHash,
        "fingerprint": candidate.fingerprint,
        "contentHash": candidate.contentHash,
        "status": candidate.status,
        "backend": candidate.backend,
        "lifecycleStage": "canonical"
      }
      found = true
    else:
      newEntries.add e
  if not found:
    newEntries.add %*{
      "modulePath": candidate.modulePath,
      "functionName": candidate.functionName,
      "irHash": irHash,
      "fingerprint": candidate.fingerprint,
      "contentHash": candidate.contentHash,
      "status": candidate.status,
      "backend": candidate.backend,
      "lifecycleStage": "canonical"
    }
  manifest["entries"] = newEntries
  try:
    let tmpPath = manifestPath & ".tmp"
    writeFile(tmpPath, pretty(manifest) & "\n")
    safeMoveFile(tmpPath, manifestPath)
    return true
  except CatchableError:
    return false

proc promoteToCanonical*(candidatePath: string; allowNegativeFixture: bool = false; candidateRoot: string = resolveCertificate(cvTransientWrite)): PromotionResult {.axiomDecision(id = "DECISION-0633", reason = "Validates candidate via gate, then copies cert into runtime canonical vault (data/trusted/certificates/) under promotion context; reverts on any failure", adr = "docs/spec/hermetic_gate_framework.md", introduced = "v32"), axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let canonicalDir = resolveCertificate(cvRuntimeCanonical)
  let buildDir = candidateRoot
  if not fileExists(candidatePath):
    return err("candidate file does not exist: " & candidatePath)
  if not candidatePath.startsWith(buildDir):
    return err("candidate must be staged under the write vault (" & buildDir & "): " & candidatePath)
  let content = try: readFile(candidatePath) except CatchableError: return err("failed to read candidate file: " & candidatePath)
  let node = try: parseJson(content) except CatchableError: return err("candidate is not valid JSON: " & candidatePath)
  if node.kind != JObject:
    return err("candidate must be a JSON object")
  let candidate = CandidateEvidence(
    modulePath: node{"modulePath"}.getStr(""),
    functionName: node{"functionName"}.getStr(""),
    irHash: node{"irHash"}.getStr(""),
    fingerprint: node{"fingerprint"}.getStr(""),
    contentHash: node{"contentHash"}.getStr(""),
    status: node{"status"}.getStr(""),
    lifecycleStage: node{"lifecycleStage"}.getStr(""),
    backend: node{"backend"}.getStr("")
  )
  if candidate.irHash.len == 0:
    return err("candidate missing irHash")
  let canonicalCount = 0
  let gate = promoteVerdict(candidate, candidate.modulePath, candidate.functionName, canonicalCount, allowNegativeFixture)
  if gate.verdict != psAllowed:
    return err("promotion gate rejected: " & gate.reason)
  ## R4 aggregate: single promotion/write gate. No promotion may
  ## bypass this eligibility check. The existing promoteVerdict
  ## identity/fingerprint/contentHash checks remain as internal
  ## conjuncts (they are verifiers inside the aggregate).
  let bundle = toEvidenceBundle(certificateEvidenceFromJson(node))
  proc deepVerifyCallback(cert: JsonNode; certPath: string): bool {.nimcall, raises: [].} =
    ## Minimal deep-verify callback for promotion gate.
    ## Checks fingerprint validity and sourceHash presence.
    ## Full isDeepVerified is injected at the call site (DIP).
    let fp = cert.getOrDefault("fingerprint").getStr("")
    if fp.len == 0:
      return false
    if not isHex(fp):
      return false
    let sourceHash = cert.getOrDefault("sourceHash").getStr("")
    if sourceHash.len == 0:
      return false
    true
  let promoRequiredVerifiers = case node{"status"}.getStr("")
    of "certGreen":
      @["verifySemanticEvidence", "verifyAcceptance", "verifyIdentityBinding", "verifyCertificateCompleteness"]
    of "certZ3Candidate", "certLeanVerified":
      # certNoObligation is intentionally absent: it has no obligation and
      # no semantic evidence; it is handled as orchestrationNoObligation
      # upstream and is never promoted.
      @["verifySemanticEvidence", "verifyIdentityBinding", "verifyCertificateCompleteness"]
    else:
      @["verifySemanticEvidence", "verifyIdentityBinding", "verifyCertificateCompleteness"]
  let promoResults = @[
    verifySemanticEvidence(node),
    verifyAcceptance(node, bundle, deepVerifyCallback),
    verifyIdentityBinding(node),
    verifyCertificateCompleteness(node)
  ]
  let promoEligibility = aggregate(promoRequiredVerifiers, promoResults)
  if not promoEligibility.eligible:
    return err("promotion aggregate gate rejected: " & promoEligibility.reasons.join("; "))
  # v3 canonical identity is established by the aggregate's verifyIdentityBinding
  # (recomputes v3IdentityFromJson against the stored identityDigest) above; the
  # legacy self-referential `contentHash` equality (contentHash == hash of the
  # bytes that include that very field) is unsatisfiable by construction and is
  # NOT a v3 requirement. Instead we DERIVE a contentHash from the candidate file
  # bytes and carry it into the canonical manifest as an honest catalog hash.
  let derivedContentHash = "sha256:" & $secureHash(Sha_256, content)
  let destPath = joinPath(canonicalDir, candidate.irHash & ".json")
  var manifestCandidate = candidate
  manifestCandidate.contentHash = derivedContentHash
  var existingBytes = ""
  var replacingSameEvidence = false
  if fileExists(destPath):
    ## C4 idempotency is established by CANONICAL IDENTITY, not raw persisted
    ## bytes. Two files whose semantic payloads project to the same v3 identity
    ## are the SAME certificate — even if their on-disk bytes differ only
    ## cosmetically (legacy trailing newline, field formatting). The aggregate
    ## gate above (verifyIdentityBinding) has already re-validated `node`'s
    ## fields, so a tampered value cannot be self-blessed here.
    let existingOpt = try: readJsonFile(destPath) except CatchableError: none(JsonNode)
    if existingOpt.isSome and sameCanonicalIdentity(existingOpt.get(), node):
      return ok("candidate already present in canonical vault (canonical identity idempotent): " & candidatePath)
    ## The v3 identity binds the subject git ref (via evidenceId/obligationId),
    ## so a re-verification after ANY commit/merge yields a new identity for
    ## the SAME function-level evidence. The cache key here is irHash, not the
    ## subject ref: when the semantic evidence key matches, the current
    ## candidate is the authoritative projection and replaces the stale cache.
    ## A genuinely different evidence key remains a hard conflict.
    let existingKey = if existingOpt.isSome: journalEvidenceKey(existingOpt.get()) else: ""
    let candidateKey = journalEvidenceKey(node)
    let existingStrict = existingOpt.isSome and isStrictContractClaim(existingOpt.get())
    let candidateStrict = isStrictContractClaim(node)
    if existingStrict and not candidateStrict:
      # One-way generation cutover: a strict canonical projection may be
      # superseded by a strict re-verification, never downgraded to a legacy
      # projection for the same irHash.
      return err("refusing to replace a strict-generation canonical certificate with a legacy projection for irHash " &
        candidate.irHash)
    if existingKey.len == 0 or existingKey != candidateKey:
      let existingIdentity =
        if existingOpt.isSome: existingOpt.get(){"identityDigest"}.getStr("") else: ""
      let candidateIdentity = node{"identityDigest"}.getStr("")
      return err("canonical file already exists with a DIFFERENT canonical identity for irHash " &
        candidate.irHash & " (existing=" & existingIdentity[0 ..< min(12, existingIdentity.len)] &
        " candidate=" & candidateIdentity[0 ..< min(12, candidateIdentity.len)] &
        " existingKey=" & existingKey[0 ..< min(12, existingKey.len)] &
        " candidateKey=" & candidateKey[0 ..< min(12, candidateKey.len)] & ")")
    replacingSameEvidence = true
    existingBytes = try: readFile(destPath) except CatchableError: ""
  try:
    if not dirExists(canonicalDir):
      createDir(canonicalDir)
  except CatchableError:
    return err("failed to create canonical directory: " & canonicalDir)
  ## ── Canonical Promotion Transaction (I1/I3: atomic commit) ──────────────
  ## The certificate's trusted state is committed durably as a TrustCommit
  ## journal record (I2/I7) — the authoritative source of truth. The cert file
  ## and the manifest are then committed as a single logical unit of *cache
  ## artifacts*:
  ##   0. journal   — commitVerification records the promotion (authoritative)
  ##   1. mutate    — write the cert file (derived cache artifact)
  ##   2. manifest  — update manifest.json (derived cache artifact)
  ##   3. rollback  — if (2) fails, delete the just-written cert file so the
  ##                  filesystem cache is restored to its pre-promotion value.
  ## The journal record is immutable; only the materialized cache artifacts are
  ## rolled back, so a crash never exposes "partly canonical" cache state.
  let jsonText = canonicalCertificateString(node)
  ## ── Authoritative promotion record (I2/I7) ──────────────────────────────
  ## The promoted certificate's trusted state is recorded durably via
  ## commitVerification into the TrustCommit journal. destPath is retained only
  ## as a materialized/cache artifact for legacy vault consumers and is never
  ## the authoritative state.
  let solverStatus = node{"solverStatus"}.getStr("")
  let leanProposition = node{"leanProposition"}.getStr("")
  let semanticProfileId = node{"semanticProfileId"}.getStr("")
  let promClaim = jsonText
  let promDigest = hash_kernel.sha256Hex(promClaim)
  let promRes =
    try:
      commitVerification(journalBaseFor(canonicalDir), TrustCommit(
        kind: tcVerifiedProof,
        evidenceId: computeEvidenceId(promClaim, "cert-promotion", promDigest),
        claim: promClaim,
        solverInvocation: "cert-promotion",
        attestation: "Certificate promotion recorded in TrustCommit journal",
        certificateDigest: promDigest,
        scopeDigest: certificateScopeDigestForPair(candidate.modulePath, candidate.functionName),
        configDigest: certificateConfigDigestForPair(
          candidate.modulePath, candidate.functionName, solverStatus, candidate.irHash,
          leanProposition, semanticProfileId),
        parentCommit: none(string)
      ))
    except CatchableError as e:
      return err("promotion TrustCommit write failed: " & e.msg)
  if promRes.isErr:
    return err("promotion TrustCommit rejected: " & promRes.error)
  var promoted = false
  try:
    setPromotionActive()
    ## Derived/cache artifact: materialize the promoted cert at destPath. The
    ## authoritative record is the TrustCommit journal committed above.
    let writeRes = writeFileOpt(destPath, jsonText)
    clearPromotionActive()
    if writeRes.isErr:
      if replacingSameEvidence and existingBytes.len > 0:
        discard writeFileOpt(destPath, existingBytes)  # axiom:best-effort(restore old projection after a failed replacement; the write failure is already returned)
      return err("promotion write failed for " & destPath & ": " & writeRes.error)
    promoted = true
  except CatchableError as e:
    clearPromotionActive()
    if replacingSameEvidence and existingBytes.len > 0:
      discard writeFileOpt(destPath, existingBytes)  # axiom:best-effort(restore old projection after a raised write; the error is already returned)
    return err("promotion write failed: " & e.msg)
  let manifestOk = updateManifestForPromotion(canonicalDir, candidatePath, candidate.irHash, manifestCandidate)
  if not manifestOk:
    ## Roll back the cert file just written: canon state must be fully old or
    ## fully new — never cert-only. Idempotent (destPath is content-addressed).
    ## An in-place evidence replacement restores the pre-promotion projection;
    ## a fresh promotion removes the new file.
    var rollbackFailed = false
    if promoted and fileExists(destPath):
      try:
        if replacingSameEvidence and existingBytes.len > 0:
          let restoreRes = writeFileOpt(destPath, existingBytes)
          if restoreRes.isErr:
            rollbackFailed = true
            writeLine(stdout, "[cert_promotion] rollback restore failed for " & destPath & ": " & restoreRes.error)
        else:
          removeFile(destPath)
      except CatchableError as e:
        rollbackFailed = true
        writeLine(stdout, "[cert_promotion] rollback removeFile failed for " & destPath & ": " & e.msg)
    let msg = "promotion failed: manifest update failed"
    if rollbackFailed:
      return err(msg & "; canonical cert rollback ALSO failed for " & candidatePath & " (partial state must be remediated)")
    return err(msg & "; canonical cert rolled back for " & candidatePath)
  ok("promoted " & candidatePath & " to canonical as " & destPath)

## ─── Reclassification Result ──────────────────────────

type
  ReclassificationResult* = object
    reclassified*: int
    skipped*: int
    failed*: int

## ─── Reclassify Canonical Certificates (P0.3) ────────
## Iterates canonical cert files, derives the correct status from stored
## evidence via certificateEvidenceFromJson / tierFromEvidence / tierToStatusString,
## and rewrites overstated statuses (e.g. certGreen → certZ3Candidate when
## leanCompilerVerified=false). Manifest contentHash is recomputed for each
## rewritten cert. Atomic commit with rollback mirrors promoteToCanonical.
## Provenance-protected certs are skipped with a log message.
proc reclassifyCertificates*(): ReclassificationResult {.axiomDecision(id = "DECISION-0636", reason = "Reclassifies overstated canonical certificates by deriving status from stored evidence rather than string-patching statuses", adr = "docs/spec/verification_density.md", introduced = "v32"), axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let canonicalDir = resolveCertificate(cvCanonicalRead)
  let manifestPath = joinPath(canonicalDir, "manifest.json")
  var manifest: JsonNode
  if fileExists(manifestPath):
    let manifestOpt = readJsonFile(manifestPath)
    if manifestOpt.isSome:
      manifest = manifestOpt.get()
    else:
      manifest = newJObject()
  else:
    manifest = newJObject()
  if manifest.kind != JObject:
    manifest = newJObject()
  if not manifest.hasKey("entries"):
    manifest["entries"] = newJArray()

  for path in walkPattern(joinPath(canonicalDir, "*.json")):
    let fileName = extractFilename(path)
    if fileName == "manifest.json":
      continue
    let irHash = splitFile(fileName).name
    let nodeOpt = readJsonFile(path)
    if nodeOpt.isNone:
      inc result.failed
      continue
    let node = nodeOpt.get()
    if node.kind != JObject:
      inc result.failed
      continue
    let currentStatus = node.getOrDefault("status").getStr("")
    if currentStatus == "certVerifiedAxiom":
      inc result.skipped
      continue
    if statusConsistentWithEvidence(node):
      inc result.skipped
      continue
    let ev = certificateEvidenceFromJson(node)
    let derivedTier = tierFromEvidence(ev)
    let derivedStatus = tierToStatusString(derivedTier)
    if derivedStatus == currentStatus:
      inc result.skipped
      continue
    if isProvenanceProtected(path):
      writeLine(stdout, "[cert_promotion] provenance-protected, skipping reclassification for " & path)
      inc result.skipped
      continue
    var updatedNode = node
    updatedNode["status"] = newJString(derivedStatus)
    let jsonText = canonicalCertificateString(updatedNode)
    let newContentHash = "sha256:" & $secureHash(Sha_256, jsonText)
    let tmpPath = path & ".tmp"
    var certWritten = false
    ## ── Authoritative reclassification record (I2/I7) ─────────────────────
    ## The reclassified certificate's trusted state is recorded durably via
    ## commitVerification. The canonical cert file and manifest below are
    ## retained only as derived/cache artifacts for legacy consumers; the
    ## journal record is the single source of truth.
    let reclassModulePath = updatedNode.getOrDefault("modulePath").getStr("")
    let reclassFunctionName = updatedNode.getOrDefault("functionName").getStr("")
    let reclassSolverStatus = updatedNode.getOrDefault("solverStatus").getStr("")
    let reclassLeanProp = updatedNode.getOrDefault("leanProposition").getStr("")
    let reclassProfileId = updatedNode.getOrDefault("semanticProfileId").getStr("")
    let reclassClaim = jsonText
    let reclassDigest = hash_kernel.sha256Hex(reclassClaim)
    let reclassRes =
      try:
        commitVerification(journalBaseFor(canonicalDir), TrustCommit(
          kind: tcVerifiedProof,
          evidenceId: computeEvidenceId(reclassClaim, "cert-promotion", reclassDigest),
          claim: reclassClaim,
          solverInvocation: "cert-promotion",
          attestation: "Certificate reclassification recorded in TrustCommit journal",
          certificateDigest: reclassDigest,
          scopeDigest: certificateScopeDigestForPair(reclassModulePath, reclassFunctionName),
          configDigest: certificateConfigDigestForPair(
            reclassModulePath, reclassFunctionName, reclassSolverStatus, irHash,
            reclassLeanProp, reclassProfileId),
          parentCommit: none(string)
        ))
      except CatchableError as e:
        writeLine(stdout, "[cert_promotion] reclassification TrustCommit write failed for " & path & ": " & e.msg)
        inc result.failed
        continue
    if reclassRes.isErr:
      writeLine(stdout, "[cert_promotion] reclassification TrustCommit rejected for " & path & ": " & reclassRes.error)
      inc result.failed
      continue
    try:
      setPromotionActive()
      ## Derived/cache artifact: materialize the reclassified cert at path. The
      ## authoritative record is the TrustCommit journal committed above.
      let writeRes = writeFileOpt(tmpPath, jsonText)
      if writeRes.isErr:
        clearPromotionActive()
        inc result.failed
        continue
      safeMoveFile(tmpPath, path)
      clearPromotionActive()
      certWritten = true
    except CatchableError as e:
      clearPromotionActive()
      writeLine(stdout, "[cert_promotion] reclassification write failed for " & path & ": " & e.msg)
      inc result.failed
      continue
    let entries = manifest["entries"]
    var manifestUpdated = false
    for i in 0 ..< entries.len:
      let e = entries[i]
      if e.kind == JObject and e{"irHash"}.getStr("") == irHash:
        entries[i]["contentHash"] = newJString(newContentHash)
        entries[i]["status"] = newJString(derivedStatus)
        manifestUpdated = true
        break
    if not manifestUpdated:
      let modulePath = node.getOrDefault("modulePath").getStr("")
      let functionName = node.getOrDefault("functionName").getStr("")
      let fingerprint = node.getOrDefault("fingerprint").getStr("")
      let backend = node.getOrDefault("backend").getStr("")
      entries.add %*{
        "modulePath": modulePath,
        "functionName": functionName,
        "irHash": irHash,
        "fingerprint": fingerprint,
        "contentHash": newContentHash,
        "status": derivedStatus,
        "backend": backend,
        "lifecycleStage": "canonical"
      }
    let manifestTmpPath = manifestPath & ".tmp"
    ## Derived/cache artifact: manifest.json is a convenience catalog over the
    ## canonical certs. Its authoritative state is the TrustCommit journal
    ## record committed above (the reclassification); this write is not the
    ## source of truth, and a failure here only rolls back the cache artifacts.
    try:
      writeFile(manifestTmpPath, pretty(manifest) & "\n")
      safeMoveFile(manifestTmpPath, manifestPath)
      inc result.reclassified
    except CatchableError:
      var rollbackFailed = false
      if certWritten and fileExists(path):
        try:
          removeFile(path)
        except CatchableError as e:
          rollbackFailed = true
          writeLine(stdout, "[cert_promotion] rollback removeFile failed for " & path & ": " & e.msg)
      if rollbackFailed:
        writeLine(stdout, "[cert_promotion] manifest update failed AND rollback failed for " & path & " (partial state must be remediated)")
      else:
        writeLine(stdout, "[cert_promotion] manifest update failed, cert rolled back for " & path)
      inc result.failed

## ─── Reissue Reference Certificate ──────────────────
## Maintenance-only workflow to reclassify a REFERENCE certificate
## under the current bundle. Operates ONLY on the reference namespace
## (src/verification/certificates/), never the runtime store.
## Reuses the same evidence-derived reclassification logic as
## reclassifyCertificates but targets a single file.
proc reissueReference*(path: string): string {.axiomDecision(id = "DECISION-0644", reason = "Maintenance-only reissue of a reference certificate by reclassifying its status from stored evidence; never auto-calls ax prove; operates only on the reference namespace", adr = "docs/spec/verification_density.md", introduced = "v33"), axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let refDir = resolveCertificate(cvCanonicalRead)
  if not path.startsWith(refDir):
    return "reissue-reference error: path must be in reference namespace (" & refDir & "): " & path
  if not fileExists(path):
    return "reissue-reference error: file not found: " & path
  let nodeOpt = readJsonFile(path)
  if nodeOpt.isNone:
    return "reissue-reference error: cannot read JSON from " & path
  let node = nodeOpt.get()
  if node.kind != JObject:
    return "reissue-reference error: not a JSON object: " & path
  let currentStatus = node.getOrDefault("status").getStr("")
  if currentStatus == "certVerifiedAxiom":
    return "reissue-reference: already certVerifiedAxiom, no reissue needed: " & path
  if statusConsistentWithEvidence(node):
    return "reissue-reference: status already consistent with evidence (" & currentStatus & "): " & path
  let ev = certificateEvidenceFromJson(node)
  let derivedTier = tierFromEvidence(ev)
  let derivedStatus = tierToStatusString(derivedTier)
  if derivedStatus == currentStatus:
    return "reissue-reference: status unchanged (" & currentStatus & "): " & path
  var updatedNode = node
  updatedNode["status"] = newJString(derivedStatus)
  let jsonText = canonicalCertificateString(updatedNode)
  let newContentHash = "sha256:" & $secureHash(Sha_256, jsonText)
  let irHash = node.getOrDefault("irHash").getStr("")
  let modulePath = node.getOrDefault("modulePath").getStr("")
  let functionName = node.getOrDefault("functionName").getStr("")
  let fingerprint = node.getOrDefault("fingerprint").getStr("")
  let backend = node.getOrDefault("backend").getStr("")
  let tmpPath = path & ".tmp"
  try:
    setPromotionActive()
    let writeRes = writeFileOpt(tmpPath, jsonText)
    if writeRes.isErr:
      clearPromotionActive()
      return "reissue-reference error: write failed for " & path & ": " & writeRes.error
    safeMoveFile(tmpPath, path)
    clearPromotionActive()
  except CatchableError as e:
    clearPromotionActive()
    return "reissue-reference error: write failed for " & path & ": " & e.msg
  ## Update manifest
  let manifestPath = joinPath(refDir, "manifest.json")
  var manifest: JsonNode
  if fileExists(manifestPath):
    let manifestOpt = readJsonFile(manifestPath)
    if manifestOpt.isSome:
      manifest = manifestOpt.get()
    else:
      manifest = newJObject()
  else:
    manifest = newJObject()
  if manifest.kind != JObject:
    manifest = newJObject()
  if not manifest.hasKey("entries"):
    manifest["entries"] = newJArray()
  if not manifest.hasKey("version"):
    manifest["version"] = newJInt(2)
  if not manifest.hasKey("fingerprint"):
    manifest["fingerprint"] = newJString("")
  var manifestUpdated = false
  let entries = manifest["entries"]
  for i in 0 ..< entries.len:
    let e = entries[i]
    if e.kind == JObject and e{"irHash"}.getStr("") == irHash:
      entries[i]["contentHash"] = newJString(newContentHash)
      entries[i]["status"] = newJString(derivedStatus)
      manifestUpdated = true
      break
  if not manifestUpdated:
    entries.add %*{
      "modulePath": modulePath,
      "functionName": functionName,
      "irHash": irHash,
      "fingerprint": fingerprint,
      "contentHash": newContentHash,
      "status": derivedStatus,
      "backend": backend,
      "lifecycleStage": "canonical"
    }
  let manifestTmpPath = manifestPath & ".tmp"
  try:
    writeFile(manifestTmpPath, pretty(manifest) & "\n")
    safeMoveFile(manifestTmpPath, manifestPath)
  except CatchableError:
    return "reissue-reference: cert reclassified but manifest update failed for " & path
  ## TrustCommit journal record
  let solverStatus = node{"solverStatus"}.getStr("")
  let leanProposition = node{"leanProposition"}.getStr("")
  let semanticProfileId = node{"semanticProfileId"}.getStr("")
  let reclassClaim = jsonText
  let reclassDigest = hash_kernel.sha256Hex(reclassClaim)
  let reclassRes =
    try:
      commitVerification(journalBaseFor(refDir), TrustCommit(
        kind: tcVerifiedProof,
        evidenceId: computeEvidenceId(reclassClaim, "cert-reissue", reclassDigest),
        claim: reclassClaim,
        solverInvocation: "cert-reissue",
        attestation: "Certificate reissue recorded in TrustCommit journal",
        certificateDigest: reclassDigest,
        scopeDigest: certificateScopeDigestForPair(modulePath, functionName),
        configDigest: certificateConfigDigestForPair(
          modulePath, functionName, solverStatus, irHash,
          leanProposition, semanticProfileId),
        parentCommit: none(string)
      ))
    except CatchableError as e:
      return "reissue-reference: cert reclassified but TrustCommit failed for " & path & ": " & e.msg
  if reclassRes.isErr:
    return "reissue-reference: cert reclassified but TrustCommit rejected for " & path & ": " & reclassRes.error
  "reissue-reference: reclassified " & path & " (" & currentStatus & " → " & derivedStatus & ")"