# Model Context Protocol (MCP) Tool Execution Protocol

## Source
- **Context7-compatible library ID:** `/modelcontextprotocol/modelcontextprotocol`
- **Topic:** MCP Tool Call JSON-RPC 2.0 Schema

## Summary
MCP defines a strict JSON-RPC 2.0 schema for executing tools and returning results.

### Request Format
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "tool_name",
    "arguments": {
      "key": "value"
    }
  }
}
```

### Response Format
Successful execution:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Tool execution result text"
      }
    ],
    "isError": false
  }
}
```

Error execution (semantic tool error):
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Error description for the model to self-correct"
      }
    ],
    "isError": true
  }
}
```

### Context for Axiom
This evidence supports the implementation of `axiom_validate_integrity` and other `src/mcp/tools.nim` commands, ensuring they return the correct `content` array and `isError` boolean flags, aligning with the standard MCP JSON-RPC 2.0 specification for tool execution errors versus protocol errors.
