import core/trusted/layer_declaration
axiomLayer "domain"
import std/math
import std/monotimes
import core/utils/constants
export constants
import core/trusted/axiom_pragmas_lite
const
  scribeMaxRounds* = 3          ## LLM (Leanstral) max feedback rounds
  cegarMaxIterations* = 20      ## CEGAR refinement max iterations
  judgeMaxAttempts* = 5         ## Lean kernel replay max attempts (pipeline_verdict_engine threshold)
  maxTotalSolverInvocations* = scribeMaxRounds + judgeMaxAttempts  ## 8 total gas units (per-node retry budget)

  MaxGasCostPerNode* = 4  ## calculateAdaptiveGas clamp 상한 — 소비 레이어와 동기화

  nodeWallClockTimeoutMs* = 120_000            ## 2 min per-node safety net

  # Deterministic solver budgets (rlimit-primary, per Z3 4.5+ rlimit docs)
  # SSOT for all solver/verification timeouts. Import proof_budget, not constants.
  z3DeterministicBudget* = 30_000_000  ## rlimit steps (deterministic, CPU-independent)
  z3SafetyNetMs* = 60_000              ## wall-clock safety net (2× typical query)
  leanLspHardTimeoutMs* = 5_000        ## Lean LSP hard timeout
  llmDefaultTimeoutMs* = 30_000        ## LLM backend default timeout
  cegarBudgetMs* = 30_000              ## CEGAR loop budget

  # Complexity Entropy weights (must sum to 1.0)
  entropyWeightTopology* = 0.25        ## w₁: topology signal weight
  entropyWeightSieve* = 0.30           ## w₂: sieve probability weight
  entropyWeightCegar* = 0.25           ## w₃: CEGAR difficulty weight
  entropyWeightHistorical* = 0.20      ## w₄: historical avg gas weight

  # Budget critical threshold (ratio → triggers Global Reset)
  budgetCriticalThreshold* = 0.85      ## gasRemaining/gasTotal ≤ this = critical

  # K-Induction depth bounds
  kInductionMaxDepthDefault* = 16      ## default max k for k-induction
  kInductionMaxDepthCeiling* = 64      ## absolute ceiling for k-induction

  # Deterministic rlimit / heartbeat budgets
  defaultRlimitBudget* = 30_000_000   ## Default Z3 rlimit (matches z3DeterministicBudget)
  defaultHeartbeatBudget* = 300_000   ## Default Lean heartbeat (matches maxHeartbeats 300000)
type
  ProofBudgetKind* = enum
    pbkGasLimit       ## Iteration-count based (deterministic)
    pbkWallClock      ## Time-based (safety net)

  ProofBudgetVerdict* = enum
    pbvContinue       ## Budget remaining
    pbvGasExhausted   ## Deterministic failure — gas limit reached
    pbvTimeout        ## Safety net — wall-clock exceeded

  ProofBudget* = object
    ## Proof execution budget with deterministic gas + wall-clock safety net.
    gasRemaining*: int            ## Solver invocations remaining
    gasTotal*: int                ## Total gas allocated
    wallDeadlineMs*: int64        ## Wall-clock deadline (nanosecond ticks)
    startMono*: int64             ## Monotonic clock at creation (nanosecond ticks)
    invocations*: int             ## Current invocation count
    rlimitBudget*: int            ## Z3 rlimit step budget (deterministic)
    rlimitConsumed*: int          ## Consumed rlimit steps
    heartbeatBudget*: int         ## Lean maxHeartbeats (deterministic)

  ComplexitySignals* = object
    ## Aggregated complexity signals for a verification node.
    ## Used by computeComplexityEntropy() to determine gas allocation.
    ##
    ## Sources (all already exist in the codebase):
    ##   - topologyScore: topology_engine.nim (TopologyNodeMetric)
    ##   - sieveProbabilityScore: sieve_engine.nim (SieveVerdict)
    ##   - cegarIterations, cegarStagnationCount: cegar_engine.nim (CegarEngineResult)
    ##   - z3RejectionCount: refactoring_engine.nim (RefactoringStagnation)
    ##   - synergyGeometricMean: refactoring_engine.nim (SynergyMetrics)
    topologyScore*: float         ## Normalized [0,1] from topology_engine
    sieveProbability*: float      ## Already [0,1] from sieve_engine
    cegarIterations*: int         ## Raw iteration count from CEGAR
    cegarStagnationCount*: int    ## Stagnation count (local var, needs export)
    z3RejectionCount*: int        ## Consecutive Z3 failures
    synergyGeometricMean*: float  ## f×g×h geometric mean [0,1]
    historicalAvgGas*: float      ## Avg gas consumed by similar nodes [0,1]
