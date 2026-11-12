import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## trust_commit_scope_gate.nim — Trust Commit Scope Gate (I7)
##
## Authority-based, sink-centric, TARGET-based scan for raw persistence
## effects whose write TARGET is an authoritative trust representation
## (data/trusted/journal) outside the TrustCommit closure. Derived
## certificate / cache / transient / sandbox targets are out of the I7
## universe; closure routing is import-aware (an unqualified allowlisted call
## in a file that imports the provider module is routed — DEBT#471).
##
## Scan-scope resolution lives in the scanner module
## (trust_commit_scope_scan.resolveScanScope) as the single SSOT: the runner
## scans that scope and the memo key layer binds the same scope plus the
## staged-index axis into the cache key (judgmentClosureDigest), so a verdict
## can never be replayed across different judgment inputs (DEBT#471: the
## staged=0 full-src / staged=1 partial scope asymmetry).
##
## Fail-closed on actual findings. Fail-open only when infrastructure
## is absent (no repo root, no staged files, no scan directory).
##
## See: Plan v13-Absolute, docs/agents/rules_workflow.md §2.13

import gate/gate_contract
import gate/gate_types
import gate/utils/gate_safety_macro
import gate/utils/macro_dispatcher
import core/gate/trust_commit_scope_scan
import std/[os, strutils]

# ─── Scan Directory Resolution ──────────────────────────────────────────

proc resolveScanDir*(ctx: InProcessGateContext): string =
  ## Thin adapter over the scanner-module SSOT (DEBT#471). The scope policy —
  ## the common ancestor directory of the staged files (capped at the I7
  ## universe <repoRoot>/src when the span reaches repo-root level), the full
  ## src tree when the staged set is empty, "" when infrastructure is absent —
  ## lives in trust_commit_scope_scan.resolveScanScope so the memo key layer
  ## binds the SAME scope the runner scans.
  resolveScanScope(ctx.repoRoot, ctx.stagedFiles)

# ─── Gate Runner ────────────────────────────────────────────────────────

proc run*(gate: GateConfig, ctx: InProcessGateContext): GateResult =
  ## Scan the resolved scope for raw persistence effects whose write TARGET is
  ## an authoritative trust representation not routed through the TrustCommit
  ## closure. Routing is import-aware: allowlisted qualified symbols, or
  ## unqualified allowlisted leaf calls in files that import the provider
  ## module, are inside the closure. Flagged targets must route through
  ## append_store, claim_store_append, trust_commit.commitVerification,
  ## io_utils, stdlib_shield, posix, or writeGlobalSymbolGraphSnapshot.

  let scanDir = resolveScanDir(ctx)
  if scanDir.len == 0:
    return GateResult(
      ok: true, name: "trust-commit-scope",
      stdout: "No scan directory resolved (no repo/staged files). Infrastructure absent — fail-open.",
      skipCiRequested: false)

  let scanResult = scanForDirectWrites(scanDir)
  if not scanResult.ok:
    return GateResult(
      ok: false, name: "trust-commit-scope",
      stdout: "trust-commit-scope: scan failed — " & scanResult.err,
      skipCiRequested: false)

  let findings = scanResult.value
  if findings.len == 0:
    return GateResult(
      ok: true, name: "trust-commit-scope",
      stdout: "No direct durable evidence writes found in " & scanDir,
      skipCiRequested: false)

  # Fail-closed: direct cert writes must route through the trust-commit allowlist.
  # "FAIL" marker line: the orchestrator's classifyFailure extracts reason lines
  # by the "FAIL" substring — without it the memo layer records this verdict as
  # moNotEvaluated (no reason evidence) and a FAIL would never replay as
  # FAIL_CACHED (DEBT#471 verdict-axis durability).
  var output = "FAIL trust-commit-scope: " & $findings.len & " direct-write(s) found (must route through trust-commit allowlist):\n"
  for f in findings:
    output &= "  " & f.file & ":" & $f.line & " — " & f.call & "\n"

  GateResult(
    ok: false, name: "trust-commit-scope",
    stdout: output,
    failureCategory: fcValidation,
    failureReason: $findings.len & " direct durable evidence write(s) found outside the trust-commit allowlist",
    skipCiRequested: false)

# ─── Compile-Time Registration ─────────────────────────────────────────
# Register this gate in the compile-time macro dispatch table.
# Duplicate gateId will cause a compile-time build failure (error() in registerGate).
registerGate("trust-commit-scope", run)

# ─── In-Process Dispatch Adapter ────────────────────────────────────────

proc runInProcess*(ctx: InProcessGateContext): GateResult {.gcsafe, raises: [].} =
  ## InProcessGateProc-shaped adapter over run(). The in-process dispatch path
  ## executes the SAME judgment logic as the runner entry — one verdict SSOT,
  ## no duplicated scan semantics (DEBT#471). A standalone AOT link of this
  ## module has no main (compile-time-only registerGate), so the allowlisted
  ## in-process path is the enforcement path for this gate.
  try:
    result = run(GateConfig(), ctx)
  except CatchableError as e:
    result = GateResult(
      ok: false, name: "trust-commit-scope",
      stdout: "FAIL trust-commit-scope: in-process execution failed — " & e.msg,
      failureCategory: fcValidation,
      failureReason: "in-process execution error: " & e.msg,
      skipCiRequested: false)

{.pop.}
