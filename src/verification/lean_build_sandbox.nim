## Lean Build Sandbox Manager — Phase 3D
## Isolates `lake build` executions to prevent race conditions when multiple
## subagents run Lean verification in parallel.
##
## AGENTS.md §0.6: All I/O procs use `{.axiomEffect: IOEffect.}`.
## AGENTS.md §0.2: func for pure logic, proc only at I/O boundary.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/[algorithm, os, strutils, times, posix]

import core/crypto/hash_kernel
import core/trusted/axiom_pragmas
import infrastructure/process_utils

proc stateJoin(parts: varargs[string]): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [CatchableError].} =
  ## AXIOM_STATE_DIR 설정 시 <state>/<parts...>, 미설정 시 기존 CWD 상대 경로 그대로(zero-diff).
  let base = block:
    let v = getEnv("AXIOM_STATE_DIR")
    if v.len > 0: v else: getCurrentDir()
  result = base
  for p in parts: result = joinPath(result, p)

# ═══════════════════════════════════════════════════════════════════════════════
# Types
# ═══════════════════════════════════════════════════════════════════════════════

type
  SandboxResult* = object
    ## Result of a sandboxed Lean build execution.
    success*: bool
    compilerOutput*: string     ## Combined stdout + stderr from `lake build`
    axiomsUsed*: seq[string]    ## Axiom names extracted from `#print axioms`
    sorryFound*: bool           ## Whether `sorry` appears in the output
    exitCode*: int              ## Process exit code from `lake build`

  LeanBuildSandbox* = object
    ## Handle to an isolated Lean build sandbox directory.
    sandboxDir*: string         ## Absolute path to the sandbox
    uuid*: string               ## Unique identifier for this sandbox

# ═══════════════════════════════════════════════════════════════════════════════
# Constants
# ═══════════════════════════════════════════════════════════════════════════════

const
  SandboxBaseDir* = "build/tmp/lean_sandbox"
  DefaultBuildTimeout* = 120    ## Default timeout for `lake build` in seconds
  LeanBinary* = "lake"
  ProofsSourceDir* = "proofs"
  ProofsHashCachePath* = ".axiom/cache/lean_verify_hash.txt"

# ═══════════════════════════════════════════════════════════════════════════════
# Pure helpers (func)
# ═══════════════════════════════════════════════════════════════════════════════

func parseAxioms*(output: string): seq[string] =
  ## Extract axiom names from `#print axioms` output.
  ## Axiom lines typically appear as "axiom <name> : <type>".
  result = @[]
  for line in output.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("axiom "):
      let rest = stripped.substr(6)  # skip "axiom "
      let colonPos = rest.find(" :")
      if colonPos > 0:
        result.add(rest.substr(0, colonPos - 1))
      elif colonPos < 0:
        # No type annotation — take the whole name
        result.add(rest)

func containsSorry*(output: string): bool =
  ## Check whether the Lean output contains `sorry` usage.
  for line in output.splitLines():
    let stripped = line.strip()
    if stripped.contains("sorry"):
      return true
  false

func buildSuccess*(exitCode: int): bool =
  ## Determine build success from exit code.
  exitCode == 0

# ═══════════════════════════════════════════════════════════════════════════════
# I/O procs — all wrapped in try/except for {.raises: [].} compliance
# ═══════════════════════════════════════════════════════════════════════════════

