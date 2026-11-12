import ../../src/core/results
import std/[os, tables, json]
import ../../src/core/symbolic/global_symbol_graph_types
import ../../src/core/types/universe_types
import ../../src/core/utils/constants
import ../../src/verification/proof_universe_lock
import ../../src/core/proof/proof_universe_lock
import ../../src/core/metrics
import ../../src/verification/proof_universe_commit
import std/unittest

# Unit tests for proof_universe_lock deterministic Merkle root

proc sampleGlobalSymbolGraph(): GlobalSymbolGraph =
  result = GlobalSymbolGraph(
    symbols: initTable[string, SymbolNode](),
    edges: @[],
    byTarget: initTable[string, seq[ReferenceEdge]]()
  )
  result.symbols["sample.sampleProc"] = SymbolNode(
    qualifiedName: "sample.sampleProc",
    kind: skProc,
    modulePath: "sample.nim",
    astNode: nil,
    visibility: "public"
  )
  result.edges.add(ReferenceEdge(
    source: "sample.sampleProc",
    target: "sample.dependency",
    kind: rkCall,
    line: 1,
    column: 1
  ))
  result.byTarget["sample.dependency"] = result.edges

proc prepareProofLockFixture(name: string; asiFixed4: string = "0.9876"): string =
  result = "logs" / name
  if dirExists(result):
    removeDir(result)
  createDir(result)
  createDir(result / "certs")
  createDir(result / "logs")
  createDir(result / "data")
  writeFile(result / "data" / "seed_symbol_graph.json", """{"schemaVersion":"axiom.global-symbol-graph.v1","symbolCount":0,"edgeCount":0,"symbols":[],"edges":[]}""")
  writeFile(result / "certs" / "sample.json", """{"status":"verified"}""")
  writeFile(result / "state.json", "{\"summary\":{\"engineAsiFixed4\":\"" & asiFixed4 & "\"}}")

proc testComputeAndVerifyLock() =
  let repoRoot = prepareProofLockFixture("proof_universe_lock_compute_test")
  let lockPath = repoRoot / "test_proof_universe.lock"
  let lockResult = computeProofUniverseLock(repoRoot, "certs", vkdFixed4 = ValidatedAsi("0.9876"))
  try:
    check lockResult.isOk  # was: assert lockResult.isOk, "computeProofUniverseLock failed: " & lockResult.error
    let lock = lockResult.get
    check lock.merkleRoot.len > 0
    check lock.fileCount > 0
    check lock.vkdFixed4 == "0.9876"
    let jsonStr = "{\"merkleRoot\":\"" & lock.merkleRoot & "\",\"timestamp\":\"" & lock.timestamp & "\",\"fileCount\":" & $lock.fileCount & ",\"vkdFixed4\":\"" & lock.vkdFixed4 & "\"}"
    writeFile(lockPath, jsonStr)
    let verifiedResult = verifyProofUniverseLock(
      repoRoot = repoRoot,
      certDir = "certs",
      path = lockPath
    )
    check verifiedResult.isOk  # was: assert verifiedResult.isOk, "verifyProofUniverseLock failed: " & verifiedResult.error
    check verifiedResult.get == true
  finally:
    if dirExists(repoRoot):
      removeDir(repoRoot)

proc testDeterministicSort() =
  ## Merkle root must be identical across repeated invocations
  let repoRoot = prepareProofLockFixture("proof_universe_lock_sort_test")
  try:
    let aResult = computeProofUniverseLock(repoRoot, "certs", vkdFixed4 = ValidatedAsi("0.9876"))
    let bResult = computeProofUniverseLock(repoRoot, "certs", vkdFixed4 = ValidatedAsi("0.9876"))
    check aResult.isOk and bResult.isOk
    let a = aResult.get
    let b = bResult.get
    check a.merkleRoot == b.merkleRoot
    check a.fileCount == b.fileCount
  finally:
    if dirExists(repoRoot):
      removeDir(repoRoot)

