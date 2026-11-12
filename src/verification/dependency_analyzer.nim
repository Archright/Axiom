import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/algorithm
import std/os
import std/sequtils
import std/sets
import std/strutils
import std/tables
import core/domain_types
# axiomIoBoundary


## Collect Dependencies.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
func collectDependencies*(cert: FunctionCertificate): seq[string] {.noSideEffect, raises: [].} =
  result = cert.calls.filterIt(it.len > 0 and it != cert.functionName).deduplicate()

## Normalize Dependency Name.
# @axiom-hint: lean="dep.length = 0 ∧ dep" smt="(assert (and (= (str.len dep) 0) dep))"
func normalizeDependencyName*(
  dep: string;
  moduleStem: string;
  moduleFunctions: HashSet[string]
): string =
  if dep.len == 0:
    return ""
  if dep.find('.') >= 0:
    return dep
  if moduleStem.len > 0 and dep in moduleFunctions:
    return moduleStem & "." & dep
  dep

## Canonicalize Calls Across Modules.
# @axiom-hint: lean="candidates.length = 1 ∧ dep.length = 0 ∧ (certificates ≥ 0) ∧ (candidatesByFunction ≥ 0) ∧ (calls ≥ 0) ∧ (uniqueByFunction ≥ 0)" smt="(assert (and (= (str.len candidates) 1) (= (str.len dep) 0) (>= certificates 0) (>= candidatesByFunction 0) (>= calls 0) (>= uniqueByFunction 0)))"
func canonicalizeCallsAcrossModules*(certificates: var seq[FunctionCertificate]) =
  var candidatesByFunction = initTable[string, seq[string]]()
  for cert in certificates:
    if cert.functionName.len == 0 or string(cert.modulePath).len == 0:
      continue
    let qualified = splitFile(string(cert.modulePath)).name & "." & cert.functionName
    if not candidatesByFunction.hasKey(cert.functionName):
      candidatesByFunction[cert.functionName] = @[]
    if qualified notin candidatesByFunction.getOrDefault(cert.functionName):
      candidatesByFunction[cert.functionName].add(qualified)
  var uniqueByFunction = initTable[string, string]()
  for functionName, candidates in candidatesByFunction.pairs:
    if candidates.len == 1:
      uniqueByFunction[functionName] = candidates[0]
  for i in 0 ..< certificates.len:
    var normalizedCalls: seq[string] = @[]
    for rawDep in certificates[i].calls:
      let dep = rawDep.strip()
      if dep.len == 0:
        continue
      if dep.find('.') >= 0:
        normalizedCalls.add(dep)
      elif uniqueByFunction.hasKey(dep):
        normalizedCalls.add(uniqueByFunction[dep])
      else:
        normalizedCalls.add(dep)
    certificates[i].calls = normalizedCalls.deduplicate()

## Build Reverse Dependencies.
# @axiom-hint: lean="dependencyIndex = idx ∧ dependencyName.length = 0 ∧ resource.length = 0 ∧ indices.length < 2 ∧ sourceName.length = 0 ∧ sourceIndex = dependentIndex ∧ (certificates ≥ 0) ∧ (dependencyIndices ≥ 0) ∧ (byResource ≥ 0) ∧ (byFunction ≥ 0) ∧ (byQualified ≥ 0) ∧ (result ≥ 0) ∧ (indices ≥ 0)" smt="(assert (and (= dependencyIndex idx) (= (str.len dependencyName) 0) (= (str.len resource) 0) (< (str.len indices) 2) (= (str.len sourceName) 0) (= sourceIndex dependentIndex) (>= certificates 0) (>= dependencyIndices 0) (>= byResource 0) (>= byFunction 0) (>= byQualified 0) (>= result 0) (>= indices 0)))"
func buildReverseDependencies*(certificates: seq[FunctionCertificate]): Table[string, seq[int]] {.noSideEffect, raises: [].} =
  var byFunction = initTable[string, seq[int]]()
  var byQualified = initTable[string, int]()
  for idx, cert in certificates:
    if cert.functionName.len > 0:
      byFunction.mgetOrPut(cert.functionName, @[]).add(idx)
      let qualified = splitFile(string(cert.modulePath)).name & "." & cert.functionName
      byQualified[qualified] = idx
  for idx, cert in certificates:
    for dep in collectDependencies(cert):
      var dependencyIndices: seq[int] = @[]
      if dep.find('.') >= 0:
        byQualified.withValue(dep, v):
          dependencyIndices = @[v[]]
      else:
        byFunction.withValue(dep, v):
          dependencyIndices = v[]
      for dependencyIndex in dependencyIndices:
        if dependencyIndex == idx:
          continue
        let dependencyName = certificates[dependencyIndex].functionName
        if dependencyName.len == 0:
          continue
        let existing = result.getOrDefault(dependencyName, @[])
        if idx notin existing:
          result[dependencyName] = existing & @[idx]
  var byResource = initTable[string, seq[int]]()
  for idx, cert in certificates:
    for resource in cert.accessedResources:
      if resource.len == 0:
        continue
      byResource.mgetOrPut(resource, @[]).add(idx)
    for resource in cert.mutatedResources:
      if resource.len == 0:
        continue
      var brr = byResource.mgetOrPut(resource, @[])
      if idx notin brr:
        brr.add(idx)
  for indices in byResource.values:
    if indices.len < 2:
      continue
    for sourceIndex in indices:
      let sourceName = certificates[sourceIndex].functionName
      if sourceName.len == 0:
        continue
      for dependentIndex in indices:
        if sourceIndex == dependentIndex:
          continue
        var srcArr = result.mgetOrPut(sourceName, @[])
        if dependentIndex notin srcArr:
          srcArr.add(dependentIndex)

