# WP4c v3 Frontier Localization: `getBitsBE` Exclusion Analysis

**Date:** 2026-08-28
**Experiment ID:** act2-wp4c-symbol-syntax-robustness
**Subject:** `<workspace>/nim-stew-clean-c75502c` (rev c75502ceedb5ed2a37b7b5e4744fc71313682859)
**Axiom root:** `.` (HEAD 089251924)
**Probe:** `experiments/act2-wp4c-symbol-syntax-robustness/wp4c_frontier_localizer.nim`

---

## Confirmed Hypothesis: H2

**getBitsBE IS in `analysis.verificationQueue` but `allDependenciesVerified` returns false.**

### Evidence

| Check | Result | File:Line |
|-------|--------|-----------|
| getBitsBE in `verificationQueue` | YES (count=2, both func+template) | `topology_engine.nim:77` |
| `nodeIndex` maps to template (not func) | YES — index 183 overwrites index 180 | `verified_frontier.nim:23-25` |
| Template `dependencyIds` | `@["stew/bitops2.nim::getBitsBE"]` (self-reference) | `topology_engine.nim:47-48` |
| Dependency resolves via `nodeIdForSorter` | YES — NodeId(116) | `symbol_interning.nim:163` |
| Dependency in `verified` set | NO — empty set | `verified_frontier.nim:36` |
| `allDependenciesVerified` result | **false** — returns at line 36 | `verified_frontier.nim:36` |
| getBitsBE in frontier (subjectMode=true) | **NO** | `verified_frontier.nim:88-89` |

### Live Probe Output (key fields)

```
targetNodeId:        "stew/bitops2.nim::getBitsBE"
inVerificationQueue: true
verificationQueueLength: 931
nodeIndex:           180 (func — first occurrence found by probe)
nodeType:            func
dependencyIds:       []   (func has no dependencies)

--- BUT nodeIndex in computeVerifiedFrontier maps to index 183 (template) ---
template dependencyIds: @["stew/bitops2.nim::getBitsBE"]
template dep resolves:  NodeId(116) — OK
template dep in verified: false — FAILS
```

---

## Root Cause: Duplicate func+template Sharing the Same nodeId

### Where the Dedup/Collision Happens

**`src/core/topology/topology_engine.nim:37-48`** (`buildTopologyAnalysis`):

Both `func getBitsBE` (line 559 of subject) and `template getBitsBE` (line 599 of subject) are scanned by `scanTopologySource` and assigned the **same** `nodeId = "stew/bitops2.nim::getBitsBE"` (see `topology_symbol_scanner.nim:34`: `nodeId: sorterNodeId(modulePath & "::" & parsed.functionName)`).

Both are added to `nodes` as separate entries (indices 180 and 183) with different `nodeType` values but identical `nodeId` strings.

**`src/core/topology/verified_frontier.nim:23-25`** (`buildNodeIndex`):

```nim
func buildNodeIndex(analysis: TopologyAnalysis): Table[string, int] =
  for idx, node in analysis.state.nodes:
    result[sorterNodeIdString(node.id)] = idx
```

The `nodeIndex` table maps each `nodeId` string to the **last** index seen. Since the template (index 183) appears after the func (index 180), `nodeIndex["stew/bitops2.nim::getBitsBE"]` = **183** (the template).

**`src/core/topology/verified_frontier.nim:84-89`** (`computeVerifiedFrontier`):

```nim
let rootIdx = nodeIndex.getOrDefault(sorterNodeIdString(rootSorterId), -1)
...
if not allDependenciesVerified(analysis.state.nodes[rootIdx], verified, internPool):
    continue
```

When `computeVerifiedFrontier` processes getBitsBE from the queue, it looks up `nodeIndex` and gets **index 183 (the template)**. The template has `dependencyIds = @["stew/bitops2.nim::getBitsBE"]` (a self-reference). `allDependenciesVerified` checks if that dependency is in the `verified` set — it is not (empty set), so returns **false**. getBitsBE is excluded from the frontier.

### Exact Drop Site

**`src/core/topology/verified_frontier.nim:88-89`** — `allDependenciesVerified` returns false because the template's self-referencing dependency (same nodeId) is not in the hydrated verified set.

---

## Hypothesis Verdict Summary

| Hypothesis | Verdict | Evidence |
|------------|---------|----------|
| H1: Not in verificationQueue | **REJECTED** | `verificationQueue` contains getBitsBE twice (count=2) |
| H2: `allDependenciesVerified` returns false | **CONFIRMED** | Template's self-ref dep not in verified set; `verified_frontier.nim:36` |
| H3: Already in verified set | **REJECTED** | Verified set is empty (no certs in experiment state) |
| H4: Kernel-scope gate excludes it | **REJECTED** | `subjectMode=true` was passed; gate is skipped at `verified_frontier.nim:78-82` |

---

## Layer Ownership

**Axiom semantic / Axiom integration** — not the subject, not config.

The subject (`nim-stew`) legitimately defines both a `func` and a `template` with the same exported name in the same module. This is valid Nim. Axiom's topology analysis assigns them the same `nodeId` because `nodeId` is derived from `modulePath :: functionName` alone, with no disambiguation by `nodeType`. The `buildNodeIndex` function then silently overwrites the func entry with the template entry, and `computeVerifiedFrontier` uses the template's dependency list (which includes a self-reference) instead of the func's (which has no dependencies).

---

## Is This Still the WP4-b "External Symbol Syntax/Target-Selection Robustness" Blocker?

**No — this is a NEW, different blocker.** The WP4-b blocker was about external symbol target selection (the `--target` flag not matching symbols in the frontier). This is a **dependency-interning / duplicate-definition identity** issue: the shared `nodeId` between func+template causes `nodeIndex` to point to the template, whose self-referencing dependency prevents it from being admitted to the frontier.

The chain is:
1. Scanner assigns same `nodeId` to func and template (`topology_symbol_scanner.nim:34`)
2. `buildTopologyAnalysis` adds both to `nodes` (`topology_engine.nim:41,48`)
3. `buildNodeIndex` maps shared `nodeId` to the LAST entry (template) (`verified_frontier.nim:23-25`)
4. `computeVerifiedFrontier` uses `nodeIndex` to get the template's dependencies (`verified_frontier.nim:84-88`)
5. Template's self-referencing dependency is not in `verified` set (`verified_frontier.nim:36`)
6. `allDependenciesVerified` returns false → getBitsBE excluded from frontier (`verified_frontier.nim:89`)

---

## Files Touched (Probe Only — No Production Changes)

- `experiments/act2-wp4c-symbol-syntax-robustness/wp4c_frontier_localizer.nim` — new experiment probe
- `experiments/act2-wp4c-symbol-syntax-robustness/wp4c_template_check.nim` — temporary template dependency checker

No production source, tests, config, lock files, journal, VKD, CI, or subject repo were modified. No git commits were made.
