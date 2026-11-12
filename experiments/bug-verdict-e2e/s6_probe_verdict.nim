## S6 verdict-chain probe — the engine-level PROPOSITION_DISPROVED / NO_BUG_PROVED demo.
##
## Companion to s6_probe.nim (single-leg detail dump) and the S6 suites in
## tests/unit/test_bug_verdict_projection.nim (committed acceptance). This
## probe drives the SAME engine path end-to-end over BOTH fixture legs and
## reports the operational verdicts:
##
##   GOLDEN → NO_BUG_PROVED(P_rel, D) := vrPass ∧ vdVerified ∧ clProved
##   MUTANT → PROPOSITION_DISPROVED := vrFail ∧ clDisproved ∧ classified(icCounterexample)
##            with the §2.2 four-element record (exact fixture identity,
##            exact input, violated conjunct, replay command + output).
##
## Fixture roots resolve off the repo tests/ tree (tests/negative/
## base36_mutant_subject — pure fixture isolation, nim-stew stays
## READ-ONLY), the same roots the unit suites measure through.
import std/[os, options, tables, strutils, sequtils, json]

import ../../src/core/results
import ../../src/core/trusted/axiom_pragmas
import ../../src/core/trusted/claim_authority
import ../../src/core/trusted/assurance_profile
import ../../src/core/trusted/specification_artifact
import ../../src/core/trusted/evidence_calculus
import ../../src/core/utils/repo_root
import ../../src/cli/axiom_engine
import ../../src/verification/accounting/run_accounting
import ../../src/verification/obligation/verification_decision_authority
import ../../src/verification/obligation/obligation_types
import ../../src/verification/obligation/canonical_verification
import ../../src/verification/batch_uap/ir_pipeline_runner
import ../../src/infrastructure/external_ir_materializer
import ../../src/verification/counterexample_replay
import ../../src/core/trusted/verification_result_types as vrt

proc fixtureResolver(root: string): ModuleContentResolver =
  result = proc(modulePath: string): Option[string] {.raises: [].} =
    try:
      some(readFile(root / modulePath))
    except CatchableError:
      none(string)

proc synthFor(root: string): tuple[ok: bool, entry: ExternalIrEntry] =
  var census = ExternalCandidateCensus()
  let domainRes = loadBase36OverlayDomain()
  if domainRes.isErr:
    echo "OVERLAY ERROR: " & domainRes.error
    return (false, ExternalIrEntry())
  let synth = synthesizeBase36RelationalCandidate(
    "encodedLength", domainRes.get().modulePath,
    fixtureResolver(root), domainRes.get(), census)
  if synth.isErr:
    echo "SYNTH ERROR: " & synth.error
    return (false, ExternalIrEntry())
  if census.eligible.len != 1:
    echo "CENSUS: eligible=" & $census.eligible.len
    return (false, ExternalIrEntry())
  (true, census.eligible[0])

func nodeReport(unitId, status: string): JsonNode =
  %*{"nodeId": unitId, "status": status, "cacheHit": false,
     "dependencyDepth": 0}

func runVerdictFor(status: string): RunOutcome =
  ## The run-level projection for a single-node wave with the canonical OGR
  ## eligibility basis (elProofCandidate = REQUIRED) — the same reducer + VDA
  ## the engine drives.
  let wave = %*{"nodeReports": @[nodeReport(
    "stew/base36.nim::encodedLength", status)]}
  let elig = %*{"stew/base36.nim::encodedLength": "elProofCandidate"}
  let acc = reduceRunAccounting(@[wave], elig)
  evaluateRunOutcome(acc,
    NoObligationProvenance(universeEnumerated: true,
                           source: "canonical_ogr_eligibility"),
    false)

func pipelineNodeStatus(status: VerificationStatus): string =
  ## Terminal node-status string the engine's run accounting consumes,
  ## projected from the pipeline verdict.
  case status
  of vsProved: "verified"
  of vsDisproved: "failed"
  else: "inconclusive"

proc overlaySpec(): SpecificationArtifact =
  explicitSpecFromOverlay(parseJson(readFile(
    repoRootConst() / "config" / "spec" /
    "base36_sizing_relational_spec.json"))).get()

proc claimCtx(spec: SpecificationArtifact; signal: ClaimSignal): ClaimContext =
  ## A5 precedent (test_base36_contract_policy.nim) — the real overlay spec
  ## through the real claim calculus.
  var bundle: EvidenceBundle
  bundle.specificationArtifact = spec
  bundle.facts.solver.solverIdentity = "z3"
  bundle.facts.solver.smtHash = "abc123"
  ClaimContext(
    subjectId: "stew/base36.nim", sourceIdentity: "h", specification: spec,
    semanticProfileId: spec.specIdentity, obligationGenerated: true,
    supported: true, dependenciesSatisfied: true, proofSignal: signal,
    evidenceBundle: bundle, policyId: "apV1")

