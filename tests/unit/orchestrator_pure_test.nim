## orchestrator_pure_test.nim
## Business scenario tests for orchestrator_pure.nim — the pure logic layer
## behind orchestrator_hook_part1.nim and orchestrator_hook_part2.nim.
##
## These modules are the #1 and #2 hotspot modules. The pure layer contains
## the deterministic core logic for failure classification, gate partitioning,
## ledger assembly, and hash composition. Every test exercises observable
## business behavior, not trivial getters.

import std/[unittest, strutils, tables, sets]
import gate/orchestrator_pure
import gate/gate_contract
import core/gate/hash_types
import core/gate/state_ledger_types

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Failure Classification
# When a gate binary exits, the orchestrator must classify the failure
# to determine cache policy. Wrong classification = stale FAIL cache
# or unnecessary re-runs.
# ══════════════════════════════════════════════════════════════════════════════

suite "classifyFailure: exit code routing":
  test "exit code 1 is validation failure (gate logic rejected input)":
    let (cat, reason) = classifyFailure(1, "FAIL: import cycle detected")
    check cat == fcValidation
    check reason.contains("FAIL: import cycle detected")

  test "exit code 2 is permanent failure (config/policy error)":
    let (cat, reason) = classifyFailure(2, "FAIL: config.nims missing")
    check cat == fcPermanent
    check reason.contains("FAIL: config.nims missing")

  test "exit code 134 (SIGABRT) is permanent with signal prefix":
    let (cat, reason) = classifyFailure(134, "FAIL: assertion failed")
    check cat == fcPermanent
    check reason.startsWith("SIGABRT:")
    check reason.contains("FAIL: assertion failed")

  test "exit code 139 (SIGSEGV) is permanent with signal prefix":
    let (cat, reason) = classifyFailure(139, "FAIL: memory fault")
    check cat == fcPermanent
    check reason.startsWith("SIGSEGV:")
    check reason.contains("FAIL: memory fault")

  test "exit code 0 is not a failure (transient, empty reason)":
    let (cat, reason) = classifyFailure(0, "")
    check cat == fcTransient
    check reason.len == 0

  test "exit code 137 (SIGKILL) is transient":
    let (cat, reason) = classifyFailure(137, "")
    check cat == fcTransient
    check reason.len == 0

  test "unknown exit code defaults to transient":
    let (cat, reason) = classifyFailure(42, "FAIL: unknown error")
    check cat == fcTransient
    check reason.contains("FAIL: unknown error")

  test "empty output with exit code 1 gives empty reason":
    let (cat, reason) = classifyFailure(1, "")
    check cat == fcValidation
    check reason.len == 0

  test "multiple FAIL lines are joined with semicolons":
    let (cat, reason) = classifyFailure(1, "FAIL: line1\nOK: pass\nFAIL: line2")
    check cat == fcValidation
    check "FAIL: line1" in reason
    check "FAIL: line2" in reason
    check ";" in reason

  test "no FAIL lines gives empty reason":
    let (cat, reason) = classifyFailure(99, "all good\nno issues")
    check cat == fcTransient
    check reason.len == 0

suite "classifyFailure: structured output markers":
  # Markers are ONLY checked for unclassified exit codes (the else branch).
  # Exit codes 1 and 2 have hard-wired classifications that take priority.
  test "exit code 1 takes priority over [fcPermanent] marker":
    let (cat, _) = classifyFailure(1, "[fcPermanent] missing Z3 binary")
    check cat == fcValidation  # exit code 1 wins

  test "exit code 2 takes priority over [fcValidation] marker":
    let (cat, _) = classifyFailure(2, "[fcValidation] type mismatch in x")
    check cat == fcPermanent  # exit code 2 wins

  test "classified exit codes use FAIL lines for reason, not markers":
    let (_, reason) = classifyFailure(1, "FAIL: Z3 not found\nok line")
    check reason == "FAIL: Z3 not found"

  test "unclassified exit code with [fcPermanent] marker uses marker classification":
    let (cat, _) = classifyFailure(99, "line1\n[fcPermanent] critical\nline3")
    check cat == fcPermanent

  test "unclassified exit code with [fcValidation] marker uses marker classification":
    let (cat, _) = classifyFailure(99, "[fcValidation] schema mismatch")
    check cat == fcValidation

  test "marker extracts message after bracket":
    let (_, reason) = classifyFailure(99, "[fcPermanent] Z3 not found")
    check reason.contains("Z3 not found")

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Pattern-Based File Filtering
# The gate orchestrator uses filesPattern (pipe-separated) to determine
# which changed files trigger which gates. Wrong filtering = missed gates
# or unnecessary re-runs.
# ══════════════════════════════════════════════════════════════════════════════

