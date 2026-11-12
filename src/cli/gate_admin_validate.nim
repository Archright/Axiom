import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}

import core/trusted/env_access
import core/utils/repo_root
import gate_effect_classifier
import gate_ring_buffer
import std/json
import std/os
import std/strutils
import std/times
import core/axiom_pragmas
# ---------------------------------------------------------------------------
# Override log (set by gate_admin.nim at startup)
# ---------------------------------------------------------------------------

var overrideLogPath*: string = ""  ## Set by gate_admin.nim at startup
proc logOverriddenAllow(command, pattern, canonicalCmd: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if overrideLogPath.len == 0:
    return
  let dir = parentDir(overrideLogPath)
  if not dirExists(dir):
    createDir(dir)
  let entry = %*{
    "timestamp": format(now().utc, "yyyy-MM-dd'T'HH:mm:ss'Z'"),
    "action": "OVERRIDDEN_ALLOW",
    "command": command,
    "pattern": pattern,
    "canonicalCmd": canonicalCmd,
    "source": "kimi-code",
    "user": (let u = getAxiomEnv(evUser); if u.len > 0: u else: "unknown")
  }
  let line = $entry & "\n"
  var f = open(overrideLogPath, fmAppend)
  defer: f.close()
  f.write(line)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
let
  projectRoot = findRepoRoot()
  ringPath = projectRoot / ".axiom" / "ring_buffer.json"

# ---------------------------------------------------------------------------
# No-op detection (unchanged from original)
# ---------------------------------------------------------------------------
const NOOP_PATTERNS = [
  "",          # empty
  ":",         # shell no-op
  "true",      # shell builtin — always succeeds
  "false",     # shell builtin — always fails but is a no-op semantically
  "echo",      # echo with no args prints empty line
  "echo ''",
  "echo \"\"",
  "printf ''",
  "printf \"\"",
]
func isNoopCommand(cmd: string): bool =
  let trimmed = cmd.strip()
  if trimmed.len == 0:
    return true
  # Check exact match against known no-op patterns
  for pat in NOOP_PATTERNS:
    if trimmed == pat:
      return true
  # Command that is only whitespace and/or semicolons
  var allNoop = true
  for ch in trimmed:
    if ch notin {' ', '\t', '\n', '\r', ';'}:
      allNoop = false
      break
  if allNoop:
    return true
  return false
# ---------------------------------------------------------------------------
# High-level validation (4-pillar architecture)
# ---------------------------------------------------------------------------
proc recordAndAllow(rb: var RingBuffer, cmd: string, effect: OpEffect,
                    ctxHash, inputHash: string, success: bool): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Record a command in the ring buffer and return 0 (allow).
  rb.append(CommandContext(
    cmdString: cmd,
    effect: ord(effect),
    contextHash: ctxHash,
    inputHash: inputHash,
    success: success,
    timestamp: $now()
  ))
  rb.saveToDisk(ringPath)
  return 0
proc validateCommand*(cmd: string): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Validate a Bash command. Returns 0 (allow) or 2 (block).
  let trimmed = cmd.strip()

  # Rule 1: empty / no-op detection (unchanged)
  if isNoopCommand(trimmed):
    return 2

  # Rule 2: semantic effect classification
  let effect = classifyCommand(trimmed)
  let ctxHash = generateContextHash(projectRoot)
  var rb = loadFromDisk(ringPath)

  case effect
  of oeDerivation:
    # Rule 3: build commands → input boundary hash + 4-cell matrix
    let inputHash = getInputBoundaryHash(trimmed, projectRoot)
    let decision = decideDerivation(inputHash, rb, trimmed)
    case decision
    of ddAllow, ddAllowNetwork:
      # success=false by default (fail-open: gate_admin only does pre-validation)
      return recordAndAllow(rb, trimmed, effect, ctxHash, inputHash, false)
    of ddBlock:
      return 2

  of oeMutation:
    # Rule 4: mutation commands → epoch verification
    let recent = rb.recentEntries(WINDOW_SIZE)
    for entry in recent:
      if entry.cmdString == trimmed and entry.contextHash == ctxHash:
        return 2  # same epoch + same mutation = block
    return recordAndAllow(rb, trimmed, effect, ctxHash, "", true)

  of oeIdempotent:
    # Rule 5: idempotent commands → same epoch repeat = loop
    let recent = rb.recentEntries(WINDOW_SIZE)
    for entry in recent:
      if entry.cmdString == trimmed and entry.contextHash == ctxHash:
        return 2
    return recordAndAllow(rb, trimmed, effect, ctxHash, "", true)

  of oeTransient:
    # Rule 6: transient commands → basic window check
    let recent = rb.recentEntries(WINDOW_SIZE)
    for entry in recent:
      if entry.cmdString == trimmed:
        return 2
    return recordAndAllow(rb, trimmed, effect, ctxHash, "", true)
proc validateStdin*(): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read JSON from stdin, extract ``tool_input.command``, validate.
  ## Returns 0 (allow) or 2 (block).
  var content = ""
  while not endOfFile(stdin):
    content.add(stdin.readLine())
  let trimmed = content.strip()
  if trimmed.len == 0:
    return 2
  try:
    let node = parseJson(trimmed)

    # In-Band guardrail context: kimi-code override takes precedence
    if node.hasKey("guardrail"):
      let guardrail = node["guardrail"]
      let policy = guardrail{"override"}.getStr("")
      let pattern = guardrail{"pattern"}.getStr("")
      if policy == "allow" and pattern.len > 0:
        var cmd = ""
        if node.hasKey("tool_input") and node["tool_input"].hasKey("command"):
          cmd = node["tool_input"]["command"].getStr()
        elif node.hasKey("toolInput") and node["toolInput"].hasKey("command"):
          cmd = node["toolInput"]["command"].getStr()
        logOverriddenAllow(cmd, pattern, guardrail{"canonicalCmd"}.getStr(""))
        return 0

    var command = ""
    if node.hasKey("tool_input") and node["tool_input"].hasKey("command"):
      command = node["tool_input"]["command"].getStr()
    elif node.hasKey("toolInput") and node["toolInput"].hasKey("command"):
      command = node["toolInput"]["command"].getStr()
    return validateCommand(command)
  except JsonParsingError:
    return 2

# ---------------------------------------------------------------------------
# Backward-compatible exports (used by gate_admin.nim)
# ---------------------------------------------------------------------------
proc loadRecentCommands*(): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Return recently observed commands from the ring buffer.
  ## Kept for backward compatibility with gate_admin.nim.
  let rb = loadFromDisk(ringPath)
  let entries = rb.recentEntries(rb.count)
  result = @[]
  for entry in entries:
    result.add(entry.cmdString)
proc isRepeatedCommand*(cmd: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check whether ``cmd`` appears in the recent-command window.
  ## Kept for backward compatibility with gate_admin.nim.
  let rb = loadFromDisk(ringPath)
  let ctxHash = generateContextHash(projectRoot)
  let recent = rb.recentEntries(WINDOW_SIZE)
  for entry in recent:
    if entry.cmdString == cmd.strip() and entry.contextHash == ctxHash:
      return true
  return false
proc recordCommand*(cmd: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Record a command in the ring buffer.
  ## Kept for backward compatibility with gate_admin.nim.
  var rb = loadFromDisk(ringPath)
  let ctxHash = generateContextHash(projectRoot)
  discard recordAndAllow(rb, cmd.strip(), oeTransient, ctxHash, "", true)

{.pop.}
