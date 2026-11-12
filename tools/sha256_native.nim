## sha256_native.nim — Pure Nim SHA-256 implementation (RFC 6234)
##
## Self-contained with ZERO external dependencies.
## Used by hermetic_build.nim for build_env content hashing.
##
## Compile-time constants: initial hash values and round constants.
## All computation procs use {.raises: [].} (pure computation, no exceptions).

import core/trusted/layer_declaration
axiomLayer "tools"
const
  # SHA-256 initial hash values (FIPS 180-4 §5.3.3)
  sha256InitialHash* = [
    0x6a09e667'u32, 0xbb67ae85'u32, 0x3c6ef372'u32, 0xa54ff53a'u32,
    0x510e527f'u32, 0x9b05688c'u32, 0x1f83d9ab'u32, 0x5be0cd19'u32
  ]

  # SHA-256 round constants K[0..63] (FIPS 180-4 §4.2.2)
  sha256RoundConstants* = [
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

# ── Bitwise helpers (32-bit) ──

func rotr32(x: uint32, n: int): uint32 {.raises: [].} =
  ## 32-bit right rotation
  (x shr n) or (x shl (32 - n))

func ch(x, y, z: uint32): uint32 {.raises: [].} =
  ## Choice: if x then y else z
  (x and y) xor ((not x) and z)

func maj(x, y, z: uint32): uint32 {.raises: [].} =
  ## Majority function
  (x and y) xor (x and z) xor (y and z)

func bsig0(x: uint32): uint32 {.raises: [].} =
  ## Σ0 (Big Sigma 0): ROTR²(x) ⊕ ROTR¹³(x) ⊕ ROTR²²(x)
  rotr32(x, 2) xor rotr32(x, 13) xor rotr32(x, 22)

func bsig1(x: uint32): uint32 {.raises: [].} =
  ## Σ1 (Big Sigma 1): ROTR⁶(x) ⊕ ROTR¹¹(x) ⊕ ROTR²⁵(x)
  rotr32(x, 6) xor rotr32(x, 11) xor rotr32(x, 25)

func ssig0(x: uint32): uint32 {.raises: [].} =
  ## σ0 (Small Sigma 0): ROTR⁷(x) ⊕ ROTR¹⁸(x) ⊕ SHR³(x)
  rotr32(x, 7) xor rotr32(x, 18) xor (x shr 3)

func ssig1(x: uint32): uint32 {.raises: [].} =
  ## σ1 (Small Sigma 1): ROTR¹⁷(x) ⊕ ROTR¹⁹(x) ⊕ SHR¹⁰(x)
  rotr32(x, 17) xor rotr32(x, 19) xor (x shr 10)

# ── SHA-256 Core Compression ──

func processBlock(state: var array[8, uint32], blk: array[64, byte]) {.raises: [].} =
  ## Process a single 64-byte block through the SHA-256 compression function.
  var w: array[64, uint32]

  # Prepare message schedule W[0..63]
  for t in 0 ..< 16:
    w[t] = (blk[t * 4].uint32 shl 24) or
           (blk[t * 4 + 1].uint32 shl 16) or
           (blk[t * 4 + 2].uint32 shl 8) or
           blk[t * 4 + 3].uint32

  for t in 16 ..< 64:
    w[t] = ssig1(w[t - 2]) + w[t - 7] + ssig0(w[t - 15]) + w[t - 16]

  # Initialize working variables
  var a, b, c, d, e, f, g, h: uint32
  a = state[0]
  b = state[1]
  c = state[2]
  d = state[3]
  e = state[4]
  f = state[5]
  g = state[6]
  h = state[7]

  # 64 rounds of compression
  for t in 0 ..< 64:
    let t1 = h + bsig1(e) + ch(e, f, g) + sha256RoundConstants[t] + w[t]
    let t2 = bsig0(a) + maj(a, b, c)
    h = g
    g = f
    f = e
    e = d + t1
    d = c
    c = b
    b = a
    a = t1 + t2

  # Add compressed chunk to current hash value
  state[0] += a
  state[1] += b
  state[2] += c
  state[3] += d
  state[4] += e
  state[5] += f
  state[6] += g
  state[7] += h

# ── Public API ──

proc sha256*(data: openArray[byte]): string {.raises: [].} =
  ## Compute SHA-256 digest of raw bytes. Returns 64-char hex string.
  var state = sha256InitialHash

  # Determine total message length in bits
  let msgLen = data.len
  let msgLenBits = msgLen.uint64 * 8

  # Process each 64-byte block
  var pos = 0
  while pos + 64 <= msgLen:
    var blk: array[64, byte]
    for i in 0 ..< 64:
      blk[i] = data[pos + i]
    processBlock(state, blk)
    pos += 64

  # Pad the message (FIPS 180-4 §5.1.1)
  # Remaining bytes: msgLen mod 64
  let remaining = msgLen - pos

  # Build padded message
  # Pad length: remaining + 1 (0x80 byte) + padding zeros + 8 (bit length)
  # Total padded length must be multiple of 64
  var padLen = remaining + 1
  while (padLen + 8) mod 64 != 0:
    inc padLen
  padLen += 8  # Add 8 bytes for the length

  var padded = newSeq[byte](padLen)
  for i in 0 ..< remaining:
    padded[i] = data[pos + i]
  padded[remaining] = 0x80  # Append '1' bit

  # Append original message length as big-endian 64-bit integer
  padded[padLen - 8] = byte(msgLenBits shr 56)
  padded[padLen - 7] = byte(msgLenBits shr 48)
  padded[padLen - 6] = byte(msgLenBits shr 40)
  padded[padLen - 5] = byte(msgLenBits shr 32)
  padded[padLen - 4] = byte(msgLenBits shr 24)
  padded[padLen - 3] = byte(msgLenBits shr 16)
  padded[padLen - 2] = byte(msgLenBits shr 8)
  padded[padLen - 1] = byte(msgLenBits)

  # Process remaining padded blocks
  pos = 0
  while pos < padLen:
    var blk: array[64, byte]
    for i in 0 ..< 64:
      blk[i] = padded[pos + i]
    processBlock(state, blk)
    pos += 64

  # Produce the final digest (big-endian 32-bit words → hex)
  const hexChars = "0123456789abcdef"
  result = newString(64)
  var idx = 0
  for i in 0 ..< 8:
    let word = state[i]
    result[idx]     = hexChars[int((word shr 28) and 0xf)]
    result[idx + 1] = hexChars[int((word shr 24) and 0xf)]
    result[idx + 2] = hexChars[int((word shr 20) and 0xf)]
    result[idx + 3] = hexChars[int((word shr 16) and 0xf)]
    result[idx + 4] = hexChars[int((word shr 12) and 0xf)]
    result[idx + 5] = hexChars[int((word shr 8) and 0xf)]
    result[idx + 6] = hexChars[int((word shr 4) and 0xf)]
    result[idx + 7] = hexChars[int(word and 0xf)]
    idx += 8

proc sha256String*(data: string): string {.raises: [].} =
  ## Compute SHA-256 of a string. Returns 64-char hex digest.
  var bytes: seq[byte] = newSeq[byte](data.len)
  for i in 0 ..< data.len:
    bytes[i] = byte(data[i])
  sha256(bytes)

proc sha256File*(path: string): string =
  ## Read a file and return its SHA-256 hex digest.
  ## Returns "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  ## for empty files.
  let content = readFile(path)
  sha256String(content)

# ── Quick self-test ──
when isMainModule:
  # Test vectors from FIPS 180-4 and RFC 6234
  block:
    let empty = sha256String("")
    doAssert empty == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "Empty string test failed: " & empty

  block:
    let abc = sha256String("abc")
    doAssert abc == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      "abc test failed: " & abc

  block:
    let abcd256 = sha256String("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
    doAssert abcd256 == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
      "abcdbc... test failed: " & abcd256

  echo "sha256_native: all self-tests passed"
