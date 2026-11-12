import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary


## Refactoring Template Types — SSOT for refactoring signal/pattern taxonomy.
## Extracted from core/diagnostics/refactoring_engine to resolve
## SOC-leaf-module-imports violation in core/types/remediation_types.nim.

type
  RefactoringSignalKind* = enum
    rskQuantifierExcess       ## quantifierCount > 0
    rskNonLinearArithmetic    ## nonLinearArithmeticCount > 0
    rskDeepDependency         ## dependencyDepth >= 3
    rskHighCoupling           ## couplingScore > threshold
    rskMissingLoopInvariant   ## hasLoop detected
    rskMissingDecreaseMeasure ## hasRecursion detected

  RefactoringPatternKind* = enum
    rpkExtractPureFunction       ## Extract quantifier scope into pure func
    rpkLinearizeVariables        ## Replace nonlinear constraints with linear aux vars
    rpkInsertCompositionNode     ## Add intermediate composition node
    rpkIsolateInterface          ## Separate boundary contract
    rpkAddLoopInvariant          ## Add loop invariant annotation
    rpkAddDecreaseMeasure        ## Add termination measure

  PreconditionSeverity* = enum
    psHard    ## 구조적 무결성 — 실패 시 변형 자체가 불가능
    psSoft    ## 적용 가능성 — 실패해도 변형 시도 가능, Z3가 검증

  RefactoringTemplate* = object
    signal*: RefactoringSignalKind
    pattern*: RefactoringPatternKind
    description*: string         ## Human-readable description
    nimHint*: string             ## Code transformation hint
    priority*: int               ## Higher = more impactful
    severity*: PreconditionSeverity  ## Phase 1: psSoft 고정

{.pop.}
