## ratchet_sign.nim — Pinned-key downgrade approval signer for the coverage
## ratchet (Audited Ratchet Authority Closure, DEBT#495).
##
## Sign mode: the offline key holder signs the canonical ratchet payload
##   "{tree_hash}|{old_baseline}|{new_baseline}|{reason}|{expires_at}|{jti}"
## and prints the AXIOM_RATCHET_APPROVAL JSON document. The private seed is
## held offline for audit and is never committed.
## Verify mode: offline provenance reconstruction from git history —
##   ratchet-sign --verify --payload <text> --signature <128hex>
## exits 0 iff the signature verifies under the pinned authority key.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, osproc, json]
import ed25519
import core/trusted/ratchet_authority

proc currentTreeHash(): string =
  let (output, exitCode) = execCmdEx("git rev-parse HEAD^{tree}")
  if exitCode == 0: output.strip() else: ""

proc fail(msg: string) =
  stderr.writeLine "ratchet-sign: " & msg
  quit(1)

proc main() =
  var reason, oldPctS, newPctS, expiresAt, jti, seedPath = ""
  var verifyMode = false
  var payload, signature = ""
  var i = 1
  while i <= paramCount():
    case paramStr(i)
    of "--reason": reason = paramStr(i + 1); inc i
    of "--old-baseline": oldPctS = paramStr(i + 1); inc i
    of "--new-baseline": newPctS = paramStr(i + 1); inc i
    of "--expires-at": expiresAt = paramStr(i + 1); inc i
    of "--jti": jti = paramStr(i + 1); inc i
    of "--seed": seedPath = paramStr(i + 1); inc i
    of "--verify": verifyMode = true
    of "--payload": payload = paramStr(i + 1); inc i
    of "--signature": signature = paramStr(i + 1); inc i
    else: fail "unknown argument: " & paramStr(i)
    inc i

  if verifyMode:
    if payload.len == 0 or signature.len == 0:
      fail "usage: ratchet-sign --verify --payload <text> --signature <128hex>"
    if verifyRatchetDowngradeSignature(payload, signature):
      stdout.writeLine "{\"valid\":true,\"keyid\":\"" & RatchetAuthorityKeyId & "\"}"
      quit(0)
    quit(1)

  if reason.len == 0 or oldPctS.len == 0 or newPctS.len == 0 or
     expiresAt.len == 0 or jti.len == 0 or seedPath.len == 0:
    stderr.writeLine "Usage: ratchet-sign --reason <text> --old-baseline <pct> --new-baseline <pct> --expires-at <ISO8601Z> --jti <id> --seed <seedfile>"
    stderr.writeLine "       ratchet-sign --verify --payload <text> --signature <128hex>"
    quit(1)

  if not fileExists(seedPath):
    fail "seed file not found: " & seedPath
  let seedHex = readFile(seedPath).strip()
  if seedHex.len != 64:
    fail "seed must be 64 hex characters (32 bytes), got " & $seedHex.len
  var seedBytes: Seed
  let raw = parseHexStr(seedHex)
  if raw.len != 32:
    fail "decoded seed is " & $raw.len & " bytes, expected 32"
  for k in 0..<32:
    seedBytes[k] = byte(raw[k])
  let kp = createKeypair(seedBytes)

  var oldPct, newPct: float
  try:
    oldPct = parseFloat(oldPctS)
    newPct = parseFloat(newPctS)
  except CatchableError:
    fail "baseline percentages must be numeric"
  if newPct >= oldPct:
    fail "refusing to sign: new baseline must be LOWER than old (downgrades only)"

  let treeHash = currentTreeHash()
  let payloadStr = formatRatchetPayload(treeHash, oldPct, newPct, reason,
                                        expiresAt, jti)
  let sig = sign(payloadStr, kp)
  var sigHex = ""
  for b in sig:
    sigHex.add b.toHex(2)

  let approval = %*{
    "payload": payloadStr,
    "signature": sigHex,
    "jti": jti,
    "expires_at": expiresAt,
    "keyid": RatchetAuthorityKeyId
  }
  stdout.writeLine $approval
  stderr.writeLine "ratchet-sign: signed tree=" & treeHash &
      " keyid=" & RatchetAuthorityKeyId & " jti=" & jti

when isMainModule:
  main()
