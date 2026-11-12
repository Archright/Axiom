## tools/collect_evidence_probe.nim — automated evidence collector (R1 + R8).
##
## Operationalization gate D (plan yelena-belova-constantine-jean-grey): replace manual
## readiness evidence with run-actuated collection. R1 (Product Contract) collects from
## real command actuation (`bin/ax --version`, `bin/ax help`, `bin/ax prove --help`,
## `bin/ax report --help`, `bin/ax report --json`) and canonical files (README.md,
## docs/spec/productization_contract.md, a v3 certificate artifact) with sha256 anchors.
## R8 (Reproducible Operability, contract §10.6 axis) executes the contract-pinned Rust
## subject prepare sequence (`cargo fetch --locked` -> `cargo metadata
## --format-version=1 --locked` -> `cargo build --frozen`) against the probe crate
## (--rust-probe-dir, default /tmp/axiom-rust-probe — the same canonical probe the
## unit/gateway tests consume) and records the real {cmd, exitCode, outputDigest}
## observations at the §4 envelope level, which ruleR8 (tools/readiness_evaluator.nim)
## machine-verifies for exact string, relative order and exit 0.
##
## Method is always "automated". No observation is fabricated: a probe that cannot run is
## recorded with its truthful outcome (false / exit code) plus an incident. The prepare
## commands are recorded ONLY when they actually ran in this collection — a missing
## cargo or probe crate leaves the commands honestly absent (R8 then fails closed at the
## evaluator); the collector never recreates the probe crate or its evidence. R8
## observation keys are claimed only when actuated by this collection:
## installFollowed (toolchain probes + bin/ax --version), documentedRunSteps (README run
## flow + the §10.6 sequence verbatim in the contract text). cleanRunSucceeded stays
## unclaimed here — full-prove actuation belongs to the R2/R3 evidence procedures.
##
## Usage:
##   collect_evidence_probe --evidence-dir OUT --repo-head SHA --tree-digest DIGEST \
##     --toolchain-nim 2.2.10 --toolchain-z3 4.13.3 --toolchain-lean 4.29.0 --eval-time ISO \
##     [--rust-probe-dir DIR]
## Exit codes: 0 = evidence written; 2 = CLI misuse; 3 = environment/validation failure.

import std/[os, osproc, json, strutils, times, streams]
import ./sha256_native

proc die(msg: string, code = 2) {.noreturn.} =
  stderr.writeLine("[collect_evidence_probe] " & msg)
  quit(code)

type
  RunResult = object
    exitCode: int
    stdout: string
    stderr: string

proc runSplit(bin: string, args: seq[string], workingDir: string): RunResult =
  ## Spawn a real binary; capture stdout/stderr separately (honest actuation).
  ## NOTE: the ax CLI writes its usage text to stderr (`[INFO] …` logger),
  ## so help-surface checks must merge both streams.
  let p = startProcess(bin, workingDir = workingDir, args = args,
                       options = {poUsePath})
  result.stdout = p.outputStream.readAll()
  result.stderr = p.errorStream.readAll()
  result.exitCode = waitForExit(p)
  close(p)
  result.stdout = result.stdout & "\n" & result.stderr

proc shellOut(s: string): string =
  ## Trimmed stdout of a shell command; empty on failure.
  let (output, code) = execCmdEx(s)
  if code != 0: "" else: output.strip()

proc sha(s: string): string =
  sha256String(s)

const
  DefaultFreshnessDays = 30
  DefaultRustProbeDir = "/tmp/axiom-rust-probe"

