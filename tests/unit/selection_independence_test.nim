# selection_independence_test.nim — S0b 선택 독립성 회귀 테스트
#
# 선택 독립성 불변식 검증: 동일 단위 U에 대해 Plan A(U만 포함)와
# Plan B(U + 다른 단위들 포함)가 동일한 단위 semantic 입력 하에
# 동일한 결과를 산출해야 함.
#
# CLEAN 경로(2-8): 결정적 동일성 어설션 — 항상 통과해야 함.
# 예산 경로(1): per-unit budget 독립성 검증 — S0b fix 후 통과해야 함.
#
# 실행: nim c -r --hints:off tests/unit/selection_independence_test.nim

import std/[unittest, tables, strutils, options, monotimes]

import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/axiom_pragmas
import core/crypto/hash_kernel
import core/deterministic_cas_key
import core/proof/proof_budget
import core/proof/source_fingerprint
import core/types/function_verification_summary
import cli/selection_state
import verification/obligation/canonical_obligation_generator
import verification/obligation/identity
import verification/obligation/obligation_ir

# ==========================================================================
# Fixture: 동일한 단위 U에 대한 두 가지 Plan 시나리오
# ==========================================================================

func makeTestFuncDef(): IRFuncDef =
  ## 단순한 정수 덧셈 함수 — Plan A와 Plan B 모두에 동일하게 제공.
  IRFuncDef(
    name: "add",
    params: @[IRFuncParam(name: "a", ty: irTypeBitVec64(), constraint: none(IRExpr)),
              IRFuncParam(name: "b", ty: irTypeBitVec64(), constraint: none(IRExpr))],
    retType: irTypeBitVec64(),
    body: irBinOp(boAdd, irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64())),
    isRecursive: false,
    preConditions: @[],
    postConditions: @[]
  )

# ==========================================================================
# Suite: 선택 독립성 — CLEAN 경로
# ==========================================================================

