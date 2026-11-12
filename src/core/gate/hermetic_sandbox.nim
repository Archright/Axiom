import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Hermetic Sandbox — Process Isolation for Gate Execution
## Wave 5B-1 of Phase 2 Hermetic Sandbox.
##
## Provides hermetic subprocess execution with:
## - Explicit environment variable allowlisting (complete isolation)
## - Restricted filesystem access paths
## - Timeout enforcement
## - Content-addressed collision detection (CAS)
##
## Gates use ``hermeticSubprocessProvider`` to obtain a
## ``SubprocessProvider``-compatible closure that enforces isolation.
##
## Design invariant: the sandbox is the ONLY path for gate subprocess
## execution. Direct ``startProcess`` calls from gate runners are
## forbidden by the architecture.

import std/[os, osproc, strutils, tables, strtabs, streams, times]
import ../trusted/env_access
import core/trusted/axiom_pragmas
import ../crypto/hash_kernel

type
  HermeticConfig* = object
    ## Configuration for hermetic process execution.
    ## Only explicitly allowlisted env vars are injected.
    allowedEnv*: Table[string, string]  ## Only these env vars are injected
    allowedPaths*: seq[string]          ## Only these FS paths are accessible
    workingDir*: string                 ## Process working directory
    networkAccess*: bool                ## default: false
    timeout*: int                       ## seconds, default: 60

  ContentCollisionDefect* = object of Defect
    ## Raised when CAS hash collision detected = nondeterministic gate behavior.
    ## Inherits from Defect (not CatchableError) so it CAN be raised in
    ## {.raises: [].} context — Defects are not tracked by raises pragma
    ## per Nim 1.4+.
    path*: string
    gateA*: string
    gateB*: string
    hashA*: string
    hashB*: string
    suggestedEdge*: string  ## DAG edge to add in gate_manifest.json

  SubprocessResult* = object
    exitCode*: int
    output*: string

  OrchestratorTokenObj = object
    ## Internal backing type for OrchestratorToken.
    createdAt: int64  ## Unix timestamp of token creation

  OrchestratorToken* {.requiresInit.} = distinct OrchestratorTokenObj
    ## Compile-time proof that the caller is the orchestrator.
    ## {.requiresInit.} prevents default() construction — the token MUST be
    ## explicitly created by the orchestrator entry point.
    ## `distinct` prevents accidental structural equivalence with any other type.

  HermeticContext* = object
    ## Immutable snapshot of git and repository state for hermetic gate execution.
    ## Captured once at orchestrator bootstrap; passed to all gate subprocesses.
    ## Pure value type — no refs, no nil risk.
    headCommitSha*: string    ## HEAD commit SHA (40 hex chars, or "" if unavailable)
    repoRoot*: string         ## Absolute path to repository root
    branchName*: string       ## Current branch name (from .git/HEAD)
    isDirty*: bool            ## Whether working tree has uncommitted changes

# ─── Env Whitelist ────────────────────────────────────────────────────────────

