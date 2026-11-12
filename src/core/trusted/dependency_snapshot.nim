import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}
import std/algorithm
import std/strutils
import core/crypto/hash_kernel

## DependencySnapshot — immutable capture of a function's static dependency
## footprint. It intentionally carries NO policy/interpreces (no BLOCKED,
## VERIFIED, FAILED) — interpretation belongs to Claim Authority (Phase 3).

type
  DependencySnapshot* = object
    directDependencies*: seq[string]
    sourceScope*: string
    snapshotHash*: string     ## deterministic sha256 of (sorted deps | sourceScope)

func snapshotDigest*(directDependencies: seq[string]; sourceScope: string): string {.raises: [].} =
  let sorted = directDependencies.sorted()
  let data = sorted.join("|") & "|" & sourceScope
  sha256Hex(data)

func captureDependencySnapshot*(directDependencies: seq[string]; sourceScope: string): DependencySnapshot {.raises: [].} =
  DependencySnapshot(
    directDependencies: directDependencies,
    sourceScope: sourceScope,
    snapshotHash: snapshotDigest(directDependencies, sourceScope)
  )

{.pop.}
