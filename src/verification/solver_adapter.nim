import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
import std/[tables, os, osproc, sequtils, strutils, times]

import core/trusted/candidate_evidence
import core/trusted/solver_invocation
import core/types/obligation_evidence

const canonicalStateRelationKey* = "state"

type
  SolverStatus* = enum
    sosUnsat
    sosSat
    sosUnknown
    sosTimeout
    sosResourceLimit
    sosProcessError
    sosParseError

  SolverStatistics* = object
    solverTimeMs*: int
    solverMemoryKb*: int

  CandidateCertificate* = object
    predicateInvariants*: OrderedTable[string, string]  ## RelationId -> Formula
    solverMetadata*: string

  SolverOutcome* = object
    status*: SolverStatus
    certificate*: CandidateCertificate
    statistics*: SolverStatistics
    diagnostics*: string
    ## S4 counterexample capture — concrete variable assignments parsed from
    ## the Z3 model output when status == sosSat. Empty on every other status.
    modelBindings*: seq[ModelBinding]

  SolverAdapter* = object
    z3Path*: string
    timeoutMs*: int
    printCertificate*: bool

proc newSolverAdapter*(z3Path: string = "z3"; timeoutMs: int = 5000; printCertificate: bool = true): SolverAdapter =
  SolverAdapter(z3Path: z3Path, timeoutMs: timeoutMs, printCertificate: printCertificate)

func extractCertificate(raw: string): string {.raises: [].} =
  ## Extract the inductive-invariant certificate printed by Z3/Spacer after a
  ## `(query ...)` command. Per Z3 source (`src/muz/fp/dl_cmds.cpp`), when the
  ## `:fp.print_certificate` option is set the `query` command handler prints
  ## the status line (`unsat`/`sat`) immediately followed by the certificate —
  ## a single paren-balanced top-level S-expression (an `inductive_property`).
  ## Returns "" if no such expression is present. Deterministic (paren-scan).
  var depth = 0
  var statusEnd = -1       # offset just past the first bare status token
  var exprStart = -1       # offset of a top-level '(' candidate
  var i = 0
  while i < raw.len:
    let c = raw[i]
    if c == '(':
      if depth == 0:
        # a top-level '(' — record start
        if exprStart < 0:
          exprStart = i
      inc depth
    elif c == ')':
      if depth > 0:
        dec depth
        if depth == 0 and exprStart >= 0:
          # closed a top-level expr; if it came after the status token, return it
          if statusEnd >= 0:
            let expr = raw[exprStart .. i]
            # `(error ...)` — e.g. Z3's "model is not available" reply to a
            # `(get-model)` issued after `unsat` — is never a certificate.
            if not expr.startsWith("(error"):
              return expr
          exprStart = -1
    elif depth == 0:
      # outside any parens — could be the status token
      if statusEnd < 0 and (c == 'u' or c == 's'):
        # candidate start of a bare status word; capture until whitespace
        var j = i
        while j < raw.len and raw[j] notin {' ', '\n', '\r', '\t'}:
          inc j
        let tok = raw[i ..< j]
        if tok.toLowerAscii() in ["unsat", "sat"]:
          statusEnd = j
          exprStart = -1
    inc i
  ""

func classifyOutput(raw: string; exitCode: int; elapsedMs: int; timeoutMs: int): SolverStatus {.raises: [].} =
  ## Determine solver status from raw combined output, the observed process exit
  ## code, and elapsed time. Scans whitespace-separated tokens; a bare
  ## sat/unsat/unknown token decides.
  ##
  ## SAT is minted only through the trusted discriminators (DECISION-0824/0825/
  ## 0826): `solverResponse(raw, exitCode) == srSat` holds only when the stream
  ## carries no `(error ...)` response, the first exact verdict token is `sat`,
  ## and the exit code is 0. An error-bearing stream that also prints a bare
  ## `sat` — Z3 answers a refused command with `(error …)` on stdout and still
  ## answers the following `(check-sat)` (calcDynamicTimeoutCore incident) —
  ## therefore lands on `sosUnknown`, never on `sosSat`. UNSAT keeps its
  ## position: this predicate gates the SAT mint only, so clean streams are
  ## byte-identical.
  for line in raw.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    if trimmed.startsWith("("):
      # parenthesized clause/certificate line — not a status marker
      continue
    let lower = trimmed.toLowerAscii()
    if lower == "unsat":
      return sosUnsat
    if lower == "sat":
      if solverResponse(raw, exitCode) == srSat:
        return sosSat
      return sosUnknown
    if lower == "unknown":
      return sosUnknown
    if lower.contains("timeout"):
      return sosTimeout
    if lower.contains("resource"):
      return sosResourceLimit
    if lower.startsWith("(error") or lower.startsWith("error"):
      continue
  result = sosUnknown
  if elapsedMs >= timeoutMs:
    result = sosTimeout

