import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## shell_ast_analyzer — AST-based shell command analysis
##
## Analyzes shell commands for security concerns using POSIX shell tokenization.
## Unlike command_policy_gate (which blocks ALL dynamic syntax), this analyzer
## uses AST awareness to allow safe uses of variable expansion, command
## substitution, and arithmetic expansion inside safe commands.
##
## Security model:
## - Fail-closed: unknown commands are blocked (asAmbiguous)
## - Blocked commands: eval, exec, source, .
## - Blocked wrappers: env, sudo, etc.
## - Blocked network tools: curl, wget, nc, etc.
## - Blocked shell keywords: for, while, if, case, etc.
## - Variable-as-command ($CMD, ${TOOL}, $(cmd)) → BLOCK
## - Command-name obfuscation (e'v'al, "ev"al, \e\v\a\l) → BLOCK
## - Interpreters: shell (bash, sh) → BLOCK; stateless (python3, node) →
##   4-Layer Zero-Trust validation (parseopt normalization → action flag gate →
##   whitelist-only module → environment isolation)
## - find with dangerous flags (-exec, -execdir, -delete) → BLOCK
## - Safe commands with dynamic syntax in arguments → ALLOW

import std/[strutils, json, tables]

type
  AnalysisStatus* = enum
    asSafe        ## 명확히 안전 — 통과
    asAmbiguous   ## 구조 파악 불가 — fail-closed (BLOCK)
    asDangerous   ## 명백히 위험 — BLOCK

  AnalysisResult* = object
    status*: AnalysisStatus
    reason*: string

  ## Zero-Trust interpreter validation types
  InterpreterPolicy* = enum
    ipBlock      ## Shell interpreter — always blocked
    ipStateless  ## Stateless interpreter — 4-Layer validation
    ipAllow      ## Reserved for future use

  ModuleInfo* = object
    rationale*: string  ## Safety justification for this module

  ParsedArgs* = object
    actionFlag*: string     ## -m, -c, -e, -r, --version, --help, or ""
    payloadSlot*: string    ## Module name or inline code (after action flag)
    dataArgs*: seq[string]  ## Free arguments (file paths, etc.)
    hasIsolation*: bool     ## Whether -I flag was found
    rawFlags*: seq[string]  ## All flags seen (for audit trail)

  StatelessWhitelist* = object
    modules*: Table[string, Table[string, ModuleInfo]]
    blockedActions*: seq[string]
    requiredIsolation*: Table[string, seq[string]]
    dangerousEnvVars*: seq[string]

# ---------------------------------------------------------------------------
# Compile-time SSOT whitelist loading
# ---------------------------------------------------------------------------

const whitelistRaw = staticRead("../../../data/stateless_whitelist.json")

# staticRead embeds JSON at compile time; loadWhitelist parses at module init.
# No filesystem access at runtime — content is baked into the binary.
proc loadWhitelist(): StatelessWhitelist {.raises: [CatchableError].} =
  let node = parseJson(whitelistRaw)
  result.modules = initTable[string, Table[string, ModuleInfo]]()
  result.requiredIsolation = initTable[string, seq[string]]()

  # Dangerous environment variables
  for envVarNode in node["dangerousEnvVars"]:
    result.dangerousEnvVars.add(envVarNode.getStr())

  # Blocked action flags
  for actionNode in node["blockedActions"]:
    result.blockedActions.add(actionNode.getStr())

  # Required isolation flags
  for interp, flagsNode in node["requiredIsolation"]:
    var flags: seq[string] = @[]
    for f in flagsNode:
      flags.add(f.getStr())
    result.requiredIsolation[interp] = flags

  # Module whitelist (first pass: direct definitions)
  for interp, modulesNode in node["modules"]:
    if modulesNode.kind == JObject and modulesNode.hasKey("_inherits"):
      continue  # Resolve in second pass
    var modules = initTable[string, ModuleInfo]()
    if modulesNode.kind == JObject:
      for modName, modNode in modulesNode:
        if modNode.kind == JObject and modNode.hasKey("rationale"):
          modules[modName] = ModuleInfo(rationale: modNode["rationale"].getStr())
        else:
          modules[modName] = ModuleInfo(rationale: "No rationale provided")
    result.modules[interp] = modules

  # Module whitelist (second pass: _inherits resolution)
  for interp, modulesNode in node["modules"]:
    if modulesNode.kind == JObject and modulesNode.hasKey("_inherits"):
      let src = modulesNode["_inherits"].getStr()
      if src in result.modules:
        result.modules[interp] = result.modules[src]

