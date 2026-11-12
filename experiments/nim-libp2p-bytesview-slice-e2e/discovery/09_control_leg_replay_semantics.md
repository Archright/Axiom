## VERDICT (a): No — no non-defect leg ever executes the subject

The subject is compiled-and-run in exactly **one** place in the whole verification stack, and it is reachable only from a confirmed disproof.

**The only subject-execution path** (all in `src/verification/counterexample_replay.nim`):
- `nim c -r` harness command built at `counterexample_replay.nim:963` (`buildHarnessCmd`, def. `:935`)
- invoked at `counterexample_replay.nim:1017`, inside `runCounterexampleReplay` (def. `:1077`); the plain harness is rendered at `:999` (`renderReplayHarness`, def. `:542`)
- `runCounterexampleReplay` is called from exactly one place: `counterexample_replay.nim:1346`, inside `replayConfirmedDisproof` (def. `:1252`) — documented as "the single entry the pipeline drives after a P4 promotion" (`counterexample_replay.nim:36-40`)

**The gate** — `src/verification/batch_uap/ir_pipeline_runner.nim:1605-1610`:
```nim
if result.verification.status == vsDisproved and
   result.provenance != vpInductiveLoop and
   result.verification.model.len > 0:
  let replay = replayConfirmedDisproof(subjectRepoRoot, ve.entry.sourcePath, ...)
```
`vsDisproved` is minted only on P4 `cvConfirmed` promotion (`ir_pipeline_runner.nim:1350-1361`, `finalizeVerdict(makeCandidateCounterexample(...), cv)`). Contract language: `docs/spec/counterexample_replay_adapter.md:32` — "발동 조건: cvConfirmed 승격(vsDisproved) … 레인 게이트: `verification.status == vsDisproved ∧ provenance ≠ vpInductiveLoop ∧ model 비어있지 않음`".

**Other call sites are tests only**: `renderReplayHarness` / `buildHarnessCmd` / `replayConfirmedDisproof` outside the module are only in `tests/unit/test_counterexample_replay.nim`, `test_sidecar_binding.nim`, `test_base36_cout_binding.nim`, `test_toml_d2_agent_binding.nim`. The Rust lane has the same shape (replay only for a refuting/SAT candidate: `src/verification/rust_rust_pipeline.nim:422, 894`).

⇒ **UNSAT (control), `certZ3Candidate`, and VERIFIED legs never compile or run the subject.** There is no code path that executes it for those outcomes. The critic is correct on this point.

## (b) The control's actual function: injection guard (model-level), not subject observation

**How the control is built** (same machinery as the defect, `src/cli/axiom_engine.nim`):
- carrier body = the materialized original body, unchanged (`:2756`); params = the one model variable (`:2769`)
- pre = `length == 2`; post = `result == 1` with `result` β-spliced **exactly once** onto a fresh clone of the original body, fail-closed on splice count + free-variable guard (`:2770-2790`)
- the control rides under its **own** name (not wave-faced): "The CONTROL carrier rides under its own name: its UNSAT is the differential's spec-injection guard" (`:2850-2858`; same wording for the d2 lane at `:2630-2639`)

**What the solver actually proves** (`src/core/trusted/private/ir_to_smt_chunk3.nim:338-341, 377-383`):
```
(assert (= length 2))
(assert (let ((result carrier_impl length)) (not (= result 1))))   ; impl = (length*179) div 277
```
i.e. UNSAT ≡ *∄ length: length = 2 ∧ ¬(((length·179) div 277) = 1)* — a fact about the **translated body plus the injected pre/post**, never about the subject's runtime.

**What a control SAT would catch** (the mis-wiring it is designed to indict):
| mis-wiring | why the control flips to SAT |
|---|---|
| β-splice mis-bound (`result` left as a free var instead of the body) | query becomes `length=2 ∧ ¬(result=1)` → SAT (result=0) |
| pre binding lost / wrong instance | drop `length=2` → length=0 gives `0 ≠ 1` → SAT; wrong pre → instance mismatch → SAT |
| wrong body / stale-carrier marshaling (carrier body ≠ subject body) | arithmetic mismatch at the pinned instance → SAT |

Contract: "A control SAT would indict the spec injection, **not the subject**" (`docs/spec/nim_stew_base36_sidecar_contract.md:80`); and it would then surface exactly like a defect: SAT → P4 `cvConfirmed` → `vsDisproved` → replay → BUG_FOUND payload → node `failed` → exit 1 (`experiments/sidecar-adoption-e2e/ACCEPTANCE.md:49`; frozen as **FAIL** at `FREEZE.md:117`).

