## Effect Isolation Unit Test
## Verifies certStale enum, prelude injection, and I/O isolation behavior.

import std/[os, json, options, strutils]
import core/types/domain_types
import core/json/json_utils
import std/unittest

proc main() =
  echo "[effect_isolation_test] starting"

  # Test 1: certStale status exists in CertificateStatus enum
  let stale = certStale
  check stale == certStale  # was: doAssert stale == certStale, "certStale must be a valid CertificateStatus"
  echo "[effect_isolation_test] certStale enum PASS"

  # Test 2: Prelude file exists
  let preludePath = "src/verification/prelude.lean"
  check fileExists(preludePath)  # was: doAssert fileExists(preludePath), "prelude.lean must exist"
  let preludeContent = readFile(preludePath)
  check "NimInt" in preludeContent  # was: doAssert "NimInt" in preludeContent, "prelude must define NimInt"
  check "external_io_isolated" in preludeContent  # was: doAssert "external_io_isolated" in preludeContent, "prelude must declare external_io_isolated"
  echo "[effect_isolation_test] prelude.lean PASS"

  # Test 3: stale certificate file on disk has correct status
  let staleCertPath = "src/verification/certificates/core_the_judge_nim__buildLeanQuery.json"
  if fileExists(staleCertPath):
    let rootOpt = readJsonFile(staleCertPath)
    if rootOpt.isSome:
      let root = rootOpt.get()
      if root.kind == JObject and root.hasKey("status") and root["status"].kind == JString:
        let status = root["status"].getStr()
        check status == "certStale" or status == "certGreen"  # was: doAssert status == "certStale" or status == "certGreen", "Unexpected status: " & status
        echo "[effect_isolation_test] stale cert disk status PASS (", status, ")"
      else:
        echo "[effect_isolation_test] SKIP: cert missing status field"
    else:
      echo "[effect_isolation_test] SKIP: could not read stale cert"
  else:
    echo "[effect_isolation_test] SKIP: stale cert file not found"

  echo "[effect_isolation_test] all checks passed"

suite "Effect Isolation":
  test "Effect Isolation tests":
    main()
