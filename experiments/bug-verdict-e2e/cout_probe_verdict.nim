## C_out verdict-chain probe — the engine-level PROPOSITION_DISPROVED(C_out) capture for
## docs/evidence/nim_stew_base36_cout_slice_2026-10-10.md.
##
## Companion to cout_probe.nim (external K observation) and the S6 precedent
## s6_probe_verdict.nim (fixture legs). This probe drives the SAME engine path
## the prove run drives — C_out overlay load → candidate synthesis →
## runIrPipelineWithCas (P4 promotion + replay adapter) — over the REAL pinned
## subject and prints the operational verdict projection and the full
## counterExample payload (glossary §2.2 four-element record):
##
##   PROPOSITION_DISPROVED(C_out) := vsDisproved(P4 cvConfirmed) ∧ replay agreed (rvAgree)
##                       ∧ node terminal failed (reduceRunAccounting/VDA)
##
## The subject root is passed as the first argument (the out-of-tree READ-ONLY
## nim-stew clone; Zero-Footprint — the subject is never modified).
import std/[os, options, tables, strutils, json]

import ../../src/core/results
import ../../src/core/trusted/axiom_pragmas
import ../../src/core/trusted/claim_authority
import ../../src/core/trusted/assurance_profile
import ../../src/cli/axiom_engine
import ../../src/verification/accounting/run_accounting
import ../../src/verification/obligation/verification_decision_authority
import ../../src/verification/batch_uap/ir_pipeline_runner
import ../../src/infrastructure/external_ir_materializer
import ../../src/core/trusted/verification_result_types as vrt

proc subjectResolver(root: string): ModuleContentResolver =
  result = proc(modulePath: string): Option[string] {.raises: [].} =
    try:
      some(readFile(root / modulePath))
    except CatchableError:
      none(string)

func nodeReport(unitId, status: string): JsonNode =
  %*{"nodeId": unitId, "status": status, "cacheHit": false,
     "dependencyDepth": 0}

func runVerdictFor(status: string): RunOutcome =
  ## The run-level projection for a single-node wave with the canonical OGR
  ## eligibility basis (elProofCandidate = REQUIRED) — the same reducer + VDA
  ## the engine drives.
  let wave = %*{"nodeReports": @[nodeReport(
    "stew/base36.nim::decodedLength", status)]}
  let elig = %*{"stew/base36.nim::decodedLength": "elProofCandidate"}
  let acc = reduceRunAccounting(@[wave], elig)
  evaluateRunOutcome(acc,
    NoObligationProvenance(universeEnumerated: true,
                           source: "canonical_ogr_eligibility"),
    false)

func pipelineNodeStatus(status: VerificationStatus): string =
  ## Terminal node-status string the engine's run accounting consumes,
  ## projected from the pipeline verdict (S6 precedent).
  case status
  of vsProved: "verified"
  of vsDisproved: "failed"
  else: "inconclusive"

proc main() =
  let root = if paramCount() >= 1: paramStr(1)
             else: "/tmp/b36slice/nim-stew"
  putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_cout_verdict")
  echo "=== C_out — PROPOSITION_DISPROVED(C_out) verdict chain ==="
  echo "subject root: " & root
  var census = ExternalCandidateCensus()
  let domainRes = loadBase36CoutOverlayDomain()
  if domainRes.isErr:
    echo "OVERLAY ERROR: " & domainRes.error
    return
  let domain = domainRes.get()
  echo "overlay: symbol=" & domain.symbol &
       " domain=" & $domain.domainLower & "<=" & domain.domainVar &
       "<=" & $domain.domainBound &
       " K=" & $domain.claimConstant &
       " decisionInput=" & domain.decisionInput
  let synth = synthesizeBase36CoutCandidate(
    domain.symbol, domain.modulePath, subjectResolver(root), domain, census)
  if synth.isErr:
    echo "SYNTH ERROR: " & synth.error
    return
  if census.eligible.len != 1:
    echo "CENSUS: eligible=" & $census.eligible.len
    return
  let ve = census.eligible[0]
  var memo = initTable[string, IrPipelineResult]()
  let pve = ValidatedIrEntry(entry: ve.entry, funcDef: ve.funcDef,
                             parseBound: ve.parseBound)
  let res = runIrPipelineWithCas(pve, nil, memo, bpRequire, root)
  echo "pipeline: success=" & $res.success &
       " status=" & $res.verification.status &
       " solverMethod=" & $res.verification.solverMethod &
       " provenance=" & $res.verification.provenance &
       " solverStatus=" & $res.verification.solverStatus
  let claimOutcome = if res.verifiedClaim.isSome: res.verifiedClaim.get.outcome
                     else: clUnknown
  echo "claim: outcome=" & $claimOutcome
  let ro = runVerdictFor(pipelineNodeStatus(res.verification.status))
  echo "run: verdict=" & $ro.verdict & " basis=" & $ro.basis
  if res.counterExample.len == 0:
    echo "counterExample: EMPTY — PROPOSITION_DISPROVED cannot be reported (fail-closed)"
    return
  echo "counterExample records (" & $res.counterExample.len & "):"
  for rec in res.counterExample:
    echo "  " & rec
  echo "PROPOSITION_DISPROVED(C_out) = (" & $res.verification.status &
       " via P4 cvConfirmed) ∧ (" & $claimOutcome & ") ∧ run(" &
       $ro.verdict & "/" & $ro.basis & ")"

when isMainModule:
  main()
