import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## real_git — Shared real git binary discovery (thin facade)
##
## Delegates to the SSOT in git_operations.nim.
## Retained for backward compatibility — all gate binaries can still
## import and call findRealGit() without changing their imports.

import core/interfaces/git_operations

proc findRealGit*(): string =
  ## Locates the real git binary, avoiding the wrapper itself.
  ## Delegates to git_operations.findRealGit().
  git_operations.findRealGit()

{.pop.}
