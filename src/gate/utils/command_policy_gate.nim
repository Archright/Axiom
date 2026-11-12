import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## command_policy_gate — Layer 0 command policy enforcement
##
## Validates agent shell commands against a compile-time policy.
## Uses AST-based analysis (shell_ast_analyzer) for security checks.
## Policy embedded at compile time via macro (Patch 11).
## Fail-closed: ANY exception → exit 2 (Patch 3).

import std/[os, strutils, strformat, json, macros, sequtils]
import ./shell_ast_analyzer
import ./git_state
import core/trusted/effect_bridge
import infrastructure/logging_facade

# ---------------------------------------------------------------------------
# Compile-time policy embedding (Patch 11)
# ---------------------------------------------------------------------------

macro compilePolicy(): untyped =
  ## Read data/command_policy.json at compile time and generate const arrays.
  let policyJson = staticRead("../../data/command_policy.json")
  let policy = parseJson(policyJson)
  var blocked: seq[string]
  var alternatives: seq[string]
  for p in policy["policies"]:
    if p["tool"].getStr() == "git":
      for sub in p["blockedSubcommands"]:
        blocked.add(sub.getStr())
      for alt in p["alternatives"]:
        alternatives.add(alt.getStr())
  result = newStmtList()
  result.add newConstStmt(ident("BlockedSubcommands"), newLit(blocked))
  result.add newConstStmt(ident("Alternatives"), newLit(alternatives))

compilePolicy()

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  GateTag = "[command-policy]"
  ShellControlOps = ["&&", "||", ";", "|"]
  WrapperSkips = ["env", "sudo", "stdbuf", "nice", "nohup", "timeout",  ## SKIP to find actual tool (not block)
                   "strace", "ltrace", "time"]  ## Note: shell_ast_analyzer.BlockedWrappers BLOCKS these
  ## Flags that consume the next argv element as their argument.
  ## Must be identical to the list in git_wrapper.nim.
  FlagsWithArgs = [
    "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix",
    "--strategy", "--strategy-option", "-X",
    "--onto", "--exec", "--empty",
    "-m", "--message", "--mainline", "--cleanup",
    "--whitespace", "-p", "--directory", "--exclude", "--include",
    "--patch-format"
  ]

# ---------------------------------------------------------------------------
# Patch 8 — Shell operator splitting (opMatched flag pattern)
# ---------------------------------------------------------------------------

func splitByOperators(cmd: string): seq[string] =
  ## Split command on shell control operators (&&, ||, ;, |)
  ## while preserving quoted content. Each segment is processed independently.
  result = @[]
  var current = ""
  var inSingle, inDouble = false
  var i = 0
  while i < cmd.len:
    let c = cmd[i]
    if c == '\'' and not inDouble:
      inSingle = not inSingle
      current.add(c)
      inc i
    elif c == '"' and not inSingle:
      inDouble = not inDouble
      current.add(c)
      inc i
    elif not inSingle and not inDouble:
      var opMatched = false
      for op in ShellControlOps:
        if i + op.len <= cmd.len and cmd[i ..< i + op.len] == op:
          if current.strip().len > 0:
            result.add(current)
          current = ""
          i += op.len
          opMatched = true
          break
      if opMatched:
        continue
      current.add(c)
      inc i
    else:
      current.add(c)
      inc i
  if current.strip().len > 0:
    result.add(current)

# ---------------------------------------------------------------------------
# Tool detection (Patch 4 — wrapper skipping)
# ---------------------------------------------------------------------------

func findTool(tokens: seq[string]): (string, int) =
  ## Find the actual tool name, skipping wrapper commands (env, sudo, etc.)
  ## and environment variable assignments (KEY=value).
  ## Returns (tool_name, index of first real argument after the tool token).
  result = ("", 0)
  for idx, tok in tokens:
    if tok in WrapperSkips:
      continue
    # Skip env variable assignments: KEY=value (common after env wrapper)
    if '=' in tok and tok.len > 0 and tok[0] != '-':
      continue
    let toolName = extractFilename(tok)
    return (toolName, idx + 1)
  return ("", 0)

# ---------------------------------------------------------------------------
# Patch 1 — Subcommand extraction with flag-argument handling
# ---------------------------------------------------------------------------

func extractSubcommand(tokens: seq[string], startIdx: int): string =
  ## Extract the subcommand from tokens, skipping flags and their arguments.
  ## FlagsWithArgs (e.g. -C, --git-dir) consume the following token as well.
  var i = startIdx
  while i < tokens.len:
    let tok = tokens[i]
    if tok.len == 0:
      inc i
      continue
    if tok[0] == '-':
      # Flag — check if it takes a separate argument
      var skipNext = false
      for flag in FlagsWithArgs:
        if tok == flag:
          # Exact match: flag + separate argument
          skipNext = true
          break
        elif flag.len > 2 and tok.startsWith(flag & "="):
          # Inline argument: --flag=value (already in this token)
          break
      inc i
      if skipNext and i < tokens.len:
        inc i  # skip the flag's argument
      continue
    # First non-flag token is the subcommand
    return tok
  return ""

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

