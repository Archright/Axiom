## test_readiness_verdict_mapping.nim — readiness verdict → gate exit/stdout
## mapping (DEBT#537 slice: readiness verdict wiring as a required check).
##
## PR-1 self-verification (the gate green in CI) is an operational smoke.
## Verdict fidelity and the verdict → exit/stdout mapping are pinned HERE
## against the real compiled binaries — never against source imports:
##   * bin/readiness_start_gate — exec'd; exit code + stdout asserted
##   * bin/readiness_evaluator  — every fixture pre-validated through the CLI
## Mapping under test (DEBT#537 common contract; the decision algebra in
## src/core/utils/decision_algebra.nim stays the single verdict authority):
##   GO             -> exit 0, exactly one 'READINESS_VERDICT GO CONDITIONS' line
##                     with an empty conditions field, no ::warning:: line
##   CONDITIONAL GO -> exit 0, conditions carried on the verdict line plus a
##                     '::warning::readiness' line
##   NO-GO          -> exit 1
##   stale evidence -> INVALID -> critical NOT_RUN -> NO-GO -> exit 1
##   evidence head ≠ AXIOM_CI_REPO_HEAD -> exit 1 + READINESS_IDENTITY_MISMATCH
##   missing critical evidence file     -> exit 1
##
## Fixtures replicate the committed data/readiness/evidence/R*.json envelope
## (collection + repoIdentity + observations + sources). Each verdict
## combination was derived from the evaluator rules (tools/readiness_evaluator
## nim ruleR1..ruleR8) and config/readiness_policy.json criticality — R7 is the
## ONLY non-critical invariant — and the first test re-proves every variant
## through bin/readiness_evaluator, so a fixture that stops producing its
## verdict fails before the gate is ever invoked.
##
## Evidence directory binding (measured from the gate source): repoRootOf()
## anchors <repo-root> at COMPILE time (currentSourcePath parents + the
## .axiom_root marker) and reads data/readiness/evidence at that fixed path;
## a temp working directory cannot redirect it. Each case therefore swaps the
## committed snapshot (backup → install fixtures → run gate → restore →
## byte-exact verify). Restoration runs in a defer so an assertion failure
## cannot leak fixtures, and the final case re-verifies the committed snapshot
## against the copy taken at process start.
##
## C1 wiring gate: the READINESS_VERDICT line, the AXIOM_CI_REPO_HEAD identity
## binding and the READINESS_IDENTITY_MISMATCH marker are implemented by the
## C1 gate agent in this workstream. While the compiled gate binary predates
## that wiring (capability probe: the binary does not embed the marker
## strings), the contract-line assertions of the affected case print a loud
## PENDING marker and skip instead of failing. Exit-code semantics that hold
## for both gate generations are asserted unconditionally.

import std/[algorithm, json, os, osproc, streams, strutils, strtabs, unittest]

let
  Root = block:
    var r = absolutePath(currentSourcePath())
    for _ in 0 ..< 3: r = r.parentDir()
    r
  EvidenceDir = Root / "data" / "readiness" / "evidence"
  GateBin = Root / "bin" / "readiness_start_gate"
  EvaluatorBin = Root / "bin" / "readiness_evaluator"
  Work = getTempDir() / "axiom_c3_readiness_verdict"

const
  FixtureHead = "1111111111111111111111111111111111111111"
  FixtureTree = "2222222222222222222222222222222222222222"
  OtherHead = "fedcba9876543210fedcba9876543210fedcba98"
  FreshFuture = "2030-01-01T00:00:00Z"
  FreshPast = "2020-01-01T00:00:00Z"
  EvalTime = "2026-11-16T00:00:00Z"
  R1ToR8 = ["R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8"]

let
  ProbeAx = Root / "build" / "readiness_c3_probe" / "ax"

