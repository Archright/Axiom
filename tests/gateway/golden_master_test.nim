{.push raises: [CatchableError].}

## Golden Master Test — Reads golden files from data/golden/ and compares
## with current module output using normalizeAndSort().
## Fails on diff with detailed error.

import std/[algorithm, json, os, sequtils, strutils, tables, unittest]

const
  projectRoot = currentSourcePath().parentDir().parentDir().parentDir()
  GoldenDir = projectRoot / "data" / "golden"
  TierConfigPath = projectRoot / "data" / "hotspot_tiers.json"

# ── Helpers (reused from tools/golden_master_capture.nim) ──────────────────────

func sortKeysRecursive(node: JsonNode) {.raises: [].} =
  if node == nil: return
  case node.kind
  of JObject:
    var sortPairs: seq[(string, JsonNode)]
    for k, v in node.fields:
      sortKeysRecursive(v)
      sortPairs.add((k, v))
    sortPairs.sort(proc (a, b: (string, JsonNode)): int {.raises: [].} = cmp(a[0], b[0]))
    node.fields.clear()
    for (k, v) in sortPairs:
      node.fields[k] = v
  of JArray:
    for item in node.elems:
      sortKeysRecursive(item)
  else: discard

func normalizeAndSort(node: JsonNode): JsonNode {.raises: [].} =
  var copy = node
  sortKeysRecursive(copy)
  copy

proc loadTier1Modules(): seq[string] =
  result = @[]
  if not fileExists(TierConfigPath): return
  try:
    let content = readFile(TierConfigPath)
    let root = parseJson(content)
    let tier1 = root["tiers"]["tier1"]["modules"]
    for entry in tier1:
      if entry.kind == JObject and entry.hasKey("path"):
        let stem = lastPathPart(entry["path"].getStr()).replace(".nim", "")
        result.add(stem)
  except CatchableError:
    discard

proc findModulePath(moduleName: string): string =
  for kind, path in walkDir(projectRoot / "src", relative = false):
    if kind == pcDir:
      for kind2, path2 in walkDir(path, relative = false):
        if kind2 == pcFile and path2.endsWith(".nim"):
          let stem = lastPathPart(path2).replace(".nim", "")
          if stem == moduleName:
            return path2
        if kind2 == pcDir:
          for kind3, path3 in walkDir(path2, relative = false):
            if kind3 == pcFile and path3.endsWith(".nim"):
              let stem = lastPathPart(path3).replace(".nim", "")
              if stem == moduleName:
                return path3
  return ""

proc loadModuleSnapshot(modulePath: string): JsonNode =
  result = newJObject()
  if not fileExists(modulePath):
    result["error"] = newJString("module not found")
    return
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
  let stem = lastPathPart(modulePath).replace(".nim", "")
  result["module"] = newJString(stem)
  result["path"] = newJString(modulePath)
  result["linesOfCode"] = newJInt(loc)
  result["procCount"] = newJInt(procs.len)
  result["funcCount"] = newJInt(funcs.len)
  let pa = newJArray()
  for p in procs: pa.add(newJString(p))
  result["procs"] = pa
  let fa = newJArray()
  for f in funcs: fa.add(newJString(f))
  result["funcs"] = fa

# ── Test Suite ────────────────────────────────────────────────────────────────

suite "golden master — file presence":
  test "golden directory exists":
    check dirExists(GoldenDir)

  test "Tier 1 modules have golden files":
    let tier1 = loadTier1Modules()
    check tier1.len > 0
    for moduleName in tier1:
      let goldenPath = GoldenDir / (moduleName & ".golden.json")
      check fileExists(goldenPath)

suite "golden master — determinism":
  test "normalizeAndSort produces canonical JSON":
    let node = %*{"b": 1, "a": 2, "c": {"z": true, "a": false}}
    let normalized = normalizeAndSort(node)
    let keys = toSeq(normalized.fields.keys)
    check keys == @["a", "b", "c"]
    let innerKeys = toSeq(normalized["c"].fields.keys)
    check innerKeys == @["a", "z"]

  test "golden files parse as valid JSON":
    let tier1 = loadTier1Modules()
    for moduleName in tier1:
      let goldenPath = GoldenDir / (moduleName & ".golden.json")
      let content = readFile(goldenPath)
      let node = parseJson(content)
      check node != nil

suite "golden master — comparison":
  test "Tier 1 modules match their golden files":
    let tier1 = loadTier1Modules()
    check tier1.len > 0
    for moduleName in tier1:
      let goldenPath = GoldenDir / (moduleName & ".golden.json")
      let goldenContent = readFile(goldenPath)
      let golden = normalizeAndSort(parseJson(goldenContent))

      let modulePath = findModulePath(moduleName)
      check modulePath.len > 0
      let current = normalizeAndSort(loadModuleSnapshot(modulePath))

      # Compare normalized outputs (excluding volatile fields)
      let currentStr = pretty(current, indent = 2)
      let goldenStr = pretty(golden, indent = 2)
      check currentStr == goldenStr

{.pop.}