## Detect Cyclic Functions.
# @axiom-hint: lean="cycleStart ≥ 0 ∧ functionName.length > 0 ∧ cycleStart = i ∧ result = cyclic ∧ (certificates ≥ 0) ∧ (byFunction ≥ 0) ∧ (byQualified ≥ 0) ∧ (result ≥ 0) ∧ (graph ≥ 0)" smt="(assert (and (>= cycleStart 0) (> (str.len functionName) 0) (= cycleStart i) (= result cyclic) (>= certificates 0) (>= byFunction 0) (>= byQualified 0) (>= result 0) (>= graph 0)))"
func detectCyclicFunctions*(certificates: seq[FunctionCertificate]): HashSet[string] =
  var cyclic = initHashSet[string]()
  var byFunction = initTable[string, seq[int]]()
  var byQualified = initTable[string, int]()
  for idx, cert in certificates:
    if cert.functionName.len == 0:
      continue
    if not byFunction.hasKey(cert.functionName):
      byFunction[cert.functionName] = @[]
    byFunction[cert.functionName].add(idx)
    let qualified = splitFile(string(cert.modulePath)).name & "." & cert.functionName
    byQualified[qualified] = idx
  var graph = initTable[int, seq[int]]()
  for idx, cert in certificates:
    if cert.functionName.len == 0:
      continue
    var deps: seq[int] = @[]
    for dep in collectDependencies(cert):
      if dep.find('.') >= 0:
        if byQualified.hasKey(dep):
          deps.add(byQualified[dep])
      elif byFunction.hasKey(dep):
        for dependencyIndex in byFunction[dep]:
          deps.add(dependencyIndex)
    graph[idx] = deps.filterIt(it != idx).deduplicate()
  var visited = initHashSet[int]()
  var visiting = initHashSet[int]()
  var stack: seq[int] = @[]
# @axiom-hint: lean="node ≥ -9223372036854775808 ∧ node ≤ 9223372036854775807" smt="(assert (and (and (>= node -9223372036854775808) (<= node 9223372036854775807))))"
# @axiom-hint: lean="cycleStart ≥ 0 ∧ functionName.length > 0 ∧ cycleStart = i" smt="(assert (and (>= cycleStart 0) (> (str.len functionName) 0) (= cycleStart i)))"
  proc dfs(node: int) =
    visiting.incl(node)
    stack.add(node)
    if graph.hasKey(node):
      for next in graph[node]:
        if next in visiting:
          var cycleStart = -1
          for i in 0 ..< stack.len:
            if stack[i] == next:
              cycleStart = i
              break
          if cycleStart >= 0:
            for i in cycleStart ..< stack.len:
              let functionName = certificates[stack[i]].functionName
              if functionName.len > 0:
                cyclic.incl(functionName)
        elif next notin visited:
          dfs(next)
    discard stack.pop()
    visiting.excl(node)
    visited.incl(node)
  for node in graph.keys.toSeq().sorted():
    if node notin visited:
      dfs(node)
  result = cyclic

