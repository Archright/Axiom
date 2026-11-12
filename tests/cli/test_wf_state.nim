{.push raises: [].}

## Comprehensive unit tests for cli/wf_state module.
## Tests business logic for proof state management, quarantine reset,
## workflow reason construction, path trimming, entry sorting, and JSON traversal.
##
## §0.7 scope: Only business scenarios -- no compiler-guaranteed behaviors.

import std/json
import std/os
import std/strutils
import std/unittest

import cli/wf_state
import cli/wf_state_vacuity
import cli/cli_types
import core/results
import core/sorter/sorter_core
import core/orchestrator/orchestrator_report_types
import core/utils/constants

# ── Helpers ────────────────────────────────────────────────────────────────
# NOTE: OrchestrationReport construction is inlined everywhere because
# Nim 2.2.10 cannot handle any proc/func/template that returns
# OrchestrationReport when enum values like axProofVerified are used in the
# same file. This is a documented compiler limitation.

func makeNodeId(raw: string): SorterNodeId =
  sorterNodeId(raw)

func makeNodeReport(
  nodeId: SorterNodeId;
  status: OrchestrationNodeStatus;
  smtlib2: string = "";
  remediationHint: string = "";
  timeoutComplexityWeight: int = 0;
  timeoutHotspots: seq[string] = @[];
  mathematicalRationale: string = "";
): OrchestrationNodeReport =
  OrchestrationNodeReport(
    nodeId: nodeId,
    dependencyDepth: 0,
    status: status,
    smtlib2: smtlib2,
    remediationHint: remediationHint,
    timeoutComplexityWeight: timeoutComplexityWeight,
    timeoutHotspots: timeoutHotspots,
    mathematicalRationale: mathematicalRationale,
  )

func makeStateEntry(
  nodeId: string;
  status: string;
  reason: string = "";
  staleReason: string = "";
  attemptCount: int = 0;
  tried: bool = false;
  leanDiagnostics: string = "";
  bottleneckLog: string = "";
  healCooldown: int = 0;
  modulePath: string = "";
  functionName: string = "";
): JsonNode =
  var entry = %*{
    nodeIdKey: nodeId,
    statusKey: status,
    "attempted": tried,
    "attemptCount": attemptCount,
  }
  if reason.len > 0:
    entry[reasonKey] = %reason
  if staleReason.len > 0:
    entry["staleReason"] = %staleReason
  if leanDiagnostics.len > 0:
    entry["leanDiagnostics"] = %leanDiagnostics
  if bottleneckLog.len > 0:
    entry["bottleneckLog"] = %bottleneckLog
  if healCooldown > 0:
    entry["healCooldown"] = %healCooldown
  if modulePath.len > 0:
    entry[modulePathKey] = %modulePath
  if functionName.len > 0:
    entry[functionNameKey] = %functionName
  entry

func makeProofState(entries: seq[JsonNode]): JsonNode =
  %*{entriesKey: entries, "summary": %*{"totalSourceFunctions": 1000}}

# ════════════════════════════════════════════════════════════════════════════
# findAxNodeStatus -- node status lookup
# ════════════════════════════════════════════════════════════════════════════

