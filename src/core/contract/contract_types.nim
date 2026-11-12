import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/sets
import std/tables

## Extracted function contract as SMT-LIB2 assertions.
type
  ExtractedContract* = object
    preconditions*: seq[string]  ## Assertions that must hold before call
    postconditions*: seq[string] ## Assertions that hold after call

  ExtractionContext* = object
    ## Scope-aware extraction context for deterministic contract extraction.
    functionName*: string
    paramNames*: HashSet[string]
    paramTypes*: Table[string, string]
    returnType*: string        ## Function return type for type-driven contract extraction
    scopeDepth*: int           ## 제어 흐름 깊이 (0=최상위)
    inControlFlow*: bool       ## if/for/while 블록 내부 여부

## Type names that should never be treated as indexing targets or indices.
const smtTypeNames* = ["int", "string", "char", "bool", "float", "seq",
                       "array", "openarray", "tuple", "set", "table"]

{.pop.}
