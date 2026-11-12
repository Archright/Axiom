import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

## git_ops — Shared real git binary discovery (thin facade)
##
## Delegates to git_operations.nim (SSOT).
## Retained for backward compatibility.

import core/interfaces/git_operations

proc findRealGit*(): string =
  git_operations.findRealGit()

{.pop.}