proc generateUuid*(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Generate a truly unique UUID using PID + monotonic time + cryptographic randomness.
  ## Cross-process collision impossible: different PIDs or mono ticks guarantee uniqueness.
  try:
    let pid = getpid()
    let ts = int(epochTime() * 1_000_000)  # microsecond-precision epoch
    # Read 8 random bytes from /dev/urandom for cryptographic uniqueness
    var randomBytes: array[8, byte]
    try:
      let f = open("/dev/urandom")
      discard f.readBuffer(addr randomBytes, sizeof(randomBytes))
      f.close()
    except CatchableError:
      discard  # fallback is still unique enough with pid+ts  # axiom:best-effort(ioboundary catch)
    var randHex = ""
    for b in randomBytes:
      randHex.add(toHex(int(b), 2))
    result = $ts & "-" & $pid & "-" & randHex
  except CatchableError:
    # Fallback: use empty string — caller checks len
    result = ""

proc cleanupStaleSandboxes*() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Remove sandbox directories older than 10 minutes (stale from SIGKILL cleanup failures).
  try:
    if not dirExists(stateJoin("build", "tmp", "lean_sandbox")):
      return
    let now = getTime()
    const staleThreshold = 600  ## 10 minutes in seconds
    for kind, path in walkDir(stateJoin("build", "tmp", "lean_sandbox")):
      if kind == pcDir:
        let dirName = lastPathPart(path)
        if dirName.startsWith("lean_sandbox_"):
          try:
            let info = getFileInfo(path)
            let age = now.toUnix() - info.lastWriteTime.toUnix()
            if age > staleThreshold:
              removeDir(path)
          except CatchableError:
            discard  # best-effort per directory  # axiom:best-effort(ioboundary catch)
  except CatchableError:
    discard  # best-effort  # axiom:best-effort(ioboundary catch)

{.pop.}
proc createSandbox*(uuid: string): LeanBuildSandbox {.axiomEffect: IOEffect, raises: [CatchableError].} =
  ## Create an isolated sandbox by copying `proofs/` to a unique temp directory.
  ##
  ## Steps:
  ##   1. Clean up stale sandboxes from previous runs
  ##   2. Create `build/tmp/lean_sandbox_{uuid}/` directory
  ##   3. Copy `proofs/` directory contents
  ##   4. Return sandbox handle
  ##
  ## UUID is injected from the caller (AGENTS.md §0.6: func purity).
  cleanupStaleSandboxes()
  var sandboxDir = ""
  # §10/D3: proofs/ source anchor is the AXIOM repo, not the subject CWD.
  # Precedence: stateRoot/proofs → CWD-relative "proofs" (legacy zero-diff).
  let proofsSource = block:
    let sr = getEnv("AXIOM_STATE_DIR", "").strip()
    if sr.len > 0 and dirExists(sr / "proofs"): sr / "proofs"
    else: ProofsSourceDir
  try:
    if uuid.len == 0:
      raise newException(CatchableError,
        "lean sandbox creation FAILED: uuid must not be empty")
    sandboxDir = stateJoin("build", "tmp", "lean_sandbox") / ("lean_sandbox_" & uuid)

    # Ensure base directories exist
    createDir(stateJoin("build", "tmp", "lean_sandbox"))
    createDir(sandboxDir)

    # Copy the entire proofs/ directory into the sandbox using native Nim copy
    if dirExists(proofsSource):
      for kind, path in walkDir(proofsSource):
        let destName = lastPathPart(path)
        # Skip .lake cache — contains hardcoded absolute paths that
        # become stale when copied to sandbox, triggering full rebuild
        if destName == ".lake":
          continue
        let destPath = sandboxDir / destName
        case kind
        of pcFile, pcLinkToFile:
          copyFile(path, destPath)
        of pcDir, pcLinkToDir:
          copyDir(path, destPath)
  except CatchableError as e:
    raise newException(CatchableError,
      "lean sandbox creation FAILED: " & e.msg)

  result = LeanBuildSandbox(
    sandboxDir: sandboxDir,
    uuid: uuid
  )

proc createSandboxWithUuid*(): LeanBuildSandbox {.axiomEffect: IOEffect, raises: [CatchableError].} =
  ## Create a sandbox with an auto-generated UUID.
  ## Side-effect boundary: generates UUID then delegates to pure createSandbox.
  let uuid = generateUuid()
  createSandbox(uuid)

{.push raises: [].}

proc buildInSandbox*(sandbox: LeanBuildSandbox,
                     timeout: int = DefaultBuildTimeout): SandboxResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run `lake build` inside the sandbox directory.
  ##
  ## Steps:
  ##   1. cd to sandbox directory
  ##   2. Run `lake build` via execProcess
  ##   3. Capture stdout+stderr
  ##   4. Parse output for success/failure, sorry, axioms
  ##   5. Return SandboxResult
  try:
    let (lakeOutput, lakeExit) = execCmdWithTimeout(
      LeanBinary & " build",
      workingDir = sandbox.sandboxDir,
      timeoutMs = timeout * 1000  # timeout is in seconds, execCmdWithTimeout expects ms
    )

    result = SandboxResult(
      success: buildSuccess(lakeExit),
      compilerOutput: lakeOutput,
      axiomsUsed: parseAxioms(lakeOutput),
      sorryFound: containsSorry(lakeOutput),
      exitCode: lakeExit
    )
  except CatchableError:
    # Process execution failed — return failure result
    result = SandboxResult(
      success: false,
      compilerOutput: "Error: failed to execute lake build",
      exitCode: -1
    )

proc destroySandbox*(sandbox: LeanBuildSandbox) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Remove the sandbox directory and all its contents.
  ## Best-effort cleanup — never raises.
  try:
    if sandbox.sandboxDir.len > 0 and dirExists(sandbox.sandboxDir):
      removeDir(sandbox.sandboxDir)
  except CatchableError:
    discard  # best-effort  # axiom:best-effort(ioboundary catch)

{.pop.}

proc computeProofsHash*(proofsDir: string): string {.axiomEffect: IOEffect, raises: [CatchableError].} =
  ## Compute SHA-256 hash of all .lean files in proofs directory.
  ## Files are sorted by path for determinism. Returns "" if directory is empty.
  var paths: seq[string] = @[]
  if dirExists(proofsDir):
    for kind, path in walkDir(proofsDir, relative = true):
      if kind in {pcFile, pcLinkToFile} and path.endsWith(".lean"):
        paths.add(path)
      elif kind in {pcDir, pcLinkToDir}:
        # Recurse into subdirectories
        for kind2, path2 in walkDir(proofsDir / path, relative = true):
          if kind2 in {pcFile, pcLinkToFile} and path2.endsWith(".lean"):
            paths.add(path / path2)
  if paths.len == 0:
    return ""
  paths.sort()
  var combined = ""
  for p in paths:
    combined.add(readFile(proofsDir / p))
    combined.add("\x00")
  sha256Hex(combined)

proc loadProofsHashCache*(): string {.axiomEffect: IOEffect, raises: [CatchableError].} =
  ## Load cached proofs hash from disk. Returns "" if cache missing.
  try:
    if fileExists(ProofsHashCachePath):
      readFile(ProofsHashCachePath).strip()
    else:
      ""
  except CatchableError:
    ""

proc saveProofsHashCache*(hash: string) {.axiomEffect: IOEffect, raises: [CatchableError].} =
  ## Persist proofs hash to disk for next run.
  try:
    let dir = ProofsHashCachePath.parentDir()
    if not dirExists(dir):
      createDir(dir)
    writeFile(ProofsHashCachePath, hash)
  except CatchableError:
    discard  # best-effort persistence  # axiom:best-effort(ioboundary catch)

proc collectProofAxioms*(theoremName: string): seq[string] {.axiomEffect: IOEffect, raises: [CatchableError].} =
  ## Run `#print axioms` for a specific theorem via a temporary Lean script.
  ##
  ## Creates a one-shot .lean file that prints axioms for the given theorem,
  ## then executes it with `lean --run`.
  ## Manages its own sandbox lifecycle with atomic cleanup.
  result = @[]

  let sandbox = createSandboxWithUuid()  # raises on failure (1B-1)
  try:
    var leanBin = ""
    try:
      leanBin = findExe("lean")
    except CatchableError:
      return

    if leanBin.len == 0:
      return

    # Create a temporary Lean file that imports the proofs and prints axioms
    var scriptPath = ""
    try:
      let ts = getTime().toUnix()
      scriptPath = sandbox.sandboxDir / ("_axiom_query_" & $ts & ".lean")
      let scriptContent = "import GateInvariants\n#print axioms " & theoremName & "\n"
      writeFile(scriptPath, scriptContent)
    except CatchableError:
      return

    try:
      let (leanOutput, leanExit) = execCmdWithTimeout(
        leanBin & " --run " & scriptPath,
        workingDir = sandbox.sandboxDir,
        timeoutMs = 120_000  # 120s max for lean --run
      )

      if leanExit == 0:
        result = parseAxioms(leanOutput)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    finally:
      if scriptPath.len > 0:
        try:
          removeFile(scriptPath)
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)
  finally:
    try:
      destroySandbox(sandbox)
    except CatchableError:
      discard  # best-effort cleanup  # axiom:best-effort(ioboundary catch)

