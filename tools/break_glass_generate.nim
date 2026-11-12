import core/trusted/layer_declaration
axiomLayer "tools"
# Break-Glass Token Generator
# Generates a one-time emergency bypass token
# Usage: break-glass-generate --reason "prod crash fix" --issue PROD-1234

import std/[os, strutils, times, hashes, json]

const
  TokenDir = "logs/break_glass"
  AuditFile = TokenDir / "audit.jsonl"

proc generateToken(reason: string, issueId: string): string =
  # Generate SHA256-like token from timestamp + reason + issue
  let timestamp = now().toTime().toUnix()
  let seed = $timestamp & reason & issueId
  result = $hash(seed) & "-" & $timestamp

proc main() =
  # Parse args
  var reason = ""
  var issueId = ""
  var i = 1
  while i < paramCount():
    case paramStr(i)
    of "--reason": inc i; reason = paramStr(i)
    of "--issue": inc i; issueId = paramStr(i)
    else: discard
    inc i

  if reason.len == 0 or issueId.len == 0:
    echo "Usage: break-glass-generate --reason \"emergency fix\" --issue PROD-1234"
    quit(1)

  # Generate token
  let token = generateToken(reason, issueId)
  let timestamp = now().format("yyyy-MM-dd'T'HH:mm:ss")

  # Create directory
  createDir(TokenDir)

  # Write audit entry
  let entry = %* {
    "token": token,
    "timestamp": timestamp,
    "reason": reason,
    "issue_id": issueId,
    "resolved": false,
    "expires": (now() + initDuration(hours = 24)).format("yyyy-MM-dd'T'HH:mm:ss")
  }

  var f = open(AuditFile, fmAppend)
  f.writeLine($entry)
  f.close()

  echo "🔑 Break-Glass Token Generated"
  echo "================================"
  echo "Token: ", token
  echo "Issue: ", issueId
  echo "Expires: 24 hours"
  echo ""
  echo "Use: AXIOM_BREAK_GLASS_TOKEN=", token, " git push"
  echo ""
  echo "⚠️  This action has been recorded in: ", AuditFile
  echo "⚠️  A debt ticket will be auto-created in: docs/debt/"

when isMainModule:
  main()
