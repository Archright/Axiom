import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## readiness_start_gate.nim — Axiom readiness start gate (Operationalization E).
##
## CI-enforcement gate for the productization vertical slice:
##   (a) runs the committed productization E2E gateway test(s)
##       (tests/gateway/productization_start*), and
##   (b) runs the readiness evaluator (tools/readiness_evaluator.nim) against
##       the canonical latest evidence directory (data/readiness/evidence).
##
## Fail-closed contract (no delay, no theater):
##   * NO productization_start* test file found in tests/gateway/ -> FAIL.
##     The vertical slice is created separately; until it lands this gate must
##     be red, not skipped. Missing test = unenforced contract.
##   * Evaluator cannot build/run; evidence dir missing/unreadable; evidence
##     stale/contradictory; any LOAD/INVALID state                      -> FAIL.
##   * Evaluator verdict "NO-GO"                                        -> FAIL.
##   * Verdict "CONDITIONAL GO" (all critical invariants PASS)          -> PASS
##     but conditions are printed loudly (non-silent; honest state).
##   * Verdict "GO"                                                     -> PASS.
##
## Evidence repo identity: the evidence files are a committed snapshot frozen
## to a specific head/treeDigest (see R*.json repoIdentity). The gate passes
## the DECLARED identity back to the evaluator (same as the audit repro in
## docs/audit/productization_readiness_CONDITIONAL-GO_2026-08-17.md), so the
## validation is deterministic and independent of the ephemeral current HEAD.
## Evidence files disagreeing on identity = contradictory evidence -> FAIL.
##
## Registration: config/gates.manifest.toml (generated from
## src/gate/topology_spec.nim by tools/sync_topology.nim), stage manual
## (topology entry "readiness-start-gate": stages = @[skManual]); the sole
## invoker is `make check-readiness-start` (Makefile:941, AXIOM_CI=1).
##
## Usage: no arguments.

import std/[os, osproc, strutils, times, json, sequtils, algorithm]
import infrastructure/logging_facade
# axiomIoBoundary

const
  ProductizationTestPrefix = "productization_start"
  GatewayTestsDir = "tests" / "gateway"
  EvaluatorSource = "tools" / "readiness_evaluator.nim"
  EvaluatorBinary = "bin" / "readiness_evaluator"
  MetricsMaterializerSource = "src" / "verification" / "obligation" / "metrics_materializer.nim"
  MetricsMaterializerBinary = "bin" / "metrics_materializer"
  PolicyPath = "config" / "readiness_policy.json"
  EvidenceDir = "data" / "readiness" / "evidence"
  E2EOutDir = "build" / "readiness_start" / "e2e"
  E2ENimcacheDir = "build" / "nimcache" / "readiness_start"
  DecisionOut = "build" / "readiness_start_decision.json"
  RootMarker = ".axiom_root"

proc repoRootOf(): string =
  ## Compile-time anchored root (this file lives in src/gate/runners/).
  ## Same pattern as external_cli_smoke.nim.
  result = currentSourcePath().parentDir().parentDir().parentDir().parentDir()
  if not fileExists(result / RootMarker):
    let cwd = getCurrentDir()
    if fileExists(cwd / RootMarker):
      result = cwd

proc findProductizationTests(root: string): seq[string] =
  ## Discover tests/gateway/productization_start* (case-insensitive prefix,
  ## mirroring `ls tests/gateway/ | grep -i product`), sorted for determinism.
  let dir = root / GatewayTestsDir
  if not dirExists(dir):
    return @[]
  for kind, path in walkDir(dir):
    if kind != pcFile:
      continue
    let name = path.extractFilename()
    if name.toLowerAscii().startsWith(ProductizationTestPrefix) and
       name.endsWith(".nim"):
      result.add(path)
  result.sort(cmp[string])

