import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## macro_dispatcher.nim — Compile-time gate dispatch via macro-generated case table
##
## Replaces the runtime LightGateAllowlist + inProcessRegistry pattern
## with a compile-time generated static dispatch table.
##
## Key properties:
##   - Zero runtime overhead (case statement generated at compile time)
##   - Compile-time duplicate gate ID detection (error() → build failure)
##   - No hash table lookup — Nim optimizes string case to hash-based dispatch
##
## See: docs/agents/architecture.md, Plan v13-Absolute

import std/macros
import std/strutils
import std/times
import gate/gate_contract
import gate/utils/gate_safety_macro

# ─── Compile-Time Gate Registry ──────────────────────────────────────────────

var registeredGates* {.compileTime.}: seq[(string, NimNode)] = @[]

macro registerGate*(gateId: static[string], runner: untyped): untyped =
  ## Register a gate runner at compile time.
  ## Each gate module calls this at top level:
  ##   registerGate("annotation-hygiene", runAnnotationHygiene)
  ##
  ## Duplicate detection: if gateId is already registered, the build fails
  ## with a clear error message — human mistakes caught at compile time.
  for (existingId, _) in registeredGates:
    if existingId == gateId:
      error("Axiom Architecture Violation: Duplicate gate identifier in registry -> " & gateId)
  registeredGates.add((gateId, runner))
  result = newEmptyNode()

macro registerLegacyCliGate*(gateId: static[string]): untyped =
  ## Bridges legacy CLI gates into the compile-time dispatch table.
  ## Generates a named wrapper proc that delegates to runLegacyGateSubprocess.
  ## The named proc is necessary because buildDispatchCase generates
  ## nnkCall.newTree(runner, ...) which requires runner to be a callable symbol.
  let procName = ident("runLegacy_" & gateId.replace("-", "_"))
  result = quote do:
    proc `procName`(gate: GateConfig, ctx: InProcessGateContext): GateResult {.raises: [CatchableError].} =
      runLegacyGateSubprocess(gate, ctx)
    registerGate(`gateId`, `procName`)

# ─── Subprocess Fallback ─────────────────────────────────────────────────────

proc runSubprocessFallback*(gate: GateConfig; ctx: InProcessGateContext): GateResult {.raises: [CatchableError].} =
  ## Defense-in-depth fallback for gates not in the compile-time registry.
  ## All 83 gates are registered via registerLegacyCliGate (2026-07-07).
  ## This safety net catches manifest/registry mismatches at runtime:
  ## if a new gate is added to gate_manifest.json but forgotten in
  ## all_gate_runners.nim, it produces a clear error instead of a
  ## Nim match failure. The name="" sentinel signals "not dispatched"
  ## to the orchestrator's macroResult.name.len check.
  ##
  ## name is LEFT EMPTY to signal "gate was NOT dispatched by macro".
  ## The caller uses `macroResult.name.len > 0` to distinguish
  ## "macro dispatched a result" from "no match, fall through to subprocess".
  GateResult(
    ok: false,
    name: "",
    stdout: "Gate not registered for in-process dispatch: " & gate.id & ". Falling back to subprocess.",
    stderr: "",
    duration: initDuration())

# ─── Dispatch Macro ──────────────────────────────────────────────────────────

macro buildDispatchCase*(gateIdSym, gateSym, ctxSym: untyped): untyped =
  ## Generate a case statement over registered gate IDs at compile time.
  ## Each branch calls the registered runner proc with the context.
  ## The else branch calls runSubprocessFallback.
  result = nnkCaseStmt.newTree(gateIdSym)
  for (gateId, runner) in registeredGates:
    result.add(
      nnkOfBranch.newTree(
        newStrLitNode(gateId),
        nnkStmtList.newTree(
          nnkAsgn.newTree(ident("result"), nnkCall.newTree(runner, gateSym, ctxSym))
        )
      )
    )
  # else: fallback to subprocess path
  result.add(
    nnkElse.newTree(
      nnkStmtList.newTree(
        nnkAsgn.newTree(ident("result"),
          nnkCall.newTree(ident("runSubprocessFallback"), ident("gate"), ctxSym))
      )
    )
  )

proc dispatchGateInProcessMacro*(gate: GateConfig; ctx: InProcessGateContext
): GateResult {.raises: [CatchableError].} =
  ## Dispatch a gate using compile-time generated static case table.
  ## Zero runtime overhead — the case statement is optimized by Nim's compiler.
  buildDispatchCase(gate.id, gate, ctx)

{.pop.}
