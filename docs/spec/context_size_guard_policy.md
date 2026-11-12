# Context Size Guard Policy

> **RETIRED 2026-10-02** — context_size_guard 게이트군 purge(건축가 지시). 본 문서는 32KB 바이트 정책 rationale의 역사 기록으로만 남는다. "L1 pre-commit runs context_size_guard" 같은 강제 주장은 이 시점 이전에도 빌드 체인 미배선으로 사실과 달랐다(정정 기록).

> Spec: 32KB threshold system for the `context_size_guard` gate.
> Implements: the retired size-guard runner (source removed 2026-10-02)
> Cross-ref: `docs/agents/operations.md` (AGENTS.md Size Guard), `docs/agents/quality-gates.md` §3.1.

## 1. Purpose

The `context_size_guard` gate verifies that AGENTS.md — the single auto-loaded
context file for every agent session (§0 Constitution) — remains within a size
budget that does not risk agent context truncation. If AGENTS.md grows beyond
the blocking threshold, the gate FAILS and the commit is blocked.

## 2. Auto-Loaded Context File Inventory

"Role tiering" was rejected. Instead, the gate operates on an explicit
**inventory of auto-loaded context files** (currently a single entry:
`AGENTS.md §0`). The inventory is centralized in the helper
`isAutoLoadedContextFile(path)`:

```nim
func isAutoLoadedContextFile*(path: string): bool =
  ## Files auto-loaded into every agent session (currently AGENTS.md §0).
  path.endsWith(AgmdPath)
```

This is a **centralized** inventory (hardcoded path checks do not scatter across
the codebase). When a future auto-loaded file is added, it is registered here in
one place and `run()` automatically enforces the size budget on it.

## 3. Byte Units (HARD — no rune counting)

`content.len` (Nim `string` length) and `getFileSize` both measure **bytes**.
The gate uses byte semantics consistently throughout. **`utf8RuneCount` is NOT
introduced** — rune counting (Unicode code points) would diverge from the
byte-based `getFileSize` self-reference test and from every other size guard in
the toolchain, breaking deterministic guarantee (identical input → identical
output).

Rationale: AI tokenizers and agent context windows generally budget in bytes /
tokens; byte semantics are the established project convention.

## 4. Threshold System (26K / 30K / 32K)

| Constant | Value | Role |
|----------|-------|------|
| `WarnThreshold` | 26,000 bytes | Non-blocking advisory (noise floor) |
| `BlockThreshold` | 30,000 bytes | Blocks commit — `run()` uses this |
| `ContextLimit`  | 32,000 bytes | Hard agent-truncation boundary |

Headroom math:

```
ContextLimit - WarnThreshold  = 32,000 - 26,000 =  6,000 bytes (warn headroom)
ContextLimit - BlockThreshold = 32,000 - 30,000 =  2,000 bytes (block headroom)
```

The previous system conflation of `contextSizeThreshold` = `BlockThreshold`
(=18,000) was removed — `run()` now consumes `BlockThreshold` directly; a single
source of truth for the blocking value.

## 5. 32KB Selection Rationale

AGENTS.md currently measures **26,850 bytes ≈ 24,431 runes**, which is safely
below all three threshold levels:

```
26,850 B  <  WarnThreshold (26,000)?  NO  → exceeds advisory   (advisory only)
26,850 B  <  BlockThreshold (30,000)? YES → gate PASSES
26,850 B  <  ContextLimit   (32,000)? YES → self-reference test PASSES
```

- At ~7K tokens (26,850 B ÷ ~3.8 B/token), AGENTS.md occupies only **~5%** of a
  128K-token context window — a comfortable safety margin against truncation
  while leaving room for the Constitution and future amendments.
- 30,000 was chosen as the blocking boundary (just above the current 26,850 B)
  so the gate PASSES immediately with no file reduction required.
- 32,000 was chosen as the hard truncation limit, giving a 2,000-byte block
  headroom to warn of imminent truncation.

## 6. Enforcement Path

1. **Pre-commit gate (L1)** runs `context_size_guard`; FAIL on > 30,000 bytes.
2. **Self-reference test** (`context_size_guard_feature_test.nim`) asserts
   `getFileSize("AGENTS.md") < ContextLimit` (32,000), guaranteeing the project's
   own policy text stays within the budget.
3. **`tools/rule_proposal.nim`** enforces `MaxAgentsMdSize = 30,000` on rule
   proposals so no single proposal can push AGENTS.md over the blocking
   threshold (matches `BlockThreshold`).

## 7. Dependencies

- context_size_guard 러너 (2026-10-02 purge로 소스 삭제)
- `src/../tools/rule_proposal.nim` (`MaxAgentsMdSize`)
- context_size_guard 게이트웨이 피처 테스트 (2026-10-02 purge로 삭제)
- context_size_guard BDD 피처 (2026-10-02 purge로 삭제)