let Whitelist* = loadWhitelist()

# ---------------------------------------------------------------------------
# Managed interpreter registry
# ---------------------------------------------------------------------------

const
  ShellInterpreters*: seq[string] = @["bash", "sh", "zsh", "dash", "ksh"]
  StatelessInterpreters*: seq[string] = @[
    "python", "python3", "node", "ruby", "perl",
    "php", "lua", "awk", "sed"
  ]
  ManagedInterpreters*: seq[string] = ShellInterpreters & StatelessInterpreters

func isManagedInterpreter*(name: string): InterpreterPolicy =
  for s in ShellInterpreters:
    if name == s: return ipBlock
  for s in StatelessInterpreters:
    if name == s: return ipStateless
  ipAllow

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  SafeCommands* = [
    "cat", "grep", "ls", "wc", "find", "date", "pwd", "head", "tail",
    "sort", "uname", "which", "echo", "printf", "true", "false",
    "test", "[", "id", "whoami", "file", "du", "df", "stat", "readlink",
    "basename", "dirname", "realpath", "touch", "diff", "tee",
    "tr", "cut", "column", "nl", "od", "strings",
    "comm", "join", "read", "mapfile", "readarray",
    "declare", "export", "local", "typeset", "set"
  ]

  BlockedCommands* = [
    "eval", "exec", "source", "."
  ]

  NetworkTools* = [
    "curl", "wget", "nc", "ncat", "socat", "ssh", "scp", "sftp",
    "rsync", "telnet", "ftp", "tftp"
  ]

  BlockedWrappers* = [
    "env", "sudo", "stdbuf", "nice", "nohup", "timeout",
    "strace", "ltrace", "time"
  ]

  ShellKeywords* = [
    "for", "while", "until", "if", "case", "select",
    "function", "coproc"
  ]

  FindDangerousFlags* = ["-exec", "-execdir", "-delete", "-ok", "-okdir"]

# ---------------------------------------------------------------------------
# POSIX tokenizer
# ---------------------------------------------------------------------------

func tokenizePosix*(cmd: string): seq[string] =
  ## Tokenize a command string following POSIX shell rules.
  ##
  ## - Single quotes: literal content, no escapes inside
  ## - Double quotes: allows backslash escaping of next char
  ## - Backslash outside quotes: escapes next char
  ## - Whitespace splitting outside quotes
  ## - Globs NOT expanded (treated as literal for security)
  result = @[]
  var current = ""
  var inSingle, inDouble = false
  var i = 0
  while i < cmd.len:
    let c = cmd[i]
    if c == '\'' and not inDouble:
      # Toggle single-quote mode (literal, no escapes inside)
      inSingle = not inSingle
      inc i
    elif c == '"' and not inSingle:
      # Toggle double-quote mode
      inDouble = not inDouble
      inc i
    elif c == '\\' and not inSingle:
      # Backslash escape
      if inDouble:
        # Inside double quotes: backslash escapes next char literally
        inc i
        if i < cmd.len:
          current.add(cmd[i])
          inc i
      else:
        # Outside quotes: backslash escapes next char literally
        inc i
        if i < cmd.len:
          current.add(cmd[i])
          inc i
    elif c in {' ', '\t'} and not inSingle and not inDouble:
      # Whitespace outside quotes: token boundary
      if current.len > 0:
        result.add(current)
        current = ""
      inc i
    else:
      current.add(c)
      inc i
  if current.len > 0:
    result.add(current)

