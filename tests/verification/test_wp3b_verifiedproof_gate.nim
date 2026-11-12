import std/[tables, options, strutils, json]
import ../../src/core/results
import ../../src/core/symbolic/global_symbol_graph_types
import ../../src/core/types/hubs/sorter_node_id
import ../../src/core/orchestrator/orchestrator_report_types
import ../../src/verification/proof_universe_commit

# WP3-b Change 3 — tcVerifiedProof positive gate regression tests.
#
# Goal: a `tcVerifiedProof` journal entry is structurally permitted ONLY when
# the run produced kernel-tier, claim-associated verified nodes. Any other
# outcome (Vacuous, Unsupported, Unknown, NoObligation, or Z3-only candidate)
# must yield an empty verified-node set so the VerifiedProof commit is skipped.
#
# These tests exercise the pure gate helpers:
#   isKernelVerifiedEvidence / claimAssociatedNodeId / verifiedCommitEvidence
#   / canonicalVerifiedNodes
# directly. Integration (journal routing, external subject immutability,
# determinism) is verified by the WP3-b runtime checks (wp3b-result.md).

var failures = 0
proc expect(cond: bool; msg: string) =
  if not cond:
    inc failures
    echo "  FAIL: " & msg

proc nodeReport(nodeId: string; status: OrchestrationNodeStatus; tier: string): OrchestrationNodeReport =
  OrchestrationNodeReport(
    nodeId: SorterNodeId(nodeId),
    status: status,
    assuranceTier: tier,
    tierResolution: "resolved"
  )

proc graphWith(modulePaths: openArray[string]): GlobalSymbolGraph =
  result = GlobalSymbolGraph(
    symbols: initTable[string, SymbolNode](),
    edges: @[],
    byTarget: initTable[string, seq[ReferenceEdge]]()
  )
  for mp in modulePaths:
    let stem = moduleNameFromPath(mp)
    result.symbols[stem & ".symbol"] = SymbolNode(
      qualifiedName: stem & ".symbol",
      kind: skProc,
      modulePath: mp,
      astNode: nil,
      visibility: "public"
    )

echo "=== WP3-b tcVerifiedProof positive gate regression tests ==="

# --- T1a: kernel-tier (lean-verified) + claim-associated node passes the gate ---
block:
  let graph = graphWith(["stew/base36.nim"])
  let reports = @[
    nodeReport("stew/base36.nim::decodedLength", orchestrationVerified, "lean-verified")
  ]
  let ev = verifiedCommitEvidence(reports, graph)
  expect(ev.len == 1, "kernel-tier associated node admitted (got " & $ev.len & ")")
  if ev.len == 1:
    expect(ev[0].nodeId == "stew/base36.nim::decodedLength", "nodeId preserved")
    expect(ev[0].modulePath == "stew/base36.nim", "modulePath subject-relative preserved")
    expect(ev[0].functionName == "decodedLength", "functionName extracted")
    expect(ev[0].assuranceTier == "lean-verified", "assuranceTier preserved")
  expect(isKernelVerifiedEvidence(reports[0]), "isKernelVerifiedEvidence true for lean-verified")
  echo "T1a PASSED: kernel-tier associated node admitted"

# --- T1b: Z3-only (z3-verified) even when orchestrationVerified must NOT pass ---
block:
  let graph = graphWith(["stew/base36.nim"])
  let reports = @[
    nodeReport("stew/base36.nim::decodedLength", orchestrationVerified, "z3-verified")
  ]
  expect(not isKernelVerifiedEvidence(reports[0]), "z3-verified is NOT kernel evidence")
  let ev = verifiedCommitEvidence(reports, graph)
  expect(ev.len == 0, "z3-only candidate excluded from verified nodes (got " & $ev.len & ")")
  echo "T1b PASSED: z3-only candidate excluded (no false VerifiedProof)"

# --- T2: empty nodeReports (Vacuous/NoObligation outcome) -> empty gate ---
block:
  let graph = graphWith(["stew/base36.nim"])
  let ev = verifiedCommitEvidence(@[], graph)
  expect(ev.len == 0, "empty run yields no verified nodes")
  echo "T2 PASSED: empty outcome yields empty verified set"