proc runCmd(cmd: string, root: string): tuple[output: string, exitCode: int] =
  ## Run a command from the repo root; this runner is an I/O boundary.
  putEnv("AXIOM_GATE_BOND", "1")
  execCmdEx(cmd, workingDir = root)

proc compileAndRunE2E(root: string, src: string): bool =
  ## Compile + run one productization E2E test with the canonical gateway
  ## compile profile (mirrors tests/gateway/all_gateway_runner.nim's compile
  ## command, single-job form).
  let name = src.splitFile().name
  let outBin = root / E2EOutDir / (name & ".e2e")
  let nimcacheDir = root / E2ENimcacheDir / name
  if not dirExists(root / E2EOutDir):
    createDir(root / E2EOutDir)
  if not dirExists(nimcacheDir):
    createDir(nimcacheDir)
  logInfo("readiness_start_gate", "[E2E] compiling " & src)
  let compileCmd =
    "nim c -d:release --threads:on --listFullPaths:off --hints:off " &
    "-d:AXIOM_GATE_BOND=1 --nimcache:" & quoteShell(nimcacheDir) &
    " --out:" & quoteShell(outBin) & " " & quoteShell(src)
  let (cOut, cCode) = runCmd(compileCmd, root)
  stdout.write(cOut)
  if cCode != 0:
    logError("readiness_start_gate", "[E2E] compile FAILED exit=" & $cCode)
    return false
  logInfo("readiness_start_gate", "[E2E] running: " & outBin)
  let (rOut, rCode) = runCmd(quoteShell(outBin), root)
  stdout.write(rOut)
  if rCode != 0:
    logError("readiness_start_gate", "[E2E] run FAILED exit=" & $rCode)
    return false
  logInfo("readiness_start_gate", "[E2E] OK: " & src & " (exit 0)")
  true

# ---------------------------------------------------------------------------
# Evidence identity (declared inside the committed evidence snapshot)
# ---------------------------------------------------------------------------

type
  EvidenceIdentity = object
    head: string
    branch: string
    treeDigest: string
    workingTreeClean: bool
    workingTreeCleanDeclared: bool
    toolchainNim: string
    toolchainZ3: string
    toolchainLean: string

proc collectEvidenceIdentity(root: string): tuple[idy: EvidenceIdentity, err: string] =
  ## Merge the repoIdentity/toolchain declared by the evidence files. Any
  ## disagreement across files is a contradiction -> err (the evaluator would
  ## also drop such evidence as INVALID; this is an earlier, clearer failure).
  ## Missing identity declarations are allowed (evaluator skips those checks
  ## "when declared" only) — then no --repo-head is passed.
  let dir = root / EvidenceDir
  if not dirExists(dir):
    return (EvidenceIdentity(), "evidence directory does not exist: " & dir)
  var idy = EvidenceIdentity()
  for f in walkFiles(dir / "*.json"):
    var node: JsonNode
    try:
      node = parseFile(f)
    except CatchableError as e:
      return (EvidenceIdentity(), "unparsable evidence file " & f & ": " & e.msg)
    if node == nil or node.kind != JObject:
      continue
    if node.hasKey("repoIdentity") and node["repoIdentity"].kind == JObject:
      let ri = node["repoIdentity"]
      let head = ri{"head"}.getStr("")
      let branch = ri{"branch"}.getStr("")
      let treeDigest = ri{"treeDigest"}.getStr("")
      if head == "" or treeDigest == "":
        return (EvidenceIdentity(),
                f & " declares incomplete repoIdentity (head and treeDigest required)")
      if idy.head == "":
        idy.head = head
        idy.branch = branch
        idy.treeDigest = treeDigest
      elif idy.head != head or idy.treeDigest != treeDigest or
           (branch != "" and branch != idy.branch):
        return (EvidenceIdentity(),
                "contradictory repoIdentity across evidence files (" & f & ")")
      let wtc = ri{"workingTreeClean"}
      if wtc != nil and wtc.kind == JBool:
        if not idy.workingTreeCleanDeclared:
          idy.workingTreeClean = wtc.getBool()
          idy.workingTreeCleanDeclared = true
        elif idy.workingTreeClean != wtc.getBool():
          return (EvidenceIdentity(),
                  "contradictory workingTreeClean across evidence files (" & f & ")")
    if node.hasKey("toolchain") and node["toolchain"].kind == JObject:
      let tc = node["toolchain"]
      let nimV = tc{"nim"}.getStr("")
      let z3V = tc{"z3"}.getStr("")
      let leanV = tc{"lean"}.getStr("")
      if nimV != "":
        if idy.toolchainNim == "": idy.toolchainNim = nimV
        elif idy.toolchainNim != nimV:
          return (EvidenceIdentity(), "contradictory toolchain.nim in " & f)
      if z3V != "":
        if idy.toolchainZ3 == "": idy.toolchainZ3 = z3V
        elif idy.toolchainZ3 != z3V:
          return (EvidenceIdentity(), "contradictory toolchain.z3 in " & f)
      if leanV != "":
        if idy.toolchainLean == "": idy.toolchainLean = leanV
        elif idy.toolchainLean != leanV:
          return (EvidenceIdentity(), "contradictory toolchain.lean in " & f)
  (idy, "")

