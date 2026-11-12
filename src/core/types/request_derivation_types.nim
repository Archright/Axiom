import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import core/types/request_id

## Request derivation shared types
##
## These types are used by request_oracle.nim, request_derivation.nim,
## and request_completeness.nim without any cross-import edges between
## those modules. All three import from this leaf type file.

## FallbackTrigger — kinds that can trigger a fallback disposition
type
  FallbackTrigger* = enum
    ftBudget           ## budget cap exceeded
    ftUnknownSeed      ## seed not in universe
    ftUnresolvedEdge   ## unresolved graph edge encountered
    ftOracleGap        ## oracle detects gap between expected and selected

## RequestPolicy — small policy object for derivation
type
  RequestPolicy* = object
    budgetCap*: int                       ## maximum number of requests allowed
    fallbackOn*: set[FallbackTrigger]     ## triggers that force fallback disposition

## DispositionKind
type
  DispositionKind* = enum
    dkSkip      ## request skipped (not derived)
    dkFallback  ## request derived via fallback policy

## Disposition — skip/fallback entries MUST carry evidence
## A disposition without evidence is treated as a Completeness violation.
type
  Disposition* = object
    kind*: DispositionKind
    requestId*: RequestId
    evidence*: string    ## reason string explaining why this disposition applies
    basis*: string       ## which independent basis it rests on (e.g., "eligibility", "budget", "fallback")

## DerivationResult — output of deriveRequests
type
  DerivationResult* = object
    requests*: seq[RequestId]
    dispositions*: seq[Disposition]

## CompletionCheck — result of checkCompleteness
type
  CompletionCheck* = object
    ok*: bool
    missing*: seq[RequestId]      ## required ∖ (derived ∪ evidence-backed dispositions)
    unauthorized*: seq[RequestId] ## derived ∖ required (unless covered by a disposition)

{.pop.}