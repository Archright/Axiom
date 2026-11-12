import core/trusted/layer_declaration
axiomLayer "infrastructure"

import core/boundary/boundary_forwarding
import core/boundary/axiom_pragmas_boundary
export persona_interface
import core/boundary/results_boundary
import core/types/domain_types
import core/types/pipeline_core_types
from core/boundary/verification_interface import StageKind, StageStatus

type
  ScribeErrorKind* {.pure.} = enum
    ArtifactGenerationFailed
    IOError
    LlmConnectionFailed
  
  ScribeError* = object
    kind*: ScribeErrorKind
    msg*: string

let ctx = defaultPersonaCtx

## Scribe Persona — Layer 3: LLM Auto-formalization
## Isolates Leanstral synthesis from the pipeline orchestrator.

proc synthesizeLeanTheorem*(
  req: UniversalPipelineRequest;
  translation: UniversalTranslation;
  healedSource: string;
  seededInvariant: string
): Result[ScribeArtifact, ScribeError] {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  ## [impure: calls ctx.callLeanstral, ctx.logStage, runLeanReplay — I/O side effects]
  ## Phase 3: Scribe — Leanstral LLM synthesis for Lean 4 theorem generation.
  var artifact = ScribeArtifact()
  try:
    let slicedContext = extractSignatureAndContracts(healedSource, req.functionName)
    let archetype = determineArchetype(healedSource, req.functionName)
    let proofStrategy = case archetype
      of archIterative: "Use induction on the loop counter with the loop invariant."
      of archRecursive: "Use structural induction on the recursive data structure."
      of archLinear: "Use direct proof with pre/post condition contracts."
    let leanPrompt = "You are a formal verification assistant. Prove the following Lean 4 theorem for function " & req.functionName &
      " with invariant: " & seededInvariant & "\n" &
      "Function signature and contracts:\n" & slicedContext & "\n" &
      "Proof strategy: " & proofStrategy & "\n" &
      "IMPORTANT: Return ONLY valid Lean 4 code. Use ONLY Lean 4 core tactics (no Mathlib): rfl, simp, intro, apply, exact, rw, " &
      "induction, cases, assumption, constructor, calc, have, refine, omega." &
      " Do NOT use aesop, ring, linarith, smt, or tauto." &
      " Wrap your code in ```lean4 code blocks."
    let lsResult = ctx.callLeanstral(leanPrompt)
    ctx.logStage(skScribe, req.functionName, "Leanstral called: success=" & $lsResult.success, 0, (if lsResult.success: ssSucceeded else: ssFailed), nil)
    if lsResult.success and lsResult.theoremSource.len > 0:
      let replayResult = runLeanReplay(req.functionName, lsResult.theoremSource)
      if replayResult.isOk and replayResult.get().isValid:
        artifact.theoremSource = lsResult.theoremSource
        artifact.tacticTrace = lsResult.tacticTrace
        artifact.verified = true
        ctx.logStage(skScribe, req.functionName, "verified by Lean kernel", 0, ssSucceeded, nil)
    ok(artifact)
  except CatchableError as e:
    # axiom:theater-fix(DEBT#370) — fail-closed: return err instead of ok(emptyArtifact)
    ctx.logStage(skScribe, req.functionName, "synthesis exception", 0, ssFailed, nil)
    err(ScribeError(kind: ScribeErrorKind.ArtifactGenerationFailed, msg: e.msg))
