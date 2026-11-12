# Phase 5: Progressive Test Generation Pipeline

> **Status**: Design Document (not yet implemented)
> **Prerequisite**: Guard Ring 4 (test_quality_guard.nim) must be active
> **Target**: DEBT#169 — 890 modules, 15.4% coverage → 80% coverage

---

## 1. Problem Statement

Axiom-core has 890 Nim modules but only 137 have test files (15.4% coverage). The remaining 753 modules have zero test coverage. Applying compile-time test enforcement to all 753 at once would break the build entirely.

**Guard Ring 4's Twin Strategy**:
- **Strategy A (Immediate)**: Enforce test quality on Tier 1 (10 core modules) — DONE
- **Strategy B (Progressive)**: Generate tests for 753 modules tier-by-tier — THIS DOCUMENT

---

## 2. Tier Classification

```
Tier 1 (Enforced): 10 core modules — already have tests, Guard Ring active
  axiom_engine, gate_memo, state_ledger, import_parser, z3_interactive,
  pipeline_context, orchestrator_hook, batch_uap, gate_registry, coverage_bridge

Tier 2 (High Priority): ~120 modules in src/core/ — business logic
  - Gate contracts, domain modules, codec, schema, types
  - Most critical for integrity proof engine correctness
  - Target: 80% coverage within Tier 2

Tier 3 (Medium Priority): ~200 modules in src/gate/ — gate runners
  - Individual gate runners, orchestrator hooks, utilities
  - Each runner is a discrete unit with clear inputs/outputs
  - Target: 70% coverage within Tier 3

Tier 4 (Low Priority): ~433 modules in src/cli/, src/infrastructure/, src/verification/, etc.
  - CLI commands, infrastructure utilities, verification pipeline
  - Many are I/O-heavy (harder to test without mocks)
  - Target: 60% coverage within Tier 4
```

---

## 3. Test Generation Pipeline

### 3.1 Module Analysis Phase

For each untested module, the pipeline:

1. **Extract public API**: Parse `proc`/`func`/`template`/`macro` declarations with `*` export marker
2. **Classify functions**: Pure (`func`) vs I/O (`proc` with `{.axiomEffect: IoEffect.}`)
3. **Identify contracts**: Extract `{.raises: [].}`, `{.noSideEffect.}`, return types
4. **Check dependencies**: What does this module import? What imports it?
5. **Determine test strategy**: Unit test (pure func) vs integration test (proc with I/O)

### 3.2 Test Generation Rules

```nim
# Template for generated test files
import std/unittest
import ../src/path/to/module_under_test

suite "module_under_test":
  test "func_name returns expected output for valid input":
    # Pure functions: direct assertion on return value
    check funcName(validInput) == expectedOutput

  test "func_name handles edge case: empty input":
    check funcName("") == expectedDefault

  test "func_name raises on invalid input":
    expect ValueError:
      discard funcName(invalidInput)

  test "proc_name side effect is correct":
    # I/O procs: verify state changes
    let before = getState()
    procName(input)
    let after = getState()
    check after == expectedState
```

### 3.3 AgentSwarm Execution Plan

```
Round 1: Tier 2 — src/core/ (~120 modules)
  Agent 1~20: Each agent handles 6 modules
  - Analyze module → generate test file → verify compilation
  - Output: tests/tier2/<module>_test.nim

Round 2: Tier 3 — src/gate/ (~200 modules)
  Agent 1~30: Each agent handles 7 modules
  - Focus on gate runner contracts (pass/fail scenarios)
  - Output: tests/tier3/<module>_test.nim

Round 3: Tier 4 — src/cli/ + src/infrastructure/ + src/verification/ (~433 modules)
  Agent 1~50: Each agent handles 9 modules
  - I/O-heavy modules get integration test skeletons
  - Output: tests/tier4/<module>_test.nim
```

### 3.4 Quality Gate for Generated Tests

Generated tests MUST pass the `enforceTestQuality` macro:
- `check true` density < 50%
- At least 1 real assertion per test file
- No stub placeholders

---

## 4. Guard Ring Integration

As each Tier's tests are generated, expand `Tier1Modules` in `test_quality_guard.nim`:

```nim
# Phase 5, Round 1 complete:
Tier1Modules = [...existing..., "deterministic_env", "import_parser", ...120 more...]

# Phase 5, Round 2 complete:
Tier1Modules = [...expanded..., "gate_runner_x", "gate_runner_y", ...200 more...]

# Phase 5, Round 3 complete:
Tier1Modules = [...all 712 modules with tests...]
```

Each expansion makes the Guard Ring enforce tests for more modules, preventing regression.

---

## 5. Metrics & Exit Criteria

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| Module coverage | 15.4% (137/890) | 80% (712/890) | `grep -rn 'test' tests/ \| wc -l` |
| Stub density | Unknown | < 10% | `enforceTestQuality` macro |
| DEBT#169 status | Open | Closed | DEBT_REGISTRY.md |
| Guard Ring enforced modules | 10 | 712 | `Tier1Modules.len` |

---

## 6. Execution Timeline

- **Round 1** (Tier 2): ~2 hours with 20 parallel agents
- **Round 2** (Tier 3): ~3 hours with 30 parallel agents  
- **Round 3** (Tier 4): ~5 hours with 50 parallel agents
- **Total**: ~10 hours wall clock time across all rounds

Each round can be executed in a separate session. The Guard Ring protects against regression between rounds.

---

## 7. Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Generated tests are low quality | `enforceTestQuality` macro rejects stubs at compile time |
| Tests break existing code | Each test file compiles independently; failures are isolated |
| Agent generates incorrect assertions | Review round after each Tier; fix before expanding Tier1Modules |
| I/O modules hard to test | Use `hermeticSandbox` macro from `sandbox_guard.nim` for isolation |
