## Certificate Hydration Tests — Content-Addressed Proof Hydration (Phase 1)
##
## Verifies:
##   1. scanCertificateDir discovers valid certs, skips invalid/empty
##   2. Hydratability rules: status, winningStrategy, leanVerified, sourceHash
##   3. Legacy certs (no sourceHash) are never hydratable
##   4. findHydratableCertificate returns some/none correctly
##   5. Transitive-dependency logic is NOT tested here (lives in loop_driver)

import std/[unittest, os, json, tables, options, times, strutils]
import verification/certificate_hydration
import core/proof/source_fingerprint
import core/orchestrator/orchestrator_request_types
import core/sorter/sorter_core

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc makeTempDir(): string =
  let dir = getTempDir() / "axiom_cert_hydration_test_" & $getCurrentProcessId() & "_" & $cast[int](epochTime())
  createDir(dir)
  dir

proc writeCert(dir: string; name: string; data: JsonNode) =
  writeFile(dir / name, pretty(data))

proc makeRequest(sourceCode: string): OrchestrationProofRequest =
  initOrchestrationProofRequest(
    nodeId = sorterNodeId("test::node"),
    sourceCode = sourceCode,
    stateValue = 0,
    inputDelta = 0
  )

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

const
  SrcA = "func add(a, b): return a + b"
  SrcB = "func mul(a, b): return a * b"

let
  fpA = computeStableSourceFingerprint(SrcA)
  fpB = computeStableSourceFingerprint(SrcB)

# ---------------------------------------------------------------------------
# Suite: scanCertificateDir
# ---------------------------------------------------------------------------

suite "scanCertificateDir":

  test "finds valid certificate with all fields":
    let tmpDir = makeTempDir()
    writeCert(tmpDir, "good.json", %*{
      "modulePath": "src/math.nim",
      "functionName": "add",
      "sourceHash": fpA,
      "fingerprint": "fp_abc",
      "status": "certGreen",
      "winningStrategy": "tautology",
      "solverMeta": { "leanCompilerVerified": true }
    })
    let certs = scanCertificateDir(tmpDir)
    check certs.len == 1
    let key = "src/math.nim::add"
    check certs.hasKey(key)
    let cert = certs[key]
    check cert.modulePath == "src/math.nim"
    check cert.functionName == "add"
    check cert.sourceHash == fpA
    check cert.fingerprint == "fp_abc"
    check cert.status == "certGreen"
    check cert.winningStrategy == "tautology"
    check cert.leanCompilerVerified == true
    check cert.certificatePath.endsWith("good.json")
    removeDir(tmpDir)

  test "skips files with invalid JSON":
    let tmpDir = makeTempDir()
    writeFile(tmpDir / "broken.json", "{invalid json!!!")
    writeCert(tmpDir, "ok.json", %*{
      "modulePath": "a.nim",
      "functionName": "f",
      "sourceHash": "h",
      "fingerprint": "fp",
      "status": "certGreen",
      "winningStrategy": "strat",
      "solverMeta": { "leanCompilerVerified": false }
    })
    let certs = scanCertificateDir(tmpDir)
    check certs.len == 1
    check certs.hasKey("a.nim::f")
    removeDir(tmpDir)

  test "skips JSON without modulePath or functionName":
    let tmpDir = makeTempDir()
    writeCert(tmpDir, "no_path.json", %*{
      "status": "certGreen",
      "winningStrategy": "x"
    })
    writeCert(tmpDir, "no_fn.json", %*{
      "modulePath": "m.nim"
    })
    let certs = scanCertificateDir(tmpDir)
    check certs.len == 0
    removeDir(tmpDir)

  test "handles legacy certificate without sourceHash":
    let tmpDir = makeTempDir()
    writeCert(tmpDir, "legacy.json", %*{
      "modulePath": "src/old.nim",
      "functionName": "legacy_fn",
      "fingerprint": "old_fp",
      "status": "certGreen",
      "winningStrategy": "manual",
      "solverMeta": { "leanCompilerVerified": true }
    })
    let certs = scanCertificateDir(tmpDir)
    check certs.len == 1
    let cert = certs["src/old.nim::legacy_fn"]
    check cert.sourceHash.len == 0
    removeDir(tmpDir)

  test "handles missing solverMeta gracefully":
    let tmpDir = makeTempDir()
    writeCert(tmpDir, "no_meta.json", %*{
      "modulePath": "x.nim",
      "functionName": "g",
      "sourceHash": "h",
      "fingerprint": "fp",
      "status": "certGreen",
      "winningStrategy": "s"
    })
    let certs = scanCertificateDir(tmpDir)
    check certs.len == 1
    check certs["x.nim::g"].leanCompilerVerified == false
    removeDir(tmpDir)

  test "pre-sizes table correctly":
    let tmpDir = makeTempDir()
    for i in 1..5:
      writeCert(tmpDir, "cert" & $i & ".json", %*{
        "modulePath": "m" & $i & ".nim",
        "functionName": "f" & $i,
        "sourceHash": "h",
        "fingerprint": "fp",
        "status": "certGreen",
        "winningStrategy": "s",
        "solverMeta": { "leanCompilerVerified": true }
      })
    let certs = scanCertificateDir(tmpDir)
    check certs.len == 5
    removeDir(tmpDir)

  test "empty directory returns empty table":
    let tmpDir = makeTempDir()
    let certs = scanCertificateDir(tmpDir)
    check certs.len == 0
    removeDir(tmpDir)

