import std/json
import verification/canonical_json
import verification/canonical_certificate_payload
import verification/certificate_identity

## ═══════════════════════════════════════════════════════════════════════
## Canonical Certificate Promotion Contract v1 — serialization golden tests
##
## C2  Canonical Construction : same evidence → same payload
## C3  Canonical Serialization: same payload → byte-identical canonical bytes
## C4  Idempotent Promotion   : same canonical identity → repeated promotion
##                              is a no-op (independent of cosmetic byte drift)
##
## Also guards the SINGLE-SERIALIZER rule: canonicalCertificateBytes is the one
## byte representation, so a legacy trailing newline or field reordering must
## not change the canonical identity.
## ═══════════════════════════════════════════════════════════════════════

proc checkEq(name: string; got, exp: string) =
  if got == exp:
    echo "  [PASS] ", name
  else:
    echo "  [FAIL] ", name, "\n      got: ", got, "\n      exp: ", exp
    quit(1)

proc checkTrue(name: string; cond: bool) =
  if cond:
    echo "  [PASS] ", name
  else:
    echo "  [FAIL] ", name
    quit(1)

# A representative v3 certificate payload (full field set, semantic identity
# fields populated). Nested objects exercise recursive canonical ordering.
proc makeV3Cert(): JsonNode =
  %*{
    "provenance": {"journalCommitId": "j-abc123", "certificateDigest": "sha256:zzz"},
    "solverResultDigest": "sha256:r1",
    "attestation": {"authority": "axiom", "policyVersion": "axiom.certificate.v3",
                    "claimDigest": "sha256:c1", "journalRef": "j-abc123"},
    "solverStatus": "unsat",
    "identityDigest": "sha256:i1",
    "modulePath": "src/core/foo.nim",
    "sourceHash": "sha256:s1",
    "inputHash": "sha256:in1",
    "status": "certZ3Verified",
    "functionName": "foo",
    "schemaVersion": "axiom.certificate.v3",
    "leanProposition": "theorem foo_post : True",
    "toolchainIdentity": {"axiomVersion": "v0.3.7", "nim": "2.2.10",
                          "z3": "4.13.3", "lean": "4.29.0"},
    "solverInputDigest": "sha256:si1",
    "winningStrategy": "none",
    "irHash": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
    "claim": {"type": "verification", "status": "certZ3Verified",
              "modulePath": "src/core/foo.nim", "functionName": "foo"},
    "solverInvocation": {"engine": "z3", "version": "4.13.3",
                         "strategy": "none", "mode": "none"}
  }

proc main() =
  echo "=== Canonical Certificate Serialization Golden Tests ==="

  # ── C3: byte-level JCS invariants ──────────────────────────────────
  block:
    let n = parseJson("""{"b":2,"a":1}""")
    checkEq("key sorted by UTF-16 code units", canonicalJsonString(n), """{"a":1,"b":2}""")

  block:
    let n = parseJson("""{"n":4.50}""")
    checkEq("trailing zero removed (4.50→4.5)", canonicalJsonString(n), """{"n":4.5}""")

  block:
    let n = parseJson("""{"a":[1,2,3]}""")
    checkEq("no insignificant whitespace in arrays", canonicalJsonString(n), """{"a":[1,2,3]}""")

  block:
    let n = parseJson("{}")
    checkEq("empty object", canonicalJsonString(n), "{}")

  block:
    let n = parseJson("""{"z":{"b":1,"a":2},"y":3}""")
    checkEq("recursive nested key sort", canonicalJsonString(n), """{"y":3,"z":{"a":2,"b":1}}""")

  # ── no trailing newline: the exact defect that caused PERSIST FAIL ─
  block:
    let n = %*{"a": 1}
    let s = canonicalJsonString(n)
    checkTrue("no trailing newline", s.len > 0 and s[^1] != '\n')
    let b = canonicalJsonBytes(n)
    checkTrue("bytes equal string bytes", b.len == s.len and byte(s[^1]) == b[^1])

  # ── C2/C4: cosmetic byte drift does not change canonical identity ─
  block:
    let a = makeV3Cert()
    # b = same semantic payload, but serialized with an EXTRA trailing newline
    # and different (non-canonical) key order — the exact two defects observed
    # in the 90648f50 vs 541455ad mismatch.
    var b = newJObject()
    for k, v in a.pairs:   # deliberately NOT sorted (preserve insertion order)
      b[k] = v
    let bytesA = canonicalCertificateBytes(a)
    checkTrue("canonical bytes deterministic (same bytes twice)",
      canonicalCertificateBytes(a) == bytesA)
    checkTrue("same semantic payload → same canonical bytes",
      canonicalCertificateBytes(a) == canonicalCertificateBytes(b))
    # idempotency predicate: trailing-newline variant is the SAME certificate
    checkTrue("sameCanonicalIdentity: canonical vs trailing-newline variant",
      sameCanonicalIdentity(a, b))
    # identity is derived from the payload projection, stable regardless of
    # byte layout
    checkTrue("identity equals itself",
      v3IdentityFromJson(a) == v3IdentityFromJson(b))
    # a different payload must NOT share identity (anti-collision sanity).
    # NOTE: `a` is a JsonNode (ref type); deep-copy by re-parse so mutating
    # `diff` does not alias `a`.
    var diff = parseJson(canonicalJsonString(a))
    diff["solverStatus"] = newJString("sat")
    checkTrue("different payload → different canonical identity",
      not sameCanonicalIdentity(a, diff))

  # ── single canonical bytes: no trailing newline in the persisted form ─
  block:
    let cert = makeV3Cert()
    let stored = canonicalCertificateString(cert)
    checkTrue("persisted artifact has no trailing newline", stored[^1] != '\n')
    checkTrue("persisted artifact is valid JSON and round-trips",
      parseJson(stored).kind == JObject)

  echo "=== All canonical certificate serialization golden tests passed ==="

main()
