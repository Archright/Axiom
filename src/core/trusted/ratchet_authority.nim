import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## ratchet_authority.nim — Pinned-key Ed25519 authority for the coverage
## ratchet baseline downgrade (Audited Ratchet Authority Closure).
##
## Authority model (docs/spec/environment_inputs.md, DEBT#495):
##   - AXIOM_RATCHET_DOWNGRADE / AXIOM_RATCHET_REASON are REQUEST signals only;
##     they carry no authority.
##   - The sole authority to lower data/reliability_score.json is an Ed25519
##     signature over the canonical ratchet payload, made by the pinned key
##     below. The private half of this keypair is held offline for audit and
##     is never committed.
##   - Ratchet payload contract (deliberately separate from the break-glass
##     formatWindow contract in bypass_verify.nim, which stays untouched):
##       "{tree_hash}|{old_baseline}|{new_baseline}|{reason}|{expires_at}|{jti}"
##     tree_hash binds the approval to one exact tree; expires_at bounds its
##     lifetime (UTC ISO 8601); jti makes each approval single-use.

import ed25519
import core/crypto/hash_kernel

const
  RatchetAuthorityPubKeyHex* = "F668B92BFE66D44E0325E0DBF5992EC167E2868EF9F64BB01CAE635933EC8770"
    ## Sole pinned downgrade-authority public key (Ed25519, 32 bytes, hex).
  RatchetAuthorityKeyId* = "e6ccd0895af2b964"
    ## key id = sha256(RatchetAuthorityPubKeyHex)[0..15]; recorded in every
    ## in-band downgrade_history record so key rotation stays auditable.
  RatchetPayloadFieldSep* = "|"

func formatRatchetFloat*(pct: float): string =
  ## Canonical decimal rendering shared verbatim by signer and verifier.
  result = $pct

func formatRatchetPayload*(treeHash: string; oldBaselinePct, newBaselinePct: float;
                           reason, expiresAtIso, jti: string): string =
  ## Canonical approval payload — the exact byte string the authority signs.
  result = treeHash & RatchetPayloadFieldSep &
           formatRatchetFloat(oldBaselinePct) & RatchetPayloadFieldSep &
           formatRatchetFloat(newBaselinePct) & RatchetPayloadFieldSep &
           reason & RatchetPayloadFieldSep &
           expiresAtIso & RatchetPayloadFieldSep & jti

func hexNibble(c: char): byte =
  case c
  of '0'..'9': byte(ord(c) - ord('0'))
  of 'a'..'f': byte(ord(c) - ord('a') + 10)
  of 'A'..'F': byte(ord(c) - ord('A') + 10)
  else: 0  # invalid char → 0 (verification fails on such input anyway)

func hexToByteArray(hex: string; targetLen: static int): array[targetLen, byte] =
  let byteLen = min(targetLen, hex.len div 2)
  for i in 0..<byteLen:
    result[i] = (hexNibble(hex[i * 2]) shl 4) or hexNibble(hex[i * 2 + 1])

func verifyRatchetDowngradeSignature*(payload, signatureHex: string): bool {.raises: [].} =
  ## Fail-closed Ed25519 verification against the PINNED authority key only.
  ## No caller-supplied key material exists by construction — pinning is what
  ## makes a self-generated keypair worthless as authority.
  if signatureHex.len != 128:
    return false
  try:
    let sigBytes = hexToByteArray(signatureHex, 64)
    let pubBytes = hexToByteArray(RatchetAuthorityPubKeyHex, 32)
    result = ed25519.verify(payload, sigBytes, pubBytes)
  except CatchableError:
    return false

func ratchetRecordHash*(prevRecordHash, jti, signatureHex, timestampIso: string;
                        granted: bool): string {.raises: [].} =
  ## Hash-chain link for in-band downgrade_history records; the chain head is
  ## persisted next to the history so removal/reordering is detectable.
  let grantedStr = if granted: "granted" else: "refused"
  result = sha256Hex(prevRecordHash & "|" & grantedStr & "|" & jti & "|" &
                     signatureHex & "|" & timestampIso)
