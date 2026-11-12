## Rust lane PRODUCT-CLI acceptance (feat/rust-lane-live-cli) — the real
## `bin/ax prove --project tests/fixtures/rust/axiom_rust_probe` surface.
##
## PLACEMENT / LEVEL (recorded decision, same as
## rust_subject_three_cases_test.nim): the filename intentionally does NOT
## match the gateway lane's `*_feature_test.nim` collection glob
## (all_gateway_runner.nim:193), so it runs standalone
## (`nim c --hints:off -r tests/gateway/rust_lane_cli_acceptance_test.nim`)
## without distorting the landing lane. Unlike the three-cases suite this IS
## an ax-spawning CLI test: it follows the spawn pattern of
## productization_start_vertical_slice_feature_test.nim (ensureAxBinary /
## runCli / fresh isolated vault) with the lane's state-root discipline
## (fresh $AXIOM_STATE_DIR carrying data/verification_scope.lock).
##
## The lane's own observable is NOT stdout — plain `ax prove` prints nothing
## to stdout (measured 0 bytes on every scenario). The durable per-run
## observables are:
##   - the trajectory SSOT entry the lane's finish() writes
##     (logStage(skReport, extra=report) →
##     $AXIOM_STATE_DIR/logs/ax_prove_trajectory.jsonl; the lane path writes
##     no ax_proof_state.json — verified live, this file is the one used).
##     A target-RESOLUTION refusal (suite 3) never reaches finish() and
##     therefore leaves NO trajectory and NO report document at all,
##   - the certificate vault at $AXIOM_PROVE_VAULT_DIR (top-level *.json,
##     irHash-keyed; the vault's data/trusted/journal subtree is not certs),
##   - the lane's log lines on stderr ([AXIOM][rust-lane] ...).
##
## CERT DETERMINISM (N=3, measured): raw certificate bytes are NOT
## byte-identical across runs — by design every cert binds its run's LOCAL
## TrustCommit journal commit (attestation.journalRef / trustCommitId /
## provenance.journalCommitId; the state journal record advances per append)
## and everything derived from that binding (attestation.signature,
## identityDigest, evidenceId, kaaDigest, canonicalKaa's executionIdentity,
## executionContractDigest) varies with it. What IS deterministic — and what
## this suite asserts across N=3 — is the exit code, the cert count, the
## irHash-keyed FILENAME (the extraction identity), and the canonical replay
## projection of the cert (the §6 discipline: the journal-chain binding
## fields excluded, the rest canonicalized and hashed; exclusion list derived
## from a 3-run field diff, not assumed).
##
## Every asserted string is the lane's own vocabulary, verbatim from
## src/cli/rust_lane_cli.nim:
##   verified entry:   status "verified", reason ""
##   kernel decline
##   (CONFIRMED):      "spec declined by kernel; counterexample CONFIRMED:
##                      <payload>" + blockStage "kernel" — status "failed"
##                      (the mutant's falsified spec is declined AND the
##                      refuting model is replay-confirmed on the real
##                      toolchain, so the entry is a FAILED target, not a
##                      pending one)
##   in-subset bool:   the v1.3 boolean Switch collapse folds is_zero/tri
##                      into the IR (zero checked-add guard goals)
##   guard probe:      undeclared targets run the declaration-free guard-
##                      obligation attempt (no certificate): discharged /
##                      declined+sat (replay-confirmed, overflow class) /
##                      zero-goals reason (suite 6, axiom_guard_probe)
##   impl identity:    (suite 7, axiom_impl_probe) the DEBT#510 addressing
##                      contract: a bare last segment shared by two or more
##                      decls is the explicit Ambiguous refusal (exit 3,
##                      every owner-qualified candidate named); the exact
##                      structured name binds ONE decl whose own honest
##                      reason flows through (impl method: out-of-subset
##                      regions; the m1 add_u8: the undeclared guard attempt,
##                      unconfirmed)
##   charon absent:    "pinned charon extraction unavailable (crNotFound): ..."
##   unresolved target: "[AXIOM] --target <t> resolved to no extraction targets
##                      (NotFound or Ambiguous) ... Refusing an implicit
##                      verification run on an unresolved target." (exit 3,
##                      CliError INVALID_INPUT — the engine's channel)
##
## EXIT-RULE DERIVATION (suite 5): the lane's exit is the single existing rule
## (axProofShortcutExitCode → decision_algebra.projectRunOutcome →
## cli_outcome.runExitCode). The charon-absent report is unknown-only with
## failedCount==0 ∧ timeoutCount==0 ∧ verified==0 → OutcomeContinue
## ("§7 requires a failed or timed-out node to make verified==0 a failure")
## → CliOutcome.SUCCESS → exit 0. The fail-closed property asserted there is
## therefore the ABSENCE of a verified claim — every declared target unknown
## with the crNotFound reason, zero certificates, no "verified" anywhere —
## not a nonzero exit code. Suite 1's base-run exit follows the SAME RULE
## through the mutant's confirmation shape: a CONFIRMED kernel decline
## (status "failed" → failedCount ≥ 1 → VERIFICATION_FAILURE → exit 1).
## Since the seal's predicate-v2 restoration (2026-11-03 — `worktreeStable`,
## docs/spec/replay_evidence_policy.md §4) the CONFIRMED shape no longer
## depends on the enclosing worktree's PRE-EXISTING state: dirt that was
## there before the run (a stale build stamp, untracked files) sits on BOTH
## sides of the seal's relative pre/post comparison and can never break it,
## so the CONFIRMED shape is asserted UNCONDITIONALLY and a deliberate
## pre-existing-noise case (fresh untracked file around a full lane run)
## asserts it under noise. The seal's negative control is no longer
## "dirty vs clean" but RUN-MADE drift: tests/gateway/rust_drift_probe_test.nim
## (subjects that write files DURING the replay land rvUnavailable). The
## guard-probe scenario (suite 6) stays exit 0 either way: every target is
## unknown (discharged attempts are non-claiming, undeclared),
## failedCount==0 ∧ verified==0 → CONTINUE.
##
## Environment gates (explicit skip — echo SKIP + quit(0), repo pattern):
##   - bin/ax absent after ensureAxBinary (the suite NEVER builds ax);
##   - `gh` absent or `gh auth token` fails (without GITHUB_TOKEN the positive
##     path cannot mint — provenance fails closed — so the whole file skips
##     honestly);
##   - the pinned charon binary absent (AXIOM_CHARON_BIN env override honored;
##     resolution order: env > the historical /tmp probe path > PATH lookup
##     of `charon` — the pinned identity is re-verified by the lane's own
##     identity gate either way): the extraction-dependent suites skip; the
##     charon-absent fail-closed suite still runs (it needs no charon —
##     absence is its subject).

import std/[algorithm, json, os, osproc, streams, strutils, unittest]
import checksums/sha2

