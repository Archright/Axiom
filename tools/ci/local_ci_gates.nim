## local_ci_gates.nim — Local Exact Gate CLI Tool
##
## Runs a CI gate locally with the exact same semantics as GitHub Actions CI,
## so a developer can get a deterministic PASS/FAIL without pushing and waiting
## for remote CI.
##
## Usage:
##   local-ci-gates --ref <git-ref | pr N> --gate <gate> --substrate <full|shallow>
##
##   --ref          Git refname or full SHA. Resolves to an immutable SHA.
##   --pr N         Resolve PR N to its CI merge commit SHA via gh api
##                  (fallback: git fetch origin pull/N/merge + rev-parse FETCH_HEAD).
##   --gate         Gate runner to execute. Default: verification-auditor.
##   --substrate    full = detached worktree at immutable ref (clean parity).
##                  shallow = depth-1 clone + fetch refs/pull/N/merge
##                  (reproduces actions/checkout@v4 default). Default: full.
##
## Exit codes: 0 = PASS, 1 = FAIL, 2 = tool error.
##
## Determinism contract:
##   - Always fresh execution — never reuses cached PASS/FAIL from gate_cache.
##   - CI env vars (AXIOM_CI=1 AXIOM_CI_PRESERVE_CACHE=1) are set verbatim.
##   - CI argv is passed verbatim matching the Makefile ci-gates target.
##   - The detached worktree is cleaned up on exit.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, strutils, times, monotimes]

# ═══════════════════════════════════════════════════════════════════════════
# §0: Compile-Time Toolchain Lock
# ═══════════════════════════════════════════════════════════════════════════

static:
  when NimMajor != 2 or NimMinor != 2:
    {.error: "local-ci-gates requires Nim v2.2.x".}

# ═══════════════════════════════════════════════════════════════════════════
# §1: CLI Arguments
# ═══════════════════════════════════════════════════════════════════════════

type
  CliArgs = object
    refName*: string      # git refname or SHA
    pr*: int              # PR number (0 = not specified)
    gate*: string         # gate runner name
    substrate*: string    # "full" or "shallow"

proc usage(): string =
  """local-ci-gates — Run a CI gate locally with exact CI semantics.

Usage:
  local-ci-gates --ref <git-ref | pr N> [--gate <gate>] [--substrate <full|shallow>]

Options:
  --ref <ref>      Git refname or full SHA (resolves to immutable SHA)
  --pr <N>         PR number — resolves to CI merge commit SHA
  --gate <gate>    Gate runner to execute (default: verification-auditor)
  --substrate <full|shallow>
                   full = detached worktree at ref (clean parity, default)
                   shallow = depth-1 clone + pull/N/merge fetch (reproduces CI)

Examples:
  local-ci-gates --ref main --gate verification-auditor --substrate full
  local-ci-gates --pr 28 --gate verification-auditor --substrate shallow
  local-ci-gates --ref abc123def --gate verification-auditor

Exit codes:
  0 = gate PASS
  1 = gate FAIL
  2 = tool error
"""

proc parseArgs(): CliArgs =
  let args = commandLineParams()
  var i = 0
  while i < args.len:
    case args[i]
    of "--ref":
      inc i
      if i >= args.len: quit("Error: --ref requires a value", 2)
      result.refName = args[i]
    of "--pr":
      inc i
      if i >= args.len: quit("Error: --pr requires a value", 2)
      try:
        result.pr = parseInt(args[i])
      except ValueError:
        quit("Error: --pr requires an integer, got: " & args[i], 2)
    of "--gate":
      inc i
      if i >= args.len: quit("Error: --gate requires a value", 2)
      result.gate = args[i]
    of "--substrate":
      inc i
      if i >= args.len: quit("Error: --substrate requires a value", 2)
      result.substrate = args[i]
    of "--help", "-h":
      echo usage()
      quit(0)
    else:
      quit("Error: unknown argument: " & args[i] & "\n" & usage(), 2)
    inc i

  # Defaults
  if result.gate.len == 0:
    result.gate = "verification-auditor"
  if result.substrate.len == 0:
    result.substrate = "full"
  if result.substrate notin @["full", "shallow"]:
    quit("Error: --substrate must be 'full' or 'shallow', got: " &
         result.substrate, 2)

  # --ref or --pr required
  if result.refName.len == 0 and result.pr == 0:
    quit("Error: --ref <git-ref> or --pr <N> is required\n" & usage(), 2)

