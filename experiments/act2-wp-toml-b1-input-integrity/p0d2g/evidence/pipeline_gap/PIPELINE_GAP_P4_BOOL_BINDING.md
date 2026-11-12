# PIPELINE GAP — P4 re-validation cannot promote bool-returning BMC SAT (p0d2g defect leg)

Date: 2026-10-17 · Branch: `followup/d2-agent-vertical` · Binding commit: `efc90940d`
Status: **NOT FIXED** — root cause is in GENERIC pipeline code (`counterexample_validator.nim`),
outside the p0d2g binding's authority. Documented per the slice constraint
("if the root cause is in GENERIC pipeline code, DO NOT fix it: document it as a
pipeline-side gap"). No tracked file was modified. No commit was made.

## Symptom (Phase E, `runs/e_defect.{out,err,exit}` + `state_e1/`; cold rerun `state_e3` identical)

BMC lane reaches SAT with a real counterexample witness, but:

- no `[ce-replay]` line for `d2StringGateReject`/`scanString`,
- `nodeReports[].counterexample = null`, model never surfaces,
- final verdict `psFail provenance=solverMethod=smBMC,provenance=pkNone`, vault `certRed`.

## Root cause (precise)

`src/verification/counterexample_validator.nim:74-79` — `preconditionSmt` asserts
bool-typed `model.semantic.initExprs` entries as **bare conditions** ("CHC models"),
while value-typed ones become **equalities** ("the one-state BMC contract model binds
each parameter to itself and `result` to the actual body").

The C20 one-state model (`src/verification/batch_uap/ir_pipeline_runner.nim:456-457`,
`lowerPostconditionModel`) binds `result`'s initExpr to `funcDef.body`. For a
**bool-returning** funcDef that binding is bool-typed → it takes the condition branch →
the P4 script asserts the carrier **body** (`gate(c)`) as a precondition.

Captured P4 script (probe, `tmp/z3shim` one-shot discharge capture — verbatim):

```smt2
(declare-fun state ((_ BitVec 64) Bool) Bool)
(declare-const c (_ BitVec 64))
(declare-const result Bool)
(assert (and (= c c) (or (or (or (= c #x0000000000000008) (= c #x0000000000000010)) (= c #x000000000000001F)) (= c #x000000000000007F))))
(assert (not (= (or (or (or (= c #x0000000000000008) (= c #x0000000000000010)) (= c #x000000000000001F)) (= c #x000000000000007F)) (or (or (bvsle c #x0000000000000008) (and (bvsge c #x000000000000000A) (bvsle c #x000000000000001F))) (= c #x000000000000007F)))))
(check-sat)
```

Z3: `unsat` → `validateCounterexample` returns `cvSpurious`
(`counterexample_validator.nim:123-124` → `:131-132`) → `finalizeVerdict` preserves the
candidate (`:146-147`) → `vsDisproved` never reached → the S4-S5 replay trigger
(`ir_pipeline_runner.nim:1439-1441`, requires `vsDisproved` + non-empty model) never fires.

The assertion `gate(c) = true` **excludes exactly the defect witnesses** (the bug lives at
`gate(c)=false ∧ forbid(c)=true` — e.g. c=7 or the actually-returned witness c=24). The P4
is supposed to re-validate the SOLVER's witness; instead it asserts the negation of the
witness's body value. The binding-equality form `(= result <gate>)` (what the value-typed
branch emits) is the correct translation and leaves the gap members SAT.

Provenance: the bool branch landed in `05055aab5` (2026-10-08, S6-S8 projection chain) —
pre-existing generic C20 code, NOT part of `efc90940d` (which did not touch
`counterexample_validator.nim`).

## Why the precedents promoted but p0d2g cannot

- C_out / base32 rem / base36 carriers: **non-bool** bodies (`length mod 8`,
  `1 + code div 128`, sizing K) → result binding takes the EQUALITY branch → P4 correct
  → cvConfirmed reachable. p0d2f's `d2HexEscapeAppendLen(code: int): int` likewise.
- p0d2g's carriers are the first **bool-returning** carriers (decision-predicate claim
  `reject(c) = forbid(c)`). Every bool-returning BMC SAT whose counterexample requires
  `body = false` (the canonical "returns true when spec says false" bug shape) is
  promotion-dead through this path.

## What is NOT the cause (verified)

- Parse-bound "unmeasured" (`EA_UNSUPPORTED ckVarTy` on `scanSingleLineString`'s
  `var T` signature — honest EA measurement carried by the binding, contract §3):
  only declines the canonical SEAL; the BMC lane decides, as designed. Not on the
  model/P4 path.
- Model capture: the BMC `(get-model)` reply DOES bind c
  (`sat\n(define-fun c () (_ BitVec 64) #x0000000000000018)` — 24, a genuine gap member).
- Exact-input replay binding: works (`parseModelBindings` finds `c`; the bespoke
  template path engages — the only probe failure was the stub's missing git identity).
- Unit tests (31/31) already prove the replay agreement logic given a model.

## Pipeline-side fix shape (NOT applied — owner decision)

`preconditionSmt` must not conflate the two roles of `VerificationModel.semantic.initExprs`
(CHC entry conditions vs C20 one-state entry bindings). Minimal discriminator available
today: the C20 model sets `sem.resultStateName = some("result")` and an identity
transition (`ir_pipeline_runner.nim:460-462`); its index-aligned initExprs are bindings by
construction, so bool-typed entries should be asserted as
`(= <states[i].name> <expr>)` there (CHC loop models keep the bare-condition reading).
Fixing it makes `cvConfirmed` — and therefore the whole SAT → model → P4 → vsDisproved →
replay chain — reachable for bool carriers without touching the binding.

## Probe evidence (this directory / tmp)

- `tmp/p4probe.nim` — direct probe: synthesizes the real carriers via the engine,
  lowers `lowerPostconditionModel`, calls `validateCounterexample` (shimmed z3Path for
  the one-shot capture), then runs the full `runIrPipelineWithCas` lane unshimmed.
  Output: `P4-VERDICT: cvSpurious`; E2E `vsInconclusive/rkCandidateCounterexample/smBMC/vpNone
  model.len=64 counterExample.len=0` — byte-for-byte the Phase E signature.
- `tmp/z3shim/z3` — observation-only z3 wrapper (PATH shim). NOTE: a PATH-shimmed run
  breaks the persistent-session transport (`z3ExecPersistent` waits on stdin that the
  shim cannot forward) — `runs/probe2.err` (pre-flight "Z3 solver dysfunctional") and
  `runs/probe3.*` + `state_probe2/` + `vault_probe2/` (all entries `smNone`) are
  SHIM-TAINTED artifacts kept only as the record of that incompatibility. Do not read
  them as pipeline behavior. The one-shot discharge capture above is unaffected.

## Binding-side options considered and rejected

Reshaping the carrier to a 0/1 bitvec result (to route the P4 into the equality branch)
would change the adopted claim's meaning (`reject(c) = forbid(c)` over booleans), break
the pinned claim shape (contract §4 D3) and the replay postcondition derivation
(`d2AgentReplayPostcondition` reads the bool forbid side), and would leave the generic
defect armed for the next bool-shaped binding — a workaround, not a cause fix.
