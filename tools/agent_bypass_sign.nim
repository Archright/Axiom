## agent_bypass_sign.nim — Ephemeral Ed25519 bypass signer for AI agents
##
## Generates a one-time Ed25519 keypair, signs the TOTP-based bypass payload,
## and outputs AXIOM_BYPASS_PUBKEY + AXIOM_BYPASS_SIGNATURE env vars.
##
## Usage: agent-bypass-sign [reason]
## Output (stderr): KEY=VALUE lines for eval
##
## Security model: cryptographic audit trail, not access control.
## Every bypass is logged with the ephemeral public key for post-hoc audit.
##
## Protocol:
##   1. Generate ephemeral 32-byte seed via CSPRNG
##   2. Derive Ed25519 keypair from seed
##   3. Sign TOTP payload: "{window}|{tree_hash}|{reason}"
##   4. Output pubkey + signature as hex env vars to stderr

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, times, osproc]
import ed25519
import nimcrypto/sysrand

proc main() =
  let reason = if paramCount() > 0: paramStr(1) else: "agent-emergency"

  # Generate ephemeral seed (32 bytes CSPRNG)
  var seed: Seed
  let generated = randomBytes(addr seed[0], 32)
  if generated != 32:
    stderr.writeLine("Error: CSPRNG insufficient entropy")
    quit(1)

  let kp = createKeypair(seed)

  # TOTP payload: window|tree_hash|reason
  let window = int64(toInt(epochTime())) div 600
  let treeHash = block:
    let (output, exitCode) = execCmdEx("git rev-parse HEAD^{tree}")
    if exitCode == 0:
      output.strip()
    else:
      stderr.writeLine("FATAL: git rev-parse HEAD^{tree} failed (exit=" & $exitCode & ")")
      quit(1)
  let payload = $window & "|" & treeHash & "|" & reason

  let sig = sign(payload, kp)

  # Output public key hex
  var pubHex = ""
  for b in kp.publicKey:
    pubHex &= b.toHex(2)

  # Output signature hex
  var sigHex = ""
  for b in sig:
    sigHex &= b.toHex(2)

  # Stderr output for agent eval
  stderr.writeLine("AXIOM_BYPASS_PUBKEY=" & pubHex)
  stderr.writeLine("AXIOM_BYPASS_SIGNATURE=" & sigHex)
  stderr.writeLine("AXIOM_BYPASS_REASON=" & reason)
  stderr.writeLine("AXIOM_BYPASS_WINDOW=" & $window)

when isMainModule:
  main()
