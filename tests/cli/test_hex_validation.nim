## Test: Hex validation guard (standalone)
## Validates that the isValidHex pattern correctly identifies valid/invalid hex strings.
##
## The isValidHex guard in src/gate/orchestrator_hook_part2_defs.nim rejects
## non-hex input BEFORE hashValueFromHex() — preventing silent corruption where
## invalid characters map to 0 and produce H_VOID collisions.
##
## This test inlines the validation logic for standalone verification,
## matching the production implementation exactly.

import std/strutils

# ── Inlined validation logic (matches production) ───────────────────────────
# Source: src/gate/orchestrator_hook_part2_defs.nim
# Kept in sync manually — any change to the production guard must be mirrored here.

func isValidHexChar(c: char): bool {.inline, raises: [].} =
  ## Returns true for [0-9a-fA-F].
  c in {'0'..'9', 'a'..'f', 'A'..'F'}

func isValidHex(s: string): bool {.inline, raises: [].} =
  ## Returns true for non-empty strings containing only hex characters.
  ## Rejects empty strings (would produce H_VOID via hashValueFromHex).
  if s.len == 0:
    return false
  for c in s:
    if not isValidHexChar(c):
      return false
  return true

# ── Valid hex strings ────────────────────────────────────────────────────────

block:
  # SHA-1 hex (40 chars) — typical git write-tree output
  doAssert isValidHex("a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"),
    "SHA-1 hex should be valid"

block:
  # Lowercase hex
  doAssert isValidHex("0123456789abcdef"),
    "lowercase hex should be valid"

block:
  # Uppercase hex
  doAssert isValidHex("0123456789ABCDEF"),
    "uppercase hex should be valid"

block:
  # All-zeros — valid hex, but note: hashValueFromHex("000...0") == H_VOID
  doAssert isValidHex("0000000000000000000000000000000000000000"),
    "all-zeros hex should be valid"

block:
  # Single zero
  doAssert isValidHex("0"),
    "single zero should be valid"

block:
  # SHA-256 hex (64 chars) — typical buildEnvHash input
  doAssert isValidHex("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
    "SHA-256 hex should be valid"

block:
  # Mixed case
  doAssert isValidHex("aAbBcCdD"),
    "mixed-case hex should be valid"

block:
  # All hex chars 0-f
  doAssert isValidHex("0123456789abcdef"),
    "full lowercase charset should be valid"

# ── Invalid hex strings ──────────────────────────────────────────────────────

block:
  # Empty string — the primary attack vector (produces H_VOID)
  doAssert not isValidHex(""),
    "empty string should be invalid"

block:
  # Non-hex uppercase chars
  doAssert not isValidHex("ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"),
    "non-hex chars should be invalid"

block:
  # Special characters
  doAssert not isValidHex("a1b2c3!@#"),
    "special chars should be invalid"

block:
  # Single non-hex char
  doAssert not isValidHex("g"),
    "single non-hex char 'g' should be invalid"

block:
  # Space in string
  doAssert not isValidHex("a1b2 c3d4"),
    "space should be invalid"

block:
  # Newline (from git output with bad strip)
  doAssert not isValidHex("a1b2c3d4\n"),
    "trailing newline should be invalid"

block:
  # Null byte embedded
  doAssert not isValidHex("a1b2c3d4\0e5f6"),
    "embedded null byte should be invalid"

# ── Edge cases ───────────────────────────────────────────────────────────────

block:
  # Single valid char
  doAssert isValidHex("f"),
    "single 'f' should be valid"

block:
  # Long hex string (> 64 chars, like SHA-512)
  let sha512 = "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"
  doAssert isValidHex(sha512),
    "SHA-512 hex (128 chars) should be valid"

block:
  # 39-char hex (not full SHA-1 length, but valid hex content)
  doAssert isValidHex("a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b"),
    "39-char valid hex should be valid (length is not the guard's concern)"

block:
  # 65-char hex (one over SHA-1)
  doAssert isValidHex("a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c"),
    "65-char valid hex should be valid (length is not the guard's concern)"

# ── Defense-in-depth: hashValueFromHex silent corruption ─────────────────────
# This block demonstrates WHY isValidHex is needed.
# hashValueFromHex("ZZZZ") silently produces H_VOID because 'Z' maps to 0.
# This means an attacker or corruption could produce a hash that collides
# with the null sentinel.

block:
  # Simulate what hashValueFromHex does with invalid input
  func hexValBad(c: char): uint8 {.raises: [].} =
    case c
    of '0'..'9': uint8(ord(c) - ord('0'))
    of 'a'..'f': uint8(ord(c) - ord('a') + 10)
    of 'A'..'F': uint8(ord(c) - ord('A') + 10)
    else: 0  # silent corruption: 'Z' maps to 0

  let badInput = "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"
  var val: uint8 = 0
  for c in badInput:
    val = val or hexValBad(c)
  # All chars mapped to 0, so val == 0
  doAssert val == 0,
    "non-hex input should map to 0 -- demonstrating the vulnerability"

echo "All hex validation tests passed."