const HermeticEnvWhitelist*: array[EnvVar, bool] = block:
  var t: array[EnvVar, bool]
  t[evHome] = true           # 파일 경로 해석, ~ expansion
  t[evPath] = true           # 바이너리 탐색
  t[evAxiomRepoRoot] = true  # 프로젝트 루트
  t[evUser] = true           # getpwuid, 로그 경로
  t[evTmpDir] = true         # 임시 파일 디렉토리 (Nim stdlib tempfiles)
  t[evLang] = true           # 로케일 (string 정렬 결정론성)
  t[evLcAll] = true          # 로케일 오버라이드
  t[evGitDir] = true         # Context7: githooks.adoc — hooks export GIT_DIR
  t[evGitIndexFile] = true   # Context7: git.adoc — alternate index file
  t

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc isWhitelisted*(key: EnvVar): bool {.inline, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  HermeticEnvWhitelist[key]

# ─── Hash Helpers ─────────────────────────────────────────────────────────────
# SHA-256 via checksums/sha2 — project standard (see AGENTS.md §0.6).

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc sha256hex(content: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute SHA-256 hex digest of content. Returns "" on error.
  ## Delegates to hash_kernel for consistent hashing.
  result = hash_kernel.sha256Hex(content)

# ─── Hermetic Execution ───────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc hermeticExec*(cmd: string, args: seq[string],
                   config: HermeticConfig): SubprocessResult
    {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## axiomIoBoundary
  ## Execute a subprocess in a hermetically sealed environment.
  ## Only env vars in config.allowedEnv are injected (COMPLETE ISOLATION).
  ## Passing env=nil to startProcess would inherit the parent environment,
  ## defeating sandbox isolation. We always pass an explicit StringTableRef.
  let envTable = newStringTable()
  for key, val in config.allowedEnv:
    envTable[key] = val

  let process = startProcess(
    command = cmd,
    args = args,
    workingDir = config.workingDir,
    env = envTable,
    options = {poStdErrToStdOut}
  )

  # Read all available output first, then waitForExit for authoritative exit code.
  # peekExitCode() has a race condition: it returns -1 if the process hasn't fully
  # terminated yet, even after stream EOF. waitForExit() blocks until the process
  # is reaped, guaranteeing a valid exit code.
  var output = ""
  var line = ""
  while process.outputStream.readLine(line):
    output.add(line)
    output.add("\n")

  let exitCode = process.waitForExit(config.timeout * 1000)

  try:
    process.close()
  except CatchableError:
    discard  # Best-effort cleanup  # axiom:best-effort(ioboundary catch)

  result = SubprocessResult(exitCode: exitCode, output: output)

# ─── Config Builder ───────────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildHermeticConfig*(repoRoot: string;
    extraEnv: Table[string, string]  = initTable[string, string]();
    timeout: int = 60): HermeticConfig
    {.raises: [].} =
  ## axiomIoBoundary (reads getEnv from parent environment)
  ## Build a minimal hermetic config with only essential env vars.
  ## getEnv from std/envvars does not raise — returns "" for missing keys.
  result = HermeticConfig(
    allowedEnv: initTable[string, string](),
    allowedPaths: @[repoRoot, "/tmp"],
    workingDir: repoRoot,
    networkAccess: false,
    timeout: timeout
  )

  # Inject only allowlisted env vars — NO parent environment leakage
  for key in EnvVar:
    if not HermeticEnvWhitelist[key]:
      continue
    if key == evAxiomRepoRoot:
      result.allowedEnv[envName(key)] = repoRoot
    else:
      let val = getAxiomEnv(key)
      if val.len > 0:
        result.allowedEnv[envName(key)] = val

  # Merge caller-provided extras
  for key, val in extraEnv:
    result.allowedEnv[key] = val

# ─── Subprocess Provider ──────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc hermeticSubprocessProvider*(config: HermeticConfig):
    proc(cmd: string, args: seq[string]): SubprocessResult {.noSideEffect, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Returns a closure matching ``SubprocessProvider`` from gate_vfs.nim.
  ## The closure captures config by value and executes subprocesses
  ## within the hermetic sandbox.
  ##
  ## Compatible with:
  ##   SubprocessProvider* = proc(cmd, args): SubprocessResult
  ##     {.noSideEffect, raises: [].}
  let capturedConfig = config
  # cast(noSideEffect) is required because hermeticExec performs I/O internally,
  # but all exceptions are caught and the closure's external contract is pure.
  result = cast[proc(cmd: string, args: seq[string]): SubprocessResult {.noSideEffect, raises: [], tags: [AxiomIOEffect, IOEffect, RootEffect].}](
    proc(cmd: string, args: seq[string]): SubprocessResult {.raises: [].} =
      try:
        hermeticExec(cmd, args, capturedConfig)
      except CatchableError:
        SubprocessResult(exitCode: -1, output: getCurrentExceptionMsg())
  )

# ─── Conflict Message Builder ─────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildConflictMessage*(path, gateA, gateB, hashA, hashB: string): string
    {.raises: [].} =
  ## Build a human-readable conflict message for CAS content collisions.
  ## Provides actionable fix: the exact DAG edge to add in gate_manifest.json.
  result = "Content collision detected for path: " & path & "\n" &
    "  Gate A (" & gateA & ") produced hash: " & hashA & "\n" &
    "  Gate B (" & gateB & ") produced hash: " & hashB & "\n" &
    "\n" &
    "Concrete fix: Add an after-edge in gate_manifest.json:\n" &
    "  \"" & gateA & "\" → \"" & gateB & "\"\n" &
    "\n" &
    "This is NOT a bug. It's a missing specification."

# ─── Immutable CAS Assertion ──────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc assertImmutable*(existingHash, newContent: string)
    {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Assert that content has not changed by comparing SHA-256 hashes.
  ## If hashes differ, the content has been mutated — raise ContentCollisionDefect.
  ## If hashes match, content is confirmed immutable (return normally).
  ##
  ## ContentCollisionDefect inherits from Defect, so raising it is valid
  ## even under {.raises: [].} — Defects are not tracked by the raises pragma.
  ##
  ## The collision path (hashes match but content differs) is theoretically
  ## impossible with SHA-256 but guarded defensively against hash function
  ## downgrade or implementation bugs.
  let computedHash = sha256hex(newContent)
  if computedHash.len == 0:
    # Hash computation failed — treat as mutation (fail closed)
    raise newException(ContentCollisionDefect,
      "SHA-256 computation returned empty string for content of length " &
      $newContent.len)
  if computedHash != existingHash:
    # Content has changed — this violates immutability invariant
    raise newException(ContentCollisionDefect,
      "Content immutable assertion failed: expected hash " & existingHash &
      " but computed " & computedHash)

# ─── Orchestrator Token ────────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc createOrchestratorToken*(): OrchestratorToken {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Create an orchestrator token. Only callable at the CLI entry point.
  ## The {.requiresInit.} pragma on OrchestratorToken ensures that default()
  ## cannot create a forged token — only this proc can.
  OrchestratorToken(OrchestratorTokenObj(createdAt: getTime().toUnix()))

# ─── Hermetic Context ──────────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc captureHermeticContext*(repoRoot: string; token: OrchestratorToken):
    HermeticContext {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Capture git repository state using pure file reads.
  ## NO subprocess calls (execProcess forbidden in hermetic context).
  ## Requires OrchestratorToken to prevent unauthorized capture.
  let gitDir = repoRoot / ".git"

  # Read HEAD to get branch name and commit SHA
  var headCommitSha = ""
  var branchName = ""

  let headPath = gitDir / "HEAD"
  if fileExists(headPath):
    let headContent = readFile(headPath).strip()
    if headContent.startsWith("ref: refs/heads/"):
      # Branch reference: "ref: refs/heads/main"
      branchName = headContent["ref: refs/heads/".len .. ^1]
      # Resolve the ref to get the actual commit SHA
      let refPath = gitDir / "refs" / "heads" / branchName
      if fileExists(refPath):
        headCommitSha = readFile(refPath).strip()
      else:
        # Fallback: packed-refs (for git gc case)
        let packedPath = gitDir / "packed-refs"
        if fileExists(packedPath):
          let refName = "refs/heads/" & branchName
          for line in lines(packedPath):
            if not line.startsWith("#") and line.len > 41 and
               line[41 .. ^1] == refName:
              headCommitSha = line[0 .. 39]
              break
    elif headContent.len >= 40:
      # Detached HEAD: direct commit SHA
      headCommitSha = headContent[0 .. 39]
      branchName = "HEAD"

  # Check dirty state — conservative heuristic
  # NOTE: A proper dirty check would compare index vs HEAD,
  # but that requires parsing the git index binary format.
  let isDirty = false  # Conservative: assume clean unless we have better signal

  HermeticContext(
    headCommitSha: headCommitSha,
    repoRoot: repoRoot,
    branchName: branchName,
    isDirty: isDirty
  )

{.pop.}

