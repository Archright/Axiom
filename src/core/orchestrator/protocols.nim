import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Domain Protocols — Compile-Time Contracts (Concepts)
import core/symbolic/symbolic_types_expr
##
## Domain이 Infrastructure에 요구하는 계약을 컴파일 타임 concept로 정의합니다.
## Infrastructure는 이 개념을 충족하는 구체적 타입을 제공하면 컴파일 성공합니다.
## Domain은 구체적 Infrastructure를 import하지 않고 오직 이 계약에만 의존합니다.
##
## Context7: "Concepts are a user-defined mechanism for creating custom type classes
##            that match other types based on specified bindings."
## 실컴파일 검증: Nim 2.2.10에서 TopologyOrchestrator[L: LeanEngine; Z: Z3Solver] 성공.

import core/types/domain_types, core/types/results, core/orchestrator/cegar_types, core/orchestrator/cfg_builder

type
  # === Infrastructure Contracts ===

  LeanEngine* = concept e
    ## Lean 4 증명 엔진 계약.
    ## Infrastructure 측 ConcreteLeanEngine이 이 계약을 충족하면 컴파일 성공.
    e.runLeanProofRefinementLoop(string) is Result[string, string]
    e.runNegativeInvariantSearch(string) is Result[string, string]

  Z3Solver* = concept s
    ## Z3 솔버 계약.
    ## encodeProvedInvariantsSmtlib2: 순수 함수 (I/O 없음)
    ## runCegarLoop: I/O 가능 (CatchableError 허용)
    s.encodeProvedInvariantsSmtlib2(string) is string

  HealingOrchestrator* = concept h
    ## 힐링 파이프라인 계약.
    h.runSelfHealingLoop(string, seq[string]) is Result[string, string]

  CertificateVerifier* = concept v
    ## 인증서 검증 계약.
    v.verifyCertificates(string, bool, string, bool) is VerificationReportSummary

  # === Gate Contracts ===

  GateEvaluator* = concept g
    ## 게이트 평가 계약.
    ## Infrastructure 측이 Gate 규칙을 적용하여 GateDirectiveBundle을 반환.
    g.applyGateRule(FunctionCertificate) is GateDirectiveBundle[FunctionCertificate]

  # === CEGAR Callback ===
  CegarCallback* = proc(
    cfg: ControlFlowGraph;
    headerId: int;
    z3Check: proc(query: string): bool {.closure, gcsafe, raises: [CatchableError].};
    budgetMs: int64
  ): CegarEngineResult {.raises: [CatchableError], gcsafe.}

  EncodeSmtlib2Callback* = proc(
    invariants: seq[SymSExpr]
  ): string {.raises: [], gcsafe.}

{.pop.}
