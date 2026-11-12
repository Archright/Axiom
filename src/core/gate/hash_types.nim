import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Re-export facade — relocated to core/crypto/hash_kernel.
import core/crypto/hash_kernel
export hash_kernel
{.pop.}
