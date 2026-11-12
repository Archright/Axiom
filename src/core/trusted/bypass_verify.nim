import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## bypass_verify.nim — Ed25519+TOTP cryptographic bypass verification
##
## AXIOM_EMERGENCY_NO_VERIFY=1 alone is insufficient for bypass.
## A valid Ed25519 signature over a TOTP-based time window is required,
## ensuring only a human architect with the private key can authorize bypasses.
##
## Protocol:
##   1. Human architect runs `bypass-sign <reason> <seed-path>` on their machine.
##   2. Output hex signature is set via AXIOM_BYPASS_SIGNATURE env var.
##   3. Public key path is set via AXIOM_BYPASS_PUBKEY env var.
##   4. verifyBypassSignature checks signature against current AND previous TOTP window.

import core/interfaces/git_operations
import std/[strutils, times, os]
import ed25519

# ── Emergency Bypass Check ────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc isEmergencyBypass*(): bool {.raises: [].} =
  ## Check if AXIOM_EMERGENCY_NO_VERIFY=1 environment variable is set.
  ## Returns true only if the value is "1" or "true" (case-insensitive).
  ## Returns false on any error (Fail-Closed principle).
  try:
    let val = getEnv("AXIOM_EMERGENCY_NO_VERIFY", "0").strip().toLowerAscii()
    return val == "1" or val == "true"
  except CatchableError:
    return false

const
  TOTPWindowSeconds* = 600  ## 10 minutes per TOTP window

# ── Hex Conversion ────────────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func hexNibble(c: char): byte {.raises: [].} =
  ## Convert a single hex character to its 4-bit value.
  case c
  of '0'..'9': byte(ord(c) - ord('0'))
  of 'a'..'f': byte(ord(c) - ord('a') + 10)
  of 'A'..'F': byte(ord(c) - ord('A') + 10)
  else: 0  # invalid char → 0 (verification will fail anyway)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func hexToByteArray(hex: string, targetLen: static int): array[targetLen, byte] {.raises: [].} =
  ## Convert a hex string to a fixed-size byte array.
  ## Pure func — no exceptions, no side effects.
  ## Invalid hex characters decode to 0x00 (safe default).
  let byteLen = min(targetLen, hex.len div 2)
  for i in 0..<byteLen:
    result[i] = (hexNibble(hex[i * 2]) shl 4) or hexNibble(hex[i * 2 + 1])

# ── TOTP Window ───────────────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc currentTimeWindow*(): int64 {.raises: [].} =
  ## Current TOTP window = epoch div 600
  try:
    result = int64(toInt(epochTime())) div TOTPWindowSeconds
  except CatchableError:
    result = 0

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc previousWindow*(): int64 {.raises: [].} =
  ## Previous TOTP window (boundary-condition replay guard)
  result = currentTimeWindow() - 1

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getTreeHash*(): string {.raises: [].} =
  ## Get current git tree hash. Returns empty string on failure.
  try:
    let (output, exitCode) = git_operations.runGit("rev-parse HEAD^{tree}")
    if exitCode == 0:
      result = output.strip()
    else:
      result = ""
  except CatchableError:
    result = ""

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func formatWindow(window: int64, treeHash, reason: string): string =
  ## Canonical payload: "{window}|{tree_hash}|{reason}"
  result = $window & "|" & treeHash & "|" & reason

# ── Verification ──────────────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc verifyBypassSignature*(reason, signatureHex, publicKeyHex: string): bool {.raises: [].} =
  ## Verify Ed25519 signature against current AND previous TOTP window.
  ## Two-window check prevents boundary-condition replay attacks.
  ##
  ## Parameters:
  ##   reason         — bypass reason string (must match signing-time reason)
  ##   signatureHex   — 128-char hex string (64-byte Ed25519 signature)
  ##   publicKeyHex   — 64-char hex string (32-byte Ed25519 public key)
  ##
  ## Returns true ONLY if signature is valid for current or previous window.
  try:
    if signatureHex.len != 128 or publicKeyHex.len != 64:
      return false

    let sigBytes = hexToByteArray(signatureHex, 64)
    let pubBytes = hexToByteArray(publicKeyHex, 32)
    let treeHash = getTreeHash()

    # Window 1: current
    let payload1 = formatWindow(currentTimeWindow(), treeHash, reason)
    if verify(payload1, sigBytes, pubBytes):
      return true

    # Window 2: previous (boundary guard)
    let payload2 = formatWindow(previousWindow(), treeHash, reason)
    if verify(payload2, sigBytes, pubBytes):
      return true

    return false
  except CatchableError:
    return false
