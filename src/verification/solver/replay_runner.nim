import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import core/axiom_pragmas
import core/trusted/solver_invocation
import core/trusted/replay_engine
import core/results
import verification/solver/z3_pool

func parseZ3Outcome(raw: string): string {.raises: [].} =
  ## Replay outcome is the solver's own response and nothing more. A replay
  ## that cannot read a ⟨check_sat_response⟩ records "unknown"; it never
  ## upgrades a bare unsat into a proof claim (docs/spec/evidence_calculus.md I6).
  $classifySolverVerdict(raw)

proc z3InvokeAdapter(smt: string; t: int): Result[string, string] {.raises: [], axiomDecision(id = "DECISION-0661", reason = "Bridge the replay runner to the Z3 CLI subprocess; wraps z3ExecPersistent with outcome parsing", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  var cd, td: string
  let res = z3ExecPersistent(smt, t,
    canonicalEnvelopeDigest = cd, transportPayloadDigest = td)
  if res.isErr():
    return err(res.error())
  let outcome = parseZ3Outcome(res.get())
  ok(outcome)

proc runReplayWithZ3*(
    si: SolverInvocation;
    storedOutcome: string;
    timeoutMs: int
): ReplayStatus =
  if si.smtScript.len == 0:
    return rsUnavailable
  if not verifySmtDigest(si):
    return rsMismatch
  runReplay(si, timeoutMs, storedOutcome, z3InvokeAdapter)

{.pop.}