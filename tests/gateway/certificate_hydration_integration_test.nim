## Certificate Hydration Integration Tests — Phase 2
##
## Verifies the full topological hydration flow:
##   1. All 3 nodes (A→B→C) hydrate when certificates are valid
##   2. Dependency gate: if B's sourceHash is stale, A does NOT hydrate
##   3. Leaf node C hydrates regardless of B's staleness (no deps)
##   4. Empty cert directory produces zero hydrations

import std/[unittest, os, json, tables, options, times, strutils]
import verification/certificate_hydration
import core/proof/source_fingerprint
import core/sorter/sorter_core
import core/orchestrator/orchestrator_request_types

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc makeTempDir(): string =
  let dir = getTempDir() / "axiom_cert_hydration_integration_" &
            $getCurrentProcessId() & "_" & $cast[int](epochTime())
  createDir(dir)
  dir

proc writeCert(dir: string; name: string; data: JsonNode) =
  writeFile(dir / name, pretty(data))

proc makeNodeRequest(nodeId: SorterNodeId; sourceCode: string): OrchestrationProofRequest =
  initOrchestrationProofRequest(
    nodeId = nodeId,
    sourceCode = sourceCode,
    stateValue = 0,
    inputDelta = 0
  )

# ---------------------------------------------------------------------------
# Fixtures — 3-node dependency chain: A -> B -> C
# (C is leaf, B depends on C, A depends on B)
# ---------------------------------------------------------------------------

const
  SrcA = "func compute(x): return x + 1"
  SrcB = "func transform(y): return y * 2"
  SrcC = "func init(): return 0"

let
  fpA = computeStableSourceFingerprint(SrcA)
  fpB = computeStableSourceFingerprint(SrcB)
  fpC = computeStableSourceFingerprint(SrcC)

# Node IDs
let
  nodeIdA = sorterNodeId("src/compute.nim::compute")
  nodeIdB = sorterNodeId("src/transform.nim::transform")
  nodeIdC = sorterNodeId("src/init.nim::init")

# ---------------------------------------------------------------------------
# Suite: Full 3-node hydration
# ---------------------------------------------------------------------------

suite "topological hydration — all nodes hydrate":

  test "all three nodes hydrate when certificates are valid":
    let tmpDir = makeTempDir()

    # Write valid certificates for all three nodes
    writeCert(tmpDir, "cert_a.json", %*{
      "modulePath": "src/compute.nim",
      "functionName": "compute",
      "sourceHash": fpA,
      "fingerprint": "fp_a",
      "status": "certGreen",
      "winningStrategy": "tautology",
      "solverMeta": { "leanCompilerVerified": true }
    })
    writeCert(tmpDir, "cert_b.json", %*{
      "modulePath": "src/transform.nim",
      "functionName": "transform",
      "sourceHash": fpB,
      "fingerprint": "fp_b",
      "status": "certVerifiedAxiom",
      "winningStrategy": "lean-replay",
      "solverMeta": { "leanCompilerVerified": true }
    })
    writeCert(tmpDir, "cert_c.json", %*{
      "modulePath": "src/init.nim",
      "functionName": "init",
      "sourceHash": fpC,
      "fingerprint": "fp_c",
      "status": "certGreen",
      "winningStrategy": "manual",
      "solverMeta": { "leanCompilerVerified": true }
    })

    let certs = scanCertificateDir(tmpDir)
    check certs.len == 3

    # Build requests
    let reqA = makeNodeRequest(nodeIdA, SrcA)
    let reqB = makeNodeRequest(nodeIdB, SrcB)
    let reqC = makeNodeRequest(nodeIdC, SrcC)

    # Simulate topological hydration pass (C -> B -> A)
    var verifiedNodes = initTable[string, bool]()
    var hydratedCount = 0

    # Depth 0: C (leaf, no deps)
    check allDependenciesInVerifiedSet(@[], verifiedNodes) == true
    let certC = findHydratableCertificate(certs, sorterNodeIdString(nodeIdC), reqC)
    check certC.isSome()
    check certC.get().winningStrategy == "manual"
    verifiedNodes[sorterNodeIdString(nodeIdC)] = true
    inc hydratedCount

    # Depth 1: B (depends on C)
    let nodeBDeps = @[nodeIdC]
    check allDependenciesInVerifiedSet(nodeBDeps, verifiedNodes) == true
    let certB = findHydratableCertificate(certs, sorterNodeIdString(nodeIdB), reqB)
    check certB.isSome()
    check certB.get().status == "certVerifiedAxiom"
    verifiedNodes[sorterNodeIdString(nodeIdB)] = true
    inc hydratedCount

    # Depth 2: A (depends on B)
    let nodeADeps = @[nodeIdB]
    check allDependenciesInVerifiedSet(nodeADeps, verifiedNodes) == true
    let certA = findHydratableCertificate(certs, sorterNodeIdString(nodeIdA), reqA)
    check certA.isSome()
    check certA.get().winningStrategy == "tautology"
    verifiedNodes[sorterNodeIdString(nodeIdA)] = true
    inc hydratedCount

    check hydratedCount == 3
    check verifiedNodes.len == 3

    removeDir(tmpDir)