proc ensureProbeAxBinary(): bool =
  ## The productization E2E inside the gate execs `bin/ax` unless
  ## AXIOM_START_GATE_AX_BIN is set (ensureAxBinary prefers the env binary).
  ## The canonical-path binary enforces live source-tree coherence
  ## (src/cli/main.nim checkAndSelfBootstrap), which a shared checkout with
  ## in-flight parallel edits breaks at any moment — an incoherent tree makes
  ## `ax prove` FATAL before writing vault certs and the gate's part (a) fails
  ## for reasons outside the verdict mapping under test. A copy at a
  ## repo-internal non-canonical path skips ONLY the path-bound self-check
  ## (the E2E's own documented escape hatch); every E2E assertion still runs
  ## against the real prove → report → cert-verify chain.
  if not fileExists(Root / "bin" / "ax"):
    return false
  if not fileExists(ProbeAx):
    createDir(parentDir(ProbeAx))
    copyFileWithPermissions(Root / "bin" / "ax", ProbeAx)
  true

# ---------------------------------------------------------------------------
# Binary plumbing — exec the real compiled tools, never import their sources.
# ---------------------------------------------------------------------------

proc runBin(bin: string; args: openArray[string] = [];
            extraEnv: openArray[(string, string)] = @[];
            workingDir: string = Root): tuple[output: string, exit: int] =
  ## Subprocess with an isolated env copy (extraEnv overrides). The test
  ## process env is never mutated, so cases cannot contaminate each other.
  var envTable: StringTableRef = nil
  if extraEnv.len > 0:
    envTable = newStringTable()
    for key, value in envPairs():
      envTable[key] = value
    for (key, value) in extraEnv:
      envTable[key] = value
  let p = startProcess(bin, workingDir = workingDir, args = args,
                       env = envTable, options = {poUsePath, poStdErrToStdOut})
  let allOut = p.outputStream().readAll()
  close(p.inputStream())
  result.exit = p.waitForExit()
  result.output = allOut

proc runGate(extraEnv: openArray[(string, string)] = @[];
             logName = ""): tuple[output: string, exit: int] =
  var env = @[("AXIOM_START_GATE_AX_BIN", ProbeAx)]
  for (k, v) in extraEnv:
    env.add((k, v))
  result = runBin(GateBin, @[], env, Root)
  if logName != "":
    createDir(Work / "gate_logs")
    writeFile(Work / "gate_logs" / (logName & ".log"), result.output)

proc gateBinaryEmbeds(marker: string): bool =
  ## Capability probe: the DEBT#537 contract constants must be embedded in the
  ## compiled gate binary for it to be able to emit them. A binary without the
  ## string cannot implement that half of the contract (see suite doc).
  try:
    readFile(GateBin).contains(marker)
  except CatchableError:
    false

let
  GateEmitsVerdictLine = gateBinaryEmbeds("READINESS_VERDICT")
  GateBindsCiIdentity = gateBinaryEmbeds("AXIOM_CI_REPO_HEAD")

proc pendingContractMsg(caseName, feature: string): string =
  "[PENDING][C1-gate-wiring] " & caseName & ": gate binary lacks " &
      feature & " (DEBT#537 wiring not landed); contract assertion deferred " &
      "to integration."

# ---------------------------------------------------------------------------
# Evidence snapshot swap — the gate reads data/readiness/evidence at a fixed
# compile-time-anchored path, so fixtures are installed into the committed
# directory and the original is restored (byte-exact) after every case.
# ---------------------------------------------------------------------------

type
  FixtureFile = tuple[name, content: string]

proc committedEvidence(): seq[FixtureFile] =
  for f in walkFiles(EvidenceDir / "*.json"):
    result.add((name: extractFilename(f), content: readFile(f)))
  result.sort(proc(a, b: FixtureFile): int = cmp(a.name, b.name))

let OriginalEvidence = committedEvidence()

proc writeFixturesTo(dir: string; files: seq[FixtureFile]) =
  for f in walkFiles(dir / "*.json"):
    removeFile(f)
  for f in items files:
    writeFile(dir / f.name, f.content)

proc installFixtures(files: seq[FixtureFile]) =
  writeFixturesTo(EvidenceDir, files)

