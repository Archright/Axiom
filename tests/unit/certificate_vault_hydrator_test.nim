import std/[os, json]
import verification/proof_state_builder
import std/unittest

proc testHydrateFromCertificateVault() =
  let certDir = "logs/hydrator_test_certs"
  createDir(certDir)
  writeFile(certDir / "sample.json", """{"status":"certGreen","modulePath":"sample.nim","functionName":"sampleProc","fingerprint":"abc123"}""")
  let hydrated = hydrateProofStateFromCertificateVault(certDir)
  check hydrated.state.kind == JObject
  let summary = hydrated.state{"summary"}
  check not summary.isNil
  let entries = hydrated.state{"entries"}
  check entries.kind == JArray
  check entries.len == 1
  removeDir(certDir)

suite "Certificate Vault Hydrator":
  test "Certificate Vault Hydrator tests":
    testHydrateFromCertificateVault()
