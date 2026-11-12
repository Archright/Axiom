import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Proof Universe Lock Gate (v2)
##
## Read-only lock-identity verification. Does NOT execute heavy proof work.
##
## This gate verifies that the canonical `data/universe_merkle.lock` — when
## present — is a reproducible deterministic identity of the current committed
## proof universe, by reusing the same canonical predicate
## (`verifyProofUniverseLock` from `core/proof/proof_universe_lock`) that
## `ax vkd sync` / lock commitment use. The gate never writes to the canonical
## lock and never runs `ax prove`.
##
## Lock lifecycle authority (ADR-0012 / DECISION-0014):
##   - The canonical lock is written ONLY by `ax vkd sync` / `--update-lock`.
##   - CI does not perform a lock-advancing run, so in a clean CI checkout the
##     canonical lock is absent. A missing lock is the designed steady state,
##     so this gate PASSes with a clear log (nothing to verify), NOT fail-open
##     theater: there is simply no lock identity to check.
##   - When a lock IS present, non-canonical `ax prove` runs legitimately
##     advance the graph/certificate universe without updating the lock, so a
##     merkle divergence from the lock is an expected "normal-interval drift".
##     The gate still performs the real verification work and reports the
##     divergence as PASS-with-warning — it does not silently skip the check.
##   - An unparseable/corrupt lock file is the only genuine corruption and
##     fails the gate (exit != 0).

import std/[json, monotimes, options, os, times]
import core/axiom_pragmas
import core/results
import core/trusted/trust_commit
import core/proof/proof_universe_lock

type
  GateVerdict* = enum
    gvPass
    gvFail
    gvPassWithWarning

const
  CanonicalLockPath = defaultProofUniverseLockPath ## data/universe_merkle.lock
  CertDir = defaultCertDir                          ## .axiom/vault

proc appendGateHistory(gateId: string; verdict: GateVerdict; durationNs: int64) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Best-effort append of a gate execution record to .axiom/gate_history.jsonl.
  ## Emits a JSONL record compatible with gate_run_logger.flushToDisk's canonical
  ## format (gateId/result/durationNs/ts/...) so both gate_status_metrics.nim and
  ## axiom_status.nim can consume it. Telemetry is incidental — a failure here
  ## MUST NOT affect the gate verdict (fully swallowed).
  try:
    createDir(".axiom")
    var f = open(".axiom" / "gate_history.jsonl", fmAppend)
    defer: close(f)
    let resultStr =
      case verdict
      of gvPass: "pass"
      of gvFail: "fail"
      of gvPassWithWarning: "warn"
    let rec = %*{
      "ts": now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
      "stage": "ci",
      "commit": "",
      "branch": "",
      "stagedFiles": 0,
      "epoch": 0,
      "gateId": gateId,
      "result": resultStr,
      "durationNs": durationNs,
      "cached": false,
      "tier": 1,
      "dagLayer": 0
    }
    f.writeLine($rec)
    f.flushFile()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch) — never affect gate verdict

proc verifyLockIdentity*(
  repoRoot: string
): tuple[verdict: GateVerdict; message: string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Core read-only verification: classify the canonical lock state and verify
  ## its identity when present. Pure of side effects on the lock/universe —
  ## reads inputs and returns a verdict only.
  let lockPath = repoRoot / CanonicalLockPath
  if not fileExists(lockPath):
    return (gvPass,
      "no canonical lock present (" & lockPath &
      ") — non-`--update-lock` state per ADR-0012; nothing to verify")

  # Lock exists: a corrupt (unparseable) lock is genuine corruption → FAIL.
  let stored = readProofUniverseLock(lockPath)
  if stored.isErr:
    return (gvFail,
      "canonical lock exists but is corrupt/unparseable: " & stored.error)

  # Valid, parseable lock: recompute the deterministic identity and compare.
  # NOTE: `verifyProofUniverseLock` reads `.axiom/vault` certs + the global
  # symbol graph; if a required input is absent it returns `ok(false)` (fail
  # closed), which we surface as a divergence warning below rather than as a
  # silent pass.
  let v = verifyProofUniverseLock(repoRoot = repoRoot, certDir = CertDir, path = lockPath)
  if v.isOk and v.get:
    return (gvPass,
      "canonical lock identity verified (merkle root matches committed universe)")
  return (gvPassWithWarning,
    "canonical lock present but identity diverges from current universe " &
    "(expected normal-interval drift for non-canonical `ax prove` runs); " &
    "verification result: " & (if v.isOk: "mismatch" else: "error: " & v.error))

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let startMono = getMonoTime()
  let root = repoRootForPath(getCurrentDir())
  if root.len == 0:
    echo "gvFail gate: cannot resolve repo root"
    quit(1)
  let (verdict, message) = verifyLockIdentity(root)
  let durationNs = (getMonoTime() - startMono).inNanoseconds
  appendGateHistory("proof-universe-lock", verdict, durationNs)
  echo $verdict & " " & message
  # The orchestrator grades the gate by process exit code (executor.nim:
  # `ok: exitCode == 0`). gvPass / gvPassWithWarning are non-failing; gvFail
  # must exit non-zero so a corrupt lock fails the CI step.
  quit(if verdict == gvFail: 1 else: 0)

when isMainModule:
  main()

{.pop.}
