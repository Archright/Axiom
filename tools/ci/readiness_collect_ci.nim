## tools/ci/readiness_collect_ci.nim — CI readiness evidence collector (R1–R8).
##
## DEBT#537 slice: this collector runs in the follow-up job of
## .github/workflows/axiom-operational-slice.yml after the E2E job produced its
## artifact set. It creates the eight readiness evidence envelopes (R1..R8)
## under data/readiness/evidence/ from THIS checkout and THIS run's artifacts,
## so the readiness verdict (required check) is decided by
## tools/readiness_evaluator.nim over machine measurements instead of a
## hand-maintained committed snapshot.
##
## Contract (measurement-only; the verdict is the gate's, never this tool's):
##   exit 0  = all eight R*.json evidence envelopes were written. Measurement
##             failures (missing artifacts, failed probes) are NOT exit
##             failures: they are recorded honestly as false/null observations
##             plus incidents, and the evaluator/gate judges NO-GO fail-closed.
##   exit 2  = tool failure — the evidence cannot be written at all (repo
##             identity unmeasurable, policy unreadable, out dir unwritable,
##             env/git identity contradiction).
##   stdout  = one summary line per R file written.
##
## Inputs:
##   --repo-root .          checkout root (merge-group checkout in CI)
##   --artifacts <dir>      E2E artifact dir (the `logs/` upload of the
##                          producing job): verify_contract_e2e_report.json,
##                          verify_contract_e2e_report_exit.txt,
##                          verify_contract_e2e_cert_path.txt,
##                          verify_contract_e2e_kernel.out, run-manifest.json,
##                          verify_contract_e2e_state.json (the state the
##                          report was validated against; legacy fallback
##                          ax_proof_state.json), r3_relocation.json (wp5).
##   --out <dir>            evidence dir (default data/readiness/evidence).
##   --policy <file>        config/readiness_policy.json (observation-key and
##                          threshold SSOT; thresholds and key lists are read
##                          from it, never restated here).
##   --ax-bin <path>        the verified CLI binary (default bin/ax).
##   --rust-probe-dir <d>   §10.6 prepare-sequence subject crate
##                          (default tests/fixtures/rust/axiom_rust_probe).
##
## Stamp (every envelope, identical across the eight files so the
## readiness_start_gate repoIdentity merge and the evaluator validation see a
## single coherent identity):
##   repoIdentity{head, treeDigest} = env AXIOM_CI_REPO_HEAD /
##   AXIOM_CI_TREE_DIGEST when set (cross-checked against git, mismatch =
##   exit 2), else `git rev-parse HEAD` / sha256(`git ls-tree -r HEAD`)
##   (tools/ci/wp5_relocation_measure.nim stamp pattern).
##   repoIdentity.branch / workingTreeClean measured BEFORE any file write
##   (`git status --porcelain --untracked-files=no`).
##   collection = {collector: "tools/ci/readiness_collect_ci.nim",
##   method: "automated", generatedAt: now, freshUntil: now +
##   policy.freshness.defaultFreshnessDays}.
##
## Honesty rules (violating any of these is slice failure):
##   * No observation value is taken from the committed
##     data/readiness/evidence snapshot — the existing files are schema
##     learning material only. Every value below is a machine measurement of
##     this checkout, this run's artifacts, or a subprocess probe executed by
##     this collection.
##   * Unmeasurable keys are recorded as JSON null ("UNKNOWN") with the reason
##     in the observation subject, or honestly omitted (string keys), so the
##     evaluator's default direction fails closed; a red light is never
##     fabricated and a missing measurement never becomes a silent PASS.
##   * A probe that cannot run (missing binary/tool) is never converted into a
##     success observation; its envelope is either red or carries no
##     observation at all (R6: empty observations -> evaluator INVALID ->
##     NOT_RUN -> NO-GO).
##
## Observation derivation table (source -> key):
##   R1 documentedCommand      policy r1.contractCommands ∩ README.md text
##     commandExists           `ax help` + `ax <cmd> --help` live probes (bin/ax)
##     promiseOutputExists     E2E report artifact (schemaVersion), subject
##                             "json-report", + resolved certificate artifact
##                             (schemaVersion), subject "certificate" (exactly
##                             policy r1.promiseOutputs tokens)
##     subjectLane             policy r1.trustBoundaryLanes lanes exercised by
##                             this run's subject (Nim kernel target -> "nim";
##                             the rust lane is not exercised by this slice)
##   R2 certGreenDualEvidenceRequired
##                             this run's certificate: status is no stronger
##                             than its stored evidence
##                             (verification_tier.statusConsistentWithEvidence:
##                             certGreen ⇒ Z3 ∧ Lean); cert absent -> null
##     z3OnlyCanProduceCertGreen
##                             this run's cert: certGreen without dual evidence
##                             -> true (red); cert absent -> null (fail-closed)
##     summaryVerifiedIncludesVacuous
##                             report summary arithmetic: verified ==
##                             max(0, statusCounts.verified +
##                             statusCounts.inductive_valid − vacuousCount)
##                             (computeVerified demotes vacuous; the sum form
##                             is the includes-vacuous red state)
##     z3VsDualDistinguishable
##                             report summary.tierCounts carries separate
##                             "z3-verified" and "dual-verified" buckets
##     verifiedSemanticsDocumented
##                             report metrics.vkd: total == policy
##                             r7.vkdContract.vksSize and ratio ==
##                             verified/total (artifact arithmetic, no docs grep)
##   R3 (from logs/r3_relocation.json produced by the E2E job's wp5 step)
##     pathIndependentProjectionEqual, subjectRunProjectionHashEqual,
##     negativeControlDigestDifferent, commentOnlyProjectionStable,
##     cachePolicy            carried verbatim (this run's measurement)
##     canonicalProjectionHashEqual
##                             two live `ax report --canonical-digest
##                             --state-file <artifacts>/ax_proof_state.json`
##                             runs in this checkout
##     canonicalInputHash     resolved certificate inputHash
##     configHash             ax_proof_state.executionIdentity.executionConfigDigest
##     solverIdentity         certificate toolchainIdentity.z3 / solverInvocation
##     canonicalExecutionFingerprint
##                             sha256(nim=..|z3=..|lean=..|buildSourceHash=..|
##                             scopeHash=..) over run-manifest identity fields
##                             (same formula as the wp5 stamp)
##     environmentControlled  observed toolchain vs the run's declared
##                             toolchain identity (cert/manifest)
##   R4 certFieldPresent      resolved certificate, policy r4.requiredFields
##     provenanceReconstructible
##                             run-manifest ↔ cert/report/state/kernel-out/
##                             cert-path join checks (field correspondence)
##     subjectTreeImmutableAcrossRun
##                             git status (tracked mutations) before any write
##   R5 commandExists/helpSurface
##                             live command probes; helpSurface additionally
##                             requires the dedicated help path to print a
##                             usage surface naming the command
##     successExitCode        a REAL successful execution of the command
##                             (`ax report --json --state-file` exit 0);
##                             `ax prove` has no independent success run, so
##                             no observation is minted (R5 UNKNOWN). Subject
##                             == the contract command — the evaluator's R5
##                             join key (every exit-code bucket of a command
##                             shares one subject; provenance rides in the
##                             scope field, "observed" vs "contract")
##     verificationFailureExitCode
##                             report exit artifact when it actuates 1, else
##                             policy r5.exitCodeContract (scope "contract")
##     invalidInputExitCode   live invalid-input probe exit (3), else policy
##                             contract value (scope "contract")
##     internalErrorExitCode  policy r5.exitCodeContract (scope "contract";
##                             not safely inducible)
##     jsonSchemaVersion      report artifact schemaVersion (absent -> null ->
##                             FAIL direction)
##     stdoutStderrSplit      live `ax report --json --state-file <state>`:
##                             stdout pure JSON, logger lines on stderr
##   R6 failureConvertsToSuccess
##                             live failure probes (unknown option, unknown
##                             subcommand, nonexistent state file) — true only
##                             if some failure probe exits 0 (red)
##     exceptionSwallowed     every nonzero-exit probe surfaces an error
##                             marker on stdout/stderr
##   R7 claimedScope          policy r7.coverageSubjects
##     measuredCoverage       report metrics.vkd.ratio (the run's canonical
##                             VKD exposure, journal-driven)
##     verifiedEmitterScope   ["vkd"] iff the report emits metrics.vkd
##   R8 installFollowed       observed nim/z3/lean + `ax --version` exit 0
##     manualStepsRequired    false: every command ran non-interactively in
##                             this automated collection (CI env corroborated)
##     cleanRunSucceeded      E2E report verdict PASS + exit 0 (absent -> false)
##     documentedRunSteps     README run flow + contract §10.6 prepare
##                             sequence verbatim in the checkout
##     (cold-set purge is incident R8-COLD-001, not an observation key:
##      it is not machine-observable from the downloaded artifact set and is
##      never fabricated into an observation)
##     commands               §10.6 prepare sequence executed here against
##                             --rust-probe-dir when cargo + the crate exist;
##                             otherwise honestly absent (ruleR8 fails closed)
##
## Build (Makefile target bin/readiness_collect_ci):
##   AXIOM_HERMETIC_BUILDING=1 nim c --path:src -d:release --hints:off \
##     --nimcache:build/nimcache/c2_collector -o:bin/readiness_collect_ci \
##     tools/ci/readiness_collect_ci.nim
##
## Exit codes: 0 = evidence written; 2 = tool failure.

import std/[os, osproc, json, strutils, times, sequtils, streams]
import core/crypto/hash_kernel
import core/types/verification_tier

const
  DefaultPolicyPath = "config" / "readiness_policy.json"
  DefaultOutDir = "data" / "readiness" / "evidence"
  DefaultAxPath = "bin" / "ax"
  DefaultRustProbeDir = "tests" / "fixtures" / "rust" / "axiom_rust_probe"
  DefaultFreshnessDays = 30
  CollectorName = "tools/ci/readiness_collect_ci.nim"

proc die(msg: string, code = 2) {.noreturn.} =
  stderr.writeLine("[readiness_collect_ci] " & msg)
  quit(code)

# ---------------------------------------------------------------------------
# Subprocess / file I/O helpers (I/O boundary; the only impure layer)
# ---------------------------------------------------------------------------

type
  RunResult = object
    exitCode: int
    stdout: string
    stderr: string

proc safeReadFile(p: string): string =
  ## readFile that degrades to "" (an unreadable doc then measures honestly
  ## as "not documented" instead of crashing the collector).
  try:
    readFile(p)
  except CatchableError:
    ""

proc runSplit(bin: string, args: seq[string], workingDir: string): RunResult =
  ## Spawn a real binary; capture stdout/stderr separately (honest actuation).
  ## Same shape as tools/collect_evidence_probe.nim — the ax CLI writes its
  ## usage text through the logger on stderr, so surface checks merge streams
  ## explicitly where a merged view is needed.
  let p = startProcess(bin, workingDir = workingDir, args = args,
                       options = {poUsePath})
  result.stdout = p.outputStream.readAll()
  result.stderr = p.errorStream.readAll()
  result.exitCode = waitForExit(p)
  close(p)

