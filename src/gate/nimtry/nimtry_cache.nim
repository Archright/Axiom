import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Nimtry Cache — SHA256 Incremental Cache
##
## Hard prerequisite for Vibe Coding rhythm preservation.
## Warm-cache full-tree scan must complete within 3 seconds.
## Cold-start full-tree scan must complete within 60 seconds.

import std/jsonutils
import std/os
import std/options
import std/strutils
import checksums/sha2
import gate/architecture_ast_facts
import core/json/json_utils
import core/json/std_redirect
import core/utils/file_utils
import core/trusted/axiom_pragmas

proc getCacheDir*(): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let cwd = try: getCurrentDir() except CatchableError: "."
  cwd / "build" / "nimcache" / "nimtry"

proc ensureCacheDir*() {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let dir = getCacheDir()
  if not dirExists(dir):
    try:
      createDir(dir)  # creates intermediate dirs (build/nimcache/nimtry)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

proc computeFileHash*(path: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not fileExists(path):
    return ""
  var hasher = initSha_256()
  let content = try: readFileSafe(path) except CatchableError: ""
  hasher.update(content)
  result = $hasher.digest()

proc computeMultiFileHash*(files: seq[string]): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute SHA-256 hash of concatenated contents of multiple files.
  ## Files that don't exist are skipped (contribute empty string).
  var hasher = initSha_256()
  for f in files:
    if fileExists(f):
      let content = try: readFileSafe(f) except CatchableError: ""
      hasher.update(content)
    else:
      hasher.update("")
  result = $hasher.digest()

proc getNimVersion*(): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  NimVersion

proc cacheFilePath*(modulePath: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let key = modulePath.replace("/", "_").replace("\\", "_")
  getCacheDir() / key & ".json"

type
  CacheEntry* = object
    sourceHash*: string
    policyHash*: string
    binaryHash*: string
    nimVersion*: string
    facts*: ModuleFacts

proc loadCachedFacts*(
  modulePath: string;
  policyHash, binaryHash: string
): Option[ModuleFacts] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let cachePath = cacheFilePath(modulePath)
  if not fileExists(cachePath):
    return none(ModuleFacts)

  let jsonContent = try: readFileSafe(cachePath) except CatchableError: ""
  if jsonContent.len == 0:
    return none(ModuleFacts)

  let node = try: parseJsonOpt(jsonContent).get(newJObject()) except CatchableError: nil
  if node.isNil:
    return none(ModuleFacts)

  let entry = try: node.jsonTo(CacheEntry) except CatchableError: return none(ModuleFacts)

  if entry.sourceHash != computeFileHash(modulePath):
    return none(ModuleFacts)
  if entry.policyHash != policyHash:
    return none(ModuleFacts)
  if entry.binaryHash != binaryHash:
    return none(ModuleFacts)
  if entry.nimVersion != getNimVersion():
    return none(ModuleFacts)

  return some(entry.facts)

proc saveCachedFacts*(
  modulePath: string;
  facts: ModuleFacts;
  policyHash, binaryHash: string
) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ensureCacheDir()
  let entry = CacheEntry(
    sourceHash: computeFileHash(modulePath),
    policyHash: policyHash,
    binaryHash: binaryHash,
    nimVersion: getNimVersion(),
    facts: facts
  )
  let node = try: entry.toJson except CatchableError: nil
  if node.isNil:
    return
  let jsonContent = try: $node except CatchableError: ""
  if jsonContent.len == 0:
    return
  let cachePath = cacheFilePath(modulePath)
  try:
    discard writeFileSafe(cachePath, jsonContent)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

{.pop.}