# ═══════════════════════════════════════════════════════════════════════════
# §2: Git Operations
# ═══════════════════════════════════════════════════════════════════════════

proc runGit(args: seq[string]; workingDir: string = ""): (string, int) =
  ## Run a git command and return (stdout, exitCode).
  let (outp, exitCode) = execCmdEx("git " & args.join(" "),
    options = {poStdErrToStdOut},
    workingDir = workingDir)
  result = (outp.strip(), exitCode)

proc resolveRefToSha(refName: string): string =
  ## Resolve a git refname or SHA to a full 40-char SHA.
  let (sha, exitCode) = runGit(@["rev-parse", refName])
  if exitCode != 0:
    quit("Error: cannot resolve ref '" & refName & "' to a SHA", 2)
  if sha.len != 40:
    quit("Error: resolved '" & refName & "' to invalid SHA: " & sha, 2)
  result = sha

proc resolvePrToSha(prNumber: int): string =
  ## Resolve PR N to its CI merge commit SHA.
  ## Strategy 1: gh api (preferred, matches CI semantics).
  ## Strategy 2: git fetch origin pull/N/merge + rev-parse FETCH_HEAD.
  ##
  ## M7 no-fallback credential guard (docs/spec/diagnostic_execution_delegation.md
  ## §4): AXIOM_DIAG_TOKEN (explicitly provisioned) is injected as GH_TOKEN for
  ## the gh api call; AXIOM_DIAG_STRICT=1 refuses the `gh auth` fallback
  ## (operator PAT) — fail closed. The credential source is ALWAYS printed.
  block:
    let explicit = getEnv("AXIOM_DIAG_TOKEN").strip()
    if explicit.len > 0:
      echo "  credential-source: AXIOM_DIAG_TOKEN"
      putEnv("GH_TOKEN", explicit)
    elif getEnv("AXIOM_DIAG_STRICT") == "1":
      echo "local-ci-gates: FAIL — AXIOM_DIAG_TOKEN absent and AXIOM_DIAG_STRICT=1: `gh` credentials (operator PAT) are refused for diagnostic execution (M7 no-fallback — docs/spec/diagnostic_execution_delegation.md §4)"
      quit(2)
    else:
      echo "  credential-source: gh-auth (fallback — AXIOM_DIAG_STRICT not set; not a diagnostic credential)"
  let (apiOut, apiExit) = execCmdEx(
    "gh api repos/Archright/Axiom/pulls/" & $prNumber &
    " --jq .merge_commit_sha",
    options = {poStdErrToStdOut})
  if apiExit == 0 and apiOut.strip().len == 40:
    return apiOut.strip()

  # Fallback: git fetch + rev-parse
  let fetchTarget = "pull/" & $prNumber & "/merge"
  let (fetchOut, fetchExit) = runGit(@["fetch", "origin", fetchTarget])
  if fetchExit != 0:
    quit("Error: cannot fetch PR " & $prNumber & " from origin", 2)
  let (sha, shaExit) = runGit(@["rev-parse", "FETCH_HEAD"])
  if shaExit != 0:
    quit("Error: cannot resolve FETCH_HEAD after PR fetch", 2)
  result = sha

# ═══════════════════════════════════════════════════════════════════════════
# §3: Worktree Management
# ═══════════════════════════════════════════════════════════════════════════

proc createDetachedWorktree(sha: string): string =
  ## Create a fresh detached worktree at the given SHA under a temp dir.
  ## Returns the path to the worktree directory.
  let tmpBase = getEnv("TMPDIR", "/tmp")
  let worktreeDir = tmpBase / "axiom-local-gate-" & $getMonoTime().ticks()
  createDir(worktreeDir)

  let (outp, exitCode) = runGit(
    @["worktree", "add", "--detach", worktreeDir, sha])
  if exitCode != 0:
    quit("Error: cannot create detached worktree at " & sha & ": " & outp, 2)

  result = worktreeDir

proc removeDetachedWorktree(path: string) =
  ## Remove a detached worktree and its entry from git's worktree list.
  if dirExists(path):
    discard execCmdEx("git worktree remove --force " & path,
      options = {poStdErrToStdOut})
    try:
      removeDir(path)
    except OSError:
      discard