const
  ProjectArg = "tests/fixtures/rust/axiom_rust_probe"
  ProjectArgGuard = "tests/fixtures/rust/axiom_guard_probe"
  AxBinaryEnv = "AXIOM_START_GATE_AX_BIN"
  CharonBinEnv = "AXIOM_CHARON_BIN"
  ## The HISTORICAL probe path — kept first in the resolution order for
  ## environments that install the pinned charon there; when absent the
  ## suite falls back to the PATH lookup of `charon` (the pin itself is
  ## re-verified by the lane's identity gate, so only the pinned binary
  ## ever passes).
  DefaultPinnedCharon = "/tmp/charon-probe/charon/target/release/charon"
  ## The pinned identity the runner's gate enforces (extraction_provenance
  ## pin SSOT: PinnedCharonVersion + PinnedCharonPinCommit).
  PinnedCharonIdentity = "0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)"
  ## Lane vocabulary, verbatim from src/cli/rust_lane_cli.nim.
  KernelConfirmedPrefix = "spec declined by kernel; counterexample CONFIRMED"
  OutOfSubsetPrefix = "out-of-subset grammar (fail-closed): "
  CharonUnavailablePrefix = "pinned charon extraction unavailable ("
  LaneDoneLine = "[AXIOM][rust-lane] done: verified=1/3 failed=1 unknown=1 error=0"
  ## Guard-probe vocabulary — the declaration-free attempt reasons
  ## (rust_rust_pipeline contract; deterministic, no raw model values).
  GuardDischargedPrefix = "guard obligation discharged (proved: '"
  GuardDeclinedPrefix = "guard goal '"
  GuardZeroGoals = "no derivable guard obligation (attempt ran; zero mechanical goals)"

proc repoRoot(): string =
  ## tests/gateway/<file> -> project root (location-based — the pattern of
  ## rust_subject_three_cases_test.nim).
  absolutePath("../..", currentSourcePath().parentDir)

proc ensureAxBinary(repo: string): string =
  let envBin = getEnv(AxBinaryEnv)
  if envBin.len > 0 and fileExists(envBin):
    return envBin
  let binAx = repo / "bin" / "ax"
  if fileExists(binAx):
    return binAx
  echo "SKIP: no ax binary (" & AxBinaryEnv & " unset and " & binAx &
       " absent) — the suite never builds ax; skipping the whole file " &
       "(explicit skip, not a failure)"
  quit(0)

proc sha256Hex(s: string): string =
  var h = initSha_256()
  h.update(s)
  $h.digest()

# ── File-level environment gates ────────────────────────────────────────────
# Declared before the run helpers (runLane arms GITHUB_TOKEN from GhToken).

let Repo = repoRoot()
let AxBin = ensureAxBinary(Repo) # quits(0) with SKIP when absent — never builds

proc githubTokenViaGh(): string =
  ## The native credential client is the ONLY discovery path (§2.4): `gh auth
  ## token`. No filesystem/env/keyring scanning — failure means skip, never a
  ## substitute source.
  if findExe("gh").len == 0:
    return ""
  let (outp, code) = execCmdEx("gh auth token")
  if code != 0:
    return ""
  outp.strip()

let GhToken = githubTokenViaGh()
if GhToken.len == 0:
  echo "SKIP: gh absent or 'gh auth token' failed — without GITHUB_TOKEN the " &
       "positive path cannot mint (provenance fails closed), so the " &
       "product-CLI acceptance suite skips the whole file (explicit skip, " &
       "not a failure)"
  quit(0)

## The mutant's replay-CONFIRMED kernel decline runs the counterexample
## replay against the fixture INSIDE this Axiom worktree. Under the seal's
## predicate v2 (rust_replay_adapter.confirmRustPostRunIntegrity,
## `worktreeStable`) the Zero-Footprint gate compares the worktree
## RELATIVELY pre/post — subject inputs + repo status (-uall) + tracked
## content — so PRE-EXISTING drift of the enclosing repo (this workstream's
## own uncommitted changes, untracked files, a stale build stamp) is on
## both sides of the comparison and can never fail-close the observation;
## the CONFIRMED shape (status "failed", exit 1) holds in a dirty checkout
## exactly as in a clean one. Only drift the RUN itself made seals
## fail-closed — that negative control is the standalone drift probe
## (tests/gateway/rust_drift_probe_test.nim), and the deliberate-noise
## case below pins CONFIRMED under fresh pre-existing untracked noise.

proc gitQuery(root: string; args: string): string =
  let (outp, code) = execCmdEx("git -C \"" & root & "\" " & args)
  if code == 0: outp.strip() else: ""

proc materializeTrackedCrate(fixtureDir, dirName: string): string =
  ## The lane's input contract collects the subject `.rs` set through the D1
  ## collector (git ls-files primary — run_context.nim) and fails closed on
  ## an LLBC↔source file-set mismatch. An UNTRACKED fixture (this branch's
  ## new fixtures before their commits land) yields an empty ls-files set
  ## and the equivalence refuses — so the fixture's REAL crate content is
  ## copied UNCHANGED into a throwaway git repo (never written in place,
  ## never bound to the Axiom repo's own git identity): Cargo.toml/
  ## Cargo.lock plus every `.rs` directly under src/. A tracked fixture
  ## (CI after landing) uses the in-repo path directly.
  let root = getTempDir() / dirName
  removeDir(root)
  createDir(root / "src")
  copyFile(fixtureDir / "Cargo.toml", root / "Cargo.toml")
  if fileExists(fixtureDir / "Cargo.lock"):
    copyFile(fixtureDir / "Cargo.lock", root / "Cargo.lock")
  for kind, path in walkDir(fixtureDir / "src"):
    if kind == pcFile and path.endsWith(".rs"):
      copyFile(path, root / "src" / extractFilename(path))
  discard execCmdEx("git -C \"" & root & "\" init -q")
  discard execCmdEx("git -C \"" & root & "\" add -A")
  discard execCmdEx("git -C \"" & root &
    "\" -c user.name=ax -c user.email=ax@test commit -q -m init")
  root

proc materializeGuardSubject(dirName: string): string =
  materializeTrackedCrate(
    Repo / "tests" / "fixtures" / "rust" / "axiom_guard_probe", dirName)

## The guard-probe project root the lane runs against: the committed
## in-repo fixture when git tracks it (the mission's --project argument),
## else the materialized tracked crate (measured, not assumed).
let GuardFixtureTracked = gitQuery(
  Repo / "tests" / "fixtures" / "rust" / "axiom_guard_probe",
  "ls-files -- src/lib.rs").len > 0
let GuardProject = (if GuardFixtureTracked: ProjectArgGuard
                    else: materializeGuardSubject(
                      "ax_rust_lane_guard_subject"))
if not GuardFixtureTracked:
  echo "NOTE: the guard fixture is not git-tracked in this worktree — the " &
       "guard-probe scenario runs against a materialized tracked crate " &
       "(the in-repo path is used once the fixture commit lands)"

## The impl-identity project root the lane runs against: the same
## tracked-vs-materialized rule, measured the same way (git ls-files).
let ImplFixtureTracked = gitQuery(
  Repo / "tests" / "fixtures" / "rust" / "axiom_impl_probe",
  "ls-files -- src/lib.rs").len > 0
