## Verification Runtime Context — DI container for LSP pool and budget.
## Replaces global mutable state (leanLspClientPoolImpl) with explicit context.
import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/locks
import core/types/lean_lsp_types

type
  VerificationRuntimeContext* = object
    ## Immutable verification runtime environment.
    ## All engines receive this via dependency injection.
    lspPool*: LeanLspClientPool

func newVerificationRuntimeContext*(): VerificationRuntimeContext =
  ## Create a new runtime context with initialized lock.
  result = VerificationRuntimeContext(
    lspPool: LeanLspClientPool(activeClients: @[])
  )
  initLock(result.lspPool.gate)

{.pop.}