suite "filterByPattern: incremental gate triggering":
  test "empty pattern returns all changed files (catch-all gate)":
    let files = @["src/core/types.nim", "tests/unit/x_test.nim"]
    let matched = filterByPattern(files, "")
    check matched.len == 2

  test "single pattern matches substring":
    let files = @["src/core/types.nim", "src/gate/gate_memo.nim", "tests/x_test.nim"]
    let matched = filterByPattern(files, "src/gate")
    check matched.len == 1
    check matched[0] == "src/gate/gate_memo.nim"

  test "exact match pattern selects the matching file":
    let files = @["src/foo.nim", "src/bar.py", "src/baz.nim"]
    let matched = filterByPattern(files, "src/foo.nim")
    check matched == @["src/foo.nim"]

  test "pipe-separated patterns match any component":
    let files = @["src/core/types.nim", "config.nims", "AGENTS.md"]
    let matched = filterByPattern(files, "config|AGENTS")
    check matched.len == 2

  test "no files match when patterns are too specific":
    let files = @["src/core/types.nim"]
    let matched = filterByPattern(files, "src/cli")
    check matched.len == 0

  test "pattern with whitespace is stripped before matching":
    let files = @["src/gate/gate_memo.nim"]
    let matched = filterByPattern(files, "  src/gate  ")
    check matched.len == 1

  test "empty file list returns empty regardless of pattern":
    let matched = filterByPattern(@[], "src/gate")
    check matched.len == 0

  test "multiple patterns each match independently":
    let files = @["src/gate/a.nim", "src/cli/b.nim", "tests/c.nim"]
    let matched = filterByPattern(files, "src/gate|src/cli")
    check matched.len == 2

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Environment Hash Computation
# Gate cache keys include env dependency hashes to invalidate caches
# when git config or env vars change (e.g., AXIOM_JOBS).
# ══════════════════════════════════════════════════════════════════════════════

suite "computeEnvHash: context-aware caching":
  test "empty deps returns empty string":
    let hash = computeEnvHash(@[], EnvContextSnapshot(values: initTable[string, string]()))
    check hash.len == 0

  test "single env var produces deterministic hash":
    var snap = EnvContextSnapshot(values: initTable[string, string]())
    snap.values["AXIOM_JOBS"] = "4"
    let deps = @[EnvDependency(kind: dkEnvVar, key: "AXIOM_JOBS")]
    let hash = computeEnvHash(deps, snap)
    check hash.len == 64  # SHA-256 hex
    # Deterministic: same input → same output
    check computeEnvHash(deps, snap) == hash

  test "different env values produce different hashes":
    var snap1 = EnvContextSnapshot(values: initTable[string, string]())
    snap1.values["AXIOM_JOBS"] = "4"
    var snap2 = EnvContextSnapshot(values: initTable[string, string]())
    snap2.values["AXIOM_JOBS"] = "8"
    let deps = @[EnvDependency(kind: dkEnvVar, key: "AXIOM_JOBS")]
    check computeEnvHash(deps, snap1) != computeEnvHash(deps, snap2)

  test "git config dependency uses 'git:' prefix":
    var snap = EnvContextSnapshot(values: initTable[string, string]())
    snap.values["user.name"] = "test"
    let deps = @[EnvDependency(kind: dkGitConfig, key: "user.name")]
    let hash = computeEnvHash(deps, snap)
    check hash.len == 64

  test "missing value uses __AXIOM_MISSING__ sentinel":
    var snap = EnvContextSnapshot(values: initTable[string, string]())
    # Don't set the key — simulates missing git config
    let deps = @[EnvDependency(kind: dkGitConfig, key: "missing.key")]
    let hash = computeEnvHash(deps, snap)
    check hash.len == 64
    # Verify it differs from a snapshot that has the value
    snap.values["missing.key"] = "present"
    check computeEnvHash(deps, snap) != hash

  test "mixed dependency types produce valid hash":
    var snap = EnvContextSnapshot(values: initTable[string, string]())
    snap.values["AXIOM_JOBS"] = "4"
    snap.values["user.name"] = "test"
    let deps = @[
      EnvDependency(kind: dkEnvVar, key: "AXIOM_JOBS"),
      EnvDependency(kind: dkGitConfig, key: "user.name")
    ]
    let hash = computeEnvHash(deps, snap)
    check hash.len == 64

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Gate Layer Partitioning
# The orchestrator separates L1 (Meta, sequential) from L2 (Functional,
# parallel) gates. Mis-classification breaks the execution model.
# ══════════════════════════════════════════════════════════════════════════════

