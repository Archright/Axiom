import std/[os, json]
import ../../src/verification/integrity_ledger
import ../../src/core/trusted/trust_commit
import std/unittest

proc testFlushGlobalAuditBufferToCertificates() =
  let baseDir = getTempDir() / ("axiom_integrity_ledger_test_" & $getCurrentProcessId())
  let certDir = baseDir / ".axiom" / "vault"
  let journalBaseDir = parentDir(certDir)
  createDir(certDir)
  let certPath = certDir / "sample.nim::testProc.json"
  let staleContent = """{"status":"stale","modulePath":"sample.nim","functionName":"testProc"}"""
  writeFile(certPath, staleContent)

  # Populate global audit buffer
  appendToReasoningTrail("sample.nim::testProc", %*{"phase": "symbolic_analysis"})
  appendToReasoningTrail("sample.nim::testProc", %*{"phase": "verdict", "verdict": "certGreen"})
  setTransitionLog("sample.nim::testProc", @[%*{"from": "", "to": "certGreen"}])

  flushGlobalAuditBufferToCertificates(certDir)

  check readFile(certPath) == staleContent
  let ids = listCommitIds(journalBaseDir)
  check ids.ok
  check ids.value.len == 1
  let commit = readCommit(journalBaseDir, ids.value[0])
  check commit.ok
  let claim = parseJson(commit.value.claim)
  check claim.kind == JObject
  let reasoningTrail = claim{"reasoningTrail"}
  check not reasoningTrail.isNil and reasoningTrail.kind == JArray
  check reasoningTrail.len == 2
  let transitionLog = claim{"transitionLog"}
  check not transitionLog.isNil and transitionLog.kind == JArray
  check transitionLog.len == 1

  removeDir(certDir)
  removeDir(journalBaseDir / "trusted")

suite "Integrity Ledger":
  test "Integrity Ledger tests":
    testFlushGlobalAuditBufferToCertificates()
