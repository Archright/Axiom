import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Axiom Effect Tags — compiler-tracked side effect classification
##
## These tags allow the compiler to enforce effect boundaries at compile time.
## A proc annotated with {.tags: [].} will fail to compile if it calls any
## proc tagged with IO, ProcessExec, etc.

type
  FileIO* = object       ## File system read/write
  ProcessExec* = object  ## External process execution
  NetworkIO* = object    ## Network communication
  MutableState* = object ## Global mutable state modification

{.pop}