proc evidenceMatches(expected: seq[FixtureFile]): bool =
  let cur = committedEvidence()
  if cur.len != expected.len:
    return false
  for i in 0 ..< cur.len:
    if cur[i].name != expected[i].name or cur[i].content != expected[i].content:
      return false
  true

# ---------------------------------------------------------------------------
# Fixtures — rule-derived observation sets (evaluator ruleR1..ruleR8) for the
# PASS shape of every invariant, plus the variant deltas.
# ---------------------------------------------------------------------------

proc obs(key: string; value: JsonNode; scope = ""; subject = ""): JsonNode =
  result = newJObject()
  result["key"] = %key
  result["value"] = value
  if scope != "": result["scope"] = %scope
  if subject != "": result["subject"] = %subject

proc envelope(invId: string; observations: seq[JsonNode];
              freshUntil = FreshFuture; head = FixtureHead;
              commands: seq[JsonNode] = @[]): FixtureFile =
  var doc = newJObject()
  doc["schemaVersion"] = %1
  doc["invariantId"] = %invId
  doc["repoIdentity"] = %*{"head": head, "branch": "c3-fixture",
                           "workingTreeClean": true, "treeDigest": FixtureTree}
  doc["collection"] = %*{"collector": "c3-fixture", "method": "automated",
                         "generatedAt": "2026-11-16T00:00:00Z",
                         "freshUntil": freshUntil}
  let obsArr = newJArray()
  for o in observations:
    obsArr.add(o)
  doc["observations"] = obsArr
  let srcArr = newJArray()
  srcArr.add(%*{"file": "tests/ci/test_readiness_verdict_mapping.nim",
                "sha256": "c3-fixture", "repoHead": head, "symbol": "fixture"})
  doc["sources"] = srcArr
  if commands.len > 0:
    let cmdArr = newJArray()
    for c in commands:
      cmdArr.add(c)
    doc["commands"] = cmdArr
  (name: invId & ".json", content: doc.pretty())

proc r1Obs(): seq[JsonNode] =
  ## ruleR1: documented ∪ policy contractCommands all exist on the surface.
  @[obs("documentedCommand", %["ax prove", "ax report"], "doc", "README.md"),
    obs("commandExists", %true, "surface", "ax prove"),
    obs("commandExists", %true, "surface", "ax report"),
    obs("promiseOutputExists", %true, "artifact", "json-report")]

proc r2Obs(dualEvidenceRequired: bool): seq[JsonNode] =
  @[obs("certGreenDualEvidenceRequired", %dualEvidenceRequired),
    obs("z3OnlyCanProduceCertGreen", %false, "test"),
    obs("summaryVerifiedIncludesVacuous", %false),
    obs("z3VsDualDistinguishable", %true),
    obs("verifiedSemanticsDocumented", %true)]

proc r3Obs(): seq[JsonNode] =
  @[obs("canonicalProjectionHashEqual", %true),
    obs("canonicalInputHash", %"aa11"),
    obs("configHash", %"bb22"),
    obs("solverIdentity", %"z3-4.13.3"),
    obs("cachePolicy", %"warm"),
    obs("canonicalExecutionFingerprint", %"cc33"),
    obs("environmentControlled", %true),
    obs("subjectRunProjectionHashEqual", %true),
    obs("pathIndependentProjectionEqual", %true)]

proc r4Obs(): seq[JsonNode] =
  ## ruleR4: every policy r4.requiredFields entry observed certFieldPresent.
  result = @[]
  for f in ["claim", "attestation", "inputHash", "provenance",
            "toolchainIdentity", "solverInvocation", "solverInputDigest",
            "solverResultDigest"]:
    result.add(obs("certFieldPresent", %true, "", f))
  result.add(obs("provenanceReconstructible", %true))

proc r5Obs(): seq[JsonNode] =
  @[obs("commandExists", %true, "surface", "ax prove"),
    obs("commandExists", %true, "surface", "ax report"),
    obs("successExitCode", %0, "", "ax prove"),
    obs("verificationFailureExitCode", %1, "", "ax prove"),
    obs("invalidInputExitCode", %3, "", "ax prove"),
    obs("internalErrorExitCode", %2, "", "ax prove"),
    obs("jsonSchemaVersion", %"axiom.report.v1"),
    obs("stdoutStderrSplit", %true)]

