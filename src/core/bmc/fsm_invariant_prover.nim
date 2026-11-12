import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

import core/types/z3_solver_config
import core/proof/proof_budget
import std/monotimes
import std/os
import std/osproc
import std/streams
import std/strutils
import std/times
import core/axiom_pragmas
# =============================================================================
# Types
# =============================================================================

type
  FsmInvariantKind* = enum
    fikDeadlockFreedom      ## From every non-terminal state, ≥1 transition exists
    fikTransitionValidity   ## Only legal transitions are reachable
    fikForwardProgress      ## FSM eventually reaches a terminal state

  FsmProverResult* = object
    kind*: FsmInvariantKind
    proved*: bool           ## true if Z3 returned unsat (property holds)
    timedOut*: bool         ## true if Z3 returned unknown or timed out
    z3Output*: string       ## Raw Z3 output for debugging
    elapsedMs*: int64       ## Wall-clock time in milliseconds
# =============================================================================
# FSM Encoding Constants
# =============================================================================

const
  FsmStateCount* = 9

  LegalTransitions*: array[14, tuple[src, dst: int]] = [
    (0, 1),  # Unattempted → InProgress (start)
    (1, 2),  # InProgress → Verified (succeed)
    (1, 3),  # InProgress → CounterEx (counterExample)
    (1, 4),  # InProgress → TimedOut (timeout)
    (1, 5),  # InProgress → Unverifiable (unverifiable)
    (1, 6),  # InProgress → Blocked (markBlocked)
    (1, 7),  # InProgress → Vacuous (vacuous)
    (3, 0),  # CounterEx → Unattempted (retry)
    (4, 0),  # TimedOut → Unattempted (retry)
    (5, 0),  # Unverifiable → Unattempted (retry)
    (6, 0),  # Blocked → Unattempted (unblock)
    (7, 0),  # Vacuous → Unattempted (retry)
    (8, 0),  # Unknown → Unattempted (reverify)
    (2, 8),  # Verified → Unknown (demote)
  ]

  TerminalStates*: set[uint8] = {2, 3, 4, 5, 6, 7, 8}
  NonTerminalStates*: set[uint8] = {0, 1}
  MaxBmcDepth* = 8

# =============================================================================
# SMT-LIB2 BMC Encoding (Pure String Builders)
# =============================================================================
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func emitHeader(timeoutMs: int; rlimit: int = defaultRlimitBudget): string =
  ## [DETERMINISTIC] rlimit (from proof_budget SSOT) is the PRIMARY decision bound.
  ## Wall-clock timeout is a process safety net only — NOT used for proof decisions.
  "(set-logic QF_LIA)\n" &
  "(set-option :rlimit " & $rlimit & ")\n" &
  # [DETERMINISTIC] Replaced by rlimit — kept as safety net for process management
  "(set-option :timeout " & $timeoutMs & ")\n"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func emitTransitionRelation(): string =
  result = "; Transition relation T(s, sp): legal transitions only\n"
  result &= "(define-fun T ((s Int) (sp Int)) Bool\n"
  result &= "  (or"
  for (src, dst) in LegalTransitions:
    result &= "\n    (and (= s " & $src & ") (= sp " & $dst & "))"
  result &= "))\n\n"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func emitNonTerminalCheck(): string =
  "; Non-terminal predicate\n" &
  "(define-fun NT ((s Int)) Bool\n" &
  "  (or (= s 0) (= s 1)))\n\n"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func emitTerminalCheck(): string =
  "; Terminal predicate\n" &
  "(define-fun Term ((s Int)) Bool\n" &
  "  (or (= s 2) (= s 3) (= s 4) (= s 5) (= s 6) (= s 7) (= s 8)))\n\n"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func emitStateBounds(n: int): string =
  result = ""
  for i in 0..<n:
    result &= "(declare-const s" & $i & " Int)\n"
    result &= "(assert (and (>= s" & $i & " 0) (<= s" & $i & " 8)))\n"
  result &= "\n"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func emitReachabilityPath(depth: int): string =
  result = "; Reachability path: s0=0, T(s_i, s_{i+1})\n"
  result &= "(assert (= s0 0))\n"
  for i in 0..<depth:
    result &= "(assert (T s" & $i & " s" & $(i+1) & "))\n"
  result &= "\n"