suite "findAxNodeStatus":

  test "returns verified when node report is orchestrationVerified":
    let nid = makeNodeId("modA::funcA")
    let nr = makeNodeReport(nid, orchestrationVerified)
    var report: OrchestrationReport
    report.nodeReports = @[nr]
    let status = findAxNodeStatus(report, nid)
    check status == axProofVerified

  test "returns counter example when node report is orchestrationProofFailed":
    let nid = makeNodeId("modB::funcB")
    let nr = makeNodeReport(nid, orchestrationProofFailed)
    var report: OrchestrationReport
    report.nodeReports = @[nr]
    let status = findAxNodeStatus(report, nid)
    check status == axProofCounterExampleFound

  test "returns timed out when node report is orchestrationTimedOut":
    let nid = makeNodeId("modC::funcC")
    let nr = makeNodeReport(nid, orchestrationTimedOut)
    var report: OrchestrationReport
    report.nodeReports = @[nr]
    let status = findAxNodeStatus(report, nid)
    check status == axProofTimedOut

  test "returns vacuous contradiction when node report is orchestrationVacuousContradiction":
    let nid = makeNodeId("modD::funcD")
    let nr = makeNodeReport(nid, orchestrationVacuousContradiction)
    var report: OrchestrationReport
    report.nodeReports = @[nr]
    let status = findAxNodeStatus(report, nid)
    check status == axProofVacuousContradiction

  test "returns unattempted when node is not found in report":
    let nid = makeNodeId("modX::funcX")
    let otherNid = makeNodeId("modY::funcY")
    let nr = makeNodeReport(otherNid, orchestrationVerified)
    var report: OrchestrationReport
    report.nodeReports = @[nr]
    let status = findAxNodeStatus(report, nid)
    check status == axProofUnattempted

  test "returns unattempted for empty report":
    let nid = makeNodeId("any::any")
    var report: OrchestrationReport
    let status = findAxNodeStatus(report, nid)
    check status == axProofUnattempted

  test "returns unknown for orchestrationBlocked":
    let nid = makeNodeId("modE::funcE")
    let nr = makeNodeReport(nid, orchestrationBlocked)
    var report: OrchestrationReport
    report.nodeReports = @[nr]
    let status = findAxNodeStatus(report, nid)
    check status == axProofUnknown

  test "picks correct node from multiple reports":
    let nid1 = makeNodeId("a::f1")
    let nid2 = makeNodeId("b::f2")
    let nr1 = makeNodeReport(nid1, orchestrationVerified)
    let nr2 = makeNodeReport(nid2, orchestrationProofFailed)
    var report: OrchestrationReport
    report.nodeReports = @[nr1, nr2]
    let s1 = findAxNodeStatus(report, nid1)
    let s2 = findAxNodeStatus(report, nid2)
    check s1 == axProofVerified
    check s2 == axProofCounterExampleFound

# ════════════════════════════════════════════════════════════════════════════
# verifyWorkflowReason -- reason string construction
# ════════════════════════════════════════════════════════════════════════════