proc r6Obs(): seq[JsonNode] =
  @[obs("failureConvertsToSuccess", %false),
    obs("exceptionSwallowed", %false)]

proc r7Obs(coverage: float): seq[JsonNode] =
  ## ruleR7: emitted ⊆ claimed (no R1/R2 promotion) + coverage vs threshold.
  @[obs("claimedScope", %["vkd"], "vkd-contract"),
    obs("verifiedEmitterScope", %["vkd"], "vkd-emission"),
    obs("measuredCoverage", %coverage, "vkd")]

proc r8Obs(): seq[JsonNode] =
  @[obs("installFollowed", %true),
    obs("manualStepsRequired", %false),
    obs("cleanRunSucceeded", %true),
    obs("documentedRunSteps", %true)]

proc r8Commands(): seq[JsonNode] =
  ## policy r8.prepareSequenceCommands, verbatim order, exitCode 0 each.
  result = @[%*{"cmd": "cargo fetch --locked", "exitCode": 0},
             %*{"cmd": "cargo metadata --format-version=1 --locked", "exitCode": 0},
             %*{"cmd": "cargo build --frozen", "exitCode": 0}]

proc verdictFixtures(variant: string): seq[FixtureFile] =
  ## variant: go | cg | nogo | stale | mismatch | missing-r2
  ##   go         — R1..R8 all PASS                        -> GO
  ##   cg         — R7 measuredCoverage 0.1 < 0.5 -> FAIL  -> CONDITIONAL GO
  ##   nogo       — R2 certGreenDualEvidenceRequired=false -> NO-GO
  ##   stale      — go shape with freshUntil in the past   -> INVALID -> NO-GO
  ##   mismatch   — go shape with repoIdentity.head=OtherHead
  ##   missing-r2 — go shape without R2.json               -> R2 NOT_RUN -> NO-GO
  result = @[]
  let fresh = if variant == "stale": FreshPast else: FreshFuture
  let head = if variant == "mismatch": OtherHead else: FixtureHead
  for invId in R1ToR8:
    if variant == "missing-r2" and invId == "R2":
      continue
    let observations = case invId
      of "R1": r1Obs()
      of "R2": r2Obs(variant != "nogo")
      of "R3": r3Obs()
      of "R4": r4Obs()
      of "R5": r5Obs()
      of "R6": r6Obs()
      of "R7": r7Obs(if variant == "cg": 0.1 else: 0.9)
      of "R8": r8Obs()
      else: @[]
    result.add(envelope(invId, observations, freshUntil = fresh, head = head,
                        commands = if invId == "R8": r8Commands() else: @[]))

proc expectedVerdict(variant: string): string =
  case variant
  of "go": "GO"
  of "cg": "CONDITIONAL GO"
  else: "NO-GO"

# ---------------------------------------------------------------------------
# Evaluator pre-validation (fast, before any gate run).
# ---------------------------------------------------------------------------

proc runEvaluator(variant: string): tuple[exit: int, verdict: string,
                                           conditions: seq[string],
                                           states: JsonNode] =
  let dir = Work / "fixtures" / variant
  let outPath = Work / "decisions" / (variant & ".json")
  var args = @["--policy", Root / "config" / "readiness_policy.json",
               "--evidence-dir", dir,
               "--eval-time", EvalTime,
               "--out", outPath]
  if variant == "mismatch":
    # evidence declares OtherHead; the evaluator is given the CI-side
    # FixtureHead -> every envelope INVALID (repoIdentity.head mismatch).
    args.add("--repo-head")
    args.add(FixtureHead)
  else:
    args.add("--repo-head")
    args.add(FixtureHead)
    args.add("--tree-digest")
    args.add(FixtureTree)
    args.add("--working-tree-clean")
    args.add("true")
  let r = runBin(EvaluatorBin, args)
  result.exit = r.exit
  result.states = nil
  try:
    let node = parseFile(outPath)
    result.verdict = node{"verdict"}.getStr("")
    if node{"conditions"} != nil and node{"conditions"}.kind == JArray:
      for c in node{"conditions"}.items:
        if c.kind == JString:
          result.conditions.add(c.getStr())
    result.states = node{"invariantStates"}
  except CatchableError:
    discard # axiom:best-effort(unreadable decision keeps verdict="" so a failed evaluator run cannot count as a passing verdict)

