import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

import std/os
import std/options
import std/json
import std/strutils
import infrastructure/logging_facade
import core/axiom_pragmas
import verification/certificate_verifier
import core/trusted/trust_commit
import core/trusted/cert_v2
import core/trusted/assurance_profile

func certFromClaimJson(node: JsonNode; subjectId: string): CertificateV2 =
  ## Project a CertificateV2 from a TrustCommit's claim JSON (the authoritative
  ## journal path). Mirrors the legacy vault reconstruction defaults so both the
  ## journal-first and legacy-fallback paths yield the same certificate shape.
  let outcomeStr = if node.hasKey("outcome"): node["outcome"].getStr() else: ""
  CertificateV2(
    subjectId: subjectId,
    outcome: (case outcomeStr
              of "clProved": clProved
              of "clDisproved": clDisproved
              of "clUnknown": clUnknown
              of "clUnsupported": clUnsupported
              of "clNoSpecification": clNoSpecification
              of "clDependencyBlocked": clDependencyBlocked
              of "clInvalidEvidence": clInvalidEvidence
              else: clProved),
    assurance: AssuranceProfile(),
    specificationId: if node.hasKey("specificationId"): node["specificationId"].getStr() else: "",
    semanticProfileId: if node.hasKey("semanticProfileId"): node["semanticProfileId"].getStr() else: "",
    obligationId: if node.hasKey("obligationId"): node["obligationId"].getStr() else: "",
    evidenceId: if node.hasKey("evidenceId"): node["evidenceId"].getStr() else: "",
    dependencySnapshotId: if node.hasKey("dependencySnapshotId"): node["dependencySnapshotId"].getStr() else: "",
    policyId: if node.hasKey("policyId"): node["policyId"].getStr() else: "",
    smtHash: if node.hasKey("smtHash"): node["smtHash"].getStr() else: "",
    proofArtifactDigest: if node.hasKey("proofArtifactDigest"): node["proofArtifactDigest"].getStr() else: "",
    schemaVersion: if node.hasKey("schemaVersion"): node["schemaVersion"].getStr() else: "2",
    identityDigest: if node.hasKey("identityDigest"): node["identityDigest"].getStr() else: ""
  )

proc locateCertFromJournal*(claimsDir: string; subjectId: string): Option[CertificateV2] {.raises: [CatchableError], axiomDecision(id = "DECISION-0641", reason = "Authoritative journal-first certificate lookup by subjectId for verify; TrustCommit journal is the authoritative source, returns none when journal absent or replay fails (non-breaking)", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  ## Authoritative journal-first lookup (Wave6a). Replays the TrustCommit journal
  ## and returns the FIRST commit whose claim JSON carries the requested
  ## subjectId, reconstructed as a CertificateV2. Returns none when the journal is
  ## absent, corrupt, or admits no matching commit — the caller then falls back to
  ## the legacy raw-vault scan.
  if not dirExists(journalDir(claimsDir)):
    logInfo("verify_cli", "[verify] journal absent for " & claimsDir & ", falling back to legacy vault")
    return none(CertificateV2)
  let replayRes = replayJournal(claimsDir)
  if not replayRes.ok:
    logInfo("verify_cli", "[verify] journal replay failed for " & claimsDir & ": " & replayRes.err & ", falling back to legacy vault")
    return none(CertificateV2)
  for commitId in replayRes.value.commitIds:
    let readRes = readCommit(claimsDir, commitId)
    if not readRes.ok:
      continue
    let node = try: parseJson(readRes.value.claim) except CatchableError: continue
    if node.hasKey("subjectId") and node["subjectId"].getStr() == subjectId:
      logInfo("verify_cli", "[verify] cert from authoritative journal for subject " & subjectId)
      return some(certFromClaimJson(node, subjectId))
  none(CertificateV2)

proc locateCertFromVault*(claimsDir: string; subjectId: string): Option[CertificateV2] {.raises: [CatchableError], axiomDecision(id = "DECISION-0642", reason = "Legacy raw-vault certificate lookup by subjectId for verify; non-authoritative fallback when journal has no matching commit", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  ## LEGACY non-authoritative raw-vault scan. Only consulted when the TrustCommit
  ## journal has no matching commit (backward-compatibility path). Kept so existing
  ## consumers (e.g. tests that write a raw cert only) keep working unchanged.
  let vaultDir = claimsDir / ".axiom/vault"
  if not dirExists(vaultDir):
    return none(CertificateV2)
  for kind, path in walkDir(vaultDir):
    if kind != pcFile:
      continue
    if not path.endsWith(".json"):
      continue
    let content = try: readFile(path) except CatchableError: continue
    let node = try: parseJson(content) except CatchableError: continue
    if node.hasKey("subjectId") and node["subjectId"].getStr() == subjectId:
      return some(certFromClaimJson(node, subjectId))
  none(CertificateV2)

proc locateCert*(claimsDir: string; subjectId: string): Option[CertificateV2] {.raises: [CatchableError], axiomDecision(id = "DECISION-0637", reason = "Locate a Claim's CertificateV2 by subjectId for verify; TrustCommit journal is authoritative, legacy vault is non-authoritative fallback; Option on miss", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  ## Locate a Claim's CertificateV2 by subjectId for verify. The TrustCommit
  ## journal (replayed) is the AUTHORITATIVE source: a matching commit's
  ## reconstructed certificate always wins. Only when the journal has no match do
  ## we fall back to the legacy raw-vault scan (non-authoritative, backward
  ## compatibility). The source is logged so the cutover is observable.
  let journalCert = locateCertFromJournal(claimsDir, subjectId)
  if journalCert.isSome:
    logInfo("verify_cli", "[verify] cert from authoritative journal for subject " & subjectId)
    return journalCert
  let vaultCert = locateCertFromVault(claimsDir, subjectId)
  if vaultCert.isSome:
    logInfo("verify_cli", "[verify] cert from legacy vault (journal has no match) for subject " & subjectId)
    return vaultCert
  none(CertificateV2)

{.pop.}

proc runVerifyCli*(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read-only artifact integrity verification — validates a persisted
  ## canonical certificate file without re-executing the verification engine.
  ## Uses the trust-closure pipeline (deep verification + identityDigest
  ## recompute + journal binding + replay input consistency + replay equality
  ## via stored semantic projection hash).
  if args.len == 0:
    echo "[verify] Usage: ax verify <cert-path>"
    return 1

  let certPath = args[0]
  if certPath.len == 0:
    echo "[verify] Usage: ax verify <cert-path>"
    return 1

  if not fileExists(certPath):
    echo "[verify] FAILED (ccsMalformed): certificate file not found: " & certPath
    return 1

  try:
    let res = verifyCertificateClosure(certPath)
    case res.status
    of ccsPass:
      echo "[verify] VERIFIED — semanticHash=" & res.semanticHash
      return 0
    of ccsNotCurrent:
      # Artifact is structurally valid but not current product truth.
      # Exit code 4 (NOT_CURRENT) distinguishes this from a genuine
      # integrity failure (exit 1 / VERIFICATION_FAILURE).
      echo "[verify] NOT CURRENT — artifact is valid but not current product truth: " & res.detail
      return 4
    of ccsJournalBindingAbsent, ccsJournalRequired:
      echo "[verify] FAILED (" & $res.status & "): " & res.detail
      return 1
    else:
      echo "[verify] FAILED (" & $res.status & "): " & res.detail
      return 1
  except CatchableError as e:
    echo "[verify] internal error: " & e.msg
    return 1
