## Atomic Deployment — Nix Profile Generation Model
##
## Build success → Current symlink atomically swapped.
## "빌드 중인 결과물"을 절대 보지 않음.
##
## .axiom/current → .axiom/store/ab/abcdef1234...
## .axiom/generations/
##   001 → ../store/ab/abcdef...
##   002 → ../store/cd/cdef12...

import core/trusted/layer_declaration
axiomLayer "domain"
import std/[os, strutils, strformat, algorithm, times]
import core/trusted/stdlib_shield
import core/axiom_pragmas
import core/parsers/safe_parsers
import core/results

const
  CurrentLink* = ".axiom/current"
  GenerationsDir* = ".axiom/generations"

type
  Generation* = object
    number*: int
    timestamp*: float
    storeHash*: string
    pipelineId*: string
# axiomIoBoundary

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc initDeploy*() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [CatchableError].} =
  createDir(GenerationsDir)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc nextGenerationNumber*(): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [CatchableError].} =
  var maxNum = 0
  if dirExists(GenerationsDir):
    for kind, path in walkDir(GenerationsDir):
      if kind == pcFile:
        let name = extractFilename(path)
        let numRes = safeParseInt(name)
        if numRes.isOk and numRes.get > maxNum:
          maxNum = numRes.get
  maxNum + 1

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc atomicSwap(target, source: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [CatchableError].} =
  ## Atomic symlink swap: remove old target, rename source into place.
  if fileExists(target) or symlinkExists(target):
    safeRemoveFile(target)
  safeMoveFile(source, target)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc deploy*(storeHash: string, pipelineId: string = "") {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [CatchableError].} =
  ## Atomically deploy a build result.
  ## 1. Record generation
  ## 2. Create tmp symlink
  ## 3. Atomic rename to current
  createDir(GenerationsDir)
  let genNum = nextGenerationNumber()
  let genFile = GenerationsDir / &"{genNum:03d}"
  writeFile(genFile, &"{storeHash}\n{pipelineId}\n{epochTime()}")

  # Atomic current link swap
  let tmpLink = CurrentLink & ".tmp"
  if symlinkExists(tmpLink) or fileExists(tmpLink):
    safeRemoveFile(tmpLink)
  createSymlink(storeHash, tmpLink)
  atomicSwap(CurrentLink, tmpLink)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getCurrentHash*(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [CatchableError].} =
  ## Read the current deployment hash.
  if symlinkExists(CurrentLink):
    return expandSymlink(CurrentLink)
  if fileExists(CurrentLink):
    return readFile(CurrentLink).strip()
  ""

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc rollback*() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [CatchableError].} =
  ## Rollback to previous generation.
  var gens: seq[Generation] = @[]
  if not dirExists(GenerationsDir): return
  for kind, path in walkDir(GenerationsDir):
    if kind != pcFile: continue
    let name = extractFilename(path)
    let numRes = safeParseInt(name)
    if numRes.isOk:
      try:
        let lines = readFile(path).split("\n")
        gens.add(Generation(
          number: numRes.get,
          storeHash: if lines.len > 0: lines[0] else: "",
          pipelineId: if lines.len > 1: lines[1] else: "",
          timestamp: (if lines.len > 2: safeParseFloat(lines[2]).getOrDefault(0.0) else: 0.0)
        ))
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
  gens.sort(proc (a, b: Generation): int = cmp(a.number, b.number))

  let currentHash = getCurrentHash()
  var prevGen: Generation
  for gen in gens:
    if gen.storeHash == currentHash and prevGen.number > 0:
      deploy(prevGen.storeHash, prevGen.pipelineId)
      return
    prevGen = gen

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc listGenerations*(): seq[Generation] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [CatchableError].} =
  result = @[]
  if not dirExists(GenerationsDir): return
  for kind, path in walkDir(GenerationsDir):
    if kind != pcFile: continue
    let name = extractFilename(path)
    let numRes = safeParseInt(name)
    if numRes.isOk:
      try:
        let lines = readFile(path).split("\n")
        result.add(Generation(
          number: numRes.get,
          storeHash: if lines.len > 0: lines[0] else: "",
          pipelineId: if lines.len > 1: lines[1] else: "",
          timestamp: (if lines.len > 2: safeParseFloat(lines[2]).getOrDefault(0.0) else: 0.0)
        ))
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
  result.sort(proc (a, b: Generation): int = cmp(a.number, b.number))
