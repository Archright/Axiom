## selection-report — S2 Local/CI Parity Machinery
##
## Emits a deterministic JSON report for the 4-step parity gate.
##
## Usage:
##   selection-report --base <ref> --head <ref> [--output <path>] [--symbols-file <path>]
##   selection-report --base main --head HEAD --symbols-file fixtures/symbols.json
##
## Exit codes (mirror impact_closure_selector contract):
##   0 — planStatus VALID (ssValid)
##   2 — planStatus FALLBACK_REQUIRED (ssFallbackRequired)
##   1 — error (argument, I/O, internal)
##
## --symbols-file JSON schema:
##   {
##     "symbolDeps":        { "symA": ["symB"], ... },
##     "symbolDependents":  { "symB": ["symA"], ... },
##     "fileSymbols":       { "src/core/foo.nim": ["src/core/foo.nim::bar"], ... }
##   }
##
## Design invariants:
##   - All digests are functions of SEMANTIC inputs only (no absolute paths,
##     hostnames, timestamps, PIDs). See canonical_execution_semantics.md §3.
##   - Keys in JSON output are sorted deterministically.
##   - Incidental state (working-tree mtime, .git/index) is excluded.
##
## The pure builders live in src/verification/selection/selection_builders.nim;
## this tool is a thin I/O shell over them.

import core/trusted/layer_declaration
import core/trusted/axiom_pragmas_lite
axiomLayer "tools"

import std/[os, osproc, strutils, strformat, json, tables, sequtils, sets, algorithm,
            options, parseopt, times]

# ═══════════════════════════════════════════════════════════════════════════
# §0: Compile-time guard
# ═══════════════════════════════════════════════════════════════════════════

static:
  when NimMajor != 2 or NimMinor != 2:
    {.error: "selection-report requires Nim v2.2.x".}

# ═══════════════════════════════════════════════════════════════════════════
# §1: Imports from project source
# ═══════════════════════════════════════════════════════════════════════════

import core/types/canonical_change_set
import core/types/graph_artifact
import core/types/selection_derivation
import core/types/execution_plan
import core/topology/topology_types
import core/trusted/scope_identity
import verification/selection/selection_engine
import verification/selection/selection_builders
import verification/selection/selection_digests

# ═══════════════════════════════════════════════════════════════════════════
# §2: Types
# ═══════════════════════════════════════════════════════════════════════════

type
  SymbolsFile* = object
    symbolDeps*: Table[string, seq[string]]
    symbolDependents*: Table[string, seq[string]]
    fileSymbols*: Table[string, seq[string]]

# ═══════════════════════════════════════════════════════════════════════════
# §3: Git helpers (I/O boundary, proc)
# ═══════════════════════════════════════════════════════════════════════════

proc runGit*(args: string): string {.axiomEffect: IoEffect.} =
  ## Run a git command and return trimmed stdout. Raises on failure.
  let cmd = "git " & args
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    raise newException(OSError, &"git {args} failed (exit {exitCode}): {output.strip()}")
  result = output.strip()

proc getDiffStatusEntrys*(base, head: string): seq[DiffStatusEntry] {.axiomEffect: IoEffect.} =
  ## Get changed files between base and head via git diff --name-status.
  ## Blob hash obtained via git ls-tree HEAD -- <path>.
  let diffOutput = runGit(&"diff --name-status {base}..{head}")
  if diffOutput.len == 0:
    return @[]

  for line in diffOutput.splitLines():
    let parts = line.split('\t')
    if parts.len < 2:
      continue
    let status = parts[0].strip()
    let filePath = parts[1].strip()
    if filePath.len == 0:
      continue

    var blobHash = ""
    try:
      let treeOutput = runGit(&"ls-tree HEAD -- {filePath}")
      let treeParts = treeOutput.split('\t')
      if treeParts.len >= 1:
        let headerParts = treeParts[0].split(' ')
        if headerParts.len >= 3:
          blobHash = headerParts[2]
    except CatchableError:
      blobHash = "000000000000000000000000000000000000"

    result.add DiffStatusEntry(path: filePath, status: status, blobHash: blobHash)

  result.sort(proc(a, b: DiffStatusEntry): int = cmp(a.path, b.path))

