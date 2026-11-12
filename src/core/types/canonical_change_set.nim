import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## CanonicalChangeSet — normalized change-set representation for the selector.
##
## Follows the layered identity pattern from candidate_identity.nim:
## each layer object carries a digest field; combined digests use
## combineHashes (cas_index.nim:80) with \x03 domain separators.
## All functions are pure and deterministic.

import std/[algorithm, json, sequtils, strutils]

# ---------------------------------------------------------------------------
# DiffInterpretationPolicy — diff-interpretation flags
# ---------------------------------------------------------------------------

type
  DiffInterpretationFlag* = enum
    difRenameDetected      ## rename/copy similarity header present in diff-pairs
    difCopyDetected        ## copy detection active; copy diff merged with original
    difSubmoduleHandling   ## submodule pointer-level interpretation (not recursive)
    difGeneratedFileHandling ## generated-file diffs included but flagged
    difLineLevelMode       ## line-level diff with blank/comment/whitespace policy

  DiffInterpretationPolicy* = object
    flags*: set[DiffInterpretationFlag]

func flagsToString*(flags: set[DiffInterpretationFlag]): string {.raises: [].} =
  let sorted = toSeq(flags).sorted(cmp)
  sorted.mapIt($it).join("|")

func toCanonicalJson*(p: DiffInterpretationPolicy): JsonNode {.raises: [].} =
  %*{"flags": flagsToString(p.flags).split("|").sorted(cmp)}

# ---------------------------------------------------------------------------
# CanonicalChangeSet
# ---------------------------------------------------------------------------

type
  CanonicalChangeSet* = object
    baseCommit*: string                ## base commit SHA
    headCommit*: string                ## head commit SHA
    mergeBase*: seq[string]            ## merge-base commit SHA(s); single or multi-parent
    canonicalDiffDigest*: string       ## SHA-256 of normalized diff content
    diffInterpretationPolicy*: DiffInterpretationPolicy

func toCanonicalJson*(cs: CanonicalChangeSet): JsonNode {.raises: [].} =
  let sortedMergeBase = cs.mergeBase.sorted(cmp)
  %*{
    "baseCommit": cs.baseCommit,
    "headCommit": cs.headCommit,
    "mergeBase": sortedMergeBase,
    "canonicalDiffDigest": cs.canonicalDiffDigest,
    "diffInterpretationPolicy": cs.diffInterpretationPolicy.toCanonicalJson}

{.pop.}