const ProjectArgImpl = "tests/fixtures/rust/axiom_impl_probe"
let ImplProject = (if ImplFixtureTracked: ProjectArgImpl
                   else: materializeTrackedCrate(
                     Repo / "tests" / "fixtures" / "rust" / "axiom_impl_probe",
                     "ax_rust_lane_impl_subject"))
if not ImplFixtureTracked:
  echo "NOTE: the impl fixture is not git-tracked in this worktree — the " &
       "impl-identity scenario runs against a materialized tracked crate " &
       "(the in-repo path is used once the fixture commit lands)"

proc resolveCharonBin(): string =
  ## AXIOM_CHARON_BIN env > the historical /tmp probe path > the PATH lookup
  ## of `charon` (resolved to its absolute path so the spawned `ax` sees the
  ## same binary this gate checked). The pinned-identity gate inside the lane
  ## re-verifies whichever binary this resolves to — an unpinned PATH charon
  ## fails closed there, never silently passes.
  let e = getEnv(CharonBinEnv)
  if e.len > 0:
    return e
  if fileExists(DefaultPinnedCharon):
    return DefaultPinnedCharon
  let onPath = findExe("charon")
  if onPath.len > 0:
    return onPath
  DefaultPinnedCharon # absent — the skip gate below reports this path verbatim

let CharonBin = resolveCharonBin()
let extractionReady = (if CharonBin.contains('/'): fileExists(CharonBin)
                       else: findExe(CharonBin).len > 0)
if not extractionReady:
  echo "SKIP: pinned charon binary not present ('" & CharonBin & "') — " &
       "extraction-dependent suites (positive/out-of-scope/unresolved/ASI/" &
       "guard-probe) are skipped; the charon-absent fail-closed suite still " &
       "runs (explicit skip, not a failure)"

type
  LaneRun = object
    exitCode: int
    stdOut: string
    stdErr: string
    stateDir: string
    vaultDir: string
    report: JsonNode ## the trajectory skReport entry's extra (the report document)

proc runCli(binary: string; args: seq[string]; cwd: string):
    tuple[exitCode: int, stdOut, stdErr: string] =
  ## Separate stdout/stderr capture (unlike the merged productization helper):
  ## this suite asserts the report JSON is NOT on stdout while the lane's log
  ## lines land on stderr. Both streams are bounded here (measured: stdout 0
  ## bytes, stderr ~4 KB incl. ledger INFO lines), far under the 64 KB pipe
  ## buffer, so sequential draining cannot deadlock.
  let p = startProcess(binary, workingDir = cwd, args = args,
                       options = {poUsePath})
  close(p.inputStream())
  let outStr = p.outputStream().readAll()
  let errStr = p.errorStream().readAll()
  result.exitCode = p.waitForExit()
  result.stdOut = outStr
  result.stdErr = errStr

var laneEnvCounter = 0

type LaneEnv = object
  stateDir: string
  vaultDir: string

proc freshLaneEnv(repo: string): LaneEnv =
  ## Fresh per-run state root carrying the repo's scope lock (the lane
  ## resolves it from $AXIOM_STATE_DIR/data — the --project discipline) plus
  ## a fresh isolated certificate vault (DECISION-0622 write side).
  inc laneEnvCounter
  let tag = $getCurrentProcessId() & "_" & $laneEnvCounter
  result.stateDir = getTempDir() / "axrustlane_state_" & tag
  result.vaultDir = getTempDir() / "axrustlane_vault_" & tag
  removeDir(result.stateDir)
  removeDir(result.vaultDir)
  createDir(result.stateDir / "data")
  copyFile(repo / "data" / "verification_scope.lock",
           result.stateDir / "data" / "verification_scope.lock")
  createDir(result.vaultDir)

proc laneReport(stateDir: string): JsonNode =
  ## The lane's per-run durable observable: the trajectory SSOT entry
  ## (detail "rust subject lane completed", extra = the full report document).
  ## $AXIOM_STATE_DIR/logs/ax_proof_state.json is NOT part of the lane path —
  ## verified live, the trajectory file is the one that exists after a run.
  ## NIL is the honest "no report document" answer: a target-RESOLUTION
  ## refusal returns err before finish(), so no trajectory is written at all.
  let trajPath = stateDir / "logs" / "ax_prove_trajectory.jsonl"
  if not fileExists(trajPath):
    return nil
  var last: JsonNode = nil
  for line in readFile(trajPath).splitLines():
    if line.strip().len == 0:
      continue
    let entry = parseJson(line)
    if entry{"detail"}.getStr() == "rust subject lane completed":
      last = entry{"extra"}
  doAssert not last.isNil,
    "no 'rust subject lane completed' entry in " & trajPath
  last

proc runLane(repo, binary: string; extraEnv: seq[(string, string)] = @[];
             extraArgs: seq[string] = @[]; charonBin: string = CharonBin;
             project: string = ProjectArg): LaneRun =
  ## One real `ax prove --project <project>` run against a fresh state root +
  ## fresh vault, with the pinned charon and the armed ledger transport.
  let env = freshLaneEnv(repo)
  putEnv("AXIOM_STATE_DIR", env.stateDir)
  putEnv("AXIOM_PROVE_VAULT_DIR", env.vaultDir)
  putEnv(CharonBinEnv, charonBin)
  putEnv("GITHUB_TOKEN", GhToken)
  delEnv("AXIOM_REQUIRE_PERFECT_ASI") # the lever is opt-in per scenario
  for (k, v) in extraEnv:
    putEnv(k, v)
  let cli = runCli(binary, @["prove", "--project", project] & extraArgs, repo)
  for (k, _) in extraEnv:
    delEnv(k)
  LaneRun(exitCode: cli.exitCode, stdOut: cli.stdOut, stdErr: cli.stdErr,
          stateDir: env.stateDir, vaultDir: env.vaultDir,
          report: laneReport(env.stateDir))

