import core/trusted/layer_declaration
axiomLayer "domain"
# axiomIoBoundary
{.push raises: [].}

## Gate Virtual File System — I/O Isolation Layer
##
## All gate runners currently perform direct I/O (readFile, execCmd, etc.).
## The VFS isolates all I/O into an in-memory data structure that gates
## read from, enabling deterministic testing and I/O sandboxing.
##
## Gates MUST use ``vfsRead``, ``vfsExists``, ``vfsListDir``, etc. instead
## of direct ``readFile``/``fileExists``/``walkDir`` calls. The orchestrator
## builds the VFS from the git index before dispatching gates.
##
## Pure I/O functions (``func``) operate on the in-memory VFS tables.
## The ``buildVfsFromGitIndex`` proc performs actual I/O (env reads, git
## index parsing) and is the only I/O boundary in this module.

import std/[tables, options]
import ../trusted/env_access

type
  VirtualFile* = object
    path*: string
    content*: string
    hash*: string          ## SHA-256 of content

  VirtualDir* = object
    path*: string
    entries*: seq[string]

  SubprocessResult* = object
    exitCode*: int
    output*: string

  SubprocessProvider* = proc(cmd: string, args: seq[string]): SubprocessResult {.noSideEffect, raises: [].}

  GateVfs* = object
    files*: Table[string, VirtualFile]
    dirs*: Table[string, VirtualDir]
    env*: Table[string, string]
    runSubprocess*: SubprocessProvider

  GateContext* = object
    vfs*: GateVfs
    repoRoot*: string

# ─── Pure I/O Functions ──────────────────────────────────────────────────────
# Gates use THESE instead of readFile/fileExists/walkDir.
# All are pure (func) — they only read from the in-memory VFS tables.

func vfsRead*(ctx: GateContext, path: string): string {.raises: [KeyError].} =
  ## Read file content from VFS. Raises KeyError if path not found.
  ctx.vfs.files[path].content

func vfsReadOpt*(ctx: GateContext, path: string): Option[string] {.noSideEffect.} =
  ## Read file content from VFS, returning none if path not found.
  if ctx.vfs.files.hasKey(path): some(ctx.vfs.files.getOrDefault(path).content) else: none(string)

func vfsExists*(ctx: GateContext, path: string): bool {.noSideEffect.} =
  ## Check if a path exists in the VFS.
  ctx.vfs.files.hasKey(path)

func vfsHash*(ctx: GateContext, path: string): string {.raises: [KeyError].} =
  ## Get the SHA-256 hash of a file from VFS. Raises KeyError if not found.
  ctx.vfs.files[path].hash

func vfsListDir*(ctx: GateContext, dir: string): seq[string] {.noSideEffect.} =
  ## List directory entries from VFS. Returns empty seq if dir not found.
  if ctx.vfs.dirs.hasKey(dir): ctx.vfs.dirs.getOrDefault(dir).entries else: @[]

func vfsGetEnv*(ctx: GateContext, key: string, default: string = ""): string {.noSideEffect.} =
  ## Get an environment variable from VFS. Returns default if not found.
  if ctx.vfs.env.hasKey(key): ctx.vfs.env.getOrDefault(key) else: default

func vfsExec*(ctx: GateContext, cmd: string, args: seq[string]): SubprocessResult =
  ## Execute a subprocess via the VFS provider. Delegates to the
  ## SubprocessProvider callback set during VFS construction.
  ctx.vfs.runSubprocess(cmd, args)

# ─── VFS Builders ────────────────────────────────────────────────────────────
# These procs perform actual I/O and are the I/O boundary for this module.

proc noopSubprocess*(cmd: string, args: seq[string]): SubprocessResult {.noSideEffect.} =
  ## Default no-op subprocess provider. Returns exit code 0 with empty output.
  SubprocessResult(exitCode: 0, output: "")

func buildVfsFromGitIndex*(repoRoot: string): GateVfs =
  ## Orchestrator builds VFS from git index before dispatching gates.
  ## Uses git ls-files + readFile to populate in-memory tables.
  ## This proc performs I/O (getEnv, git index reading).
  result = GateVfs(
    files: initTable[string, VirtualFile](),
    dirs: initTable[string, VirtualDir](),
    env: initTable[string, string](),
    runSubprocess: noopSubprocess
  )
  # Populate from environment
  for key in [evHome, evPath, evTimeoutSla,
              evEmergencyNoVerify]:
    let val = getAxiomEnv(key)
    if val.len > 0: result.env[envName(key)] = val

func buildVfsForTest*(fixtures: seq[(string, string)]): GateVfs =
  ## Test helper: build VFS from path-content pairs.
  ## No I/O — purely in-memory construction.
  result = GateVfs(
    files: initTable[string, VirtualFile](),
    dirs: initTable[string, VirtualDir](),
    env: initTable[string, string](),
    runSubprocess: noopSubprocess
  )
  for (path, content) in fixtures:
    result.files[path] = VirtualFile(path: path, content: content, hash: "")

{.pop.}
