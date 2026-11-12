# ADR: MCP Server Integration

## 1. Context
An interface was needed for external AI agents or IDEs (e.g., OpenCode) to transparently and deterministically call Axiom engine's verification and refinement tools. While the existing CLI-based pipeline was excellent, process creation overhead and file I/O dependencies could become bottlenecks for agents to track complex states and quickly iterate source modification/verification (Self-Healing) in memory.

## 2. Decision
- Build a lightweight **MCP (Model Context Protocol) server** in the `src/mcp/` layer that provides memory-based verification and refinement tools.
- Expose `axiom_read_source`, `axiom_apply_hint`, `axiom_verify_in_memory`, `axiom_suggest_refinement` tools through JSON-RPC 2.0 stdio protocol.
- **Zero-Exception & Mathematical Integrity**: The MCP layer is also separated from core domain logic and internally relies entirely on core functions (`func`) that comply with `.nosideeffect.` pragmas. Side effects (I/O, OS calls) are isolated only in outermost boundaries (Executor Tier) like `tools.nim`.

## 3. Consequences
- Agents can directly call SMT/Lean verification through `axiom_verify_in_memory` without disk I/O, greatly improving recovery pipeline speed.
- Hint suggestions from `axiom_suggest_refinement` using the Legislator persona can be immediately utilized for deterministic invariant refinement by external agents.
- `ax.cmd` and `refresh_cli_binaries.ps1` in the repository were extended to support `mcp` subcommand, integrating with build integrity gate (`prek`).

## 4. Evidence Log (Related Commits)
- `6a45b199` feat(mcp): implement high-level in-memory verification and refinement tools
- `a5e27e12` refactor: rename mcp-serve subcommand to mcp in launcher scripts
- `9b6a66e6` feat: build lightweight MCP server for Axiom integration