proc solve*(adapter: SolverAdapter; chcScript: string): SolverOutcome {.raises: [].} =
  ## Run the Spacer CHC pipeline via `adapter.z3Path -in -smt2`.
  ## Produces a SolverOutcome. The Z3/Spacer output format is fully hidden
  ## inside this proc (SolverAdapter bound, C9).
  ##
  ## Certificate retrieval — per Z3 source (`src/muz/fp/dl_cmds.cpp`,
  ## `print_certificate` gate; `fp_params.pyg` `print_certificate` param): the
  ## inductive-invariant certificate is emitted by the `(query ...)` command
  ## when `:fp.print_certificate` is set. It is NOT retrieved via `(get-answer)`.
  ## So we set the option and rely on a `(query ...)` command being present.
  var fullInput: string
  if adapter.printCertificate and not chcScript.contains("(query "):
    # No HORN query command — leave the script untouched (evidence queries are
    # assert-based and have no `error` relation to query).
    fullInput = chcScript
  else:
    if adapter.printCertificate and not chcScript.contains(":fp.print_certificate"):
      fullInput = "(set-option :fp.print_certificate true)\n" & chcScript
    else:
      fullInput = chcScript

  # S4 counterexample capture: for assert-based scripts, issue Z3's official
  # `(get-model)` so a SAT answer carries the concrete variable assignment
  # (`(define-fun ...)` bindings). After `unsat` the command replies with an
  # `(error ...)` S-expression, which extractCertificate skips and
  # classifyOutput ignores — the UNSAT path is byte-identical. Cost is zero
  # on UNSAT; capture happens only when the answer is SAT.
  if fullInput.contains("(check-sat)") and not fullInput.contains("(get-model)"):
    fullInput.add("\n(get-model)")

  let start = getTime()
  var output = ""
  var exitCode: int
  try:
    (output, exitCode) = execCmdEx(
      adapter.z3Path & " -in -smt2",
      input = fullInput,
      options = {poStdErrToStdOut}
    )
  except OSError, IOError:
    return SolverOutcome(
      status: sosProcessError,
      statistics: SolverStatistics(solverTimeMs: int((getTime() - start).inMilliseconds)),
      diagnostics: "z3 launch failed"
    )
  let elapsedMs = int((getTime() - start).inMilliseconds)

  var outcome = SolverOutcome(statistics: SolverStatistics(solverTimeMs: elapsedMs))

  if output.len == 0 and exitCode == QuitFailure:
    outcome.status = sosProcessError
    outcome.diagnostics = "empty output, exit code " & $exitCode
    return outcome

  let status = classifyOutput(output, exitCode, elapsedMs, adapter.timeoutMs)
  outcome.status = status

  if status == sosUnsat:
    let cert = extractCertificate(output)
    if cert.len > 0:
      # Keep the raw inductive-property expression for the canonical state relation.
      outcome.certificate.predicateInvariants[canonicalStateRelationKey] = cert
  if status == sosSat:
    # S4: carry the concrete model assignment out of the raw blob.
    outcome.modelBindings = parseModelBindings(output)
  outcome.certificate.solverMetadata = output
  outcome.diagnostics = output
  outcome

func toCandidateEvidence*(oc: SolverOutcome): CandidateEvidence {.raises: [].} =
  ## SAT outcomes carry the raw solver blob (incl. the `(get-model)` reply) as
  ## `model` even when no UNSAT predicate invariant exists — the P4 I3
  ## promotion gate (evidenceVerdict) re-validates that model concretely before
  ## any DISPROVED verdict, so dropping it here would make the promotion
  ## unreachable for every BMC SAT (dead path = theater). UNSAT without a
  ## certificate still yields empty evidence.
  if oc.certificate.predicateInvariants.len == 0 and
     not (oc.status == sosSat and oc.certificate.solverMetadata.len > 0):
    return CandidateEvidence()
  var invs: seq[(string, string)] = @[]
  for k, v in oc.certificate.predicateInvariants:
    invs.add((k, v))
  let modelStr = if oc.status == sosSat: oc.certificate.solverMetadata else: ""
  candidateEvidence(cesSolver, invs, provenance="solver:" & $oc.status, fingerprint="", model=modelStr)

func parseSatModelBindings*(rawOutput: string): seq[ModelBinding] {.raises: [].} =
  ## S4 wrapper — the pipeline consumes model capture through this adapter
  ## boundary (obligation_evidence stays a solver-layer detail here).
  parseModelBindings(rawOutput)

{.pop.}