proc getMergeBase*(base, head: string): seq[string] {.axiomEffect: IoEffect.} =
  ## Run git merge-base and return sorted merge-base commits.
  ## Handles multiple outputs deterministically (octopus merge).
  let output = runGit(&"merge-base {base} {head}")
  if output.len == 0:
    return @[]
  result = output.splitLines().mapIt(it.strip()).filterIt(it.len > 0)
  result.sort(cmp)

# ═══════════════════════════════════════════════════════════════════════════
# §4: Universe digest from verification_scope.lock
# ═══════════════════════════════════════════════════════════════════════════

proc loadVerificationScope*(lockPath: string): (seq[string], int, int) =
  ## Load kernel_symbols, kernel_total, vksTotal from verification_scope.lock.
  ## Returns (kernelSymbols, kernelTotal, vksTotal).
  let content = readFile(lockPath)
  let root = parseJson(content)

  let kernelSymbols = if root.hasKey("kernel_symbols") and root["kernel_symbols"].kind == JArray:
    root["kernel_symbols"].getElems().mapIt(it.getStr())
  else:
    @[]

  let kernelTotal = if root.hasKey("kernel_total"): root["kernel_total"].getInt() else: kernelSymbols.len
  let vksTotal = if root.hasKey("vksTotal"): root["vksTotal"].getInt()
                elif root.hasKey("vks_total"): root["vks_total"].getInt()
                else: 0

  (kernelSymbols, kernelTotal, vksTotal)

proc computeUniverseDigest*(lockPath: string): string =
  ## Compute universeDigest from verification_scope.lock (pure part in builders).
  let (kernelSymbols, kernelTotal, vksTotal) = loadVerificationScope(lockPath)
  computeUniverseDigest(kernelSymbols, kernelTotal, vksTotal)

# ═══════════════════════════════════════════════════════════════════════════
# §5: Toolchain version strings (semantic; used in report toolchain section)
# ═══════════════════════════════════════════════════════════════════════════

proc nimVersionString*(): string =
  &"{NimMajor}.{NimMinor}.{NimPatch}"

proc leanVersionString*(): string =
  try:
    let content = readFile("lean-toolchain")
    let line = content.strip().splitLines()[0]
    if ":" in line:
      result = line.split(":")[^1]
    elif "/" in line:
      result = line.split("/")[^1]
    else:
      result = line
  except CatchableError:
    result = ""

# ═══════════════════════════════════════════════════════════════════════════
# §6: CLI entry point
# ═══════════════════════════════════════════════════════════════════════════

proc printHelp() =
  echo ""
  echo "  selection-report — S2 Local/CI Parity Machinery"
  echo ""
  echo "  Emits a deterministic JSON report for the 4-step parity gate."
  echo ""
  echo "  Usage:"
  echo "    selection-report --base <ref> --head <ref> [--output <path>] [--symbols-file <path>] [--plan-out <path>]"
  echo ""
  echo "  Options:"
  echo "    --base <ref>          Base ref for diff (required)"
  echo "    --head <ref>          Head ref for diff (default: HEAD)"
  echo "    --output <path>       Output JSON report path"
  echo "                          (default: docs/reports/selection_report_<date>.json)"
  echo "    --symbols-file <path> Path to symbols-file JSON (required)"
  echo "    --plan-out <path>     If given, also write ExecutionPlan JSON to this path"
  echo "                          for downstream consumption by --plan-based verify"
  echo "    --help, -h            Show this help"
  echo ""
  echo "  Exit codes:"
  echo "    0 — planStatus VALID (ssValid)"
  echo "    2 — planStatus FALLBACK_REQUIRED (ssFallbackRequired)"
  echo "    1 — error"
  echo ""
  echo "  --symbols-file JSON schema:"
  echo "    {"
  echo "      \"symbolDeps\":        { \"symA\": [\"symB\"], ... },"
  echo "      \"symbolDependents\":  { \"symB\": [\"symA\"], ... },"
  echo "      \"fileSymbols\":       { \"src/core/foo.nim\": [\"src/core/foo.nim::bar\"], ... }"
  echo "    }"
  echo ""