proc compileEvaluator(root: string): bool =
  ## Build bin/readiness_evaluator from tools/readiness_evaluator.nim if
  ## missing or stale (same build as the audit repro command).
  let binPath = root / EvaluatorBinary
  let srcPath = root / EvaluatorSource
  if not fileExists(srcPath):
    logError("readiness_start_gate", "evaluator source missing: " & srcPath)
    return false
  if fileExists(binPath) and not fileNewer(srcPath, binPath):
    return true
  logInfo("readiness_start_gate", "building " & EvaluatorBinary & " ...")
  let (outp, code) = runCmd(
    "nim c --hints:off -o:" & quoteShell(binPath) & " " & quoteShell(srcPath), root)
  stdout.write(outp)
  if code != 0:
    logError("readiness_start_gate", "evaluator build FAILED exit=" & $code)
    return false
  true

proc compileMetricsMaterializer(root: string): bool =
  ## Build bin/metrics_materializer subprocess tool if missing or stale.
  ## The gate layer must not import verification/* directly, so the terminal
  ## measurement projection (B3/MEAS) is invoked as an I/O-boundary subprocess.
  let binPath = root / MetricsMaterializerBinary
  let srcPath = root / MetricsMaterializerSource
  if not fileExists(srcPath):
    logError("readiness_start_gate", "metrics-materializer source missing: " & srcPath)
    return false
  if fileExists(binPath) and not fileNewer(srcPath, binPath):
    return true
  logInfo("readiness_start_gate", "building " & MetricsMaterializerBinary & " ...")
  let (outp, code) = runCmd(
    "nim c --hints:off -o:" & quoteShell(binPath) & " " & quoteShell(srcPath), root)
  stdout.write(outp)
  if code != 0:
    logError("readiness_start_gate", "metrics-materializer build FAILED exit=" & $code)
    return false
  true

proc runMetricsMaterializer(root: string) =
  ## Terminal measurement projection (B3/MEAS-3b): materialize
  ## data/metrics/obligation_metrics.json from the completed report snapshot.
  ## Runs strictly AFTER verdict derivation; any failure is fail-open and must
  ## never disturb the gate verdict.
  if not fileExists(root / MetricsMaterializerBinary):
    return  # not built -> fail-open (projection skipped)
  let reportPath = root / "logs" / "ax_proof_state.json"
  if not fileExists(reportPath):
    return  # no completed snapshot -> nothing to project
  let cmd = quoteShell(root / MetricsMaterializerBinary) & " " & quoteShell(reportPath)
  let (outp, code) = runCmd(cmd, root)
  if code != 0:
    logWarn("readiness_start_gate",
            "metrics-materializer exit=" & $code & " (fail-open; does not affect verdict)")
  else:
    logInfo("readiness_start_gate", "metrics materialized (obligation_metrics.json)")

