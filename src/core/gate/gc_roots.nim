import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

## GC Root Manager — Nix Model
##
## Root-based garbage collection for the content-addressable store.
## Only content reachable from a GC root is preserved.
## Unreachable content is deleted by mark-and-sweep.
##
## .axiom/gcroots/
##   pipeline-20260619-101924  → contains list of store hashes
##   gate-integrity-workflow   → contains list of store hashes

import std/[os, sets, strutils, sequtils]
import core/io/file_utils
import core/trusted/stdlib_shield
import core/trusted/axiom_pragmas_lite
import core/trusted/effect_bridge

const
  GcRootsDir* = ".axiom/gcroots"

type
  GcRoot* = object
    name*: string
    storeHashes*: seq[string]
# axiomIoBoundary

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc initGcRoots*() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  createDir(GcRootsDir)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc registerGcRoot*(name: string, hashes: seq[string]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Register a GC root. Called on successful pipeline/gate completion.
  createDir(GcRootsDir)
  writeFile(GcRootsDir / name, hashes.join("\n"))

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc removeGcRoot*(name: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let path = GcRootsDir / name
  if fileExists(path): safeRemoveFile(path)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc listGcRoots*(): seq[GcRoot] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = @[]
  if not dirExists(GcRootsDir): return
  for kind, path in walkDir(GcRootsDir):
    if kind == pcFile:
      let name = extractFilename(path)
      let hashes = readFileSafe(path).split("\n").filterIt(it.len > 0)
      result.add(GcRoot(name: name, storeHashes: hashes))

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc collectLiveHashes*(): HashSet[string] {.axiomEffect: IOEffect.} =
  ## Mark phase: collect all hashes reachable from any GC root.
  result = initHashSet[string]()
  for root in listGcRoots():
    for hash in root.storeHashes:
      result.incl(hash)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc sweep*(storeDir: string, live: HashSet[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Sweep phase: delete store content not in live set.
  ## Returns count of deleted items.
  result = 0
  if not dirExists(storeDir): return
  for kind, shard in walkDir(storeDir):
    if kind != pcDir: continue
    let shardName = extractFilename(shard)
    if shardName.startsWith("_"): continue  # skip _tmp, _gcroots
    for kind2, file in walkDir(shard):
      if kind2 != pcFile: continue
      let hash = extractFilename(file)
      if hash notin live:
        safeRemoveFile(file)
        inc result
  # Remove empty shards
  for kind, shard in walkDir(storeDir):
    if kind != pcDir: continue
    let shardName = extractFilename(shard)
    if shardName.startsWith("_"): continue
    var isEmpty = true
    for _ in walkDir(shard):
      isEmpty = false
      break
    if isEmpty:
      removeDir(shard)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc gc*(storeDir: string): int {.axiomEffect: IOEffect.} =
  ## Full garbage collection cycle: mark + sweep.
  let live = collectLiveHashes()
  sweep(storeDir, live)