## Detect Architectural Cyclic Functions.
# @axiom-hint: lean="certificates.size ≥ 0 ∧ node ≥ -9223372036854775808 ∧ node ≤ 9223372036854775807" smt="(assert (and (>= (seq.len certificates) 0) (and (>= node -9223372036854775808) (<= node 9223372036854775807))))"
# @axiom-hint: lean="cycleStart ≥ 0 ∧ modules.length > 1 ∧ functionName.length > 0 ∧ cycleStart = i ∧ result = cyclic ∧ (certificates ≥ 0) ∧ (byFunction ≥ 0) ∧ (byQualified ≥ 0) ∧ (result ≥ 0) ∧ (graph ≥ 0)" smt="(assert (and (>= cycleStart 0) (> (str.len modules) 1) (> (str.len functionName) 0) (= cycleStart i) (= result cyclic) (>= certificates 0) (>= byFunction 0) (>= byQualified 0) (>= result 0) (>= graph 0)))"
func detectArchitecturalCyclicFunctions*(certificates: seq[FunctionCertificate]): HashSet[string] =
  ## Return only cross-module certificate dependency cycles. Local recursion and
  ## mutually recursive helpers inside one module are algorithmic structure, not
  ## architecture-layer cycles.
  var cyclic = initHashSet[string]()
  var byFunction = initTable[string, seq[int]]()
  var byQualified = initTable[string, int]()
  for idx, cert in certificates:
    if cert.functionName.len == 0:
      continue
    if not byFunction.hasKey(cert.functionName):
      byFunction[cert.functionName] = @[]
    byFunction[cert.functionName].add(idx)
    let qualified = splitFile(string(cert.modulePath)).name & "." & cert.functionName
    byQualified[qualified] = idx
  var graph = initTable[int, seq[int]]()
  for idx, cert in certificates:
    if cert.functionName.len == 0:
      continue
    var deps: seq[int] = @[]
    for dep in collectDependencies(cert):
      if dep.find('.') >= 0:
        if byQualified.hasKey(dep):
          deps.add(byQualified[dep])
      elif byFunction.hasKey(dep):
        for dependencyIndex in byFunction[dep]:
          deps.add(dependencyIndex)
    graph[idx] = deps.filterIt(it != idx).deduplicate()
  var visited = initHashSet[int]()
  var visiting = initHashSet[int]()
  var stack: seq[int] = @[]
  proc dfs(node: int) =
    visiting.incl(node)
    stack.add(node)
    if graph.hasKey(node):
      for next in graph[node]:
        if next in visiting:
          var cycleStart = -1
          for i in 0 ..< stack.len:
            if stack[i] == next:
              cycleStart = i
              break
          if cycleStart >= 0:
            var modules = initHashSet[string]()
            for i in cycleStart ..< stack.len:
              modules.incl(splitFile(string(certificates[stack[i]].modulePath)).name)
            if modules.len > 1:
              for i in cycleStart ..< stack.len:
                let functionName = certificates[stack[i]].functionName
                if functionName.len > 0:
                  cyclic.incl(functionName)
        elif next notin visited:
          dfs(next)
    discard stack.pop()
    visiting.excl(node)
    visited.incl(node)
  for node in graph.keys.toSeq().sorted():
    if node notin visited:
      dfs(node)
  result = cyclic

## Invalidate Dependents.
# @axiom-hint: lean="head < queue.length ∧ (certificates ≥ 0) ∧ ((head ≥ 0) ∧ (head < queue))" smt="(assert (and (< head (str.len queue)) (>= certificates 0) (and (>= head 0) (< head queue))))"
proc invalidateDependents*(
  certificates: var seq[FunctionCertificate];
  markPending: proc (cert: var FunctionCertificate; dependency: string) {.raises: [].}
) {.raises: [].} =
  let reverseDeps = buildReverseDependencies(certificates)
  var queue: seq[string] = @[]
  for cert in certificates:
    if (cert.status == certRed or cert.reason == "source-changed") and cert.functionName.len > 0:
      queue.add(cert.functionName)
  var visited = initHashSet[string]()
  var head = 0
  while head < queue.len:
    let changed = queue[head]
    inc head
    if changed in visited:
      continue
    visited.incl(changed)
    reverseDeps.withValue(changed, deps):
      for dependentIndex in deps:
        if certificates[dependentIndex].status == certRed:
          continue
        markPending(certificates[dependentIndex], changed)
        if certificates[dependentIndex].functionName.len > 0:
          queue.add(certificates[dependentIndex].functionName)
{.pop.}
