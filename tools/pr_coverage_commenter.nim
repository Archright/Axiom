## pr_coverage_commenter.nim — PR Coverage Diff Comment Bot
##
## Posts coverage diff comments to GitHub PRs using the REST API.
##
## Reads build/branch_coverage.json for head coverage, fetches main branch
## baseline from git, computes delta, and posts a formatted Markdown table
## as a PR comment annotated with # axiom:pr-bot.
##
## Usage (standalone):
##   nim c -o:bin/pr_coverage_commenter tools/pr_coverage_commenter.nim
##   bin/pr_coverage_commenter [--dry-run]
##
## Environment variables:
##   GITHUB_TOKEN     — GitHub personal access token (required)
##   GITHUB_REPO      — "owner/repo" override (default: parsed from git remote)
##   CIRCLE_PR_NUMBER — PR number from CircleCI (required in CI)
##   BASE_REF         — Base branch for comparison (default: main)
##
## Exit codes:
##   0  Success (or --dry-run)
##   1  Fatal error (missing token, invalid JSON, API failure)
##   2  Graceful skip (no PR number, not a PR build)

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[httpclient, json, os, osproc, strformat, strutils, uri, sequtils, math, algorithm, options]

# ═══════════════════════════════════════════════════════════════════════════════
# §0: Compile-Time Toolchain Lock
# ═══════════════════════════════════════════════════════════════════════════════

static:
  when NimMajor != 2 or NimMinor != 2:
    {.error: "PR Coverage Commenter requires Nim v2.2.x".}

# ═══════════════════════════════════════════════════════════════════════════════
# §1: Constants
# ═══════════════════════════════════════════════════════════════════════════════

const
  CommentTag = "# axiom:pr-bot"
  BranchCoveragePath = "build/branch_coverage.json"
  ModuleCoveragePath = "data/coverage_report.json"
  CachedBaselinePath = "data/.coverage_baseline_main.json"
  DefaultBaseRef = "main"
  HttpTimeoutMs = 30_000
  MaxRetries = 2

# ═══════════════════════════════════════════════════════════════════════════════
# §2: Types
# ═══════════════════════════════════════════════════════════════════════════════

type
  CoverageSnapshot* = object
    timestamp*: string
    branch*: string
    commitHash*: string
    lineCoveragePct*: float
    branchCoveragePct*: float
    moduleCoveragePct*: float
    totalFiles*: int
    filesCovered*: int
    filesUncovered*: int

  CoverageDiff* = object
    target*: string       # "Line", "Branch", "Module"
    basePct*: float
    headPct*: float
    delta*: float

  PrCommentResult* = object
    success*: bool
    commentUrl*: string
    body*: string
    error*: string

# ═══════════════════════════════════════════════════════════════════════════════
# §3: Repo Root Detection
# ═══════════════════════════════════════════════════════════════════════════════

proc findRepoRoot(): string =
  ## Walk up from CWD looking for .axiom_root marker.
  var dir = getCurrentDir()
  for i in 0 ..< 20:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  return getCurrentDir()

# ═══════════════════════════════════════════════════════════════════════════════
# §4: Git Helpers
# ═══════════════════════════════════════════════════════════════════════════════

proc runGit(args: string): string =
  let cmd = "git " & args
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    raise newException(IOError, &"git {args} failed (exit {exitCode}): {output.strip()}")
  result = output.strip()

proc getRemoteOwnerAndRepo(): tuple[owner: string, repo: string] =
  ## Parse owner/repo from git remote origin URL.
  try:
    let url = runGit("remote get-url origin")
    var cleaned = url
    if cleaned.startsWith("git@github.com:"):
      cleaned = cleaned[len("git@github.com:") .. ^1]
    elif "github.com/" in cleaned:
      let idx = cleaned.find("github.com/") + len("github.com/")
      cleaned = cleaned[idx .. ^1]
    cleaned = cleaned.strip(chars = {'/'})
    if cleaned.endsWith(".git"):
      cleaned = cleaned[0 .. ^5]
    let parts = cleaned.split('/')
    if parts.len >= 2:
      result.owner = parts[0]
      result.repo = parts[^1]
    else:
      result.owner = "Archright"
      result.repo = "Axiom"
  except CatchableError:
    result.owner = "Archright"
    result.repo = "Axiom"

