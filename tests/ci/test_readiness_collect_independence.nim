## test_readiness_collect_independence.nim — readiness collector independence
## (DEBT#537 slice: readiness verdict wiring as a required check).
##
## PR-1 self-verification proves the collector RUNS in CI; it does not prove
## the collector REPORTS HONESTLY when it cannot measure. These are the three
## user-required independence cases, driven against the real compiled
## collector (bin/readiness_collect_ci --repo-root . --artifacts <dir>
## --out <dir>), with the real gate and evaluator completing the chain:
##
##   1. mandatory artifacts missing -> exit 0 (evidence is still produced —
##      collector success is independent of observation outcome) and no
##      forged success: the generated bundle must not evaluate to GO.
##      Forged PASS is detected through the verdict SSOT
##      (bin/readiness_evaluator over the generated evidence), so the check
##      does not depend on the collector's observation encoding.
##   2. foreign identity: the collector REFUSES to run with
##      AXIOM_CI_REPO_HEAD contradicting git HEAD (exit 2, no evidence
##      written); a clean run stamps the TRUE repo identity; and a bundle
##      whose repoIdentity is rewritten to a foreign commit (what a
##      different checkout would legitimately produce) is rejected by the
##      gate's CI identity authority as a READINESS_IDENTITY_MISMATCH
##      (exit 1) — evidence collected for a foreign commit never enters a
##      verdict for this one. (Adjudicated against C2's landed contract:
##      refusing contradictory identity is stronger than stamping env
##      values verbatim and relying on the gate to catch them.)
##   3. ax binary absent: the collector run against a repo-root without bin/ax
##      keeps exit 0 and records the CLI-surface observations (R1/R5/R6) as
##      UNKNOWN/FAIL — never PASS: no commandExists observation may claim
##      true, and the evaluator states for R1/R5/R6 must not be PASS.
##
## C2 gating: bin/readiness_collect_ci is landed by the C2 collector agent in
## this workstream. While the binary is absent, each case prints a loud
## PENDING marker and is skipped (unittest SKIPPED) instead of failing; once
## the binary exists, the contract above is asserted unconditionally. The
## gate half of case 2 additionally requires the C1 identity binding (see
## test_readiness_verdict_mapping.nim for the same probe).
##
## Interface assumptions this file makes about the C2 contract surface
## (flagged to the integrator — adjust here if C2 differs):
##   * the collector writes one evidence file per invariant, named R<n>.json
##     under --out, in the committed data/readiness/evidence/R*.json schema;
##   * repoIdentity stamps carry the TRUE git identity (env values are
##     cross-checked against git HEAD; a contradicting pair is refused with
##     exit 2 before any evidence is written).

import std/[algorithm, json, os, osproc, streams, strutils, strtabs, unittest]

let
  Root = block:
    var r = absolutePath(currentSourcePath())
    for _ in 0 ..< 3: r = r.parentDir()
    r
  CollectorBin = Root / "bin" / "readiness_collect_ci"
  CollectorSrc = Root / "tools" / "ci" / "readiness_collect_ci.nim"
  GateBin = Root / "bin" / "readiness_start_gate"
  EvaluatorBin = Root / "bin" / "readiness_evaluator"
  EvidenceDir = Root / "data" / "readiness" / "evidence"
  Work = getTempDir() / "axiom_c3_readiness_collect"

const
  OtherHead = "fedcba9876543210fedcba9876543210fedcba98"
  OtherTree = "0123456789abcdef0123456789abcdef01234567"
  TmpRepoHead = "89abcdef89abcdef89abcdef89abcdef89abcdef"
  TmpRepoTree = "456789ab456789ab456789ab456789ab456789ab"
  EvalTime = "2026-11-16T00:00:00Z"
  R1ToR8 = ["R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8"]

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

let
  ProbeAx = Root / "build" / "readiness_c3_probe" / "ax"

proc ensureProbeAxBinary(): bool =
  ## Same rationale as test_readiness_verdict_mapping.nim: the E2E inside the
  ## gate execs bin/ax unless AXIOM_START_GATE_AX_BIN names an existing
  ## binary; a repo-internal non-canonical copy skips only the path-bound
  ## source-coherence self-check while every E2E assertion still runs.
  if not fileExists(Root / "bin" / "ax"):
    return false
  if not fileExists(ProbeAx):
    createDir(parentDir(ProbeAx))
    copyFileWithPermissions(Root / "bin" / "ax", ProbeAx)
  true

proc tempProbeCopy(): string =
  ## The collector resolves a relative --rust-probe-dir against --repo-root
  ## (tools/ci/readiness_collect_ci.nim probeRoot), so a "."-rooted run would
  ## let cargo write target/ into the tracked tree. Each case gets a sandbox
  ## copy under the test work dir instead.
  result = Work / "probe_copy_" & $getCurrentProcessId()
  if dirExists(result):
    removeDir(result)
  createDir(result)
  copyDir(Root / "tests" / "fixtures" / "rust" / "axiom_rust_probe", result)