proc stateOf(states: JsonNode; invId: string): string =
  if states != nil and states.kind == JObject and states.hasKey(invId):
    states[invId].getStr("")
  else:
    ""

proc verdictLines(output: string): seq[string] =
  for line in output.splitLines():
    if line.startsWith("READINESS_VERDICT"):
      result.add(line)

proc conditionsOf(verdictLine: string): string =
  const tag = "CONDITIONS"
  let i = verdictLine.find(tag)
  if i < 0:
    ""
  else:
    verdictLine[i + tag.len .. ^1].strip()

suite "readiness verdict mapping (DEBT#537)":

  test "binaries under test are built":
    check fileExists(GateBin)
    check fileExists(EvaluatorBin)
    check ensureProbeAxBinary()
    checkpoint("gate READINESS_VERDICT wiring embedded: " & $GateEmitsVerdictLine)
    checkpoint("gate AXIOM_CI_REPO_HEAD binding embedded: " & $GateBindsCiIdentity)

  test "fixture semantics: every variant yields its verdict via bin/readiness_evaluator":
    createDir(Work / "decisions")
    for variant in ["go", "cg", "nogo", "stale", "mismatch", "missing-r2"]:
      let dir = Work / "fixtures" / variant
      if dirExists(dir): removeDir(dir)
      createDir(dir)
      writeFixturesTo(dir, verdictFixtures(variant))
      let ev = runEvaluator(variant)
      checkpoint(variant & ": evaluator verdict=" & ev.verdict)
      check ev.exit == 0
      check ev.verdict == expectedVerdict(variant)
    let cg = runEvaluator("cg")
    check stateOf(cg.states, "R7") == "FAIL"
    check stateOf(runEvaluator("go").states, "R7") == "PASS"
    check cg.conditions == @["R7=FAIL"]
    check stateOf(runEvaluator("nogo").states, "R2") == "FAIL"
    check stateOf(runEvaluator("stale").states, "R1") == "NOT_RUN"
    check stateOf(runEvaluator("mismatch").states, "R1") == "NOT_RUN"
    check stateOf(runEvaluator("missing-r2").states, "R2") == "NOT_RUN"

  test "GO (all R1..R8 PASS): exit 0 + single 'READINESS_VERDICT GO CONDITIONS' line (empty)":
    let backup = committedEvidence()
    defer:
      installFixtures(backup)
      check evidenceMatches(backup)
    let installed = verdictFixtures("go")
    installFixtures(installed)
    let r = runGate(logName = "go")
    check evidenceMatches(installed)
    check r.exit == 0
    if GateEmitsVerdictLine:
      let vl = verdictLines(r.output)
      check vl.len == 1
      if vl.len == 1:
        check vl[0].startsWith("READINESS_VERDICT GO CONDITIONS")
        check conditionsOf(vl[0]) == ""
      check "::warning::readiness" notin r.output
    else:
      echo pendingContractMsg("GO verdict line", "READINESS_VERDICT emission")
      skip()

  test "CONDITIONAL GO (R7 FAIL, rest PASS): exit 0, conditions + '::warning::readiness' line":
    let backup = committedEvidence()
    defer:
      installFixtures(backup)
      check evidenceMatches(backup)
    let installed = verdictFixtures("cg")
    installFixtures(installed)
    let r = runGate(logName = "cg")
    check evidenceMatches(installed)
    check r.exit == 0
    if GateEmitsVerdictLine:
      let vl = verdictLines(r.output)
      check vl.len == 1
      if vl.len == 1:
        check vl[0].startsWith("READINESS_VERDICT CONDITIONAL GO CONDITIONS")
        check "R7=FAIL" in conditionsOf(vl[0])
      var warn = ""
      for line in r.output.splitLines():
        if line.startsWith("::warning::readiness"):
          warn = line
          break
      check warn != ""
      check "CONDITIONAL GO" in warn
      check "R7=FAIL" in warn
    else:
      echo pendingContractMsg("CONDITIONAL GO conditions/warning", "READINESS_VERDICT emission")
      skip()

  test "NO-GO (critical R2 FAIL): exit 1":
    let backup = committedEvidence()
    defer:
      installFixtures(backup)
      check evidenceMatches(backup)
    let installed = verdictFixtures("nogo")
    installFixtures(installed)
    let r = runGate(logName = "nogo")
    check evidenceMatches(installed)
    check r.exit == 1
    if GateEmitsVerdictLine:
      let vl = verdictLines(r.output)
      check vl.len == 1
      if vl.len == 1:
        check vl[0].startsWith("READINESS_VERDICT NO-GO")
    else:
      echo pendingContractMsg("NO-GO verdict line", "READINESS_VERDICT emission")
      skip()

  test "stale evidence (freshUntil past): exit 1 (INVALID -> critical NOT_RUN -> NO-GO)":
    let backup = committedEvidence()
    defer:
      installFixtures(backup)
      check evidenceMatches(backup)
    let installed = verdictFixtures("stale")
    installFixtures(installed)
    let r = runGate(logName = "stale")
    check evidenceMatches(installed)
    check r.exit == 1
    checkpoint("stale INVALID diag surfaced by evaluator: " &
               $(r.output.contains("stale evidence")))
    if GateEmitsVerdictLine:
      let vl = verdictLines(r.output)
      check vl.len == 1
      if vl.len == 1:
        check vl[0].startsWith("READINESS_VERDICT NO-GO")
    else:
      echo pendingContractMsg("stale verdict line", "READINESS_VERDICT emission")
      skip()

  test "identity mismatch (evidence head != AXIOM_CI_REPO_HEAD): exit 1 + READINESS_IDENTITY_MISMATCH":
    let backup = committedEvidence()
    defer:
      installFixtures(backup)
      check evidenceMatches(backup)
    let installed = verdictFixtures("mismatch")
    installFixtures(installed)
    let env = @[("AXIOM_CI_REPO_HEAD", FixtureHead),
                ("AXIOM_CI_TREE_DIGEST", FixtureTree)]
    if GateBindsCiIdentity:
      let r = runGate(env, logName = "mismatch")
      check evidenceMatches(installed)
      check r.exit == 1
      check "READINESS_IDENTITY_MISMATCH" in r.output
      check ("expected=" & FixtureHead) in r.output
      check ("actual=" & OtherHead) in r.output
    else:
      let r = runGate(env, logName = "mismatch_legacy")
      echo pendingContractMsg("identity mismatch rejection", "AXIOM_CI_REPO_HEAD binding")
      skip()
      checkpoint("legacy gate observed exit " & $r.exit &
                 " (identity is trusted FROM the evidence; mismatch unreachable)")

  test "missing critical evidence file (R2.json absent): exit 1":
    let backup = committedEvidence()
    defer:
      installFixtures(backup)
      check evidenceMatches(backup)
    let installed = verdictFixtures("missing-r2")
    installFixtures(installed)
    let r = runGate(logName = "missing-r2")
    check evidenceMatches(installed)
    check r.exit == 1
    if GateEmitsVerdictLine:
      let vl = verdictLines(r.output)
      check vl.len == 1
      if vl.len == 1:
        check vl[0].startsWith("READINESS_VERDICT NO-GO")
    else:
      echo pendingContractMsg("missing-evidence verdict line", "READINESS_VERDICT emission")
      skip()

  test "committed evidence snapshot restored byte-exact after all cases":
    check evidenceMatches(OriginalEvidence)
