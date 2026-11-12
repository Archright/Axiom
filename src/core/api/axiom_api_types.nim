import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Axiom API Types
## Response and payload type definitions for the Axiom public API.

type
  BmcVerificationResponse* = object
    raceDetected*: bool
    raceFinalState*: int
    bothWritePathExists*: bool
    sequentialResultA*: int
    sequentialResultB*: int
    sequentialUniqueCount*: int
    stepBound*: int

  SymbolicVerificationResponse* = object
    status*: string
    smt2*: string
    hasCounterExample*: bool
    counterExampleProperty*: string
    inductionProved*: bool
    k*: int
    baseSmt2*: string
    stepSmt2*: string

{.pop.}
