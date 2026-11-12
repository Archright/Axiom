import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Pure Universe Lock Types
## Extracted from proof_universe_lock.nim to prevent Domain→Infrastructure
## reverse references during module relocation.

const AuthorizedLockCaller* = "ax_prove_core"

type
  ProofUniverseLock* = object
    merkleRoot*: string
    timestamp*: string
    fileCount*: int
    vkdFixed4*: string

{.pop.}

{.pop.}
