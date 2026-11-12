import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## ExecutionWitness — records a canonical proof/solver invocation.
##
## Witness existence is orthogonal to the result value.
## A TIMEOUT has an execution witness and IS EXECUTED.
## The executionIdentity comes from executionIdentity() in obligation/identity.nim.

type
  ExecutionWitness* = object
    executionIdentity*: string   ## from executionIdentity() (obligation/identity.nim:252)
    prover*: string              ## "z3" | "lean"
    invocationId*: string

{.pop.}