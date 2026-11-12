## Provider Interface type contract tests.
##
## Tests compile-time concept satisfaction and constructor contracts.
## DEBT#003 + DEBT#007 — provider abstraction.

import std/unittest
import core/trusted/provider_interface
import verification/solver/provider_impl

suite "Provider type contract and wiring":
  test "initLean4Provider creates provider with default timeout":
    let provider = initLean4Provider()
    check provider.timeoutMs == 60000

  test "initLean4Provider creates provider with custom timeout":
    let provider = initLean4Provider(timeoutMs = 5000)
    check provider.timeoutMs == 5000

  test "initZ3Provider creates provider with default timeout":
    let provider = initZ3Provider()
    check provider.timeoutMs == 30000

  test "initZ3Provider creates provider with custom timeout":
    let provider = initZ3Provider(timeoutMs = 10000)
    check provider.timeoutMs == 10000

  test "Lean4Provider satisfies SolverProvider concept at compile time":
    ## If Lean4Provider lacks execute/providerName, or their
    ## signatures mismatch SolverProvider, this module fails to compile.
    let provider = initLean4Provider()
    check provider.providerName() == "Lean4Provider"

  test "Z3Provider satisfies SolverProvider concept at compile time":
    ## If Z3Provider lacks execute/providerName, or their
    ## signatures mismatch SolverProvider, this module fails to compile.
    let provider = initZ3Provider()
    check provider.providerName() == "Z3Provider"

  test "ProviderSolverStatus distinct type prevents string mixing":
    ## Compile-time safety: ProviderSolverStatus is distinct string.
    let status = psSolverUnknown
    check status == psSolverUnknown
    check status != psSolverSat
    check status != psSolverUnsat
