import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import std/locks
import std/os
import std/sequtils
import std/sets
import std/strutils
import std/tables

import core/domain_types
import core/domain_utils
import core/utils/io_utils
import core/results
import core/parser_utils
import core/parsers/lean
import gate/gate_rules_normalization
import ../core/trusted/axiom_pragmas

type
  ModuleClassificationCache = object
    table: Table[string, tuple[hasConcrete: bool; hasAbstract: bool]]
    gate: Lock

var moduleClassificationCacheImpl: ModuleClassificationCache

  ## axiom-smt: (assert (and ast_parse_failed_isolated (>= depth 0)))
  ## axiom-lean: ast_parse_failed_isolated ∧ depth >= 0
proc initModuleClassificationCache() {.axiom, axiomImpl.} =
  initLock(moduleClassificationCacheImpl.gate)

proc getModuleClassificationCache(): ptr ModuleClassificationCache {.raises: [], axiomNoEscape, axiom: ["(assert (and ast_parse_failed_isolated (>= depth 0)))", "ast_parse_failed_isolated ∧ depth >= 0"].} =
  addr moduleClassificationCacheImpl

initModuleClassificationCache()

proc classifyModuleByPath*(modulePath: string): tuple[hasConcrete: bool; hasAbstract: bool] {.raises: [], axiom: ["(assert (and (>= (str.len modulePath) 0) (= (option.isNone sourceOpt) true) (= (str.len source) 0) (>= result 0)))", "modulePath.length ≥ 0 ∧ sourceRes.isErr = true ∧ source.length = 0 ∧ (result ≥ 0)"], axiomEffect: IOEffect.} =
  ## Parse a module's AST and classify it as concrete, abstract, or unknown.
  ## Concrete modules define object types; abstract modules define concepts or methods.
  let cache = getModuleClassificationCache()
  acquire(cache.gate)
  defer: release(cache.gate)
  if cache.table.hasKey(modulePath):
    return cache.table.getOrDefault(modulePath)
  result = (false, false)
  if modulePath.len == 0 or not fileExists(modulePath):
    return
  let sourceRes = readFileOpt(modulePath)
  if sourceRes.isErr:
    return
  let source = sourceRes.get()
  if source.len == 0:
    return
  let astRes = parseNimRes(source)
  if astRes.isOk:
    result = classifyModuleAstP(astRes.get)
    cache.table[modulePath] = result

  ## axiom-smt: (assert (and (>= (seq.len certificates) 0) (>= certificates 0) (>= result 0)))
  ## axiom-lean: certificates.size ≥ 0 ∧ (certificates ≥ 0) ∧ (result ≥ 0)
proc buildModulePathMap*(certificates: seq[FunctionCertificate]): Table[string, string] {.axiom, axiomImpl.} =
  ## Build a map from module stem to module path using certificate metadata.
  for cert in certificates:
    let stem = moduleStem(cert)
    if stem.len > 0 and string(cert.modulePath).len > 0:
      if not result.hasKey(stem):
        result[stem] = string(cert.modulePath)

  ## axiom-smt: (assert (and ast_parse_failed_isolated (>= (str.len moduleStem) 0)))
  ## axiom-lean: ast_parse_failed_isolated ∧ moduleStem.length ≥ 0
proc isConcreteModule*(moduleStem: string; modulePaths: Table[string, string]): bool {.axiom, axiomImpl.} =
  ## AST-based classification: a module is concrete if its AST contains
  ## object_declaration nodes and no concept_declaration/method_declaration nodes.
  if not modulePaths.hasKey(moduleStem):
    return false
  let classification = classifyModuleByPath(modulePaths.getOrDefault(moduleStem))
  result = classification.hasConcrete and not classification.hasAbstract

  ## axiom-smt: (assert (and ast_parse_failed_isolated (>= (str.len moduleStem) 0)))
  ## axiom-lean: ast_parse_failed_isolated ∧ moduleStem.length ≥ 0
proc isAbstractModule*(moduleStem: string; modulePaths: Table[string, string]): bool {.axiom, axiomImpl.} =
  ## AST-based classification: a module is abstract if its AST contains
  ## concept_declaration or method_declaration nodes.
  if not modulePaths.hasKey(moduleStem):
    return false
  let classification = classifyModuleByPath(modulePaths.getOrDefault(moduleStem))
  result = classification.hasAbstract

  ## axiom-smt: (assert (and (>= (str.len dep) 0)))
  ## axiom-lean: dep.length ≥ 0
