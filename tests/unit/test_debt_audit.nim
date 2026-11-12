## Phase 7/8 audit module tests.
##
## Verifies:
##  (a) manifestInputId is deterministic and differs on rule change
##  (b) two runs for the SAME manifest+ordinal+nonce yield the SAME auditRunId
##  (c) replayExact: a persisted run round-trips (ok=true)
##  (d) a tampered run (change one byte) → replay ok=false

import std/[unittest, os, strutils, json]
import core/types/debt_types
import core/trusted/append_store
import core/debt/debt_audit
import core/debt/debt_identity
import core/debt/debt_classifier

suite "buildAuditInput — deterministic input id (I9)":
  test "manifestInputId is deterministic for identical manifests":
    let evRoot = ContentDigest(sha256Ref("evidence:", "sample-evidence-payload"))
    let m1 = buildAuditInput(evRoot, "rules-v1", "nim-2.2.10")
    let m2 = buildAuditInput(evRoot, "rules-v1", "nim-2.2.10")
    check manifestInputId(m1) == manifestInputId(m2)

  test "manifestInputId differs when ruleSetHash changes":
    let evRoot = ContentDigest(sha256Ref("evidence:", "sample-evidence-payload"))
    let m1 = buildAuditInput(evRoot, "rules-v1", "nim-2.2.10")
    let m2 = buildAuditInput(evRoot, "rules-v2", "nim-2.2.10")
    check manifestInputId(m1) != manifestInputId(m2)

  test "manifestInputId differs when evidenceRoot changes":
    let evRoot1 = ContentDigest(sha256Ref("evidence:", "payload-A"))
    let evRoot2 = ContentDigest(sha256Ref("evidence:", "payload-B"))
    let m1 = buildAuditInput(evRoot1, "rules-v1", "nim-2.2.10")
    let m2 = buildAuditInput(evRoot2, "rules-v1", "nim-2.2.10")
    check manifestInputId(m1) != manifestInputId(m2)

suite "recordAuditRun — deterministic run id (I10)":
  test "two runs for the SAME manifest+ordinal+nonce yield the SAME auditRunId":
    let evRoot = ContentDigest(sha256Ref("evidence:", "sample-evidence-payload"))
    let manifest = buildAuditInput(evRoot, "rules-v1", "nim-2.2.10")
    let resultRoot = ContentDigest(sha256Ref("result:", ""))
    let nonce = "test-nonce-42"
    let tmpDir = getTempDir()
    let journalPath = tmpDir & "/axiom_audit_test_runs.journal"
    # Clean up any leftover file from a previous run.
    if fileExists(journalPath):
      removeFile(journalPath)

    let run1 = recordAuditRun(manifest, resultRoot, nonce, journalPath)
    let run2 = recordAuditRun(manifest, resultRoot, nonce, journalPath)

    # Both runs share the same auditInputId (same manifest).
    check run1.auditInputId == run2.auditInputId
    # ordinal=0 for the first run, ordinal=1 for the second — different run ids.
    check run1.auditRunId != run2.auditRunId

    # Now verify that a SECOND manifest with the same ordinal+nonce gives the SAME run id
    # as the first run for that ordinal. This is the core I10 guarantee.
    let _ = recordAuditRun(manifest, resultRoot, nonce, journalPath)
    # This is ordinal=2 now (third run for this input). To test same ordinal+nonce,
    # we need to construct the run id manually.
    let expectedRunId = newAuditRunId(manifestInputId(manifest), 0, nonce)
    check run1.auditRunId == expectedRunId

  test "same manifest+ordinal+nonce always produces the same auditRunId":
    let evRoot = ContentDigest(sha256Ref("evidence:", "sample-evidence-payload"))
    let manifest = buildAuditInput(evRoot, "rules-v1", "nim-2.2.10")
    let resultRoot = ContentDigest(sha256Ref("result:", ""))
    let nonce = "deterministic-nonce"
    let tmpDir = getTempDir()
    let journalPath = tmpDir & "/axiom_audit_test_runs2.journal"
    if fileExists(journalPath):
      removeFile(journalPath)

    # ordinal=0, nonce="deterministic-nonce" → runId A
    let runId0 = newAuditRunId(manifestInputId(manifest), 0, nonce)
    let _ = recordAuditRun(manifest, resultRoot, nonce, journalPath)
    # ordinal=1, nonce="deterministic-nonce" → runId B
    let runId1 = newAuditRunId(manifestInputId(manifest), 1, nonce)
    let _ = recordAuditRun(manifest, resultRoot, nonce, journalPath)

    # Read back and verify the stored run ids match the derived ones.
    let runs = readAuditRuns(journalPath)
    check runs.len == 2
    check runs[0].auditRunId == runId0
    check runs[1].auditRunId == runId1

