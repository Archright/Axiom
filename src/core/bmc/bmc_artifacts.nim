import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
## BMC Analysis Artifact — Immutable snapshot of BMC analysis results
##
## Aggregates BmcConfig, BmcTransition sequence, safety property,
## and VariableMapTable into a single heap-allocated ref object
## for zero-copy pipeline transport via {.cursor.} binding.
##
## Design: Domain layer artifact per AGENTS.md §1.2 (Domain never imports Infrastructure)

import core/bmc/bmc_generic
import core/bmc/bmc_types
import core/bmc/bmc_variable_map

type
  BmcAnalysisArtifact* {.acyclic.} = ref object
    ## BMC 분석 단계에서 도출된 대수적 전이 시스템 정형 스펙
    ## 힙 할당 + ARC 관리 → 안전한 수명주기
    config*: BmcConfig
    transitions*: seq[BmcTransition]
    safetyProperty*: string
    varMap*: VariableMapTable
    scopeCtx*: ScopeContextStack

func initBmcAnalysisArtifact*(
  config: BmcConfig;
  transitions: seq[BmcTransition];
  safetyProperty: string;
  varMap: VariableMapTable;
  scopeCtx: ScopeContextStack
): BmcAnalysisArtifact =
  ## BMC 분석 결과를 단일 아티팩트로 응집
  result = BmcAnalysisArtifact(
    config: config,
    transitions: transitions,
    safetyProperty: safetyProperty,
    varMap: varMap,
    scopeCtx: scopeCtx
  )

func isEmpty*(artifact: BmcAnalysisArtifact): bool =
  ## 아티팩트가 유효한 전이 데이터를 포함하는지 검증
  artifact == nil or artifact.transitions.len == 0

{.pop.}
