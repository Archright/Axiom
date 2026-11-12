## Minimal Gate Runner template
## A simplified ICommandValidator for quick gate prototyping.

import ../path/to/kimi-sdk/interfaces/command_validator

type
  SimpleGateRunner* = object
    allowedCommands: seq[string]

proc newSimpleGateRunner*(allowed: seq[string]): SimpleGateRunner =
  SimpleGateRunner(allowedCommands: allowed)

proc validateCommand*(r: SimpleGateRunner, cmd: string): ValidationResult =
  ## Simple allowlist check
  let allowed = cmd in r.allowedCommands
  ValidationResult(
    allowed: allowed,
    reason: if allowed: "allowlist" else: "not in allowlist",
    effect: oeIdempotent
  )

proc recordCommand*(r: var SimpleGateRunner, cmd: string, effect: CommandEffect) =
  discard  # Simple runner doesn't track history

proc recentCommands*(r: SimpleGateRunner): seq[string] =
  @[]  # Simple runner doesn't track history

# === TEST SKELETON ===
when isMainModule:
  var r = newSimpleGateRunner(@["read", "list", "status"])
  assert r.validateCommand("read").allowed
  assert not r.validateCommand("delete").allowed
  echo "✅ All tests passed."