suite "replayExact — byte-level replay verification":
  test "persisted run round-trips (ok=true)":
    let evRoot = ContentDigest(sha256Ref("evidence:", "sample-evidence-payload"))
    let manifest = buildAuditInput(evRoot, "rules-v1", "nim-2.2.10")
    let resultRoot = ContentDigest(sha256Ref("result:", ""))
    let nonce = "replay-test-nonce"
    let tmpDir = getTempDir()
    let journalPath = tmpDir & "/axiom_audit_test_replay.journal"
    if fileExists(journalPath):
      removeFile(journalPath)

    let run = recordAuditRun(manifest, resultRoot, nonce, journalPath)
    # ordinal=0 for the first run for this input.
    let expectedRunId = newAuditRunId(manifestInputId(manifest), 0, nonce)
    check run.auditRunId == expectedRunId

    let (ok, reason) = replayExact(run.auditRunId, journalPath)
    check ok == true
    check reason == ""

  test "tampered run (change one byte) → replay ok=false":
    let evRoot = ContentDigest(sha256Ref("evidence:", "sample-evidence-payload"))
    let manifest = buildAuditInput(evRoot, "rules-v1", "nim-2.2.10")
    let resultRoot = ContentDigest(sha256Ref("result:", ""))
    let nonce = "tamper-test-nonce"
    let tmpDir = getTempDir()
    let journalPath = tmpDir & "/axiom_audit_test_tamper.journal"
    if fileExists(journalPath):
      removeFile(journalPath)

    let run = recordAuditRun(manifest, resultRoot, nonce, journalPath)

    # Tamper: read the journal, change one byte in the nonce field of the stored record,
    # then write it back. This makes the stored nonce differ from what replayExact will
    # use to re-derive the run id, causing a mismatch.
    var lines = readRecords(journalPath)
    check lines.len >= 1
    var node = parseJson(lines[0])
    # Flip one character in the nonce (change last char 'e' to 'f').
    let originalNonce = node["nonce"].getStr()
    let tamperedNonce = originalNonce[0 .. ^2] & "f"
    node["nonce"] = %tamperedNonce
    # Keep auditRunId unchanged — now the stored run id won't match the re-derived one.
    lines[0] = $node
    # Write the tampered record back as a single line.
    writeFile(journalPath, lines.join("\n") & "\n")

    let (ok, reason) = replayExact(run.auditRunId, journalPath)
    check ok == false
    check reason != ""

suite "reevaluate — new manifest with changed rule set":
  test "reevaluate produces a new manifest with different ruleSetHash and different inputId":
    let evRoot = ContentDigest(sha256Ref("evidence:", "sample-evidence-payload"))
    let manifest = buildAuditInput(evRoot, "rules-v1", "nim-2.2.10")
    let originalInputId = manifestInputId(manifest)

    let newManifest = reevaluate(manifest, "rules-v2")
    let newInputId = manifestInputId(newManifest)

    check newManifest.ruleSetHash == "rules-v2"
    check newManifest.evidenceRoot == manifest.evidenceRoot
    check newManifest.repositorySnapshot == manifest.repositorySnapshot
    check newManifest.toolchainContext == manifest.toolchainContext
    # The input id must change because the ruleSetHash changed.
    check newInputId != originalInputId

  test "reevaluate preserves all roots (past evidence preserved)":
    let evRoot = ContentDigest(sha256Ref("evidence:", "sample-evidence-payload"))
    let provRoot = ContentDigest(sha256Ref("provenance:", "prov-data"))
    let artRoot = ContentDigest(sha256Ref("artifact:", "artifact-data"))
    let execRoot = ContentDigest(sha256Ref("execution:", "exec-data"))
    let manifest = AuditInputManifest(
      repositorySnapshot: "repo-abc123",
      evidenceRoot: evRoot,
      provenanceRoot: provRoot,
      artifactRoot: artRoot,
      executionRoot: execRoot,
      ruleSetHash: "rules-v1",
      toolchainContext: "nim-2.2.10"
    )
    let newManifest = reevaluate(manifest, "rules-v2")
    check newManifest.evidenceRoot == evRoot
    check newManifest.provenanceRoot == provRoot
    check newManifest.artifactRoot == artRoot
    check newManifest.executionRoot == execRoot
    check newManifest.repositorySnapshot == "repo-abc123"
    check newManifest.toolchainContext == "nim-2.2.10"
    check newManifest.ruleSetHash == "rules-v2"
