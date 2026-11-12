## tools/ci/wp5_relocation_measure.nim — WP5 relocation-invariance measurement (R3).
##
## Measures the live relocation invariant of productization_contract.md §6/R3:
##   pathIndependentProjectionEqual — the SAME logical subject, verified at two
##     different physical roots (two different AXIOM_STATE_DIR), projects to the
##     same canonical projection hash (`ax report --canonical-digest`).
##   subjectRunProjectionHashEqual — two subject-scoped cold runs of the same
##     subject project to the same canonical projection hash.
##
## Controls (fail-closed — the harness proves it observes the projection):
##   negative control (must-flip): a false_post-style mutation (identical body,
##     falsified postcondition) MUST change the digest; otherwise the
##     measurement is not observing the projection and no evidence is emitted.
##   sensitivity check (must-NOT-flip): a comment-only source change must NOT
##     change the digest — the projection is about semantics, not bytes.
##
## All runs use the same cache policy: cold (a fresh AXIOM_STATE_DIR per run),
## because cacheHit/cacheHitCount sensitivity across a cold/warm boundary is
## real (productization_contract.md §6 exclusion table).
##
## Fail-closed on infrastructure absence: a missing bin/ax, z3, lean, nim,
## unusable git identity, a prove-run crash, or a missing proof state yields
## exit 3 and no evidence file.
##
## State seeding: each fresh AXIOM_STATE_DIR is seeded with the repo's canonical
## execution-contract snapshot `data/verification_scope.lock` (identical bytes
## at every root — the pipeline fail-closes without it, and it is contract
## input, not run output, so seeding it keeps every comparison on the same
## execution contract).
##
## Build: nim c --path:src -d:release -o:bin/wp5_relocation_measure \
##          tools/ci/wp5_relocation_measure.nim
## Usage:
##   wp5_relocation_measure --repo-root D --out E.json [--keep-workdir] [--help]
## Exit codes: 0 = evidence written; 2 = CLI misuse; 3 = infrastructure absence;
##             4 = measurement invalid (a control failed; no evidence emitted).

import std/[os, osproc, json, strutils, times, strtabs]
import core/crypto/hash_kernel

const
  ProveTimeoutSeconds = 300
  ReportTimeoutSeconds = 60
  SubjectFileName = "proximity.nim"
  # Certified-subset subject (cf. topology_dependency.nim::proximityScore,
  # tests/unit/test_proximity_score_canonical_spike.nim): the early-return
  # ckIfStmt shape (single elif branch whose then-body is exactly a
  # [ckReturnStmt]) plus one non-constant division — inside the
  # certified-subset wire set (src/verification/ast_wire.nim), so the
  # extraction agreement seals and the canonical Lean path verifies. The
  # previous absVal probe body (`if x < 0: -x else: x`) is an if-EXPRESSION
  # (Nim nnkIfExpr → ckIfExpr, rejected in any shape; Nim doc/astspec.txt:
  # statement form parses nnkIfStmt(nnkElifBranch(…)), expression form
  # nnkIfExpr(nnkElifExpr(…))) and its `## @axiom:` doc comment is parsed by
  # no extractor — both probe states collapsed to the same no-obligation
  # UNKNOWN projection and the negative control could never flip. The
  # contract rides the `{.axiom: [...]}` pragma channel — the only spec
  # channel the external materializer reads (external_ir_materializer.nim
  # ingestExplicitSpec). Subject symbol name must not collide with a
  # kernel-registered symbol (a `proximityScore` subject dedupes against the
  # compiled-in entry and never appears as an external census candidate).
  SubjectContractPrefix =
    "func subjectProximity(interfaceDistance: int; nodeCount: int): int {.\n" &
    "  axiom: [pre: (interfaceDistance >= 0 and nodeCount >= 0),\n"
  SubjectBodySuffix =
    "          ].} =\n" &
    "  if interfaceDistance > nodeCount:\n" &
    "    return 0\n" &
    "  60 div (interfaceDistance + 1)\n"
  # Positive subject — a true postcondition the canonical kernel admits
  # (0 ≤ 60 div (i+1) ≤ 60 on the pre-domain; measured lean_kernel_accepted).
  SubjectPositive =
    SubjectContractPrefix & "          post: (result >= 0 and result <= 60)" &
    SubjectBodySuffix
  # Negative control — false_post style (docs/spec/rust_negative_control_norm.md):
  # body byte-identical (shared suffix), ONLY the postcondition is falsified
  # (`result > 60` is false at interfaceDistance == nodeCount, where the body
  # returns 0) — the kernel genuinely rejects (measured lean_kernel_rejected,
  # prove exit 1), it is not merely left unverified.
  SubjectFalsePost =
    SubjectContractPrefix & "          post: (result > 60)" & SubjectBodySuffix
  # Sensitivity check — semantically inert byte change: a trailing comment line.
  SubjectCommentOnly =
    SubjectPositive &
    "# comment-only mutation: semantically inert bytes\n"

