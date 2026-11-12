## Component C — Pure Verdict Engine
##
## Verdict classification and JSON serialization for verification reports.
## Zero I/O.

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import std/options

import core/solver/types
import core/types/pipeline_core_types
export pipeline_core_types
import core/logic/pipeline_trace_artifacts
import core/json/std_redirect
import ../../core/trusted/axiom_pragmas

## Build Semantic Verification Verdict Report is now in core/contracts/universal_pipeline_contract.

## Build Verification Verdict Report.
func buildVerificationVerdictReport*(
  verificationVerdict: string;
  evolutionHit: Option[AnnotatedHit];
  nearestLeanDiagnostic: string;
  failedReplayAttempts: int
): VerificationVerdictReport {.raises: [], axiom: ["(assert (and (>= bindings 0) (>= result 0)))", "(bindings ≥ 0) ∧ (result ≥ 0)"].} =
  result = VerificationVerdictReport(
    status: verificationVerdict,
    category:
      if verificationVerdict == "critical_failure": "critical_failure"
      elif verificationVerdict == "refuted_by_counterexample": "logical_contradiction"
      elif verificationVerdict == "proven_by_induction": "proof_necessary"
      else: "pipeline_result",
    failureOrigin:
      if verificationVerdict == "critical_failure": "precondition"
      elif verificationVerdict == "refuted_by_counterexample": "code"
      elif verificationVerdict == "proven_by_induction": "none"
      else: "engine",
    finalVerdict:
      if verificationVerdict == "critical_failure":
        "CRITICAL_FAILURE: LOGIC_MODEL_CONFLICT. Final Verdict: the logical model is contradictory (poison pill), so UNSAT evidence is non-probative."
      elif verificationVerdict == "refuted_by_counterexample":
        "Final Verdict: the pipeline found a concrete counterexample, so the failure is caused by the implementation."
      elif verificationVerdict == "proven_by_induction":
        "Final Verdict: the pipeline closed the proof deterministically from solver evidence to Lean replay."
      else:
        "Final Verdict: the pipeline did not complete a deterministic proof replay.",
    counterExampleProperty: "",
    counterExampleBindings: @[],
    counterExampleSummary: "",
    nearestLeanDiagnostic: nearestLeanDiagnostic,
    failedReplayAttempts: failedReplayAttempts
  )
  if evolutionHit.isSome():
    let selected = evolutionHit.get()
    result.counterExampleProperty = selected.violatedProperty
    result.counterExampleSummary = buildTraceReport(evolutionHit).counterExampleSummary
    let bindings = bindingsFromCounterExample(selected.counterExampleInput)
    if bindings.kind == JObject:
      for key, value in bindings:
        result.counterExampleBindings.add(SolverBinding(name: key, value: $value))

## Build Evolution Reasoning.
func buildEvolutionReasoning*(
  hit: AnnotatedHit;
  refinedInvariant: string;
  proofReplayVerdict: string
): string {.raises: [], axiom: ["(assert (and (>= (str.len refinedInvariant) 0) (>= (str.len proofReplayVerdict) 0)))", "refinedInvariant.length ≥ 0 ∧ proofReplayVerdict.length ≥ 0"].} =
  let traceSignature = traceSignatureFromCounterExample(hit.counterExampleInput)
  case hit.hit.kind
  of vkGhostUpdate:
    "rootCause=stale write path can mutate payload without a monotonic version contract; trace=" &
      traceSignature &
      "; defense=" & refinedInvariant &
      "; proofReplay=" & proofReplayVerdict
  of vkBufferOverflow:
    "rootCause=index branch accepts out-of-range access; trace=" & traceSignature &
      "; defense=" & refinedInvariant &
      "; proofReplay=" & proofReplayVerdict
  of vkNullPointerDereference:
    "rootCause=pointer path reaches dereference without nil guard; trace=" & traceSignature &
      "; defense=" & refinedInvariant &
      "; proofReplay=" & proofReplayVerdict
  of vkIntegerOverflowUnderflow:
    "rootCause=arithmetic transition lacks balance-range invariant; trace=" & traceSignature &
      "; defense=" & refinedInvariant &
      "; proofReplay=" & proofReplayVerdict
  of vkDeadlockRaceCondition:
    "rootCause=shared-state branch lacks synchronization invariant; trace=" & traceSignature &
      "; defense=" & refinedInvariant &
      "; proofReplay=" & proofReplayVerdict


{.pop.}
