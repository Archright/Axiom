## baseline_ratchet.nim — Coverage Baseline Ratchet Mechanism
##
## Ensures per-module test coverage never regresses. Stores a baseline
## of module source hashes and coverage percentages; any module whose
## source changed but coverage dropped is flagged as a violation.
##
## Usage:
##   nim c -o:bin/baseline-ratchet tools/baseline_ratchet.nim
##   bin/baseline-ratchet --check --module=<path> --baseline=<path>
##   bin/baseline-ratchet --update --module=<path> --coverage=<pct> --baseline=<path>

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[json, os, strutils, algorithm]
import checksums/sha2
import shared_types/shared_types


# ── Types ──────────────────────────────────────────────────────────────────────

type
  BaselineEntry* = object
    module*: string       ## Module path relative to project root
    coverage*: float      ## Coverage percentage (0.0–100.0)
    srcHash*: string      ## SHA-1 of source file contents
    lastCommit*: string   ## Commit hash when last updated

  Baseline* = object
    version*: int         ## Schema version (currently 1)
    entries*: seq[BaselineEntry]

  RatchetResult* = object
    ok*: bool                           ## true if no violations
    violations*: seq[string]            ## Human-readable violation messages
    newModules*: seq[string]            ## Modules not in baseline
    modifiedModules*: seq[string]       ## Modules whose srcHash changed

# ── JSON Determinism ──────────────────────────────────────────────────────────

func sortKeysRecursive*(node: JsonNode) {.raises: [].} =
  ## Recursively sort all JObject keys alphabetically for canonical output.
  ## Inline copy of the golden_master_capture.nim pattern to avoid
  ## cross-module tool dependency.
  if node == nil: return
  case node.kind
  of JObject:
    var sortedPairs: seq[(string, JsonNode)]
    for k, v in node:
      sortKeysRecursive(v)
      sortedPairs.add((k, v))
    sortedPairs.sort(proc (a, b: (string, JsonNode)): int {.raises: [].} = cmp(a[0], b[0]))
    # Rebuild with sorted keys
    var rebuilt = newJObject()
    for (k, v) in sortedPairs:
      rebuilt[k] = v
    # Swap content into original node
    node[] = rebuilt[]
  of JArray:
    for item in node:
      sortKeysRecursive(item)
  else: discard

# ── Hashing ────────────────────────────────────────────────────────────────────

proc computeSrcHash*(filePath: string): string =
  ## Compute SHA-256 hash of a file's contents.
  result = $secureHash(Sha256, readFile(filePath))

# ── Serialization ──────────────────────────────────────────────────────────────

proc entryToJson(entry: BaselineEntry): JsonNode =
  result = newJObject()
  result["module"] = newJString(entry.module)
  result["coverage"] = newJFloat(entry.coverage)
  result["srcHash"] = newJString(entry.srcHash)
  result["lastCommit"] = newJString(entry.lastCommit)

proc jsonToEntry(node: JsonNode): BaselineEntry =
  result.module = node["module"].getStr()
  result.coverage = node["coverage"].getFloat()
  result.srcHash = node["srcHash"].getStr()
  result.lastCommit = if node.hasKey("lastCommit"): node["lastCommit"].getStr() else: ""

proc loadBaseline*(path: string): Baseline =
  ## Load baseline from a JSON file.
  let content = readFile(path)
  let root = parseJson(content)
  result.version = if root.hasKey("version"): root["version"].getInt() else: 1
  result.entries = @[]
  if root.hasKey("entries"):
    for node in root["entries"]:
      result.entries.add(jsonToEntry(node))

proc saveBaseline*(path: string, baseline: Baseline) =
  ## Save baseline to a JSON file with deterministic output.
  ## Sorts entries by module name and sorts JSON keys recursively
  ## to avoid git diff noise from key reordering.
  var sorted = baseline.entries
  sorted.sort(proc (a, b: BaselineEntry): int = cmp(a.module, b.module))

  let root = newJObject()
  root["version"] = newJInt(baseline.version)
  let arr = newJArray()
  for entry in sorted:
    arr.add(entryToJson(entry))
  root["entries"] = arr

  sortKeysRecursive(root)
  let content = pretty(root, indent = 2) & "\n"
  discard writeFileIdempotent(path, content)

# ── Ratchet Check ─────────────────────────────────────────────────────────────

proc findEntry(baseline: Baseline, module: string): int =
  ## Find entry index by module path. Returns -1 if not found.
  for i, entry in baseline.entries:
    if entry.module == module:
      return i
  return -1