type
  RunOutcome = object
    exitCode: int
    output: string
  ProveRecord = object
    runName: string
    cmdline: string
    exitCode: int
    output: string
    digest: string
    digestCmd: string
    digestExitCode: int
    digestOutput: string

proc die(msg: string, code = 3) {.noreturn.} =
  stderr.writeLine("[wp5_relocation_measure] " & msg)
  quit(code)

proc quoted(args: seq[string]): string =
  var parts: seq[string]
  for a in args:
    parts.add(quoteShell(a))
  parts.join(" ")

proc runCmd(cmdline: string, workingDir: string, stateDir = ""): RunOutcome =
  ## Run a command with an optional AXIOM_STATE_DIR override in its environment.
  var env: StringTableRef = nil
  if stateDir.len > 0:
    env = newStringTable(modeCaseSensitive)
    for k, v in envPairs():
      env[k] = v
    env["AXIOM_STATE_DIR"] = stateDir
  let (output, code) = execCmdEx(cmdline, workingDir = workingDir, env = env)
  RunOutcome(exitCode: code, output: output)

proc runTimed(timeoutSec: int, cmdline: string, workingDir: string,
              stateDir = ""): RunOutcome =
  ## GNU coreutils `timeout` wrapper: bounded, deterministic run length.
  result = runCmd("timeout " & $timeoutSec & " " & cmdline, workingDir, stateDir)
  if result.exitCode == 124:
    die("command exceeded " & $timeoutSec & "s deadline: " & cmdline, 3)

proc gitOut(repoRoot: string, args: seq[string]): string =
  let r = runCmd("git " & quoted(args), repoRoot)
  if r.exitCode != 0:
    die("git " & args.join(" ") & " failed (exit " & $r.exitCode & "): " &
        r.output.strip(), 3)
  r.output.strip()

proc firstLine(s: string): string =
  for line in s.splitLines():
    let t = line.strip()
    if t.len > 0:
      return t
  ""

proc requireTool(name: string) =
  if findExe(name).len == 0:
    die("required tool not found on PATH: " & name, 3)

proc isoNow(): string =
  now().toTime.utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc isoFreshUntil(): string =
  format(now().toTime + initDuration(days = 30), "yyyy-MM-dd'T'HH:mm:ss'Z'")

proc canonicalDigest(repoRoot, axBin, stateFile: string): ProveRecord =
  ## Canonical projection digest of a proof state via the CLI surface
  ## (`ax report --canonical-digest --state-file …`) — the single SSOT path.
  if not fileExists(stateFile):
    die("proof state missing after run: " & stateFile, 3)
  let digestCmd = quoted(@[axBin, "report", "--canonical-digest",
                           "--state-file", stateFile])
  let r = runTimed(ReportTimeoutSeconds, digestCmd, repoRoot)
  if r.exitCode != 0:
    die("ax report --canonical-digest failed (exit " & $r.exitCode & "): " &
        r.output.strip(), 3)
  # Output may carry logger noise; the digest is the 64-hex line.
  for line in r.output.splitLines():
    let t = line.strip()
    if t.len == 64 and t.allCharsInSet(HexDigits):
      result.digest = t
      result.digestCmd = digestCmd
      result.digestExitCode = r.exitCode
      result.digestOutput = r.output
      return
  die("no 64-hex digest in --canonical-digest output: " & r.output.strip(), 3)