suite "verifyWorkflowReason":

  test "returns reproof required when no reasons found":
    let nid = makeNodeId("mod::func")
    var report: OrchestrationReport
    let reason = verifyWorkflowReason(report, nid)
    check reason == "reproof required"

  test "includes stale axiom for stale dependency nodes":
    let nid = makeNodeId("mod::func")
    var report: OrchestrationReport
    report.staleDependencyNodes = @[nid]
    let reason = verifyWorkflowReason(report, nid)
    check reason.contains("stale axiom")

  test "includes timeout for timeout nodes":
    let nid = makeNodeId("mod::func")
    var report: OrchestrationReport
    report.timeoutNodes = @[nid]
    let reason = verifyWorkflowReason(report, nid)
    check reason.contains("timeout")

  test "includes timeout impact only when not in timeoutNodes":
    let nid = makeNodeId("mod::func")
    var report: OrchestrationReport
    report.timeoutImpactNodes = @[nid]
    let reason = verifyWorkflowReason(report, nid)
    check reason.contains("timeout impact")

  test "excludes timeout impact when node is also in timeoutNodes":
    let nid = makeNodeId("mod::func")
    var report: OrchestrationReport
    report.timeoutNodes = @[nid]
    report.timeoutImpactNodes = @[nid]
    let reason = verifyWorkflowReason(report, nid)
    check not reason.contains("timeout impact")
    check reason.contains("timeout")

  test "includes blocked branch for blocked nodes":
    let nid = makeNodeId("mod::func")
    var report: OrchestrationReport
    report.blockedNodes = @[nid]
    let reason = verifyWorkflowReason(report, nid)
    check reason.contains("blocked branch")

  test "includes proof failed from node report status":
    let nid = makeNodeId("mod::func")
    let nr = makeNodeReport(nid, orchestrationProofFailed)
    var report: OrchestrationReport
    report.nodeReports = @[nr]
    let reason = verifyWorkflowReason(report, nid)
    check reason.contains("proof failed")

  test "includes vacuous contradiction from node report":
    let nid = makeNodeId("mod::func")
    let nr = makeNodeReport(nid, orchestrationVacuousContradiction)
    var report: OrchestrationReport
    report.nodeReports = @[nr]
    let reason = verifyWorkflowReason(report, nid)
    check reason.contains("vacuous contradiction")

  test "includes pre-sieved unverifiable":
    let nid = makeNodeId("mod::func")
    let nr = makeNodeReport(nid, orchestrationPreSievedUnverifiable)
    var report: OrchestrationReport
    report.nodeReports = @[nr]
    let reason = verifyWorkflowReason(report, nid)
    check reason.contains("pre-sieved unverifiable")

  test "verified node with no other flags returns reproof required":
    let nid = makeNodeId("mod::func")
    let nr = makeNodeReport(nid, orchestrationVerified)
    var report: OrchestrationReport
    report.nodeReports = @[nr]
    let reason = verifyWorkflowReason(report, nid)
    check reason == "reproof required"

  test "deduplicates multiple reasons":
    let nid = makeNodeId("mod::func")
    let nr = makeNodeReport(nid, orchestrationTimedOut)
    var report: OrchestrationReport
    report.nodeReports = @[nr]
    report.timeoutNodes = @[nid]
    let reason = verifyWorkflowReason(report, nid)
    let count = reason.count("timeout")
    check count == 1

  test "combines multiple distinct reasons with comma separator":
    let nid = makeNodeId("mod::func")
    let nr = makeNodeReport(nid, orchestrationProofFailed)
    var report: OrchestrationReport
    report.staleDependencyNodes = @[nid]
    report.blockedNodes = @[nid]
    report.nodeReports = @[nr]
    let reason = verifyWorkflowReason(report, nid)
    check reason.contains("stale axiom")
    check reason.contains("blocked branch")
    check reason.contains("proof failed")
    check reason.contains(",")

# ════════════════════════════════════════════════════════════════════════════
# trimProofStatePathPrefix -- path prefix removal
# ════════════════════════════════════════════════════════════════════════════

suite "trimProofStatePathPrefix":

  test "returns value unchanged when prefix is empty":
    let result = trimProofStatePathPrefix("src/foo.nim", "")
    check result == "src/foo.nim"

  test "trims matching prefix with separator":
    let result = trimProofStatePathPrefix("project/src/foo.nim", "project/src")
    check result == "foo.nim"

  test "trims matching prefix that ends with slash":
    let result = trimProofStatePathPrefix("project/src/foo.nim", "project/src/")
    check result == "foo.nim"

  test "returns value unchanged when prefix does not match":
    let result = trimProofStatePathPrefix("other/foo.nim", "project/src")
    check result == "other/foo.nim"

  test "handles deeply nested path":
    let result = trimProofStatePathPrefix(
      "/a/b/c/d/e/file.nim", "/a/b/c"
    )
    check result == "d/e/file.nim"

  test "handles single segment prefix":
    let result = trimProofStatePathPrefix("src/foo.nim", "src")
    check result == "foo.nim"

# ════════════════════════════════════════════════════════════════════════════
# sortAxProofEntries -- JSON entry sorting
# ════════════════════════════════════════════════════════════════════════════

