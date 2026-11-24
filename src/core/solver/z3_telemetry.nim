import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/json
import std/os
import std/strutils
import core/trusted/axiom_pragmas

const Z3TelemetrySchema* = "axiom-z3-telemetry/2"
  ## What a row MEANS, so a reader never has to guess which definition of
  ## `result` it is looking at.
  ##
  ## `/1` is the rows written before this key existed: `result` was the
  ## whole-stream `solverResponse`, so any `(error ...)` in the stream collapsed
  ## a real verdict into `"error"` (issue #349). Those rows are NOT reinterpreted
  ## — `"error"` in a `.jsonl` without this key still means what it meant when it
  ## was written.
  ##
  ## `/2` splits the two facts apart: `result` is the solver's answer
  ## (`sat`/`unsat`/`unknown`) read the way the verdict path reads it, and
  ## `transport_error` carries the refused-command fact on its own axis.

type
  Z3TelemetryRecord* = object
    ts*: string          ## ISO timestamp
    queryType*: string   ## "bmc", "cegar", "k_induction", etc.
    rlimit*: int         ## Injected rlimit value
    result*: string      ## The lane's ⟨check_sat_response⟩ — "sat" | "unsat" |
                         ## "unknown" — or "timeout" | "error" when the pool
                         ## itself produced no answer (read-deadline, transport
                         ## failure, or a stream with no response line at all).
    transportError*: string ## "error-response" when the raw stream carried an
                         ## SMT-LIB ⟨error_response⟩ — Z3 refused a command, e.g.
                         ## `(error "... model is not available")` answering
                         ## `(get-model)` after `unsat` — else "". Independent of
                         ## `result`: a stream can answer `unsat` AND have a
                         ## command refused.
    timeMs*: int         ## Wall-clock time in milliseconds
    memoryMb*: int       ## Peak memory in megabytes
    cegarIters*: int       ## CEGAR iterations if applicable, else 0
    baseCaseResult*: string ## "unsat" | "sat" | "unknown" | ""
    stepCaseResult*: string ## "unsat" | "sat" | "unknown" | ""
    canonicalEnvelopeDigest*: string ## H(pre-sentinel envelope bytes)
    transportPayloadDigest*: string  ## H(full payload incl sentinel)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc appendZ3Telemetry*(record: Z3TelemetryRecord) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Append a Z3 telemetry record to logs/z3_telemetry.jsonl.
  ## Fails silently on I/O errors to avoid disrupting solver execution.
  try:
    let jsonObj = %*{
      "schema": Z3TelemetrySchema,
      "ts": record.ts,
      "query_type": record.queryType,
      "rlimit": record.rlimit,
      "result": record.result,
      "transport_error": record.transportError,
      "time_ms": record.timeMs,
      "memory_mb": record.memoryMb,
      "cegar_iters": record.cegarIters,
      "base_case_result": record.baseCaseResult,
      "step_case_result": record.stepCaseResult,
      "canonical_envelope_digest": record.canonicalEnvelopeDigest,
      "transport_payload_digest": record.transportPayloadDigest
    }
    let line = $jsonObj & "\n"
    # WP2-a: stateRoot routing for subject immutability.
    let path = block:
      let v = getEnv("AXIOM_STATE_DIR", "").strip()
      if v.len > 0: joinPath(v, "logs", "z3_telemetry.jsonl")
      else: "logs/z3_telemetry.jsonl"
    let dir = parentDir(path)
    if dir.len > 0 and not dirExists(dir):
      createDir(dir)
    let f = open(path, fmAppend)
    f.write(line)
    f.close()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

{.pop.}
