import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

import core/json/std_redirect

# -----------------------------------------------------------------------------
# JSON-RPC 2.0 Base Protocol
# -----------------------------------------------------------------------------

type
  RpcRequest* = object
    jsonrpc*: string
    id*: JsonNode
    methodName*: string
    params*: JsonNode

  RpcResponse* = object
    jsonrpc*: string
    id*: JsonNode
    result*: JsonNode
    error*: JsonNode

  RpcError* = object
    code*: int
    message*: string
    data*: JsonNode

# -----------------------------------------------------------------------------
# MCP Specific Types
# -----------------------------------------------------------------------------

type
  McpTool* = object
    name*: string
    description*: string
    inputSchema*: JsonNode

## New Rpc Error.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
func newRpcError*(code: int, message: string, data: JsonNode = newJNull()): RpcError =
  result.code = code
  result.message = message
  result.data = data

## To Error Node.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
func toErrorNode*(err: RpcError): JsonNode =
  result = %*{
    "code": err.code,
    "message": err.message
  }
  if err.data.kind != JNull:
    result["data"] = err.data

## Parse Rpc Request.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
func parseRpcRequest*(node: JsonNode): RpcRequest =
  result.jsonrpc = node.getOrDefault("jsonrpc").getStr()
  result.id = node.getOrDefault("id")
  result.methodName = node.getOrDefault("method").getStr()
  result.params = node.getOrDefault("params")

## New Rpc Response.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
func newRpcResponse*(id: JsonNode, res: JsonNode): RpcResponse =
  result.jsonrpc = "2.0"
  result.id = id
  result.result = res
  result.error = newJNull()

## New Rpc Error Response.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
func newRpcErrorResponse*(id: JsonNode, err: RpcError): RpcResponse =
  result.jsonrpc = "2.0"
  result.id = id
  result.result = newJNull()
  result.error = err.toErrorNode()

## To Json.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
func toJson*(res: RpcResponse): JsonNode =
  result = %*{"jsonrpc": res.jsonrpc, "id": res.id}
  if res.error.kind != JNull:
    result["error"] = res.error
  else:
    result["result"] = res.result
{.pop.}