suite "sortAxProofEntries":

  test "sorts by dependencyDepth ascending":
    var entries = @[
      %*{dependencyDepthKey: 3, impactIndexKey: 0, labelKey: "c"},
      %*{dependencyDepthKey: 1, impactIndexKey: 0, labelKey: "a"},
      %*{dependencyDepthKey: 2, impactIndexKey: 0, labelKey: "b"},
    ]
    sortAxProofEntries(entries)
    check entries[0][dependencyDepthKey].getInt() == 1
    check entries[1][dependencyDepthKey].getInt() == 2
    check entries[2][dependencyDepthKey].getInt() == 3

  test "sorts by impactIndex descending when depth is equal":
    var entries = @[
      %*{dependencyDepthKey: 1, impactIndexKey: 10, labelKey: "low"},
      %*{dependencyDepthKey: 1, impactIndexKey: 50, labelKey: "high"},
      %*{dependencyDepthKey: 1, impactIndexKey: 30, labelKey: "mid"},
    ]
    sortAxProofEntries(entries)
    check entries[0][impactIndexKey].getInt() == 50
    check entries[1][impactIndexKey].getInt() == 30
    check entries[2][impactIndexKey].getInt() == 10

  test "sorts by label alphabetically when depth and impact are equal":
    var entries = @[
      %*{dependencyDepthKey: 1, impactIndexKey: 5, labelKey: "charlie"},
      %*{dependencyDepthKey: 1, impactIndexKey: 5, labelKey: "alpha"},
      %*{dependencyDepthKey: 1, impactIndexKey: 5, labelKey: "bravo"},
    ]
    sortAxProofEntries(entries)
    check entries[0][labelKey].getStr() == "alpha"
    check entries[1][labelKey].getStr() == "bravo"
    check entries[2][labelKey].getStr() == "charlie"

  test "handles missing keys gracefully (defaults to 0/empty)":
    var entries = @[
      %*{"no_depth_key": true, labelKey: "b"},
      %*{dependencyDepthKey: 0, impactIndexKey: 0, labelKey: "a"},
    ]
    sortAxProofEntries(entries)
    check entries.len == 2

  test "handles empty sequence":
    var entries: seq[JsonNode] = @[]
    sortAxProofEntries(entries)
    check entries.len == 0

  test "single entry remains unchanged":
    var entries = @[
      %*{dependencyDepthKey: 5, impactIndexKey: 99, labelKey: "only"}
    ]
    sortAxProofEntries(entries)
    check entries.len == 1
    check entries[0][labelKey].getStr() == "only"

# ════════════════════════════════════════════════════════════════════════════
# axStateEntryEngine -- JSON traversal tests
# ════════════════════════════════════════════════════════════════════════════

suite "axStateEntryEngine":

  test "returns unknown when no semanticProof field":
    let entry = %*{"status": "verified"}
    let engine = axStateEntryEngine(entry)
    check engine == "unknown"

  test "returns unknown when semanticProof is not JObject":
    let entry = %*{"semanticProof": "not-an-object"}
    let engine = axStateEntryEngine(entry)
    check engine == "unknown"

  test "returns engine from universalPipeline.provenance.engine":
    let entry = %*{
      "semanticProof": {
        "universalPipeline": {
          "provenance": {
            "engine": "lean-4"
          }
        }
      }
    }
    let engine = axStateEntryEngine(entry)
    check engine == "lean-4"

  test "falls back to semanticProof.engine when no universalPipeline":
    let entry = %*{
      "semanticProof": {
        "engine": "z3-bmc"
      }
    }
    let engine = axStateEntryEngine(entry)
    check engine == "z3-bmc"

  test "prefers universalPipeline.provenance.engine over semanticProof.engine":
    let entry = %*{
      "semanticProof": {
        "universalPipeline": {
          "provenance": {
            "engine": "lean-4"
          }
        },
        "engine": "z3-bmc"
      }
    }
    let engine = axStateEntryEngine(entry)
    check engine == "lean-4"

  test "returns unknown when semanticProof.engine is not a string":
    let entry = %*{
      "semanticProof": {
        "engine": 42
      }
    }
    let engine = axStateEntryEngine(entry)
    check engine == "unknown"

  test "returns unknown when universalPipeline is null":
    let entry = %*{
      "semanticProof": {
        "universalPipeline": nil
      }
    }
    let engine = axStateEntryEngine(entry)
    check engine == "unknown"

  test "returns unknown when provenance.engine is missing":
    let entry = %*{
      "semanticProof": {
        "universalPipeline": {
          "provenance": {}
        }
      }
    }
    let engine = axStateEntryEngine(entry)
    check engine == "unknown"