# --- T3: node NOT claim-associated (module absent from graph) is discarded ---
block:
  let graph = graphWith(["stew/base36.nim"])
  let reports = @[
    nodeReport("stew/endian2.nim::swapEndian", orchestrationVerified, "lean-verified")
  ]
  let ev = verifiedCommitEvidence(reports, graph)
  expect(ev.len == 0, "module absent from graph universe is discarded (got " & $ev.len & ")")
  let (mp, fn) = claimAssociatedNodeId(reports[0], graph)
  expect(mp.len == 0 and fn.len == 0, "claimAssociatedNodeId empty for unknown module")
  echo "T3 PASSED: non-associated node discarded (claim association enforced)"

# --- T4: orchestrationVerified but assuranceTier "" / none -> excluded ---
block:
  let graph = graphWith(["stew/base36.nim"])
  let reports = @[
    nodeReport("stew/base36.nim::decodedLength", orchestrationVerified, ""),
    nodeReport("stew/base36.nim::otherFn", orchestrationVerified, "none")
  ]
  let ev = verifiedCommitEvidence(reports, graph)
  expect(ev.len == 0, "verified status with empty/none tier excluded (got " & $ev.len & ")")
  echo "T4 PASSED: verified-but-unresolved-tier nodes excluded"

# --- T5: canonicalVerifiedNodes dedupes + byte-lex sorts deterministically ---
block:
  let graph = graphWith(["stew/a.nim", "stew/b.nim"])
  let reports = @[
    nodeReport("stew/b.nim::fB", orchestrationVerified, "dual-verified"),
    nodeReport("stew/a.nim::fA", orchestrationVerified, "lean-verified"),
    nodeReport("stew/b.nim::fB", orchestrationVerified, "dual-verified")   # duplicate
  ]
  let ev = verifiedCommitEvidence(reports, graph)
  let canon = canonicalVerifiedNodes(ev)
  expect(canon.len == 2, "duplicates removed (got " & $canon.len & ")")
  if canon.len == 2:
    expect(canon[0].nodeId == "stew/a.nim::fA", "byte-lex first is fA (got " & canon[0].nodeId & ")")
    expect(canon[1].nodeId == "stew/b.nim::fB", "byte-lex second is fB")
  # Repeat for determinism
  let canon2 = canonicalVerifiedNodes(ev)
  expect(canon.len == canon2.len, "canonical length deterministic")
  if canon.len == canon2.len:
    for i in 0 ..< canon.len:
      expect(canon[i].nodeId == canon2[i].nodeId, "order deterministic at index " & $i)
  echo "T5 PASSED: dedupe + byte-lex sort deterministic"

# --- T6: kernel-tier dual-verified admitted, only Axiom-support-origin graph ---
block:
  # A subject graph should NOT contain Axiom-support modules. When a support
  # function reports kernel-verified but its module is absent from the subject
  # universe graph, it must be discarded (claim association).
  let graph = graphWith(["stew/base36.nim"])
  let reports = @[
    nodeReport("core/utils/normalize.nim::normalizeMaxWorkers", orchestrationVerified, "dual-verified")
  ]
  let ev = verifiedCommitEvidence(reports, graph)
  expect(ev.len == 0, "Axiom-support origin not present in subject universe is discarded (got " & $ev.len & ")")
  echo "T6 PASSED: support-origin not in subject universe discarded"

# --- T7: mixed report — only the kernel-tier associated node survives ---
block:
  let graph = graphWith(["stew/base36.nim"])
  let reports = @[
    nodeReport("stew/base36.nim::decodedLength", orchestrationVerified, "lean-verified"),
    nodeReport("stew/base36.nim::encode", orchestrationVerified, "z3-verified"),
    nodeReport("stew/base36.nim::decode", orchestrationProofFailed, "none"),
    nodeReport("src/core/kernel.nim::kernelFn", orchestrationVerified, "dual-verified")
  ]
  let ev = verifiedCommitEvidence(reports, graph)
  expect(ev.len == 1, "only the kernel-tier associated node survives (got " & $ev.len & ")")
  if ev.len == 1:
    expect(ev[0].nodeId == "stew/base36.nim::decodedLength", "survivor is decodedLength")
  echo "T7 PASSED: mixed report filtered to single kernel-tier associated node"

echo ""
if failures == 0:
  echo "=== All WP3-b verifiedproof gate tests PASSED ==="
else:
  echo "=== " & $failures & " WP3-b verifiedproof gate test(s) FAILED ==="
  quit(1)
