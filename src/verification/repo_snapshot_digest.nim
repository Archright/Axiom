## repo_snapshot_digest.nim — Working-Tree Snapshot Digest
##
## Computes a deterministic digest of the live working tree (untracked and
## modified files included — this is NOT a git-tree digest). The verification
## auditor walks the LIVE working tree, so the snapshot must reflect what is
## on disk, not the index.
##
## Selection rule (the rule itself is a semantic input — see
## semantic_query_types.nim SelectionRule): default includeDirs are
## ["src", "tests/features", "tests/gateway"] and the default skipDirs
## match src/core/gate/merkle_vfs.nim.
##
## Symlink decision (documented): we follow symlinks that resolve to
## regular files (hash their target content) and skip symlinks that resolve
## to directories (to avoid cycles and infinite recursion). This resolves
## the inconsistency in src/core/gate/merkle_vfs.nim where discoverFiles
## hashes symlinks but buildVfs skips them — a single deterministic rule
## is chosen here instead.
##
## Limitation: walkDirRec is files-only, so empty directories are invisible
## to the digest (they produce no entries). This is documented, not a bug.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}
# axiomIoBoundary

import core/trusted/axiom_pragmas_lite
import std/[os, strutils, algorithm]
import core/crypto/hash_kernel
import core/types/results
import verification/semantic_query_types

# ---------------------------------------------------------------------------
# RepoSnapshotDigest
# ---------------------------------------------------------------------------

type
  RepoSnapshotDigest* = distinct string
    ## SHA-256 hex digest of the live working-tree snapshot under a
    ## SelectionRule.

func newRepoSnapshotDigest*(hex: string): RepoSnapshotDigest =
  RepoSnapshotDigest(hex)

func `$`*(d: RepoSnapshotDigest): string {.raises: [].} = string(d)

# ---------------------------------------------------------------------------
# Default selection rule
# ---------------------------------------------------------------------------

const
  DefaultSelectionRule* = SelectionRule(
    includeDirs: @["src", "tests/features", "tests/gateway"],
    skipDirs: @[".git", ".axiom", "build", "nimcache", ".nimcache", "logs"],
    symlinkPolicy: spFollowRegularFiles,
    version: 1
  )
  ## Default selection rule. skipDirs matches the merkle_vfs skip list
  ## (src/core/gate/merkle_vfs.nim). THE SKIP LIST IS PART OF THE
  ## SELECTION RULE and is therefore a component of query identity.

# ---------------------------------------------------------------------------
# computeRepoSnapshotDigest
# ---------------------------------------------------------------------------

proc computeRepoSnapshotDigest*(
  repoRoot: string;
  selectionRule: SelectionRule = DefaultSelectionRule
): Result[RepoSnapshotDigest, string] {.
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect],
  raises: [CatchableError].} =
  ## Compute the digest of the live working tree.
  ##
  ## For each entry found under the includeDirs (after skipDir filtering):
  ##   relPath + entry type + sha256(content)  ->  per-entry hash.
  ## The per-entry hashes are sorted by relPath, concatenated, and
  ## SHA-256'd to produce RepoSnapshotDigest.
  ##
  ## Symlinks resolving to regular files are followed and their target
  ## content is hashed (recorded as "link" type). Directory symlinks are
  ## skipped. Empty directories are invisible (walkDirRec files-only).
  var entries: seq[string] = @[]

  for dir in selectionRule.includeDirs:
    let absDir = repoRoot / dir
    if not dirExists(absDir): continue
    for relPath in walkDirRec(absDir, relative = true):
      # Skip any path component that matches skipDirs or starts with ".".
      var skip = false
      for part in relPath.split(DirSep):
        if part in selectionRule.skipDirs or part.startsWith("."):
          skip = true; break
      if skip: continue

      let absPath = absDir / relPath
      let isLink = symlinkExists(absPath)

      if isLink:
        # Follow symlinks that resolve to regular files; skip dir symlinks.
        if fileExists(absPath):
          let fi = getFileInfo(absPath)
          if fi.kind == pcFile:
            let content = readFile(absPath)
            let h = hash_kernel.sha256Hex(content)
            entries.add(relPath & "|link|file|" & h)
        # Directory symlinks are skipped (not recursed into).
        continue

      if fileExists(absPath):
        let fi = getFileInfo(absPath)
        if fi.kind == pcFile:
          let content = readFile(absPath)
          let h = hash_kernel.sha256Hex(content)
          entries.add(relPath & "|file|" & h)

  if entries.len == 0:
    return ok(newRepoSnapshotDigest(hash_kernel.sha256Hex("")))

  # Sort and dedupe adjacent equal entries (walkDirRec may yield the same
  # path through different symlink routes).
  entries.sort()
  var uniq: seq[string] = @[]
  for i, e in entries:
    if i == 0 or e != entries[i - 1]:
      uniq.add(e)
  let allEntries = uniq.join("\n")
  return ok(newRepoSnapshotDigest(hash_kernel.sha256Hex(allEntries)))

{.pop.}
