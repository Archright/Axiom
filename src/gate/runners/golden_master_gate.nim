## Golden Master Gate — Verifies golden files exist for Tier 1 modules
##
## Reads data/hotspot_tiers.json for the Tier 1 module list,
## checks data/golden/<module>.golden.json exists for each,
## and optionally verifies content matches current output.
##
## Exit 0 if all Tier 1 modules have golden files; exit 1 otherwise.
##
## Usage:
##   golden-master-gate                    — check golden file existence
##   golden-master-gate <repoRoot>         — check in specified repo
##   golden-master-gate --verify           — also compare content
##   golden-master-gate --self-test        — run built-in self-test

import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import std/[algorithm, json, os, sequtils, strutils, tables]
import core/axiom_pragmas
import infrastructure/logging_facade



const
  GateName = "golden-master-gate"
  GoldenDir = "data/golden"
  TierConfigPath = "data/hotspot_tiers.json"

# ── Helpers ───────────────────────────────────────────────────────────────────

proc sortKeysRecursive(node: JsonNode) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Canonicalize JSON key order for deterministic comparison.
  if node == nil: return
  case node.kind
  of JObject:
    var pairs: seq[(string, JsonNode)]
    for k, v in node.fields:
      sortKeysRecursive(v)
      pairs.add((k, v))
    pairs.sort(proc (a, b: (string, JsonNode)): int {.raises: [].} = cmp(a[0], b[0]))
    node.fields.clear()
    for (k, v) in pairs:
      node.fields[k] = v
  of JArray:
    for item in node.elems:
      sortKeysRecursive(item)
  else: discard

proc loadTier1Modules(repoRoot: string): seq[string] {.axiomEffect: IOEffect.} =
  ## Load Tier 1 module name stems from hotspot_tiers.json.
  result = @[]
  let configPath = repoRoot / TierConfigPath
  if not fileExists(configPath): return
  try:
    let content = readFile(configPath)
    let root = parseJson(content)
    let tier1 = root["tiers"]["tier1"]["modules"]
    for entry in tier1:
      if entry.kind == JObject and entry.hasKey("path"):
        let p = entry["path"].getStr()
        let stem = lastPathPart(p).replace(".nim", "")
        result.add(stem)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc goldenPath(repoRoot, moduleName: string): string =
  result = repoRoot / GoldenDir / (moduleName & ".golden.json")

proc loadGolden(repoRoot, moduleName: string): (JsonNode, string) {.axiomEffect: IOEffect.} =
  let path = goldenPath(repoRoot, moduleName)
  if not fileExists(path):
    return (nil, "golden file not found: " & path)
  try:
    let content = readFile(path)
    let node = parseJson(content)
    sortKeysRecursive(node)
    return (node, "")
  except CatchableError as e:
    return (nil, "failed to parse " & path & ": " & e.msg)

proc loadModuleSnapshot(repoRoot, moduleName: string): (JsonNode, string) {.axiomEffect: IOEffect.} =
  ## Build a module snapshot from source (same logic as capture tool).
  result = (newJObject(), "")
  # Search for module file under src/
  var modulePath = ""
  for kind, path in walkDir(repoRoot / "src", relative = false):
    if kind == pcDir:
      for kind2, path2 in walkDir(path, relative = false):
        if kind2 == pcFile and path2.endsWith(".nim"):
          if lastPathPart(path2).replace(".nim", "") == moduleName:
            modulePath = path2
            break
        if kind2 == pcDir and modulePath.len == 0:
          for kind3, path3 in walkDir(path2, relative = false):
            if kind3 == pcFile and path3.endsWith(".nim"):
              if lastPathPart(path3).replace(".nim", "") == moduleName:
                modulePath = path3
                break
    if modulePath.len > 0: break

  if modulePath.len == 0:
    return (nil, "module not found: " & moduleName)

  try:
    let content = readFile(modulePath)
    let lines = content.splitLines()
    var procs: seq[string] = @[]
    var funcs: seq[string] = @[]
    var loc = 0
    for line in lines:
      let trimmed = line.strip()
      if trimmed.len == 0 or trimmed.startsWith("##") or trimmed.startsWith("#"):
        continue
      inc loc
      if trimmed.startsWith("proc ") or trimmed.startsWith("proc["):
        let idx = trimmed.find('(')
        if idx > 4: procs.add(trimmed[4 ..< idx].strip())
      elif trimmed.startsWith("func ") or trimmed.startsWith("func["):
        let idx = trimmed.find('(')
        if idx > 4: funcs.add(trimmed[4 ..< idx].strip())
    procs.sort()
    funcs.sort()
    let snapshot = newJObject()
    snapshot["module"] = newJString(moduleName)
    snapshot["path"] = newJString(modulePath)
    snapshot["linesOfCode"] = newJInt(loc)
    snapshot["procCount"] = newJInt(procs.len)
    snapshot["funcCount"] = newJInt(funcs.len)
    let pa = newJArray()
    for p in procs: pa.add(newJString(p))
    snapshot["procs"] = pa
    let fa = newJArray()
    for f in funcs: fa.add(newJString(f))
    snapshot["funcs"] = fa
    sortKeysRecursive(snapshot)
    return (snapshot, "")
  except CatchableError as e:
    return (nil, "failed to read " & modulePath & ": " & e.msg)

