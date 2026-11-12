## Phase 3-G — R8 prepare-sequence machine verification (contract §10.6).
##
## Targets the R8 gate in tools/readiness_evaluator.nim: the contract-fixed
## Rust subject prepare order (`cargo fetch --locked` → `cargo metadata
## --format-version=1 --locked` → `cargo build --frozen`) must be
## machine-verified from the evidence envelope's §4 `commands` array —
## exact cmd match, required relative order, exitCode 0. Missing /
## out-of-order / nonzero-exit / duplicated / malformed / fully-absent
## commands all FAIL toward NOT GO, with reasons read back through
## r8SequenceViolations (the trustLaneViolations consumer pattern).
##
## Run from repo root:
##   nim c -r --hints:off --nimcache:/tmp/axiom_r8_nimcache \
##       tests/readiness/readiness_r8_sequence_test.nim

import std/[json, unittest, strutils, os, sequtils]
import ../../tools/readiness_evaluator

# Test lives at tests/readiness/, so repo root is three parentDir() levels up.
const REPO_ROOT = currentSourcePath().parentDir().parentDir().parentDir()

proc loadPolicy(): JsonNode =
  let path = "config/readiness_policy.json"
  if fileExists(path):
    parseFile(path)
  else:
    parseFile(REPO_ROOT / path)

let POLICY = loadPolicy()

# ── Envelope construction helpers ───────────────────────────────────────────

proc r8Envelope(commands: JsonNode): JsonNode =
  ## A valid R8 evidence envelope; `commands` is the §4 envelope-level array
  ## (nil = the key is absent entirely).
  result = %*{
    "schemaVersion": 1,
    "invariantId": "R8",
    "collection": {
      "collector": "tests/readiness/readiness_r8_sequence_test.nim",
      "method": "synthetic",
      "generatedAt": "2026-08-01T00:00:00Z",
      "freshUntil": "2027-08-01T00:00:00Z"
    },
    "observations": [
      {"key": "installFollowed", "value": true, "scope": "", "subject": ""},
      {"key": "manualStepsRequired", "value": false, "scope": "", "subject": ""},
      {"key": "cleanRunSucceeded", "value": true, "scope": "", "subject": ""},
      {"key": "documentedRunSteps", "value": true, "scope": "", "subject": ""}
    ],
    "sources": [
      {"file": "tests/readiness/readiness_r8_sequence_test.nim", "lines": "1",
       "symbol": "R8", "sha256": "sha256:synthetic", "repoHead": "synthetic"}
    ]
  }
  if commands != nil:
    result["commands"] = commands

proc commandsOf(steps: varargs[tuple[c: string, x: int]]): JsonNode =
  ## §4 commands entries: {"cmd", "exitCode", "outputDigest"} — the shape
  ## tools/collect_evidence_probe.nim records.
  result = newJArray()
  for s in steps:
    result.add(%*{"cmd": s.c, "exitCode": s.x,
                  "outputDigest": "sha256:synthetic-" & s.c.replace(" ", "-")})

proc mergedOf(lists: varargs[JsonNode]): JsonNode =
  ## The merged bundle shape r8SequenceViolations consumes: one inner array
  ## per evidence envelope, in evidence order (normalizeBundle output).
  result = newJArray()
  for l in lists:
    result.add(l)

proc evaluatedR8(commands: JsonNode): tuple[state: string, reasons: seq[string]] =
  ## normalize -> evaluate; returns R8's state plus the gate's own reasons
  ## read back off the merged bundle node.
  let bundle = readiness_evaluator.normalizeBundle(@[r8Envelope(commands)]).get
  let d = readiness_evaluator.evaluateReadiness(POLICY, bundle)
  result.state = d.invariantStates["R8"].getStr()
  result.reasons = readiness_evaluator.r8SequenceViolations(
    bundle{"invariants"}{"R8"}{"commands"}, POLICY)

proc fetchStep(): tuple[c: string, x: int] =
  ("cargo fetch --locked", 0)

proc metadataStep(): tuple[c: string, x: int] =
  ("cargo metadata --format-version=1 --locked", 0)

proc buildStep(): tuple[c: string, x: int] =
  ("cargo build --frozen", 0)

