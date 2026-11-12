import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## architecture_config_gate.nim — Architecture Configuration Gate
##
## Two responsibilities:
##   1. (Gate runner) Check debt_registry.json for runtime-generated
##      timestamp fields that violate determinism guarantees.
##   2. (Test support) Export checkLayerIsolation, checkSsotMutation,
##      extractImports, getDomainPrefix for business-scenario tests.
##
## The architecture-config-gate is registered via registerGate() and runs
## as an in-process gate (tier 1, weight gwMedium).

import gate/gate_contract
import gate/gate_types
import gate/utils/gate_safety_macro
import gate/utils/macro_dispatcher
import std/[json, strutils, os]
import core/trusted/axiom_pragmas

# ─── Types ───────────────────────────────────────────────────────────────────

type
  Violation* = object
    ruleId*: string
    severity*: string
    filePath*: string
    path*: string
    line*: int
    message*: string

# ─── Constants: Timestamp field patterns ─────────────────────────────────────

const RuntimeTimestampPatterns* = [
  "timestamp",
  "generatedAt",
  "lastModified",
  "mtime",
  "updatedAt",
  "firstSeen",
  "lastSeen",
]

const StaticAuditTimestampKeys* = [
  "lastVerifiedAt",
  "resolvedAt",
]
  ## Schema-sanctioned audit metadata: `data/debt_schema.json` defines both
  ## fields on every debt entry, and `docs/spec/debt_registry_schema.md`
  ## requires `lastVerifiedAt` on Theater entries. They are hand-maintained,
  ## git-tracked values — deterministic static state, not runtime-generated
  ## stamps — so the runtime-timestamp rule must not flag them.

func isUnixTimeNumber*(val: JsonNode): bool {.raises: [].} =
  val.kind == JInt and val.num >= 946684800 and val.num <= 2147483647000

func isIso8601Timestamp*(val: JsonNode): bool {.raises: [], axiomDecision(id = "DECISION-0635", reason = "Detect ISO 8601 wall-clock timestamps in git-tracked data so determinism violations are surfaced structurally rather than silently passing", adr = "docs/spec/cert_lifecycle_contracts.md", introduced = "v34").} =
  if val.kind != JString:
    return false
  let s = val.getStr()
  if s.len < 16:
    return false
  if s[4] != '-' or s[7] != '-' or s[10] != 'T':
    return false
  if s[^1] == 'Z':
    return true
  if s.len >= 25 and (s[^5] == '+' or s[^5] == '-') and s[^2] == ':':
    return true
  if s.len >= 20 and (s[^6] == '+' or s[^6] == '-') and s[^3] == ':':
    return true
  false

func hasRuntimeTimestampKey*(key: string): bool {.raises: [].} =
  let lower = key.toLowerAscii()
  for pattern in RuntimeTimestampPatterns:
    if lower.contains(pattern.toLowerAscii()):
      return true
  if key.endsWith("Time") or key.endsWith("At"):
    return true
  return false

func scanJsonForTimestamps*(node: JsonNode; path: string = ""): seq[string] {.raises: [].} =
  case node.kind
  of JObject:
    for key, val in node.pairs:
      let curPath = if path.len == 0: key else: path & "." & key
      if key notin StaticAuditTimestampKeys and
          hasRuntimeTimestampKey(key) and
          (isUnixTimeNumber(val) or isIso8601Timestamp(val)):
        result.add(curPath & " = " & $val)
      result.add(scanJsonForTimestamps(val, curPath))
  of JArray:
    # Index iteration, NOT `for i, item in node`: the two-variable form binds
    # json.nim's pairs() iterator, which asserts kind == Jobject and crashes
    # (AssertionDefect) on any array. Latent since the gate could only run via
    # the hollow-CAS shell — surfaced by the DEBT#497 real-main wiring.
    for i in 0 ..< node.len:
      let item = node[i]
      result.add(scanJsonForTimestamps(item, path & "[" & $i & "]"))
  else:
    discard

# ─── Gate Runner ─────────────────────────────────────────────────────────────

