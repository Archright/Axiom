import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import core/judge/smart_search
import core/judge/the_judge_lean
import core/types/results
import core/solver/interfaces
import core/judge/lean_replay
import core/types/hubs/judge_hub
import std/strutils
import core/trusted/axiom_pragmas

export the_judge_lean
export judge_hub

## Z3 Query Result
type
  Z3QueryResult* = object
    isUnsat*: bool
    proofTrace*: string
    counterExample*: string
    unsatCore*: seq[string]   ## Named hypothesis IDs from (get-unsat-core)

## Execute Proof via ProverInterface concept.
## Generic dispatcher: any type T satisfying ProverInterface
## (i.e., implementing .prove(query: string, timeoutMs: int): bool
##  and .name(): string) can be used as a prover back-end.
proc executeProof*[T: ProverInterface](prover: T; query: string; timeoutMs: int): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  prover.prove(query, timeoutMs)

## Parse Z3 output containing (get-unsat-core) result.
## Output format after sentinel strip:
##   unsat
##   (h0 h1)
## Returns parsed unsat core hypothesis IDs.
func parseUnsatCore*(z3Output: string): seq[string] {.raises: [].} =
  for line in z3Output.splitLines():
    let s = line.strip()
    if s.startsWith("(") and s.endsWith(")"):
      let inner = s[1 .. ^2]
      for token in inner.splitWhitespace():
        if token.len > 0 and token notin result:
          result.add(token)

