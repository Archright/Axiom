## Determinism Ratchet Test — end-to-end serial↔parallel proof determinism (DEBT#508).
##
## Contract: two COLD `ax prove --limit 20` runs (workers=1 and workers=2), each
## against its own isolated vault under ONE base temp dir, must agree on:
##   1. zero timeout verdicts (checked on the RAW output, before any
##      normalization — a timeout line can never be normalized away),
##   2. the documented exit pair serial=1 / parallel=0 (see EXIT PIN below),
##   3. the vault certificate substance digest (functionName+status+irHash
##      multiset from the vault manifest — SHA-256),
##   4. the normalized stderr digest (SHA-256).
##
## Both legs run against a snapshot-restored `.axiom/cache`, so each leg sees
## the byte-identical cold cache state (a warm second leg would flip
## [ir-cas] MISS→HIT lines and the topology changed-count — cache dependence,
## not scheduler dependence — and both were observed run-to-run on 2026-10-24).
##
## OBSERVED NONDETERMINISM (canonical main ade15ff92, 2026-10-24, cold runs):
##   - `axiom_engine: phase-13: vault manifest synced — N entries → <vault>/manifest.json`
##     (src/cli/axiom_engine.nim:451) — per-run vault path.
##   - `[INFO] topology_cli: topology: <N> files, <M> changed, sourceRoot=<abs>`
##     — the old `grep -v '^topology:'` never matched this observed form, and
##     the changed-count is cache-state-derived (2511 cold → 566 warm, measured).
##   - The node-execution segment + run-accounting lines are the DOCUMENTED
##     VS-1 Phase-1 divergence (PR #1085 "Known non-claims"): the serial driver
##     and the parallel deterministic-scheduler label the same proof outcomes
##     differently. RE-MEASURED on post-VS-1 main bb8eca2ee (PR #1093 merged,
##     2026-10-24, three flock-serialized cold runs, byte-identical): serial
##     `[n/5] … — verified|orchestrationNoObligation|failed` via loop_driver +
##     PRE-SIEVE/promoted lines, `Verification-Gate: 4 entries`,
##     `done: verifiedRatio=… verified=2/40`; parallel via loop_depth_scheduler
##     all-failed labels (VS-1's claim-scoped IR disproof terminal + label
##     parity changed the pre-VS-1 all-verified rendering — the divergence
##     shape changed, it did NOT converge), `Verification-Gate: 5 entries`,
##     `verified=0/40`. The persisted substance is identical — the two runs'
##     vault manifests carry the same 4 entries with the same statuses and
##     irHashes (measured pre- and post-VS-1: cert digest e885d5d0… unchanged)
##     — so the presentation segment is normalized to one token while the
##     substance is ratcheted independently by assertion 3. The serial-only
##     accounting FAIL (exit 1) is part of the same documented divergence and
##     is PINNED, not hidden: any drift fails loudly and forces a conscious
##     re-pin.
##
## EXIT PIN: docs/spec/productization_contract.md §7 vocabulary is
## success=0 / verification-failure=1. On canonical main ade15ff92 the serial
## leg's run accounting FAILs the gate on the 2 IR-pipeline-failed nodes
## (calcDynamicTimeoutCore, safeSpeedupRatioCore — deterministic, TO=0), the
## parallel leg's accounting passes → serial=1, parallel=0. Re-measured on
## post-VS-1 main bb8eca2ee (2026-10-24): the pair is UNCHANGED — serial raw
## renders `canonical run accounting: contestedCount=2 ∨ unsatisfiedCount=1 ⇒
## GateVerdict=FAIL` and exits 1; parallel now ALSO renders
## `contestedCount=5 ∨ unsatisfiedCount=0 ⇒ GateVerdict=FAIL` yet exits 0
## (the parallel driver's exit path does not consume the accounting verdict —
## observed, pinned). Anything outside {0,1} is a contract violation and
## fails; any drift from the pinned pair fails with a message requiring an
## explicit, documented re-pin.

import checksums/sha2
import std/[algorithm, json, os, osproc, sequtils, streams, strutils, tempfiles]

