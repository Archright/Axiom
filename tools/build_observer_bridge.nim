## tools/build_observer_bridge.nim — ProjectMap integration for build.nim
## Provides a single-scan entry point that replaces:
## - dep_graph.computeSourceHash (walkDirRec + readFile)
## - dep_graph.buildGraph (walkDirRec + readFile + parse)
##
## Usage in build.nim:
##   import tools/build_observer_bridge
##   let pm = scanForBuild(config.srcDir)
##   let currentHash = pm.sourceHash

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/os

import shared_types/shared_types

proc scanForBuild*(srcDir: string): ProjectMap =
  ## Scan source directory for build pipeline.
  ## Returns ProjectMap with all .nim files read + hashed.
  let repoRoot = getCurrentDir()
  scanProject(repoRoot, scanDirs = @[srcDir])

proc createBuildContext*(srcDir: string): PipelineContext {.axiomEffect: IoEffect.} =
  ## Create PipelineContext for build pipeline (pmBuild mode).
  ## Includes Gate 0 sync protocol enforcement.
  let repoRoot = getCurrentDir()
  let metadata = gatherGitMetadata(repoRoot)
  discard assertSyncProtocol(metadata)
  let pm = scanProject(repoRoot, scanDirs = @[srcDir])
  let state = computeStateHash(pm, repoRoot)
  PipelineContext(
    pm: pm,
    ast: astCache(),
    state: state,
    repoRoot: repoRoot,
    mode: pmBuild,
    repoState: metadata
  )

proc sourceHash*(pm: ProjectMap): string =
  ## Merkle root of all source file hashes.
  pm.sourceHash

proc fileCount*(pm: ProjectMap): int =
  pm.fileCount

proc scanDurationMs*(pm: ProjectMap): float =
  pm.scanDurationMs