func initProofBudgetFromMono*(
  startMono: int64;
  gasLimit: int = maxTotalSolverInvocations;
  wallClockMs: int = orchestrationWallClockTimeoutMs;
  rlimitBudget: int = defaultRlimitBudget;
  heartbeatBudget: int = defaultHeartbeatBudget
): ProofBudget {.raises: [].} =
  ## Pure constructor — inject monotonic clock value at the boundary.
  ProofBudget(
    gasRemaining: gasLimit,
    gasTotal: gasLimit,
    wallDeadlineMs: startMono + int64(wallClockMs) * 1_000_000,
    startMono: startMono,
    invocations: 0,
    rlimitBudget: rlimitBudget,
    rlimitConsumed: 0,
    heartbeatBudget: heartbeatBudget
  )
proc initProofBudget*(
  gasLimit: int = maxTotalSolverInvocations;
  wallClockMs: int = orchestrationWallClockTimeoutMs
): ProofBudget {.raises: [], axiomEffect: IOEffect.} =
  ## Effectful wrapper — reads system clock, delegates to pure constructor.
  initProofBudgetFromMono(getMonoTime().ticks, gasLimit, wallClockMs)
func consumeGas*(budget: var ProofBudget; cost: int = 1): ProofBudgetVerdict {.raises: [].} =
  ## Consume gas units proportional to cost (default 1). Returns verdict.
  ## Use topologyScore-weighted cost for dynamic allocation.
  inc budget.invocations
  budget.gasRemaining -= cost
  if budget.gasRemaining <= 0:
    return pbvGasExhausted
  pbvContinue
func consumeRlimit*(budget: var ProofBudget; steps: int): ProofBudgetVerdict {.raises: [].} =
  ## Consume rlimit steps. Returns verdict.
  budget.rlimitConsumed += steps
  if budget.rlimitConsumed >= budget.rlimitBudget:
    return pbvGasExhausted
  pbvContinue
proc checkBudget*(budget: ProofBudget): ProofBudgetVerdict {.raises: [], axiomEffect: IOEffect.} =
  ## Check if budget is exhausted (without consuming).
  if budget.gasRemaining <= 0:
    return pbvGasExhausted
  if getMonoTime().ticks >= budget.wallDeadlineMs:
    return pbvTimeout
  pbvContinue
func gasUsed*(budget: ProofBudget): int {.raises: [].} =
  budget.gasTotal - budget.gasRemaining
proc elapsedMs*(budget: ProofBudget): int64 {.raises: [], axiomEffect: IOEffect.} =
  (getMonoTime().ticks - budget.startMono) div 1_000_000
func isDeterministicFailure*(verdict: ProofBudgetVerdict): bool {.raises: [].} =
  ## True if failure was deterministic (gas limit), not timing-dependent.
  verdict == pbvGasExhausted
## ─── Complexity Entropy ──────────────────────────────────────────────────────
## Adaptive gas allocation based on node complexity.
##
## Problem: static gasCost = clamp(topologyScore, 1, 10) allows a single
## high-topology node to consume the entire budget (8 units).
##
## Solution: Complexity Entropy combines multiple signals into a single
## difficulty metric, then allocates gas proportionally.
##
## Theory: Shannon entropy H measures uncertainty. High entropy = high
## difficulty = more gas needed. Low entropy = predictable = less gas.
##
## References:
##   - Gulwani 2017: search space pruning by difficulty estimation
##   - CompCert (Leroy 2008): per-pass resource allocation
func clamp01*(x: float): float {.raises: [].} =
  ## Clamp to [0, 1] range.
  if x < 0.0: 0.0
  elif x > 1.0: 1.0
  else: x
func computeCegarDifficulty*(signals: ComplexitySignals): float {.raises: [].} =
  ## Compute CEGAR difficulty from iteration count and stagnation.
  ## Range: [0, 1] where 1 = maximum difficulty.
  let iterNorm = if cegarMaxIterations > 0:
    float(signals.cegarIterations) / float(cegarMaxIterations)
  else: 0.0
  let stagnationNorm = if signals.cegarStagnationCount > 0:
    min(1.0, float(signals.cegarStagnationCount) / 3.0)
  else: 0.0
  let z3Norm = if signals.z3RejectionCount > 0:
    min(1.0, float(signals.z3RejectionCount) / 3.0)
  else: 0.0
  clamp01(iterNorm * 0.4 + stagnationNorm * 0.3 + z3Norm * 0.3)
func computeComplexityEntropy*(signals: ComplexitySignals): float {.raises: [].} =
  ## Compute the Complexity Entropy H(n) for a verification node.
  ##
  ## Formula:
  ##   H(n) = w₁·topologyScore + w₂·sieveProbability +
  ##          w₃·cegarDifficulty + w₄·historicalAvgGas
  ##
  ## Range: [0, 1] where 1 = maximum complexity.
  ## All inputs are pre-normalized to [0, 1].
  let cegarDiff = computeCegarDifficulty(signals)
  result =
    entropyWeightTopology * clamp01(signals.topologyScore) +
    entropyWeightSieve * clamp01(signals.sieveProbability) +
    entropyWeightCegar * cegarDiff +
    entropyWeightHistorical * clamp01(signals.historicalAvgGas)
  result = clamp01(result)
