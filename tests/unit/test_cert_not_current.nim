# Phase-4 seed: csbNotCurrent — legacy evidence is NOT a trusted input,
# parseable/serializable, and cannot transition into verified/green.

import core/trusted/layer_declaration
import std/json
import core/types/certificate_types
import core/types/verification_tier

proc main() =
  # 1. parseable + serializable
  doAssert $certNotCurrent == "certNotCurrent"
  doAssert parseCertificateStatus("certNotCurrent") == certNotCurrent
  # 2. not a verified status
  doAssert not statusConsistentWithEvidence(
    %*{"status": "certNotCurrent", "solverMeta": {"leanCompilerVerified": true}})
  # 3. terminal: cannot transition notCurrent -> green; stale allowed
  doAssert isValidTransition(certNotCurrent, certStale)
  doAssert not isValidTransition(certNotCurrent, certGreen)
  echo "=== csbNotCurrent seed OK ==="