# ── Gate Logic ────────────────────────────────────────────────────────────────

type
  GateResult = object
    passed: bool
    total: int
    present: int
    missing: seq[string]
    mismatched: seq[string]

proc runGate(repoRoot: string, verifyContent: bool = false): GateResult {.axiomEffect: IOEffect.} =
  result.passed = true
  result.total = 0
  result.present = 0
  result.missing = @[]
  result.mismatched = @[]

  let tier1 = loadTier1Modules(repoRoot)
  if tier1.len == 0:
    stdout.writeLine("[", GateName, "] PASS — no Tier 1 modules defined in ", TierConfigPath)
    return

  result.total = tier1.len

  for moduleName in tier1:
    let gp = goldenPath(repoRoot, moduleName)
    if not fileExists(gp):
      result.missing.add(moduleName)
      logInfo("golden_master_gate", "[" & $(GateName) & "] MISSING — " & $(moduleName) & " (" & $(gp) & ")")
      continue

    inc result.present

    if verifyContent:
      let (golden, gErr) = loadGolden(repoRoot, moduleName)
      if gErr.len > 0:
        result.mismatched.add(moduleName & ": " & gErr)
        logError("golden_master_gate", "[" & $(GateName) & "] ERROR — " & $(moduleName) & ": " & $(gErr))
        continue

      let (current, cErr) = loadModuleSnapshot(repoRoot, moduleName)
      if cErr.len > 0:
        result.mismatched.add(moduleName & ": " & cErr)
        logError("golden_master_gate", "[" & $(GateName) & "] ERROR — " & $(moduleName) & ": " & $(cErr))
        continue

      let goldenStr = pretty(golden, indent = 2)
      let currentStr = pretty(current, indent = 2)
      if goldenStr != currentStr:
        result.mismatched.add(moduleName)
        logInfo("golden_master_gate", "[" & $(GateName) & "] MISMATCH — " & $(moduleName))

  result.passed = result.missing.len == 0 and result.mismatched.len == 0

  # Summary
  let missingCount = result.missing.len
  let mismatchCount = result.mismatched.len
  if result.passed:
    stdout.writeLine("[", GateName, "] PASS — ", $result.present, "/",
                $result.total, " Tier 1 modules have golden files")
  else:
    logError("golden_master_gate", "[" & $(GateName) & "] FAIL — " & $missingCount & " missing, " & $mismatchCount & " mismatched out of " & $result.total & " Tier 1 modules")

# ── Self-Test ─────────────────────────────────────────────────────────────────

proc selfTest() {.axiomEffect: IOEffect.} =
  var allPassed = true

  # Test 1: loadTier1Modules with valid config
  block:
    let tier1 = loadTier1Modules(".")
    if tier1.len == 0:
      logError("golden_master_gate", "[self-test] FAIL — expected >0 Tier 1 modules")
      allPassed = false
    else:
      stdout.writeLine("[self-test] PASS — loaded ", $tier1.len, " Tier 1 modules")

  # Test 2: goldenPath construction
  block:
    let p = goldenPath("/repo", "my_module")
    if p != "/repo/data/golden/my_module.golden.json":
      logError("golden_master_gate", "[self-test] FAIL — unexpected golden path: " & $(p))
      allPassed = false
    else:
      stdout.writeLine("[self-test] PASS — goldenPath works")

  # Test 3: sortKeysRecursive determinism
  block:
    let node = %*{"z": 1, "a": 2, "m": 3}
    sortKeysRecursive(node)
    let keys = toSeq(node.fields.keys)
    if keys != @["a", "m", "z"]:
      logError("golden_master_gate", "[self-test] FAIL — keys not sorted: " & $keys)
      allPassed = false
    else:
      stdout.writeLine("[self-test] PASS — sortKeysRecursive works")

  if allPassed:
    stdout.writeLine("[", GateName, "] self-test PASS")
    quit(0)
  else:
    logError("golden_master_gate", "[" & $(GateName) & "] self-test FAIL")
    quit(1)

# ── Main ──────────────────────────────────────────────────────────────────────

proc main() =
  let args = commandLineParams()

  if args.len > 0 and args[0] == "--self-test":
    selfTest()
    return

  var repoRoot = getCurrentDir()
  var verifyContent = false

  for arg in args:
    if arg == "--verify":
      verifyContent = true
    elif not arg.startsWith("-") and arg.len > 0:
      repoRoot = expandFilename(arg)

  try:
    let result = runGate(repoRoot, verifyContent)
    if not result.passed:
      quit(1)
    quit(0)
  except CatchableError as e:
    logError("golden_master_gate", "[" & $(GateName) & "] ERROR — " & $(e.msg))
    quit(1)

when isMainModule:
  main()

{.pop.}
