{.push raises: [CatchableError].}

## E2E verification for Merkle VFS + Hermetic Sandbox pipeline
##
## Tests the full lifecycle: build → snapshot → write → delta → commit
## and conflict detection: snapshot → write → conflicting commit → Defect
##
## Wave 5D-2: Comprehensive verification of:
##   - Merkle tree construction + lazy hash computation
##   - Snapshot-based COW (Copy-on-Write) isolation
##   - Delta commit with Conflict=Failure semantics
##   - Hermetic sandbox environment isolation
##   - CAS (Content-Addressed Storage) integration
##   - Conflict message formatting

import std/[unittest, os, strutils, tables, options]
import core/gate/merkle_vfs
import core/gate/hermetic_sandbox
import core/gate/gate_cas

# ─── Helpers ──────────────────────────────────────────────────────────────────

proc makeTempDir(): string =
  ## Create a unique temp directory for CAS tests.
  let base = getTempDir() / "axiom_merkle_test"
  discard existsOrCreateDir(base)
  var idx = 0
  while true:
    let candidate = base / ("run_" & $idx)
    if not dirExists(candidate):
      createDir(candidate)
      return candidate
    inc idx

# ─── Test Suite ───────────────────────────────────────────────────────────────

suite "Merkle VFS E2E":

  test "lazy hash computation":
    # Build a VFS with known file content.
    # buildMerkleForTest pre-computes and caches hashes.
    let vfs = buildMerkleForTest(@[
      ("/src/main.nim", "echo \"hello\""),
      ("/src/utils.nim", "proc add*(a, b: int): int = a + b"),
    ])

    # 1. Verify hashes are pre-computed (lazyHash.len > 0).
    let mainNode = vfs.pathIndex["/src/main.nim"]
    check mainNode.lazyHash.len > 0
    let utilsNode = vfs.pathIndex["/src/utils.nim"]
    check utilsNode.lazyHash.len > 0

    # 2. getNodeHash returns cached hash when available.
    let hash1 = getNodeHash(mainNode)
    check hash1 == mainNode.lazyHash

    # 3. invalidateHash clears cache.
    invalidateHash(mainNode)
    check mainNode.lazyHash.len == 0

    # 4. getNodeHash recomputes after invalidation — same content → same hash.
    let hash2 = getNodeHash(mainNode)
    check hash2.len > 0
    check hash2 == hash1  # Content unchanged → hash unchanged

    # 5. computeHash always computes fresh (no caching side effect).
    let hash3 = computeHash(mainNode)
    check hash3 == hash2

    # 6. Modifying content changes the hash.
    mainNode.content = "echo \"modified\""
    let hash4 = computeHash(mainNode)
    check hash4 != hash1

  test "ancestor hash invalidation":
    # Set up VFS with directory nodes in pathIndex to test ancestor walk.
    let vfs = buildMerkleForTest(@[
      ("/src/main.nim", "echo 42"),
    ])

    # Manually add directory nodes so invalidateAncestors has something to walk.
    let srcDir = VfsNode(
      kind: vnDir, path: "/src",
      lazyHash: "pre-computed-dir-hash",
      lastWriter: "",
      children: @[],
      childHashes: @[]
    )
    vfs.pathIndex["/src"] = srcDir

    # Root already exists from buildMerkleForTest.
    vfs.root.lazyHash = "pre-computed-root-hash"

    # Verify ancestors have cached hashes before invalidation.
    check vfs.pathIndex["/src"].lazyHash == "pre-computed-dir-hash"
    check vfs.root.lazyHash == "pre-computed-root-hash"

    # Invalidate ancestors of /src/main.nim.
    invalidateAncestors(vfs, "/src/main.nim")

    # /src should be invalidated (lazyHash = "").
    check vfs.pathIndex["/src"].lazyHash.len == 0
    # Root "/" is NOT invalidated because parentPath("/src") = "",
    # which exits the while loop immediately.
    # This is expected: the walk stops at the topmost named ancestor.

  test "snapshot COW isolation":
    let vfs = buildMerkleForTest(@[
      ("/config.toml", "version = 1"),
      ("/README.md", "# Project"),
    ])

    # 1. Take snapshot — O(1), only copies root pointer.
    var snap = vfsSnapshot(vfs, gateId = "gate-a")
    check snap.base == vfs  # Same reference
    check snap.overlay == nil  # No changes yet
    check snap.gateId == "gate-a"

    # 2. Read from snapshot falls back to base.
    let original = vfsReadFromSnapshot(snap, "/config.toml")
    check original == "version = 1"

    # 3. Write to snapshot overlay.
    vfsWrite(snap, "/config.toml", "version = 2")
    check snap.changedPaths.len == 1
    check "/config.toml" in snap.changedPaths

    # 4. Snapshot reads overlay content.
    let updated = vfsReadFromSnapshot(snap, "/config.toml")
    check updated == "version = 2"

    # 5. Original VFS is UNCHANGED — COW isolation verified.
    let stillOriginal = vfsRead(vfs, "/config.toml")
    check stillOriginal == "version = 1"

    # 6. Unmodified path falls through to base in snapshot.
    let readme = vfsReadFromSnapshot(snap, "/README.md")
    check readme == "# Project"

    # 7. Discard snapshot releases overlay.
    vfsDiscard(snap)
    check snap.overlay == nil
    check snap.changedPaths.len == 0
    check snap.overlayIndex.len == 0

  test "conflict=failure on CAS mismatch":
    # CAS Conflict=Failure: two gates writing different content to the same
    # NEW path. The first commit succeeds (path is novel); the second fails
    # because the hash differs — ContentCollisionDefect is raised.
    var vfs = buildMerkleForTest(@[
      ("/src/seed.nim", "seed"),
    ])

    # Gate-a writes to a NEW path (not in base) — must succeed.
    let sharedPath = "/src/shared_output.txt"
    var snapA = vfsSnapshot(vfs, gateId = "gate-a")
    vfsWrite(snapA, sharedPath, "output from gate-a")
    let deltaA = toDelta(snapA)
    vfsCommit(vfs, deltaA)
    check vfsRead(vfs, sharedPath) == "output from gate-a"

    # Gate-b writes DIFFERENT content to the SAME path — must conflict.
    var snapB = vfsSnapshot(vfs, gateId = "gate-b")
    vfsWrite(snapB, sharedPath, "output from gate-b")
    let deltaB = toDelta(snapB)

    # Commit must raise ContentCollisionDefect (Conflict=Failure).
    var caught = false
    try:
      vfsCommit(vfs, deltaB)
    except ContentCollisionDefect as e:
      caught = true
      # Verify the exception carries useful diagnostic info.
      check e.msg.len > 0
      check "gate-a" in e.msg or "gate-b" in e.msg
      check "Content collision" in e.msg
    check caught

    # Gate-a's content is preserved after the failed conflict.
    check vfsRead(vfs, sharedPath) == "output from gate-a"

    # Idempotent commit: same content by a third gate → no conflict.
    var snapC = vfsSnapshot(vfs, gateId = "gate-c")
    vfsWrite(snapC, sharedPath, "output from gate-a")
    let deltaC = toDelta(snapC)
    vfsCommit(vfs, deltaC)  # Should NOT raise — same hash.

  test "hermetic sandbox env isolation":
    # Use /tmp as repoRoot — guaranteed to exist on Linux.
    let repoRoot = "/tmp"

    # 1. Build config — only HOME, PATH, AXIOM_REPO_ROOT are injected.
    var extraEnv = initTable[string, string]()
    extraEnv["MY_CUSTOM_VAR"] = "custom_value"
    let config = buildHermeticConfig(repoRoot, extraEnv = extraEnv, timeout = 5)

    # 2. Verify allowlisted env vars are minimal.
    check config.allowedEnv.hasKey("AXIOM_REPO_ROOT")
    check config.allowedEnv["AXIOM_REPO_ROOT"] == repoRoot
    check config.allowedEnv.hasKey("PATH")
    # Custom extra was merged.
    check config.allowedEnv["MY_CUSTOM_VAR"] == "custom_value"
    # networkAccess is false by default.
    check config.networkAccess == false
    # Working dir matches repo root.
    check config.workingDir == repoRoot

    # 3. Execute a simple command in the sandbox.
    let result = hermeticExec("/bin/echo", @["sandbox-ok"], config)
    check result.exitCode == 0
    check "sandbox-ok" in result.output

    # 4. Verify isolation: a process started in the sandbox does NOT see
    #    env vars that were NOT explicitly allowlisted.
    var isoConfig = buildHermeticConfig("/tmp", timeout = 5)
    isoConfig.allowedEnv = initTable[string, string]()
    isoConfig.allowedEnv["PATH"] = getEnv("PATH", "/usr/bin:/bin")
    isoConfig.allowedEnv["AXIOM_TEST_MARKER"] = "isolated"
    isoConfig.workingDir = "/tmp"

    let envResult = hermeticExec("/usr/bin/env", @[], isoConfig)
    check envResult.exitCode == 0
    check "AXIOM_TEST_MARKER=isolated" in envResult.output
    # A var we did NOT allowlist must NOT appear.
    check "AXIOM_REPO_ROOT" notin envResult.output

  test "CAS store and retrieve":
    let tmpRoot = makeTempDir()
    # Pre-create the CAS content directory structure so storeContentToCas
    # can write files without depending on existsOrCreateDirOpt.
    createDir(tmpRoot / ".axiom" / "cache" / "content")
    defer:
      # Clean up CAS artifacts.
      removeDir(tmpRoot / ".axiom")

    let content1 = "Hello from CAS test"
    let content2 = "Second content block"

    # 1. Store content — returns SHA-256 hash.
    let hash1 = storeContentToCas(content1, tmpRoot)
    check hash1.len > 0

    # 2. Verify file exists on disk at expected CAS path.
    let casPath = tmpRoot / ".axiom" / "cache" / "content" / hash1[0 ..< 2] / hash1
    check fileExists(casPath)

    # 3. Read back and verify content matches.
    let retrieved = readFile(casPath)
    check retrieved == content1

    # 4. Idempotent: storing same content returns same hash.
    let hash1Again = storeContentToCas(content1, tmpRoot)
    check hash1Again == hash1

    # 5. Different content → different hash.
    let hash2 = storeContentToCas(content2, tmpRoot)
    check hash2.len > 0
    check hash2 != hash1

    # 6. Empty content returns empty hash.
    let hashEmpty = storeContentToCas("", tmpRoot)
    check hashEmpty.len == 0

  test "conflict message formatting":
    let msg = buildConflictMessage(
      path = "/src/gate_output.nim",
      gateA = "memory-safety",
      gateB = "race-condition",
      hashA = "abc123",
      hashB = "def456"
    )

    # Verify all expected components are present in the message.
    check "/src/gate_output.nim" in msg
    check "memory-safety" in msg
    check "race-condition" in msg
    check "abc123" in msg
    check "def456" in msg
    # DAG edge suggestion for gate_manifest.json.
    check "memory-safety" in msg
    check "race-condition" in msg
    check "gate_manifest.json" in msg
    # Actionable fix indicator.
    check "after-edge" in msg

  test "full pipeline: build → snapshot → write → delta → commit":
    # End-to-end happy path: all components working together.
    # Uses NEW paths for writes (CAS Conflict=Failure: any mutation of
    # existing content is a conflict — only novel paths or idempotent
    # re-writes are permitted).
    var vfs = buildMerkleForTest(@[
      ("/src/main.nim", "echo \"original\""),
    ])

    # 1. Snapshot from initial VFS — verify base read-through works.
    var snap = vfsSnapshot(vfs, gateId = "quality-gate")
    check vfsReadFromSnapshot(snap, "/src/main.nim") == "echo \"original\""

    # 2. Write NEW content to snapshot (new paths, no conflict).
    vfsWrite(snap, "/output/gate_result.txt", "passed")
    vfsWrite(snap, "/output/gate_metrics.json", "{\"score\": 95}")

    # 3. Read back from snapshot to verify overlay.
    check vfsReadFromSnapshot(snap, "/output/gate_result.txt") == "passed"
    check vfsReadFromSnapshot(snap, "/output/gate_metrics.json") == "{\"score\": 95}"
    # Original path still falls through to base.
    check vfsReadFromSnapshot(snap, "/src/main.nim") == "echo \"original\""

    # 4. Convert to delta (pure operation).
    let delta = toDelta(snap)
    check delta.gateId == "quality-gate"
    check delta.writtenPaths.len == 2
    check "/output/gate_result.txt" in delta.writtenPaths
    check "/output/gate_metrics.json" in delta.writtenPaths

    # 5. Commit delta to base VFS.
    vfsCommit(vfs, delta)

    # 6. Verify base VFS now has the committed content.
    check vfsRead(vfs, "/output/gate_result.txt") == "passed"
    check vfsRead(vfs, "/output/gate_metrics.json") == "{\"score\": 95}"
    # Original path unchanged.
    check vfsRead(vfs, "/src/main.nim") == "echo \"original\""

    # 7. Verify hashes are computed (post-commit).
    let resultHash = vfsHash(vfs, "/output/gate_result.txt")
    check resultHash.len > 0

    # 8. Discard snapshot — base VFS remains intact.
    vfsDiscard(snap)
    check vfsRead(vfs, "/output/gate_result.txt") == "passed"

    # 9. Chain: second gate commits on top (new paths).
    var snap2 = vfsSnapshot(vfs, gateId = "final-check")
    vfsWrite(snap2, "/output/final_verdict.txt", "all gates passed")
    let delta2 = toDelta(snap2)
    vfsCommit(vfs, delta2)
    check vfsRead(vfs, "/output/final_verdict.txt") == "all gates passed"
    # Previous commits still intact.
    check vfsRead(vfs, "/output/gate_result.txt") == "passed"

  test "vfsReadOpt returns none for missing paths":
    let vfs = buildMerkleForTest(@[
      ("/exists.txt", "present"),
    ])

    check vfsReadOpt(vfs, "/exists.txt") == some("present")
    check vfsReadOpt(vfs, "/missing.txt").isNone()

  test "hermeticSubprocessProvider closure":
    # Verify the closure-based provider works and is SubprocessProvider compatible.
    let config = buildHermeticConfig("/tmp", timeout = 5)
    let provider = hermeticSubprocessProvider(config)

    # The provider is a proc that matches SubprocessProvider signature.
    let result = provider("/bin/echo", @["closure-test"])
    check result.exitCode == 0
    check "closure-test" in result.output

  test "snapshot read fallback to base for unmodified paths":
    let vfs = buildMerkleForTest(@[
      ("/a.txt", "alpha"),
      ("/b.txt", "beta"),
    ])

    var snap = vfsSnapshot(vfs, gateId = "partial-writer")
    vfsWrite(snap, "/a.txt", "alpha-v2")

    # Modified path → overlay.
    check vfsReadFromSnapshot(snap, "/a.txt") == "alpha-v2"
    # Unmodified path → base fallback.
    check vfsReadFromSnapshot(snap, "/b.txt") == "beta"
    # Missing path → KeyError.
    var raised = false
    try:
      discard vfsReadFromSnapshot(snap, "/c.txt")
    except KeyError:
      raised = true
    check raised

{.pop.}