# ════════════════════════════════════════════════════════════════════════════
# resetForceHealQuarantine -- quarantine reset business logic
# ════════════════════════════════════════════════════════════════════════════

suite "resetForceHealQuarantine":

  test "returns 0 for non-object state":
    var state = %*"not-an-object"
    let count = resetForceHealQuarantine(state)
    check count == 0

  test "returns 0 when entries key is missing":
    var state = %*{"metadata": {}}
    let count = resetForceHealQuarantine(state)
    check count == 0

  test "returns 0 when entries is not an array":
    var state = %*{entriesKey: "not-array"}
    let count = resetForceHealQuarantine(state)
    check count == 0

  test "skips unattempted entries":
    var state = makeProofState(@[
      makeStateEntry("a::f1", unattemptedKey)
    ])
    let count = resetForceHealQuarantine(state)
    check count == 0

  test "skips certified_exempt entries":
    var state = makeProofState(@[
      makeStateEntry("a::f1", certifiedExemptStatus)
    ])
    let count = resetForceHealQuarantine(state)
    check count == 0

  test "resets entry with extractor_limitation in reason":
    var state = makeProofState(@[
      makeStateEntry("a::f1", "timed_out", reason = "extractor_limitation")
    ])
    let resetCount = resetForceHealQuarantine(state)
    check resetCount == 1
    check state[entriesKey][0][statusKey].getStr() == unattemptedKey
    check state[entriesKey][0]["attempted"].getBool() == false
    check state[entriesKey][0]["attemptCount"].getInt() == 0
    check state[entriesKey][0][reasonKey].getStr() == "force-heal-quarantine-reset"
    check state[entriesKey][0]["staleReason"].getStr() == "force-heal-retry"

  test "resets entry with vacuous_primitive in reason":
    var state = makeProofState(@[
      makeStateEntry("a::f1", "verified", reason = "vacuous_primitive_detected")
    ])
    let resetCount = resetForceHealQuarantine(state)
    check resetCount == 1
    check state[entriesKey][0][statusKey].getStr() == unattemptedKey

  test "resets entry with vacuous_contradiction in reason":
    var state = makeProofState(@[
      makeStateEntry("a::f1", "verified", reason = "vacuous_contradiction")
    ])
    let resetCount = resetForceHealQuarantine(state)
    check resetCount == 1

  test "resets entry with extractor_limitation in staleReason":
    var state = makeProofState(@[
      makeStateEntry("a::f1", "timed_out", staleReason = "extractor-limitation-retry")
    ])
    let resetCount = resetForceHealQuarantine(state)
    check resetCount == 1

  test "resets entry with extractor_limitation in leanDiagnostics":
    var state = makeProofState(@[
      makeStateEntry("a::f1", "verified", leanDiagnostics = "extractor_limitation encountered")
    ])
    let resetCount = resetForceHealQuarantine(state)
    check resetCount == 1

  test "resets entry with vacuous_contradiction in transitionLog":
    var entry = makeStateEntry("a::f1", "verified")
    entry["transitionLog"] = %*[
      {"from": "unattempted", "to": "vacuous_contradiction"}
    ]
    var state = makeProofState(@[entry])
    let resetCount = resetForceHealQuarantine(state)
    check resetCount == 1

  test "does not reset entry with clean reason":
    var state = makeProofState(@[
      makeStateEntry("a::f1", "verified", reason = "clean proof")
    ])
    let resetCount = resetForceHealQuarantine(state)
    check resetCount == 0

  test "clears healCooldown, leanDiagnostics, bottleneckLog on reset":
    var state = makeProofState(@[
      makeStateEntry("a::f1", "timed_out",
        reason = "extractor_limitation",
        leanDiagnostics = "some diag",
        bottleneckLog = "some bottleneck",
        healCooldown = 5
      )
    ])
    discard resetForceHealQuarantine(state)
    check not state[entriesKey][0].hasKey("healCooldown")
    check not state[entriesKey][0].hasKey("leanDiagnostics")
    check not state[entriesKey][0].hasKey("bottleneckLog")

  test "resets multiple qualifying entries":
    var state = makeProofState(@[
      makeStateEntry("a::f1", "timed_out", reason = "extractor_limitation"),
      makeStateEntry("a::f2", "verified", reason = "clean proof"),
      makeStateEntry("a::f3", "timed_out", reason = "vacuous_primitive"),
    ])
    let resetCount = resetForceHealQuarantine(state)
    check resetCount == 2
    # Entry 2 should remain unchanged
    check state[entriesKey][1][statusKey].getStr() == "verified"
    check state[entriesKey][1][reasonKey].getStr() == "clean proof"

  test "version mismatch resets all non-exempt entries":
    var state = makeProofState(@[
      makeStateEntry("a::f1", "verified", reason = "clean proof"),
      makeStateEntry("a::f2", "timed_out", reason = "timeout"),
    ])
    state["metadata"] = %*{"engineVersionHash": "old-hash-abc"}
    let resetCount = resetForceHealQuarantine(state, "new-hash-def")
    check resetCount == 2
    check state[entriesKey][0][statusKey].getStr() == unattemptedKey
    check state[entriesKey][0][reasonKey].getStr() == "auto-invalidation:engine-version-changed"
    check state[entriesKey][0]["staleReason"].getStr() == "version-hash-mismatch-retry"

  test "version match does not trigger reset without quarantine":
    var state = makeProofState(@[
      makeStateEntry("a::f1", "verified", reason = "clean proof"),
    ])
    state["metadata"] = %*{"engineVersionHash": "same-hash"}
    let resetCount = resetForceHealQuarantine(state, "same-hash")
    check resetCount == 0

  test "version mismatch updates metadata engineVersionHash":
    var state = makeProofState(@[
      makeStateEntry("a::f1", "verified", reason = "clean proof"),
    ])
    state["metadata"] = %*{"engineVersionHash": "old"}
    discard resetForceHealQuarantine(state, "new")
    check state["metadata"]["engineVersionHash"].getStr() == "new"

  test "creates metadata if missing when version hash provided":
    var state = makeProofState(@[
      makeStateEntry("a::f1", "verified", reason = "clean proof"),
    ])
    discard resetForceHealQuarantine(state, "new-hash")
    check state.hasKey("metadata")
    check state["metadata"]["engineVersionHash"].getStr() == "new-hash"

  test "skips non-object entries in entries array":
    var state = %*{entriesKey: [
      makeStateEntry("a::f1", "verified", reason = "clean"),
      %*"not-an-object",
      makeStateEntry("a::f2", "verified", reason = "clean"),
    ]}
    let resetCount = resetForceHealQuarantine(state)
    check resetCount == 0