proc vaultCertSetDigest(vaultDir: string): string =
  ## Digest over the sorted (fileName, replay-projection digest) list of the
  ## vault's TOP-LEVEL *.json certificates. The replay projection is the §6
  ## discipline (productization_start_vertical_slice_feature_test.nim):
  ## canonical JSON over the cert MINUS the fields that bind it to its run's
  ## LOCAL TrustCommit journal commit — by design these advance per append,
  ## so raw bytes differ across runs while the verification identity does
  ## not. Exclusion list derived from a 3-run field diff (see the module
  ## header), not assumed:
  ##   attestation.journalRef, attestation.signature (signs the journalRef),
  ##   canonicalKaa (embeds the run's executionIdentity),
  ##   evidenceId, executionContractDigest, identityDigest, kaaDigest,
  ##   provenance (certificateDigest + journalCommitId), trustCommitId.
  ## The vault's data/trusted/journal subtree is not certs and is excluded.
  const RunBoundCertKeys = [
    "canonicalKaa", "evidenceId", "executionContractDigest", "identityDigest",
    "kaaDigest", "provenance", "trustCommitId"]

  proc replayProjection(n: JsonNode): string =
    var doc = copy(n)
    var att = newJObject()
    if not n{"attestation"}.isNil:
      for k, v in n{"attestation"}.pairs:
        if k notin ["journalRef", "signature"]:
          att{k} = copy(v)
    doc{"attestation"} = att
    for k in RunBoundCertKeys:
      doc.delete(k)

    # canonical JSON: recursively sorted object keys
    proc canon(n: JsonNode): string =
      case n.kind
      of JObject:
        result = "{"
        var keys: seq[string] = @[]
        for k in n.keys:
          keys.add(k)
        keys.sort()
        for i, k in keys:
          if i > 0: result.add(",")
          result.add(escapeJson(k) & ":")
          result.add(canon(n{k}))
        result.add("}")
      of JArray:
        result = "["
        for i, e in n.elems:
          if i > 0: result.add(",")
          result.add(canon(e))
        result.add("]")
      of JString: result.add(escapeJson(n.getStr()))
      of JInt: result.add($n.getInt())
      of JFloat: result.add($n.getFloat())
      of JBool: result.add($n.getBool())
      else: result.add("null")
    result = canon(doc)

  var pairs: seq[string] = @[]
  if dirExists(vaultDir):
    for kind, path in walkDir(vaultDir):
      if kind == pcFile and path.endsWith(".json"):
        pairs.add(splitFile(path).name & "=" &
          sha256Hex(replayProjection(parseFile(path))))
  pairs.sort()
  var h = initSha_256()
  for p in pairs:
    h.update(sha256Hex(p))
  sha256Hex($h.digest())

proc vaultCertCount(vaultDir: string): int =
  if dirExists(vaultDir):
    for kind, path in walkDir(vaultDir):
      if kind == pcFile and path.endsWith(".json"):
        inc result

proc targetEntry(report: JsonNode; suffix: string): JsonNode =
  ## Entry lookup by the target's last "::" segment — the producer's match
  ## key; report names are the full "::"-joined LLBC declaration path
  ## ("axiom_rust_probe::add_u8"). endsWith("::add_u8") cannot collide with
  ## "::add_u8_mutant".
  for t in report{"targets"}.elems:
    if t{"name"}.getStr().endsWith("::" & suffix):
      return t
  nil

# ── Suite 1: positive — add_u8 verified, cert minted, N=3 determinism ──────

suite "rust lane product-CLI — positive: add_u8 verified, cert minted (N=3 determinism)":
  if extractionReady:
    let r1 = runLane(Repo, AxBin)
    let r2 = runLane(Repo, AxBin)
    let r3 = runLane(Repo, AxBin)

    test "full run ×3: exit 1 (the mutant's kernel decline CONFIRMS — " &
        "predicate v2 seals only run-made drift, so pre-existing worktree " &
        "state never demotes the observation); the report JSON is NOT on stdout":
      for r in @[r1, r2, r3]:
        check r.exitCode == 1
        check r.stdOut.len == 0 # plain prove prints nothing to stdout (measured)
        check r.stdErr.contains("[AXIOM][rust-lane] charon pinned='" &
          PinnedCharonIdentity & "'")

    test "vault cert-set digest identical across N=3; exactly one cert per run":
      ## The digest is the canonical REPLAY projection (journal-chain binding
      ## fields excluded — see vaultCertSetDigest and the module header): raw
      ## cert bytes bind the run's local TrustCommit journal commit and are
      ## NOT byte-identical across runs.
      let d1 = vaultCertSetDigest(r1.vaultDir)
      check vaultCertSetDigest(r2.vaultDir) == d1
      check vaultCertSetDigest(r3.vaultDir) == d1
      check vaultCertCount(r1.vaultDir) == 1
      check vaultCertCount(r2.vaultDir) == 1
      check vaultCertCount(r3.vaultDir) == 1
      # the extraction identity (irHash-keyed filename) is identical across runs
      let names1: seq[string] =
        block:
          var n: seq[string] = @[]
          for kind, path in walkDir(r1.vaultDir):
            if kind == pcFile and path.endsWith(".json"):
              n.add(splitFile(path).name)
          n.sort()
          n
      for r in @[r2, r3]:
        var n: seq[string] = @[]
        for kind, path in walkDir(r.vaultDir):
          if kind == pcFile and path.endsWith(".json"):
            n.add(splitFile(path).name)
        n.sort()
        check n == names1

    test "minted cert: axiom.certificate.v3 with non-empty identity/evidence digests":
      let entry = targetEntry(r1.report, "add_u8")
      check not entry.isNil
      check entry{"status"}.getStr() == "verified"
      let certPath = entry{"certPath"}.getStr()
      check certPath.len > 0
      check fileExists(certPath)
      let cert = parseFile(certPath)
      check cert{"schemaVersion"}.getStr() == "axiom.certificate.v3"
      check cert{"identityDigest"}.getStr().len == 64
      check cert{"evidenceId"}.getStr().len == 64
      check cert{"kaaDigest"}.getStr().len == 64
      # content-addressed binding: the vault filename IS the entry's irHash
      check splitFile(certPath).name == entry{"irHash"}.getStr()

    test "trajectory report: add_u8 verified; mutant CONFIRMED kernel decline " &
        "(failed); is_zero in-subset zero-goal guard — distinct verbatim reasons; summary 1/3":
      let rep = r1.report
      check not rep.isNil
      check rep{"schemaVersion"}.getStr() == "axiom.report.v1"
      check rep{"subjectLane"}.getStr() == "rust"
      check rep{"charon"}{"ok"}.getBool() == true
      check rep{"charon"}{"pinned"}.getStr() == PinnedCharonIdentity

      let add = targetEntry(rep, "add_u8")
      check not add.isNil
      check add{"name"}.getStr() == "axiom_rust_probe::add_u8"
      check add{"status"}.getStr() == "verified"
      check add{"reason"}.getStr() == ""
      check add{"irHash"}.getStr().len == 64

      let mutant = targetEntry(rep, "add_u8_mutant")
      check not mutant.isNil
      check mutant{"name"}.getStr() == "axiom_rust_probe::add_u8_mutant"
      # The falsified spec is declined by the kernel and z3's refuting
      # candidate is replayed on the real toolchain → status "failed".
      # Predicate v2 (2026-11-03): the seal compares the worktree
      # RELATIVELY pre/post, so pre-existing dirt (this workstream's own
      # uncommitted changes, untracked files) cannot demote the
      # observation — only run-made drift can (the drift probe's subject).
      check mutant{"blockStage"}.getStr() == "kernel"
      check mutant{"status"}.getStr() == "failed"
      check mutant{"reason"}.getStr().startsWith(KernelConfirmedPrefix)
      check mutant{"reason"}.getStr().contains("counterexample CONFIRMED")

      let oos = targetEntry(rep, "is_zero")
      check not oos.isNil
      check oos{"status"}.getStr() == "unknown"
      # v1.3 boolean Switch collapse: is_zero is now IN-subset (and(eq,eq));
      # undeclared → the declaration-free guard attempt runs and finds zero
      # mechanical goals (no checked arithmetic) — honest, non-claiming.
      check oos{"reason"}.getStr() == GuardZeroGoals

      check rep{"summary"}{"verified"}.getInt() == 1
      check rep{"summary"}{"timeoutCount"}.getInt() == 0
      check rep{"summary"}{"statusCounts"}{"verified"}.getInt() == 1
      check rep{"summary"}{"statusCounts"}{"error"}.getInt() == 0
      check rep{"summary"}{"failedCount"}.getInt() >= 1
      check rep{"summary"}{"statusCounts"}{"failed"}.getInt() == 1
      check rep{"summary"}{"statusCounts"}{"unknown"}.getInt() == 1
      check r1.stdErr.contains(LaneDoneLine)
      check r1.stdErr.contains("[AXIOM][rust-lane] verified: axiom_rust_probe::add_u8 → ")

    test "lane re-extracts every run into the state workDir (the committed " &
        "fixture LLBC is never consumed)":
      # workDir = <state>/.axiom/rust-lane/sha256(absolute projectAbs)[0:16]
      # (§10 identity discipline: the engine absolutizes --project
      # unconditionally — the CWD-relative spelling is convenience, never
      # identity; a relative spelling must not key the lane workDir).
      let laneDirHash = sha256Hex(absolutePath(Repo / ProjectArg))[0 ..< 16]
      for r in @[r1, r2, r3]:
        check fileExists(r.stateDir / ".axiom" / "rust-lane" / laneDirHash /
                         "subject.llbc")

    test "deliberate PRE-EXISTING worktree noise does not seal — a fresh " &
        "untracked file around a full run still CONFIRMS the mutant " &
        "(predicate v2: noise on both sides of the relative comparison)":
      # The restoration's acceptance witness, mirroring the very scenario of
      # docs/spec/build_metadata_stamp_porcelain_quirk.md (there: the build
      # stamp; here: a throwaway untracked file created BEFORE the run and
      # removed after). The noise is present on both sides of the seal's
      # pre/post comparison, so the mutant's kernel decline must still land
      # CONFIRMED (status "failed", exit 1) — the honest unconfirmed shape
      # is reachable only through run-made drift (the drift probe).
      let noisePath = Repo / "_untracked_noise_drift_probe.txt"
      writeFile(noisePath,
        "pre-existing noise — must never seal a CONFIRMED counterexample\n")
      var r: LaneRun
      try:
        r = runLane(Repo, AxBin)
      finally:
        removeFile(noisePath)
      check r.exitCode == 1
      let rep = r.report
      check not rep.isNil
      let mutant = targetEntry(rep, "add_u8_mutant")
      check not mutant.isNil
      check mutant{"status"}.getStr() == "failed"
      check mutant{"reason"}.getStr().startsWith(KernelConfirmedPrefix)
      check mutant{"reason"}.getStr().contains("counterexample CONFIRMED")
      check rep{"summary"}{"failedCount"}.getInt() >= 1