proc createShallowClone(prNumber: int): string =
  ## Create a shallow clone (depth-1) and fetch refs/pull/N/merge.
  ## This reproduces actions/checkout@v4 default behavior.
  ## Returns the path to the shallow clone directory.
  let tmpBase = getEnv("TMPDIR", "/tmp")
  let cloneDir = tmpBase / "axiom-local-gate-shallow-" & $getMonoTime().ticks()

  # Get the origin URL for cloning
  let (originUrl, originExit) = runGit(@["remote", "get-url", "origin"])
  if originExit != 0 or originUrl.len == 0:
    quit("Error: cannot determine origin remote URL for shallow clone", 2)

  # Step 1: Clone with depth=1 from the origin URL
  let (cloneOut, cloneExit) = execCmdEx(
    "git clone --depth=1 " & originUrl & " " & cloneDir,
    options = {poStdErrToStdOut})
  if cloneExit != 0:
    quit("Error: cannot create shallow clone: " & cloneOut, 2)

  # Step 2: Fetch the PR merge ref
  let fetchTarget = "pull/" & $prNumber & "/merge"
  let (fetchOut, fetchExit) = execCmdEx(
    "git fetch origin " & fetchTarget,
    options = {poStdErrToStdOut},
    workingDir = cloneDir)
  if fetchExit != 0:
    quit("Error: cannot fetch " & fetchTarget & ": " & fetchOut, 2)

  # Step 3: Check out FETCH_HEAD (the PR merge commit)
  let (checkoutOut, checkoutExit) = runGit(
    @["checkout", "FETCH_HEAD"],
    workingDir = cloneDir)
  if checkoutExit != 0:
    quit("Error: cannot checkout FETCH_HEAD: " & checkoutOut, 2)

  result = cloneDir

proc removeShallowClone(path: string) =
  ## Remove a shallow clone directory.
  if dirExists(path):
    try:
      removeDir(path)
    except OSError:
      discard

# ═══════════════════════════════════════════════════════════════════════════
# §4: Gate Execution
# ═══════════════════════════════════════════════════════════════════════════

proc gateNameToFilename(gateName: string): string =
  ## Convert gate display name (hyphens) to runner filename (underscores).
  ## e.g. "verification-auditor" → "verification_auditor"
  result = gateName.replace("-", "_")

proc buildGateBinary(repoRoot: string; gateName: string): bool =
  ## Ensure the gate runner source exists. Returns true if source is present.
  let runnerName = gateNameToFilename(gateName)
  let sourcePath = repoRoot / "src" / "gate" / "runners" / runnerName & "_gate.nim"
  if fileExists(sourcePath):
    return true
  # Try without _gate suffix
  let altPath = repoRoot / "src" / "gate" / "runners" / runnerName & ".nim"
  if fileExists(altPath):
    return true
  echo "Error: gate source not found for '" & gateName & "'"
  echo "  tried: " & sourcePath
  echo "  tried: " & altPath
  return false

proc buildGateCmd(gateName: string; repoRoot: string): string =
  ## Build the exact command string matching the Makefile ci-gates target.
  ## The gate runner always receives "full" as the mode argument,
  ## matching the Makefile ci-gates target exactly.
  let runnerName = gateNameToFilename(gateName)
  case gateName
  of "verification-auditor":
    result = "nim c --hints:off -r src/gate/runners/" & runnerName &
      "_gate.nim " & repoRoot & " full 2"
  of "external-cli-smoke":
    result = "nim c --hints:off -r src/gate/runners/" & runnerName & ".nim"
  of "readiness-start":
    result = "nim c --hints:off -r src/gate/runners/" & runnerName &
      "_gate.nim " & repoRoot & " full 2"
  else:
    result = "nim c --hints:off -r src/gate/runners/" & runnerName &
      "_gate.nim " & repoRoot & " full 2"

proc runGate(repoRoot: string; gateName: string): (int, string) =
  ## Run the gate in the substrate directory with CI env vars.
  ## Returns (exitCode, combinedOutput).
  ##
  ## CI env vars are set via putEnv so the subprocess inherits them.
  ## This bypasses gate_cache entirely — we run the gate runner directly,
  ## not through gate_hook which is the only consumer of gate_cache.
  let cmd = buildGateCmd(gateName, repoRoot)

  # Set CI environment vars verbatim (matching Makefile ci-gates target).
  # These override any existing values in the parent process env.
  putEnv("AXIOM_CI", "1")
  putEnv("AXIOM_CI_PRESERVE_CACHE", "1")

  let (outp, exitCode) = execCmdEx(cmd,
    options = {poStdErrToStdOut})

  result = (exitCode, outp)