proc checkRatchet*(baseline: Baseline, modulePath: string,
                   currentHash: string): RatchetResult =
  ## Check whether a module's coverage has regressed relative to baseline.
  ##
  ## - If module is new (not in baseline): added to newModules, not a violation.
  ## - If module srcHash matches: source unchanged, no violation.
  ## - If module srcHash differs: source changed, coverage must not drop.
  ##   Coverage data must be provided by the caller via updateBaseline.
  result.ok = true
  result.violations = @[]
  result.newModules = @[]
  result.modifiedModules = @[]

  let idx = findEntry(baseline, modulePath)
  if idx < 0:
    result.newModules.add(modulePath)
    return

  let entry = baseline.entries[idx]
  if entry.srcHash == currentHash:
    return  # source unchanged — no violation possible

  result.modifiedModules.add(modulePath)

  # Source changed — this is informational. The caller should supply
  # current coverage and compare. For now we record it as modified;
  # the gate pipeline decides whether to enforce the ratchet.
  # A violation is reported when the caller explicitly checks coverage
  # via the checkRatchetWithCoverage overload below.

proc checkRatchetWithCoverage*(baseline: Baseline, modulePath: string,
                               currentHash: string,
                               currentCoverage: float): RatchetResult =
  ## Full ratchet check including coverage comparison.
  ## Violation if source changed and coverage dropped.
  result = checkRatchet(baseline, modulePath, currentHash)

  if result.modifiedModules.len == 0:
    return  # new module or unchanged — no further check needed

  let idx = findEntry(baseline, modulePath)
  if idx < 0: return

  let entry = baseline.entries[idx]
  if currentCoverage < entry.coverage:
    result.ok = false
    result.violations.add(
      "Coverage regression: " & modulePath &
      " was " & formatFloat(entry.coverage, ffDecimal, 2) & "%" &
      ", now " & formatFloat(currentCoverage, ffDecimal, 2) & "%"
    )

# ── CLI Entry ──────────────────────────────────────────────────────────────────

proc main() =
  let args = commandLineParams()
  var mode = ""
  var modulePath = ""
  var baselinePath = "data/baseline_ratchet.json"
  var coverage = -1.0

  for arg in args:
    if arg == "--check": mode = "check"
    elif arg == "--update": mode = "update"
    elif arg.startsWith("--module="): modulePath = arg.split("=", 1)[1]
    elif arg.startsWith("--baseline="): baselinePath = arg.split("=", 1)[1]
    elif arg.startsWith("--coverage="):
      try: coverage = parseFloat(arg.split("=", 1)[1])
      except CatchableError: discard  # axiom:best-effort(invalid coverage value)
    elif arg == "--help" or arg == "-h":
      stdout.writeLine("Usage: baseline-ratchet --check --module=<path> [--baseline=<path>]")
      stdout.writeLine("       baseline-ratchet --update --module=<path> --coverage=<pct> [--baseline=<path>]")
      quit(0)

  if modulePath.len == 0:
    stderr.writeLine("[baseline-ratchet] ERROR — --module is required")
    quit(1)

  if not fileExists(baselinePath):
    stderr.writeLine("[baseline-ratchet] WARNING — baseline not found: ", baselinePath)
    stderr.writeLine("[baseline-ratchet] Creating empty baseline")
    saveBaseline(baselinePath, Baseline(version: 1, entries: @[]))

  var baseline = loadBaseline(baselinePath)
  let hash = computeSrcHash(modulePath)

  if mode == "check":
    var result: RatchetResult
    if coverage >= 0:
      result = checkRatchetWithCoverage(baseline, modulePath, hash, coverage)
    else:
      result = checkRatchet(baseline, modulePath, hash)

    if result.newModules.len > 0:
      stdout.writeLine("[baseline-ratchet] NEW — ", result.newModules.join(", "))
    if result.modifiedModules.len > 0:
      stdout.writeLine("[baseline-ratchet] MODIFIED — ", result.modifiedModules.join(", "))
    for v in result.violations:
      stderr.writeLine("[baseline-ratchet] VIOLATION — ", v)

    if not result.ok:
      quit(1)

  elif mode == "update":
    let idx = findEntry(baseline, modulePath)
    if idx >= 0:
      baseline.entries[idx].srcHash = hash
      if coverage >= 0:
        baseline.entries[idx].coverage = coverage
    else:
      baseline.entries.add(BaselineEntry(
        module: modulePath,
        coverage: if coverage >= 0: coverage else: 0.0,
        srcHash: hash,
        lastCommit: ""
      ))
    saveBaseline(baselinePath, baseline)
    stdout.writeLine("[baseline-ratchet] Updated: ", modulePath)

  else:
    stderr.writeLine("[baseline-ratchet] ERROR — specify --check or --update")
    quit(1)

when isMainModule:
  main()

{.pop.}