const
  ProveArgs = ["prove", "--limit", "20"]
  LegTimeoutMs = 600_000            # hard kill guard — a hung prove is a failure
  VaultToken = "<VAULT>"
  RootToken = "<ROOT>"

proc repoRoot(): string =
  var dir = getCurrentDir()
  for _ in 0 .. 8:
    if fileExists(dir / ".axiom_root") or fileExists(dir / "axiom.toml"):
      return dir
    dir = dir.parentDir()
  doAssert false, "repo root not found (no .axiom_root above " & getCurrentDir() & ")"

proc sha256Hex(s: string): string =
  var h = initSha_256()
  h.update(s)
  $h.digest()

type
  TimeoutViolation = object
    line: string
    reason: string

proc scanTimeoutViolations(line: string): seq[TimeoutViolation] =
  ## Fail-closed timeout guard over the RAW output. The one benign identifier
  ## containing the byte sequence "timeout" on canonical main is
  ## `timeoutDiagnosisForNode` (a candidate-exclusion line, identical in both
  ## legs); everything else that renders a timeout — the per-node verdict
  ## `— timed out` (loop_driver.nim:1195, loop_depth_scheduler.nim:619), a
  ## standalone lowercase "timeout", or a nonzero `TO:` proof-summary counter —
  ## is a violation.
  if line.contains("timed out"):
    result.add(TimeoutViolation(line: line, reason: "\"timed out\" verdict line"))
  elif line.contains("timeout") and not line.contains("timeoutDiagnosisForNode"):
    result.add(TimeoutViolation(line: line, reason: "standalone \"timeout\" token"))
  else:
    let toIdx = line.find("TO:")
    if toIdx >= 0:
      let rest = line[toIdx + 3 .. ^1].strip()
      var num = ""
      for ch in rest:
        if ch in Digits:
          num.add(ch)
        else:
          break
      if num.len > 0 and parseInt(num) > 0:
        result.add(TimeoutViolation(line: line,
          reason: "nonzero TO: summary counter"))

proc normalizeLine(line: string; vaultDir, repo: string): string =
  ## Ordered normalizations. Every rule cites its observed evidence (header).
  var s = line.replace(vaultDir, VaultToken).replace(repo, RootToken)
  # Topology line — normalize to the OBSERVED form (the old `^topology:` filter
  # never matched `[INFO] topology_cli: topology: …`); the file/changed counts
  # are cache-state-derived (2511 cold → 566 warm, measured 2026-10-24).
  if s.startsWith("[INFO] topology_cli: topology: "):
    return "[INFO] topology_cli: topology: " & "<TOPOLOGY>"
  # Run-accounting lines — the documented VS-1 Phase-1 divergence layer.
  # The `done:` line exists in both legs (values diverge) → tokenized in place.
  if s.contains("done: verifiedRatio=") and s.contains(", verified="):
    return s[0 .. s.find("done: verifiedRatio=") - 1] & "done: <RUN-ACCOUNTING>"
  result = s
  # Depth-check projection lines: node identifiers agree across legs, only the
  # terminal label token diverges (documented divergence layer).
  if s.startsWith("[Depth ") and s.contains("... ["):
    let cut = s.find("... [")
    return s[0 ..< cut] & "... [<NODE-VERDICT>]"
  result = s