proc proveAndDigest(repoRoot, axBin, runDir, runName, subjectSrc: string): ProveRecord =
  ## One cold subject-scoped prove run in its own root + fresh state dir, then
  ## the canonical projection digest of the resulting proof state.
  createDir(runDir / "subject")
  createDir(runDir / "state")
  writeFile(runDir / "subject" / SubjectFileName, subjectSrc)
  let subjectDir = runDir / "subject"
  let stateDir = runDir / "state"
  # Seed the execution-contract scope lock into the fresh state root
  # (identical bytes at every run — fail-closed pipeline requirement).
  let scopeLockSrc = repoRoot / "data" / "verification_scope.lock"
  if not fileExists(scopeLockSrc):
    die("execution-contract scope lock missing in repo: " & scopeLockSrc, 3)
  createDir(stateDir / "data")
  copyFile(scopeLockSrc, stateDir / "data" / "verification_scope.lock")
  result.runName = runName
  result.cmdline = quoted(@[axBin, "prove", "--project", subjectDir,
                            "--limit", "1"])
  let prove = runTimed(ProveTimeoutSeconds, result.cmdline, repoRoot, stateDir)
  result.exitCode = prove.exitCode
  result.output = prove.output
  # exit 1 = verification-failure outcome — a legitimate deterministic result
  # (the negative control relies on it); anything else is infrastructure.
  if prove.exitCode != 0 and prove.exitCode != 1:
    die("ax prove crashed on " & runName & " (exit " & $prove.exitCode & "): " &
        prove.output.strip(), 3)
  let digestRec = canonicalDigest(repoRoot, axBin,
                                  stateDir / "logs" / "ax_proof_state.json")
  result.digest = digestRec.digest
  result.digestCmd = digestRec.digestCmd
  result.digestExitCode = digestRec.digestExitCode
  result.digestOutput = digestRec.digestOutput

proc obsBool(key: string, value: bool, scope, subject: string): JsonNode =
  ## Readiness observation — value MUST be a JSON bool: the string "true" is
  ## silently read as UNKNOWN by the evaluator.
  %*{"key": key, "value": value, "scope": scope, "subject": subject}

proc obsStr(key: string, value: string, scope, subject: string): JsonNode =
  %*{"key": key, "value": value, "scope": scope, "subject": subject}

proc addCommandEntry(commands: JsonNode, cmd: string, exitCode: int,
                     output: string) =
  commands.add(%*{"cmd": cmd, "exitCode": exitCode,
                  "outputDigest": "sha256:" & sha256Hex(output)})

proc shaFile(p: string): string =
  sha256Hex(readFile(p))