# ════════════════════════════════════════════════════════════════════════════
# applyCertifiedExemptionsFromSource -- filesystem + source inspection
# ════════════════════════════════════════════════════════════════════════════

suite "applyCertifiedExemptionsFromSource":

  test "returns 0 for non-object state":
    var state = %*"not-object"
    let count = applyCertifiedExemptionsFromSource(state, "/tmp")
    check count == 0

  test "returns 0 when entries key missing":
    var state = %*{"metadata": {}}
    let count = applyCertifiedExemptionsFromSource(state, "/tmp")
    check count == 0

  test "skips entries with empty modulePath or functionName":
    var state = makeProofState(@[
      makeStateEntry("a::f1", "verified", modulePath = "", functionName = "foo"),
    ])
    let count = applyCertifiedExemptionsFromSource(state, "/tmp")
    check count == 0

  test "skips entries when source file does not exist":
    var state = makeProofState(@[
      makeStateEntry("a::f1", "verified",
        modulePath = "nonexistent/module.nim",
        functionName = "foo"),
    ])
    let count = applyCertifiedExemptionsFromSource(state, "/tmp")
    check count == 0

  test "exempts entry with axiom pragma in source":
    let tmpDir = getTempDir() / "axiom_test_exemptions"
    let srcDir = tmpDir / "src"
    createDir(srcDir)
    let srcFile = srcDir / "mod.nim"
    writeFile(srcFile, "func foo*() {.axiom.} = discard\n")
    var state = makeProofState(@[
      makeStateEntry("a::f1", "timed_out",
        modulePath = "src/mod.nim",
        functionName = "foo"),
    ])
    let count = applyCertifiedExemptionsFromSource(state, tmpDir)
    check count == 1
    check state[entriesKey][0][statusKey].getStr() == certifiedExemptStatus
    check state[entriesKey][0]["attempted"].getBool() == true
    check state[entriesKey][0]["exemptionReason"].getStr() == "axiom-pure-or-vacuous-primitive"
    # Cleanup
    removeFile(srcFile)
    removeDir(srcDir)
    removeDir(tmpDir)

  test "does not exempt entry with non-axiom source":
    let tmpDir = getTempDir() / "axiom_test_no_exemption"
    removeDir(tmpDir)
    let srcDir = tmpDir / "src"
    createDir(srcDir)
    let srcFile = srcDir / "mod2.nim"
    writeFile(srcFile, "let x = 1\n")
    var state = makeProofState(@[
      makeStateEntry("a::f1", "timed_out",
        modulePath = "src/mod2.nim",
        functionName = "foo"),
    ])
    let count = applyCertifiedExemptionsFromSource(state, tmpDir)
    check count == 0
    check state[entriesKey][0][statusKey].getStr() == "timed_out"
    # Cleanup
    removeFile(srcFile)
    removeDir(srcDir)
    removeDir(tmpDir)

  test "removes healCooldown when exempting":
    let tmpDir = getTempDir() / "axiom_test_heal_cooldown"
    let srcDir = tmpDir / "src"
    createDir(srcDir)
    let srcFile = srcDir / "mod3.nim"
    writeFile(srcFile, "func bar*() {.axiom.} = discard\n")
    var state = makeProofState(@[
      makeStateEntry("a::f1", "timed_out",
        modulePath = "src/mod3.nim",
        functionName = "bar",
        healCooldown = 10),
    ])
    discard applyCertifiedExemptionsFromSource(state, tmpDir)
    check not state[entriesKey][0].hasKey("healCooldown")
    # Cleanup
    removeFile(srcFile)
    removeDir(srcDir)
    removeDir(tmpDir)

  test "skips non-object entries in array":
    var state = %*{entriesKey: [
      makeStateEntry("a::f1", "timed_out",
        modulePath = "nonexistent/module.nim",
        functionName = "baz"),
      %*"not-an-object",
    ]}
    let count = applyCertifiedExemptionsFromSource(state, "/tmp")
    check count == 0

