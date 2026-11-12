# Wave 5: UAP certificate writer writes JSON payload and hydrates from TrustCommit journal.

import std/json
import std/options
import std/os
import std/strutils

import core/crypto/hash_kernel
import core/trusted/claim_authority
import core/trusted/trust_commit
import core/types/certificate_types
import verification/cert_writer
import verification/proof_state_builder

proc expect(cond: bool; msg: string) =
  if not cond:
    echo "  FAIL: " & msg
    quit(1)

proc main() =
  echo "=== Wave 5 certificate writer TrustCommit hydration ==="
  let repo = getTempDir() / ("ax_wave5_writer_" & $getCurrentProcessId())
  try:
    removeDir(repo)
  except CatchableError:
    # axiom:best-effort(temp dir pre-cleanup is non-fatal; test asserts on certificate writer output)
    discard
  createDir(repo)
  writeFile(repo / ".axiom_root", "repo\n")
  createDir(repo / ".axiom" / "vault")
  createDir(repo / "trusted")

  var logLines: seq[string] = @[]
  let ok = writeCertificateFromUapResult(
    certDir = repo / ".axiom" / "vault",
    modulePath = "src/mod.nim",
    functionName = "f",
    sourceCode = "func f(x:int):int = x",
    leanKernelVerified = true,
    smtlib2 = "(set-logic QF_BV)",
    solverStatus = "unsat",
    logLines = logLines,
    irHash = "wave5ir",
    verifiedClaim = none(VerifiedClaim),
    semanticProfileId = "SPV1")
  expect(ok, "Wave 5 writer succeeds: " & logLines.join("; "))

  let certPath = repo / ".axiom" / "vault" / "wave5ir.json"
  expect(fileExists(certPath), "Wave 5 writer raw JSON exists")
  let certNode = parseFile(certPath)
  expect(certNode["modulePath"].getStr == "src/mod.nim", "raw JSON modulePath")
  expect(certNode["functionName"].getStr == "f", "raw JSON functionName")
  expect(certNode["status"].getStr == "certZ3Candidate", "raw JSON status certZ3Candidate")
  expect(certNode["reason"].getStr == "z3-verified", "raw JSON reason z3-verified")
  expect(certNode["smtlib2"].getStr == "(set-logic QF_BV)", "raw JSON smtlib2")

  let idsRes = listCommitIds(repo)
  expect(idsRes.ok, "writer journal ids available")
  # A2/S2-rev.4: a naked leanKernelVerified flag (no bound leanProposition) is
  # lean-evidence-unbound, so the Z3-only tier status is emitted (never certGreen).
  # The batch-uap-loop certificate projection is journaled at the repo root
  # (commitCertificateVerification routes via repoRootForPath); the z3out record
  # journals under the certDir-relative journal.
  expect(idsRes.value.len == 1, "writer emits exactly one batch-uap-loop commit")
  let commitId = idsRes.value[0]
  let journalCommitPath = commitPath(repo, commitId)
  expect(fileExists(journalCommitPath), "journal commit exists")
  let commitRes = readCommit(repo, commitId)
  expect(commitRes.ok, "journal commit reads")
  expect(validateCommit(commitRes.value).ok, "journal commit validates")
  expect(commitRes.value.solverInvocation == "batch-uap-loop", "journal solverInvocation is batch-uap-loop")
  expect(commitRes.value.certificateDigest == sha256Hex(commitRes.value.claim), "journal certificateDigest binds claim")
  let commitNode = parseJson(commitToJson(commitRes.value))
  let claimNode = parseJson(commitRes.value.claim)
  expect(commitNode["kind"].getStr == "tcVerifiedProof", "journal kind tcVerifiedProof")
  expect(claimNode["modulePath"].getStr == "src/mod.nim", "journal claim modulePath")
  expect(claimNode["functionName"].getStr == "f", "journal claim functionName")
  expect(claimNode["status"].getStr == "certZ3Candidate", "journal claim status certZ3Candidate")
  expect(claimNode["reason"].getStr == "z3-verified", "journal claim reason z3-verified")

  let replayRes = replayJournal(repo)
  expect(replayRes.ok, "replayJournal succeeds")
  expect(replayRes.value.commitIds == idsRes.value, "replayJournal returns writer commits")

  let (journalHydratedState, journalHydratedCertificates) = hydrateProofStateFromTrustCommitJournal(repo)
  expect(journalHydratedCertificates.len == 1, "journal hydrate returns one certificate")
  expect(journalHydratedState["entries"].len == 1, "journal hydrate returns one entry")
  # B2: a certZ3Candidate is candidate-only — it must never be counted verified.
  expect(journalHydratedState["summary"]["verified"].getInt == 0, "journal hydrate verified count")
  expect(journalHydratedState["summary"]["attemptedNodes"].getInt == 1, "journal hydrate attemptedNodes")
  expect(string(journalHydratedCertificates[0].modulePath) == "src/mod.nim", "journal hydrate modulePath")
  expect(journalHydratedCertificates[0].functionName == "f", "journal hydrate functionName")
  expect(journalHydratedCertificates[0].status == certZ3Candidate, "journal hydrate certZ3Candidate")

  let (vaultHydratedState, vaultHydratedCertificates) = hydrateProofStateFromCertificateVault(repo / ".axiom" / "vault", repo)
  expect(vaultHydratedCertificates.len == 1, "vault hydrate does not duplicate journal certificate")
  expect(vaultHydratedState["entries"].len == 1, "vault hydrate does not duplicate journal entry")
  expect(vaultHydratedState["summary"]["verified"].getInt == 0, "vault hydrate verified count")
  expect(vaultHydratedState["summary"]["attemptedNodes"].getInt == 1, "vault hydrate attemptedNodes")
  expect(string(vaultHydratedCertificates[0].modulePath) == "src/mod.nim", "vault hydrate modulePath")
  expect(vaultHydratedCertificates[0].functionName == "f", "vault hydrate functionName")
  expect(vaultHydratedCertificates[0].status == certZ3Candidate, "vault hydrate certZ3Candidate")

  let (journalDirHydratedState, journalDirHydratedCertificates) = hydrateProofStateFromCertificateVault(repo / "trusted" / "journal", repo)
  expect(journalDirHydratedCertificates.len == 1, "journal-dir hydrate returns journal certificate once")
  expect(journalDirHydratedState["entries"].len == 1, "journal-dir hydrate returns journal entry once")
  expect(journalDirHydratedState["summary"]["verified"].getInt == 0, "journal-dir hydrate verified count")
  expect(journalDirHydratedState["summary"]["attemptedNodes"].getInt == 1, "journal-dir hydrate attemptedNodes")
  expect(string(journalDirHydratedCertificates[0].modulePath) == "src/mod.nim", "journal-dir hydrate modulePath")
  expect(journalDirHydratedCertificates[0].functionName == "f", "journal-dir hydrate functionName")
  expect(journalDirHydratedCertificates[0].status == certZ3Candidate, "journal-dir hydrate certZ3Candidate")

  echo "  OK: Wave 5 writer JSON payload + TrustCommit hydration"
  removeDir(repo)
  echo "=== Wave 5 certificate writer TrustCommit hydration OK ==="

main()
