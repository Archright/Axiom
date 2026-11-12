## PersonaContext Wiring Test — deterministic replacement for persona_bridge PBT.
##
## Per ADR-014: instead of generating random PersonaBridge values, we verify
## that the application-layer composition root wires every callback.
##
## DEBT#247: Removed 7 compile-only tests (runNimCheck) — §0.7 violation.
## Compiler-guaranteed behaviors (module compilation) do not get tested.

import unittest

import core/application/persona_context
import core/application/persona_context_init

suite "persona context wiring":
  test "initPersonaContext wires all callbacks":
    let ctx = initPersonaContext()
    check ctx.callLeanstral != nil
    check ctx.runLeanReplay != nil
    check ctx.runNegativeInvariantSearch != nil
    check ctx.runLayer1Bmc != nil
    check ctx.runSwatStage != nil
    check ctx.runKInductionStage != nil
    check ctx.z3CheckViaProcess != nil
    check ctx.runCegarLoop != nil
    check ctx.proveWithFixedpoint != nil
    check ctx.encodeProvedInvariantsSmtlib2 != nil
    check ctx.loadPromotionFromProofVault != nil
    check ctx.syncRecoveredSourceToModule != nil
    check ctx.writeReproductionArtifact != nil
    check ctx.writeBddFeature != nil
    check ctx.logStage != nil
    check ctx.analyzeVariableIntervalsAtLoopHeader != nil
    check ctx.detectInductionVariables != nil
    check ctx.deriveInvariantCandidates != nil
    check ctx.extractLoopConditionFromHeader != nil
    check ctx.runSelfHealingLoop != nil
    check ctx.runLeanProofRefinementLoop != nil
    check ctx.inferLeanSpec != nil
