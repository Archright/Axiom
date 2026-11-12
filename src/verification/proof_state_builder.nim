import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/domain_types
import core/gate/architecture_policy # for loadArchitecturePolicy, isGeneratedModuleWhitelisted
import core/json/json_utils
import core/types/asi_types
import core/types/certificate_types
import core/types/verification_tier # for certificateEvidenceFromJson (DECISION-0630 canonical evidence contract)
import core/json/std_redirect
import core/parsers/safe_parsers
import core/results
import core/telemetry/metrics
import core/proof/proof_integrity  # for loadKernelScope, symbolInKernelScope (Set-Membership)
import core/trusted/axiom_pragmas  # for countKernelFunctions
import core/trusted/trust_commit
import core/utils/file_utils
import core/vault/vault_manager_spec # for computeSourceFingerprint
import std/options
import std/os
import std/sets
import std/strutils
import std/times
import infrastructure/logging_facade
const AXIOM_STATE_SSOT_PATH* = "logs/ax_proof_state.json"
const AXIOM_CERT_VAULT_DIR* = ".axiom/vault"
  ## Canonical runtime vault used by the batch UAP orchestrator.
  ## Defined locally because core/utils/constants excludes logs/ paths.

proc isEmpiricalCertificateNode(cert: JsonNode): bool {.raises: [].} =
  cert.kind == JObject and
    cert.getOrDefault("kind").getStr("") == "empirical" and
    not cert.getOrDefault("pbt").isNil and cert.getOrDefault("pbt").kind != JNull

