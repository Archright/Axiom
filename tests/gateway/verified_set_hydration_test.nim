## VerifiedSet Hydration Tests — Build a VerifiedSet from certificate JSON files.
##
## Verifies:
##   1. Valid certGreen certificates with matching sourceHash are accepted.
##   2. Certificates with a mismatched sourceHash are rejected.
##   3. Legacy v1 certificates without sourceHash are accepted via migration bridge.
##   4. loadVerifiedAxiomsFromProofVault extracts smtlib2 formulas.

import std/[unittest, os, json, options, tables]
import core/sorter/sorter_core
import core/topology/topology_engine
import core/topology/topology_types
import core/topology/symbol_interning
import core/topology/verified_set
import core/proof/proof_integrity
import core/proof/source_fingerprint
import core/utils/io_utils
import core/axiom_pragmas
import verification/verified_set_hydration

func makeHydrationSymbol(
  modulePath, functionName: string
): TopologySymbol =
  TopologySymbol(
    modulePath: modulePath,
    functionName: functionName,
    nodeType: "func",
    nodeId: sorterNodeId(modulePath & "::" & functionName),
    declarationLine: 1,
    bodyStartLine: 1,
    bodyEndLine: 2,
    exported: false,
    boundaryKind: topologyBoundaryNone,
    rawCallTargets: @[],
    branchCount: 0,
    nestingDepth: 0,
    lineSpan: 2
  )

proc writeCert(path: string; node: JsonNode) =
  var f: File
  if open(f, path, fmWrite):
    f.write($node)
    f.close()

proc makeContentResolver(content: string): ModuleContentResolver =
  result = proc(modulePath: string): Option[string] {.raises: [], noSideEffect.} =
    some(content)

suite "VerifiedSetHydration":

  let moduleContent = "proc ok*() = discard\nproc stale*() = discard\nproc legacy*() = discard\n"
  let contentHash = computeStableSourceFingerprint(moduleContent)
  let analysis = buildTopologyAnalysis(@[
    makeHydrationSymbol("src/mod.nim", "ok"),
    makeHydrationSymbol("src/mod.nim", "stale"),
    makeHydrationSymbol("src/mod.nim", "legacy")
  ])

  func buildSnapshot(analysis: TopologyAnalysis): InternPoolSnapshot =
    var pool = initInternPool(analysis.state.nodes.len)
    for node in analysis.state.nodes:
      discard nodeIdForSorter(pool, node.id)
    freezeInternPool(pool)

  let snapshot = buildSnapshot(analysis)

  # SSOT kernel scope: all three test symbols are in kernel scope, so the
  # Set-Membership filter in hydrateVerifiedSetFromProofVault accepts them.
  let testScope = KernelScopeInfo(
    kernelSymbols: @["src/mod.nim::ok", "src/mod.nim::stale", "src/mod.nim::legacy"],
    kernelTotal: 3
  )

  test "hydration accepts matching certGreen certificate":
    let tmpDir = getTempDir() / ("axiom_hydration_" & $getCurrentProcessId())
    discard existsOrCreateDirOpt(tmpDir)
    let cert = %*{
      "modulePath": "src/mod.nim",
      "functionName": "ok",
      "status": "certGreen",
      "kernel": true,
      "sourceHash": contentHash,
      "solverMeta": {"leanCompilerVerified": true},
      "solverStatus": "unsat",
      "verificationTier": "lean-verified",
      "vcHash": "dummy-vc-hash"
    }
    writeCert(tmpDir / "ok.json", cert)
    let resolver = makeContentResolver(moduleContent)
    let verified = hydrateVerifiedSetFromProofVault(tmpDir, snapshot, analysis, resolver, testScope)
    let nodeId = nodeIdForSorter(snapshot, sorterNodeId("src/mod.nim::ok"))
    check nodeId.isSome and verified.contains(nodeId.get())
    removeDir(tmpDir)

  test "hydration rejects v2+ cert with mismatched sourceHash (I-D fail-closed)":
    let tmpDir = getTempDir() / ("axiom_hydration_v2stale_" & $getCurrentProcessId())
    discard existsOrCreateDirOpt(tmpDir)
    let cert = %*{
      "modulePath": "src/mod.nim",
      "functionName": "ok",
      "status": "certGreen",
      "kernel": true,
      "sourceHash": "wrong-for-current-source",
      "vcHash": "some-vc-hash",
      "solverMeta": {"leanCompilerVerified": true},
      "solverStatus": "unsat"
    }
    writeCert(tmpDir / "ok.json", cert)
    let resolver = makeContentResolver(moduleContent)
    let verified = hydrateVerifiedSetFromProofVault(tmpDir, snapshot, analysis, resolver, testScope)
    let nodeId = nodeIdForSorter(snapshot, sorterNodeId("src/mod.nim::ok"))
    check nodeId.isNone or not verified.contains(nodeId.get())
    removeDir(tmpDir)

  test "hydration rejects stale sourceHash":
    let tmpDir = getTempDir() / ("axiom_hydration_stale_" & $getCurrentProcessId())
    discard existsOrCreateDirOpt(tmpDir)
    let cert = %*{
      "modulePath": "src/mod.nim",
      "functionName": "stale",
      "status": "certGreen",
      "kernel": true,
      "sourceHash": "wrong-hash",
      "solverMeta": {"leanCompilerVerified": true}
    }
    writeCert(tmpDir / "stale.json", cert)
    let resolver = makeContentResolver(moduleContent)
    let verified = hydrateVerifiedSetFromProofVault(tmpDir, snapshot, analysis, resolver, testScope)
    let nodeId = nodeIdForSorter(snapshot, sorterNodeId("src/mod.nim::stale"))
    check nodeId.isNone or not verified.contains(nodeId.get())
    removeDir(tmpDir)

  test "hydration removes legacy v1 certificate from the verified set":
    let tmpDir = getTempDir() / ("axiom_hydration_legacy_" & $getCurrentProcessId())
    discard existsOrCreateDirOpt(tmpDir)
    let cert = %*{
      "modulePath": "src/mod.nim",
      "functionName": "legacy",
      "status": "certVerifiedAxiom",
      "kernel": true,
      "schemaVersion": "axiom.proof.v1",
      "solverMeta": {"leanCompiler": true},
      "verificationTier": "lean-verified"
    }
    writeCert(tmpDir / "legacy.json", cert)
    let resolver = makeContentResolver(moduleContent)
    let verified = hydrateVerifiedSetFromProofVault(tmpDir, snapshot, analysis, resolver, testScope)
    let nodeId = nodeIdForSorter(snapshot, sorterNodeId("src/mod.nim::legacy"))
    check nodeId.isNone or not verified.contains(nodeId.get())
    removeDir(tmpDir)

  test "loadVerifiedAxioms extracts smtlib2 formulas":
    let tmpDir = getTempDir() / ("axiom_hydration_axioms_" & $getCurrentProcessId())
    discard existsOrCreateDirOpt(tmpDir)
    let cert = %*{
      "modulePath": "src/mod.nim",
      "functionName": "ok",
      "status": "certGreen",
      "kernel": true,
      "sourceHash": contentHash,
      "smtlib2": "(assert true)",
      "solverStatus": "unsat",
      "solverMeta": {"leanCompilerVerified": true}
    }
    writeCert(tmpDir / "ok.json", cert)
    let resolver = makeContentResolver(moduleContent)
    let axioms = loadVerifiedAxiomsFromProofVault(tmpDir, resolver, TopologyAnalysis())
    check axioms.hasKey("src/mod.nim::ok")
    removeDir(tmpDir)
