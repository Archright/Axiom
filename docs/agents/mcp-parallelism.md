# MCP Parallelism & Sub-Agent Policy

> Extracted from AGENTS.md §2.4.1–§2.4.3. Refer to AGENTS.md §2.4 for the mandate summary.

---

#### 2.4.1 Mandatory Parallelism Checklist (BEFORE FIRST TOOL CALL)

Every agent MUST evaluate these checks **before calling any tool**:

| # | Check | Action if YES |
|---|-------|---------------|
| 1 | Does this task touch ≥2 independent file domains? | MUST use `delegate_task(tasks=[])` per AGENTS.md §2.6a |
| 2 | Is this a search/exploration task with ≥2 targets? | MUST use parallel `explore` sub-agents per §2.6a |
| 3 | Am I about to run sequential terminal/file commands? | STOP — classify task per §2.6a table first |
| 4 | Is `subagent-mandate` skill loaded? | If NO, load it immediately via `skill_view` |
| 5 | Did I document a waiver if using direct tools? | If NO and task is not single-tool → violation |

---

#### 2.4.2 Sub-Agent Result Verification (PARENT LIABILITY)

**Flash is the worker, Pro is the inspector.** All work reported as "complete" by a sub-agent (flash) must be directly verified by the parent agent (pro). This verification responsibility cannot be delegated to the sub-agent.

| Verification Step | Command/Method | Responsible |
|-----------|-----------|--------|
| File existence | `stat <path>` | Parent agent |
| Code correctness | `read_file <path>` | Parent agent |
| Compilation | `nim check src/cli/main.nim` | Parent agent |
| Gate | `src/gate/nimtry/nimtry_cli.nim --full-tree` | Parent agent |

**Principle**: Sub-agent results are **hypotheses to be verified**, not primary information. Forwarding a "SuccessX" self-report directly to the user is a policy violation.

---

#### 2.4.3 MCP Tool Naming in Sub-Agent Context (NO SHORTHAND)

When passing `context` to a sub-agent, MCP tool names **must use the fully qualified name**. Shorthand forms are not recognized by the MCP protocol, causing the sub-agent to raise an `Unknown tool` error and waste up to 3 turns.

| ❌ Shorthand (Do Not Use) | ✅ Fully Qualified Name (Use) |
|---------------------|-----------------|
| `sequentialthinking` | `mcp_sequential_thinking_sequentialthinking` |
| `code_index_search` | `mcp_code_index_search_code_advanced` |

**Principle**: If a sub-agent needs to use an MCP tool, explicitly include its fully qualified name in the context. The tool name is not conveyed through `toolsets` alone.

---

## Related

- [AGENTS.md §2.4](../../AGENTS.md) — Mandate summary
- [docs/agents/quality-gates.md](quality-gates.md) — Quality gates
