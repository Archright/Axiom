import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## DiscoveryPolicy — Deterministic source-file filtering for topology scanning.
##
## Ensures only valid Nim source files enter the verification pipeline,
## preventing C compiler artifacts from polluting the sampling pool.

import std/algorithm
import std/os
import std/osproc
import std/strutils
import std/json
import core/crypto/hash_kernel
import core/axiom_pragmas
import infrastructure/logging_facade

type
  DiscoveryPolicy* = object
    includeExtensions*: seq[string]
    excludePaths*: seq[string]

const nimSourcePolicy* = DiscoveryPolicy(
  includeExtensions: @[".nim", ".nims"],
  excludePaths: @[
    "nimcache", ".nimcache", ".nimcache_gate_hook",
    "build", ".lake", "vendor", ".git",
    "logs", "bin", "node_modules",
    "semantic_proofs", "verifications", "experimental"
  ]
)

const rustSourcePolicy* = DiscoveryPolicy(
  includeExtensions: @[".rs"],
  excludePaths: @["target", "build", "node_modules", ".git"]
)
  ## Rust subject policy (feat/rust-subject-v1): `*.rs` sources only;
  ## `target` is Cargo's build dir (excluded for the walkDirRec fallback
  ## the same way `build` is for the Nim policy). Feeds the parameterized
  ## collectSubjectFileSet and the rust subject input contract.

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isValidSourceNode*(path: string;
    policy: DiscoveryPolicy = nimSourcePolicy): bool =
  ## Check if `path` is a valid source node under `policy`.
  ## Returns true only for files with allowed extensions that are not
  ## inside any excluded directory path.
  let (_, _, ext) = splitFile(path)
  if ext.len == 0:
    return false
  let lowerExt = ext.toLowerAscii()
  var extMatch = false
  for allowed in policy.includeExtensions:
    if lowerExt == allowed:
      extMatch = true
      break
  if not extMatch:
    return false
  let normalizedPath = path.toLowerAscii()
  for excl in policy.excludePaths:
    if "/" & excl & "/" in normalizedPath or
       normalizedPath.endsWith("/" & excl) or
       normalizedPath.startsWith(excl & "/"):
      return false
  true

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc collectGitTrackedSources*(repoRoot: string): seq[string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## git ls-files로 추적된 .nim 파일만 수집 (화이트리스트 방식)
  ## .worktrees, .axiom, nimcache 등 미추적 디렉토리 자동 제외
  ## .git/index SHA-256 캐시: 인덱스 변경 없으면 git ls-files 스킵
  ## Deterministic: SHA-256 content hash replaces mtime for cache validation.

  # ── Stage 1: SHA-256 content-hash cache check ──────────────────
  # WP2-a: cache routes to stateRoot when set (subject immutability).
  let cachePath = block:
    let sr = getEnv("AXIOM_STATE_DIR", "").strip()
    (if sr.len > 0: sr else: repoRoot) / ".axiom" / "cache" / "git_file_list.json"
  let indexPath = repoRoot / ".git" / "index"

  try:
    if cachePath.fileExists() and indexPath.fileExists():
      let indexContent = indexPath.readFile()
      let indexHash = sha256Hex(indexContent)
      let cacheJson = parseJson(cachePath.readFile())
      if cacheJson.hasKey("gitIndexHash") and
         cacheJson["gitIndexHash"].getStr() == indexHash:
        # Cache is fresh — load from JSON, skip git ls-files
        let files = cacheJson["files"]
        for item in files:
          let p = repoRoot / item.getStr()
          # Skip paths that no longer exist on disk (e.g. deleted-but-unstaged
          # tracked files). Scanning/stat'ing a missing path is both wrong
          # (deleted sources are not part of the topology) and can hang in
          # the fileCache fast path below.
          if p.fileExists():
            result.add(p)
        if result.len > 0:
          return
  except CatchableError:
    logWarn("node_filter", "Cache parse failed — falling back to git ls-files")

  # ── Stage 2: git ls-files (cache miss or stale) ────────────────
  try:
    let (output, exitCode) = execCmdEx(
      "git ls-files --cached --others --exclude-standard -- '*.nim'",
      options = {poUsePath},
      workingDir = repoRoot
    )
    if exitCode == 0 and output.len > 0:
      for line in output.splitLines():
        if line.len > 0 and line.endsWith(".nim"):
          let p = repoRoot / line
          # Same existence guard as the cache path above: a tracked-but-deleted
          # file must not enter the scan set.
          if p.fileExists():
            result.add(p)
      result.sort()

      # Persist to cache with SHA-256 hash
      try:
        let cacheDir = repoRoot / ".axiom" / "cache"
        if not cacheDir.dirExists():
          cacheDir.createDir()
        var fileList = newJArray()
        for f in result:
          # Store paths relative to repoRoot for worktree portability
          if f.startsWith(repoRoot) and f.len > repoRoot.len:
            fileList.add(newJString(f[repoRoot.len + 1 .. ^1]))
          else:
            fileList.add(newJString(f))
        var cacheJson = newJObject()
        let indexContent = indexPath.readFile()
        cacheJson["gitIndexHash"] = newJString(sha256Hex(indexContent))
        cacheJson["files"] = fileList
        cachePath.writeFile($cacheJson)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)

      return
  except CatchableError:
    logWarn("node_filter", "git ls-files failed — falling back to walkDirRec scan")

  # ── Stage 3: Fallback — git 미초기화 환경에서는 walkDirRec ───────
  try:
    for filePath in walkDirRec(repoRoot):
      if isValidSourceNode(filePath):
        result.add(filePath)
  except OSError as e:
    logWarn("node_filter", "walkDirRec fallback failed — returning empty scan set: " & e.msg)
  result.sort()

{.pop.}
