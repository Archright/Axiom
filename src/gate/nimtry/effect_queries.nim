import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

import core/gate/architecture_policy
import gate/architecture_ast_facts
import gate/nimtry/call_graph
import gate/nimtry/io_module_registry
import gate/nimtry/nimtry_registry
import gate/rule_patterns
import std/[sets, deques, tables, options, strutils, algorithm]
type
  NimtryEffectKind* = enum
    nekUnknown, nekPure, nekIo
func effectKindFromPragma*(pragmaValue: string): NimtryEffectKind {.raises: [].} =
  ## Map {.axiomEffect: X.} pragma string to NimtryEffectKind.
  case pragmaValue
  of "IOEffect": nekIo
  of "Pure": nekPure
  else: nekUnknown
func buildFunctionToModuleTable(allFacts: seq[ModuleFacts]): Table[string, string] {.raises: [].} =
  ## Path-sorted iteration makes last-write-wins bare-name resolution independent
  ## of filesystem walk order (CI ext4/xfs vs local).
  for facts in allFacts.sortedByIt(it.path):
    for fn in facts.functions:
      result[fn.name] = facts.path
func buildReverseGraph(
  graph: CallGraph;
  fnToModule: Table[string, string]
): Table[string, seq[string]] {.raises: [].} =
  for callerKey, callees in graph.edges:
    for callee in callees:
      let calleeModule = graph.calleeModule.getOrDefault(callee, fnToModule.getOrDefault(callee, ""))
      let normalizedCallee = if calleeModule.len > 0: calleeModule & "::" & callee else: callee
      result.mgetOrPut(normalizedCallee, @[]).add(callerKey)
func seedIoFunctions(allFacts: seq[ModuleFacts]): HashSet[string] {.raises: [].} =
  for facts in allFacts:
    if isIoModuleOrHint(facts.path):
      for fn in facts.functions:
        result.incl(facts.path & "::" & fn.name)
func seedPragmaIoFunctions(allFacts: seq[ModuleFacts]): HashSet[string] {.raises: [].} =
  for facts in allFacts:
    for fn in facts.functions:
      let ev = axiomEffectOf(facts, fn.name)
      if ev.isSome and effectKindFromPragma(ev.get) == nekIo:
        result.incl(facts.path & "::" & fn.name)
func seedDirectIoCallers(
  allFacts: seq[ModuleFacts];
  graph: CallGraph;
  fnToModule: Table[string, string]
): HashSet[string] {.raises: [].} =
  for facts in allFacts:
    for edge in facts.callEdges:
      let calleeModule = graph.calleeModule.getOrDefault(edge.calleeFunction,
                            fnToModule.getOrDefault(edge.calleeFunction, ""))
      if calleeModule.len > 0 and isIoModuleOrHint(calleeModule):
        result.incl(edge.callerModule & "::" & edge.callerFunction)
func collectIoSeeds(
  allFacts: seq[ModuleFacts];
  graph: CallGraph;
  fnToModule: Table[string, string]
): HashSet[string] {.raises: [].} =
  result = seedIoFunctions(allFacts)
  for key in seedPragmaIoFunctions(allFacts):
    result.incl(key)
  for key in seedDirectIoCallers(allFacts, graph, fnToModule):
    result.incl(key)
func runReverseBfs(
  reverseGraph: Table[string, seq[string]];
  seeds: HashSet[string]
): HashSet[string] {.raises: [].} =
  result = seeds
  var queue = initDeque[string]()
  for seed in seeds:
    queue.addLast(seed)
  while queue.len > 0:
    let current = queue.popFirst()
    for caller in reverseGraph.getOrDefault(current, @[]):
      if caller notin result:
        result.incl(caller)
        queue.addLast(caller)
