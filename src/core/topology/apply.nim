## Apply Orchestrator for Topology Reconciliation
## Pure builder: turns a Plan into a TopologyExecutionPlan (intent only).
## All filesystem/process I/O lives in infrastructure/topology_executor.nim.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/[strutils, tables, sequtils, algorithm]
import core/topology/[plan, staging, rewrite, lock_update, topology_types]
{.push raises: [].}
# axiomIoBoundary

export plan, staging, rewrite, lock_update, topology_types

# ── nimpretty exclusion list ─────────────────────────────
# Files known to trigger nimpretty corruption (concatenates
# `and` keyword with adjacent identifier). Tracked upstream:
# https://github.com/nim-lang/Nim/issues — nimpretty formatter bug.
const NimprettyExclusions*: seq[string] = @[
  "src/core/logic/lean_diagnostic.nim",
  "src/verification/pipeline_negative_scan_part2.nim",
]

# ── batch chunking ────────────────────────────────────────
const DefaultChunkSize* = 10

func chunkPairs*[V](t: Table[string, V]; size: int): seq[Table[string, V]] {.raises: [].} =
  ## Split a Table into deterministic (sorted-key) chunks of `size`.
  let keys = toSeq(t.keys).sorted
  var chunk: Table[string, V]
  var count = 0
  for key in keys:
    chunk[key] = t[key]
    inc count
    if count >= size:
      result.add(chunk)
      chunk.clear()
      count = 0
  if chunk.len > 0:
    result.add(chunk)

func chunkStrings*(files: seq[string]; size: int): seq[seq[string]] {.raises: [].} =
  ## Split a seq of strings into deterministic sorted chunks.
  let sortedFiles = files.sorted
  var chunk: seq[string]
  var count = 0
  for f in sortedFiles:
    chunk.add(f)
    inc count
    if count >= size:
      result.add(chunk)
      chunk = @[]
      count = 0
  if chunk.len > 0:
    result.add(chunk)

# ---------------------------------------------------------------------------
# Pure policy / plan builders
# ---------------------------------------------------------------------------

func buildTopologyExecutionPolicy*(dryRun, autoApprove, force: bool): TopologyExecutionPolicy {.raises: [].} =
  result = TopologyExecutionPolicy(
    dryRun: dryRun,
    force: force,
    requireCleanGit: not force,
    requireApproval: not autoApprove,
    allowRollback: true,
    autoApprove: autoApprove
  )

func buildTopologyExecutionPlan*(plan: Plan;
                                 fileContents: Table[string, string];
                                 policy: TopologyExecutionPolicy;
                                 axPath: string;
                                 lockPath: string): TopologyExecutionPlan {.raises: [].} =
  ## Build an I/O-free execution plan from a topology reconciliation plan.
  result.policy = policy

  var ops: seq[TopologyOperation] = @[]
  var stagedPaths: seq[string] = @[]
  func addStage(path: string) {.raises: [].} =
    if path.len > 0 and path notin stagedPaths:
      ops.add(TopologyOperation(kind: tokStageFile, stageSrc: path))
      stagedPaths.add(path)

  # Stage all files that will be touched.
  for m in plan.moves:
    addStage(m.fromPath)
  for r in plan.rewrites:
    addStage(r.file)

  # Record manifest for forensics/rollback.
  ops.add(TopologyOperation(kind: tokRecordManifest, manifestPlan: plan))

  # Stage topology.lock if it will be mutated.
  if lockPath.len > 0:
    ops.add(TopologyOperation(kind: tokStageFile, stageSrc: lockPath))

  # Build move path remap so rewrites of moved files use the new path.
  var moveMap: Table[string, string]
  for m in plan.moves:
    moveMap[m.fromPath] = m.toPath

  # Create target directories and move files.
  for m in plan.moves:
    let targetDir = topologyParentDir(m.toPath)
    if targetDir.len > 0:
      ops.add(TopologyOperation(kind: tokCreateDir, dirPath: targetDir))
    ops.add(TopologyOperation(kind: tokMoveFile, srcPath: m.fromPath, dstPath: m.toPath))

  # Group rewrites by post-move file path.
  var rewritesByFile: Table[string, seq[ImportRewriteRule]]
  for r in plan.rewrites:
    let rewriteFile = moveMap.getOrDefault(r.file, r.file)
    rewritesByFile.mgetOrPut(rewriteFile, @[]).add(ImportRewriteRule(oldPath: r.oldPath, newPath: r.newPath))

  # Rewrite consumer imports.
  var changedFiles: seq[string] = @[]
  for file, fileRules in rewritesByFile.pairs:
    let content = fileContents.getOrDefault(file, "")
    let rewritten = rewriteContentImports(content, fileRules)
    ops.add(TopologyOperation(kind: tokWriteFile, writePath: file, content: rewritten))
    if file notin changedFiles:
      changedFiles.add(file)

  # Track changed files for downstream tooling.
  for m in plan.moves:
    if m.toPath notin changedFiles:
      changedFiles.add(m.toPath)
  for r in plan.rewrites:
    if r.file notin changedFiles:
      changedFiles.add(r.file)

  # nimpretty on changed files (chunked + exclusions).
  let prettyChunks = chunkStrings(changedFiles, DefaultChunkSize)
  for chunk in prettyChunks:
    var safeFiles: seq[string] = @[]
    for f in chunk:
      var excluded = false
      for excl in NimprettyExclusions:
        if f.endsWith(excl) or f == excl:
          excluded = true
          break
      if not excluded:
        safeFiles.add(f)
    if safeFiles.len > 0:
      ops.add(TopologyOperation(kind: tokExec, command: @["nimpretty"] & safeFiles))

  # nim check on changed files plus affected consumers.
  if changedFiles.len > 1:
    ops.add(TopologyOperation(kind: tokExec, command: @["nim", "check", "src/cli/main.nim"]))
  elif changedFiles.len == 1:
    ops.add(TopologyOperation(kind: tokExec, command: @["nim", "check", changedFiles[0]]))

  # topology audit.
  if axPath.len > 0:
    ops.add(TopologyOperation(kind: tokExec, command: @[axPath, "topology", "audit", "--format", "json"]))

  # Lock update.
  if lockPath.len > 0:
    ops.add(TopologyOperation(kind: tokUpdateLock, lockPath: lockPath, lockMoves: plan.moves))

  result.operations = ops

{.pop}
