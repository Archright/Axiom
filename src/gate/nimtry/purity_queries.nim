import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Purity queries — proc→func conversion enforcement and func-first coding standards.
## SPLIT from forbidden_patterns.nim for SoC compliance.

import std/strutils
import std/tables
import std/sets
import std/deques
import std/algorithm
import gate/nimtry/nimtry_registry
import gate/architecture_ast_facts
import core/gate/architecture_policy
import gate/nimtry/io_module_registry
import gate/nimtry/call_graph
import gate/nimtry/safety_queries  # for legacyViolationPaths, loadLegacyViolations
import core/utils/file_utils
from core/trusted/axiom_pragmas_lite import axiomEffect, AxiomEffectKind, IOEffect, Pure
from core/trusted/effect_bridge import AxiomIOEffect

func checkProcPurity*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## Audit each proc declaration: if it has no transitive I/O calls, it should be func.
  ## Uses reverse BFS from I/O modules to find all functions that can reach I/O.

  # 1단계: call graph 빌드 + calleeModule 보강
  var graph = buildCallGraph(allFacts)
  graph.resolveCalleeModules(allFacts)

  # 2단계: 함수명 → 모듈 매핑 테이블 구축 (calleeModule 보강용)
  # Path-sorted iteration keeps last-write-wins resolution deterministic across
  # filesystems (CI ext4/xfs vs local) — see call_graph resolveCalleeModules.
  var fnToModule = initTable[string, string]()
  for facts in allFacts.sortedByIt(it.path):
    for fn in facts.functions:
      fnToModule[fn.name] = facts.path

  # 3단계: 역방향 그래프 빌드 (정규화된 callee → 정규화된 callers)
  var reverseGraph = initTable[string, seq[string]]()
  for callerKey, callees in graph.edges:
    for callee in callees:
      # callee를 정규화된 키로 변환 (module::fn 형태)
      let calleeModule = graph.calleeModule.getOrDefault(callee, fnToModule.getOrDefault(callee, ""))
      let normalizedCallee = if calleeModule.len > 0: calleeModule & "::" & callee else: callee
      reverseGraph.mgetOrPut(normalizedCallee, @[]).add(callerKey)

  # 4단계: I/O 모듈 함수를 시드로 역방향 BFS
  var ioReachable = initHashSet[string]()
  var queue = initDeque[string]()

  # I/O 모듈에 직접 정의된 함수들을 시드로 추가
  for facts in allFacts:
    if isIoModule(facts.path):
      for fn in facts.functions:
        let key = facts.path & "::" & fn.name
        if key notin ioReachable:
          ioReachable.incl(key)
          queue.addLast(key)

  # I/O를 직접 호출하는 함수들을 시드로 추가
  for facts in allFacts:
    for edge in facts.callEdges:
      let calleeModule = graph.calleeModule.getOrDefault(edge.calleeFunction,
                         fnToModule.getOrDefault(edge.calleeFunction, ""))
      if calleeModule.len > 0 and isIoModule(calleeModule):
        let callerKey = edge.callerModule & "::" & edge.callerFunction
        if callerKey notin ioReachable:
          ioReachable.incl(callerKey)
          queue.addLast(callerKey)

  # var proc / 미해석 callee 호출자를 시드로 추가 (conservative: purity 미증명 시 I/O 가정)
  var knownFuncs = initHashSet[string]()
  for facts in allFacts:
    for fn in facts.functions:
      knownFuncs.incl(fn.name)
  for facts in allFacts:
    for edge in facts.callEdges:
      let calleeModule = graph.calleeModule.getOrDefault(edge.calleeFunction,
                         fnToModule.getOrDefault(edge.calleeFunction, ""))
      if calleeModule.len > 0 and isIoModule(calleeModule):
        continue  # 이미 처리됨
      if edge.calleeFunction notin knownFuncs:
        # callee가 어떤 모듈의 함수에도 매칭되지 않음 → var proc, callback 등
        let callerKey = edge.callerModule & "::" & edge.callerFunction
        if callerKey notin ioReachable:
          ioReachable.incl(callerKey)
          queue.addLast(callerKey)

  # 역방향 BFS 실행
  while queue.len > 0:
    let current = queue.popFirst()
    let callers = reverseGraph.getOrDefault(current, @[])
    for caller in callers:
      if caller notin ioReachable:
        ioReachable.incl(caller)
        queue.addLast(caller)

  # 5단계: ioReachable에 없는 proc만 플래깅
  for facts in allFacts:
    for fn in facts.functions:
      if fn.declKind != fdkProc:
        continue
      let fullName = facts.path & "::" & fn.name
      if fullName notin ioReachable:
        result.add(ArchitectureViolationArtifact(
          rule: "SAFETY-proc-purity",
          detail: fn.name & " (" & facts.path & ":" & $fn.location.line &
                  ") is proc but has no transitive I/O calls. Convert to func.",
          files: @[facts.path],
          severity: "warning"
        ))

