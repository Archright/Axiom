import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Hash Kernel — Single Source of Truth for all hashing operations
## All computeHash/computeContentHash/sha256Hex/HashValue implementations
## must use this module.
## Duplicate hash implementations are forbidden by axiomHashConsolidation macro.

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
#
# Self-contained by contract: the trusted-checker preflight compiles the
# checker tree with --skipProjCfg --skipParentCfg (no nimble package paths),
# so the hash kernel must not import the external `checksums` package.
# FIPS 180-4 / RFC 6234; digest bytes are identical to checksums/sha2.

const
  sha256InitialHash = [
    0x6a09e667'u32, 0xbb67ae85'u32, 0x3c6ef372'u32, 0xa54ff53a'u32,
    0x510e527f'u32, 0x9b05688c'u32, 0x1f83d9ab'u32, 0x5be0cd19'u32
  ]
  sha256RoundConstants = [
    0x428a2f98'u32, 0x71374491'u32, 0xb5c0fbcf'u32, 0xe9b5dba5'u32,
    0x3956c25b'u32, 0x59f111f1'u32, 0x923f82a4'u32, 0xab1c5ed5'u32,
    0xd807aa98'u32, 0x12835b01'u32, 0x243185be'u32, 0x550c7dc3'u32,
    0x72be5d74'u32, 0x80deb1fe'u32, 0x9bdc06a7'u32, 0xc19bf174'u32,
    0xe49b69c1'u32, 0xefbe4786'u32, 0x0fc19dc6'u32, 0x240ca1cc'u32,
    0x2de92c6f'u32, 0x4a7484aa'u32, 0x5cb0a9dc'u32, 0x76f988da'u32,
    0x983e5152'u32, 0xa831c66d'u32, 0xb00327c8'u32, 0xbf597fc7'u32,
    0xc6e00bf3'u32, 0xd5a79147'u32, 0x06ca6351'u32, 0x14292967'u32,
    0x27b70a85'u32, 0x2e1b2138'u32, 0x4d2c6dfc'u32, 0x53380d13'u32,
    0x650a7354'u32, 0x766a0abb'u32, 0x81c2c92e'u32, 0x92722c85'u32,
    0xa2bfe8a1'u32, 0xa81a664b'u32, 0xc24b8b70'u32, 0xc76c51a3'u32,
    0xd192e819'u32, 0xd6990624'u32, 0xf40e3585'u32, 0x106aa070'u32,
    0x19a4c116'u32, 0x1e376c08'u32, 0x2748774c'u32, 0x34b0bcb5'u32,
    0x391c0cb3'u32, 0x4ed8aa4a'u32, 0x5b9cca4f'u32, 0x682e6ff3'u32,
    0x748f82ee'u32, 0x78a5636f'u32, 0x84c87814'u32, 0x8cc70208'u32,
    0x90befffa'u32, 0xa4506ceb'u32, 0xbef9a3f7'u32, 0xc67178f2'u32
  ]

func rotr32(x: uint32, n: int): uint32 {.inline.} =
  (x shr n) or (x shl (32 - n))

func ch32(x, y, z: uint32): uint32 {.inline.} =
  (x and y) xor ((not x) and z)

func maj32(x, y, z: uint32): uint32 {.inline.} =
  (x and y) xor (x and z) xor (y and z)

func bsig0(x: uint32): uint32 {.inline.} =
  rotr32(x, 2) xor rotr32(x, 13) xor rotr32(x, 22)

func bsig1(x: uint32): uint32 {.inline.} =
  rotr32(x, 6) xor rotr32(x, 11) xor rotr32(x, 25)

func ssig0(x: uint32): uint32 {.inline.} =
  rotr32(x, 7) xor rotr32(x, 18) xor (x shr 3)

func ssig1(x: uint32): uint32 {.inline.} =
  rotr32(x, 17) xor rotr32(x, 19) xor (x shr 10)

