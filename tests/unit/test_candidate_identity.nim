import std/[unittest, os, tempfiles]
import core/crypto/hash_kernel
import core/types/candidate_identity
import core/results

## Unit tests for candidate_identity.nim (ADR-0020 Phase 1).
## Covers: deterministic identity digests, hash-of-parts convention,
## materialization matching, and JSON round-trip.

var failures = 0

proc expect(cond: bool; msg: string) =
  if not cond:
    inc failures
    echo "  FAIL: " & msg

proc expectOk[T](r: Result[T, string]; msg: string) =
  if not r.ok:
    inc failures
    echo "  FAIL: " & msg & " — error: " & r.err
  else:
    echo "  PASS: " & msg

proc expectEq[T](a, b: T; msg: string) =
  if a != b:
    inc failures
    echo "  FAIL: " & msg & " — got: " & $a & ", expected: " & $b
  else:
    echo "  PASS: " & msg

suite "Candidate identity — deterministic digests and round-trip":

  test "candidateStateIdentity: same treeDigest → same identityDigest":
    let a = candidateStateIdentity("abc123")
    let b = candidateStateIdentity("abc123")
    expect(a.identityDigest == b.identityDigest, "same treeDigest yields same identityDigest")
    expect(a.identityDigest == sha256Hex("abc123"), "identityDigest is sha256(treeDigest)")

  test "candidateStateIdentity: different treeDigest → different identityDigest":
    let a = candidateStateIdentity("abc123")
    let b = candidateStateIdentity("def456")
    expect(a.identityDigest != b.identityDigest, "different treeDigest yields different identityDigest")

  test "candidateStateIdentity: treeDigest preserved":
    let tree = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    let csi = candidateStateIdentity(tree)
    expect(csi.treeDigest == tree, "treeDigest preserved in CandidateStateIdentity")
    expect(csi.identityDigest == sha256Hex(tree), "identityDigest is sha256(treeDigest)")

  test "candidateProvenance: order-sensitive digest":
    let cd1 = ChangeDescriptor(prNumber: 1, headSha: "aaa")
    let cd2 = ChangeDescriptor(prNumber: 2, headSha: "bbb")
    let p1 = candidateProvenance("base1", @[cd1, cd2], "repoX")
    let p2 = candidateProvenance("base1", @[cd2, cd1], "repoX")
    expect(p1.provenanceDigest != p2.provenanceDigest, "order of changes affects provenanceDigest")
    expect(p1.baseCommit == "base1", "baseCommit preserved")
    expect(p1.orderedChanges.len == 2, "two ordered changes")

  test "candidateProvenance: deterministic":
    let cd = ChangeDescriptor(prNumber: 1, headSha: "aaa")
    let p1 = candidateProvenance("base1", @[cd], "repoX")
    let p2 = candidateProvenance("base1", @[cd], "repoX")
    expect(p1.provenanceDigest == p2.provenanceDigest, "same inputs yield same provenanceDigest")

  test "verificationContextIdentity: contextDigest is sha256 of parts":
    let vci = verificationContextIdentity("pol", "tool", "contract")
    expect(vci.contextDigest == sha256Hex("pol|tool|contract"), "contextDigest = sha256(policy|toolchain|contract)")
    expect(vci.policyDigest == "pol", "policyDigest preserved")
    expect(vci.toolchainDigest == "tool", "toolchainDigest preserved")
    expect(vci.verificationContractDigest == "contract", "verificationContractDigest preserved")

  test "verificationContextIdentity: deterministic":
    let v1 = verificationContextIdentity("pol", "tool", "contract")
    let v2 = verificationContextIdentity("pol", "tool", "contract")
    expect(v1.contextDigest == v2.contextDigest, "same inputs yield same contextDigest")

  test "candidateEvidenceDigest: hash-of-parts convention":
    let ced = candidateEvidenceDigest("state1", "prov1", "ctx1")
    expect(ced.digest == sha256Hex("state1|prov1|ctx1"), "digest = sha256(state|provenance|context)")
    expect(ced.stateIdentity == "state1", "stateIdentity preserved")
    expect(ced.provenanceDigest == "prov1", "provenanceDigest preserved")
    expect(ced.contextDigest == "ctx1", "contextDigest preserved")

  test "candidateEvidenceDigest: different inputs → different digest":
    let ced1 = candidateEvidenceDigest("s1", "p1", "c1")
    let ced2 = candidateEvidenceDigest("s2", "p1", "c1")
    expect(ced1.digest != ced2.digest, "different stateIdentity → different digest")

  test "materializationMatches: true when declared == resolved":
    let matchRec = MaterializationRecord(
      candidateRef: "ref", declaredTreeDigest: "tree123",
      resolvedTreeDigest: "tree123", readPath: "/commits/abc", match: false)
    expect(materializationMatches(matchRec), "match=true when declared == resolved")

  test "materializationMatches: false when declared != resolved":
    let mismatchRec = MaterializationRecord(
      candidateRef: "ref", declaredTreeDigest: "tree123",
      resolvedTreeDigest: "tree456", readPath: "/commits/abc", match: false)
    expect(not materializationMatches(mismatchRec), "match=false when declared != resolved")

  test "MaterializedCandidate: toJson/fromJson round-trip":
    let cd = ChangeDescriptor(prNumber: 1, headSha: "abc")
    let prov = candidateProvenance("base1", @[cd], "repoX")
    let mc = MaterializedCandidate(
      candidateRef: "refs/heads/mybranch", candidateCommit: "abc123",
      declaredTreeDigest: "tree123", provenance: prov)
    let json = mc.toJson
    let back = materializedCandidateFromJson(json)
    expectOk(back, "materializedCandidateFromJson succeeds")
    if back.ok:
      let b = back.value
      expect(b.candidateRef == mc.candidateRef, "candidateRef round-trip")
      expect(b.candidateCommit == mc.candidateCommit, "candidateCommit round-trip")
      expect(b.declaredTreeDigest == mc.declaredTreeDigest, "declaredTreeDigest round-trip")
      expect(b.provenance.baseCommit == prov.baseCommit, "provenance.baseCommit round-trip")

  test "MaterializationRecord: toJson/fromJson round-trip":
    let mr = MaterializationRecord(
      candidateRef: "ref", declaredTreeDigest: "decl",
      resolvedTreeDigest: "res", readPath: "/path", match: true)
    let json = mr.toJson
    let back = materializationRecordFromJson(json)
    expectOk(back, "materializationRecordFromJson succeeds")
    if back.ok:
      let b = back.value
      expect(b.candidateRef == mr.candidateRef, "candidateRef round-trip")
      expect(b.declaredTreeDigest == mr.declaredTreeDigest, "declaredTreeDigest round-trip")
      expect(b.resolvedTreeDigest == mr.resolvedTreeDigest, "resolvedTreeDigest round-trip")
      expect(b.readPath == mr.readPath, "readPath round-trip")
      expect(b.match == mr.match, "match round-trip")

  test "ChangeDescriptor: stable hash":
    let cd1 = ChangeDescriptor(prNumber: 5, headSha: "sha1")
    let cd2 = ChangeDescriptor(prNumber: 5, headSha: "sha1")
    expect(changeDescriptorHash(cd1) == changeDescriptorHash(cd2), "same descriptor → same hash")
    let cd3 = ChangeDescriptor(prNumber: 6, headSha: "sha1")
    expect(changeDescriptorHash(cd1) != changeDescriptorHash(cd3), "different prNumber → different hash")

echo ""
if failures == 0:
  echo "=== All candidate_identity tests PASSED ==="
else:
  echo "=== " & $failures & " candidate_identity test(s) FAILED ==="
  quit(1)