proc testRepoRootAbsolutePath() =
  ## repoRoot parameter must resolve correctly from any cwd
  let repoRoot = prepareProofLockFixture("proof_universe_lock_repo_root_test")
  try:
    let lockResult = computeProofUniverseLock(absolutePath(repoRoot), "certs", vkdFixed4 = ValidatedAsi("0.9876"))
    check lockResult.isOk  # was: assert lockResult.isOk, "computeProofUniverseLock failed: " & lockResult.error
    check lockResult.get.fileCount > 0
  finally:
    if dirExists(repoRoot):
      removeDir(repoRoot)

proc testParseAsiFromStateFile() =
  ## parseAsiFromStateFile must extract ASI from valid state JSON
  let testState = "test_ax_state.json"
  writeFile(testState, """{"summary":{"asiFixed4":"0.9876"}}""")
  let asiResult = parseAsiFromStateFile(testState)
  check asiResult.isOk
  check asiResult.get == "0.9876"
  removeFile(testState)

proc testExplicitRuntimeZeroAsiIsNotFallback() =
  ## Explicit runtime ASI is already computed evidence, even when not perfect.
  let tempRoot = prepareProofLockFixture("proof_universe_lock_zero_asi_test", "0.0000")
  try:
    let lockResult = computeProofUniverseLock(
      repoRoot = tempRoot,
      certDir = "certs",
      vkdFixed4 = ValidatedAsi("0.0000"),
      source = asiComputed
    )
    check lockResult.isOk
    let lock = lockResult.get
    check lock.vkdFixed4 == "0.0000"
    check lock.fileCount > 0
  finally:
    if dirExists(tempRoot):
      removeDir(tempRoot)

proc testComputeGraphMerkleHashRejectsMissingGraph() =
  let graphHash = computeGraphMerkleHash("logs/missing_global_symbol_graph.json")
  check graphHash.isErr

proc testCommitUniverseIntegrityAndLockWritesGraphAndLock() =
  let repoRoot = prepareProofLockFixture("proof_universe_lock_commit_test")
  let graphPath = repoRoot / defaultGlobalSymbolGraphPath
  let lockPath = repoRoot / defaultProofUniverseLockPath
  try:
    if fileExists(graphPath):
      removeFile(graphPath)
    discard commitUniverseIntegrityAndLock(repoRoot, sampleGlobalSymbolGraph(), ValidatedAsi("0.9876"), caller = AuthorizedLockCaller) # axiom:best-effort(test-side-effect verification — write outcome confirmed via fileExists(graphPath)/fileExists(lockPath)/computeGraphMerkleHash below)
    check fileExists(graphPath)
    check fileExists(lockPath)
    check computeGraphMerkleHash(graphPath).isOk
  finally:
    if dirExists(repoRoot):
      removeDir(repoRoot)

proc testPurgeStaleEvidenceFiles() =
  ## [Synchronous Terminal Activation 1/2] Only evidence files that do not match
  ## whitelisted certificates are eliminated.
  let repoRoot = prepareProofLockFixture("purge_stale_evidence_test")
  let evidenceDir = repoRoot / "logs" / "evidence"
  let certDir = repoRoot / "certs"
  createDir(evidenceDir)
  # valid certificate with modulePath and functionName
  writeFile(certDir / "valid.json", """{"status":"verified","modulePath":"valid.nim","functionName":"validProc"}""")
  # evidence files for valid and orphan nodes
  writeFile(evidenceDir / "valid.nim::validProc.z3out", "solver output")
  writeFile(evidenceDir / "valid.nim::validProc_leanstral_0.json", "lean output")
  writeFile(evidenceDir / "orphan.nim::orphanProc.z3out", "solver output")
  writeFile(evidenceDir / "orphan.nim::orphanProc_leanstral_1.json", "lean output")
  try:
    purgeStaleEvidenceFiles(evidenceDir, certDir)
    check fileExists(evidenceDir / "valid.nim::validProc.z3out") == true
    check fileExists(evidenceDir / "valid.nim::validProc_leanstral_0.json") == true
    check fileExists(evidenceDir / "orphan.nim::orphanProc.z3out") == false
    check fileExists(evidenceDir / "orphan.nim::orphanProc_leanstral_1.json") == false
  finally:
    if dirExists(repoRoot):
      removeDir(repoRoot)

proc testAuthorizedLockCallerValue() =
  check AuthorizedLockCaller == "ax_prove_core"