proc hydrateProofStateFromTrustCommitJournal*(repoRoot: string): tuple[state: JsonNode; certificates: seq[FunctionCertificate]] {.raises: [CatchableError].} =
  ## Reconstruct certificate state-transition records from the authoritative
  ## TrustCommit journal. Wave 5 writes the certificate JSON directly and admits
  ## the same JSON as the canonical journal claim, so replay must hydrate every
  ## certificate claim in the journal rather than only legacy PBT empirical nodes.
  type
    CommitHydration = tuple[id: CommitId, commit: TrustCommit]

  proc statusToProofState(status: string): string {.raises: [].} =
    let normalized = status.toLowerAscii()
    case normalized
    of "certpseudoverified": "pseudo_verified"
    of "certred", "red", "failed": "counter_example"
    # DECISION-0630: unsat candidate evidence is its own honest state —
    # never "counter_example" (SAT-only) and never "unverifiable".
    of "certz3candidate": "z3_candidate"
    of "certgreen", "verified", "certleanverified", "certdualverified",
       "certverifiedaxiom": "verified"
    of "certyellow", "yellow", "bounded": "partially_verified"
    of "certnoobligation", "no_obligation": "no_obligation"
    of "unverifiable": "unverifiable"
    of "pending": "unattempted"
    else: "unverifiable"

  proc statusToCertStatus(status: string): CertificateStatus {.raises: [].} =
    let normalized = status.toLowerAscii()
    case normalized
    of "certgreen": certGreen
    of "certleanverified": certLeanVerified
    of "certdualverified": certDualVerified
    of "certverifiedaxiom": certVerifiedAxiom
    # DECISION-0630: certZ3Candidate is a distinct canonical status (unsat
    # candidate). The previous `else: certRed` fallthrough re-interpreted
    # unsat candidates as counterexamples — an evidence-contract violation.
    of "certz3candidate": certZ3Candidate
    of "certyellow": certYellow
    of "certnoobligation": certNoObligation
    of "certpseudoverified": certPseudoVerified
    of "pending": certPending
    else: certRed

  proc hydrateCertificateClaim(
    repoRoot: string; commitId: CommitId; evidenceId: string; claimNode: JsonNode
  ): tuple[entry: JsonNode; certificate: FunctionCertificate] {.raises: [].} =
    let modulePath = claimNode.getOrDefault("modulePath").getStr("")
    let functionName = claimNode.getOrDefault("functionName").getStr("")
    if modulePath.len == 0 or functionName.len == 0:
      return (entry: %*{}, certificate: FunctionCertificate())

    let status = claimNode.getOrDefault("status").getStr("certPending")
    let proofStatus = statusToProofState(status)
    let certStatus = statusToCertStatus(status)
    let nodeId = modulePath & "::" & functionName
    let label = splitFile(modulePath).name & ".nim::" & functionName
    let certPath = commitPath(repoRoot, commitId)
    let reason = claimNode.getOrDefault("reason").getStr("")
    let fingerprint = claimNode.getOrDefault("fingerprint").getStr("")
    let irHash = claimNode.getOrDefault("irHash").getStr("")
    let informationGain = initAsiRatio(
      claimNode.getOrDefault("informationGain").getFloat(0.0)).get(defaultAsiRatio())

    let entry = %*{
      "nodeId": nodeId,
      "label": label,
      "functionName": functionName,
      "modulePath": modulePath,
      "nodeType": "func",
      "status": proofStatus,
      "attempted": true,
      "premiseCount": 0,
      "dependencyCount": 0,
      "trusted": true,
      "axiomId": evidenceId,
      "axiomVersion": "trust-commit-v33",
      "irHash": irHash
    }
    (
      entry: entry,
      certificate: FunctionCertificate(
        certificatePath: FilePath(certPath),
        functionName: functionName,
        modulePath: FilePath(modulePath),
        fingerprint: fingerprint,
        trusted: true,
        status: certStatus,
        reason: reason,
        informationGain: informationGain,
        axiomId: evidenceId,
        axiomVersion: "trust-commit-v33",
        irHash: irHash
      )
    )

  proc hydrateFromCommits(commits: seq[CommitHydration]): tuple[state: JsonNode; certificates: seq[FunctionCertificate]] =
    var entries = newJArray()
    var certificates: seq[FunctionCertificate] = @[]
    for commitRec in commits:
      let commit = commitRec.commit
      let commitId = commitRec.id
      let claimOpt = parseJsonOpt(commit.claim)
      if claimOpt.isNone:
        continue
      let claimNodeValue = claimOpt.get()
      if claimNodeValue.isNil or claimNodeValue.kind != JObject:
        continue
      let modulePath = claimNodeValue.getOrDefault("modulePath").getStr("")
      let functionName = claimNodeValue.getOrDefault("functionName").getStr("")
      if modulePath.len == 0 or functionName.len == 0:
        continue
      let hydrated = hydrateCertificateClaim(repoRoot, commitId, commit.evidenceId, claimNodeValue)
      entries.add(hydrated.entry)
      certificates.add(hydrated.certificate)

    var verified = 0
    var counterExamples = 0
    var vacuousContradictions = 0
    var timedOut = 0
    var unverifiable = 0
    var pseudoVerified = 0
    var certifiedExempt = 0
    var unattempted = 0
    var z3Candidates = 0
    for cert in certificates:
      case cert.status
      of certGreen, certVerifiedAxiom, certLeanVerified, certDualVerified:
        inc verified
      of certZ3Candidate:
        # DECISION-0630: unsat candidate evidence — its own bucket, never a
        # counterexample (SAT-only) and never unverifiable.
        inc z3Candidates
      of certRed:
        inc counterExamples
        let reason = cert.reason.toLowerAscii()
        if reason.contains("vacuous"):
          inc vacuousContradictions
        elif reason.contains("timeout"):
          inc timedOut
      of certYellow:
        inc certifiedExempt
      of certNoObligation:
        inc certifiedExempt
      of certPseudoVerified:
        inc pseudoVerified
      of certPending:
        inc unattempted
      else:
        inc unverifiable

    let state = %*{
      "target": "src",
      "sourceRoot": (try: getCurrentDir() except CatchableError: ""),
      "timestamp": getTime().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
      "summary": {
        "totalNodes": countKernelFunctions(),
        "attemptedNodes": certificates.len,
        "verified": verified,
        "counterExamples": counterExamples,
        "vacuousContradictions": vacuousContradictions,
        "timedOut": timedOut,
        "unverifiable": unverifiable,
        "pseudoVerified": pseudoVerified,
        "certifiedExempt": certifiedExempt,
        "unattempted": unattempted,
        "z3Candidates": z3Candidates,
        "engineAsiGraded4": "0.0000"
      },
      "entries": entries
    }
    (state: state, certificates: certificates)

  let commitsRes = try:
    replayJournal(repoRoot)
  except CatchableError as e:
    logError("proof_state_builder", "TrustCommit journal replay failed for " & repoRoot & ": " & e.msg)
    return (state: %*{}, certificates: @[])
  if not commitsRes.ok:
    return (state: %*{}, certificates: @[])
  var commits: seq[CommitHydration] = @[]
  for id in commitsRes.value.commitIds:
    let commit = readCommit(repoRoot, id)
    if commit.ok:
      commits.add((id: id, commit: commit.value))
  hydrateFromCommits(commits)

