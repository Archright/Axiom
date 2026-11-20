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
## Evidence repo identity (normal modes): the evidence snapshot's declared
## identity is NEVER the authority. The gate measures the checkout itself:
##   git rev-parse HEAD / --abbrev-ref HEAD,
##   sha256(git ls-tree -r HEAD)                       (treeDigest),
##   git status --porcelain --untracked-files=no over the verdict-input tree
##   (derived-output paths excluded, mirroring the CI identity-chain step:
##    data/readiness/evidence, logs, build, bin, .axiom, proofs,
##    src/generated).
## The evaluator is invoked with these measured values; evidence whose
## declared repoIdentity disagrees is dropped by the evaluator (UNKNOWN ->
## NO-GO), never trusted as a substitute.
##
## CI identity authority mode (DEBT#537): when BOTH AXIOM_CI_REPO_HEAD and
## AXIOM_CI_TREE_DIGEST are exported, the environment is the identity
## authority AND the measured git identity must agree with it:
##   * git HEAD/treeDigest disagreeing with the environment prints
##       READINESS_GIT_IDENTITY_MISMATCH <head|treeDigest> expected=<env> actual=<git>
##     and exits 1 (the checkout is not the CI commit — distinct from an
##     evidence mismatch);
##   * every evidence file must declare repoIdentity.head and
##     repoIdentity.treeDigest exactly equal to the environment values; a
##     missing field or mismatch prints the stable stdout marker line
##       READINESS_IDENTITY_MISMATCH <file> expected=<v> actual=<v> field=<head|treeDigest>
##     (repo-relative <file>; expected/actual carry the failing axis's
##     environment vs evidence-declared value, empty when the field is
##     missing) and exits 1 — fail-closed, distinct from every tool-failure
##     path; and
##   * the evaluator is invoked with the environment head/digest
##     (--repo-head/--tree-digest).
## A partially set CI pair is a wiring error: warned about, then ignored
## (CI authority mode is never half-active; the measured git identity stays
## in force).
##
## Replay mode (explicit audit reproduction): AXIOM_READINESS_REPLAY=1 makes
## the evidence-DECLARED identity the evaluator context (the audit repro in
## docs/audit/productization_readiness_CONDITIONAL-GO_2026-08-17.md) and
## allows AXIOM_READINESS_EVAL_TIME to pin the evaluation instant. The gate
## logs both loudly: this mode validates a frozen historical snapshot, not
## the current checkout. CI identity variables are ignored in replay mode;
## without the replay flag the gate never trusts a self-declared identity.
##
## Machine-readable verdict exposure: whenever the evaluator produced a
## decision, the finalized verdict is printed to stdout exactly once (GO
## included) as
##   READINESS_VERDICT <GO|CONDITIONAL GO|NO-GO|UNKNOWN> CONDITIONS <list>
## where <list> is the decision.json conditions array joined with ';' (empty
## string when absent; the literal " CONDITIONS " separator is always
## present). Verdict/conditions strings are the evaluator's own decision.json
## output, never re-derived here (decision algebra is the SSOT); UNKNOWN is
## the fail-closed token for a verdict outside the evaluator's table. When
## conditions exist, an additional GitHub Actions annotation is printed:
##   ::warning::readiness <verdict>: conditions: <list>
## Tool failures (build/parse/infra) emit no READINESS_VERDICT line and keep
## their pre-existing exit codes — a missing line means "no verdict produced".
##
## Registration: config/gates.manifest.toml (generated from
## src/gate/topology_spec.nim by tools/sync_topology.nim), stage manual
## (topology entry "readiness-start-gate": stages = @[skManual]); the sole
## invoker is `make check-readiness-start` (Makefile:941, AXIOM_CI=1).
##
## Usage: no arguments. Environment: AXIOM_CI_REPO_HEAD + AXIOM_CI_TREE_DIGEST
## (both required together) enable CI identity authority mode;
## AXIOM_READINESS_REPLAY=1 enables the explicit replay (evidence-declared
## identity) mode and AXIOM_READINESS_EVAL_TIME pins its evaluation instant;
## registered in docs/spec/environment_inputs.md §2.15.

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
  CiRepoHeadEnv = "AXIOM_CI_REPO_HEAD"
  CiTreeDigestEnv = "AXIOM_CI_TREE_DIGEST"
  ReplayEnv = "AXIOM_READINESS_REPLAY"
  EvalTimeEnv = "AXIOM_READINESS_EVAL_TIME"
  VerdictInputExcludes =
    "':(exclude)data/readiness/evidence' ':(exclude)logs' " &
    "':(exclude)build' ':(exclude)bin' ':(exclude).axiom' " &
    "':(exclude)proofs' ':(exclude)src/generated'"

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

proc collectDeclaredEvidenceIdentity(root: string): tuple[idy: EvidenceIdentity, err: string] =
  ## REPLAY-ONLY: merge the repoIdentity/toolchain declared by the evidence
  ## files (explicit AXIOM_READINESS_REPLAY=1). Normal modes never call this —
  ## a self-declared identity is not authority. Any disagreement across files
  ## is a contradiction -> err (the evaluator would also drop such evidence as
  ## INVALID; this is an earlier, clearer failure). Missing identity
  ## declarations are allowed (evaluator skips those checks "when declared"
  ## only) — then no --repo-head is passed.
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