# ---------------------------------------------------------------------------
# Suite: Dependency gate — stale B blocks A
# ---------------------------------------------------------------------------

suite "topological hydration — dependency gate":

  test "stale B blocks A from hydrating":
    let tmpDir = makeTempDir()

    # Write certificate for C (valid) and B (valid), but A's cert has stale sourceHash
    writeCert(tmpDir, "cert_c.json", %*{
      "modulePath": "src/init.nim",
      "functionName": "init",
      "sourceHash": fpC,
      "fingerprint": "fp_c",
      "status": "certGreen",
      "winningStrategy": "manual",
      "solverMeta": { "leanCompilerVerified": true }
    })
    writeCert(tmpDir, "cert_b.json", %*{
      "modulePath": "src/transform.nim",
      "functionName": "transform",
      "sourceHash": fpB,
      "fingerprint": "fp_b",
      "status": "certGreen",
      "winningStrategy": "lean-replay",
      "solverMeta": { "leanCompilerVerified": true }
    })
    writeCert(tmpDir, "cert_a.json", %*{
      "modulePath": "src/compute.nim",
      "functionName": "compute",
      "sourceHash": fpA,
      "fingerprint": "fp_a",
      "status": "certGreen",
      "winningStrategy": "tautology",
      "solverMeta": { "leanCompilerVerified": true }
    })

    let certs = scanCertificateDir(tmpDir)
    check certs.len == 3

    let reqA = makeNodeRequest(nodeIdA, SrcA)
    let reqB = makeNodeRequest(nodeIdB, SrcB)
    let reqC = makeNodeRequest(nodeIdC, SrcC)

    # Simulate topological hydration pass
    var verifiedNodes = initTable[string, bool]()
    var hydratedCount = 0

    # Depth 0: C hydrates
    let certC = findHydratableCertificate(certs, sorterNodeIdString(nodeIdC), reqC)
    check certC.isSome()
    verifiedNodes[sorterNodeIdString(nodeIdC)] = true
    inc hydratedCount

    # Depth 1: B — sourceHash mismatch (simulate stale cert)
    # Create a request with different source to trigger mismatch
    let staleReqB = makeNodeRequest(nodeIdB, "func transform(y): return y * 3")  # changed source
    let certBStale = findHydratableCertificate(certs, sorterNodeIdString(nodeIdB), staleReqB)
    check certBStale.isNone()  # sourceHash mismatch → not hydratable
    # B is NOT added to verified set

    # Depth 2: A — dependency gate blocks because B is not verified
    let nodeADeps = @[nodeIdB]
    check allDependenciesInVerifiedSet(nodeADeps, verifiedNodes) == false  # B not in set
    # A cannot hydrate even though its certificate is valid

    check hydratedCount == 1  # only C hydrated

    removeDir(tmpDir)

  test "leaf node C hydrates regardless of B staleness":
    let tmpDir = makeTempDir()

    # Write certificate only for C
    writeCert(tmpDir, "cert_c.json", %*{
      "modulePath": "src/init.nim",
      "functionName": "init",
      "sourceHash": fpC,
      "fingerprint": "fp_c",
      "status": "certGreen",
      "winningStrategy": "manual",
      "solverMeta": { "leanCompilerVerified": true }
    })

    let certs = scanCertificateDir(tmpDir)
    let reqC = makeNodeRequest(nodeIdC, SrcC)

    # C has no dependencies, so it hydrates regardless
    var verifiedNodes = initTable[string, bool]()
    check allDependenciesInVerifiedSet(@[], verifiedNodes) == true
    let certC = findHydratableCertificate(certs, sorterNodeIdString(nodeIdC), reqC)
    check certC.isSome()
    verifiedNodes[sorterNodeIdString(nodeIdC)] = true

    # Now B depends on C, and C is verified — B can hydrate if cert exists
    # But we didn't write a cert for B, so B won't hydrate
    let reqB = makeNodeRequest(nodeIdB, SrcB)
    let nodeBDeps = @[nodeIdC]
    check allDependenciesInVerifiedSet(nodeBDeps, verifiedNodes) == true  # deps OK
    let certB = findHydratableCertificate(certs, sorterNodeIdString(nodeIdB), reqB)
    check certB.isNone()  # no cert for B

    removeDir(tmpDir)