# ── Suite 2: out-of-scope — --target is_zero ───────────────────────────────

suite "rust lane product-CLI — out-of-scope: --target is_zero":
  if extractionReady:
    let r = runLane(Repo, AxBin, extraArgs = @["--target", "is_zero"])

    test "exit 0; zero certificates minted":
      check r.exitCode == 0
      check r.stdOut.len == 0
      check vaultCertCount(r.vaultDir) == 0

    test "trajectory report: exactly the is_zero target, in-subset unknown " &
        "with the zero-goal guard reason":
      let rep = r.report
      check not rep.isNil
      check rep{"targets"}.elems.len == 1
      let entry = targetEntry(rep, "is_zero")
      check not entry.isNil
      check entry{"status"}.getStr() == "unknown"
      check entry{"reason"}.getStr() == GuardZeroGoals
      check rep{"summary"}{"verified"}.getInt() == 0
      check rep{"summary"}{"statusCounts"}{"unknown"}.getInt() == 1

# ── Suite 3: unresolved target — canonicalTargetRefusal ────────────────────

suite "rust lane product-CLI — unresolved target: --target nosuch":
  if extractionReady:
    let r = runLane(Repo, AxBin, extraArgs = @["--target", "nosuch"])

    test "exit 3 (CliError INVALID_INPUT) with the canonical refusal on stderr; " &
        "no report document is produced at all":
      check r.exitCode == 3
      check r.stdOut.len == 0
      check r.stdErr.contains("--target nosuch resolved to no extraction " &
        "targets (NotFound or Ambiguous)")
      check r.stdErr.contains(
        "Refusing an implicit verification run on an unresolved target.")
      # target-RESOLUTION failures never produce a report: the lane returns
      # err before finish(), so not even a trajectory entry exists.
      check r.report.isNil

# ── Suite 4: perfect-ASI lever ──────────────────────────────────────────────

suite "rust lane product-CLI — perfect-ASI lever (AXIOM_REQUIRE_PERFECT_ASI=1)":
  if extractionReady:
    let r = runLane(Repo, AxBin,
      extraEnv = @[("AXIOM_REQUIRE_PERFECT_ASI", "1")])

    test "exit 1 — the lever flips only the exit projection, not the verdicts":
      # The verification itself is unchanged (add_u8 still verifies, the
      # mutant is still the confirmed failed target), so the report still
      # says verified=1; the lever keeps the exit at VERIFICATION_FAILURE(1)
      # via axProofShortcutExitCode's requirePerfectAsi branch (the base run
      # is already exit 1 through the failedCount rule — see suite 1).
      check r.exitCode == 1
      check r.stdOut.len == 0
      check not r.report.isNil
      check r.report{"summary"}{"verified"}.getInt() == 1

# ── Suite 5: charon absent — fail-closed ────────────────────────────────────
#
# Runs WITHOUT the extractionReady gate: absence is the subject. The pinned
# charon is overridden with a nonexistent path; the identity gate refuses
# before cargo (crNotFound) and EVERY declared target lands on the runner's
# verbatim reason.

suite "rust lane product-CLI — charon absent: fail-closed extraction":
  let r = runLane(Repo, AxBin, charonBin = "/nonexistent-charon")

  test "exit 0 is RULE-DERIVED (unknown-only = no-obligation CONTINUE run); " &
      "zero certificates; no verified claim anywhere":
    # exit 0 derivation (see the module header): the lane's exit is the single
    # rule axProofShortcutExitCode → decision_algebra.projectRunOutcome →
    # cli_outcome.runExitCode. The unknown-only report has failedCount==0 ∧
    # timeoutCount==0 ∧ verified==0 → OutcomeContinue → SUCCESS → 0 ("§7
    # requires a failed or timed-out node to make verified==0 a failure").
    # Fail-closed here means: NO verified claim, NO certificate.
    check r.exitCode == 0
    check r.stdOut.len == 0
    check vaultCertCount(r.vaultDir) == 0

  test "every declared target unknown with the runner's crNotFound reason; " &
      "charon.ok=false in the report":
    let rep = r.report
    check not rep.isNil
    check rep{"charon"}{"ok"}.getBool() == false
    check rep{"charon"}{"reason"}.getStr().contains(
      "charon not found (pinned charon required): '/nonexistent-charon'")
    let add = targetEntry(rep, "add_u8")
    let mutant = targetEntry(rep, "add_u8_mutant")
    check not add.isNil
    check not mutant.isNil
    for entry in @[add, mutant]:
      check entry{"status"}.getStr() == "unknown"
      check entry{"reason"}.getStr().startsWith(CharonUnavailablePrefix)
      check entry{"reason"}.getStr().contains("crNotFound")
    check rep{"summary"}{"verified"}.getInt() == 0
    for t in rep{"targets"}.elems:
      check t{"status"}.getStr() != "verified"

