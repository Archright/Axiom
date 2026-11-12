import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Provers — Concrete prover implementations (Infrastructure layer).
##
## Z3PoolProver wraps z3_pool.z3ExecPersistent behind prove/name.
## LeanProver wraps lean_replay.runLeanReplay behind prove/name.
## Both satisfy the ProverInterface concept from core/solver/interfaces.nim,
## enabling compile-time polymorphism via executeProof[T: ProverInterface].
##
## Extracted from core/solver/wrappers.nim during PR #3 (SoC enforcement:
## concrete implementations belong in Infrastructure, not Domain).
##
## QF_FP isolation (v32): proveQfFp spawns a SEPARATE Z3 process per query,
## never reusing the QF_BV persistent pool. Uses (set-logic QF_FP) with
## (set-option :rlimit 500000) for deterministic resource bounds.
## Audit trail: every QF_FP invocation is logged to Z3 telemetry.

import core/results
import verification/solver/z3_pool
import core/judge/lean_replay
import std/strutils
import core/axiom_pragmas

import core/solver/prover_types
import core/sync/sync_utils_process
import core/types/z3_solver_config
# axiomIoBoundary
export prover_types

const
  qfFpRlimit* = 500_000  ## QF_FP-specific rlimit budget (stricter than QF_BV's 30M).
                          ## Float theory is combinatorially expensive — bounded
                          ## to prevent solver explosion on seq × float products.
                          ## SSOT: proof_budget.defaultRlimitBudget for QF_BV (30M).
                          ## QF_FP uses a tighter budget due to combinatorial blowup.

proc prove*(p: Z3PoolProver; query: string; timeoutMs: int): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Execute Z3 via persistent pool, return true iff result is "unsat".
  var cd, td: string
  let res = z3ExecPersistent(query, timeoutMs, desiredWorkers = 2,
    canonicalEnvelopeDigest = cd, transportPayloadDigest = td)
  return res.isOk and res.get().strip().toLowerAscii() == "unsat"

proc name*(p: Z3PoolProver): string = "Z3PoolProver"

proc prove*(p: LeanProver; query: string; timeoutMs: int): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Execute Lean 4 compiler, return true iff type-checking succeeds.
  let res = runLeanReplay("node_auto", query)
  return res.isOk and res.get().isValid

proc name*(p: LeanProver): string = "LeanProver"

proc proveQfFp*(p: Z3PoolProver; query: string; timeoutMs: int = 5000): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Run a QF_FP (floating-point theory) query via isolated subprocess.
  ## Uses rlimit for deterministic resource bounds.
  ## Returns true if the property holds (unsat), false if timeout or error.
  ##
  ## **Isolation**: spawns a FRESH Z3 process per call — never reuses the
  ## QF_BV persistent pool. This prevents QF_FP's combinatorial blowup
  ## from starving QF_BV queries of pool worker slots.
  ##
  ## **Audit trail**: every QF_FP invocation goes through runProcessWithTimeout
  ## and result is logged by the caller via Z3 telemetry.
  ##
  ## **Fail-open on error**: returns false (unproven) on timeout, Z3 crash,
  ## or non-unsat response. Caller may retry or escalate to Lean.
  let z3Path = resolveZ3Path()
  if z3Path.len == 0:
    return false
  # Build QF_FP query: logic declaration + rlimit (PRIMARY) + timeout (safety net)
  var qfFpPayload = "(set-logic QF_FP)\n"
  # [DETERMINISTIC] rlimit is the PRIMARY decision bound — CPU-independent
  qfFpPayload.add("(set-option :rlimit " & $qfFpRlimit & ")\n")
  # [DETERMINISTIC] Replaced by rlimit — wall-clock timeout kept as process safety net only
  if timeoutMs > 0:
    qfFpPayload.add("(set-option :timeout " & $timeoutMs & ")\n")
  qfFpPayload.add(query)
  if not qfFpPayload.endsWith("\n"):
    qfFpPayload.add("\n")
  # Spawn isolated Z3 process — one-shot, no pool, no shared state
  var res: ManagedProcessResult
  try:
    res = runProcessWithTimeout(z3Path, @["-smt2", "-in"], timeoutMs, qfFpPayload)
  except CatchableError:
    return false  # axiom:best-effort(Z3 QF_FP subprocess crash — return false (unproven) is the safe closed-world default; caller retries or escalates to Lean)
  if res.timedOut or res.exitCode == -1:
    return false
  return res.output.strip().toLowerAscii() == "unsat"

{.pop.}

proc proveWithOutput*(p: Z3PoolProver; query: string; timeoutMs: int): Result[string, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Execute Z3 via persistent pool, return raw output string.
  ## Satisfies ProverOutputInterface concept.
  ## Unlike prove (which returns bool), this preserves the full Z3 response
  ## for unsat core extraction and constructive witness parsing.
  var cd, td: string
  z3ExecPersistent(query, timeoutMs, desiredWorkers = 1,
    canonicalEnvelopeDigest = cd, transportPayloadDigest = td)

proc proveRaw*(p: Z3PoolProver; query: string; timeoutMs: int): Result[string, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Execute Z3 via persistent pool, return raw output string.
  ## Unlike prove (which returns bool), this preserves the full Z3 response
  ## for counterexample extraction and invariant parsing.
  var cd2, td2: string
  z3ExecPersistent(query, timeoutMs, desiredWorkers = 1,
    canonicalEnvelopeDigest = cd2, transportPayloadDigest = td2)

# ---------------------------------------------------------------------------
# QF_FP Classification (post-{.pop.} — pure func, no effect constraints)
# ---------------------------------------------------------------------------

import core/trusted/axiom_ir

proc classifyAsQfFp*(funcDef: IRFuncDef): bool =
  ## Detect if a function requires QF_FP (floating-point theory) verification.
  ##
  ## Routing criteria:
  ## - Has float-typed parameter or return type AND has list/seq parameter → QF_FP
  ## - Simple float-only functions → QF_BV with fixed-point scaling (SA-4's job)
  ## - Float+seq composite types → QF_FP (this function's domain)
  ##
  ## Detection uses serialized IR string matching against type markers.
  ## When irtFloat is added to IRTypeKind, upgrade to structural matching
  ## on IRFuncDef.params[].ty.kind and funcDef.retType.kind.
  let serialized = serializeIRFuncDef(funcDef)
  # Float type marker: will be "FLOAT" when irtFloat is added to IRTypeKind.
  # For now, also matches "float"/"Float" in function names as heuristic.
  let hasFloatType = "FLOAT" in serialized or
                     funcDef.name.contains("Float") or
                     funcDef.name.contains("float")
  # List/seq type marker in parameter positions
  let hasListType = "LIST(" in serialized
  return hasFloatType and hasListType