proc firstLineOf(s: string): string =
  for line in s.splitLines():
    let t = line.strip()
    if t.len > 0:
      return t
  ""

proc measureGitIdentity(root: string): tuple[idy: EvidenceIdentity, err: string] =
  ## Independent measurement of the checkout (the evidence snapshot is never
  ## the authority outside replay mode). `clean` covers the verdict-input tree
  ## only: derived-output paths are excluded exactly as in the CI
  ## identity-chain step, so collector/evaluator outputs cannot make the
  ## source tree read dirty.
  var idy = EvidenceIdentity()
  let (headOut, headCode) = runCmd("git rev-parse HEAD", root)
  if headCode != 0:
    return (idy, "git rev-parse HEAD failed: " & headOut.strip())
  idy.head = headOut.strip()
  if idy.head.len == 0:
    return (idy, "git rev-parse HEAD produced no commit id")
  let (branchOut, branchCode) = runCmd("git rev-parse --abbrev-ref HEAD", root)
  if branchCode != 0:
    return (idy, "git rev-parse --abbrev-ref HEAD failed: " & branchOut.strip())
  idy.branch = branchOut.strip()
  # Same formula as the CI env export and the collector: command substitution
  # strips the trailing newline, printf re-emits the exact bytes.
  let (treeOut, treeCode) = runCmd(
    "printf '%s' \"$(git ls-tree -r HEAD)\" | sha256sum", root)
  if treeCode != 0:
    return (idy, "git ls-tree -r HEAD failed: " & treeOut.strip())
  let parts = treeOut.strip().splitWhitespace()
  if parts.len == 0 or parts[0].len != 64:
    return (idy, "git ls-tree -r HEAD digest unmeasurable: " & treeOut.strip())
  idy.treeDigest = parts[0]
  let (statusOut, statusCode) = runCmd(
    "git status --porcelain --untracked-files=no -- . " & VerdictInputExcludes,
    root)
  if statusCode != 0:
    return (idy, "git status failed: " & statusOut.strip())
  idy.workingTreeClean = statusOut.strip() == ""
  idy.workingTreeCleanDeclared = true
  # Toolchain observables: the same first lines the collector records. A
  # missing tool leaves its field empty, so the evaluator skips that declared
  # check instead of comparing against a failure message.
  let (nimOut, nimCode) = runCmd("nim --version", root)
  if nimCode == 0:
    idy.toolchainNim = firstLineOf(nimOut)
  let (z3Out, z3Code) = runCmd("z3 --version", root)
  if z3Code == 0:
    idy.toolchainZ3 = firstLineOf(z3Out)
  let (leanOut, leanCode) = runCmd("lean --version", root)
  if leanCode == 0:
    idy.toolchainLean = firstLineOf(leanOut)
  (idy, "")

# ---------------------------------------------------------------------------
# CI identity authority (DEBT#537): environment-supplied repository identity
# ---------------------------------------------------------------------------

proc relToRoot(root: string; p: string): string =
  ## Repo-relative form of a path inside the repo — marker lines must not
  ## embed machine-local checkout paths.
  if p.startsWith(root & DirSep):
    p[(root.len + 1) .. ^1]
  else:
    p

proc identityMismatchLine(root: string; f: string; field: string;
                          expected: string; actual: string): string =
  ## Stable stdout marker for a CI identity violation. The line always starts
  ## READINESS_IDENTITY_MISMATCH <file> expected=<v> actual=<v>; the trailing
  ## field names which identity axis failed (expected/actual carry that
  ## axis's environment vs evidence-declared value, empty when the field is
  ## missing). Machine surface contract: DEBT#537 CI wiring consumers match
  ## the marker prefix + exit 1 to distinguish identity failure from every
  ## other fail-closed reason.
  "READINESS_IDENTITY_MISMATCH " & relToRoot(root, f) &
    " expected=" & expected & " actual=" & actual & " field=" & field

