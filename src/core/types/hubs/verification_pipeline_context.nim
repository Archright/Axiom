import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Canonical VerificationPipelineContext — SSOT for the verification
## pipeline's shared mutable state.
##
## Renamed from VerificationContext to disambiguate from the BMC/CEGAR/SMT
## bounded context in core/application/verification_context.nim (SSOT).

import std/sets
import std/tables
import core/types/domain_types
import core/symbolic/global_symbol_graph_types

type
  VerificationPipelineContext* = object
    ## Shared mutable state for the verification pipeline.
    ## Replaces 6+ loose variables previously threaded through verifyCertificates.
    report*: VerificationReportSummary
    idx*: VaultIndex
    graph*: GlobalSymbolGraph
    knownFunctions*: HashSet[string]
    globalsByModule*: Table[string, HashSet[string]]
    moduleFunctionsByPath*: Table[string, HashSet[string]]
    # Computed paths
    certDir*: string
    certBaseDir*: string
    normalizedCertDir*: string
    repoRoot*: string
    srcRoot*: string
    idxPath*: string
    # Control flags
    enableSymbolic*: bool
    freezeGraphCache*: bool
    tStart*: float
    shouldAbort*: bool  ## Set by stages that require early pipeline termination

{.pop.}
