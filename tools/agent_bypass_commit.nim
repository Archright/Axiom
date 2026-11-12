## agent_bypass_commit.nim — Single-command bypass: sign + git commit
##
## Automates the full emergency bypass workflow:
##   1. Generate ephemeral Ed25519 keypair (CSPRNG)
##   2. Sign TOTP payload: "{window}|{tree_hash}|{reason}"
##   3. Execute git commit with AXIOM_EMERGENCY_NO_VERIFY env vars injected
##
## Usage:
##   bin/agent-bypass-commit --reason "emergency fix" --message "fix: something"
##   bin/agent-bypass-commit --message "fix: something"  (reason defaults to "agent-emergency")
##
## Security model: cryptographic audit trail, not access control.
## Every bypass is logged with the ephemeral public key for post-hoc audit.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, times, osproc]
import ed25519
import nimcrypto/sysrand

proc jsonEscape(s: string): string =
  ## Escape a string for safe embedding in JSON values.
  result = newStringOfCap(s.len + 10)
  result.add('"')
  for c in s:
    case c
    of '"': result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else:
      if ord(c) < 0x20:
        result.add("\\u" & toHex(ord(c), 4))
      else:
        result.add(c)
  result.add('"')

proc parseArgs(): (string, string) =
  ## Parse --reason and --message from CLI args.
  ## Returns (reason, message). message is required.
  var reason = "agent-emergency"
  var message = ""
  var i = 1
  while i <= paramCount():
    let arg = paramStr(i)
    if arg == "--reason" and i < paramCount():
      reason = paramStr(i + 1)
      inc i
    elif arg == "--message" and i < paramCount():
      message = paramStr(i + 1)
      inc i
    elif arg == "--help" or arg == "-h":
      stderr.writeLine("Usage: agent-bypass-commit --reason <string> --message <string>")
      stderr.writeLine("")
      stderr.writeLine("  --reason <string>   Bypass reason (default: \"agent-emergency\")")
      stderr.writeLine("  --message <string>  Git commit message (required)")
      stderr.writeLine("")
      stderr.writeLine("Generates ephemeral Ed25519 keypair, signs TOTP bypass payload,")
      stderr.writeLine("and executes git commit with AXIOM_EMERGENCY_NO_VERIFY env vars.")
      quit(0)
    else:
      stderr.writeLine("Unknown argument: " & arg)
      stderr.writeLine("Use --help for usage.")
      quit(1)
    inc i

  if message.len == 0:
    stderr.writeLine("Error: --message is required.")
    stderr.writeLine("Usage: agent-bypass-commit --reason <string> --message <string>")
    quit(1)

  result = (reason, message)

proc main() =
  let (reason, message) = parseArgs()

  # Step 1: Generate ephemeral seed (32 bytes CSPRNG)
  var seed: Seed
  let generated = randomBytes(addr seed[0], 32)
  if generated != 32:
    stderr.writeLine("Error: CSPRNG insufficient entropy")
    quit(1)

  let kp = createKeypair(seed)

  # Step 2: TOTP payload: window|tree_hash|reason
  let window = int64(toInt(epochTime())) div 600
  let treeHash = block:
    let (output, exitCode) = execCmdEx("git rev-parse HEAD^{tree}")
    if exitCode == 0: output.strip() else: ""
  let payload = $window & "|" & treeHash & "|" & reason

  # Step 3: Sign payload
  let sig = sign(payload, kp)

  # Step 4: Convert to hex
  var pubHex = ""
  for b in kp.publicKey:
    pubHex &= b.toHex(2)

  var sigHex = ""
  for b in sig:
    sigHex &= b.toHex(2)

  # Step 5: Audit log — record bypass before execution
  stderr.writeLine("[agent-bypass-commit] reason=" & reason)
  stderr.writeLine("[agent-bypass-commit] window=" & $window & " tree=" & treeHash)
  stderr.writeLine("[agent-bypass-commit] pubkey=" & pubHex[0..15] & "...")

  # Step 5a: Log to audit trail files
  let auditEntry = "{\"ts\":" & $int(epochTime()) &
                   ",\"reason\":" & jsonEscape(reason) &
                   ",\"pubkey\":\"" & pubHex[0..<16] &
                   "\",\"type\":\"agent-bypass-commit\",\"commit_msg\":" & jsonEscape(message) & "}"
  # axiom:best-effort(audit trail write) — audit log is best-effort
  try:
    createDir(".axiom")
    let f1 = open(".axiom/bypass_audit.jsonl", fmAppend)
    f1.writeLine(auditEntry)
    f1.close()
  except CatchableError as e:
    stderr.writeLine("[agent-bypass-commit] WARNING: Cannot write .axiom/bypass_audit.jsonl: " & e.msg)

  # axiom:best-effort(audit trail write) — audit log is best-effort
  try:
    let f2 = open("data/bypass_audit.jsonl", fmAppend)
    f2.writeLine(auditEntry)
    f2.close()
  except CatchableError as e:
    stderr.writeLine("[agent-bypass-commit] WARNING: Cannot write data/bypass_audit.jsonl: " & e.msg)

  # Step 6: Inject env vars and execute git commit
  putEnv("AXIOM_EMERGENCY_NO_VERIFY", "1")
  putEnv("AXIOM_BYPASS_SIGNATURE", sigHex)
  putEnv("AXIOM_BYPASS_PUBKEY", pubHex)
  putEnv("AXIOM_BYPASS_REASON", reason)

  let commitCmd = "git commit -m " & jsonEscape(message)
  stderr.writeLine("[agent-bypass-commit] Executing: " & commitCmd)

  let (output, exitCode) = execCmdEx(commitCmd)

  if exitCode == 0:
    stderr.writeLine("[agent-bypass-commit] ✅ Commit succeeded (exit=0)")
    if output.strip().len > 0:
      stderr.writeLine(output.strip())
  else:
    stderr.writeLine("[agent-bypass-commit] ❌ Commit failed (exit=" & $exitCode & ")")
    if output.strip().len > 0:
      stderr.writeLine(output.strip())
    quit(exitCode)

when isMainModule:
  main()