func sha256Compress(state: var array[8, uint32]; blk: array[64, byte]) =
  var w: array[64, uint32]
  for t in 0 ..< 16:
    w[t] = (uint32(blk[t * 4]) shl 24) or
           (uint32(blk[t * 4 + 1]) shl 16) or
           (uint32(blk[t * 4 + 2]) shl 8) or
           uint32(blk[t * 4 + 3])
  for t in 16 ..< 64:
    w[t] = ssig1(w[t - 2]) + w[t - 7] + ssig0(w[t - 15]) + w[t - 16]

  var a, b, c, d, e, f, g, h: uint32
  a = state[0]
  b = state[1]
  c = state[2]
  d = state[3]
  e = state[4]
  f = state[5]
  g = state[6]
  h = state[7]

  for t in 0 ..< 64:
    let t1 = h + bsig1(e) + ch32(e, f, g) + sha256RoundConstants[t] + w[t]
    let t2 = bsig0(a) + maj32(a, b, c)
    h = g
    g = f
    f = e
    e = d + t1
    d = c
    c = b
    b = a
    a = t1 + t2

  state[0] += a
  state[1] += b
  state[2] += c
  state[3] += d
  state[4] += e
  state[5] += f
  state[6] += g
  state[7] += h

func sha256DigestHex(data: openArray[char]): string =
  var state = sha256InitialHash
  let msgLen = data.len
  let msgLenBits = uint64(msgLen) * 8

  var pos = 0
  while pos + 64 <= msgLen:
    var blk: array[64, byte]
    for i in 0 ..< 64:
      blk[i] = byte(data[pos + i])
    sha256Compress(state, blk)
    pos += 64

  let remaining = msgLen - pos
  var padLen = remaining + 1
  while (padLen + 8) mod 64 != 0:
    inc padLen
  padLen += 8

  var padded = newSeq[byte](padLen)
  for i in 0 ..< remaining:
    padded[i] = byte(data[pos + i])
  padded[remaining] = 0x80
  padded[padLen - 8] = byte(msgLenBits shr 56)
  padded[padLen - 7] = byte(msgLenBits shr 48)
  padded[padLen - 6] = byte(msgLenBits shr 40)
  padded[padLen - 5] = byte(msgLenBits shr 32)
  padded[padLen - 4] = byte(msgLenBits shr 24)
  padded[padLen - 3] = byte(msgLenBits shr 16)
  padded[padLen - 2] = byte(msgLenBits shr 8)
  padded[padLen - 1] = byte(msgLenBits)

  pos = 0
  while pos < padLen:
    var blk: array[64, byte]
    for i in 0 ..< 64:
      blk[i] = padded[pos + i]
    sha256Compress(state, blk)
    pos += 64

  const hexChars = "0123456789abcdef"
  result = newString(64)
  var idx = 0
  for i in 0 ..< 8:
    let word = state[i]
    result[idx] = hexChars[int((word shr 28) and 0xf)]
    result[idx + 1] = hexChars[int((word shr 24) and 0xf)]
    result[idx + 2] = hexChars[int((word shr 20) and 0xf)]
    result[idx + 3] = hexChars[int((word shr 16) and 0xf)]
    result[idx + 4] = hexChars[int((word shr 12) and 0xf)]
    result[idx + 5] = hexChars[int((word shr 8) and 0xf)]
    result[idx + 6] = hexChars[int((word shr 4) and 0xf)]
    result[idx + 7] = hexChars[int(word and 0xf)]
    idx += 8

func hexNibble(c: char): uint32 {.inline.} =
  case c
  of '0'..'9': uint32(ord(c) - ord('0'))
  of 'a'..'f': uint32(ord(c) - ord('a') + 10)
  else: 0'u32

func stableHash32*(s: openArray[char]): uint32 {.inline.} =
  ## First 32 digest bits (big-endian) — the pre-existing byte contract.
  let digest = sha256DigestHex(s)
  result = 0'u32
  for i in 0 ..< 8:
    result = (result shl 4) or hexNibble(digest[i])

axiomHashConsolidation:
  func computeContentHash*(content: string): string =
    result = sha256DigestHex(content)

  func computeHash*(content: string): string =
    result = computeContentHash(content)

  func sha256Hex*(data: string): string =
    result = sha256DigestHex(data)

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
