## Minimal ICommandValidator implementation
## Copy this file and customize the type names and validation rules.
## axiom:template-implementation — all TODOs replaced with working examples

import std/[strutils, tables]

# === Inline interface types (copy into your project if needed) ===

type
  CommandEffect* = enum
    oeIdempotent, oeSideEffect, oeDestructive

  ValidationResult* = object
    allowed*: bool
    reason*: string
    effect*: CommandEffect

# === Configurable constants ===

const
  DefaultCommandBufferCapacity* = 100  # Number of recent commands to retain
  DefaultRateLimitWindowSec* = 60     # Sliding window for rate limiting
  DefaultRateLimitMaxPerWindow* = 10  # Max commands per window

# === State fields ===

type
  MyCommandValidator* = object
    ## Example state: allowlist, blocklist, and command history tracking
    allowedCommands*: OrderedTable[string, bool]  # Allowlist (empty = no restrictions)
    blockedPatterns*: seq[string]                 # Blocklisted prefix patterns
    recentCmds*: seq[string]                     # Circular buffer of recent commands
    bufferSize*: int                             # Configurable max buffer size
    rateLimitMax*: int                           # Max commands per sliding window

# === Constructor: full-args (required, positional) — enables Nim type inference ===

proc newMyCommandValidator*(
  allowed: openArray[string],
  blocked: openArray[string],
  bufferSize: int,
  rateLimitMax: int
): MyCommandValidator =
  ## Initialize validator with explicit allowlist and blocklist.
  var tbl = initOrderedTable[string, bool]()
  for cmd in allowed:
    tbl[cmd] = true
  result.allowedCommands = tbl
  result.blockedPatterns = @[]
  result.recentCmds = @[]
  result.bufferSize = bufferSize
  result.rateLimitMax = rateLimitMax
  for cmd in allowed:
    result.allowedCommands[cmd] = true

# === Constructor: zero-arg convenience overload ===

proc newMyCommandValidator*(): MyCommandValidator =
  ## Initialize validator with defaults (no allowlist, no blocklist).
  newMyCommandValidator(@[], @[], DefaultCommandBufferCapacity, DefaultRateLimitMaxPerWindow)

proc isBlocked*(v: MyCommandValidator, cmd: string): bool =
  ## Check if command matches any blocklisted pattern.
  for pattern in v.blockedPatterns:
    if cmd.startsWith(pattern):
      return true
  false

proc validateCommand*(v: MyCommandValidator, cmd: string): ValidationResult =
  ## Validation logic: blocklist > rate limit > allowlist > default-deny.
  ##
  ## Priority order:
  ##   1. Blocklist check — reject immediately if command matches a blocked prefix
  ##   2. Rate limit check — reject if too many commands in the current window
  ##   3. Allowlist check — if allowlist is non-empty, only listed commands pass
  ##   4. Default deny — empty allowlist means everything is allowed except blocked

  # Step 1: Blocklist
  if v.isBlocked(cmd):
    return ValidationResult(
      allowed: false,
      reason: "blocked by pattern",
      effect: oeDestructive
    )

  # Step 2: Rate limiting (simple count-based within buffer)
  if v.recentCmds.len >= v.rateLimitMax:
    return ValidationResult(
      allowed: false,
      reason: "rate limit exceeded",
      effect: oeIdempotent
    )

  # Step 3: Allowlist
  if v.allowedCommands.len > 0:
    if cmd in v.allowedCommands:
      return ValidationResult(
        allowed: true,
        reason: "allowlist match",
        effect: oeIdempotent
      )
    else:
      return ValidationResult(
        allowed: false,
        reason: "not in allowlist",
        effect: oeIdempotent
      )

  # Step 4: Default allow (no allowlist configured)
  return ValidationResult(
    allowed: true,
    reason: "default allow",
    effect: oeIdempotent
  )

proc recordCommand*(v: var MyCommandValidator, cmd: string, effect: CommandEffect) =
  ## Store the command in a circular buffer, evicting oldest when full.
  v.recentCmds.add(cmd)
  if v.recentCmds.len > v.bufferSize:
    v.recentCmds.delete(0)

proc recentCommands*(v: MyCommandValidator): seq[string] =
  v.recentCmds

# === TEST SKELETON ===

when isMainModule:
  # Full-args constructor — Nim type inference works with positional args
  var v = newMyCommandValidator(
    @["read", "list", "status"],
    @["rm -rf", "delete --all"],
    50,
    5
  )

  block test_allowlist_pass:
    let r = v.validateCommand("read")
    assert r.allowed == true, "read should be allowed"
    assert r.reason == "allowlist match"
    echo "allowlist pass works"

  block test_allowlist_fail:
    let r = v.validateCommand("destroy")
    assert r.allowed == false, "destroy should not be in allowlist"
    assert r.reason == "not in allowlist"
    echo "allowlist fail works"

  block test_blocklist:
    let r = v.validateCommand("rm -rf /tmp")
    assert r.allowed == false, "rm -rf should be blocked"
    assert r.reason == "blocked by pattern"
    assert r.effect == oeDestructive
    echo "blocklist works"

  block test_rate_limit:
    var v2 = newMyCommandValidator(@[], @[], 100, 3)
    v2.recordCommand("a", oeIdempotent)
    v2.recordCommand("b", oeIdempotent)
    v2.recordCommand("c", oeIdempotent)
    let r = v2.validateCommand("d")
    assert r.allowed == false, "should hit rate limit"
    assert r.reason == "rate limit exceeded"
    echo "rate limit works"

  block test_record_and_recent:
    var v3 = newMyCommandValidator(@[], @[], 3, 100)
    v3.recordCommand("cmd1", oeIdempotent)
    v3.recordCommand("cmd2", oeSideEffect)
    v3.recordCommand("cmd3", oeDestructive)
    assert v3.recentCommands().len == 3
    v3.recordCommand("cmd4", oeIdempotent)  # evicts cmd1
    assert v3.recentCommands().len == 3
    assert v3.recentCommands()[0] == "cmd2"
    echo "circular buffer works"

  block test_default_allow:
    var v4 = newMyCommandValidator()  # zero-arg overload, no allowlist/blocklist
    let r = v4.validateCommand("anything")
    assert r.allowed == true, "should default allow"
    assert r.reason == "default allow"
    echo "default allow works"

  echo "All tests passed."
