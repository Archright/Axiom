import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Action Cache — Bazel Action Cache Model
##
## Maps Action Keys to execution results.
## Persistent on disk for cross-session cache reuse.
##
## Layout:
## .axiom/cache/actions/
##   <hash[:2]>/<hash>/
##     result.json      — execution result
##     outputs.json     — output path → content hash
##     inputs.json      — input path → content hash (for verification)
##     toolchain.json   — PATH manifest hash (for verification)

import std/[os, json, tables, times]
import std/options
import core/trusted/axiom_pragmas_lite

const
  CacheRoot* = ".axiom/cache/actions"

type
  ActionCache* {.acyclic.} = ref object
    root*: string

  ActionResult* = object
    ok*: bool
    stdout*: string
    stderr*: string
    exitCode*: int
    outputHashes*: Table[string, string]   # output path → content hash
    inputHashes*: Table[string, string]    # input path → content hash (for verification)
    pathManifestHash*: string              # PATH manifest hash (for verification)
    cachedAt*: float                       # epoch timestamp

proc initActionCache*(root: string = CacheRoot): ActionCache =
  ## Initialize action cache, creating shard directories on first use.
  result = ActionCache(root: root)
  createDir(root)

proc cachePath*(cache: ActionCache, key: string): string {.axiomEffect: IOEffect.} =
  ## Compute on-disk path for an action key.
  ## Layout: <root>/<first2hex>/<fullhash>/
  assert key.len >= 2
  cache.root / key[0..1] / key

proc lookup*(cache: ActionCache, key: string): Option[ActionResult] {.axiomEffect: IOEffect.} =
  ## Look up a cached action result. Returns none if miss.
  let dir = cachePath(cache, key)
  let resultFile = dir / "result.json"
  if not fileExists(resultFile):
    return none(ActionResult)

  try:
    let j = parseJson(readFile(resultFile))
    var res = ActionResult(
      ok: j["ok"].getBool(),
      stdout: j["stdout"].getStr(),
      stderr: j["stderr"].getStr(),
      exitCode: j["exitCode"].getInt(),
      pathManifestHash: j{"pathManifestHash"}.getStr(""),
      cachedAt: j{"cachedAt"}.getFloat()
    )

    # Load output hashes
    let outputsFile = dir / "outputs.json"
    if fileExists(outputsFile):
      let oj = parseJson(readFile(outputsFile))
      res.outputHashes = initTable[string, string]()
      for k, v in oj:
        res.outputHashes[k] = v.getStr()

    # Load input hashes
    let inputsFile = dir / "inputs.json"
    if fileExists(inputsFile):
      let ij = parseJson(readFile(inputsFile))
      res.inputHashes = initTable[string, string]()
      for k, v in ij:
        res.inputHashes[k] = v.getStr()

    return some(res)
  except CatchableError:
    return none(ActionResult)

proc store*(cache: ActionCache, key: string, result: ActionResult) {.axiomEffect: IOEffect.} =
  ## Store an action result in cache.
  let dir = cachePath(cache, key)
  createDir(dir)

  # Store result.json
  var j = %*{
    "ok": result.ok,
    "stdout": result.stdout,
    "stderr": result.stderr,
    "exitCode": result.exitCode,
    "pathManifestHash": result.pathManifestHash,
    "cachedAt": epochTime()
  }
  writeFile(dir / "result.json", pretty(j))

  # Store outputs.json
  var oj = newJObject()
  for k, v in result.outputHashes:
    oj[k] = %v
  writeFile(dir / "outputs.json", pretty(oj))

  # Store inputs.json
  if result.inputHashes.len > 0:
    var ij = newJObject()
    for k, v in result.inputHashes:
      ij[k] = %v
    writeFile(dir / "inputs.json", pretty(ij))

proc invalidate*(cache: ActionCache, key: string) =
  ## Remove a cached entry.
  let dir = cachePath(cache, key)
  if dirExists(dir):
    removeDir(dir)

proc verifyOutputs*(cache: ActionCache, key: string,
                    storeExists: proc(hash: string): bool): bool {.axiomEffect: IOEffect.} =
  ## Verify that all cached outputs still exist in the content store.
  ## Returns false if any output is missing (cache invalidation needed).
  let opt = cache.lookup(key)
  if opt.isNone: return false
  let cacheResult = opt.get()
  for path, hash in cacheResult.outputHashes:
    if not storeExists(hash):
      return false
  true

{.pop.}

