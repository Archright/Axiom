import std/[options, strutils]
import core/ir/ir_types
import core/ir/ir_to_lean as core_ir_to_lean
import core/trusted/effect_bridge
import core/verifier/legislator
import cas_promote
import verification/lean_repl_bridge as lrb

proc runVerificationPipeline*(ir: AxiomIRNode): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let tier1Result = generateOptimalTactic(ir)
  if tier1Result.isSome:
    return true

  let baseLeanCodeOpt = core_ir_to_lean.irToLeanRefinedDefinition(ir)
  if baseLeanCodeOpt.isNone:
    let z3Result = lrb.runZ3Bmc(ir, kBound = 20)
    return lrb.handleZ3BmcResult(ir, lrb.classifyZ3BmcResult(z3Result), ($z3Result).toLowerAscii())
  let baseLeanCode = baseLeanCodeOpt.get
  let inductiveTactic = tryInductiveTactics(ir, baseLeanCode)
  if inductiveTactic.isSome:
    let artifact = generateVerificationArtifact(ir, inductiveTactic.get())
    let casHash = promoteToGitCAS(artifact)
    echo "[CAS] Promoted verification artifact for ", ir.name, ": ", casHash
    return true

  let llmTactic = callLeanstralWithTimeout(ir)
  if llmTactic.isSome:
    let artifact = generateVerificationArtifact(ir, llmTactic.get())
    let casHash = promoteToGitCAS(artifact)
    echo "[CAS] Promoted verification artifact for ", ir.name, ": ", casHash
    return true

  let z3Result = lrb.runZ3Bmc(ir, kBound = 20)
  # Propagate the Z3 BMC result instead of masking verification failure as success.
  return lrb.handleZ3BmcResult(ir, lrb.classifyZ3BmcResult(z3Result), ($z3Result).toLowerAscii())