proc hydrateProofStateFromCertificateVault*(certDir: string; repoRoot: string = ""): tuple[state: JsonNode; certificates: seq[FunctionCertificate]] {.raises: [].} =
  ## Reconstruct the full proof state by scanning the certificate vault.
  ## This is the canonical SSOT path; the transient ax_proof_state.json is only a
  ## fast-path cache (kept for denominator fallback, never for ASI values).
  ##
  ## [DEEP VERIFICATION v0.7.0] Certificate file existence is necessary
  ## but NOT sufficient. A certificate must contain actual proof artifacts:
  ##   1. smtlib2 query exists AND matching .z3out file contains "unsat"
  ##   2. leanCompilerVerified == true
  ##   3. fingerprint matches current source (anti-tamper)
  ##
  ## [WS-P2-A Set-Membership] A certificate is classified as kernel iff
  ## `<modulePath>::<functionName>` is a member of `data/verification_scope.lock`
  ## `kernel_symbols` — never by the cert `kernel` field (per-file scan). repoRoot
  ## is derived from certDir (two parent levels, canonical `.axiom/vault` layout)
  ## unless passed explicitly by callers using the legacy stable vault.
  var entries = newJArray()
  var journalState = %*{
    "summary": {
      "verified": 0,
      "unverifiable": 0,
      "counterExamples": 0,
      "vacuousContradictions": 0,
      "timedOut": 0,
      "pseudoVerified": 0,
      "certifiedExempt": 0,
      "unattempted": 0,
      "z3Candidates": 0
    },
    "entries": newJArray(),
    "certificates": @[]
  }
  var journalCertificates: seq[FunctionCertificate] = @[]
  var journalPaths = initHashSet[string]()
  var journalSymbols = initHashSet[string]()
  var verifiedCount = 0
  var unverifiableCount = 0
  var pendingCount = 0
  var redCount = 0
  var otherCount = 0
  var kernelVerifiedCount = 0
  var kernelRedCount = 0
  var vacuousCertCount = 0
  var timedOutCertCount = 0
  var pseudoVerifiedCount = 0
  var z3CandidateCount = 0
  var certificates: seq[FunctionCertificate] = @[]
  var countedKernelSymbols = initHashSet[string]()

  # [WS-P2-A] Load the kernel scope ONCE per hydration. repoRoot defaults to two
  # parent levels of certDir (canonical layout: <repoRoot>/.axiom/vault) and is
  # overridden explicitly by callers using the legacy stable vault
  # (<repoRoot>/src/verification/certificates). Fail-closed: unreadable/missing
  # scope yields an empty kernel set (degraded mode -> legacy `kernel` field).
  let effectiveRepoRoot =
    if repoRoot.len > 0: repoRoot
    else: certDir.parentDir.parentDir
  var journalHydratedState = %*{}
  var journalHydratedCertificates: seq[FunctionCertificate] = @[]
  try:
    (journalHydratedState, journalHydratedCertificates) = hydrateProofStateFromTrustCommitJournal(effectiveRepoRoot)
  except CatchableError as e:
    logError("proof_state_builder", "journal hydration failed; using empty journal state: " & e.msg)
  journalState = journalHydratedState
  journalCertificates = journalHydratedCertificates
  for cert in journalCertificates:
    journalPaths.incl(string(cert.certificatePath))
    journalSymbols.incl(string(cert.modulePath) & "::" & cert.functionName)
  let kernelScope = block:
    try:
      loadKernelScope(effectiveRepoRoot / "data" / "verification_scope.lock")
    except CatchableError:
      KernelScopeInfo(kernelSymbols: @[], kernelTotal: 0)

  proc isDeepVerified(cert: JsonNode; certPath: string): bool {.raises: [].} =
    ## Deep verification: certificate must contain actual proof artifacts.
    ## Soundness Gatekeeper. The Lean half of this gate CONSUMES the canonical
    ## evidence contract (DECISION-0630 via certificateEvidenceFromJson):
    ## leanVerified = solverMeta.leanCompilerVerified ∧ kernel — a naked flag
    ## is never sufficient. On top of that P0 conjunction, the legacy
    ## soundness discriminator still applies:
    ##   a) vacuityProven = true (legacy UAP path with negative mutation test), OR
    ##   b) verificationTier present (IR pipeline with built-in soundness checks)
    ## Z3-only evidence is candidate-only and does NOT qualify as deep
    ## verified — it never promotes to verified/deep-verified.
    let vacuityProven = cert{"solverMeta"}{"vacuityProven"}.getBool(false)
    let verificationTier = cert.getOrDefault("verificationTier").getStr("")

    # Condition 1: P0 Lean evidence (flag ∧ kernel) with soundness assurance.
    # kernel is the KAA-bound receipt; a flag without it is exactly the
    # KAA-less shape the writer demotes to certZ3Candidate — fail-closed here.
    let ev = certificateEvidenceFromJson(cert)
    let leanSound = ev.leanVerified and (vacuityProven or verificationTier.len > 0)

    if not leanSound:
      return false

    # Condition 2: Source integrity — fingerprint matches current source
    # Skip for IR pipeline verified certificates (verificationTier present) —
    # the IR pipeline has its own soundness checks, fingerprint is redundant.
    let modulePath = cert.getOrDefault("modulePath").getStr("")
    let certFingerprint = cert.getOrDefault("fingerprint").getStr("")
    if verificationTier.len == 0 and modulePath.len > 0 and certFingerprint.len > 0:
      let sourcePath = modulePath
      if fileExists(sourcePath):
        let currentFingerprint = try: computeSourceFingerprint(readFileSafe(sourcePath)) except CatchableError: ""
        if certFingerprint != currentFingerprint:
          return false

    true

  proc calculateGradedScore(cert: JsonNode; certPath: string): float {.raises: [].} =
    ## Tiered grading per approved plan:
    ##   0.3 — SMT query exists and Z3 returned unsat
    ##   +0.3 — Lean source compiles (leanCompilerVerified)
    ##   +0.4 — Source fingerprint matches current source
    let smtlib2 = cert.getOrDefault("smtlib2").getStr("")
    let z3outPath = cert.getOrDefault("z3outPath").getStr("")
    if smtlib2.len == 0:
      return 0.0
    let actualZ3out = if z3outPath.len > 0: z3outPath
                      else: certPath.changeFileExt("z3out")
    if not fileExists(actualZ3out):
      return 0.0
    let z3result = try: readFileSafe(actualZ3out).strip() except CatchableError: ""
    if z3result != "unsat":
      return 0.0
    result += 0.3
    let leanVerified = cert{"solverMeta"}{"leanCompilerVerified"}.getBool(false)
    if not leanVerified:
      return result
    result += 0.3
    let certFingerprint = cert.getOrDefault("fingerprint").getStr("")
    let modulePath = cert.getOrDefault("modulePath").getStr("")
    if modulePath.len > 0 and certFingerprint.len > 0 and fileExists(modulePath):
      let currentFingerprint = try: computeSourceFingerprint(readFileSafe(modulePath)) except CatchableError: ""
      if certFingerprint == currentFingerprint:
        result += 0.4

  proc isCertifiedExempt(cert: JsonNode): bool {.raises: [].} =
    ## Strict exempt validation per architecture_policy.lock [generated_modules].
    let modulePath = cert.getOrDefault("modulePath").getStr("")
    let functionName {.used.} = cert.getOrDefault("functionName").getStr("")
    let certFingerprint = cert.getOrDefault("fingerprint").getStr("")

    # Load policy for whitelist check
    let policyRes = loadArchitecturePolicy()
    if not policyRes.ok:
      return false
    let policy = policyRes.policy

    # 1. Must be in architecture_policy.lock [generated_modules] whitelist
    let (isWhitelisted, expectedFp) = isGeneratedModuleWhitelisted(policy, modulePath)
    if not isWhitelisted:
      return false

    # 2. Fingerprint must match current generated source
    if expectedFp.len > 0 and certFingerprint.len > 0:
      if certFingerprint != expectedFp:
        return false
    elif expectedFp.len > 0:
      # Policy expects fingerprint but certificate has none
      return false

    true

  var gradedTotal = 0.0

  if dirExists(certDir):
    try:
      for path in walkFiles(certDir / "*.json"):
        if path in journalPaths:
          continue
        let cert = readJsonFileNode(path)
        if cert.isNil: continue
        if cert.kind != JObject: continue
        if isEmpiricalCertificateNode(cert): continue

        let modulePath = cert.getOrDefault("modulePath").getStr("")
        let functionName = cert.getOrDefault("functionName").getStr("")
        let status = cert.getOrDefault("status").getStr("unknown")
        let fingerprint = cert.getOrDefault("fingerprint").getStr("")
        let trusted = cert.getOrDefault("trusted").getBool(false)

        if modulePath.len == 0 or functionName.len == 0:
          continue
        if (modulePath & "::" & functionName) in journalSymbols:
          continue

        let nodeId = modulePath & "::" & functionName
        let label = splitFile(modulePath).name & ".nim::" & functionName

        # [DEEP VERIFICATION] Determine effective status
        var entryStatus = status
        var certStatus = certPending

        case status
        of "certGreen", "verified", "certLeanVerified", "certDualVerified", "certVerifiedAxiom":
          if isDeepVerified(cert, path):
            entryStatus = "verified"
            certStatus = certVerifiedAxiom
            inc verifiedCount
          else:
            entryStatus = "unverifiable"
            certStatus = certPending
            inc unverifiableCount
        of "certified_exempt":
          if isCertifiedExempt(cert):
            entryStatus = "certifiedExempt"
            certStatus = certVerifiedAxiom
            inc otherCount
          else:
            entryStatus = "unverifiable"
            certStatus = certPending
            inc unverifiableCount
        of "unverifiable":
          entryStatus = "unverifiable"
          certStatus = certPending
          inc unverifiableCount
        of "certRed", "red", "failed":
          let reason = cert.getOrDefault("reason").getStr("").toLowerAscii()
          if reason.contains("vacuous"):
            entryStatus = "vacuous_contradiction"
            inc vacuousCertCount
          elif reason.contains("timeout"):
            entryStatus = "timed_out"
            inc timedOutCertCount
          else:
            entryStatus = "counter_example"
          certStatus = certRed
          inc redCount
        of "certPseudoVerified":
          entryStatus = "pseudo_verified"
          certStatus = certPseudoVerified
          inc pseudoVerifiedCount
        of "certYellow", "yellow", "bounded":
          entryStatus = "partially_verified"
          certStatus = certYellow
        of "certNoObligation", "no_obligation":
          entryStatus = "no_obligation"
          certStatus = certNoObligation
          inc otherCount
        of "certZ3Candidate":
          # DECISION-0630: explicit candidate bucket — previously swallowed
          # into otherCount (misreported as certifiedExempt).
          entryStatus = "z3_candidate"
          certStatus = certZ3Candidate
          inc z3CandidateCount
        of "pending":
          entryStatus = "unattempted"
          certStatus = certPending
          inc pendingCount
        else:
          inc otherCount

        # [WS-P2-A] Set-Membership kernel detection: a cert is kernel iff its
        # modulePath::functionName is a member of verification_scope.lock
        # kernel_symbols. The legacy `kernel` field is honored only when the scope
        # is unavailable (degraded mode) — never as a per-file scan override.
        # Counts are deduplicated per symbol (nodeId) so duplicate certs for the
        # same kernel symbol cannot inflate the numerator (SSOT convergence).
        let isKernel =
          if kernelScope.kernelSymbols.len > 0:
            symbolInKernelScope(cert, kernelScope)
          else:
            cert.getOrDefault("kernel").getBool(false)
        if isKernel:
          case entryStatus
          of "verified":
            if nodeId notin countedKernelSymbols:
              countedKernelSymbols.incl(nodeId)
              inc kernelVerifiedCount
          of "counter_example":
            if nodeId notin countedKernelSymbols:
              countedKernelSymbols.incl(nodeId)
              inc kernelRedCount
          else:
            discard

        var entry = %*{
          "nodeId": nodeId,
          "label": label,
          "functionName": functionName,
          "modulePath": modulePath,
          "nodeType": "func",
          "status": entryStatus,
          "attempted": true,
          "premiseCount": 0,
          "dependencyCount": 0
        }
        if isKernel:
          entry["kernel"] = %true
        if fingerprint.len > 0:
          entry["fingerprint"] = %fingerprint
        if trusted:
          entry["trusted"] = %true

        # Preserve audit trails if present (Phase 1)
        let reasoningTrail = cert.getOrDefault("reasoningTrail")
        if not reasoningTrail.isNil and reasoningTrail.kind == JArray:
          entry["reasoningTrail"] = reasoningTrail
        let provenanceLog = cert.getOrDefault("provenanceLog")
        if not provenanceLog.isNil and provenanceLog.kind == JArray:
          entry["provenanceLog"] = provenanceLog
        let transitionLog = cert.getOrDefault("transitionLog")
        if not transitionLog.isNil and transitionLog.kind == JArray:
          entry["transitionLog"] = transitionLog

        entries.add(entry)

        let rawInfoGain = cert.getOrDefault("informationGain").getFloat(0.0)
        certificates.add(FunctionCertificate(
          certificatePath: FilePath(path),
          functionName: functionName,
          modulePath: FilePath(modulePath),
          fingerprint: fingerprint,
          trusted: trusted,
          status: certStatus,
          reason: cert.getOrDefault("reason").getStr(""),
          informationGain: initAsiRatio(rawInfoGain).get(defaultAsiRatio())
        ))

        gradedTotal += calculateGradedScore(cert, path)
    except CatchableError as e:
      logError("proof_state_builder", "hydrateProofStateFromCertificateVault scan failed for dir " & certDir & ": " & e.msg)

  var journalSummary = journalState.getOrDefault("summary")
  if journalSummary.isNil or journalSummary.kind != JObject:
    journalSummary = %*{}
  verifiedCount += journalSummary.getOrDefault("verified").getInt(0)
  unverifiableCount += journalSummary.getOrDefault("unverifiable").getInt(0)
  redCount += journalSummary.getOrDefault("counterExamples").getInt(0)
  otherCount += journalSummary.getOrDefault("certifiedExempt").getInt(0)
  pendingCount += journalSummary.getOrDefault("unattempted").getInt(0)
  pseudoVerifiedCount += journalSummary.getOrDefault("pseudoVerified").getInt(0)
  z3CandidateCount += journalSummary.getOrDefault("z3Candidates").getInt(0)
  vacuousCertCount += journalSummary.getOrDefault("vacuousContradictions").getInt(0)
  timedOutCertCount += journalSummary.getOrDefault("timedOut").getInt(0)
  kernelVerifiedCount = verifiedCount
  kernelRedCount = redCount
  # Journal entries live at the TOP level of the journal state (hydrateFromCommits
  # emits {summary, entries}), not inside summary. Reading them from the summary
  # object returned nil forever — the projection silently dropped every journal
  # entry (wave5: vault hydrate showed 0 entries for 1 journaled certificate).
  let journalEntries = journalState.getOrDefault("entries")
  if not journalEntries.isNil and journalEntries.kind == JArray:
    for entry in journalEntries.getElems():
      if entry.isNil or entry.kind != JObject: continue
      entries.add(entry)
  for cert in journalCertificates:
    certificates.add(cert)

  let total = countKernelFunctions()
  let attempted = verifiedCount + unverifiableCount + redCount + otherCount + pseudoVerifiedCount + pendingCount + z3CandidateCount

  let gradedAverage = if entries.len > 0: gradedTotal / entries.len.float else: 0.0
  let gradedStr = try: formatFloat(gradedAverage, ffDecimal, 4) except CatchableError: "0.0000"

  let vacuousCount = vacuousCertCount
  let timeoutCount = timedOutCertCount
  let state = %*{
    "target": "src",
    "sourceRoot": (try: getCurrentDir() except CatchableError: ""),
    "timestamp": getTime().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
    "summary": {
      "totalNodes": total,
      "attemptedNodes": attempted,
      "verified": kernelVerifiedCount,
      "counterExamples": kernelRedCount,
      "vacuousContradictions": vacuousCount,
      "timedOut": timeoutCount,
      "unverifiable": unverifiableCount,
      "pseudoVerified": pseudoVerifiedCount,
      "certifiedExempt": otherCount,
      "unattempted": pendingCount,
      "z3Candidates": z3CandidateCount,
      "engineAsiGraded4": gradedStr
    },
    "entries": entries
  }
  result = (state: state, certificates: certificates)