func extractProcNameFromLine(line: string): string {.raises: [].} =
  ## Extract bare proc name from a stripped source line for whitelist lookup.
  var name = line
  if name.startsWith("proc "):
    name = name[5 .. ^1].strip()
  let parenIdx = name.find('(')
  let colonIdx = name.find(':')
  let spaceIdx = name.find(' ')
  var endIdx = name.len
  if parenIdx >= 0 and parenIdx < endIdx: endIdx = parenIdx
  if colonIdx >= 0 and colonIdx < endIdx: endIdx = colonIdx
  if spaceIdx >= 0 and spaceIdx < endIdx: endIdx = spaceIdx
  name = name[0 ..< endIdx]
  if name.endsWith("*"):
    name = name[0 .. ^2]
  name

proc checkPurityNewCodeMustBeFunc*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## [impure: calls readFileSafe (file I/O), loadLegacyViolations (file I/O)]
  ## PURITY: new proc declarations in non-I/O modules must be func.
  ## AGENTS.md §0.6: all core logic MUST default to func.
  ## Procs in impure_procedures_whitelist (architecture_policy.lock) are treated
  ## as legacy (warning, not error) — they are known impure and cannot be func.
  loadLegacyViolations()
  # Build whitelist set for O(1) lookup: entries are "path:procName"
  var whitelistSet = initHashSet[string]()
  for entry in policy.impureProceduresWhitelist:
    whitelistSet.incl(entry)
  for facts in allFacts:
    let isIoBoundary = facts.path.startsWith("src/cli/") or
                       facts.path.startsWith("src/mcp/") or
                       facts.path.startsWith("src/gate/runners/") or
                       facts.path.startsWith("src/gate/nimtry/") or
                       isIoModuleOrHint(facts.path)
    let isFileLegacy = facts.path in legacyViolationPaths
    if not facts.path.startsWith("src/") or isIoBoundary:
      continue
    # Declarative I/O boundary: skip files with {.axiomIoBoundary.}
    try:
      let fileText = readFileSafe(facts.path)
      if "axiomIoBoundary" in fileText:
        continue
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    try:
      let content = readFileSafe(facts.path)
      let lines = content.splitLines()
      for i, line in lines:
        let stripped = line.strip()
        if stripped.startsWith("proc ") and not stripped.startsWith("func "):
          let procName = extractProcNameFromLine(stripped)
          let whitelistKey = facts.path & ":" & procName
          let isWhitelisted = whitelistKey in whitelistSet
          # severity=error for new code, warning for legacy or whitelisted impure
          let severity = if isFileLegacy or isWhitelisted: "warning" else: "error"
          result.add(ArchitectureViolationArtifact(
            rule: "PURITY-new-code-must-be-func",
            detail: facts.path & ":" & $(i + 1) & " new proc declaration in non-I/O module. " &
                    "Use 'func' instead of 'proc'. AGENTS.md §0.6: all core logic MUST default to func." &
                    (if isWhitelisted: " (whitelisted in impure_procedures_whitelist)" else: ""),
            files: @[facts.path],
            severity: severity,
          ))
    except CatchableError:
      discard  # file read failure — skip  # axiom:best-effort(ioboundary catch)

template registerPurityQueries*(queries: var seq[NimtryQuery]) =
  # ── Purity queries ─────────────────────────────────────────────────
  # SAFETY: proc purity audit — proc without I/O should be func
  queries.add(NimtryQuery(
    name: "safety-proc-purity",
    rule: "SAFETY",
    severity: "warning",
    taxonomy: procPurity,
    checker: checkProcPurity
  ))

  # PURITY: new proc in non-I/O module must be func (AGENTS.md §0.6)
  queries.add(NimtryQuery(
    name: "purity-new-code-must-be-func",
    rule: "PURITY",
    severity: "warning",
    taxonomy: procPurity,
    checker: checkPurityNewCodeMustBeFunc
  ))

{.pop.}