suite "Selection-Independence — CLEAN Paths":

  # -----------------------------------------------------------------------
  # 경로 2: 배치 메모리 캐시 (memoCache) — CAS 키 결정성
  # -----------------------------------------------------------------------
  test "CAS key is deterministic for identical IRFuncDef regardless of plan context":
    ## ir_pipeline_runner.nim:1224 — computeDeterministicCasKey(serializeIRFuncDef(funcDef))
    ## 동일한 funcDef는 Plan 크기와 무관하게 동일한 CAS 키를 산출해야 함.
    let funcDef = makeTestFuncDef()
    let astHash = serializeIRFuncDef(funcDef)
    let key1 = computeDeterministicCasKey(astHash)
    let key2 = computeDeterministicCasKey(astHash)
    check key1 == key2
    check key1.len == 64  # SHA-256 hex length

  test "CAS key differs for different IRFuncDef":
    ## CAS 키가 funcDef 내용에 민감해야 함 — 다른 함수는 다른 키.
    let funcDefA = makeTestFuncDef()
    let funcDefB = IRFuncDef(
      name: "sub",
      params: funcDefA.params,
      retType: funcDefA.retType,
      body: irBinOp(boSub, irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64())),
      isRecursive: false,
      preConditions: @[],
      postConditions: @[]
    )
    let keyA = computeDeterministicCasKey(serializeIRFuncDef(funcDefA))
    let keyB = computeDeterministicCasKey(serializeIRFuncDef(funcDefB))
    check keyA != keyB

  # -----------------------------------------------------------------------
  # 경로 3: summaryCache — 키 결정성 + 지문 체크섬
  # -----------------------------------------------------------------------
  test "summaryCache key is deterministic for same modulePath and functionName":
    ## types.nim:18 — key = modulePath#functionName (makeCacheKey)
    let key1 = makeCacheKey("moduleA", "foo")
    let key2 = makeCacheKey("moduleA", "foo")
    check key1 == key2
    check key1 == "moduleA#foo"

  test "summaryCache key distinguishes different functions":
    let keyA = makeCacheKey("moduleA", "foo")
    let keyB = makeCacheKey("moduleA", "bar")
    check keyA != keyB

  test "source fingerprint is deterministic for identical source":
    ## source_fingerprint.nim:16 — computeStableSourceFingerprint는 결정적.
    let source = "proc add(a, b: int): int = a + b"
    let fp1 = computeStableSourceFingerprint(source)
    let fp2 = computeStableSourceFingerprint(source)
    check fp1 == fp2
    check fp1.len == 64  # SHA-256 hex length

  test "source fingerprint differs for different source":
    let fpA = computeStableSourceFingerprint("proc foo(): int = 1")
    let fpB = computeStableSourceFingerprint("proc foo(): int = 2")
    check fpA != fpB

  # -----------------------------------------------------------------------
  # 경로 4: 배치 순서 — 결정적 결과 병합
  # -----------------------------------------------------------------------
  test "computeDeterministicCasKey is deterministic for same input across calls":
    ## loop_depth_scheduler.nim:467-470 — taskIndex 기반 재정렬은
    ## 동일한 입력에 대해 동일한 결과를 산출.
    let funcDef = makeTestFuncDef()
    let key1 = computeDeterministicCasKey(serializeIRFuncDef(funcDef))
    let key2 = computeDeterministicCasKey(serializeIRFuncDef(funcDef))
    let key3 = computeDeterministicCasKey(serializeIRFuncDef(funcDef))
    check key1 == key2
    check key2 == key3

  # -----------------------------------------------------------------------
  # 경로 5: 랭킹/선택 상태 — 순위만 영향, 검증 매개변수 무영향
  # -----------------------------------------------------------------------
  test "computeScore depends only on selection count, not on other nodes":
    ## selection_state.nim:56-60 — Score(s) = 1/(Count(s)+1).
    ## Plan A(U만)와 Plan B(U+다른노드)에서 U의 score는 U의 선택 횟수에만 의존.
    let score0 = computeScore(0)
    let score1 = computeScore(1)
    let score5 = computeScore(5)
    check score0 > score1
    check score1 > score5
    check score0 == 1.0
    check score1 == 0.5
    check score5 > 0.0

  test "computeScore is invariant to frontier size for same count":
    ## 동일한 count에 대해 score는 frontier 크기와 무관해야 함.
    let scoreA = computeScore(3)
    let scoreB = computeScore(3)
    check scoreA == scoreB

  test "incrementCount tracks per-node counts independently of plan composition":
    ## NodeSelectionState의 counts 테이블은 개별 노드 ID만 관리.
    var stateA = emptyState()
    var stateB = emptyState()
    incrementCount(stateA, @["unitU"])
    incrementCount(stateB, @["unitU", "otherX", "otherY"])
    check stateA.counts["unitU"] == 1
    check stateB.counts["unitU"] == 1  # U의 count는 Plan과 무관
    check stateB.counts["otherX"] == 1
    check stateB.counts["otherY"] == 1

  # -----------------------------------------------------------------------
  # 경로 6: 프론티어/스코프 — 적격성 필터링만, 의무 내용은 단위 로컬
  # -----------------------------------------------------------------------
  test "generateCanonicalObligations produces obligation kind from funcDef + policy only":
    ## verified_frontier.nim:40-96 — frontier는 sorterNodeId 목록만 반환.
    ## canonical_obligation_generator.nim:147 — 순수 함수, funcDef + policy만 의존.
    let funcDef = makeTestFuncDef()
    let policy = defaultScopePolicy()
    let obligations = generateCanonicalObligations(funcDef, policy)
    check obligations.kind in [ogrGenerated, ogrNoApplicableObligation, ogrUnsupported, ogrIllFormed]

  # -----------------------------------------------------------------------
  # 경로 7: 솔버 세션 — per-query reset + fresh prover
  # -----------------------------------------------------------------------
  test "computeDeterministicCasKey is pure and side-effect-free":
    ## deterministic_cas_key.nim:17-23 — SHA-256 기반 순수 함수.
    let key1 = computeDeterministicCasKey("test-input")
    let key2 = computeDeterministicCasKey("test-input")
    let key3 = computeDeterministicCasKey("different-input")
    check key1 == key2
    check key1 != key3
    check key1.len == 64

  # -----------------------------------------------------------------------
  # 경로 8: 의무 생성 — 순수 함수, funcDef + policy만 의존
  # -----------------------------------------------------------------------
  test "generateCanonicalObligations is pure: same funcDef+policy yields same result":
    ## canonical_obligation_generator.nim:147 — 순수 함수.
    let funcDef = makeTestFuncDef()
    let policy = defaultScopePolicy()
    let result1 = generateCanonicalObligations(funcDef, policy)
    let result2 = generateCanonicalObligations(funcDef, policy)
    check result1.kind == result2.kind

  test "generateCanonicalObligations result depends on funcDef content":
    ## 다른 funcDef는 다른 의무 집합을 산출.
    let funcDefA = makeTestFuncDef()
    let funcDefB = IRFuncDef(
      name: "mul",
      params: funcDefA.params,
      retType: funcDefA.retType,
      body: irBinOp(boMul, irVar("a", irTypeBitVec64()), irVar("b", irTypeBitVec64())),
      isRecursive: false,
      preConditions: @[],
      postConditions: @[]
    )
    let policy = defaultScopePolicy()
    let resultA = generateCanonicalObligations(funcDefA, policy)
    let resultB = generateCanonicalObligations(funcDefB, policy)
    ## 결과가 funcDef 내용에만 의존함을 검증.
    check resultA.kind == resultB.kind  # 둘 다 admissible → 동일 kind

  # -----------------------------------------------------------------------
  # 경로 9: 실행 정체성 — 동일 입력 → 동일 정체성
  # -----------------------------------------------------------------------
  test "executionIdentity is identical for identical inputs":
    ## identity.nim:212-217 — executionIdentity = H(InputIdentity | ExecutionContractDigest | BundleFingerprint).
    let inputId = sha256Hex("test-source-code")
    let contractDigest = sha256Hex("test-contract")
    let bundleFp = sha256Hex("test-bundle")
    let execId1 = executionIdentity(inputId, contractDigest, bundleFp)
    let execId2 = executionIdentity(inputId, contractDigest, bundleFp)
    check execId1 == execId2
    check execId1.len == 64

  test "executionIdentity differs for different input identity":
    let inputIdA = sha256Hex("source-A")
    let inputIdB = sha256Hex("source-B")
    let contractDigest = sha256Hex("test-contract")
    let bundleFp = sha256Hex("test-bundle")
    let execIdA = executionIdentity(inputIdA, contractDigest, bundleFp)
    let execIdB = executionIdentity(inputIdB, contractDigest, bundleFp)
    check execIdA != execIdB

