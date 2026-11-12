import core/trusted/semantic_profile
import core/trusted/project_setup

proc main() =
  doAssert profileIdentityFor("v1") == SemanticProfileV1Hash,
    "profileIdentityFor(\"v1\") must equal SemanticProfileV1Hash"
  doAssert profileIdentityFor("v1") != "",
    "profileIdentityFor(\"v1\") must not be empty"
  doAssert profileIdentityFor("nonexistent") == "",
    "profileIdentityFor for unknown profile must return empty string"

  let digest1 = resolvedConfigDigest(profileIdentityFor("v1"), "lockhash1")
  let digest2 = resolvedConfigDigest(profileIdentityFor("v1"), "lockhash1")
  doAssert digest1 == digest2,
    "resolvedConfigDigest must be deterministic for same inputs"

  let digest3 = resolvedConfigDigest("different_profile", "lockhash1")
  doAssert digest3 != digest1,
    "different profileIdentity must produce different digest"

  echo "All project_setup tests passed."

main()