proc run*(gate: GateConfig; ctx: InProcessGateContext): GateResult =
  ## Verify debt_registry.json contains no runtime-generated timestamps.
  ##
  ## Scans the file for field keys matching timestamp patterns whose
  ## values are unix-epoch numbers — evidence of runtime generation
  ## that defeats determinism guarantees.
  let root = ctx.repoRoot
  let registryPath = root / "data" / "debt_registry.json"
  var output = "Architecture Config Gate: checking " & registryPath & "\n"
  var foundTimestamps: seq[string]

  try:
    if not fileExists(registryPath):
      output &= "SKIP: debt_registry.json not found at " & registryPath & "\n"
      return GateResult(
        ok: true, name: "architecture-config-gate",
        stdout: output,
        skipCiRequested: false)
    let content = readFile(registryPath)
    let json = parseJson(content)
    foundTimestamps = scanJsonForTimestamps(json)
  except CatchableError as e:
    return GateResult(
      ok: false, name: "architecture-config-gate",
      stdout: output & "ERROR: " & e.msg,
      failureCategory: fcPermanent,
      failureReason: "Failed to read/parse debt_registry.json: " & e.msg,
      skipCiRequested: false)

  if foundTimestamps.len > 0:
    let details = foundTimestamps.join("\n  ")
    output &= "FAIL: Found " & $foundTimestamps.len & " runtime timestamp(s):\n  " & details & "\n"
    GateResult(
      ok: false, name: "architecture-config-gate",
      stdout: output,
      failureCategory: fcValidation,
      failureReason: "debt_registry.json contains runtime-generated timestamps (" &
                      $foundTimestamps.len & " found). Registry must be deterministic.",
      skipCiRequested: false)
  else:
    output &= "PASS: No runtime timestamps found in debt_registry.json\n"
    GateResult(
      ok: true, name: "architecture-config-gate",
      stdout: output,
      skipCiRequested: false)

# ─── Test-support exports ────────────────────────────────────────────────────
# These are used by tests/gateway/architecture_config_gate_test.nim.

proc extractImports*(content: string): seq[Violation] =
  ## Extract imports from Nim source content.
  ## Returns Violation seq where each entry represents one import.
  for line in content.splitLines:
    let trimmed = line.strip()
    if trimmed.len == 0 or trimmed.startsWith("#"):
      continue
    if trimmed.startsWith("import") or trimmed.startsWith("from"):
      let pathStart = if trimmed.startsWith("import"): 6 else: 4
      var rest = trimmed[pathStart..^1].strip()
      if rest.startsWith("std/") or rest.startsWith("pkg/"):
        continue
      for part in rest.split(','):
        var p = part.strip()
        if p.len == 0:
          continue
        if p.endsWith("import") or p.endsWith(".."):
          continue
        result.add(Violation(
          ruleId: "import-extraction",
          severity: "info",
          filePath: p,
          path: p,
          message: "import " & p))
  if result.len == 0:
    result.add(Violation(
      ruleId: "import-extraction",
      severity: "info",
      filePath: "none",
      path: "none",
      message: "no imports found"))

proc checkLayerIsolation*(repoRoot: string; config: JsonNode): seq[Violation] =
  ## Check that files under the rule's source directory do not import
  ## from forbidden directories. Uses extractImports logic.
  result = @[]
  let rules = config.getOrDefault("rules")
  if rules.isNil:
    return
  let rule = rules.getOrDefault("layer-isolation")
  if rule.isNil:
    return
  let source = rule.getOrDefault("source").getStr("")
  if source.len == 0:
    return
  let forbiddenNode = rule.getOrDefault("forbidden")
  if forbiddenNode.isNil:
    return
  var forbidden: seq[string]
  for item in forbiddenNode.items:
    forbidden.add(item.getStr())
  if forbidden.len == 0:
    return
  var exempt: seq[string]
  let exemptNode = rule.getOrDefault("exempt")
  if not exemptNode.isNil:
    for item in exemptNode.items:
      exempt.add(item.getStr())

  let checkDir = repoRoot / source
  var files: seq[string]
  try:
    for entryKind, fp in walkDir(checkDir):
      if entryKind == pcFile and fp.endsWith(".nim"):
        files.add(fp)
  except CatchableError:
    return

  for fp in files:
    let content = try: readFile(fp) except CatchableError: ""
    if content.len == 0:
      continue
    let imports = extractImports(content)
    for imp in imports:
      for fb in forbidden:
        if imp.filePath.startsWith(fb):
          var exempted = false
          for ex in exempt:
            if fp.contains(ex):
              exempted = true
              break
          if not exempted:
            result.add(Violation(
              ruleId: "layer-isolation",
              severity: "error",
              filePath: fp,
              message: "forbidden import: " & imp.filePath & " (imports from " & fb & ")"))

