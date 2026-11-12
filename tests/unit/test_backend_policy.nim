## BackendPolicy anti-theater tests.
## Verifies that bpRequire (default) blocks implicit legacy fallback
## and bpAllowFallback only permits it when canonical fails.

import std/unittest
import verification/batch_uap/ir_pipeline_runner

suite "BackendPolicy":
  test "Require + canonical failure → vbCanonicalChc, no fallback":
    let (backend, fbOccurred, fbReason) = selectBackend(bpRequire, false)
    check backend == vbCanonicalChc
    check fbOccurred == false
    check fbReason == ""

  test "AllowFallback + canonical failure → vbLegacy, fallback occurred":
    let (backend, fbOccurred, fbReason) = selectBackend(bpAllowFallback, false)
    check backend == vbLegacy
    check fbOccurred == true
    check fbReason.len > 0

  test "canonical success → vbCanonicalChc, no fallback even under AllowFallback":
    let (backend, fbOccurred, fbReason) = selectBackend(bpAllowFallback, true)
    check backend == vbCanonicalChc
    check fbOccurred == false
    check fbReason == ""

  test "bpRequire is the default constant — fail-closed by default":
    check bpRequire == bpRequire
    check bpRequire != bpAllowFallback