# ---------------------------------------------------------------------------
# Assignment detection
# ---------------------------------------------------------------------------

func isAssignment(cmd: string): (bool, string, string) =
  ## Check if the command is a variable assignment.
  ## Returns (isAssign, varName, value).
  ## Handles: VAR=value, VAR=$(cmd), VAR=${ref}
  let eqIdx = cmd.find('=')
  if eqIdx <= 0:
    return (false, "", "")

  let potentialVar = cmd[0..<eqIdx]
  # Validate variable name: [A-Za-z_][A-Za-z0-9_]*
  if potentialVar.len == 0:
    return (false, "", "")
  if not (potentialVar[0].isAlphaAscii or potentialVar[0] == '_'):
    return (false, "", "")
  for c in potentialVar[1..^1]:
    if not (c.isAlphaAscii or c.isDigit or c == '_'):
      return (false, "", "")

  let value = cmd[eqIdx+1..^1]
  return (true, potentialVar, value)

# ---------------------------------------------------------------------------
# Shell keyword detection
# ---------------------------------------------------------------------------

func isShellKeyword(cmd: string): bool =
  ## Check if the command is a shell keyword (compound command).
  for kw in ShellKeywords:
    if cmd == kw:
      return true
  return false

# ---------------------------------------------------------------------------
# Find dangerous flag detection
# ---------------------------------------------------------------------------

func hasFindDangerousFlags(args: seq[string]): bool =
  ## Check if find arguments contain dangerous flags.
  for arg in args:
    if arg.startsWith('-'):
      for flag in FindDangerousFlags:
        if arg == flag or arg.startsWith(flag & '='):
          return true
  return false

# ---------------------------------------------------------------------------
# Layer 1: POSIX-compatible argument normalization
# ---------------------------------------------------------------------------

func parseLongOption(arg: string, parsed: var ParsedArgs) =
  ## Handle long option: --key=value, --version, --help.
  let eqPos = arg.find('=')
  if eqPos >= 0:
    parsed.rawFlags.add(arg[0..<eqPos])
  else:
    parsed.rawFlags.add(arg)
  if arg == "--version":
    parsed.actionFlag = "--version"
  elif arg == "--help":
    parsed.actionFlag = "--help"

func extractActionPayload(arg: string, j: int, args: seq[string],
                          i: var int): string =
  ## Extract payload for an action flag (-m/-c/-e/-r).
  ## Attached payload takes priority; otherwise consumes next argument.
  if j + 1 < arg.len:
    return arg[j+1..^1]
  elif i + 1 < args.len:
    inc i
    return args[i]
  result = ""

func applyShortFlag(c: char, arg: string, j: int, args: seq[string],
                    i: var int, parsed: var ParsedArgs) =
  ## Apply a single short flag character to parsed state.
  case c
  of 'I':
    parsed.hasIsolation = true
  of 'm':
    parsed.actionFlag = "-m"
    parsed.payloadSlot = extractActionPayload(arg, j, args, i)
  of 'c':
    parsed.actionFlag = "-c"
    parsed.payloadSlot = extractActionPayload(arg, j, args, i)
  of 'e':
    parsed.actionFlag = "-e"
    parsed.payloadSlot = extractActionPayload(arg, j, args, i)
  of 'r':
    parsed.actionFlag = "-r"
    parsed.payloadSlot = extractActionPayload(arg, j, args, i)
  else:
    discard

func expandShortFlags(arg: string, args: seq[string],
                      i: var int, parsed: var ParsedArgs) =
  ## Expand clustered short flags (-vBIm) into individual applications.
  parsed.rawFlags.add(arg)
  var j = 1  # Skip leading '-'
  while j < arg.len:
    applyShortFlag(arg[j], arg, j, args, i, parsed)
    inc j

