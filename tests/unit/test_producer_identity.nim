## Unit tests for producer_identity.nim — Producer Boundary Contract (Phase 2.7).
## Uses custom main() pattern to avoid unittest framework crashes.
## Verifies: identity digest determinism/sensitivity/order-boundary,
## the DependencyDomain contract adapter, and H(SemanticQuery, ProducerIdentity).

import std/[strutils]
import core/crypto/hash_kernel
import verification/verification_dependency
import verification/semantic_query_types
import verification/producer_identity

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  # Hex test components (64-char sha256-like hex strings; digest uses hexToBytes)
  let hA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let hB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let hC = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  let hD = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

  echo "=== producerIdentityDigest: determinism ==="

  block:
    let pi1 = newProducerIdentity(
      gateSourceClosure = hA, auditorSourceClosure = hB,
      compilerExeDigest = hC, compilerVersion = hA,
      hostIdentity = hB, nimLibClosure = hC, buildConfig = hD)
    let pi2 = newProducerIdentity(
      gateSourceClosure = hA, auditorSourceClosure = hB,
      compilerExeDigest = hC, compilerVersion = hA,
      hostIdentity = hB, nimLibClosure = hC, buildConfig = hD)
    check "same components -> same digest":
      assert producerIdentityDigest(pi1) == producerIdentityDigest(pi2)
    check "digest is 64 hex chars":
      assert producerIdentityDigest(pi1).len == 64

  echo "=== producerIdentityDigest: per-component sensitivity ==="

  block:
    let base = newProducerIdentity(
      gateSourceClosure = hA, auditorSourceClosure = hB,
      compilerExeDigest = hC, compilerVersion = hA,
      hostIdentity = hB, nimLibClosure = hC, buildConfig = hD)
    let baseDigest = producerIdentityDigest(base)
    check "gateSourceClosure mutation -> digest changes":
      assert producerIdentityDigest(newProducerIdentity(
        gateSourceClosure = hB, auditorSourceClosure = hB,
        compilerExeDigest = hC, compilerVersion = hA,
        hostIdentity = hB, nimLibClosure = hC, buildConfig = hD)) != baseDigest
    check "auditorSourceClosure mutation -> digest changes":
      assert producerIdentityDigest(newProducerIdentity(
        gateSourceClosure = hA, auditorSourceClosure = hC,
        compilerExeDigest = hC, compilerVersion = hA,
        hostIdentity = hB, nimLibClosure = hC, buildConfig = hD)) != baseDigest
    check "compilerExeDigest mutation -> digest changes":
      assert producerIdentityDigest(newProducerIdentity(
        gateSourceClosure = hA, auditorSourceClosure = hB,
        compilerExeDigest = hD, compilerVersion = hA,
        hostIdentity = hB, nimLibClosure = hC, buildConfig = hD)) != baseDigest
    check "compilerVersion mutation -> digest changes":
      assert producerIdentityDigest(newProducerIdentity(
        gateSourceClosure = hA, auditorSourceClosure = hB,
        compilerExeDigest = hC, compilerVersion = hC,
        hostIdentity = hB, nimLibClosure = hC, buildConfig = hD)) != baseDigest
    check "hostIdentity mutation -> digest changes":
      assert producerIdentityDigest(newProducerIdentity(
        gateSourceClosure = hA, auditorSourceClosure = hB,
        compilerExeDigest = hC, compilerVersion = hA,
        hostIdentity = hD, nimLibClosure = hC, buildConfig = hD)) != baseDigest
    check "nimLibClosure mutation -> digest changes":
      assert producerIdentityDigest(newProducerIdentity(
        gateSourceClosure = hA, auditorSourceClosure = hB,
        compilerExeDigest = hC, compilerVersion = hA,
        hostIdentity = hB, nimLibClosure = hA, buildConfig = hD)) != baseDigest
    check "buildConfig mutation -> digest changes":
      assert producerIdentityDigest(newProducerIdentity(
        gateSourceClosure = hA, auditorSourceClosure = hB,
        compilerExeDigest = hC, compilerVersion = hA,
        hostIdentity = hB, nimLibClosure = hC, buildConfig = hA)) != baseDigest

  echo "=== producerIdentityDigest: order boundary preservation ==="

  block:
    let ordered = newProducerIdentity(
      gateSourceClosure = hA, auditorSourceClosure = hB,
      compilerExeDigest = hC, compilerVersion = "",
      hostIdentity = "", nimLibClosure = "", buildConfig = "")
    let swapped = newProducerIdentity(
      gateSourceClosure = hB, auditorSourceClosure = hA,
      compilerExeDigest = hC, compilerVersion = "",
      hostIdentity = "", nimLibClosure = "", buildConfig = "")
    check "component order matters (gate<->auditor swap changes digest)":
      assert producerIdentityDigest(ordered) != producerIdentityDigest(swapped)

  echo "=== producerIdentityDigest: pure function of the 7 components only ==="

  block:
    # Structural: the digest has no read-list / observation input — two
    # identities with identical components yield identical digests regardless
    # of any hypothetical difference in the observed syscall read set.
    let piA = newProducerIdentity(
      gateSourceClosure = hA, auditorSourceClosure = hB,
      compilerExeDigest = hC, compilerVersion = hA,
      hostIdentity = hB, nimLibClosure = hC, buildConfig = hD)
    let piB = newProducerIdentity(
      gateSourceClosure = hA, auditorSourceClosure = hB,
      compilerExeDigest = hC, compilerVersion = hA,
      hostIdentity = hB, nimLibClosure = hC, buildConfig = hD)
    check "identity is a pure function of components (read-set irrelevant)":
      assert producerIdentityDigest(piA) == producerIdentityDigest(piB)

  echo "=== dependencyDomain: contract adapter ==="

  block:
    check "producer phase + any rc -> ddProducer":
      assert dependencyDomain(rcOther, "src/foo.nim", ppProducer) == ddProducer
      assert dependencyDomain(rcModuleContent, "src/foo.nim", ppProducer) == ddProducer
      assert dependencyDomain(rcEnvVar, "", ppProducer) == ddProducer

  block:
    check "verification phase semantic classes -> ddSemantic":
      assert dependencyDomain(rcModuleContent, "src/foo.nim", ppVerification) == ddSemantic
      assert dependencyDomain(rcTestGateway, "tests/gateway/x.nim", ppVerification) == ddSemantic
      assert dependencyDomain(rcManualFeature, "tests/features/x.feature", ppVerification) == ddSemantic
      assert dependencyDomain(rcBaseline, "data/verification_auditor_baseline.json", ppVerification) == ddSemantic
      assert dependencyDomain(rcLockFile, "topology.lock", ppVerification) == ddSemantic
      assert dependencyDomain(rcPolicy, "config/gates.json", ppVerification) == ddSemantic

  block:
    check "verification phase provenance/internal/output":
      assert dependencyDomain(rcCommitId, "HEAD", ppVerification) == ddProvenance
      assert dependencyDomain(rcTimestamp, "ts", ppVerification) == ddInternal
      assert dependencyDomain(rcHistory, "h", ppVerification) == ddInternal
      assert dependencyDomain(rcGateOutput, ".axiom/cache/x", ppVerification) == ddOutput

  block:
    check "gate-binary existence -> ddProducer; other existence -> ddUnknown":
      assert dependencyDomain(rcModuleExistence, "bin/verification_auditor", ppVerification) == ddProducer
      assert dependencyDomain(rcModuleExistence, "bin/verification_auditor_gate_ABC", ppVerification) == ddProducer
      assert dependencyDomain(rcModuleExistence, "data/whatever.json", ppVerification) == ddUnknown

  block:
    check "unclassified classes -> ddUnknown (fail-closed)":
      assert dependencyDomain(rcEnvVar, "", ppVerification) == ddUnknown
      assert dependencyDomain(rcCwd, "", ppVerification) == ddUnknown
      assert dependencyDomain(rcCompilerSubprocess, "", ppVerification) == ddUnknown
      assert dependencyDomain(rcOther, "/home/x/.choosenim/nim/bin/nim", ppVerification) == ddUnknown

  echo "=== isSystemRuntimePath / isGateBinaryPath ==="

  block:
    check "system runtime paths -> true":
      assert isSystemRuntimePath("/lib/x86_64-linux-gnu/libc.so.6")
      assert isSystemRuntimePath("/usr/lib/locale/locale-archive")
      assert isSystemRuntimePath("/etc/ld.so.cache")
      assert isSystemRuntimePath("/proc/self/exe")
      assert isSystemRuntimePath("/usr/share/locale/ko/LC_MESSAGES/libc.mo")
    check "non-system paths -> false":
      assert not isSystemRuntimePath("src/foo.nim")
      assert not isSystemRuntimePath("/home/u/.choosenim/toolchains/nim-2.2.10/bin/nim")
    check "nim toolchain lib path -> true (lib/ rule; producer-aligned anyway)":
      assert isSystemRuntimePath("/home/u/.choosenim/toolchains/nim-2.2.10/lib/system.nim")
    check "gate binary path detection":
      assert isGateBinaryPath("/wt/bin/verification_auditor")
      # The gate runner binary is ALSO a verification binary (producer artifact):
      assert isGateBinaryPath("/wt/bin/verification_auditor_gate_HASH")
      assert not isGateBinaryPath("/wt/bin/unrelated_tool")

  echo "=== provisionalVerificationIdentity: H(SemanticQuery, ProducerIdentity) ==="

  block:
    let pi = newProducerIdentity(
      gateSourceClosure = hA, auditorSourceClosure = hB,
      compilerExeDigest = hC, compilerVersion = hA,
      hostIdentity = hB, nimLibClosure = hC, buildConfig = hD)
    let sq1 = SemanticQuery(
      gateId: newGateId("g"),
      snapshot: newSnapshotDigest(hA),
      testClosure: newTestClosureDigest(hB),
      baseline: newBaselineDigest(hC),
      lock: newLockDigest(hD),
      policy: newPolicyDigest(hA),
      gateImpl: newGateImplDigest(hB),
      selectionRuleVersion: "1",
      selectionRuleDigest: hC)
    let sq2 = SemanticQuery(
      gateId: newGateId("g"),
      snapshot: newSnapshotDigest(hB),   # semantic mutation
      testClosure: newTestClosureDigest(hB),
      baseline: newBaselineDigest(hC),
      lock: newLockDigest(hD),
      policy: newPolicyDigest(hA),
      gateImpl: newGateImplDigest(hB),
      selectionRuleVersion: "1",
      selectionRuleDigest: hC)
    check "same SQ + same PI -> same identity":
      assert provisionalVerificationIdentity(sq1, pi) == provisionalVerificationIdentity(sq1, pi)
    check "SQ change -> identity changes":
      assert provisionalVerificationIdentity(sq1, pi) != provisionalVerificationIdentity(sq2, pi)
    let pi2 = newProducerIdentity(
      gateSourceClosure = hB, auditorSourceClosure = hB,
      compilerExeDigest = hC, compilerVersion = hA,
      hostIdentity = hB, nimLibClosure = hC, buildConfig = hD)
    check "PI change -> identity changes":
      assert provisionalVerificationIdentity(sq1, pi) != provisionalVerificationIdentity(sq1, pi2)
    check "identity output is 64 hex chars":
      assert provisionalVerificationIdentity(sq1, pi).len == 64

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0: quit(1)

main()