# ═══════════════════════════════════════════════════════════════════════════════
# §5: Coverage Data Parsing
# ═══════════════════════════════════════════════════════════════════════════════

proc extractJson(path: string): JsonNode =
  ## Read and parse a JSON file. Returns nil on any error.
  try:
    let content = readFile(path)
    if content.len == 0:
      return nil
    result = parseJson(content)
  except CatchableError:
    result = nil

proc safeFloat(node: JsonNode; default: float = 0.0): float =
  ## Safely extract a float from a JsonNode, returning default on error.
  if node.isNil or node.kind == JNull:
    return default
  try:
    return node.getFloat(default)
  except CatchableError:
    return default

proc safeInt(node: JsonNode; default: int = 0): int =
  ## Safely extract an int from a JsonNode, returning default on error.
  if node.isNil or node.kind == JNull:
    return default
  try:
    return node.getInt(default)
  except CatchableError:
    return default

proc loadSnapshotFromJson(data: JsonNode): CoverageSnapshot =
  ## Parse a CoverageSnapshot from a branch_coverage-style JSON node.
  let summary = data.getOrDefault("summary")
  if summary.isNil or summary.kind == JNull:
    raise newException(CatchableError, "Missing 'summary' key in coverage JSON")

  result.timestamp = data.getOrDefault("timestamp").getStr("")
  result.branch = data.getOrDefault("branch").getStr("")
  result.commitHash = data.getOrDefault("commitHash").getStr("")
  result.totalFiles = safeInt(summary["totalFiles"])
  result.lineCoveragePct = safeFloat(summary["lineCoveragePct"])
  result.branchCoveragePct = safeFloat(summary["branchCoveragePct"])

  # Count covered/uncovered files
  let filesArr = data.getOrDefault("files")
  if not filesArr.isNil and filesArr.kind == JArray:
    for fObj in filesArr:
      let pct = safeFloat(fObj.getOrDefault("branchCoveragePct"))
      if pct > 0.0:
        inc result.filesCovered
      else:
        inc result.filesUncovered

  # Fallback: check metrics key directly
  let metrics = data.getOrDefault("metrics")
  if not metrics.isNil and metrics.kind == JObject:
    if metrics.hasKey("coveragePercent"):
      if result.branchCoveragePct == 0.0:
        result.branchCoveragePct = safeFloat(metrics["coveragePercent"])

proc loadHeadSnapshot(projectRoot: string): CoverageSnapshot =
  ## Load coverage snapshot from build/branch_coverage.json and
  ## fall back to data/coverage_report.json for module coverage.
  let bcPath = projectRoot / BranchCoveragePath
  let mcPath = projectRoot / ModuleCoveragePath

  let bcData = extractJson(bcPath)
  if bcData.isNil:
    raise newException(CatchableError, &"Failed to read {bcPath}")

  result = bcData.loadSnapshotFromJson()

  # Parse module coverage for moduleCoveragePct
  let mcData = extractJson(mcPath)
  if not mcData.isNil and mcData.kind == JObject:
    result.moduleCoveragePct = safeFloat(mcData.getOrDefault("coverage_pct"))
    if result.moduleCoveragePct == 0.0:
      result.moduleCoveragePct = safeFloat(mcData.getOrDefault("moduleCoverage"))

proc loadCachedBaseline(projectRoot: string): CoverageSnapshot =
  ## Load cached baseline from data/.coverage_baseline_main.json.
  let baselinePath = projectRoot / CachedBaselinePath
  let bcData = extractJson(baselinePath)
  if bcData.isNil or bcData.kind == JNull:
    raise newException(CatchableError, &"No cached baseline found at {baselinePath}")

  result = bcData.loadSnapshotFromJson()

  # Also check module-level keys
  result.moduleCoveragePct = safeFloat(bcData.getOrDefault("moduleCoverage"))
  if result.moduleCoveragePct == 0.0:
    result.moduleCoveragePct = safeFloat(bcData.getOrDefault("coverage_pct"))