proc checkSsotMutation*(repoRoot: string; config: JsonNode): seq[Violation] =
  ## Check that SSOT mutation patterns (like cert.status =) only appear
  ## in exempted files (like certificate_manager.nim).
  result = @[]
  let rules = config.getOrDefault("rules")
  if rules.isNil:
    return
  let rule = rules.getOrDefault("ssot-mutation")
  if rule.isNil:
    return
  let patternsNode = rule.getOrDefault("patterns")
  if patternsNode.isNil:
    return
  var patterns: seq[string]
  for item in patternsNode.items:
    patterns.add(item.getStr())
  if patterns.len == 0:
    return
  var exemptFiles: seq[string]
  let exemptNode = rule.getOrDefault("exempt_files")
  if not exemptNode.isNil:
    for item in exemptNode.items:
      exemptFiles.add(item.getStr())

  var allNimFiles: seq[string]
  try:
    for fp in walkDirRec(repoRoot):
      if fp.endsWith(".nim"):
        allNimFiles.add(fp)
  except CatchableError:
    return

  for fp in allNimFiles:
    var exempted = false
    for ex in exemptFiles:
      if fp.contains(ex):
        exempted = true
        break
    if exempted:
      continue
    let content = try: readFile(fp) except CatchableError: ""
    if content.len == 0:
      continue
    for line in content.splitLines:
      for pat in patterns:
        if line.contains(pat):
          result.add(Violation(
            ruleId: "ssot-mutation",
            severity: "error",
            filePath: fp,
            message: "SSOT mutation pattern found: " & pat))

func getDomainPrefix*(path: string): string {.raises: [].} =
  ## Extract the second segment of a module path as the domain prefix.
  ## e.g. "core/bmc/foo" → "bmc", "cli/topology" → "topology"
  let parts = path.split('/')
  if parts.len >= 2:
    result = parts[1]
  else:
    result = parts[0]

# ─── Compile-Time Registration ───────────────────────────────────────────────

registerGate("architecture-config-gate", run)

# ─── Standalone Entry (DEBT#497 follow-up) ──────────────────────────────────

proc main() {.raises: [CatchableError].} =
  ## Real standalone entry: every AOT link of this module now carries the
  ## actual judgment. Previously the module was registerGate-only, so a
  ## standalone link produced an empty 31,872-byte exit-0 binary — the
  ## subprocess CAS path executed nothing and reported PASS (DEBT#497
  ## measured hollow-CAS shape). This module is not wired into manifest.d,
  ## so it cannot be dispatched in-process (DEBT#270 manifest↔runner 1:1
  ## invariant); a real main is the closure for its hollow-CAS exposure.
  let ctx = InProcessGateContext(
    repoRoot: getCurrentDir(),
    stagedFiles: @[],
    gateId: "architecture-config-gate",
    epoch: 0,
    dirtyHash: "",
    subtreeRoot: "",
    stage: 0,
    maxJobs: 1,
    passFilenames: false,
    effectiveTimeoutMs: 0)
  let res = run(GateConfig(), ctx)
  stdout.write(res.stdout)
  quit(if res.ok: 0 else: 1)

when isMainModule:
  main()

{.pop.}