type
  EvaluatorResult = object
    verdict: string
    conditions: seq[string]
    invariantStates: JsonNode
    outcome: string            ## CONTINUE | BLOCK | UNRESOLVED
    failureCategory: string    ## CONTRACT_FAIL | EVIDENCE_FAIL | PROVENANCE_FAIL | UNKNOWN | INFRA_FAIL | ""
    decisionDigest: string
    err: string

proc writeInfraFailRecord(root: string) =
  ## An evaluator infra/execution failure is NOT a confirmed product contract
  ## BLOCK. Record it as outcome=UNRESOLVED / failureCategory=INFRA_FAIL so the
  ## artifact distinguishes "check could not run" from "invariant failed".
  let rec = %*{
    "schemaVersion": 1,
    "verdict": "NO-GO",
    "outcome": "UNRESOLVED",
    "failureCategory": "INFRA_FAIL",
    "reason": "readiness evaluator infra/execution failure (not a confirmed contract invariant violation)",
    "invariantStates": {}
  }
  try:
    let outPath = root / DecisionOut
    createDir(parentDir(outPath))
    writeFile(outPath, rec.pretty())
  except CatchableError:
    discard  # best-effort: failing to write the record must not mask the infra failure

proc runEvaluator(root: string, idy: EvidenceIdentity,
                  evalTime: string): EvaluatorResult =
  ## Invoke the evaluator CLI with the declared evidence identity and parse
  ## its decision JSON (fixed output path => deterministic artifact).
  if not fileExists(root / PolicyPath):
    return EvaluatorResult(err: "policy not found: " & root / PolicyPath)
  var args: seq[string] = @[
    "--policy", root / PolicyPath,
    "--evidence-dir", root / EvidenceDir,
    "--eval-time", evalTime,
    "--out", root / DecisionOut,
    "--branch", (if idy.branch != "": idy.branch else: "main")
  ]
  if idy.head != "":
    args.add("--repo-head"); args.add(idy.head)
    args.add("--tree-digest"); args.add(idy.treeDigest)
    args.add("--working-tree-clean")
    args.add(if idy.workingTreeCleanDeclared and idy.workingTreeClean: "true" else: "false")
  if idy.toolchainNim != "":
    args.add("--toolchain-nim"); args.add(idy.toolchainNim)
  if idy.toolchainZ3 != "":
    args.add("--toolchain-z3"); args.add(idy.toolchainZ3)
  if idy.toolchainLean != "":
    args.add("--toolchain-lean"); args.add(idy.toolchainLean)

  var cmd = quoteShell(root / EvaluatorBinary)
  for a in args:
    cmd.add(" " & quoteShell(a))
  logInfo("readiness_start_gate", "running: " & EvaluatorBinary)
  let (outp, code) = runCmd(cmd, root)
  stdout.write(outp)
  if code != 0:
    return EvaluatorResult(err: "evaluator exited " & $code & " (evidence load/validation failure — fail-closed)")
  let outPath = root / DecisionOut
  if not fileExists(outPath):
    return EvaluatorResult(err: "evaluator produced no decision file at " & outPath)
  var node: JsonNode
  try:
    node = parseFile(outPath)
  except CatchableError as e:
    return EvaluatorResult(err: "cannot parse decision file: " & e.msg)
  result.verdict = node{"verdict"}.getStr("")
  if node{"conditions"} != nil and node["conditions"].kind == JArray:
    for c in node["conditions"].items:
      if c.kind == JString:
        result.conditions.add(c.getStr())
  result.invariantStates = node{"invariantStates"}
  result.outcome = node{"outcome"}.getStr("")
  result.failureCategory = node{"failureCategory"}.getStr("")
  result.decisionDigest = node{"decisionDigest"}.getStr("")
  if result.verdict == "":
    return EvaluatorResult(err: "decision file has no verdict field")
  result.err = ""

