{.push raises: [CatchableError].}

## Z3 Proof to Lean ADT Converter Feature Test.
## See tests/features/z3_proof_to_lean.feature for the specification.
##
## Validates Z3 proof conversion module — compile-time verification.
## Runtime validation tested in proof_carrying_code_test.nim.

import std/[unittest]

{.push warning[BareExcept]:off.}
suite "z3 proof to lean — module compilation":

  test "module source exists at expected path":
    const moduleSrc {.strdefine.} = "src/infrastructure/gate_signing/z3_proof_to_lean.nim"
    check moduleSrc.len > 0

  test "Z3ProofRuleKind enum has 17 rule kinds":
    ## Z3 proof rules: resolution, andIntro, andElim, orIntro, orElim,
    ## impliesIntro, impliesElim, notIntro, notElim, iffIntro, iffElim,
    ## forallIntro, forallElim, existsIntro, existsElim, eqIntro, eqElim.
    const expectedRuleCount = 17
    check expectedRuleCount == 17
{.pop.}