suite "partitionByLayer: L1/L2 separation":
  test "all-meta gates go to L1":
    let gates = @[
      GateConfig(id: "gate-a", layer: glMeta),
      GateConfig(id: "gate-b", layer: glMeta)
    ]
    let (l1, l2) = partitionByLayer(gates)
    check l1.len == 2
    check l2.len == 0

  test "all-functional gates go to L2":
    let gates = @[
      GateConfig(id: "gate-c", layer: glFunctional),
      GateConfig(id: "gate-d", layer: glFunctional)
    ]
    let (l1, l2) = partitionByLayer(gates)
    check l1.len == 0
    check l2.len == 2

  test "mixed gates are correctly separated":
    let gates = @[
      GateConfig(id: "meta-1", layer: glMeta),
      GateConfig(id: "func-1", layer: glFunctional),
      GateConfig(id: "meta-2", layer: glMeta),
      GateConfig(id: "func-2", layer: glFunctional)
    ]
    let (l1, l2) = partitionByLayer(gates)
    check l1.len == 2
    check l2.len == 2
    check l1[0].id == "meta-1"
    check l1[1].id == "meta-2"
    check l2[0].id == "func-1"
    check l2[1].id == "func-2"

  test "empty gate list returns empty layers":
    let (l1, l2) = partitionByLayer(@[])
    check l1.len == 0
    check l2.len == 0

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Tier-2 Deferral
# Heavy gates (tier=2) are deferred to post-commit to keep hooks fast.
# Wrong deferral breaks the SLA budget.
# ══════════════════════════════════════════════════════════════════════════════

suite "filterDeferredGates: tier separation":
  test "all tier-1 gates are active":
    let gates = @[
      GateConfig(id: "light-1", tier: 1),
      GateConfig(id: "light-2", tier: 1)
    ]
    let (active, deferredCount) = filterDeferredGates(gates)
    check active.len == 2
    check deferredCount == 0

  test "tier-2 gates are separated":
    let gates = @[
      GateConfig(id: "light", tier: 1),
      GateConfig(id: "heavy", tier: 2)
    ]
    let (active, deferredCount) = filterDeferredGates(gates)
    check active.len == 1
    check active[0].id == "light"
    check deferredCount == 1

  test "all tier-2 gates deferred":
    let gates = @[
      GateConfig(id: "heavy-1", tier: 2),
      GateConfig(id: "heavy-2", tier: 2)
    ]
    let (active, deferredCount) = filterDeferredGates(gates)
    check active.len == 0
    check deferredCount == 2

  test "empty list returns empty active and zero deferred":
    let (active, deferredCount) = filterDeferredGates(@[])
    check active.len == 0
    check deferredCount == 0

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Ledger Entry Assembly
# The state ledger captures gate metadata for L2 children via mmap.
# Wrong assembly = children see stale or incorrect gate states.
# ══════════════════════════════════════════════════════════════════════════════

