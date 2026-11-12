import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## observer/types.nim — Pure type definitions for Axiom Pipeline Engine
## SSOT for ProjectMap, ASTCache, StateHash, PipelineContext.
## No I/O. No side effects. Pure data structures.

import std/tables
export tables

type
  FileEntry* = object
    ## Single file's state — content read once, hash computed once.
    path*: string           ## Absolute path
    relativePath*: string   ## repoRoot-relative path (deterministic key)
    content*: string        ## File content (read once)
    contentHash*: string    ## SHA-256 hex digest
    mtime*: int64           ## Unix timestamp
    size*: int64            ## Byte count

  ProjectMap* = object
    ## Single Source of Truth for all project source files.
    ## Created once by scanProject(), consumed by build + gate pipelines.
    files*: Table[string, FileEntry]  ## relativePath → entry
    sortedPaths*: seq[string]         ## Deterministic ordering
    sourceHash*: string               ## Merkle root of all content hashes
    repoRoot*: string
    stagedFiles*: seq[string]
    scanDurationMs*: float
    fileCount*: int
    excludedCount*: int               ## Files excluded due to read/hash errors (observable for integrity)

  ASTEntry* = object
    ## Parsed AST data for a single module.
    imports*: seq[string]   ## Import paths extracted from AST
    procCount*: int         ## Number of proc definitions
    funcCount*: int         ## Number of func definitions

  ASTCache* = object
    ## Memoized AST cache — IdentCache/ConfigRef shared across all files.
    ## PNode is stored as pointer (ref), so we keep metadata only.
    entries*: Table[string, ASTEntry]  ## relativePath → ASTEntry
    parseDurationMs*: float
    totalParsed*: int
    totalFailed*: int

  StateHash* = object
    ## Deterministic project state identifier.
    ## If combined hash matches, build + gate results are guaranteed identical.
    sourceHash*: string     ## ProjectMap.sourceHash
    configHash*: string     ## config.nims + nimble + nim version
    gateHash*: string       ## All gate source files hash
    combined*: string       ## SHA-256(source + config + gate)

  GitMetadata* = object
    ## Git repository state snapshot — gathered once at pipeline start.
    ## Used by Gate 0 (assertSyncProtocol) to enforce sync protocol.
    currentBranch*: string          ## Current branch name (or "HEAD" if detached)
    headHash*: string               ## Full SHA-1 of HEAD commit
    remoteBranch*: string           ## Upstream tracking branch (e.g. "origin/main")
    remoteHash*: string             ## SHA-1 of remote tracking ref
    isDetached*: bool               ## True when HEAD is detached
    hasUncommittedChanges*: bool    ## True when working tree is dirty
    syncBranchToken*: bool          ## True when axiom.sync-authorized is set in git config

  PipelineMode* = enum
    pmBuild               ## Build pipeline only
    pmGate                ## Gate pipeline only
    pmUnified             ## Build + Gate in parallel

  PipelineContext* {.bycopy.} = object
    ## Unified context passed to all pipeline stages.
    pm*: ProjectMap
    ast*: ASTCache
    state*: StateHash
    repoRoot*: string
    mode*: PipelineMode
    repoState*: GitMetadata         ## Gate 0: sync protocol precondition

  GateFunc* = proc(ctx: PipelineContext): bool {.nimcall, raises: [].}
    ## Pure function gate signature.
    ## Returns true if gate passes, false if it fails.

func fileEntry*(path, relPath, content, hash: string;
                mtime: int64; size: int64): FileEntry {.raises: [].} =
  FileEntry(path: path, relativePath: relPath, content: content,
            contentHash: hash, mtime: mtime, size: size)

func projectMap*(repoRoot: string): ProjectMap {.raises: [].} =
  ProjectMap(
    files: initTable[string, FileEntry](),
    sortedPaths: @[],
    sourceHash: "",
    repoRoot: repoRoot,
    stagedFiles: @[],
    scanDurationMs: 0.0,
    fileCount: 0,
    excludedCount: 0
  )

func astCache*(): ASTCache {.raises: [].} =
  ASTCache(
    entries: initTable[string, ASTEntry](),
    parseDurationMs: 0.0,
    totalParsed: 0,
    totalFailed: 0
  )

func pipelineContext*(repoRoot: string; mode: PipelineMode): PipelineContext {.raises: [].} =
  PipelineContext(
    pm: projectMap(repoRoot),
    ast: astCache(),
    state: StateHash(),
    repoRoot: repoRoot,
    mode: mode,
    repoState: GitMetadata()
  )

{.pop.}
