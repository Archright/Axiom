import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/application/persona_context
import core/contract/verification_interface
import core/judge/lean_replay
import core/results
import core/pipeline_core_types
import verification/leanstral_gateway
import verification/pipeline_lean_spec_inference
# axiomIoBoundary

func registerLeanstral*(ctx: var PersonaContext) {.raises: [].} =
  ctx.callLeanstral = proc(prompt: string): verification_interface.LeanstralResult {.closure, raises: [].} =
    let gw = leanstral_gateway.callLeanstral(prompt)
    verification_interface.LeanstralResult(
      success: gw.success,
      proof: "",
      theoremSource: gw.theoremSource,
      tacticTrace: gw.tacticTrace,
      premises: gw.premises,
      diagnostics: gw.diagnostics,
      rawOutput: gw.rawOutput,
      timedOut: gw.timedOut,
      confidence: if gw.success: 1.0 else: 0.0,
      error: if not gw.success: gw.diagnostics else: ""
    )

  ctx.runLeanReplay = proc(nodeId: string; leanSource: string): Result[LeanReplayResult, string] {.closure, raises: [].} =
    lean_replay.runLeanReplay(nodeId, leanSource)

  ctx.inferLeanSpec = proc(modulePath: string; functionName: string; translation: UniversalTranslation; sourceCode: string; activeInvariant: string; verificationVerdict: string): LeanSpecInference {.closure, raises: [].} =
    pipeline_lean_spec_inference.inferLeanSpec(modulePath, functionName, translation, sourceCode, activeInvariant, verificationVerdict)

{.pop.}