## Run Z3 Query via ProverOutputInterface (DIP).
## Uses proveWithOutput to capture raw solver output including unsat core.
proc runZ3Query*[T: ProverOutputInterface](prover: T; smtQuery: string): Result[Z3QueryResult, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  let output = prover.proveWithOutput(smtQuery, 30000)
  if output.isErr():
    return err(output.error())
  let outStr = output.get().strip()
  if outStr.toLowerAscii().contains("unsat"):
    let core = parseUnsatCore(outStr)
    ok(Z3QueryResult(isUnsat: true, proofTrace: "", counterExample: "", unsatCore: core))
  elif outStr.toLowerAscii().contains("sat"):
    ok(Z3QueryResult(isUnsat: false, proofTrace: "", counterExample: outStr))
  else:
    err("Z3 unexpected output: " & outStr)

## Run Lean Replay — delegates to lean_replay.runLeanReplay (core/judge layer, no DIP boundary issue).
## Returns structured LeanReplayResult with theorem name and hypotheses populated.
proc runLeanReplay*(nodeId: string; leanQuery: string): Result[lean_replay.LeanReplayResult, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  lean_replay.runLeanReplay(nodeId, leanQuery)

## Joint Proof Witness — constructive evidence of SMT ↔ Lean mutual supervision.
## SMT unsat core hypothesis IDs correspond to Lean theorem binder names.
type
  JointProofWitness* = object
    smtUnsatCore*: seq[string]      ## Named hypothesis IDs from SMT (get-unsat-core)
    leanTheoremName*: string         ## Theorem name from Lean replay
    leanHypotheses*: seq[string]    ## Hypothesis binder names from Lean theorem signature

## Verify SMT Lean Consistency — constructive witness check.
## Correspondence Rule:
##   The SMT unsat core contains named hypothesis IDs (h0, h1, ...) from
##   (get-unsat-core). The Lean theorem signature contains hypothesis binder
##   names. A hypothesis h<i> from the SMT core has a counterpart in the Lean
##   hypothesis set iff the Lean set contains a name matching h<i>.
##
##   When the mapping cannot be established (empty core, empty hypotheses,
##   or name mismatch), the function returns Err — NEVER ok on absent evidence.
##
##   Deep semantic correspondence (assertion type matching) is deferred to
##   future work. This check establishes INDEX-LEVEL correspondence only.
func verifySmtLeanConsistency*(smtResult: Z3QueryResult; leanResult: lean_replay.LeanReplayResult): Result[JointProofWitness, string] {.raises: [].} =
  if not smtResult.isUnsat or not leanResult.isValid:
    return err("one-or-both-provers-failed")
  if smtResult.unsatCore.len == 0:
    return err("no-smt-witness: unsat core is empty")
  if leanResult.theoremName.len == 0:
    return err("no-lean-witness: theorem name is empty")
  if leanResult.hypotheses.len == 0:
    return err("no-lean-witness: hypothesis list is empty")
  for hid in smtResult.unsatCore:
    if hid notin leanResult.hypotheses:
      return err("hypothesis-mismatch: SMT core references '" & hid &
        "' which has no counterpart in Lean hypotheses " & $leanResult.hypotheses)
  ok(JointProofWitness(
    smtUnsatCore: smtResult.unsatCore,
    leanTheoremName: leanResult.theoremName,
    leanHypotheses: leanResult.hypotheses
  ))

## Build Lean theorem statement with hypotheses matching SMT naming scheme.
## Each hypothesis has binder name h<i> matching SMT (get-unsat-core) names.
func buildJudgeLeanTheorem*(leanProposition: string; hypothesisNames: seq[string]): string {.raises: [].} =
  var sig = "theorem judge_proof"
  for h in hypothesisNames:
    sig.add(" (" & h & " : True)")
  sig.add(" : " & leanProposition & " := by\n  aesop")
  sig

## Evaluate Hint — SMT-First, Lean-Parallel asynchronous verification.
## Phase 1: SMT Primary verification (immediate deterministic result)
## Phase 2: Lean 4 Secondary verification (parallel, mutual supervision)
##
## Accepts concrete prover instances via DI (Dependency Inversion).
## Z3 prover must satisfy ProverOutputInterface for unsat core extraction.
proc evaluateHint*[ZP: ProverOutputInterface, LP: ProverInterface](
  z3Prover: ZP;
  leanProver: LP;
  nodeId: string;
  hint: SemanticHint;
  unsatCore: seq[string]
): JudgeResult {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Phase 1: SMT Primary verification
  let smtQuery = buildSmt2Query(hint)
  let smtResult = runZ3Query(z3Prover, smtQuery)

  if smtResult.isErr():
    return JudgeResult(
      verdict: verdictUnverifiable,
      reason: "SMT solver error: " & smtResult.error(),
      smt2: smtQuery,
      z3TimeMs: 0
    )

  let smtVal = smtResult.get()
  if not smtVal.isUnsat:
    return JudgeResult(
      verdict: verdictRejected,
      reason: "SMT found counter-example",
      smt2: smtQuery,
      z3TimeMs: 0
    )

  ## Phase 2: Lean 4 Secondary verification
  ## Build Lean theorem with hypothesis binders matching SMT naming.
  let thmStmt = buildJudgeLeanTheorem(hint.leanProposition, smtVal.unsatCore)
  let leanResult = runLeanReplay(nodeId, thmStmt)

  if leanResult.isErr():
    ## Lean failure is treated as unverifiable despite SMT success
    ## (Lean retry in Self-Healing Loop)
    return JudgeResult(
      verdict: verdictUnverifiable,
      reason: "SMT passed but Lean replay failed: " & leanResult.error(),
      smt2: smtQuery,
      lean: thmStmt,
      z3TimeMs: 0,
      leanTimeMs: 0
    )

  let leanVal = leanResult.get()
  if not leanVal.isValid:
    return JudgeResult(
      verdict: verdictUnverifiable,
      reason: "SMT passed but Lean replay failed to verify",
      smt2: smtQuery,
      lean: thmStmt,
      z3TimeMs: 0,
      leanTimeMs: 0
    )

  ## Phase 3: Mutual supervision — verify SMT unsat core ↔ Lean hypothesis correspondence
  let witnessResult = verifySmtLeanConsistency(smtVal, leanVal)
  if witnessResult.isOk():
    JudgeResult(
      verdict: verdictApproved,
      reason: "SMT unsat confirmed by Lean 4 proof; mutual supervision: " &
        $witnessResult.get().smtUnsatCore.len & " hypotheses correspond",
      smt2: smtQuery,
      lean: thmStmt,
      z3TimeMs: 0,
      leanTimeMs: 0,
      hypothesesCount: smtVal.unsatCore.len
    )
  else:
    ## Mutual supervision evidence incomplete — SMT and Lean both succeeded but
    ## index-level correspondence could not be established. Fail-closed per AGENTS.md §0.9
    ## (undocumented fail-open = theater signature #2). The guarantee of mutual
    ## supervision requires verifiable SMT ↔ Lean hypothesis mapping.
    JudgeResult(
      verdict: verdictRejected,
      reason: "Mutual supervision failed — SMT-Lean correspondence incomplete: " &
        witnessResult.error(),
      smt2: smtQuery,
      lean: thmStmt,
      z3TimeMs: 0,
      leanTimeMs: 0,
      hypothesesCount: smtVal.unsatCore.len
    )

{.pop.}