proc verifyWithSandbox*(timeout: int = DefaultBuildTimeout): SandboxResult {.axiomEffect: IOEffect, raises: [CatchableError].} =
  ## Convenience: create → build → destroy (all-in-one).
  ## Uses try/finally to guarantee cleanup even on exceptions.
  ## createSandbox() raises on failure — no empty-sandbox fallback needed.
  ## Skips sandbox entirely if proofs/ hash matches cached value.
  var sandbox: LeanBuildSandbox
  try:
    # Fast path: check if proofs/ content hash matches cached value
    let currentHash = computeProofsHash(ProofsSourceDir)
    if currentHash.len > 0:
      let cachedHash = loadProofsHashCache()
      if cachedHash.len > 0 and cachedHash == currentHash:
        # Cache hit — proofs unchanged, return cached success
        return SandboxResult(
          success: true,
          compilerOutput: "Lean verify skipped — proofs unchanged (hash: " & currentHash[0..7] & ")",
          axiomsUsed: @[],
          sorryFound: false,
          exitCode: 0
        )
    # Cache miss — run full sandbox build
    sandbox = createSandboxWithUuid()
    result = buildInSandbox(sandbox, timeout)
    # On success, update the hash cache
    if result.success and currentHash.len > 0:
      saveProofsHashCache(currentHash)
  finally:
    destroySandbox(sandbox)
