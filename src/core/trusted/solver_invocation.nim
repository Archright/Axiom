import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/strutils
import core/crypto/hash_kernel
import core/proof/proof_budget
import core/trusted/axiom_pragmas_lite
import core/types/solver_types

const
  Z3PinnedRandomSeed* = 42
  ## SMT-LIB 2.7 §4.1.7: `:random-seed 0` means the solver MAY use a different
  ## seed on every run of the same script, so 0 is the opt-OUT value. A
  ## non-zero seed is the only way the recorded option set can promise
  ## run-to-run reproducibility at all.

type
  SolverInvocation* = object
    scriptDigest*: string
    solverIdentity*: string
    solverVersion*: string
    solverOptionsDigest*: string
    ## sha256Hex of the solver executable actually handed the problem. Empty on
    ## records written before binary identity was captured — emptiness is
    ## therefore "not recorded", never "verified to be the empty digest".
    solverBinaryDigest*: string
    semanticProfileId*: string
    encodingIdentity*: string
    env*: string
    canonicalSourceIdentity*: string
    specificationIdentity*: string
    translationIdentityHash*: string
    smtScriptDigest*: string
    smtScript*: string

  SolverOptionSpec* = object
    name*: string
    value*: string

  SolverVerdict* {.pure.} = enum
    ## SMT-LIB 2.7 §4.1.7 ⟨check_sat_response⟩. The enumeration has no member
    ## that could carry "proved": a recorded solver outcome cannot exceed the
    ## grammar the standard fixes for a solver's answer.
    svSat = "sat"
    svUnsat = "unsat"
    svUnknown = "unknown"

  SolverResponse* = enum
    ## What the response stream actually answered, as distinct from what the
    ## ⟨check_sat_response⟩ grammar can express. `srNoDecision` is not a response
    ## the standard defines — it is the outcome when the stream carries an
    ## ⟨error_response⟩, when the process exited non-zero, or when no response
    ## line is present at all. Splitting it out is what lets a caller tell
    ## "the solver gave up" apart from "the solver never got asked", which are
    ## different facts about a run and collapse to the same fail-closed svUnknown
    ## only at the very end.
    srNoDecision = "no-decision"
    srSat = "sat"
    srUnsat = "unsat"
    srUnknown = "unknown"

func pinnedDeterminismOptions*(seed: int = Z3PinnedRandomSeed): seq[SolverOptionSpec] {.raises: [].} =
  ## The options the product requires for reproducibility, in canonical order.
  ## The order is part of the digest input, so reordering is a digest change
  ## rather than a cosmetic edit.
  ##
  ## `auto_config` is deliberately absent. It rescales solver parameters from
  ## the problem's own statistics — flipping it moved `:num-allocs` from 23812
  ## to 24070 on an unchanged script — but never from wall-clock, CPU count or
  ## host memory: ten runs at the Z3 default were byte-identical, and identical
  ## again under `taskset -c 0` and `ulimit -v`. Pinning it would shift which
  ## queries finish inside `:rlimit` without removing a nondeterminism source,
  ## and the binary digest already pins the heuristics that could drift.
  ##
  ## `parallel.enable` is pinned even though it already defaults to false:
  ## the option set is replayed on other Z3 builds, where the default is not
  ## this product's evidence.
  result = @[
    SolverOptionSpec(name: "random-seed", value: $seed),
    SolverOptionSpec(name: "sat.random_seed", value: $seed),
    SolverOptionSpec(name: "fp.spacer.random_seed", value: $seed),
    SolverOptionSpec(name: "parallel.enable", value: "false")
  ]

func deterministicSolverOptions*(rlimitSteps: int; timeoutMs: int;
    seed: int = Z3PinnedRandomSeed): seq[SolverOptionSpec] {.raises: [].} =
  ## The complete option set Axiom hands Z3: the reproducibility subset plus
  ## the deterministic budget. `rlimitSteps` is the logical budget; `timeoutMs`
  ## is the liveness backstop and never decides the answer.
  result = pinnedDeterminismOptions(seed)
  result.add SolverOptionSpec(name: "rlimit", value: $rlimitSteps)
  result.add SolverOptionSpec(name: "timeout", value: $timeoutMs)

func solverOptionDirective*(spec: SolverOptionSpec): string {.inline, raises: [].} =
  "(set-option :" & spec.name & " " & spec.value & ")"

func solverOptionsPayload*(options: seq[SolverOptionSpec]): string {.raises: [].} =
  for spec in options:
    result.add solverOptionDirective(spec) & "\n"

func solverOptionsDigest*(options: seq[SolverOptionSpec]): string {.inline, raises: [].} =
  sha256Hex(solverOptionsPayload(options))

func deterministicSolverOptionsDigest*(): string {.raises: [].} =
  ## The digest Axiom records for the option set it hands Z3. Derived from the
  ## same projection the SMT envelope emits, so the recorded digest cannot
  ## drift from what was actually sent.
  solverOptionsDigest(deterministicSolverOptions(z3DeterministicBudget, z3SafetyNetMs))