func adaptiveGasCost*(
  entropy: float;
  gasTotal: int;
  expectedNodeCount: int
): int {.raises: [].} =
  ## Compute gas cost for a node based on its complexity entropy.
  ##
  ## Replaces the static `clamp(topologyScore, 1, 10)` with an
  ## entropy-proportional allocation.
  ##
  ## Formula:
  ##   maxGasPerNode = gasTotal / expectedNodeCount
  ##   gasCost = max(1, round(entropy × maxGasPerNode × 2))
  ##
  ## The ×2 factor allows high-entropy nodes to consume up to
  ## 2× their fair share, compensated by low-entropy nodes using less.
  if expectedNodeCount <= 0:
    return 1
  let maxGasPerNode = max(1, gasTotal div expectedNodeCount)
  let rawCost = int(float(maxGasPerNode) * 2.0 * clamp01(entropy) + 0.5)
  max(1, min(rawCost, gasTotal))  # At least 1, at most total
func redistributeSurplus*(
  budget: var ProofBudget;
  allocatedCost: int;
  actualCost: int;
  remainingNodes: int
) {.raises: [].} =
  ## After a node completes, redistribute unused gas to remaining nodes.
  ##
  ## This closes the open-loop → adaptive budget cycle:
  ##   1. Allocate gas proportional to entropy
  ##   2. Node completes (may use less or more than allocated)
  ##   3. Surplus is redistributed to remaining nodes
  if remainingNodes <= 0:
    return
  let surplus = allocatedCost - actualCost
  if surplus > 0:
    # Return surplus to the budget pool
    budget.gasRemaining += surplus
func isBudgetCritical*(budget: ProofBudget): bool {.raises: [].} =
  ## True if gas remaining ≤ 20% of total.
  ## Used as a Global Reset trigger.
  if budget.gasTotal <= 0:
    return true
  float(budget.gasRemaining) / float(budget.gasTotal) <= budgetCriticalThreshold

## ─── K-Induction Depth Estimation ────────────────────────────────────────────
func estimateMaxK*(
  entropy: float;
  maxLoopNestingDepth: int;
  cegarIterations: int = 0
): int {.raises: [].} =
  ## Estimate the maximum k for k-induction based on code complexity.
  ##
  ## Sheeran et al. (2000): "The length of the longest serial connection
  ## of latches is usually a lower bound on the number of iterations needed."
  ##
  ## maxLoopNestingDepth is the maximum nesting depth of loop constructs,
  ## which approximates the latch chain length.
  ##
  ## Formula:
  ##   baseK = max(2, maxLoopNestingDepth)
  ##   cegarBonus = min(cegarIterations div 3, 4)
  ##   entropyBonus = entropy × 8
  ##   result = min(baseK + cegarBonus + entropyBonus, kInductionMaxDepthCeiling)
  let baseK = max(kInductionMaxDepthDefault, maxLoopNestingDepth)
  let cegarBonus = min(cegarIterations div 3, 4)
  let entropyBonus = int(clamp01(entropy) * 8.0)
  min(baseK + cegarBonus + entropyBonus, kInductionMaxDepthCeiling)

## ─── Geometric Mean Gas Allocation ──────────────────────────────────────────
func calculateAdaptiveGas*(
  topologyScore: int;
  entropy: float;
  nestingDepth: int
): int {.raises: [].} =
  ## 위상적 위치 + 코드 내부 복잡도 + 루프 중첩 깊이의 기하평균.
  ## 기하평균은 산술평균보다 이상치에 강건함.
  ##
  ## Safeguard 1 (Gemini): pow(x, 1/3) 폴백 사용 (cbrt 바인딩 모호성 회피)
  ## Safeguard 2: 모든 인자를 float으로 명시적 캐스팅
  if topologyScore <= 0: return 1
  let tWeight = float(max(1, topologyScore))
  let eWeight = max(1.0, entropy * 4.0)
  let dWeight = float(max(1, nestingDepth * 2))
  let product = tWeight * eWeight * dWeight
  let geoMean = pow(product, 1.0 / 3.0)  # cbrt 대신 pow 폴백
  result = clamp(int(round(geoMean)), 1, MaxGasCostPerNode)  # 최소 1, 최대 MaxGasCostPerNode

func initPerUnitBudget*(
  topologyScore: int;
  entropy: float;
  nestingDepth: int;
  startMono: int64
): ProofBudget {.raises: [].} =
  ## Per-unit budget derived from the unit's own complexity signals.
  ## Gas limit is computed from the unit's own topology, entropy, and
  ## nesting depth — independent of run-global frontier size.
  let gasLimit = calculateAdaptiveGas(topologyScore, entropy, nestingDepth)
  initProofBudgetFromMono(startMono, gasLimit = gasLimit)