# ---------------------------------------------------------------------------
# Suite: isCertificateHydratable
# ---------------------------------------------------------------------------

suite "isCertificateHydratable":

  test "hydratable when all conditions met":
    let cert = CertificateHydrationRecord(
      modulePath: "m.nim", functionName: "f",
      sourceHash: fpA, fingerprint: "fp",
      status: "certGreen", winningStrategy: "tautology",
      leanCompilerVerified: true, certificatePath: ""
    )
    let req = makeRequest(SrcA)
    check isCertificateHydratable(cert, req) == true

  test "hydratable with certVerifiedAxiom status":
    let cert = CertificateHydrationRecord(
      modulePath: "m.nim", functionName: "f",
      sourceHash: fpA, fingerprint: "fp",
      status: "certVerifiedAxiom", winningStrategy: "lean-replay",
      leanCompilerVerified: true, certificatePath: ""
    )
    let req = makeRequest(SrcA)
    check isCertificateHydratable(cert, req) == true

  test "not hydratable with certRed status":
    let cert = CertificateHydrationRecord(
      modulePath: "m.nim", functionName: "f",
      sourceHash: fpA, fingerprint: "fp",
      status: "certRed", winningStrategy: "tautology",
      leanCompilerVerified: true, certificatePath: ""
    )
    let req = makeRequest(SrcA)
    check isCertificateHydratable(cert, req) == false

  test "not hydratable with certPending status":
    let cert = CertificateHydrationRecord(
      modulePath: "m.nim", functionName: "f",
      sourceHash: fpA, fingerprint: "fp",
      status: "certPending", winningStrategy: "tautology",
      leanCompilerVerified: true, certificatePath: ""
    )
    let req = makeRequest(SrcA)
    check isCertificateHydratable(cert, req) == false

  test "not hydratable with empty winningStrategy":
    let cert = CertificateHydrationRecord(
      modulePath: "m.nim", functionName: "f",
      sourceHash: fpA, fingerprint: "fp",
      status: "certGreen", winningStrategy: "",
      leanCompilerVerified: true, certificatePath: ""
    )
    let req = makeRequest(SrcA)
    check isCertificateHydratable(cert, req) == false

  test "not hydratable when leanCompilerVerified is false":
    let cert = CertificateHydrationRecord(
      modulePath: "m.nim", functionName: "f",
      sourceHash: fpA, fingerprint: "fp",
      status: "certGreen", winningStrategy: "tautology",
      leanCompilerVerified: false, certificatePath: ""
    )
    let req = makeRequest(SrcA)
    check isCertificateHydratable(cert, req) == false

  test "not hydratable when sourceHash is empty (legacy)":
    let cert = CertificateHydrationRecord(
      modulePath: "m.nim", functionName: "f",
      sourceHash: "", fingerprint: "fp",
      status: "certGreen", winningStrategy: "tautology",
      leanCompilerVerified: true, certificatePath: ""
    )
    let req = makeRequest(SrcA)
    check isCertificateHydratable(cert, req) == false

  test "not hydratable when sourceHash mismatches":
    let cert = CertificateHydrationRecord(
      modulePath: "m.nim", functionName: "f",
      sourceHash: fpA, fingerprint: "fp",
      status: "certGreen", winningStrategy: "tautology",
      leanCompilerVerified: true, certificatePath: ""
    )
    let req = makeRequest(SrcB)  # different source code
    check isCertificateHydratable(cert, req) == false

  test "empty status is not hydratable":
    let cert = CertificateHydrationRecord(
      modulePath: "m.nim", functionName: "f",
      sourceHash: fpA, fingerprint: "fp",
      status: "", winningStrategy: "tautology",
      leanCompilerVerified: true, certificatePath: ""
    )
    let req = makeRequest(SrcA)
    check isCertificateHydratable(cert, req) == false