func reportMissingIoAnnotations(
  allFacts: seq[ModuleFacts];
  ioReachable: HashSet[string]
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  for facts in allFacts:
    for fn in facts.functions:
      if fn.declKind != fdkProc:
        continue
      let fullName = facts.path & "::" & fn.name
      if fullName notin ioReachable:
        continue
      let ev = axiomEffectOf(facts, fn.name)
      if ev.isNone or effectKindFromPragma(ev.get) != nekIo:
        result.add(ArchitectureViolationArtifact(
          rule: "EFFECT-transitive-io",
          detail: fn.name & " transitively reaches I/O but lacks {.raises: [].}",
          files: @[facts.path],
          severity: "warning"
        ))
func checkTransitiveIoAnnotation*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  var graph = buildCallGraph(allFacts)
  graph.resolveCalleeModules(allFacts)
  let fnToModule = buildFunctionToModuleTable(allFacts)
  let reverseGraph = buildReverseGraph(graph, fnToModule)
  let seeds = collectIoSeeds(allFacts, graph, fnToModule)
  let ioReachable = runReverseBfs(reverseGraph, seeds)
  result = reportMissingIoAnnotations(allFacts, ioReachable)

# ══════════════════════════════════════════════════════════════════════════
# enforce-proc-purity precision refinement — I/O-driven exemption (P2, 2026-08-05)
# ══════════════════════════════════════════════════════════════════════════
# ANTI-THEATER RATIONALE (§0.9):
# The legacy rule flagged EVERY src/core proc that is neither in the impure
# whitelist nor annotated `{.axiomEffect: IOEffect.}` as an error — WITHOUT
# checking whether the proc actually performs I/O. This mis-flagged genuinely
# impure procs (callers of getEnv / execCmdEx / readFile / epochTime /
# startProcess / ...) that can never be declared `func`.
#
# The refined rule is I/O-DRIVEN: a proc is accepted as natively impure ONLY
# when the call graph PROVES it reaches I/O — either a direct stdlib I/O call
# (isStdlibIoCall) or a transitive call through project functions that do
# (reverse BFS over the module call graph, reusing collectIoSeeds). Everything
# that is not provably impure — and not compiler-verified pure via
# `{.noSideEffect.}` — remains an error.
#
# CONSERVATIVE DIRECTION (no fail-open): exemption happens ONLY on proof of I/O
# reachability or compiler-verified purity. If detection MISSES an I/O path,
# the proc stays flagged (safe, conservative). We never pass an impure-looking
# proc by guessing "it probably does I/O". Misclassifying impure as pure would
# be theater (rule #2: swallowed failure); keeping the error on detection gaps
# is the honest, conservative choice.
const stdlibIoFunctionNames* = [
  # std/os — filesystem + environment + process identity
  "getEnv", "existsEnv", "putEnv", "delEnv", "getCurrentDir", "setCurrentDir",
  "getAppFilename", "getHomeDir", "getTempDir", "getCurrentProcessId",
  "getFileSize", "lastModificationTime", "getLastModificationTime", "getFileInfo",
  "fileExists", "dirExists", "walkDir", "walkDirRec", "readFile", "writeFile",
  "removeFile", "createDir", "removeDir", "moveFile", "copyFile", "symlinkExists",
  "expandSymlink", "createSymlink", "sleep", "paramCount", "paramStr",
  "commandLineParams", "getEnvConfig", "existsConfigDir",
  # std/osproc — subprocess execution
  "execCmd", "execCmdEx", "execProcess", "startProcess", "startProcessQuoted",
  "execShell", "terminate", "kill", "waitForExit", "waitForProcess",
  "processExists", "popen2", "popen3",
  # std/streams + syncio + system — terminal/stream I/O
  "newFileStream", "openFileStream", "readLine", "readAll", "readStr",
  "readChar", "writeLine", "write", "flush", "echo",
  # std/times — system clock / non-deterministic time reads
  "epochTime", "now", "getTime", "cpuTime", "getDate", "getClockStr",
  # std/net + std/httpclient + nativesockets + asyncdispatch — network I/O
  "request", "send", "recv", "connect", "accept", "close", "getAddrInfo",
  "newSocket", "newSocketPair", "dial", "listen", "bindAddr", "newHttpClient",
  "getContent", "postContent", "httpGet", "httpPost", "waitFor",
  # std/locks + threads — concurrency primitives (non-reentrant global state)
  "acquire", "release", "initLock", "deinitLock", "createThread",
  "createNativeThread", "joinThread", "joinThreads",
  # std/random — global RNG state (non-deterministic)
  "randomize", "rand", "shuffle",
  # terminal
  "eraseScreen", "setCursorPos", "setForegroundColor", "setBackgroundColor",
  "readPasswordFromStdin",
  # misc global state / FFI / process exit
  "getLastError", "loadSharedLib", "quit", "getMemUsage", "allocStats"
].toHashSet

func isStdlibIoCall*(name: string): bool {.raises: [].} =
  ## True if `name` is a known stdlib function that performs I/O, reads the
  ## system clock, or touches non-reentrant global state — i.e. can never be
  ## declared `func` (noSideEffect) regardless of context.
  name in stdlibIoFunctionNames

func collectDirectIoCallers*(allFacts: seq[ModuleFacts]): HashSet[string] {.raises: [].} =
  ## Procs whose body directly calls a stdlib I/O function (readFile, getEnv,
  ## execCmdEx, epochTime, startProcess, ...). Result keys are "module::fn" —
  ## the same format as the existing I/O seed sets.
  ##
  ## Two complementary detections are combined (both conservative — a missed
  ## I/O call keeps the proc flagged rather than wrongly exempting it):
  ##   1. Per-function AST call edges (callerFunction/calleeFunction), which
  ##      cover statement-level calls.
  ##   2. Module-wide call facts mapped to function line ranges. The call-edge
  ##      extractor records only the OUTERMOST call of each expression (e.g.
  ##      `getEnv(...).strip().toLowerAscii()` yields just `toLowerAscii`), so
  ##      nested I/O calls inside argument chains (getEnv, epochTime, ...) would
  ##      otherwise be missed. `facts.calls` recurses into call arguments and
  ##      carries accurate line numbers; we map each call back to its enclosing
  ##      function via the [location.line, location.line+physicalSpan) span.
  for facts in allFacts:
      for edge in facts.callEdges:
        if isStdlibIoCall(edge.calleeFunction):
          result.incl(facts.path & "::" & edge.callerFunction)
      for fn in facts.functions:
        let fnStart = fn.location.line
        let fnEnd = fnStart + (if fn.physicalSpan > 0: fn.physicalSpan - 1 else: 0)
        var foundIo = false
        for c in facts.calls:
          let cl = c.location.line
          if cl >= fnStart and cl <= fnEnd and isStdlibIoCall(c.callee):
            foundIo = true
            break
        if foundIo:
          result.incl(facts.path & "::" & fn.name)

func hasPragma*(facts: ModuleFacts; procName, pragmaName: string): bool {.raises: [].} =
  ## Check if a proc has a specific pragma (by name).
  ## Used by checkEnforceProcPurity to accept compiler-verified-pure procs
  ## (`{.noSideEffect.}`) and by checkTripleAnnotation for the tags check.
  for p in facts.pragmas:
    if p.targetName == procName and p.pragmaName == pragmaName:
      return true

func checkEnforceProcPurity*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## Every proc in src/core/ must be either (a) whitelisted as impure,
  ## (b) annotated `{.axiomEffect: IOEffect.}`, (c) provably I/O-reachable via
  ## the call graph (natively impure — cannot be `func`), or (d) compiler-
  ## verified pure via `{.noSideEffect.}` (func-equivalent semantics).
  ##
  ## P2 refinement (2026-08-05): the I/O-driven exemptions (c) and (d) fix the
  ## false positives described in the anti-theater rationale above. Whitelist
  ## and IOEffect annotation remain as a dual safety net — a proc is exempted
  ## if ANY of the four conditions holds.
  ##
  ## Conservative (§0.9): exemption requires PROOF (call-graph reachability or
  ## compiler-verified purity). Detection gaps keep the proc flagged.
  var graph = buildCallGraph(allFacts)
  graph.resolveCalleeModules(allFacts)
  let fnToModule = buildFunctionToModuleTable(allFacts)
  var seeds = collectIoSeeds(allFacts, graph, fnToModule)
  for key in collectDirectIoCallers(allFacts):
    seeds.incl(key)
  let ioReachable = runReverseBfs(buildReverseGraph(graph, fnToModule), seeds)

  # Build whitelist set for O(1) lookup: entries are "path:procName"
  var whitelistSet = initHashSet[string]()
  for entry in policy.impureProceduresWhitelist:
    whitelistSet.incl(entry)
  for facts in allFacts:
    if not facts.path.startsWith("src/core"):
      continue
    for fn in facts.functions:
      if fn.declKind != fdkProc:
        continue
      let entry = facts.path & ":" & fn.name
      if entry in whitelistSet:
        continue
      let ev = axiomEffectOf(facts, fn.name)
      if ev.isSome and effectKindFromPragma(ev.get) == nekIo:
        continue
      let fullName = facts.path & "::" & fn.name
      if fullName in ioReachable:
        continue  # natively impure via I/O — cannot be a func (see rationale)
      if hasPragma(facts, fn.name, "noSideEffect"):
        continue  # compiler-verified pure — func-equivalent, not theater
      result.add(ArchitectureViolationArtifact(
        rule: "EFFECT-enforce-proc-purity",
        detail: fn.name & " is proc but not in impure_procedures_whitelist and not marked {.raises: [].}",
        files: @[facts.path],
        severity: "error"
      ))
func checkTripleAnnotation*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## SA-β3: Verify triple annotation pattern.
  ## Every proc with {.axiomEffect: IOEffect.} should also have
  ## {.tags: [AxiomIOEffect].} for Nim-native compile-time enforcement.
  for facts in allFacts:
    for fn in facts.functions:
      let ev = axiomEffectOf(facts, fn.name)
      if ev.isNone or effectKindFromPragma(ev.get) != nekIo:
        continue
      # Has axiomEffect: IOEffect — check for complementary tags pragma
      if not hasPragma(facts, fn.name, "tags"):
        result.add(ArchitectureViolationArtifact(
          rule: "EFFECT-triple-annotation",
          detail: fn.name & " has {.axiomEffect: IOEffect.} but missing {.tags: [AxiomIOEffect].}",
          files: @[facts.path],
          severity: "warning"
        ))
func checkEffectPragmaConsistency*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## Verify that functions with {.axiomEffect: X.} pragma have consistent annotations.
  for facts in allFacts:
    for fn in facts.functions:
      if fn.declKind != fdkProc:
        continue
      let ev = axiomEffectOf(facts, fn.name)
      if ev.isNone:
        continue
      let kind = effectKindFromPragma(ev.get)
      if kind == nekUnknown:
        result.add(ArchitectureViolationArtifact(
          rule: "EFFECT-pragma-consistency",
          detail: fn.name & " has unrecognized axiomEffect value: " & ev.get,
          files: @[facts.path],
          severity: "error"
        ))
func registerEffectQueries*(): seq[NimtryQuery] {.raises: [].} =
  result.add(NimtryQuery(
    name: "effect-pragma-consistency",
    rule: "EFFECT",
    severity: "error",
    taxonomy: procPurity,
    checker: checkEffectPragmaConsistency
  ))
  result.add(NimtryQuery(
    name: "effect-transitive-io",
    rule: "EFFECT",
    severity: "warning",
    taxonomy: procPurity,
    checker: checkTransitiveIoAnnotation
  ))
  result.add(NimtryQuery(
    name: "enforce-proc-purity",
    rule: "EFFECT",
    severity: "error",
    taxonomy: procPurity,
    checker: checkEnforceProcPurity
  ))
  result.add(NimtryQuery(
    name: "effect-triple-annotation",
    rule: "EFFECT",
    severity: "warning",
    taxonomy: procPurity,
    checker: checkTripleAnnotation
  ))

{.pop.}