proc runCollector(repoRoot, artifactsDir, outDir: string;
                  extraEnv: openArray[(string, string)] = @[];
                  rustProbeDir: string = ""):
    tuple[output: string, exit: int] =
  var args = @["--repo-root", repoRoot, "--artifacts", artifactsDir,
               "--out", outDir]
  if rustProbeDir.len > 0:
    args.add(@["--rust-probe-dir", rustProbeDir])
  runBin(CollectorBin, args, extraEnv, Root)

proc runGate(extraEnv: openArray[(string, string)] = @[]):
    tuple[output: string, exit: int] =
  var env = @[("AXIOM_START_GATE_AX_BIN", ProbeAx)]
  for (k, v) in extraEnv:
    env.add((k, v))
  runBin(GateBin, @[], env, Root)

proc gateBinaryEmbeds(marker: string): bool =
  try:
    readFile(GateBin).contains(marker)
  except CatchableError:
    false

let GateBindsCiIdentity = gateBinaryEmbeds("AXIOM_CI_REPO_HEAD")

proc collectorPendingMsg(caseName: string): string =
  "[PENDING][C2-collector] " & caseName & ": bin/readiness_collect_ci " &
       "absent (source " &
       (if fileExists(CollectorSrc): "exists — not built yet" else:
        "absent — C2 not landed") &
       "); contract assertions deferred to integration."
proc gateIdentityPendingMsg(): string =
  "[PENDING][C1-gate-wiring] gate half of the foreign-SHA chain: gate " &
       "binary lacks AXIOM_CI_REPO_HEAD binding; mismatch rejection not " &
       "assertable yet."

# ---------------------------------------------------------------------------
# Evaluator projection — the no-forged-success detector.
# ---------------------------------------------------------------------------

proc runEvaluatorOn(evidenceDir: string; decisionName: string):
    tuple[exit: int, verdict: string, states: JsonNode] =
  let outDir = Work / "decisions"
  createDir(outDir)
  let outPath = outDir / decisionName
  let r = runBin(EvaluatorBin,
                 @["--policy", Root / "config" / "readiness_policy.json",
                   "--evidence-dir", evidenceDir,
                   "--eval-time", EvalTime,
                   "--out", outPath])
  result.exit = r.exit
  result.states = nil
  try:
    let node = parseFile(outPath)
    result.verdict = node{"verdict"}.getStr("")
    result.states = node{"invariantStates"}
  except CatchableError:
    discard # axiom:best-effort(unreadable decision keeps verdict="" so the no-forged-success check fails closed)

proc stateOf(states: JsonNode; invId: string): string =
  if states != nil and states.kind == JObject and states.hasKey(invId):
    states[invId].getStr("")
  else:
    ""

# ---------------------------------------------------------------------------
# Evidence snapshot swap (same fixed-path constraint as the mapping test: the
# gate reads data/readiness/evidence at a compile-time-anchored repo root).
# ---------------------------------------------------------------------------

type
  FixtureFile = tuple[name, content: string]

proc committedEvidence(): seq[FixtureFile] =
  for f in walkFiles(EvidenceDir / "*.json"):
    result.add((name: extractFilename(f), content: readFile(f)))
  result.sort(proc(a, b: FixtureFile): int = cmp(a.name, b.name))

let OriginalEvidence = committedEvidence()

proc installFixtures(files: seq[FixtureFile]) =
  for f in walkFiles(EvidenceDir / "*.json"):
    removeFile(f)
  for f in items files:
    writeFile(EvidenceDir / f.name, f.content)

proc collectedAsFixtures(outDir: string): seq[FixtureFile] =
  for f in walkFiles(outDir / "*.json"):
    result.add((name: extractFilename(f), content: readFile(f)))
  result.sort(proc(a, b: FixtureFile): int = cmp(a.name, b.name))

proc evidenceMatches(expected: seq[FixtureFile]): bool =
  let cur = committedEvidence()
  if cur.len != expected.len:
    return false
  for i in 0 ..< cur.len:
    if cur[i].name != expected[i].name or cur[i].content != expected[i].content:
      return false
  true

# ---------------------------------------------------------------------------
# Case helpers.
# ---------------------------------------------------------------------------

proc parseEvidenceFile(f: string): JsonNode =
  try:
    parseFile(f)
  except CatchableError:
    nil

proc lastNonEmptyLine(s: string): string =
  ## The collector's fatal lines end the output; a trailing newline must not
  ## blank out the only diagnostic the integrator gets.
  for line in s.splitLines():
    if line.strip().len > 0:
      result = line.strip()