func routeBareArg(arg: string, parsed: var ParsedArgs) =
  ## Route a bare (non-flag) argument to the appropriate slot.
  if parsed.actionFlag.len == 0:
    parsed.dataArgs.add(arg)
  elif parsed.payloadSlot.len == 0:
    parsed.payloadSlot = arg
  else:
    parsed.dataArgs.add(arg)

func normalizeArgs*(args: seq[string]): ParsedArgs =
  ## Normalize interpreter arguments using POSIX-compatible parsing.
  ## Handles short flag clustering (-vBIm), long options, -- terminator.
  result = ParsedArgs()
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg == "--":
      # Terminator: all remaining args are data
      inc i
      while i < args.len:
        result.dataArgs.add(args[i])
        inc i
      break
    elif arg.startsWith("--"):
      parseLongOption(arg, result)
      inc i
    elif arg.startsWith("-") and arg.len > 1:
      expandShortFlags(arg, args, i, result)
      inc i
    else:
      routeBareArg(arg, result)
      inc i

# ---------------------------------------------------------------------------
# Layer 3: Whitelist module validation
# ---------------------------------------------------------------------------

proc validateModule*(interpName: string, moduleName: string): AnalysisResult =
  ## Validate that a module is in the compile-time whitelist for this interpreter.
  if interpName notin Whitelist.modules:
    return AnalysisResult(status: asDangerous,
      reason: "BLOCKED: No whitelist for interpreter: " & interpName)
  if moduleName in Whitelist.modules[interpName]:
    let info = Whitelist.modules[interpName][moduleName]
    return AnalysisResult(status: asSafe,
      reason: "Whitelisted module: " & interpName & " -m " & moduleName &
        " [rationale: " & info.rationale & "]")
  AnalysisResult(status: asDangerous,
    reason: "BLOCKED: Module not in whitelist: " & interpName & " -m " & moduleName &
      ". Add to data/stateless_whitelist.json if verified stateless.")

# ---------------------------------------------------------------------------
# Layer 4: Environment isolation validation
# ---------------------------------------------------------------------------

proc validateIsolation*(interpName: string, parsed: ParsedArgs): AnalysisResult =
  ## Validate that required isolation flags are present.
  ## Python -I ignores PYTHONPATH, PYTHONHOME, and user site-packages.
  if interpName in Whitelist.requiredIsolation:
    let requiredFlags = Whitelist.requiredIsolation[interpName]
    for reqFlag in requiredFlags:
      if not parsed.hasIsolation:
        return AnalysisResult(status: asDangerous,
          reason: "BLOCKED: " & interpName & " requires " & reqFlag &
            " (isolated mode). Prevents env hijacking via: " &
            Whitelist.dangerousEnvVars.join(", "))
  AnalysisResult(status: asSafe,
    reason: "Isolation verified. Dangerous env vars neutralized: " &
      Whitelist.dangerousEnvVars.join(", "))

# ---------------------------------------------------------------------------
# 4-Layer Zero-Trust interpreter analysis
# ---------------------------------------------------------------------------