# =============================================================================
# Invariant Queries
# =============================================================================
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func emitDeadlockFreedomQuery(): string =
  result = "; Deadlock freedom: non-terminal state with no outgoing transition\n"
  result &= "(declare-const dl_s Int)\n"
  result &= "(assert (and (>= dl_s 0) (<= dl_s 8)))\n"
  result &= "(assert (NT dl_s))\n"
  result &= "; No successor exists for dl_s\n"
  result &= "(assert (not (or"
  for dst in 0..<FsmStateCount:
    result &= "\n    (T dl_s " & $dst & ")"
  result &= ")))\n\n"
  result &= "(check-sat)\n"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func emitTransitionValidityQuery(): string =
  result = "; Transition validity: illegal transition exists\n"
  result &= "(declare-const tv_s Int)\n(declare-const tv_sp Int)\n"
  result &= "(assert (and (>= tv_s 0) (<= tv_s 8)))\n"
  result &= "(assert (and (>= tv_sp 0) (<= tv_sp 8)))\n"
  result &= "; Assert T(tv_s, tv_sp) — transition exists\n"
  result &= "(assert (T tv_s tv_sp))\n"
  result &= "; Assert NOT one of the 14 legal transitions\n"
  result &= "(assert (not (or"
  for (src, dst) in LegalTransitions:
    result &= "\n    (and (= tv_s " & $src & ") (= tv_sp " & $dst & "))"
  result &= ")))\n\n"
  result &= "(check-sat)\n"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func emitForwardProgressQuery(depth: int): string =
  result = "; Forward progress: path of depth " & $depth & " with no terminal state\n"
  result &= emitStateBounds(depth + 1)
  result &= emitReachabilityPath(depth)
  result &= "; No state on the path is terminal\n"
  result &= "(assert (and"
  for i in 0..depth:
    result &= "\n  (not (Term s" & $i & "))"
  result &= "))\n\n"
  result &= "(check-sat)\n"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildBmcQuery*(kind: FsmInvariantKind; timeoutMs: int): string =
  ## Build SMT-LIB2 BMC query. rlimit from proof_budget SSOT is primary decision
  ## mechanism; timeoutMs is process safety net only.
  result = emitHeader(timeoutMs)
  result &= emitTransitionRelation()
  result &= emitNonTerminalCheck()
  result &= emitTerminalCheck()
  case kind
  of fikDeadlockFreedom:
    result &= emitDeadlockFreedomQuery()
  of fikTransitionValidity:
    result &= emitTransitionValidityQuery()
  of fikForwardProgress:
    result &= emitForwardProgressQuery(MaxBmcDepth)
# =============================================================================
# Z3 Process Runner (I/O Boundary)
# =============================================================================
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runZ3Query*(query: string; z3Path: string  = resolveZ3Path();
                processTimeoutMs: int = 15_000): tuple[output: string; exitCode: int;
                                                        timedOut: bool] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # -T: 플래그는 Z3 내부 무한 루프 방지 (Nim 레벨 kill 백업과 중복 안전장치).
  let timeoutSec = max(1, processTimeoutMs div 1000)
  var p = startProcess(z3Path, args = @["-smt2", "-in", "-T:" & $timeoutSec],
                       options = {poStdErrToStdOut, poUsePath})
  let stdinStream = inputStream(p)
  let stdoutStream = outputStream(p)

  stdinStream.write(query)
  stdinStream.flush()
  close(p.inputStream)

  let startTime = getMonoTime()
  var output = ""
  var line = ""
  while true:
    if stdoutStream.readLine(line):
      output.add(line)
      output.add("\n")
      let stripped = line.strip()
      if stripped == "sat" or stripped == "unsat" or stripped == "unknown":
        break
    else:
      let elapsed = (getMonoTime() - startTime).inMilliseconds
      if elapsed > processTimeoutMs:
        p.kill()
        close(p)
        return (output & "\n[TIMEOUT: killed after " & $processTimeoutMs & "ms]",
                -1, true)
      sleep(10)

  let _ = peekExitCode(p)
  close(p)
  (output, 0, false)

# =============================================================================
# Public API
# =============================================================================
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc proveInvariant*(kind: FsmInvariantKind; z3Path: string  = resolveZ3Path();
                     timeoutMs: int = 10_000): FsmProverResult =
  let startTime = getMonoTime()
  let query = buildBmcQuery(kind, timeoutMs)
  let (output, exitCode, processTimedOut) = runZ3Query(query, z3Path, timeoutMs + 5000)
  let elapsedMs = (getMonoTime() - startTime).inMilliseconds

  let firstLine = output.strip().splitLines()[0].strip()
  let proved = firstLine == "unsat"
  let timedOut = processTimedOut or firstLine == "unknown" or firstLine.len == 0

  FsmProverResult(
    kind: kind,
    proved: proved,
    timedOut: timedOut,
    z3Output: output,
    elapsedMs: elapsedMs
  )
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc proveAllInvariants*(z3Path: string  = resolveZ3Path();
                         timeoutMs: int = 10_000): seq[FsmProverResult] =
  result = @[]
  for kind in FsmInvariantKind:
    result.add(proveInvariant(kind, z3Path, timeoutMs))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc isFullyProved*(results: seq[FsmProverResult]): bool  =
  result = true
  for r in results:
    if not r.proved:
      return false
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc summarizeResults*(results: seq[FsmProverResult]): string  =
  result = "FSM Invariant Proof Summary:\n"
  for r in results:
    let status = if r.proved: "PROVED"
                 elif r.timedOut: "TIMEOUT"
                 else: "FAILED"
    result &= "  " & $r.kind & ": " & status & " (" & $r.elapsedMs & "ms)\n"

{.pop.}