proc testCallerGuardRejectsUnknownByDefault() =
  ## The default caller value "unknown" must not match the authorized token.
  check AuthorizedLockCaller != "unknown"


proc testSeedGraphFallbackProducesValidMerkleHash() =
  ## When the global symbol graph is missing, seed copy should produce a
  ## verifiable Merkle hash matching the lock generated with the actual graph.
  let repoRoot = prepareProofLockFixture("proof_universe_lock_seed_fallback_test")
  let graphPath = repoRoot / defaultGlobalSymbolGraphPath
  let seedPath = repoRoot / defaultSeedSymbolGraphPath
  let lockPath = repoRoot / "test_seed_fallback.lock"
  try:
    # Generate lock with actual graph present (seed-only source, graph hydrated)
    let lockResult = computeProofUniverseLock(repoRoot, "certs", vkdFixed4 = ValidatedAsi("0.9876"))
    check lockResult.isOk  # was: assert lockResult.isOk, "computeProofUniverseLock failed: " & lockResult.error
    let lock = lockResult.get
    check fileExists(graphPath)
    # Persist the lock so verification can replay it
    writeFile(lockPath, "{\"merkleRoot\":\"" & lock.merkleRoot & "\",\"timestamp\":\"" & lock.timestamp & "\",\"fileCount\":" & $lock.fileCount & ",\"vkdFixed4\":\"" & lock.vkdFixed4 & "\"}")
    # Copy graph as seed (defaultSeedSymbolGraphPath), then remove actual graph
    # so proof_universe_lock must fall back to the seed on verification.
    copyFile(graphPath, seedPath)
    removeFile(graphPath)
    # Verify with seed fallback should pass
    let verifiedResult = verifyProofUniverseLock(repoRoot = repoRoot, certDir = "certs", path = lockPath)
    check verifiedResult.isOk  # was: assert verifiedResult.isOk, "verifyProofUniverseLock failed: " & verifiedResult.error
    check verifiedResult.get == true
  finally:
    if dirExists(repoRoot):
      removeDir(repoRoot)

proc isShaDigest(value: string): bool =
  if value.len != 64:
    return false
  for ch in value:
    if not (ch in {'0'..'9', 'a'..'f', 'A'..'F'}):
      return false
  true

proc testMerkleRootUsesStableShaDigest() =
  ## The lock root must not depend on Nim's process-local hash seed.
  let repoRoot = prepareProofLockFixture("proof_universe_lock_sha_digest_test")
  let lockPath = repoRoot / "sha_digest.lock"
  try:
    let lockResult = computeProofUniverseLock(repoRoot, "certs", vkdFixed4 = ValidatedAsi("0.9876"), source = asiComputed)
    check lockResult.isOk
    let lock = lockResult.get
    check isShaDigest(lock.merkleRoot)
    writeFile(lockPath, pretty(%*{
      "merkleRoot": lock.merkleRoot,
      "timestamp": lock.timestamp,
      "fileCount": lock.fileCount,
      vkdFixed4Key: lock.vkdFixed4
    }) & "\n")
    let verifiedResult = verifyProofUniverseLock(repoRoot = repoRoot, certDir = "certs", path = lockPath)
    check verifiedResult.isOk
    check verifiedResult.get
  finally:
    if dirExists(repoRoot):
      removeDir(repoRoot)

proc testThreeWaySplitCompiles() =
  # Wave 7 topological stratification: proof_universe_lock split into
  # core kernel, verification I/O, and verification orchestration.
  # If these imports compile, the 3-way split is structurally sound.
  discard

suite "Proof Universe Lock":
  test "Proof Universe Lock tests":
    testComputeAndVerifyLock()
    testDeterministicSort()
    testRepoRootAbsolutePath()
    testParseAsiFromStateFile()
    testExplicitRuntimeZeroAsiIsNotFallback()
    testComputeGraphMerkleHashRejectsMissingGraph()
    testCommitUniverseIntegrityAndLockWritesGraphAndLock()
    testPurgeStaleEvidenceFiles()
    testAuthorizedLockCallerValue()
    testCallerGuardRejectsUnknownByDefault()
    testSeedGraphFallbackProducesValidMerkleHash()
    testMerkleRootUsesStableShaDigest()
    testThreeWaySplitCompiles()