# ── Suite 6: declaration-free guard obligations — axiom_guard_probe ─────────
#
# The guard-probe crate carries NO spec sidecar and NONE of its symbols are
# declared in the scope lock's rust_targets (which lists only
# axiom_rust_probe) — every target runs the DECLARATION-FREE guard-obligation
# attempt, and nothing may claim:
#   offset — one guard goal (a+b<256): kernel-declined, z3 confirms a
#            refuting candidate; counterexample confirmed by replay under
#            the recorded overflow-checking profile (overflow-checks=on,
#            debug-assertions=on; extraction witness AddChecked;
#            overflow-class observation, out-of-subset per §3 —
#            profile-bound, not language semantics). The panic
#            classification runs before the replay's worktree-stability
#            check, so a dirty (but stable) enclosing worktree still
#            confirms — the CONFIRMED class is asserted unconditionally.
#   bump0  — one guard goal (a+0<256): DISCHARGED by the kernel (receipt,
#            sorry-free); non-claiming — no certificate (undeclared)
#   echo   — no arithmetic → zero mechanical goals (the attempt still ran)
#   tri    — bool Switch collapsed to ite → zero mechanical goals (the
#            is_zero shape, now in-subset)
# The run is unknown-only with failedCount==0 ∧ verified==0 → CONTINUE →
# exit 0, zero certificates, and the four reason strings are deterministic
# by contract (N=3 equality below).
#
# Project resolution (measured, not assumed): the committed in-repo fixture
# when git tracks it (the --project argument of record), else — before the
# fixture commit lands in a worktree — a materialized tracked crate copy
# (the input contract's D1 subject collector is git-ls-files based; an
# untracked fixture fail-closes the LLBC↔source equivalence by design).

suite "rust lane product-CLI — guard probe: declaration-free attempts (N=3 determinism)":
  if extractionReady:
    let g1 = runLane(Repo, AxBin, project = GuardProject)
    let g2 = runLane(Repo, AxBin, project = GuardProject)
    let g3 = runLane(Repo, AxBin, project = GuardProject)

    test "×3 runs: exit 0 everywhere (unknown-only = CONTINUE); stdout " &
        "empty; the pinned-charon log line":
      for r in @[g1, g2, g3]:
        check r.exitCode == 0
        check r.stdOut.len == 0
        check r.stdErr.contains("[AXIOM][rust-lane] charon pinned='" &
          PinnedCharonIdentity & "'")
        check r.stdErr.contains(
          "[AXIOM][rust-lane] done: verified=0/4 failed=0 unknown=4 error=0")

    test "trajectory report: 4 targets, ALL unknown, the four expected " &
        "reason classes (offset declined+sat, replay-CONFIRMED; bump0 " &
        "discharged; echo zero-goals; tri zero-goals)":
      let rep = g1.report
      check not rep.isNil
      check rep{"schemaVersion"}.getStr() == "axiom.report.v1"
      check rep{"subjectLane"}.getStr() == "rust"
      check rep{"charon"}{"ok"}.getBool() == true
      check rep{"charon"}{"pinned"}.getStr() == PinnedCharonIdentity
      check rep{"targets"}.elems.len == 4

      let offset = targetEntry(rep, "offset")
      check not offset.isNil
      check offset{"name"}.getStr() == "axiom_guard_probe::offset"
      check offset{"status"}.getStr() == "unknown"
      let offReason = offset{"reason"}.getStr()
      check offReason.contains("guard attempt: 1 goal(s)")
      check offReason.contains("guard goal '")
      check offReason.contains("declined by kernel")
      check offReason.contains("VIOLATED")
      check offReason.contains("counterexample confirmed by replay")
      check offReason.contains("model script digest")
      check offReason.contains("not a declared-spec failure")
      # No raw model values, no panic text, no fallback wording: the
      # confirmed class retires the unconfirmed text entirely (the panic
      # observation is log-only; the record schema is unchanged).
      check not offReason.contains("define-fun")
      check not offReason.contains("attempt to add with overflow")
      check not offReason.contains("confirmation unavailable")
      check not offReason.contains("Z3 confirms a refuting candidate exists")

      let bump = targetEntry(rep, "bump0")
      check not bump.isNil
      check bump{"name"}.getStr() == "axiom_guard_probe::bump0"
      check bump{"status"}.getStr() == "unknown"
      let bumpReason = bump{"reason"}.getStr()
      check bumpReason.contains("guard attempt: 1 goal(s)")
      check bumpReason.contains("guard obligation discharged (proved: '")
      check bumpReason.contains("kernel receipt, sorry-free")
      check bumpReason.contains("non-claiming — no certificate (undeclared)")

      let echoEntry = targetEntry(rep, "echo")
      check not echoEntry.isNil
      check echoEntry{"name"}.getStr() == "axiom_guard_probe::echo"
      check echoEntry{"status"}.getStr() == "unknown"
      check echoEntry{"reason"}.getStr() == GuardZeroGoals

      let tri = targetEntry(rep, "tri")
      check not tri.isNil
      check tri{"name"}.getStr() == "axiom_guard_probe::tri"
      check tri{"status"}.getStr() == "unknown"
      # v1.3 boolean Switch collapse: `if a == b { a } else { b }` is now
      # in-subset (ite); the guard attempt runs and finds zero checked-add
      # goals.
      check tri{"reason"}.getStr() == GuardZeroGoals

      check rep{"summary"}{"verified"}.getInt() == 0
      check rep{"summary"}{"failedCount"}.getInt() == 0
      check rep{"summary"}{"timeoutCount"}.getInt() == 0
      check rep{"summary"}{"statusCounts"}{"verified"}.getInt() == 0
      check rep{"summary"}{"statusCounts"}{"failed"}.getInt() == 0
      check rep{"summary"}{"statusCounts"}{"unknown"}.getInt() == 4
      check rep{"summary"}{"statusCounts"}{"error"}.getInt() == 0

    test "NO certificate in the fresh vault — a discharged guard is " &
        "non-claiming (undeclared), nothing mints":
      for r in @[g1, g2, g3]:
        check vaultCertCount(r.vaultDir) == 0

    test "N=3 determinism: identical {name,status} sets, identical reason " &
        "strings (deterministic by contract), identical summary":
      proc runProjection(r: LaneRun): string =
        ## The deterministic lane projection: the sorted
        ## name|status|reason triples + the summary document.
        var triples: seq[string] = @[]
        for t in r.report{"targets"}.elems:
          triples.add(t{"name"}.getStr() & "|" & t{"status"}.getStr() & "|" &
            t{"reason"}.getStr())
        triples.sort()
        triples.join("\n") & "\n--\n" & $r.report{"summary"}
      check runProjection(g2) == runProjection(g1)
      check runProjection(g3) == runProjection(g1)