proc extractModuleStemFromDependency*(dep: string): string {.axiom, axiomImpl.} =
  ## Extract the module stem from a qualified dependency name (module.function).
  for i in 0 ..< dep.len:
    if dep[i] == '.':
      return dep[0 ..< i]
  result = ""

  ## axiom-smt: (assert (and (>= (str.len dep) 0)))
  ## axiom-lean: dep.length ≥ 0
proc isLikelyConcreteName*(dep: string; modulePaths: Table[string, string]): bool {.axiom, axiomImpl.} =
  ## AST-based classification of a dependency as concrete.
  ## Checks the callee module's AST for object declarations.
  let stem = extractModuleStemFromDependency(dep)
  if stem.len > 0:
    return isConcreteModule(stem, modulePaths)
  result = false

  ## axiom-smt: (assert (and (>= (str.len dep) 0)))
  ## axiom-lean: dep.length ≥ 0
proc isLikelyAbstractionName*(dep: string; modulePaths: Table[string, string]): bool {.axiom, axiomImpl.} =
  ## AST-based classification of a dependency as abstract.
  ## Checks the callee module's AST for concept or method declarations.
  let stem = extractModuleStemFromDependency(dep)
  if stem.len > 0:
    return isAbstractModule(stem, modulePaths)
  result = false

  ## axiom-smt: (assert (and (>= (seq.len certificates) 0) (= (str.len qn) 0) (= (str.len dep) 0) (not (= candidate qn)) (>= certificates 0) (>= qnSeq 0) (>= byFunction 0) (>= byQualified 0) (>= result 0)))
  ## axiom-lean: certificates.size ≥ 0 ∧ qn.length = 0 ∧ dep.length = 0 ∧ candidate ≠ qn ∧ (certificates ≥ 0) ∧ (qnSeq ≥ 0) ∧ (byFunction ≥ 0) ∧ (byQualified ≥ 0) ∧ (result ≥ 0)
proc buildQualifiedCallGraph*(certificates: seq[FunctionCertificate]): Table[string, seq[string]] {.axiom, axiomImpl.} =
  var byFunction = initTable[string, seq[string]]()
  var byQualified = initTable[string, string]()
  for cert in certificates:
    let qn = qualifiedName(cert)
    if qn.len == 0:
      continue
    byQualified[qn] = qn
    byFunction.mgetOrPut(cert.functionName, @[]).add(qn)
  for qnSeq in byFunction.mvalues:
    qnSeq = qnSeq.deduplicate()
  for cert in certificates:
    let qn = qualifiedName(cert)
    if qn.len == 0:
      continue
    var deps: seq[string] = @[]
    for dep in cert.calls:
      if dep.len == 0:
        continue
      if dep.find('.') >= 0:
        if byQualified.hasKey(dep):
          deps.add(dep)
      elif byFunction.hasKey(dep):
        for candidate in byFunction.getOrDefault(dep):
          if candidate != qn:
            deps.add(candidate)
    result[qn] = deps.deduplicate()

  ## axiom-smt: (assert (and (>= (str.len node) 0) 0 (>= memo 0) (>= result 0) (>= best 0)))
  ## axiom-lean: node.length ≥ 0 ∧ 0 ∧ (memo ≥ 0) ∧ (result ≥ 0) ∧ (best ≥ 0)
proc computeMaxCallDepth*(graph: Table[string, seq[string]]): int {.axiom, axiomImpl.} =
  var memo = initTable[string, int]()
  var visiting = initHashSet[string]()
    ## axiom-smt: (assert (and (>= (str.len node) 0) 0 (>= memo 0) (>= best 0)))
    ## axiom-lean: node.length ≥ 0 ∧ 0 ∧ (memo ≥ 0) ∧ (best ≥ 0)
  func dfs(node: string): int {.axiom, axiomImpl.} =
    if memo.hasKey(node):
      return memo.getOrDefault(node)
    if node in visiting:
      return 0
    visiting.incl(node)
    var best = 1
    if graph.hasKey(node):
      for next in graph.getOrDefault(node):
        best = max(best, 1 + dfs(next))
    visiting.excl(node)
    memo[node] = best
    result = best
  for node in graph.keys.toSeq():
    result = max(result, dfs(node))
{.pop.}

