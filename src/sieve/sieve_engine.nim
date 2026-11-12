import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## Pre-Sieve engine — Subjective Logic evidence synthesis.
## AST parsing at I/O boundary, pure rules, fuseAll for combination.

import core/trusted/axiom_pragmas
import std/options
import compiler/ast
import sieve/sieve_types
import sieve/sieve_rules
import sieve/subjective_logic
import core/sorter/sorter_core
import core/topology/topology_engine
import core/parser_utils
import core/types/results                # isOk/isErr/get on custom Result

const
  blockThreshold* = 0.50    ## E >= 0.50 → blocked
  warningThreshold* = 0.30  ## E >= 0.30 → warning

static:
  assert blockThreshold > warningThreshold,
    "blockThreshold must exceed warningThreshold"

const defaultRules*: seq[SieveRule] = @[
  SieveRule(evaluateFileValidity),    # 최외곽 공리적 게이트 (비-Nim 파일 차단)
  SieveRule(evaluateSymbolValidity),  # AST 태그 화이트리스팅 (비루틴 심볼 차단)
  SieveRule(evaluateTopology),
  SieveRule(evaluateAst),
  SieveRule(evaluateUnsatCore),
  SieveRule(evaluateIoBoundary)       # I/O 경계 검출 (d=0.30 불확실성 감소)
]

proc detectConflicts(results: seq[RuleResult]): seq[ConflictIntensity] {.raises: [].} =
  ## Detect safe-vs-danger conflicts between rules
  result = @[]
  for i in 0 ..< results.len:
    for j in (i+1) ..< results.len:
      let iDanger = results[i].verdict != "linear"
      let jDanger = results[j].verdict != "linear"
      if iDanger != jDanger:
        let danger = if results[i].verdict != "linear": results[i] else: results[j]
        let safe   = if results[i].verdict == "linear": results[i] else: results[j]
        result.add(ConflictIntensity(
          sourceA: danger.source, sourceB: safe.source,
          dangerOpinion: danger.opinion, safeOpinion: safe.opinion,
          intensity: min(danger.opinion.d, safe.opinion.b)
        ))

proc applyPreSieve*(ctx: SieveContext;
    rules: seq[SieveRule] = defaultRules): SieveVerdict {.raises: [], refines: "src/sieve/sieve_engine_shadow.nim".} =
  var opinions: seq[BinomialOpinion] = @[]
  var results: seq[RuleResult] = @[]
  var ruleNodes: seq[DerivationNode] = @[]
  for rule in rules:
    let r = rule(ctx)
    if r.isSome:
      results.add(r.get())
      opinions.add(r.get().opinion)
      ruleNodes.add(DerivationNode(
        stepKind: dkRule,
        ruleName: $r.get().source,
        inputOpinion: BinomialOpinion(b: 0.0, d: 0.0, u: 1.0, a: 0.5),
        outputOpinion: r.get().opinion,
        reason: r.get().verdict & ": " & r.get().warning,
        children: @[]
      ))
  # If no rules produced results, fail-closed (no evidence = block)
  if opinions.len == 0:
    let dangerFusion = BinomialOpinion(b: 0.0, d: 0.0, u: 1.0, a: 0.5)
    return SieveVerdict(
      blocked: true,
      combinedOpinion: dangerFusion,
      probabilityScore: 1.0,
      reason: "No sieve rules produced results — fail-closed policy",
      warning: "SIEVE_UNMATCHED_ERROR: input bypassed all sieve rules",
      appliedRules: @[],
      conflictDetected: false,
      conflicts: @[],
      derivation: DerivationNode(
        stepKind: dkDecision,
        ruleName: "emptyBlock",
        inputOpinion: dangerFusion,
        outputOpinion: dangerFusion,
        reason: "No rules fired — fail-closed reject",
        children: @[]))
  let combined = fuseAll(opinions)
  let score = probabilityProjection(combined)
  let conflicts = detectConflicts(results)
  let isBlocked = score >= blockThreshold
  let fusionNode = DerivationNode(
    stepKind: dkFusion,
    ruleName: "fuseAll",
    inputOpinion: opinions[0],
    outputOpinion: combined,
    reason: $opinions.len & " rules fused → E=" & $score,
    children: ruleNodes
  )
  let decisionNode = DerivationNode(
    stepKind: dkDecision,
    ruleName: if isBlocked: "blockDecision" else: "allowDecision",
    inputOpinion: combined,
    outputOpinion: combined,
    reason: if isBlocked: "E=" & $score & " >= " & $blockThreshold else: "E=" & $score & " < " & $blockThreshold,
    children: @[fusionNode]
  )
  SieveVerdict(
    blocked: isBlocked,
    combinedOpinion: combined,
    probabilityScore: score,
    reason: if isBlocked: "E=" & $score & " >= " & $blockThreshold else: "",
    warning: if score >= warningThreshold and score < blockThreshold:
      "E=" & $score & " approaching " & $blockThreshold else: "",
    appliedRules: results,
    conflictDetected: conflicts.len > 0,
    conflicts: conflicts,
    derivation: decisionNode
  )

proc buildSieveContext*(sourceCode: string; nodeId: SorterNodeId;
    topology: TopologyNodeMetric;
    unsatCoreVars: seq[string] = @[];
    modulePath: string = "";
    functionName: string = "";
    nodeType: string = ""): SieveContext {.raises: [].} =
  var astCache: Option[PNode] = none(PNode)
  try:
    let parseResult = parseNimRes(sourceCode)
    if parseResult.isOk():
      astCache = some(parseResult.get())
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  SieveContext(
    sourceCode: sourceCode,
    nodeId: nodeId,
    functionName: functionName,
    modulePath: modulePath,
    nodeType: nodeType,
    topology: topology,
    unsatCoreVars: unsatCoreVars,
    astCache: astCache
  )
{.pop.}
