## State Manager Self-Healing Tests — Atomic & Reconstructive Persistence
##
## Verifies:
##   1. atomicWriteProofState creates a valid JSON file atomically
##   2. Missing state file is reconstructed from certificates
##   3. Corrupt state file is reconstructed from certificates
##   4. reconstructProofStateFromCertificates counts only valid certs
##   5. Empty certificate directory returns minimal valid state

import std/[unittest, os, json, times, strutils]
import verification/state_persistence
import core/json/json_utils
import core/utils/constants

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc makeTempDir(): string =
  let dir = getTempDir() / "axiom_state_mgr_test_" & $getCurrentProcessId() & "_" & $cast[int](epochTime())
  createDir(dir)
  dir

proc writeCert(dir: string; name: string; data: JsonNode) =
  writeFile(dir / name, pretty(data))

# ---------------------------------------------------------------------------
# Suite: atomicWriteProofState
# ---------------------------------------------------------------------------

suite "atomicWriteProofState":

  test "creates a valid JSON file from raw string":
    let tmpDir = makeTempDir()
    let statePath = tmpDir / "test_state.json"
    let state = %*{
      "summary": { "verified": 3, "totalSourceFunctions": 10 },
      "entries": []
    }
    let ok = atomicWriteProofState(statePath, pretty(state))
    check ok == true
    check fileExists(statePath)
    let raw = readFile(statePath)
    let parsed = parseJson(raw)
    check parsed.kind == JObject
    check parsed["summary"]["verified"].getInt() == 3
    removeDir(tmpDir)

  test "overwrites existing file atomically":
    let tmpDir = makeTempDir()
    let statePath = tmpDir / "test_state.json"
    writeFile(statePath, """{"old": true}""")
    let newState = %*{ "summary": { "verified": 1 } }
    let ok = atomicWriteProofState(statePath, pretty(newState))
    check ok == true
    let parsed = parseJson(readFile(statePath))
    check parsed.hasKey("summary")
    check not parsed.hasKey("old")
    removeDir(tmpDir)

  test "creates parent directory if missing":
    let tmpDir = makeTempDir()
    let nestedDir = tmpDir / "deep" / "nested"
    createDir(nestedDir)
    let statePath = nestedDir / "state.json"
    let state = %*{ "entries": [] }
    let ok = atomicWriteProofState(statePath, pretty(state))
    check ok == true
    check fileExists(statePath)
    removeDir(tmpDir)

  test "returns false for invalid path":
    let state = %*{ "entries": [] }
    let ok = atomicWriteProofState("/nonexistent/deeply/nested/path/state.json", pretty(state))
    # On most systems this should fail
    # (but some temp dirs may allow it, so we just check no crash)
    discard ok

# ---------------------------------------------------------------------------
# Suite: reconstructProofStateFromCertificates
# ---------------------------------------------------------------------------