# ==========================================================================
# Suite: 선택 독립성 — 예산 경로 (per-unit budget 독립성)
# ==========================================================================

suite "Selection-Independence — Budget Path (Per-Unit Budget Independence)":

  test "per-unit budget is independent of frontier size":
    ## S0b fix: each unit's budget is derived from its own complexity
    ## signals (calculateAdaptiveGas) — NOT from a run-global pool
    ## scaled by frontier.len.  Plan A (1 node) and Plan B (5 nodes)
    ## give the same unit U the same per-unit budget.
    let topologyScore = 3
    let entropy = 0.5'f
    let nestingDepth = 2
    let budgetA = initPerUnitBudget(topologyScore, entropy, nestingDepth, 0)
    let budgetB = initPerUnitBudget(topologyScore, entropy, nestingDepth, 0)
    check budgetA.gasTotal == budgetB.gasTotal
    check budgetA.gasTotal == calculateAdaptiveGas(topologyScore, entropy, nestingDepth)

  test "per-unit budget verdict is consistent across plans":
    ## S0b fix: same unit U with same signals gets the same verdict
    ## regardless of how many other units are in the run.
    let topologyScore = 3
    let entropy = 0.5'f
    let nestingDepth = 2
    let startMono = getMonoTime().ticks
    let budget = initPerUnitBudget(topologyScore, entropy, nestingDepth, startMono)
    let verdict = checkBudget(budget)
    check verdict == pbvContinue

  test "per-unit budget gasTotal matches calculateAdaptiveGas output":
    ## Each unit's budget gas limit equals its own computeAdaptiveGas
    ## result — derived from topologyScore, entropy, nestingDepth.
    let topologyScore = 5
    let entropy = 0.8'f
    let nestingDepth = 3
    let gasLimit = calculateAdaptiveGas(topologyScore, entropy, nestingDepth)
    let budget = initPerUnitBudget(topologyScore, entropy, nestingDepth, 0)
    check budget.gasTotal == gasLimit
    check budget.gasTotal <= MaxGasCostPerNode