## golden_master_capture.nim — Golden Master Snapshot Tool
##
## Reads a Nim module's key procs and captures their JSON output as
## deterministic golden files. Non-deterministic data (timestamps, UUIDs,
## memory addresses, epoch seconds) is masked for stable comparisons.
##
## Usage:
##   nim c -d:allowMissingZ3 -o:bin/golden-master-capture tools/golden_master_capture.nim
##   bin/golden-master-capture --module=<name>
##   bin/golden-master-capture --module=<name> --update-golden
##   bin/golden-master-capture --verify-all
##
## Output: data/golden/<module>.golden.json

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[algorithm, json, os, posix, re, sequtils, strutils, tables, times]

# ── Constants ──────────────────────────────────────────────────────────────────

const
  ToolName = "golden-master-capture"
  GoldenDir = "data/golden"
  TierConfigPath = "data/hotspot_tiers.json"
  DefaultModule = "wf_state"

  ## Regex patterns for non-deterministic data masking
  IsoTimestampPattern* = r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})"
  UuidPattern* = r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
  AddrPattern* = r"0x[0-9a-fA-F]{8,16}"
  EpochPattern* = r"(?<=[\s,:\[])\d{10}(?=[,\]\s}])"

# ── JSON Determinism ──────────────────────────────────────────────────────────

func sortKeysRecursive*(node: JsonNode) {.raises: [].} =
  ## Recursively sort all JObject keys alphabetically for canonical output.
  ## Reuses the pattern from tools/axiom_manifest_merge_driver.nim.
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

# ── Non-Deterministic Data Masking ────────────────────────────────────────────

func maskTimestamps*(s: string): string {.raises: [].} =
  ## Replace ISO 8601 timestamps with <TIMESTAMP> placeholder.
  result = s
  var pattern: Regex
  try:
    pattern = re"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2}))"
  except CatchableError:
    return
  try:
    result = s.replacef(pattern, "<TIMESTAMP>")
  except CatchableError:
    discard  # axiom:best-effort(timestamp-regex-compile-failure: skip masking, return raw string)

func maskUuids*(s: string): string {.raises: [].} =
  ## Replace UUIDs with <UUID> placeholder.
  result = s
  var pattern: Regex
  try:
    pattern = re"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
  except CatchableError:
    return
  try:
    result = s.replacef(pattern, "<UUID>")
  except CatchableError:
    discard  # axiom:best-effort(uuid-regex-compile-failure: skip masking, return raw string)

func maskAddresses*(s: string): string {.raises: [].} =
  ## Replace 0x memory addresses with <ADDR> placeholder.
  result = s
  var pattern: Regex
  try:
    pattern = re"0x[0-9a-fA-F]{8,16}"
  except CatchableError:
    return
  try:
    result = s.replacef(pattern, "<ADDR>")
  except CatchableError:
    discard  # axiom:best-effort(address-regex-compile-failure: skip masking, return raw string)

func maskEpochs*(s: string): string {.raises: [].} =
  ## Replace Unix epoch seconds (10-digit integers in context) with <EPOCH>.
  ## Only masks integers that look like epoch timestamps (between 1500000000
  ## and 2000000000, i.e. 2017–2033 range).
  result = s
  let lines = s.splitLines()
  var masked: seq[string] = @[]
  for line in lines:
    var maskedLine = line
    # Find standalone 10-digit numbers that look like epochs
    for word in maskedLine.split(' '):
      let stripped = word.strip(chars = {'"', ',', ':', '[', ']', '{', '}', ' '})
      if stripped.len == 10:
        try:
          let val = parseInt(stripped)
          if val >= 1_500_000_000 and val <= 2_000_000_000:
            maskedLine = maskedLine.replace(stripped, "<EPOCH>")
        except CatchableError:
          discard  # axiom:best-effort(epoch-parse-failure: non-numeric token, skip this word)
    masked.add(maskedLine)
  result = masked.join("\n")

proc normalizeJson*(node: JsonNode): JsonNode =
  ## Mask all non-deterministic data in a JSON tree, then sort keys.
  ## This produces a canonical representation suitable for golden comparison.
  var normalized = node
  sortKeysRecursive(normalized)
  # Serialize to string, mask, re-parse
  let raw = pretty(normalized, indent = 2)
  var masked = raw
  masked = maskTimestamps(masked)
  masked = maskUuids(masked)
  masked = maskAddresses(masked)
  masked = maskEpochs(masked)
  try:
    result = parseJson(masked)
  except CatchableError:
    # Fallback: return sorted but unmasked
    result = normalized