func matchesPinnedOptions*(digest: string): bool {.inline, raises: [].} =
  digest == deterministicSolverOptionsDigest()

func solverInvocationSelfDescribing*(si: SolverInvocation): bool {.inline, raises: [].} =
  ## A declared field that is never populated is false authority: a record that
  ## cannot name its own executable or option set does not describe the
  ## invocation it claims to describe.
  si.solverIdentity.len > 0 and si.solverVersion.len > 0 and
  si.solverOptionsDigest.len > 0 and si.solverBinaryDigest.len > 0

func solverStreamHasErrorResponse*(raw: string): bool {.raises: [], axiomDecision(id = "DECISION-0824", reason = "Recognize the SMT-LIB (error <s_expr>) response form in a solver response stream, so an internal tool failure is never mistaken for a solver decision", adr = "docs/spec/evidence_calculus.md", introduced = "v34").} =
  ## True iff the stream carries an SMT-LIB ⟨error_response⟩ — the `(error
  ## <s_expr>)` form the standard defines as a command's answer when the command
  ## is rejected.
  ##
  ## Z3 4.13.3 writes this to STDOUT, not stderr, and keeps going: a rejected
  ## command is answered `(error …)` and the following `(check-sat)` is still
  ## answered with a real verdict line, with a non-zero exit. Measured on the
  ## pinned binary, the out-of-scope `let` case yields stdout containing BOTH
  ## `(error "… unknown constant …")` AND `sat`, stderr empty, exit 1. A consumer
  ## that scans for a verdict token without rejecting this form first records an
  ## internal tool error as a solver decision, and on an evidence path a tool
  ## failure becomes a product verdict.
  ##
  ## Matching the START of the form is enough and is deliberately not more than
  ## that: once one is present the stream is already un-decision-worthy, so
  ## paren-balancing a payload the standard leaves open-ended would buy nothing
  ## and would put an s-expression parser into the trusted layer for no gain.
  ## Z3 emits one error per line at column 0 without wrapping (measured: a
  ## 400-character error message stayed on a single line).
  ##
  ## The head must be exactly `error` followed by a separator, so a symbol named
  ## `errors`, `error_msg` or `errorMsg` is not mistaken for the response form.
  ## The trade-off this accepts: a proof or model payload that itself renders a
  ## term as `(error …)` would be rejected as an error response. Z3 prints a
  ## symbol named `error` as a bare atom, so no such term was produced on the
  ## pinned binary, and failing closed on it is the right direction anyway.
  for line in raw.splitLines():
    let trimmed = line.strip(leading = true, trailing = false)
    if not trimmed.startsWith("("):
      continue
    let head = trimmed[1 .. ^1].strip(leading = true, trailing = false)
    if not head.startsWith("error"):
      continue
    let rest = head["error".len .. ^1]
    if rest.len > 0 and (rest[0] == ' ' or rest[0] == '\t' or rest[0] == '('):
      return true
  false

func solverResponse*(raw: string): SolverResponse {.raises: [], axiomDecision(id = "DECISION-0825", reason = "Classify a solver response stream into sat | unsat | unknown | no-decision, rejecting any stream carrying an (error ...) response before a verdict token is read", adr = "docs/spec/evidence_calculus.md", introduced = "v34").} =
  ## Reads a stream whose process status is NOT observable — the persistent pool
  ## hands one script to a live worker per sentinel window and the worker has no
  ## per-query exit code, so the ⟨error_response⟩ form is the only discriminator
  ## available on that path.
  ##
  ## A response line must EQUAL one of the three tokens. A substring test would
  ## read an unsat-core entry, a model line or an error payload as a verdict: on
  ## the pinned binary `(declare-fun x () sat)` produces
  ## `(error "…: unknown sort 'sat'")` followed by `sat`, so the token really can
  ## occur inside an error payload. `:reason-unknown` is solver-specific free text
  ## that must never be matched against — the standard fixes no vocabulary for it.
  ##
  ## The first response wins because one invocation issues one `(check-sat)`;
  ## anything the solver prints afterwards is elaboration of that answer. Absent
  ## a response — and absent an error response, which is a stronger reason — the
  ## result is `srNoDecision`, never a proof (docs/spec/evidence_calculus.md I6).
  if solverStreamHasErrorResponse(raw):
    return srNoDecision
  for line in raw.splitLines():
    let token = line.strip()
    if token == "unsat": return srUnsat
    if token == "sat": return srSat
    if token == "unknown": return srUnknown
  srNoDecision