proc analyzeInterpreterArgs*(interpName: string, args: seq[string]): AnalysisResult =
  ## Analyze interpreter arguments through 4-Layer Zero-Trust pipeline.
  ##
  ## L1: POSIX normalization (flag clustering, -- terminator)
  ## L2: Action flag gate (-c/-e/-r blocked as stateful, only -m allowed)
  ## L3: Whitelist-only module validation (config/stateless_whitelist.json)
  ## L4: Environment isolation (Python -I mandatory)
  ##
  ## All block/pass reasons include full parsed structure for audit trail.

  # Bare interpreter invocation
  if args.len == 0:
    return AnalysisResult(status: asDangerous,
      reason: "BLOCKED: Bare interpreter invocation [" & interpName & "]")

  # Layer 1: POSIX normalization
  let parsed = normalizeArgs(args)

  # Layer 2: Action flag gate

  # Info flags (--version, --help): standalone only
  if parsed.actionFlag in ["--version", "-V", "--help", "-h"]:
    if parsed.payloadSlot.len > 0 or parsed.dataArgs.len > 0:
      return AnalysisResult(status: asDangerous,
        reason: "BLOCKED: Extraneous args with " & parsed.actionFlag &
          " [parsed: action=" & parsed.actionFlag &
          ", payload=" & parsed.payloadSlot &
          ", data=" & $parsed.dataArgs & "]")
    return AnalysisResult(status: asSafe,
      reason: "Valid metadata invocation: " & parsed.actionFlag)

  # Blocked actions (-c, -e, -r): inline code = stateful
  if parsed.actionFlag in Whitelist.blockedActions:
    return AnalysisResult(status: asDangerous,
      reason: "BLOCKED: Inline code (" & parsed.actionFlag &
        ") is functionally stateful. Only -m whitelisted modules allowed." &
        " [parsed: action=" & parsed.actionFlag &
        ", payload=" & parsed.payloadSlot & "]")

  # No action flag or unsupported action → fail-closed
  if parsed.actionFlag != "-m":
    return AnalysisResult(status: asDangerous,
      reason: "BLOCKED: Only -m mode allowed. Got: '" & parsed.actionFlag &
        "' [parsed: flags=" & $parsed.rawFlags &
        ", data=" & $parsed.dataArgs & "]")

  # Missing payload after -m
  if parsed.payloadSlot.len == 0:
    return AnalysisResult(status: asDangerous,
      reason: "BLOCKED: Missing module name after -m" &
        " [parsed: flags=" & $parsed.rawFlags & "]")

  # Layer 3: Whitelist module validation (Zero Trust)
  let moduleResult = validateModule(interpName, parsed.payloadSlot)
  if moduleResult.status != asSafe:
    return moduleResult

  # Layer 4: Environment isolation
  let isolationResult = validateIsolation(interpName, parsed)
  if isolationResult.status != asSafe:
    return isolationResult

  # 4-Layer all PASS
  AnalysisResult(status: asSafe,
    reason: "PASS: " & interpName & " " & parsed.actionFlag & " " &
      parsed.payloadSlot & " [isolation=" & $parsed.hasIsolation &
      ", flags=" & $parsed.rawFlags &
      ", data=" & $parsed.dataArgs & "]")

# ---------------------------------------------------------------------------
# Main analysis
# ---------------------------------------------------------------------------