proc fetchBaseFromGit(baseRef: string; projectRoot: string): CoverageSnapshot =
  ## Fetch baseline coverage from git tree at base ref.
  ## Tries branch_coverage.json first, then falls back to cached baseline.
  var snapshot: CoverageSnapshot

  # Try branch coverage path
  let branchCmd = "git show " & baseRef & ":" & BranchCoveragePath
  let (branchOutput, branchExit) = execCmdEx(branchCmd)
  if branchExit == 0 and branchOutput.len > 0:
    let tmpPath = getTempDir() / "axiom_pr_base_branch.json"
    writeFile(tmpPath, branchOutput)
    try:
      let bcData = extractJson(tmpPath)
      if not bcData.isNil:
        snapshot = bcData.loadSnapshotFromJson()
        snapshot.branch = baseRef
        return snapshot
    finally:
      try: removeFile(tmpPath)
      except: discard

  # Fallback: try fetching cached baseline from git
  let cacheCmd = "git show " & baseRef & ":" & CachedBaselinePath
  let (cacheOutput, cacheExit) = execCmdEx(cacheCmd)
  if cacheExit == 0 and cacheOutput.len > 0:
    let tmpPath = getTempDir() / "axiom_pr_base_cache.json"
    writeFile(tmpPath, cacheOutput)
    try:
      let bcData = extractJson(tmpPath)
      if not bcData.isNil:
        snapshot = bcData.loadSnapshotFromJson()
        snapshot.branch = baseRef
        return snapshot
    finally:
      try: removeFile(tmpPath)
      except: discard

  raise newException(CatchableError, &"Could not fetch baseline from {baseRef}")

# ═══════════════════════════════════════════════════════════════════════════════
# §6: Coverage Diff Calculation
# ═══════════════════════════════════════════════════════════════════════════════

func calcDelta(head: float; base: float): float =
  ## Calculate percentage point difference.
  result = head - base

func roundTo(pct: float; decimals: int = 1): float =
  ## Round to specified decimal places.
  let factor = pow(10.0, float(decimals))
  result = (pct * factor).round / factor

func formatStatus(delta: float): string =
  ## Determine status emoji based on coverage delta.
  if delta >= 0.5:
    ":white_check_mark:"   # Improvement
  elif delta < -0.5:
    ":x:"                   # Regression
  else:
    ":heavy_minus_sign:"   # Stable (within noise threshold)

func formatDelta(delta: float): string =
  ## Format delta with sign prefix.
  if delta >= 0:
    "+" & $roundTo(delta) & "%"
  else:
    "-" & $roundTo(abs(delta)) & "%"

proc computeDiffs(head: CoverageSnapshot; base: CoverageSnapshot): seq[CoverageDiff] =
  ## Compute coverage diffs across all metric types.
  result = @[]

  let lineDiff = head.lineCoveragePct.calcDelta(base.lineCoveragePct)
  result.add(CoverageDiff(target: "Line", basePct: base.lineCoveragePct, headPct: head.lineCoveragePct, delta: lineDiff))

  let branchDiff = head.branchCoveragePct.calcDelta(base.branchCoveragePct)
  result.add(CoverageDiff(target: "Branch", basePct: base.branchCoveragePct, headPct: head.branchCoveragePct, delta: branchDiff))

  let moduleDiff = head.moduleCoveragePct.calcDelta(base.moduleCoveragePct)
  result.add(CoverageDiff(target: "Module", basePct: base.moduleCoveragePct, headPct: head.moduleCoveragePct, delta: moduleDiff))

# ═══════════════════════════════════════════════════════════════════════════════
# §7: Comment Body Generation
# ═══════════════════════════════════════════════════════════════════════════════

proc truncate(s: string; maxLen: int): string =
  ## Truncate string to maxLen characters safely.
  if s.len <= maxLen:
    return s
  result = s[0 ..< maxLen]