proc normalizeAndSort*(node: JsonNode): JsonNode =
  ## Alias for normalizeJson — mask + sort for golden comparison.
  result = normalizeJson(node)

# ── Module Introspection ──────────────────────────────────────────────────────

func moduleGoldenPath*(moduleName: string): string =
  ## Build the golden file path for a module.
  result = GoldenDir / (moduleName & ".golden.json")

proc findModulePath*(moduleName: string): string =
  ## Locate a Nim module file by name stem under src/.
  ## Returns the first match, or "" if not found.
  for kind, path in walkDir("src", relative = false):
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

proc loadModuleJson*(modulePath: string): JsonNode =
  ## Load a module's JSON output by parsing its exported types.
  ## Returns a metadata snapshot of the module.
  result = newJObject()
  if not fileExists(modulePath):
    result["error"] = newJString("module not found: " & modulePath)
    return

  let content = readFile(modulePath)
  let lines = content.splitLines()

  # Extract procs/funcs as metadata
  var procs: seq[string] = @[]
  var funcs: seq[string] = @[]
  var linesOfCode = 0

  for line in lines:
    let trimmed = line.strip()
    if trimmed.len == 0 or trimmed.startsWith("##") or trimmed.startsWith("#"):
      continue
    inc linesOfCode
    if trimmed.startsWith("proc ") or trimmed.startsWith("proc["):
      let nameEnd = trimmed.find('(')
      if nameEnd > 4:
        procs.add(trimmed[4 ..< nameEnd].strip())
    elif trimmed.startsWith("func ") or trimmed.startsWith("func["):
      let nameEnd = trimmed.find('(')
      if nameEnd > 4:
        funcs.add(trimmed[4 ..< nameEnd].strip())

  procs.sort()
  funcs.sort()

  let stem = lastPathPart(modulePath).replace(".nim", "")
  result["module"] = newJString(stem)
  result["path"] = newJString(modulePath)
  result["capturedAt"] = newJString(getTime().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'"))
  result["linesOfCode"] = newJInt(linesOfCode)
  result["procCount"] = newJInt(procs.len)
  result["funcCount"] = newJInt(funcs.len)

  let procArray = newJArray()
  for p in procs:
    procArray.add(newJString(p))
  result["procs"] = procArray

  let funcArray = newJArray()
  for f in funcs:
    funcArray.add(newJString(f))
  result["funcs"] = funcArray

# ── Tier Awareness ────────────────────────────────────────────────────────────

proc loadTier1Modules*(): seq[string] =
  ## Load Tier 1 module names from hotspot_tiers.json.
  result = @[]
  if not fileExists(TierConfigPath): return
  try:
    let content = readFile(TierConfigPath)
    let root = parseJson(content)
    let tier1 = root["tiers"]["tier1"]["modules"]
    for entry in tier1:
      if entry.kind == JString:
        let stem = lastPathPart(entry.getStr()).replace(".nim", "")
        result.add(stem)
      elif entry.kind == JObject and entry.hasKey("path"):
        let stem = lastPathPart(entry["path"].getStr()).replace(".nim", "")
        result.add(stem)
  except CatchableError:
    discard  # axiom:best-effort(tier-config-read-failure: no tier modules loaded, gate runs without tier awareness)

# ── Capture & Verify ──────────────────────────────────────────────────────────

proc captureModule*(moduleName: string): (JsonNode, string) =
  ## Capture golden data for a module. Returns (normalizedJson, errorOrEmpty).
  let modulePath = findModulePath(moduleName)
  if modulePath.len == 0:
    return (newJObject(), "module not found: " & moduleName)

  let raw = loadModuleJson(modulePath)
  let normalized = normalizeJson(raw)
  result = (normalized, "")

proc writeGolden*(moduleName: string, data: JsonNode): string =
  ## Write golden file for a module. Returns error or "" on success.
  let dir = GoldenDir
  if not dirExists(dir):
    try:
      createDir(dir)
    except CatchableError as e:
      return "failed to create " & dir & ": " & e.msg

  let path = moduleGoldenPath(moduleName)
  let content = pretty(data, indent = 2)
  try:
    writeFile(path, content & "\n")
  except CatchableError as e:
    return "failed to write " & path & ": " & e.msg
  return ""

proc readGolden*(moduleName: string): (JsonNode, string) =
  ## Read existing golden file. Returns (jsonNode, errorOrEmpty).
  let path = moduleGoldenPath(moduleName)
  if not fileExists(path):
    return (nil, "golden file not found: " & path)
  try:
    let content = readFile(path)
    let node = parseJson(content)
    return (node, "")
  except CatchableError as e:
    return (nil, "failed to parse " & path & ": " & e.msg)

proc compareGolden*(moduleName: string): tuple[ok: bool, diff: string] =
  ## Compare current module output against stored golden file.
  let (current, capErr) = captureModule(moduleName)
  if capErr.len > 0:
    return (false, "capture failed: " & capErr)

  let (golden, readErr) = readGolden(moduleName)
  if readErr.len > 0:
    return (false, "golden read failed: " & readErr)

  let currentStr = pretty(current, indent = 2)
  let goldenStr = pretty(golden, indent = 2)

  if currentStr == goldenStr:
    return (true, "")

  # Find first difference for detailed error
  let currentLines = currentStr.splitLines()
  let goldenLines = goldenStr.splitLines()
  var diffLines: seq[string] = @[]
  let maxLines = max(currentLines.len, goldenLines.len)
  for i in 0 ..< maxLines:
    let c = if i < currentLines.len: currentLines[i] else: "<EOF>"
    let g = if i < goldenLines.len: goldenLines[i] else: "<EOF>"
    if c != g:
      diffLines.add("  line " & $(i + 1) & ":")
      diffLines.add("    got:      " & c)
      diffLines.add("    expected: " & g)
      if diffLines.len > 20:
        diffLines.add("  ... (truncated)")
        break

  return (false, "golden mismatch for " & moduleName & ":\n" & diffLines.join("\n"))

proc verifyAllGolden*(): bool =
  ## Verify all Tier 1 modules have matching golden files.
  ## Returns true if all pass.
  var allPassed = true
  let tier1 = loadTier1Modules()

  if tier1.len == 0:
    stderr.writeLine("[", ToolName, "] WARNING — no Tier 1 modules found in ", TierConfigPath)
    return false

  for moduleName in tier1:
    let goldenPath = moduleGoldenPath(moduleName)
    if not fileExists(goldenPath):
      stderr.writeLine("[", ToolName, "] MISSING golden: ", goldenPath)
      allPassed = false
      continue

    let (ok, diff) = compareGolden(moduleName)
    if ok:
      stdout.writeLine("[", ToolName, "] PASS — ", moduleName)
    else:
      stderr.writeLine("[", ToolName, "] FAIL — ", moduleName)
      stderr.writeLine(diff)
      allPassed = false

  return allPassed

# ── CLI Entry ─────────────────────────────────────────────────────────────────

proc main() =
  let args = commandLineParams()
  var moduleName = ""
  var updateGolden = false
  var verifyAll = false

  for arg in args:
    if arg.startsWith("--module="):
      moduleName = arg.split("=", 1)[1]
    elif arg == "--update-golden":
      updateGolden = true
    elif arg == "--verify-all":
      verifyAll = true
    elif arg == "--help" or arg == "-h":
      stdout.writeLine("Usage: ", ToolName, " --module=<name> [--update-golden]")
      stdout.writeLine("       ", ToolName, " --verify-all")
      stdout.writeLine("")
      stdout.writeLine("Options:")
      stdout.writeLine("  --module=<name>   Module name stem (e.g. wf_state)")
      stdout.writeLine("  --update-golden   Write/refresh golden file")
      stdout.writeLine("  --verify-all      Verify all Tier 1 module golden files")
      stdout.writeLine("  --help            Show this help")
      quit(0)

  if verifyAll:
    if not verifyAllGolden():
      quit(1)
    quit(0)

  if moduleName.len == 0:
    moduleName = DefaultModule

  if updateGolden:
    let (data, err) = captureModule(moduleName)
    if err.len > 0:
      stderr.writeLine("[", ToolName, "] ERROR — ", err)
      quit(1)
    let writeErr = writeGolden(moduleName, data)
    if writeErr.len > 0:
      stderr.writeLine("[", ToolName, "] ERROR — ", writeErr)
      quit(1)
    stdout.writeLine("[", ToolName, "] OK — golden captured for ", moduleName)
    quit(0)
  else:
    # Default: compare against existing golden
    let (ok, diff) = compareGolden(moduleName)
    if ok:
      stdout.writeLine("[", ToolName, "] PASS — ", moduleName, " matches golden")
      quit(0)
    else:
      stderr.writeLine("[", ToolName, "] FAIL — ", moduleName)
      stderr.writeLine(diff)
      quit(1)

when isMainModule:
  main()

{.pop.}
