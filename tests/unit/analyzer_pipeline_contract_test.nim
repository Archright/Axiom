## Contract tests for analyzer pipeline (analyzer_pipeline.nim).
##
## Verifies the I/O contracts of:
##   - initVerificationContext: parameter → initialized VerificationPipelineContext
##   - addStage / run: stage execution and early-abort behavior
##
## Tests focus on observable pipeline behavior — not internal stage logic.
## DEBT#012 — solver/analyzer test coverage.

import std/unittest
import std/sets


import core/domain_types
import verification/analyzer/analyzer_pipeline

# ─── initVerificationContext contracts ────────────────────────────────────

suite "initVerificationContext contract":
  test "shouldAbort defaults to false":
    let ctx = initVerificationContext("/tmp/certs", true, "", false)
    check ctx.shouldAbort == false

  test "enableSymbolic flag is stored":
    let ctxOn = initVerificationContext("/tmp/certs", true, "", false)
    let ctxOff = initVerificationContext("/tmp/certs", false, "", false)
    check ctxOn.enableSymbolic == true
    check ctxOff.enableSymbolic == false

  test "freezeGraphCache flag is stored":
    let ctx = initVerificationContext("/tmp/certs", true, "", true)
    check ctx.freezeGraphCache == true

  test "knownFunctions starts empty":
    let ctx = initVerificationContext("/tmp/certs", true, "", false)
    check ctx.knownFunctions.len == 0

  test "report starts with zero trusted functions":
    let ctx = initVerificationContext("/tmp/certs", true, "", false)
    check ctx.report.totalTrustedFunctions == 0

  test "tStart is positive (epoch time)":
    let ctx = initVerificationContext("/tmp/certs", true, "", false)
    check ctx.tStart > 0.0

  test "certDir matches input":
    let ctx = initVerificationContext("/tmp/certs", true, "", false)
    check ctx.certDir == "/tmp/certs"

  test "report.generatedAt is non-empty ISO timestamp":
    let ctx = initVerificationContext("/tmp/certs", true, "", false)
    check ctx.report.generatedAt.len > 0
    check 'T' in ctx.report.generatedAt

# ─── addStage / pipeline execution contracts ─────────────────────────────

suite "pipeline stage execution contract":
  test "addStage increments stage count":
    var pipeline = VerificationPipeline()
    check pipeline.stages.len == 0
    pipeline.addStage("s1", proc(ctx: var VerificationPipelineContext) = discard)
    check pipeline.stages.len == 1
    pipeline.addStage("s2", proc(ctx: var VerificationPipelineContext) = discard)
    check pipeline.stages.len == 2

  test "stages execute in order":
    var order: seq[string] = @[]
    var pipeline = VerificationPipeline()
    pipeline.addStage("first", proc(ctx: var VerificationPipelineContext) =
      order.add("first"))
    pipeline.addStage("second", proc(ctx: var VerificationPipelineContext) =
      order.add("second"))
    pipeline.addStage("third", proc(ctx: var VerificationPipelineContext) =
      order.add("third"))
    var ctx = initVerificationContext("/tmp/certs", true, "", false)
    pipeline.run(ctx, proc(step: string; report: VerificationReportSummary) = discard)
    check order == @["first", "second", "third"]

  test "pipeline stops when shouldAbort is set":
    var executed: seq[string] = @[]
    var pipeline = VerificationPipeline()
    pipeline.addStage("s1", proc(ctx: var VerificationPipelineContext) =
      executed.add("s1"))
    pipeline.addStage("s2", proc(ctx: var VerificationPipelineContext) =
      ctx.shouldAbort = true
      executed.add("s2"))
    pipeline.addStage("s3", proc(ctx: var VerificationPipelineContext) =
      executed.add("s3"))
    var ctx = initVerificationContext("/tmp/certs", true, "", false)
    pipeline.run(ctx, proc(step: string; report: VerificationReportSummary) = discard)
    check executed.len == 2
    check "s3" notin executed

  test "auditFn called after each stage with auditAfter=true":
    var auditedStages: seq[string] = @[]
    var pipeline = VerificationPipeline()
    pipeline.addStage("audited", proc(ctx: var VerificationPipelineContext) = discard,
      auditAfter = true)
    pipeline.addStage("silent", proc(ctx: var VerificationPipelineContext) = discard,
      auditAfter = false)
    pipeline.addStage("audited2", proc(ctx: var VerificationPipelineContext) = discard,
      auditAfter = true)
    var ctx = initVerificationContext("/tmp/certs", true, "", false)
    pipeline.run(ctx, proc(step: string; report: VerificationReportSummary) =
      auditedStages.add(step))
    check auditedStages.len == 2
    check auditedStages[0] == "audited"
    check auditedStages[1] == "audited2"

  test "stage can mutate context report":
    var pipeline = VerificationPipeline()
    pipeline.addStage("mutate", proc(ctx: var VerificationPipelineContext) =
      ctx.report.totalTrustedFunctions = 42
      ctx.report.certifiedExemptCount = 7)
    var ctx = initVerificationContext("/tmp/certs", true, "", false)
    check ctx.report.totalTrustedFunctions == 0
    pipeline.run(ctx, proc(step: string; report: VerificationReportSummary) = discard)
    check ctx.report.totalTrustedFunctions == 42
    check ctx.report.certifiedExemptCount == 7
