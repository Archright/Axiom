import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Provider Interface Abstraction (DEBT#003 + DEBT#007)
##
## Compile-time safe provider abstraction for solver backends.
## Uses distinct string for SolverStatus to prevent accidental raw string usage.
## Context7 reference: Nim manual - distinct types are incompatible with base type.
##
## Abstract types and SolverProvider concept live here (Domain layer).
## Concrete implementations (Z3Provider.execute, Lean4Provider.execute)
## live in verification/solver/provider_impl.nim (Infrastructure layer).

import core/solver/types
import core/trusted/axiom_pragmas

# ============================================================================
# Distinct SolverStatus (compile-time safe wrapper)
# ============================================================================

type
  ProviderSolverStatus* = distinct string
    ## Compile-time safe solver status.
    ## Prevents accidental mixing with raw strings.

# Status constants
const
  psSolverSat* = "sat".ProviderSolverStatus
  psSolverUnsat* = "unsat".ProviderSolverStatus
  psSolverUnknown* = "unknown".ProviderSolverStatus
  psSolverTimeout* = "timeout".ProviderSolverStatus
  psSolverVacuousContradiction* = "vacuous_contradiction".ProviderSolverStatus

# Conversion functions
func toProviderStatus*(status: SolverStatus): ProviderSolverStatus {.inline, raises: [].} =
  ## Convert enum SolverStatus to distinct string ProviderSolverStatus.
  solverStatusString(status).ProviderSolverStatus

func toSolverStatus*(ps: ProviderSolverStatus): SolverStatus {.raises: [].} =
  ## Convert distinct string ProviderSolverStatus back to enum SolverStatus.
  let s = string(ps)
  case s
  of "sat": solverSat
  of "unsat": solverUnsat
  of "unknown": solverUnknown
  of "timeout": solverTimeout
  of "vacuous_contradiction": solverVacuousContradiction
  else: solverUnknown

func providerStatusString*(ps: ProviderSolverStatus): string {.inline, raises: [].} =
  ## Get string representation of ProviderSolverStatus.
  string(ps)

func `==`*(a, b: ProviderSolverStatus): bool {.inline, raises: [].} =
  ## Equality comparison for ProviderSolverStatus.
  string(a) == string(b)

# ============================================================================
# Provider Interface (compile-time polymorphism)
# ============================================================================

type
  ProviderResult* = object
    ## Result from provider execution.
    status*: ProviderSolverStatus
    output*: string
    error*: string

  Z3Provider* = object
    ## Concrete Z3 provider backed by persistent process pool.
    timeoutMs*: int

  Lean4Provider* = object
    ## Concrete Lean 4 provider backed by compiler subprocess.
    timeoutMs*: int

# ============================================================================
# Provider Interface Concept
# ============================================================================

type
  SolverProvider* = concept p
    ## Compile-time interface for solver providers.
    ## Any type implementing execute() and providerName() satisfies this.
    p.execute("") is ProviderResult
    p.providerName() is string

# ============================================================================
# Provider Constructors (pure — no infrastructure dependency)
# ============================================================================

func initZ3Provider*(timeoutMs: int = 30000): Z3Provider {.inline, raises: [].} =
  ## Create Z3Provider with specified timeout.
  Z3Provider(timeoutMs: timeoutMs)

func initLean4Provider*(timeoutMs: int = 60000): Lean4Provider {.inline, raises: [].} =
  ## Create Lean4Provider with specified timeout.
  Lean4Provider(timeoutMs: timeoutMs)

# ============================================================================
# Generic Provider Execution (compile-time polymorphism)
# ============================================================================

proc executeProof*[T: SolverProvider](provider: T; query: string): ProviderResult {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Generic proof execution via provider interface.
  ## Compile-time polymorphism - no vtable overhead.
  provider.execute(query)

# ============================================================================
# NOTE: Concrete execute/providerName procs for Z3Provider and Lean4Provider
# live in verification/solver/provider_impl.nim (Infrastructure layer).
# Import that module at the composition root where solver execution is needed.
# ============================================================================

{.pop.}
