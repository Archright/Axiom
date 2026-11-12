import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## Pre-Sieve type definitions.
## Subjective Logic opinion-based pipeline types.

import std/options
import std/json
import compiler/ast

import core/sorter/sorter_core
import core/topology/topology_engine
import sieve/subjective_logic

type
  SieveSourceKind* = enum
    rsTopology     ## Topology metrics (indirect indicator)
    rsAstAnalysis  ## tree-sitter AST (structural evidence)
    rsUnsatCore    ## Z3 unsat core correlation (mathematical evidence)
    rsIOEffect     ## I/O boundary detection (filesystem effect evidence)

  RuleResult* = object
    source*: SieveSourceKind
    opinion*: BinomialOpinion    ## Subjective Logic opinion (b, d, u, a)
    verdict*: string             ## "linear"(safe) | "nonlinear" | "recursive"(danger)
    warning*: string
    metadata*: JsonNode

  SieveVerdict* = object
    blocked*: bool              ## probabilityProjection >= blockThreshold
    combinedOpinion*: BinomialOpinion  ## Fused opinion from all rules
    probabilityScore*: float    ## E = b + a·u
    reason*: string
    warning*: string
    appliedRules*: seq[RuleResult]
    conflictDetected*: bool
    conflicts*: seq[ConflictIntensity]
    derivation*: DerivationNode ## Root of the derivation tree for auditability

  ConflictIntensity* = object
    sourceA*, sourceB*: SieveSourceKind
    dangerOpinion*: BinomialOpinion
    safeOpinion*: BinomialOpinion
    intensity*: float

  SieveContext* = object
    sourceCode*: string
    nodeId*: SorterNodeId
    functionName*: string
    modulePath*: string      ## 파일 경로 포함 (예: src/core/types/results.nim)
    nodeType*: string        ## 토폴로지 스캐너가 감지한 선언 키워드 (proc/func/method/template 등)
    topology*: TopologyNodeMetric
    unsatCoreVars*: seq[string]
    astCache*: Option[PNode]
    complexityScore*: int

  SieveRule* = proc(ctx: SieveContext): Option[RuleResult] {.closure, noSideEffect, raises: [].}

  DerivationStepKind* = enum
    dkRule        ## Individual rule application
    dkFusion      ## Cumulative fusion of multiple opinions
    dkDecision    ## Final block/allow decision

  DerivationNode* = object
    stepKind*: DerivationStepKind
    ruleName*: string              ## "evaluateTopology", "fuseAll", "blockDecision"
    inputOpinion*: BinomialOpinion ## opinion before this step
    outputOpinion*: BinomialOpinion ## opinion after this step
    reason*: string                ## human-readable explanation
    children*: seq[DerivationNode] ## sub-steps (for fusion/decision nodes)
{.pop.}