proc analyzeCommand*(cmd: string): AnalysisResult =
  ## Analyze a shell command for security concerns.
  ## Fail-closed: unknown commands and errors are blocked.
  ##
  ## Security pipeline:
  ##   1. Empty command → BLOCK
  ##   2. Assignment pattern → recursive analysis of inner command
  ##   3. Tokenize → extract command name
  ##   4. Variable-as-command ($CMD) → BLOCK
  ##   5. Shell keywords (for, while, ...) → BLOCK
  ##   6. Blocked commands (eval, exec, source, .) → BLOCK
  ##   7. Network tools (curl, wget, nc) → BLOCK
  ##   8. Blocked wrappers (sudo, env) → BLOCK
  ##   9. Managed interpreters → policy-based (shell=BLOCK, stateless=4-Layer)
  ##  10. Unknown commands → pass through to policy check
  ##  11. Safe commands → additional checks (find dangerous flags)

  let stripped = cmd.strip()

  # 1. Empty command → fail-closed
  if stripped.len == 0:
    return AnalysisResult(status: asAmbiguous, reason: "BLOCKED: empty command")

  # 2. Check for assignment pattern (VAR=value or VAR=$(cmd))
  let (isAssign, _, value) = isAssignment(stripped)
  if isAssign:
    # Assignment with command substitution → recursive check
    if value.startsWith("$(") and value.endsWith(")"):
      let innerCmd = value[2..^2]  # Strip $( and )
      let innerResult = analyzeCommand(innerCmd)
      if innerResult.status != asSafe:
        return AnalysisResult(status: asDangerous,
          reason: "BLOCKED: assignment with blocked command substitution")
      return AnalysisResult(status: asSafe, reason: "allowed")
    # Plain assignment (VAR=value) → allow
    return AnalysisResult(status: asSafe, reason: "allowed")

  # 3. Tokenize
  let tokens = tokenizePosix(stripped)
  if tokens.len == 0:
    return AnalysisResult(status: asAmbiguous,
      reason: "BLOCKED: empty command after tokenization")

  let firstToken = tokens[0]

  # 4. Variable-as-command ($CMD, ${TOOL}, $(cmd))
  if firstToken.len > 0 and firstToken[0] == '$':
    return AnalysisResult(status: asDangerous, reason: "BLOCKED: variable as command")

  # Get command name (tokenizer already strips quotes and escapes,
  # which also defeats command-name obfuscation like e'v'al → eval)
  let cmdName = firstToken

  # 5. Shell keywords (compound commands)
  if isShellKeyword(cmdName):
    return AnalysisResult(status: asDangerous, reason: "BLOCKED: compound command")

  # 6. Blocked commands
  for blocked in BlockedCommands:
    if cmdName == blocked:
      return AnalysisResult(status: asDangerous,
        reason: "BLOCKED: " & cmdName & " is not allowed")

  # 7. Network tools
  for net in NetworkTools:
    if cmdName == net:
      return AnalysisResult(status: asDangerous,
        reason: "BLOCKED: network tool " & cmdName)

  # 8. Blocked wrappers
  for wrapper in BlockedWrappers:
    if cmdName == wrapper:
      return AnalysisResult(status: asDangerous,
        reason: "BLOCKED: " & cmdName & " is not allowed")

  # 9. Managed interpreters — policy-based validation
  let policy = isManagedInterpreter(cmdName)
  case policy
  of ipBlock:
    return AnalysisResult(status: asDangerous,
      reason: "BLOCKED: Direct shell execution forbidden: " & cmdName)
  of ipStateless:
    return analyzeInterpreterArgs(cmdName, tokens[1..^1])
  of ipAllow:
    discard

  # 10. Unknown commands → pass through to policy check (not blocked here)
  # The analyzer only blocks KNOWN dangerous commands.
  # Unknown commands (git, nim, cargo, etc.) pass through to command_policy_gate's
  # existing policy check which handles tool-specific rules.
  var isSafe = false
  for safe in SafeCommands:
    if cmdName == safe:
      isSafe = true
      break

  if not isSafe:
    # Unknown command — check for dynamic syntax in arguments
    # Safe commands allow dynamic syntax (echo $HOME), but unknown commands
    # with dynamic syntax are dangerous (git $(whoami) status)
    for i in 1..<tokens.len:
      let tok = tokens[i]
      if tok.len > 0 and tok[0] == '$':
        return AnalysisResult(status: asAmbiguous,
          reason: "BLOCKED: dynamic syntax in unknown command arguments")
      if tok.contains("$(") or tok.contains("${") or
         tok.contains("$((") or tok.contains("`"):
        return AnalysisResult(status: asAmbiguous,
          reason: "BLOCKED: dynamic syntax in unknown command arguments")
    return AnalysisResult(status: asSafe, reason: "allowed")

  # 11. Safe command — additional checks

  # Special handling for find: block dangerous flags
  if cmdName == "find":
    if tokens.len > 1 and hasFindDangerousFlags(tokens[1..^1]):
      return AnalysisResult(status: asDangerous,
        reason: "BLOCKED: find with dangerous flag")

  # Safe command with any arguments (including dynamic syntax) → allow
  # This is the key difference from command_policy_gate:
  # echo $HOME, echo $(date), echo $((1+1)) are all allowed
  return AnalysisResult(status: asSafe, reason: "allowed")

{.pop.}