# ---------------------------------------------------------------------------
# Suite: Edge cases
# ---------------------------------------------------------------------------

suite "topological hydration — edge cases":

  test "empty cert directory produces zero hydrations":
    let tmpDir = makeTempDir()
    let certs = scanCertificateDir(tmpDir)
    check certs.len == 0

    let reqA = makeNodeRequest(nodeIdA, SrcA)
    let certA = findHydratableCertificate(certs, sorterNodeIdString(nodeIdA), reqA)
    check certA.isNone()
    removeDir(tmpDir)

  test "allDependenciesInVerifiedSet passes for empty deps":
    var verifiedNodes = initTable[string, bool]()
    check allDependenciesInVerifiedSet(@[], verifiedNodes) == true

  test "allDependenciesInVerifiedSet fails when dep missing":
    var verifiedNodes = initTable[string, bool]()
    verifiedNodes["src/a.nim::f"] = true
    let deps = @[sorterNodeId("src/b.nim::g")]
    check allDependenciesInVerifiedSet(deps, verifiedNodes) == false

  test "allDependenciesInVerifiedSet passes when all deps present":
    var verifiedNodes = initTable[string, bool]()
    verifiedNodes["src/a.nim::f"] = true
    verifiedNodes["src/b.nim::g"] = true
    let deps = @[sorterNodeId("src/a.nim::f"), sorterNodeId("src/b.nim::g")]
    check allDependenciesInVerifiedSet(deps, verifiedNodes) == true

  test "certificate with certRed status is not hydratable even with valid deps":
    let tmpDir = makeTempDir()
    writeCert(tmpDir, "red.json", %*{
      "modulePath": "src/bad.nim",
      "functionName": "fail",
      "sourceHash": fpA,
      "fingerprint": "fp",
      "status": "certRed",
      "winningStrategy": "attempted",
      "solverMeta": { "leanCompilerVerified": true }
    })
    let certs = scanCertificateDir(tmpDir)
    let req = makeNodeRequest(sorterNodeId("src/bad.nim::fail"), SrcA)
    let cert = findHydratableCertificate(certs, "src/bad.nim::fail", req)
    check cert.isNone()
    removeDir(tmpDir)