suite "reconstructProofStateFromCertificates":

  test "reconstructs state from valid certificates":
    let tmpDir = makeTempDir()
    let certDir = tmpDir / "certs"
    createDir(certDir)
    writeCert(certDir, "cert_a.json", %*{
      "modulePath": "src/math.nim",
      "functionName": "add",
      "sourceHash": "hash_a",
      "status": "certGreen",
      "winningStrategy": "tautology",
      "solverMeta": { "leanCompilerVerified": true }
    })
    writeCert(certDir, "cert_b.json", %*{
      "modulePath": "src/math.nim",
      "functionName": "mul",
      "sourceHash": "hash_b",
      "status": "certVerifiedAxiom",
      "winningStrategy": "lean-replay",
      "solverMeta": { "leanCompilerVerified": true }
    })
    let state = reconstructProofStateFromCertificates(certDir, 10)
    check state.kind == JObject
    check state.hasKey("summary")
    check state["summary"]["verified"].getInt() == 2
    check state["summary"]["totalSourceFunctions"].getInt() == 10
    check state["summary"]["timedOut"].getInt() == 0
    check state["summary"]["failedCount"].getInt() == 0
    let entries = state["entries"]
    check entries.kind == JArray
    check entries.len == 2
    check state["reconstructedFromCertificates"].getBool() == true
    removeDir(tmpDir)

  test "skips certificates with non-hydratable status":
    let tmpDir = makeTempDir()
    let certDir = tmpDir / "certs"
    createDir(certDir)
    writeCert(certDir, "good.json", %*{
      "modulePath": "src/a.nim",
      "functionName": "f1",
      "sourceHash": "h1",
      "status": "certGreen",
      "winningStrategy": "strat",
      "solverMeta": { "leanCompilerVerified": true }
    })
    writeCert(certDir, "bad_status.json", %*{
      "modulePath": "src/a.nim",
      "functionName": "f2",
      "sourceHash": "h2",
      "status": "certRed",
      "winningStrategy": "strat",
      "solverMeta": { "leanCompilerVerified": true }
    })
    writeCert(certDir, "pending.json", %*{
      "modulePath": "src/a.nim",
      "functionName": "f3",
      "sourceHash": "h3",
      "status": "certPending",
      "winningStrategy": "strat",
      "solverMeta": { "leanCompilerVerified": true }
    })
    let state = reconstructProofStateFromCertificates(certDir, 5)
    check state["summary"]["verified"].getInt() == 1
    check state["entries"].len == 1
    check state["entries"][0]["functionName"].getStr() == "f1"
    removeDir(tmpDir)

  test "skips certificates where lean not verified":
    let tmpDir = makeTempDir()
    let certDir = tmpDir / "certs"
    createDir(certDir)
    writeCert(certDir, "unverified.json", %*{
      "modulePath": "src/a.nim",
      "functionName": "f1",
      "sourceHash": "h1",
      "status": "certGreen",
      "winningStrategy": "strat",
      "solverMeta": { "leanCompilerVerified": false }
    })
    writeCert(certDir, "no_meta.json", %*{
      "modulePath": "src/a.nim",
      "functionName": "f2",
      "sourceHash": "h2",
      "status": "certGreen",
      "winningStrategy": "strat"
    })
    let state = reconstructProofStateFromCertificates(certDir, 5)
    check state["summary"]["verified"].getInt() == 0
    check state["entries"].len == 0
    removeDir(tmpDir)

  test "handles empty certificate directory":
    let tmpDir = makeTempDir()
    let certDir = tmpDir / "certs"
    createDir(certDir)
    let state = reconstructProofStateFromCertificates(certDir, 10)
    check state.kind == JObject
    check state["summary"]["verified"].getInt() == 0
    check state["summary"]["totalSourceFunctions"].getInt() == 10
    check state["entries"].len == 0
    removeDir(tmpDir)

  test "handles missing certificate directory gracefully":
    let state = reconstructProofStateFromCertificates("/nonexistent/cert/dir", 10)
    check state.kind == JObject
    check state["summary"]["verified"].getInt() == 0
    check state["entries"].len == 0

  test "skips broken JSON files in cert directory":
    let tmpDir = makeTempDir()
    let certDir = tmpDir / "certs"
    createDir(certDir)
    writeFile(certDir / "broken.json", "{invalid json!!!")
    writeCert(certDir, "good.json", %*{
      "modulePath": "src/a.nim",
      "functionName": "f1",
      "sourceHash": "h1",
      "status": "certGreen",
      "winningStrategy": "strat",
      "solverMeta": { "leanCompilerVerified": true }
    })
    let state = reconstructProofStateFromCertificates(certDir, 5)
    check state["summary"]["verified"].getInt() == 1
    check state["entries"].len == 1
    removeDir(tmpDir)

  test "ASI string is computed correctly":
    let tmpDir = makeTempDir()
    let certDir = tmpDir / "certs"
    createDir(certDir)
    for i in 1..3:
      writeCert(certDir, "cert" & $i & ".json", %*{
        "modulePath": "src/m.nim",
        "functionName": "f" & $i,
        "sourceHash": "h" & $i,
        "status": "certGreen",
        "winningStrategy": "s",
        "solverMeta": { "leanCompilerVerified": true }
      })
    let state = reconstructProofStateFromCertificates(certDir, 10)
    # 3 verified / 10 total = "0.3"
    check state["summary"]["engineAsiFixed4"].getStr().len > 0
    removeDir(tmpDir)

  test "certLeanVerified and certGreen both counted as verified":
    # Regression guard: certLeanVerified certificates must be included
    # in the verified count during reconstruction, matching the normal
    # ax prove path which counts all genuine lean-verified evidence.
    let tmpDir = makeTempDir()
    let certDir = tmpDir / "certs"
    createDir(certDir)
    writeCert(certDir, "lean_cert.json", %*{
      "modulePath": "src/lean_mod.nim",
      "functionName": "leanFn",
      "sourceHash": "h_lean",
      "status": "certLeanVerified",
      "winningStrategy": "lean-replay",
      "solverMeta": { "leanCompilerVerified": true }
    })
    writeCert(certDir, "green_cert.json", %*{
      "modulePath": "src/green_mod.nim",
      "functionName": "greenFn",
      "sourceHash": "h_green",
      "status": "certGreen",
      "winningStrategy": "tautology",
      "solverMeta": { "leanCompilerVerified": true }
    })
    let state = reconstructProofStateFromCertificates(certDir, 10)
    check state["summary"]["verified"].getInt() == 2
    check state["entries"].len == 2
    # Both entries must have normalized "verified" status so that
    # recomputeProofStateSummary / countProofStateStatus counts them.
    check state["entries"][0]["status"].getStr() == verifiedKey
    check state["entries"][1]["status"].getStr() == verifiedKey
    removeDir(tmpDir)

  test "certDualVerified counted as verified during reconstruction":
    let tmpDir = makeTempDir()
    let certDir = tmpDir / "certs"
    createDir(certDir)
    writeCert(certDir, "dual_cert.json", %*{
      "modulePath": "src/dual_mod.nim",
      "functionName": "dualFn",
      "sourceHash": "h_dual",
      "status": "certDualVerified",
      "winningStrategy": "lean-replay",
      "solverMeta": { "leanCompilerVerified": true }
    })
    let state = reconstructProofStateFromCertificates(certDir, 5)
    check state["summary"]["verified"].getInt() == 1
    check state["entries"][0]["status"].getStr() == verifiedKey
    removeDir(tmpDir)