# ── Fixture helpers (duplicated from readiness_policy_test on purpose: im-
#    porting that module would re-run its suites inside this binary) ─────────

proc loadFixture(): JsonNode =
  parseFile(currentSourcePath().parentDir() / "fixtures" / "synthetic_bundle.json")

proc setFixtureVkd(fixture: JsonNode, coverage: float) =
  for e in fixture.items:
    if e["invariantId"].getStr() == "R7":
      for o in e["observations"].items:
        if o["key"].getStr() == "measuredCoverage":
          o["value"] = %coverage
          return
  doAssert false, "fixture has no R7 measuredCoverage"

proc stripFixtureCommands(fixture: JsonNode) =
  for e in fixture.items:
    if e["invariantId"].getStr() == "R8":
      e.delete("commands")
      return
  doAssert false, "fixture has no R8 envelope"

# ══════════════════════════════════════════════════════════════════════════════
# Suite — R8 prepare-sequence gate (§10.6)
# ══════════════════════════════════════════════════════════════════════════════

suite "Phase 3-G — R8 prepare-sequence machine verification":

  test "valid sequence in required order, exit 0 -> R8 PASS":
    let r = evaluatedR8(commandsOf(fetchStep(), metadataStep(), buildStep()))
    check r.state == "PASS"
    check r.reasons.len == 0
    echo "  [r8-seq] fetch -> metadata -> build (exit 0) -> PASS"

  test "valid sequence contributes to the GO path (fixture, vkd lifted)":
    let fixture = loadFixture()
    setFixtureVkd(fixture, 0.8)
    let bundle = readiness_evaluator.normalizeBundle(
      readiness_evaluator.loadEvidenceFromJson(fixture)).get
    let d = readiness_evaluator.evaluateReadiness(POLICY, bundle)
    check d.invariantStates["R8"].getStr() == "PASS"
    check d.verdict == "GO"
    echo "  [r8-seq] fixture with contract sequence -> R8 PASS, verdict GO"

  test "fixture without the sequence loses GO (gate is load-bearing)":
    let fixture = loadFixture()
    setFixtureVkd(fixture, 0.8)
    stripFixtureCommands(fixture)
    let bundle = readiness_evaluator.normalizeBundle(
      readiness_evaluator.loadEvidenceFromJson(fixture)).get
    let d = readiness_evaluator.evaluateReadiness(POLICY, bundle)
    check d.invariantStates["R8"].getStr() == "FAIL"
    check d.verdict == "NO-GO"
    check d.outcome == "BLOCK"
    check d.failureCategory == "CONTRACT_FAIL"
    echo "  [r8-seq] same fixture minus commands -> R8 FAIL, verdict NO-GO"

  test "missing metadata step -> FAIL, reason names the command":
    let r = evaluatedR8(commandsOf(fetchStep(), buildStep()))
    check r.state == "FAIL"
    check r.reasons.len == 1
    check r.reasons[0].contains("'cargo metadata --format-version=1 --locked' missing")
    check r.reasons[0].contains("(no GO)")
    echo "  [r8-seq] missing metadata -> FAIL: " & r.reasons[0]

  test "wrong order -> FAIL with out-of-order reasons":
    let r = evaluatedR8(commandsOf(fetchStep(), buildStep(), metadataStep()))
    check r.state == "FAIL"
    check r.reasons.len == 2
    check r.reasons.allIt(it.contains("out of order"))
    check r.reasons.anyIt(it.contains(
      "'cargo metadata --format-version=1 --locked' expected at position 2"))
    check r.reasons.anyIt(it.contains(
      "'cargo build --frozen' expected at position 3"))
    echo "  [r8-seq] build before metadata -> FAIL with 2 order reasons"

  test "nonzero exit -> FAIL, exit 0 required":
    var bad = buildStep()
    bad.x = 1
    let r = evaluatedR8(commandsOf(fetchStep(), metadataStep(), bad))
    check r.state == "FAIL"
    check r.reasons.len == 1
    check r.reasons[0].contains("'cargo build --frozen' exits 1")
    check r.reasons[0].contains("exit 0 required")
    echo "  [r8-seq] build exit 1 -> FAIL: " & r.reasons[0]

  test "absent commands observation -> FAIL (never silently skipped)":
    let absent = evaluatedR8(nil)
    check absent.state == "FAIL"
    check absent.reasons == @["prepare sequence: no commands recorded in R8 evidence (no GO)"]
    # an explicit empty commands array is the same fact
    let empty = evaluatedR8(newJArray())
    check empty.state == "FAIL"
    check empty.reasons.len == 1
    check empty.reasons[0].contains("empty commands list")
    echo "  [r8-seq] absent/empty commands -> FAIL (fail-closed)"

  test "commands outside the prepare sequence are tolerated":
    let r = evaluatedR8(commandsOf(
      ("bin/ax --version", 0), fetchStep(), metadataStep(), buildStep(),
      ("cargo test --locked", 0)))
    check r.state == "PASS"
    check r.reasons.len == 0
    echo "  [r8-seq] extra non-prepare commands recorded -> still PASS"

  test "duplicated required command -> FAIL":
    let r = evaluatedR8(commandsOf(fetchStep(), metadataStep(), buildStep(),
                                   fetchStep()))
    check r.state == "FAIL"
    check r.reasons.len == 1
    check r.reasons[0].contains("'cargo fetch --locked' recorded 2 times")
    check r.reasons[0].contains("expected exactly once")
    echo "  [r8-seq] duplicate fetch -> FAIL: " & r.reasons[0]

  test "malformed exitCode -> FAIL":
    let cmds = newJArray()
    for s in [fetchStep(), metadataStep()]:
      cmds.add(%*{"cmd": s.c, "exitCode": s.x, "outputDigest": "sha256:synthetic"})
    cmds.add(%*{"cmd": "cargo build --frozen", "exitCode": "zero",
                "outputDigest": "sha256:synthetic"})
    let r = evaluatedR8(cmds)
    check r.state == "FAIL"
    check r.reasons.anyIt(it.contains("has no integer exitCode"))
    echo "  [r8-seq] non-integer exitCode -> FAIL (fail-closed)"

  test "sequence is policy-driven (r8.prepareSequenceCommands), fallback anchored":
    let custom = %*{"r8": {"prepareSequenceCommands": ["alpha step", "beta step"]}}
    check readiness_evaluator.r8SequenceViolations(
      mergedOf(commandsOf(("alpha step", 0), ("beta step", 0))), custom).len == 0
    # empty/missing policy -> the §10.6 strings anchor the gate (never empty)
    check readiness_evaluator.r8SequenceViolations(
      mergedOf(commandsOf(("alpha step", 0), ("beta step", 0))),
      newJObject()).len > 0
    check readiness_evaluator.r8SequenceViolations(
      mergedOf(commandsOf(fetchStep(), metadataStep(), buildStep())),
      newJObject()).len == 0
    echo "  [r8-seq] policy read live; contract strings remain the fallback"

  test "commands enter the canonical evidence identity (bundleDigest)":
    let withC = readiness_evaluator.normalizeBundle(
      @[r8Envelope(commandsOf(fetchStep(), metadataStep(), buildStep()))]).get
    let withoutC = readiness_evaluator.normalizeBundle(@[r8Envelope(nil)]).get
    check withC{"invariants"}{"R8"}.hasKey("commands")
    check withC["bundleDigest"].getStr() != withoutC["bundleDigest"].getStr()
    echo "  [r8-seq] merged R8 node carries commands; digest sensitive to it"

  test "two R8 envelopes: one invalid list fails the gate (fail-closed)":
    let good = r8Envelope(commandsOf(fetchStep(), metadataStep(), buildStep()))
    let bad = r8Envelope(commandsOf(fetchStep(), buildStep()))
    let bundle = readiness_evaluator.normalizeBundle(@[good, bad]).get
    check bundle{"invariants"}{"R8"}{"commands"}.len == 2
    let d = readiness_evaluator.evaluateReadiness(POLICY, bundle)
    check d.invariantStates["R8"].getStr() == "FAIL"
    check d.verdict == "NO-GO"
    echo "  [r8-seq] valid + invalid envelope pair -> FAIL (every list must hold)"
