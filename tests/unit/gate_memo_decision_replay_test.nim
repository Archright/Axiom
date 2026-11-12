## gate_memo_decision_replay_test.nim
## DEBT#471 — Decision Replay Integrity (Memo Closure Identity slice).
##
## Business scenarios under contract:
##   1. Key closure — the composite memo key binds the scan-scope/staged axes
##      and carries the producing gate's hash; same content under a different
##      scan scope must NEVER replay an entry recorded under another scope.
##   2. Structured value — a memo FAIL stores finding coordinates
##      (file · line · detail), not quoted stdout prose.
##   3. Read-time re-render — a memo HIT is rendered by the CURRENT formatter
##      from stored findings; past prose is never re-emitted as authority.
##   4. Daemon guard — the daemon checkCache consumption path applies the same
##      classifyMemoOutcome verdict-axis semantics as the CAS layer.

import std/[unittest, os, strutils, times, json, options]
import core/crypto/hash_kernel  # sha256Hex (empty-change-set constant); slice_hash re-exports its own
import core/gate/gate_memo
import core/types/gate_types
import gate/orchestrator/hook/memo  # computeScopeAxisDigest, daemonMemoVerdict
import gate/slice_hash              # InputSlice construction
import gate/gate_contract           # InputSliceKind (skFilesPattern)

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario 1: Key closure (scan-scope / staged axes)
# A memo key names one evaluation: which scope was scanned and what staged set
# was observed. Two evaluations that differ in either axis must not share a key.
# ══════════════════════════════════════════════════════════════════════════════

suite "DEBT#471 key closure: gateHash slot + scan-scope/staged axes":
  test "gateHash slot is consumed — different producing gates never share a key":
    # Pre-fix regression: the hook memo passed an already-resolved digest into
    # a path-expecting slot, so fileExists(digest) was false and the gateHash
    # component collapsed to "" — two different digests produced ONE key.
    let kA = computeCompositeLockHash("same-input", "gatehash-a",
                                      "/repo", "", "", "", "", "")
    let kB = computeCompositeLockHash("same-input", "gatehash-b",
                                      "/repo", "", "", "", "", "")
    check kA != kB

  test "same gateHash and inputs produce the same key (deterministic)":
    let k1 = computeCompositeLockHash("same-input", "gatehash-a",
                                      "/repo", "subtree", "bin", "env", "trans", "scope")
    let k2 = computeCompositeLockHash("same-input", "gatehash-a",
                                      "/repo", "subtree", "bin", "env", "trans", "scope")
    check k1 == k2

  test "scope axis digest separates distinct scan scopes":
    let srcScope = InputSlice(kind: skFilesPattern, paths: @["src/"], excludePatterns: @[])
    let docsScope = InputSlice(kind: skFilesPattern, paths: @["docs/"], excludePatterns: @[])
    check computeScopeAxisDigest(srcScope, @[]) != computeScopeAxisDigest(docsScope, @[])

  test "staged axis digest separates staged=0 from staged=1 under one scope":
    let srcScope = InputSlice(kind: skFilesPattern, paths: @["src/"], excludePatterns: @[])
    check computeScopeAxisDigest(srcScope, @[]) !=
          computeScopeAxisDigest(srcScope, @["docs/evidence/a.md"])

  test "staged axis digest is order-insensitive (sorted) and stable":
    let srcScope = InputSlice(kind: skFilesPattern, paths: @["src/"], excludePatterns: @[])
    check computeScopeAxisDigest(srcScope, @["b.nim", "a.nim"]) ==
          computeScopeAxisDigest(srcScope, @["a.nim", "b.nim"])

  test "staged aliasing repro: constant filtered hash across scopes yields distinct keys":
    # The DEBT#471 repro shape: computeSliceHash over an empty filtered set
    # produces sha256("") for ANY scope — pre-fix both evaluations shared one
    # memo key and a staged=0 FAIL replayed for a staged=1 run.
    let emptyInputHash = hash_kernel.sha256Hex("")
    let srcScope = InputSlice(kind: skFilesPattern, paths: @["src/"], excludePatterns: @[])
    let docsScope = InputSlice(kind: skFilesPattern, paths: @["docs/"], excludePatterns: @[])
    let keyStaged0SrcScan = computeCompositeLockHash(
      emptyInputHash, "gatehash-tcs", "/repo", "", "", "", "",
      computeScopeAxisDigest(srcScope, @[]))
    let keyStaged1DocsScan = computeCompositeLockHash(
      emptyInputHash, "gatehash-tcs", "/repo", "", "", "", "",
      computeScopeAxisDigest(docsScope, @["docs/evidence/a.md"]))
    check keyStaged0SrcScan != keyStaged1DocsScan

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario 2: Structured value — findings, not prose
# ══════════════════════════════════════════════════════════════════════════════

const trustCommitScopeStyleOutput* = """trust-commit-scope: 2 direct-write(s) found (must route through trust-commit allowlist):
  src/verification/vault_index.nim:124 — writeFileOpt(path, journal)
  src/other/module.nim:7 — writeFile(dest, data)
"""