proc freshWorkDir(name: string): string =
  result = Work / name
  if dirExists(result):
    removeDir(result)
  createDir(result)

suite "readiness collector independence (DEBT#537)":

  test "1. missing artifacts: exit 0, evidence produced, no forged success":
    if not fileExists(CollectorBin):
      echo collectorPendingMsg("missing artifacts honesty")
      skip()
    else:
      let artifacts = freshWorkDir("empty_artifacts")
      let outDir = freshWorkDir("case1_out")
      let r = runCollector(".", artifacts, outDir, rustProbeDir = tempProbeCopy())
      checkpoint("collector exit " & $r.exit)
      checkpoint("collector output tail: " & lastNonEmptyLine(r.output))
      check r.exit == 0
      for invId in R1ToR8:
        let f = outDir / (invId & ".json")
        check fileExists(f)
        # `check doc != nil` segfaults inside unittest's failure formatting
        # (it stringifies the JsonNode operand; `$` of nil crashes), so a
        # missing/unparseable evidence file fails via a bool-only check.
        let doc = parseEvidenceFile(f)
        if doc == nil:
          checkpoint(invId & ": " & f & " missing or unparseable")
          check false
          continue
        check doc{"schemaVersion"}.getInt(0) == 1
        check doc{"invariantId"}.getStr("") == invId
        check doc{"collection"}{"generatedAt"}.getStr("") != ""
        check doc{"collection"}{"freshUntil"}.getStr("") != ""
        check doc{"repoIdentity"}{"head"}.getStr("") != ""
      let ev = runEvaluatorOn(outDir, "case1")
      # exit==0 + non-empty verdict keep the no-forged-success check from
      # passing vacuously on a failed evaluator run (the evaluator exits 1
      # when it cannot write its decision; verdict parsing then yields "").
      checkpoint("evaluator exit " & $ev.exit &
                 ", empty-artifact bundle evaluates to: '" & ev.verdict & "'")
      check ev.exit == 0
      check ev.verdict != ""
      check ev.verdict != "GO"

  test "2. foreign identity refused; honest stamp; gate rejects foreign bundle":
    if not fileExists(CollectorBin):
      echo collectorPendingMsg("foreign-SHA refusal + gate chain")
      skip()
    else:
      # Integrator adjudication (DEBT#537 slice): C2's collector
      # cross-validates AXIOM_CI_REPO_HEAD against git HEAD and exits 2 on
      # contradiction — a STRONGER contract than the env-verbatim stamp this
      # case originally assumed (refusing to collect for a foreign commit
      # beats stamping it and relying on the gate to reject). The case now
      # asserts the landed contract: (a) contradictory identity is refused
      # with no evidence written, (b) a clean run stamps the TRUE repo
      # identity, and (c) a foreign-identity bundle — the artifact a
      # different checkout would legitimately produce — is rejected by the
      # gate's CI identity authority. (c) rewrites repoIdentity in a COPY of
      # the collected bundle (all files, consistently, so the gate's local
      # identity merge succeeds and the CI-authority comparison is the
      # failing layer).
      let artifacts = freshWorkDir("empty_artifacts")
      let refusedOut = freshWorkDir("case2_refused")
      let r = runCollector(".", artifacts, refusedOut,
                           @[("AXIOM_CI_REPO_HEAD", OtherHead),
                             ("AXIOM_CI_TREE_DIGEST", OtherTree)],
                           rustProbeDir = tempProbeCopy())
      checkpoint("collector exit " & $r.exit)
      checkpoint("collector output tail: " & lastNonEmptyLine(r.output))
      check r.exit == 2
      check "identity contradiction" in r.output
      var refusedFiles: seq[string] = @[]
      for f in walkFiles(refusedOut / "*.json"):
        refusedFiles.add(f)
      checkpoint("evidence files after refusal: " & $refusedFiles.len)
      check refusedFiles.len == 0

      let honestOut = freshWorkDir("case2_out")
      let h = runCollector(".", artifacts, honestOut,
                           rustProbeDir = tempProbeCopy())
      checkpoint("honest collector exit " & $h.exit)
      check h.exit == 0
      let headRes = runBin("git", ["rev-parse", "HEAD"])
      # Same digest recipe as the workflow's AXIOM_CI_TREE_DIGEST export and
      # the collector's shellTrim+sha256Hex: hash the ls-tree output with the
      # trailing newline stripped, not the raw stream.
      let lsRes = runBin("sh",
          ["-c", "printf '%s' \"$(git ls-tree -r HEAD)\" | sha256sum | cut -d' ' -f1"])
      check headRes.exit == 0
      check lsRes.exit == 0
      let trueHead = headRes.output.strip()
      let trueTree = lsRes.output.strip()
      for invId in R1ToR8:
        let f = honestOut / (invId & ".json")
        check fileExists(f)
        let doc = parseEvidenceFile(f)
        if doc == nil:
          checkpoint(invId & ": " & f & " missing or unparseable")
          check false
          continue
        checkpoint(invId & " stamped head=" &
                   doc{"repoIdentity"}{"head"}.getStr(""))
        check doc{"repoIdentity"}{"head"}.getStr("") == trueHead
        check doc{"repoIdentity"}{"treeDigest"}.getStr("") == trueTree

      if fileExists(GateBin) and GateBindsCiIdentity:
        check ensureProbeAxBinary()
        let foreign = freshWorkDir("case2_foreign")
        for invId in R1ToR8:
          let doc = parseEvidenceFile(honestOut / (invId & ".json"))
          if doc == nil:
            checkpoint(invId & ": honest bundle file missing or unparseable")
            check false
            continue
          doc{"repoIdentity"}{"head"} = %OtherHead
          doc{"repoIdentity"}{"treeDigest"} = %OtherTree
          writeFile(foreign / (invId & ".json"), doc.pretty())
        let backup = committedEvidence()
        defer:
          installFixtures(backup)
          check evidenceMatches(backup)
        installFixtures(collectedAsFixtures(foreign))
        let g = runGate([("AXIOM_CI_REPO_HEAD", trueHead),
                         ("AXIOM_CI_TREE_DIGEST", trueTree)])
        check g.exit == 1
        check "READINESS_IDENTITY_MISMATCH" in g.output
        check ("expected=" & trueHead) in g.output
        check ("actual=" & OtherHead) in g.output
      else:
        echo gateIdentityPendingMsg()

  test "3. ax binary absent: R1/R5/R6 UNKNOWN/FAIL, never PASS":
    if not fileExists(CollectorBin):
      echo collectorPendingMsg("ax-absent honesty")
      skip()
    else:
      let tmpRoot = freshWorkDir("repo_no_ax")
      createDir(tmpRoot / "config")
      copyFile(Root / "config" / "readiness_policy.json",
               tmpRoot / "config" / "readiness_policy.json")
      writeFile(tmpRoot / ".axiom_root", "")
      # The collector's R2 source-structure entry reads this file through an
      # unguarded shaFile; a checkout without it crashes the collector with
      # an unhandled IOError (exit 1, partial evidence — reported as a
      # robustness contract difference). A real checkout-without-bin/ax has
      # the source tree, so the fixture carries it.
      createDir(tmpRoot / "src" / "core" / "types")
      copyFile(Root / "src" / "core" / "types" / "certificate_types.nim",
               tmpRoot / "src" / "core" / "types" / "certificate_types.nim")
      # No bin/ and no bin/ax: the CLI surface the R1/R5/R6 rules read is
      # deliberately absent — unmeasurable, so it must not become PASS.
      # The CI identity env pair is exported as in the workflow: the temp root
      # is not a git checkout, so the repo identity can only arrive via the
      # environment (the collector measures identity from env/git; a non-git
      # root without env is unmeasurable and fails closed on its own).
      let artifacts = Work / "empty_artifacts"
      if not dirExists(artifacts):
        createDir(artifacts)
      let outDir = freshWorkDir("case3_out")
      let r = runCollector(tmpRoot, artifacts, outDir,
                           @[("AXIOM_CI_REPO_HEAD", TmpRepoHead),
                             ("AXIOM_CI_TREE_DIGEST", TmpRepoTree)])
      checkpoint("collector exit " & $r.exit)
      checkpoint("collector output tail: " & lastNonEmptyLine(r.output))
      check r.exit == 0
      for invId in ["R1", "R5", "R6"]:
        let f = outDir / (invId & ".json")
        check fileExists(f)
        let doc = parseEvidenceFile(f)
        if doc == nil:
          checkpoint(invId & ": " & f & " missing or unparseable")
          check false
          continue
        if doc{"observations"} != nil and doc{"observations"}.kind == JArray:
          for o in doc{"observations"}.items:
            if o{"key"}.getStr("") == "commandExists":
              let v = o{"value"}
              if v != nil and v.kind == JBool:
                check v.getBool() == false
      let ev = runEvaluatorOn(outDir, "case3")
      checkpoint("evaluator exit " & $ev.exit &
                 ", ax-absent bundle evaluates to: '" & ev.verdict & "'")
      check ev.exit == 0
      check ev.verdict != ""
      check ev.verdict != "GO"
      for invId in ["R1", "R5", "R6"]:
        checkpoint(invId & " = " & stateOf(ev.states, invId))
        check stateOf(ev.states, invId) != "PASS"

  test "committed evidence snapshot untouched by collector cases":
    check evidenceMatches(OriginalEvidence)