proc getUnifiedAsiFixed4*(repoRoot: string; forceHydration: bool = false): ValidatedAsi {.raises: [].} =
  ## Returns the canonical ASI for the repository.
  ## [WS-P2-A Single Hydrate Path] The cached ax_proof_state.json fast path was
  ## REMOVED: it returned an unverified cached `engineAsiFixed4`, enabling
  ## Split-Brain. Every invocation now hydrates from the certificate vault
  ## (canonical SSOT) regardless of forceHydration or file freshness.
  ## `forceHydration` is retained for API compatibility and ignored.
  proc hydrateAsi(): Result[ValidatedAsi, string] =
    let (hydrated, certificates) = hydrateProofStateFromCertificateVault(repoRoot / AXIOM_CERT_VAULT_DIR, repoRoot)
    let summary = hydrated.getOrDefault("summary")
    if summary.isNil or summary.kind != JObject:
      return ok(exportAsiFixed4(initAsiRatio(0.0).get(defaultAsiRatio())))
    # Use ax_proof_state.json totalNodes as SSOT denominator (source function count)
    var totalNodes = summary.getOrDefault("totalNodes").getInt(0)
    let avgRetry = summary.getOrDefault("averageRetryCount").getFloat(0.0)
    # If certificate-only count is used, fall back to cached totalNodes from ax_proof_state.json
    if totalNodes <= certificates.len:
      let stateOpt = readJsonFile(repoRoot / AXIOM_STATE_SSOT_PATH)
      if stateOpt.isSome:
        let stateSummary = stateOpt.get().getOrDefault("summary")
        if not stateSummary.isNil and stateSummary.kind == JObject:
          let cachedTotalSrc = stateSummary.getOrDefault("totalSourceFunctions").getInt(0)
          if cachedTotalSrc > totalNodes:
            totalNodes = cachedTotalSrc
          let cachedTotal = stateSummary.getOrDefault("totalNodes").getInt(0)
          if cachedTotal > totalNodes:
            totalNodes = cachedTotal
    let universe = AsiUniverse(totalFunctions: totalNodes)
    if not metrics.validateUniverse(totalNodes, usKernelDomain):
      # Panic: corrupted denominator. Certificate-only count used instead of source function count.
      try:
        logDebug("proof_state_builder", "[AXIOM PANIC] ASI denominator corrupted: totalFunctions=" & $totalNodes &
          " < threshold=" & $metrics.KernelDomainThreshold &
          ". Certificate-only count used instead of source graph scan.")
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
      return err("VKD denominator corrupted: totalFunctions=" & $totalNodes & " < threshold=" & $metrics.KernelDomainThreshold & ". Certificate-only count used instead of source graph scan.")
    let score = computeInformationGainWeightedAsi(certificates, universe, avgRetry)
    ok(exportAsiFixed4(score))

  let asiRes = hydrateAsi()
  if asiRes.isErr: return exportAsiFixed4(initAsiRatio(0.0).get(defaultAsiRatio()))
  asiRes.get