suite "DEBT#471 structured value: finding coordinates from gate output":
  test "coordinate lines are mined; prose headers are not":
    let findings = parseFindingsFromOutput(trustCommitScopeStyleOutput)
    check findings.len == 2
    check findings[0].file == "src/verification/vault_index.nim"
    check findings[0].line == 124
    check findings[0].detail == "writeFileOpt(path, journal)"
    check findings[1].file == "src/other/module.nim"
    check findings[1].line == 7

  test "plain path:line: message format is mined":
    let findings = parseFindingsFromOutput("FAIL\nsrc/a.nim:42: import cycle detected\n")
    check findings.len == 1
    check findings[0].file == "src/a.nim"
    check findings[0].line == 42
    check findings[0].detail == "import cycle detected"

  test "non-finding output yields no findings":
    check parseFindingsFromOutput("").len == 0
    check parseFindingsFromOutput("PASS: all clean\n").len == 0
    check parseFindingsFromOutput("trust-commit-scope: 0 direct-write(s) found\n").len == 0

  test "renderMemoFindings renders coordinates in current vocabulary":
    let findings = parseFindingsFromOutput(trustCommitScopeStyleOutput)
    let rendered = renderMemoFindings(findings)
    check rendered == "src/verification/vault_index.nim:124 (writeFileOpt(path, journal)); " &
                      "src/other/module.nim:7 (writeFile(dest, data))"

  test "empty findings render to empty string":
    check renderMemoFindings(@[]) == ""

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario 3: Read-time re-render — past prose never replays
# ══════════════════════════════════════════════════════════════════════════════

suite "DEBT#471 read-time re-render: prose is not authority":
  proc makeMemoTmpDir(prefix: string): string =
    let tmpDir = getTempDir() / (prefix & $epochTime().int)
    createDir(tmpDir / ".axiom" / "cache" / "gate_memo")
    return tmpDir

  test "structured entry stores findings; replay renders coordinates, not prose":
    let tmpDir = makeMemoTmpDir("axiom_memo_dr_")
    let savedDir = getCurrentDir()
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    let gateId = "dr-gate"
    let lockHash = "dr-lock-1"
    let findings: seq[MemoFinding] = @[("src/verification/vault_index.nim", 124,
                                        "writeFileOpt(path, journal)")]
    saveGateMemo(gateId, lockHash, false, 0, fcValidation,
                 "2 direct durable evidence write(s) found outside the trust-commit allowlist",
                 findings)
    let loaded = loadGateMemo(gateId, lockHash, 0)
    check loaded.isSome
    check loaded.get.result == false
    check loaded.get.findings.len == 1
    check loaded.get.findings[0].file == "src/verification/vault_index.nim"
    # The replay surface is the CURRENT rendering of the coordinates:
    let replayed = renderMemoFindings(loaded.get.findings)
    check replayed.contains("vault_index.nim:124")
    check replayed.contains("writeFileOpt(path, journal)")

  test "legacy prose entry: verdict persists, prose never re-emitted":
    let tmpDir = makeMemoTmpDir("axiom_memo_dr_legacy_")
    let savedDir = getCurrentDir()
    setCurrentDir(tmpDir)
    defer: setCurrentDir(savedDir)
    defer: removeDir(tmpDir)

    # A pre-fix entry: prose reason, no findings field (legacy layout).
    let gateId = "dr-legacy-gate"
    let lockHash = "dr-legacy-lock"
    let epochDir = joinPath(getCurrentDir(), GateMemoBaseDir, "epoch_0")
    let casJson = %*{
      "gateId": gateId,
      "compositeLockHash": lockHash,
      "result": false,
      "timestamp": getTime().toUnix(),
      "epoch": 0,
      "expiresAt": 0,
      "failureCategory": $fcValidation,
      "failureReason": "FAIL: vault_index.nim:124 — writeFileOpt(path, journal) must route through trust-commit"
    }
    # Save through saveGateMemo to inherit the CAS layout, then rewrite the
    # entry as its legacy shape (no findings array).
    saveGateMemo(gateId, lockHash, true, 0)
    writeFile(joinPath(epochDir, gateId & ".json"), $casJson & "\n")
    # The legacy path ignores compositeLockHash — but for THIS scenario we
    # read the legacy record directly to pin its semantics.
    let loaded = loadLegacyGateMemo(gateId, 0)
    check loaded.isSome  # verdict survives under the prose-evidence rule
    check loaded.get.findings.len == 0
    # Read-time closure: nothing to re-render from coordinates → the past
    # prose is never re-emitted as the replayed reason.
    check renderMemoFindings(loaded.get.findings) == ""
    check renderMemoFindings(loaded.get.findings) != loaded.get.failureReason

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario 4: Daemon guard — one verdict axis across all memo sinks
# ══════════════════════════════════════════════════════════════════════════════

suite "DEBT#471 daemon guard: checkCache consumes verdicts only":
  test "unevaluated outcomes are never consumed as cache hits":
    # tool failure (fcPermanent), unclassifiable (fcUnknown), and evidence-free
    # FAILs are execution states — the same rule the CAS layer enforces via
    # classifyMemoOutcome.
    check daemonMemoVerdict(false, $fcPermanent, "compile failed") == moNotEvaluated
    check daemonMemoVerdict(false, $fcUnknown, "theater detection") == moNotEvaluated
    check daemonMemoVerdict(false, $fcValidation, "") == moNotEvaluated
    check daemonMemoVerdict(false, $fcTransient, "   ") == moNotEvaluated

  test "evidenced verdicts are consumable":
    check daemonMemoVerdict(false, $fcValidation, "import cycle") == moVerdictFail
    check daemonMemoVerdict(false, $fcTransient, "network timeout") == moVerdictFail
    check daemonMemoVerdict(true, $fcTransient, "") == moVerdictPass

  test "unknown category string fails closed to fcTransient (then judged)":
    check daemonMemoVerdict(false, "bogus-category", "evidence") == moVerdictFail
    check daemonMemoVerdict(false, "bogus-category", "") == moNotEvaluated