proc shellOut(cmdline: string, workingDir: string): tuple[outp: string, code: int] =
  let (output, code) = execCmdEx(cmdline, workingDir = workingDir)
  (output, code)

proc shellTrim(cmdline: string, workingDir: string): string =
  ## Trimmed stdout of a shell command; "" on failure (caller decides whether
  ## absence is fatal).
  let (o, c) = shellOut(cmdline, workingDir)
  if c != 0: "" else: o.strip()

proc shaFile(p: string): string =
  sha256Hex(readFile(p))

proc safeParseFile(p: string): tuple[node: JsonNode, err: string] =
  ## parseFile without exceptions; the caller records the failure honestly.
  if not fileExists(p):
    return (nil, "file does not exist: " & p)
  try:
    (parseFile(p), "")
  except CatchableError as e:
    (nil, "unparsable JSON: " & e.msg)

# ---------------------------------------------------------------------------
# Pure helpers
# ---------------------------------------------------------------------------

proc isoNow(): string =
  now().toTime.utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc isoPlusDays(days: int): string =
  format(now().toTime + initDuration(days = days),
         "yyyy-MM-dd'T'HH:mm:ss'Z'")

func firstLine(s: string): string =
  for line in s.splitLines():
    let t = line.strip()
    if t.len > 0:
      return t
  ""

func shortVersion(s: string): string =
  ## First x.y[.z]-shaped token of a version line ("Nim Compiler Version
  ## 2.2.10 [Linux: amd64]" -> "2.2.10"). Empty when none found.
  var i = 0
  while i < s.len:
    if s[i].isDigit:
      var j = i
      while j < s.len and (s[j].isDigit or s[j] == '.'):
        inc j
      let tok = s[i ..< j]
      if tok.count('.') >= 1 and tok.len > 1 and tok[0].isDigit and tok[^1].isDigit:
        return tok
      i = j
    else:
      inc i
  ""

func isHex64(s: string): bool {.raises: [].} =
  s.len == 64 and s.allCharsInSet(HexDigits)

func hex64Line(output: string): string =
  ## First 64-hex line of a CLI output (canonical-digest surface).
  for line in output.splitLines():
    let t = line.strip()
    if isHex64(t):
      return t
  ""

func jStr(node: JsonNode, key: string): string =
  if node != nil and node.kind == JObject:
    let v = node{key}
    if v != nil and v.kind == JString: v.getStr() else: ""
  else: ""

func jInt(node: JsonNode, key: string, default = 0): int =
  if node != nil and node.kind == JObject:
    let v = node{key}
    if v != nil and v.kind in {JInt, JFloat}:
      return (if v.kind == JInt: v.getInt() else: int(v.getFloat()))
  default

func jFloat(node: JsonNode, key: string, default = 0.0): float =
  if node != nil and node.kind == JObject:
    let v = node{key}
    if v != nil and v.kind == JFloat: return v.getFloat()
    if v != nil and v.kind == JInt: return float(v.getInt())
  default

func jObj(node: JsonNode, key: string): JsonNode =
  if node != nil and node.kind == JObject:
    let v = node{key}
    if v != nil and v.kind == JObject: v else: nil
  else: nil

func jArr(node: JsonNode, key: string): JsonNode =
  if node != nil and node.kind == JObject:
    let v = node{key}
    if v != nil and v.kind == JArray: v else: nil
  else: nil

func strSeq(node: JsonNode): seq[string] {.raises: [].} =
  result = @[]
  if node != nil and node.kind == JArray:
    for it in node.items:
      if it.kind == JString and it.getStr() != "":
        result.add(it.getStr())

func policyStrSeq(policy: JsonNode, section, key: string): seq[string] =
  strSeq(jArr(jObj(policy, section), key))

func fieldNonEmpty(node: JsonNode, key: string): bool =
  ## A required certificate field is present when the top-level key exists and
  ## is neither null, nor an empty string, nor an empty object.
  if node == nil or node.kind != JObject or not node.hasKey(key):
    return false
  let v = node[key]
  case v.kind
  of JNull: false
  of JString: v.getStr().len > 0
  of JObject: v.len > 0
  else: true

func collapseSpaces(s: string): string =
  ## Runs of whitespace -> single spaces (structure checks must not depend on
  ## source indentation).
  result = newStringOfCap(s.len)
  var prevSpace = false
  for ch in s:
    if ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r':
      if not prevSpace:
        result.add(' ')
      prevSpace = true
    else:
      result.add(ch)
      prevSpace = false

func max0(n: int): int =
  if n < 0: 0 else: n

func cmdRecord(cmd: string, r: RunResult): JsonNode =
  %*{"cmd": cmd, "exitCode": r.exitCode,
      "stdoutDigest": sha256Hex(r.stdout),
      "stderrDigest": sha256Hex(r.stderr),
      "outputDigest": sha256Hex(r.stdout & r.stderr)}

# ---------------------------------------------------------------------------
# Observation constructors (schema: key/value/scope/subject)
# ---------------------------------------------------------------------------

func obsNull(key, scope, subject: string): JsonNode =
  ## UNKNOWN marker: a bool key whose evaluator default is the fail direction
  ## (R2 z3OnlyCanProduceCertGreen / summaryVerifiedIncludesVacuous,
  ## R5 jsonSchemaVersion) fails closed on a null value; boolValue(v, def)
  ## returns the default for non-bool values by design.
  %*{"key": key, "value": newJNull(), "scope": scope, "subject": subject}

func obsBool(key: string, value: bool, scope, subject: string): JsonNode =
  %*{"key": key, "value": value, "scope": scope, "subject": subject}

func obsInt(key: string, value: int, scope, subject: string): JsonNode =
  %*{"key": key, "value": value, "scope": scope, "subject": subject}

func obsFloat(key: string, value: float, scope, subject: string): JsonNode =
  %*{"key": key, "value": value, "scope": scope, "subject": subject}

func obsStr(key: string, value: string, scope, subject: string): JsonNode =
  %*{"key": key, "value": value, "scope": scope, "subject": subject}

func obsStrList(key: string, value: seq[string], scope, subject: string): JsonNode =
  let arr = newJArray()
  for v in value:
    arr.add(%v)
  %*{"key": key, "value": arr, "scope": scope, "subject": subject}

func incident(id, severity, summary: string): JsonNode =
  %*{"id": id, "severity": severity, "summary": summary}

func sourceEntry(file, sha, repoHead, symbol: string): JsonNode =
  %*{"file": file, "sha256": sha, "repoHead": repoHead, "symbol": symbol}

# ---------------------------------------------------------------------------
# Shared measurement record
# ---------------------------------------------------------------------------

type
  Stamp = object
    head: string
    branch: string
    treeDigest: string
    workingTreeClean: bool
    nimLine: string
    z3Line: string
    leanLine: string
    generatedAt: string
    freshUntil: string

  Artifacts = object
    dir: string
    report: JsonNode            ## parsed E2E report (nil = absent/unparsable)
    reportErr: string
    reportExit: int
    reportExitOk: bool
    certPathDeclared: string    ## trimmed content of cert_path.txt
    certPath: string            ## resolved path ("" = not found)
    cert: JsonNode
    certErr: string
    kernelOut: string
    kernelOutOk: bool
    manifest: JsonNode
    manifestErr: string
    state: JsonNode
    stateErr: string
    statePath: string           ## resolved E2E state artifact (alias preferred)
    wp5: JsonNode               ## parsed logs/r3_relocation.json
    wp5Err: string

  Probes = object
    axBin: string
    axPresent: bool
    version: RunResult
    help: RunResult
    proveHelp: RunResult
    reportHelp: RunResult
    reportJson: RunResult       ## ax report --json --state-file <state>
    canon1: RunResult
    canon2: RunResult
    unknownOption: RunResult    ## ax prove --definitely-unknown-option-xyz
    unknownSubcmd: RunResult    ## ax garbage-subcommand-xyz
    missingStateFile: RunResult ## ax report --json --state-file <absent>

func jSeq(items: seq[JsonNode]): JsonNode =
  let arr = newJArray()
  for it in items:
    arr.add(it)
  arr

func makeEnvelope(invId: string, stamp: Stamp, observations: seq[JsonNode],
                  incidents: seq[JsonNode], sources: seq[JsonNode],
                  commands: seq[JsonNode]): JsonNode =
  result = newJObject()
  result["schemaVersion"] = %1
  result["invariantId"] = %invId
  result["repoIdentity"] = %*{"head": stamp.head, "branch": stamp.branch,
                              "workingTreeClean": stamp.workingTreeClean,
                              "treeDigest": stamp.treeDigest}
  let tc = newJObject()
  if stamp.nimLine.len > 0: tc["nim"] = %stamp.nimLine
  if stamp.z3Line.len > 0: tc["z3"] = %stamp.z3Line
  if stamp.leanLine.len > 0: tc["lean"] = %stamp.leanLine
  result["toolchain"] = tc
  result["collection"] = %*{"collector": CollectorName,
                            "method": "automated",
                            "generatedAt": stamp.generatedAt,
                            "freshUntil": stamp.freshUntil}
  result["observations"] = jSeq(observations)
  result["incidents"] = jSeq(incidents)
  result["sources"] = jSeq(sources)
  result["commands"] = jSeq(commands)

proc writeEnvelope(path: string, envelope: JsonNode) =
  ## The only evidence-writing path: failure to write is tool failure (exit 2).
  try:
    writeFile(path, envelope.pretty())
  except CatchableError as e:
    die("cannot write evidence file (tool failure): " & path & ": " & e.msg)

proc repoRelPath(repoRoot, p: string): string =
  ## Path relative to the repo root for source entries (deterministic record).
  let abs = absolutePath(p, getCurrentDir())
  let root = absolutePath(repoRoot, getCurrentDir())
  if abs.startsWith(root & DirSep):
    abs.substr(root.len + 1)
  else:
    p

proc addSourceIf(sources: var seq[JsonNode], repoRoot, rel, head, symbol: string) =
  let p = repoRoot / rel
  if fileExists(p):
    sources.add(sourceEntry(rel, "sha256:" & shaFile(p), head, symbol))

proc addArtifactSource(sources: var seq[JsonNode], artifactsDir, name, head,
                       symbol: string) =
  let p = artifactsDir / name
  if fileExists(p):
    sources.add(sourceEntry(name, "sha256:" & shaFile(p), head, symbol))

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