proc generateCommentBody(diffs: seq[CoverageDiff]; head: CoverageSnapshot; base: CoverageSnapshot; prNumber: string): string =
  ## Generate the Markdown comment body for the PR comment.
  var sb = newStringOfCap(1024)

  sb.add("### :bar_chart: Test Coverage Report\n\n")
  sb.add(CommentTag & "\n\n")

  # Summary table
  sb.add("| Target | Base Coverage | Head Coverage | Delta | Status |\n")
  sb.add("| :--- | :--- | :--- | :--- | :--- |\n")

  for d in diffs:
    let status = d.delta.formatStatus()
    let deltaStr = d.delta.formatDelta()
    let baseFormatted = $roundTo(d.basePct) & "%"
    let headFormatted = $roundTo(d.headPct) & "%"
    let boldTarget = "**" & d.target & "**"
    sb.add(&"| {boldTarget} | {baseFormatted} | {headFormatted} | {deltaStr} | {status} |\n")

  sb.add("\n")

  # Build metadata
  sb.add("---\n\n")
  sb.add("*Generated by `pr_coverage_commenter` · Axiom Integrity Engine*\n")

  if head.branch.len > 0:
    sb.add(&"\n*Head branch: `{head.branch}` ({truncate(head.commitHash, 8)})*\n")
  if base.branch.len > 0:
    sb.add(&"*Base branch: `{base.branch}` ({truncate(base.commitHash, 8)})*\n")

  # Per-file breakdown (top 10 by coverage)
  let bcData = extractJson(BranchCoveragePath)
  if not bcData.isNil and bcData.kind == JObject:
    let files = bcData.getOrDefault("files")
    if not files.isNil and files.kind == JArray and files.len > 0:
      sb.add("\n")
      sb.add("### :file_folder: Top Files by Coverage\n\n")
      sb.add("| File | Branch Coverage |\n")
      sb.add("| :--- | :--- |\n")

      # Sort files by coverage descending
      var sortedFiles = files.toSeq().mapIt(it)
      sortedFiles.sort(proc(a, b: JsonNode): int =
        let aPct = safeFloat(a.getOrDefault("branchCoveragePct"))
        let bPct = safeFloat(b.getOrDefault("branchCoveragePct"))
        if aPct > bPct: -1
        elif aPct < bPct: 1
        else: 0
      )

      for i in 0 ..< min(10, sortedFiles.len):
        let fObj = sortedFiles[i]
        let fpath = fObj.getOrDefault("path").getStr("")
        let fpct = safeFloat(fObj.getOrDefault("branchCoveragePct"))
        sb.add(&"| `{fpath}` | {roundTo(fpct)}% |\n")

  return sb

# ═══════════════════════════════════════════════════════════════════════════════
# §8: GitHub REST API Integration
# ═══════════════════════════════════════════════════════════════════════════════

proc getGithubToken(): string =
  ## Get GitHub token from environment.
  let token = getEnv("GITHUB_TOKEN", "")
  if token.len == 0:
    raise newException(CatchableError, "GITHUB_TOKEN environment variable is not set")
  return token

proc getPrNumber(): Option[string] =
  ## Get PR number from environment. Returns none if not available.
  let prNum = getEnv("CIRCLE_PR_NUMBER", "")
  if prNum.len == 0:
    # Fallback: check other CI providers
    let ghprNum = getEnv("GITHUB_PULL_REQUEST_NUMBER", "")
    if ghprNum.len > 0:
      return some(ghprNum)
    return none(string)
  return some(prNum)

proc getGithubRepo(): string =
  ## Get repo identifier (owner/repo) from environment or git remote.
  let override = getEnv("GITHUB_REPO", "")
  if override.len > 0:
    return override
  let (owner, repo) = getRemoteOwnerAndRepo()
  return owner & "/" & repo