**Important correction to the critic's framing:** the eligibility gate does *not* reject tautological/vacuous claims. `src/verification/obligation/candidate_eligibility.nim` rule F (`:205-221`, `:278-292`, `:483-507`) covers only `okSafetyDiv` obligations of the form `¬(k == 0)` (constant-divisor / `¬(0==0)`), decided by IR shape with no solver; `classifyAndGenerate` (`:118-142`) checks only obligation kind + admissibility/fragment boundary. A *claim*-shaped tautology (e.g. the d2 lane's control post `forbid == forbid`, `counterexample_replay.nim:1238-1242`) is not rejected there — it simply solves to UNSAT. The T3 pre-tautology check (`ir_pipeline_runner.nim:1069-1089`, `src/verification/ax_tautology.nim:24-52`) rejects a candidate whose **precondition** is a tautology; `length == 2` is not one. So the control's UNSAT is *not* a "rejection" — it is an affirmative solver result whose only purpose is to witness that the injection was wired correctly.

## (c) Precedent evidence: no precedent ever claimed subject execution for a control leg

- `experiments/sidecar-adoption-e2e/ACCEPTANCE.md:53` — "**Injection guard held: control UNSAT (unproven, as expected).**"; §3 (`:47-51`) lists only routing, `dual-declined`, absence from the 3 FAIL rows, vault row `certZ3Candidate` (no `certRed`), evidence-CAS byte-identity; `:49` "a control SAT would have surfaced exactly like the defect leg (payload + FAIL row)". Final table `:178` — "control | injection guard held — control UNSAT: no counterexample…".
- `experiments/sidecar-adoption-e2e/runs/d1_stderr.log` — control: `:21` `[dual-declined] decodedLength_sidecar_control …`, `:22` `[ir-cas] MISS func=decodedLength_sidecar_control …`, **no `[ce-replay]` line**; the only `[ce-replay]` is `:26` for the defect carrier ("replay agreed; BUG_FOUND payload assembled (13 records)").
- `experiments/sidecar-adoption-e2e/FREEZE.md:106` — control expectation is "control carrier solver **UNSAT** (injection guard) — recorded from trajectory/manifest rows of the same run"; `:126` "Control evidence: extracted from the SAME runs' trajectory/manifest rows". The "no replayed subject execution" criterion (`FREEZE.md:116` → INCOMPLETE) is scoped to the **defect** verdict.
- `docs/evidence/nim_stew_base36_cout_slice_2026-10-10.md` — contains **no control leg at all** (zero hits for "control"); it is the C_out single-origin carrier slice. Its honesty caveat `:67` is directly on point: "`replay.verdict=rvAgree`는 `decode` 실행 정확성을 검증하지 **않는다** — 캐리어 산술(`decodedLength(3) = 1`)의 실측 재현만을 진술하며, 어댑터는 관찰자로서 권위가 없다".

⇒ No precedent claims control-leg subject execution. The precedents claim **solver-level UNSAT only**, consistently with the contract's own non-claim (`config/spec/nim_stew_base36_sidecar.json:52`): "NOT a claim that the replay validates the sizing formula or the inferred law in general — it observes ONE pinned input per case on the pinned subject bytes"; `docs/spec/nim_stew_base36_sidecar_contract.md:90` repeats it.

## (d) VERIFIED outcome: purely model/kernel level

`docs/spec/nim_stew_base32_rem_binding_contract.md:65` — "Single verdict — VERIFIED only via `canonicalLeanKernelCheck` → `bindReceipt` → `evaluate` (non-empty axiom allowlist + `spForbid`)". `:53` — the rule-F division guards "never constitute the verified proposition (measured: the guard alone reaches Z3 and its UNSAT yields only `certZ3Candidate` — **never VERIFIED**)"; A5 (`:84`) — "solver UNSAT alone cannot promote — the certificate stays `certZ3Candidate`". Implementation: `executeCanonicalVerification` (`src/verification/obligation/canonical_verification.nim:664, 721, 1591, 1661`) renders Lean source and runs the Lean kernel check — **no subject execution, no harness, no `nim c -r`**. `src/verification/obligation/verified_fragment.nim:16-23` makes the same boundary explicit: "The actual proof boundary is established only at execution time by `CanonicalLeanEvidence`" (i.e. Lean-kernel acceptance, not subject execution).

## Caveats worth relaying

1. The critic is right that the control leg's UNSAT is model-level and says nothing about the subject's runtime behavior — but it is not a *syntactic* tautology in the sidecar lane (unlike the d2 lane's `forbid == forbid` control post). It is a **contingent** model-level fact: it holds only if the pre binding and the β-splice onto the original body are correct, which is exactly what makes it an injection guard.
2. The control does **not** validate translation↔runtime equivalence of the body (a body-translation divergence would be invisible to it). Only the defect leg's replay observes the subject's actual behavior. So the honest statement is: the control validates the *spec injection*, not the *subject*.
3. Ambiguity: I found no value parameter named `b` in this lane. The sidecar binds only `length` (`valueParam`, `config/spec/nim_stew_base36_sidecar.json:8`); the `btype: typedesc[Base36Types]` formal is a **static discriminator, not a value parameter** and is never solver-bound (`docs/spec/nim_stew_base36_sidecar_contract.md` §4 D3, §5; `src/cli/axiom_engine.nim:2757-2768`). So "executing the subject at b=0" does not correspond to any leg; if the critic meant the model-bound instance (`length = 2`), the verdict above stands unchanged.