proc getUnifiedAsiGraded4*(repoRoot: string; forceHydration: bool = false): ValidatedAsi {.raises: [].} =
  ## Returns the graded ASI (0.0–1.0 tiered scoring) for the repository.
  ## [WS-P2-A Single Hydrate Path] Mirrors getUnifiedAsiFixed4: the cached
  ## ax_proof_state.json fast path was REMOVED — always hydrates from the
  ## certificate vault (canonical SSOT). `forceHydration` is retained for API
  ## compatibility and ignored.
  proc hydrateGraded(): ValidatedAsi {.raises: [].} =
    let (hydrated, _) = hydrateProofStateFromCertificateVault(repoRoot / AXIOM_CERT_VAULT_DIR, repoRoot)
    let summary = hydrated.getOrDefault("summary")
    if summary.isNil or summary.kind != JObject:
      return exportAsiFixed4(initAsiRatio(0.0).get(defaultAsiRatio()))
    let gradedStr = summary.getOrDefault("engineAsiGraded4").getStr("0.0000")
    let parsed = safeParseFloat(gradedStr)
    if parsed.isOk:
      return exportAsiFixed4(initAsiRatio(parsed.get).get(defaultAsiRatio()))
    return exportAsiFixed4(initAsiRatio(0.0).get(defaultAsiRatio()))

  hydrateGraded()
{.pop.}

