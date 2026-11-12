import std/json
import core/trusted/legacy_cert_classifier

proc main() =
  echo "=== Legacy Cert Classifier ==="

  # Test 1: schemaVersion "1" + no claimId → legacy=true, demote → "certNotCurrent"
  let cert1 = parseJson("""{"schemaVersion":"1","status":"certZ3Verified"}""")
  doAssert classifyLegacyCert(cert1) == true, "cert1 should be legacy"
  doAssert demoteStatus(cert1) == "certNotCurrent", "cert1 should be demoted to certNotCurrent"

  # Test 2: No schemaVersion + status certZ3Verified → legacy=true
  let cert2 = parseJson("""{"status":"certZ3Verified"}""")
  doAssert classifyLegacyCert(cert2) == true, "cert2 should be legacy (no schemaVersion)"

  # Test 3: schemaVersion "2" + claimId present → legacy=false, demote keeps status
  let cert3 = parseJson("""{"schemaVersion":"2","claimId":"claim-abc","specificationId":"spec-xyz","status":"certZ3Verified"}""")
  doAssert classifyLegacyCert(cert3) == false, "cert3 should NOT be legacy"
  doAssert demoteStatus(cert3) == "certZ3Verified", "cert3 status should be kept"

  # Never promotes: a cert can NEVER be classified as trusted/verified by this function
  doAssert classifyLegacyCert(cert1) == true, "cert1 can never be promoted to trusted"
  doAssert classifyLegacyCert(cert2) == true, "cert2 can never be promoted to trusted"
  doAssert classifyLegacyCert(cert3) == false, "cert3 is non-legacy (V2)"

  echo "=== Legacy Cert Classifier OK ==="

main()