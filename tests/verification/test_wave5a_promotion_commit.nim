import std/options
import std/os
import std/json
import std/tempfiles
import core/results
import core/crypto/hash_kernel
import core/trusted/scope_identity
import core/trusted/trust_commit

## Test suite for Wave5a: cert_promotion durable writes migrated to the
## TrustCommit journal.
##
## Verifies the promotion / reclassification TrustCommit shape (built exactly as
## cert_promotion.promoteToCanonical / reclassifyCertificates build it) validates,
## persists durably, round-trips, replays, and is content-sensitive.

var failures = 0

proc expect(cond: bool; msg: string) =
  if not cond:
    inc failures
    echo "  FAIL: " & msg

var baseCounter = 0
proc tmpBase(): string =
  inc baseCounter
  let d = getTempDir() / "axiom_w5a_test" / ($getCurrentProcessId() & "_" & $baseCounter)
  if not dirExists(d):
    createDir(d)
  d

## Build the same TrustCommit shape as cert_promotion: claim = canonical JSON of
## the promoted cert content, solverInvocation = "cert-promotion",
## certificateDigest = sha256(claim), scope/config digests via the certificate*
## helpers, kind = tcVerifiedProof.
proc promotionCommit(certJson: JsonNode; irHash, solverStatus, leanProposition,
                     semanticProfileId: string): TrustCommit =
  let claim = pretty(certJson) & "\n"
  let digest = hash_kernel.sha256Hex(claim)
  let modulePath = certJson.getOrDefault("modulePath").getStr("")
  let functionName = certJson.getOrDefault("functionName").getStr("")
  TrustCommit(
    kind: tcVerifiedProof,
    evidenceId: computeEvidenceId(claim, "cert-promotion", digest),
    claim: claim,
    solverInvocation: "cert-promotion",
    attestation: "Certificate promotion recorded in TrustCommit journal",
    certificateDigest: digest,
    scopeDigest: certificateScopeDigestForPair(modulePath, functionName),
    configDigest: certificateConfigDigestForPair(
      modulePath, functionName, solverStatus, irHash, leanProposition, semanticProfileId),
    parentCommit: none(string)
  )

echo "=== wave5a promotion TrustCommit tests ==="

# --- 1. Promotion commit shape validates ---
block:
  let cert = %*{
    "modulePath": "src/example/add.nim",
    "functionName": "add",
    "irHash": "w5a-irhash-1",
    "status": "certGreen",
    "solverStatus": "unsat",
    "leanProposition": "add_commutes",
    "backend": "z3",
    "contentHash": "sha256:abc"
  }
  let c = promotionCommit(cert, "w5a-irhash-1", "unsat", "add_commutes", "")
  expect(validateCommit(c).ok, "promotion TrustCommit validates")
  expect(c.solverInvocation == "cert-promotion", "solverInvocation is cert-promotion")
  expect(c.kind == tcVerifiedProof, "kind is tcVerifiedProof")
  echo "Test 1 PASSED: promotion commit validates"

# --- 2. commitVerification roundtrip ---
block:
  let base = tmpBase()
  let cert = %*{
    "modulePath": "src/example/add.nim",
    "functionName": "add",
    "irHash": "w5a-irhash-2",
    "status": "certGreen",
    "solverStatus": "unsat"
  }
  let c = promotionCommit(cert, "w5a-irhash-2", "unsat", "", "")
  let res = commitVerification(base, c)
  expect(res.ok, "commitVerification ok: " & (if res.isErr: res.error else: ""))
  let cid = res.value
  expect(fileExists(commitPath(base, cid)), "journal file created at <commitId>.json")
  let back = readCommit(base, cid)
  expect(back.ok, "readCommit ok")
  expect(back.value.claim == c.claim, "claim round-trip")
  expect(back.value.solverInvocation == "cert-promotion", "solverInvocation round-trip")
  expect(back.value.evidenceId == c.evidenceId, "evidenceId round-trip")
  expect(back.value.certificateDigest == c.certificateDigest, "certificateDigest round-trip")
  expect(validateCommit(back.value).ok, "persisted commit re-validates")
  echo "Test 2 PASSED: commitVerification roundtrip"

# --- 3. replayJournal admits the promotion commit ---
block:
  let base = tmpBase()
  let cert = %*{
    "modulePath": "src/example/add.nim",
    "functionName": "add",
    "irHash": "w5a-irhash-3",
    "status": "certGreen",
    "solverStatus": "unsat"
  }
  let c = promotionCommit(cert, "w5a-irhash-3", "unsat", "", "")
  let r = commitVerification(base, c)
  expect(r.ok, "commit ok: " & (if r.isErr: r.error else: ""))
  let st = replayJournal(base)
  expect(st.ok, "replayJournal ok: " & (if st.isErr: st.error else: ""))
  expect(st.value.commitIds == @[r.value], "replay admits exactly one commit")
  expect(st.value.stateDigest == computeStateDigest(@[r.value]), "stateDigest matches recompute")
  expect(st.value.scopeDigest == c.scopeDigest, "replay carries scopeDigest")
  expect(st.value.configDigest == c.configDigest, "replay carries configDigest")
  echo "Test 3 PASSED: replayJournal"

# --- 4. evidenceId is content-sensitive ---
block:
  let certA = %*{"modulePath": "m", "functionName": "f", "irHash": "h", "status": "certGreen"}
  let certB = %*{"modulePath": "m", "functionName": "f", "irHash": "h", "status": "certYellow"}
  let ca = promotionCommit(certA, "h", "unsat", "", "")
  let cb = promotionCommit(certB, "h", "unsat", "", "")
  expect(ca.evidenceId != cb.evidenceId, "changed status content changes evidenceId")
  var changed = ca
  changed.certificateDigest = "other-digest"
  expect(computeEvidenceId(changed.claim, changed.solverInvocation, changed.certificateDigest) != ca.evidenceId,
         "changed certificateDigest changes evidenceId")
  echo "Test 4 PASSED: evidenceId content-sensitive"

echo ""
if failures == 0:
  echo "=== All wave5a promotion TrustCommit tests PASSED ==="
else:
  echo "=== " & $failures & " wave5a promotion TrustCommit test(s) FAILED ==="
  quit(1)