func solverResponse*(raw: string; exitCode: int): SolverResponse {.raises: [], axiomDecision(id = "DECISION-0826", reason = "Classify a one-shot solver invocation, treating a non-zero exit as no decision regardless of any verdict text the stream also carries", adr = "docs/spec/evidence_calculus.md", introduced = "v34").} =
  ## Reads a stream from a process whose exit status IS part of the evidence.
  ##
  ## A non-zero exit means the script Axiom authored is not the script that ran,
  ## so no verdict in that stream answers the question Axiom asked. The exit
  ## status is deliberately not read positionally against the first response:
  ## Z3 answers a command rejected mid-script with `(error …)` and then keeps
  ## answering later commands, so a stream can legitimately show a verdict
  ## BEFORE the error, the error, and a second verdict after it. Ordering the
  ## response against the error would have to guess which commands the error
  ## invalidates; the whole-run property does not have to.
  if exitCode != 0:
    return srNoDecision
  solverResponse(raw)

func hasSolverDecision*(response: SolverResponse): bool {.inline, raises: [].} =
  ## Whether this outcome is a solver's answer at all, as opposed to the absence
  ## of one. Fail-closed by construction: only `srNoDecision` reads false.
  response != srNoDecision

func solverVerdictOf*(response: SolverResponse): SolverVerdict {.inline, raises: [].} =
  ## Projects the stream outcome onto the recorded-outcome grammar. The absence
  ## of a decision collapses to `svUnknown` because the recorded vocabulary has
  ## no member that could mean "the solver failed to answer" — and inventing one
  ## would let a failure travel as an answer. Callers that must distinguish the
  ## two test `hasSolverDecision` on the `SolverResponse` instead.
  case response
  of srSat: svSat
  of srUnsat: svUnsat
  of srUnknown: svUnknown
  of srNoDecision: svUnknown

func classifySolverVerdict*(raw: string): SolverVerdict {.raises: [].} =
  ## Single-invocation ⟨check_sat_response⟩, projected onto the three-token
  ## grammar every recorded outcome is allowed to use.
  ##
  ## Delegates to `solverResponse` so the ⟨error_response⟩ and no-response rules
  ## are applied at ONE point and cannot be bypassed by a caller that only knows
  ## the three-token vocabulary. `srNoDecision` projects to `svUnknown`: an
  ## unreadable or error-bearing stream yields no verdict, and the one thing it
  ## must never yield is a proof.
  solverVerdictOf(solverResponse(raw))

func solverVerdictOf*(status: SolverStatus): SolverVerdict {.inline, raises: [].} =
  ## Projects the domain solver status onto the standard response grammar.
  ## `solverVacuousContradiction` collapses to `svUnknown`: "no obligation was
  ## discharged" is not an answer the solver gave about the property.
  case status
  of solverSat: svSat
  of solverUnsat: svUnsat
  else: svUnknown

func replayKey*(si: SolverInvocation): string {.inline, raises: [].} =
  ## Deliberately excludes solverBinaryDigest. Folding the binary digest in
  ## would change the key value of every invocation already committed to the
  ## append-only ledger, and re-asserting a historical claim must be a fresh
  ## attestation rather than a mutation (docs/adr/0017-trust-claim-authority.md).
  ## Binary identity is carried as its own field and compared on its own terms.
  let canonical = si.smtScriptDigest & "|" &
                  si.solverIdentity & "|" &
                  si.solverVersion & "|" &
                  si.solverOptionsDigest & "|" &
                  si.semanticProfileId & "|" &
                  si.translationIdentityHash & "|" &
                  si.env
  result = sha256Hex(canonical)

func irIdentity*(si: SolverInvocation): string {.inline, raises: [].} =
  sha256Hex(si.scriptDigest)

func makeSolverInvocation*(
    scriptDigest: string;
    solverVersion: string;
    solverOptionsDigest: string;
    semanticProfileId: string;
    encodingIdentity: string;
    solverIdentity: string = "z3";
    solverBinaryDigest: string = "";
    env: string = "";
    canonicalSourceIdentity: string = "";
    specificationIdentity: string = "";
    translationIdentityHash: string = "";
    smtScriptDigest: string = "";
    smtScript: string = ""
): SolverInvocation {.inline, raises: [].} =
  result.scriptDigest = scriptDigest
  result.solverIdentity = solverIdentity
  result.solverVersion = solverVersion
  result.solverOptionsDigest = solverOptionsDigest
  result.solverBinaryDigest = solverBinaryDigest
  result.semanticProfileId = semanticProfileId
  result.encodingIdentity = encodingIdentity
  result.env = env
  result.canonicalSourceIdentity = canonicalSourceIdentity
  result.specificationIdentity = specificationIdentity
  result.translationIdentityHash = translationIdentityHash
  result.smtScriptDigest = smtScriptDigest
  result.smtScript = smtScript

func smtDigestConsistent*(si: SolverInvocation): bool {.inline, raises: [].} =
  if si.smtScript.len == 0:
    return true
  sha256Hex(si.smtScript) == si.smtScriptDigest

{.pop.}