# ════════════════════════════════════════════════════════════════════════════
# persistAxProofState -- filesystem persistence
# ════════════════════════════════════════════════════════════════════════════

suite "persistAxProofState":

  test "creates directory if missing and writes file":
    let tmpDir = getTempDir() / "axiom_test_persist"
    let statePath = tmpDir / "proof_state.json"
    removeDir(tmpDir)
    var reportNode = %*{"entries": [], "summary": {"totalNodes": 0}}
    let res = persistAxProofState(statePath, reportNode)
    check res.isOk()
    check fileExists(statePath)
    # Verify file content is valid JSON
    let content = readFile(statePath)
    let parsed = parseJson(content)
    check parsed.kind == JObject
    # Cleanup
    removeFile(statePath)
    removeDir(tmpDir)

  test "overwrites existing file":
    let tmpDir = getTempDir() / "axiom_test_persist_overwrite"
    createDir(tmpDir)
    let statePath = tmpDir / "state.json"
    writeFile(statePath, "old content")
    var reportNode = %*{"entries": [], "summary": {"totalNodes": 0}}
    let res = persistAxProofState(statePath, reportNode)
    check res.isOk()
    let content = readFile(statePath)
    check content != "old content"
    # Cleanup
    removeFile(statePath)
    removeDir(tmpDir)

  test "returns ok with the state path on success":
    let tmpDir = getTempDir() / "axiom_test_persist_ok"
    let statePath = tmpDir / "ok.json"
    var reportNode = %*{"entries": []}
    let res = persistAxProofState(statePath, reportNode)
    check res.isOk()
    let pathResult = res.get()
    check pathResult == statePath
    # Cleanup
    removeFile(statePath)
    removeDir(tmpDir)