proc validate(command: string): (bool, string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Validate a command against the compile-time policy.
  ## Returns (allowed, reason).
  ##
  ## Pipeline:
  ##   1. AST-based security analysis
  ##   2. Shell operator splitting
  ##   3. Per-segment: tokenize → find tool → extract subcommand → state-aware policy check

  # P-AST: AST-based security analysis
  let astResult = analyzeCommand(command)
  if astResult.status != asSafe:
    return (false, astResult.reason)

  # P2: Split on shell control operators
  let segments = splitByOperators(command)

  # Detect Git state once for all segments
  let ctx = detectGitContext()

  for segment in segments:
    let tokens = tokenizePosix(segment)
    if tokens.len == 0:
      continue

    let (tool, argStart) = findTool(tokens)
    if tool == "git":
      let subcmd = extractSubcommand(tokens, argStart)
      if subcmd.len == 0:
        continue

      # State-aware policy evaluation
      case ctx.state
      of gsContextFree:
        if subcmd in BlockedSubcommands:
          let alts = Alternatives.join("; ")
          return (false, &"BLOCKED: git {subcmd} — use {alts}")
      of gsRebasing, gsRebasingConflict:
        if subcmd == "rebase" and isRebaseResolutionCommand(tokens[argStart .. ^1]):
          continue  # allowed resolution command
        return (false, "BLOCKED: git " & subcmd & " during rebase — use --continue|--abort|--skip")
      of gsMerging:
        if subcmd == "merge" and tokens[argStart .. ^1].anyIt(it in ["--continue", "--abort", "--quit"]):
          continue
        return (false, "BLOCKED: git " & subcmd & " during merge — use --continue|--abort|--quit")
      of gsCherryPick, gsReverting, gsBisecting:
        # During other operations, only the specific resolution command is allowed
        if subcmd in BlockedSubcommands:
          return (false, "BLOCKED: git " & subcmd & " during " & $ctx.state)
    else:
      # Managed interpreter validation (4-Layer Zero-Trust)
      let policy = isManagedInterpreter(tool)
      case policy
      of ipBlock:
        return (false, "BLOCKED: Shell interpreter in pipeline: " & tool)
      of ipStateless:
        let r = analyzeInterpreterArgs(tool, tokens[argStart .. ^1])
        if r.status != asSafe:
          return (false, r.reason)
      of ipAllow:
        discard

  return (true, "allowed")

# ---------------------------------------------------------------------------
# Input reading
# ---------------------------------------------------------------------------

proc readCommandFromStdin(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read command from stdin. Handles:
  ##   1. JSON: {"tool_input":{"command":"..."}}
  ##   2. Plain text
  var input = ""
  while not endOfFile(stdin):
    let line = stdin.readLine()
    if input.len > 0:
      input.add("\n")
    input.add(line)
  input = input.strip()
  if input.len == 0:
    return ""

  # Try JSON parsing first
  try:
    let j = parseJson(input)
    if j.hasKey("tool_input") and j["tool_input"].hasKey("command"):
      return j["tool_input"]["command"].getStr()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  # Plain text fallback
  return input

# ---------------------------------------------------------------------------
# Main entry point (Patch 3 — fail-closed: ANY error → exit 2)
# ---------------------------------------------------------------------------

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Gate entry point. Reads command from CLI arg or stdin, validates, exits.
  ##   exit 0 = allowed (PASS)
  ##   exit 2 = blocked or error (FAIL, fail-closed)
  var command = ""

  # 1. CLI argument: --test-command=<value>
  for arg in commandLineParams():
    if arg.startsWith("--test-command="):
      command = arg["--test-command=".len .. ^1]
      break

  # 2. stdin (JSON or plain text)
  if command.len == 0:
    try:
      command = readCommandFromStdin()
    except CatchableError:
      logError("command_policy_gate", &"{GateTag} FAIL: could not read stdin")
      quit(2)

  if command.len == 0:
    logError("command_policy_gate", &"{GateTag} FAIL: no command provided")
    quit(2)

  logInfo("command_policy_gate", &"{GateTag} Validating command...")

  try:
    let (allowed, reason) = validate(command)
    if allowed:
      logInfo("command_policy_gate", &"{GateTag} PASS: {reason}")
      quit(0)
    else:
      logError("command_policy_gate", &"{GateTag} FAIL: {reason}")
      quit(2)
  except CatchableError as e:
    # Patch 3: Fail-closed — any exception = block
    logError("command_policy_gate", &"{GateTag} FAIL: exception during validation: {e.msg}")
    quit(2)

when isMainModule:
  main()

{.pop.}
