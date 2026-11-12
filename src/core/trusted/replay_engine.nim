import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import core/trusted/solver_invocation
import core/trusted/evidence_calculus
import core/results
import std/strutils

type
  ReplayStatus* = enum
    rsMatch
    rsMismatch
    rsUnavailable

func replayKeyFor*(si: SolverInvocation): string {.inline, raises: [].} =
  si.replayKey

proc runReplay*(
    si: SolverInvocation;
    timeoutMs: int;
    storedOutcome: string;
    invoke: proc(smt: string, t: int): Result[string, string]
): ReplayStatus {.raises: [].} =
  if si.smtScript.len == 0:
    return rsUnavailable
  let res = invoke(si.smtScript, timeoutMs)
  if res.isErr:
    return rsUnavailable
  let outcome = res.get().strip().toLowerAscii()
  if outcome == storedOutcome.toLowerAscii():
    rsMatch
  else:
    rsMismatch

func verifySmtDigest*(si: SolverInvocation): bool {.inline, raises: [].} =
  smtDigestConsistent(si)

func setReplayEvidence*(bundle: var EvidenceBundle; status: ReplayStatus) {.raises: [].} =
  bundle.facts.replay.checker = "z3"
  bundle.facts.replay.artifactDigest = bundle.solverInvocation.replayKey
  case status
  of rsMatch:
    bundle.facts.replay.result = "MATCH"
  of rsMismatch:
    bundle.facts.replay.result = "MISMATCH"
  of rsUnavailable:
    bundle.facts.replay.result = "UNAVAILABLE"

{.pop.}