# ═══════════════════════════════════════════════════════════════════════════
# §5: Result Reporting
# ═══════════════════════════════════════════════════════════════════════════

proc extractObservables(output: string): (string, string) =
  ## Extract key observable values from gate output.
  ## Returns (domainDelta, declaredTransition) or ("", "") if not found.
  var domainDelta = ""
  var declaredTransition = ""

  for line in output.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("domain:") or stripped.startsWith("observed domain"):
      domainDelta = stripped
    if stripped.startsWith("declared") or stripped.startsWith("transition"):
      declaredTransition = stripped
    if stripped.startsWith("axiom-transition:"):
      declaredTransition = stripped

  result = (domainDelta, declaredTransition)

proc printResult(exitCode: int; gateName: string; substrate: string;
                 observables: (string, string); durationMs: int64) =
  echo ""
  echo "══════════════════════════════════════════════"
  echo "  local-ci-gates result"
  echo "══════════════════════════════════════════════"
  echo "  gate:       " & gateName
  echo "  substrate:  " & substrate
  echo "  exit code:  " & $exitCode
  echo "  duration:   " & $durationMs & "ms"
  if observables[0].len > 0:
    echo "  domain delta: " & observables[0]
  if observables[1].len > 0:
    echo "  transition:   " & observables[1]
  echo "══════════════════════════════════════════════"

# ═══════════════════════════════════════════════════════════════════════════
# §6: Main
# ═══════════════════════════════════════════════════════════════════════════

proc main() =
  let args = parseArgs()

  echo "=== local-ci-gates ==="
  echo "  gate:       " & args.gate
  echo "  substrate:  " & args.substrate

  # Step 1: Resolve immutable ref to SHA
  var sha: string
  if args.pr > 0:
    echo "  resolving PR " & $args.pr & " → merge commit SHA ..."
    sha = resolvePrToSha(args.pr)
  else:
    echo "  resolving ref '" & args.refName & "' → SHA ..."
    sha = resolveRefToSha(args.refName)
  echo "  immutable SHA: " & sha

  # Step 2: Create fresh substrate (worktree or shallow clone)
  var substrateDir: string
  if args.substrate == "shallow":
    if args.pr == 0:
      quit("Error: --substrate shallow requires --pr <N>", 2)
    echo "  creating shallow clone (depth=1) for PR " & $args.pr & " ..."
    substrateDir = createShallowClone(args.pr)
    echo "  shallow clone: " & substrateDir
    defer: removeShallowClone(substrateDir)
  else:
    echo "  creating detached worktree at " & sha & " ..."
    substrateDir = createDetachedWorktree(sha)
    echo "  worktree: " & substrateDir
    defer: removeDetachedWorktree(substrateDir)

  # Step 3: Verify gate source exists
  if not buildGateBinary(substrateDir, args.gate):
    quit("Error: gate binary/source preparation failed", 2)

  # Step 4: Change to substrate directory for gate execution
  try:
    setCurrentDir(substrateDir)
  except OSError:
    quit("Error: cannot chdir to substrate " & substrateDir, 2)

  # Step 5: Run gate with CI env + CI argv (always fresh — no cache reuse)
  echo "  running gate (CI env, fresh execution) ..."
  let startTime = getMonoTime()
  let (exitCode, output) = runGate(substrateDir, args.gate)
  let durationMs = (getMonoTime() - startTime).inMilliseconds

  # Step 6: Extract and print observables
  let observables = extractObservables(output)
  printResult(exitCode, args.gate, args.substrate, observables, durationMs)

  # Step 6: Print gate output (last 30 lines)
  if output.len > 0:
    echo ""
    echo "--- gate output ---"
    let lines = output.splitLines()
    let startLine = max(0, lines.len - 30)
    for i in startLine ..< lines.len:
      echo lines[i]
    if lines.len > 30:
      echo "(showing last 30 of " & $lines.len & " lines)"

  # Step 7: Exit with gate's exit code
  quit(exitCode)

when isMainModule:
  main()
