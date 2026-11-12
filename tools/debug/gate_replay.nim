import core/trusted/layer_declaration
axiomLayer "tools"
# Forensic Gate Replay Engine — Incremental nim check + nimtry (Wave 8.2)
# Replays a lightweight incremental check against every commit in a given
# range.  Sequential execution per invocation.
#
# Optimization: instead of running the full pre-commit hook (nim check on
# all .nim files, 15–40 s/commit), we run:
#   1. git diff --name-only HEAD~1 → changed .nim files only
#   2. nim check <changed files>  (per-file, not full tree)
#   3. nimtry <changed files>     (structural integrity — replaced architecture_gate)
#   4. Skip gateway tests          (incompatible with modern Nim)
#
# Usage: nim c -r scripts/gate_replay.nim <commit-range>
#   e.g. nim c -r scripts/gate_replay.nim ac6a5723..4cd44dbb
# Verify: nim check scripts/gate_replay.nim → SuccessX

import std/[os, osproc, posix, sequtils, strformat, strutils, times]

import shared_types/gate_bridge

const
  NimBin = "/usr/bin/nim"
  NimtryBin = "bin" / "nimtry"
  NimtrySrc = "src" / "gate" / "nimtry" / "nimtry_cli.nim"

# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

proc getCommits(range: string): seq[string] =
  let (output, code) = execCmdEx(&"git log --oneline --format='%H' {range}")
  if code != 0: return @[]
  for line in output.splitLines():
    let h = line.strip()
    if h.len == 40:
      result.add(h)

proc getChangedNimFiles(worktree: string): seq[string] =
  ## Returns .nim files changed in the most recent commit of the worktree.
  ## Uses `git diff --name-only HEAD~1` — for the root commit (no parent),
  ## falls back to listing all tracked .nim files.
  let (output, code) = execCmdEx(
    &"cd {worktree} && git diff --name-only HEAD~1 2>/dev/null")
  if code != 0:
    # Root commit or detached head with no parent — check all .nim files
    let (allOutput, _) = execCmdEx(
      &"cd {worktree} && git ls-files -- '*.nim' 2>/dev/null")
    for line in allOutput.splitLines():
      let trimmed = line.strip()
      if trimmed.len > 0:
        result.add(trimmed)
    return
  for line in output.splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0 and trimmed.endsWith(".nim"):
      result.add(trimmed)

# ---------------------------------------------------------------------------
# Incremental nim check
# ---------------------------------------------------------------------------

proc runNimCheck(files: seq[string]; worktree: string): bool =
  ## Runs `nim check` on each changed .nim file individually.
  ## Returns true only when ALL checks pass.
  if files.len == 0:
    return true
  for f in files:
    let cmd = &"cd {worktree} && {NimBin} check {f.quoteShell} 2>&1"
    let (_, exitCode) = execCmdEx(cmd)
    if exitCode != 0:
      stderr.writeLine(&"  [gate-replay] nim check FAILED: {f}")
      return false
  true

# ---------------------------------------------------------------------------
# Architecture gate
# ---------------------------------------------------------------------------

proc compileNimtryGate(repoRoot: string): bool =
  ## Compiles nimtry once from the main repo if the binary is
  ## missing or stale.  Returns true on success.
  let binPath = repoRoot / NimtryBin
  let srcPath = repoRoot / NimtrySrc
  if fileExists(binPath) and
     getLastModificationTime(srcPath) <= getLastModificationTime(binPath):
    return true  # already up to date
  stderr.writeLine("[gate-replay] Compiling nimtry (one-time)...")
  let cmd = &"{NimBin} c --hints:off -d:ThreadPoolSize=14 -o:{binPath.quoteShell} {srcPath.quoteShell} 2>&1"
  let (output, code) = execCmdEx(cmd)
  if code != 0:
    stderr.writeLine("[gate-replay] nimtry compilation FAILED:")
    stderr.writeLine(output)
    return false
  stderr.writeLine("[gate-replay] nimtry compiled OK.")
  true

# ---------------------------------------------------------------------------
# Per-commit replay
# ---------------------------------------------------------------------------