proc postPRComment(token: string; repo: string; prNumber: string; body: string): PrCommentResult =
  ## POST a comment to a GitHub PR via the REST API.
  ## Endpoint: POST /repos/{owner}/{repo}/issues/{number}/comments
  {.push raises: [].}
  let baseUrl = "https://api.github.com"
  let endpoint = &"/repos/{repo}/issues/{prNumber}/comments"
  let url = baseUrl & endpoint

  result.commentUrl = ""
  result.body = body
  result.success = false

  try:
    var client = newHttpClient(timeout = HttpTimeoutMs)
    try:
      client.headers["Authorization"] = "token " & token
      client.headers["Accept"] = "application/vnd.github.v3+json"
      client.headers["Content-Type"] = "application/json"
      client.headers["User-Agent"] = "Axiom-PR-Coverage-Bot/1.0"

      # Build request body
      var reqBody = newJObject()
      reqBody["body"] = %body
      let jsonStr = reqBody.pretty(indent = 0)

      echo "[pr-commenter] Posting to ", url
      echo "[pr-commenter] Body length: ", jsonStr.len, " bytes"

      let response = client.post(url, jsonStr)
      let statusCode = response.code

      if statusCode == Http201:
        # Created successfully
        let responseData = response.body
        let parsed = parseJson(responseData)
        result.commentUrl = parsed.getOrDefault("html_url").getStr("")
        result.success = true
        echo "[pr-commenter] Comment posted successfully: ", result.commentUrl
      elif statusCode == Http403:
        result.error = "API rate limit exceeded or insufficient permissions"
        echo "[pr-commenter] ERROR: Rate limited or auth failed (403)"
      elif statusCode == Http404:
        result.error = "PR not found or repository inaccessible"
        echo "[pr-commenter] ERROR: Not found (404)"
      elif statusCode == Http422:
        let errBody = truncate(response.body, 200)
        result.error = "Validation failed: " & errBody
        echo "[pr-commenter] ERROR: Validation failed (422)"
      else:
        let errBody = truncate(response.body, 200)
        result.error = &"HTTP {ord(statusCode)}: {errBody}"
        echo "[pr-commenter] ERROR: Unexpected status {ord(statusCode)}"

    except CatchableError as e:
      result.error = &"HTTP request failed: {e.msg}"
      echo "[pr-commenter] ERROR: ", e.msg
    except:
      result.error = "Unexpected error"
      echo "[pr-commenter] ERROR: Unexpected error"
    finally:
      client.close()
  except:
    discard
  {.pop.}

# ═══════════════════════════════════════════════════════════════════════════════
# §9: Main Orchestration
# ═══════════════════════════════════════════════════════════════════════════════

proc postPRComment*(headCoverage: CoverageSnapshot; baseCoverage: CoverageSnapshot): PrCommentResult =
  ## Public API: compute diffs and post PR comment.
  let prNumOpt = getPrNumber()
  if prNumOpt.isNone:
    echo "[pr-commenter] No PR number found — skipping comment (not a PR build?)"
    return PrCommentResult(success: false, error: "No PR number available")

  let prNumber = prNumOpt.get()
  let token = getGithubToken()
  let repo = getGithubRepo()
  let diffs = headCoverage.computeDiffs(baseCoverage)
  let body = diffs.generateCommentBody(headCoverage, baseCoverage, prNumber)
  result = token.postPRComment(repo, prNumber, body)

  if not result.success:
    echo "[pr-commenter] Failed to post comment: ", result.error
  else:
    echo "[pr-commenter] Coverage comment posted to PR #", prNumber

