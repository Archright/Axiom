import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Hash Kernel — Single Source of Truth for all hashing operations
## All computeHash/computeContentHash/sha256Hex/HashValue implementations
## must use this module.
## Duplicate hash implementations are forbidden by axiomHashConsolidation macro.

import checksums/sha2
import core/crypto/hash_consolidation

# ─── HashValue Type ──────────────────────────────────────────────────────
# Fixed-size 256-bit hash (4 × uint64). Used for content hashing, Merkle
# roots, and cache keys.

type
  HashValue* = object
    data*: array[4, uint64]

const
  H_VOID* = HashValue(data: [0'u64, 0, 0, 0])

func `==`*(a, b: HashValue): bool {.inline.} =
  a.data[0] == b.data[0] and a.data[1] == b.data[1] and
  a.data[2] == b.data[2] and a.data[3] == b.data[3]

func isVoid*(h: HashValue): bool {.inline.} =
  h == H_VOID

# ─── SHA-256 Based Hash Functions ───────────────────────────────────────
# SHA-256 is identical on Linux/macOS/Windows.

func stableHash32*(s: openArray[char]): uint32 {.inline.} =
  var ctx = initSha(Sha_256)
  ctx.update(s)
  var digest: ShaDigest_256
  discard ctx.digest(digest)
  result = uint32(digest[0].byte) shl 24 or
           uint32(digest[1].byte) shl 16 or
           uint32(digest[2].byte) shl 8 or
           uint32(digest[3].byte)

axiomHashConsolidation:
  when nimvm:
    proc vmSafeSha256Hex(data: string): string =
      result = $secureHash(Sha_256, data)

  func computeContentHash*(content: string): string =
    when nimvm:
      result = vmSafeSha256Hex(content)
    else:
      result = $secureHash(Sha_256, content)

  func computeHash*(content: string): string =
    result = computeContentHash(content)

  func sha256Hex*(data: string): string =
    when nimvm:
      result = vmSafeSha256Hex(data)
    else:
      result = $secureHash(Sha_256, data)

# ─── Hex Conversion Helpers ─────────────────────────────────────────────
# Convert between HashValue (binary 32-byte) and hex string (64-char).
# Used by State Ledger to bridge SHA-256 hex strings from workspace_receipt
# to the fixed-size HashValue binary format.

func hashValueFromHex*(hex: string): HashValue {.inline, raises: [].} =
  func hexVal(c: char): uint8 {.inline, raises: [].} =
    case c
    of '0'..'9': result = uint8(ord(c) - ord('0'))
    of 'a'..'f': result = uint8(ord(c) - ord('a') + 10)
    of 'A'..'F': result = uint8(ord(c) - ord('A') + 10)
    else: result = 0
  for i in 0..3:
    var val: uint64 = 0
    for j in 0..15:
      let idx = i * 16 + j
      if idx < hex.len:
        val = (val shl 4) or uint64(hexVal(hex[idx]))
      else:
        val = val shl 4
    result.data[i] = val

func hashValueToHex*(h: HashValue): string {.inline, raises: [].} =
  const hexChars = "0123456789abcdef"
  result = newString(64)
  for i in 0..3:
    var val = h.data[i]
    for j in countdown(15, 0):
      result[i * 16 + j] = hexChars[int(val and 0xF)]
      val = val shr 4

func sha1HexToBytes*(hex: string): array[20, byte] {.inline, raises: [].} =
  func hexVal(c: char): byte {.inline, raises: [].} =
    case c
    of '0'..'9': result = byte(ord(c) - ord('0'))
    of 'a'..'f': result = byte(ord(c) - ord('a') + 10)
    of 'A'..'F': result = byte(ord(c) - ord('A') + 10)
    else: result = 0.byte
  for i in 0 ..< 20:
    let idx = i * 2
    if idx + 1 < hex.len:
      result[i] = (hexVal(hex[idx]) shl 4) or hexVal(hex[idx + 1])

{.pop.}
