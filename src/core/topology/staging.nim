## Staging Snapshot & Rollback Manager — Pure manifest types.
## Filesystem operations (create/copy/remove directories) moved to
## infrastructure/topology_executor.nim so core/topology stays I/O-free.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/json
import core/topology/plan
{.push raises: [].}
# axiomIoBoundary

export plan

type
  StagingManifest* = object
    createdAt*: string
    stagingRoot*: string
    moves*: seq[MoveOp]
    rewrites*: seq[RewriteOp]

func buildStagingManifest*(stagingRoot: string; plan: Plan): JsonNode {.raises: [].} =
  ## Pure: build a manifest JSON node for forensics and rollback.
  %*{
    "created_at": stagingRoot,  # caller provides timestamp separately
    "staging_root": stagingRoot,
    "moves": plan.moves,
    "rewrites": plan.rewrites
  }

func stagingManifestJson*(stagingRoot: string; plan: Plan): string {.raises: [].} =
  ## Pure: render manifest as JSON string.
  result = $buildStagingManifest(stagingRoot, plan)

{.pop}
