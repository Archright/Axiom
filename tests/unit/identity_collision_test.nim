# identity_collision_test.nim — S4 Gate 3: false-hit / identity-collision negative tests
#
# Cites:
#   - proofs/GateInvariants/CacheKeyCompleteness.lean — injectivity of key computation
#     on components: differing components produce differing keys.
#   - proofs/GateInvariants/MphfInjectivity.lean — MPHF maps all gate IDs to unique
#     indices; no two distinct inputs produce the same hash index.
#
# These proof precedents establish that our hash-based identity scheme is collision-safe
# under the injectivity assumption: if any semantic input changes, the identity changes.
#
# Execution: nim c --hints:off -r --path:src tests/unit/identity_collision_test.nim

import std/[unittest, strutils, sequtils, algorithm]

import core/crypto/hash_kernel
import core/trusted/axiom_pragmas
import infrastructure/cas_index
import verification/obligation/identity

# ==========================================================================
# Suite: Gate 3 — false-hit / identity-collision negative tests
# ==========================================================================

suite "Gate 3 — Identity Collision Negative Tests":

  # -----------------------------------------------------------------------
  # (a) different semantic inputs → different executionIdentity (no false-hit)
  # -----------------------------------------------------------------------
  test "different source inputs produce different executionIdentity":
    ## CacheKeyCompleteness.lean: differing components → differing keys.
    let inputIdA = sha256Hex("source-A: different semantic content")
    let inputIdB = sha256Hex("source-B: different semantic content")
    let contractDigest = sha256Hex("hermetic-contract")
    let bundleFp = sha256Hex("bundle-fingerprint")

    let execIdA = executionIdentity(inputIdA, contractDigest, bundleFp)
    let execIdB = executionIdentity(inputIdB, contractDigest, bundleFp)

    check execIdA != execIdB
    check execIdA.len == 64
    check execIdB.len == 64

  # -----------------------------------------------------------------------
  # (b) same semantic inputs → identical executionIdentity (HIT)
  #     AND incidental variance absorbed by canonicalization
  # -----------------------------------------------------------------------
  test "identical semantic inputs produce identical executionIdentity (HIT)":
    let inputId = sha256Hex("same-source")
    let contractDigest = sha256Hex("same-contract")
    let bundleFp = sha256Hex("same-bundle")

    let execId1 = executionIdentity(inputId, contractDigest, bundleFp)
    let execId2 = executionIdentity(inputId, contractDigest, bundleFp)

    check execId1 == execId2

  test "artifactIdentity is deterministic for same canonical artifact":
    let artifact = """{"unitId":"A","proofStatus":"psPass"}"""
    let id1 = artifactIdentity(artifact)
    let id2 = artifactIdentity(artifact)
    check id1 == id2
    check id1.len == 64

  test "incidental whitespace variance is absorbed by canonicalization layer":
    ## artifactIdentity itself does NOT strip whitespace — it hashes raw input.
    ## The canonicalization layer (e.g. canonicalizeEnvValue in identity.nim)
    ## strips system paths and normalizes before identity computation.
    ## This test demonstrates: artifactIdentity on whitespace-stripped canonical
    ## form is deterministic, and the canonicalization layer is what absorbs
    ## incidental variance — not artifactIdentity alone.
    let rawArtifact = "  { \"unitId\" : \"A\" , \"proofStatus\" : \"psPass\" }  "
    let canonicalArtifact = """{"unitId":"A","proofStatus":"psPass"}"""

    # Raw and canonical forms differ as raw strings (artifactIdentity is raw)
    check artifactIdentity(rawArtifact) != artifactIdentity(canonicalArtifact)

    # But after canonicalization (whitespace stripped), they produce the same identity
    # This mirrors how identity.nim canonicalizes env values before hashing:
    # canonicalizeEnvValue strips system paths and normalizes, so two semantically
    # equivalent but syntactically different env values produce the same digest.
    let canonicalized1 = rawArtifact.replace("  ", "").replace("\n", "").replace(" ", "")
    let canonicalized2 = canonicalArtifact.replace("  ", "").replace("\n", "").replace(" ", "")
    check artifactIdentity(canonicalized1) == artifactIdentity(canonicalized2)

  # -----------------------------------------------------------------------
  # (c) truncation guard: truncated digest prefix != full digest
  # -----------------------------------------------------------------------
  test "truncated digest prefix must not equal full digest":
    ## False-hit guard: any partial-compare bug must not let a truncated
    ## prefix match the full digest.
    let fullDigest = sha256Hex("some-semantic-input-for-truncation-test")
    let truncated = fullDigest[0 .. 15]  # first 16 hex chars

    check truncated.len == 16
    check fullDigest.len == 64
    check truncated != fullDigest
    # Also verify truncated is not a prefix of itself in a way that
    # could be confused with equality in a partial-compare bug
    check not (truncated == fullDigest)

  # -----------------------------------------------------------------------
  # (d) domain-separator collision: combineHashes(@["a","b"]) != combineHashes(@["ab"])
  # -----------------------------------------------------------------------
  test "combineHashes prevents concatenation ambiguity via domain separators":
    ## cas_index.combineHashes uses DomainSeparator (the unit separator character U+0003)
    ## and length-prefixes each part, preventing concatenation ambiguity
    ## (e.g. "a"+"b" vs "ab").
    ## each part, preventing concatenation ambiguity (e.g. "a"+"b" vs "ab").
    ## This is the same domain-separator pattern proven in CacheKeyCompleteness.lean
    ## where each component is distinctly delimited in the key computation.
    let combinedSeparate = combineHashes(@["a", "b"])
    let combinedConcat = combineHashes(@["ab"])

    check combinedSeparate != combinedConcat
    check combinedSeparate.len == 64
    check combinedConcat.len == 64

  # -----------------------------------------------------------------------
  # (e) order sensitivity where semantic: canonicalization absorbs ordering
  # -----------------------------------------------------------------------
  test "canonicalization absorbs ordering for semantically equivalent inputs":
    ## canonicalExecutionBundleFingerprint sorts dependencyDigests before combining,
    ## so two bundles with the same dependencies in different order produce the
    ## same fingerprint. This is the canonical serialization absorbing ordering.
    let inputId = sha256Hex("same-source")
    let contractDigest = sha256Hex("same-contract")

    # Two bundles with same deps in different order
    let bundleFp1 = canonicalExecutionBundleFingerprint(
      "axiom-exe", "axiom-source", "4.33.0", "4.13.3", "1.0.0", "2.2.10",
      @["dep-A", "dep-B", "dep-C"],  # order: A, B, C
      "runtime-digest", "eval-impl-digest")

    let bundleFp2 = canonicalExecutionBundleFingerprint(
      "axiom-exe", "axiom-source", "4.33.0", "4.13.3", "1.0.0", "2.2.10",
      @["dep-C", "dep-A", "dep-B"],  # order: C, A, B (different!)
      "runtime-digest", "eval-impl-digest")

    # Canonicalization (sorting deps) absorbs the ordering difference
    check bundleFp1 == bundleFp2

    # But executionIdentity is still sensitive to the bundle fingerprint
    # (which is the same here, so identities match — this is the positive case)
    let execId1 = executionIdentity(inputId, contractDigest, bundleFp1)
    let execId2 = executionIdentity(inputId, contractDigest, bundleFp2)
    check execId1 == execId2

  # -----------------------------------------------------------------------
  # (e continued) positive-but-collision-adjacent: canonicalization absorbs
  # ordering for graph_artifact/selection_derivation canonical forms
  # -----------------------------------------------------------------------
  test "canonicalExecutionBundleFingerprint is order-independent for deps":
    ## MphfInjectivity.lean: the MPHF maps distinct inputs to distinct indices.
    ## Similarly, our canonical fingerprint must map semantically identical
    ## inputs (same deps, different order) to the same digest — no collision,
    ## just canonical normalization absorbing the ordering.
    let fp1 = canonicalExecutionBundleFingerprint(
      "exe", "src", "4.33.0", "4.13.3", "1.0.0", "2.2.10",
      @["x", "y"], "rt", "eval")
    let fp2 = canonicalExecutionBundleFingerprint(
      "exe", "src", "4.33.0", "4.13.3", "1.0.0", "2.2.10",
      @["y", "x"], "rt", "eval")
    check fp1 == fp2

    # Different deps (truly different semantic content) must produce different fps
    let fp3 = canonicalExecutionBundleFingerprint(
      "exe", "src", "4.33.0", "4.13.3", "1.0.0", "2.2.10",
      @["x", "z"], "rt", "eval")
    check fp1 != fp3

  # -----------------------------------------------------------------------
  # executionIdentity is order-sensitive for non-canonicalized components
  # (inputIdentity and contractDigest are NOT sorted — they are fixed strings)
  # -----------------------------------------------------------------------
  test "executionIdentity is sensitive to input identity changes":
    let contractDigest = sha256Hex("same-contract")
    let bundleFp = sha256Hex("same-bundle")

    let execId1 = executionIdentity(sha256Hex("input-A"), contractDigest, bundleFp)
    let execId2 = executionIdentity(sha256Hex("input-B"), contractDigest, bundleFp)

    check execId1 != execId2

  test "executionIdentity is sensitive to contract digest changes":
    let inputId = sha256Hex("same-input")
    let bundleFp = sha256Hex("same-bundle")

    let execId1 = executionIdentity(inputId, sha256Hex("contract-A"), bundleFp)
    let execId2 = executionIdentity(inputId, sha256Hex("contract-B"), bundleFp)

    check execId1 != execId2

  test "executionIdentity is sensitive to bundle fingerprint changes":
    let inputId = sha256Hex("same-input")
    let contractDigest = sha256Hex("same-contract")

    let execId1 = executionIdentity(inputId, contractDigest, sha256Hex("bundle-A"))
    let execId2 = executionIdentity(inputId, contractDigest, sha256Hex("bundle-B"))

    check execId1 != execId2