# ── Suite 7: impl-method identity — axiom_impl_probe (DEBT#510 closure) ──────
#
# The impl-identity fixture pins the DEBT#510 addressing contract on the real
# product CLI: a bare last segment that TWO OR MORE decls share is an explicit
# Ambiguous INVALID_INPUT refusal naming every owner-qualified candidate
# (never a silent first document-order match), and the exact structured name
# binds exactly one decl whose OWN honest reason flows into the report:
#   speak / add_u8 (bare)  → exit 3, the Ambiguous refusal on stderr, NO
#                            report document (a resolution refusal never
#                            reaches finish() — measured: no trajectory file)
#   m1::Dog::speak (exact) → exit 0, ONE unknown target whose name IS the
#                            requested structured full name; the honest
#                            out-of-subset reason (an &self method's
#                            anonymous region generic fails the monomorphic
#                            gate before param decoding names the Ref type)
#   m2::Cat::speak (exact) → the same shape on m2 — the selection is
#                            identity-driven, not first-match (Dog and Cat
#                            are distinct decls with distinct modules)
#   m1::add_u8 (exact)     → exit 0, ONE unknown target on the declaration-
#                            free guard-attempt path (kernel-declined + Z3
#                            SAT, unconfirmed — the replay binds only
#                            src/lib.rs and add_u8 lives in m1, so the
#                            harness cannot splice it; the honest
#                            overflow-discretion fallback text stays
#                            verbatim, and the reason is deterministic
#                            across runs: every embedded digest is
#                            input-derived, never a raw model value)

suite "rust lane product-CLI — impl identity: DEBT#510 ambiguity + structured names (axiom_impl_probe)":
  if extractionReady:
    let bareSpeak = runLane(Repo, AxBin, project = ImplProject,
                            extraArgs = @["--target", "speak"])
    let bareAdd = runLane(Repo, AxBin, project = ImplProject,
                          extraArgs = @["--target", "add_u8"])
    let dogSpeak = runLane(Repo, AxBin, project = ImplProject,
                           extraArgs = @["--target",
                             "axiom_impl_probe::m1::Dog::speak"])
    let catSpeak = runLane(Repo, AxBin, project = ImplProject,
                           extraArgs = @["--target",
                             "axiom_impl_probe::m2::Cat::speak"])
    let m1AddA = runLane(Repo, AxBin, project = ImplProject,
                         extraArgs = @["--target",
                           "axiom_impl_probe::m1::add_u8"])
    let m1AddB = runLane(Repo, AxBin, project = ImplProject,
                         extraArgs = @["--target",
                           "axiom_impl_probe::m1::add_u8"])

    test "(A) bare 'speak' → exit 3 INVALID_INPUT; the Ambiguous refusal " &
        "names BOTH owner-qualified fullNames on stderr; no report document":
      check bareSpeak.exitCode == 3
      check bareSpeak.stdOut.len == 0
      check bareSpeak.stdErr.contains("--target speak resolved to more than " &
        "one extraction target (Ambiguous): axiom_impl_probe::m1::Dog::speak, " &
        "axiom_impl_probe::m2::Cat::speak. The rust lane requires exactly one " &
        "match.")
      # A resolution refusal returns before finish(): no trajectory entry,
      # hence no report document at all.
      check bareSpeak.report.isNil

    test "(D) bare 'add_u8' → exit 3 Ambiguous across the m1/m2 pair " &
        "(the DEBT#510 same-last-segment pair, both candidates named)":
      check bareAdd.exitCode == 3
      check bareAdd.stdOut.len == 0
      check bareAdd.stdErr.contains("--target add_u8 resolved to more than " &
        "one extraction target (Ambiguous): axiom_impl_probe::m1::add_u8, " &
        "axiom_impl_probe::m2::add_u8. The rust lane requires exactly one " &
        "match.")
      check bareAdd.report.isNil

    test "(B) exact 'axiom_impl_probe::m1::Dog::speak' → exit 0; ONE unknown " &
        "target whose NAME is the structured full name (the impl method is " &
        "ADDRESSABLE); honest out-of-subset reason (region generic); zero " &
        "certificates":
      check dogSpeak.exitCode == 0
      check dogSpeak.stdOut.len == 0
      check vaultCertCount(dogSpeak.vaultDir) == 0
      let rep = dogSpeak.report
      check not rep.isNil
      check rep{"targets"}.elems.len == 1
      let entry = rep{"targets"}.elems[0]
      check entry{"name"}.getStr() == "axiom_impl_probe::m1::Dog::speak"
      check entry{"status"}.getStr() == "unknown"
      let reason = entry{"reason"}.getStr()
      check reason.startsWith(OutOfSubsetPrefix)
      check reason.contains("generic parameter 'regions'")
      check rep{"summary"}{"verified"}.getInt() == 0
      check rep{"summary"}{"statusCounts"}{"unknown"}.getInt() == 1

    test "(C) exact 'axiom_impl_probe::m2::Cat::speak' → the SAME shape on " &
        "m2 — the selection is identity-driven (Dog and Cat are DISTINCT " &
        "decls, not a first document-order match)":
      check catSpeak.exitCode == 0
      check catSpeak.stdOut.len == 0
      check vaultCertCount(catSpeak.vaultDir) == 0
      let rep = catSpeak.report
      check not rep.isNil
      check rep{"targets"}.elems.len == 1
      let entry = rep{"targets"}.elems[0]
      check entry{"name"}.getStr() == "axiom_impl_probe::m2::Cat::speak"
      check entry{"status"}.getStr() == "unknown"
      let reason = entry{"reason"}.getStr()
      check reason.startsWith(OutOfSubsetPrefix)
      check reason.contains("generic parameter 'regions'")
      check rep{"summary"}{"statusCounts"}{"unknown"}.getInt() == 1

    test "(E) exact 'axiom_impl_probe::m1::add_u8' → exit 0; the undeclared " &
        "guard-attempt reason (kernel-declined + Z3 SAT, UNCONFIRMED — the " &
        "replay binds only src/lib.rs; add_u8 lives in m1); deterministic " &
        "reason across runs":
      for r in @[m1AddA, m1AddB]:
        check r.exitCode == 0
        check r.stdOut.len == 0
        check vaultCertCount(r.vaultDir) == 0
        let rep = r.report
        check not rep.isNil
        check rep{"targets"}.elems.len == 1
        let entry = rep{"targets"}.elems[0]
        check entry{"name"}.getStr() == "axiom_impl_probe::m1::add_u8"
        check entry{"status"}.getStr() == "unknown"
        let reason = entry{"reason"}.getStr()
        check reason.startsWith("guard attempt: 1 goal(s); guard goal '")
        check reason.contains("declined by kernel")
        check reason.contains("Z3 confirms a refuting candidate exists")
        check reason.contains("counterexample confirmation unavailable " &
          "(overflow-discretion class, out-of-subset per §3)")
        check rep{"summary"}{"statusCounts"}{"unknown"}.getInt() == 1
      check m1AddB.report{"targets"}.elems[0]{"reason"}.getStr() ==
        m1AddA.report{"targets"}.elems[0]{"reason"}.getStr()

