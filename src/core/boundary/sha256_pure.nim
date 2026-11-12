import core/trusted/layer_declaration
axiomLayer "domain"
import ../../../tools/sha256_native
import core/crypto/hash_kernel
func sha256String*(data: string): string {.raises: [].} =
  ## Compute SHA-256 hex digest of input string.
  ## Pure Nim implementation via checksums/sha2 library.
  result = hash_kernel.sha256Hex(data)
export sha256_native