proc main() =
  ## Main entry point: load coverage data, compute diffs, post comment.
  echo "[pr-commenter] Starting..."

  # Check for dry-run mode
  let dryRun = "--dry-run" in commandLineParams()
  if dryRun:
    echo "[pr-commenter] Dry-run mode enabled — will not post to GitHub"

  # Detect project root
  let projectRoot = findRepoRoot()
  echo "[pr-commenter] Project root: ", projectRoot

  # Load head snapshot (current branch coverage)
  echo "[pr-commenter] Loading head coverage from ", BranchCoveragePath
  var headSnapshot: CoverageSnapshot
  try:
    headSnapshot = projectRoot.loadHeadSnapshot()
  except CatchableError as e:
    # Fail-closed since DEBT#461 (2026-09-07): the needs-gate + download-artifact
    # steps already hard-fail upstream when the artifact is missing — this WARN
    # path is defense in depth, so a missing snapshot must RED, not silently pass.
    echo "[pr-commenter] WARNING: No head coverage data (", e.msg, ") — skipping PR comment"
    quit(1)

  echo "[pr-commenter] Head coverage — Lines: ", roundTo(headSnapshot.lineCoveragePct),
    "%, Branch: ", roundTo(headSnapshot.branchCoveragePct),
    "%, Module: ", roundTo(headSnapshot.moduleCoveragePct), "%"

  # Determine base reference
  let baseRef = getEnv("BASE_REF", DefaultBaseRef)
  echo "[pr-commenter] Comparing against base branch: ", baseRef

  # Load base snapshot
  var baseSnapshot: CoverageSnapshot
  try:
    # Try cached baseline first
    baseSnapshot = projectRoot.loadCachedBaseline()
    echo "[pr-commenter] Loaded cached baseline"
  except CatchableError:
    try:
      # Fall back to git fetch
      baseSnapshot = baseRef.fetchBaseFromGit(projectRoot)
      echo "[pr-commenter] Fetched baseline from git"
    except CatchableError as e:
      echo "[pr-commenter] WARNING: Could not fetch baseline: ", e.msg
      echo "[pr-commenter] Using zero baseline (all deltas will be positive)"
      baseSnapshot = CoverageSnapshot(
        branch: baseRef,
        lineCoveragePct: 0.0,
        branchCoveragePct: 0.0,
        moduleCoveragePct: 0.0
      )

  echo "[pr-commenter] Base coverage — Lines: ", roundTo(baseSnapshot.lineCoveragePct),
    "%, Branch: ", roundTo(baseSnapshot.branchCoveragePct),
    "%, Module: ", roundTo(baseSnapshot.moduleCoveragePct), "%"

  # Compute diffs
  let diffs = headSnapshot.computeDiffs(baseSnapshot)
  echo "[pr-commenter] Coverage deltas:"
  for d in diffs:
    echo "  ", d.target, ": ", d.delta.formatDelta(),
      " (base: ", roundTo(d.basePct), "% → head: ", roundTo(d.headPct), "%)"

  # Skip posting if no PR number (local development)
  let prNumOpt = getPrNumber()
  if prNumOpt.isNone:
    echo "[pr-commenter] No PR number found — running in local/dev mode"
    echo "[pr-commenter] Set CIRCLE_PR_NUMBER or GITHUB_PULL_REQUEST_NUMBER to post comments"
    echo ""
    echo "[pr-commenter] Preview comment body:"
    echo "────────────────────────────────────────────────────────────────────"
    let prNumber = "0"
    let body = diffs.generateCommentBody(headSnapshot, baseSnapshot, prNumber)
    echo body
    echo "────────────────────────────────────────────────────────────────────"
    quit(0)

  # Post comment
  if dryRun:
    echo "[pr-commenter] Dry-run: would post the following comment:"
    echo "─".repeat(60)
    let body = diffs.generateCommentBody(headSnapshot, baseSnapshot, prNumOpt.get())
    echo body
    echo "─".repeat(60)
    quit(0)

  let token = getGithubToken()
  let repo = getGithubRepo()
  let prNumber = prNumOpt.get()

  var lastError = ""
  for retry in 0 ..< MaxRetries:
    if retry > 0:
      echo "[pr-commenter] Retry ", retry, "/", MaxRetries - 1
      sleep(2000)

    let body = diffs.generateCommentBody(headSnapshot, baseSnapshot, prNumber)
    let commentResult = token.postPRComment(repo, prNumber, body)

    if commentResult.success:
      echo "[pr-commenter] Done. Comment URL: ", commentResult.commentUrl
      quit(0)
    else:
      lastError = commentResult.error
      echo "[pr-commenter] Attempt ", retry + 1, " failed: ", lastError

  echo "[pr-commenter] FAILED after ", MaxRetries, " attempts: ", lastError
  quit(1)

when isMainModule:
  main()