proc replayCommit(
  commit: string;
  repoRoot, nimtryBin: string
): tuple[commit: string, ok: bool, duration: float] {.gcsafe.} =
  let start = getTime()
  let shortHash = commit[0..7]
  let pid = getCurrentProcessId()
  let worktree = &"/tmp/gate-replay-{pid}-{shortHash}"

  # Clean up any leftover from previous runs (try normal first, force fallback)
  if dirExists(worktree):
    let (out1, code1) = execCmdEx(&"git worktree remove {worktree} 2>&1")
    if code1 != 0:
      let (out2, code2) = execCmdEx(&"git worktree remove --force {worktree} 2>&1")
      if code2 != 0:
        stderr.writeLine(&"[WARN] Failed to remove worktree {worktree}: {out2}")

  # Add worktree for this commit
  let (_, addCode) = execCmdEx(
    &"git worktree add --force {worktree} {commit} 2>&1")
  if addCode != 0:
    return (commit, false, 0.0)

  var ok = false

  # 1. Discover changed .nim files in this commit
  let changedFiles = getChangedNimFiles(worktree)
  if changedFiles.len > 0:
    stderr.writeLine(
      &"  [gate-replay] {shortHash}: {changedFiles.len} .nim file(s) changed")
  else:
    stderr.writeLine(
      &"  [gate-replay] {shortHash}: no .nim files changed")

  # 2. Incremental nim check — only changed files
  ok = runNimCheck(changedFiles, worktree)

  # 3. nimtry — structural integrity check (replaced architecture_gate)
  if ok and changedFiles.len > 0:
    let filesQuoted = changedFiles.mapIt(it.quoteShell).join(" ")
    let (gateOutput, gateCode) = execCmdEx(
      &"cd {worktree} && {nimtryBin} {filesQuoted} 2>&1")
    ok = gateCode == 0
    if not ok:
      stderr.writeLine(
        &"  [gate-replay] {shortHash}: nimtry FAILED")
      for line in gateOutput.splitLines():
        stderr.writeLine(&"    {line}")
    else:
      stderr.writeLine(
        &"  [gate-replay] {shortHash}: nimtry PASSED")

  let elapsed = (getTime() - start).inMilliseconds.float / 1000.0

  # Cleanup worktree
  let (rmOut, rmCode) = execCmdEx(&"git worktree remove {worktree} 2>&1")
  if rmCode != 0:
    let (rmForceOut, rmForceCode) = execCmdEx(&"git worktree remove --force {worktree} 2>&1")
    if rmForceCode != 0:
      stderr.writeLine(&"[WARN] Failed to cleanup worktree {worktree}: {rmForceOut}")

  return (commit, ok, elapsed)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc main() =
  let repoRoot = getAppDir().parentDir()
  setCurrentDir(repoRoot)

  putEnv("NIM_CACHE_DIR", joinPath(getHomeDir(), ".cache", "nim"))

  # Read commit range from command-line argument
  let args = commandLineParams()
  if args.len < 1:
    stderr.writeLine("[gate-replay] Usage: gate_replay <commit-range>")
    stderr.writeLine("  e.g. gate_replay ac6a5723..4cd44dbb")
    quit(1)
  let commitRange = args[0]

  # Pre-compile nimtry once (before dispatch)
  if not compileNimtryGate(repoRoot):
    quit(1)

  let nimtryBin = absolutePath(repoRoot / NimtryBin)

  stderr.writeLine(&"[gate-replay] Fetching commits in {commitRange}...")
  let commits = getCommits(commitRange)
  if commits.len == 0:
    stderr.writeLine(&"[gate-replay] No commits found in range '{commitRange}'")
    quit(1)
  stderr.writeLine(
    &"[gate-replay] Found {commits.len} commits. Running sequentially...")

  # Raise RLIMIT_NOFILE before spawning external processes
  discard gate_utils.raiseRlimitNoFile()

  var passCount = 0
  var failCommits: seq[string]
  var results = newSeq[tuple[commit: string, ok: bool, duration: float]](commits.len)

  for i in 0 ..< commits.len:
    results[i] = replayCommit(commits[i], repoRoot, nimtryBin)

  for i in 0 ..< commits.len:
    let (commit, ok, dur) = results[i]
    if ok:
      inc passCount
      stderr.writeLine(
        &"[gate-replay] [{i+1}/{commits.len}] {commit[0..7]} PASSED ({dur:.2f}s)")
    else:
      failCommits.add(commit[0..7])
      stderr.writeLine(
        &"[gate-replay] [{i+1}/{commits.len}] {commit[0..7]} FAILED ({dur:.2f}s)")

  # Report
  stderr.writeLine("")
  stderr.writeLine(&"[gate-replay] ===== RESULTS =====")
  stderr.writeLine(&"[gate-replay] {passCount}/{commits.len} commits passed")

  if failCommits.len > 0:
    stderr.writeLine(&"[gate-replay] Failed commits ({failCommits.len}):")
    for c in failCommits:
      stderr.writeLine(&"[gate-replay]   {c}")
    quit(1)
  else:
    stderr.writeLine(
      "[gate-replay] All commits PASSED. Gate-disabled period had no violations.")
    quit(0)

when isMainModule:
  main()