# ---------------------------------------------------------------------------
# Suite: findHydratableCertificate
# ---------------------------------------------------------------------------

suite "findHydratableCertificate":

  test "returns some when certificate is hydratable":
    let tmpDir = makeTempDir()
    writeCert(tmpDir, "good.json", %*{
      "modulePath": "src/math.nim",
      "functionName": "add",
      "sourceHash": fpA,
      "fingerprint": "fp_abc",
      "status": "certGreen",
      "winningStrategy": "tautology",
      "solverMeta": { "leanCompilerVerified": true }
    })
    let certs = scanCertificateDir(tmpDir)
    let req = makeRequest(SrcA)
    let result = findHydratableCertificate(certs, "src/math.nim::add", req)
    check result.isSome()
    check result.get().status == "certGreen"
    removeDir(tmpDir)

  test "returns none for unknown nodeId":
    let certs = initTable[string, CertificateHydrationRecord]()
    let req = makeRequest(SrcA)
    let result = findHydratableCertificate(certs, "nonexistent::fn", req)
    check result.isNone()

  test "returns none when certificate is not hydratable":
    let tmpDir = makeTempDir()
    writeCert(tmpDir, "legacy.json", %*{
      "modulePath": "src/old.nim",
      "functionName": "legacy_fn",
      "fingerprint": "old_fp",
      "status": "certGreen",
      "winningStrategy": "manual",
      "solverMeta": { "leanCompilerVerified": true }
    })
    let certs = scanCertificateDir(tmpDir)
    let req = makeRequest(SrcA)
    let result = findHydratableCertificate(certs, "src/old.nim::legacy_fn", req)
    check result.isNone()  # no sourceHash => not hydratable
    removeDir(tmpDir)

  test "returns none when source code changed since cert was written":
    let tmpDir = makeTempDir()
    writeCert(tmpDir, "cert.json", %*{
      "modulePath": "src/math.nim",
      "functionName": "add",
      "sourceHash": fpA,
      "fingerprint": "fp_abc",
      "status": "certGreen",
      "winningStrategy": "tautology",
      "solverMeta": { "leanCompilerVerified": true }
    })
    let certs = scanCertificateDir(tmpDir)
    let req = makeRequest(SrcB)  # different source
    let result = findHydratableCertificate(certs, "src/math.nim::add", req)
    check result.isNone()
    removeDir(tmpDir)

  test "returns none when lean not verified":
    let tmpDir = makeTempDir()
    writeCert(tmpDir, "unverified.json", %*{
      "modulePath": "src/math.nim",
      "functionName": "add",
      "sourceHash": fpA,
      "fingerprint": "fp_abc",
      "status": "certGreen",
      "winningStrategy": "tautology",
      "solverMeta": { "leanCompilerVerified": false }
    })
    let certs = scanCertificateDir(tmpDir)
    let req = makeRequest(SrcA)
    let result = findHydratableCertificate(certs, "src/math.nim::add", req)
    check result.isNone()
    removeDir(tmpDir)
