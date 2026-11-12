import std/unittest
import std/sets
import std/tables
import compiler/ast
import verification/analyzer/analyzer_pipeline
import verification/analyzer/stage_adapters
import core/types/verification_types
import core/types/certificate_types
import core/symbolic/global_symbol_graph_types

suite "stage_adapters - stageCertifiedExempt":
  test "sets certifiedExemptCount to zero":
    var ctx = initVerificationContext("/tmp/certs", false, "", false)
    ctx.report.certifiedExemptCount = 42
    check ctx.report.certifiedExemptCount == 42
    stageCertifiedExempt(ctx)
    check ctx.report.certifiedExemptCount == 0

  test "sets certifiedExemptCount to zero when already zero":
    var ctx = initVerificationContext("/tmp/certs", false, "", false)
    ctx.report.certifiedExemptCount = 0
    stageCertifiedExempt(ctx)
    check ctx.report.certifiedExemptCount == 0

  test "idempotent multiple calls":
    var ctx = initVerificationContext("/tmp/certs", false, "", false)
    ctx.report.certifiedExemptCount = 100
    stageCertifiedExempt(ctx)
    check ctx.report.certifiedExemptCount == 0
    stageCertifiedExempt(ctx)
    check ctx.report.certifiedExemptCount == 0

  test "deterministic result independent of other context state":
    var ctx1 = initVerificationContext("/tmp/certs", false, "", false)
    var ctx2 = initVerificationContext("/tmp/certs", false, "", false)
    ctx1.report.totalTrustedFunctions = 50
    ctx2.report.totalTrustedFunctions = 50
    ctx1.report.certifiedExemptCount = 10
    ctx2.report.certifiedExemptCount = 99
    stageCertifiedExempt(ctx1)
    stageCertifiedExempt(ctx2)
    check ctx1.report.certifiedExemptCount == 0
    check ctx2.report.certifiedExemptCount == 0

suite "stage_adapters - stageInfluenceGate":
  test "sets blockingFailure and shouldAbort when totalTrustedFunctions is zero":
    var emptyGraph = GlobalSymbolGraph(
      symbols: initTable[string, SymbolNode](),
      edges: @[],
      byTarget: initTable[string, seq[ReferenceEdge]]()
    )
    var ctx = initVerificationContext("/tmp/certs", false, "", false)
    ctx.graph = emptyGraph
    ctx.report.certificates = @[]
    ctx.report.totalTrustedFunctions = 0
    ctx.report.blockingFailure = false
    ctx.shouldAbort = false
    stageInfluenceGate(ctx)
    check ctx.report.blockingFailure == true
    check ctx.shouldAbort == true

  test "does not set blockingFailure when totalTrustedFunctions is positive":
    var graph = GlobalSymbolGraph(
      symbols: initTable[string, SymbolNode](),
      edges: @[],
      byTarget: initTable[string, seq[ReferenceEdge]]()
    )
    var symNode = SymbolNode(
      qualifiedName: "test.mod.foo",
      kind: skFunc,
      modulePath: "test/mod.nim",
      astNode: nil,
      visibility: "public"
    )
    graph.symbols["test.mod.foo"] = symNode
    var ctx = initVerificationContext("/tmp/certs", false, "", false)
    ctx.graph = graph
    ctx.report.certificates = @[]
    ctx.report.totalTrustedFunctions = 1
    ctx.report.blockingFailure = false
    ctx.shouldAbort = false
    stageInfluenceGate(ctx)
    check ctx.report.blockingFailure == false
    check ctx.shouldAbort == false

  test "updates graph hash and counts from empty graph":
    var emptyGraph = GlobalSymbolGraph(
      symbols: initTable[string, SymbolNode](),
      edges: @[],
      byTarget: initTable[string, seq[ReferenceEdge]]()
    )
    var ctx = initVerificationContext("/tmp/certs", false, "", false)
    ctx.graph = emptyGraph
    ctx.report.certificates = @[]
    ctx.report.totalTrustedFunctions = 0
    let initialHash = ctx.report.currentGraphHash
    stageInfluenceGate(ctx)
    check ctx.report.currentGraphHash != initialHash

  test "computes missingCertificates correctly from graph":
    var graph = GlobalSymbolGraph(
      symbols: initTable[string, SymbolNode](),
      edges: @[],
      byTarget: initTable[string, seq[ReferenceEdge]]()
    )
    for i in 0..<5:
      var symNode = SymbolNode(
        qualifiedName: "test.mod.fn" & $i,
        kind: skFunc,
        modulePath: "test/mod.nim",
        astNode: nil,
        visibility: "public"
      )
      graph.symbols["test.mod.fn" & $i] = symNode
    var ctx = initVerificationContext("/tmp/certs", false, "", false)
    ctx.graph = graph
    ctx.report.certificates = @[]
    stageInfluenceGate(ctx)
    check ctx.report.totalTrustedFunctions == 5
    check ctx.report.missingCertificates == 5
    check ctx.report.symbolCount == 5

  test "does not set blockingFailure when graph has proc symbols":
    var graph = GlobalSymbolGraph(
      symbols: initTable[string, SymbolNode](),
      edges: @[],
      byTarget: initTable[string, seq[ReferenceEdge]]()
    )
    var symNode = SymbolNode(
      qualifiedName: "test.mod.foo",
      kind: skProc,
      modulePath: "test/mod.nim",
      astNode: nil,
      visibility: "public"
    )
    graph.symbols["test.mod.foo"] = symNode
    var ctx = initVerificationContext("/tmp/certs", false, "", false)
    ctx.graph = graph
    ctx.report.certificates = @[]
    stageInfluenceGate(ctx)
    check ctx.report.blockingFailure == false
    check ctx.shouldAbort == false