proc main() =
  var baseRef = ""
  var headRef = "HEAD"
  var outputPath = ""
  var symbolsFilePath = ""
  var planOutPath = ""
  var showHelp = false

  var p = initOptParser(commandLineParams(),
                        shortNoVal = {'h'},
                        longNoVal = @["help"])
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "base", "b":
        baseRef = p.val
      of "head", "H":
        headRef = p.val
      of "output", "o":
        outputPath = p.val
      of "symbols-file", "s":
        symbolsFilePath = p.val
      of "plan-out":
        planOutPath = p.val
      of "help", "h":
        showHelp = true
      else:
        echo &"[selection-report] Unknown option: {p.key}"
        showHelp = true
    of cmdArgument:
      if baseRef.len == 0:
        baseRef = p.key
      elif headRef == "HEAD":
        headRef = p.key

  if showHelp or baseRef.len == 0:
    printHelp()
    if baseRef.len == 0 and not showHelp:
      quit(1)
    return

  # --- Step 1: Determine repo root ---
  var repoRoot = getCurrentDir()
  for _ in 0 ..< 10:
    if dirExists(repoRoot / ".axiom_root"):
      break
    let parent = repoRoot.parentDir()
    if parent == repoRoot:
      break
    repoRoot = parent

  # --- Step 2: Default output path ---
  if outputPath.len == 0:
    let dateStr = now().utc().format("yyyy-MM-dd")
    outputPath = repoRoot / "docs/reports" / &"selection_report_{dateStr}.json"

  # --- Step 3: Ensure output directory exists ---
  let outDir = outputPath.parentDir()
  if not dirExists(outDir):
    createDir(outDir)

  # --- Step 4: Get changed files ---
  let changedFiles = getDiffStatusEntrys(baseRef, headRef)

  # --- Step 5: Get merge base ---
  let mergeBase = getMergeBase(baseRef, headRef)

  # --- Step 6: Build CanonicalChangeSet ---
  let changeSet = buildCanonicalChangeSet(baseRef, headRef, mergeBase, changedFiles)
  let changeSetDigest = computeChangeSetDigest(changeSet)

  # --- Step 7: Load symbols-file (required) ---
  if symbolsFilePath.len == 0:
    echo "[selection-report] ERROR: --symbols-file is required."
    echo "  A full topology scan is too heavy to run inline; provide a symbols-file JSON."
    echo "  See --help for the schema."
    quit(1)

  if not fileExists(symbolsFilePath):
    echo &"[selection-report] ERROR: symbols-file not found: {symbolsFilePath}"
    quit(1)

  let symbolsContent = readFile(symbolsFilePath)
  let symbolsRoot = parseJson(symbolsContent)

  var symbolsFile = SymbolsFile(
    symbolDeps: initTable[string, seq[string]](),
    symbolDependents: initTable[string, seq[string]](),
    fileSymbols: initTable[string, seq[string]]())

  if symbolsRoot.hasKey("symbolDeps") and symbolsRoot["symbolDeps"].kind == JObject:
    for key, val in symbolsRoot["symbolDeps"]:
      if val.kind == JArray:
        symbolsFile.symbolDeps[key] = val.getElems().mapIt(it.getStr())

  if symbolsRoot.hasKey("symbolDependents") and symbolsRoot["symbolDependents"].kind == JObject:
    for key, val in symbolsRoot["symbolDependents"]:
      if val.kind == JArray:
        symbolsFile.symbolDependents[key] = val.getElems().mapIt(it.getStr())

  if symbolsRoot.hasKey("fileSymbols") and symbolsRoot["fileSymbols"].kind == JObject:
    for key, val in symbolsRoot["fileSymbols"]:
      if val.kind == JArray:
        symbolsFile.fileSymbols[key] = val.getElems().mapIt(it.getStr())

  # --- Step 8: Build GraphArtifact ---
  let graphArtifact = buildGraphArtifact(
    symbolsFile.symbolDeps, symbolsFile.symbolDependents)
  let graphDigest = computeGraphDigest(graphArtifact)

  # --- Step 9: Load universe and compute universeDigest ---
  let lockPath = repoRoot / "data" / "verification_scope.lock"
  let (universe, _, _) = loadVerificationScope(lockPath)
  let universeDigest = computeUniverseDigest(lockPath)

  # --- Step 10: Derive changed symbol seeds ---
  var universeSet = initHashSet[string]()
  for sym in universe:
    universeSet.incl(sym)

  let (changedSymbolSeeds, unmappedDiffStatusEntrys) = deriveChangedSymbolSeeds(
    changedFiles, symbolsFile.fileSymbols, universeSet)

  # --- Step 11: Run selection engine ---
  let selectorInputs = SelectorInputs(
    changeSet: changeSet,
    graph: graphArtifact,
    symbolDeps: symbolsFile.symbolDeps,
    symbolDependents: symbolsFile.symbolDependents,
    universe: universe,
    policyDigest: SelectionPolicyDigest,
    changedSymbolSeeds: changedSymbolSeeds)

  let outcome = computeSelection(selectorInputs)

  # --- Step 12: Build report JSON ---
  # semanticInputIdentity
  let semanticInputIdentity = %*{
    "changeSetDigest": changeSetDigest,
    "graphDigest": graphDigest,
    "universeDigest": universeDigest,
    "policyDigest": SelectionPolicyDigest}

  # selection
  let selectedIds = outcome.derivation.selected.mapIt(it.unitId)
  let excludedIds = outcome.derivation.excluded.mapIt(it[0])
  let selectionNode = %*{
    "status": selectionStatusToString(outcome.derivation.status),
    "selected": selectedIds.sorted(cmp),
    "excluded": excludedIds.sorted(cmp),
    "derivationDigest": computeSelectionDerivationDigest(outcome.derivation),
    "witnessDigest": outcome.derivation.witnessDigest,
    "fallbackReason": outcome.derivation.fallbackReason}

  # plan
  let planNode = %*{
    "mode": universeModeToString(outcome.plan.mode),
    "unitIds": outcome.plan.selectedUnitIds.sorted(cmp),
    "planDigest": outcome.plan.planDigest}

  # toolchain
  let toolchainNode = %*{
    "nimVersion": nimVersionString(),
    "leanVersion": leanVersionString()}

  # Full report
  let report = %*{
    "semanticInputIdentity": semanticInputIdentity,
    "selection": selectionNode,
    "plan": planNode,
    "unmappedDiffStatusEntrys": unmappedDiffStatusEntrys.sorted(cmp),
    "toolchain": toolchainNode}

  # Write output
  let prettyJson = pretty(report, 2)
  writeFile(outputPath, prettyJson)

  echo &"[selection-report] Report written to: {outputPath}"
  echo &"[selection-report] planStatus: {selectionStatusToString(outcome.derivation.status)}"
  echo &"[selection-report] selectionDigest: {outcome.plan.planIdentity.selectionDigest}"

  # --plan-out: write the full ExecutionPlan JSON for downstream consumption
  if planOutPath.len > 0:
    let planOutDir = planOutPath.parentDir()
    if not dirExists(planOutDir):
      createDir(planOutDir)
    let planJson = pretty(outcome.plan.toJson(), 2)
    writeFile(planOutPath, planJson)
    echo &"[selection-report] ExecutionPlan written to: {planOutPath}"

  # Exit contract
  case outcome.derivation.status
  of ssValid:
    quit(0)
  of ssFallbackRequired:
    quit(2)
  of ssError:
    quit(1)

when isMainModule:
  main()