when isMainModule:
  var
    repoRoot = ""
    artifactsDir = ""
    outDir = DefaultOutDir
    policyPath = DefaultPolicyPath
    axBinArg = ""
    rustProbeDir = DefaultRustProbeDir
  var i = 0
  let cliArgs = commandLineParams()
  proc needValue(flag: string): string =
    if i >= cliArgs.len - 1:
      die("missing value for " & flag)
    inc i
    cliArgs[i]
  while i < cliArgs.len:
    let a = cliArgs[i]
    case a
    of "--repo-root": repoRoot = needValue(a)
    of "--artifacts": artifactsDir = needValue(a)
    of "--out": outDir = needValue(a)
    of "--policy": policyPath = needValue(a)
    of "--ax-bin": axBinArg = needValue(a)
    of "--rust-probe-dir": rustProbeDir = needValue(a)
    of "--help", "-h":
      echo "usage: readiness_collect_ci --repo-root D --artifacts D " &
           "[--out D] [--policy F] [--ax-bin P] [--rust-probe-dir D]"
      quit(0)
    else:
      die("unknown option: " & a)
    inc i
  if repoRoot.len == 0 or artifactsDir.len == 0:
    die("usage: readiness_collect_ci --repo-root D --artifacts D " &
        "[--out D] [--policy F] [--ax-bin P] [--rust-probe-dir D]")
  if not dirExists(repoRoot):
    die("repo root does not exist: " & repoRoot)
  if not dirExists(artifactsDir):
    # An absent artifacts dir is a MEASUREMENT condition (the E2E job produced
    # nothing this collector can observe), not a tool failure: the eight
    # envelopes are still minted with honest absence observations.
    stderr.writeLine("[readiness_collect_ci] WARNING: artifacts dir does not " &
                     "exist (all artifact-derived observations will record " &
                     "absence): " & artifactsDir)
  let policyRes = safeParseFile(repoRoot / policyPath)
  if policyRes.err != "":
    die("cannot read policy (tool failure — policy is the observation-key " &
        "SSOT): " & policyPath & ": " & policyRes.err)
  let policy = policyRes.node
  let freshnessDays =
    if policy.hasKey("freshness"):
      jInt(policy, "defaultFreshnessDays", DefaultFreshnessDays)
    else:
      DefaultFreshnessDays
  if freshnessDays <= 0:
    die("policy freshness.defaultFreshnessDays must be positive")

  # ── repository identity stamp (measured BEFORE any file write) ───────────
  let gitHead = shellTrim("git rev-parse HEAD", repoRoot)
  let envHead = getEnv("AXIOM_CI_REPO_HEAD")
  let envTree = getEnv("AXIOM_CI_TREE_DIGEST")
  var
    stampHead = ""
    stampTree = ""
  if gitHead.len == 0 and envHead.len == 0:
    die("repo identity unmeasurable: git rev-parse HEAD failed and " &
        "AXIOM_CI_REPO_HEAD is not set")
  if envHead.len > 0:
    if gitHead.len > 0 and envHead != gitHead:
      die("identity contradiction: AXIOM_CI_REPO_HEAD=" & envHead &
          " != git HEAD=" & gitHead)
    stampHead = envHead
  else:
    stampHead = gitHead
  if envTree.len > 0:
    stampTree = envTree
  else:
    let ls = shellTrim("git ls-tree -r HEAD", repoRoot)
    if ls.len == 0:
      die("repo identity unmeasurable: git ls-tree -r HEAD produced no output")
    stampTree = sha256Hex(ls)
  let gitBranch = shellTrim("git rev-parse --abbrev-ref HEAD", repoRoot)
  let porcelain = shellTrim("git status --porcelain --untracked-files=no", repoRoot)
  let stamp = Stamp(
    head: stampHead,
    branch: (if gitBranch.len > 0: gitBranch else: "unknown"),
    treeDigest: stampTree,
    workingTreeClean: porcelain.len == 0,
    nimLine: firstLine(shellTrim("nim --version", repoRoot)),
    z3Line: firstLine(shellTrim("z3 --version", repoRoot)),
    leanLine: firstLine(shellTrim("lean --version", repoRoot)),
    generatedAt: isoNow(),
    freshUntil: isoPlusDays(freshnessDays))
  echo "[readiness_collect_ci] repoHead=" & stamp.head
  echo "[readiness_collect_ci] branch=" & stamp.branch
  echo "[readiness_collect_ci] treeDigest=" & stamp.treeDigest
  echo "[readiness_collect_ci] workingTreeClean=" & $stamp.workingTreeClean
  echo "[readiness_collect_ci] toolchain: nim='" & stamp.nimLine &
       "' z3='" & stamp.z3Line & "' lean='" & stamp.leanLine & "'"

  # ── E2E artifacts (absence is a recorded measurement, never fatal) ───────
  var art = Artifacts(dir: artifactsDir)
  block report:
    let r = safeParseFile(artifactsDir / "verify_contract_e2e_report.json")
    art.report = r.node
    art.reportErr = r.err
  block reportExit:
    art.reportExitOk = false
    art.reportExit = -1
    let p = artifactsDir / "verify_contract_e2e_report_exit.txt"
    if fileExists(p):
      try:
        art.reportExit = readFile(p).strip().parseInt()
        art.reportExitOk = true
      except CatchableError:
        discard # axiom:best-effort(unparseable exit file records reportExit as unmeasured; the observation honestly stays unset)
  block cert:
    art.certPathDeclared = ""
    let p = artifactsDir / "verify_contract_e2e_cert_path.txt"
    if fileExists(p):
      art.certPathDeclared = safeReadFile(p).strip()
    art.certPath = ""
    if art.certPathDeclared.len > 0:
      # Resolution chain: the path recorded by the E2E job is repo-root
      # relative; when the certificate was not restored into this checkout it
      # may ride alongside the downloaded artifacts under its basename (or
      # under its declared relative path inside the artifact dir). The fourth
      # candidate is the fixed transport alias: the producer job copies the
      # declared certificate to <artifacts>/e2e_certificate.json so the
      # evidence artifact stays single-rooted — the alias carries no path
      # identity of its own; its binding to this run is enforced by the R4
      # joins (manifest.certificate.identityDigest/sha256 == cert values).
      for cand in [repoRoot / art.certPathDeclared,
                   artifactsDir / art.certPathDeclared.splitPath().tail,
                   artifactsDir / art.certPathDeclared,
                   artifactsDir / "e2e_certificate.json"]:
        if fileExists(cand):
          art.certPath = cand
          break
    let r = safeParseFile(art.certPath)
    art.cert = r.node
    art.certErr = (if art.certPath.len == 0: "certificate artifact not found (declared path: " &
                      (if art.certPathDeclared.len > 0: art.certPathDeclared else: "<none>") & ")"
                   else: r.err)
  block kernel:
    let p = artifactsDir / "verify_contract_e2e_kernel.out"
    art.kernelOutOk = fileExists(p)
    art.kernelOut = (if art.kernelOutOk: safeReadFile(p) else: "")
  block manifest:
    let r = safeParseFile(artifactsDir / "run-manifest.json")
    art.manifest = r.node
    art.manifestErr = r.err
  block state:
    # The producer snapshots the state it validated against the E2E report as
    # verify_contract_e2e_state.json (fixed transport alias, same pattern as
    # e2e_certificate.json): later steps in the producing job run their own
    # proves against the default logs/ax_proof_state.json and would otherwise
    # leave a foreign run's state under the artifact name. The alias is
    # preferred; the legacy name is the fallback for producers without it.
    art.statePath = artifactsDir / "verify_contract_e2e_state.json"
    if not fileExists(art.statePath):
      art.statePath = artifactsDir / "ax_proof_state.json"
    let r = safeParseFile(art.statePath)
    art.state = r.node
    art.stateErr = r.err
  block wp5:
    let r = safeParseFile(artifactsDir / "r3_relocation.json")
    art.wp5 = r.node
    art.wp5Err = r.err
    if art.wp5 != nil and jStr(art.wp5, "invariantId") != "R3":
      art.wp5 = nil
      art.wp5Err = "r3_relocation.json is not an R3 envelope (invariantId=" &
                   jStr(art.wp5, "invariantId") & ")"

  # ── CLI probes (bin/ax absent or failing is a recorded measurement) ──────
  let axBin = (if axBinArg.len > 0: axBinArg else: repoRoot / DefaultAxPath)
  var pr = Probes(axBin: axBin, axPresent: fileExists(axBin))
  if pr.axPresent:
    pr.version = runSplit(axBin, @["--version"], repoRoot)
    pr.help = runSplit(axBin, @["help"], repoRoot)
    pr.proveHelp = runSplit(axBin, @["prove", "--help"], repoRoot)
    pr.reportHelp = runSplit(axBin, @["report", "--help"], repoRoot)
    # The success/canonical probes consume the SAME state artifact the report
    # was validated against (alias resolution in the state block above), so a
    # probe can never mint evidence from a different run's state.
    let stateArg = art.statePath
    pr.reportJson = runSplit(axBin, @["report", "--json", "--state-file", stateArg], repoRoot)
    pr.canon1 = runSplit(axBin, @["report", "--canonical-digest", "--state-file", stateArg], repoRoot)
    pr.canon2 = runSplit(axBin, @["report", "--canonical-digest", "--state-file", stateArg], repoRoot)
    pr.unknownOption = runSplit(axBin, @["prove", "--definitely-unknown-option-xyz"], repoRoot)
    pr.unknownSubcmd = runSplit(axBin, @["garbage-subcommand-xyz"], repoRoot)
    let missingPath = artifactsDir / "definitely-absent-state-file.json"
    pr.missingStateFile = runSplit(axBin, @["report", "--json", "--state-file", missingPath], repoRoot)
  else:
    stderr.writeLine("[readiness_collect_ci] WARNING: " & axBin &
                     " not found — CLI-surface observations (R1 commandExists, " &
                     "R5 exit codes, R6 failure probes) record honest absence")

  # ── R8 §10.6 prepare sequence (only when actually runnable here) ─────────
  var
    r8Prepare: seq[JsonNode] = @[]
    r8PrepareIncidents: seq[JsonNode] = @[]
    cargoRan = false
  let cargoExe = findExe("cargo")
  let probeRoot = (if rustProbeDir.isAbsolute: rustProbeDir else: repoRoot / rustProbeDir)
  let probeManifest = probeRoot / "Cargo.toml"
  let probeLock = probeRoot / "Cargo.lock"
  if cargoExe.len == 0:
    r8PrepareIncidents.add(incident(
      "R8-PREP-001", "warning",
      "cargo not found on PATH; §10.6 prepare sequence not executed in this " &
      "collection — commands honestly absent (ruleR8 fails closed; install " &
      "the Rust toolchain in the job to actuate the sequence)"))
  elif not fileExists(probeManifest) or not fileExists(probeLock):
    r8PrepareIncidents.add(incident(
      "R8-PREP-002", "warning",
      "Rust probe crate incomplete at " & rustProbeDir &
      " (Cargo.toml/Cargo.lock required); prepare sequence not executed — " &
      "commands honestly absent"))
  else:
    cargoRan = true
    let fetchRes = runSplit("cargo", @["fetch", "--locked"], probeRoot)
    let metaRes = runSplit("cargo", @["metadata", "--format-version=1", "--locked"], probeRoot)
    let buildRes = runSplit("cargo", @["build", "--frozen"], probeRoot)
    r8Prepare.add(cmdRecord("cargo fetch --locked", fetchRes))
    r8Prepare.add(cmdRecord("cargo metadata --format-version=1 --locked", metaRes))
    r8Prepare.add(cmdRecord("cargo build --frozen", buildRes))
    let prepChecks: seq[tuple[id: string, c: string, r: RunResult]] = @[
      ("R8-PREP-003", "cargo fetch --locked", fetchRes),
      ("R8-PREP-004", "cargo metadata --format-version=1 --locked", metaRes),
      ("R8-PREP-005", "cargo build --frozen", buildRes)]
    for chk in prepChecks:
      if chk.r.exitCode != 0:
        r8PrepareIncidents.add(incident(
          chk.id, "warning", chk.c & " exited " & $chk.r.exitCode &
          " (recorded truthfully; exit 0 required)"))

  # ── policy projections used by several invariants ───────────────────────
  let r1Commands = policyStrSeq(policy, "r1", "contractCommands")
  let r5Commands = policyStrSeq(policy, "r5", "contractCommands")
  let r4Fields = policyStrSeq(policy, "r4", "requiredFields")
  let r7Subjects = policyStrSeq(policy, "r7", "coverageSubjects")
  let r8Sequence = policyStrSeq(policy, "r8", "prepareSequenceCommands")
  let vksSize = jInt(jObj(jObj(policy, "r7"), "vkdContract"), "vksSize", 23)

  # exit-code contract, read from policy r5.exitCodeContract (keys are code
  # strings, values name the class; never hardcoded here)
  var
    successCode = 0
    verifFailCode = 1
    invalidCode = 3
    internalCode = 2
  block exitCodes:
    successCode = jInt(jObj(policy, "r5"), "successExitCode", 0)
    let ecc = jObj(jObj(policy, "r5"), "exitCodeContract")
    if ecc != nil:
      for k, v in ecc.pairs:
        if k.len == 0 or not k.allCharsInSet(Digits):
          continue
        let desc = (if v.kind == JString: v.getStr() else: "").toLowerAscii()
        if "success" in desc: successCode = k.parseInt()
        elif "verification-failure" in desc: verifFailCode = k.parseInt()
        elif "internal" in desc: internalCode = k.parseInt()
        elif "invalid" in desc: invalidCode = k.parseInt()

  let readmeText = safeReadFile(repoRoot / "README.md")
  let contractPath = repoRoot / "docs" / "spec" / "productization_contract.md"
  let contractText = safeReadFile(contractPath)

  try:
    createDir(outDir)
  except CatchableError as e:
    die("cannot create evidence out dir (tool failure): " & outDir & ": " & e.msg)

  # ═════════════════════════════════════════════════════════════ R1 ═══════
  block r1:
    var
      obs: seq[JsonNode] = @[]
      inc: seq[JsonNode] = @[]
      src: seq[JsonNode] = @[]
      cmds: seq[JsonNode] = @[]
    # documentedCommand: the policy contract commands that this checkout's
    # README actually documents (single array-valued observation — per-token
    # observations would collide in normalizeBundle).
    var documented: seq[string] = @[]
    for c in r1Commands:
      if c in readmeText:
        documented.add(c)
    for c in r1Commands:
      if c notin documented:
        inc.add(incident("R1-DOC-001", "warning",
                         "contract command '" & c & "' not found in README.md " &
                         "(documentedCommand records the documented subset only; " &
                         "commandExistence is still measured below)"))
    obs.add(obsStrList("documentedCommand", documented, "doc",
                       "policy r1.contractCommands ∩ README.md text (this checkout)"))
    # commandExists: live surface probes.
    let helpOut = (if pr.axPresent: pr.help.stdout & "\n" & pr.help.stderr else: "")
    for cmd in r1Commands:
      let sub = cmd.split(' ')[1 .. ^1].join(" ")
      let dedicated = (if sub == "prove": pr.proveHelp elif sub == "report": pr.reportHelp
                       else: RunResult(exitCode: -1, stdout: "", stderr: ""))
      let exists = pr.axPresent and
                   pr.help.exitCode == 0 and sub in helpOut and
                   dedicated.exitCode == 0
      obs.add(obsBool("commandExists", exists, "surface", cmd))
    if not pr.axPresent:
      inc.add(incident("R1-OBS-001", "warning",
                       "bin/ax absent — commandExists for every contract command " &
                       "measured false (command not actuable in this collection)"))
    # promiseOutputExists: this run's E2E artifacts. Subjects are EXACTLY the
    # policy r1.promiseOutputs tokens — the evaluator joins on subject, so a
    # descriptive string would be an unrelated key and could never satisfy
    # closure (DEBT#559).
    let reportSchema = jStr(art.report, "schemaVersion")
    let promiseJson = art.report != nil and reportSchema == "axiom.report.v1"
    obs.add(obsBool("promiseOutputExists", promiseJson, "artifact", "json-report"))
    let certSchema = jStr(art.cert, "schemaVersion")
    let promiseCert = art.cert != nil and certSchema == "axiom.certificate.v3"
    obs.add(obsBool("promiseOutputExists", promiseCert, "artifact", "certificate"))
    if not promiseJson:
      inc.add(incident("R1-OBS-002", "warning",
                       "E2E report artifact absent or wrong schema (" & art.reportErr &
                       ") — promiseOutputExists measured false"))
    if not promiseCert:
      inc.add(incident("R1-OBS-003", "warning",
                       "certificate artifact unresolvable (" & art.certErr &
                       ") — promiseOutputExists measured false"))
    # subjectLane: the trust-boundary lanes exercised by THIS run's subjects.
    # The E2E target (run-manifest target.nodeId) is a Nim source path; the
    # rust lane is not exercised by this slice — claiming it would be an
    # unmeasured overclaim.
    let lanes = jObj(jObj(policy, "r1"), "trustBoundaryLanes")
    var claimedLanes: seq[string] = @[]
    let targetNode = jStr(jObj(art.manifest, "target"), "nodeId")
    if targetNode.contains(".nim::") and lanes != nil and lanes.hasKey("nim"):
      claimedLanes.add("nim")
    obs.add(obsStrList("subjectLane", claimedLanes, "trust-boundary",
                       "policy r1.trustBoundaryLanes lanes exercised by this run's " &
                       "subject (E2E target " &
                       (if targetNode.len > 0: targetNode else: "<manifest absent>") &
                       " is a Nim source; rust lane not exercised)"))
    if not stamp.workingTreeClean:
      inc.add(incident("R1-OBS-004", "warning",
                       "working tree not clean at collection time — R1 evidence " &
                       "requires a clean tree per the evaluator (envelope will be " &
                       "invalidated)"))
    if pr.axPresent:
      cmds.add(cmdRecord("bin/ax --version", pr.version))
      cmds.add(cmdRecord("bin/ax help", pr.help))
      cmds.add(cmdRecord("bin/ax prove --help", pr.proveHelp))
      cmds.add(cmdRecord("bin/ax report --help", pr.reportHelp))
    src.add(sourceEntry("config/readiness_policy.json",
                        "sha256:" & shaFile(repoRoot / policyPath), stamp.head,
                        "r1.contractCommands / trustBoundaryLanes"))
    addSourceIf(src, repoRoot, "README.md", stamp.head, "documented run steps")
    addSourceIf(src, repoRoot, "docs/spec/productization_contract.md", stamp.head,
                "R1 contract")
    if art.report != nil:
      addArtifactSource(src, art.dir, "verify_contract_e2e_report.json", stamp.head,
                        "E2E report artifact (promiseOutput)")
    if art.certPath.len > 0:
      src.add(sourceEntry(repoRelPath(repoRoot, art.certPath),
                          "sha256:" & shaFile(art.certPath), stamp.head,
                          "certificate artifact (promiseOutput)"))
    let envelope = makeEnvelope("R1", stamp, obs, inc, src, cmds)
    writeEnvelope(outDir / "R1.json", envelope)
    echo "[readiness_collect_ci] wrote " & (outDir / "R1.json") &
         " — observations=" & $obs.len

  # ═════════════════════════════════════════════════════════════ R2 ═══════
  block r2:
    var
      obs: seq[JsonNode] = @[]
      inc: seq[JsonNode] = @[]
      src: seq[JsonNode] = @[]
      cmds: seq[JsonNode] = @[]
    # certGreenDualEvidenceRequired: this run's certificate status must be
    # consistent with its stored evidence (certGreen ⟹ Z3 ∧ Lean), judged by
    # the single trust reader in core/types/verification_tier.nim. No source
    # grep: only stored evidence counts. Cert absent -> null (UNKNOWN).
    var certEvidence = CertificateEvidence()
    if art.cert != nil:
      certEvidence = certificateEvidenceFromJson(art.cert)
      obs.add(obsBool("certGreenDualEvidenceRequired",
                      statusConsistentWithEvidence(art.cert), "observed",
                      "certificate status=" & jStr(art.cert, "status") &
                      " consistent with stored evidence (z3Passed=" &
                      $certEvidence.z3Passed & ", leanVerified=" &
                      $certEvidence.leanVerified &
                      ") via verification_tier.statusConsistentWithEvidence"))
    else:
      obs.add(obsNull("certGreenDualEvidenceRequired", "observed",
                      "unmeasured: certificate artifact absent (" & art.certErr &
                      ") — UNKNOWN, never an implicit PASS"))
      inc.add(incident("R2-CERT-001", "warning",
                       "certificate artifact absent — certGreenDualEvidenceRequired " &
                       "recorded UNKNOWN (no source-structure substitute)"))
    # z3OnlyCanProduceCertGreen: red only when this run's cert declares
    # certGreen WITHOUT dual evidence; cert absent -> null (fail-closed).
    if art.cert != nil:
      let status = jStr(art.cert, "status")
      let z3OnlyGreen = status == "certGreen" and
                        not (certEvidence.z3Passed and certEvidence.leanVerified)
      obs.add(obsBool("z3OnlyCanProduceCertGreen", z3OnlyGreen, "canonical",
                      "cert status=" & status & " verificationTier=" &
                      jStr(art.cert, "verificationTier") &
                      " — z3-only never produced certGreen in this run"))
    else:
      obs.add(obsNull("z3OnlyCanProduceCertGreen", "canonical",
                      "unmeasured: certificate artifact absent (" & art.certErr &
                      ") — UNKNOWN, evaluator default is the FAIL direction"))
    # summaryVerifiedIncludesVacuous: report summary arithmetic.
    if art.report != nil:
      let summary = jObj(art.report, "summary")
      let statusCounts = jObj(summary, "statusCounts")
      let verified = jInt(summary, "verified", -1)
      let rawVerified = jInt(statusCounts, "verified", -1)
      let inductive = jInt(statusCounts, "inductive_valid", -1)
      let vacuous = jInt(summary, "vacuousCount", -1)
      if verified >= 0 and rawVerified >= 0 and inductive >= 0 and vacuous >= 0:
        let demoted = verified == max0(rawVerified + inductive - vacuous)
        let included = verified == rawVerified + inductive + vacuous
        if included and not demoted:
          obs.add(obsBool("summaryVerifiedIncludesVacuous", true, "summary",
                          "verified == statusCounts.verified + inductive_valid + " &
                          "vacuousCount — the summary folds vacuous into verified"))
        elif demoted:
          # demoted holds (also when vacuous == 0, where both arithmetic forms
          # coincide and no vacuous proof exists to fold in)
          obs.add(obsBool("summaryVerifiedIncludesVacuous", false, "summary",
                          "verified == max(0, statusCounts.verified + " &
                          "statusCounts.inductive_valid − vacuousCount) = " &
                          $max0(rawVerified + inductive - vacuous) &
                          " (computeVerified demotes vacuous; vacuous=" & $vacuous & ")"))
        else:
          obs.add(obsNull("summaryVerifiedIncludesVacuous", "summary",
                          "verified=" & $verified & " matches neither the demoting " &
                          "nor the including arithmetic (raw=" & $rawVerified &
                          " inductive=" & $inductive & " vacuous=" & $vacuous &
                          ") — UNKNOWN"))
          inc.add(incident("R2-ARITH-001", "warning",
                           "report verified-count arithmetic matched no known " &
                           "accounting form — recorded UNKNOWN"))
      else:
        obs.add(obsNull("summaryVerifiedIncludesVacuous", "summary",
                        "report summary lacks the vacuity accounting fields " &
                        "(verified/statusCounts.verified/inductive_valid/vacuousCount) " &
                        "— UNKNOWN"))
        inc.add(incident("R2-ARITH-002", "warning",
                         "report summary vacuity accounting fields incomplete — " &
                         "cannot machine-check that verified excludes vacuous"))
    else:
      obs.add(obsNull("summaryVerifiedIncludesVacuous", "summary",
                      "unmeasured: E2E report artifact absent (" & art.reportErr &
                      ") — UNKNOWN, evaluator default is the FAIL direction"))
    # z3VsDualDistinguishable: the report's tier accounting keeps separate
    # z3-only and dual buckets.
    let tiers = jObj(jObj(art.report, "summary"), "tierCounts")
    if tiers != nil:
      let distinguishable = tiers.hasKey("z3-verified") and tiers.hasKey("dual-verified")
      obs.add(obsBool("z3VsDualDistinguishable", distinguishable, "canonical",
                      "report summary.tierCounts carries separate 'z3-verified' " &
                      "and 'dual-verified' buckets"))
    else:
      obs.add(obsNull("z3VsDualDistinguishable", "canonical",
                      "unmeasured: report tierCounts absent (" & art.reportErr &
                      ") — UNKNOWN"))
    # verifiedSemanticsDocumented: the run's report metrics.vkd must agree with
    # the policy VKS denominator and with its own verified/total arithmetic.
    # Docs greps are not evidence (DEBT#559): only the artifact counts.
    let vkdNode = jObj(jObj(art.report, "metrics"), "vkd")
    if vkdNode != nil:
      let total = jInt(vkdNode, "total", -1)
      let verifiedN = jInt(vkdNode, "verified", -1)
      let ratio = jFloat(vkdNode, "ratio", -1.0)
      let expectedRatio = if total > 0: float(verifiedN) / float(total) else: -1.0
      let consistent = total == vksSize and verifiedN >= 0 and ratio >= 0.0 and
                       abs(ratio - expectedRatio) < 1e-9
      obs.add(obsBool("verifiedSemanticsDocumented", consistent, "observed",
                      "report metrics.vkd: total=" & $total &
                      " (policy VKS=" & $vksSize & "), verified=" & $verifiedN &
                      ", ratio=" & $ratio & " (verified/total=" & $expectedRatio & ")"))
    else:
      obs.add(obsNull("verifiedSemanticsDocumented", "observed",
                      "unmeasured: report metrics.vkd absent (" & art.reportErr &
                      ") — UNKNOWN, never an implicit PASS"))
      inc.add(incident("R2-VKD-001", "warning",
                       "report metrics.vkd absent — verifiedSemanticsDocumented " &
                       "recorded UNKNOWN"))
    if art.reportErr != "":
      inc.add(incident("R2-OBS-001", "warning",
                       "E2E report artifact absent/unparsable (" & art.reportErr &
                       ") — R2 report-derived observations recorded UNKNOWN"))
    src.add(sourceEntry("src/core/types/verification_tier.nim",
                        "sha256:" & shaFile(repoRoot / "src" / "core" / "types" /
                                            "verification_tier.nim"), stamp.head,
                        "statusConsistentWithEvidence / certificateEvidenceFromJson"))
    addSourceIf(src, repoRoot, "src/core/metrics.nim", stamp.head,
                "computeVerified (vacuous demotion)")
    addSourceIf(src, repoRoot, "docs/spec/verification_density.md", stamp.head,
                "VKD formula / verified semantics")
    addSourceIf(src, repoRoot, "docs/spec/productization_contract.md", stamp.head,
                "R2 contract")
    if art.report != nil:
      addArtifactSource(src, art.dir, "verify_contract_e2e_report.json", stamp.head,
                        "E2E report (summary arithmetic / tierCounts)")
    if art.certPath.len > 0:
      src.add(sourceEntry(repoRelPath(repoRoot, art.certPath),
                          "sha256:" & shaFile(art.certPath), stamp.head,
                          "run certificate (status/verificationTier/solverMeta)"))
    let envelope = makeEnvelope("R2", stamp, obs, inc, src, cmds)
    writeEnvelope(outDir / "R2.json", envelope)
    echo "[readiness_collect_ci] wrote " & (outDir / "R2.json") &
         " — observations=" & $obs.len

  # ═════════════════════════════════════════════════════════════ R3 ═══════
  block r3:
    var
      obs: seq[JsonNode] = @[]
      inc: seq[JsonNode] = @[]
      src: seq[JsonNode] = @[]
      cmds: seq[JsonNode] = @[]
    # Relocation observations produced by the E2E job's wp5 step, carried
    # verbatim (they are THIS run's measurements; only the envelope identity is
    # re-stamped here so the gate's repoIdentity merge sees one identity).
    if art.wp5 != nil:
      let carried = jArr(art.wp5, "observations")
      if carried != nil:
        for o in carried.items:
          if o.kind == JObject and o.hasKey("key"):
            obs.add(o)
      let carriedCmds = jArr(art.wp5, "commands")
      if carriedCmds != nil:
        for c in carriedCmds.items:
          cmds.add(c)
      let carriedInc = jArr(art.wp5, "incidents")
      if carriedInc != nil:
        for c in carriedInc.items:
          inc.add(c)
      let carriedSrc = jArr(art.wp5, "sources")
      if carriedSrc != nil:
        for s in carriedSrc.items:
          src.add(s)
      addArtifactSource(src, art.dir, "r3_relocation.json", stamp.head,
                        "wp5 relocation measurement produced by the E2E job " &
                        "(observations carried verbatim, envelope re-stamped)")
      inc.add(incident("R3-CARRY-001", "info",
                       "R3 relocation observations carried from " &
                       "logs/r3_relocation.json (wp5, this run) and re-stamped " &
                       "under this collection's repoIdentity"))
    else:
      inc.add(incident("R3-OBS-001", "warning",
                       "wp5 relocation output absent (" & art.wp5Err &
                       ") — pathIndependentProjectionEqual/" &
                       "subjectRunProjectionHashEqual unmeasured; R3 stays " &
                       "fail-closed UNKNOWN at the evaluator"))
    # canonicalProjectionHashEqual: two live canonical-digest runs of THIS
    # checkout against the run's persisted state.
    if pr.axPresent and art.state != nil:
      let d1 = hex64Line(pr.canon1.stdout & "\n" & pr.canon1.stderr)
      let d2 = hex64Line(pr.canon2.stdout & "\n" & pr.canon2.stderr)
      if d1.len == 64 and d2.len == 64:
        obs.add(obsBool("canonicalProjectionHashEqual", d1 == d2, "artifact",
                        "ax report --canonical-digest --state-file <artifacts state> " &
                        "run twice in this checkout: " & d1[0 ..< 12] & "… / " &
                        d2[0 ..< 12] & "…"))
        cmds.add(cmdRecord("bin/ax report --canonical-digest --state-file <state>", pr.canon1))
        cmds.add(cmdRecord("bin/ax report --canonical-digest --state-file <state> (run2)", pr.canon2))
        let manifestDigest = jStr(jObj(art.manifest, "report"), "canonicalDigest")
        if manifestDigest.len == 64:
          if d1 == manifestDigest:
            inc.add(incident("R3-CANON-001", "info",
                             "canonical digest reproduced in this checkout equals the " &
                             "run-manifest digest (" & d1[0 ..< 12] & "…)"))
          else:
            inc.add(incident("R3-CANON-002", "warning",
                             "canonical digest in this checkout (" & d1[0 ..< 12] &
                             "…) differs from run-manifest canonicalDigest (" &
                             manifestDigest[0 ..< 12] & "…) — projection vs manifest drift"))
      else:
        obs.add(obsNull("canonicalProjectionHashEqual", "artifact",
                        "canonical-digest probe produced no 64-hex digest (exit " &
                        $pr.canon1.exitCode & "/" & $pr.canon2.exitCode &
                        ") — UNKNOWN"))
        inc.add(incident("R3-CANON-003", "warning",
                         "canonical-digest probe failed — no digest observed"))
    else:
      obs.add(obsNull("canonicalProjectionHashEqual", "artifact",
                      (if not pr.axPresent: "unmeasured: bin/ax absent"
                       else: "unmeasured: run state artifact absent (" & art.stateErr & ")") &
                      " — UNKNOWN"))
    # canonicalInputHash: this run's certificate input digest.
    if art.cert != nil:
      let ih = jStr(art.cert, "inputHash")
      if ih.len > 0:
        obs.add(obsStr("canonicalInputHash", ih, "artifact",
                       "certificate inputHash (module+scope canonical input digest, " &
                       "this run)"))
    else:
      inc.add(incident("R3-OBS-002", "warning",
                       "certificate artifact absent — canonicalInputHash honestly " &
                       "omitted (R3 UNKNOWN at the evaluator, fail-closed)"))
    # configHash / solverIdentity from the run's persisted state (manifest
    # mirror as fallback).
    var configHash = jStr(jObj(art.state, "executionIdentity"), "executionConfigDigest")
    if configHash.len == 0 and art.manifest != nil:
      configHash = jStr(jObj(art.manifest, "policy"), "executionConfigDigest")
    if configHash.len > 0:
      obs.add(obsStr("configHash", configHash, "config",
                     "ax_proof_state.executionIdentity.executionConfigDigest " &
                     "(this run)"))
    var solverIdentity = ""
    if art.cert != nil:
      let z3v = jStr(jObj(art.cert, "toolchainIdentity"), "z3")
      if z3v.len > 0:
        solverIdentity = "z3_" & z3v & " (cert toolchainIdentity.z3 + solverInvocation" &
                         "{engine:" & jStr(jObj(art.cert, "solverInvocation"), "engine") &
                         ", version:" & z3v & "})"
    if solverIdentity.len == 0 and art.state != nil:
      solverIdentity = jStr(jObj(art.state, "executionIdentity"), "toolchainIdentity")
    if solverIdentity.len > 0:
      obs.add(obsStr("solverIdentity", solverIdentity, "toolchain",
                     "solver identity of this run (cert/state executionIdentity)"))
    else:
      inc.add(incident("R3-OBS-003", "warning",
                       "solverIdentity unmeasurable (cert and state absent) — omitted"))
    # canonicalExecutionFingerprint: same formula as the wp5 stamp, over this
    # run's manifest identity fields and this collection's observed toolchain.
    if art.manifest != nil:
      let sourceTree = jObj(art.manifest, "sourceTree")
      let bsh = jStr(sourceTree, "buildSourceHash")
      let scopeHash = jStr(sourceTree, "scopeHash")
      let nv = shortVersion(stamp.nimLine)
      let zv = shortVersion(stamp.z3Line)
      let lv = shortVersion(stamp.leanLine)
      if bsh.len > 0 and scopeHash.len > 0:
        let fp = sha256Hex("nim=" & nv & "|z3=" & zv & "|lean=" & lv &
                           "|buildSourceHash=" & bsh & "|scopeHash=" & scopeHash)
        obs.add(obsStr("canonicalExecutionFingerprint", fp, "execution-contract",
                       "sha256('nim=" & nv & "|z3=" & zv & "|lean=" & lv &
                       "|buildSourceHash=" & bsh & "|scopeHash=" & scopeHash &
                       "') — components: observed toolchain + run-manifest " &
                       "sourceTree.buildSourceHash/policy.scopeHash"))
    else:
      inc.add(incident("R3-OBS-004", "warning",
                       "run-manifest absent — canonicalExecutionFingerprint omitted"))
    # environmentControlled: the collection environment's toolchain matches the
    # toolchain identity the run declared (cert toolchainIdentity object, else
    # the state/manifest toolchainIdentity string).
    var reference = ""
    let certTc = jObj(art.cert, "toolchainIdentity")
    if certTc != nil:
      reference = ($certTc)
    elif art.state != nil:
      reference = jStr(jObj(art.state, "executionIdentity"), "toolchainIdentity")
    elif art.manifest != nil:
      reference = jStr(jObj(art.manifest, "toolchain"), "toolchainIdentity")
    if reference.len > 0:
      let nv = shortVersion(stamp.nimLine)
      let zv = shortVersion(stamp.z3Line)
      let lv = shortVersion(stamp.leanLine)
      let obsv = [nv, zv, lv].filterIt(it.len > 0)
      var allIn = obsv.len > 0
      for v in obsv:
        if v notin reference:
          allIn = false
      obs.add(obsBool("environmentControlled", allIn, "env",
                      "observed toolchain (nim=" & nv & " z3=" & zv & " lean=" & lv &
                      ") vs this run's declared toolchain identity — " &
                      (if allIn: "pinned and matching" else: "MISMATCH")))
      if not allIn:
        inc.add(incident("R3-ENV-001", "warning",
                         "collection toolchain differs from the run's declared " &
                         "toolchain identity — environmentControlled measured false"))
    else:
      obs.add(obsNull("environmentControlled", "env",
                      "unmeasured: no declared toolchain identity in the artifact set " &
                      "(cert/state/manifest absent) — UNKNOWN"))
    src.add(sourceEntry("config/readiness_policy.json",
                        "sha256:" & shaFile(repoRoot / policyPath), stamp.head,
                        "observationKeys R3"))
    addSourceIf(src, repoRoot, "src/core/utils/canonical_projection.nim", stamp.head,
                "canonical projection SSOT (volatile-key stripping)")
    let envelope = makeEnvelope("R3", stamp, obs, inc, src, cmds)
    writeEnvelope(outDir / "R3.json", envelope)
    echo "[readiness_collect_ci] wrote " & (outDir / "R3.json") &
         " — observations=" & $obs.len

  # ═════════════════════════════════════════════════════════════ R4 ═══════
  block r4:
    var
      obs: seq[JsonNode] = @[]
      inc: seq[JsonNode] = @[]
      src: seq[JsonNode] = @[]
      cmds: seq[JsonNode] = @[]
    # certFieldPresent: policy r4.requiredFields over this run's resolved
    # certificate. Absent certificate -> measured false (field not observable;
    # fail-closed red, never a silent skip).
    for f in r4Fields:
      let present = fieldNonEmpty(art.cert, f)
      obs.add(obsBool("certFieldPresent", present, "v3-provenance", f))
      if art.cert == nil:
        inc.add(incident("R4-OBS-001", "warning",
                         "certificate artifact absent (" & art.certErr &
                         ") — certFieldPresent('" & f & "') measured false"))
      elif not present:
        inc.add(incident("R4-OBS-002", "warning",
                         "required field '" & f & "' missing or empty in the certificate"))
    # provenanceReconstructible: manifest ↔ cert/report/state/kernel joins.
    block provenance:
      var joins: seq[tuple[label: string, ok: bool]] = @[]
      let coreInputs = art.manifest != nil and art.report != nil and
                       art.state != nil and art.cert != nil and
                       art.reportExitOk and art.kernelOutOk and
                       art.certPathDeclared.len > 0
      if art.manifest != nil:
        joins.add(("manifest.certificate.path == cert_path.txt",
                   jStr(jObj(art.manifest, "certificate"), "path") ==
                   art.certPathDeclared))
        joins.add(("manifest.sourceTree.gitHead == repoIdentity.head",
                   jStr(jObj(art.manifest, "sourceTree"), "gitHead") == stamp.head))
        joins.add(("manifest.report.exit == report_exit.txt",
                   jInt(jObj(art.manifest, "report"), "exit", -1) == art.reportExit))
        joins.add(("manifest.verification.certVerifyKernelStdout == kernel.out",
                   jStr(jObj(art.manifest, "verification"), "certVerifyKernelStdout").strip() ==
                   art.kernelOut.strip()))
      if art.manifest != nil and art.cert != nil:
        joins.add(("manifest.target.symbol == cert.functionName",
                   jStr(jObj(art.manifest, "target"), "symbol") ==
                   jStr(art.cert, "functionName")))
        joins.add(("manifest.certificate.identityDigest == cert.identityDigest",
                   jStr(jObj(art.manifest, "certificate"), "identityDigest") ==
                   jStr(art.cert, "identityDigest")))
        # File-level digest: binds the RESOLVED cert file (which may arrive
        # under the fixed transport alias e2e_certificate.json, carrying no
        # path identity of its own) to the manifest's recorded sha256 — a
        # wrong or foreign file fails this join and R4 goes red.
        joins.add(("manifest.certificate.sha256 == sha256(resolved cert file)",
                   jStr(jObj(art.manifest, "certificate"), "sha256") ==
                   shaFile(art.certPath)))
      if art.manifest != nil and art.state != nil:
        joins.add(("manifest.toolchain.executionBundleFingerprint == state.executionIdentity",
                   jStr(jObj(art.manifest, "toolchain"), "executionBundleFingerprint") ==
                   jStr(jObj(art.state, "executionIdentity"), "executionBundleFingerprint")))
      var allOk = coreInputs
      var failedLabels: seq[string] = @[]
      for (label, ok) in joins:
        if not ok:
          allOk = false
          failedLabels.add(label)
      var subject = "run-manifest ↔ {cert, report, state, kernel.out, cert_path} " &
                    "field correspondence, all measured joins: " &
                    (if joins.len == 0: "none (manifest absent)" else: $joins.len)
      if not coreInputs:
        var missing: seq[string] = @[]
        if art.manifest == nil: missing.add("run-manifest")
        if art.report == nil: missing.add("report")
        if art.state == nil: missing.add("state")
        if art.cert == nil: missing.add("certificate")
        if not art.reportExitOk: missing.add("report_exit.txt")
        if not art.kernelOutOk: missing.add("kernel.out")
        if art.certPathDeclared.len == 0: missing.add("cert_path.txt")
        subject = "provenance chain NOT reconstructible — absent inputs: " &
                  missing.join(", ")
        inc.add(incident("R4-JOIN-001", "warning",
                         "provenance join inputs absent: " & missing.join(", ") &
                         " — provenanceReconstructible measured false (fail-closed)"))
      if failedLabels.len > 0:
        subject = "provenance join failures: " & failedLabels.join("; ")
        inc.add(incident("R4-JOIN-002", "warning",
                         "provenance join failures: " & failedLabels.join("; ")))
      obs.add(obsBool("provenanceReconstructible", allOk, "artifact", subject))
    # subjectTreeImmutableAcrossRun: tracked mutations at collection time,
    # measured before this collector wrote anything.
    let immutable = stamp.workingTreeClean and
                    (art.manifest == nil or
                     jStr(jObj(art.manifest, "sourceTree"), "gitHead") == stamp.head)
    obs.add(obsBool("subjectTreeImmutableAcrossRun", immutable, "git",
                    "git status --porcelain --untracked-files=no empty at collection " &
                    "start" & (if art.manifest != nil:
                      "; checkout head == run-manifest sourceTree.gitHead" else: "") &
                    " (measured before any evidence write)"))
    if not stamp.workingTreeClean:
      inc.add(incident("R4-TREE-001", "warning",
                       "working tree carries tracked mutations — " &
                       "subjectTreeImmutableAcrossRun measured false"))
    src.add(sourceEntry("config/readiness_policy.json",
                        "sha256:" & shaFile(repoRoot / policyPath), stamp.head,
                        "r4.requiredFields"))
    addSourceIf(src, repoRoot, "docs/spec/provenance_contract_v3.md", stamp.head,
                "certificate v3 provenance contract")
    addArtifactSource(src, art.dir, "run-manifest.json", stamp.head,
                      "provenance join input")
    addArtifactSource(src, art.dir, "verify_contract_e2e_report.json", stamp.head,
                      "provenance join input")
    addArtifactSource(src, art.dir, "ax_proof_state.json", stamp.head,
                      "provenance join input")
    addArtifactSource(src, art.dir, "verify_contract_e2e_cert_path.txt", stamp.head,
                      "certificate path declaration")
    addArtifactSource(src, art.dir, "verify_contract_e2e_kernel.out", stamp.head,
                      "kernel replay stdout")
    if art.certPath.len > 0:
      src.add(sourceEntry(repoRelPath(repoRoot, art.certPath),
                          "sha256:" & shaFile(art.certPath), stamp.head,
                          "run certificate (v3 provenance fields)"))
    let envelope = makeEnvelope("R4", stamp, obs, inc, src, cmds)
    writeEnvelope(outDir / "R4.json", envelope)
    echo "[readiness_collect_ci] wrote " & (outDir / "R4.json") &
         " — observations=" & $obs.len

  # ═════════════════════════════════════════════════════════════ R5 ═══════
  block r5:
    var
      obs: seq[JsonNode] = @[]
      inc: seq[JsonNode] = @[]
      src: seq[JsonNode] = @[]
      cmds: seq[JsonNode] = @[]
    let helpOut = (if pr.axPresent: pr.help.stdout & "\n" & pr.help.stderr else: "")
    for cmd in r5Commands:
      let sub = cmd.split(' ')[1 .. ^1].join(" ")
      let dedicated = (if sub == "prove": pr.proveHelp elif sub == "report": pr.reportHelp
                       else: RunResult(exitCode: -1, stdout: "", stderr: ""))
      let exists = pr.axPresent and
                   pr.help.exitCode == 0 and sub in helpOut and
                   dedicated.exitCode == 0
      obs.add(obsBool("commandExists", exists, "surface", cmd))
      # helpSurface: the dedicated help path must exit 0 AND actually print a
      # usage surface naming the command — an exit-0 with no help text is not
      # a help surface (DEBT#559).
      let helpText = dedicated.stdout & "\n" & dedicated.stderr
      let helpShowsUsage = helpText.toLowerAscii().contains("usage") and
                           (sub in helpText or cmd in helpText)
      obs.add(obsBool("helpSurface", pr.axPresent and dedicated.exitCode == 0 and
                      helpShowsUsage, "surface", cmd))
      if pr.axPresent and dedicated.exitCode == 0 and not helpShowsUsage:
        inc.add(incident("R5-HELP-001", "warning",
                         "'" & cmd & " --help' exited 0 but printed no usage " &
                         "surface naming the command — helpSurface measured false"))
      # successExitCode: only a real successful execution of the command is
      # evidence. `ax report` is actuated here (reportJson) against the state
      # artifact the E2E report was validated with. `ax prove` has no
      # independent success run in this collection — its success bucket is
      # declared by the R8 E2E contract instead (r8.successfulExecutionContract,
      # consumed by ruleR8), so no successExitCode observation is minted for it
      # and R5 never substitutes a help exit for a real success run.
      if pr.axPresent and sub == "report":
        if pr.reportJson.exitCode == successCode:
          obs.add(obsInt("successExitCode", successCode, "observed", cmd))
        else:
          obs.add(obsNull("successExitCode", "observed", cmd))
          inc.add(incident("R5-EXIT-003", "warning",
                           "`ax report` actuation exited " & $pr.reportJson.exitCode &
                           " != success " & $successCode &
                           " — successExitCode recorded UNKNOWN, never a help-exit " &
                           "stand-in"))
      else:
        inc.add(incident("R5-EXIT-004", "warning",
                         "no independent successful execution observed for '" & cmd &
                         "' — successExitCode not minted (R5 UNKNOWN at the evaluator)"))
      # Exit-code observations, subject-scoped per contract command. The
      # subject is the evaluator's join key: ruleR5 groups a command's
      # success/failure exit codes by identical subject (pinned by
      # tests/ci/test_readiness_verdict_mapping.nim and
      # tests/readiness/fixtures/synthetic_bundle.json — every bucket for a
      # command carries subject == cmd, never a free-form description; a
      # descriptive subject breaks the join and FAILs R5). Buckets actuated
      # by this collection are recorded at scope "observed" with the measured
      # code; buckets not actuated (no safe probe exists) record the policy
      # contract value at scope "contract" — the evaluator's key closure
      # excludes declared values, so an unactuated bucket keeps R5 UNKNOWN
      # instead of silently passing on a policy echo.
      # invalid input: actuated for both contract commands — the probes are
      # read-only and each command has its own rejection path (`ax prove`
      # unknown option; `ax report` unknown flag / absent state file).
      if pr.axPresent:
        let invalidProbe = (if sub == "prove": pr.unknownOption else: pr.missingStateFile)
        obs.add(obsInt("invalidInputExitCode", invalidProbe.exitCode, "observed", cmd))
        inc.add(incident(
          "R5-EXIT-001", (if invalidProbe.exitCode == invalidCode: "info" else: "warning"),
          "invalid-input probe for '" & cmd & "' exited " & $invalidProbe.exitCode &
          " (policy INVALID_INPUT=" & $invalidCode & ")"))
      else:
        obs.add(obsInt("invalidInputExitCode", invalidCode, "contract", cmd))
      # verification failure: actuated when this collection observed a
      # verification-failure exit (the E2E report exit, or the live `ax report`
      # probe over the E2E state — the probe is the same exit family and runs
      # on this checkout's binary).
      let observedVerifFail =
        (art.reportExitOk and art.reportExit == verifFailCode) or
        (pr.axPresent and sub == "report" and pr.reportJson.exitCode == verifFailCode)
      if observedVerifFail:
        obs.add(obsInt("verificationFailureExitCode", verifFailCode, "observed", cmd))
      else:
        obs.add(obsInt("verificationFailureExitCode", verifFailCode, "contract", cmd))
      # internal error: no safe inducible probe exists for either command, so
      # the bucket stays a declared vocabulary value and never counts as
      # evidence (policy presence=vocabulary for this key).
      obs.add(obsInt("internalErrorExitCode", internalCode, "contract", cmd))
    inc.add(incident("R5-EXIT-000", "info",
                     "exit-code buckets with no safe actuation (internal-error) are " &
                     "recorded at scope=contract (policy vocabulary, presence=vocabulary); " &
                     "required buckets are actuated — never a default PASS (DEBT#559)"))
    if not pr.axPresent:
      inc.add(incident("R5-OBS-001", "warning",
                       "bin/ax absent — no exit-code actuation for any subject; " &
                       "no successExitCode observation is minted (R5 UNKNOWN at " &
                       "the evaluator, fail-closed)"))
    # jsonSchemaVersion: the run's report document schema identity.
    let reportSchema = jStr(art.report, "schemaVersion")
    if reportSchema.len > 0:
      obs.add(obsStr("jsonSchemaVersion", reportSchema, "surface",
                     "E2E report top-level schemaVersion"))
    else:
      obs.add(obsNull("jsonSchemaVersion", "surface",
                      "unmeasured: E2E report artifact absent (" & art.reportErr &
                      ") — UNKNOWN, evaluator treats non-string as failure"))
    # stdoutStderrSplit: live report actuation in this checkout.
    if pr.axPresent and art.state != nil:
      var stdoutIsJson = false
      try:
        let j = parseJson(pr.reportJson.stdout)
        stdoutIsJson = j.kind == JObject
      except CatchableError:
        discard # axiom:best-effort(non-JSON stdout honestly measures stdoutIsJson=false)
      var stderrIsJson = false
      try:
        let j2 = parseJson(pr.reportJson.stderr)
        stderrIsJson = j2.kind == JObject
      except CatchableError:
        discard # axiom:best-effort(non-JSON stderr honestly measures stderrIsJson=false)
      obs.add(obsBool("stdoutStderrSplit", stdoutIsJson and not stderrIsJson,
                      "surface",
                      "ax report --json --state-file <artifacts state>: stdout parses " &
                      "as a JSON object (exit " & $pr.reportJson.exitCode &
                      "), logger output on stderr"))
      cmds.add(cmdRecord("bin/ax report --json --state-file <state>", pr.reportJson))
    else:
      obs.add(obsNull("stdoutStderrSplit", "surface",
                      (if not pr.axPresent: "unmeasured: bin/ax absent"
                       else: "unmeasured: state artifact absent (" & art.stateErr & ")") &
                      " — UNKNOWN"))
    if pr.axPresent:
      cmds.add(cmdRecord("bin/ax help", pr.help))
      cmds.add(cmdRecord("bin/ax prove --help", pr.proveHelp))
      cmds.add(cmdRecord("bin/ax report --help", pr.reportHelp))
      cmds.add(cmdRecord("bin/ax prove --definitely-unknown-option-xyz", pr.unknownOption))
      cmds.add(cmdRecord("bin/ax garbage-subcommand-xyz", pr.unknownSubcmd))
      cmds.add(cmdRecord("bin/ax report --json --state-file <absent>", pr.missingStateFile))
    src.add(sourceEntry("config/readiness_policy.json",
                        "sha256:" & shaFile(repoRoot / policyPath), stamp.head,
                        "r5 contractCommands/exitCodeContract"))
    addSourceIf(src, repoRoot, "docs/spec/productization_contract.md", stamp.head,
                "R5 CLI contract")
    if art.report != nil:
      addArtifactSource(src, art.dir, "verify_contract_e2e_report.json", stamp.head,
                        "report schemaVersion")
    addArtifactSource(src, art.dir, "verify_contract_e2e_report_exit.txt", stamp.head,
                      "report exit observation")
    let envelope = makeEnvelope("R5", stamp, obs, inc, src, cmds)
    writeEnvelope(outDir / "R5.json", envelope)
    echo "[readiness_collect_ci] wrote " & (outDir / "R5.json") &
         " — observations=" & $obs.len

  # ═════════════════════════════════════════════════════════════ R6 ═══════
  block r6:
    var
      obs: seq[JsonNode] = @[]
      inc: seq[JsonNode] = @[]
      src: seq[JsonNode] = @[]
      cmds: seq[JsonNode] = @[]
    if pr.axPresent:
      # Failure-path probes: unknown option (ax prove), unknown subcommand,
      # nonexistent state file (ax report). All are read-only, fast, and
      # cannot mutate the subject tree.
      let probes: seq[tuple[name: string, r: RunResult]] = @[
        ("bin/ax prove --definitely-unknown-option-xyz", pr.unknownOption),
        ("bin/ax garbage-subcommand-xyz", pr.unknownSubcmd),
        ("bin/ax report --json --state-file <absent>", pr.missingStateFile)]
      var anyConverted = false
      var anySwallowed = false
      for probe in probes:
        let name = probe.name
        let r = probe.r
        cmds.add(cmdRecord(name, r))
        if r.exitCode == 0:
          anyConverted = true
          inc.add(incident("R6-PROBE-001", "warning",
                           "failure probe '" & name & "' exited 0 — failure path " &
                           "converted to success"))
        else:
          let outp = r.stdout & "\n" & r.stderr
          let surfaced = outp.contains("[ERROR]") or outp.contains("[FATAL]") or
                         outp.toLowerAscii().contains("unknown") or
                         outp.toLowerAscii().contains("not found") or
                         outp.toLowerAscii().contains("error")
          if not surfaced:
            anySwallowed = true
            inc.add(incident("R6-PROBE-002", "warning",
                             "failure probe '" & name & "' exited " & $r.exitCode &
                             " with no error marker on either stream — " &
                             "exception swallowed"))
      obs.add(obsBool("failureConvertsToSuccess", anyConverted, "runtime",
                      "three failure-path probes (unknown option / unknown " &
                      "subcommand / nonexistent state file): " &
                      (if anyConverted: "at least one exited 0 (red)"
                       else: "all exited nonzero")))
      obs.add(obsBool("exceptionSwallowed", anySwallowed, "runtime",
                      "every nonzero-exit failure probe surfaced an error marker " &
                      "([ERROR]/[FATAL]/unknown/not found) on stdout or stderr"))
    else:
      # No binary -> NO R6 observation is minted. An empty observation set
      # makes the envelope INVALID at the evaluator (validateEvidence: "no
      # observations recorded") -> R6 NOT_RUN -> NO-GO: the honest fail-closed
      # state, instead of null values that ruleR6's defaults would silently
      # read as PASS.
      inc.add(incident("R6-PROBE-000", "warning",
                       "bin/ax absent — no failure-semantics probe could run; no " &
                       "R6 observation minted (envelope intentionally invalid: " &
                       "NOT_RUN fails closed at the evaluator)"))
    if pr.axPresent:
      src.add(sourceEntry(repoRelPath(repoRoot, axBin), "sha256:" & shaFile(axBin),
                          stamp.head, "failure-path probe target"))
    addSourceIf(src, repoRoot, "config/readiness_policy.json", stamp.head,
                "r5.exitCodeContract (failure exit semantics)")
    addSourceIf(src, repoRoot, "docs/spec/productization_contract.md", stamp.head,
                "R6 failure semantics contract")
    let envelope = makeEnvelope("R6", stamp, obs, inc, src, cmds)
    writeEnvelope(outDir / "R6.json", envelope)
    echo "[readiness_collect_ci] wrote " & (outDir / "R6.json") &
         " — observations=" & $obs.len &
         (if obs.len == 0: " (intentionally empty: probe could not run)" else: "")

  # ═════════════════════════════════════════════════════════════ R7 ═══════
  block r7:
    var
      obs: seq[JsonNode] = @[]
      inc: seq[JsonNode] = @[]
      src: seq[JsonNode] = @[]
      cmds: seq[JsonNode] = @[]
    # claimedScope: the coverage subjects this product claims (policy SSOT).
    obs.add(obsStrList("claimedScope", r7Subjects, "vkd-contract",
                       "policy r7.coverageSubjects (claimed coverage subjects)"))
    # verifiedEmitterScope / measuredCoverage: the run's own report emission.
    let vkd = jObj(jObj(art.report, "metrics"), "vkd")
    if vkd != nil:
      obs.add(obsStrList("verifiedEmitterScope", @["vkd"], "vkd-emission",
                         "report metrics.vkd emitted by this run's report"))
      let ratio = jFloat(vkd, "ratio", -1.0)
      let total = jInt(vkd, "total", -1)
      if ratio >= 0.0:
        obs.add(obsFloat("measuredCoverage", ratio, "vkd",
                         "report metrics.vkd.ratio (verified=" & $jInt(vkd, "verified") &
                         ", total=" & $total & ") — the run's canonical VKD exposure"))
        if total != vksSize:
          inc.add(incident("R7-VKD-001", "warning",
                           "report metrics.vkd.total=" & $total &
                           " != policy r7.vkdContract.vksSize=" & $vksSize &
                           " — VKS denominator drift recorded"))
      else:
        obs.add(obsNull("measuredCoverage", "vkd",
                        "report metrics.vkd present but ratio unparseable — UNKNOWN"))
    else:
      obs.add(obsStrList("verifiedEmitterScope", @[], "vkd-emission",
                         "no metrics emission observed (E2E report artifact absent: " &
                         art.reportErr & ")"))
      obs.add(obsNull("measuredCoverage", "vkd",
                      "unmeasured: E2E report artifact absent (" & art.reportErr &
                      ") — UNKNOWN; R7 stays UNKNOWN at the evaluator (fail-closed)"))
      inc.add(incident("R7-OBS-001", "warning",
                       "E2E report artifact absent — measuredCoverage UNKNOWN " &
                       "(no fabricated ratio)"))
    src.add(sourceEntry("config/readiness_policy.json",
                        "sha256:" & shaFile(repoRoot / policyPath), stamp.head,
                        "r7 coverageSubjects/vkdContract"))
    addSourceIf(src, repoRoot, "data/verification_scope.lock", stamp.head,
                "VKS scope truth (kernel_symbols − kernel_exempt_symbols)")
    addSourceIf(src, repoRoot, "docs/spec/verification_density.md", stamp.head,
                "VKD formula (|VKS ∩ certGreen| / |VKS|)")
    if art.report != nil:
      addArtifactSource(src, art.dir, "verify_contract_e2e_report.json", stamp.head,
                        "metrics.vkd (measuredCoverage source)")
    let envelope = makeEnvelope("R7", stamp, obs, inc, src, cmds)
    writeEnvelope(outDir / "R7.json", envelope)
    echo "[readiness_collect_ci] wrote " & (outDir / "R7.json") &
         " — observations=" & $obs.len

  # ═════════════════════════════════════════════════════════════ R8 ═══════
  block r8:
    var
      obs: seq[JsonNode] = @[]
      inc: seq[JsonNode] = @[]
      src: seq[JsonNode] = @[]
      cmds: seq[JsonNode] = @[]
    # installFollowed: toolchains observed + product binary version actuation.
    let installFollowed = stamp.nimLine.len > 0 and stamp.z3Line.len > 0 and
                          stamp.leanLine.len > 0 and
                          pr.axPresent and pr.version.exitCode == 0
    obs.add(obsBool("installFollowed", installFollowed, "operability",
                    "toolchains nim/z3/lean observed + bin/ax --version exit " &
                    (if pr.axPresent: $pr.version.exitCode else: "<binary absent>")))
    if pr.axPresent:
      cmds.add(cmdRecord("bin/ax --version", pr.version))
    # manualStepsRequired: every command in this envelope ran non-interactively
    # in this automated collection; CI env corroborates when present.
    let ciEnv = getEnv("CI") == "true" or getEnv("GITHUB_ACTIONS") == "true"
    obs.add(obsBool("manualStepsRequired", false, "operability",
                    "all commands in this envelope executed non-interactively by " &
                    "this automated collection (CI=" & $ciEnv &
                    "); no manual step interposed — measurement definition: a " &
                    "manual step is any step a human performed between the " &
                    "recorded commands"))
    # cleanRunSucceeded: the E2E clean run's own outcome.
    let verdict = jStr(jObj(art.report, "runOutcome"), "verdict")
    let cleanRun = art.report != nil and verdict == "PASS" and
                   art.reportExitOk and art.reportExit == successCode
    obs.add(obsBool("cleanRunSucceeded", cleanRun, "operability",
                    "E2E report runOutcome.verdict=" &
                    (if verdict.len > 0: verdict else: "<absent>") &
                    " reportExit=" & (if art.reportExitOk: $art.reportExit else: "<absent>") &
                    " (success=" & $successCode & ") — no successful clean run " &
                    "observed unless both hold"))
    if not cleanRun:
      inc.add(incident("R8-RUN-001", "warning",
                       "clean run success not observed (report " &
                       (if art.reportErr != "": "absent: " & art.reportErr
                        else: "verdict=" & verdict & " exit=" &
                              (if art.reportExitOk: $art.reportExit else: "<absent>")) &
                       ") — cleanRunSucceeded measured false"))
    # documentedRunSteps: README run flow + contract §10.6 sequence verbatim.
    let flowDocumented = "ax prove" in readmeText and "ax report" in readmeText
    var seqDocumented = true
    for c in r8Sequence:
      if c notin contractText:
        seqDocumented = false
    obs.add(obsBool("documentedRunSteps", flowDocumented and seqDocumented,
                    "operability",
                    "README run flow + contract §10.6 prepare sequence verbatim " &
                    "(checked commands: " & r8Sequence.join(" -> ") & ")"))
    # Cold-set purge is a property of the producing CI job, not a machine
    # observation this collector can make; it is deliberately not an
    # observation key (DEBT#559). The fact stays visible as an incident, never
    # as a fabricated observation.
    inc.add(incident("R8-COLD-001", "info",
                     "cold-set purge before the E2E run is not machine-observable " &
                     "from the downloaded artifact set; not emitted as an " &
                     "observation key (no fabrication)"))
    # commands: §10.6 prepare sequence — executed ONLY when cargo and the probe
    # crate are actually available here (collect_evidence_probe reuse); a
    # missing cargo leaves the commands honestly absent and ruleR8 fails
    # closed at the evaluator.
    for c in r8Prepare:
      cmds.add(c)
    for c in r8PrepareIncidents:
      inc.add(c)
    if not cargoRan:
      inc.add(incident("R8-SEQ-001", "warning",
                       "§10.6 prepare sequence not executed in this collection " &
                       "(cargo/probe availability above) — the commands list " &
                       "carries no cargo entries; ruleR8 requires the sequence " &
                       "recorded with exit 0 to PASS"))
    src.add(sourceEntry("config/readiness_policy.json",
                        "sha256:" & shaFile(repoRoot / policyPath), stamp.head,
                        "r8 prepareSequenceCommands / distribution"))
    addSourceIf(src, repoRoot, "README.md", stamp.head, "documented run steps")
    addSourceIf(src, repoRoot, "docs/spec/productization_contract.md", stamp.head,
                "R8 contract §10.6 prepare sequence")
    if fileExists(probeManifest):
      src.add(sourceEntry(rustProbeDir / "Cargo.toml",
                          "sha256:" & shaFile(probeManifest), stamp.head,
                          "Rust probe crate manifest"))
    if fileExists(probeLock):
      src.add(sourceEntry(rustProbeDir / "Cargo.lock",
                          "sha256:" & shaFile(probeLock), stamp.head,
                          "Rust probe crate lockfile"))
    if art.report != nil:
      addArtifactSource(src, art.dir, "verify_contract_e2e_report.json", stamp.head,
                        "clean-run outcome")
    let envelope = makeEnvelope("R8", stamp, obs, inc, src, cmds)
    writeEnvelope(outDir / "R8.json", envelope)
    echo "[readiness_collect_ci] wrote " & (outDir / "R8.json") &
         " — observations=" & $obs.len

  echo "[readiness_collect_ci] DONE — 8 evidence envelopes under " & outDir &
       " (measurements only; the verdict belongs to the readiness gate)"
  quit(0)