proc freshUntilOf(evalTime: string): string =
  ## generatedAt + 30 days (config/readiness_policy.json freshness).
  let t = parse(evalTime, "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
  format(t + initDuration(days = DefaultFreshnessDays),
         "yyyy-MM-dd'T'HH:mm:ss'Z'")

when isMainModule:
  var
    evidenceDir = ""
    repoHead = ""
    treeDigest = ""
    nimT = ""
    z3T = ""
    leanT = ""
    evalTime = ""
    rustProbeDir = DefaultRustProbeDir
  var i = 0
  let args = commandLineParams()
  proc needValue(a: string): string =
    if i >= args.len - 1:
      die("missing value for " & a)
    inc i
    args[i]
  while i < args.len:
    let a = args[i]
    case a
    of "--evidence-dir": evidenceDir = needValue(a)
    of "--repo-head": repoHead = needValue(a)
    of "--tree-digest": treeDigest = needValue(a)
    of "--toolchain-nim": nimT = needValue(a)
    of "--toolchain-z3": z3T = needValue(a)
    of "--toolchain-lean": leanT = needValue(a)
    of "--eval-time": evalTime = needValue(a)
    of "--rust-probe-dir": rustProbeDir = needValue(a)
    of "--help", "-h":
      echo "usage: collect_evidence_probe --evidence-dir D --repo-head SHA --tree-digest D --toolchain-nim X --toolchain-z3 Y --toolchain-lean Z --eval-time ISO [--rust-probe-dir DIR]"
      quit(0)
    else:
      die("unknown option: " & a)
    inc i

  if evidenceDir == "" or repoHead == "" or treeDigest == "" or
     nimT == "" or z3T == "" or leanT == "" or evalTime == "":
    die("usage: collect_evidence_probe --evidence-dir D --repo-head SHA --tree-digest D --toolchain-nim X --toolchain-z3 Y --toolchain-lean Z --eval-time ISO [--rust-probe-dir DIR]")

  # --- repository identity validation (fail-closed: no match -> no evidence) ---
  let actualHead = shellOut("git rev-parse HEAD")
  if actualHead != repoHead:
    die("repo-head mismatch: got '" & actualHead & "' expected '" & repoHead & "'", 3)
  let actualDigest = shellOut("git ls-tree -r HEAD | sha256sum").splitWhitespace()[0]
  if actualDigest != treeDigest:
    die("tree-digest mismatch: got '" & actualDigest & "' expected '" & treeDigest & "'", 3)
  let porcelain = shellOut("git status --porcelain --untracked-files=no")
  let workingTreeClean = porcelain.len == 0
  let actualBranch = shellOut("git rev-parse --abbrev-ref HEAD")
  echo "[collect_evidence_probe] repoHead=" & actualHead
  echo "[collect_evidence_probe] branch=" & actualBranch
  echo "[collect_evidence_probe] treeDigest=" & actualDigest
  echo "[collect_evidence_probe] workingTreeClean=" & $workingTreeClean

  # --- toolchain probes (observed, for the evidence toolchain envelope) ---
  let nimVer = shellOut("nim --version | head -1")
  let z3Ver = shellOut("z3 --version")
  let leanVer = shellOut("lean --version | head -1")
  echo "[collect_evidence_probe] observed tools: " & nimVer & " | " & z3Ver & " | " & leanVer

  # --- product surface actuation ---
  let repoRoot = getCurrentDir()
  let axBin = repoRoot / "bin" / "ax"
  if not fileExists(axBin):
    die("product binary missing: " & axBin & " (rebuild via `make ci-bootstrap`)", 3)
  let axVer     = runSplit(axBin, @["--version"], repoRoot)
  let axHelp    = runSplit(axBin, @["help"], repoRoot)
  let proveHelp = runSplit(axBin, @["prove", "--help"], repoRoot)
  let reportHelp = runSplit(axBin, @["report", "--help"], repoRoot)
  let reportJson = runSplit(axBin, @["report", "--json"], repoRoot)

  # --- documented commands: README.md (canonical doc, sha256-anchored below) ---
  let readmeText = readFile(repoRoot / "README.md")
  var documented: seq[string] = @[]
  for tok in ["ax prove", "ax report", "ax cert verify"]:
    if tok in readmeText:
      documented.add(tok)

  # --- commandExists: live help listing cross-checked by dedicated probes ---
  let surfaceProve  = (axHelp.exitCode == 0 and "prove" in axHelp.stdout) and
                      proveHelp.exitCode == 0 and "prove" in proveHelp.stdout
  let surfaceReport = (axHelp.exitCode == 0 and "report" in axHelp.stdout) and
                      reportHelp.exitCode == 0 and "report" in reportHelp.stdout
  let surfaceCert   = (axHelp.exitCode == 0 and "cert" in axHelp.stdout)

  # --- promise outputs ---
  var promiseJson = false
  var reportSchema = ""
  try:
    let j = parseJson(reportJson.stdout)
    if j.hasKey("schemaVersion"):
      reportSchema = j["schemaVersion"].getStr()
      promiseJson = reportSchema == "axiom.report.v1"
  except CatchableError:
    discard
  let certDir = repoRoot / "build" / "certificates"
  var certPath = ""
  try:
    for f in walkFiles(certDir / "*.json"):
      let cf = parseFile(f)
      if cf.hasKey("schemaVersion") and cf["schemaVersion"].getStr() == "axiom.certificate.v3":
        certPath = f
        break
  except CatchableError:
    discard
  let promiseCert = certPath.len > 0

  # --- R1 observations ---
  var observations = newJArray()
  # documentedCommand is a SINGLE observation with a JSON-array value:
  # ruleR1 (tools/readiness_evaluator.nim:419) reduces it via stringListValue,
  # which expands a JArray. Emitting one observation per token instead would
  # collide on (key,scope,subject)=(documentedCommand,doc,README.md) in
  # normalizeBundle and force contradiction -> UNKNOWN.
  var docArr = newJArray()
  for tok in documented:
    docArr.add(%tok)
  observations.add(%*{"key": "documentedCommand", "value": docArr,
                      "scope": "doc", "subject": "README.md"})
  observations.add(%*{"key": "commandExists", "value": surfaceProve,
                      "scope": "surface", "subject": "ax prove"})
  observations.add(%*{"key": "commandExists", "value": surfaceReport,
                      "scope": "surface", "subject": "ax report"})
  observations.add(%*{"key": "commandExists", "value": surfaceCert,
                      "scope": "surface", "subject": "ax cert verify"})
  observations.add(%*{"key": "promiseOutputExists", "value": promiseJson,
                      "scope": "artifact",
                      "subject": "json-report: ax report --json top-level schemaVersion" &
                                  (if reportSchema.len > 0: "=" & reportSchema else: "")})
  observations.add(%*{"key": "promiseOutputExists", "value": promiseCert,
                      "scope": "artifact",
                      "subject": "v3 certificate artifact under build/certificates/"})

  # --- envelope ---
  let envelope = newJObject()
  envelope["schemaVersion"] = %1
  envelope["invariantId"] = %"R1"
  envelope["repoIdentity"] = %*{"head": repoHead, "branch": actualBranch,
                                "workingTreeClean": workingTreeClean,
                                "treeDigest": treeDigest}
  envelope["toolchain"] = %*{"nim": nimT, "z3": z3T, "lean": leanT}
  envelope["collection"] = %*{"collector": "tools/collect_evidence_probe.nim",
                              "method": "automated",
                              "generatedAt": evalTime,
                              "freshUntil": freshUntilOf(evalTime)}
  envelope["observations"] = observations
  var incidents = newJArray()
  if reportJson.exitCode != 0:
    incidents.add(%*{"id": "R1-OBS-001", "severity": "info",
                     "summary": "ax report --json exited " & $reportJson.exitCode &
                     " (verification-failure state; JSON still emitted on stdout)"})
  if not workingTreeClean:
    incidents.add(%*{"id": "R1-OBS-002", "severity": "warning",
                     "summary": "working tree not clean (tracked file changes present); R1 evidence requires clean tree per evaluator"})
  envelope["incidents"] = incidents

  var sources = newJArray()
  if fileExists(repoRoot / "README.md"):
    sources.add(%*{"file": "README.md", "sha256": sha256File(repoRoot / "README.md"),
                   "repoHead": repoHead, "symbol": "documented run steps"})
  if fileExists(repoRoot / "docs/spec/productization_contract.md"):
    sources.add(%*{"file": "docs/spec/productization_contract.md",
                   "sha256": sha256File(repoRoot / "docs/spec/productization_contract.md"),
                   "repoHead": repoHead, "symbol": "R1 contract"})
  if certPath.len > 0:
    sources.add(%*{"file": certPath, "sha256": sha256File(certPath),
                   "repoHead": repoHead, "symbol": "v3 certificate artifact"})
  envelope["sources"] = sources

  var commands = newJArray()
  proc addCommand(list: var JsonNode; cmdLine: string; r: RunResult) =
    list.add(%*{"cmd": cmdLine, "exitCode": r.exitCode,
                "stdoutDigest": sha256String(r.stdout),
                "stderrDigest": sha256String(r.stderr),
                "outputDigest": sha256String(r.stdout & r.stderr)})
  addCommand(commands, "bin/ax --version", axVer)
  addCommand(commands, "bin/ax help", axHelp)
  addCommand(commands, "bin/ax prove --help", proveHelp)
  addCommand(commands, "bin/ax report --help", reportHelp)
  addCommand(commands, "bin/ax report --json", reportJson)
  envelope["commands"] = commands

  # --- write evidence ---
  createDir(evidenceDir)
  let outPath = evidenceDir / "R1.json"
  writeFile(outPath, pretty(envelope))
  stdout.writeLine("[collect_evidence_probe] wrote " & outPath)
  stdout.writeLine("[collect_evidence_probe] R1 documented=" & $documented &
                   " exists(prove,report,cert)=" & $surfaceProve & "," & $surfaceReport & "," & $surfaceCert &
                   " promiseJson=" & $promiseJson & " schemaVersion=" & reportSchema &
                   " promiseCert=" & $promiseCert)

  # --- R8 evidence: §10.6 Rust subject prepare sequence (real actuation).
  # The prepare commands are recorded ONLY as actually executed in this
  # collection; a missing cargo/probe crate is a truthful incident and leaves
  # the commands absent (R8 fails closed at the evaluator — never fabricated).
  var r8Commands = newJArray()
  var r8Incidents = newJArray()
  addCommand(r8Commands, "bin/ax --version", axVer)

  proc addPrepIncident(id: string; cmdLine: string; r: RunResult) =
    if r.exitCode != 0:
      r8Incidents.add(%*{"id": id, "severity": "warning",
                         "summary": cmdLine & " exited " & $r.exitCode &
                         " (recorded truthfully; exit 0 required)"})

  let cargoExe = findExe("cargo")
  let probeManifest = rustProbeDir / "Cargo.toml"
  let probeLock = rustProbeDir / "Cargo.lock"
  if cargoExe.len == 0:
    r8Incidents.add(%*{"id": "R8-PREP-001", "severity": "warning",
                       "summary": "cargo not found on PATH; §10.6 prepare sequence not executed — commands honestly absent (fail-closed at the evaluator)"})
  elif not fileExists(probeManifest) or not fileExists(probeLock):
    r8Incidents.add(%*{"id": "R8-PREP-002", "severity": "warning",
                       "summary": "Rust probe crate incomplete at " & rustProbeDir &
                       " (Cargo.toml/Cargo.lock required); prepare sequence not executed — commands honestly absent"})
  else:
    let fetchRes = runSplit("cargo", @["fetch", "--locked"], rustProbeDir)
    let metaRes = runSplit("cargo", @["metadata", "--format-version=1", "--locked"], rustProbeDir)
    let buildRes = runSplit("cargo", @["build", "--frozen"], rustProbeDir)
    addCommand(r8Commands, "cargo fetch --locked", fetchRes)
    addCommand(r8Commands, "cargo metadata --format-version=1 --locked", metaRes)
    addCommand(r8Commands, "cargo build --frozen", buildRes)
    addPrepIncident("R8-PREP-003", "cargo fetch --locked", fetchRes)
    addPrepIncident("R8-PREP-004", "cargo metadata --format-version=1 --locked", metaRes)
    addPrepIncident("R8-PREP-005", "cargo build --frozen", buildRes)

  # R8 observations — only what this collection actuates (absence of a key is
  # no claim; the evaluator never reads absence as false).
  let contractPath = repoRoot / "docs" / "spec" / "productization_contract.md"
  let contractText = if fileExists(contractPath): readFile(contractPath) else: ""
  let seqDocumented = ("cargo fetch --locked" in contractText and
                       "cargo metadata --format-version=1 --locked" in contractText and
                       "cargo build --frozen" in contractText)
  let flowDocumented = ("ax prove" in readmeText and "ax report" in readmeText)
  let installFollowed = (nimVer.len > 0 and z3Ver.len > 0 and leanVer.len > 0 and
                         axVer.exitCode == 0)
  var r8Obs = newJArray()
  r8Obs.add(%*{"key": "installFollowed", "value": installFollowed,
               "scope": "operability",
               "subject": "toolchains nim/z3/lean observed + bin/ax --version exit " &
                          $axVer.exitCode})
  r8Obs.add(%*{"key": "documentedRunSteps", "value": flowDocumented and seqDocumented,
               "scope": "operability",
               "subject": "README run flow + contract §10.6 prepare sequence verbatim"})

  var r8Sources = newJArray()
  if fileExists(repoRoot / "README.md"):
    r8Sources.add(%*{"file": "README.md", "sha256": sha256File(repoRoot / "README.md"),
                     "repoHead": repoHead, "symbol": "documented run steps"})
  if fileExists(contractPath):
    r8Sources.add(%*{"file": "docs/spec/productization_contract.md",
                     "sha256": sha256File(contractPath),
                     "repoHead": repoHead, "symbol": "R8 contract §10.6 prepare sequence"})
  if fileExists(probeManifest):
    r8Sources.add(%*{"file": probeManifest, "sha256": sha256File(probeManifest),
                     "repoHead": repoHead, "symbol": "Rust probe crate manifest"})
  if fileExists(probeLock):
    r8Sources.add(%*{"file": probeLock, "sha256": sha256File(probeLock),
                     "repoHead": repoHead, "symbol": "Rust probe crate lockfile"})

  let r8Envelope = newJObject()
  r8Envelope["schemaVersion"] = %1
  r8Envelope["invariantId"] = %"R8"
  r8Envelope["repoIdentity"] = %*{"head": repoHead, "branch": actualBranch,
                                  "workingTreeClean": workingTreeClean,
                                  "treeDigest": treeDigest}
  r8Envelope["toolchain"] = %*{"nim": nimT, "z3": z3T, "lean": leanT}
  r8Envelope["collection"] = %*{"collector": "tools/collect_evidence_probe.nim",
                                "method": "automated",
                                "generatedAt": evalTime,
                                "freshUntil": freshUntilOf(evalTime)}
  r8Envelope["observations"] = r8Obs
  r8Envelope["incidents"] = r8Incidents
  r8Envelope["sources"] = r8Sources
  r8Envelope["commands"] = r8Commands
  let r8Path = evidenceDir / "R8.json"
  writeFile(r8Path, pretty(r8Envelope))
  stdout.writeLine("[collect_evidence_probe] wrote " & r8Path)
  stdout.writeLine("[collect_evidence_probe] R8 installFollowed=" & $installFollowed &
                   " documentedRunSteps=" & $(flowDocumented and seqDocumented) &
                   " prepareCommands=" & $(r8Commands.len - 1) &
                   " incidents=" & $r8Incidents.len)
  quit(0)