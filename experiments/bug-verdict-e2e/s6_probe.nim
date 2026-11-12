## S6 probe 2 — canonical verdict detail + SMT script inspection.
import std/[unittest, os, strutils, options, tables, sequtils, json]

import ../../src/core/results
import ../../src/core/trusted/axiom_pragmas
import ../../src/core/trusted/claim_authority
import ../../src/cli/axiom_engine
import ../../src/verification/obligation/canonical_verification
import ../../src/verification/obligation/obligation_types
import ../../src/infrastructure/external_ir_materializer
import ../../src/verification/batch_uap/ir_pipeline_runner
import ../../src/verification/obligation/obligation_ir
import ../../src/verification/obligation/canonical_obligation_generator
import ../../src/core/types/smt_types
import ../../src/core/trusted/private/obligation_smt_lowering
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

proc main() =
  putEnv("AXIOM_STATE_DIR", getTempDir() / "ax_s6_probe2_state")
  let goldenRoot = currentSourcePath().parentDir().parentDir() / "golden" / "base36_subject"
  let mutantRoot = currentSourcePath().parentDir().parentDir() / "negative" / "base36_mutant_subject"
  let subjects = @[("GOLDEN", goldenRoot), ("MUTANT", mutantRoot)]
  for pair in subjects:
    let name = pair[0]
    let root = pair[1]
    echo "=== " & name & " ==="
    let s = synthFor(root)
    if not s.ok: continue
    let ve = s.entry
    # canonical directly
    let cres = executeCanonicalVerification(
      ve.funcDef, ve.entry.sourcePath, ve.entry.name, ve.entry.sourceContent,
      subjectRepoRoot = root, preSynthesisIrDigest = "", parseBound = ve.parseBound)
    echo "canonical: verdict=" & $cres.verdict & " success=" & $cres.success &
      " evidence=" & cres.evidence & " sealError=" & cres.sealError
    echo "  leanSourceHash=" & cres.leanSourceHash[0..7]
    # obligations dump
    let scopePolicy = defaultScopePolicy()
    let ogr = generateCanonicalObligations(ve.funcDef, scopePolicy)
    if ogr.kind == ogrGenerated:
      for i, obl in ogr.obligations.value:
        echo "obligation[" & $i & "] kind=" & $obl.kind & " subject=" & obl.subject &
          " prop=" & smtTermFor(obl.proposition, slQfBv)    # pipeline + smt script
    var memo = initTable[string, IrPipelineResult]()
    let pve = ValidatedIrEntry(entry: ve.entry, funcDef: ve.funcDef, parseBound: ve.parseBound)
    let res = runIrPipelineWithCas(pve, nil, memo, bpRequire, root)
    echo "pipeline: success=" & $res.success & " status=" & $res.verification.status &
      " evidence=" & res.verification.evidence
    if res.verifiedClaim.isSome:
      echo "claim: outcome=" & $res.verifiedClaim.get.outcome
    for i, rec in res.counterExample:
      echo "counterExample[" & $i & "]: " & rec

    echo "smtScript.len=" & $res.smtScript.len
    if res.smtScript.len > 0 and res.smtScript.len < 4000:
      echo res.smtScript
    else:
      echo res.smtScript[0 ..< min(3000, res.smtScript.len)]

when isMainModule:
  main()
