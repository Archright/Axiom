## all_gate_runners.nim — Compile-time gate registration hub
##
## All gates from manifest.d registered in the compile-time
## macro dispatch table. Legacy gates use registerLegacyCliGate
## (subprocess delegation via runSingleGateImpl); native
## InProcessGateContext gates register themselves via registerGate.
##
## See: docs/agents/architecture.md, Plan v13-Absolute

import core/trusted/layer_declaration
axiomLayer "gate"
import gate/utils/macro_dispatcher
import gate/gate_contract          # GateConfig, GateResult
import gate/utils/gate_safety_macro  # InProcessGateContext
import gate/orchestrator_hook  # runSingleGateImpl (via executor re-export)
import gate/runners/trust_commit_scope_gate as trustCommitScopeGate  # native InProcessGateContext handler

import std/macros
import std/json
import std/os
import std/strutils
import std/sets

# ── Subprocess bridge for legacy CLI gates ────────────────────────────────────

proc runLegacyGateSubprocess*(gate: GateConfig, ctx: InProcessGateContext): GateResult {.raises: [CatchableError].} =
  ## Bridges InProcessGateContext → existing subprocess dispatch.
  ## Delegates to runSingleGateImpl which handles CAS compilation,
  ## args template substitution, and startProcess execution.
  let stage = GateStage(ctx.stage)
  let mode = if stage == gsPreCommit: grmIncremental else: grmExhaustive
  runSingleGateImpl(gate, ctx.repoRoot, ctx.stagedFiles, stage, mode, ctx.maxJobs, ctx.effectiveTimeoutMs)

# ── Native InProcessGateContext gates ─────────────────────────────────────────
# Native gates register themselves via registerGate in their own modules;
# importing them here triggers that registration.

# ── Manifest-driven legacy CLI gate registration ──────────────────────────────
# The manifest.d directory is the single source of truth for legacy gate wiring.
# This macro scans manifest.d at macro-expansion time and emits
# registerLegacyCliGate calls at top level — ensuring the dispatch table
# stays in lockstep with the manifest.

macro registerAllManifestGates: untyped =
  let manifestDir = currentSourcePath().parentDir / "manifest.d"
  var resultStmts: seq[NimNode]
  var manifestIds: seq[string]

  for item in walkDir(manifestDir):
    let path = item.path
    if path.endsWith(".json") and path.rsplit('/', 1)[^1] != "_index.json":
      let j = parseJson(staticRead(path))
      let gateId = j["id"].getStr()
      manifestIds.add(gateId)

  # ── Index consistency check ───────────────────────────────────────────
  let indexContent = staticRead(manifestDir / "_index.json")
  var indexEntryCount = 0
  for line in indexContent.splitLines():
    if line.strip().len > 0:
      inc indexEntryCount

  if manifestIds.len != indexEntryCount:
    error("Axiom Architecture Violation: manifest.d has " & $manifestIds.len &
          " JSON files but _index.json lists " & $indexEntryCount &
          " entries — directory/index mismatch")

  # ── Emit registerLegacyCliGate calls (top-level AST) ──────────────────
  for gateId in manifestIds:
    if gateId != "trust-commit-scope":
      resultStmts.add(
        nnkCall.newTree(
          bindSym("registerLegacyCliGate"),
          newLit(gateId)
        )
      )

  # ── 1:1 invariant assertion (DEBT#270) — emitted as static: block ────
  # This static: block will be evaluated after the registerLegacyCliGate
  # calls above have been compiled, so registeredGates is fully populated.
  let manifestSetLit = newLit(manifestIds)
  resultStmts.add(quote do:
    static:
      var manifestSet: HashSet[string]
      for id in `manifestSetLit`:
        manifestSet.incl(id)
      var runnerSet: HashSet[string]
      for (id, _) in registeredGates:
        runnerSet.incl(id)

      let onlyManifest = manifestSet - runnerSet
      let onlyRunners = runnerSet - manifestSet

      if onlyManifest.len > 0 or onlyRunners.len > 0:
        var msg = "Axiom Architecture Violation (DEBT#270): Manifest ↔ Runner 1:1 invariant broken."
        if onlyManifest.len > 0:
          msg &= "\n  Manifest-only (no runner): " & ($onlyManifest)
        if onlyRunners.len > 0:
          msg &= "\n  Runner-only (no manifest): " & ($onlyRunners)
        msg &= "\n  Manifest count: " & $manifestSet.len & ", Runner count: " & $runnerSet.len
        error(msg)
  )

  result = nnkStmtList.newTree(resultStmts)

registerAllManifestGates()


