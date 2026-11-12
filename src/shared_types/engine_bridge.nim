## Engine Layer Bridge — Thin Interface for tools/
## Re-exports atomic file operations needed by tools/.
import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}
import engine/atomic_ops
export atomic_ops.atomicWrite
{.pop.}