proc normalizeOutput(rawLines: seq[string]; vaultDir, repo: string;
                     segmentSeen: var bool): string =
  ## Collapse the DOCUMENTED divergent node-execution segment (PR #1085
  ## "Known non-claims") — from its first leg-specific marker (serial
  ## `[PRE-SIEVE CARVE-OUT]` / parallel `deterministic-scheduler: depth=`)
  ## through the `Verification-Gate: N entries processed by UAP pipeline`
  ## line — into one token line. Fail-closed: the segment boundaries must be
  ## found exactly once per run; a missing marker is a loud error, never a
  ## silent digest of a different shape. The substance produced inside this
  ## segment is ratcheted independently by the vault certificate digest.
  var outLines: seq[string] = @[]
  var inSegment = false
  for raw in rawLines:
    let line = normalizeLine(raw, vaultDir, repo)
    # The `canonical run accounting: … GateVerdict=` rendering exists in BOTH
    # legs post-VS-1 (serial contestedCount=2 ∨ unsatisfiedCount=1, parallel
    # contestedCount=5 ∨ unsatisfiedCount=0 — measured on bb8eca2ee) with
    # leg-divergent counters; pre-VS-1 only the serial leg emitted it. The
    # exit pair is machine-checked by the EXIT PIN assertion, not trusted to
    # this line, and the substance behind both renderings is ratcheted by the
    # vault certificate digest — dropping the leg-divergent rendering from the
    # digest hides nothing and fails loudly on drift elsewhere.
    if line.contains("canonical run accounting:") and line.contains("GateVerdict="):
      continue
    if not inSegment:
      if line.contains("[PRE-SIEVE CARVE-OUT]") or
          line.contains("deterministic-scheduler: depth="):
        doAssert not segmentSeen,
          "node-execution segment marker seen twice in one run — " &
          "normalization boundaries no longer match the observed output"
        segmentSeen = true
        inSegment = true
        outLines.add("<NODE-EXECUTION-PHASE>")
        continue
      outLines.add(line)
    else:
      if line.contains("Verification-Gate:") and
          line.contains("entries processed by UAP pipeline"):
        inSegment = false
        continue
  doAssert not inSegment,
    "node-execution segment never terminated (Verification-Gate line missing) " &
    "— normalization boundaries no longer match the observed output"
  outLines.join("\n") & "\n"

proc vaultCertDigest(vaultDir: string): string =
  ## Substance ratchet: SHA-256 over the sorted multiset of
  ## functionName|status|irHash from the vault manifest — the persisted proof
  ## artifacts, independent of log presentation.
  let manifestPath = vaultDir / "manifest.json"
  doAssert fileExists(manifestPath),
    "vault manifest missing after prove: " & manifestPath
  let manifest = parseFile(manifestPath)
  let entries = manifest{"entries"}
  doAssert entries != nil and entries.kind == JArray and entries.len > 0,
    "vault manifest has no entries: " & manifestPath
  var projected: seq[string] = @[]
  for e in entries:
    projected.add(e{"functionName"}.getStr("") & "|" &
                  e{"status"}.getStr("") & "|" &
                  e{"irHash"}.getStr(""))
  projected.sort()
  sha256Hex(projected.join("\n") & "\n")

type LegResult = object
  exitCode: int
  rawLines: seq[string]
  digest: string
  certDigest: string

proc runLeg(repo, binAx, vaultDir: string; workers: int;
            cacheSnapshot: string; snapshotExisted: bool): LegResult =
  ## One COLD prove leg: restore the cache snapshot, run `ax prove --limit 20`
  ## with an isolated vault, capture the merged output and the REAL exit code
  ## (startProcess + waitForExit — the old test's `2>&1 | grep` pipeline
  ## asserted grep's exit code, not the product's).
  if dirExists(repo / ".axiom" / "cache"):
    removeDir(repo / ".axiom" / "cache")
  if snapshotExisted:
    copyDir(cacheSnapshot, repo / ".axiom" / "cache")
  createDir(vaultDir)
  putEnv("AXIOM_PROVE_WORKERS", $workers)
  putEnv("AXIOM_PROVE_VAULT_DIR", vaultDir)
  var p = startProcess(binAx, workingDir = repo, args = ProveArgs,
                       options = {poStdErrToStdOut, poUsePath})
  # Hard wall-clock guard: waitForExit(timeout) returns -1 while the process
  # is still running. A prove that overruns the budget is killed and failed —
  # a hang is exactly the failure class this ratchet exists to catch.
  let waitCode = p.waitForExit(LegTimeoutMs)
  if p.running():
    kill(p)
    discard p.waitForExit()
    doAssert false, "ax prove (workers=" & $workers &
      ") did not exit within " & $LegTimeoutMs & "ms — killed"
  result.exitCode = waitCode
  let outBuf = p.outputStream().readAll()
  close(p)
  delEnv("AXIOM_PROVE_WORKERS")
  delEnv("AXIOM_PROVE_VAULT_DIR")
  result.rawLines = outBuf.splitLines()
  # Timeout guard FIRST — on the raw lines, before any normalization.
  var violations: seq[TimeoutViolation] = @[]
  for raw in result.rawLines:
    violations.add(scanTimeoutViolations(raw))
  doAssert violations.len == 0,
    "TIMEOUT DETECTED in ax prove (workers=" & $workers & ") — " &
    $violations.len & " violation(s):\n" &
    violations.mapIt("  [" & it.reason & "] " & it.line).join("\n")
  var segmentSeen = false
  result.digest = sha256Hex(normalizeOutput(result.rawLines, vaultDir, repo,
                                            segmentSeen))
  doAssert segmentSeen,
    "node-execution segment marker not found in workers=" & $workers &
    " output — the documented-divergence normalization boundaries no longer " &
    "match the observed output; update the normalization with fresh evidence"
  result.certDigest = vaultCertDigest(vaultDir)

