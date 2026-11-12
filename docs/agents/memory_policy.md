# Memory Policy

This file is **auto-generated** from `[memory_policy_markers]` in `src/gate/architecture_policy.lock`. Do not edit manually.

AGENTS.md must contain the following markers verbatim:

- **agents_ssot**: `프로젝트 정책/규칙/컨벤션은 모두 AGENTS.md에`
- **no_memory_records**: `메모리에 기록하지 말 것`

## Rationale

Project policy, rules, and conventions must live in `AGENTS.md`, not in agent session memory or ephemeral notes. These markers are enforced by the memory-policy lockfile at `src/gate/architecture_policy.lock`.
