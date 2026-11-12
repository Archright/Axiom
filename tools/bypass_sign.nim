## bypass_sign.nim — Human Architect bypass signature generator
##
## Usage: bypass-sign <reason> <private-key-seed-path>
## Outputs: hex signature to stdout
##
## The human architect runs this with their PRIVATE KEY (never on agent machine).
## The output is set as AXIOM_BYPASS_SIGNATURE env var for bypass verification.
##
## Protocol:
##   1. Generate a seed: ed25519 seed() > my_seed.hex
##   2. Derive public key: store separately as AXIOM_BYPASS_PUBKEY file
##   3. Sign: bypass-sign "#EMERGENCY_FIX" my_seed.hex
##   4. Set env: AXIOM_BYPASS_SIGNATURE=<output> AXIOM_EMERGENCY_NO_VERIFY=1

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, times, osproc]
import ed25519

proc main() =
  if paramCount() < 2:
    stderr.writeLine "Usage: bypass-sign <reason> <private-key-seed-path>"
    stderr.writeLine ""
    stderr.writeLine "  reason               — bypass reason string (e.g. \"#EMERGENCY_FIX\")"
    stderr.writeLine "  private-key-seed-path — path to file containing hex-encoded 32-byte seed"
    quit(1)

  let reason = paramStr(1)
  let seedPath = paramStr(2)

  if not fileExists(seedPath):
    stderr.writeLine "Error: seed file not found: " & seedPath
    quit(1)

  let seedHex = readFile(seedPath).strip()
  if seedHex.len != 64:
    stderr.writeLine "Error: seed must be 64 hex characters (32 bytes), got " & $seedHex.len
    quit(1)

  # Parse hex seed to Seed type (array[32, byte])
  var seedBytes: Seed
  let rawSeed = parseHexStr(seedHex)
  if rawSeed.len != 32:
    stderr.writeLine "Error: decoded seed is " & $rawSeed.len & " bytes, expected 32"
    quit(1)
  for i in 0..<32:
    seedBytes[i] = byte(rawSeed[i])

  let kp = createKeypair(seedBytes)

  # Derive TOTP payload with tree hash
  let window = int64(toInt(epochTime())) div 600
  let treeHash = block:
    let (output, exitCode) = execCmdEx("git rev-parse HEAD^{tree}")
    if exitCode == 0: output.strip() else: ""
  let payload = $window & "|" & treeHash & "|" & reason

  let sig = sign(payload, kp)

  # Output hex signature to stdout
  for b in sig:
    stdout.write b.toHex(2)
  stdout.writeLine ""

  # informational stderr
  stderr.writeLine "Signed window=" & $window & " tree=" & treeHash & " reason=" & reason

when isMainModule:
  main()
