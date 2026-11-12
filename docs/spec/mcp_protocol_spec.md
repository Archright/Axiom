# MCP Protocol — Specification

> DEBT#182 — Last updated: 2026-06-05

## Purpose

The MCP (Model Context Protocol) subsystem exposes Axiom's verification capabilities as **JSON-RPC 2.0
tools** over stdio transport, enabling agentic IDE environments (Kimi, Cursor, Claude, etc.) to invoke
proof verification, trace inspection, and invariant refinement without CLI coupling.

Per AGENTS.md §1.1: "MCP as Extension — calls `src/core/`; does not replace CLI."

## Module Map

| File | Responsibility |
|------|---------------|
| `mcp_params.nim` | Pure parameter extraction helpers: `stringField`, `optionalIntField`, `objectField`, `lookupField`. All `func`. |
| `protocol.nim` | **Legacy** JSON-RPC 2.0 types: `RpcRequest`, `RpcResponse`, `RpcError`. Parse/serialize. |
| `server.nim` | **Legacy** stdin/stdout event loop with logger. Dispatches to `tools.nim`. |
| `tools.nim` | **Legacy** tool implementations: `axiom_read_source`, `axiom_apply_hint`, `axiom_verify`, `axiom_verify_in_memory`, `axiom_suggest_refinement`, `axiom_validate_integrity`. |
| `axiom_mcp_part1.nim` | **Modern** protocol layer: tool definitions, JSON-RPC dispatch, `handleJsonRpcMessage`, `runStdioServer`. |
| `axiom_mcp_part2.nim` | **Modern** tool execution: `executeToolCall` routing, `getProofToolResult`, `suggestRefinementToolResult`. |

## Architecture: Two Generations

The MCP subsystem contains two coexisting implementations:

1. **Legacy** (`protocol.nim` + `server.nim` + `tools.nim`): Original implementation with `@axiom-hint`
   pragmas. Uses `execCmdEx` for `axiom_verify` (shells out to `ax heal`).

2. **Modern** (`axiom_mcp_part1.nim` + `axiom_mcp_part2.nim`): Refactored implementation with
   dot-namespaced tools (`axiom.verify`), `Result`-based error handling, and in-memory pipeline
   execution. The preferred entry point.

Both share `mcp_params.nim` for parameter extraction.

## Transport

- **stdio**: One JSON-RPC message per line (newline-delimited)
- **Notifications**: Messages without `"id"` field are silently acknowledged (empty response)
- **Logging**: `server.nim` logs to `logs/mcp_server.log` with timestamps

## Tool Inventory (Modern)

| Tool | Required Params | Description |
|------|----------------|-------------|
| `axiom.verify` | `language`, `modulePath`, `functionName`, `astJson`, `sourceCode` | Run UAP, return normalized proof summary |
| `axiom.inspectTrace` | (proof source — one of: `proofJson`, `proof`, `proofSummaryPath`, `proofArtifactPath`) | Extract trace details from proof artifact |
| `axiom.getProof` | (session or proof source) | Return `ProofArtifact` + ASI score |
| `axiom.suggestRefinement` | `language`, `modulePath`, `functionName`, `astJson`, `sourceCode` | Legislator persona invariant refinement |

## Tool Inventory (Legacy)

| Tool | Description |
|------|-------------|
| `axiom_read_source` | Read file content |
| `axiom_apply_hint` | Write `@axiom-hint` annotated source back to file |
| `axiom_verify` | Shell out to `ax heal --limit 1` |
| `axiom_verify_in_memory` | In-memory UAP execution |
| `axiom_suggest_refinement` | Legislator refinement (legacy variant) |
| `axiom_validate_integrity` | 3-tier triangular integrity check (Evidence, Context, BDD) |

## JSON-RPC Error Codes

| Code | Meaning |
|------|---------|
| `-32700` | Parse error |
| `-32600` | Invalid Request |
| `-32601` | Method not found |
| `-32602` | Invalid params |
| `-32000 - ord(AxiomError)` | Domain-specific errors (mapped from `AxiomError` enum) |

## Integration Points

- **`core/axiom_api`** — `inspectTrace`, `generateProofFromSession`, `generateProofFromSessionId`
- **`verification/universal_pipeline`** — `runUniversalAcceptanceWorkflow` for in-memory verification
- **`personas/legislator`** — `legislate()` for invariant refinement proposals
- **`translator/universal_mapper`** — AST JSON → `UniversalTranslation` mapping
- **`core/logic/pipeline_fingerprint_engine`** — ASI score computation

## Key Contracts

1. **CLI First**: MCP extends CLI, never replaces it. All MCP tools are thin wrappers over core logic.
2. **Effect boundary**: `mcp_params.nim` helpers are `func`; tool executors are `proc` (I/O).
3. **Protocol version**: Modern implements `"2025-11-25"`; Legacy reports `"2024-11-05"`.
4. **Server notification**: Modern sends `axiom/ready` notification on startup.

## Known Limitations

- **Dual implementation**: Legacy and modern coexist — code duplication in tool logic.
- **Legacy `axiom_verify`**: Uses `execCmdEx` (subprocess) rather than in-memory pipeline.
- **No streaming**: Responses are single JSON objects; no incremental progress reporting.
- **No authentication**: stdio transport assumes trusted local process.
- **`axiom_validate_integrity`**: Calls `quit(1)` on failure — terminates the MCP server process.