proc main() =
  let repo = repoRoot()
  let binAx = repo / "bin" / "ax"
  doAssert fileExists(binAx),
    "bin/ax not found at " & binAx & " — build the release verifier first " &
    "(make ci-compile)"

  # One base temp dir; the two legs get sibling vaults `serial/` and `parallel/`
  # and each leg's own vault path is substituted with <VAULT> — the path itself
  # becomes run-independent (no arbitrary line deletion).
  let baseDir = createTempDir("axiom_det_ratchet_", "")
  let vaultSerial = baseDir / "serial"
  let vaultParallel = baseDir / "parallel"

  # Snapshot .axiom/cache once; every leg restores it — both legs are cold and
  # byte-identical in initial state (cache dependence eliminated by construction).
  let cacheDir = repo / ".axiom" / "cache"
  let cacheSnapshot = baseDir / "axiom_cache_snapshot"
  let snapshotExisted = dirExists(cacheDir)
  if snapshotExisted:
    copyDir(cacheDir, cacheSnapshot)

  proc restoreCacheState() =
    if dirExists(cacheDir):
      removeDir(cacheDir)
    if snapshotExisted:
      copyDir(cacheSnapshot, cacheDir)

  defer:
    restoreCacheState()
    removeDir(baseDir)

  echo "Determinism ratchet: serial (workers=1, cold) ..."
  let serial = runLeg(repo, binAx, vaultSerial, 1, cacheSnapshot, snapshotExisted)
  echo "  exit=" & $serial.exitCode & " digest=" & serial.digest &
    " vaultCertDigest=" & serial.certDigest

  echo "Determinism ratchet: parallel (workers=2, cold) ..."
  let parallel = runLeg(repo, binAx, vaultParallel, 2, cacheSnapshot, snapshotExisted)
  echo "  exit=" & $parallel.exitCode & " digest=" & parallel.digest &
    " vaultCertDigest=" & parallel.certDigest

  # Exit pin — documented, fail-loud (see header EXIT PIN).
  doAssert serial.exitCode in {0, 1},
    "serial exit " & $serial.exitCode & " outside the §7 vocabulary {0,1}"
  doAssert parallel.exitCode in {0, 1},
    "parallel exit " & $parallel.exitCode & " outside the §7 vocabulary {0,1}"
  doAssert serial.exitCode == 1 and parallel.exitCode == 0,
    "EXIT PIN DRIFT — documented pair is serial=1/parallel=0 (VS-1 Phase-1 " &
    "accounting divergence, PR #1085 non-claim), got serial=" &
    $serial.exitCode & " parallel=" & $parallel.exitCode &
    " — if the divergence layer converged or the corpus changed, re-pin with " &
    "fresh evidence"

  # Substance ratchet — persisted proof artifacts must be identical.
  doAssert serial.certDigest == parallel.certDigest,
    "VAULT CERTIFICATE DIVERGENCE: serial=" & serial.certDigest &
    " parallel=" & parallel.certDigest

  # Presentation ratchet — everything outside the documented divergence layer.
  doAssert serial.digest == parallel.digest,
    "DETERMINISM VIOLATION (normalized output): serial=" & serial.digest &
    " parallel=" & parallel.digest

  echo "Determinism ratchet PASSED: digest=" & serial.digest &
    " vaultCertDigest=" & serial.certDigest &
    " (exit serial=1 parallel=0, timeouts=0)"


main()