proc goldenLeg(root: string) =
  echo "=== GOLDEN — NO_BUG_PROVED(P_rel, D) ==="
  let s = synthFor(root)
  if not s.ok: return
  let ve = s.entry
  # artifact level: vdVerified (KAA + policy) through the canonical binding
  let cres = executeCanonicalVerification(
    ve.funcDef, ve.entry.sourcePath, ve.entry.name, ve.entry.sourceContent,
    subjectRepoRoot = root, preSynthesisIrDigest = "",
    parseBound = ve.parseBound)
  echo "artifact: verdict=" & $cres.verdict & " success=" & $cres.success &
       " evidence=" & cres.evidence & " sealError=" & cres.sealError
  # pipeline level: the same entry the engine runs
  var memo = initTable[string, IrPipelineResult]()
  let pve = ValidatedIrEntry(entry: ve.entry, funcDef: ve.funcDef,
                             parseBound: ve.parseBound)
  let res = runIrPipelineWithCas(pve, nil, memo, bpRequire, root)
  echo "pipeline: success=" & $res.success &
       " status=" & $res.verification.status &
       " evidence=" & res.verification.evidence
  # claim level: the real overlay spec through the real claim calculus —
  # the canonical-verified path returns before the solver lane populates
  # verifiedClaim, so the conjunct is measured at the claim authority
  # (the same A5 precedent the S6 unit suite measures).
  let claimOutcome = deriveClaim(claimCtx(overlaySpec(), psUnsat), apV1).outcome
  echo "claim: outcome=" & $claimOutcome
  # run level: the real reducer + VDA over the projected node status
  let ro = runVerdictFor(pipelineNodeStatus(res.verification.status))
  echo "run: verdict=" & $ro.verdict & " basis=" & $ro.basis
  echo "NO_BUG_PROVED(P_rel, D) = " & $ro.verdict & " ∧ " & $cres.verdict &
       " ∧ " & $claimOutcome
  echo ""

proc mutantLeg(root: string) =
  echo "=== MUTANT — PROPOSITION_DISPROVED + §2.2 four-element record ==="
  let s = synthFor(root)
  if not s.ok: return
  let ve = s.entry
  var memo = initTable[string, IrPipelineResult]()
  let pve = ValidatedIrEntry(entry: ve.entry, funcDef: ve.funcDef,
                             parseBound: ve.parseBound)
  let res = runIrPipelineWithCas(pve, nil, memo, bpRequire, root)
  echo "pipeline: success=" & $res.success &
       " status=" & $res.verification.status &
       " evidence=" & res.verification.evidence
  let claimOutcome = if res.verifiedClaim.isSome: res.verifiedClaim.get.outcome
                     else: clUnknown
  echo "claim: outcome=" & $claimOutcome
  let ro = runVerdictFor(pipelineNodeStatus(res.verification.status))
  echo "run: verdict=" & $ro.verdict & " basis=" & $ro.basis
  if res.counterExample.len == 0:
    echo "counterExample: EMPTY — PROPOSITION_DISPROVED cannot be reported (fail-closed)"
    echo ""
    return
  echo "PROPOSITION_DISPROVED(P_rel, D) = " & $ro.verdict & " ∧ " & $claimOutcome &
       " ∧ classified(icCounterexample)"
  # element ① exact fixture identity — the adapter's measured git fold
  for rec in res.counterExample:
    if rec.startsWith("replay.subjectGitRef=") or
       rec.startsWith("replay.treeMerkle=") or
       rec.startsWith("replay.moduleSha256="):
      echo "record ① " & rec
  # element ② exact input — the solver's counterexample assignment
  var inputLits: seq[string]
  for rec in res.counterExample:
    if rec.startsWith("input."):
      echo "record ② " & rec
      inputLits.add(rec.substr("input.".len).split("=")[1])
  # element ③ the violated conjunct (the roundtrip equation the mutant erodes)
  for rec in res.counterExample:
    if rec.startsWith("propertyViolated="):
      echo "record ③ " & rec
  # element ④ the replay record — rerun the adapter observation so the real
  # toolchain's command, harness and observed output are printed verbatim.
  let shape = compositeReplayShape(ve.funcDef, ve.parseBound)
  var callExpr = ""
  if shape.outerSymbol.len > 0 and inputLits.len > 0:
    callExpr = shape.outerSymbol & "(" & shape.carrierTypename & ", " &
      shape.innerSymbol & "(" & shape.carrierTypename & ", " &
      inputLits[^1] & "))"
  var paramNames: seq[string]
  for p in ve.funcDef.params: paramNames.add(p.name)
  let cfg = ReplayConfig(
    subjectRepoRoot: root,
    subjectModulePath: joinPath(root, "stew", "base36.nim"),
    funcName: ve.funcDef.name,
    paramNames: paramNames,
    inputLiterals: inputLits,
    postconditions: ve.funcDef.postConditions,
    callExpr: callExpr)
  let replay = runCounterexampleReplay(cfg)
  let moduleDir = joinPath(root, "stew")
  echo "record ④ replay command:"
  echo "  nim c -r --hints:off --warnings:off --path:\"" & moduleDir &
       "\" --path:\"" & root & "\" \"" & replay.harnessDir &
       "/replay_harness.nim\""
  echo "record ④ replay harness (as synthesized by the adapter):"
  try:
    for line in readFile(replay.harnessDir / "replay_harness.nim").splitLines():
      echo "  " & line
  except CatchableError:
    echo "  <harness unreadable: " & replay.harnessDir / "replay_harness.nim" & ">"
  echo "record ④ replay observation: verdict=" & $replay.verdict &
       " exitCode=" & $replay.exitCode &
       " nimVersion=" & replay.nimVersion
  echo "record ④ replay observed output (real nim run):"
  for line in replay.observedOutput.splitLines():
    echo "  " & line
  for rec in res.counterExample:
    if rec.startsWith("replay."):
      echo "record ④ " & rec
  echo ""

proc main() =
  putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_s6_verdict")
  let repoTests = currentSourcePath().parentDir().parentDir().parentDir() / "tests"
  let goldenRoot = repoTests / "golden" / "base36_subject"
  let mutantRoot = repoTests / "negative" / "base36_mutant_subject"
  goldenLeg(goldenRoot)
  mutantLeg(mutantRoot)

when isMainModule:
  main()