proc ciIdentityMismatch(root: string; ciHead: string;
                        ciTree: string): tuple[marker: string, err: string] =
  ## CI authority check: every evidence file must declare repoIdentity.head
  ## and repoIdentity.treeDigest exactly equal to the environment values
  ## (missing field = mismatch, fail-closed). Files are walked in sorted
  ## order so the reported violation is deterministic. An unparsable file is
  ## a tool failure (err), NOT an identity mismatch — the failure categories
  ## stay distinguishable.
  let dir = root / EvidenceDir
  if not dirExists(dir):
    return ("", "evidence directory does not exist: " & dir)
  var files: seq[string] = @[]
  for f in walkFiles(dir / "*.json"):
    files.add(f)
  files.sort(cmp[string])
  for f in files:
    var node: JsonNode
    try:
      node = parseFile(f)
    except CatchableError as e:
      return ("", "unparsable evidence file " & f & ": " & e.msg)
    if node == nil or node.kind != JObject:
      return (identityMismatchLine(root, f, "head", ciHead, ""), "")
    let ri = node{"repoIdentity"}
    let actHead = if ri != nil and ri.kind == JObject: ri{"head"}.getStr("") else: ""
    let actTree = if ri != nil and ri.kind == JObject: ri{"treeDigest"}.getStr("") else: ""
    if actHead != ciHead:
      return (identityMismatchLine(root, f, "head", ciHead, actHead), "")
    if actTree != ciTree:
      return (identityMismatchLine(root, f, "treeDigest", ciTree, actTree), "")
  ("", "")

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

  # ── (b) Identity: measured from git, never declared by the evidence ─────
  let replay = getEnv(ReplayEnv) == "1"
  var idy: EvidenceIdentity
  var idyErr = ""
  if replay:
    logWarn("readiness_start_gate",
            "REPLAY mode (" & ReplayEnv & "=1): the evidence-DECLARED identity " &
            "is the evaluator context — this validates a frozen snapshot, not " &
            "the current checkout.")
    (idy, idyErr) = collectDeclaredEvidenceIdentity(root)
    if idyErr != "":
      logError("readiness_start_gate", "evidence identity error: " & idyErr)
      quit(1)
    logInfo("readiness_start_gate",
            "replay identity: head=" & idy.head & " treeDigest=" & idy.treeDigest &
            " branch=" & idy.branch &
            " workingTreeClean=" & $idy.workingTreeClean)
  else:
    (idy, idyErr) = measureGitIdentity(root)
    if idyErr != "":
      logError("readiness_start_gate",
               "independent git identity measurement failed: " & idyErr)
      quit(1)
    logInfo("readiness_start_gate",
            "measured git identity: head=" & idy.head & " treeDigest=" &
            idy.treeDigest & " branch=" & idy.branch &
            " verdictInputClean=" & $idy.workingTreeClean)

  # ── (b0) CI identity authority mode (both env vars set) ────────────────
  # The environment is the identity authority: the checkout AND the evidence
  # snapshot must describe exactly the CI commit. The checkout check is
  # independent of the evidence (git measurement above); the evidence check
  # keeps the stable READINESS_IDENTITY_MISMATCH marker.
  let ciHead = getEnv(CiRepoHeadEnv)
  let ciTree = getEnv(CiTreeDigestEnv)
  if replay:
    if ciHead.len > 0 or ciTree.len > 0:
      logWarn("readiness_start_gate",
              "CI identity variables ignored in replay mode (" & ReplayEnv & "=1).")
  else:
    if (ciHead.len > 0) xor (ciTree.len > 0):
      logWarn("readiness_start_gate",
              CiRepoHeadEnv & " and " & CiTreeDigestEnv & " must be set " &
              "together; partial CI identity ignored — using the measured git " &
              "identity (check the CI exporter wiring).")
    if ciHead.len > 0 and ciTree.len > 0:
      logInfo("readiness_start_gate",
              "CI identity authority mode: head=" & ciHead &
              " treeDigest=" & ciTree)
      if idy.head != ciHead:
        echo "READINESS_GIT_IDENTITY_MISMATCH head expected=" & ciHead &
             " actual=" & idy.head
        logError("readiness_start_gate",
                 "checkout HEAD is not the CI commit — gate FAILS (fail-closed).")
        quit(1)
      if idy.treeDigest != ciTree:
        echo "READINESS_GIT_IDENTITY_MISMATCH treeDigest expected=" & ciTree &
             " actual=" & idy.treeDigest
        logError("readiness_start_gate",
                 "checkout treeDigest is not the CI commit's tree — gate FAILS " &
                 "(fail-closed).")
        quit(1)
      let (marker, ciErr) = ciIdentityMismatch(root, ciHead, ciTree)
      if ciErr != "":
        logError("readiness_start_gate", "evidence identity error: " & ciErr)
        quit(1)
      if marker != "":
        echo marker
        logError("readiness_start_gate",
                 "CI identity mismatch — the evidence snapshot does not " &
                 "describe the CI commit; gate FAILS (fail-closed).")
        quit(1)
  if not compileEvaluator(root):
    quit(1)
  var evalTime = utc(now()).format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  if replay and getEnv(EvalTimeEnv).len > 0:
    evalTime = getEnv(EvalTimeEnv)
    logInfo("readiness_start_gate", "replay eval time pinned: " & evalTime)
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

  # Machine-readable verdict line (stdout, exactly once, GO included). The
  # verdict/conditions strings come verbatim from the evaluator's
  # decision.json; UNKNOWN is the fail-closed token for a verdict outside
  # the evaluator's table. Conditions are semicolon-joined; an empty list
  # leaves the trailing " CONDITIONS " separator with an empty tail.
  var verdictToken = res.verdict
  if verdictToken != "GO" and verdictToken != "CONDITIONAL GO" and
     verdictToken != "NO-GO":
    verdictToken = "UNKNOWN"
  let conditionsLine = join(res.conditions, ";")
  echo "READINESS_VERDICT " & verdictToken & " CONDITIONS " & conditionsLine
  if res.conditions.len > 0:
    echo "::warning::readiness " & verdictToken & ": conditions: " & conditionsLine

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