when isMainModule:
  var
    repoRoot = ""
    outPath = ""
    keepWorkdir = false
  var i = 0
  let cliArgs = commandLineParams()
  proc needValue(flag: string): string =
    if i >= cliArgs.len - 1:
      die("missing value for " & flag, 2)
    inc i
    cliArgs[i]
  while i < cliArgs.len:
    let a = cliArgs[i]
    case a
    of "--repo-root": repoRoot = needValue(a)
    of "--out": outPath = needValue(a)
    of "--keep-workdir": keepWorkdir = true
    of "--help", "-h":
      stdout.writeLine("usage: wp5_relocation_measure --repo-root D --out E.json [--keep-workdir]")
      quit(0)
    else:
      die("unknown option: " & a, 2)
    inc i
  if repoRoot.len == 0 or outPath.len == 0:
    die("usage: wp5_relocation_measure --repo-root D --out E.json [--keep-workdir]", 2)
  if not dirExists(repoRoot):
    die("repo root does not exist: " & repoRoot, 3)

  # ── infrastructure presence (fail-closed) ────────────────────────────────
  let axBin = repoRoot / "bin" / "ax"
  if not fileExists(axBin):
    die("product binary missing: " & axBin & " (build via `make build`)", 3)
  requireTool("z3")
  requireTool("lean")
  requireTool("nim")
  let nimVersion = firstLine(runTimed(ReportTimeoutSeconds, "nim --version", repoRoot).output)
  let z3Version = firstLine(runTimed(ReportTimeoutSeconds, "z3 --version", repoRoot).output)
  let leanVersion = firstLine(runTimed(ReportTimeoutSeconds, "lean --version", repoRoot).output)

  # ── repository identity (truthful; R3 requires a clean tree downstream) ──
  let repoHead = gitOut(repoRoot, @["rev-parse", "HEAD"])
  let repoBranch = gitOut(repoRoot, @["rev-parse", "--abbrev-ref", "HEAD"])
  let treeDigest = sha256Hex(gitOut(repoRoot, @["ls-tree", "-r", "HEAD"]))
  let porcelain = gitOut(repoRoot, @["status", "--porcelain", "--untracked-files=no"])
  let workingTreeClean = porcelain.len == 0

  # ── measurement: five cold runs, each with its own physical root and a
  #    fresh AXIOM_STATE_DIR (same cache policy on both sides of every
  #    comparison) ──────────────────────────────────────────────────────────
  # The per-run subject workdir lives UNDER the repo root at `.cache/`
  # (gitignored): the canonical subject-binding seal measures the SUBJECT
  # repo's git identity (canonical_verification.nim measureSubjectGitRef →
  # `git rev-parse HEAD` in the subject root). A subject outside any git
  # repo fails that seal (`subjectGitRef unmeasurable`) and every run
  # collapses to the same inconclusive projection. Under the repo, the
  # identity resolves to the repo HEAD at every root — identical for
  # identical runs, so relocation still compares like with like. Untracked
  # files do not dirty the tree-digest / porcelain checks below
  # (--untracked-files=no).
  # `.cache/` is the only root-contract-allowed location satisfying all
  # constraints (measured: PR #1263 first attempt used build/tmp/ and R3
  # failed): (1) under the repo root — git identity seal above; (2)
  # gitignored — clean status; (3) NOT under node_filter.nim excludePaths —
  # the subject source is collected via the walkDirRec fallback after
  # `git ls-files --cached --others --exclude-standard` returns empty, and
  # `build` is an excluded token there: a subject under build/ is invisible
  # to the scan ("no source files found" → ax prove exit 2 → die(…,3)).
  let workBase = repoRoot / ".cache" /
      ("axiom_wp5_relocation_" & $getCurrentProcessId())
  createDir(workBase)
  if keepWorkdir:
    stdout.writeLine("[wp5_relocation_measure] workdir: " & workBase)

  var records: seq[ProveRecord]
  for def in [
    (name: "rootA", subject: SubjectPositive),
    (name: "rootB", subject: SubjectPositive),
    (name: "rootA_rerun", subject: SubjectPositive),
    (name: "root_false_post", subject: SubjectFalsePost),
    (name: "root_comment_only", subject: SubjectCommentOnly)]:
    let runDir = workBase / def.name
    stdout.writeLine("[wp5_relocation_measure] run " & def.name & " …")
    records.add(proveAndDigest(repoRoot, axBin, runDir, def.name, def.subject))

  let digestA = records[0].digest
  let digestB = records[1].digest
  let digestA2 = records[2].digest
  let digestFalsePost = records[3].digest
  let digestCommentOnly = records[4].digest

  let pathIndependent = digestA == digestB
  let subjectRunEqual = digestA == digestA2
  let negativeControlFlips = digestFalsePost != digestA
  let commentOnlyStable = digestCommentOnly == digestA

  # Controls guard the observation: a must-flip that does not flip (or a
  # must-not-flip that flips) means the digest is not tracking semantics —
  # fail closed WITHOUT minting R3 evidence.
  if not negativeControlFlips:
    die("negative control did NOT flip the digest (false_post digest == " &
        digestFalsePost & "): measurement does not observe the projection", 4)
  if not commentOnlyStable:
    die("sensitivity check FAILED (comment-only change moved the digest to " &
        digestCommentOnly & "): projection is byte-sensitive, not semantic", 4)

  # ── evidence envelope (productization_contract.md §4 format) ─────────────
  var observations = newJArray()
  observations.add(obsBool("pathIndependentProjectionEqual", pathIndependent,
    "runtime", "same logical subject at two physical roots (distinct AXIOM_STATE_DIR), cold cache policy"))
  observations.add(obsBool("subjectRunProjectionHashEqual", subjectRunEqual,
    "runtime", "two cold subject-scoped prove runs of the same subject root"))
  observations.add(obsBool("negativeControlDigestDifferent", negativeControlFlips,
    "runtime", "false_post-style mutation (falsified postcondition) must change the digest"))
  observations.add(obsBool("commentOnlyProjectionStable", commentOnlyStable,
    "runtime", "comment-only source change must not change the digest"))
  observations.add(obsStr("wp5ProjectionHashRootA", digestA, "runtime", "cold run @rootA"))
  observations.add(obsStr("wp5ProjectionHashRootB", digestB, "runtime", "cold run @rootB (relocated)"))
  observations.add(obsStr("wp5ProjectionHashRootARerun", digestA2, "runtime", "cold rerun @rootA"))
  observations.add(obsStr("cachePolicy", "cold (fresh AXIOM_STATE_DIR per run)",
    "cache", "wp5 runs: same cache policy on both sides of every comparison"))

  var commands = newJArray()
  for r in records:
    addCommandEntry(commands, r.cmdline, r.exitCode, r.output)
    addCommandEntry(commands, r.digestCmd, r.digestExitCode, r.digestOutput)

  var sources = newJArray()
  for anchor in [
    (file: "src/core/utils/canonical_projection.nim",
     symbol: "canonical projection SSOT (volatile-key stripping)"),
    (file: "src/cli/wf_render.nim",
     symbol: "report payload fields (vaultPath/cacheHit/evidenceLogJson)"),
    (file: "docs/spec/productization_contract.md",
     symbol: "§6/R3 pathIndependentProjectionEqual contract"),
    (file: "tools/ci/wp5_relocation_measure.nim",
     symbol: "this measurement")]:
    let p = repoRoot / anchor.file
    if fileExists(p):
      sources.add(%*{"file": anchor.file, "symbol": anchor.symbol,
                     "sha256": "sha256:" & shaFile(p), "repoHead": repoHead})

  var incidents = %*[
    %*{"id": "WP5-CTRL-001", "severity": "info",
       "summary": "negative control flipped the digest (false_post mutation observed)"},
    %*{"id": "WP5-CTRL-002", "severity": "info",
       "summary": "comment-only change left the digest unchanged (semantic projection)"},
    %*{"id": "WP5-CACHE-001", "severity": "info",
       "summary": "all comparisons used the same cache policy: cold, fresh AXIOM_STATE_DIR per run"},
  ]
  if not workingTreeClean:
    incidents.add(%*{"id": "WP5-TREE-001", "severity": "warning",
      "summary": "working tree not clean — R3 evidence requires workingTreeClean=true; the evaluator will invalidate this envelope"})

  var envelope = newJObject()
  envelope["schemaVersion"] = %1
  envelope["invariantId"] = %"R3"
  envelope["repoIdentity"] = %*{"head": repoHead, "branch": repoBranch,
                                "workingTreeClean": workingTreeClean,
                                "treeDigest": treeDigest}
  envelope["toolchain"] = %*{"nim": nimVersion, "z3": z3Version, "lean": leanVersion}
  envelope["collection"] = %*{"collector": "tools/ci/wp5_relocation_measure.nim",
                              "method": "automated",
                              "generatedAt": isoNow(),
                              "freshUntil": isoFreshUntil()}
  envelope["observations"] = observations
  envelope["incidents"] = incidents
  envelope["sources"] = sources
  envelope["commands"] = commands

  writeFile(outPath, pretty(envelope))
  stdout.writeLine("[wp5_relocation_measure] wrote " & outPath)
  stdout.writeLine("[wp5_relocation_measure] pathIndependentProjectionEqual=" &
                   $pathIndependent & " subjectRunProjectionHashEqual=" & $subjectRunEqual)
  stdout.writeLine("[wp5_relocation_measure] digests A=" & digestA[0 ..< 12] &
                   " B=" & digestB[0 ..< 12] & " A2=" & digestA2[0 ..< 12] &
                   " falsePost=" & digestFalsePost[0 ..< 12] &
                   " commentOnly=" & digestCommentOnly[0 ..< 12])
  if not keepWorkdir:
    removeDir(workBase)
  quit(0)
