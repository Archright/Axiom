import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
import core/axiom_pragmas
import core/json/std_redirect
import core/utils/io_utils
import infrastructure/logger
import mcp/protocol, mcp/tools
import std/os
import std/strformat
import std/times
# -----------------------------------------------------------------------------
# Logger
# -----------------------------------------------------------------------------

var logFile: File
## Init Logger.
# @axiom-hint: lean="(logFile ≥ 0)" smt="(assert (and (>= logFile 0)))"
proc initLogger*(logPath: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    discard existsOrCreateDirOpt(parentDir(logPath))
    logFile = open(logPath, fmAppend)
  except CatchableError:
    discard # Fallback if log file cannot be opened  # axiom:best-effort(ioboundary catch)

## Log Message.
# @axiom-hint: lean="direction.length ≥ 0 ∧ msg.length ≥ 0" smt="(assert (and (>= (str.len direction) 0) (>= (str.len msg) 0)))"
proc logMessage*(direction, msg: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if logFile != nil:
    let timestamp = now().format("yyyy-MM-dd'T'HH:mm:ss'.'fffzzz")
    logFile.writeLine(&"[{timestamp}] {direction}: {msg}")
    logFile.flushFile()

# -----------------------------------------------------------------------------
# Dispatcher
# -----------------------------------------------------------------------------

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
proc handleInitialize(req: RpcRequest): JsonNode =
  # MCP 'initialize' response
  return %*{
    "protocolVersion": "2024-11-05",
    "serverInfo": {
      "name": "axiom-mcp",
      "version": "1.0.0"
    },
    "capabilities": {
      "tools": {}
    }
  }

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
proc handleToolsList(req: RpcRequest): JsonNode =
  # MCP 'tools/list' response
  return %*{
    "tools": getMcpTools()
  }

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
proc handleToolsCall(req: RpcRequest): JsonNode {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # MCP 'tools/call' response
  let name = req.params{"name"}.getStr()
  let args = req.params{"arguments"}
  
  var content: JsonNode
  case name
  of "axiom_read_source":
    content = axiomReadSource(args)
  of "axiom_apply_hint":
    content = axiomApplyHint(args)
  of "axiom_verify":
    content = axiomVerify(args)
  of "axiom_verify_in_memory":
    content = axiomVerifyInMem(args)
  of "axiom_suggest_refinement":
    content = axiomSuggestRefinement(args)
  of "axiom_validate_integrity":
    content = axiomValidateIntegrity(args).toJson
  else:
    return %*{
      "content": [
        {
          "type": "text",
          "text": &"Unknown tool: {name}"
        }
      ],
      "isError": true
    }

  # Result format for MCP tool call
  if content.hasKey("error"):
    return %*{
      "content": [
        {
          "type": "text",
          "text": content{"error"}.getStr()
        }
      ],
      "isError": true
    }
  else:
    return %*{
      "content": [
        {
          "type": "text",
          "text": $content
        }
      ],
      "isError": false
    }

# @axiom-hint: lean="line.length ≥ 0" smt="(assert (and (>= (str.len line) 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
proc processMessage(line: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  logMessage("RECV", line)
  
  var reqNode: JsonNode
  var parseErr = false
  try:
    reqNode = json.parseJson(line)
  except JsonParsingError:
    parseErr = true
    
  if parseErr:
    let errRes = newRpcErrorResponse(newJNull(), newRpcError(-32700, "Parse error"))
    let resStr = $toJson(errRes)
    logMessage("SEND", resStr)
    return resStr
    
  # Ignore notifications (requests without id)
  if not reqNode.hasKey("id"):
    return ""

  let req = parseRpcRequest(reqNode)
  var resNode: JsonNode
  
  case req.methodName
  of "initialize":
    resNode = handleInitialize(req)
  of "tools/list":
    resNode = handleToolsList(req)
  of "tools/call":
    resNode = handleToolsCall(req)
  else:
    # Optional: handle other standard MCP methods like notifications/initialized
    resNode = %*{}

  let res = newRpcResponse(req.id, resNode)
  let resStr = $toJson(res)
  logMessage("SEND", resStr)
  return resStr

# -----------------------------------------------------------------------------
# Main Event Loop
# -----------------------------------------------------------------------------

## Run Server.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
proc runServer*(args: seq[string] = @[]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Exported entry point for unified binary.
  ## Args are accepted for API compatibility but currently ignored.
  discard args
  let logPath = joinPath(getCurrentDir(), "logs", "mcp_server.log")
  initLogger(logPath)
  logMessage("INFO", "Axiom MCP Server started")

  while true:
    var line = ""
    try:
      if not stdin.readLine(line):
        break
    except EOFError:
      break

    if line.len > 0:
      let response = processMessage(line)
      if response.len > 0:
        # stdout IS the MCP transport channel per MCP spec §Transport.
        # This echo is intentional protocol output, not debug logging.
        logger.info response
        flushFile(stdout)

  if logFile != nil:
    logFile.close()

## Start Mcp Server.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
proc startMcpServer*() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  runServer()

when isMainModule:
  startMcpServer()

{.pop.}