# ─── Suite 8: u64 boundary types (axiom_u64_probe, ③ u64-scalar-2026-11-02) ──

## The u64 project root: the same tracked-vs-materialized rule, measured the
## same way (git ls-files). Pre-landing (untracked fixture) the lane runs
## against a materialized throwaway git crate; post-landing (CI) the in-repo
## tracked path is used.
let U64FixtureTracked = gitQuery(
  Repo / "tests" / "fixtures" / "rust" / "axiom_u64_probe",
  "ls-files -- src/lib.rs").len > 0
const ProjectArgU64 = "tests/fixtures/rust/axiom_u64_probe"
let U64Project = (if U64FixtureTracked: ProjectArgU64
                  else: materializeTrackedCrate(
                    Repo / "tests" / "fixtures" / "rust" / "axiom_u64_probe",
                    "ax_rust_lane_u64_subject"))
if not U64FixtureTracked:
  echo "NOTE: the u64 fixture is not git-tracked in this worktree — the " &
       "u64-boundary scenario runs against a materialized tracked crate " &
       "(the in-repo path is used once the fixture commit lands)"

suite "rust lane product-CLI — u64 boundary: echo verified, mutant " &
    "kernel-decline, add verified (axiom_u64_probe, v1.2 wall retired)":
  if extractionReady:
    let echoRun = runLane(Repo, AxBin, project = U64Project,
                          extraArgs = @["--target",
                            "axiom_u64_probe::u64_echo"])
    let mutantRun = runLane(Repo, AxBin, project = U64Project,
                            extraArgs = @["--target",
                              "axiom_u64_probe::u64_seven_mutant"])
    let addRun = runLane(Repo, AxBin, project = U64Project,
                         extraArgs = @["--target",
                           "axiom_u64_probe::u64_add"])
    let sevenRun = runLane(Repo, AxBin, project = U64Project,
                           extraArgs = @["--target",
                             "axiom_u64_probe::u64_seven"])

    test "(A) u64_echo (declared) → exit 0; verified with ONE certificate; " &
        "the cert filename IS the entry's irHash (content-addressed)":
      check echoRun.exitCode == 0
      check echoRun.stdOut.len == 0
      check vaultCertCount(echoRun.vaultDir) == 1
      let rep = echoRun.report
      check not rep.isNil
      check rep{"targets"}.elems.len == 1
      let entry = rep{"targets"}.elems[0]
      check entry{"name"}.getStr() == "axiom_u64_probe::u64_echo"
      check entry{"status"}.getStr() == "verified"
      check entry{"reason"}.getStr() == ""
      check entry{"irHash"}.getStr().len == 64
      let certPath = entry{"certPath"}.getStr()
      check certPath.len > 0
      check fileExists(certPath)
      check splitFile(certPath).name == entry{"irHash"}.getStr()
      check rep{"summary"}{"verified"}.getInt() == 1
      check rep{"summary"}{"statusCounts"}{"verified"}.getInt() == 1

    test "(B) u64_seven_mutant (declared) → kernel decline CONFIRMED — the " &
        "refuting model replays on the real toolchain (failed, exit 1) in " &
        "a materialized crate AND in a dirty tracked checkout (predicate " &
        "v2 seals only run-made drift). Zero certificates either way":
      let rep = mutantRun.report
      check not rep.isNil
      check rep{"targets"}.elems.len == 1
      let entry = rep{"targets"}.elems[0]
      check entry{"name"}.getStr() == "axiom_u64_probe::u64_seven_mutant"
      check entry{"blockStage"}.getStr() == "kernel"
      # Predicate v2 (2026-11-03): the pre/post worktree comparison is
      # relative, so BOTH subject bindings confirm — the materialized
      # throwaway crate (its own git repo) and the tracked in-repo fixture
      # under an enclosing dirty worktree (pre-existing dirt sits on both
      # sides of the comparison). Run-made drift stays the drift probe's
      # subject.
      check mutantRun.exitCode == 1
      check entry{"status"}.getStr() == "failed"
      check entry{"reason"}.getStr().startsWith(KernelConfirmedPrefix)
      check entry{"reason"}.getStr().contains("counterexample CONFIRMED")
      check rep{"summary"}{"failedCount"}.getInt() == 1
      check rep{"summary"}{"statusCounts"}{"failed"}.getInt() == 1
      check vaultCertCount(mutantRun.vaultDir) == 0
      check mutantRun.stdOut.len == 0

    test "(C) u64_add (declared, v1.2) → exit 0; verified with ONE " &
        "certificate — full-width '+' discharges via the closed-form " &
        "obligation `a + b ≤ 2^64−1` (the wall is retired; the retired " &
        "reason survives only as the greppable named constant)":
      check addRun.exitCode == 0
      check addRun.stdOut.len == 0
      check vaultCertCount(addRun.vaultDir) == 1
      let rep = addRun.report
      check not rep.isNil
      check rep{"targets"}.elems.len == 1
      let entry = rep{"targets"}.elems[0]
      check entry{"name"}.getStr() == "axiom_u64_probe::u64_add"
      check entry{"status"}.getStr() == "verified"
      check entry{"reason"}.getStr() == ""
      check entry{"irHash"}.getStr().len == 64
      let certPath = entry{"certPath"}.getStr()
      check certPath.len > 0
      check fileExists(certPath)
      check splitFile(certPath).name == entry{"irHash"}.getStr()
      check rep{"summary"}{"verified"}.getInt() == 1
      check rep{"summary"}{"statusCounts"}{"verified"}.getInt() == 1

    test "(D) u64_seven (undeclared, spec exists but not declared) → " &
        "exit 0; the declaration-free guard attempt with ZERO mechanical " &
        "goals (the constant body has no guard obligation); no certificate":
      check sevenRun.exitCode == 0
      check sevenRun.stdOut.len == 0
      check vaultCertCount(sevenRun.vaultDir) == 0
      let rep = sevenRun.report
      check not rep.isNil
      check rep{"targets"}.elems.len == 1
      let entry = rep{"targets"}.elems[0]
      check entry{"name"}.getStr() == "axiom_u64_probe::u64_seven"
      check entry{"status"}.getStr() == "unknown"
      check entry{"reason"}.getStr() == GuardZeroGoals
      check rep{"summary"}{"statusCounts"}{"unknown"}.getInt() == 1
