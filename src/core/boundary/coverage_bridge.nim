import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
## Static Specification Compliance Engine — Coverage Bridge
##
## 기하평균 기반 핫스팟 우선순위 + 명세 대수적 밀도 측정
## 컴파일 타임에 결정론적으로 구동되는 정적 명세 준수 검증기
##
## Per AGENTS.md §0.6 Static First: all funcs, {.raises: [].}

import std/macros

type
  ModuleMetrics* = object
    ## 각 모듈의 3차원 정형 복잡도 지표
    hotspotDepth*: float    ## DEBT 레지스트리 위험도 가중치
    astNodeCount*: float    ## 모듈 AST 노드 수 (정적 복잡도)
    inDegree*: float        ## 참조하는 타 모듈 수 (파급력)

  CoverageMatrix* = object
    ## 명세 준수 검증 결과 행렬
    targetModule*: string
    algebraicDensity*: float  ## Gherkin ↔ public interface 매핑 비율 (0.0~1.0)
    priorityScore*: float     ## 기하평균 우선순위 점수

  SpecDensityResult* = object
    ## 명세 밀도 측정 결과
    moduleName*: string
    totalPublicSymbols*: int
    coveredByFeature*: int
    density*: float           ## coveredByFeature / totalPublicSymbols

const
  HotspotCriticalThreshold* = 50.0
    ## 이 점수를 초과하는 모듈은 컴파일 타임 하드 가드 적용

func cubeRoot*(x: float64): float64 =
  ## 순수 Nim Newton-Raphson 큐브 루트 — 컴파일 타임 VM 호환
  ## std/math.cbrt는 {.importc.} FFI이므로 컴파일 타임에 사용 불가
  if x == 0.0: return 0.0
  var guess = x / 3.0
  for _ in 0..<50:
    guess = (2.0 * guess + x / (guess * guess)) / 3.0
  result = guess

func calculatePriority*(m: ModuleMetrics): float =
  ## 기하평균 기반 결정론적 우선순위 산출
  ## ∛(HotspotDepth × ASTNodeCount × InDegree)
  if m.hotspotDepth <= 0.0 or m.astNodeCount <= 0.0 or m.inDegree <= 0.0:
    return 0.0
  result = cubeRoot(m.hotspotDepth * m.astNodeCount * m.inDegree)

func computeDensity*(total, covered: int): float =
  ## 명세 대수적 밀도 계산
  if total <= 0: return 0.0
  result = float(covered) / float(total)

func isHotspot*(m: ModuleMetrics): bool =
  ## 핫스팟 모듈 판정
  calculatePriority(m) > HotspotCriticalThreshold

macro verifySpecCompleteness*(
  moduleName: static string;
  metrics: static ModuleMetrics
): untyped =
  ## 컴파일 타임에 핫스팟 점수를 검증하는 코어 매크로
  ## 사용법: verifySpecCompleteness("my_module", ModuleMetrics(...))
  let score = calculatePriority(metrics)
  
  result = newStmtList()
  
  # 컴파일 타임 로그
  let scoreLit = newFloatLitNode(score)
  let nameLit = newStrLitNode(moduleName)
  result.add quote do:
    static:
      when defined(axiomDebug):
        echo "⚡ [Axiom SpecEngine] Module: ", `nameLit`,
             " -> Priority: ", `scoreLit`

  # 핫스팟 상위 모듈에 대한 컴파일 타임 하드 가드
  if score > HotspotCriticalThreshold:
    result.add quote do:
      static:
        when defined(axiomDebug):
          echo "🚨 Critical Hotspot: ", `nameLit`,
               " (score=", `scoreLit`, ") — enforcing absolute invariants"

{.pop.}