# ════════════════════════════════════════════════════════════════════════════
# semanticEntryDependencyMismatchReason -- JSON traversal + filesystem
# ════════════════════════════════════════════════════════════════════════════

suite "semanticEntryDependencyMismatchReason":

  test "returns empty when no semanticProof":
    let entry = %*{"status": "verified"}
    let reason = semanticEntryDependencyMismatchReason(entry)
    check reason == ""

  test "returns empty when semanticProof is not JObject":
    let entry = %*{"semanticProof": "string"}
    let reason = semanticEntryDependencyMismatchReason(entry)
    check reason == ""

  test "returns empty when no universalPipeline":
    let entry = %*{"semanticProof": {"engine": "z3"}}
    let reason = semanticEntryDependencyMismatchReason(entry)
    check reason == ""

  test "returns empty when no dependencyContext":
    let entry = %*{
      "semanticProof": {
        "universalPipeline": {
          "smtTrack": {modulePathKey: "foo.nim"}
        }
      }
    }
    let reason = semanticEntryDependencyMismatchReason(entry)
    check reason == ""

  test "returns empty when no smtTrack":
    let entry = %*{
      "semanticProof": {
        "universalPipeline": {
          "dependencyContext": {"symbolChecksums": []}
        }
      }
    }
    let reason = semanticEntryDependencyMismatchReason(entry)
    check reason == ""

  test "returns empty when modulePath is empty in smtTrack":
    let entry = %*{
      "semanticProof": {
        "universalPipeline": {
          "dependencyContext": {"symbolChecksums": []},
          "smtTrack": {modulePathKey: ""}
        }
      }
    }
    let reason = semanticEntryDependencyMismatchReason(entry)
    check reason == ""

  test "returns empty when symbolChecksums is missing":
    let entry = %*{
      "semanticProof": {
        "universalPipeline": {
          "dependencyContext": {},
          "smtTrack": {modulePathKey: "some.nim"}
        }
      }
    }
    let reason = semanticEntryDependencyMismatchReason(entry)
    check reason == ""

  test "returns dependency missing when file does not exist":
    let entry = %*{
      "semanticProof": {
        "universalPipeline": {
          "dependencyContext": {
            "symbolChecksums": [
              {"symbol": "/nonexistent/file.nim", "checksum": "abc123"}
            ]
          },
          "smtTrack": {modulePathKey: "/nonexistent/file.nim"}
        }
      }
    }
    let reason = semanticEntryDependencyMismatchReason(entry)
    check reason.startsWith("dependency missing:")

  test "returns empty when no matching checksum entry for modulePath":
    let entry = %*{
      "semanticProof": {
        "universalPipeline": {
          "dependencyContext": {
            "symbolChecksums": [
              {"symbol": "other.nim", "checksum": "abc123"}
            ]
          },
          "smtTrack": {modulePathKey: "target.nim"}
        }
      }
    }
    let reason = semanticEntryDependencyMismatchReason(entry)
    check reason == ""

  test "returns checksum mismatch when file content differs":
    let tmpDir = getTempDir() / "axiom_test_checksum"
    createDir(tmpDir)
    let testFile = tmpDir / "check.nim"
    writeFile(testFile, "let x = 1\n")
    let entry = %*{
      "semanticProof": {
        "universalPipeline": {
          "dependencyContext": {
            "symbolChecksums": [
              {"symbol": testFile, "checksum": "WRONG_CHECKSUM"}
            ]
          },
          "smtTrack": {modulePathKey: testFile}
        }
      }
    }
    let reason = semanticEntryDependencyMismatchReason(entry)
    check reason.startsWith("dependency checksum mismatch:")
    # Cleanup
    removeFile(testFile)
    removeDir(tmpDir)

{.pop.}