when isMainModule:
  let root = repoRootOf()
  if root == "" or not fileExists(root / RootMarker):
    logError("readiness_start_gate",
             "repo root not found (no " & RootMarker & " marker); run from the repo root.")
    quit(1)
  logInfo("readiness_start_gate", "repo root: " & root)

  # ── (a) Productization vertical-slice E2E test ─────────────────────────
  let tests = findProductizationTests(root)
  if tests.len == 0:
    logError("readiness_start_gate",
      "FAIL-CLOSED: no tests/gateway/productization_start* test found " &
      "(expected e.g. tests/gateway/productization_start_*_feature_test.nim). " &
      "The productization vertical-slice E2E is not committed yet; this gate " &
      "stays red until it lands. No delay, no skip — missing test = unenforced " &
      "contract.")
    quit(1)
  logInfo("readiness_start_gate",
          "productization E2E tests found: " & $tests.len)
  var e2eOk = true
  for t in tests:
    if not compileAndRunE2E(root, t):
      e2eOk = false
      break
  if not e2eOk:
    logError("readiness_start_gate",
             "productization E2E FAILED — see output above.")
    quit(1)

  # ── (b) Readiness evaluator over the latest evidence ───────────────────
  let (idy, idyErr) = collectEvidenceIdentity(root)
  if idyErr != "":
    logError("readiness_start_gate", "evidence identity error: " & idyErr)
    quit(1)
  if not compileEvaluator(root):
    quit(1)
  let evalTime = utc(now()).format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  logInfo("readiness_start_gate",
          "evaluating evidence " & root / EvidenceDir & " @ " & evalTime)
  let res = runEvaluator(root, idy, evalTime)
  if res.err != "":
    writeInfraFailRecord(root)
    let msg = "evaluator error (INFRA_FAIL/UNRESOLVED — not a confirmed product BLOCK): " & res.err
    logError("readiness_start_gate", msg)
    quit(1)

  # ── (b2) MEAS materializer: fresh prove snapshot → obligation metrics ─────
  #      Terminal projection AFTER verdict derivation (MEAS-3b fail-open): the
  #      projection never disturbs the gate verdict. data/metrics/* is a derived
  #      measurement artifact, NOT part of the canonical product execution path.
  #      The gate layer shells out to an I/O-boundary subprocess rather than
  #      importing verification/* directly (layer enforcement).
  if compileMetricsMaterializer(root):
    runMetricsMaterializer(root)

  # ── Verdict enforcement (evaluator algebra is the SSOT) ─────────────────
  echo "[readiness_start_gate] decision digest: " & res.decisionDigest
  if res.outcome != "": echo "[readiness_start_gate] outcome: " & res.outcome
  if res.failureCategory != "": echo "[readiness_start_gate] failureCategory: " & res.failureCategory
  if res.invariantStates != nil and res.invariantStates.kind == JObject:
    for inv in res.invariantStates.keys:
      let st = res.invariantStates[inv].getStr("")
      echo "  " & inv & " = " & st
  case res.verdict
  of "NO-GO":
    logError("readiness_start_gate",
             "readiness verdict NO-GO — contract blockers present; gate FAILS.")
    quit(1)
  of "CONDITIONAL GO":
    for c in res.conditions:
      logWarn("readiness_start_gate", "CONDITION: " & c)
    logWarn("readiness_start_gate",
            "verdict CONDITIONAL GO — conditions above are attached to the GO; not silent.")
  of "GO":
    logInfo("readiness_start_gate", "verdict GO — all invariants PASS.")
  else:
    logError("readiness_start_gate",
             "unexpected verdict '" & res.verdict & "' — fail-closed.")
    quit(1)
  logInfo("readiness_start_gate",
          "readiness-start-gate PASSED (E2E " & $tests.len & " test(s) + evaluator).")

{.pop.}