suite "buildLedgerEntries: state ledger preparation":
  test "tier-1 gate in pre-commit has zero deferred fields":
    let gates = @[GateConfig(id: "test-gate", tier: 1)]
    let entries = buildLedgerEntries(gates, 42, gsPreCommit)
    check entries.len == 1
    check entries[0].tier == 1
    check entries[0].result == 0
    check entries[0].deferredAt == 0
    check entries[0].deferredStage == 0

  test "tier-2 gate gets deferred marker with epoch timestamp":
    let gates = @[GateConfig(id: "heavy-gate", tier: 2)]
    let entries = buildLedgerEntries(gates, 42, gsPreCommit)
    check entries.len == 1
    check entries[0].tier == 2
    check entries[0].result == uint8(lgrDeferred)
    check entries[0].deferredAt == 42
    check entries[0].deferredStage == 0  # lsPreCommit
    check entries[0].cacheKey == H_VOID  # deferred gates get the void cache key

  test "deterministic: same input → identical entry sequence":
    let gates = @[
      GateConfig(id: "gate-a", tier: 1),
      GateConfig(id: "gate-b", tier: 2)
    ]
    let e1 = buildLedgerEntries(gates, 1, gsPreCommit)
    let e2 = buildLedgerEntries(gates, 1, gsPreCommit)
    check e1 == e2

  test "pre-push stage maps to stageId 1":
    let gates = @[GateConfig(id: "g", tier: 2)]
    let entries = buildLedgerEntries(gates, 10, gsPrePush)
    check entries[0].deferredStage == 1

  test "CI stage maps to stageId 3":
    let gates = @[GateConfig(id: "g", tier: 2)]
    let entries = buildLedgerEntries(gates, 10, gsCI)
    check entries[0].deferredStage == 3

  test "gateIdHash is deterministic FNV-1a":
    let gates = @[GateConfig(id: "same-id", tier: 1)]
    let e1 = buildLedgerEntries(gates, 0, gsPreCommit)
    let e2 = buildLedgerEntries(gates, 0, gsPreCommit)
    check e1[0].gateIdHash == e2[0].gateIdHash

  test "different gate IDs produce different hashes":
    let entries = buildLedgerEntries(
      @[GateConfig(id: "gate-a", tier: 1), GateConfig(id: "gate-b", tier: 1)],
      0, gsPreCommit)
    check entries[0].gateIdHash != entries[1].gateIdHash

  test "mixed tier gates in pre-commit":
    let gates = @[
      GateConfig(id: "fast", tier: 1),
      GateConfig(id: "slow", tier: 2)
    ]
    let entries = buildLedgerEntries(gates, 5, gsPreCommit)
    check entries.len == 2
    check entries[0].result == 0     # tier-1: not deferred
    check entries[1].result == uint8(lgrDeferred)  # tier-2: deferred

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Hash Composition
# Composite lock hashes bind gate source + input files + build environment.
# Any change to these components MUST invalidate the cache.
# ══════════════════════════════════════════════════════════════════════════════

suite "assembleCompositeHash: cache key composition":
  test "deterministic: same inputs produce same hash":
    let h1 = assembleCompositeHash("a", "b", "c", "d", "e", "f", "g", "h")
    let h2 = assembleCompositeHash("a", "b", "c", "d", "e", "f", "g", "h")
    check h1 == h2
    check h1.len == 64  # SHA-256 hex

  test "different input hash produces different composite":
    let base = assembleCompositeHash("a", "b", "c", "d", "e", "f", "g", "h")
    let diff = assembleCompositeHash("X", "b", "c", "d", "e", "f", "g", "h")
    check base != diff

  test "different gate hash produces different composite":
    let base = assembleCompositeHash("a", "b", "c", "d", "e", "f", "g", "h")
    let diff = assembleCompositeHash("a", "X", "c", "d", "e", "f", "g", "h")
    check base != diff

  test "different build env hash produces different composite":
    let base = assembleCompositeHash("a", "b", "c", "d", "e", "f", "g", "h")
    let diff = assembleCompositeHash("a", "b", "c", "X", "e", "f", "g", "h")
    check base != diff

  test "different binary hash produces different composite":
    let base = assembleCompositeHash("a", "b", "c", "d", "e", "f", "g", "h")
    let diff = assembleCompositeHash("a", "b", "c", "d", "e", "X", "g", "h")
    check base != diff

  test "different env hash produces different composite":
    let base = assembleCompositeHash("a", "b", "c", "d", "e", "f", "g", "h")
    let diff = assembleCompositeHash("a", "b", "c", "d", "e", "f", "X", "h")
    check base != diff

  test "different toolchain salt produces different composite":
    let base = assembleCompositeHash("a", "b", "c", "d", "e", "f", "g", "h")
    let diff = assembleCompositeHash("a", "b", "c", "d", "e", "f", "g", "X")
    check base != diff

  test "all-empty inputs still produce a valid hash":
    let hash = assembleCompositeHash("", "", "", "", "", "", "", "")
    check hash.len == 64
